#!/usr/bin/env bash
# 💻 LOCAL: generate a self-contained, idempotent SERVER script that turns OPTIONAL command
# auditing on/off for the agent's `cc` account. The agent runs THIS locally (no secrets); YOU
# run the emitted script on the server, as your own sudo-capable account.
#
# What it audits: every `ssh <alias> "<cmd>"` the agent sends lands as $SSH_ORIGINAL_COMMAND on
# the server. A tiny sshd ForceCommand wrapper (scoped to `Match User cc`) logs that string via
# `logger` → the system journal, then execs it transparently. The journal is root-owned, so the
# unprivileged `cc` account cannot erase its own trail. This closes the "ssh command string is
# invisible to the local machine" blind spot — from the SERVER side, the only place it can live.
#
# Honest limits (see references/audit-logging.md): it is DETECT, not PREVENT (the four safety
# nets still do the preventing); it records the command string, not every sub-process; and `cc`
# can add noise via its own `logger` but cannot delete real entries. It only touches the safe-
# mode `cc` account — full-power (you log in as yourself) is never intercepted.
#
# Opt-in: nothing here runs until YOU run the emitted script with an explicit `enable`.
#
# Usage: bash scripts/gen-audit-setup.sh [output-file]   (default: ./luffy-arm-audit-setup.sh)
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in." >&2; exit 1; }
# shellcheck source=/dev/null
source "$PARAMS"
: "${CC_USER:?CC_USER not set in params}"

OUT="${1:-./luffy-arm-audit-setup.sh}"

