#!/usr/bin/env bash
# 💻 LOCAL: end-to-end self-check for opt-in full-power mode.
# Prereq: run `bash scripts/fullpower.sh on` first (asks for the admin passphrase — INV-3).
# Verifies: the admin alias logs in as ADMIN_USER and can WRITE a read-only root (full r/w),
# while at the SAME time the safe alias is still cc + read-only (dual-identity isolation).
set -uo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
source "$PARAMS"
: "${ADMIN_KEY:?ADMIN_KEY not set in params — add the full-power vars (see scripts/params.example.sh).}"
H="$HOST_ALIAS"; A="$ADMIN_ALIAS"
pass=0; fail=0
ok(){ echo "✅ $1"; pass=$((pass+1)); }
no(){ echo "❌ $1"; fail=$((fail+1)); }

# 0. full-power MUST be ON (admin key in ssh-agent), else this test is meaningless
fp(){ ssh-keygen -lf "$ADMIN_KEY.pub" 2>/dev/null | awk '{print $2}'; }
if ! { [[ -n "$(fp)" ]] && ssh-add -l 2>/dev/null | grep -q "$(fp)"; }; then
  echo "⚠️  full-power is currently OFF — this self-check needs it ON."
  echo "    Run first (asks for the admin passphrase):  bash scripts/fullpower.sh on"
  echo "    Then re-run:                                 bash scripts/verify-fullpower.sh"
  exit 2
fi

RR="${READ_ROOTS[0]}"                 # first read-only root, used as the "writable under full-power" probe
S="-o BatchMode=yes -o ConnectTimeout=10"

# 1. admin alias identity == ADMIN_USER
who_admin=$(ssh $S "$A" whoami 2>/dev/null)
[ "$who_admin" = "$ADMIN_USER" ] && ok "admin alias logs in as $ADMIN_USER" \
                                  || no "admin alias identity=[$who_admin] (expected $ADMIN_USER)"

# 2. full-power write: a read-only root (denied for cc) is now writable (and cleaned up)
if ssh $S "$A" "touch '$RR/._fpverify_$$' && rm -f '$RR/._fpverify_$$'" 2>/dev/null; then
  ok "full-power can write read-only root $RR"
else
  no "full-power write to $RR failed (likely: admin pubkey not in $ADMIN_USER's authorized_keys)"
fi

# 3. isolation: the safe alias is still cc right now
who_safe=$(ssh $S "$H" whoami 2>/dev/null)
[ "$who_safe" = "$CC_USER" ] && ok "safe alias is still $CC_USER" \
                              || no "safe alias identity=[$who_safe] (expected $CC_USER)"

# 4. isolation: cc is still denied write to the read-only root
if ssh $S "$H" "touch '$RR/._ccverify_$$'" 2>/dev/null; then
  no "$CC_USER could write $RR (should not!)"; ssh $S "$H" "rm -f '$RR/._ccverify_$$'" 2>/dev/null
else
  ok "$CC_USER still denied write to $RR (read-only isolation holds)"
fi

echo "----"; echo "passed $pass / failed $fail"
if [[ $fail -eq 0 ]]; then
  echo "🎉 full-power self-check passed. When done: bash scripts/fullpower.sh off"
else
  echo "see ❌ above. Most common cause: admin pubkey not in $ADMIN_USER's ~/.ssh/authorized_keys (references/server-setup.md)."
  exit 1
fi
