# tentacle — server-side setup (🖥 runs on the SERVER, by YOU)

> These are the **privileged** steps. The AGENT does **not** run them — it generates a
> filled-in version of these commands for you, and **you** run them on the server with
> your own `sudo`. This preserves INV-3 (the agent never holds your password).
>
> Log in to the server as your own account first:
> ```bash
> ssh <YOUR_OWN_USERNAME>@<SERVER_IP>
> ```
> Placeholders come from your `params.sh`: `<CC_USER>` (default `cc`),
> `<READ_ROOT>` (each READ_ROOTS entry), `<WORK_DIR>` (each WORK_DIRS entry),
> `<EXCLUDE>` (each READ_EXCLUDES entry).

```bash
# === 1. Create the non-privileged agent account ===
sudo adduser --disabled-password --gecos "" <CC_USER>
sudo deluser <CC_USER> users 2>/dev/null || true   # leave shared writable group → cannot write your files
groups <CC_USER>                                    # confirm: no sudo; ideally just "<CC_USER> : <CC_USER>"

# === 2. Install the agent's PUBLIC key (the line printed by keygen.sh) ===
sudo install -d -m 700 -o <CC_USER> -g <CC_USER> /home/<CC_USER>/.ssh
echo 'ssh-ed25519 AAAA...paste the LOCAL tentacle_key.pub line... tentacle-cc' \
  | sudo tee /home/<CC_USER>/.ssh/authorized_keys
sudo chown <CC_USER>:<CC_USER> /home/<CC_USER>/.ssh/authorized_keys
sudo chmod 600 /home/<CC_USER>/.ssh/authorized_keys

# === 3. Read-only roots: recursive ACL + default ACL ===
which setfacl || sudo apt-get install -y acl     # other distros: use the matching package
for d in <READ_ROOT ...>; do
  sudo setfacl -R  -m u:<CC_USER>:rX "$d"
  sudo setfacl -R -d -m u:<CC_USER>:rX "$d"
done
# carve out secrets (THIS is the real protection — see security-model.md)
for s in <EXCLUDE ...>; do
  sudo setfacl -R  -x u:<CC_USER> "<READ_ROOT>/$s" 2>/dev/null || true
  sudo setfacl -R -d -x u:<CC_USER> "<READ_ROOT>/$s" 2>/dev/null || true
done

# === 4. Writable work dirs (optional) ===
for d in <WORK_DIR ...>; do
  sudo setfacl -R  -m u:<CC_USER>:rwX "$d"
  sudo setfacl -R -d -m u:<CC_USER>:rwX "$d"
done
# Version control is NOT set here — init git/jj inside individual projects when you want rollback.

exit   # back to your local machine; continue with ssh-config.sh + verify.sh
```

## What ACL does (one line)

Plain Unix permissions only cover owner/group/other; **ACLs** grant a *named user*
(`<CC_USER>`) its own permission, and the `-d` (default) rule is inherited by files
created **later** under that dir — so new/scattered paths stay readable without
re-granting. `rX` = read files + traverse directories (never sets execute on plain
files).
