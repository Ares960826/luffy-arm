# luffy-arm — the complete tutorial

Zero to a working remote hand, assuming **no prior SSH experience**. By the end, your local
Claude Code will read data and run commands on a remote Linux server — safely — while its
brain never leaves your machine.

- **Time:** ~15 minutes.
- **Two places:** 💻 your **LOCAL** machine, and 🖥 the **SERVER**.
- **The deal:** the agent does the fiddly local setup for you (after asking); *you* run a few
  one-time commands on the server (that needs your password — by design).

---

## 0. Will this work for me? (prerequisites)

You need:

1. **A local machine running Claude Code** (macOS or Linux; on Windows use WSL).
2. **A remote Linux server you can log into**, and the username you use there.
3. On that server, the ability to **`sudo`** — yourself, or a colleague who can run 4
   commands for you once.
4. **`ssh` on your local machine** (built in on macOS/Linux). Check:
   ```bash
   ssh -V        # prints e.g. OpenSSH_9.x ...
   ```

> **Never used SSH?** SSH is just a secure way to run commands on another computer over the
> network: you type `ssh name@server` and you're in that machine's terminal. That's all we
> use here — and the agent sets it up for you.

**Do you actually have access to the server yet?** Test it (use your real values):
```bash
ssh youruser@your.server.ip "echo it-works"
```
- Prints `it-works` → ready. ✅
- Asks for a **password** → fine, you have access. (luffy-arm switches the *agent* to a key;
  your own login can stay as-is.)
- `Connection refused` / `timeout` / `could not resolve hostname` → you don't have network or
  account access yet. Sort that with whoever owns the server first — getting an account is
  outside luffy-arm's scope.

---

## 1. The mental model (1 minute)

```
💻 LOCAL (your machine)                          🖥 SERVER (the remote box)
┌────────────────────────────┐                  ┌──────────────────────────┐
│ Claude Code = the brain     │  ssh (luffy-arm)  │ cc = a restricted guest  │
│ stays here, always          │ ───────────────▶ │ reads your data          │
│ ~/.ssh/luffy-arm-key         │                  │ writes only in WORK_DIRS │
└────────────────────────────┘                  └──────────────────────────┘
```

- Your data never moves. `cc` is a new, restricted account on the **same** server — like a
  guest key that only opens certain doors, read-only.
- Four safety nets keep it safe: sudo password gate · data read-only · per-project version
  control · your local copy is the source of truth. (Details: `references/security-model.md`.)

**Who does what:**

| The agent does (💻 local, after you say OK) | You do (🖥 server, once) |
|---|---|
| make the SSH key, write `~/.ssh/config`, verify, then read/run on the server | run 4 commands it hands you (create `cc`, install the key, grant read access) |

The agent never types your password and never runs the server's admin commands — it writes
them out for you to paste. That boundary is the point.

---

## 2. Install luffy-arm

```bash
git clone https://github.com/Ares960826/luffy-arm ~/.claude/skills/luffy-arm
```

Claude Code auto-discovers skills in `~/.claude/skills/`. Next time you mention reaching a
remote server, the `luffy-arm` skill kicks in.

---

## 3. The easy path: let the agent drive

Open Claude Code and say:

> "Use luffy-arm to set up access to my server `your.server.ip`, my login is `youruser`."

The agent will ask what to read/write, write your params file, ask permission and make the
key + ssh config, hand you the server commands to paste, then verify. Want to understand each
step (or do it without the agent)? The manual path below is the exact same thing.

---

## 4. The manual path, step by step

### 4.1 — Tell luffy-arm about your server

