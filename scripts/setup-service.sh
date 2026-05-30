#!/usr/bin/env bash
# auto-notebooklm-bridge Systemd Service Setup
# Usage: sudo ./scripts/setup-service.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE_NAME="notebooklm-bridge"
USER_NAME="$(whoami)"

# Determine the start command
# We use the existing start-bridge.sh and start-domain.sh
# But for a service, it's better to run them in foreground or manage them directly.

SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Creating systemd service: ${SERVICE_NAME}..."

cat <<EOF | sudo tee "$SERVICE_FILE" > /dev/null
[Unit]
Description=Auto NotebookLM Bridge Service
After=network.target

[Service]
Type=simple
User=${USER_NAME}
WorkingDirectory=${ROOT_DIR}
# Start both bridge and tunnel
ExecStart=/usr/bin/bash -c "${ROOT_DIR}/bridge/start.sh & ${ROOT_DIR}/scripts/start-domain.sh --foreground"
Restart=on-failure
RestartSec=10
StandardOutput=append:${HOME}/.notebooklm-bridge/service.log
StandardError=append:${HOME}/.notebooklm-bridge/service.log

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl start "${SERVICE_NAME}"

echo "✅ Service ${SERVICE_NAME} installed and started."
echo "   Status : systemctl status ${SERVICE_NAME}"
echo "   Logs   : tail -f ${HOME}/.notebooklm-bridge/service.log"
