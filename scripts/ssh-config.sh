#!/usr/bin/env bash
# 💻 LOCAL: write the Host block(s) to ~/.ssh/config:
#   - HOST_ALIAS  → logs in as cc (safe / read-only mode, the default)
#   - ADMIN_ALIAS → logs in as ADMIN_USER through the dedicated full-power credential by
#                   default. An explicit IdentitiesOnly=no can admit other credentials;
#                   fullpower status detects that effective access separately.
# This edits ~/.ssh/config — run it only AFTER the user authorizes it.
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
# shellcheck source=/dev/null
source "$PARAMS"
: "${FULLPOWER_AGENT_SOCKET:=$HOME/.config/luffy-arm/fullpower-agent.sock}"
mkdir -p ~/.ssh && chmod 700 ~/.ssh

add_block(){ # $1=alias $2=user $3=identity_for_ssh $4=multiplex(yes|no) $5=identity_agent(optional)
  local identity_agent="${5:-}"
  touch ~/.ssh/config && chmod 600 ~/.ssh/config
  if grep -qxF "Host $1" ~/.ssh/config; then
    echo "Host $1 already in ~/.ssh/config (connection fields left unchanged)"; return 0
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
  [[ -n "$identity_agent" ]] && echo "  IdentityAgent $identity_agent" >> ~/.ssh/config
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

set_identity_agent(){ # Update only the exact luffy-arm admin Host block, preserving everything else.
  local alias="$1" agent_socket="$2" tmp
  tmp="$(mktemp "$HOME/.ssh/config.luffy-arm.XXXXXX")"
  if awk -v target="Host $alias" -v agent="$agent_socket" '
    function finish_block() {
      if (inside && !wrote_agent) print "  IdentityAgent " agent
    }
    /^(Host|Match)[[:space:]]+/ {
      finish_block()
      inside = ($0 == target)
      if (inside) found = 1
      wrote_agent = 0
      print
      next
    }
    inside && $1 == "IdentityAgent" {
      if (!wrote_agent) print "  IdentityAgent " agent
      wrote_agent = 1
      next
    }
    { print }
    END {
      finish_block()
      if (!found) exit 42
    }
  ' ~/.ssh/config > "$tmp"; then
    chmod 600 "$tmp"
    mv "$tmp" ~/.ssh/config
    echo "Set IdentityAgent for Host $alias → $agent_socket"
  else
    rm -f "$tmp"
    echo "Could not update IdentityAgent for Host $alias" >&2
    return 1
  fi
}

# safe mode: cc's passphrase-less private key (always usable); multiplexed for cheap repeat calls
add_block "$HOST_ALIAS" "$CC_USER" "$KEY" yes ""

# full-power mode (opt-in): IdentityFile points at the PUBLIC key + IdentitiesOnly, so this
# dedicated credential is usable ONLY via ssh-agent. Until `fullpower.sh on` loads it, the
# dedicated gate is closed. This does not revoke other keys if a caller overrides the identity
# policy (for example with IdentitiesOnly=no), so status reports effective access separately.
if [[ -n "${ADMIN_ALIAS:-}" && -n "${ADMIN_KEY:-}" && -n "${ADMIN_USER:-}" ]]; then
  add_block "$ADMIN_ALIAS" "$ADMIN_USER" "$ADMIN_KEY.pub" no "$FULLPOWER_AGENT_SOCKET"
  set_identity_agent "$ADMIN_ALIAS" "$FULLPOWER_AGENT_SOCKET"
else
  echo "(ADMIN_* not set in params — skipping the full-power admin alias)"
fi
