#!/usr/bin/env bash
# Uploads storage_state.json to R2 when auth is currently valid.
# Safe to run at any time; exits 0 silently if nothing to do.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
ENV_FILE="$STATE_DIR/env"
STORAGE_STATE="${NOTEBOOKLM_STORAGE_STATE:-$HOME/.notebooklm/profiles/default/storage_state.json}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

NOTEBOOKLM_BIN="${NOTEBOOKLM_BIN:-notebooklm}"

if [[ ! -f "$STORAGE_STATE" ]]; then
  echo "[sync-auth] storage_state.json not found at $STORAGE_STATE" >&2
  exit 1
fi

if ! "$NOTEBOOKLM_BIN" list --json >/dev/null 2>&1; then
  echo "[sync-auth] Auth check failed, skipping upload" >&2
  exit 1
fi

"$ROOT_DIR/scripts/upload-file.sh" \
  --file "$STORAGE_STATE" \
  --name "storage_state.json" \
  --path "notebooklm" \
  >/dev/null

echo "[sync-auth] $(date -u '+%Y-%m-%d %H:%M:%S UTC') Uploaded storage_state.json to R2"
