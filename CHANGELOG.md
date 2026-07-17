# Changelog

All notable changes to luffy-arm. Format follows [Keep a Changelog](https://keepachangelog.com/);
versions follow [SemVer](https://semver.org/). Versions before 1.2.0 are tagged retroactively.

## [1.2.0] — 2026-07-17

Security-hardening + token-economy release, prepared for the public launch.

### Security

- **Full-power admin alias no longer multiplexes SSH connections** (`ControlMaster no`).
  Previously a cached master connection could keep admin access alive *past the ssh-agent TTL*
  — the auto-off guarantee now holds. Existing setups: re-run `scripts/ssh-config.sh` after
  removing the old admin Host block, or add `ControlMaster no` to it manually.
- `fullpower.sh off` now **verifies** the admin alias really no longer authenticates and fails
  loudly if the key survives in another ssh-agent or a cached connection; `status` performs the
  same reality check instead of trusting the local agent's key list.
- `admin-keygen.sh` now **enforces** a non-empty passphrase (an empty one silently removed the
  entire full-power on/off gate). Newly generated empty-passphrase keys are deleted;
  pre-existing ones get in-place `ssh-keygen -p` instructions.
- `READ_EXCLUDES` default list greatly expanded: Docker/npm/PyPI/Cargo/RubyGems/Maven/Gradle/
  Composer registry tokens, Terraform/Vault/sops, `pass`/keyrings, plus **server-side AI-agent
  config dirs** (`.claude`, `.codex`, `.cursor`, `.config/opencode`). `.cache/huggingface` was
  narrowed to just its `token` file so datasets/models stay explorable.
- Generated Host blocks use `StrictHostKeyChecking accept-new` (no TOFU hang, still detects key
  changes); `~/.ssh/config` is created with mode 600.

### Fixed

- `verify.sh` / `grant.sh` no longer crash on empty `WORK_DIRS=()` / `READ_EXCLUDES=()` under
  stock macOS bash 3.2 (`set -u` + empty-array expansion).
- `verify.sh` uses `BatchMode` + `ConnectTimeout` — a broken setup now fails fast with ❌
  instead of hanging on a password prompt; the write-denied probe cleans up after itself if the
  ACL is misconfigured.
- `keygen.sh` / `admin-keygen.sh` create `~/.ssh` (mode 700) when missing.
- `ssh-config.sh`: exact-match duplicate detection (aliases with `.` no longer false-match) and
  an explicit warning that an existing block is not updated when params change.
- `install.sh`: clone failures now print the git error; temp clone dir is cleaned on exit; the
  no-rsync fallback no longer ships `.omc/`/`.DS_Store` and removes stale files on upgrade.
- TUTORIAL: expected `verify.sh` output corrected (checks scale with your roots/dirs — the old
  text hardcoded `passed 9`).

### Changed

- `install.sh` no longer copies `assets/` (~3.3 MB of README images) or `.github/` into each
  agent's skills directory.
- Docs deduplicated (~12% fewer words; SKILL.md ~15% leaner **per activation**):
  `references/server-setup.md` is now the single source of privileged server commands;
  `references/setup-guide.md` repositioned as terse checklist + canonical troubleshooting;
  canonical rationale lives in `references/security-model.md`.
- SKILL.md frontmatter: added `version`, plus routing triggers ("luffy-arm", data-download
  phrasings).

### Added

- `.github/`: bug-report & feature-request issue forms (with redaction guidance), PR template,
  CONTRIBUTING.md, SECURITY.md (private vulnerability reporting), shellcheck CI.
- This CHANGELOG; version/license/CI badges and "When you need this" + Prerequisites sections
  in README.

## [1.1.0] — 2026-07-03 (retroactive tag)

- Agent-agnostic: one skill serving Claude Code / Codex / Cursor / OpenCode.
- Opt-in **full-power mode** (passphrase-gated admin key via ssh-agent + TTL) ported into the
  skill with `verify-fullpower.sh` self-check.
- One-command auto-detecting `install.sh` (`curl | bash` supported); path-agnostic docs.
- Architecture diagram; data-download (scp/rsync) documentation.

## [1.0.0] — 2026-06-23 (retroactive tag)

- Initial release (born "tentacle", renamed luffy-arm): safe mode — dedicated unprivileged
  `cc` account, ACL read-only roots + `READ_EXCLUDES` carve-outs, writable `WORK_DIRS`,
  sudo password gate; `keygen/ssh-config/verify/grant` scripts; full TUTORIAL.
