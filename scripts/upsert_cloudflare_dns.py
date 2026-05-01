#!/usr/bin/env python3

import argparse
import json
import os
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request


API_BASE = "https://api.cloudflare.com/client/v4"
SSL_CONTEXT = ssl._create_unverified_context()


def api_request(method, path, token, payload=None):
    data = None
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")

    request = urllib.request.Request(f"{API_BASE}{path}", data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(request, context=SSL_CONTEXT) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Cloudflare API error {exc.code}: {body}") from exc


def lookup_zone(token, account_id, zone_name):
    query = urllib.parse.urlencode({"name": zone_name, "account.id": account_id})
    response = api_request("GET", f"/zones?{query}", token)
    results = response.get("result", [])
    if not results:
        raise RuntimeError(f"Zone not found: {zone_name}")
    return results[0]["id"]


def lookup_record(token, zone_id, fqdn, record_type):
    query = urllib.parse.urlencode({"name": fqdn, "type": record_type})
    response = api_request("GET", f"/zones/{zone_id}/dns_records?{query}", token)
    results = response.get("result", [])
    return results[0] if results else None


def upsert_record(token, zone_id, fqdn, ip_address, proxied):
    payload = {
        "type": "A",
        "name": fqdn,
        "content": ip_address,
        "ttl": 1,
        "proxied": proxied,
    }
    existing = lookup_record(token, zone_id, fqdn, "A")
    if existing:
        if existing.get("content") == ip_address and existing.get("proxied") == proxied:
            print(f"No change for {fqdn} -> {ip_address}")
            return
        api_request("PUT", f"/zones/{zone_id}/dns_records/{existing['id']}", token, payload)
        print(f"Updated {fqdn} -> {ip_address}")
        return
    api_request("POST", f"/zones/{zone_id}/dns_records", token, payload)
    print(f"Created {fqdn} -> {ip_address}")


def delete_record(token, zone_id, fqdn, record_type):
    existing = lookup_record(token, zone_id, fqdn, record_type)
    if not existing:
        print(f"No {record_type} record found for {fqdn}")
        return
    api_request("DELETE", f"/zones/{zone_id}/dns_records/{existing['id']}", token)
    print(f"Deleted {record_type} record for {fqdn}")


def list_records(token, zone_id, fqdn, record_type):
    query = urllib.parse.urlencode({"name": fqdn, "type": record_type})
    response = api_request("GET", f"/zones/{zone_id}/dns_records?{query}", token)
    return response.get("result", [])


def delete_acme_txt_records(token, zone_id, zone_name, hostnames):
    for hostname in hostnames:
        fqdn = f"_acme-challenge.{hostname}.{zone_name}"
        records = list_records(token, zone_id, fqdn, "TXT")
        if not records:
            print(f"No TXT records found for {fqdn}")
            continue
        for record in records:
            api_request("DELETE", f"/zones/{zone_id}/dns_records/{record['id']}", token)
            print(f"Deleted TXT record for {fqdn}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone-name", required=True)
    parser.add_argument("--zone-id")
    parser.add_argument("--account-id", default=os.environ.get("CF_ACCOUNT_ID"))
    parser.add_argument("--api-token", default=os.environ.get("CF_API_TOKEN"))
    parser.add_argument("--vip1-ip", required=True)
    parser.add_argument("--vip2-ip", required=True)
    parser.add_argument("--vip1-host", default="vip1")
    parser.add_argument("--vip2-host", default="vip2")
    parser.add_argument("--proxied", action="store_true")
    parser.add_argument("--action", choices=["upsert", "delete", "delete-acme-txt"], default="upsert")
    args = parser.parse_args()

    if not args.api_token:
        print("Missing Cloudflare API token", file=sys.stderr)
        sys.exit(1)

    zone_id = args.zone_id
    if not zone_id:
        if not args.account_id:
            print("Missing Cloudflare account id", file=sys.stderr)
            sys.exit(1)
        zone_id = lookup_zone(args.api_token, args.account_id, args.zone_name)

    vip1_fqdn = f"{args.vip1_host}.{args.zone_name}"
    vip2_fqdn = f"{args.vip2_host}.{args.zone_name}"
    if args.action == "delete-acme-txt":
        delete_acme_txt_records(args.api_token, zone_id, args.zone_name, [args.vip1_host, args.vip2_host])
        return

    if args.action == "delete":
        delete_record(args.api_token, zone_id, vip1_fqdn, "A")
        delete_record(args.api_token, zone_id, vip2_fqdn, "A")
        return

    upsert_record(args.api_token, zone_id, vip1_fqdn, args.vip1_ip, args.proxied)
    upsert_record(args.api_token, zone_id, vip2_fqdn, args.vip2_ip, args.proxied)


if __name__ == "__main__":
    main()
