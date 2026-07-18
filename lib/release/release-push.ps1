# release-push.ps1 -- committed gated push+tag tool (developer lib/release; level-3).
# PRE-PUSH DIFF + INTEGRITY GATE -> remote-URL HTTPS guard -> CHANGELOG date-stamp -> per-repo
# commit/push/tag in push_order (resource-listings LAST; never move a published tag). Host-run only.
# Usage: powershell -ExecutionPolicy Bypass -File release-push.ps1 -Manifest <manifest.json>
param([Parameter(Mandatory=$true)][string]$Manifest)
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
  & git -C $p push origin HEAD; if ($LASTEXITCODE -ne 0) { Die "push failed for $n" }
  if (-not $v) { Write-Host "  no version supplied for $n -- pushed, tag SKIPPED (set version in the manifest if tag-pinned, e.g. resource-listings)"; continue }
  $tag = "v$v"; $existing = (& git -C $p tag -l $tag)
  if ($existing) {
    $at = (& git -C $p rev-list -n1 $tag); $head = (& git -C $p rev-parse HEAD)
    if ($at -eq $head) { Write-Host "  tag $tag already at HEAD -- left as is" }
    else { Write-Host "  WARNING: tag $tag points elsewhere ($at). NOT moving it. Cut a NEW version if a re-tag is needed." }
  } else {
    if (Confirm "  tag $n $tag and push tag?") { & git -C $p tag -a $tag -m "release $tag"; & git -C $p push origin $tag } else { Write-Host "  skipped tag" }
  }
}
Write-Host ""
if ($m.dist_publish -eq $true) {
  Write-Host "DIST PUBLISH HANDOFF: clone at the new tags (lib/clone) then run create-org/apply-updates to"
  Write-Host "diff the clone against the backend and republish /shared/dist/ + manifest.json; verify the manifest."
}
Write-Host "PUSH COMPLETE."
exit 0
