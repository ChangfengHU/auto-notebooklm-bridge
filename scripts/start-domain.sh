#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
PORT="${NOTEBOOKLM_BRIDGE_PORT:-18800}"
MACHINE_ID="$("$ROOT_DIR/scripts/machine-id.sh")"
DOMAIN_NAME="${NOTEBOOKLM_DOMAIN_NAME:-notebooklm-bridge-${MACHINE_ID}}"
DOMAIN_LOG="$STATE_DIR/domain.log"
FOREGROUND=0

if [[ "${1:-}" == "--foreground" ]]; then
  FOREGROUND=1
fi

mkdir -p "$STATE_DIR"

# 停掉旧的 tunneling 进程
if command -v pkill >/dev/null 2>&1; then
  pkill -f ".tunneling/machine-agent" 2>/dev/null || true
  pkill -f "machine-agent" 2>/dev/null || true
fi
if command -v taskkill >/dev/null 2>&1; then
  taskkill //F //IM machine-agent.exe >/dev/null 2>&1 || true
fi

if [[ ! -x "$ROOT_DIR/vendor/auto-domain/run.sh" && -x "$HOME/.codex/skills/auto-domain/scripts/run.sh" ]]; then
  AUTO_DOMAIN="$HOME/.codex/skills/auto-domain/scripts/run.sh"
else
  AUTO_DOMAIN="$ROOT_DIR/vendor/auto-domain/run.sh"
fi

if [[ ! -x "$AUTO_DOMAIN" ]]; then
  echo "auto-domain skill is required. Install it before running release." >&2
  exit 1
fi

# 准备元数据：包含安装命令和健康检查命令
MACHINE_ID="$("$ROOT_DIR/scripts/machine-id.sh")"
TEST_CMD="curl -fsSL https://${DOMAIN_NAME}.chxyka.ccwu.cc/health"
INSTALL_CMD="bash <(curl -fsSL https://skill.vyibc.com/notebooklm-bridge/${MACHINE_ID}/release/install-notebooklm-bridge.sh)"

METADATA="{\"title\":\"NotebookLM Bridge\",\"install_command\":\"$INSTALL_CMD\",\"test_command\":\"$TEST_CMD\"}"

if [[ "$FOREGROUND" == "1" ]]; then
  "$AUTO_DOMAIN" "$PORT" "$DOMAIN_NAME" --metadata="$METADATA" | tee "$DOMAIN_LOG"
  exit 0
fi

# 后台守护模式：等待隧道上线并打印公网 URL
"$AUTO_DOMAIN" "$PORT" "$DOMAIN_NAME" --metadata="$METADATA" --daemon