```bash
mkdir -p ~/.config/luffy-arm
cp ~/.claude/skills/luffy-arm/scripts/params.example.sh ~/.config/luffy-arm/params.sh
${EDITOR:-nano} ~/.config/luffy-arm/params.sh
```
Fill these (the rest can stay default):
```bash
export SERVER="your.server.ip"            # the server's IP or hostname
export ADMIN_USER="youruser"              # YOUR login on the server
export HOST_ALIAS="mybox"                 # any nickname you like
export READ_ROOTS=( "/home/youruser" )    # what the agent may READ (add "/data" etc.)
export WORK_DIRS=( )                       # what it may WRITE (empty = fully read-only)
```
> This file holds your real values and **never** goes into the repo (it's git-ignored).

### 4.2 — Make the agent's key (💻 LOCAL)

```bash
bash ~/.claude/skills/luffy-arm/scripts/keygen.sh
```
Creates `~/.ssh/luffy-arm-key` (passphrase-less, so the agent can log in automatically) and
prints a line starting `ssh-ed25519 AAAA…`. **Copy that whole line** — it's the *public* key
you install on the server next.

### 4.3 — Name the connection (💻 LOCAL)

```bash
bash ~/.claude/skills/luffy-arm/scripts/ssh-config.sh
```
Adds a short block to `~/.ssh/config` so you can type `ssh mybox`, and reuses one connection
for speed.

### 4.4 — Set up the server side (🖥 SERVER — you, once)

Log in as yourself:
```bash
ssh youruser@your.server.ip
```
> First time it may ask "continue connecting? (yes)" and your password — both normal. You're
> now in the server's terminal.

Run the commands from [`references/server-setup.md`](references/server-setup.md) (the agent
fills them in for you). They: **(1)** create the `cc` account, **(2)** install the public key
you copied, **(3)** grant `cc` read-only on your `READ_ROOTS` and carve out your secrets,
**(4)** optionally add a writable work dir. Then `exit`.

> Why you run these, not the agent: they need `sudo`. Keeping `sudo` (your password) in your
> hands is exactly the safety boundary — the agent never holds it.

### 4.5 — Verify (💻 LOCAL)

```bash
bash ~/.claude/skills/luffy-arm/scripts/verify.sh
```
Expected ending:
```
passed 9 / failed 0
🎉 all passed
```
That confirms: passwordless login, connection reuse, the agent can **read** your data but
**not write** it, the work dir is writable, `sudo` is blocked, and your brain is local. Any
❌ → see Troubleshooting.

---

## 5. Use it day to day

Just ask Claude Code, e.g.:
- "luffy-arm: what's the GPU usage on the server right now?"
- "read `/data/experiments/run42/metrics.json` from the server and summarize it"
- "run `python train.py` on the server and tail the log"

The agent reaches in over `ssh mybox "…"`. It's **read-only** everywhere except your
`WORK_DIRS`, and it will **not** edit source files on the server — by design you edit locally
and sync, so your local copy stays the source of truth.

---

## 6. Maintenance

- **Read a new folder:**
  ```bash
  bash ~/.claude/skills/luffy-arm/scripts/grant.sh ro /absolute/new/path
  ```
  Prints server commands (with secret carve-out) to paste; then add the path to `READ_ROOTS`
  in your params. (Files added *under* an already-granted folder need nothing.)
- **Write a new folder:** `grant.sh rw /absolute/new/path` → paste → add to `WORK_DIRS`.
- **New laptop:** install the skill, write a fresh `params.sh`, re-run keygen / ssh-config /
  verify. The server side is unchanged.

---

## 7. Troubleshooting

| Symptom | Fix |
|---|---|
| `Permission denied (publickey)` even though fingerprints match | The agent key has a passphrase. It must be passphrase-less: `rm ~/.ssh/luffy-arm-key*; bash …/keygen.sh`, then reinstall the new public key. |
| Step 4.5 still asks for a password | Public key not installed right (redo 4.4), or key perms: `chmod 600 ~/.ssh/luffy-arm-key`. |
| "read-only root can't read" | The `setfacl … -d` step (4.4 part 3) was missed; `getfacl <dir>` should show `user:cc:r-x`. |
| "work dir write denied" | That path isn't in `WORK_DIRS`, or part 4 was skipped. |
| `setfacl: command not found` on the server | `sudo apt-get install -y acl` (Debian/Ubuntu; use your distro's package elsewhere). |
| Want to know *why* the server rejected login | See the LogLevel DEBUG1 recipe in `references/setup-guide.md`. |

---

## 8. What luffy-arm can and can't do

- ✅ **Can:** read your data, run commands, inspect logs, diagnose — on the server.
- 🚫 **Can't (by design):** write outside `WORK_DIRS`, run `sudo`, touch your passwords, or
  move itself / its config onto the server.
- 🔭 **Later (v2):** opt-in *full-power mode* — log in as yourself for full read/write, gated
  by a passphrase you type. Not in this version.

---

## 9. Uninstall / undo

**Local:**
```bash
rm -rf ~/.claude/skills/luffy-arm
rm -f ~/.ssh/luffy-arm-key ~/.ssh/luffy-arm-key.pub
# remove the "Host mybox" block from ~/.ssh/config (open it in an editor)
rm -rf ~/.config/luffy-arm
```
**Server (as yourself):**
```bash
sudo deluser --remove-home cc            # remove the cc account (its ACLs go with it)
# or, to only revoke access: sudo setfacl -R -x u:cc <READ_ROOT>
```

---

That's the whole loop: **brain home, hand remote.** Rough edges or questions → open an issue.
