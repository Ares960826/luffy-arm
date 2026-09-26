---
name: luffy-arm-fullpower-on
metadata:
  version: "1.8.0"
description: Use when the user explicitly asks to turn on, enable, open, or arm luffy-arm full-power mode, including "turn on full power", "enable full-power", 打开 full power, 开启全功率模式. Check layered host status first and reuse an already-ON dedicated gate; gate state and effective ADMIN_USER access are distinct. The agent never loads the key for them.
---

# luffy-arm full-power ON

This is the explicit ON companion operation for luffy-arm. Read the sibling `luffy-arm` skill's
**Full-power mode** section first; its invariants remain authoritative.

## Operation

If a registered target is selected, read the main skill's `references/targets.md`
and check `python3 scripts/power.py status TARGET` on the host. Only the human runs
`luffy fullpower on TARGET [DURATION] [--password]`; the password flag is required
only for password targets. Reuse ON without renewing expiry. Preserve the explicit
target; never fall back to the default key params. The default-key procedure below
is only for unregistered legacy setups or a deliberately selected default.

For an explicitly selected password-session target, read the main skill's
`references/user-sessions.md` and check `python3 scripts/session.py status TARGET`
on the host first. Reuse verified ON; UNKNOWN is not OFF. Only verified OFF calls
for the human to run `luffy fullpower on TARGET --password`. Never run ON for them.
Use that target throughout; skip the default key-gate procedure below. If several
targets are in scope and the intended target is unclear, ask which one first.
New password connections detach after authentication; old foreground connections
need an explicit OFF/ON by the human to migrate. Neither repeated session ON nor
repeated key-gate ON silently renews a lifetime or creates another managed connection.

1. Confirm the user explicitly asked to enable full-power. Never infer consent from a task that
   merely needs write access.
2. **Check before re-arming.** Run the main skill's `python3 scripts/power.py status` from the
   sibling `luffy-arm` directory before showing any ON command. If the agent runtime is known to
   sandbox SSH or ssh-agent, request narrowly scoped, user-approved **host execution** for this
   first check immediately; do not run a known-blocked sandbox probe first.
   - `DEDICATED GATE: ON`: do not ask the user to re-enter the passphrase. Report the verified state. If the same
     request also contains an authorized remote task, continue it under the sibling `luffy-arm`
     skill instead of stopping at the switch.
   - `DEDICATED GATE: UNKNOWN`: do not ask the user to re-enable Full Power. Retry with approved host execution;
     if that is unavailable, ask the user to run `luffy fullpower status` in their normal login
     terminal and report the result.
   - `DEDICATED GATE: OFF` plus `EFFECTIVE USER ACCESS: AVAILABLE`: an alternate credential
     already reaches `ADMIN_USER`. Do not claim Safe Mode or require re-arming merely to obtain
     the same remote user capability. Ask for the dedicated gate only if the user explicitly wants
     that credential path armed.
   - `DEDICATED GATE: OFF` plus no effective user access: continue to step 3.
3. Only after verified `OFF`, do **not** execute the ON wrapper on the user's behalf. Show the user
   this command from this skill directory and wait for them to run it in their own interactive
   login terminal:

   ```bash
   bash scripts/fullpower-on.sh [seconds]
   ```

   The wrapper delegates to the main `luffy-arm/scripts/fullpower-route.sh on`; it checks the admin key
   and SSH alias, then the user types the key passphrase directly into `ssh-add`. ON publishes a
   stable reference to that time-limited agent so other conversations can use the same gate without
   inheriting the same `SSH_AUTH_SOCK`. Never request, capture, paste, or store that passphrase.
4. After the user confirms the command completed, repeat the same host-first status check.
5. Report exactly one of these outcomes:
   - `DEDICATED GATE: ON`: independently confirmed.
   - `UNKNOWN`: approved host execution was unavailable, or the host could not inspect the
     login-session ssh-agent/SSH channel. State that the user reported ON but it is not
     independently visible; never translate UNKNOWN to OFF.
   - `DEDICATED GATE: OFF` or an error: report the separate effective-access layer before saying
     which capabilities remain. Never equate gate OFF with Safe Mode by itself.

Full-power expires at the configured TTL. When the write task ends, invoke the sibling
`luffy-arm-fullpower-off` operation.
