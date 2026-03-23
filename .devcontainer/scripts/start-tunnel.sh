#!/usr/bin/env bash
# postStartCommand — create Cloudflare Tunnel, DNS records, and start dev servers.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/compute-urls.sh"

CF_API="https://api.cloudflare.com/client/v4"
STATE_DIR="$SCRIPT_DIR/../.tunnel-state"
STATE_FILE="$STATE_DIR/current.json"

mkdir -p "$STATE_DIR"

# --- Cleanup trap ---
cleanup() {
  echo "Cleaning up tunnel and DNS records..."
  "$SCRIPT_DIR/cleanup-tunnel.sh" || true
}
trap cleanup EXIT

# --- Verify required env vars ---
for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_ZONE_ID; do
  if [ -z "${!var:-}" ]; then
    echo "Error: $var is not set. Make sure it's exported in your shell environment."
    echo "(devcontainer.json reads from host env vars, not .env files)"
    exit 1
  fi
done

# --- Create or reuse Cloudflare Tunnel ---
echo "Creating Cloudflare Tunnel: $TUNNEL_NAME"

# Check if tunnel already exists
EXISTING_TUNNEL=$(curl -s --fail-with-body \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME&is_deleted=false")

if [ $? -ne 0 ]; then
  echo "Failed to query tunnels:"
  echo "$EXISTING_TUNNEL" | jq . 2>/dev/null || echo "$EXISTING_TUNNEL"
  exit 1
fi

EXISTING_TUNNEL=$(echo "$EXISTING_TUNNEL" | jq -r '.result[0] // empty')

if [ -n "$EXISTING_TUNNEL" ]; then
  TUNNEL_ID=$(echo "$EXISTING_TUNNEL" | jq -r '.id')
  echo "Reusing existing tunnel: $TUNNEL_ID"
else
  TUNNEL_RESPONSE=$(curl -sf \
    -X POST \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$TUNNEL_NAME\", \"tunnel_secret\": \"$(openssl rand -base64 32)\"}" \
    "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel")

  TUNNEL_ID=$(echo "$TUNNEL_RESPONSE" | jq -r '.result.id')
  if [ -z "$TUNNEL_ID" ] || [ "$TUNNEL_ID" = "null" ]; then
    echo "Failed to create tunnel:"
    echo "$TUNNEL_RESPONSE" | jq .
    exit 1
  fi
  echo "Created tunnel: $TUNNEL_ID"
fi

# --- Get tunnel token ---
TOKEN_RESPONSE=$(curl -sf \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/token")

TUNNEL_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.result')
if [ -z "$TUNNEL_TOKEN" ] || [ "$TUNNEL_TOKEN" = "null" ]; then
  echo "Failed to get tunnel token:"
  echo "$TOKEN_RESPONSE" | jq .
  exit 1
fi

# --- Configure tunnel ingress ---
echo "Configuring tunnel ingress..."
curl -sf \
  -X PUT \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$(jq -n \
    --arg web_host "$WEB_HOSTNAME" \
    --arg auth_host "$AUTH_HOSTNAME" \
    '{
      config: {
        ingress: [
          { hostname: $web_host, service: "http://localhost:3000" },
          { hostname: $auth_host, service: "http://localhost:8788" },
          { service: "http_status:404" }
        ]
      }
    }')" \
  "$CF_API/accounts/$CLOUDFLARE_ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" > /dev/null

# --- Create DNS CNAME records ---
CNAME_TARGET="${TUNNEL_ID}.cfargotunnel.com"

create_dns_record() {
  local hostname="$1"
  local record_name="$hostname"

  # Check if record exists
  local existing
  existing=$(curl -sf \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records?type=CNAME&name=$record_name" \
    | jq -r '.result[0].id // empty')

  if [ -n "$existing" ]; then
    # Update existing record
    curl -sf \
      -X PUT \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"type\": \"CNAME\", \"name\": \"$record_name\", \"content\": \"$CNAME_TARGET\", \"proxied\": true}" \
      "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records/$existing" > /dev/null
    echo "Updated DNS: $record_name -> $CNAME_TARGET"
  else
    # Create new record
    curl -sf \
      -X POST \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"type\": \"CNAME\", \"name\": \"$record_name\", \"content\": \"$CNAME_TARGET\", \"proxied\": true}" \
      "$CF_API/zones/$CLOUDFLARE_ZONE_ID/dns_records" > /dev/null
    echo "Created DNS: $record_name -> $CNAME_TARGET"
  fi
}

create_dns_record "$WEB_HOSTNAME"
create_dns_record "$AUTH_HOSTNAME"

# --- Save tunnel state for cleanup ---
jq -n \
  --arg tunnel_id "$TUNNEL_ID" \
  --arg tunnel_name "$TUNNEL_NAME" \
  --arg web_hostname "$WEB_HOSTNAME" \
  --arg auth_hostname "$AUTH_HOSTNAME" \
  '{
    tunnel_id: $tunnel_id,
    tunnel_name: $tunnel_name,
    web_hostname: $web_hostname,
    auth_hostname: $auth_hostname
  }' > "$STATE_FILE"

echo "Tunnel state saved to $STATE_FILE"

# --- Start cloudflared in background ---
echo "Starting cloudflared..."
cloudflared tunnel run --token "$TUNNEL_TOKEN" &
CLOUDFLARED_PID=$!

# --- Write .env.local for Vite ---
cat > .env.local <<EOF
VITE_AUTH_WORKER_URL=${AUTH_URL}
EOF
echo "Wrote .env.local with VITE_AUTH_WORKER_URL=$AUTH_URL"

# --- Start dev servers ---
echo ""
echo "==========================================="
echo "  Web:  $WEB_URL"
echo "  Auth: $AUTH_URL"
echo "==========================================="
echo ""

WEB_URL="$WEB_URL" BETTER_AUTH_URL="$AUTH_URL" pnpm dev

# If pnpm dev exits, also kill cloudflared
kill $CLOUDFLARED_PID 2>/dev/null || true
