locals {
  vip1_fqdn = "${var.vip1_hostname}.${var.zone_name}"
  vip2_fqdn = "${var.vip2_hostname}.${var.zone_name}"
}

resource "local_file" "as3_declaration" {
  filename        = "${path.module}/rendered-as3.json"
  file_permission = "0600"
  content = templatefile("${path.module}/../../as3/two-vips.as3.json.tftpl", {
    vip1_private_ip = var.vip1_private_ip
    vip2_private_ip = var.vip2_private_ip
    vip1_fqdn       = local.vip1_fqdn
    vip2_fqdn       = local.vip2_fqdn
  })
}

resource "null_resource" "cloudflare_dns" {
  depends_on = [module.bigip]

  triggers = {
    vip1_public_ip = local.vip1_public_ip
    vip2_public_ip = local.vip2_public_ip
    zone_name      = var.zone_name
    vip1_host      = var.vip1_hostname
    vip2_host      = var.vip2_hostname
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      source "$HOME/.bashrc"
      python3 "${path.module}/../../scripts/upsert_cloudflare_dns.py" \
        --zone-name "${var.zone_name}" \
        --vip1-host "${var.vip1_hostname}" \
        --vip2-host "${var.vip2_hostname}" \
        --vip1-ip "${local.vip1_public_ip}" \
        --vip2-ip "${local.vip2_public_ip}"
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      source "$HOME/.bashrc"
      python3 "${path.module}/../../scripts/upsert_cloudflare_dns.py" \
        --action delete \
        --zone-name "${lookup(self.triggers, "zone_name", "example.com")}" \
        --vip1-host "${lookup(self.triggers, "vip1_host", "vip1")}" \
        --vip2-host "${lookup(self.triggers, "vip2_host", "vip2")}" \
        --vip1-ip "${lookup(self.triggers, "vip1_public_ip", "")}" \
        --vip2-ip "${lookup(self.triggers, "vip2_public_ip", "")}"

      python3 "${path.module}/../../scripts/upsert_cloudflare_dns.py" \
        --action delete-acme-txt \
        --zone-name "${lookup(self.triggers, "zone_name", "example.com")}" \
        --vip1-host "${lookup(self.triggers, "vip1_host", "vip1")}" \
        --vip2-host "${lookup(self.triggers, "vip2_host", "vip2")}" \
        --vip1-ip "${lookup(self.triggers, "vip1_public_ip", "")}" \
        --vip2-ip "${lookup(self.triggers, "vip2_public_ip", "")}"
    EOT
  }
}

