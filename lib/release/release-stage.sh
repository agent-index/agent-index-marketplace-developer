#!/usr/bin/env bash
# release-stage.sh -- stage a release candidate to a distribution channel (developer lib/release; 1.14.0).
# Reads the same release-delta manifest as release-push and pushes every repo in push_order to the
# branch channel/<name>, so a test org whose "Distribution channel" is <name> can install the
# candidate BEFORE anything is tagged. Never creates tags. Never pushes the default branch.
#
# Per repo (push_order; catalogs / resource-listings last), with B = the checked-out branch:
#   B == channel/<name>  (iterating)  -> add -A, commit "stage(<name>): <repo> v<version>", push (fast-forward, no force)
#   otherwise, channel absent or already contained in B -> checkout -B channel/<name> (keeps working
#                                         changes), add, commit, push (a fast-forward, with an explicit lease)
#   otherwise, channel holds commits not on B:
#       no working changes            -> left as is (already staged; nothing new)
#       working changes               -> refused unless you type REPLACE (new candidate); the message says how
#                                         to add the changes to the candidate instead (stash, checkout, pop)
#   no changes, nothing staged yet    -> still pushes the branch at HEAD so the channel includes the repo
# Cleanup (1.14.0): after each repo is pushed it is checked out on the branch it started on (the default
# branch if it started on the channel). The staged commits stay on channel/<name>. --stay-on-channel skips this.
#
# Promote later: PR channel/<name> -> <default>, merge, release-push --tag-only, then
# git checkout <default> && git pull.
#
# Usage: bash release-stage.sh <manifest.json> --channel <name> [--skip-preflight] [--yes] [--stay-on-channel]
#   --stay-on-channel  leave staged repos checked out on channel/<name> (default: switch each back -- cleanup)
#   --skip-preflight  skip the preflight gate (loud warning; emergencies only)
#   --yes             answer y to every prompt -- TEST/CI ONLY, never for a real stage
set -u
M=""; CH=""; SKIP_PF=0; YES=0; STAY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --channel) CH="${2:-}"; shift 2 ;;
    --channel=*) CH="${1#--channel=}"; shift ;;
    --skip-preflight) SKIP_PF=1; shift ;;
    --yes) YES=1; shift ;;
    --stay-on-channel) STAY=1; shift ;;
    -*) echo "FATAL: unknown option $1"; exit 2 ;;
    *) [ -z "$M" ] && M="$1" || { echo "FATAL: unexpected argument $1"; exit 2; }; shift ;;
  esac
