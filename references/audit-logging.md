# luffy-arm — optional command auditing (🖥 server-side, opt-in)

> **Off by default. You turn it on when you want it, and off when you don't.**
> It answers one question the *local* machine physically cannot: **"what has the agent
> actually run on the server?"**

## The gap it closes

No **local** guardrail can see inside `ssh <alias> "…"` — the remote command is an opaque
string to your machine (see `security-model.md` → *the unavoidable blind spot*). The command
only becomes visible **on the server**, at the moment sshd hands it to a shell. So the audit
has to live there too.

When the agent runs `ssh <alias> "<cmd>"`, sshd exposes `<cmd>` as `$SSH_ORIGINAL_COMMAND`.
A one-file sshd `ForceCommand` wrapper — scoped to `Match User <CC_USER>` only — logs that
string via `logger` into the **system journal**, then execs the command transparently. The
journal is root-owned, so the unprivileged `cc` account **cannot erase its own trail**.

## Turn it on / off

Generate the server script locally (agent does this — no secrets, no sudo):

```bash
bash scripts/gen-audit-setup.sh          # emits ./luffy-arm-audit-setup.sh with CC_USER inlined
```

Copy it to the server and run it **as your own sudo-capable account** (it uses `sudo`
internally — *you* type the password; the agent never does, INV-3):

```bash
bash luffy-arm-audit-setup.sh enable      # turn auditing ON  (validates sshd, then reloads)
bash luffy-arm-audit-setup.sh show        # last 50 audited commands (show N for more)
bash luffy-arm-audit-setup.sh status      # ON/OFF + sshd config validity
bash luffy-arm-audit-setup.sh disable     # full clean removal (past log entries are kept)
```

`enable` appends a marked block at the **end** of `/etc/ssh/sshd_config` (so the `Match` block
can't bleed into unrelated config), backs the file up once to `sshd_config.luffy-arm.bak`,
runs `sshd -t` **before** reloading (a bad edit can never lock you out), and reloads sshd.
`disable` removes the block and the wrapper and reloads. Both are idempotent.

## Reading the log

```bash
bash luffy-arm-audit-setup.sh show 200            # via the script
sudo journalctl -t luffy-arm-cc --since today     # directly
```

Each line records the source IP (`$SSH_CONNECTION`), the account, and the exact command
string, e.g. `from=10.0.0.5 user=cc cmd=ls -la /data`.

## Honest limits (read before you rely on it)

- **Detect, not prevent.** This is an audit trail. The *preventing* is still done by the four
  safety nets (unprivileged account, ACL read-only, sudo gate, local authoritative copy).
  Auditing is a fifth, **complementary** layer — accountability, not a wall.
- **Complete for the agent's surface.** The agent acts via `ssh <alias> "<cmd>"`, which is
  always a command channel → always logged. Interactive logins are logged as
  `<interactive-login>`.
- **Command string, not every sub-process.** Running `bash deploy.sh` logs `bash deploy.sh`,
  not each line it executes. For process-level, kernel-tamper-evident coverage, use the
  **auditd alternative** below.
- **`cc` can add noise, not erase truth.** Without sudo, `cc` cannot delete journald entries,
  but it *can* call `logger` itself to inject lines. Timestamps and the journal's own metadata
  remain authoritative; deletion is what's prevented.
- **Safe mode only.** The wrapper is scoped to `Match User <CC_USER>`. **Full-power** logs you
  in as *yourself*, so it is deliberately never intercepted (audit your own account with your
  own tools if you want that).
- **File transfers.** `rsync` and legacy `scp -O` arrive as commands, run normally, and **are
  logged** (rsync as its `rsync --server …` invocation) — use these. Modern `scp` (OpenSSH 9+)
  uses the SFTP subsystem, and behaviour under `ForceCommand` depends on the server: with an
  external `sftp-server` (Debian/Ubuntu/RHEL default) it still works and logs; but with
  `internal-sftp` (common on hardened/chroot boxes) modern `scp` **fails outright**
  (`Connection closed`, exit 255) because the wrapper can't exec the subsystem. So while
  auditing is on, **prefer `rsync` or `scp -O`** — both work and log everywhere. The failure is
  loud (never silent data loss), transfers can't execute code, and they're ACL-bound regardless.
- **Not for multi-tenant / hostile boxes** — same caveat as the rest of the model.

## Alternative: auditd (kernel-level, tamper-evident)

If you want every `execve` (not just the ssh command string), and stronger tamper-resistance,
use the kernel audit subsystem instead of — or alongside — the wrapper:

```bash
# as root, once:  audit every process the cc account execs
CC_UID=$(id -u <CC_USER>)
echo "-a always,exit -F arch=b64 -F uid=$CC_UID -S execve -k luffy_arm_cc" \
  | sudo tee /etc/audit/rules.d/luffy-arm.rules
sudo augenrules --load        # or: sudo service auditd restart
sudo ausearch -k luffy_arm_cc # read it
```

Pure config, no wrapper script, and `cc` cannot touch the audit log at all. The cost is
verbosity (every sub-process, not one clean line per command) and the need for `auditd`
installed. Pick the wrapper for a readable command trail; pick auditd for forensic depth.
