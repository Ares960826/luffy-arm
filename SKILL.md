---
name: tentacle
description: Use when a local AI agent needs to reach into a remote Linux server over SSH — to explore data, run commands, inspect logs, or diagnose something on the server — or to set up that SSH access for the first time. Triggers include "connect to my server", "ssh into the remote box", "explore/poke around the server", "run this on the server", "set up remote access", "reverse remote-ssh", 远程服务器, 远程开发. Not for purely local work, and not for moving the agent or its config onto the server.
---

# tentacle

Give a **local** agent a **remote hand**: the agent's brain (process, config, memory)
stays on this machine; an SSH "tentacle" reaches into a remote Linux server to **read,
run, and diagnose** — never to rewrite. Native parts only (SSH keys, ssh config,
ControlMaster, POSIX ACLs). The agent logs in as a non-privileged `cc` account.

## When to use
- Inspect data / run a command / read logs / reproduce something **on a server**.
- **Set up** that local-agent→server SSH channel for the first time.

Not for: purely local tasks; running the agent itself on the server; cloud/remote-control.

## Which mode am I in?
- `ssh <alias>` already works (Host in `~/.ssh/config`; `ssh -O check <alias>` ok) → **USE mode**.
- Otherwise → **INSTALL mode** (set it up first).

## Invariants you MUST hold

**Violating the letter of these is violating the spirit.** They hold in default (safe)
mode; full-power mode is a separate opt-in that does not exist in this version.

- **INV-1 — brain stays local.** Never install the agent on the server or copy `~/.claude`
  (it holds credentials + MCP secrets) there. Fix lag with ControlMaster, not by moving.
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
| "Just hotfix the file directly over ssh, no reason to re-upload" | That's editing remote source (INV-2). Edit locally + sync; the server copy is not authoritative. |
| "We're in a hurry / it's only one line" | Urgency doesn't change which copy is the truth. Still local-then-sync. |
| "I have ssh+sudo, I'll just run adduser/setfacl myself" | Server-root is the user's, gated by their password (INV-3). Print the commands; let them run them. |
| "Copy ~/.claude up so it behaves the same on the server" | Leaks credentials + breaks INV-1. Use ControlMaster for speed instead. |
| "Embed the password/passphrase so it runs unattended" | Never (INV-3). Use a passphrase-less dedicated key + the user's interactive sudo. |

**Red flags — STOP:** about to run `sed -i` / `vim` / `tee` / `>` on a remote path · about
to `sudo` (or `ssh "... sudo ..."`) for adduser/setfacl/authorized_keys · about to `scp`
`~/.claude` or install the agent on the server · about to put a secret in a command.

## USE mode (channel exists)

Reach in over the alias. Default is **read-only**; only `WORK_DIRS` are writable.

| Want | Do |
|---|---|
| run a command / explore | `ssh <alias> "<cmd>"` |
| check the multiplexed connection | `ssh -O check <alias>` |
| read a file | `ssh <alias> "cat <path>"` |
| grant a new read/write dir | `bash scripts/grant.sh ro\|rw <path>` → user runs the printed server cmds |

Source edits happen **locally**; sync up only into `WORK_DIRS` when needed.

## INSTALL mode (set the channel up)

Treat the user as a first-timer — **assume nothing is configured.** Run scripts from this
skill's directory. The complete human walkthrough is `TUTORIAL.md` — point them to it.

1. **Reachability first.** Confirm the user can already `ssh <their-user>@<server>` (or has
   an account they can get). If they can't reach the server at all, help with that before
   anything else — don't proceed without it.
2. **Params — gather by asking, then write the file.** Ask for: server IP/host, their server
   username, an alias nickname, which dirs to read, which (if any) to write. **Write those
   into `~/.config/tentacle/params.sh` yourself** (template: `scripts/params.example.sh`).
   Don't make the user hand-edit unless they prefer to.
3. **Local — ask permission first** (these touch `~/.ssh`): run `bash scripts/keygen.sh`
   (prints the public key) then `bash scripts/ssh-config.sh`.
4. **Server — the USER runs it (you must NOT):** present the filled-in commands from
   `references/server-setup.md` (create `cc`, paste the pubkey, set ACLs); they run them on
   the server with their own sudo.
5. **Verify:** `bash scripts/verify.sh` → expect `🎉 all passed`.

Human walkthrough: `TUTORIAL.md`. Quick steps: `references/setup-guide.md`. Why it's safe:
`references/security-model.md`.

## Common mistakes
- Agent key has a passphrase → non-interactive login fails. It **must** be passphrase-less.
- Wrong pubkey installed → compare fingerprints (`ssh-keygen -lf`) on both ends.
- Read-only root unreadable → the `setfacl` default-ACL (`-d`) step was missed.
