#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_NAME="notebooklm-bridge-release"
WORK_DIR="$(mktemp -d /tmp/notebooklm-release-skill-XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
TS="$(date +%Y%m%d%H%M%S)"

cp -R "$ROOT_DIR/skills/$SKILL_NAME" "$WORK_DIR/$SKILL_NAME"
ZIP_FILE="$WORK_DIR/${SKILL_NAME}-${TS}.zip"
(cd "$WORK_DIR" && zip -qr "$ZIP_FILE" "$SKILL_NAME")

ZIP_JSON="$("$ROOT_DIR/scripts/upload-file.sh" --file "$ZIP_FILE" --name "${SKILL_NAME}-${TS}.zip" --path "notebooklm-bridge/release")"
ZIP_URL="$(printf '%s' "$ZIP_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("image_url",""))')"

INSTALL_SCRIPT="$WORK_DIR/install-${SKILL_NAME}.sh"
sed "s|__ZIP_URL__|$ZIP_URL|g; s|__SKILL_NAME__|$SKILL_NAME|g" "$ROOT_DIR/templates/install-skill.sh" > "$INSTALL_SCRIPT"
chmod +x "$INSTALL_SCRIPT"

"$ROOT_DIR/scripts/upload-file.sh" --file "$INSTALL_SCRIPT" --name "install-${SKILL_NAME}.sh" >/dev/null
echo 'PRODUCER_INSTALL_COMMAND=bash <(curl -fsSL https://skill.vyibc.com/install-notebooklm-bridge-release.sh?v=$(date +%s))'
