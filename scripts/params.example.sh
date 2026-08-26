#!/usr/bin/env bash
# luffy-arm — per-host parameters (EXAMPLE / TEMPLATE).
#
# Copy this to your PRIVATE params file (OUTSIDE the repo) and fill in real values:
#   mkdir -p ~/.config/luffy-arm && cp params.example.sh ~/.config/luffy-arm/params.sh
#   ${EDITOR:-nano} ~/.config/luffy-arm/params.sh
# Every script reads it via:  ${LUFFY_ARM_PARAMS:-~/.config/luffy-arm/params.sh}
# NEVER commit your filled-in params.sh (real values live only on your machine).

# --- connection ---
export SERVER="<SERVER_IP_OR_HOST>"        # host/IP only, no username
export SSH_PORT="22"
export CC_USER="cc"                         # dedicated NON-privileged account the agent logs in as
export ADMIN_USER="<YOUR_OWN_USERNAME>"     # YOUR account (has sudo); used only by YOU for server-side root setup
export KEY="$HOME/.ssh/luffy-arm-key"        # the agent's private key — MUST be passphrase-less (non-interactive login)
export HOST_ALIAS="<SSH_ALIAS>"             # ssh shortcut name, e.g. my-gpu-box

# --- read-only roots: dirs the agent may read recursively (granted via ACL + default-ACL) ---
# default-ACL means files you create LATER under these roots auto-inherit read access —
# this is what handles "many / scattered / growing" paths without re-granting each one.
export READ_ROOTS=(
  "/home/<YOUR_OWN_USERNAME>"
  # "/data"
)

# --- writable work dirs: dirs the agent may WRITE (build outputs etc.); usually few ---
# Version control is NOT pre-set — init git/jj per project yourself when you want rollback.
# Empty () = server side fully read-only (strictest).
export WORK_DIRS=(
  # "/home/<YOUR_OWN_USERNAME>/project-x"
)

# --- the agent's own writable home/scratch (optional) ---
export CC_HOME=""                           # e.g. "/home/$CC_USER"

# --- sensitive dirs to EXCLUDE from read access (relative to each READ_ROOT) ---
# Write is already blocked for free (cc is another user, removed from shared groups), so the
# ONE thing to actively prevent is cc READING your keys/tokens. This blacklist is fail-open,
# so err toward MORE entries. Tune for your machine.
export READ_EXCLUDES=(
  # core credential stores
  ".ssh" ".gnupg" ".netrc" ".pgpass" ".git-credentials"
  # cloud / infra CLIs
  ".aws" ".azure" ".kube" ".config/gcloud" ".config/gh" ".config/rclone"
  ".boto" ".s3cfg" ".config/doctl" ".databrickscfg"
  ".vault-token" ".terraform.d" ".config/sops"
  # package-manager / registry publish tokens
  ".docker" ".npmrc" ".pypirc" ".cargo/credentials" ".cargo/credentials.toml"
  ".gem/credentials" ".m2/settings.xml" ".m2/settings-security.xml"
  ".gradle/gradle.properties" ".composer/auth.json"
  # password stores / keyrings
  ".password-store" ".local/share/keyrings"
  # ML platform tokens — deliberately NARROW for huggingface: only the token file is blocked,
  # so downloaded models/datasets under .cache/huggingface stay readable (often the point!)
  ".kaggle" ".jupyter" ".huggingface" ".cache/huggingface/token"
  # SERVER-side AI-agent configs (OAuth creds, API keys, MCP secrets) — the local agent has
  # no business reading another agent's brain (also reinforces INV-1)
  ".claude" ".claude.json" ".codex" ".cursor" ".config/opencode"
)

# --- full-power mode (OPT-IN; OFF by default) ---
# Lets the agent log in as ADMIN_USER (you), with that account's path-specific permissions. The
# safe account's data nets no longer apply; the sudo gate, your local copy, and INV-3 (never
# touch a password) still hold. Controlled by a passphrase-protected admin key loaded into
# ssh-agent; toggle that dedicated credential with scripts/fullpower.sh on|off|status. This
# switch does not revoke other SSH keys accepted for ADMIN_USER; status detects that separately.
# Leave these as-is if you don't want full-power. Full reasoning: references/security-model.md.
export ADMIN_KEY="$HOME/.ssh/luffy-arm-admin-key"   # admin key — HAS a passphrase (logs in as ADMIN_USER)
export ADMIN_ALIAS="${HOST_ALIAS}-admin"            # ssh alias used for full-power mode
export FULLPOWER_TTL="3600"                          # seconds before full-power auto-disables (default 1h)
export FULLPOWER_AGENT_SOCKET="$HOME/.config/luffy-arm/fullpower-agent.sock" # stable cross-conversation agent entry
