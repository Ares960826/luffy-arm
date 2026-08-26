# luffy-arm — security model

Exactly what protects you when a local agent's SSH arm reaches into your server.

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

> Full-power mode is a deliberate opt-in exception — see §Full-power mode below.

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

**Optional fifth layer — 📓 command auditing (opt-in, off by default).** A server-side
`sshd` `ForceCommand` wrapper (scoped to `cc` only) logs every `ssh <alias> "<cmd>"` into the
root-owned system journal, so you have a tamper-evident record of what the agent ran. This is
**detect, not prevent** — accountability on top of the four preventing nets, not a wall. Turn
it on/off with `scripts/gen-audit-setup.sh`; full mechanism and honest limits in
`references/audit-logging.md`.

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

**How the carve-out is enforced (matters — a subtle trap).** Each `READ_EXCLUDES`
entry is applied as an **explicit deny** — `setfacl -m u:cc:---` — not as a *removed
grant* (`setfacl -x u:cc`). The difference bites on **world-readable** secret dirs
(mode `o+r`, common for `.claude`, `.claude-mem`, `.agents`, …): merely removing cc's
ACL entry lets it **fall back to the "other" read bit**, so `-x` silently fails to hide
them. A named-user entry (`u:cc:---`) is checked **before** "other", so it denies cc
even when everyone else can read. If you ever hand-write an exclusion, use `-m
u:cc:---`, never `-x`.

## The unavoidable blind spot (important)

No **local** guardrail can see inside `ssh server "…"` — the remote command is an
opaque string to your machine. So **remote safety can only live server-side** (the
four nets above). Don't rely on local hooks to police what runs on the server, and
don't try to parse ssh command strings locally (evaluated and rejected as
over-engineering). If you want *visibility* into that opaque string, the answer is
also server-side: the opt-in command auditing above logs it where it becomes visible
(on the server), never on your machine.

## Full-power mode (opt-in; dedicated credential gate off by default)

Sometimes you *want* the agent to edit/write as yourself, not just read. Full-power mode does
that as a deliberate, narrow exception:

- **How the dedicated gate works:** a *separate* admin key **with a passphrase** logs you in as
  `ADMIN_USER` (you). `scripts/fullpower.sh on` loads it into ssh-agent — **you type the
  passphrase** (INV-3 holds) — and `off` removes it. The generated admin alias selects that public
  key with `IdentitiesOnly yes`, and the key auto-expires after `FULLPOWER_TTL` (default 1h).
  The alias is deliberately NOT connection-multiplexed, so no cached connection can outlive the
  key TTL. This controls the luffy-arm admin credential only. SSH options can admit other agent
  keys, and any such key accepted for the same `ADMIN_USER` reaches the same Unix identity and
  is not a lower permission tier.
- **Cross-conversation agent reference:** ON creates a symlink at
  `~/.config/luffy-arm/fullpower-agent.sock` to the user's current ssh-agent socket and the admin
  alias uses it through `IdentityAgent`. This avoids process-local `SSH_AUTH_SOCK` drift between
  conversations. The containing directory is mode `0700`; neither private-key material nor the
  passphrase is copied. OFF removes the admin key from that agent, and TTL expiry still removes it
  automatically. The inert socket reference may remain so later status checks can verify explicit
  authentication denial. If that agent also contains a personal key accepted for `ADMIN_USER`,
  `IdentitiesOnly=no` can still provide user-level access; the socket is then a route to that other
  credential, not an independent permission grant.
- **Identity and permissions:** a successful probe records the actual remote identity. Commands
  authenticated as `ADMIN_USER` receive that user's OS permissions regardless of which accepted
  key was used. Exact write access is path-specific, and sudo remains separately password-gated;
  verify both at the target instead of inferring them from a key name.
- **What user-level access lifts:** the safe account's *data read-only* net no longer applies
  because commands are no longer running as `cc`. INV-2 may be lifted only when the user has
  explicitly authorized the full-power workflow.
- **What still holds:** the **sudo password gate** (root still needs your password), your
  **local authoritative copy**, **INV-3** (passphrase + sudo password are typed by you, never
  the agent), and **INV-1** (the brain stays local).
- **Enable:** `admin-keygen.sh` (make the passphrased key — an empty passphrase is rejected)
  → install its pubkey under your own account (server-setup.md step 5) → `fullpower.sh on` →
  `verify-fullpower.sh`. Close with `fullpower.sh off`.
- **Intent-shaped switches:** the installer also exposes `luffy-arm-fullpower-on` and
  `luffy-arm-fullpower-off` as companion skills. Current skill hosts have no parent/sub-skill
  metadata, so UI labels group them under Luffy Arm while retaining independent invocation. They
  delegate to the same `fullpower.sh`; ON remains a command the user runs personally, while OFF
  may be invoked by the agent.
- **Layered evidence:** status reports four distinct facts: configured `ADMIN_USER`, dedicated
  credential gate (`ON`/`OFF`/`UNKNOWN`), authenticated remote identity, and alternate effective
  user access with `IdentitiesOnly=no` (`AVAILABLE`/`NOT FOUND`/`UNKNOWN`). Dedicated gate OFF
  never proves user-level capability is absent. An inaccessible ssh-agent, sandbox denial, or
  network failure proves neither and is reported as `UNKNOWN`. In a known sandboxed agent,
  request narrowly scoped host execution from the first probe.
- **Not for** multi-tenant / low-trust boxes — same caveat as the read model above.

## Non-goals

- Not a multi-tenant / hostile-server hardening kit.
- Not a secrets manager.
- The dedicated Full Power credential is opt-in and its gate is off by default (see above).
