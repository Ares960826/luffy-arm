#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/luffy-arm-state-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home/.config/luffy-arm" "$TMP/home/.ssh"
touch "$TMP/home/.ssh/luffy-arm-admin-key" "$TMP/home/.ssh/luffy-arm-admin-key.pub"

cat > "$TMP/home/.config/luffy-arm/params.sh" <<'EOF'
export SERVER="example.invalid"
export SSH_PORT="22"
export HOST_ALIAS="safe-alias"
export CC_USER="cc"
export ADMIN_ALIAS="admin-alias"
export ADMIN_USER="example-admin"
export ADMIN_KEY="$HOME/.ssh/luffy-arm-admin-key"
export FULLPOWER_AGENT_SOCKET="$HOME/.config/luffy-arm/fullpower-agent.sock"
EOF

cat > "$TMP/bin/ssh" <<'EOF'
#!/usr/bin/env bash
[[ " $* " == *" -O exit "* ]] && exit 0
if [[ " $* " == *" IdentitiesOnly=no "* ]]; then
  state="${MOCK_ALT_STATE:-deny}"
else
  state="${MOCK_STRICT_STATE:-deny}"
fi
case "$state" in
  allow)   echo "example-admin"; exit 0 ;;
  wrong)   echo "somebody-else"; exit 0 ;;
  deny)    echo "Permission denied (publickey)." >&2; exit 255 ;;
  unknown) echo "ssh: connect to host example.invalid port 22: Network is unreachable" >&2; exit 255 ;;
  *)       echo "bad mock state: $state" >&2; exit 99 ;;
esac
EOF

cat > "$TMP/bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
echo "256 SHA256:admin-fingerprint luffy-arm-admin (ED25519)"
EOF

cat > "$TMP/bin/ssh-add" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-d" ]] && exit 0
echo "The agent has no identities." >&2
exit 1
EOF
chmod +x "$TMP/bin/ssh" "$TMP/bin/ssh-keygen" "$TMP/bin/ssh-add"

run_case() {
  local strict="$1" alternate="$2" operation="$3"
  set +e
  OUTPUT="$({
    HOME="$TMP/home" \
    PATH="$TMP/bin:$PATH" \
    MOCK_STRICT_STATE="$strict" \
    MOCK_ALT_STATE="$alternate" \
    bash "$ROOT/scripts/fullpower.sh" "$operation"
  } 2>&1)"
  RC=$?
  set -e
}

contains() {
  [[ "$OUTPUT" == *"$1"* ]] || {
    printf 'expected output to contain: %s\nactual output:\n%s\n' "$1" "$OUTPUT" >&2
    exit 1
  }
}

not_contains() {
  [[ "$OUTPUT" != *"$1"* ]] || {
    printf 'expected output not to contain: %s\nactual output:\n%s\n' "$1" "$OUTPUT" >&2
    exit 1
  }
}

run_case allow deny status
[[ $RC -eq 0 ]]
contains "DEDICATED GATE: ON"
contains "REMOTE IDENTITY: example-admin"

run_case deny allow status
[[ $RC -eq 0 ]]
contains "DEDICATED GATE: OFF"
contains "EFFECTIVE USER ACCESS: AVAILABLE"
contains "does not remove this capability or reduce it to Safe Mode"
not_contains "safe mode only"

run_case deny allow off
[[ $RC -eq 4 ]]
contains "DEDICATED GATE: OFF"
contains "personal/other SSH keys are outside this switch"

run_case deny deny status
[[ $RC -eq 0 ]]
contains "DEDICATED GATE: OFF"
contains "EFFECTIVE USER ACCESS: NOT FOUND"

run_case deny wrong status
[[ $RC -eq 3 ]]
contains "EFFECTIVE USER ACCESS: UNKNOWN"
contains "authenticated as 'somebody-else'"

run_case unknown allow status
[[ $RC -eq 3 ]]
contains "DEDICATED GATE: UNKNOWN"
not_contains "DEDICATED GATE: OFF"

echo "fullpower layered-state regression tests: passed"
