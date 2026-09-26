---
name: luffy-arm-fullpower-off
metadata:
  version: "1.8.0"
description: Use when the user asks to turn off, disable, close, or disarm luffy-arm full-power mode, including "turn off full power", "disable full-power", 关闭 full power, 退出全功率模式. Removes the dedicated admin key, verifies that credential is off, and reports alternate user-level SSH access separately.
---

# luffy-arm full-power OFF

This is the explicit OFF companion operation for luffy-arm. Read the sibling `luffy-arm` skill's
**Full-power mode** section first; its invariants remain authoritative.

## Operation

For any explicitly selected registered target, use the main skill's
`python3 scripts/power.py off TARGET` with host execution. Key and password targets
have equal selection rules; never route a named key target to unrelated default params.
The legacy default-key procedure below applies only when no registered target is selected.

For an explicit request to close **all** Luffy connections, call the main skill's
`python3 scripts/lifecycle.py all off` with host execution. It closes registered
sessions and the default key gate; report incomplete targets and alternate credentials.
Never substitute a blanket process-name kill or terminate the shared ssh-agent.

For an explicitly selected password-session target, read the main skill's
`references/user-sessions.md` and run `python3 scripts/session.py off TARGET` on
the host. Report that session's result; skip the default key-gate procedure below.
Do not close another target or claim other credentials/jobs were revoked/cancelled.
If several targets are in scope and the intended target is unclear, ask which one first.

1. Run this wrapper from this skill directory. It uses luffy-arm's published ssh-agent reference;
   in a known sandboxed runtime, request narrowly scoped, user-approved **host execution** from
   the outset instead of first trying inside the sandbox:

   ```bash
   bash scripts/fullpower-off.sh
   ```

   It delegates to the main `luffy-arm/scripts/fullpower-route.sh off`, removes the admin key from the
   visible ssh-agent, closes any legacy master connection, and probes the dedicated credential.
2. Report `DEDICATED GATE: OFF` only when that credential receives an explicit authentication
   denial. Do not shorten this to a claim that all user-level access is off.
3. Read the second layer. If `EFFECTIVE USER ACCESS: AVAILABLE`, another key still authenticates
   as `ADMIN_USER`. Report that the dedicated gate is off but effective user permissions remain;
   do not claim Safe Mode has returned. Personal keys are outside this switch.
4. If either layer reports `UNKNOWN`, a sandbox, network boundary, or identity mismatch prevented
   verification. Retry with approved host execution; only if unavailable ask for the same command
   in the user's normal login terminal.
5. If the dedicated gate remains ON, relay the remediation. TTL expiry is a fallback, not evidence
   of immediate shutdown.
