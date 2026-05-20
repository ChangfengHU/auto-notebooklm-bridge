#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${NOTEBOOKLM_BRIDGE_HOME:-$HOME/.notebooklm-bridge}"
VENV_DIR="${NOTEBOOKLM_VENV_DIR:-$HOME/.venvs/notebooklm-py}"
ENV_FILE="$STATE_DIR/env"

mkdir -p "$STATE_DIR"

upsert_env() {
  local key="$1"
  local value="$2"
  touch "$ENV_FILE"
  if grep -q "^${key}=" "$ENV_FILE"; then
    awk -v key="$key" -v value="$value" '
      index($0, key "=") == 1 { print key "=" value; next }
      { print }
    ' "$ENV_FILE" > "$ENV_FILE.tmp"
    mv "$ENV_FILE.tmp" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

if [[ -x "$VENV_DIR/bin/notebooklm" ]]; then
  upsert_env "PATH" "$VENV_DIR/bin:\$PATH"
  upsert_env "NOTEBOOKLM_BIN" "$VENV_DIR/bin/notebooklm"
  exit 0
fi

if [[ -x "$VENV_DIR/Scripts/notebooklm.exe" ]]; then
  upsert_env "PATH" "$VENV_DIR/Scripts:\$PATH"
  upsert_env "NOTEBOOKLM_BIN" "$VENV_DIR/Scripts/notebooklm.exe"
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

DRY_RUN="$("$VENV_PY" -m playwright install --dry-run chromium 2>/dev/null || true)"
CHROMIUM_DIR="$(printf '%s\n' "$DRY_RUN" | awk '
  /Chrome for Testing/ { seen=1 }
  seen && /Install location:/ {
    sub(/^.*Install location:[[:space:]]*/, "")
    print
    exit
  }
')"

if [[ -n "$CHROMIUM_DIR" && ! -d "$CHROMIUM_DIR" ]]; then
  echo "Playwright Chromium is not installed." >&2
  echo "Normal 'notebooklm login' may fail until you run:" >&2
  echo "  $VENV_PY -m playwright install chromium" >&2
  echo "Deploy will continue because macOS/Windows can often login with Chrome cookies:" >&2
  echo "  notebooklm login --browser-cookies chrome" >&2
  printf '%s\n' "$DRY_RUN" > "$STATE_DIR/playwright-chromium-download.txt"
  echo "Download details were written to: $STATE_DIR/playwright-chromium-download.txt" >&2
fi

upsert_env "PATH" "$VENV_BIN:\$PATH"
upsert_env "NOTEBOOKLM_BIN" "$NOTEBOOKLM_BIN"

echo "NOTEBOOKLM_BIN=$NOTEBOOKLM_BIN"
