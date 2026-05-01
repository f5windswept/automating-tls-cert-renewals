resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.prefix}-vnet"
  address_space       = [var.vnet_cidr]
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet" "mgmt" {
  name                 = "${var.prefix}-mgmt-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.mgmt_subnet_cidr]
}

resource "azurerm_subnet" "external" {
  name                 = "${var.prefix}-external-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.external_subnet_cidr]
}

resource "azurerm_network_security_group" "mgmt" {
  name                = "${var.prefix}-mgmt-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_group" "external" {
  name                = "${var.prefix}-external-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "allow_https" {
  name                        = "allow-https"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.mgmt.name
}

resource "azurerm_network_security_rule" "allow_ssh" {
  name                        = "allow-ssh"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.mgmt.name
}

resource "azurerm_network_security_rule" "allow_vip_https" {
  name                        = "allow-vip-https"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.allowed_cidr
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.this.name
  network_security_group_name = azurerm_network_security_group.external.name
}

resource "azurerm_marketplace_agreement" "bigip" {
  publisher = var.bigip_publisher
  offer     = var.bigip_offer
  plan      = var.bigip_sku
}

resource "random_password" "bigip_admin" {
  length           = 20
  special          = true
  override_special = "!@#%^*-_=+?"
}

module "bigip" {
  source = "./modules/f5-bigip-azure"

  depends_on = [azurerm_marketplace_agreement.bigip]

  prefix                      = var.prefix
  resource_group_name         = azurerm_resource_group.this.name
  vm_name                     = var.bigip_vm_name
  f5_username                 = var.bigip_admin_username
  f5_password                 = random_password.bigip_admin.result
  f5_instance_type            = var.bigip_instance_type
  f5_product_name             = var.bigip_offer
  f5_image_name               = var.bigip_sku
  f5_version                  = var.bigip_version
  availability_zone           = var.availability_zone
  availabilityZones_public_ip = var.availability_zones_public_ip
  enable_ssh_key              = true
  f5_ssh_publickey            = local.ssh_publickey
  tags                        = var.tags

  mgmt_subnet_ids = [
    {
      subnet_id          = azurerm_subnet.mgmt.id
      public_ip          = true
      private_ip_primary = var.bigip_mgmt_private_ip
    }
  ]

  mgmt_securitygroup_ids = [azurerm_network_security_group.mgmt.id]

  external_subnet_ids = [
    {
      subnet_id            = azurerm_subnet.external.id
      public_ip            = true
      private_ip_primary   = var.bigip_external_self_ip
      private_ip_secondary = var.vip1_private_ip
      private_ip_tertiary  = var.vip2_private_ip
    }
  ]

  external_securitygroup_ids = [azurerm_network_security_group.external.id]
}

locals {
  bigip_mgmt_ip       = try(module.bigip.mgmtPublicIP[0], module.bigip.mgmtPublicIP)
  bigip_mgmt_port     = try(module.bigip.mgmtPort, "8443")
  bigip_password      = try(module.bigip.bigip_password[0], module.bigip.bigip_password)
  ssh_publickey_path  = var.f5_ssh_publickey != "" ? var.f5_ssh_publickey : pathexpand("~/.ssh/id_ed25519.pub")
  ssh_publickey       = trimspace(file(local.ssh_publickey_path))
  ssh_privatekey_path = trimsuffix(local.ssh_publickey_path, ".pub")
  vip1_public_ip      = try(module.bigip.public_addresses.external_secondary_public[0], "")
  vip2_public_ip      = try(module.bigip.public_addresses.external_tertiary_public[0], "")
  external_vlan_name  = azurerm_subnet.external.name

  do_declaration = {
    class         = "Device"
    schemaVersion = "1.0.0"
    async         = true
    label         = "Terraform Azure Onboarding"
    Common = merge(
      {
        class = "Tenant"
        provisioningLevels = merge(
          { class = "Provision" },
          var.provision_modules
        )
        mySystem = {
          class    = "System"
          hostname = var.bigip_hostname
        }
        myDns = {
          class       = "DNS"
          nameServers = var.dns_servers
        }
        myNtp = {
          class   = "NTP"
          servers = var.ntp_servers
        }
        myLicense = {
          class       = "License"
          licenseType = "regKey"
          regKey      = var.bigip_license_key
        }
      },
      {
        (local.external_vlan_name) = {
          class = "VLAN"
          tag   = 4093
          mtu   = 1500
          interfaces = [
            {
              name   = "1.1"
              tagged = false
            }
          ]
          cmpHash = "dst-ip"
        }
        "${local.external_vlan_name}-self" = {
          class        = "SelfIp"
          address      = "${var.bigip_external_self_ip}/${split("/", var.external_subnet_cidr)[1]}"
          vlan         = local.external_vlan_name
          allowService = ["tcp:1028"]
          trafficGroup = "traffic-group-local-only"
        }
        default = {
          class   = "Route"
          gw      = cidrhost(var.external_subnet_cidr, 1)
          network = "default"
          mtu     = 1500
        }
      }
    )
  }
}

resource "local_file" "do_declaration" {
  filename        = "${path.module}/rendered-do.json"
  content         = jsonencode(local.do_declaration)
  file_permission = "0600"
}

resource "null_resource" "apply_do" {
  depends_on = [module.bigip, local_file.do_declaration]

  triggers = {
    mgmt_ip = local.bigip_mgmt_ip
    do_hash = sha256(local_file.do_declaration.content)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      RESPONSE_FILE=$(mktemp)
      TASK_FILE=$(mktemp)
      REMOTE_DO_FILE="/var/tmp/terraform-do.json"
      trap 'rm -f "$RESPONSE_FILE" "$TASK_FILE"' EXIT

      echo "Waiting for SSH connectivity to ${local.bigip_mgmt_ip}"
      for i in $(seq 1 90); do
        if ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=10 -i '${local.ssh_privatekey_path}' \
          '${var.bigip_admin_username}@${local.bigip_mgmt_ip}' 'true' >/dev/null 2>&1; then
          echo "SSH is ready"
          break
        fi

        if [ "$i" -eq 90 ]; then
          echo "Timed out waiting for SSH connectivity" >&2
          exit 1
        fi

        sleep 10
      done

      echo "Ensuring BIG-IP is licensed"
      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i '${local.ssh_privatekey_path}' \
        '${var.bigip_admin_username}@${local.bigip_mgmt_ip}' \
        "tmsh show sys license 2>&1 | grep -q 'Active Modules' || tmsh install sys license registration-key ${var.bigip_license_key} no-certificate-update"

      echo "Waiting for Declarative Onboarding endpoint on localhost:${local.bigip_mgmt_port}"
      for i in $(seq 1 90); do
        if ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -i '${local.ssh_privatekey_path}' \
          '${var.bigip_admin_username}@${local.bigip_mgmt_ip}' \
          "curl -sk --connect-timeout 10 -u '${var.bigip_admin_username}:${local.bigip_password}' https://localhost:${local.bigip_mgmt_port}/mgmt/shared/declarative-onboarding/info >/dev/null"; then
          echo "DO endpoint is ready"
          break
        fi

        if [ "$i" -eq 90 ]; then
          echo "Timed out waiting for Declarative Onboarding endpoint" >&2
          exit 1
        fi

        sleep 10
      done

      scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i '${local.ssh_privatekey_path}' \
        '${local_file.do_declaration.filename}' \
        '${var.bigip_admin_username}@${local.bigip_mgmt_ip}:'"$REMOTE_DO_FILE"

      echo "Posting DO declaration"
      ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -i '${local.ssh_privatekey_path}' \
        '${var.bigip_admin_username}@${local.bigip_mgmt_ip}' \
        "curl -sk -u '${var.bigip_admin_username}:${local.bigip_password}' -H 'Content-Type: application/json' -X POST https://localhost:${local.bigip_mgmt_port}/mgmt/shared/declarative-onboarding --data-binary @$${REMOTE_DO_FILE}" \
        > "$RESPONSE_FILE"

      TASK_ID=$(python3 - "$RESPONSE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)

task_id = data.get('id', '')
if not task_id:
    print('Unable to determine Declarative Onboarding task ID from response', file=sys.stderr)
    sys.exit(1)

print(task_id)
PY
      )

      TASK_URL="https://localhost:${local.bigip_mgmt_port}/mgmt/shared/declarative-onboarding/task/$TASK_ID"

      echo
      echo "Declarative Onboarding request submitted: $TASK_ID"
      echo "Polling task status until completion"

      for i in $(seq 1 180); do
        ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -i '${local.ssh_privatekey_path}' \
          '${var.bigip_admin_username}@${local.bigip_mgmt_ip}' \
          "curl -sk -u '${var.bigip_admin_username}:${local.bigip_password}' $TASK_URL" > "$TASK_FILE"

        TASK_STATUS=$(python3 - "$TASK_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], 'r', encoding='utf-8') as fh:
    data = json.load(fh)

result = data.get('result', {}) or {}
status = result.get('status', data.get('status', 'UNKNOWN'))
message = result.get('message', '')
print(f"{status}\t{message}")
PY
        )

        STATUS_VALUE=$(printf '%s' "$TASK_STATUS" | cut -f1)
        STATUS_MESSAGE=$(printf '%s' "$TASK_STATUS" | cut -f2-)
        if [ -n "$STATUS_MESSAGE" ]; then
          echo "DO task status: $STATUS_VALUE - $STATUS_MESSAGE"
        else
          echo "DO task status: $STATUS_VALUE"
        fi

        case "$STATUS_VALUE" in
          OK)
            echo "Declarative Onboarding completed successfully"
            exit 0
            ;;
          ERROR|FAILED)
            echo "Declarative Onboarding failed" >&2
            cat "$TASK_FILE" >&2
            exit 1
            ;;
        esac

        sleep 10
      done

      echo "Timed out waiting for Declarative Onboarding task completion" >&2
      cat "$TASK_FILE" >&2
      exit 1
    EOT
  }
}
