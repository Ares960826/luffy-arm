#!/usr/bin/env bash
# 💻 LOCAL: update luffy-arm to the latest published version, then re-install into every
# detected agent. Works from a git clone (git pull) or an installed copy (re-runs the
# official installer, which fetches the latest).
#
# Claude Code users who installed via the plugin marketplace should instead run:
#     /plugin update luffy-arm@ares-toolkit
# (or enable auto-update once — see README "Updating").
set -euo pipefail
REPO_URL="https://github.com/Ares960826/luffy-arm"
RAW_INSTALL="https://raw.githubusercontent.com/Ares960826/luffy-arm/main/install.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # skill root = scripts/..

ver_of(){ sed -n 's/^version:[[:space:]]*//p' "$1" 2>/dev/null | head -1; }
echo "current version: $(ver_of "$HERE/SKILL.md" || true)"

if [[ -d "$HERE/.git" ]]; then
  echo "→ git clone detected — pulling latest…"
  git -C "$HERE" pull --ff-only
  bash "$HERE/install.sh"
else
  echo "→ installed copy (no .git) — re-running the official installer…"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_INSTALL" | bash
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$RAW_INSTALL" | bash
  else
    echo "❌ need curl or wget to self-update (or update from a git clone of $REPO_URL)."; exit 1
  fi
fi
echo "✅ updated."
