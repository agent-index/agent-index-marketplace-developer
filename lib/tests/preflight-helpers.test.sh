#!/usr/bin/env bash
# preflight-helpers.test.sh — regression tests for preflight-cli.sh's node helper checks.
# Run: bash lib/tests/preflight-helpers.test.sh   (needs node; exits non-zero on any failure)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PF="$HERE/../preflight-cli.sh"
fail=0; pass=0
check(){ # name, condition-result (0 = ok)
  if [ "$2" -eq 0 ]; then echo "ok   - $1"; pass=$((pass+1)); else echo "FAIL - $1"; fail=$((fail+1)); fi
}
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. Check 18: a crashing helper must fail the check, not read as OK (developer#10 review).
#    An adapter repo whose src/exec.mjs is a directory makes check-tool-coverage.mjs throw EISDIR.
A="$TMP/agent-index-filesystem-crash"; mkdir -p "$A/src/exec.mjs" "$A/dist"
echo '{"name":"agent-index-filesystem-crash","version":"1.0.0"}' > "$A/adapter.json"
printf '#!/bin/bash\necho help\n' > "$A/src/aifs-exec.sh"
out=$(bash "$PF" --collection "$A" 2>&1); rc=$?
echo "$out" | grep -q "Check 18 helper failed"; check "Check 18: helper crash is reported as an error" $?
echo "$out" | grep -q "OK: every routed tool"; [ $? -ne 0 ]; check "Check 18: helper crash is not reported as OK" $?
[ $rc -eq 1 ]; check "Check 18: helper crash makes preflight exit 1" $?

echo "# pass $pass, fail $fail"
[ $fail -eq 0 ]
