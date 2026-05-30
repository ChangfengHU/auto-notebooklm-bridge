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

if command -v pkill >/dev/null 2>&1; then
  pkill -f ".tunneling/machine-agent" 2>/dev/null || true
  pkill -f "machine-agent" 2>/dev/null || true
fi

if command -v taskkill >/dev/null 2>&1; then
  taskkill //F //IM machine-agent.exe >/dev/null 2>&1 || true
fi

if [[ -f "$HOME/.auto-domain/config" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.auto-domain/config" 2>/dev/null || true
fi

AUTO_DOMAIN_URL="${AUTO_DOMAIN_URL:-https://skill.vyibc.com/auto-domain.sh}"
AUTO_DOMAIN_ARGS=(
  "--port=$PORT"
  "--name=$DOMAIN_NAME"
  "--daemon"
  "--replace"
)
if [[ -n "${AUTO_DOMAIN_TOKEN:-}" ]]; then
  AUTO_DOMAIN_ARGS+=("--token=$AUTO_DOMAIN_TOKEN")
fi

if [[ "$FOREGROUND" == "1" ]]; then
  bash <(curl -fsSL "$AUTO_DOMAIN_URL") "${AUTO_DOMAIN_ARGS[@]}" | tee "$DOMAIN_LOG"
  exit 0
fi

setsid bash -c 'bash <(curl -fsSL "$1") "${@:2}"' _ "$AUTO_DOMAIN_URL" "${AUTO_DOMAIN_ARGS[@]}" >"$DOMAIN_LOG" 2>&1 < /dev/null &
echo $! > "$PID_FILE"
echo "DOMAIN_PID=$(cat "$PID_FILE")"
echo "DOMAIN_LOG=$DOMAIN_LOG"
