# release-stage.ps1 -- stage a release candidate to a distribution channel (developer lib/release; 1.14.0).
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
# branch if it started on the channel). The staged commits stay on channel/<name>. -StayOnChannel skips this.
#
# Promote later: PR channel/<name> -> <default>, merge, release-push -TagOnly, then
# git checkout <default>; git pull.
#
# Usage: powershell -ExecutionPolicy Bypass -File release-stage.ps1 -Manifest <manifest.json> -Channel <name> [-SkipPreflight] [-Yes] [-StayOnChannel]
#   -StayOnChannel  leave staged repos checked out on channel/<name> (default: switch each back -- cleanup)
#   -SkipPreflight  skip the preflight gate (loud warning; emergencies only)
#   -Yes            answer y to every prompt -- TEST/CI ONLY, never for a real stage
param([Parameter(Mandatory=$true)][string]$Manifest,
      [Parameter(Mandatory=$true)][string]$Channel,
      [switch]$SkipPreflight, [switch]$Yes, [switch]$StayOnChannel)
$ErrorActionPreference = "Continue"
function Die([string]$m){ Write-Host "FATAL: $m"; exit 2 }
function Confirm([string]$m){
  if ($Yes) { Write-Host "$m [y/N] y (-Yes)"; return $true }
  $a = Read-Host "$m [y/N]"; return ($a -eq "y" -or $a -eq "Y")
}
# Locate the Git bash explicitly (avoids WSL bash) -- same as release-prep.ps1.
function Get-GitBash {
  $g = (Get-Command git -ErrorAction SilentlyContinue).Source
  if ($g) {
    $root = Split-Path (Split-Path $g)
    foreach ($rel in @("bin\bash.exe","usr\bin\bash.exe")) {
      $c = Join-Path $root $rel
      if (Test-Path $c) { return $c }
    }
  }
  $b = (Get-Command bash -ErrorAction SilentlyContinue).Source
  if ($b) { return $b }
  return $null
}
function ConvertTo-BashPath([string]$p) {
  $p = $p -replace '\\','/'
  if ($p -match '^([A-Za-z]):/(.*)$') { return '/' + $Matches[1].ToLower() + '/' + $Matches[2] }
  return $p
}

if (-not (Test-Path $Manifest)) { Die "manifest not found: $Manifest" }
if ($Channel -cnotmatch '^[a-z0-9][a-z0-9-]{0,39}$') { Die "invalid channel name '$Channel' (lowercase letters, digits, '-'; must start with a letter/digit; max 40 chars)" }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die "git required" }
try { $m = Get-Content -Raw $Manifest | ConvertFrom-Json } catch { Die "manifest not valid JSON" }
$br = "channel/$Channel"
$self = Split-Path -Parent $MyInvocation.MyCommand.Path
$preflight = Join-Path $self "..\preflight-cli.sh"
if ($Yes) { Write-Host "NOTE: -Yes answers every prompt with y. This switch is for tests/CI only." }
$paths = @{}; $vers = @{}
foreach ($r in $m.repos) { $paths["$($r.name)"] = "$($r.path)"; $vers["$($r.name)"] = "$($r.version)" }
$order = @($m.push_order)
if ($order.Count -eq 0) { Die "manifest push_order is empty" }
if (-not ($order -contains "agent-index-core")) { Write-Host "WARNING: agent-index-core is not in this release set -- a channel set without agent-index-core makes the test org use the released core clone tooling, which (before core 3.32.0 is released) has no channel support and would move the org back to tags on the next refresh. Include agent-index-core unless you are sure the released core supports channels." }

