#!/usr/bin/env bash
# 💻 LOCAL: append one Host block to ~/.ssh/config so you can `ssh $HOST_ALIAS`.
# (v1 = safe / read-only mode only. The full-power admin alias arrives in a later version.)
# This edits ~/.ssh/config — run it only AFTER the user authorizes it.
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
source "$PARAMS"
mkdir -p ~/.ssh && chmod 700 ~/.ssh

if grep -qE "^Host[[:space:]]+$HOST_ALIAS\$" ~/.ssh/config 2>/dev/null; then
  echo "Host $HOST_ALIAS already in ~/.ssh/config (skipping)"
else
  cat >> ~/.ssh/config <<EOF

Host $HOST_ALIAS
  HostName $SERVER
  Port $SSH_PORT
  User $CC_USER
  IdentityFile $KEY
  IdentitiesOnly yes
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
EOF
  echo "Appended Host $HOST_ALIAS (User $CC_USER) to ~/.ssh/config"
fi
