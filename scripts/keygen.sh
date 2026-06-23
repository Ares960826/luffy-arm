#!/usr/bin/env bash
# 💻 LOCAL: generate the agent's dedicated SSH keypair.
# The key is passphrase-LESS on purpose: the agent logs in non-interactively, so a passphrase
# would break auto-login. This touches ~/.ssh — run it only AFTER the user authorizes it.
set -euo pipefail
PARAMS="${TENTACLE_PARAMS:-$HOME/.config/tentacle/params.sh}"
[[ -f "$PARAMS" ]] || { echo "Missing params: $PARAMS — copy scripts/params.example.sh there and fill it in."; exit 1; }
source "$PARAMS"

if [[ -f "$KEY" ]]; then
  echo "Key already exists: $KEY (skipping generation)"
else
  ssh-keygen -t ed25519 -f "$KEY" -C "tentacle-cc" -N ""   # -N "" = NO passphrase (required for auto-login)
fi
chmod 600 "$KEY"
echo
echo "Public key — install THIS on the server in the next step (server-setup.md, step 'install pubkey'):"
cat "$KEY.pub"
