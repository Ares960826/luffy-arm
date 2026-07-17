#!/usr/bin/env bash
# 💻 LOCAL: generate a self-contained, idempotent SERVER-setup script with YOUR params and
# public key(s) already filled in. The agent runs THIS (all local, no secrets); you then run
# the emitted script ON THE SERVER, as your own sudo-capable account.
#
# Why a generated script (not the agent doing it): server setup needs sudo, and by design the
# agent never holds your password (INV-3). The emitted script calls `sudo` internally for the
# privileged parts — YOU type the password, once, on the server.
#
# Usage: bash scripts/gen-server-setup.sh [output-file]   (default: ./luffy-arm-server-setup.sh)
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in." >&2; exit 1; }
# shellcheck source=/dev/null
source "$PARAMS"
: "${CC_USER:?CC_USER not set in params}"
: "${KEY:?KEY not set in params}"
[[ -f "$KEY.pub" ]] || { echo "Missing $KEY.pub — run scripts/keygen.sh first." >&2; exit 1; }

CC_PUB="$(cat "$KEY.pub")"
ADMIN_PUB=""
if [[ -n "${ADMIN_KEY:-}" && -f "${ADMIN_KEY}.pub" ]]; then
  ADMIN_PUB="$(cat "${ADMIN_KEY}.pub")"   # only present if the user set up full-power locally
fi

OUT="${1:-./luffy-arm-server-setup.sh}"

