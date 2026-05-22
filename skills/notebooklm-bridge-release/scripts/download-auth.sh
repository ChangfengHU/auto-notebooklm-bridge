#!/usr/bin/env bash
# Downloads storage_state.json from R2 to the local notebooklm profile.
# Exits 0 on success, 1 on failure (no R2 file or invalid JSON).
set -euo pipefail

STORAGE_STATE="${NOTEBOOKLM_STORAGE_STATE:-$HOME/.notebooklm/profiles/default/storage_state.json}"
R2_URL="https://skill.vyibc.com/notebooklm/storage_state.json"

mkdir -p "$(dirname "$STORAGE_STATE")"

if ! curl -fsSL "${R2_URL}?v=$(date +%s)" -o "${STORAGE_STATE}.tmp" 2>/dev/null; then
  echo "[download-auth] No storage_state.json on R2 yet" >&2
  exit 1
fi

# Validate: must be JSON containing a 'cookies' key
if ! python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert 'cookies' in d and isinstance(d['cookies'], list) and len(d['cookies']) > 0
" "${STORAGE_STATE}.tmp" 2>/dev/null; then
  echo "[download-auth] Downloaded file is not a valid storage_state.json" >&2
  rm -f "${STORAGE_STATE}.tmp"
  exit 1
fi

mv "${STORAGE_STATE}.tmp" "$STORAGE_STATE"
echo "[download-auth] Restored storage_state.json from R2 → $STORAGE_STATE"