done
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die(){ echo "FATAL: $*"; exit 2; }
confirm(){ if [ $YES -eq 1 ]; then echo "$1 [y/N] y (--yes)"; return 0; fi; local a; read -r -p "$1 [y/N] " a || return 1; [ "$a" = "y" ] || [ "$a" = "Y" ]; }
[ -n "$M" ] && [ -f "$M" ] || die "usage: release-stage.sh <manifest.json> --channel <name> [--skip-preflight] [--yes] [--stay-on-channel]"
[ -n "$CH" ] || die "--channel <name> is required"
[[ "$CH" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || die "invalid channel name '$CH' (lowercase letters, digits, '-'; must start with a letter/digit; max 40 chars)"
command -v python3 >/dev/null || die "python3 required"
command -v git >/dev/null || die "git required"
BR="channel/$CH"
PREFLIGHT="$SELF/../preflight-cli.sh"
[ $YES -eq 1 ] && echo "NOTE: --yes answers every prompt with y. This flag is for tests/CI only."

mapfile -t ORDER < <(python3 -c "import json,sys;[print(x) for x in json.load(open(sys.argv[1])).get('push_order',[])]" "$M")
declare -A PATHS VERS
while IFS=$'\t' read -r n p v; do [ -n "$n" ] && { PATHS[$n]="$p"; VERS[$n]="$v"; }; done < <(python3 -c "
import json,sys
for r in json.load(open(sys.argv[1])).get('repos',[]): print('%s\t%s\t%s'%(r.get('name',''),r.get('path',''),r.get('version','')))
" "$M")
[ ${#ORDER[@]} -gt 0 ] || die "manifest push_order is empty"
[ -n "${PATHS[agent-index-core]:-}" ] || echo "WARNING: agent-index-core is not in this release set -- a channel set without agent-index-core makes the test org use the released core clone tooling, which (before core 3.32.0 is released) has no channel support and would move the org back to tags on the next refresh. Include agent-index-core unless you are sure the released core supports channels."

# The repo's default branch, from origin/HEAD; falls back to main, then master (same as release-push).
default_branch(){
  local b; b=$(git -C "$1" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); b="${b#origin/}"
  if [ -z "$b" ]; then
    if git -C "$1" show-ref --verify --quiet refs/remotes/origin/main; then b=main
    elif git -C "$1" show-ref --verify --quiet refs/remotes/origin/master; then b=master; else b=main; fi
  fi
  echo "$b"
}
# Run a push, show its output, and surface a GitHub rule bypass / protected-branch rejection (as release-push).
push_and_report(){
  local out rc; out=$("$@" 2>&1); rc=$?; echo "$out" | sed 's/^/  /'
  if echo "$out" | grep -q "Bypassed rule violations"; then
    echo "  WARNING: this push only succeeded by BYPASSING the repo's rules (see above). Anyone without"
    echo "           bypass rights will be rejected -- check the rules that cover channel/* branches."
  fi
  if [ $rc -ne 0 ] && echo "$out" | grep -qiE "protected branch|must be made through a pull request|GH006|GH013"; then
    echo "  The remote rejected the push under a branch rule. channel/* branches must be pushable"
    echo "  without a pull request -- ask a repo admin to exempt channel/* from the rule."
  fi
  if [ $rc -ne 0 ] && echo "$out" | grep -qiE "stale info|non-fast-forward|fetch first"; then
    echo "  origin/$BR moved since it was read (someone else staged to it?). Re-run to see the new state."
  fi
  return $rc
}

# ---------------- GATES (all repos, before any write) ----------------
echo "=================== STAGE GATES: channel '$CH' (branch $BR) ==================="
gate_fail=0
for n in "${ORDER[@]}"; do
  p="${PATHS[$n]:-}"
  [ -n "$p" ] || { echo "  FAIL $n: in push_order but not in repos[]"; gate_fail=1; continue; }
  [ -d "$p/.git" ] || { echo "  FAIL $n: no git repo at $p"; gate_fail=1; continue; }
  gd=$(git -C "$p" rev-parse --absolute-git-dir 2>/dev/null || echo "$p/.git")
  if [ -e "$gd/index.lock" ]; then
    echo "  FAIL $n: $gd/index.lock exists. If no git process is running in this repo, delete that file"
    echo "       and re-run; if one is running, let it finish first. (Not removed automatically.)"
    gate_fail=1; continue
  fi
  git -C "$p" remote get-url origin >/dev/null 2>&1 || { echo "  FAIL $n: no 'origin' remote"; gate_fail=1; continue; }
  b=$(git -C "$p" symbolic-ref --short -q HEAD) || { echo "  FAIL $n: detached HEAD -- check out a branch first"; gate_fail=1; continue; }
  echo "  ok $n (on $b)"
done
[ $gate_fail -eq 0 ] || die "stage gates failed -- nothing was changed"

if [ $SKIP_PF -eq 1 ]; then
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!  WARNING: --skip-preflight -- the preflight gate is NOT being run.          !!"
  echo "!!  The test org may install a candidate that preflight would have rejected.  !!"
  echo "!!  Promotion still requires release-prep (preflight) to pass.                !!"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
else
  [ -f "$PREFLIGHT" ] || die "preflight-cli.sh not found at $PREFLIGHT"
  echo ""; echo "=================== PREFLIGHT GATE ==================="
  pf_fail=0
  for n in "${ORDER[@]}"; do
    p="${PATHS[$n]}"
    if [ ! -f "$p/collection.json" ]; then
      echo "  $n: no collection.json (adapter or catalog repo) -- preflight not applicable, skipped"; continue
    fi
    # Same invocation release-prep uses.
    if ! bash "$PREFLIGHT" --collection "$p" >/tmp/pf.$$ 2>&1; then
      echo "  FAIL $n: preflight errors:"; grep -E '✗|error' /tmp/pf.$$ | head | sed 's/^/    /'; pf_fail=1
    else
      echo "  ok $n: preflight passed"
    fi
    rm -f /tmp/pf.$$
  done
  [ $pf_fail -eq 0 ] || die "preflight gate failed -- nothing was changed (fix the errors, or --skip-preflight for an emergency)"
fi

# ---------------- STAGE ----------------
echo ""; echo "=================== STAGE TO $BR ==================="
staged=(); skipped=(); unchanged=(); returned=(); not_returned=()
# Put the repo back on the branch it started on (the default branch when it started on the channel).
restore_branch(){ # $1=name $2=path $3=branch
  [ $STAY -eq 1 ] && return 0
  if git -C "$2" checkout -q "$3" 2>/dev/null; then returned+=("$1 -> $3"); else not_returned+=("$1 (git -C \"$2\" checkout $3)"); fi
}
fail_repo(){ # $1=name $2=path $3=branch $4=msg
  echo "  $1 is left on $BR (its changes are committed there). To go back: git -C \"$2\" checkout $3"
  die "$4"
}
for n in "${ORDER[@]}"; do
  p="${PATHS[$n]}"; v="${VERS[$n]}"
  echo ""; echo "----- $n v$v ($p) -----"
  B=$(git -C "$p" symbolic-ref --short -q HEAD)
  db=$(default_branch "$p")
  if [ "$B" = "$BR" ]; then back="$db"; else back="$B"; fi
  remote_sha=$(git -C "$p" ls-remote --heads origin "refs/heads/$BR" 2>/dev/null | awk '{print $1}' | head -n1)
  dirty=0; [ -n "$(git -C "$p" status --porcelain)" ] && dirty=1
  echo "  current branch: $B   default branch: $db"
  echo "  --- git status --short ---"; git -C "$p" status --short | sed 's/^/  /'
  echo "  --- git diff --stat HEAD ---"; git -C "$p" diff --stat HEAD 2>/dev/null | sed 's/^/  /'
  # Does the staged channel hold commits that are not on the current branch? (needs the remote tip locally)
  diverged=0
  if [ -n "$remote_sha" ] && [ "$B" != "$BR" ]; then
    git -C "$p" fetch -q origin "+refs/heads/$BR:refs/remotes/origin/$BR" 2>/dev/null
    git -C "$p" merge-base --is-ancestor "$remote_sha" HEAD 2>/dev/null || diverged=1
  fi
  mode=push
  if [ "$B" = "$BR" ]; then
    if [ -n "$remote_sha" ]; then echo "  origin/$BR exists at ${remote_sha:0:12}; this push fast-forwards it (no force)."
    else echo "  origin/$BR does not exist yet; this push creates it."; fi
    [ $dirty -eq 0 ] && echo "  (no working changes -- the branch is still pushed at HEAD so the channel includes $n)"
    confirm "  stage $n to $BR?" || { echo "  skipped $n"; skipped+=("$n"); restore_branch "$n" "$p" "$back"; continue; }
  elif [ $diverged -eq 1 ] && [ $dirty -eq 0 ]; then
    echo "  origin/$BR (${remote_sha:0:12}) already holds staged commits for $n that are not on '$B', and you have no new changes."
    echo "  Left as is -- the channel keeps what was staged."
    unchanged+=("$n"); continue
  elif [ $diverged -eq 1 ]; then
    echo "  You have changes on '$B', but origin/$BR (${remote_sha:0:12}) holds staged commits that are NOT on '$B'."
    echo "  Staging from '$B' would DROP those staged commits from the channel."
    echo "  To ADD these changes to the candidate instead (usual case), run this, then re-run this script:"
    echo "    git -C \"$p\" stash && git -C \"$p\" checkout $BR && git -C \"$p\" stash pop"
    if [ $YES -eq 1 ]; then echo "  skipped $n (--yes never replaces a channel)"; skipped+=("$n"); continue; fi
    a=""; read -r -p "  Type REPLACE to start a NEW candidate for $n from '$B' (anything else skips it): " a || a=""
    [ "$a" = "REPLACE" ] || { echo "  skipped $n"; skipped+=("$n"); continue; }
    git -C "$p" checkout -B "$BR" || die "checkout -B $BR failed for $n"
    mode=replace
  else
    if [ -n "$remote_sha" ]; then echo "  origin/$BR is at ${remote_sha:0:12}, already contained in '$B'; this push fast-forwards it to '$B' + your working changes."
    else echo "  origin/$BR does not exist yet; it will be created from '$B' + your working changes."; fi
    [ $dirty -eq 0 ] && echo "  (no working changes -- the branch is still pushed at HEAD so the channel includes $n)"
    confirm "  switch $n to $BR (git checkout -B, keeps working changes) and stage it?" || { echo "  skipped $n"; skipped+=("$n"); continue; }
    git -C "$p" checkout -B "$BR" || die "checkout -B $BR failed for $n"
  fi
  git -C "$p" add -A || fail_repo "$n" "$p" "$back" "git add failed for $n"
  if git -C "$p" diff --cached --quiet; then
    echo "  nothing to commit -- pushing $BR at HEAD"
  else
    git -C "$p" commit -q -m "stage($CH): $n v$v" || fail_repo "$n" "$p" "$back" "commit failed for $n"
    echo "  committed: $(git -C "$p" log --oneline -1)"
  fi
  if [ "$B" = "$BR" ]; then
    push_and_report git -C "$p" push -u origin "refs/heads/$BR:refs/heads/$BR" || fail_repo "$n" "$p" "$back" "push failed for $n (no force used; stopping before later repos so catalogs stay last)"
  else
    # Explicit lease: the remote branch must still be what ls-remote saw (or still absent).
    # Only the REPLACE path can drop remote commits; every other path is a fast-forward.
    push_and_report git -C "$p" push -u --force-with-lease="refs/heads/$BR:$remote_sha" origin "refs/heads/$BR:refs/heads/$BR" || fail_repo "$n" "$p" "$back" "push failed for $n (stopping before later repos so catalogs stay last)"
  fi
  [ "$mode" = replace ] && echo "  origin/$BR REPLACED for $n."
  staged+=("$n")
  restore_branch "$n" "$p" "$back"
done

echo ""
echo "=================== STAGE COMPLETE: channel '$CH' ==================="
echo "Staged to $BR (origin): ${staged[*]:-none}"
[ ${#unchanged[@]} -gt 0 ] && echo "Already on the channel, nothing new (left as is): ${unchanged[*]}"
if [ $STAY -eq 1 ]; then echo "--stay-on-channel: staged repos are left checked out on $BR."
else
  [ ${#returned[@]} -gt 0 ] && { j=$(printf '%s, ' "${returned[@]}"); echo "Checked out again (cleanup): ${j%, }"; }
  [ ${#not_returned[@]} -gt 0 ] && { j=$(printf '%s; ' "${not_returned[@]}"); echo "COULD NOT switch back -- still on $BR: ${j%; }"; }
  echo "The staged changes live on $BR (local and origin); your default branches are as they were before staging."
fi
[ ${#skipped[@]} -gt 0 ] && echo "Skipped (NOT on the channel -- the test org will not see them): ${skipped[*]}"
echo "No tags were created. No default branch was pushed."
echo ""
echo "NEXT -- on the TEST org's admin install:"
echo "  1. Create the org with distribution channel '$CH', or set it via edit-org (\"Distribution channel\")."
echo "  2. Refresh the clones (they now resolve $BR)."
echo "  3. Say \"publish our org updates\"."
echo "Iterate: git checkout $BR in the repo(s) you're changing, edit, re-run this script (fast-forward"
echo "  pushes, no force; each repo goes back to its branch afterwards). Repos you didn't touch are left as is."
echo ""
echo "PROMOTE when the candidate passes, per repo (code repos first, listings last):"
echo "  1. Open a PR $BR -> <default branch>, and merge it."
echo "  2. bash lib/release/release-push.sh $M --tag-only"
echo "  3. git checkout <default branch> && git pull && git branch -D $BR"
exit 0
# AIFS:FILE-END
