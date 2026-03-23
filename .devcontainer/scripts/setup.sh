#!/usr/bin/env bash
# postCreateCommand — one-time container setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/compute-urls.sh"

echo "=== Dev Container Setup ==="
echo "Repo:       $REPO_NAME"
echo "Branch:     $BRANCH_NAME"
echo "Hash:       $BRANCH_HASH"
echo "Web URL:    $WEB_URL"
echo "Auth URL:   $AUTH_URL"
echo "Tunnel:     $TUNNEL_NAME"
echo "==========================="

# Write .dev.vars for auth worker (overrides wrangler.toml [vars] during local dev)
cat > workers/auth-worker/.dev.vars <<EOF
BETTER_AUTH_SECRET=${BETTER_AUTH_SECRET}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
WEB_URL=${WEB_URL}
BETTER_AUTH_URL=${AUTH_URL}
EOF

echo "Wrote workers/auth-worker/.dev.vars"

# Run database migrations
pnpm db:migrate:local

echo "Setup complete."
