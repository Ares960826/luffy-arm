#!/usr/bin/env bash
# luffy-arm installer — detect the AI coding agents on this machine and install the skill
# into each one's skills directory. One command, works for Claude Code / Codex / Cursor / OpenCode.
#
# Usage:
#   bash install.sh                          # from a clone: install into every detected agent
#   curl -fsSL https://raw.githubusercontent.com/Ares960826/luffy-arm/main/install.sh | bash
#   LUFFY_ARM_DIR=/custom/skills bash install.sh   # force one target skills dir, skip detection
#
# Agent → skills dir it reads:
#   Claude Code · Cursor · OpenCode  → ~/.claude/skills/   (Cursor/OpenCode read it for compat)
#   Codex                            → ~/.agents/skills/
set -euo pipefail

REPO_URL="https://github.com/Ares960826/luffy-arm"
SKILL_NAME="luffy-arm"
SUBSKILLS=("luffy-arm-fullpower-on" "luffy-arm-fullpower-off")

# --- 1. locate the skill source (this repo) ---
SRC=""
if [[ "${BASH_SOURCE[0]:-}" == *install.sh ]]; then
  cand="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  [[ -f "$cand/SKILL.md" ]] && SRC="$cand"
fi
if [[ -z "$SRC" ]]; then          # piped via curl, or not run from a clone → fetch it
  command -v git >/dev/null 2>&1 || { echo "❌ need git to fetch $SKILL_NAME"; exit 1; }
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "→ cloning $REPO_URL …"
  git clone --depth 1 "$REPO_URL" "$TMP/$SKILL_NAME" >/dev/null   # stderr kept: a failed clone must say why
  SRC="$TMP/$SKILL_NAME"
fi
[[ -f "$SRC/SKILL.md" ]] || { echo "❌ skill source not found (no SKILL.md at $SRC)"; exit 1; }

# --- 2. detect agents → target skills dirs (deduped) ---
TARGETS=(); AGENTS=()
add_target(){ local t="$1" x; for x in "${TARGETS[@]:-}"; do [[ "$x" == "$t" ]] && return 0; done; TARGETS+=("$t"); }

if [[ -n "${LUFFY_ARM_DIR:-}" ]]; then
  add_target "$LUFFY_ARM_DIR"; AGENTS+=("forced:$LUFFY_ARM_DIR")
else
  [[ -d "$HOME/.claude"          ]] && { add_target "$HOME/.claude/skills"; AGENTS+=("Claude Code"); }
  [[ -d "$HOME/.cursor"          ]] && { add_target "$HOME/.claude/skills"; AGENTS+=("Cursor→~/.claude/skills"); }
  [[ -d "$HOME/.config/opencode" ]] && { add_target "$HOME/.claude/skills"; AGENTS+=("OpenCode→~/.claude/skills"); }
  [[ -d "$HOME/.codex"           ]] && { add_target "$HOME/.agents/skills"; AGENTS+=("Codex→~/.agents/skills"); }
