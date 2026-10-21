using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using CoveQoLTrainer;

internal static class SetupTests {
  internal static void Run(Action<bool,string> check) {
    string root=Path.Combine(Path.GetTempPath(),"CoveReleaseSetup-"+Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(root);
    var payload=Bootstrap.Payload();check(payload.Count==15,"standalone EXE contains loader, native mod and app-local CRT");
    string bin=Path.Combine(root,"Game","CorsairCove","Binaries","Win64"),data=Path.Combine(root,"Data");
    Directory.CreateDirectory(bin);File.WriteAllText(Path.Combine(bin,"CorsairCove.exe"),"fixture executable");
    check(Bootstrap.ResolveBin(Path.Combine(root,"Game"))==bin,"game-root selection resolves native executable");
    bool rejected=false;try{Bootstrap.Install(bin,data);}catch(SetupException ex){rejected=ex.Key=="unsupported";}
    check(rejected&&!Directory.Exists(data)&&Directory.GetFiles(bin).Length==1,"unsupported EXE rejected before any writes");
    var plan=Bootstrap.Plan(bin,data,payload);check(plan.Needed,"fresh game receives complete runtime");plan.Apply(data,null);
    check(File.ReadAllBytes(Path.Combine(bin,"ue4ss","UE4SS.dll")).SequenceEqual(payload["ue4ss/UE4SS.dll"]),"bundled runtime deployed byte-for-byte");
    check(File.Exists(Path.Combine(bin,"vcruntime140.dll"))&&File.Exists(Path.Combine(bin,"msvcp140_atomic_wait.dll")),"required runtime dependencies deployed without installer");
    check(File.ReadAllText(Path.Combine(data,"settings.ini")).Contains("CampRadiusEnabled=0"),"fresh installation enables no range cheat");
    check(!Bootstrap.Plan(bin,data,payload).Needed,"second launch is read-only when setup is current");
    string mods=Path.Combine(bin,"ue4ss","Mods");
    File.WriteAllText(Path.Combine(mods,"mods.txt"),"; preserve my comment\nOtherMod : 1\nExtendedPirateCampRange : 1\nCoveQoLResearch : 1\nKeybinds : 1\n");
    File.WriteAllText(Path.Combine(mods,"mods.json"),"[{\"mod_name\":\"OtherMod\",\"mod_enabled\":true,\"custom\":42},{\"mod_name\":\"ExtendedPirateCampRange\",\"mod_enabled\":true}]");
    string old=Path.Combine(mods,"ExtendedPirateCampRange");Directory.CreateDirectory(Path.Combine(old,"Scripts"));
    File.WriteAllText(Path.Combine(old,"Scripts","config.lua"),"return { Enabled=true, RadiusMultiplier=42, AbsoluteRadius=0 }");
    File.WriteAllText(Path.Combine(old,"enabled.txt"),"old marker");
    File.WriteAllText(Path.Combine(data,"settings.ini"),"Revision=old\nTransportEnabled=1\nTransportSteps=35\nBattleCrewEnabled=1\n");
    plan=Bootstrap.Plan(bin,data,payload);plan.Apply(data,null);
    string profile=File.ReadAllText(Path.Combine(data,"settings.ini"));
    check(profile.Contains("TransportSteps=35")&&profile.Contains("BattleCrewEnabled=1")&&profile.Contains("CampRadiusEnabled=1")&&profile.Contains("CampRadiusSteps=420"),"existing settings and old range factor migrate together");
    check(!File.Exists(Path.Combine(old,"enabled.txt"))&&File.Exists(Path.Combine(old,"Scripts","config.lua")),"only conflicting legacy activation removed, source preserved");
    check(File.ReadAllText(Path.Combine(mods,"mods.txt")).Contains("; preserve my comment\r\nOtherMod : 1")&&File.ReadAllText(Path.Combine(mods,"mods.json")).Contains("\"custom\":42"),"unrelated mod state and metadata preserved");
    check(Directory.GetFiles(plan.Backup,"*.bak").Length>=4,"migration has recoverable backups");
    check(!Bootstrap.Plan(bin,data,payload).Needed,"migrated setup is idempotent");
    string first=Path.Combine(root,"rollback-existing"),created=Path.Combine(root,"rollback-new"),removed=Path.Combine(root,"rollback-deleted");
    File.WriteAllText(first,"before");File.WriteAllText(removed,"restore me");
    var tx=new SetupPlan();tx.Put(first,Bootstrap.Utf8("after"));tx.Put(created,Bootstrap.Utf8("new"));tx.Delete.Add(removed);
    bool failed=false;try{tx.Apply(data,i=>{if(i==3)throw new IOException("injected failure");});}catch(IOException){failed=true;}
    check(failed&&File.ReadAllText(first)=="before"&&!File.Exists(created)&&File.ReadAllText(removed)=="restore me","failed setup rolls back overwritten, new and deleted files");
    check(Directory.GetFiles(root,"*.tmp",SearchOption.AllDirectories).Length==0,"transaction leaves no temporary files");
    File.WriteAllText(Path.Combine(mods,"mods.json"),"malformed");
    rejected=false;try{Bootstrap.Plan(bin,data,payload);}catch(SetupException ex){rejected=ex.Key=="invalidRegistry";}
    check(rejected&&File.ReadAllText(Path.Combine(data,"settings.ini"))==profile,"bad registry rejected before changing settings");
    rejected=false;try{Bootstrap.SafeTarget(bin,"../outside.dll");}catch(SetupException){rejected=true;}
    check(rejected,"payload paths cannot escape the game directory");
    File.WriteAllText(Path.Combine(bin,"dwmapi.dll"),"other loader");
    rejected=false;try{Bootstrap.Plan(bin,data,payload);}catch(SetupException ex){rejected=ex.Key=="loaderConflict";}
    check(rejected&&File.ReadAllText(Path.Combine(bin,"dwmapi.dll"))=="other loader","foreign loaders are not overwritten");
    // Only this newly-created test root is removed; no actual installation is used.
    string resolved=Path.GetFullPath(root),expected=Path.GetFullPath(Path.GetTempPath()).TrimEnd('\\')+"\\CoveReleaseSetup-";
    if(!resolved.StartsWith(expected,StringComparison.OrdinalIgnoreCase))throw new Exception("Invalid cleanup root");
    Directory.Delete(resolved,true);
  }
}
