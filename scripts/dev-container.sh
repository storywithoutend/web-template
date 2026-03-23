#!/usr/bin/env bash
set -euo pipefail

# Launch the dev container from the CLI (no VS Code required).
# Uses @devcontainers/cli to build, start, and attach to the container.

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"

# --- Pre-flight checks ---

# 1. Source .env file if it exists (devcontainer.json reads from host env)
if [ -f "$WORKSPACE/.env" ]; then
  set -a
  source "$WORKSPACE/.env"
  set +a
fi

# 2. Docker must be running
if ! docker info >/dev/null 2>&1; then
  echo "Error: Docker is not running. Please start Docker and try again."
  exit 1
fi

# --- Start the container ---

echo "Building and starting the dev container..."
npx -y @devcontainers/cli up --workspace-folder "$WORKSPACE"

echo ""
echo "Attaching to the container..."
npx -y @devcontainers/cli exec --workspace-folder "$WORKSPACE" /bin/bash