resource "null_resource" "install_kojot" {
  depends_on = [null_resource.apply_do, null_resource.cloudflare_dns]

  triggers = {
    vip1_fqdn          = local.vip1_fqdn
    vip2_fqdn          = local.vip2_fqdn
    acme_directory_url = var.acme_directory_url
    acme_schedule      = var.acme_schedule
    zone_name          = var.zone_name
    install_script_hash = filesha256("${path.module}/../../acme/kojot-acme/install.sh")
    dns_script_hash     = filesha256("${path.module}/../../scripts/dns_cloudflare.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      source "$HOME/.bashrc"

      BIGIP_HOST='${local.bigip_mgmt_ip}'
      BIGIP_USER='${var.bigip_admin_username}'
      SSH_KEY='${local.ssh_privatekey_path}'
      ACME_CONFIG_REMOTE='/var/tmp/config_cloudflare'
      DNS_SCRIPT_REMOTE='/var/tmp/dns_cloudflare.sh'
      INSTALL_SCRIPT_REMOTE='/var/tmp/install_kojot.sh'

      scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
        "${path.module}/../../acme/kojot-acme/install.sh" "$BIGIP_USER@$BIGIP_HOST:$INSTALL_SCRIPT_REMOTE"

      scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
        "${path.module}/../../scripts/dns_cloudflare.sh" "$BIGIP_USER@$BIGIP_HOST:$DNS_SCRIPT_REMOTE"

      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
        "$BIGIP_USER@$BIGIP_HOST" "cat > $ACME_CONFIG_REMOTE <<'EOF'
CONTACT_EMAIL=${var.acme_contact_email}
KEY_ALGO=rsa
KEYSIZE=2048
THRESHOLD=30
VALIDATION_TIMEOUT=120
ORDER_TIMEOUT=120
ACME_METHOD=dns-01
DNSAPI=dns_cloudflare
DNS_DELAY=60
FORCE_SYNC=false
CHECK_REVOCATION=false
DEBUGLOG=true
ERRORLOG=true
FULLCHAIN=true
CREATEPROFILE=false
CF_API_TOKEN=$CF_API_TOKEN
CF_ACCOUNT_ID=$CF_ACCOUNT_ID
CF_ZONE_NAME=${var.zone_name}
EOF"

      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
        "$BIGIP_USER@$BIGIP_HOST" "bash $INSTALL_SCRIPT_REMOTE && install -m 700 $DNS_SCRIPT_REMOTE /shared/acme/dnsapi/dns_cloudflare.sh && install -m 600 $ACME_CONFIG_REMOTE /shared/acme/config_cloudflare && tmsh modify ltm data-group internal dg_acme_config records replace-all-with { \"${local.vip1_fqdn}\" { data \"--ca ${var.acme_directory_url} --config /shared/acme/config_cloudflare\" } \"${local.vip2_fqdn}\" { data \"--ca ${var.acme_directory_url} --config /shared/acme/config_cloudflare\" } }"

      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
        "$BIGIP_USER@$BIGIP_HOST" "/shared/acme/f5acmehandler.sh --force --domain ${local.vip1_fqdn} --verbose && tmsh list sys file ssl-cert ${local.vip1_fqdn} >/dev/null 2>&1 && tmsh list sys file ssl-key ${local.vip1_fqdn} >/dev/null 2>&1"

      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
        "$BIGIP_USER@$BIGIP_HOST" "/shared/acme/f5acmehandler.sh --force --domain ${local.vip2_fqdn} --verbose && tmsh list sys file ssl-cert ${local.vip2_fqdn} >/dev/null 2>&1 && tmsh list sys file ssl-key ${local.vip2_fqdn} >/dev/null 2>&1"

      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY" \
        "$BIGIP_USER@$BIGIP_HOST" "(tmsh list ltm profile client-ssl vip1_clientssl >/dev/null 2>&1 && tmsh modify ltm profile client-ssl vip1_clientssl cert ${local.vip1_fqdn} key ${local.vip1_fqdn} || tmsh create ltm profile client-ssl vip1_clientssl cert ${local.vip1_fqdn} key ${local.vip1_fqdn}) && (tmsh list ltm profile client-ssl vip2_clientssl >/dev/null 2>&1 && tmsh modify ltm profile client-ssl vip2_clientssl cert ${local.vip2_fqdn} key ${local.vip2_fqdn} || tmsh create ltm profile client-ssl vip2_clientssl cert ${local.vip2_fqdn} key ${local.vip2_fqdn}) && /shared/acme/f5acmehandler.sh --schedule '${var.acme_schedule}' && tmsh save sys config"
    EOT
  }
}

resource "null_resource" "revoke_license" {
  depends_on = [module.bigip, null_resource.apply_as3]

  triggers = {
    host        = local.bigip_mgmt_ip
    user        = var.bigip_admin_username
    ssh_key     = local.ssh_privatekey_path
    license_key = var.bigip_license_key
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      SSH_BASE=(ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i '${self.triggers.ssh_key}')
      TARGET='${self.triggers.user}@${self.triggers.host}'

      if ! "$${SSH_BASE[@]}" "$TARGET" "tmsh show sys license | grep -q 'Registration key'"; then
        echo 'No active BIG-IP license to revoke'
        exit 0
      fi

      echo 'Revoking BIG-IP license'
      "$${SSH_BASE[@]}" "$TARGET" "nohup sh -c 'tmsh revoke sys license >/var/tmp/terraform_revoke_license.log 2>&1' >/dev/null 2>&1 &" || true

      for i in $(seq 1 24); do
        if "$${SSH_BASE[@]}" "$TARGET" "tmsh show sys license 2>/dev/null | grep -q 'Registration key'"; then
          sleep 5
          continue
        fi

        echo 'BIG-IP license revoked successfully'
        exit 0
      done

      echo 'License revoke did not complete successfully; check BIG-IP and replace the key in terraform/azure-bigip/terraform.tfvars if needed' >&2
      "$${SSH_BASE[@]}" "$TARGET" "cat /var/tmp/terraform_revoke_license.log 2>/dev/null || true" >&2 || true
      exit 1
    EOT
  }
}

resource "null_resource" "apply_as3" {
  depends_on = [null_resource.install_kojot, local_file.as3_declaration]

  triggers = {
    declaration_hash = sha256(local_file.as3_declaration.content)
    vip1_private_ip  = var.vip1_private_ip
    vip2_private_ip  = var.vip2_private_ip
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      RESPONSE_FILE=$(mktemp)
      trap 'rm -f "$RESPONSE_FILE"' EXIT

      scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i '${local.ssh_privatekey_path}' \
        '${local_file.as3_declaration.filename}' \
        '${var.bigip_admin_username}@${local.bigip_mgmt_ip}:/var/tmp/rendered-as3.json'

      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i '${local.ssh_privatekey_path}' \
        '${var.bigip_admin_username}@${local.bigip_mgmt_ip}' \
        "curl -sk -u '${var.bigip_admin_username}:${local.bigip_password}' -H 'Content-Type: application/json' -X POST https://localhost:${local.bigip_mgmt_port}/mgmt/shared/appsvcs/declare --data-binary @/var/tmp/rendered-as3.json" > "$RESPONSE_FILE"

      python3 - "$RESPONSE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)

results = data.get('results', [])
if not results:
    print(json.dumps(data, indent=2), file=sys.stderr)
    raise SystemExit('No AS3 results returned')

bad = [item for item in results if item.get('code', 0) >= 300]
if bad:
    print(json.dumps(data, indent=2), file=sys.stderr)
    raise SystemExit('AS3 deployment failed')

print('AS3 deployment completed successfully')
PY
    EOT
  }
}
