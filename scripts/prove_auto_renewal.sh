#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TF_DIR="$ROOT_DIR/terraform/azure-bigip"
SSH_KEY_DEFAULT="$TF_DIR/.ssh/bigip_azure_eval_rsa"

STAGING_CA_URL="https://acme-staging-v02.api.letsencrypt.org/directory"
ZONE_NAME="${TF_VAR_zone_name:-}"
CONTACT_EMAIL="${TF_VAR_acme_contact_email:-}"
THRESHOLD_DAYS=365
DOMAIN_PREFIX="renewal-proof"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zone-name)
      ZONE_NAME="$2"
      shift 2
      ;;
    --contact-email)
      CONTACT_EMAIL="$2"
      shift 2
      ;;
    --threshold-days)
      THRESHOLD_DAYS="$2"
      shift 2
      ;;
    --domain-prefix)
      DOMAIN_PREFIX="$2"
      shift 2
      ;;
    --help)
      cat <<'EOF'
Usage: scripts/prove_auto_renewal.sh [options]

Creates a temporary staging certificate on BIG-IP, then reruns the normal
kojot-acme renewal path without --force but with a very high renewal threshold.
If the certificate serial changes while the certificate is still valid, the test
proves the scheduled renewal logic will renew before expiry.

Options:
  --zone-name <zone>         DNS zone to use
  --contact-email <email>    ACME contact email
  --threshold-days <days>    Renewal threshold in days (default: 365)
  --domain-prefix <prefix>   Prefix for temporary test hostname
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

source "$HOME/.bashrc"

if [[ -z "${CF_API_TOKEN:-}" ]]; then
  echo "CF_API_TOKEN is not set in ~/.bashrc" >&2
  exit 1
fi

if [[ -z "${CF_ACCOUNT_ID:-}" ]]; then
  echo "CF_ACCOUNT_ID is not set in ~/.bashrc" >&2
  exit 1
fi

