#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
PORT="${NOTEBOOKLM_BRIDGE_PORT:-18800}"
HOST="${NOTEBOOKLM_BRIDGE_HOST:-localhost}"

mkdir -p "$STATE_DIR"

if [[ -f "$STATE_DIR/env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$STATE_DIR/env"
  set +a
fi

export NOTEBOOKLM_BRIDGE_PORT="$PORT"
export NOTEBOOKLM_BRIDGE_HOST="$HOST"
export NOTEBOOKLM_BRIDGE_TOKEN="${NOTEBOOKLM_BRIDGE_TOKEN:-${HERMES_WEBHOOK_TOKEN:-}}"

PYTHON="${PYTHON:-python3}"
exec "$PYTHON" -m uvicorn bridge.server:app --host "$HOST" --port "$PORT"
