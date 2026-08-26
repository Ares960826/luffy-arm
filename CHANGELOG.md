# Changelog

All notable changes to luffy-arm. Format follows [Keep a Changelog](https://keepachangelog.com/);
versions follow [SemVer](https://semver.org/). Versions before 1.2.0 are tagged retroactively.

## [1.7.1] — 2026-08-26

Patch release correcting the security meaning of the Full Power switch.

### Fixed

- **Credential gate is no longer confused with effective permission.** `fullpower status` now
  reports the dedicated `luffy-arm-admin` key gate separately from the authenticated remote
  identity and from alternate non-interactive SSH access with `IdentitiesOnly=no`. If another
  key reaches the same `ADMIN_USER`, the result explicitly says effective user access remains;
  it never claims Safe Mode merely because the dedicated key is OFF.
- **OFF is honest about residual access.** `fullpower off` removes and verifies the dedicated key,
  then probes for alternate credentials. It exits with status 4 when the gate is OFF but another
  key still reaches `ADMIN_USER`, because personal keys are outside the luffy-arm switch.
- **Permission language is identity-based.** Successful authentication is reported as the actual
  remote user. Exact path write access and sudo are left to target-specific verification instead
  of being inferred from the key filename.

### Tests

- Added layered-state regression coverage for dedicated ON, dedicated OFF plus alternate access,
  complete denial, remote-identity mismatch, and transport-unknown cases.

## [1.7.0] — 2026-08-07

Full-power is now a dependable, intent-shaped product operation across normal shells and
sandboxed agents.

### Added

- **Independent `luffy-arm-fullpower-on` and `luffy-arm-fullpower-off` skills.** Each has its own
  trigger surface and a thin wrapper around the existing `scripts/fullpower.sh`; the installer
  places them beside the main skill and the plugin manifest exposes all three skills. UI metadata
  labels the pair as Luffy Arm companion operations because current skill hosts do not expose a
  native parent/sub-skill relationship.
- **Human CLI parity:** `luffy-arm fullpower-on [seconds]` and `luffy-arm fullpower-off` remain
  thin aliases over the existing full-power switch.
- **Product-only install allowlist:** installation copies only the shipped skill, scripts,
  references, license, changelog, and user documentation; unrelated local development artifacts
  are excluded by default.

### Fixed

- **Sandbox-safe full-power state.** `status`, `off`, and `verify-fullpower.sh` now distinguish
  `ON`, explicit authentication-denied `OFF`, and transport/agent-inaccessible `UNKNOWN`.
  Sandbox or network failures are no longer reported as OFF.
- **Host-first SSH execution for sandboxed agents.** Once a runtime is known to isolate SSH or
  ssh-agent, the skill requests narrowly scoped, user-approved host execution from the first
  probe instead of repeating a known-blocked sandbox check or asking the user to re-arm the key.
- **Full-power verification uses the live admin alias as authority** instead of requiring the
  current process to see the user's login-session ssh-agent.
- **Full-power now works across separate conversations.** The interactive ON command publishes a
  stable, user-private agent socket reference, and the admin SSH alias uses that reference instead
  of whichever `SSH_AUTH_SOCK` a particular process happened to inherit. No key material or
  passphrase is copied, and the existing TTL remains authoritative.
- **ON preflight** checks that the passphrased admin key exists and that the admin SSH alias uses
  it before asking the user to load it.
- **ON is idempotent across conversations.** The ON skill now checks host status before prompting:
  it reuses an already-ON gate, preserves UNKNOWN without demanding a re-arm, and asks for the
  passphrase command only after verified OFF. A remote task included with the switch continues
  under the main luffy-arm skill once ON is confirmed.

### Upgrade note

After updating an existing installation, run `luffy-arm ssh-config` once. It adds the shared
`IdentityAgent` entry to the existing admin alias while leaving its connection fields unchanged.

### Repository

- Removed development-only CI and contribution workflow files from the published product tree.

## [1.6.0] — 2026-07-17

Security fix: the read-exclusion carve-out now actually hides world-readable secret dirs.

### Fixed

- **`READ_EXCLUDES` are now enforced with explicit deny (`setfacl -m u:cc:---`), not a removed
  grant (`setfacl -x u:cc`).** Removing cc's ACL entry lets it fall back to the file's **"other"
  read bit**, so on any **world-readable** secret dir (mode `o+r` — common for `.claude`,
  `.claude-mem`, `.agents`, `.codex`) the old `-x` carve-out **silently failed to hide it**. A
  named-user entry is checked before "other", so `u:cc:---` denies cc even when everyone else can
  read. Found in live testing: cc could still read `.agents`/`.claude-mem` after a `-x` exclude.
  Fixed in `scripts/gen-server-setup.sh`, `scripts/grant.sh`, and `references/server-setup.md`.
- **`references/security-model.md`** documents the trap ("How the carve-out is enforced").

### Note

- If you set up a server with an earlier version, re-run your exclusions with the new form (or
  `bash scripts/grant.sh ro <read-root>` prints them), then verify with
  `[ -r /home/<you>/.claude ] && echo LEAK || echo ok` as the cc account.

## [1.5.0] — 2026-07-17

One command instead of long script paths — a thin, human-only convenience layer.

### Added

- **Unified `luffy-arm` command.** `scripts/luffy-arm` is a thin dispatcher that forwards each
  subcommand to the matching `scripts/*.sh`: `luffy-arm keygen | ssh-config | setup | verify |
  grant | admin-keygen | fullpower | verify-fullpower | audit-gen | update | check-update |
  version | help`. It adds **no logic** and **bypasses no gate** — `fullpower on` still makes
  you type the passphrase, `audit-gen`'s output still needs your sudo on the server. It resolves
  its own path through symlinks, so it works when linked onto your PATH.
- **`install.sh` PATH shortcut (opt-in surface).** After installing the skill, the installer
  symlinks the dispatcher to `~/.local/bin/luffy-arm` (tracks updates automatically; remove with
  `rm ~/.local/bin/luffy-arm`) and, if `~/.local/bin` isn't on PATH, prints the one line to add
  it. Purely a human convenience.

### Notes

- **Naming.** The canonical command is `luffy-arm` (collision-free). The installer also adds a
  shorter `luffy` alias for convenience — but **only if no other `luffy` already exists on your
  PATH** (a maintained Homebrew CLI, a movie/TV streamer, ships a `luffy` binary), so it never
  clobbers someone else's tool. If the name is taken, the installer prints that it skipped the
  alias and you keep `luffy-arm`.
- **Agent behavior is unchanged.** SKILL.md still directs the agent to call `scripts/*.sh`
  directly (PATH-independent, stable). The `luffy-arm`/`luffy` command is documented for humans only.

## [1.4.0] — 2026-07-17

Optional command auditing — the server-side answer to the one thing a local machine can't see.

### Added

- **Opt-in command auditing.** `scripts/gen-audit-setup.sh` (run locally, no secrets) emits an
  idempotent `luffy-arm-audit-setup.sh` with `enable | disable | status | show [N]`. `enable`
  installs a one-file `sshd` `ForceCommand` wrapper scoped to `Match User <cc>` that logs every
  `ssh <alias> "<cmd>"` (as `$SSH_ORIGINAL_COMMAND`) to the root-owned system journal, then
  execs it transparently — so the unprivileged `cc` account cannot erase its own trail. This
  closes the *visibility* half of the "ssh command string is invisible to the local machine"
  blind spot, from the only place it can live: the server.
- **Safety.** Off by default; nothing changes until the **user** runs `enable` with their own
  sudo (INV-3 — the agent never runs it). The block is appended at the end of `sshd_config`
  (can't bleed into unrelated config), backed up once, and `sshd -t`-validated **before** any
  reload, so a bad edit can't lock you out. `disable` is a full clean removal.
- **`references/audit-logging.md`** — mechanism, how to read the log, honest limits (detect not
  prevent; command string not per-process; `cc` can add noise but not delete; safe-mode only;
  modern-`scp` caveat), and an **auditd** alternative for kernel-level, per-`execve` coverage.

### Changed

- `security-model.md` documents auditing as an optional **fifth**, complementary layer on top
  of the four preventing nets, and points the "unavoidable blind spot" section at it as the
  server-side way to gain visibility. SKILL.md gains a short opt-in "command auditing" section.

## [1.3.0] — 2026-07-17

Two headline features: one-command guided setup, and real update paths for every agent.

### Added

- **One-command guided setup.** `scripts/gen-server-setup.sh` turns your params + public key
  into a single, self-contained, idempotent `luffy-arm-server-setup.sh`. Everything local is
  automated by the agent; the server side collapses from ~8 copy-paste commands to one
  `bash luffy-arm-server-setup.sh` you run with your own sudo. The generated script also
  installs the optional full-power admin key under *your own* account (no sudo). SKILL.md's
  INSTALL mode is rewritten as a guided wizard that drives this end to end.
- **Update paths.** `scripts/update.sh` (git pull or re-run the installer) upgrades luffy-arm
  in place for Codex/Cursor/OpenCode/curl users; `scripts/check-update.sh` prints a
  non-fatal "newer version available" nudge, and `verify.sh` runs it at the end.
- **Claude Code plugin marketplace.** `.claude-plugin/plugin.json` makes the repo installable
  as a plugin; the companion `ares-agent-toolkit` marketplace lets Claude Code users
  `/plugin install luffy-arm@ares-toolkit` and `/plugin update`. README documents enabling
  auto-update (per-user via the `/plugin` UI toggle; org-wide via managed settings).

### Changed

- Full-power mode documentation hardened: SKILL.md now spells out that the passphrase-in-
  ssh-agent IS the gate, and that the agent must NEVER auto-load the key, make it
  passphrase-less, or enable the mode on the user's behalf.
- `install.sh` also excludes `.claude-plugin/` from the standalone skill copy.

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
  no-rsync fallback ships only product files and removes stale files on upgrade.
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

- `.github/`: bug-report & feature-request issue forms (with redaction guidance) and SECURITY.md
  (private vulnerability reporting).
- This CHANGELOG; version/license badges and "When you need this" + Prerequisites sections
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
