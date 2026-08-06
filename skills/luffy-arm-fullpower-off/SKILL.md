---
name: luffy-arm-fullpower-off
version: 1.7.0
description: Use when the user asks to turn off, disable, close, or disarm luffy-arm full-power mode, including "turn off full power", "disable full-power", 关闭 full power, 退出全功率模式. Removes the admin key and verifies that the admin alias no longer authenticates.
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
   visible ssh-agent, closes any legacy master connection, and probes the live admin alias.
2. Report `OFF` only when the command says authentication was explicitly denied.
3. If it reports `UNKNOWN`, a sandbox or network boundary prevented verification. Do not claim
   safe mode has returned. Retry with approved host execution; only if that is unavailable ask
   the user to run the same command in their normal login terminal and confirm verified OFF.
4. If the alias still authenticates, report that full-power remains ON and relay the command's
   remediation. TTL expiry is a fallback, not evidence of immediate shutdown.