fi
if [[ ${#TARGETS[@]} -eq 0 ]]; then
  echo "⚠ no known agent detected (~/.claude, ~/.codex, ~/.cursor, ~/.config/opencode)."
  echo "  Defaulting to ~/.claude/skills — override with LUFFY_ARM_DIR=/path."
  add_target "$HOME/.claude/skills"; AGENTS+=("(default ~/.claude/skills)")
fi

# --- 3. copy the skill into each target ---
copy_into(){
  local dest="$1/$SKILL_NAME"
  # guard: if the target IS the source (user cloned straight into the skills dir), copying
  # would first wipe the source — nothing to do, it's already in place
  if [[ -e "$dest" && "$(cd "$SRC" && pwd)" == "$(cd "$dest" 2>/dev/null && pwd)" ]]; then
    echo "  ✓ $dest (is the source clone itself — left as-is)"; return 0
  fi
  mkdir -p "$dest"
  # Product allowlist: local development/test artifacts are excluded by default.
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --delete-excluded \
      --include='/SKILL.md' --include='/TUTORIAL.md' --include='/README.md' \
      --include='/LICENSE' --include='/CHANGELOG.md' --include='/install.sh' \
      --include='/scripts/***' --include='/references/***' --include='/agents/***' --exclude='*' \
      "$SRC/" "$dest/"
  else
    rm -rf "$dest"; mkdir -p "$dest"       # poor man's --delete: no stale files across upgrades
    for item in SKILL.md TUTORIAL.md README.md LICENSE CHANGELOG.md install.sh scripts references agents; do
      [[ -e "$SRC/$item" ]] && cp -R "$SRC/$item" "$dest/"
    done
  fi
  echo "  ✓ $dest"
}

copy_subskill(){
  local src="$SRC/skills/$2" dest="$1/$2"
  [[ -f "$src/SKILL.md" ]] || { echo "❌ sub-skill source not found: $src"; exit 1; }
  mkdir -p "$dest"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --delete-excluded --include='/SKILL.md' --include='/scripts/***' \
      --include='/agents/***' \
      --exclude='*' "$src/" "$dest/"
  else
    rm -rf "$dest"; mkdir -p "$dest"
    cp "$src/SKILL.md" "$dest/"
    [[ -d "$src/scripts" ]] && cp -R "$src/scripts" "$dest/"
    [[ -d "$src/agents" ]] && cp -R "$src/agents" "$dest/"
  fi
  echo "  ✓ $dest"
}

echo "luffy-arm installer"
echo "Detected: ${AGENTS[*]}"
echo "Installing →"
for t in "${TARGETS[@]}"; do
  copy_into "$t"
  for subskill in "${SUBSKILLS[@]}"; do copy_subskill "$t" "$subskill"; done
done

# --- 4. optional: put the `luffy-arm` command on your PATH (human convenience only) ---
# The AGENT never needs this — it calls scripts/*.sh directly. This is purely so a human can
# type `luffy-arm fullpower on` instead of the full script path. It's a symlink to the installed
# dispatcher, so updates track automatically; remove it any time with `rm ~/.local/bin/luffy-arm`.
CMD_NOTE=""
DISPATCH="${TARGETS[0]}/$SKILL_NAME/scripts/luffy-arm"
if [[ -f "$DISPATCH" ]]; then
  BINDIR="$HOME/.local/bin"
  mkdir -p "$BINDIR"
  if ln -sf "$DISPATCH" "$BINDIR/$SKILL_NAME" 2>/dev/null; then
    chmod +x "$DISPATCH" 2>/dev/null || true
    if [[ ":$PATH:" == *":$BINDIR:"* ]]; then
      CMD_NOTE="  • \`$SKILL_NAME\` command ready → $BINDIR/$SKILL_NAME (on your PATH ✓). Try: $SKILL_NAME help"
    else
      CMD_NOTE="  • \`$SKILL_NAME\` command linked → $BINDIR/$SKILL_NAME — add ~/.local/bin to PATH to use it:
       echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc   # or ~/.bashrc, then reopen the shell"
    fi
    # short alias `luffy` — convenience; only if no OTHER `luffy` already owns the name
    # (a Homebrew movie CLI ships a `luffy` binary), so we never clobber someone else's tool.
    SHORT="$BINDIR/luffy"; EXIST="$(command -v luffy 2>/dev/null || true)"
    if [[ -z "$EXIST" || "$EXIST" == "$SHORT" ]]; then
      ln -sf "$DISPATCH" "$SHORT" 2>/dev/null && CMD_NOTE="$CMD_NOTE
  • short alias \`luffy\` → same command (e.g. \`luffy verify\`)."
    else
      CMD_NOTE="$CMD_NOTE
  • \`luffy\` alias SKIPPED — another 'luffy' is already at $EXIST. Use \`$SKILL_NAME\`, or remove that and re-run."
    fi
  fi
fi

# --- 5. next steps ---
cat <<EOF

✅ Installed luffy-arm + fullpower-on/off switches. Next:
  1) Create your params (kept OUTSIDE any repo):
       mkdir -p ~/.config/$SKILL_NAME
       cp "$SRC/scripts/params.example.sh" ~/.config/$SKILL_NAME/params.sh
       \${EDITOR:-nano} ~/.config/$SKILL_NAME/params.sh
  2) Tell your agent, e.g.: "use $SKILL_NAME to set up access to my server"
     (or follow the walkthrough in $SKILL_NAME/TUTORIAL.md)
${CMD_NOTE:+
Optional human shortcut:
$CMD_NOTE}
EOF
