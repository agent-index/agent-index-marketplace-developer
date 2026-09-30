# release-push.ps1 -- committed gated push+tag tool (developer lib/release; level-3).
# PRE-PUSH DIFF + INTEGRITY GATE -> remote-URL HTTPS guard -> CHANGELOG date-stamp -> per-repo
# commit/push/tag in push_order (resource-listings LAST; never move a published tag). Host-run only.
#
# Branch-aware (developer 1.13.0): a release tag must point at a commit on the repo's default
# branch. Run from the default branch, this behaves as before (commit -> push -> tag). Run from
# any other branch (the PR workflow), it commits and pushes the branch, then DEFERS tagging --
# open the PR, merge it, then run with -TagOnly to tag the merged commit on origin/<default>.
#
# Usage: powershell -ExecutionPolicy Bypass -File release-push.ps1 -Manifest <manifest.json>            # commit + push (+ tag on default branch)
#        powershell -ExecutionPolicy Bypass -File release-push.ps1 -Manifest <manifest.json> -TagOnly   # after merge: tag origin/<default>
param([Parameter(Mandatory=$true)][string]$Manifest, [switch]$TagOnly)
$ErrorActionPreference = "Continue"
function Die([string]$m){ Write-Host "FATAL: $m"; exit 2 }
function Confirm([string]$m){ $a = Read-Host "$m [y/N]"; return ($a -eq "y" -or $a -eq "Y") }
if (-not (Test-Path $Manifest)) { Die "manifest not found: $Manifest" }
try { $m = Get-Content -Raw $Manifest | ConvertFrom-Json } catch { Die "manifest not valid JSON" }
$today = Get-Date -Format "yyyy-MM-dd"
$paths = @{}; $vers = @{}
foreach ($r in $m.repos) { $paths["$($r.name)"] = "$($r.path)"; $vers["$($r.name)"] = "$($r.version)" }
$order = @($m.push_order)
if ($order.Count -eq 0) { Die "manifest push_order is empty" }

# The repo's default branch, from origin/HEAD; falls back to main, then master.
function Get-DefaultBranch([string]$p) {
  $b = (& git -C $p symbolic-ref --short refs/remotes/origin/HEAD 2>$null)
  if ($b) { return ("$b" -replace '^origin/','') }
  & git -C $p show-ref --verify --quiet refs/remotes/origin/main 2>$null; if ($LASTEXITCODE -eq 0) { return "main" }
  & git -C $p show-ref --verify --quiet refs/remotes/origin/master 2>$null; if ($LASTEXITCODE -eq 0) { return "master" }
  return "main"
}
# Run a git push, show its output, and surface a GitHub rule bypass instead of burying it.
function Push-AndReport([string]$p, [string[]]$pushArgs) {
  $out = (& git -C $p push @pushArgs 2>&1 | ForEach-Object { "$_" }); $rc = $LASTEXITCODE
  $out | ForEach-Object { Write-Host "  $_" }
  $txt = ($out -join "`n")
  if ($txt -match "Bypassed rule violations") {
    Write-Host "  WARNING: this push only succeeded by BYPASSING the repo's rules (see above). Anyone without"
    Write-Host "           bypass rights will be rejected -- release from a branch + PR, then -TagOnly."
  }
  if ($rc -ne 0 -and $txt -match "protected branch|must be made through a pull request|GH006|GH013") {
    Write-Host "  The default branch requires a pull request. Check out a release branch, re-run this"
    Write-Host "  script to push it, open the PR, then run with -TagOnly after it merges."
  }
  return ($rc -eq 0)
}
# Tag commit $sha as v$v, never moving a published tag.
function Set-ReleaseTag([string]$p, [string]$v, [string]$sha, [string]$n) {
  $tag = "v$v"
  if (& git -C $p tag -l $tag) {
    $at = (& git -C $p rev-list -n1 $tag)
    if ($at -eq $sha) { Write-Host "  tag $tag already at $sha -- left as is" }
    else { Write-Host "  WARNING: tag $tag exists but points elsewhere ($at). NOT moving it. Cut a NEW version if a re-tag is needed." }
    return
  }
  if (-not (Confirm "  tag $n $tag at $($sha.Substring(0,12)) and push tag?")) { Write-Host "  skipped tag"; return }
  & git -C $p tag -a $tag $sha -m "release $tag"; if ($LASTEXITCODE -ne 0) { Die "tag failed for $n" }
  if (-not (Push-AndReport $p @("origin", $tag))) { Die "tag push failed for $n" }
}
function Write-DistHandoff {
  if ($m.dist_publish -eq $true) {
    Write-Host "DIST PUBLISH HANDOFF: clone at the new tags (lib/clone) then run create-org/apply-updates to"
    Write-Host "diff the clone against the backend and republish /shared/dist/ + manifest.json; verify the manifest."
  }
}

