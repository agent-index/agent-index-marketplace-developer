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

# 2. Check 19: a crashing helper must fail the check. An unreadable .md file makes check-docs.mjs throw.
C="$TMP/agent-index-marketplace-crash"; mkdir -p "$C/api"
echo '{"name":"crash","version":"1.0.0","api":[]}' > "$C/collection.json"
echo "# Doc" > "$C/README.md"; echo "secret" > "$C/api/locked.md"; chmod 000 "$C/api/locked.md"
if [ -r "$C/api/locked.md" ]; then
  echo "skip - Check 19 crash case (running as a user that can read mode-000 files)"
else
  out=$(bash "$PF" --collection "$C" 2>&1); rc=$?
  echo "$out" | grep -q "Check 19 helper failed"; check "Check 19: helper crash is reported as an error" $?
  [ $rc -eq 1 ]; check "Check 19: helper crash makes preflight exit 1" $?
fi
chmod 644 "$C/api/locked.md"

# 3. Check 19: a broken citation inside a .json file is reported (escaped quotes; developer#11 review).
J="$TMP/agent-index-marketplace-json"; mkdir -p "$J"
echo '{"name":"json","version":"1.0.0","api":[]}' > "$J/collection.json"
printf '# Guide\n\n## Real Heading\n' > "$J/guide.md"
printf '{"see": "guide.md \\u00a7 \\"Missing Heading\\"", "ok": "guide.md \\u00a7 \\"Real Heading\\""}\n' | sed 's/\\u00a7/§/g' > "$J/notes.json"
out=$(node "$HERE/../check-docs.mjs" 19 "$J" 2>&1)
echo "$out" | grep -q 'notes.json:1: guide.md § "Missing Heading"'; check "Check 19: broken citation in a .json file is reported" $?
echo "$out" | grep -q '"Real Heading" — no such heading'; [ $? -ne 0 ]; check "Check 19: valid citation in a .json file is not reported" $?

# 4. Check 21: an object api[] entry with no "triggers" array is a WARNING (DC-001 follow-up).
K="$TMP/agent-index-marketplace-api"; mkdir -p "$K"
echo '{"name":"api","version":"1.0.0","api":[{"name":"no-triggers"},{"name":"bad-triggers","triggers":"x"},{"name":"ok-empty","triggers":[]}]}' > "$K/collection.json"
out=$(node "$HERE/../check-docs.mjs" 21 "$K" 2>&1)
echo "$out" | grep -q '^WARN .*"no-triggers" has no "triggers" array'; check "Check 21: object entry without triggers warns" $?
echo "$out" | grep -q '^WARN .*"bad-triggers": "triggers" is not an array'; check "Check 21: non-array triggers warns" $?
echo "$out" | grep -q 'ok-empty'; [ $? -ne 0 ]; check "Check 21: entry with triggers [] is not reported" $?

echo "# pass $pass, fail $fail"
[ $fail -eq 0 ]