# POSIX-safe single-quote escaping, so a username with metacharacters survives verbatim
sq(){ printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

: >"$OUT"
{
  echo '#!/usr/bin/env bash'
  echo '# luffy-arm — OPTIONAL command auditing for the cc account (AUTO-GENERATED; re-generate,'
  echo '# do not hand-edit). Run ON THE SERVER, as your OWN sudo-capable account:'
  echo '#     bash luffy-arm-audit-setup.sh enable      # turn auditing ON'
  echo '#     bash luffy-arm-audit-setup.sh disable     # turn it back OFF (full clean removal)'
  echo '#     bash luffy-arm-audit-setup.sh status      # is it on? is sshd config valid?'
  echo '#     bash luffy-arm-audit-setup.sh show [N]    # last N audited commands (default 50)'
  echo '# It calls sudo internally only where needed — YOU type the password (INV-3). Idempotent.'
  echo 'set -euo pipefail'
} >>"$OUT"
printf 'CC_USER=%s\n' "$(sq "$CC_USER")" >>"$OUT"

# Fixed logic (quoted heredoc → no local expansion; runs against the inlined CC_USER above)
cat >>"$OUT" <<'AUDITLOGIC'

TAG='luffy-arm-cc'
WRAPPER='/usr/local/bin/luffy-arm-audit-shell'
SSHD='/etc/ssh/sshd_config'
BEGIN='# >>> luffy-arm-audit >>>'
END='# <<< luffy-arm-audit <<<'

say(){ printf '\n==> %s\n' "$1"; }

reload_sshd(){
  # validate BEFORE reloading so a bad edit can never lock you out
  if ! sudo sshd -t; then
    echo "❌ sshd config test failed — NOT reloading. Fix the error above." >&2
    return 1
  fi
  sudo systemctl reload ssh 2>/dev/null \
    || sudo systemctl reload sshd 2>/dev/null \
    || sudo service ssh reload 2>/dev/null \
    || sudo service sshd reload 2>/dev/null \
    || { echo "⚠ could not reload sshd automatically — reload it yourself so the change takes effect." >&2; return 0; }
}

is_enabled(){ # sshd_config is normally world-readable → no sudo needed; fall back to sudo if not
  grep -qsF "$BEGIN" "$SSHD" 2>/dev/null || sudo -n grep -qF "$BEGIN" "$SSHD" 2>/dev/null
}

install_wrapper(){
  # A ForceCommand shell: log the incoming command to the journal, then run it transparently.
  # journald is root-owned → cc cannot erase what lands here. POSIX sh; safe for scp/rsync
  # (they arrive as $SSH_ORIGINAL_COMMAND and are exec'd normally).
  sudo tee "$WRAPPER" >/dev/null <<'WRAP'
#!/bin/sh
# luffy-arm audit shell (AUTO-GENERATED). Logs the agent's command, then runs it.
from=${SSH_CONNECTION%% *}
logger -t luffy-arm-cc -- "from=${from:-?} user=$(id -un) cmd=${SSH_ORIGINAL_COMMAND:-<interactive-login>}"
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
  exec "${SHELL:-/bin/bash}" -c "$SSH_ORIGINAL_COMMAND"
else
  exec "${SHELL:-/bin/bash}" -l
fi
WRAP
  sudo chown root:root "$WRAPPER"
  sudo chmod 755 "$WRAPPER"
}

enable(){
  id "$CC_USER" >/dev/null 2>&1 || { echo "❌ account '$CC_USER' does not exist — run luffy-arm-server-setup.sh first." >&2; exit 1; }
  say "install audit wrapper → $WRAPPER"
  install_wrapper
  if is_enabled; then
    echo "   sshd block already present — refreshed wrapper only."
  else
    say "enable ForceCommand for $CC_USER (appended at end of $SSHD)"
    sudo cp -n "$SSHD" "$SSHD.luffy-arm.bak" 2>/dev/null || true   # one-time backup
    # Append at END so the Match block cannot bleed into unrelated config above it.
    printf '%s\nMatch User %s\n    ForceCommand %s\n%s\n' "$BEGIN" "$CC_USER" "$WRAPPER" "$END" \
      | sudo tee -a "$SSHD" >/dev/null
  fi
  reload_sshd
  printf '\n✅ auditing ON. Every command the agent runs as %s is now logged.\n' "$CC_USER"
  printf '   Read it with:  bash %s show\n' "$(basename "$0")"
}

disable(){
  local changed=0
  if is_enabled; then
    say "remove ForceCommand block from $SSHD"
    # delete the marked block in place (portable sed range delete)
    sudo sed -i "\|$BEGIN|,\|$END|d" "$SSHD"
    changed=1
  else
    echo "   sshd block not present — nothing to remove."
  fi
  if [[ -e "$WRAPPER" ]]; then
    say "remove wrapper $WRAPPER"
    sudo rm -f "$WRAPPER"
    changed=1
  fi
  [[ "$changed" -eq 1 ]] && reload_sshd
  printf '\n✅ auditing OFF. (Past log entries stay in the journal — history is not erased.)\n'
}

status(){
  if is_enabled && [[ -e "$WRAPPER" ]]; then
    echo "audit: ON  (ForceCommand → $WRAPPER, Match User $CC_USER)"
  elif is_enabled || [[ -e "$WRAPPER" ]]; then
    echo "audit: PARTIAL — run 'enable' or 'disable' to make it consistent."
  else
    echo "audit: OFF"
  fi
  # distinguish "config is invalid" from "we couldn't check because we have no sudo here".
  # The assignment lives in an `if` condition so `set -e` won't abort on a failing sudo.
  local out
  if out="$(sudo -n sshd -t 2>&1)"; then
    echo "sshd config: valid"
  elif printf '%s' "$out" | grep -qiE 'password|askpass|terminal is required|not allowed'; then
    echo "sshd config: (not checked — run 'status' as a sudo-capable account)"
  else
    echo "sshd config: INVALID — do not reload until fixed:"; printf '  %s\n' "$out"
  fi
}

show(){
  local n="${1:-50}"
  # every luffy-arm-cc entry is produced BY cc, so cc can read its own trail without sudo;
  # a sudo-capable reader also sees it. Try unprivileged first, then sudo, then raw syslog.
  journalctl -q -t "$TAG" -n "$n" --no-pager 2>/dev/null | grep -q . && { journalctl -q -t "$TAG" -n "$n" --no-pager; return 0; }
  sudo -n journalctl -q -t "$TAG" -n "$n" --no-pager 2>/dev/null | grep -q . && { sudo journalctl -q -t "$TAG" -n "$n" --no-pager; return 0; }
  for f in /var/log/syslog /var/log/messages; do
    [[ -r "$f" ]] && { grep -F "$TAG" "$f" | tail -n "$n"; return 0; }
  done
  echo "no audit entries visible yet (none logged, or need a sudo-capable account to read them)." >&2
}

case "${1:-status}" in
  enable)  enable ;;
  disable) disable ;;
  status)  status ;;
  show)    show "${2:-}" ;;
  *) echo "usage: bash $(basename "$0") enable|disable|status|show [N]" >&2; exit 2 ;;
esac
AUDITLOGIC

chmod +x "$OUT"
echo "✅ wrote $OUT"
echo
echo "This is OPT-IN — nothing changes on the server until you run it with 'enable'."
echo "Copy it to the server and run there as your own account (it uses sudo internally):"
echo "    scp $OUT ${ADMIN_USER:-<you>}@${SERVER:-<server>}:~/"
echo "    ssh ${ADMIN_USER:-<you>}@${SERVER:-<server>}    # then, on the server:"
echo "    bash luffy-arm-audit-setup.sh enable      # turn auditing on"
echo "    bash luffy-arm-audit-setup.sh show        # read what the agent has run"
echo "    bash luffy-arm-audit-setup.sh disable     # turn it fully back off"
exit 0
