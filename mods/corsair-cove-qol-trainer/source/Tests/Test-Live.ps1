# Historical v0.2 test. Simon performs all in-game tests himself.
throw 'Deaktiviert: Ingame-Tests und Einstellungswechsel fuehrt ausschliesslich Simon selbst aus.'
$ErrorActionPreference='Stop'
$data=Join-Path $env:LOCALAPPDATA 'CorsairCoveQoL'
$settings=Join-Path $data 'settings.ini'
$status=Join-Path $data 'status.ini'
function Read-Status {
    $values=@{}
    foreach($line in [IO.File]::ReadAllLines($status)) {
        $split=$line.IndexOf('=')
        if($split -gt 0){$values[$line.Substring(0,$split)]=$line.Substring($split+1)}
    }
    return $values
}
function Wait-Applied([string]$revision) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while($timer.Elapsed.TotalSeconds -lt 15) {
        $state=Read-Status
        if($state.Revision -eq $revision -and $state.Status -eq 'Applied') {return $state}
        Start-Sleep -Milliseconds 250
    }
    throw "No complete acknowledgement for $revision"
}
function Write-Atomic([byte[]]$bytes) {
    $tmp=$settings+'.live-test-'+[guid]::NewGuid().ToString('N')+'.tmp'
    $previous=$tmp+'.previous'
    try {[IO.File]::WriteAllBytes($tmp,$bytes);[IO.File]::Replace($tmp,$settings,$previous)}
    finally {foreach($path in @($tmp,$previous)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}}}
}
$original=[IO.File]::ReadAllBytes($settings)
$text=[Text.Encoding]::UTF8.GetString($original)
$originalRevision=[regex]::Match($text,'(?m)^Revision=(\w+)').Groups[1].Value
if(!$originalRevision){throw 'Save through the 0.2 UI before running the live test.'}
$initial=Wait-Applied $originalRevision
$revision='live-reset-'+[guid]::NewGuid().ToString('N')
$reset="Revision=$revision`nTransportEnabled=0`nTransportSteps=10`nCarryEnabled=0`nCarrySteps=1`nShipsEnabled=0`nShipsSteps=10`n"
$results=[ordered]@{Initial=$initial}
$didWrite=$false
try {
    Write-Atomic ([Text.Encoding]::UTF8.GetBytes($reset))
    $didWrite=$true
    $off=Wait-Applied $revision
    foreach($name in @('Transport','Carry','Ships')) {
        if([int]$off[($name+'Errors')] -ne 0 -or [int]$off[($name+'Changed')] -le 0) {throw "Reset did not change and verify $name"}
    }
    $results.Reset=$off
} finally {
    if($didWrite) {
        $current=[IO.File]::ReadAllText($settings)
        if($current -eq $reset) {Write-Atomic $original}
        else {throw 'Settings were changed by another writer; preserved those newer settings instead of restoring the test snapshot.'}
    }
}
$restored=Wait-Applied $originalRevision
foreach($name in @('Transport','Carry','Ships')) {
    if([int]$restored[($name+'Errors')] -ne 0 -or [int]$restored[($name+'Changed')] -le 0) {throw "Reapply did not change and verify $name"}
}
$results.Restored=$restored
$out=Join-Path $PSScriptRoot '..\Analysis\live-v02-results.json'
$results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Output 'LIVE PASS: all three modules reset and reapplied; all writes verified; original settings restored byte-for-byte.'
$results | ConvertTo-Json -Depth 5
