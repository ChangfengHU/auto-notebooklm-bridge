#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-}"
NAME="${2:-}"

if [[ -z "$PORT" ]]; then
  echo "usage: run.sh <port> [name] [extra flags...]" >&2
  exit 1
fi

ARGS="--port=$PORT"
if [[ -n "$NAME" ]]; then
  ARGS="$ARGS --name=$NAME"
fi

# 读取 token（环境变量 > 缓存文件）
if [[ -z "${AUTO_DOMAIN_TOKEN:-}" && -f "$HOME/.auto-domain/config" ]]; then
  source "$HOME/.auto-domain/config" 2>/dev/null || true
fi
if [[ -n "${AUTO_DOMAIN_TOKEN:-}" ]]; then
  ARGS="$ARGS --token=$AUTO_DOMAIN_TOKEN"
fi

# 透传额外参数（如 --daemon, --stop, --reset）
EXTRA="${@:3}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/allocate-domain.sh" $ARGS $EXTRA

