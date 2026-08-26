---
name: luffy-arm-fullpower-off
version: 1.7.1
description: Use when the user asks to turn off, disable, close, or disarm luffy-arm full-power mode, including "turn off full power", "disable full-power", 关闭 full power, 退出全功率模式. Removes the dedicated admin key, verifies that credential is off, and reports alternate user-level SSH access separately.
---

# luffy-arm full-power OFF

This is the explicit OFF companion operation for luffy-arm. Read the sibling `luffy-arm` skill's
**Full-power mode** section first; its invariants remain authoritative.

## Operation

1. Run this wrapper from this skill directory. It uses luffy-arm's published ssh-agent reference;
   in a known sandboxed runtime, request narrowly scoped, user-approved **host execution** from
   the outset instead of first trying inside the sandbox:

   ```bash
   bash scripts/fullpower-off.sh
   ```

   It delegates to the main `luffy-arm/scripts/fullpower.sh off`, removes the admin key from the
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
