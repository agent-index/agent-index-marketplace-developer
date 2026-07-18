#!/usr/bin/env bash
# release-push.sh -- committed gated push+tag tool (developer lib/release; level-3).
# Reads the same release-delta manifest and performs the irreversible phase:
# PRE-PUSH DIFF + INTEGRITY GATE -> remote-URL HTTPS guard -> CHANGELOG date-stamp ->
# per-repo commit -> push -> tag v<version> in push_order (resource-listings LAST; never move a
# published tag). Host-run only (real repos, credentials, clean tree). Usage: bash release-push.sh <manifest.json>
set -u
M="${1:-}"
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
  git -C "$p" push origin HEAD || die "push failed for $n"
  # tag v<version>: leave an existing identical tag; NEVER move a published tag
  if [ -z "$v" ]; then echo "  no version supplied for $n -- pushed, tag SKIPPED (set version in the manifest if this repo is tag-pinned, e.g. resource-listings)"; continue; fi
  tag="v$v"
  existing=$(git -C "$p" tag -l "$tag")
  if [ -n "$existing" ]; then
    at=$(git -C "$p" rev-list -n1 "$tag"); head=$(git -C "$p" rev-parse HEAD)
    if [ "$at" = "$head" ]; then echo "  tag $tag already at HEAD -- left as is"
    else echo "  WARNING: tag $tag exists but points elsewhere ($at). NOT moving it. Cut a NEW version if a re-tag is needed."; fi
  else
    confirm "  tag $n $tag and push tag?" && { git -C "$p" tag -a "$tag" -m "release $tag" && git -C "$p" push origin "$tag"; } || echo "  skipped tag for $n"
  fi
done
echo ""
DP=$(python3 -c "import json;print(json.load(open('$M')).get('dist_publish',False))")
if [ "$DP" = "True" ]; then
  echo "DIST PUBLISH HANDOFF: now clone at the new tags (lib/clone) then run create-org/apply-updates"
  echo "to diff the clone against the backend and republish /shared/dist/ + manifest.json; verify the manifest."
fi
echo "PUSH COMPLETE."
exit 0
