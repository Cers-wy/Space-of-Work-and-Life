param([string]$Repository = "$PSScriptRoot/../..")
$ErrorActionPreference = 'Stop'
$Repository = (Resolve-Path $Repository).Path
$build = Join-Path $Repository 'flutter/build/windows/x64/runner/Release'
$config = Get-Content (Join-Path $Repository 'flutter/windows/flutter/ephemeral/generated_config.cmake') -Raw
if ($config -notmatch 'FLUTTER_TARGET=lib/main\.dart"') { throw 'Rebuild the production lib/main.dart entry point first' }
$version = ((Get-Content (Join-Path $Repository 'flutter/pubspec.yaml') | Select-String '^version:').ToString().Split(':')[1]).Trim()
$name = 'Space-' + $version.Split('+')[0] + '-Windows-x64-更新包'
$stage = Join-Path $Repository 'work/windows-baseline/update-stage'
if (Test-Path $stage) { throw 'Use a fresh update staging directory' }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item "$build/*" $stage -Recurse
Copy-Item (Join-Path $Repository 'flutter/THIRD_PARTY_NOTICES.txt') $stage
$crt = Get-ChildItem (Join-Path $Repository 'work/vs-buildtools/VC/Redist/MSVC') -Directory -Recurse -Filter Microsoft.VC143.CRT |
  Where-Object { $_.FullName -match '\\x64\\' -and $_.FullName -notmatch '\\onecore\\' } | Select-Object -First 1
if (!$crt) { throw 'Portable Visual C++ runtime missing' }
Copy-Item "$($crt.FullName)/*.dll" $stage
foreach ($required in @('Space.exe','flutter_windows.dll','pdfium.dll','onnxruntime.dll','space_ocr_math.dll','sqlite3.dll','pdfrx_pdfium_gate.dll')) {
  if (!(Test-Path (Join-Path $stage $required))) { throw "Missing $required" }
}
$all = @(Get-ChildItem $stage -Recurse -File)
if ($all | Where-Object { $_.Extension -in @('.sqlite','.sqlite3','.db','.spacepack','.dmp','.log') -or $_.Name -in @('settings.json','config.json','credentials.json') }) {
  throw 'Unexpected personal/test data in application bundle'
}
$models = Join-Path $stage 'data/flutter_assets/assets/models/ppocrv6'
foreach ($model in (Get-ChildItem (Join-Path $Repository 'flutter/assets/models/ppocrv6') -Filter '*.onnx')) {
  if ((Get-FileHash $model.FullName).Hash -ne (Get-FileHash (Join-Path $models $model.Name)).Hash) { throw "Model differs: $($model.Name)" }
}
$downloads = Join-Path $Repository 'downloads'
New-Item -ItemType Directory -Force $downloads | Out-Null
$zip = Join-Path $downloads "$name.zip"
if (Test-Path $zip) { throw 'Update ZIP already exists; inspect before replacing' }
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
  $files = @($archive.Entries | Where-Object { !$_.FullName.EndsWith('/') })
  if ($files.Count -ne $all.Count) { throw 'ZIP file count differs' }
  foreach ($entry in $files) {
    $stream = $entry.Open()
    try { $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stream)) } finally { $stream.Dispose() }
    if ($hash -ne (Get-FileHash (Join-Path $stage $entry.FullName)).Hash) { throw "ZIP content mismatch: $($entry.FullName)" }
  }
} finally { $archive.Dispose() }
$sha = (Get-FileHash $zip).Hash.ToLower()
$record = Join-Path $Repository 'flutter/verification/windows-2026-11-13'
"$sha  $name.zip" | Set-Content (Join-Path $record 'SHA256SUMS.txt') -Encoding utf8
[ordered]@{
  version = $version; filename = "$name.zip"; sha256 = $sha; bytes = (Get-Item $zip).Length
  files = $all.Count; productionEntrypoint = 'lib/main.dart'; configuration = 'Release x64'
  sourceParent = (git -C $Repository rev-parse HEAD).Trim()
  applicationGitBlob = (git -C $Repository hash-object flutter/lib/core/repository.dart).Trim()
  personalDataIncluded = $false; allZipFilesHashVerified = $true; modelHashesMatch = $true
  isolatedStartupTested = $false; foregroundPerformanceVerified = $false
} | ConvertTo-Json | Set-Content (Join-Path $record 'package.json') -Encoding utf8
Write-Output $zip
