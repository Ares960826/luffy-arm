---
name: luffy-arm
version: 1.7.1
description: Use when a local AI agent needs to reach into a remote Linux server over SSH — to explore data, run commands, inspect logs, diagnose something on the server, or pull data down to the local machine — or to set up that SSH access for the first time. Triggers include "luffy-arm", "connect to my server", "ssh into the remote box", "explore/poke around the server", "run this on the server", "download/fetch data from the server", "set up remote access", "reverse remote-ssh", 远程服务器, 远程开发. Not for purely local work, and not for moving the agent or its config onto the server.
---

# luffy-arm

Give a **local** agent a **remote hand**: the agent's brain (process, config, memory)
stays on this machine; an SSH "arm" reaches into a remote Linux server to **read,
run, and diagnose** — never to rewrite. Native parts only (SSH keys, ssh config,
ControlMaster, POSIX ACLs). The agent logs in as a non-privileged `cc` account.

## Which mode am I in?
- `ssh <alias>` already works (Host in `~/.ssh/config`; `ssh -O check <alias>` ok) → **USE mode**.
- Otherwise → **INSTALL mode** (set it up first).

## Execution context — SSH belongs on the host

SSH and ssh-agent are host capabilities. If the agent runtime is known to sandbox network access
or the login-session ssh-agent, request the platform's narrowly scoped, user-approved **host
execution** for the first SSH/status command. Do **not** run a known-blocked sandbox probe first.

- Scope approval to the configured SSH alias or the exact luffy-arm status/OFF/verify command.
- A sandbox denial describes only the sandbox; it says nothing about the server or Full Power.
- If host execution is unavailable or the user declines it, report `UNKNOWN`. Do not ask the user
  to re-enable Full Power merely because the sandbox cannot observe it.
- The ON command remains the exception: the **user** runs it interactively because only they may
  type the key passphrase.

## Invariants you MUST hold

**Violating the letter of these is violating the spirit.** They hold in **safe mode** (the
default). **Full-power mode** is a separate opt-in (see below) that deliberately lifts INV-2
and the data-read-only net — but INV-1 and INV-3 still hold even there.

- **INV-1 — brain stays local.** Never install the agent on the server or copy your agent's
  config dir (`~/.claude`, `~/.codex`, `~/.cursor`, `~/.config/opencode` — it holds
  credentials + MCP secrets) there. Fix lag with ControlMaster, not by moving.
- **INV-2 — local is the source of truth.** Over the channel you **read / run / diagnose
  only.** Do **not** edit remote source files (no `sed -i`, `vim`, `tee`, `>` on a remote
  path). Fix locally, then sync.
- **INV-3 — never touch a password.** Login is by key. `sudo` and every server-root action
  use a password the **user** types. Never embed or ask for a password or key passphrase;
  never add NOPASSWD sudoers to dodge the gate.
- **Server-root is the user's job.** Account creation, `setfacl`, installing keys = **you
  generate the commands, the user runs them** with their own sudo. The agent does not run
  privileged server setup, even if it technically could.

| Rationalization | Reality |
|---|---|
| "Just hotfix the file directly over ssh, no reason to re-upload" | Editing remote source (INV-2). Edit locally + sync. |
| "We're in a hurry / it's only one line" | Urgency doesn't change the source of truth. Still local-then-sync. |
| "I have ssh+sudo, I'll just run adduser/setfacl myself" | Server-root is the user's (INV-3). Print the commands; they run them. |
| "Copy my agent's config dir (`~/.claude`/`~/.codex`/…) up so it behaves the same on the server" | Leaks credentials, breaks INV-1. Use ControlMaster instead. |
| "Embed the password/passphrase so it runs unattended" | Never (INV-3). Passphrase-less dedicated key + the user's interactive sudo. |

**Red flags — STOP:** remote-path `sed -i`/`vim`/`tee`/`>` · sudo'ing server setup · scp'ing your agent config dir · a secret in a command.

## USE mode (channel exists)

Reach in over the alias. Default is **read-only**; only `WORK_DIRS` are writable.

