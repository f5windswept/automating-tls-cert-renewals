#!/usr/bin/env sh

CF_API_BASE="https://api.cloudflare.com/client/v4"

dns_cloudflare_add() {
    fulldomain=$1
    txtvalue=$2

    _cf_require_vars || return 1

    payload=$(printf '{"type":"TXT","name":"%s","content":"%s","ttl":60}' "$fulldomain" "$txtvalue")

    _cf_resolve_zone_id || return 1

    response=$(curl -sk -X POST \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        "${CF_API_BASE}/zones/${CF_RESOLVED_ZONE_ID}/dns_records" \
        --data "$payload")

    printf "%s" "$response" | grep -q '"success":true' || {
        f5_process_errors "ERROR dns_cloudflare: failed adding TXT record for ${fulldomain}"
        printf "%s\n" "$response" >&2
        return 1
    }

    if [ -n "$DNS_DELAY" ]; then
        sleep "$DNS_DELAY"
    else
        sleep 60
    fi

    f5_process_errors "DEBUG dns_cloudflare: added TXT record for ${fulldomain}"
    return 0
}

dns_cloudflare_rm() {
    fulldomain=$1
    txtvalue=$2

    _cf_require_vars || return 1

    query_name=$(printf "%s" "$fulldomain" | sed 's/+/%2B/g')
    _cf_resolve_zone_id || return 1

    response=$(curl -sk \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        "${CF_API_BASE}/zones/${CF_RESOLVED_ZONE_ID}/dns_records?type=TXT&name=${query_name}")

    record_ids=$(RESPONSE_JSON="$response" python - "$txtvalue" <<'PY'
import json
import os
import sys

payload = json.loads(os.environ['RESPONSE_JSON'])
target = sys.argv[1]
for item in payload.get('result', []):
    if item.get('content') == target:
        print(item.get('id', ''))
PY
)
    [ -z "$record_ids" ] && return 0

    for record_id in $record_ids; do
        delete_response=$(curl -sk -X DELETE \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            "${CF_API_BASE}/zones/${CF_RESOLVED_ZONE_ID}/dns_records/${record_id}")
        printf "%s" "$delete_response" | grep -q '"success":true' || {
            f5_process_errors "ERROR dns_cloudflare: failed removing TXT record for ${fulldomain}"
            printf "%s\n" "$delete_response" >&2
            return 1
        }
    done

    f5_process_errors "DEBUG dns_cloudflare: removed TXT record for ${fulldomain}"
    return 0
}

_cf_require_vars() {
    [ -z "$CF_API_TOKEN" ] && {
        f5_process_errors "ERROR dns_cloudflare: CF_API_TOKEN is not set"
        return 1
    }
    [ -z "$CF_ACCOUNT_ID" ] && {
        f5_process_errors "ERROR dns_cloudflare: CF_ACCOUNT_ID is not set"
        return 1
    }
    [ -z "$CF_ZONE_NAME" ] && {
        f5_process_errors "ERROR dns_cloudflare: CF_ZONE_NAME is not set"
        return 1
    }
    return 0
}

_cf_resolve_zone_id() {
    if [ -n "$CF_RESOLVED_ZONE_ID" ]; then
        return 0
    fi

    response=$(curl -sk \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        "${CF_API_BASE}/zones?name=${CF_ZONE_NAME}&account.id=${CF_ACCOUNT_ID}")

    CF_RESOLVED_ZONE_ID=$(RESPONSE_JSON="$response" python - <<'PY'
import json
import os

payload = json.loads(os.environ['RESPONSE_JSON'])
results = payload.get('result', [])
print(results[0]['id'] if results else '')
PY
)

    [ -z "$CF_RESOLVED_ZONE_ID" ] && {
        f5_process_errors "ERROR dns_cloudflare: failed to resolve Cloudflare zone id for ${CF_ZONE_NAME}"
        printf "%s\n" "$response" >&2
        return 1
    }

    return 0
}
