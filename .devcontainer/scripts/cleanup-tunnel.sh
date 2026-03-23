#!/usr/bin/env bash
# Clean up Cloudflare Tunnel and DNS records using saved state.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/../.tunnel-state/current.json"

CF_API="https://api.cloudflare.com/client/v4"

if [ ! -f "$STATE_FILE" ]; then
  echo "No tunnel state file found, nothing to clean up."
  exit 0
fi

TUNNEL_ID=$(jq -r '.tunnel_id' "$STATE_FILE")
WEB_HOSTNAME=$(jq -r '.web_hostname' "$STATE_FILE")
AUTH_HOSTNAME=$(jq -r '.auth_hostname' "$STATE_FILE")

# --- Delete DNS records ---
delete_dns_record() {
  local hostname="$1"

  local record_id
  record_id=$(curl -sf \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CNAME&name=$hostname" \
    | jq -r '.result[0].id // empty')

  if [ -n "$record_id" ]; then
    curl -sf \
      -X DELETE \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records/$record_id" > /dev/null
    echo "Deleted DNS record: $hostname"
  else
    echo "DNS record not found: $hostname"
  fi
}

delete_dns_record "$WEB_HOSTNAME"
delete_dns_record "$AUTH_HOSTNAME"

# --- Delete tunnel ---
# Must clean connections first
curl -sf \
  -X DELETE \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/connections" > /dev/null 2>&1 || true

curl -sf \
  -X DELETE \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID" > /dev/null

echo "Deleted tunnel: $TUNNEL_ID"

# Remove state file
rm -f "$STATE_FILE"
echo "Cleanup complete."