# POSIX-safe single-quote escaping, so paths/keys with spaces or metacharacters survive verbatim
sq(){ printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
emit_array(){ # $1 = array name, rest = elements
  local name="$1"; shift
  printf '%s=(' "$name" >>"$OUT"
  local e; for e in "$@"; do printf ' %s' "$(sq "$e")" >>"$OUT"; done
  printf ' )\n' >>"$OUT"
}

: >"$OUT"
{
  echo '#!/usr/bin/env bash'
  echo '# luffy-arm — SERVER setup (AUTO-GENERATED; do not hand-edit — re-generate instead).'
  echo '# Run ON THE SERVER, as your OWN sudo-capable account:'
  echo '#     bash luffy-arm-server-setup.sh'
  echo '# NOT "sudo bash" — it calls sudo internally only where needed, and the optional'
  echo '# full-power step must land in YOUR home, not root'"'"'s. Idempotent: safe to re-run.'
  echo 'set -euo pipefail'
} >>"$OUT"
printf 'CC_USER=%s\n' "$(sq "$CC_USER")" >>"$OUT"
emit_array READ_ROOTS    ${READ_ROOTS[@]+"${READ_ROOTS[@]}"}
emit_array WORK_DIRS     ${WORK_DIRS[@]+"${WORK_DIRS[@]}"}
emit_array READ_EXCLUDES ${READ_EXCLUDES[@]+"${READ_EXCLUDES[@]}"}
printf 'CC_PUB=%s\n' "$(sq "$CC_PUB")" >>"$OUT"
printf 'ADMIN_PUB=%s\n' "$(sq "$ADMIN_PUB")" >>"$OUT"

# Fixed logic (quoted heredoc → no local expansion; runs against the inlined values above)
cat >>"$OUT" <<'SERVERLOGIC'

say(){ printf '\n==> %s\n' "$1"; }

# 1. dedicated non-privileged account -----------------------------------------
say "account: $CC_USER"
if id "$CC_USER" >/dev/null 2>&1; then
  echo "   exists — skipping creation"
else
  sudo adduser --disabled-password --gecos "" "$CC_USER"
fi
sudo deluser "$CC_USER" users 2>/dev/null || true   # leave the shared writable group → can't write your files
echo "   groups: $(id -nG "$CC_USER" 2>/dev/null)"

# 2. install the agent's public key (dedicated account → authorized_keys IS this one key) ------
say "install agent key for $CC_USER"
sudo install -d -m 700 -o "$CC_USER" -g "$CC_USER" "/home/$CC_USER/.ssh"
printf '%s\n' "$CC_PUB" | sudo tee "/home/$CC_USER/.ssh/authorized_keys" >/dev/null
sudo chown "$CC_USER:$CC_USER" "/home/$CC_USER/.ssh/authorized_keys"
sudo chmod 600 "/home/$CC_USER/.ssh/authorized_keys"

# 3. ensure setfacl is available ----------------------------------------------
if ! command -v setfacl >/dev/null 2>&1; then
  say "installing 'acl' package"
  sudo apt-get install -y acl 2>/dev/null \
    || sudo dnf install -y acl 2>/dev/null \
    || sudo yum install -y acl 2>/dev/null \
    || sudo pacman -S --noconfirm acl 2>/dev/null \
    || { echo "❌ couldn't auto-install 'acl' — install it manually, then re-run."; exit 1; }
fi

# 4. read-only roots: recursive + default ACL, then carve out secrets ---------
for d in ${READ_ROOTS[@]+"${READ_ROOTS[@]}"}; do
  if [[ ! -e "$d" ]]; then echo "⚠ read root $d does not exist — skipping"; continue; fi
  say "read-only: $d"
  sudo setfacl -R  -m u:"$CC_USER":rX "$d"
  sudo setfacl -R -d -m u:"$CC_USER":rX "$d"
  for s in ${READ_EXCLUDES[@]+"${READ_EXCLUDES[@]}"}; do
    [[ -e "$d/$s" ]] || continue
    echo "   carve out $d/$s"
    sudo setfacl -R  -x u:"$CC_USER" "$d/$s" 2>/dev/null || true
    sudo setfacl -R -d -x u:"$CC_USER" "$d/$s" 2>/dev/null || true
  done
done

# 5. writable work dirs -------------------------------------------------------
for d in ${WORK_DIRS[@]+"${WORK_DIRS[@]}"}; do
  if [[ ! -e "$d" ]]; then echo "⚠ work dir $d does not exist — skipping"; continue; fi
  say "writable: $d"
  sudo setfacl -R  -m u:"$CC_USER":rwX "$d"
  sudo setfacl -R -d -m u:"$CC_USER":rwX "$d"
done

# 6. OPTIONAL full-power: admin key under YOUR OWN account (NO sudo — it's your home) ----------
if [[ -n "$ADMIN_PUB" ]]; then
  if [[ "$(id -u)" -eq 0 ]]; then
    echo "⚠ running as root — SKIPPING the full-power admin key (it must go under your own"
    echo "  account, not root). Re-run this script as your normal user (without sudo) to add it."
  else
    say "full-power admin key for $(whoami)"
    install -d -m 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"; chmod 600 "$HOME/.ssh/authorized_keys"
    if grep -qF "$ADMIN_PUB" "$HOME/.ssh/authorized_keys"; then
      echo "   already present — skipping"
    else
      printf '%s\n' "$ADMIN_PUB" >> "$HOME/.ssh/authorized_keys"
      echo "   added. (Full-power stays OFF until you run 'fullpower.sh on' and type the passphrase.)"
    fi
  fi
fi

printf '\n✅ server side done. Back on your LOCAL machine: bash scripts/verify.sh\n'
SERVERLOGIC

chmod +x "$OUT"
echo "✅ wrote $OUT"
echo
echo "Next — copy it to the server and run it there as your own account (it will ask for your"
echo "sudo password; the agent never sees it):"
echo "    scp $OUT ${ADMIN_USER:-<you>}@${SERVER:-<server>}:~/"
echo "    ssh ${ADMIN_USER:-<you>}@${SERVER:-<server>}    # then, on the server:"
echo "    bash luffy-arm-server-setup.sh"
if [[ -n "$ADMIN_PUB" ]]; then
  echo "(includes the optional full-power admin key — full-power still stays OFF until you enable it.)"
fi
exit 0
