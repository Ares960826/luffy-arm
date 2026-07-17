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
  # assets/ (~3.3 MB of README images), .github/ and .claude-plugin/ (marketplace metadata)
  # are repo décor, not skill content — skip them
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude='.git' --exclude='.github' --exclude='.claude-plugin' \
      --exclude='.omc' --exclude='.DS_Store' --exclude='ChatGPT*' --exclude='assets' "$SRC/" "$dest/"
    rm -rf "$dest/assets" "$dest/.github" "$dest/.claude-plugin" "$dest/.omc"   # purge pre-1.2 leftovers
  else
    rm -rf "$dest"; mkdir -p "$dest"       # poor man's --delete: no stale files across upgrades
    cp -R "$SRC/." "$dest/"
    rm -rf "$dest/.git" "$dest/.github" "$dest/.claude-plugin" "$dest/.omc" "$dest/.DS_Store" "$dest/assets"
  fi
  echo "  ✓ $dest"
}

echo "luffy-arm installer"
echo "Detected: ${AGENTS[*]}"
echo "Installing →"
for t in "${TARGETS[@]}"; do copy_into "$t"; done

# --- 4. next steps ---
cat <<EOF

✅ Installed. Next:
  1) Create your params (kept OUTSIDE any repo):
       mkdir -p ~/.config/$SKILL_NAME
       cp "$SRC/scripts/params.example.sh" ~/.config/$SKILL_NAME/params.sh
       \${EDITOR:-nano} ~/.config/$SKILL_NAME/params.sh
  2) Tell your agent, e.g.: "use $SKILL_NAME to set up access to my server"
     (or follow the walkthrough in $SKILL_NAME/TUTORIAL.md)
EOF
