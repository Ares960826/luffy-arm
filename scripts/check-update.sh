#!/usr/bin/env bash
# 💻 LOCAL: best-effort "is a newer luffy-arm published?" check. Non-fatal, network-optional,
# never auto-applies anything. verify.sh calls this at the end; you can also run it directly.
REPO_URL="https://github.com/Ares960826/luffy-arm"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cur="$(sed -n 's/^version:[[:space:]]*//p' "$HERE/SKILL.md" 2>/dev/null | head -1)"
[[ -n "$cur" ]] || exit 0

# latest published tag (works without a local clone); short low-speed timeout so we never hang
latest="$(GIT_TERMINAL_PROMPT=0 git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=5 \
  ls-remote --tags --refs "$REPO_URL" 2>/dev/null \
  | sed -n 's#.*refs/tags/v##p' | sort -V | tail -1)"
[[ -n "$latest" ]] || exit 0   # offline / no tags → stay silent

# print the nudge only if latest is strictly newer than current
if [[ "$latest" != "$cur" && "$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | tail -1)" == "$latest" ]]; then
  echo "🆙 luffy-arm v$latest is available (you have v$cur)."
  echo "   Update: bash scripts/update.sh   ·   Claude Code plugin users: /plugin update luffy-arm"
fi
exit 0
