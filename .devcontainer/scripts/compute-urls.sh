#!/usr/bin/env bash
# Sourced utility — exports URL/hostname variables for tunnel scripts.
# Usage: source .devcontainer/scripts/compute-urls.sh

set -euo pipefail

REPO_NAME="$(basename -s .git "$(git remote get-url origin)")"
BRANCH_NAME="$(git rev-parse --abbrev-ref HEAD)"
BRANCH_HASH="$(printf '%s' "$BRANCH_NAME" | sha256sum | cut -c1-8)"
STAGE="${STAGE:-localhost}"

WEB_HOSTNAME="${REPO_NAME}-${BRANCH_HASH}.${STAGE}.yolotime.dev"
AUTH_HOSTNAME="auth.${REPO_NAME}-${BRANCH_HASH}.${STAGE}.yolotime.dev"

WEB_URL="https://${WEB_HOSTNAME}"
AUTH_URL="https://${AUTH_HOSTNAME}"

TUNNEL_NAME="${REPO_NAME}-${BRANCH_HASH}-${STAGE}"

export REPO_NAME BRANCH_NAME BRANCH_HASH STAGE
export WEB_HOSTNAME AUTH_HOSTNAME
export WEB_URL AUTH_URL
export TUNNEL_NAME
