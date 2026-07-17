# luffy-arm — setup guide (quick reference)

> Terse step checklist + deep troubleshooting. **New to this? Read `TUTORIAL.md` instead —
> it assumes nothing.** Every command is marked **💻 LOCAL** (your machine) or **🖥 SERVER**
> (the remote box). Values in `<ANGLE>` come from your `params.sh`.

Mental model & safety nets: `TUTORIAL.md` §1 · `references/security-model.md`.

## Prep checklist

- [ ] Server IP/host + SSH port (default 22)
- [ ] Your own account on the server, and it can `sudo`
- [ ] Server is Linux with ACL support (ext4/xfs have it; step 3 checks)
- [ ] You filled in `~/.config/luffy-arm/params.sh` (copy from `scripts/params.example.sh`)

---

# Part 1 — 💻 LOCAL

## Step 1 — confirm params

Open `~/.config/luffy-arm/params.sh` and check `SERVER`, `CC_USER` (default `cc`),
`ADMIN_USER`, `HOST_ALIAS`, `READ_ROOTS`, `WORK_DIRS`. Add/change paths by editing the
arrays (one per line). All scripts pick the changes up automatically.

## Step 2 — generate the agent's key (passphrase-less)

```bash
# 💻 LOCAL
bash scripts/keygen.sh
```
It prints a line `ssh-ed25519 AAAA…` — that's the **public** key; keep it for step 4.
(The private key is passphrase-less on purpose so the agent can log in non-interactively.)

---

# Part 2 — 🖥 SERVER

> Steps 3–6 run **ON THE SERVER** — use the single copy-pasteable block in
> `references/server-setup.md` (1 create `cc` · 2 install pubkey · 3 read ACLs + secret
> carve-out · 4 optional work dir). Log in as yourself first:
> `ssh <YOUR_OWN_USERNAME>@<SERVER_IP>`.

## Step 3 — create the read-only `cc` account
Why: a separate user outside any shared writable group makes write-protection airtight
and free.

## Step 4 — install the public key for `cc`
Why: after this, the agent can log in as `cc` without a password.

## Step 5 — grant read-only on your data
Why: the default ACL (`-d`) makes future files auto-inherit (handles growing paths).
Then **carve secrets back out** (`READ_EXCLUDES` — the real protection): fail-open —
list generously; see `references/security-model.md`.

## Step 6 — grant write on a work area (optional)
Why: `WORK_DIRS` are the agent's only writable area. Version control is **not** pre-set —
`git`/`jj` init individual projects when you want rollback. Then `exit` back to LOCAL.

---

# Part 3 — 💻 back LOCAL

## Step 7 — name the connection + verify passwordless login
```bash
# 💻 LOCAL
bash scripts/ssh-config.sh
ssh <SSH_ALIAS> "whoami; hostname"
```
**Expect:** no password prompt, prints `cc` and the server hostname → channel is up 🎉.
(If it asks for a password or errors, see Troubleshooting.)

## Step 8 — verify the safety nets
```bash
# 💻 LOCAL
bash scripts/verify.sh
```
**Expect:** `🎉 all passed` — login, ControlMaster, read-only roots readable / writes
denied, work dir writable, sudo gate, local brain present.

---

# Maintenance

**Read a new directory** (backfill the whitelist):
```bash
# 💻 LOCAL — prints the server commands (with secret carve-out); you run them on the server
bash scripts/grant.sh ro /absolute/new/path
```
Then append the path to `READ_ROOTS` in your `params.sh`. Files added under an
already-granted root need nothing — the default ACL covers them (the source of
day-to-day zero maintenance).

**Write in a new directory:** `bash scripts/grant.sh rw /absolute/new/path` → run printed
commands → append to `WORK_DIRS`.

**New machine:** copy the repo, fill in a fresh `params.sh`, re-run steps 2, 7, 8. The
server side (steps 3–6) is unchanged unless you switch servers.

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Permission denied (publickey)` **even though the fingerprint matches** | The agent key has a **passphrase** → non-interactive auth can't sign. Test: `ssh-keygen -y -P '' -f <KEY>` (error = has passphrase). Fix: `rm <KEY>*; bash scripts/keygen.sh` (regenerates passphrase-less), reinstall the new pubkey on the server. The agent key **must** be passphrase-less. |
| Login rejected, suspect wrong key installed | Compare fingerprints: LOCAL `ssh-keygen -lf <KEY>.pub` vs SERVER `sudo ssh-keygen -lf /home/<CC_USER>/.ssh/authorized_keys` — must match exactly. (Common slip: pasting the wrong key.) |
| Want to know **why** sshd rejected | Temporary verbose log: `echo 'LogLevel DEBUG1' \| sudo tee /etc/ssh/sshd_config.d/99-debug.conf; sudo sshd -t && sudo systemctl reload ssh`. Log in once, then `sudo journalctl -u ssh \| tail -40` (look for `Accepted`/`Failed publickey`). Remove the file + reload to restore. |
| Alt debug port (e.g. 2222) unreachable | Lab firewalls often allow only 22; use the LogLevel method above instead of `sshd -d` on another port. |
| Step 7 still asks for a password | Pubkey not installed right (redo step 4), or key perms wrong (`chmod 600 <KEY>`). |
| Read-only root "can't read" | Step 5 ACL didn't apply; `getfacl <READ_ROOT>` should show `user:<CC_USER>:r-x`. |
| Work dir "write denied" | Step 6 missed, or path not in `WORK_DIRS`. |
| `setfacl: command not found` | Server lacks `acl` (install it, step 5). |
