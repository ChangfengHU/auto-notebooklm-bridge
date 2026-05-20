#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-}"
NAME="${2:-}"

if [[ -z "$PORT" ]]; then
  echo "usage: run.sh <port> [name]" >&2
  exit 1
fi

ARGS="--port=$PORT"
if [[ -n "$NAME" ]]; then
  ARGS="$ARGS --name=$NAME"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/allocate-domain.sh" $ARGS

