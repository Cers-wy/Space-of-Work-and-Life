# Read-only OS instrumentation for an already built Release benchmark.
param([Parameter(Mandatory=$true)][string]$Application,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
if(Test-Path $OutputDirectory){throw 'Use a new isolated output directory'}
Add-Type @'
using System; using System.Runtime.InteropServices;
public class SpaceForegroundProbe {
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint id);
}
'@
$env:SPACE_FLUTTER_DATA_DIRECTORY=$OutputDirectory
$p=Start-Process $Application -WindowStyle Normal -PassThru
$samples=[Collections.Generic.List[object]]::new()
$timer=[Diagnostics.Stopwatch]::StartNew()
while(!$p.HasExited -and $timer.Elapsed.TotalSeconds -lt 180){
 [uint32]$foregroundPid=0
 [SpaceForegroundProbe]::GetWindowThreadProcessId([SpaceForegroundProbe]::GetForegroundWindow(),[ref]$foregroundPid) | Out-Null
 $p.Refresh()
 $samples.Add(@{unixMs=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();foregroundPid=$foregroundPid;appPid=$p.Id;cpuSeconds=$p.TotalProcessorTime.TotalSeconds;workingSetMiB=$p.WorkingSet64/1MB})
 Start-Sleep -Milliseconds 100
}
if(!$p.HasExited){Stop-Process -Id $p.Id;throw 'Benchmark timed out'}
$samples | ConvertTo-Json -Depth 3 | Set-Content "$OutputDirectory\native-samples.json" -Encoding UTF8
@{pid=$p.Id;sessionId=$p.SessionId;exitCode=$p.ExitCode;mode='Release, native GetForegroundWindow sampled every 100ms; Flutter lifecycle may be unavailable'} | ConvertTo-Json | Set-Content "$OutputDirectory\native-run.json" -Encoding UTF8
