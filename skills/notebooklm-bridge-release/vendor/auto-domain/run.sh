#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-}"
NAME="${2:-}"

if [[ -z "$PORT" ]]; then
  echo "usage: run.sh <port> [name]" >&2
  exit 1
fi

ARGS="--port=$PORT --daemon"
if [[ -n "$NAME" ]]; then
  ARGS="$ARGS --name=$NAME"
fi

# token: env var > ~/.auto-domain/config
if [[ -z "${AUTO_DOMAIN_TOKEN:-}" && -f "$HOME/.auto-domain/config" ]]; then
  source "$HOME/.auto-domain/config" 2>/dev/null || true
fi
if [[ -n "${AUTO_DOMAIN_TOKEN:-}" ]]; then
  ARGS="$ARGS --token=$AUTO_DOMAIN_TOKEN"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/allocate-domain.sh" $ARGS
