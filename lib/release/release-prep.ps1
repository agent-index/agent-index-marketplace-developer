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

$fail = $false
foreach ($r in $m.repos) {
  $name = "$($r.name)"; $path = "$($r.path)"; $ver = "$($r.version)"
  Write-Host "== prep: $name v$ver =="
  if (-not (Test-Path $path)) { Write-Host "  FAIL: repo path missing: $path"; $fail = $true; continue }
  if (-not (Test-Path (Join-Path $path "collection.json"))) { Write-Host "  (no collection.json -- directory/listings repo; skipping preflight + restamp, will be pushed as-is)"; Write-Host "  OK prep $name"; continue }

  # 1. adapter build + checksum (only when flagged)
  if ($r.is_adapter -eq $true) {
    Push-Location $path; & npm run build; $rc = $LASTEXITCODE; Pop-Location
    if ($rc -ne 0) { Write-Host "  FAIL: npm run build"; $fail = $true; continue }
    $b = Join-Path $path "dist/aifs-exec.bundle.js"
    $actual = (Get-FileHash -Algorithm SHA256 -Path $b).Hash.ToLower()
    $stamped = (Select-String -Path (Join-Path $path "adapter.json") -Pattern '"exec_bundle_checksum"\s*:\s*"([0-9a-f]{64})"' | Select-Object -First 1).Matches.Groups[1].Value
    if ($actual -ne $stamped) { Write-Host "  FAIL: checksum mismatch after build ($stamped vs $actual)"; $fail = $true; continue }
    & node --check $b; if ($LASTEXITCODE -ne 0) { Write-Host "  FAIL: node --check bundle"; $fail = $true; continue }
    Write-Host "  adapter bundle built + checksum verified"
  }

  # 2. restamp api/*-manifest.json collection_version
  $apiDir = Join-Path $path "api"
  if (Test-Path $apiDir) {
    Get-ChildItem -Path $apiDir -Filter "*-manifest.json" | ForEach-Object {
      try { $j = Get-Content -Raw $_.FullName | ConvertFrom-Json } catch { return }
      if (($j.PSObject.Properties.Name -contains 'collection_version') -and ("$($j.collection_version)" -ne $ver) -and $ver) {
        $j.collection_version = $ver
        ($j | ConvertTo-Json -Depth 40) | Set-Content -Path $_.FullName -Encoding ascii
        Write-Host ("  restamped " + $_.Name + " -> " + $ver)
      }
    }
  }

  # 3. preflight HARD GATE (after stamping, so Check 2 sees aligned manifests)
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
Write-Host ""; Write-Host "PREP OK -- all repos gated + stamped. Next: release-push.ps1 -Manifest $Manifest"
exit 0
