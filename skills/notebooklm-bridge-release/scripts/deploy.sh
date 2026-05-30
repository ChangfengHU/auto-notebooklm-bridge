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

# ── Fix permissions on all scripts ───────────────────────────────────────────
chmod +x "$ROOT_DIR/scripts/"*.sh \
         "$ROOT_DIR/bridge/start.sh" \
         "$ROOT_DIR/vendor/auto-domain/"*.sh 2>/dev/null || true

# ── Load config.env (tokens) ─────────────────────────────────────────────────
CONFIG_ENV="$ROOT_DIR/config.env"
if [[ -f "$CONFIG_ENV" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$CONFIG_ENV"
  set +a
fi

# ── Check zip ────────────────────────────────────────────────────────────────
if ! command -v zip >/dev/null 2>&1; then
  echo "zip is required but not installed." >&2
  echo "Run: sudo apt-get install -y zip" >&2
  exit 1
fi

# ── Telegram helper ───────────────────────────────────────────────────────────
tg_notify() {
  local text="$1"
  [[ -z "${TG_BOT_TOKEN:-}" || -z "${TG_CHAT_ID:-}" ]] && return 0
  curl -fsS -X POST "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "{\"chat_id\":\"${TG_CHAT_ID}\",\"text\":$(python3 -c "import json,sys; print(json.dumps(sys.argv[1]))" "$text"),\"parse_mode\":\"HTML\"}" \
    >/dev/null 2>&1 || true
}

tg_msg() {
  local emoji="$1" title="$2"; shift 2
  local now; now="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  local msg="${emoji} <b>${title}</b>"$'\n'
  while [[ $# -ge 2 ]]; do
    msg+="   ${1}: <code>${2}</code>"$'\n'
    shift 2
  done
  msg+="   Time: ${now}"
  echo "$msg"
}

# ── Bridge env helpers ────────────────────────────────────────────────────────
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

# ── Deploy ────────────────────────────────────────────────────────────────────
MACHINE_ID="$("$ROOT_DIR/scripts/machine-id.sh")"
echo "MACHINE_ID=$MACHINE_ID"

tg_notify "$(tg_msg '🚀' 'Bridge Deploy Started' 'Machine' "$MACHINE_ID" 'Mode' "${SKIP_LOGIN:+skip-login}${SKIP_LOGIN:-full}")"

if ! "$ROOT_DIR/scripts/install-notebooklm.sh"; then
  tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'install-notebooklm' 'Machine' "$MACHINE_ID")"
  echo "NotebookLM CLI setup is incomplete." >&2
  exit 1
fi
load_bridge_env

# ── Prefer existing local auth, then try R2 before browser login ──────────────
if [[ "$SKIP_LOGIN" != "1" ]]; then
  if notebooklm_auth_ok; then
    echo "Existing local NotebookLM auth is valid — skipping browser login."
    tg_notify "$(tg_msg '🔑' 'Auth Reused Locally' 'Machine' "$MACHINE_ID" 'Hint' 'skip-login active')" || true
    SKIP_LOGIN=1
  elif "$ROOT_DIR/scripts/download-auth.sh" 2>/dev/null && notebooklm_auth_ok; then
    echo "Auth restored from R2 — skipping browser login."
    tg_notify "$(tg_msg '🔑' 'Auth Restored from R2' 'Machine' "$MACHINE_ID" 'Hint' 'skip-login active')" || true
    SKIP_LOGIN=1
  fi
fi

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
    tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'login' 'Machine' "$MACHINE_ID")"
    exit "$LOGIN_STATUS"
  fi
else
  if ! notebooklm_auth_ok; then
    tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'auth-check' 'Machine' "$MACHINE_ID" 'Hint' 'Run without --skip-login')"
    echo "--skip-login was requested, but NotebookLM auth is not valid." >&2
    exit 1
  fi
fi

if ! notebooklm_auth_ok; then
  tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'auth-check-post-login' 'Machine' "$MACHINE_ID")"
  echo "NotebookLM auth check failed after login." >&2
  exit 1
fi

"$ROOT_DIR/scripts/start-bridge.sh"
load_bridge_env

if ! bridge_run_list_ok "http://localhost:$PORT"; then
  tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'local-bridge-test' 'Machine' "$MACHINE_ID")"
  echo "Local bridge is running, but authenticated NotebookLM list test failed." >&2
  exit 1
fi

"$ROOT_DIR/scripts/start-domain.sh"
DOMAIN_LOG="$STATE_DIR/domain.log"

PUBLIC_URL=""
for _ in $(seq 1 60); do
  PUBLIC_URL="$(grep -Eo 'https://[^ ]+' "$DOMAIN_LOG" 2>/dev/null | head -1 || true)"
  [[ -n "$PUBLIC_URL" ]] && break
  sleep 2
done

if [[ -z "$PUBLIC_URL" ]]; then
  tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'auto-domain' 'Machine' "$MACHINE_ID" 'Log' "$DOMAIN_LOG")"
  echo "auto-domain did not print a public URL. Check $DOMAIN_LOG" >&2
  exit 1
fi

if ! curl -fsS "$PUBLIC_URL/health" >/dev/null 2>&1; then
  tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'public-health-check' 'URL' "$PUBLIC_URL")"
  echo "Public tunnel health check failed: $PUBLIC_URL/health" >&2
  exit 1
fi

if ! bridge_run_list_ok "$PUBLIC_URL"; then
  tg_notify "$(tg_msg '❌' 'Deploy Failed' 'Step' 'public-bridge-test' 'URL' "$PUBLIC_URL")"
  echo "Public bridge test failed: $PUBLIC_URL/run" >&2
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

BRIDGE_TOKEN="$(grep -E '^HERMES_WEBHOOK_TOKEN=' "$STATE_DIR/env" | cut -d= -f2)"

echo "PUBLIC_URL=$PUBLIC_URL"
echo "AUTH_STATUS=pass"
echo "BRIDGE_TOKEN_FILE=$STATE_DIR/env"
echo "CONSUMER_INSTALL_COMMAND=$INSTALL_COMMAND"

# ── Self-test curl command ────────────────────────────────────────────────────
echo ""
echo "=== Self-test ==="
echo "curl -s -X POST \"$PUBLIC_URL/run\" \\"
echo "  -H \"X-Token: $BRIDGE_TOKEN\" \\"
echo "  -H \"Content-Type: application/json\" \\"
echo "  -d '{\"args\": [\"list\", \"--json\"]}'"

# ── TG deploy success ─────────────────────────────────────────────────────────
tg_notify "$(tg_msg '✅' 'Bridge Deploy Success' \
  'Machine' "$MACHINE_ID" \
  'URL' "$PUBLIC_URL" \
  'Auth' 'pass' \
  'Consumer' "$INSTALL_COMMAND")"
