# Security Policy

luffy-arm is a security-sensitive tool by nature: it wires an AI agent into a remote server
over SSH. We take reports seriously.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Use GitHub's private vulnerability reporting:
[Report a vulnerability](https://github.com/Ares960826/luffy-arm/security/advisories/new).

You can expect an acknowledgement within a few days. Coordinated disclosure preferred —
we'll credit you in the advisory and CHANGELOG unless you'd rather stay anonymous.

## Scope

Reports we care about most:

- Ways an agent in **safe mode** could gain write access or escalate on the server
  (ACL model bypass, `READ_EXCLUDES` gaps that expose credential stores, etc.)
- Ways **full-power mode** could stay silently enabled past its TTL, or be enabled without
  the human typing the key passphrase
- Anything that causes key material or passphrases to touch the agent's context
- `install.sh` / `curl | bash` supply-chain concerns

## Supported versions

Only the latest release (`main` / newest tag) is supported.
