#!/usr/bin/env bash
# 💻 LOCAL: generate the ADMIN key for opt-in full-power mode (logs in as ADMIN_USER = you).
# CRITICAL: this key MUST have a passphrase. The passphrase is the master switch for full
# power — YOU type it, the agent never sees it (preserves INV-3). This touches ~/.ssh; run it
# only after you authorize it.
set -euo pipefail
PARAMS="${LUFFY_ARM_PARAMS:-$HOME/.config/luffy-arm/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
source "$PARAMS"
: "${ADMIN_KEY:?ADMIN_KEY not set in params — add the full-power vars (see scripts/params.example.sh).}"
: "${ADMIN_USER:?ADMIN_USER not set in params.}"

if [[ -f "$ADMIN_KEY" ]]; then
  echo "Admin key already exists: $ADMIN_KEY (skipping generation)"
else
  echo ">>> You'll be asked to set a PASSPHRASE — enter a real one, do NOT leave it empty"
  echo "    (an empty passphrase means there's no master switch for full power)."
  ssh-keygen -t ed25519 -f "$ADMIN_KEY" -C "luffy-arm-admin"   # no -N: prompts for a passphrase on purpose
fi
chmod 600 "$ADMIN_KEY"
# The .pub is used as the admin block's IdentityFile in ~/.ssh/config, so the key is usable
# ONLY through ssh-agent (that's what makes the on/off switch work). ssh perm-checks that file
# as if it were a private key; 600 silences the "permissions too open" warning seen while OFF.
chmod 600 "$ADMIN_KEY.pub"

echo
echo "Admin PUBLIC key — install it under YOUR OWN account ($ADMIN_USER) on the server"
echo "(append to ~/.ssh/authorized_keys; no sudo — it's your own home. See references/server-setup.md):"
cat "$ADMIN_KEY.pub"
echo
echo "Then enable full-power with:  bash scripts/fullpower.sh on   (it asks for the passphrase above)"
