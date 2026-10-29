param([switch]$Test,[switch]$UiOnly,[string]$DependencyRoot=(Join-Path $PSScriptRoot '.local-dependencies'),[string]$CrtDirectory='')
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$workspace=Split-Path $root -Parent
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$release=Join-Path $root 'Releases\CoveQoLTrainer-1.2.5'
$build=Join-Path $root 'Build\Release-1.2.5'
New-Item -ItemType Directory -Force -Path $release,$build | Out-Null
if(!$UiOnly){& "$root\Native\Build-Native.ps1" -Test:$Test}
$runtime=Join-Path $DependencyRoot 'UE4SS_v3.0.1-1165-g12ec45a0'
$crt=$CrtDirectory
if(!$crt){$crt='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Redist\MSVC\14.44.35112\x64\Microsoft.VC143.CRT'}
$files=[ordered]@{
 'dwmapi.dll'="$runtime\dwmapi.dll"
 'ue4ss/UE4SS.dll'="$runtime\ue4ss\UE4SS.dll"
 'ue4ss/UE4SS-settings.ini'="$runtime\ue4ss\UE4SS-settings.ini"
 'ue4ss/LICENSE'="$runtime\ue4ss\LICENSE"
 'ue4ss/Mods/CoveQoLTrainer/Scripts/WarehouseUI.lua'="$root\Scripts\WarehouseUI.lua"
 'ue4ss/Mods/CoveQoLTrainer/Scripts/main.lua'="$root\Scripts\main.lua"
 'ue4ss/Mods/CoveQoLTrainer/Scripts/CoveQoLNative.dll'="$root\Native\Build\CoveQoLNative.dll"
}
foreach($name in @('msvcp140.dll','msvcp140_1.dll','msvcp140_2.dll','msvcp140_atomic_wait.dll','msvcp140_codecvt_ids.dll','vcruntime140.dll','vcruntime140_1.dll','concrt140.dll')){$files[$name]=Join-Path $crt $name}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$payload=Join-Path $build 'Payload.zip'
if(Test-Path -LiteralPath $payload){Remove-Item -LiteralPath $payload}
$zip=[IO.Compression.ZipFile]::Open($payload,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($entry in $files.GetEnumerator()){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,$entry.Value,$entry.Key,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$zip.Dispose()}
$notices="UE4SS 3.0.1-1165-g12ec45a0`r`nhttps://github.com/UE4SS-RE/RE-UE4SS`r`n"+[IO.File]::ReadAllText("$runtime\ue4ss\LICENSE")+"`r`nMinHook 1.3.4`r`nhttps://github.com/TsudaKageyu/minhook`r`n"+[IO.File]::ReadAllText("$root\third_party\minhook\LICENSE.txt")+"`r`nMicrosoft Visual C++ Runtime 14.44.35112 (x64)`r`nCopyright Microsoft Corporation. Redistributable runtime components supplied with Microsoft Visual Studio Build Tools. Windows 10/11 supplies .NET Framework and the Universal CRT.`r`n"
$notices+="`r`nFeature references and acknowledgements`r`nTREG - More Fetchers (Nexus mod 31): route-limit feature inspiration.`r`nNavyMage - Carry Capacity (Nexus mod 24): cargo mechanics research; cargo scaling is not included.`r`nCaites - Balance Tweaks (Nexus mod 5): camp-housing feature reference. The housing hook was independently implemented from the game executable; no mod code or assets copied.`r`nhttps://www.nexusmods.com/corsaircove/mods/31`r`nhttps://www.nexusmods.com/corsaircove/mods/24`r`nhttps://www.nexusmods.com/corsaircove/mods/5`r`n"
[IO.File]::WriteAllText("$build\Notices.txt",$notices)
$resources=@("/resource:$payload,Payload.zip","/resource:$build\Notices.txt,Notices.txt")
foreach($file in Get-ChildItem -LiteralPath "$root\UI\Languages" -Filter '*.json'){$resources+="/resource:$($file.FullName),Languages.$($file.Name)"}
$sources=@("$root\UI\CoveQoLTrainer.cs","$root\UI\Localization.cs","$root\UI\Bootstrap.cs")
$common=@('/nologo','/platform:x64','/optimize+','/reference:System.Drawing.dll','/reference:System.Windows.Forms.dll','/reference:System.Web.Extensions.dll','/reference:System.IO.Compression.dll',"/win32manifest:$root\UI\app.manifest")
if(Test-Path -LiteralPath "$root\UI\cove.ico"){$common+="/win32icon:$root\UI\cove.ico"}
& $compiler @common /target:winexe "/out:$release\CoveQoLTrainer.exe" @resources @sources
if($LASTEXITCODE){throw 'Release compilation failed.'}
if($Test){
 if(!$UiOnly){& node "$root\Tests\run-backend.js"
 if($LASTEXITCODE){throw 'Backend tests failed.'}}
 & $compiler @common /target:exe /main:ReleaseTests "/out:$build\ReleaseTests.exe" @resources @sources "$root\Tests\ReleaseTests.cs" "$root\Tests\SetupTests.cs"
 if($LASTEXITCODE){throw 'Release tests compilation failed.'}
 $renders=Join-Path $root 'Analysis\Release-1.2.5'
 New-Item -ItemType Directory -Force -Path $renders|Out-Null
 & "$build\ReleaseTests.exe" $renders
 if($LASTEXITCODE){throw 'Release tests failed.'}
}
Copy-Item -LiteralPath "$release\CoveQoLTrainer.exe" -Destination "$root\UI\CoveQoLTrainer.exe" -Force
$archive=Join-Path $root 'Releases\CoveQoLTrainer-1.2.5.zip'
Compress-Archive -LiteralPath "$release\CoveQoLTrainer.exe" -DestinationPath $archive -Force
$manifest=@{}
foreach($entry in $files.GetEnumerator()){$manifest[$entry.Key]=(Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash.ToLowerInvariant()}
$manifest['CoveQoLTrainer.exe']=(Get-FileHash -LiteralPath "$release\CoveQoLTrainer.exe" -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest['CoveQoLTrainer-1.2.5.zip']=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest|ConvertTo-Json|Set-Content "$root\Analysis\release-v125-hashes.json"
Write-Output "Build complete: $release"
