#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
for main in \
  "$HERE/../../luffy-arm/scripts/fullpower.sh" \
  "$HERE/../../../scripts/fullpower.sh"
do
  if [[ -f "$main" ]]; then
    exec bash "$main" on "$@"
  fi
done

echo "luffy-arm-fullpower-on: sibling luffy-arm/scripts/fullpower.sh not found" >&2
exit 1
