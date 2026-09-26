# Targets and command grammar

All servers use one registry and the same ON/OFF/status commands. Authentication
is a property of a target, not a special server name.

## Register once

```bash
luffy target add my-lab --params ~/.config/luffy-arm/params.sh --name "My lab"
luffy target add my-cluster --password --host login.example.org --user my-account --name "My cluster"
luffy tlist
luffy target default my-lab
```

Registration is local only; it never logs in, loads keys or changes the server.
Password registration supports `--port` (default 22). Key registration reuses an
existing Luffy key setup: host, port, user, key and aliases come from the supplied
trusted local shell params file. Each key target needs distinct params and a
dedicated key; duplicate registrations of the same key/params are rejected.
Later changes to the params' host/user/port cause a mismatch error, not a silent switch.

Repeated registration with the same settings is safe. An explicit `--name` may
update the display name; changing connection/authentication settings under an
existing ID is rejected. Password/passphrase values are never accepted or saved.
Owner-only profiles under `~/.config/luffy-arm/targets/` contain `auth` (`key` or
`password`), `name`, `host`, `user`, `port`, and key-only `params`. Older three-field
password profiles and their live sessions remain compatible.

`tlist` (also `target list`) lists IDs, names, modes, addresses and default **offline**.
It does not claim that a listed server is online. Live state uses `fullpower status --all`.
Unknown IDs point back to `tlist`. Any target can be selected as default. With
multiple targets and no default, omitted TARGET is an error, not a guess. A sole
target is selected automatically. Before any registration, legacy params-only key
commands still work with a migration hint; registered commands use the registry.

## Daily use

```bash
luffy fullpower on my-lab 120000
luffy fullpower on my-cluster --password 120000
luffy fullpower on my-cluster 120000 --password
luffy fullpower status my-lab
luffy fullpower status --all
luffy fullpower off my-cluster
luffy fullpower off --all
```

Both `luffy` and `luffy-arm` accept `fullpower on [TARGET] [DURATION] [--password]`.
TARGET precedes DURATION; the password flag can precede or follow the positionals.
Positive seconds and units (`2h`, `1h30m`) are supported. Invalid/zero/negative
durations, extra positionals, and ON-only flags on OFF/status fail before login.
`fullpower on 120000` uses the selected default target for 120000 seconds.
Missing `--password` on a password target prints a corrected command including
its duration. Passing `--password` to a key target is rejected.

Omitted duration preserves prior behavior: keys use `FULLPOWER_TTL` from params
(default 3600); password sessions stay up until OFF or disconnect. Duration means
elapsed lifetime, not idle timeout. Key TTL uses ssh-agent; password TTL starts
after identity verification and uses a detached local timer. A timed password
session has one timer; an untimed session has none. OFF/replacement makes it exit.
A generation check prevents an old timer from closing a new session with the same
ID. Expired password sessions reject new agent commands even if cleanup is delayed.
A paused/asleep computer cannot clean up until it resumes; failed closure remains visible.

Repeated ON neither duplicates a connection nor extends its expiry, even if a new
duration is supplied. To change duration, explicitly OFF then ON. Closure may
interrupt foreground commands/transfers using the connection; no cancellation
command is sent to independent background or scheduler jobs. Key expiry removes
that credential, not jobs or other credentials.

Agents use absolute paths: `python3 scripts/power.py status TARGET` / `off TARGET`.
Only the human runs ON interactively. Password command execution uses `session.py run`
as described in [user-sessions.md](user-sessions.md). Opening a connection does not
extend task authorization.
