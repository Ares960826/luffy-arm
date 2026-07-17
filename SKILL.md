---
name: luffy-arm
version: 1.2.0
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

Source edits happen **locally**; sync up only into `WORK_DIRS` when needed.

## INSTALL mode (set the channel up)

Treat the user as a first-timer — **assume nothing is configured.** Run scripts from this
skill's directory.

1. **Reachability first.** Confirm the user can already `ssh <their-user>@<server>` (or has
   an account they can get). If they can't reach the server at all, help with that before
   anything else — don't proceed without it.
2. **Params — gather by asking, then write the file.** Ask for: server IP/host, their server
   username, an alias nickname, which dirs to read, which (if any) to write. **Write those
   into `~/.config/luffy-arm/params.sh` yourself** (template: `scripts/params.example.sh`).
   Don't make the user hand-edit unless they prefer to.
3. **Local — ask permission first** (these touch `~/.ssh`): run `bash scripts/keygen.sh`
   (prints the public key) then `bash scripts/ssh-config.sh`.
4. **Server — the USER runs it (you must NOT):** present the filled-in commands from
   `references/server-setup.md` (create `cc`, paste the pubkey, set ACLs); they run them on
   the server with their own sudo.
5. **Verify:** `bash scripts/verify.sh` → expect `🎉 all passed`.

Human walkthrough: `TUTORIAL.md`. Quick steps: `references/setup-guide.md`. Why it's safe:
`references/security-model.md`.

## Full-power mode (opt-in — only when the user wants write-as-themselves)

Default is safe mode (read-only `cc`). If the user **explicitly** wants the agent to
edit/write **as themselves**, full-power mode is available — treat it as a loaded gun:

- **The user enables it, not you.** They run `bash scripts/fullpower.sh on` and type the admin
  key **passphrase** — you never see, ask for, or embed it (INV-3). One-time setup:
  TUTORIAL §8 / `references/server-setup.md` step 5.
- **Use it:** while ON, `ssh <ADMIN_ALIAS> "<cmd>"` runs as the user with full read/write.
  Confirm with `bash scripts/verify-fullpower.sh`.
- **It lifts** the data-read-only net + INV-2 (you may now edit remote files). **Still holds:**
  INV-1 (brain local), INV-3 (passphrase/sudo are the user's), and the sudo password gate.
- **Close it when done:** `bash scripts/fullpower.sh off` (it also auto-expires after the TTL).

## Common mistakes
- Agent key has a passphrase → non-interactive login fails. It **must** be passphrase-less.
- Other failures: `references/setup-guide.md` → Troubleshooting.
