#!/usr/bin/env bash
set -euo pipefail

SKIP_LOGIN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-login) SKIP_LOGIN=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_DIR="$SKILL_DIR"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
PORT="${NOTEBOOKLM_BRIDGE_PORT:-18800}"

mkdir -p "$STATE_DIR"

load_bridge_env() {
  if [[ -f "$STATE_DIR/env" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$STATE_DIR/env"
    set +a
  fi
}

notebooklm_auth_ok() {
  load_bridge_env
  local cmd="${NOTEBOOKLM_BIN:-notebooklm}"
  "$cmd" list --json >/dev/null 2>&1 && return 0
  "$cmd" auth check --test >/dev/null 2>&1 && return 0
  return 1
}

bridge_run_list_ok() {
  local url="$1"
  local token="${HERMES_WEBHOOK_TOKEN:-${NOTEBOOKLM_BRIDGE_TOKEN:-}}"
  [[ -n "$token" ]] || return 1
  curl -fsS -X POST "$url/run" \
    -H "X-Token: $token" \
    -H "Content-Type: application/json" \
    -d '{"args":["list","--json"]}' >/dev/null
}

MACHINE_ID="$("$ROOT_DIR/scripts/machine-id.sh")"
echo "MACHINE_ID=$MACHINE_ID"

if ! "$ROOT_DIR/scripts/install-notebooklm.sh"; then
  echo "NotebookLM CLI setup is incomplete." >&2
  echo "If Playwright Chromium is missing, run the command printed above and then rerun:" >&2
  echo "  $SKILL_DIR/scripts/deploy.sh" >&2
  exit 1
fi
load_bridge_env

if [[ "$SKIP_LOGIN" != "1" ]]; then
  set +e
  "$ROOT_DIR/scripts/login-notebooklm.sh"
  LOGIN_STATUS=$?
  set -e
  if [[ "$LOGIN_STATUS" == "2" ]]; then
    echo "Linux headless login needs VNC. Run:"
    echo "$SKILL_DIR/scripts/deploy-linux-vnc.sh"
    exit 2
  fi
  if [[ "$LOGIN_STATUS" != "0" ]]; then
    exit "$LOGIN_STATUS"
  fi
else
  if ! notebooklm_auth_ok; then
    echo "--skip-login was requested, but NotebookLM auth is not valid." >&2
    echo "Run without --skip-login or login manually, then rerun deploy." >&2
    exit 1
  fi
fi

if ! notebooklm_auth_ok; then
  echo "NotebookLM auth check failed after login." >&2
  echo "Try one of these commands, then rerun deploy:" >&2
  echo "  ${NOTEBOOKLM_BIN:-notebooklm} login" >&2
  echo "  ${NOTEBOOKLM_BIN:-notebooklm} login --browser-cookies chrome" >&2
  exit 1
fi

"$ROOT_DIR/scripts/start-bridge.sh"
load_bridge_env

if ! bridge_run_list_ok "http://localhost:$PORT"; then
  echo "Local bridge is running, but authenticated NotebookLM list test failed." >&2
  echo "Check $STATE_DIR/bridge.log and NotebookLM login state." >&2
  exit 1
fi

"$ROOT_DIR/scripts/start-domain.sh"
DOMAIN_LOG="$STATE_DIR/domain.log"

PUBLIC_URL=""
for _ in $(seq 1 60); do
  PUBLIC_URL="$(grep -Eo 'https://[^ ]+' "$DOMAIN_LOG" 2>/dev/null | head -1 || true)"
  if [[ -n "$PUBLIC_URL" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$PUBLIC_URL" ]]; then
  echo "auto-domain did not print a public URL. Check $DOMAIN_LOG" >&2
  exit 1
fi

if ! curl -fsS "$PUBLIC_URL/health" >/dev/null 2>&1; then
  echo "Public tunnel URL was allocated, but health check failed: $PUBLIC_URL/health" >&2
  echo "Local bridge is still running. Check tunnel logs:" >&2
  echo "  $DOMAIN_LOG" >&2
  echo "  $HOME/.tunneling/machine-agent/agent.log" >&2
  echo "If domain.log contains a command for wss://domain-gateway.vyibc.com, run that command and rerun deploy with --skip-login." >&2
  grep -E "domain-gateway\.vyibc\.com|wss://" "$DOMAIN_LOG" 2>/dev/null >&2 || true
  exit 1
fi

if ! bridge_run_list_ok "$PUBLIC_URL"; then
  echo "Public bridge is reachable, but token-protected NotebookLM list test failed: $PUBLIC_URL/run" >&2
  echo "Check token in $STATE_DIR/env and tunnel logs:" >&2
  echo "  $DOMAIN_LOG" >&2
  echo "  $HOME/.tunneling/machine-agent/agent.log" >&2
  exit 1
fi

cat > "$STATE_DIR/domain-current.json" <<JSON
{
  "machine_id": "$MACHINE_ID",
  "public_url": "$PUBLIC_URL",
  "forward_to": "http://localhost:$PORT"
}
JSON

DOMAIN_PATH="notebooklm-bridge/${MACHINE_ID}/domain"
"$ROOT_DIR/scripts/upload-file.sh" --file "$STATE_DIR/domain-current.json" --name current.json --path "$DOMAIN_PATH" >/dev/null

RELEASE_OUTPUT="$("$ROOT_DIR/scripts/publish-consumer-skill.sh" --public-url "$PUBLIC_URL")"
echo "$RELEASE_OUTPUT"
INSTALL_COMMAND="$(printf '%s\n' "$RELEASE_OUTPUT" | sed -n 's/^INSTALL_COMMAND=//p')"

echo "PUBLIC_URL=$PUBLIC_URL"
echo "AUTH_STATUS=pass"
echo "BRIDGE_TOKEN_FILE=$STATE_DIR/env"
echo "CONSUMER_INSTALL_COMMAND=$INSTALL_COMMAND"
