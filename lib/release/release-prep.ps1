# release-prep.ps1 -- committed release build+prep tool (developer lib/release; level-3).
# Reads a release-delta manifest and runs the prep phase (adapter build+checksum if flagged ->
# manifest collection_version restamp -> preflight hard gate). NO git writes; safe to re-run.
# Usage: powershell -ExecutionPolicy Bypass -File release-prep.ps1 -Manifest <manifest.json>
param([Parameter(Mandatory=$true)][string]$Manifest)
$ErrorActionPreference = "Continue"
function Die([string]$m){ Write-Host "FATAL: $m"; exit 2 }

# Locate the Git bash explicitly (avoids WSL bash, which needs /mnt/c and cannot see the repos here).
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
# Convert a Windows path (C:\a\b) to Git-Bash form (/c/a/b) for arguments used inside the shell script.
function ConvertTo-BashPath([string]$p) {
  $p = $p -replace '\\','/'
  if ($p -match '^([A-Za-z]):/(.*)$') { return '/' + $Matches[1].ToLower() + '/' + $Matches[2] }
  return $p
}

if (-not (Test-Path $Manifest)) { Die "manifest not found: $Manifest" }
$self = Split-Path -Parent $MyInvocation.MyCommand.Path
$preflight = Join-Path $self "..\preflight-cli.sh"
if (-not (Test-Path $preflight)) { Die "preflight-cli.sh not found at $preflight" }
try { $m = Get-Content -Raw $Manifest | ConvertFrom-Json } catch { Die "manifest not valid JSON" }
$bash = Get-GitBash
if (-not $bash) { Die "could not find bash (Git for Windows provides it). Install Git, or run the .sh prep under bash." }
$bashPreflight = ConvertTo-BashPath ((Resolve-Path $preflight).Path)

# An empty repo list must never reach "PREP OK".
if (@($m.repos).Count -eq 0) { Die "manifest lists no repos ($Manifest) -- nothing to prep" }
$fail = $false; $nPrepped = 0
foreach ($r in $m.repos) {
  $nPrepped++
  $name = "$($r.name)"; $path = "$($r.path)"; $ver = "$($r.version)"
  Write-Host "== prep: $name v$ver =="
  if (-not (Test-Path $path)) { Write-Host "  FAIL: repo path missing: $path"; $fail = $true; continue }
  $kind = "collection"
  if (-not (Test-Path (Join-Path $path "collection.json"))) {
    if (Test-Path (Join-Path $path "adapter.json")) { $kind = "adapter" }
    else { Write-Host "  (no collection.json / adapter.json -- directory/listings repo; skipping preflight + restamp, will be pushed as-is)"; Write-Host "  OK prep $name"; continue }
  }
  $adapterJson = Join-Path $path "adapter.json"

  # 1. adapter: version gate (adapter.json), build (only when flagged is_adapter), checksum + node --check
  if ($kind -eq "adapter") {
    $aj = (Get-Content -Raw $adapterJson)
    $av = if ($aj -match '"version"\s*:\s*"([^"]+)"') { $Matches[1] } else { "" }
    if ($av -ne $ver) { Write-Host "  FAIL: adapter.json version is $av, manifest says $ver"; $fail = $true; continue }
    if ($r.is_adapter -ne $true) { Write-Host "  note: adapter.json present but is_adapter is not set -- no build; verifying the existing bundle" }
  }
  if ($r.is_adapter -eq $true) {
    Push-Location $path; & npm run build; $rc = $LASTEXITCODE; Pop-Location
    if ($rc -ne 0) { Write-Host "  FAIL: npm run build"; $fail = $true; continue }
  }
  if ($r.is_adapter -eq $true -or $kind -eq "adapter") {
    $b = Join-Path $path "dist/aifs-exec.bundle.js"
    if (-not (Test-Path $b)) {
      if ($r.is_adapter -eq $true) { Write-Host "  FAIL: $b missing after build"; $fail = $true; continue }
      Write-Host "  note: no built bundle at $b -- checksum not verified (flag is_adapter to build)"
    } else {
      $actual = (Get-FileHash -Algorithm SHA256 -Path $b).Hash.ToLower()
      # exec_bundle_checksum may be bare hex or "sha256:<hex>"
      $hit = Select-String -Path $adapterJson -Pattern '"exec_bundle_checksum"\s*:\s*"(sha256:)?([0-9a-fA-F]{64})"' | Select-Object -First 1
      $stamped = if ($hit) { $hit.Matches[0].Groups[2].Value.ToLower() } else { "" }
      if (-not $stamped) { Write-Host "  FAIL: adapter.json exec_bundle_checksum missing or not <hex64> / sha256:<hex64>"; $fail = $true; continue }
      if ($actual -ne $stamped) { Write-Host "  FAIL: checksum mismatch ($stamped vs $actual)"; $fail = $true; continue }
      & node --check $b; if ($LASTEXITCODE -ne 0) { Write-Host "  FAIL: node --check bundle"; $fail = $true; continue }
      Write-Host "  adapter bundle checksum verified"
    }
  }

  # 2. restamp api/*-manifest.json collection_version
  $apiDir = Join-Path $path "api"
  if ($kind -eq "collection" -and (Test-Path $apiDir)) {
    Get-ChildItem -Path $apiDir -Filter "*-manifest.json" | ForEach-Object {
      try { $j = Get-Content -Raw $_.FullName | ConvertFrom-Json } catch { return }
      if (($j.PSObject.Properties.Name -contains 'collection_version') -and ("$($j.collection_version)" -ne $ver) -and $ver) {
        $j.collection_version = $ver
        ($j | ConvertTo-Json -Depth 40) | Set-Content -Path $_.FullName -Encoding ascii
        Write-Host ("  restamped " + $_.Name + " -> " + $ver)
      }
    }
  }

  # 3. preflight HARD GATE (after stamping, so Check 2 sees aligned manifests).
  # preflight-cli needs collection.json; for an adapter repo the checksum + node --check gate above
  # is the verification (it is what preflight Check 14 checks).
  if ($kind -eq "adapter") { Write-Host "  (adapter repo: preflight-cli needs collection.json -- checksum gate above is the verification)"; Write-Host "  OK prep $name"; continue }
  $bashColl = ConvertTo-BashPath ((Resolve-Path $path).Path)
  $pf = & $bash "$bashPreflight" --collection "$bashColl" 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host "  FAIL: preflight did not pass -- output:"
    ($pf | Select-Object -Last 20) | ForEach-Object { Write-Host "    $_" }
    $fail = $true; continue
  }
  Write-Host "  OK prep $name"
}
if ($fail) { Write-Host ""; Write-Host "PREP FAILED -- fix the above before push."; exit 1 }
if ($nPrepped -eq 0) { Die "no repos were prepped -- refusing to report PREP OK" }
Write-Host ""; Write-Host "PREP OK -- $nPrepped repo(s) gated + stamped. Next: release-push.ps1 -Manifest $Manifest"
exit 0
# AIFS:FILE-END
