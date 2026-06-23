# luffy-arm — security model

luffy-arm gives a **local** AI agent a **remote hand**: the agent's brain (process,
config, memory) never leaves your machine; only an SSH "arm" reaches into the
server to **read, run, and diagnose**. This file explains exactly what protects you.

## The metaphor → the rules

A rubber arm stretches out from a body that stays put. So:

- The **body/brain stays home** — we never move the agent or its config to the server.
- The luffy-arm has **a read-only touch by default** — it can feel around (read) and
  grasp tools (run commands), but it does **not** rewrite what it touches.
- A **reach limit** (the sudo password) stops it from triggering system-level changes.

## Three invariants

| # | Invariant | Meaning |
|---|-----------|---------|
| INV-1 | **Brain stays local** | Never copy the agent / its config dir (`~/.claude`, `~/.codex`, `~/.cursor`, `~/.config/opencode`) / memory to the server. (That dir holds credentials + MCP secrets — moving it leaks them.) |
| INV-2 | **Local is the source of truth** | On the server the agent only **reads / runs / diagnoses**. It does **not** edit remote source files. Edit locally, then sync. |
| INV-3 | **The agent never touches a password** | Login is by SSH key. `sudo` and every server-root action use a password **you** type. The agent never holds, embeds, or asks for a password or key passphrase. |

> **Full-power mode (opt-in, off by default)** lets the agent log in as your own account for
> full read/write — a deliberate exception that lifts INV-2 and the data-read-only net. It
> stays gated by a passphrase you type (INV-3 holds) and auto-disables after a TTL; the sudo
> gate and your local authoritative copy still apply. Details in "Full-power mode" below.

## Four safety nets (defense in depth)

1. **🔒 sudo password gate** — the agent's account (`cc`) is non-privileged; `sudo`
   needs a password only you know → system-level actions are blocked.
2. **👁 data read-only (ACL)** — `cc` gets a *read-only* ACL on your `READ_ROOTS`;
   sensitive subdirs (`READ_EXCLUDES`) are carved back out.
3. **♻ version control (per project)** — `WORK_DIRS` are the agent's writable area;
   you `git`/`jj` init the projects you want rollback on (not pre-set, to avoid
   snapshotting huge trees).
4. **🗄 local authoritative copy** — your local source is the ground truth and the
   ultimate backup.

## Why write-protection is basically free

`cc` is a **different user** and is removed from any shared writable group (e.g.
`users`). The OS therefore denies it write access to your files **for free** — you
don't configure write-protection, you simply never grant write. That's why the ACL
work is only about **granting read** (otherwise `cc` couldn't even enter your `0700`
home).

## What you actually defend: reads of secrets

Since writes are free and reads are broadly granted, the **one** thing to actively
prevent is `cc` *reading* your keys/tokens — that is `READ_EXCLUDES`. It is a
**blacklist → fail-open**: miss an entry and it stays readable. So **err toward more
entries**. On a single-user machine you trust the agent on, anything it reads only
flows back to your own local agent — inside your trust boundary. For a multi-tenant
or low-trust box this model is **not** sufficient; don't use it there.

## The unavoidable blind spot (important)

No **local** guardrail can see inside `ssh server "…"` — the remote command is an
opaque string to your machine. So **remote safety can only live server-side** (the
four nets above). Don't rely on local hooks to police what runs on the server, and
don't try to parse ssh command strings locally (evaluated and rejected as
over-engineering).

## Full-power mode (opt-in, off by default)

Sometimes you *want* the agent to edit/write as yourself, not just read. Full-power mode does
that as a deliberate, narrow exception:

- **How it works:** a *separate* admin key **with a passphrase** logs you in as `ADMIN_USER`
  (you). `scripts/fullpower.sh on` loads it into ssh-agent — **you type the passphrase**
  (INV-3 holds) — and `off` removes it. The admin ssh alias authenticates *only* while the key
  is loaded (its `IdentityFile` is the public key, so it's usable solely via the agent), and
  the key auto-expires after `FULLPOWER_TTL` (default 1h).
- **What it lifts:** the *data read-only* net and INV-2 (no editing remote source) — you now
  have full read/write as yourself.
- **What still holds:** the **sudo password gate** (root still needs your password), your
  **local authoritative copy**, **INV-3** (passphrase + sudo password are typed by you, never
  the agent), and **INV-1** (the brain stays local).
- **Enable:** `admin-keygen.sh` (make the passphrased key) → install its pubkey under your own
  account (server-setup.md step 5) → `fullpower.sh on` → `verify-fullpower.sh`. Close with
  `fullpower.sh off`.
- **Not for** multi-tenant / low-trust boxes — same caveat as the read model above.

## Non-goals

- Not a multi-tenant / hostile-server hardening kit.
- Not a secrets manager.
- Full-power (read/write as yourself) is **opt-in and off by default** (see above) — enable it
  deliberately, and not on multi-tenant/hostile boxes.
