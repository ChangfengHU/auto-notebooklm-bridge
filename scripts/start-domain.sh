#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
PORT="${NOTEBOOKLM_BRIDGE_PORT:-18800}"
MACHINE_ID="$("$ROOT_DIR/scripts/machine-id.sh")"
DOMAIN_NAME="${NOTEBOOKLM_DOMAIN_NAME:-notebooklm-bridge-${MACHINE_ID}}"
DOMAIN_LOG="$STATE_DIR/domain.log"
PID_FILE="$STATE_DIR/domain.pid"
FOREGROUND=0

if [[ "${1:-}" == "--foreground" ]]; then
  FOREGROUND=1
fi

mkdir -p "$STATE_DIR"

if [[ ! -x "$ROOT_DIR/vendor/auto-domain/run.sh" && -x "$HOME/.codex/skills/auto-domain/scripts/run.sh" ]]; then
  AUTO_DOMAIN="$HOME/.codex/skills/auto-domain/scripts/run.sh"
else
  AUTO_DOMAIN="$ROOT_DIR/vendor/auto-domain/run.sh"
fi

if [[ ! -x "$AUTO_DOMAIN" ]]; then
  echo "auto-domain skill is required. Install it before running release." >&2
  exit 1
fi

if [[ "$FOREGROUND" == "1" ]]; then
  "$AUTO_DOMAIN" "$PORT" "$DOMAIN_NAME" | tee "$DOMAIN_LOG"
  exit 0
fi

nohup "$AUTO_DOMAIN" "$PORT" "$DOMAIN_NAME" >"$DOMAIN_LOG" 2>&1 &
echo $! > "$PID_FILE"
echo "DOMAIN_PID=$(cat "$PID_FILE")"
echo "DOMAIN_LOG=$DOMAIN_LOG"
