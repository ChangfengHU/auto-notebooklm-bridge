#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
MACHINE_ID_FILE="$STATE_DIR/machine-id"

mkdir -p "$STATE_DIR"

if [[ -s "$MACHINE_ID_FILE" ]]; then
  cat "$MACHINE_ID_FILE"
  exit 0
fi

if command -v uuidgen >/dev/null 2>&1; then
  RAW_ID="$(uuidgen)"
else
  RAW_ID="$(date +%s)-$RANDOM-$RANDOM"
fi

if command -v sha256sum >/dev/null 2>&1; then
  HASH="$(printf '%s' "$RAW_ID" | sha256sum | awk '{print $1}')"
else
  HASH="$(printf '%s' "$RAW_ID" | shasum -a 256 | awk '{print $1}')"
fi
MACHINE_ID="nbb-$(printf '%s' "$HASH" | cut -c1-10)"
printf '%s\n' "$MACHINE_ID" > "$MACHINE_ID_FILE"
chmod 600 "$MACHINE_ID_FILE"
cat "$MACHINE_ID_FILE"
