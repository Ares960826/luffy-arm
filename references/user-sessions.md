# User-authenticated sessions

An existing account can be used without creating `cc` or registering a new key.
The human opens a per-target SSH connection in a local terminal and types the
account password into OpenSSH. SSH then detaches into the background; an agent
reuses the authenticated connection even after that terminal closes.
The password is never a command argument, environment variable or saved value.
This optional path requires local Python 3 and OpenSSH; no remote install or sudo.

## One-time local target configuration

Use the common registration command described in [targets.md](targets.md):

```bash
luffy target add my-server --password --host server.example.org --user your-account --name "My server"
luffy tlist
```

Use separate IDs for separate servers. Profiles store login mode and display name
alongside host/user/port; older three-field profiles remain valid. Omitting `--password`
on ON prints the target's corrected command and exits without opening a connection
or changing an existing session. Passwords themselves are never stored in profiles.
Actual credentials and server-specific operating rules do not belong in this file.
Establish the server's host key through an independently verified fingerprint first.
The session commands use strict host checking and never add unknown keys automatically.
This first version supports direct SSH hosts; it does not inherit SSH config aliases,
ProxyJump or other per-host configuration. Key targets use their registered params/SSH aliases.

## Daily use

The **human**, in a local terminal:

```bash
luffy fullpower on my-server --password
luffy fullpower on my-server --password 120000
luffy fullpower status my-server
luffy fullpower off my-server
```

`luffy-arm` accepts the same arguments as `luffy`. `--password` is an ordinary flag
that selects SSH password/keyboard-interactive authentication, including any
server-provided challenges. It does not accept a password value. OpenSSH's native
`-f` option backgrounds the connection only after authentication. The command
reports `SESSION ON | background` after verifying the Unix user, then returns the
shell prompt. The terminal may close. Untimed sessions have no Python supervisor;
an explicit duration adds one local expiry timer that exits with the session.
Use OFF to end it. A broken connection is never automatically reauthenticated.
An existing verified session is reused without another password, new process or
lifetime renewal. The output explicitly distinguishes reuse from fresh login.

Without a target, the CLI uses the selected registered default (any login mode).
Use `luffy target default TARGET` to select it. Explicit IDs never fall back to
another target. Duration-only target names are reserved. Password sessions without
a duration last until OFF/disconnect; with one they expire after that elapsed number
of seconds. Status shows remaining time/deadline. See [targets.md](targets.md).
Key targets retain their ssh-agent TTL. Repeated ON no longer reloads a
loaded key or silently resets its TTL, even when a different duration is supplied.
Choose a new duration with an explicit OFF followed by ON. Failed verification of
a loaded key reports UNKNOWN rather than reloading it.

An old foreground/external connection is reused in place and identified as such;
it is not silently converted or restarted. To migrate, close that target and
run the new ON command once, typing the password personally.

The **agent**, after its server skill selects the target, calls the installed script:

```bash
python3 /path/to/luffy-arm/scripts/session.py status my-server
python3 /path/to/luffy-arm/scripts/session.py run my-server 'pwd'
```

`run` verifies identity, then executes the task-authorized shell command using only
that target's socket. With no socket, wrong identity or broken connection, it fails
without another authentication attempt. Agent actions require normal task authorization;
opening the connection is not blanket permission to write, delete or submit jobs.
Host execution is still needed when the agent's sandbox blocks the control socket.

Close the selected session with `luffy fullpower off my-server`. Other targets' sessions
and credentials are not modified. Closure may interrupt foreground commands/transfers
using the connection; it sends no cancellation to independent remote jobs and
does not revoke any other login path to the same account. Open multiplexed channels
may take time to drain; if the socket remains, OFF reports unverified closure.

## All-target status and shutdown

```bash
luffy fullpower status --all
luffy fullpower off --all
```

All-target OFF closes each registered session through its exact control socket,
including a session whose target profile was subsequently edited or removed. It
also closes each registered key target's safe master and removes its dedicated
Full Power key, once per params file, using the verified OFF operation. It does not kill a
shared ssh-agent, delete unrelated keys, scan/kill arbitrary SSH processes or
cancel remote jobs. Alternate credentials remain visible in the key-gate report.
Failure of one target does not hide or prevent cleanup of the others; incomplete
closure returns nonzero and retains its record for retry. A broken remote network
does not prevent trying the local socket's exit command.

Kernel locks serialize each target's login, and all-target OFF excludes new ON
operations during shutdown. If a user is still entering a password, finish or
cancel that prompt before retrying shutdown. Lock files are harmless fixed metadata,
not running processes; the OS releases their locks on exit or crash. Successful
OFF and the next ON remove owned stale records/empty socket directories. The
keepalive policy ends an unresponsive SSH connection; no reconnect loop is used.
`LUFFY_ARM_STATE_DIR` may isolate the lifecycle/target state directory for testing;
its default is `~/.config/luffy-arm`. It does not change `LUFFY_ARM_PARAMS`.

For migration only, an explicitly selected user-authenticated socket can be registered:

```bash
python3 /path/to/luffy-arm/scripts/session.py attach my-server --socket /absolute/private/control
```

Only attach a socket whose target was established by the user. The socket and parent
directory must belong to the current OS user; the directory must have mode 700.
The socket's remote Unix identity is checked. Socket reuse cannot redo the original
host-key exchange; this command does not independently prove which host created a socket.
An attached session remains owned by its original launcher. OFF explicitly closes it;
simply registering it does not open, close or reauthenticate it.

## Permission and lifecycle boundaries

The account's actual OS permissions apply. The shared `fullpower` command name does
not turn a password session into `cc` ACL isolation or a dedicated key gate.
A personal account session can have personal-account write access even
when the agent is instructed to operate read-only. No sudo privileges are inferred.
The master socket permits reuse by other processes running as the same local OS user;
it is not isolation between agents under that user.

Target records are held under `~/.config/luffy-arm/sessions/`, with locks preventing
competing ON operations for one target. Each newly opened session has its own private,
random temporary socket directory. A changed target profile is not silently applied to
an old connection. OFF/no record is scoped to this entry point, never to all account access.
Interrupted or failed login removes its own record. No project-specific scheduler,
server addresses, usernames or institution rules are shipped in the product.
