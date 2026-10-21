using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Diagnostics;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using System.Reflection;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace CoveQoLTrainer {
  internal sealed class SetupException:Exception {
    public readonly string Key;
    public SetupException(string key):base(key){Key=key;}
  }
  internal sealed class SetupPlan {
    internal readonly Dictionary<string,byte[]> Files=new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
    internal readonly List<string> Delete=new List<string>();
    internal string Backup;
    internal void Put(string path,byte[] value) {if(!File.Exists(path)||!File.ReadAllBytes(path).SequenceEqual(value))Files[path]=value;}
    internal bool Needed {get{return Files.Count+Delete.Count>0;}}
    // Snapshot every touched file before the first mutation, and restore both
    // replaced and newly-created files if any step fails. No recursive deletion.
    internal void Apply(string data,Action<int> checkpoint) {
      if(!Needed)return;
      Backup=Path.Combine(data,"InstallBackups",DateTime.UtcNow.ToString("yyyyMMdd_HHmmss")+"_"+Guid.NewGuid().ToString("N"));
      Directory.CreateDirectory(Backup);
      var before=new Dictionary<string,byte[]>(StringComparer.OrdinalIgnoreCase);
      foreach(string path in Files.Keys.Concat(Delete).Distinct(StringComparer.OrdinalIgnoreCase)) {
        before[path]=File.Exists(path)?File.ReadAllBytes(path):null;
        if(before[path]!=null)File.WriteAllBytes(Path.Combine(Backup,before.Count.ToString("D4")+".bak"),before[path]);
      }
      File.WriteAllText(Path.Combine(Backup,"manifest.json"),new JavaScriptSerializer().Serialize(before.Select((p,i)=>new {path=p.Key,backup=p.Value==null?null:(i+1).ToString("D4")+".bak"}).ToArray()));
      var touched=new List<string>();
      try {
        int count=0;
        foreach(var item in Files){AtomicWrite(item.Key,item.Value);touched.Add(item.Key);if(checkpoint!=null)checkpoint(++count);}
        foreach(string path in Delete){File.Delete(path);touched.Add(path);if(checkpoint!=null)checkpoint(++count);}
      }catch {
        Exception rollback=null;
        foreach(string path in touched.AsEnumerable().Reverse())try {if(before[path]==null){if(File.Exists(path))File.Delete(path);}else AtomicWrite(path,before[path]);}catch(Exception ex){rollback=ex;}
        if(rollback!=null)throw new IOException("Rollback: "+Backup,rollback);
        throw;
      }
    }
    internal static void AtomicWrite(string path,byte[] bytes) {
      Directory.CreateDirectory(Path.GetDirectoryName(path));
      string tmp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
      try{File.WriteAllBytes(tmp,bytes);if(File.Exists(path))File.Replace(tmp,path,null);else File.Move(tmp,path);}finally{if(File.Exists(tmp))File.Delete(tmp);}
    }
  }
  internal static class Bootstrap {
    internal const string GameHash="c8d9fea9f172b79a43b226c9a58ff021dcc5ecbcc410c5dca2155b70f4ad5195";
    internal static readonly string[] PayloadNames={"dwmapi.dll","ue4ss/UE4SS.dll","ue4ss/UE4SS-settings.ini","ue4ss/LICENSE","ue4ss/Mods/CoveQoLTrainer/Scripts/main.lua","ue4ss/Mods/CoveQoLTrainer/Scripts/WarehouseUI.lua","ue4ss/Mods/CoveQoLTrainer/Scripts/CoveQoLNative.dll","msvcp140.dll","msvcp140_1.dll","msvcp140_2.dll","msvcp140_atomic_wait.dll","msvcp140_codecvt_ids.dll","vcruntime140.dll","vcruntime140_1.dll","concrt140.dll"};
    internal static string Hash(string path){using(var stream=File.OpenRead(path))using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(stream)).Replace("-","").ToLowerInvariant();}
    internal static string Hash(byte[] data){using(var hash=SHA256.Create())return BitConverter.ToString(hash.ComputeHash(data)).Replace("-","").ToLowerInvariant();}
    internal static Dictionary<string,byte[]> Payload() {
      var result=new Dictionary<string,byte[]>();
      using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Payload.zip")) {
        if(stream==null)throw new SetupException("installMissing");
        using(var zip=new ZipArchive(stream,ZipArchiveMode.Read))foreach(var entry in zip.Entries) {
          if(!PayloadNames.Contains(entry.FullName)||result.ContainsKey(entry.FullName)||entry.Length>35000000)throw new SetupException("installMissing");
          using(var input=entry.Open())using(var output=new MemoryStream()){input.CopyTo(output);result.Add(entry.FullName,output.ToArray());}
        }
      }
      if(result.Count!=PayloadNames.Length)throw new SetupException("installMissing");
      return result;
    }
    internal static string ResolveBin(string root) {
      if(string.IsNullOrWhiteSpace(root))return null;
      foreach(string suffix in new[]{"CorsairCove/Binaries/Win64","Binaries/Win64",""}) {
        string bin=Path.GetFullPath(Path.Combine(root,suffix.Replace('/',Path.DirectorySeparatorChar)));
        if(File.Exists(Path.Combine(bin,"CorsairCove.exe")))return bin;
      }
      return null;
    }
    internal static string FindGame() {
      try {
        string remembered=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CorsairCoveQoL","game-path.txt");
        if(File.Exists(remembered)){string saved=ResolveBin(File.ReadAllText(remembered).Trim());if(saved!=null)return saved;}
        string steam=Registry.GetValue(@"HKEY_CURRENT_USER\Software\Valve\Steam","SteamPath",null) as string;
        if(string.IsNullOrEmpty(steam))steam=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Steam");
        var libraries=new List<string>{steam};string vdf=Path.Combine(steam,"steamapps","libraryfolders.vdf");
        if(File.Exists(vdf))foreach(Match m in Regex.Matches(File.ReadAllText(vdf),"\"path\"\\s*\"([^\"]+)\""))libraries.Add(m.Groups[1].Value.Replace("\\\\","\\"));
        foreach(string library in libraries.Distinct(StringComparer.OrdinalIgnoreCase)) {
          string manifest=Path.Combine(library,"steamapps","appmanifest_1368140.acf");
          if(!File.Exists(manifest))continue;
          var match=Regex.Match(File.ReadAllText(manifest),"\"installdir\"\\s*\"([^\"]+)\"");
          if(match.Success){string bin=ResolveBin(Path.Combine(library,"steamapps","common",match.Groups[1].Value));if(bin!=null)return bin;}
        }
      }catch{}
      return null;
    }
    internal static bool GameRunning(){foreach(string name in new[]{"CorsairCove","CorsairCove-Win64-Shipping"}){var games=Process.GetProcessesByName(name);int count=games.Length;foreach(var game in games)game.Dispose();if(count>0)return true;}return false;}
    internal static byte[] Utf8(string text){return new UTF8Encoding(false).GetBytes(text);}
    internal static string SafeTarget(string root,string relative) {
      string full=Path.GetFullPath(Path.Combine(root,relative.Replace('/',Path.DirectorySeparatorChar)));
      string prefix=Path.GetFullPath(root).TrimEnd('\\','/')+Path.DirectorySeparatorChar;
      if(!full.StartsWith(prefix,StringComparison.OrdinalIgnoreCase))throw new SetupException("installMissing");
      // A mod-folder junction must not redirect writes outside the chosen game.
      var dir=new DirectoryInfo(Path.GetDirectoryName(full));
      while(dir!=null&&dir.FullName.Length>=root.Length){if(dir.Exists&&(dir.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Reparse point: "+dir.FullName);dir=dir.Parent;}
      if(File.Exists(full)&&(File.GetAttributes(full)&FileAttributes.ReparsePoint)!=0)throw new IOException("Reparse point: "+full);
      return full;
    }
    internal static SetupPlan Plan(string bin,string data,Dictionary<string,byte[]> payload) {
      var plan=new SetupPlan();
      string ue=SafeTarget(bin,"ue4ss/UE4SS.dll"),loader=SafeTarget(bin,"dwmapi.dll");
      if((File.Exists(ue)&&Hash(ue)!=Hash(payload["ue4ss/UE4SS.dll"]))||(File.Exists(loader)&&Hash(loader)!=Hash(payload["dwmapi.dll"])))throw new SetupException("loaderConflict");
      string ini=SafeTarget(bin,"ue4ss/UE4SS-settings.ini");
      if(File.Exists(ini)&&Regex.IsMatch(File.ReadAllText(ini),@"(?mi)^[ \t]*(ModsFolderPath|ControllingModsTxt)[ \t]*=[ \t]*[^\s;\r\n]"))throw new SetupException("loaderConflict");
      foreach(var item in payload) {
        string target=SafeTarget(bin,item.Key);
        if(item.Key=="ue4ss/UE4SS-settings.ini"&&File.Exists(target))continue;
        if(!item.Key.Contains("/")&&item.Key!="dwmapi.dll"&&File.Exists(target)) {
          // Preserve a newer application-local CRT; compare bundled file version
          // using the embedded build manifest instead of loading any DLL.
          var version=FileVersionInfo.GetVersionInfo(target);
          if(new Version(version.FileMajorPart,version.FileMinorPart,version.FileBuildPart,version.FilePrivatePart)>=new Version(14,44,35112,1))continue;
        }
        plan.Put(target,item.Value);
      }
      string txt=SafeTarget(bin,"ue4ss/Mods/mods.txt"),json=SafeTarget(bin,"ue4ss/Mods/mods.json");
      string text=File.Exists(txt)?File.ReadAllText(txt):"";
      var serializer=new JavaScriptSerializer();var entries=new List<Dictionary<string,object>>();
      if(File.Exists(json))try {
        object[] parsed=serializer.DeserializeObject(File.ReadAllText(json)) as object[];
        if(parsed==null)throw new Exception();
        foreach(object obj in parsed){var item=obj as Dictionary<string,object>;if(item==null||!item.ContainsKey("mod_name")||!(item["mod_name"] is string)||!item.ContainsKey("mod_enabled")||!(item["mod_enabled"] is bool))throw new Exception();entries.Add(item);}
      }catch{throw new SetupException("invalidRegistry");}
      string rangeMarker=SafeTarget(bin,"ue4ss/Mods/ExtendedPirateCampRange/enabled.txt");
      bool legacyRange=File.Exists(rangeMarker)||Regex.IsMatch(text,@"(?mi)^\s*ExtendedPirateCampRange\s*:\s*1\s*$")||entries.Any(e=>(string)e["mod_name"]=="ExtendedPirateCampRange"&&(bool)e["mod_enabled"]);
      var lines=new List<string>();
      foreach(string row in Regex.Split(text,"\r?\n")) {
        if(Regex.IsMatch(row,@"^\s*CoveQoLTrainer\s*:"))continue;
        string line=Regex.Replace(row,@"^(\s*(?:CoveQoLResearch|ExtendedPirateCampRange)\s*:)\s*\d+", "$1 0");
        lines.Add(line);
      }
      while(lines.Count>0&&lines[lines.Count-1]=="")lines.RemoveAt(lines.Count-1);
      int keybind=lines.FindIndex(row=>Regex.IsMatch(row,@"^\s*Keybinds\s*:"));lines.Insert(keybind<0?lines.Count:keybind,"CoveQoLTrainer : 1");
      plan.Put(txt,Utf8(string.Join("\r\n",lines)+"\r\n"));
      entries.RemoveAll(e=>(string)e["mod_name"]=="CoveQoLTrainer");
      foreach(var entry in entries)if((string)entry["mod_name"]=="CoveQoLResearch"||(string)entry["mod_name"]=="ExtendedPirateCampRange")entry["mod_enabled"]=false;
      entries.Add(new Dictionary<string,object>{{"mod_name","CoveQoLTrainer"},{"mod_enabled",true}});
      plan.Put(json,Utf8(serializer.Serialize(entries)));
      foreach(string mod in new[]{"CoveQoLResearch","ExtendedPirateCampRange"}){string marker=SafeTarget(bin,"ue4ss/Mods/"+mod+"/enabled.txt");if(File.Exists(marker))plan.Delete.Add(marker);}
      string settings=Path.Combine(data,"settings.ini");
      string profile=File.Exists(settings)?File.ReadAllText(settings):"Revision=initial\nWarehouseEnabled=0\nWarehouseTypes=9\nBridgesEnabled=0\nBridgesSteps=30\nTransportEnabled=0\nTransportSteps=20\nShipsEnabled=0\nShipsSteps=20\nConstructionEnabled=0\nConstructionSteps=20\nCampHousingEnabled=0\nCampHousingSteps=100\nRoutesEnabled=0\nCampOverlapEnabled=0\nNearestCoastEnabled=0\nKeepRevealedEnabled=0\nBattleHullEnabled=0\nBattleCrewEnabled=0\nBattleSuppliesEnabled=0\n";
      if(!Regex.IsMatch(profile,@"(?m)^CampRadiusEnabled=")) {
        double factor=50;bool enabled=legacyRange;
        string config=SafeTarget(bin,"ue4ss/Mods/ExtendedPirateCampRange/Scripts/config.lua");
        if(legacyRange&&File.Exists(config)) {
          string old=Regex.Replace(File.ReadAllText(config),@"--[^\r\n]*","");
          if(Regex.IsMatch(old,@"\bEnabled\s*=\s*false\b"))enabled=false;
          var radius=Regex.Match(old,@"\bRadiusMultiplier\s*=\s*([0-9.]+)");double parsed;
          if(radius.Success&&double.TryParse(radius.Groups[1].Value,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out parsed))factor=parsed;
          var absolute=Regex.Match(old,@"\bAbsoluteRadius\s*=\s*([0-9.]+)");
          if(absolute.Success&&double.TryParse(absolute.Groups[1].Value,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out parsed)&&parsed>0)factor=parsed/3000;
        }
        profile=profile.TrimEnd()+"\nCampRadiusEnabled="+(enabled?"1":"0")+"\nCampRadiusSteps="+((int)Math.Round(Math.Max(1,Math.Min(500,factor))*10)).ToString(System.Globalization.CultureInfo.InvariantCulture)+"\n";
        plan.Put(settings,Utf8(profile));
      }
      return plan;
    }
    internal static void Install(string bin,string data) {
      if(ResolveBin(bin)!=Path.GetFullPath(bin)||Hash(Path.Combine(bin,"CorsairCove.exe"))!=GameHash)throw new SetupException("unsupported");
      var plan=Plan(bin,data,Payload());if(plan.Needed&&GameRunning())throw new SetupException("closeGame");plan.Apply(data,null);
    }
    internal static bool Prepare(ref string game,string data,Localization lang) {
      while(true) {
        if(game==null)using(var folder=new FolderBrowserDialog{Description=lang["selectGame"],ShowNewFolderButton=false}) {
          if(folder.ShowDialog()!=DialogResult.OK)return false;game=ResolveBin(folder.SelectedPath);if(game==null)continue;
        }
        try{Install(game,data);Remember(game,data);return true;}
        catch(UnauthorizedAccessException) {
          try {
            var start=new ProcessStartInfo(Application.ExecutablePath,"--install-elevated "+Quote(game)+" "+Quote(data)){UseShellExecute=true,Verb="runas",WindowStyle=ProcessWindowStyle.Hidden};
            using(var process=Process.Start(start)){process.WaitForExit();if(process.ExitCode==0){Remember(game,data);return true;}}
            return false;
          }catch(Exception ex){MessageBox.Show(lang["elevation"]+"\n"+ex.Message,"Cove QoL Trainer");return false;}
        }
        catch(Exception ex) {
          var reason=ex as SetupException;string message=reason==null?lang["installError"]+"\n"+ex.Message:lang[reason.Key];
          if(MessageBox.Show(message,"Cove QoL Trainer",MessageBoxButtons.RetryCancel,MessageBoxIcon.Warning)!=DialogResult.Retry)return false;
        }
      }
    }
    static void Remember(string game,string data){try{SetupPlan.AtomicWrite(Path.Combine(data,"game-path.txt"),Utf8(game));}catch{}}
    static string Quote(string value){return "\""+value.Replace("\"","").TrimEnd('\\')+"\"";}
    internal static int Elevated(string[] args) {
      if(args.Length!=3)return 2;
      var lang=new Localization(Localization.Detect(args[1]));
      try{Install(args[1],args[2]);return 0;}catch(Exception ex){var reason=ex as SetupException;MessageBox.Show(reason==null?lang["installError"]+"\n"+ex.Message:lang[reason.Key],"Cove QoL Trainer");return 1;}
    }
  }
}
