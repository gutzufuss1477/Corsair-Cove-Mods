param(
    [string]$GameDirectory,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'CorsairCoveQoL'),
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
function Resolve-ModsDirectory([string]$game) {
    foreach ($relative in @('CorsairCove\Binaries\Win64\ue4ss\Mods','Binaries\Win64\ue4ss\Mods','ue4ss\Mods')) {
        $candidate = Join-Path $game $relative
        if (Test-Path -LiteralPath $candidate -PathType Container) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    return $null
}
if ($GameDirectory) {
    $mods = Resolve-ModsDirectory $GameDirectory
} else {
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    $libraries = @()
    if ($steam) {
        $libraries += $steam
        $libraryFile = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $libraryFile) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($libraryFile),'"path"\s*"([^"]+)"')) {
                $libraries += $match.Groups[1].Value.Replace('\\','\')
            }
        }
    }
    foreach ($library in ($libraries | Select-Object -Unique)) {
        $mods = Resolve-ModsDirectory (Join-Path $library 'steamapps\common\CorsairCove')
        if ($mods) { break }
    }
}
if (!$mods) { throw 'Corsair Cove mit UE4SS nicht gefunden. Install.ps1 -GameDirectory "Pfad zum Spielordner" verwenden.' }
$targetBin=(Split-Path (Split-Path $mods -Parent) -Parent).TrimEnd('\')+'\'
foreach($game in @(Get-Process -Name CorsairCove,CorsairCove-Win64-Shipping -ErrorAction SilentlyContinue)) {
    if(!$game.Path -or $game.Path.StartsWith($targetBin,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'Bitte Corsair Cove vor der Installation/Deaktivierung normal beenden.'
    }
}
$mod = Join-Path $mods 'CoveQoLTrainer'
$source = Join-Path $PSScriptRoot 'Mod\CoveQoLTrainer\Scripts\main.lua'
if (!$Uninstall -and !(Test-Path -LiteralPath $source)) { throw 'Paket unvollstaendig: Mod\CoveQoLTrainer\Scripts\main.lua fehlt.' }
$nativeSource=Join-Path (Split-Path $source -Parent) 'CoveQoLNative.dll'
if (!$Uninstall -and !(Test-Path -LiteralPath $nativeSource)) { throw 'Paket unvollstaendig: CoveQoLNative.dll fehlt.' }
$txtPath = Join-Path $mods 'mods.txt'
$jsonPath = Join-Path $mods 'mods.json'
$lines = if (Test-Path -LiteralPath $txtPath) { @(Get-Content -LiteralPath $txtPath) } else { @() }
$json = if (Test-Path -LiteralPath $jsonPath) { @(Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json) } else { @() }
# Validate before changing any installed files.
foreach ($entry in $json) { if (!$entry.mod_name) { throw 'mods.json enthaelt einen ungueltigen Eintrag.' } }
$backup = Join-Path $DataDirectory ('InstallBackups\' + (Get-Date -Format yyyyMMdd_HHmmss) + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
foreach ($path in @($txtPath,$jsonPath,$mod,(Join-Path $DataDirectory 'settings.ini'))) {
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $backup -Recurse }
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
$enabled = if ($Uninstall) { 0 } else { 1 }
$newLines = New-Object System.Collections.Generic.List[string]
$inserted = $false
foreach ($line in $lines) {
    if ($line -match '^\s*CoveQoLTrainer\s*:') { continue }
    if (!$Uninstall -and $line -match '^\s*CoveQoLResearch\s*:') { $line = 'CoveQoLResearch : 0' }
    if (!$inserted -and $line -match '^\s*Keybinds\s*:') {
        $newLines.Add("CoveQoLTrainer : $enabled"); $inserted = $true
    }
    $newLines.Add($line)
}
if (!$inserted) { $newLines.Add("CoveQoLTrainer : $enabled") }
$newJson = @($json | Where-Object { $_.mod_name -ne 'CoveQoLTrainer' })
if (!$Uninstall) {
    foreach ($entry in $newJson) { if ($entry.mod_name -eq 'CoveQoLResearch') { $entry.mod_enabled = $false } }
}
$newJson += [pscustomobject]@{ mod_name='CoveQoLTrainer'; mod_enabled=(!$Uninstall.IsPresent) }
try {
    if (!$Uninstall) {
        $destination = Join-Path $mod 'Scripts'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination (Join-Path $destination 'main.lua') -Force
        Copy-Item -LiteralPath $nativeSource -Destination (Join-Path $destination 'CoveQoLNative.dll') -Force
        $settings = Join-Path $DataDirectory 'settings.ini'
        if (!(Test-Path -LiteralPath $settings)) {
            [IO.File]::WriteAllLines($settings,@('Revision=initial','TransportEnabled=0','TransportSteps=20','RoutesEnabled=0','BattleHullEnabled=0','BattleCrewEnabled=0','BattleSuppliesEnabled=0','ShipsEnabled=0','ShipsSteps=20','ConstructionEnabled=0','ConstructionSteps=20','CampOverlapEnabled=0','NearestCoastEnabled=0','KeepRevealedEnabled=0'),$utf8)
        }
        $researchMarker = Join-Path $mods 'CoveQoLResearch\enabled.txt'
        if (Test-Path -LiteralPath $researchMarker) {
            Copy-Item -LiteralPath $researchMarker -Destination (Join-Path $backup 'CoveQoLResearch-enabled.txt')
            Remove-Item -LiteralPath $researchMarker
        }
    } else {
        $marker = Join-Path $mod 'enabled.txt'
        if (Test-Path -LiteralPath $marker) { Remove-Item -LiteralPath $marker }
    }
    [IO.File]::WriteAllLines($txtPath,$newLines,$utf8)
    [IO.File]::WriteAllText($jsonPath,(ConvertTo-Json -InputObject @($newJson) -Depth 20),$utf8)
} catch {
    foreach ($name in @('mods.txt','mods.json')) {
        $old = Join-Path $backup $name
        if (Test-Path -LiteralPath $old) { Copy-Item -LiteralPath $old -Destination (Join-Path $mods $name) -Force }
    }
    $oldMain = Join-Path $backup 'CoveQoLTrainer\Scripts\main.lua'
    if (Test-Path -LiteralPath $oldMain) { Copy-Item -LiteralPath $oldMain -Destination (Join-Path $mod 'Scripts\main.lua') -Force }
    $oldNative = Join-Path $backup 'CoveQoLTrainer\Scripts\CoveQoLNative.dll'
    $installedNative = Join-Path $mod 'Scripts\CoveQoLNative.dll'
    if (Test-Path -LiteralPath $oldNative) { Copy-Item -LiteralPath $oldNative -Destination $installedNative -Force }
    elseif (Test-Path -LiteralPath $installedNative) { Remove-Item -LiteralPath $installedNative }
    throw "Installation fehlgeschlagen. Sicherung: $backup. $($_.Exception.Message)"
}
$action = if ($Uninstall) { 'deaktiviert' } else { 'installiert' }
Write-Output "Cove QoL Trainer 0.13 Testversion $action."
Write-Output "Mod: $mod"
Write-Output "Sicherung: $backup"
Write-Output 'Aenderungen gelten beim naechsten Spielstart. Bestehende Einstellungen wurden beibehalten.'