| Want | Do |
|---|---|
| run a command / explore | `ssh <alias> "<cmd>"` |
| check the multiplexed connection | `ssh -O check <alias>` |
| read a file | `ssh <alias> "cat <path>"` |
| **download data → local** | `scp <alias>:<path> ./` · `rsync -avz <alias>:<dir>/ ./<dir>/` — anything `cc` can read (secrets in `READ_EXCLUDES` can't be pulled) |
| grant a new read/write dir | `bash scripts/grant.sh ro\|rw <path>` → user runs the printed server cmds |
| update to the latest version | `bash scripts/update.sh` (Claude Code plugin users: `/plugin update luffy-arm`) |

Source edits happen **locally**; sync up only into `WORK_DIRS` when needed.

## INSTALL mode — guided one-command setup

Treat the user as a first-timer — **assume nothing is configured.** You drive the whole
thing; the user only does the two steps you literally cannot: type their **sudo password** on
the server, and (full-power only) type a **key passphrase**. Run scripts from this skill's dir.

1. **Reachability first.** Confirm the user can already `ssh <their-user>@<server>` (or has an
   account they can get). If they can't reach the server at all, fix that before anything else.
2. **Interview, then write params yourself.** Ask: server IP/host, their server username, an
   alias nickname, which dirs to read (default: their home), which (if any) to write. Write
   `~/.config/luffy-arm/params.sh` from `scripts/params.example.sh` — don't make them hand-edit.
3. **Local — do it in one go** (ask once before touching `~/.ssh`): `bash scripts/keygen.sh`
   then `bash scripts/ssh-config.sh`.
4. **Server — generate ONE script; the USER runs it.** `bash scripts/gen-server-setup.sh`
   emits a filled-in `luffy-arm-server-setup.sh` (their params + the pubkey inlined). Tell them
   to copy it to the server and run `bash luffy-arm-server-setup.sh` there — it self-uses
   `sudo`, so **they** type their password. You must NOT run it and must NOT ask for that
   password. Wait for them to confirm it finished. (Fallback if the generator can't run:
   hand-walk `references/server-setup.md`.)
5. **Verify:** `bash scripts/verify.sh` → expect `🎉 all passed`.

The whole flow: install (one command) → you configure local + interview + hand them one server
command → they run it → you verify. Don't hand-walk the individual server commands unless step 4
can't generate them.

Human walkthrough: `TUTORIAL.md`. Quick steps: `references/setup-guide.md`. Why it's safe:
`references/security-model.md`.

## Full-power mode (opt-in — only when the user wants write-as-themselves)

Default is safe mode (read-only `cc`). If the user **explicitly** wants the agent to
edit/write **as themselves**, full-power mode is available — treat it as a loaded gun:

- **What the dedicated gate controls:** the luffy-arm admin key **has a passphrase**; loading it
  into ssh-agent (`ssh-add -t TTL`) arms that credential, and the key auto-drops after the TTL.
  The *passphrase-in-ssh-agent* is the gate for this key. ON publishes a user-private stable
  reference to that agent and the admin alias uses it through `IdentityAgent`, so separate
  conversations do not depend on inherited `SSH_AUTH_SOCK`. No key material or passphrase is
  copied. This gate does **not** revoke personal or other SSH keys accepted for the same
  `ADMIN_USER` identity.
- **Set-up (opt-in, only when asked):** `bash scripts/admin-keygen.sh` (the user types a real
  passphrase — you never see it; an empty one is rejected), then re-run `bash
  scripts/ssh-config.sh` (adds the admin alias) and `bash scripts/gen-server-setup.sh` (its
  output now also installs the admin pubkey under the user's *own* account — no sudo).
- **Upgrade from before 1.7.0:** after updating, run `bash scripts/ssh-config.sh` once so the
  existing admin alias receives the shared `IdentityAgent` entry. Connection fields are preserved.
- **Enabling is ALWAYS the user, NEVER you.** They run `bash scripts/fullpower.sh on` and type
  the passphrase. Never auto-load the key, never make it passphrase-less, never add it to
  ssh-agent on their behalf, never enable it "to save a step" (that removes the gate = INV-3).
- **Dedicated switch operations:** the plugin bundles two companion skills because current skill
  hosts expose each slash-invokable operation as an independent skill (there is no nested-skill
  metadata). Their UI labels group them under Luffy Arm. An explicit "turn on full power" request
  routes to the sibling
  `luffy-arm-fullpower-on` skill; "turn off full power" routes to
  `luffy-arm-fullpower-off`. ON checks host status first: an already-ON gate is reused without
  another passphrase prompt, and only verified OFF asks the user to run the ON command personally.
  If the same request includes a remote task, a verified-ON switch continues under this main
  skill. OFF may be run by the agent. It proves whether the dedicated key stopped authenticating,
  then separately reports any alternate credential that still reaches `ADMIN_USER`.
- **Use it:** while the dedicated gate is ON, `ssh <ADMIN_ALIAS> "<cmd>"` runs as
  `ADMIN_USER`. Confirm the identity and configured target-path write access with
  `bash scripts/verify-fullpower.sh`.
- **It lifts** the data-read-only net + INV-2 (you may now edit remote files). **Still holds:**
  INV-1 (brain local), INV-3 (passphrase/sudo are the user's), and the sudo password gate.
- **Close the dedicated gate when done:** `bash scripts/fullpower.sh off` (the key also expires
  after the TTL). If another key still reaches `ADMIN_USER`, OFF reports that effective user
  access remains and does **not** claim Safe Mode has returned.
- **Read the layered state literally:** `status` reports the dedicated credential gate
  (`ON`/`OFF`/`UNKNOWN`), the authenticated remote identity, and alternate non-interactive user
  access (`AVAILABLE`/`NOT FOUND`/`UNKNOWN`). Authentication as `ADMIN_USER` means commands run
  with that user's OS permissions; exact path write access and sudo must be verified separately.
  Never infer effective permissions from the key filename or gate state alone.
- **Sandbox evidence remains tri-state:** In a known sandboxed agent,
  request approved host execution directly instead of probing inside the sandbox first. If host
  execution is unavailable, report `UNKNOWN`; never infer a gate or capability state from
  `Operation not permitted`, network failure, or an inaccessible agent socket. A user-run
  normal-terminal check is the last fallback, not the default agent workflow.

## Optional: command auditing (opt-in — off by default)

If the user wants a record of **what the agent has actually run on the server** — the one
thing the *local* machine can't see inside `ssh <alias> "…"` — offer server-side auditing.
It's off until the user explicitly turns it on, and it's **detect, not prevent** (a fifth,
complementary layer on top of the four safety nets; it never blocks anything).

- **Turn on:** `bash scripts/gen-audit-setup.sh` (local, no secrets) emits
  `luffy-arm-audit-setup.sh`; the **user** copies it to the server and runs
  `bash luffy-arm-audit-setup.sh enable` with their own sudo. You do NOT run it (INV-3).
- **Read / off:** `bash luffy-arm-audit-setup.sh show [N]` lists recent audited commands;
  `… disable` removes it cleanly (past log entries are kept).
- **Scope:** only the safe-mode `cc` account is audited; full-power (login as the user) is
  never intercepted. Details + honest limits + an auditd alternative: `references/audit-logging.md`.

> **Human shortcut (not for you, the agent):** if the user ran `install.sh`, they may have a
> `luffy-arm` command on their PATH — or its shorter `luffy` alias — (`luffy-arm fullpower on`,
> `luffy verify`, `luffy-arm audit-gen`, …) that simply forwards to these same `scripts/*.sh`.
> **You** should keep calling the scripts by path — it's PATH-independent and unambiguous. The
> command exists for the human.

## Common mistakes
- Agent key has a passphrase → non-interactive login fails. It **must** be passphrase-less.
- Full-power status says `UNKNOWN` in a sandbox → this is not OFF. Retry with approved host
  execution; only explicit authentication denial proves OFF.
- Dedicated gate says `OFF`, but `EFFECTIVE USER ACCESS: AVAILABLE` → an alternate key reaches
  the same `ADMIN_USER`. The agent has that user's effective permissions; do not call this Safe
  Mode or pause merely to re-arm the dedicated key.
- Other failures: `references/setup-guide.md` → Troubleshooting.
