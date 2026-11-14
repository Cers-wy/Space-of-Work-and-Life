param([string]$FlutterRoot = "$PSScriptRoot/../../work/flutter-sdk-bootstrap/flutter")
$ErrorActionPreference = 'Stop'
# Flutter 3.47.9 / Dart 3.13.7: the Windows native stack sampler crashed in
# dart::ProfilerNativeStackWalker::walk during FFI tests. This changes only the
# local test command; production builds and frame/OS measurements are unchanged.
$version = (git -C $FlutterRoot describe --tags --exact-match).Trim()
if ($version -ne '3.47.9') { throw "Reassess the sampler workaround for Flutter $version" }
$source = Join-Path $FlutterRoot 'packages/flutter_tools/lib/src/commands/test.dart'
$text = [IO.File]::ReadAllText($source).Replace("`r`n", "`n")
$setting = '      enableDartProfiling: !globals.platform.isWindows,'
if (!$text.Contains($setting)) {
  $needle = "    final debuggingOptions = DebuggingOptions.enabled(`n      buildInfo,"
  if (!$text.Contains($needle)) { throw 'Unexpected Flutter test command source' }
  [IO.File]::WriteAllText($source, $text.Replace($needle, "$needle`n$setting"), [Text.UTF8Encoding]::new($false))
  $snapshot = Join-Path $FlutterRoot 'bin/cache/flutter_tools.snapshot'
  if (Test-Path -LiteralPath $snapshot) { Remove-Item -LiteralPath $snapshot }
}