# The repo's default branch, from origin/HEAD; falls back to main, then master (same as release-push).
function Get-DefaultBranch([string]$p) {
  $b = (& git -C $p symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
  if ($b) { return ("$b" -replace '^origin/','') }
  & git -C $p show-ref --verify --quiet refs/remotes/origin/main 2>$null; if ($LASTEXITCODE -eq 0) { return "main" }
  & git -C $p show-ref --verify --quiet refs/remotes/origin/master 2>$null; if ($LASTEXITCODE -eq 0) { return "master" }
  return "main"
}
# Run a git push, show its output, and surface a rule bypass / protected-branch rejection (as release-push).
function Push-AndReport([string]$p, [string[]]$pushArgs) {
  $out = (& git -C $p push @pushArgs 2>&1 | ForEach-Object { "$_" }); $rc = $LASTEXITCODE
  $out | ForEach-Object { Write-Host "  $_" }
  $txt = ($out -join "`n")
  if ($txt -match "Bypassed rule violations") {
    Write-Host "  WARNING: this push only succeeded by BYPASSING the repo's rules (see above). Anyone without"
    Write-Host "           bypass rights will be rejected -- check the rules that cover channel/* branches."
  }
  if ($rc -ne 0 -and $txt -match "protected branch|must be made through a pull request|GH006|GH013") {
    Write-Host "  The remote rejected the push under a branch rule. channel/* branches must be pushable"
    Write-Host "  without a pull request -- ask a repo admin to exempt channel/* from the rule."
  }
  if ($rc -ne 0 -and $txt -match "stale info|non-fast-forward|fetch first") {
    Write-Host "  origin/$br moved since it was read (someone else staged to it?). Re-run to see the new state."
  }
  return ($rc -eq 0)
}

# ---------------- GATES (all repos, before any write) ----------------
Write-Host "=================== STAGE GATES: channel '$Channel' (branch $br) ==================="
$gateFail = $false
foreach ($n in $order) {
  $p = $paths[$n]
  if (-not $p) { Write-Host "  FAIL ${n}: in push_order but not in repos[]"; $gateFail = $true; continue }
  if (-not (Test-Path (Join-Path $p ".git"))) { Write-Host "  FAIL ${n}: no git repo at $p"; $gateFail = $true; continue }
  $gd = (& git -C $p rev-parse --absolute-git-dir 2>$null); if (-not $gd) { $gd = Join-Path $p ".git" }
  if (Test-Path (Join-Path $gd "index.lock")) {
    Write-Host "  FAIL ${n}: $gd/index.lock exists. If no git process is running in this repo, delete that file"
    Write-Host "       and re-run; if one is running, let it finish first. (Not removed automatically.)"
    $gateFail = $true; continue
  }
  & git -C $p remote get-url origin *> $null
  if ($LASTEXITCODE -ne 0) { Write-Host "  FAIL ${n}: no 'origin' remote"; $gateFail = $true; continue }
  $b = (& git -C $p symbolic-ref --short -q HEAD 2>$null)
  if (-not $b) { Write-Host "  FAIL ${n}: detached HEAD -- check out a branch first"; $gateFail = $true; continue }
  Write-Host "  ok $n (on $b)"
}
if ($gateFail) { Die "stage gates failed -- nothing was changed" }

if ($SkipPreflight) {
  Write-Host ""
  Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  Write-Host "!!  WARNING: -SkipPreflight -- the preflight gate is NOT being run.           !!"
  Write-Host "!!  The test org may install a candidate that preflight would have rejected.  !!"
  Write-Host "!!  Promotion still requires release-prep (preflight) to pass.                !!"
  Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
} else {
  if (-not (Test-Path $preflight)) { Die "preflight-cli.sh not found at $preflight" }
  $bash = Get-GitBash
  if (-not $bash) { Die "could not find bash (Git for Windows provides it). Install Git, or run release-stage.sh under bash." }
  $bashPreflight = ConvertTo-BashPath ((Resolve-Path $preflight).Path)
  Write-Host ""; Write-Host "=================== PREFLIGHT GATE ==================="
  $pfFail = $false
  foreach ($n in $order) {
    $p = $paths[$n]
    if (-not (Test-Path (Join-Path $p "collection.json"))) { Write-Host "  ${n}: no collection.json (adapter or catalog repo) -- preflight not applicable, skipped"; continue }
    # Same invocation release-prep uses.
    $bashColl = ConvertTo-BashPath ((Resolve-Path $p).Path)
    $pf = & $bash "$bashPreflight" --collection "$bashColl" 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  FAIL ${n}: preflight did not pass -- output:"
      ($pf | Select-Object -Last 20) | ForEach-Object { Write-Host "    $_" }
      $pfFail = $true
    } else { Write-Host "  ok ${n}: preflight passed" }
  }
  if ($pfFail) { Die "preflight gate failed -- nothing was changed (fix the errors, or -SkipPreflight for an emergency)" }
}

