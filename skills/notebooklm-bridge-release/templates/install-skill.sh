#!/usr/bin/env bash
set -euo pipefail

SKILL_NAME="__SKILL_NAME__"
ZIP_URL="__ZIP_URL__"
TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "Choose install target:"
  echo "  1) Codex        ~/.codex/skills"
  echo "  2) Cursor       ~/.cursor/skills"
  echo "  3) Claude       ~/.claude/skills"
  echo "  4) Gemini       ~/.gemini/skills"
  echo "  5) Antigravity  ~/.gemini/antigravity/skills"
  echo "  6) Copilot      ~/.copilot/skills"
  echo "  7) OpenClaw     ~/.openclaw/workspace/skills"
  echo "  8) Agents       ~/.agents/skills"
  echo "  9) Hermes       ~/.hermes/skills/devops"
  echo " 10) All"
  read -r -p "Target [1-10]: " CHOICE
  case "$CHOICE" in
    1) TARGET="codex" ;;
    2) TARGET="cursor" ;;
    3) TARGET="claude" ;;
    4) TARGET="gemini" ;;
    5) TARGET="antigravity" ;;
    6) TARGET="copilot" ;;
    7) TARGET="openclaw" ;;
    8) TARGET="agents" ;;
    9) TARGET="hermes" ;;
   10) TARGET="all" ;;
    *) echo "invalid target" >&2; exit 1 ;;
  esac
fi

case "$TARGET" in
  codex) DIRS=("$HOME/.codex/skills") ;;
  cursor) DIRS=("$HOME/.cursor/skills") ;;
  claude) DIRS=("$HOME/.claude/skills") ;;
  gemini) DIRS=("$HOME/.gemini/skills") ;;
  antigravity) DIRS=("$HOME/.gemini/antigravity/skills") ;;
  copilot) DIRS=("$HOME/.copilot/skills") ;;
  openclaw) DIRS=("$HOME/.openclaw/workspace/skills") ;;
  agents) DIRS=("$HOME/.agents/skills") ;;
  hermes) DIRS=("$HOME/.hermes/skills/devops") ;;
  all)
    DIRS=(
      "$HOME/.codex/skills"
      "$HOME/.cursor/skills"
      "$HOME/.claude/skills"
      "$HOME/.gemini/skills"
      "$HOME/.gemini/antigravity/skills"
      "$HOME/.copilot/skills"
      "$HOME/.openclaw/workspace/skills"
      "$HOME/.agents/skills"
      "$HOME/.hermes/skills/devops"
    ) ;;
  *) echo "unsupported target: $TARGET" >&2; exit 1 ;;
esac

TMPWORK="$(mktemp -d /tmp/install-skill-XXXXXX)"
trap 'rm -rf "$TMPWORK"' EXIT

curl -fsSL "$ZIP_URL" -o "$TMPWORK/skill.zip"
mkdir -p "$TMPWORK/extracted"
if command -v unzip >/dev/null 2>&1; then
  unzip -q "$TMPWORK/skill.zip" -d "$TMPWORK/extracted"
elif command -v python3 >/dev/null 2>&1; then
  python3 -m zipfile -e "$TMPWORK/skill.zip" "$TMPWORK/extracted"
elif command -v python >/dev/null 2>&1; then
  python -m zipfile -e "$TMPWORK/skill.zip" "$TMPWORK/extracted"
else
  echo "unzip or python is required to extract the skill archive" >&2
  exit 1
fi

EXTRACTED_DIR="$TMPWORK/extracted/$SKILL_NAME"
if [[ ! -d "$EXTRACTED_DIR" ]]; then
  EXTRACTED_DIR="$(find "$TMPWORK/extracted" -mindepth 1 -maxdepth 1 -type d | head -1)"
fi
if [[ -z "$EXTRACTED_DIR" || ! -d "$EXTRACTED_DIR" ]]; then
  echo "could not find extracted skill directory" >&2
  exit 1
fi

for BASE_DIR in "${DIRS[@]}"; do
  mkdir -p "$BASE_DIR"
  rm -rf "$BASE_DIR/$SKILL_NAME"
  cp -R "$EXTRACTED_DIR" "$BASE_DIR/$SKILL_NAME"
  find "$BASE_DIR/$SKILL_NAME/scripts" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
  echo "installed: $BASE_DIR/$SKILL_NAME"
done
