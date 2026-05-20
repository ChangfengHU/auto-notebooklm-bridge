#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
MACHINE_ID="$("$ROOT_DIR/scripts/machine-id.sh")"
PUBLIC_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --public-url) PUBLIC_URL="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PUBLIC_URL" ]]; then
  echo "missing --public-url" >&2
  exit 1
fi

if [[ -f "$STATE_DIR/env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$STATE_DIR/env"
  set +a
fi

BRIDGE_TOKEN="${HERMES_WEBHOOK_TOKEN:-${NOTEBOOKLM_BRIDGE_TOKEN:-}}"
if [[ -z "$BRIDGE_TOKEN" ]]; then
  echo "missing HERMES_WEBHOOK_TOKEN or NOTEBOOKLM_BRIDGE_TOKEN in $STATE_DIR/env" >&2
  exit 1
fi

WORK_DIR="$(mktemp -d /tmp/notebooklm-consumer-skill-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
SKILL_NAME="notebooklm-bridge"
SKILL_DIR="$WORK_DIR/$SKILL_NAME"
mkdir -p "$SKILL_DIR"

if [[ -f "$ROOT_DIR/templates/notebooklm-bridge.SKILL.md" ]]; then
  TEMPLATE="$ROOT_DIR/templates/notebooklm-bridge.SKILL.md"
else
  TEMPLATE="$ROOT_DIR/skills/notebooklm-bridge/SKILL.md"
fi

sed "s|__PUBLIC_URL__|$PUBLIC_URL|g; s|__HERMES_WEBHOOK_TOKEN__|$BRIDGE_TOKEN|g" "$TEMPLATE" > "$SKILL_DIR/SKILL.md"
cat > "$SKILL_DIR/bridge.env" <<ENV
NOTEBOOKLM_BRIDGE_URL="$PUBLIC_URL"
HERMES_WEBHOOK_TOKEN="$BRIDGE_TOKEN"
NOTEBOOKLM_BRIDGE_TOKEN="$BRIDGE_TOKEN"
ENV

ZIP_FILE="$WORK_DIR/${SKILL_NAME}.zip"
(cd "$WORK_DIR" && zip -qr "$ZIP_FILE" "$SKILL_NAME")

RELEASE_PATH="notebooklm-bridge/${MACHINE_ID}/release"
ZIP_JSON="$("$ROOT_DIR/scripts/upload-file.sh" --file "$ZIP_FILE" --name "${SKILL_NAME}.zip" --path "$RELEASE_PATH")"
ZIP_URL="$(printf '%s' "$ZIP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("image_url",""))')"

INSTALL_SCRIPT="$WORK_DIR/install-${SKILL_NAME}.sh"
sed "s|__ZIP_URL__|$ZIP_URL|g; s|__SKILL_NAME__|$SKILL_NAME|g" "$ROOT_DIR/templates/install-skill.sh" > "$INSTALL_SCRIPT"
chmod +x "$INSTALL_SCRIPT"

INSTALL_JSON="$("$ROOT_DIR/scripts/upload-file.sh" --file "$INSTALL_SCRIPT" --name "install-${SKILL_NAME}.sh" --path "$RELEASE_PATH")"
INSTALL_URL="$(printf '%s' "$INSTALL_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("image_url",""))')"

mkdir -p "$STATE_DIR"
cat > "$STATE_DIR/release.json" <<JSON
{
  "machine_id": "$MACHINE_ID",
  "public_url": "$PUBLIC_URL",
  "zip_url": "$ZIP_URL",
  "install_url": "$INSTALL_URL",
  "install_command": "bash <(curl -fsSL \\\"$INSTALL_URL?v=\$(date +%s)\\\")"
}
JSON

echo "INSTALL_COMMAND=bash <(curl -fsSL \"$INSTALL_URL?v=\$(date +%s)\")"
