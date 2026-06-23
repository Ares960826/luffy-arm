#!/usr/bin/env bash
# 💻 LOCAL: master switch for opt-in full-power mode. Loading the passphrase-protected admin
# key into ssh-agent = ON; removing it = OFF. While OFF the admin alias simply cannot
# authenticate, so the mode is genuinely closed (not just "discouraged").
# Usage: bash scripts/fullpower.sh [on [seconds] | off | status]
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
source "$PARAMS"
: "${ADMIN_KEY:?ADMIN_KEY not set in params — add the full-power vars (see scripts/params.example.sh).}"
: "${ADMIN_ALIAS:?ADMIN_ALIAS not set in params.}"
: "${ADMIN_USER:?ADMIN_USER not set in params.}"
: "${FULLPOWER_TTL:=3600}"

fp()     { ssh-keygen -lf "$ADMIN_KEY.pub" 2>/dev/null | awk '{print $2}'; }
loaded() { [[ -n "$(fp)" ]] && ssh-add -l 2>/dev/null | grep -q "$(fp)"; }

case "${1:-status}" in
  on)
    [[ -f "$ADMIN_KEY" ]] || { echo "❌ Missing admin key $ADMIN_KEY — run first: bash scripts/admin-keygen.sh"; exit 1; }
    ttl="${2:-$FULLPOWER_TTL}"
    ssh-add -t "$ttl" "$ADMIN_KEY"   # prompts for the key passphrase; -t auto-removes it after TTL
    echo "🟢 full-power ON (auto-off in ~${ttl}s)."
    echo "   The agent can now run 'ssh $ADMIN_ALIAS \"...\"' as $ADMIN_USER with FULL read/write."
    ;;
  off)
    ssh-add -d "$ADMIN_KEY" 2>/dev/null || true     # remove the key from the agent
    ssh -O exit "$ADMIN_ALIAS" 2>/dev/null || true  # drop any live multiplexed connection → effective immediately
    echo "🔴 full-power OFF. 'ssh $ADMIN_ALIAS' can no longer authenticate; back to read-only cc mode."
    ;;
  status)
    if loaded; then
      echo "🟢 ON  — $ADMIN_ALIAS available ($ADMIN_USER, full read/write)"
    else
      echo "🔴 OFF — safe mode only ($HOST_ALIAS: cc read-only + WORK_DIRS writable)"
    fi
    ;;
  *)
    echo "Usage: bash scripts/fullpower.sh [on [seconds] | off | status]"; exit 1
    ;;
esac
