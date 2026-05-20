#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
PORT="${NOTEBOOKLM_BRIDGE_PORT:-18800}"

mkdir -p "$STATE_DIR"

if [[ -f "$STATE_DIR/env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$STATE_DIR/env"
  set +a
fi

cd "$ROOT_DIR"
PYTHON_BIN="${NOTEBOOKLM_BIN%/notebooklm}"
PYTHON_BIN="${PYTHON_BIN%/notebooklm.exe}"
if [[ -x "$PYTHON_BIN/python" ]]; then
  BRIDGE_PYTHON="$PYTHON_BIN/python"
elif [[ -x "$PYTHON_BIN/python.exe" ]]; then
  BRIDGE_PYTHON="$PYTHON_BIN/python.exe"
else
  BRIDGE_PYTHON="${PYTHON:-python3}"
fi

"$BRIDGE_PYTHON" -m pip install -r bridge/requirements.txt >/dev/null

if [[ -z "${NOTEBOOKLM_BRIDGE_TOKEN:-${HERMES_WEBHOOK_TOKEN:-}}" ]]; then
  TOKEN="$("$BRIDGE_PYTHON" - <<'PY'
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
NOTEBOOKLM_BRIDGE_PORT="$PORT" PYTHON="$BRIDGE_PYTHON" nohup "$ROOT_DIR/bridge/start.sh" >"$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

sleep 2
curl -fsS "http://localhost:$PORT/health" >/dev/null
echo "BRIDGE_LOCAL_URL=http://localhost:$PORT"
echo "BRIDGE_PID=$(cat "$PID_FILE")"
