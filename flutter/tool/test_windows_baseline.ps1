param([string]$Flutter = "$PSScriptRoot/../../work/flutter-sdk-bootstrap/flutter/bin/flutter.bat")
$ErrorActionPreference = 'Stop'
$project = Split-Path $PSScriptRoot -Parent
$root = Split-Path $project -Parent
$logs = Join-Path $root 'work/windows-baseline/unit'
New-Item -ItemType Directory -Force $logs | Out-Null
$env:PUB_CACHE = Join-Path $root 'work/flutter-sdk-bootstrap/pub-cache'
foreach ($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy')) {
  Remove-Item "Env:$key" -ErrorAction SilentlyContinue
}
$env:NO_PROXY = 'localhost,127.0.0.1,::1'
$rows = @()
Push-Location $project
try {
  $source = (git rev-parse HEAD).Trim()
  foreach ($file in (Get-ChildItem test -Filter '*test.dart' | Sort-Object Name)) {
    $log = Join-Path $logs ($file.BaseName + '.jsonl')
    $errors = Join-Path $logs ($file.BaseName + '.stderr.log')
    $timer = [Diagnostics.Stopwatch]::StartNew()
    & $Flutter test --no-pub --reporter json "test/$($file.Name)" 1> $log 2> $errors
    $code = $LASTEXITCODE
    $events = @(Get-Content $log | ForEach-Object { try { $_ | ConvertFrom-Json } catch {} })
    $ends = @($events | Where-Object type -EQ 'testDone')
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
} finally { Pop-Location }
if (@($rows | Where-Object status -EQ 'failed').Count) { exit 1 }
