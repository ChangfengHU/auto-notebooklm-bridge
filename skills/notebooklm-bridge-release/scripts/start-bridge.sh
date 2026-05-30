#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
PORT="${NOTEBOOKLM_BRIDGE_PORT:-18800}"

mkdir -p "$STATE_DIR"

ENV_FILE="$STATE_DIR/env"
upsert_env() {
  local key="$1"
  local value="$2"
  touch "$ENV_FILE"
  if grep -q "^${key}=" "$ENV_FILE"; then
    awk -v key="$key" -v value="$value" '
      index($0, key "=") == 1 { print key "=" value; next }
      { print }
    ' "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

cd "$ROOT_DIR"
NOTEBOOKLM_BIN="${NOTEBOOKLM_BIN:-notebooklm}"
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
  export NOTEBOOKLM_BRIDGE_TOKEN="$TOKEN"
  export HERMES_WEBHOOK_TOKEN="$TOKEN"
else
  TOKEN="${NOTEBOOKLM_BRIDGE_TOKEN:-${HERMES_WEBHOOK_TOKEN:-}}"
  export NOTEBOOKLM_BRIDGE_TOKEN="$TOKEN"
  export HERMES_WEBHOOK_TOKEN="$TOKEN"
fi
upsert_env "NOTEBOOKLM_BRIDGE_TOKEN" "$TOKEN"
upsert_env "HERMES_WEBHOOK_TOKEN" "$TOKEN"

LOG_FILE="$STATE_DIR/bridge.log"
PID_FILE="$STATE_DIR/bridge.pid"
if [[ -f "$PID_FILE" ]]; then
  OLD_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    kill "$OLD_PID" 2>/dev/null || true
    sleep 1
  fi
fi
setsid bash -c 'NOTEBOOKLM_BRIDGE_PORT="$1" PYTHON="$2" exec "$3" >>"$4" 2>&1' _ "$PORT" "$BRIDGE_PYTHON" "$ROOT_DIR/bridge/start.sh" "$LOG_FILE" < /dev/null &
echo $! > "$PID_FILE"

sleep 2
curl -fsS "http://localhost:$PORT/health" >/dev/null
echo "BRIDGE_LOCAL_URL=http://localhost:$PORT"
echo "BRIDGE_PID=$(cat "$PID_FILE")"

# ── Background auth sync: upload valid storage_state.json to R2 every 30 min ──
AUTH_SYNC_LOG="$STATE_DIR/auth-sync.log"
AUTH_SYNC_PID="$STATE_DIR/auth-sync.pid"
SYNC_SCRIPT="$ROOT_DIR/scripts/sync-auth.sh"
if [[ -x "$SYNC_SCRIPT" ]]; then
  (
    while true; do
      sleep 1800
      "$SYNC_SCRIPT" >> "$AUTH_SYNC_LOG" 2>&1 || true
    done
  ) &
  echo $! > "$AUTH_SYNC_PID"
  # Run once immediately so R2 always has the latest auth on fresh deploy
  "$SYNC_SCRIPT" >> "$AUTH_SYNC_LOG" 2>&1 || true
  echo "AUTH_SYNC_PID=$(cat "$AUTH_SYNC_PID")"
fi
