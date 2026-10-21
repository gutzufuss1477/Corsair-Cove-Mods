param([Parameter(Mandatory=$true)][string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
$fixture = Join-Path $PSScriptRoot ('InstallFixture-' + [guid]::NewGuid().ToString('N'))
$mods = Join-Path $fixture 'Game\CorsairCove\Binaries\Win64\ue4ss\Mods'
$data = Join-Path $fixture 'Data'
New-Item -ItemType Directory -Path (Join-Path $mods 'ExtendedPirateCampRange\Scripts'),(Join-Path $mods 'CoveQoLResearch'),$data -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $mods 'ExtendedPirateCampRange\Scripts\main.lua'),'unchanged-range')
[IO.File]::WriteAllText((Join-Path $mods 'CoveQoLResearch\enabled.txt'),'')
[IO.File]::WriteAllText((Join-Path $mods 'mods.txt'),"ExtendedPirateCampRange : 1`r`nCoveQoLResearch : 1`r`nKeybinds : 1`r`n")
[IO.File]::WriteAllText((Join-Path $mods 'mods.json'),'[{"mod_name":"ExtendedPirateCampRange","mod_enabled":true},{"mod_name":"CoveQoLResearch","mod_enabled":true}]')
$custom = "TransportEnabled=1`nTransportSteps=35`nCarryEnabled=1`nCarrySteps=5`nShipsEnabled=0`nShipsSteps=15`n"
[IO.File]::WriteAllText((Join-Path $data 'settings.ini'),$custom)
$installer = Join-Path $PackageDirectory 'Install.ps1'
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $data
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $data
$txt = Get-Content -LiteralPath (Join-Path $mods 'mods.txt') -Raw
if (([regex]::Matches($txt,'CoveQoLTrainer : 1')).Count -ne 1) { throw 'Install is not idempotent.' }
if (!$txt.Contains('ExtendedPirateCampRange : 1') -or !$txt.Contains('CoveQoLResearch : 0')) { throw 'Mod activation state incorrect.' }
if (Test-Path -LiteralPath (Join-Path $mods 'CoveQoLResearch\enabled.txt')) { throw 'Research marker not disabled.' }
if ([IO.File]::ReadAllText((Join-Path $data 'settings.ini')) -ne $custom) { throw 'User settings changed.' }
if ([IO.File]::ReadAllText((Join-Path $mods 'ExtendedPirateCampRange\Scripts\main.lua')) -ne 'unchanged-range') { throw 'Range mod changed.' }
$expected = (Get-FileHash -LiteralPath (Join-Path $PackageDirectory 'Mod\CoveQoLTrainer\Scripts\main.lua')).Hash
if ((Get-FileHash -LiteralPath (Join-Path $mods 'CoveQoLTrainer\Scripts\main.lua')).Hash -ne $expected) { throw 'Installed backend differs.' }
$expectedNative=(Get-FileHash -LiteralPath (Join-Path $PackageDirectory 'Mod\CoveQoLTrainer\Scripts\CoveQoLNative.dll')).Hash
if((Get-FileHash -LiteralPath (Join-Path $mods 'CoveQoLTrainer\Scripts\CoveQoLNative.dll')).Hash -ne $expectedNative){throw 'Installed native DLL differs.'}
$withConstruction=$custom+"ConstructionEnabled=1`nConstructionSteps=55`nCampOverlapEnabled=1`nAttackRadiusEnabled=1`nAttackRadiusSteps=85`n"
[IO.File]::WriteAllText((Join-Path $data 'settings.ini'),$withConstruction)
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $data
if ([IO.File]::ReadAllText((Join-Path $data 'settings.ini')) -ne $withConstruction) { throw 'Construction/overlap/attack settings changed during update.' }
$withFog=$withConstruction+"NearestCoastEnabled=1`nKeepRevealedEnabled=1`n"
[IO.File]::WriteAllText((Join-Path $data 'settings.ini'),$withFog)
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $data
if ([IO.File]::ReadAllText((Join-Path $data 'settings.ini')) -ne $withFog) { throw 'Fog option changed during update.' }
$withRoutesAndBattle=$withFog+"RoutesEnabled=1`nBattleProtectionEnabled=1`n"
[IO.File]::WriteAllText((Join-Path $data 'settings.ini'),$withRoutesAndBattle)
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $data
if ([IO.File]::ReadAllText((Join-Path $data 'settings.ini')) -ne $withRoutesAndBattle) { throw 'Routes/battle options changed during update.' }
$withIndividual=$withFog+"RoutesEnabled=1`nBattleHullEnabled=1`nBattleCrewEnabled=0`nBattleSuppliesEnabled=1`n"
[IO.File]::WriteAllText((Join-Path $data 'settings.ini'),$withIndividual)
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $data
if ([IO.File]::ReadAllText((Join-Path $data 'settings.ini')) -ne $withIndividual) { throw 'Individual battle switches changed during update.' }
$freshData=Join-Path $fixture 'FreshData'
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $freshData
$fresh=Get-Content -LiteralPath (Join-Path $freshData 'settings.ini') -Raw
if (!$fresh.Contains('ConstructionEnabled=0') -or !$fresh.Contains('ConstructionSteps=20')) { throw 'Fresh construction defaults incorrect.' }
if (!$fresh.Contains('CampOverlapEnabled=0')) { throw 'Fresh camp overlap must start disabled.' }
if (!$fresh.Contains('NearestCoastEnabled=0') -or $fresh.Contains('AttackRadius')) { throw 'Fresh nearest coast defaults incorrect.' }
if (!$fresh.Contains('KeepRevealedEnabled=0')) { throw 'Fresh fog option must start disabled.' }
if (!$fresh.Contains('RoutesEnabled=0') -or $fresh.Contains('BattleProtectionEnabled') -or $fresh.Contains('Carry')) { throw 'Fresh route defaults or retired keys incorrect.' }
foreach ($key in @('BattleHullEnabled','BattleCrewEnabled','BattleSuppliesEnabled')) {
    if (!$fresh.Contains($key+'=0')) { throw 'Fresh individual protection must start disabled.' }
}
& $installer -GameDirectory (Join-Path $fixture 'Game') -DataDirectory $data -Uninstall
$json = @(Get-Content -LiteralPath (Join-Path $mods 'mods.json') -Raw | ConvertFrom-Json)
if (($json | Where-Object mod_name -eq CoveQoLTrainer).mod_enabled) { throw 'Deactivation failed.' }
if (!(Get-Content -LiteralPath (Join-Path $mods 'mods.txt') -Raw).Contains('CoveQoLTrainer : 0')) { throw 'Text deactivation failed.' }
Write-Output 'Installer: install/update, legacy/construction/overlap/attack/fog/routes/battle settings preservation, fresh defaults, range preservation, backup and deactivation passed.'
# Check the resolved target stays within this test workspace before deleting it.
$resolved = (Resolve-Path -LiteralPath $fixture).Path
$testRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path.TrimEnd('\') + '\'
if (!$resolved.StartsWith($testRoot,[StringComparison]::OrdinalIgnoreCase) -or !(Split-Path $resolved -Leaf).StartsWith('InstallFixture-')) { throw 'Unsafe test cleanup path.' }
Remove-Item -LiteralPath $resolved -Recurse -Force
