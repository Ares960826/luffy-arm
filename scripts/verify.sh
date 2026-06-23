#!/usr/bin/env bash
# 💻 LOCAL: end-to-end check of the channel + the safety nets (probes the server via ssh).
set -uo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there first."; exit 1; }
source "$PARAMS"
H="$HOST_ALIAS"
pass=0; fail=0
check(){ if eval "$2"; then echo "✅ $1"; pass=$((pass+1)); else echo "❌ $1"; fail=$((fail+1)); fi; }

# 1. Passwordless login + connection reuse (ControlMaster)
check "passwordless ssh login" "ssh $H true"
check "ControlMaster active" "ssh -O check $H 2>&1 | grep -q 'Master running'"

# 2. Read-only roots: readable, but writes are denied (Net 2: data read-only)
for d in "${READ_ROOTS[@]}"; do
  check "read-only root readable: $d" "ssh $H 'ls \"$d\" >/dev/null 2>&1'"
  check "read-only root write denied: $d" "! ssh $H 'touch \"$d/._luffyarm_probe\" 2>/dev/null'"
done

# 3. Writable work dirs (version control is per-project, not checked here)
for d in "${WORK_DIRS[@]}"; do
  check "work dir writable: $d" "ssh $H 'touch \"$d/._luffyarm_probe\" && rm -f \"$d/._luffyarm_probe\"'"
done

# 4. sudo password gate: non-interactive sudo must fail (Net 1)
check "sudo without password denied (gate)" "! ssh $H 'sudo -n true 2>/dev/null'"

# 5. Local brain: agent config stays local (INV-1) — any skills-aware agent counts
check "local brain present (agent config dir)" 'test -d "$HOME/.claude" || test -d "$HOME/.codex" || test -d "$HOME/.cursor" || test -d "$HOME/.config/opencode"'

echo "----"; echo "passed $pass / failed $fail"
[[ $fail -eq 0 ]] && echo "🎉 all passed" || { echo "see ❌ above; consult references/setup-guide.md"; exit 1; }
