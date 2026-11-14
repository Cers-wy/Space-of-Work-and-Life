param(
  [string]$Flutter = "$PSScriptRoot/../../work/flutter-sdk-bootstrap/flutter/bin/flutter.bat",
  [string[]]$TestFiles
)
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$root = Split-Path $project -Parent
$logs = Join-Path $root 'work/windows-baseline/unit'
New-Item -ItemType Directory -Force $logs | Out-Null
$env:PUB_CACHE = Join-Path $root 'work/flutter-sdk-bootstrap/pub-cache'
$env:TEMP = Join-Path $root 'work/windows-baseline/temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force $env:TEMP | Out-Null
& "$PSScriptRoot/configure_windows_tests.ps1" -FlutterRoot (Split-Path (Split-Path $Flutter -Parent) -Parent)
Add-Type @'
using System.Runtime.InteropServices;
public static class SpaceTestErrorMode {
  [DllImport("kernel32.dll")] public static extern uint SetErrorMode(uint mode);
}
'@
# Process-local only: native crashes still fail the test and remain in logs.
$previousErrorMode = [SpaceTestErrorMode]::SetErrorMode(3)
foreach ($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy')) {
  Remove-Item "Env:$key" -ErrorAction SilentlyContinue
}
$env:NO_PROXY = 'localhost,127.0.0.1,::1'
$resultFile = Join-Path $project 'verification/windows-2026-11-13/unit-test-results.json'
$rows = if ($TestFiles -and (Test-Path $resultFile)) { @(Get-Content $resultFile -Raw | ConvertFrom-Json) } else { @() }
Push-Location $project
try {
  $source = (git rev-parse HEAD).Trim()
  $files = if ($TestFiles) { $TestFiles | ForEach-Object { Get-Item $_ } } else { Get-ChildItem test -Filter '*test.dart' | Sort-Object Name }
  foreach ($file in $files) {
    $env:SPACE_FLUTTER_DATA_DIRECTORY = Join-Path $root ('work/windows-baseline/app-data/' + $file.BaseName)
    $log = Join-Path $logs ($file.BaseName + '.jsonl')
    $errors = Join-Path $logs ($file.BaseName + '.stderr.log')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    & $Flutter test --no-pub --reporter json "test/$($file.Name)" 1> $log 2> $errors
    $code = $LASTEXITCODE
    $events = @(Get-Content $log | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
    $ends = @($events | Where-Object type -EQ 'testDone')
    $rows = @($rows | Where-Object file -NE ('test/' + $file.Name))
    $rows += [pscustomobject]@{
      id = 'UT-' + $file.BaseName; file = 'test/' + $file.Name; source = $source
      status = $(if ($code -eq 0) {'passed'} else {'failed'})
      exitCode = $code; seconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
      passed = @($ends | Where-Object { $_.result -eq 'success' -and !$_.hidden -and !$_.skipped }).Count
      failed = @($ends | Where-Object result -EQ 'error').Count
      skipped = @($ends | Where-Object skipped -EQ $true).Count
      log = 'work/windows-baseline/unit/' + $file.BaseName + '.jsonl'
    }
    $rows | ConvertTo-Json -Depth 5 | Set-Content verification/windows-2026-11-13/unit-test-results.json -Encoding utf8
    Write-Output "$($file.Name): exit=$code"
  }
} finally {
  Pop-Location
  [SpaceTestErrorMode]::SetErrorMode($previousErrorMode) | Out-Null
}
if (@($rows | Where-Object status -EQ 'failed').Count) { exit 1 }
