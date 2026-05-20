#!/usr/bin/env bash
set -euo pipefail

exec bash <(curl -fsSL https://skill.vyibc.com/auto-domain.sh) "$@"

