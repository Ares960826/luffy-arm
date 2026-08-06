#!/usr/bin/env bash
# 💻 LOCAL: master switch for opt-in full-power mode. Loading the passphrase-protected admin
# key into ssh-agent = ON; removing it = OFF. While OFF the admin alias simply cannot
# authenticate, so the mode is genuinely closed (not just "discouraged").
# Usage: bash scripts/fullpower.sh [on [seconds] | off | status]
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
# shellcheck source=/dev/null
source "$PARAMS"
: "${ADMIN_KEY:?ADMIN_KEY not set in params — add the full-power vars (see scripts/params.example.sh).}"
: "${ADMIN_ALIAS:?ADMIN_ALIAS not set in params.}"
: "${ADMIN_USER:?ADMIN_USER not set in params.}"
: "${FULLPOWER_TTL:=3600}"
: "${FULLPOWER_AGENT_SOCKET:=$HOME/.config/luffy-arm/fullpower-agent.sock}"

fp() { ssh-keygen -lf "$ADMIN_KEY.pub" 2>/dev/null | awk '{print $2}'; }

agent_socket() {
  if [[ -S "$FULLPOWER_AGENT_SOCKET" ]]; then
    printf '%s\n' "$FULLPOWER_AGENT_SOCKET"
  elif [[ -n "${SSH_AUTH_SOCK:-}" && -S "$SSH_AUTH_SOCK" ]]; then
    printf '%s\n' "$SSH_AUTH_SOCK"
  else
    return 1
  fi
}

publish_agent_socket() {
  local source_socket="${SSH_AUTH_SOCK:-}" socket_dir
  [[ -n "$source_socket" && -S "$source_socket" ]] || {
    echo "❌ No usable SSH_AUTH_SOCK in this terminal." >&2
    return 1
  }
  socket_dir="$(dirname "$FULLPOWER_AGENT_SOCKET")"
  mkdir -p "$socket_dir"
  chmod 700 "$socket_dir"
  if [[ -e "$FULLPOWER_AGENT_SOCKET" && ! -L "$FULLPOWER_AGENT_SOCKET" ]]; then
    echo "❌ Refusing to replace non-symlink: $FULLPOWER_AGENT_SOCKET" >&2
    return 1
  fi
  ln -sfn "$source_socket" "$FULLPOWER_AGENT_SOCKET"
}

remove_agent_socket_link() {
  [[ -L "$FULLPOWER_AGENT_SOCKET" ]] && rm -f "$FULLPOWER_AGENT_SOCKET"
}

# Return 0 when the published/current agent has the key, 1 when the agent is reachable but does
# not, and 2 when no usable agent can be inspected.
agent_state() {
  local fingerprint listing rc socket
  AGENT_DETAIL=""
  fingerprint="$(fp)"
  if [[ -z "$fingerprint" ]]; then
    AGENT_DETAIL="admin public key is missing or unreadable: $ADMIN_KEY.pub"
    return 2
  fi
  if ! socket="$(agent_socket)"; then
    AGENT_DETAIL="no usable Full Power ssh-agent socket"
    return 2
  fi
  if listing="$(SSH_AUTH_SOCK="$socket" ssh-add -l 2>&1)"; then
    printf '%s\n' "$listing" | grep -Fq "$fingerprint" && return 0
    return 1
  else
    rc=$?
    [[ $rc -eq 1 ]] && return 1  # reachable agent, no identities
    AGENT_DETAIL="$listing"
    return 2
  fi
}

# Return 0 when the admin alias authenticates, 1 only for an explicit authentication denial,
# and 2 when transport/sandbox state prevents a trustworthy answer.
auth_probe() {
  local output
  local args=(-o BatchMode=yes -o ConnectTimeout=5)
  AUTH_DETAIL=""
  [[ -S "$FULLPOWER_AGENT_SOCKET" ]] && args+=(-o IdentityAgent="$FULLPOWER_AGENT_SOCKET")
  if output="$(ssh "${args[@]}" "$ADMIN_ALIAS" true 2>&1)"; then
    return 0
  else
    AUTH_DETAIL="$output"
    if printf '%s\n' "$output" | grep -Eqi \
      'Permission denied|Authentication failed|No supported authentication methods available'; then
      return 1
    fi
    return 2
  fi
}

admin_alias_uses_key() {
  local keyword identity rest
  while read -r keyword identity rest; do
    [[ "$keyword" == "identityfile" ]] || continue
    if [[ "${identity:0:1}" == "~" && "${identity:1:1}" == "/" ]]; then
      identity="$HOME/${identity:2}"
    fi
    [[ "$identity" == "$ADMIN_KEY" || "$identity" == "$ADMIN_KEY.pub" ]] && return 0
  done < <(ssh -G "$ADMIN_ALIAS" 2>/dev/null)
  return 1
}

admin_alias_uses_agent_socket() {
  local keyword configured rest
  while read -r keyword configured rest; do
    [[ "$keyword" == "identityagent" ]] || continue
    [[ "$configured" == "$FULLPOWER_AGENT_SOCKET" ]] && return 0
  done < <(ssh -G "$ADMIN_ALIAS" 2>/dev/null)
  return 1
}

