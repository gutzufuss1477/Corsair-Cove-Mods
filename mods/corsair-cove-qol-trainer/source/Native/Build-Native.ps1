param([switch]$Test)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$vswhere='C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(!$vs){throw 'Visual C++ Build Tools not found.'}
$vc=(Get-ChildItem -LiteralPath "$vs\VC\Tools\MSVC" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$sdk='C:\Program Files (x86)\Windows Kits\10'
$ver=(Get-ChildItem -LiteralPath "$sdk\Lib" -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
$minhook=Join-Path $root 'third_party\minhook'
if(!(Test-Path "$minhook\include\MinHook.h")){throw 'Pinned MinHook v1.3.4 source missing in Tools.'}
$out=Join-Path $PSScriptRoot 'Build'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$oldPath=$env:PATH;$oldInclude=$env:INCLUDE;$oldLib=$env:LIB
try {
    $env:PATH="$vc\bin\Hostx64\x64;$oldPath"
    $env:INCLUDE="$vc\include;$sdk\Include\$ver\ucrt;$sdk\Include\$ver\shared;$sdk\Include\$ver\um"
    $env:LIB="$vc\lib\x64;$sdk\Lib\$ver\ucrt\x64;$sdk\Lib\$ver\um\x64"
    Push-Location $out
    try {
        & cl /nologo /c /O2 /MT /W3 /D_WIN64 "/I$minhook\include" "$minhook\src\buffer.c" "$minhook\src\hook.c" "$minhook\src\trampoline.c" "$minhook\src\hde\hde64.c"
        if($LASTEXITCODE){throw 'MinHook compilation failed.'}
        & ml64 /nologo /c "$PSScriptRoot\TransportHooks.asm"
        if($LASTEXITCODE){throw 'Transport stubs compilation failed.'}
        & cl /nologo /std:c++17 /EHsc /O2 /MT /W4 /LD "/I$minhook\include" "$PSScriptRoot\CoveQoLNative.cpp" buffer.obj hook.obj trampoline.obj hde64.obj TransportHooks.obj /link /OUT:CoveQoLNative.dll
        if($LASTEXITCODE){throw 'Native DLL compilation failed.'}
        if($Test) {
            & ml64 /nologo /c "$root\Tests\NativeHarness.asm"
            if($LASTEXITCODE){throw 'Native harness compilation failed.'}
            & cl /nologo /std:c++17 /EHsc /O2 /MT /W4 "/I$minhook\include" "$root\Tests\NativeTests.cpp" buffer.obj hook.obj trampoline.obj hde64.obj TransportHooks.obj NativeHarness.obj /link /OUT:NativeTests.exe
            if($LASTEXITCODE){throw 'Native tests compilation failed.'}
            & .\NativeTests.exe
            if($LASTEXITCODE){throw 'Native tests failed.'}
        }
    } finally {Pop-Location}
} finally {$env:PATH=$oldPath;$env:INCLUDE=$oldInclude;$env:LIB=$oldLib}