# ---- -TagOnly: after the release PRs merged, tag the merged commit on each default branch ----
if ($TagOnly) {
  Write-Host "=================== TAG-ONLY: tag merged releases on the default branch ==================="
  foreach ($n in $order) {
    $p = $paths[$n]; $v = $vers[$n]
    if (-not (Test-Path (Join-Path $p ".git"))) { Write-Host "SKIP $n (no git repo)"; continue }
    if (-not $v) { Write-Host "SKIP $n (no version in manifest)"; continue }
    Write-Host ""; Write-Host "----- $n v$v -----"
    & git -C $p fetch origin --tags --quiet; if ($LASTEXITCODE -ne 0) { Die "fetch failed for $n" }
    $db = Get-DefaultBranch $p
    $sha = (& git -C $p rev-parse "origin/$db" 2>$null); if ($LASTEXITCODE -ne 0 -or -not $sha) { Die "no origin/$db in $n" }
    Write-Host "  origin/$db is at $(& git -C $p log --oneline -1 $sha)"
    & git -C $p cat-file -e "${sha}:collection.json" 2>$null
    if ($LASTEXITCODE -eq 0) {
      $cj = (& git -C $p show "${sha}:collection.json") -join "`n"
      $got = if ($cj -match '"version"\s*:\s*"([^"]+)"') { $Matches[1] } else { "" }
      if ($got -ne $v) { Die "${n}: origin/$db collection.json is $got, manifest says $v -- has the release PR merged? Stopping before later repos (listings stay last)." }
    }
    Set-ReleaseTag $p $v $sha $n
  }
  Write-Host ""; Write-DistHandoff; Write-Host "TAG-ONLY COMPLETE."; exit 0
}

Write-Host "=================== PRE-PUSH DIFF + INTEGRITY GATE ==================="
$integrityFail = $false
foreach ($n in $order) {
  $p = $paths[$n]; if (-not (Test-Path (Join-Path $p ".git"))) { Write-Host "SKIP $n (no git repo)"; continue }
  Write-Host ""; Write-Host "----- $n ($p) -----"
  $url = (& git -C $p remote get-url origin 2>$null)
  if (-not $url) { Write-Host "  no origin remote -- git -C $p remote add origin <https-url>"; $integrityFail = $true }
  elseif ($url -notlike "https://*") { Write-Host "  origin NOT https ($url) -- git -C $p remote set-url origin <https-url>"; $integrityFail = $true }
  $changed = & git -C $p diff --name-only HEAD 2>$null
  foreach ($f in $changed) {
    if ($f -match '\.(md|sh|js|json)$') {
      $fp = Join-Path $p $f
      if ((Test-Path $fp) -and (Get-Item $fp).Length -gt 0) {
        $bytes = [IO.File]::ReadAllBytes($fp)
        if ($bytes[$bytes.Length-1] -ne 10) { Write-Host "  INTEGRITY: $f does not end in a newline (possible truncation)"; $integrityFail = $true }
      }
      $headHas = (& git -C $p show "HEAD:$f" 2>$null | Select-String -Pattern 'AIFS:FILE-END' -Quiet)
      if ($headHas) { if (-not (Select-String -Path $fp -Pattern 'AIFS:FILE-END' -Quiet)) { Write-Host "  INTEGRITY: $f lost its AIFS:FILE-END sentinel vs HEAD (truncation?)"; $integrityFail = $true } }
      if ($f -match '\.md$' -and (Test-Path $fp)) {
        $nb = (Get-Content $fp) | Where-Object { $_ -match '\S' }
        $lastLine = if ($nb) { $nb[-1] } else { "" }
        $hasSent = (Select-String -Path $fp -Pattern 'AIFS:FILE-END' -Quiet)
        if (($lastLine -match '[A-Za-z0-9]$') -and -not $hasSent) { Write-Host "  INTEGRITY: $f last line ends mid-word with no terminator/sentinel (likely truncated)"; $integrityFail = $true }
      }
    }
  }
  Write-Host "  --- git diff --stat HEAD ---"; & git -C $p diff --stat HEAD 2>$null | ForEach-Object { Write-Host "  $_" }
  Write-Host "  (full diff -- review it)"; (& git -C $p --no-pager diff HEAD 2>$null | Select-Object -First 400) | ForEach-Object { Write-Host "  | $_" }
}
Write-Host ""
if ($integrityFail) { Write-Host "INTEGRITY GATE FLAGGED ISSUES ABOVE."; if (-not (Confirm "Proceed ANYWAY? Only if every flag is understood and intended.")) { Die "aborted at integrity gate" } }
if (-not (Confirm "Have you reviewed EVERY diff above and confirm all changes are intended?")) { Die "aborted at diff-review gate" }

