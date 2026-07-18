#!/usr/bin/env bash
# release-prep.sh -- committed release build+prep tool (developer lib/release; level-3).
# Reads a release-delta manifest (data the agent emits) and runs the prep phase:
# preflight (hard gate) -> adapter build+checksum (only repos flagged is_adapter) ->
# manifest collection_version restamp -> resource-listings stamp. Makes NO git commits/pushes/tags
# and touches no /shared/. Safe to re-run. Usage: bash release-prep.sh <manifest.json>
set -u
M="${1:-}"; SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die(){ echo "FATAL: $*"; exit 2; }
[ -n "$M" ] && [ -f "$M" ] || die "usage: release-prep.sh <manifest.json>"
command -v python3 >/dev/null || die "python3 required"
PREFLIGHT="$SELF/../preflight-cli.sh"
[ -f "$PREFLIGHT" ] || die "preflight-cli.sh not found at $PREFLIGHT"

rows=$(python3 -c "
import json,sys
m=json.load(open('$M'))
for r in m.get('repos',[]):
    print('%s\t%s\t%s\t%s\t%s'%(r.get('name',''),r.get('path',''),r.get('version',''),
        str(r.get('is_adapter',False)).lower(),str(r.get('in_listings',False)).lower()))
")
fail=0
while IFS=$'\t' read -r name path ver is_adapter in_listings; do
  [ -n "$name" ] || continue
  echo "== prep: $name v$ver =="
  [ -d "$path" ] || { echo "  FAIL: repo path missing: $path"; fail=1; continue; }
  [ -f "$path/collection.json" ] || { echo "  (no collection.json -- directory/listings repo; skipping preflight + restamp)"; echo "  OK prep $name"; continue; }
  # 1. adapter build + checksum (only when flagged)
  if [ "$is_adapter" = "true" ]; then
    ( cd "$path" && npm run build ) || { echo "  FAIL: npm run build"; fail=1; continue; }
    b="$path/dist/aifs-exec.bundle.js"
    actual=$(sha256sum "$b" 2>/dev/null | awk '{print $1}')
    stamped=$(grep -m1 '"exec_bundle_checksum"' "$path/adapter.json" | sed -E 's/.*"([0-9a-f]{64})".*/\1/')
    [ "$actual" = "$stamped" ] || { echo "  FAIL: checksum mismatch after build ($stamped vs $actual)"; fail=1; continue; }
    node --check "$b" || { echo "  FAIL: node --check bundle"; fail=1; continue; }
    echo "  adapter bundle built + checksum verified"
  fi
  # 2. restamp api/*-manifest.json collection_version to $ver
  if [ -d "$path/api" ]; then
    python3 - "$path" "$ver" <<'PY'
import json,glob,sys,os
path,ver=sys.argv[1:3]
for f in glob.glob(os.path.join(path,'api','*-manifest.json')):
    try:
        j=json.load(open(f))
    except: continue
    if j.get('collection_version')!=ver:
        j['collection_version']=ver
        open(f,'w').write(json.dumps(j,indent=2)+'\n')
        print('  restamped',os.path.basename(f),'->',ver)
PY
  fi
  # 3. preflight HARD GATE (after stamping, so Check 2 sees aligned manifests) (errors abort)
  if ! bash "$PREFLIGHT" --collection "$path" >/tmp/pf.$$ 2>&1; then
    echo "  FAIL: preflight errors:"; grep -E '✗|error' /tmp/pf.$$ | head; fail=1; rm -f /tmp/pf.$$; continue
  fi
  rm -f /tmp/pf.$$
  echo "  OK prep $name"
done <<< "$rows"
[ $fail -eq 0 ] || { echo ""; echo "PREP FAILED -- fix the above before push."; exit 1; }
echo ""; echo "PREP OK -- all repos gated + stamped. Next: bash release-push.sh $M"
exit 0
