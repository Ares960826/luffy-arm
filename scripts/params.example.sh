#!/usr/bin/env bash
# tentacle — per-host parameters (EXAMPLE / TEMPLATE).
#
# Copy this to your PRIVATE params file (OUTSIDE the repo) and fill in real values:
#   mkdir -p ~/.config/tentacle && cp params.example.sh ~/.config/tentacle/params.sh
#   ${EDITOR:-nano} ~/.config/tentacle/params.sh
# Every script reads it via:  ${TENTACLE_PARAMS:-~/.config/tentacle/params.sh}
# NEVER commit your filled-in params.sh (real values live only on your machine).

# --- connection ---
export SERVER="<SERVER_IP_OR_HOST>"        # host/IP only, no username
export SSH_PORT="22"
export CC_USER="cc"                         # dedicated NON-privileged account the agent logs in as
export ADMIN_USER="<YOUR_OWN_USERNAME>"     # YOUR account (has sudo); used only by YOU for server-side root setup
export KEY="$HOME/.ssh/tentacle_key"        # the agent's private key — MUST be passphrase-less (non-interactive login)
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
  ".ssh" ".gnupg" ".aws" ".azure" ".kube"
  ".config/gcloud" ".config/gh" ".config/rclone"
  ".netrc" ".pgpass" ".git-credentials"
  ".huggingface" ".cache/huggingface" ".kaggle" ".jupyter"
)

# NOTE: "full-power mode" (logging in as ADMIN_USER for full read/write) is intentionally
# NOT part of v1. It ships in a later version once verified. See references/security-model.md.
