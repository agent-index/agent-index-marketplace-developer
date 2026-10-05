#!/usr/bin/env bash
# release-push.sh -- committed gated push+tag tool (developer lib/release; level-3).
# Reads the same release-delta manifest and performs the irreversible phase:
# PRE-PUSH DIFF + INTEGRITY GATE -> remote-URL HTTPS guard -> CHANGELOG date-stamp ->
# per-repo commit -> push -> tag v<version> in push_order (resource-listings LAST; never move a
# published tag). Host-run only (real repos, credentials, clean tree).
#
# Branch-aware (developer 1.13.0): a release tag must point at a commit on the repo's default
# branch. Run from the default branch, this behaves as before (commit -> push -> tag). Run from
# any other branch (the PR workflow), it commits and pushes the branch, then DEFERS tagging --
# open the PR, merge it, then run with --tag-only to tag the merged commit on origin/<default>.
#
# Usage: bash release-push.sh <manifest.json>              # commit + push (+ tag if on default branch)
#        bash release-push.sh <manifest.json> --tag-only   # after merge: tag origin/<default>
set -u
M="${1:-}"
TAG_ONLY=0; [ "${2:-}" = "--tag-only" ] && TAG_ONLY=1
die(){ echo "FATAL: $*"; exit 2; }
confirm(){ read -r -p "$1 [y/N] " a; [ "$a" = "y" ] || [ "$a" = "Y" ]; }
[ -n "$M" ] && [ -f "$M" ] || die "usage: release-push.sh <manifest.json>"
command -v python3 >/dev/null || die "python3 required"
command -v git >/dev/null || die "git required"

