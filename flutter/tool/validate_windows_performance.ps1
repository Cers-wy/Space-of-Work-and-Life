# Correlate scenario timing with read-only native foreground samples.
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$dir=$OutputDirectory
$r=Get-Content "$dir\report.json" -Raw | ConvertFrom-Json
$s=Get-Content "$dir\native-samples.json" -Raw | ConvertFrom-Json
foreach($row in $r.results){
 $end=([DateTimeOffset](Get-Item "$dir\$($row.scenario).json").LastWriteTimeUtc).ToUnixTimeMilliseconds()
 $during=@($s | Where-Object {$_.unixMs -ge ($end-$row.seconds*1000) -and $_.unixMs -le $end})
 $ok=@($during | Where-Object {$_.appPid -eq $_.foregroundPid})
 $row | Add-Member nativeForegroundSamples $during.Count
 $row | Add-Member nativeForegroundThroughout ($during.Count -gt 0 -and $ok.Count -eq $during.Count)
 $row | Add-Member nativeForegroundRatio $(if($during.Count){$ok.Count/$during.Count}else{0})
}
$r | Add-Member foregroundMethod 'Win32 GetForegroundWindow/GetWindowThreadProcessId every 100ms; Flutter lifecycle null on this runner'
$r | ConvertTo-Json -Depth 8 | Set-Content "$dir\validated-report.json" -Encoding UTF8