case "${1:-status}" in
  on)
    [[ -f "$ADMIN_KEY" ]] || { echo "❌ Missing admin key $ADMIN_KEY — run first: bash scripts/admin-keygen.sh"; exit 1; }
    [[ -f "$ADMIN_KEY.pub" ]] || { echo "❌ Missing admin public key $ADMIN_KEY.pub — re-run: bash scripts/admin-keygen.sh"; exit 1; }
    admin_alias_uses_key || {
      echo "❌ SSH alias '$ADMIN_ALIAS' is not configured with $ADMIN_KEY (or $ADMIN_KEY.pub)."
      echo "   Run first: bash scripts/ssh-config.sh"
      exit 1
    }
    admin_alias_uses_agent_socket || {
      echo "❌ SSH alias '$ADMIN_ALIAS' is missing the shared Full Power IdentityAgent."
      echo "   Run first: bash scripts/ssh-config.sh"
      exit 1
    }
    ttl="${2:-$FULLPOWER_TTL}"
    if ! ssh-add -t "$ttl" "$ADMIN_KEY"; then
      echo "🟡 full-power was NOT enabled in this shell."
      echo "   Agent runtimes: retry with approved host execution. Human fallback: run in your login terminal:"
      echo "     bash scripts/fullpower.sh on $ttl"
      exit 1
    fi
    if ! publish_agent_socket; then
      ssh-add -d "$ADMIN_KEY" 2>/dev/null || true
      exit 1
    fi
    if ! auth_probe; then
      ssh-add -d "$ADMIN_KEY" 2>/dev/null || true
      remove_agent_socket_link
      echo "❌ Full Power key was loaded, but '$ADMIN_ALIAS' could not authenticate through the shared agent socket."
      [[ -n "$AUTH_DETAIL" ]] && echo "   ssh probe: $AUTH_DETAIL"
      exit 1
    fi
    echo "🟢 full-power ON (auto-off in ~${ttl}s)."
    echo "   Shared across conversations through $FULLPOWER_AGENT_SOCKET."
    echo "   The agent can now run 'ssh $ADMIN_ALIAS \"...\"' as $ADMIN_USER with FULL read/write."
    ;;
  off)
    if socket="$(agent_socket 2>/dev/null)"; then
      SSH_AUTH_SOCK="$socket" ssh-add -d "$ADMIN_KEY" 2>/dev/null || true
    fi
    ssh -O exit "$ADMIN_ALIAS" 2>/dev/null || true  # drop any leftover multiplexed connection (older configs)
    # trust but verify: the mode is only OFF if the alias really can't authenticate anymore
    if auth_probe; then
      echo "⚠️  '$ADMIN_ALIAS' STILL AUTHENTICATES — the admin key is loaded in another ssh-agent"
      echo "    (tmux/forwarded agent?), or a cached master connection survived (old ~/.ssh/config"
      echo "    block with multiplexing — re-run scripts/ssh-config.sh on a fresh alias to fix)."
      echo "    Close it: run 'ssh-add -d $ADMIN_KEY' in the shell that ran 'on', then 'ssh -O exit $ADMIN_ALIAS'."
      exit 1
    else
      probe_rc=$?
      if [[ $probe_rc -eq 1 ]]; then
        echo "🔴 full-power OFF — verified: 'ssh $ADMIN_ALIAS' no longer authenticates; back to read-only cc mode."
      else
        echo "🟡 full-power state UNKNOWN — the admin alias could not be tested from this environment."
        [[ -n "$AUTH_DETAIL" ]] && echo "    ssh probe: $AUTH_DETAIL"
        echo "    Agent: retry with approved host execution. Human fallback (require verified OFF):"
        echo "      bash scripts/fullpower.sh off"
        exit 3
      fi
    fi
    ;;
  status)
    if auth_probe; then
      echo "🟢 ON  — $ADMIN_ALIAS available ($ADMIN_USER, full read/write across conversations)"
    else
      probe_rc=$?
      if agent_state; then
        agent_rc=0
      else
        agent_rc=$?
      fi
      if [[ $probe_rc -eq 1 ]]; then
        echo "🔴 OFF — verified authentication denial; safe mode only ($HOST_ALIAS: cc read-only + WORK_DIRS writable)"
      else
        echo "🟡 UNKNOWN — this environment cannot prove whether full-power is ON or OFF."
        [[ $agent_rc -eq 2 && -n "$AGENT_DETAIL" ]] && echo "    ssh-agent: $AGENT_DETAIL"
        [[ -n "$AUTH_DETAIL" ]] && echo "    ssh probe: $AUTH_DETAIL"
        echo "    Do not treat UNKNOWN as OFF. Agent: retry with approved host execution."
        echo "    Human fallback — check from your normal login terminal:"
        echo "      bash scripts/fullpower.sh status"
        exit 3
      fi
    fi
    ;;
  *)
    echo "Usage: bash scripts/fullpower.sh [on [seconds] | off | status]"; exit 1
    ;;
esac
