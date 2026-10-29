# Building the published 1.2.5 source

Windows x64, Visual Studio C++ Build Tools, Windows SDK and .NET Framework csc
are required. MinHook source and its full license are in `third_party/minhook`.

Provide the exact UE4SS 3.0.1-1165-g12ec45a0 distribution locally under
`.local-dependencies/UE4SS_v3.0.1-1165-g12ec45a0/`, or pass `-DependencyRoot`.
Provide the licensed Microsoft VC143 x64 runtime directory using `-CrtDirectory`
if it differs from the documented local default. Those runtime binaries are not
tracked in Git. An optional locally supplied `UI/cove.ico` is used if present.

Run `npm install` and `npm test` for the Lua regression suite. Run
`powershell -File Build.ps1 -Test -DependencyRoot <directory> -CrtDirectory <directory>`
for the native and trainer build. These commands build local files; they do not
install the mod into the game. Gameplay source matches the 1.2.5 release workspace. The portable dependency paths and optional icon handling are repository-specific build conveniences.
