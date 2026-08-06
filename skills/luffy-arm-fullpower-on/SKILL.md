---
name: luffy-arm-fullpower-on
version: 1.7.0
description: Use when the user explicitly asks to turn on, enable, open, or arm luffy-arm full-power mode, including "turn on full power", "enable full-power", 打开 full power, 开启全功率模式. Check host status first and reuse an already-ON gate; only verified OFF requires the user to run the passphrase prompt. The agent never loads the key for them.
---

# luffy-arm full-power ON

This is the explicit ON companion operation for luffy-arm. Read the sibling `luffy-arm` skill's
**Full-power mode** section first; its invariants remain authoritative.

## Operation

1. Confirm the user explicitly asked to enable full-power. Never infer consent from a task that
   merely needs write access.
2. **Check before re-arming.** Run the main skill's `bash scripts/fullpower.sh status` from the
   sibling `luffy-arm` directory before showing any ON command. If the agent runtime is known to
   sandbox SSH or ssh-agent, request narrowly scoped, user-approved **host execution** for this
   first check immediately; do not run a known-blocked sandbox probe first.
   - `ON`: do not ask the user to re-enter the passphrase. Report the verified state. If the same
     request also contains an authorized remote task, continue it under the sibling `luffy-arm`
     skill instead of stopping at the switch.
   - `UNKNOWN`: do not ask the user to re-enable Full Power. Retry with approved host execution;
     if that is unavailable, ask the user to run `luffy fullpower status` in their normal login
     terminal and report the result.
   - verified `OFF`: continue to step 3.
3. Only after verified `OFF`, do **not** execute the ON wrapper on the user's behalf. Show the user
   this command from this skill directory and wait for them to run it in their own interactive
   login terminal:

   ```bash
   bash scripts/fullpower-on.sh [seconds]
   ```

   The wrapper delegates to the main `luffy-arm/scripts/fullpower.sh on`; it checks the admin key
   and SSH alias, then the user types the key passphrase directly into `ssh-add`. ON publishes a
   stable reference to that time-limited agent so other conversations can use the same gate without
   inheriting the same `SSH_AUTH_SOCK`. Never request, capture, paste, or store that passphrase.
4. After the user confirms the command completed, repeat the same host-first status check.
5. Report exactly one of these outcomes:
   - `ON`: independently confirmed.
   - `UNKNOWN`: approved host execution was unavailable, or the host could not inspect the
     login-session ssh-agent/SSH channel. State that the user reported ON but it is not
     independently visible; never translate UNKNOWN to OFF.
   - `OFF` or an error: full-power was not enabled; keep safe mode and show the reported fix.

Full-power expires at the configured TTL. When the write task ends, invoke the sibling
`luffy-arm-fullpower-off` operation.