Write-Host "=================== DATE-STAMP + PUSH ==================="
$deferred = $false
foreach ($n in $order) {
  $p = $paths[$n]; $v = $vers[$n]; if (-not (Test-Path (Join-Path $p ".git"))) { Write-Host "SKIP $n"; continue }
  Write-Host ""; Write-Host "----- pushing $n v$v -----"
  $cl = Join-Path $p "CHANGELOG.md"
  if ((Test-Path $cl) -and (Select-String -Path $cl -Pattern '<RELEASE_DATE>' -Quiet)) {
    (Get-Content -Raw $cl) -replace '<RELEASE_DATE>', $today | Set-Content -Path $cl -Encoding utf8; Write-Host "  stamped CHANGELOG date -> $today"
  }
  & git -C $p add -A
  & git -C $p diff --cached --quiet; $hasStaged = ($LASTEXITCODE -ne 0)
  if ($hasStaged) { if (Confirm "  commit $n?") { & git -C $p commit -m "release: $n v$v"; if ($LASTEXITCODE -ne 0) { Die "commit failed for $n" } } else { Write-Host "  skipped commit"; continue } }
  else { Write-Host "  nothing staged" }
  if (-not (Confirm "  push $n to origin?")) { Write-Host "  skipped push"; continue }
  $cur = (& git -C $p rev-parse --abbrev-ref HEAD); $db = Get-DefaultBranch $p
  $pushArgs = if ($cur -eq $db) { @("origin", "HEAD") } else { @("-u", "origin", "HEAD") }
  if (-not (Push-AndReport $p $pushArgs)) { Die "push failed for $n" }
  if (-not $v) { Write-Host "  no version supplied for $n -- pushed, tag SKIPPED (set version in the manifest if tag-pinned, e.g. resource-listings)"; continue }
  if ($cur -ne $db) {
    # A tag must point at the commit that lands on the default branch; a squash/rebase merge
    # would leave a pre-merge tag pointing at a commit that is not on it.
    Write-Host "  on branch '$cur', not '$db': tag v$v DEFERRED. Open a PR $cur -> $db; after it merges run:"
    Write-Host "      release-push.ps1 -Manifest $Manifest -TagOnly"
    $deferred = $true; continue
  }
  Set-ReleaseTag $p $v (& git -C $p rev-parse HEAD) $n
}
Write-Host ""
if ($deferred) {
  Write-Host "PUSH COMPLETE -- TAGS DEFERRED. Merge the release PR(s) (code repos first, listings last), then:"
  Write-Host "    powershell -ExecutionPolicy Bypass -File release-push.ps1 -Manifest $Manifest -TagOnly"
  exit 0
}
Write-DistHandoff
Write-Host "PUSH COMPLETE."
exit 0
