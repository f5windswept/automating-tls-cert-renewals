# Renewal Proof Test

This test proves the BIG-IP certificate automation renews a certificate before it expires.

It does that by:

- creating a temporary hostname under your configured DNS zone
- using `Let's Encrypt` staging to avoid production rate limits
- setting a very high renewal threshold (`365` days)
- issuing an initial certificate
- running the normal `kojot-acme` renewal path again without `--force`
- confirming the certificate serial number changes while the certificate is still valid

Because `kojot-acme` only renews when `THRESHOLD >= days_until_expiry`, a second certificate issuance under those conditions proves the threshold-based pre-expiry renewal behavior works.

## Run it

From the repo root:

```bash
./scripts/prove_auto_renewal.sh
```

Optional flags:

```bash
./scripts/prove_auto_renewal.sh --threshold-days 365 --domain-prefix renewal-proof
```

## What it uses

- Terraform outputs for BIG-IP host and username
- the local SSH key in `terraform/azure-bigip/.ssh/bigip_azure_eval_rsa`
- `CF_API_TOKEN` and `CF_ACCOUNT_ID` from `~/.bashrc`
- `Let's Encrypt` staging CA: `https://acme-staging-v02.api.letsencrypt.org/directory`

## Cleanup

The script automatically cleans up:

- the temporary `dg_acme_config` entry
- the temporary BIG-IP certificate and key objects
- the temporary BIG-IP ACME config file
- the temporary cert working directory on BIG-IP

## Notes

- The test exercises the same threshold-based `f5acmehandler.sh` logic that cron invokes in production.
- It does not modify the live `vip1.<your zone>` or `vip2.<your zone>` certificate objects.
