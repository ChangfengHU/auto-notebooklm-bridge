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

MACHINE_ID="$("$ROOT_DIR/scripts/machine-id.sh")"
echo "MACHINE_ID=$MACHINE_ID"

"$ROOT_DIR/scripts/install-notebooklm.sh"

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
fi

"$ROOT_DIR/scripts/start-bridge.sh"

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
echo "CONSUMER_INSTALL_COMMAND=$INSTALL_COMMAND"
