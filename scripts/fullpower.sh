#!/usr/bin/env bash
# 💻 LOCAL: master switch for the dedicated, passphrase-gated full-power credential.
# Loading that key into ssh-agent = dedicated gate ON; removing it = dedicated gate OFF.
# Other SSH credentials may still authenticate as ADMIN_USER, so gate state and effective
# user capability are reported separately.
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

# Probe a fresh, non-interactive public-key login and return 0 only when it reaches ADMIN_USER.
# $1=yes tests the configured dedicated gate. $1=no deliberately admits other agent keys so
# status can detect the exact alternate-credential path that the dedicated gate does not control.
# Return 1 only for explicit authentication denial and 2 for transport errors or identity mismatch.
identity_probe() {
  local identities_only="$1" output identity socket
  local args=(
    -o BatchMode=yes
    -o ConnectTimeout=5
    -o ConnectionAttempts=1
    -o ControlMaster=no
    -o ControlPath=none
    -o IdentitiesOnly="$identities_only"
    -o PreferredAuthentications=publickey
    -o PasswordAuthentication=no
    -o KbdInteractiveAuthentication=no
    -o NumberOfPasswordPrompts=0
  )
  PROBE_DETAIL=""; PROBE_IDENTITY=""
  if socket="$(agent_socket 2>/dev/null)"; then
    args+=(-o IdentityAgent="$socket")
  fi
  if output="$(ssh "${args[@]}" "$ADMIN_ALIAS" 'id -un' 2>&1)"; then
    identity="$(printf '%s\n' "$output" | awk 'NF { line=$0 } END { print line }')"
    PROBE_IDENTITY="$identity"
    if [[ "$identity" == "$ADMIN_USER" ]]; then
      return 0
    fi
    PROBE_DETAIL="authenticated as '$identity', expected ADMIN_USER '$ADMIN_USER'"
    return 2
  fi

  PROBE_DETAIL="$output"
  if printf '%s\n' "$output" | grep -Eqi \
    'Permission denied|Authentication failed|No supported authentication methods available'; then
    return 1
  fi
  return 2
}

auth_probe() {
  if identity_probe yes; then
    AUTH_IDENTITY="$PROBE_IDENTITY"; AUTH_DETAIL=""; return 0
  else
    local rc=$?
    AUTH_IDENTITY="$PROBE_IDENTITY"; AUTH_DETAIL="$PROBE_DETAIL"; return "$rc"
  fi
}

effective_access_probe() {
  if identity_probe no; then
    EFFECTIVE_IDENTITY="$PROBE_IDENTITY"; EFFECTIVE_DETAIL=""; return 0
  else
    local rc=$?
    EFFECTIVE_IDENTITY="$PROBE_IDENTITY"; EFFECTIVE_DETAIL="$PROBE_DETAIL"; return "$rc"
  fi
}

report_effective_access() {
  if effective_access_probe; then
    echo "⚠️  EFFECTIVE USER ACCESS: AVAILABLE — another SSH credential authenticates as $EFFECTIVE_IDENTITY with IdentitiesOnly=no."
    echo "    Dedicated gate OFF does not remove this capability or reduce it to Safe Mode."
    echo "    Permissions are those of remote user $EFFECTIVE_IDENTITY; verify each target path and sudo separately."
    return 0
  else
    local rc=$?
    if [[ $rc -eq 1 ]]; then
      echo "🔒 EFFECTIVE USER ACCESS: NOT FOUND — the alternate non-interactive public-key probe was denied."
      echo "    The configured luffy-arm path is limited to $HOST_ALIAS ($CC_USER; READ_ROOTS read-only, WORK_DIRS writable)."
      return 1
    fi
    echo "🟡 EFFECTIVE USER ACCESS: UNKNOWN — alternate credentials or remote identity could not be verified."
    [[ -n "$EFFECTIVE_DETAIL" ]] && echo "    alternate probe: $EFFECTIVE_DETAIL"
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
    echo "🟢 DEDICATED GATE: ON (auto-off in ~${ttl}s)."
    echo "   Shared across conversations through $FULLPOWER_AGENT_SOCKET."
    echo "   REMOTE IDENTITY: $AUTH_IDENTITY via the dedicated luffy-arm-admin credential."
    echo "   EFFECTIVE PERMISSIONS: those of $ADMIN_USER; verify target-path write and sudo separately."
    ;;
  off)
    if socket="$(agent_socket 2>/dev/null)"; then
      SSH_AUTH_SOCK="$socket" ssh-add -d "$ADMIN_KEY" 2>/dev/null || true
    fi
    ssh -O exit "$ADMIN_ALIAS" 2>/dev/null || true  # drop any leftover multiplexed connection (older configs)
    # Verify the dedicated credential separately from any alternate key that reaches ADMIN_USER.
    if auth_probe; then
      echo "⚠️  DEDICATED GATE STILL ON — $ADMIN_ALIAS authenticates as $AUTH_IDENTITY with IdentitiesOnly=yes."
      echo "    The admin key may be loaded in another ssh-agent (tmux/forwarded agent), or a cached"
      echo "    master connection may have survived an older SSH configuration."
      echo "    Close it: run 'ssh-add -d $ADMIN_KEY' in the shell that ran 'on', then 'ssh -O exit $ADMIN_ALIAS'."
      exit 1
    else
      probe_rc=$?
      if [[ $probe_rc -eq 1 ]]; then
        echo "🔴 DEDICATED GATE: OFF — the luffy-arm-admin credential was explicitly denied."
        if report_effective_access; then
          echo "    OFF removed the dedicated credential only; personal/other SSH keys are outside this switch."
          exit 4
        else
          effective_rc=$?
          [[ $effective_rc -eq 1 ]] && exit 0
          exit 3
        fi
      else
        echo "🟡 DEDICATED GATE: UNKNOWN — the admin credential could not be tested from this environment."
        [[ -n "$AUTH_DETAIL" ]] && echo "    ssh probe: $AUTH_DETAIL"
        echo "    Agent: retry with approved host execution. Human fallback (require verified OFF):"
        echo "      bash scripts/fullpower.sh off"
        exit 3
      fi
    fi
    ;;
  status)
    if auth_probe; then
      echo "🟢 DEDICATED GATE: ON — luffy-arm-admin authenticates through $ADMIN_ALIAS."
      echo "   REMOTE IDENTITY: $AUTH_IDENTITY."
      echo "   EFFECTIVE PERMISSIONS: those of $AUTH_IDENTITY; verify target-path write and sudo separately."
    else
      probe_rc=$?
      if agent_state; then
        agent_rc=0
      else
        agent_rc=$?
      fi
      if [[ $probe_rc -eq 1 ]]; then
        echo "🔴 DEDICATED GATE: OFF — luffy-arm-admin was explicitly denied."
        if report_effective_access; then
          : # Layered state is complete: gate OFF, effective ADMIN_USER access still available.
        else
          effective_rc=$?
          if [[ $effective_rc -eq 2 ]]; then
            exit 3
          fi
        fi
      else
        echo "🟡 DEDICATED GATE: UNKNOWN — this environment cannot prove its state."
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
