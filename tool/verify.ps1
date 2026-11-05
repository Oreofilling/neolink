# NeoLink unattended verification loop (v7d+ automation tier).
#
# Chains everything the box can run without a human:
#   pub get -> plugin junction repair -> gen-l10n -> analyze x4 ->
#   widget tests x4 -> E2E on the real exe -> real-device probe.
#
# The real-device step runs a detect pass first: if no CT-Prov device is
# advertising it is recorded as SKIP (press the device config key, rerun
# to include the loop). Every run appends a dated gate record to
# docs\gate-records - the M6 "gate records archived in repo" deliverable.
#
# Usage (PowerShell on the build box):
#   powershell -NoProfile -ExecutionPolicy Bypass -File tool\verify.ps1
#   powershell ... -File tool\verify.ps1 -SkipDevice     # no BLE at all
#   powershell ... -File tool\verify.ps1 -Cycles 5 -KillAt editing
#
# Pure ASCII on purpose: PS 5.1 reads BOM-less UTF-8 scripts as ANSI/GBK.

param(
  [switch]$SkipDevice,
  [int]$Cycles = 3,
  [string]$KillAt = 'none'
)

$repo = Split-Path -Parent $PSScriptRoot
$app = Join-Path $repo 'apps\desktop_app'
$started = Get-Date
$results = New-Object System.Collections.Generic.List[object]
$script:failed = $false
$script:detectOut = ''

# Detached runs (WMI/scheduled task launch) may lose their stdout pipe;
# the transcript is the record that survives any launch weirdness.
$transcript = Join-Path $env:TEMP 'neolink-verify.log'
Start-Transcript -Path $transcript -Append | Out-Null

function Invoke-Step {
  param([string]$Name, [scriptblock]$Body)
  Write-Host ""
  Write-Host "=== $Name ===" -ForegroundColor Cyan
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $detail = ''
  try {
    $out = & $Body 2>&1 | Out-String
    $tail = ($out -split "`r?`n" | Where-Object { $_ -ne '' } |
      Select-Object -Last 2) -join ' | '
    if ($LASTEXITCODE -eq 0) { $state = 'PASS' }
    else { $state = 'FAIL'; $script:failed = $true }
    $detail = $tail
    if ($tail -ne '') { Write-Host $tail }
  } catch {
    $state = 'FAIL'
    $detail = $_.Exception.Message
    $script:failed = $true
  }
  $sw.Stop()
  [void]$results.Add([pscustomobject]@{
    Step = $Name; State = $state
    Seconds = [math]::Round($sw.Elapsed.TotalSeconds); Detail = $detail
  })
  Write-Host "[$state] $Name ($([math]::Round($sw.Elapsed.TotalSeconds))s)"
}

Set-Location $app

Invoke-Step 'pub get' { flutter pub get }

Invoke-Step 'plugin junctions' {
  $links = "$app\windows\flutter\ephemeral\.plugin_symlinks"
  $cache = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev"
  $plugins = @(
    'universal_ble|universal_ble-3.1.2',
    'file_selector_windows|file_selector_windows-0.9.3+6',
    'flutter_zxing|flutter_zxing-1.9.1',
    'camera_windows|camera_windows-0.3.0+1'
  )
  foreach ($p in $plugins) {
    $n, $v = $p.Split('|')
    cmd /c rmdir "$links\$n" 2>$null
    cmd /c mklink /J "$links\$n" "$cache\$v" | Out-Null
  }
  if (Test-Path "$links\universal_ble\pubspec.yaml") {
    $global:LASTEXITCODE = 0
  } else {
    Write-Output 'universal_ble junction broken'
    $global:LASTEXITCODE = 1
  }
}

Invoke-Step 'gen-l10n' { flutter gen-l10n }

Invoke-Step 'analyze neolink_ui' { Set-Location "$repo\packages\neolink_ui"; dart analyze }
Invoke-Step 'analyze ble_universal' { Set-Location "$repo\packages\ble_universal"; dart analyze }
Invoke-Step 'analyze provisioning_session' { Set-Location "$repo\packages\provisioning_session"; dart analyze }
Invoke-Step 'analyze desktop_app' { Set-Location $app; dart analyze }

Invoke-Step 'test neolink_ui' { Set-Location "$repo\packages\neolink_ui"; flutter test }
# flutter test, NOT dart test: the VM platform has no dart:ui.
Invoke-Step 'test ble_universal' { Set-Location "$repo\packages\ble_universal"; flutter test }
Invoke-Step 'test provisioning_session' { Set-Location "$repo\packages\provisioning_session"; flutter test }
Invoke-Step 'test desktop_app' { Set-Location $app; flutter test }

Invoke-Step 'E2E real exe' {
  Set-Location $app
  flutter test integration_test\app_e2e_test.dart -d windows
}

if ($SkipDevice) {
  [void]$results.Add([pscustomobject]@{
    Step = 'real device probe'; State = 'SKIP'; Seconds = 0; Detail = '-SkipDevice'
  })
} else {
  Invoke-Step 'probe detect' {
    Set-Location $app
    $env:NL_PROBE_MODE = 'detect'
    # Absence of a device is a SKIP decided below, never a FAIL here.
    $script:detectOut = & flutter test integration_test\real_device_probe_test.dart -d windows 2>&1 | Out-String
    $global:LASTEXITCODE = 0
  }
  if ($script:detectOut -match 'RESULT=device-found') {
    Invoke-Step "probe full x$Cycles (killAt=$KillAt)" {
      Set-Location $app
      $env:NL_PROBE_MODE = 'full'
      $env:NL_PROBE_CYCLES = "$Cycles"
      $env:NL_PROBE_KILL_AT = $KillAt
      flutter test integration_test\real_device_probe_test.dart -d windows
    }
  } else {
    [void]$results.Add([pscustomobject]@{
      Step = 'real device probe'; State = 'SKIP'; Seconds = 0
      Detail = 'no CT-Prov advertisement (wake the device, rerun)'
    })
  }
  Remove-Item Env:NL_PROBE_MODE, Env:NL_PROBE_CYCLES, Env:NL_PROBE_KILL_AT -ErrorAction SilentlyContinue
}

# ---- gate record ----
$head = git -C $repo log --oneline -1
$dir = Join-Path $repo 'docs\gate-records'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir ("verify-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$lines = @()
$lines += "# Gate record - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$lines += ""
$lines += "- HEAD: $head"
$lines += "- Total: $([math]::Round(((Get-Date) - $started).TotalSeconds))s"
$lines += ""
$lines += "| Step | State | s | Detail |"
$lines += "|---|---|---|---|"
foreach ($r in $results) {
  $d = if ($r.Detail.Length -gt 90) { $r.Detail.Substring(0, 90) + '...' } else { $r.Detail }
  $lines += "| $($r.Step) | $($r.State) | $($r.Seconds) | $d |"
}
Set-Content -Path $file -Value ($lines -join "`r`n") -Encoding ASCII
Write-Host ""
Write-Host "Gate record: $file"
Write-Host ""
Stop-Transcript | Out-Null
if ($script:failed) {
  Write-Host "VERIFY: FAIL" -ForegroundColor Red
  exit 1
}
Write-Host "VERIFY: ALL GREEN" -ForegroundColor Green
exit 0
