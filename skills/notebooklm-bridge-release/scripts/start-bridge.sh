#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
PORT="${NOTEBOOKLM_BRIDGE_PORT:-18800}"

mkdir -p "$STATE_DIR"

cd "$ROOT_DIR"
python3 -m pip install --user -r bridge/requirements.txt >/dev/null

if [[ -z "${NOTEBOOKLM_BRIDGE_TOKEN:-${HERMES_WEBHOOK_TOKEN:-}}" ]]; then
  TOKEN="$(python3 - <<'PY'
import secrets
print(secrets.token_urlsafe(32))
PY
)"
  {
    echo "NOTEBOOKLM_BRIDGE_TOKEN=$TOKEN"
    echo "HERMES_WEBHOOK_TOKEN=$TOKEN"
  } >> "$STATE_DIR/env"
  export NOTEBOOKLM_BRIDGE_TOKEN="$TOKEN"
  export HERMES_WEBHOOK_TOKEN="$TOKEN"
fi

LOG_FILE="$STATE_DIR/bridge.log"
PID_FILE="$STATE_DIR/bridge.pid"
NOTEBOOKLM_BRIDGE_PORT="$PORT" nohup "$ROOT_DIR/bridge/start.sh" >"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 2
curl -fsS "http://localhost:$PORT/health" >/dev/null
echo "BRIDGE_LOCAL_URL=http://localhost:$PORT"
echo "BRIDGE_PID=$(cat "$PID_FILE")"
