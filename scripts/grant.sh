#!/usr/bin/env bash
# 💻 LOCAL: generate the SERVER commands to grant the agent read (ro) or write (rw) on a new dir.
# It only PRINTS the commands — it does NOT run them, because setfacl needs the server's sudo,
# which only YOU have (preserves INV-3). Copy the printed commands to the server and run them.
# Usage: bash grant.sh ro|rw /absolute/path
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS"; exit 1; }
source "$PARAMS"
mode="${1:-}"; dir="${2:-}"
if [[ ! "$mode" =~ ^(ro|rw)$ || -z "$dir" ]]; then
  echo "Usage: bash grant.sh ro|rw /absolute/path"
  echo "  ro = read-only (READ_ROOTS class)   rw = writable (WORK_DIRS class)"
  exit 1
fi
perm=$([[ "$mode" == ro ]] && echo "rX" || echo "rwX")

echo "# ===== 🖥 RUN ON THE SERVER (needs sudo; YOU run it, not the agent) ====="
echo "sudo setfacl -R  -m u:$CC_USER:$perm \"$dir\""
echo "sudo setfacl -R -d -m u:$CC_USER:$perm \"$dir\""
if [[ "$mode" == ro ]]; then
  echo "# carve out sensitive subdirs (keys/tokens):"
  for s in "${READ_EXCLUDES[@]}"; do
    echo "sudo setfacl -R -x u:$CC_USER \"$dir/$s\" 2>/dev/null; sudo setfacl -R -d -x u:$CC_USER \"$dir/$s\" 2>/dev/null"
  done
fi
echo "# ===== 💻 then append \"$dir\" to $([[ $mode == ro ]] && echo READ_ROOTS || echo WORK_DIRS) in your params.sh ====="
[[ "$mode" == rw ]] && echo "# (optional) version-control it per-project: ssh $HOST_ALIAS \"cd '$dir' && git init\""
