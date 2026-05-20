#!/usr/bin/env bash
set -euo pipefail

OS_NAME="$(uname -s 2>/dev/null || echo unknown)"

case "$OS_NAME" in
  Linux)
    if [[ -n "${DISPLAY:-}" ]]; then
      notebooklm login
      exit 0
    fi
    echo "Linux headless mode detected."
    echo "Start a VNC/noVNC desktop first, then run: DISPLAY=:99 notebooklm login"
    echo "If this repo is installed through the producer skill, use deploy-linux-vnc.sh."
    exit 2
    ;;
  Darwin)
    notebooklm login
    ;;
  MINGW*|MSYS*|CYGWIN*)
    notebooklm login
    ;;
  *)
    notebooklm login
    ;;
esac

