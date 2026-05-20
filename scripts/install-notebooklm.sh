#!/usr/bin/env bash
set -euo pipefail

if command -v notebooklm >/dev/null 2>&1; then
  notebooklm --version >/dev/null 2>&1 || true
  exit 0
fi

PYTHON="${PYTHON:-python3}"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

"$PYTHON" -m pip install --user -U notebooklm-py

if ! command -v notebooklm >/dev/null 2>&1; then
  echo "notebooklm was installed, but it is not on PATH. Add ~/.local/bin to PATH." >&2
  exit 1
fi

