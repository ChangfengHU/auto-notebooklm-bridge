#!/usr/bin/env bash
set -euo pipefail

OS_NAME="$(uname -s 2>/dev/null || echo unknown)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"

if [[ -f "$STATE_DIR/env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$STATE_DIR/env"
  set +a
fi

NOTEBOOKLM_CMD="${NOTEBOOKLM_BIN:-notebooklm}"

case "$OS_NAME" in
  Linux)
    if [[ -n "${DISPLAY:-}" ]]; then
      "$NOTEBOOKLM_CMD" login
      exit 0
    fi
    echo "Linux headless mode detected."
    echo "Start VNC first: ./scripts/deploy-linux-vnc.sh"
    echo "Then run: DISPLAY=:99 $NOTEBOOKLM_CMD login"
    exit 2
    ;;
  Darwin)
    "$NOTEBOOKLM_CMD" login
    ;;
  MINGW*|MSYS*|CYGWIN*)
    "$NOTEBOOKLM_CMD" login
    ;;
  *)
    "$NOTEBOOKLM_CMD" login
    ;;
esac
