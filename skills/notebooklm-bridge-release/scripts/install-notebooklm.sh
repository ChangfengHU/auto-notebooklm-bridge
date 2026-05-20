#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
VENV_DIR="${NOTEBOOKLM_VENV_DIR:-$HOME/.venvs/notebooklm-py}"
ENV_FILE="$STATE_DIR/env"

mkdir -p "$STATE_DIR"

if [[ -x "$VENV_DIR/bin/notebooklm" ]]; then
  echo "PATH=$VENV_DIR/bin:\$PATH" > "$ENV_FILE"
  echo "NOTEBOOKLM_BIN=$VENV_DIR/bin/notebooklm" >> "$ENV_FILE"
  exit 0
fi

if [[ -x "$VENV_DIR/Scripts/notebooklm.exe" ]]; then
  echo "PATH=$VENV_DIR/Scripts:\$PATH" > "$ENV_FILE"
  echo "NOTEBOOKLM_BIN=$VENV_DIR/Scripts/notebooklm.exe" >> "$ENV_FILE"
  exit 0
fi

find_python() {
  for candidate in python3.12 python3.11 python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      "$candidate" - <<'PY' >/dev/null 2>&1 && { echo "$candidate"; return 0; }
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
    fi
  done
  if command -v py >/dev/null 2>&1; then
    py -3.12 - <<'PY' >/dev/null 2>&1 && { echo "py -3.12"; return 0; }
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
  fi
  return 1
}

PYTHON_CMD="$(find_python || true)"
if [[ -z "$PYTHON_CMD" ]]; then
  echo "Python >= 3.11 is required. Install Python 3.12, then rerun deploy." >&2
  exit 1
fi

# shellcheck disable=SC2086
$PYTHON_CMD -m venv "$VENV_DIR"

if [[ -x "$VENV_DIR/bin/python" ]]; then
  VENV_PY="$VENV_DIR/bin/python"
  VENV_BIN="$VENV_DIR/bin"
  NOTEBOOKLM_BIN="$VENV_DIR/bin/notebooklm"
else
  VENV_PY="$VENV_DIR/Scripts/python.exe"
  VENV_BIN="$VENV_DIR/Scripts"
  NOTEBOOKLM_BIN="$VENV_DIR/Scripts/notebooklm.exe"
fi

"$VENV_PY" -m pip install -U pip
"$VENV_PY" -m pip install "notebooklm-py==0.4.1"

{
  echo "PATH=$VENV_BIN:\$PATH"
  echo "NOTEBOOKLM_BIN=$NOTEBOOKLM_BIN"
} > "$ENV_FILE"

echo "NOTEBOOKLM_BIN=$NOTEBOOKLM_BIN"