# ---------------- STAGE ----------------
Write-Host ""; Write-Host "=================== STAGE TO $br ==================="
$staged = @(); $skipped = @(); $unchanged = @(); $returned = @(); $notReturned = @()
# Put the repo back on the branch it started on (the default branch when it started on the channel).
function Restore-Branch([string]$n, [string]$p, [string]$to) {
  if ($StayOnChannel) { return }
  & git -C $p checkout -q $to 2>$null
  if ($LASTEXITCODE -eq 0) { $script:returned += "$n -> $to" } else { $script:notReturned += "$n (git -C `"$p`" checkout $to)" }
}
function Fail-Repo([string]$n, [string]$p, [string]$to, [string]$msg) {
  Write-Host "  $n is left on $br (its changes are committed there). To go back: git -C `"$p`" checkout $to"
  Die $msg
}
foreach ($n in $order) {
  $p = $paths[$n]; $v = $vers[$n]
  Write-Host ""; Write-Host "----- $n v$v ($p) -----"
  $B = (& git -C $p symbolic-ref --short -q HEAD 2>$null)
  $db = Get-DefaultBranch $p
  $back = if ($B -ceq $br) { $db } else { $B }
  $remoteSha = ""
  $ls = (& git -C $p ls-remote --heads origin "refs/heads/$br" 2>$null | Select-Object -First 1)
  if ($ls) { $remoteSha = ("$ls" -split '\s+')[0] }
  $dirty = [bool](& git -C $p status --porcelain)
  Write-Host "  current branch: $B   default branch: $db"
  Write-Host "  --- git status --short ---"; & git -C $p status --short | ForEach-Object { Write-Host "  $_" }
  Write-Host "  --- git diff --stat HEAD ---"; & git -C $p diff --stat HEAD 2>$null | ForEach-Object { Write-Host "  $_" }
  $short = if ($remoteSha) { $remoteSha.Substring(0,12) } else { "" }
  # Does the staged channel hold commits that are not on the current branch? (needs the remote tip locally)
  $diverged = $false
  if ($remoteSha -and -not ($B -ceq $br)) {
    & git -C $p fetch -q origin "+refs/heads/${br}:refs/remotes/origin/$br" 2>$null
    & git -C $p merge-base --is-ancestor $remoteSha HEAD 2>$null
    $diverged = ($LASTEXITCODE -ne 0)
  }
  $mode = "push"
  if ($B -ceq $br) {
    if ($remoteSha) { Write-Host "  origin/$br exists at $short; this push fast-forwards it (no force)." }
    else { Write-Host "  origin/$br does not exist yet; this push creates it." }
    if (-not $dirty) { Write-Host "  (no working changes -- the branch is still pushed at HEAD so the channel includes $n)" }
    if (-not (Confirm "  stage $n to ${br}?")) { Write-Host "  skipped $n"; $skipped += $n; Restore-Branch $n $p $back; continue }
  } elseif ($diverged -and -not $dirty) {
    Write-Host "  origin/$br ($short) already holds staged commits for $n that are not on '$B', and you have no new changes."
    Write-Host "  Left as is -- the channel keeps what was staged."
    $unchanged += $n; continue
  } elseif ($diverged) {
    Write-Host "  You have changes on '$B', but origin/$br ($short) holds staged commits that are NOT on '$B'."
    Write-Host "  Staging from '$B' would DROP those staged commits from the channel."
    Write-Host "  To ADD these changes to the candidate instead (usual case), run this, then re-run this script:"
    Write-Host "    git -C `"$p`" stash; git -C `"$p`" checkout $br; git -C `"$p`" stash pop"
    if ($Yes) { Write-Host "  skipped $n (-Yes never replaces a channel)"; $skipped += $n; continue }
    $a = Read-Host "  Type REPLACE to start a NEW candidate for $n from '$B' (anything else skips it)"
    if ($a -cne "REPLACE") { Write-Host "  skipped $n"; $skipped += $n; continue }
    & git -C $p checkout -B $br; if ($LASTEXITCODE -ne 0) { Die "checkout -B $br failed for $n" }
    $mode = "replace"
  } else {
    if ($remoteSha) { Write-Host "  origin/$br is at $short, already contained in '$B'; this push fast-forwards it to '$B' + your working changes." }
    else { Write-Host "  origin/$br does not exist yet; it will be created from '$B' + your working changes." }
    if (-not $dirty) { Write-Host "  (no working changes -- the branch is still pushed at HEAD so the channel includes $n)" }
    if (-not (Confirm "  switch $n to $br (git checkout -B, keeps working changes) and stage it?")) { Write-Host "  skipped $n"; $skipped += $n; continue }
    & git -C $p checkout -B $br; if ($LASTEXITCODE -ne 0) { Die "checkout -B $br failed for $n" }
  }
  & git -C $p add -A; if ($LASTEXITCODE -ne 0) { Fail-Repo $n $p $back "git add failed for $n" }
  & git -C $p diff --cached --quiet
  if ($LASTEXITCODE -eq 0) { Write-Host "  nothing to commit -- pushing $br at HEAD" }
  else {
    & git -C $p commit -q -m "stage(${Channel}): $n v$v"; if ($LASTEXITCODE -ne 0) { Fail-Repo $n $p $back "commit failed for $n" }
    Write-Host "  committed: $(& git -C $p log --oneline -1)"
  }
  if ($B -ceq $br) {
    $ok = Push-AndReport $p @("-u", "origin", "refs/heads/${br}:refs/heads/$br")
    if (-not $ok) { Fail-Repo $n $p $back "push failed for $n (no force used; stopping before later repos so catalogs stay last)" }
  } else {
    # Explicit lease: the remote branch must still be what ls-remote saw (or still absent).
    # Only the REPLACE path can drop remote commits; every other path is a fast-forward.
    $ok = Push-AndReport $p @("-u", "--force-with-lease=refs/heads/${br}:$remoteSha", "origin", "refs/heads/${br}:refs/heads/$br")
    if (-not $ok) { Fail-Repo $n $p $back "push failed for $n (stopping before later repos so catalogs stay last)" }
  }
  if ($mode -eq "replace") { Write-Host "  origin/$br REPLACED for $n." }
  $staged += $n
  Restore-Branch $n $p $back
}

Write-Host ""
Write-Host "=================== STAGE COMPLETE: channel '$Channel' ==================="
$stagedTxt = if ($staged.Count -gt 0) { $staged -join ' ' } else { "none" }
Write-Host "Staged to $br (origin): $stagedTxt"
if ($unchanged.Count -gt 0) { Write-Host "Already on the channel, nothing new (left as is): $($unchanged -join ' ')" }
if ($StayOnChannel) { Write-Host "-StayOnChannel: staged repos are left checked out on $br." }
else {
  if ($returned.Count -gt 0) { Write-Host "Checked out again (cleanup): $($returned -join ', ')" }
  if ($notReturned.Count -gt 0) { Write-Host "COULD NOT switch back -- still on ${br}: $($notReturned -join '; ')" }
  Write-Host "The staged changes live on $br (local and origin); your default branches are as they were before staging."
}
if ($skipped.Count -gt 0) { Write-Host "Skipped (NOT on the channel -- the test org will not see them): $($skipped -join ' ')" }
Write-Host "No tags were created. No default branch was pushed."
Write-Host ""
Write-Host "NEXT -- on the TEST org's admin install:"
Write-Host "  1. Create the org with distribution channel '$Channel', or set it via edit-org (`"Distribution channel`")."
Write-Host "  2. Refresh the clones (they now resolve $br)."
Write-Host "  3. Say `"publish our org updates`"."
Write-Host "Iterate: git checkout $br in the repo(s) you're changing, edit, re-run this script (fast-forward"
Write-Host "  pushes, no force; each repo goes back to its branch afterwards). Repos you didn't touch are left as is."
Write-Host ""
Write-Host "PROMOTE when the candidate passes, per repo (code repos first, listings last):"
Write-Host "  1. Open a PR $br -> <default branch>, and merge it."
Write-Host "  2. powershell -ExecutionPolicy Bypass -File lib\release\release-push.ps1 -Manifest $Manifest -TagOnly"
Write-Host "  3. git checkout <default branch>; git pull; git branch -D $br"
exit 0
# AIFS:FILE-END
