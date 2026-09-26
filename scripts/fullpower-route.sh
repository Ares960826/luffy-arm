#!/usr/bin/env bash
# Compatibility entry; one parser now handles both authentication modes.
set -euo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/power.py" "$@"