TODAY=$(date +%F)
mapfile -t ORDER < <(python3 -c "import json;[print(x) for x in json.load(open('$M')).get('push_order',[])]")
declare -A PATHS VERS
while IFS=$'\t' read -r n p v; do PATHS[$n]="$p"; VERS[$n]="$v"; done < <(python3 -c "
import json
for r in json.load(open('$M')).get('repos',[]): print('%s\t%s\t%s'%(r['name'],r['path'],r['version']))
")
[ ${#ORDER[@]} -gt 0 ] || die "manifest push_order is empty"

# The repo's default branch, from origin/HEAD; falls back to main, then master.
default_branch(){
  local b; b=$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); b="${b#origin/}"
  if [ -z "$b" ]; then
    if git -C "$1" show-ref --verify --quiet refs/remotes/origin/main; then b=main
    elif git -C "$1" show-ref --verify --quiet refs/remotes/origin/master; then b=master; else b=main; fi
  fi
  echo "$b"
}
# Run a push, show its output, and surface a GitHub rule bypass instead of burying it.
push_and_report(){
  local out rc; out=$("$@" 2>&1); rc=$?; echo "$out" | sed 's/^/  /'
  if echo "$out" | grep -q "Bypassed rule violations"; then
    echo "  WARNING: this push only succeeded by BYPASSING the repo's rules (see above). Anyone without"
    echo "           bypass rights will be rejected -- release from a branch + PR, then --tag-only."
  fi
  if [ $rc -ne 0 ] && echo "$out" | grep -qiE "protected branch|must be made through a pull request|GH006|GH013"; then
    echo "  The default branch requires a pull request. Check out a release branch, re-run this"
    echo "  script to push it, open the PR, then run with --tag-only after it merges."
  fi
  return $rc
}
# Tag commit $3 in repo $1 as v$2, never moving a published tag.
tag_commit(){
  local p="$1" v="$2" sha="$3" n="$4" tag="v$2" at
  if [ -n "$(git -C "$p" tag -l "$tag")" ]; then
    at=$(git -C "$p" rev-list -n1 "$tag")
    if [ "$at" = "$sha" ]; then echo "  tag $tag already at $sha -- left as is"
    else echo "  WARNING: tag $tag exists but points elsewhere ($at). NOT moving it. Cut a NEW version if a re-tag is needed."; fi
    return 0
  fi
  confirm "  tag $n $tag at ${sha:0:12} and push tag?" || { echo "  skipped tag for $n"; return 0; }
  git -C "$p" tag -a "$tag" "$sha" -m "release $tag" || die "tag failed for $n"
  push_and_report git -C "$p" push origin "$tag" || die "tag push failed for $n"
}

# --tag-only version gate at commit $2 of repo $1 (name $3, manifest version $4, label $5):
#   collection.json -> its "version" must equal the manifest version
#   adapter.json    -> its "version" must equal the manifest version
#   catalog repo (marketplace-/infrastructure-/filesystem-adapter-directory.json) -> every entry that
#     lists another repo in this manifest (matched by repo_url basename or name) must carry that repo's
#     manifest version as current_version. (The catalog repo's own tag is a repo-level counter, not
#     any one file's directory_version, so the entries are what prove the release PR merged.)
version_gate_at(){
  python3 - "$1" "$2" "$3" "$4" "$5" "$M" <<'PY'
import json,subprocess,sys
p,sha,name,ver,label,mpath=sys.argv[1:7]
def show(f):
    r=subprocess.run(['git','-C',p,'show','%s:%s'%(sha,f)],capture_output=True)
    return r.stdout.decode('utf-8','replace') if r.returncode==0 else None
def jl(t):
    try: return json.loads(t.lstrip('\ufeff'))
    except Exception: return None
for f in ('collection.json','adapter.json'):
    t=show(f)
    if t is None: continue
    j=jl(t); got=(j or {}).get('version','')
    if got!=ver:
        print('  %s %s is %s, manifest says %s'%(label,f,got or '(unreadable)',ver)); sys.exit(1)
    print('  %s %s version %s == manifest'%(label,f,got)); sys.exit(0)
cats=[c for c in ('marketplace-directory.json','infrastructure-directory.json','filesystem-adapter-directory.json') if show(c) is not None]
if not cats:
    print('  (no collection.json / adapter.json / catalog file at %s -- no version to check)'%label); sys.exit(0)
m=json.load(open(mpath))
want={r['name']:(r.get('version',''),bool(r.get('in_listings',False))) for r in m.get('repos',[]) if r.get('name')!=name}
seen=set(); bad=0
for c in cats:
    j=jl(show(c)) or {}
    for k,arr in j.items():
        if not isinstance(arr,list): continue
        for e in arr:
            if not isinstance(e,dict) or 'current_version' not in e: continue
            base=str(e.get('repo_url','')).rstrip('/').split('/')[-1]
            if base.endswith('.git'): base=base[:-4]
            for rn,(rv,_) in want.items():
                if rn in (base,e.get('name')):
                    seen.add(rn)
                    if e['current_version']!=rv:
                        print('  %s %s: %s current_version %s, manifest says %s'%(label,c,rn,e['current_version'],rv)); bad=1
                    else:
                        print('  %s %s: %s current_version %s == manifest'%(label,c,rn,rv))
for rn,(rv,inl) in want.items():
    if inl and rn not in seen: print('  note: %s is in_listings but has no entry in this catalog repo'%rn)
if not seen: print('  note: no catalog entry lists another repo in this manifest (listings-only release) -- confirm the merge by hand')
sys.exit(bad)
PY
}

# ---- --tag-only: after the release PRs merged, tag the merged commit on each default branch ----
if [ $TAG_ONLY -eq 1 ]; then
  echo "=================== TAG-ONLY: tag merged releases on the default branch ==================="
  for n in "${ORDER[@]}"; do
    p="${PATHS[$n]}"; v="${VERS[$n]}"; [ -d "$p/.git" ] || { echo "SKIP $n (no git repo)"; continue; }
    [ -n "$v" ] || { echo "SKIP $n (no version in manifest)"; continue; }
    echo ""; echo "----- $n v$v -----"
    git -C "$p" fetch origin --tags --quiet || die "fetch failed for $n"
    db=$(default_branch "$p"); sha=$(git -C "$p" rev-parse "origin/$db" 2>/dev/null) || die "no origin/$db in $n"
    echo "  origin/$db is at $(git -C "$p" log --oneline -1 "$sha")"
    version_gate_at "$p" "$sha" "$n" "$v" "origin/$db" || die "$n: version check failed at origin/$db (above) -- has the release PR merged? Stopping before later repos (listings stay last)."
    tag_commit "$p" "$v" "$sha" "$n"
  done
  echo ""
  if [ "$(python3 -c "import json;print(json.load(open('$M')).get('dist_publish',False))")" = "True" ]; then
    echo "DIST PUBLISH HANDOFF: now clone at the new tags (lib/clone) then run create-org/apply-updates"
    echo "to diff the clone against the backend and republish /shared/dist/ + manifest.json; verify the manifest."
  fi
  echo "TAG-ONLY COMPLETE."
  exit 0
fi

echo "=================== PRE-PUSH DIFF + INTEGRITY GATE ==================="
integrity_fail=0
for n in "${ORDER[@]}"; do
  p="${PATHS[$n]}"; [ -d "$p/.git" ] || { echo "SKIP $n (no git repo at $p)"; continue; }
  echo ""; echo "----- $n ($p) -----"
  # remote-URL HTTPS guard
  url=$(git -C "$p" remote get-url origin 2>/dev/null || echo "")
  if [ -z "$url" ]; then echo "  no 'origin' remote -- run: git -C $p remote add origin <https-url>"; integrity_fail=1
  elif [[ "$url" != https://* ]]; then echo "  origin is NOT https ($url) -- run: git -C $p remote set-url origin <https-url>"; integrity_fail=1; fi
  # integrity guard: sentinel lost vs HEAD + trailing newline
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in *.md|*.sh|*.js|*.json)
      # trailing-newline (torn-write signature -- create-org.md class)
      if [ -s "$p/$f" ] && [ -n "$(tail -c1 "$p/$f" 2>/dev/null)" ]; then
        echo "  INTEGRITY: $f does not end in a newline (possible truncation)"; integrity_fail=1
      fi
      # sentinel present at HEAD but lost in working tree
      if git -C "$p" show "HEAD:$f" 2>/dev/null | grep -q 'AIFS:FILE-END'; then
        grep -q 'AIFS:FILE-END' "$p/$f" 2>/dev/null || { echo "  INTEGRITY: $f had the AIFS:FILE-END sentinel at HEAD but lost it (truncation?)"; integrity_fail=1; }
      fi
      case "$f" in *.md)
        lastline=$(grep -v '^[[:space:]]*$' "$p/$f" 2>/dev/null | tail -n1)
        if [[ "$lastline" =~ [A-Za-z0-9]$ ]] && ! grep -q 'AIFS:FILE-END' "$p/$f" 2>/dev/null; then
          echo "  INTEGRITY: $f last line ends mid-word with no terminator/sentinel (likely truncated)"; integrity_fail=1
        fi ;; esac
    ;; esac
  done < <(git -C "$p" diff --name-only HEAD 2>/dev/null)
  # show the diff for operator review
  echo "  --- git diff --stat HEAD ---"; git -C "$p" diff --stat HEAD 2>/dev/null | sed 's/^/  /'
  echo "  (full diff follows; review it)"; git -C "$p" --no-pager diff HEAD 2>/dev/null | sed 's/^/  | /' | head -400
done
echo ""
if [ $integrity_fail -ne 0 ]; then
  echo "INTEGRITY GATE FLAGGED ISSUES ABOVE (lost sentinel / no trailing newline / non-https remote)."
  confirm "Proceed ANYWAY? Only if every flag is understood and intended." || die "aborted at integrity gate"
fi
confirm "Have you reviewed EVERY diff above and confirm all changes are intended?" || die "aborted at diff-review gate"

echo "=================== DATE-STAMP + PUSH ==================="
DEFERRED=0
for n in "${ORDER[@]}"; do
  p="${PATHS[$n]}"; v="${VERS[$n]}"; [ -d "$p/.git" ] || { echo "SKIP $n"; continue; }
  echo ""; echo "----- pushing $n v$v -----"
  # CHANGELOG date-stamp at push (replace RELEASE_DATE placeholder)
  if [ -f "$p/CHANGELOG.md" ] && grep -q '<RELEASE_DATE>' "$p/CHANGELOG.md"; then
    sed -i "s/<RELEASE_DATE>/$TODAY/g" "$p/CHANGELOG.md"; echo "  stamped CHANGELOG date -> $TODAY"
  fi
  git -C "$p" add -A
  if ! git -C "$p" diff --cached --quiet; then
    confirm "  commit $n?" || { echo "  skipped commit for $n"; continue; }
    git -C "$p" commit -m "release: $n v$v" || die "commit failed for $n"
  else echo "  nothing staged to commit"; fi
  confirm "  push $n to origin?" || { echo "  skipped push for $n"; continue; }
  cur=$(git -C "$p" rev-parse --abbrev-ref HEAD); db=$(default_branch "$p")
  if [ "$cur" = "$db" ]; then
    push_and_report git -C "$p" push origin HEAD || die "push failed for $n"
  else
    push_and_report git -C "$p" push -u origin HEAD || die "push failed for $n"
  fi
  if [ -z "$v" ]; then echo "  no version supplied for $n -- pushed, tag SKIPPED (set version in the manifest if this repo is tag-pinned, e.g. resource-listings)"; continue; fi
  if [ "$cur" != "$db" ]; then
    # A tag must point at the commit that lands on the default branch; a squash/rebase merge
    # would leave a pre-merge tag pointing at a commit that is not on it.
    echo "  on branch '$cur', not '$db': tag v$v DEFERRED. Open a PR $cur -> $db; after it merges run:"
    echo "      bash release-push.sh $M --tag-only"
    DEFERRED=1; continue
  fi
  tag_commit "$p" "$v" "$(git -C "$p" rev-parse HEAD)" "$n"
done
echo ""
DP=$(python3 -c "import json;print(json.load(open('$M')).get('dist_publish',False))")
if [ "$DP" = "True" ] && [ $DEFERRED -eq 0 ]; then
  echo "DIST PUBLISH HANDOFF: now clone at the new tags (lib/clone) then run create-org/apply-updates"
  echo "to diff the clone against the backend and republish /shared/dist/ + manifest.json; verify the manifest."
fi
if [ $DEFERRED -eq 1 ]; then
  echo "PUSH COMPLETE -- TAGS DEFERRED. Merge the release PR(s) (code repos first, listings last), then:"
  echo "    bash release-push.sh $M --tag-only"
  exit 0
fi
echo "PUSH COMPLETE."
exit 0
# AIFS:FILE-END
