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
| INV-1 | **Brain stays local** | Never copy the agent / its `~/.claude` config / memory to the server. (`~/.claude` holds credentials + MCP secrets — moving it leaks them.) |
| INV-2 | **Local is the source of truth** | On the server the agent only **reads / runs / diagnoses**. It does **not** edit remote source files. Edit locally, then sync. |
| INV-3 | **The agent never touches a password** | Login is by SSH key. `sudo` and every server-root action use a password **you** type. The agent never holds, embeds, or asks for a password or key passphrase. |

> Full-power mode (the agent logs in as your own account for full read/write) is an
> *opt-in* exception to INV-2 — **not part of v1.** It ships later, once verified.

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

## Non-goals (v1)

- Not a multi-tenant / hostile-server hardening kit.
- Not a secrets manager.
- Full-power (read/write as yourself) is deferred to a later version.