if [[ -z "$ZONE_NAME" ]]; then
  vip1_url=$(terraform -chdir="$TF_DIR" output -raw vip1_url)
  vip1_host=$(printf '%s' "$vip1_url" | python3 -c 'import sys, urllib.parse; print(urllib.parse.urlparse(sys.stdin.read().strip()).hostname or "")')
  ZONE_NAME=${vip1_host#*.}
fi

if [[ -z "$CONTACT_EMAIL" && -f "$TF_DIR/terraform.tfvars" ]]; then
  CONTACT_EMAIL=$(python3 - "$TF_DIR/terraform.tfvars" <<'PY'
import re, sys
text = open(sys.argv[1], 'r', encoding='utf-8').read()
m = re.search(r'^\s*acme_contact_email\s*=\s*"([^"]+)"', text, re.M)
print(m.group(1) if m else '')
PY
)
fi

if [[ -z "$CONTACT_EMAIL" ]]; then
  echo "ACME contact email is not set. Pass --contact-email, set TF_VAR_acme_contact_email, or add acme_contact_email to terraform/azure-bigip/terraform.tfvars." >&2
  exit 1
fi

if [[ -z "$ZONE_NAME" ]]; then
  echo "Zone name is not set. Pass --zone-name or set TF_VAR_zone_name." >&2
  exit 1
fi

BIGIP_HOST=$(terraform -chdir="$TF_DIR" output -raw bigip_management_ip)
BIGIP_USER=$(terraform -chdir="$TF_DIR" output -raw bigip_admin_username)
SSH_KEY="${BIGIP_SSH_KEY:-$SSH_KEY_DEFAULT}"

if [[ ! -f "$SSH_KEY" ]]; then
  echo "SSH key not found: $SSH_KEY" >&2
  exit 1
fi

RUN_ID=$(date +%s)
TEST_DOMAIN="${DOMAIN_PREFIX}-${RUN_ID}.${ZONE_NAME}"
REMOTE_CONFIG="/shared/acme/config_${DOMAIN_PREFIX}_${RUN_ID}"
REMOTE_CERT_DIR="/shared/acme/certs/${TEST_DOMAIN}"
REMOTE_DNS_SCRIPT="/shared/acme/dnsapi/dns_cloudflare.sh"
REMOTE_CA_CONFIG_DIR="/shared/acme/accounts"
REMOTE_STAGING_CA_DIR=$(printf '%s\n' "$STAGING_CA_URL" | base64 | tr -d '=')

ssh_base=(ssh -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY")
scp_base=(scp -q -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY")
target="${BIGIP_USER}@${BIGIP_HOST}"

remote_cleanup_command() {
  cat <<EOF
tmsh modify ltm data-group internal dg_acme_config records delete { "${TEST_DOMAIN}" } >/dev/null 2>&1 || true
tmsh delete sys file ssl-cert ${TEST_DOMAIN} >/dev/null 2>&1 || true
tmsh delete sys file ssl-key ${TEST_DOMAIN} >/dev/null 2>&1 || true
rm -rf '${REMOTE_CERT_DIR}' '${REMOTE_CONFIG}' /var/tmp/${TEST_DOMAIN}.config >/dev/null 2>&1 || true
EOF
}

cleanup_stale_prefix_records() {
  "${ssh_base[@]}" "$target" "PREFIX='${DOMAIN_PREFIX}' ZONE='${ZONE_NAME}' python3 - <<'PY'
import re
import os
import subprocess

prefix = os.environ['PREFIX']
zone = os.environ['ZONE']
pattern = re.compile(rf'^{re.escape(prefix)}-[0-9]+\\.{re.escape(zone)}$')

output = subprocess.check_output(['tmsh', 'list', 'ltm', 'data-group', 'internal', 'dg_acme_config'], text=True)
records = sorted(set(pattern.findall(output)))
for record in records:
    subprocess.call(['tmsh', 'modify', 'ltm', 'data-group', 'internal', 'dg_acme_config', 'records', 'delete', '{', record, '}'])
    subprocess.call(['tmsh', 'delete', 'sys', 'file', 'ssl-cert', record])
    subprocess.call(['tmsh', 'delete', 'sys', 'file', 'ssl-key', record])
print('\n'.join(records))
PY" | while IFS= read -r stale_record; do
    [ -z "$stale_record" ] && continue
    echo "Removed stale renewal-proof record: $stale_record"
  done

  "${ssh_base[@]}" "$target" "rm -rf /shared/acme/certs/${DOMAIN_PREFIX}-*.${ZONE_NAME} /shared/acme/config_${DOMAIN_PREFIX}_* /var/tmp/${DOMAIN_PREFIX}-*.config >/dev/null 2>&1 || true"
}

cleanup() {
  "${ssh_base[@]}" "$target" "$(remote_cleanup_command)" || true
}

trap cleanup EXIT INT TERM

tmp_config=$(mktemp)
cat > "$tmp_config" <<EOF
CONTACT_EMAIL=${CONTACT_EMAIL}
KEY_ALGO=rsa
KEYSIZE=2048
ALWAYS_GENERATE_KEY=true
THRESHOLD=${THRESHOLD_DAYS}
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
CF_API_TOKEN=${CF_API_TOKEN}
CF_ACCOUNT_ID=${CF_ACCOUNT_ID}
CF_ZONE_NAME=${ZONE_NAME}
EOF

echo "Uploading temporary renewal-proof config for ${TEST_DOMAIN}"
cleanup_stale_prefix_records
"${ssh_base[@]}" "$target" "mkdir -p '${REMOTE_CA_CONFIG_DIR}'"
"${scp_base[@]}" "$ROOT_DIR/scripts/dns_cloudflare.sh" "$target:/var/tmp/dns_cloudflare.sh"
"${ssh_base[@]}" "$target" "install -m 700 /var/tmp/dns_cloudflare.sh '${REMOTE_DNS_SCRIPT}'"
"${scp_base[@]}" "$tmp_config" "$target:/var/tmp/${TEST_DOMAIN}.config"
rm -f "$tmp_config"

"${ssh_base[@]}" "$target" "install -m 600 /var/tmp/${TEST_DOMAIN}.config '${REMOTE_CONFIG}'"
"${ssh_base[@]}" "$target" "rm -rf '${REMOTE_CA_CONFIG_DIR}/${REMOTE_STAGING_CA_DIR}' && /shared/acme/bin/dehydrated --register --accept-terms --config '${REMOTE_CONFIG}' --ca '${STAGING_CA_URL}'"
"${ssh_base[@]}" "$target" "tmsh modify ltm data-group internal dg_acme_config records add { \"${TEST_DOMAIN}\" { data \"--ca ${STAGING_CA_URL} --config ${REMOTE_CONFIG}\" } }"

run_handler() {
  local domain="$1"
  "${ssh_base[@]}" "$target" "/shared/acme/f5acmehandler.sh --domain ${domain} --verbose"
}

get_cert_field() {
  local domain="$1"
  local field="$2"
  "${ssh_base[@]}" "$target" "tmsh list sys file ssl-cert ${domain} all-properties | awk '/^[[:space:]]*${field}[[:space:]]/ {\$1=\"\"; sub(/^[[:space:]]+/,\"\"); print; exit}'"
}

echo "Issuing initial staging certificate"
run_handler "$TEST_DOMAIN" >/dev/null

serial_before=$(get_cert_field "$TEST_DOMAIN" "serial-number")
expiry_before=$(get_cert_field "$TEST_DOMAIN" "expiration-string")
update_before=$(get_cert_field "$TEST_DOMAIN" "last-update-time")

if [[ -z "$serial_before" ]]; then
  echo "Failed to read initial certificate serial for ${TEST_DOMAIN}" >&2
  exit 1
fi

echo "Initial serial: ${serial_before}"
echo "Initial expiry: ${expiry_before}"
echo "Initial update time: ${update_before}"

sleep 5

echo "Triggering standard renewal path without --force"
run_handler "$TEST_DOMAIN" >/dev/null

serial_after=$(get_cert_field "$TEST_DOMAIN" "serial-number")
expiry_after=$(get_cert_field "$TEST_DOMAIN" "expiration-string")
update_after=$(get_cert_field "$TEST_DOMAIN" "last-update-time")

echo "Renewed serial: ${serial_after}"
echo "Renewed expiry: ${expiry_after}"
echo "Renewed update time: ${update_after}"

if [[ "$serial_before" == "$serial_after" ]]; then
  echo "Renewal proof failed: serial number did not change" >&2
  exit 1
fi

cat <<EOF
Renewal proof passed.

- Temporary domain: ${TEST_DOMAIN}
- Initial serial: ${serial_before}
- Renewed serial: ${serial_after}
- Threshold used: ${THRESHOLD_DAYS} days
- CA used: Let's Encrypt staging

This proves kojot-acme renewed a still-valid certificate before expiry using the
same threshold-based renewal logic that the scheduled job uses.
EOF
