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

run_login() {
  if "$NOTEBOOKLM_CMD" login; then
    return 0
  fi

  echo "Normal notebooklm login failed." >&2
  echo "Trying Chrome cookie login: $NOTEBOOKLM_CMD login --browser-cookies chrome" >&2
  "$NOTEBOOKLM_CMD" login --browser-cookies chrome
}

case "$OS_NAME" in
  Linux)
    if [[ -n "${DISPLAY:-}" ]]; then
      run_login
      exit 0
    fi
    echo "Linux headless mode detected."
    echo "Start VNC first: ./scripts/deploy-linux-vnc.sh"
    echo "Then run: DISPLAY=:99 $NOTEBOOKLM_CMD login"
    exit 2
    ;;
  Darwin)
    run_login
    ;;
  MINGW*|MSYS*|CYGWIN*)
    run_login
    ;;
  *)
    run_login
    ;;
esac
