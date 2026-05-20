#!/usr/bin/env bash
set -euo pipefail

DISPLAY_ID="${NOTEBOOKLM_VNC_DISPLAY:-:99}"
NOVNC_PORT="${NOTEBOOKLM_NOVNC_PORT:-1006}"
VNC_PORT="${NOTEBOOKLM_VNC_PORT:-5900}"

if ! command -v Xvfb >/dev/null 2>&1 || ! command -v x11vnc >/dev/null 2>&1 || ! command -v websockify >/dev/null 2>&1; then
  echo "Linux VNC login needs xvfb, x11vnc, openbox and websockify installed." >&2
  echo "Install them with your package manager, then rerun this script." >&2
  exit 1
fi

pgrep -f "Xvfb $DISPLAY_ID" >/dev/null 2>&1 || Xvfb "$DISPLAY_ID" -screen 0 1280x900x24 >/tmp/notebooklm-xvfb.log 2>&1 &
sleep 1
DISPLAY="$DISPLAY_ID" openbox >/tmp/notebooklm-openbox.log 2>&1 || true &
pgrep -f "x11vnc.*$DISPLAY_ID" >/dev/null 2>&1 || x11vnc -display "$DISPLAY_ID" -forever -shared -rfbport "$VNC_PORT" >/tmp/notebooklm-x11vnc.log 2>&1 &
pgrep -f "websockify.*$NOVNC_PORT" >/dev/null 2>&1 || websockify --web=/usr/share/novnc "$NOVNC_PORT" "localhost:$VNC_PORT" >/tmp/notebooklm-novnc.log 2>&1 &

echo "VNC_URL=http://localhost:$NOVNC_PORT/vnc.html"
echo "If this is a remote Linux machine, replace localhost with the machine address."
echo "Run this in another shell after opening VNC:"
echo "DISPLAY=$DISPLAY_ID notebooklm login"
