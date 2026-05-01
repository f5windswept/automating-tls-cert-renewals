# BIG-IP Azure Fast Deploy

This Terraform plan is the fastest no-click deployment pattern for a standalone BIG-IP VE in Azure using a BYOL image and an evaluation registration key.

It does four things in one `terraform apply`:

1. Creates Azure networking and a management subnet
2. Deploys a BIG-IP VE from the Azure Marketplace using the official F5 Terraform module
3. Waits for the BIG-IP Declarative Onboarding (DO) endpoint to become ready
4. Posts a DO declaration that applies the BIG-IP license and base system settings and polls the DO task until it reports success or failure

This is intentionally optimized for speed and repeatability, not for a production-grade multi-NIC HA design.

## What Gets Deployed

- 1 resource group
- 1 virtual network
- 1 management subnet
- 1 management NSG
- 1 standalone BIG-IP VE VM with a public management IP on port `8443`
- 1 DO declaration rendered locally and applied automatically

## Prerequisites

- Azure CLI authenticated to the target subscription: `az login`
- Terraform installed locally
- Access to the Azure Marketplace BIG-IP BYOL image in your subscription
- An F5 evaluation or BYOL registration key
- Outbound internet access from the BIG-IP so runtime-init can install ATC components

## Fastest Workflow

1. Copy `terraform.tfvars.example` to `terraform.tfvars`
2. Set `bigip_license_key`
3. Optionally adjust `location`, `prefix`, and `bigip_vm_name`
4. Run:

```bash
terraform init
terraform plan
terraform apply
```

## Notes

- This plan uses the official module source `F5Networks/bigip-module/azure`
- The module performs the initial VM bootstrap and ATC install
- Terraform licenses the device if needed, then posts a DO declaration automatically and waits for the DO task to finish
- The generated admin password is random and returned as a sensitive output
- After apply, you can also inspect the DO endpoints with the outputs `bigip_do_info_url` and `bigip_do_tasks_url`

## Production Follow-Ups

For production, I would extend this plan with:

- 3-NIC or HA architecture
- Azure Key Vault for secrets
- AS3 for app declarations
- Cloud Failover Extension for HA
- Private management access instead of public management
- CI/CD pipeline execution instead of local `terraform apply`
