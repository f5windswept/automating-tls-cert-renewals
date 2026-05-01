# Automating TLS Cert Renewals

This repo deploys a standalone F5 BIG-IP VE in Azure, publishes two HTTPS VIPs with AS3, automates DNS in Cloudflare, and uses `kojot-acme` to acquire and renew separate Let's Encrypt certificates for `vip1.<your zone>` and `vip2.<your zone>`.

## Layout

- `terraform/azure-bigip/` - Azure infrastructure, BIG-IP onboarding, Cloudflare A records, kojot-acme bootstrap, and AS3 deployment
- `as3/` - AS3 declaration templates for the two HTTPS VIPs
- `acme/kojot-acme/` - vendored upstream kojot-acme repo used for certificate automation on BIG-IP
- `scripts/` - local helper scripts, including Cloudflare DNS record management and a Cloudflare DNS API hook for kojot-acme

Each deployment creates:

- listen on `443`
- serve static HTML from `iRules`
- present separate Let's Encrypt certificates
- renew through scheduled `kojot-acme` jobs on BIG-IP

## Required inputs

Set these environment variables before running Terraform:

- `CF_API_TOKEN` - Cloudflare API token with permission to read the account and edit DNS records in your zone
- `CF_ACCOUNT_ID` - Cloudflare account id used to look up the zone automatically

Set these Terraform variables in `terraform/azure-bigip/terraform.tfvars` or via environment variables:

- `zone_name` - your DNS zone, for example `example.com`
- `acme_contact_email` - contact email for ACME account registration
- `bigip_license_key` - BIG-IP evaluation or BYOL registration key

The VIP FQDNs are built from:

- `vip1_hostname` + `zone_name`
- `vip2_hostname` + `zone_name`

## Demo teardown and redeploy

- `terraform destroy` now includes a destroy-time license revocation step on BIG-IP so the evaluation key can be reused on the next deployment
- if license revocation fails during destroy, Terraform will fail so you know to swap in a different key in `terraform/azure-bigip/terraform.tfvars`
- certificates are requested from Let's Encrypt during deployment as needed

## Demo wrapper

From the repo root:

- `make demo-init` - initialize Terraform providers and modules
- `make demo-plan` - show the deploy/update plan
- `make demo-up` - deploy or update the demo
- `make demo-status` - print current Terraform outputs
- `make demo-destroy-plan` - show what teardown will remove
- `make demo-down` - destroy the demo, revoke the BIG-IP license, and delete the Cloudflare A records
- `make demo-renewal-proof` - run a non-destructive staging test that proves pre-expiry renewal logic works

## Quick CLI login lookup

From the repo root:

- `make demo-status` - prints the current Terraform outputs, but sensitive values such as the BIG-IP password are masked
- `terraform -chdir=terraform/azure-bigip output -raw bigip_admin_username` - prints the BIG-IP username
- `terraform -chdir=terraform/azure-bigip output -raw bigip_admin_password` - prints the BIG-IP password

## Notes

- Local secrets and state are intentionally ignored by git.
- `terraform/azure-bigip/terraform.tfvars` and `terraform/azure-bigip/.ssh/` stay local only.
- Cloudflare credentials are sourced from your shell environment during Terraform apply.
- `terraform/azure-bigip/terraform.tfvars.example` uses a generic SSH public key path; update it to match your local key location.
