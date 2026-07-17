#!/usr/bin/env bash
# 💻 LOCAL: write the Host block(s) to ~/.ssh/config:
#   - HOST_ALIAS  → logs in as cc (safe / read-only mode, the default)
#   - ADMIN_ALIAS → logs in as ADMIN_USER (opt-in full-power; only authenticates while
#                   fullpower.sh has loaded the admin key into ssh-agent). Added only if set.
# This edits ~/.ssh/config — run it only AFTER the user authorizes it.
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
# shellcheck source=/dev/null
source "$PARAMS"
mkdir -p ~/.ssh && chmod 700 ~/.ssh

add_block(){ # $1=alias $2=user $3=identity_for_ssh $4=multiplex(yes|no)
  touch ~/.ssh/config && chmod 600 ~/.ssh/config
  if grep -qxF "Host $1" ~/.ssh/config; then
    echo "Host $1 already in ~/.ssh/config (skipping — existing block NOT updated; edit ~/.ssh/config yourself if SERVER/SSH_PORT changed)"; return 0
  fi
  cat >> ~/.ssh/config <<EOF

Host $1
  HostName $SERVER
  Port $SSH_PORT
  User $2
  IdentityFile $3
  IdentitiesOnly yes
  StrictHostKeyChecking accept-new
EOF
  if [[ "$4" == yes ]]; then
    cat >> ~/.ssh/config <<'EOF'
  ControlMaster auto
  ControlPath ~/.ssh/cm-%r@%h:%p
  ControlPersist 10m
EOF
  else
    # full-power alias: NO multiplexing — a cached master connection never re-authenticates,
    # so it would let admin access outlive the ssh-agent TTL (defeats the auto-off).
    echo '  ControlMaster no' >> ~/.ssh/config
  fi
  echo "Appended Host $1 (User $2) to ~/.ssh/config"
}

# safe mode: cc's passphrase-less private key (always usable); multiplexed for cheap repeat calls
add_block "$HOST_ALIAS" "$CC_USER" "$KEY" yes

# full-power mode (opt-in): IdentityFile points at the PUBLIC key + IdentitiesOnly, so the key
# is usable ONLY via ssh-agent. Until `fullpower.sh on` loads it, the agent doesn't have it →
# auth fails outright = the mode is closed by default (and no hanging passphrase prompt).
if [[ -n "${ADMIN_ALIAS:-}" && -n "${ADMIN_KEY:-}" && -n "${ADMIN_USER:-}" ]]; then
  add_block "$ADMIN_ALIAS" "$ADMIN_USER" "$ADMIN_KEY.pub" no
else
  echo "(ADMIN_* not set in params — skipping the full-power admin alias)"
fi
