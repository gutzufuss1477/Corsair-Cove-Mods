using System;
using System.IO;
using System.Drawing;
using System.Reflection;
using System.Collections.Generic;
using System.Windows.Forms;
using CoveQoLTrainer;

internal static class TrainerTests {
  static int passed;
  static void Check(bool condition,string message){if(!condition)throw new Exception(message);passed++;Console.WriteLine("PASS "+message);}
  static T Field<T>(object o,string name){return (T)o.GetType().GetField(name,BindingFlags.NonPublic|BindingFlags.Instance).GetValue(o);}
  static object Call(object o,string name){return o.GetType().GetMethod(name,BindingFlags.NonPublic|BindingFlags.Instance).Invoke(o,null);}
  [STAThread] static int Main(string[] args){
    try {
      Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
      string root=Path.Combine(Path.GetTempPath(),"CoveQoLTests-"+Guid.NewGuid().ToString("N"));
      Directory.CreateDirectory(root);
      using(var form=new TrainerForm(root)) {
        Check(!Field<CheckBox>(form,"walkEnabled").Checked,"fresh profile starts disabled");
        Check(!Field<CheckBox>(form,"campOverlapEnabled").Checked,"camp overlap starts disabled");
        Check(!Field<CheckBox>(form,"keepRevealedEnabled").Checked,"fog preservation starts disabled");
        Field<CheckBox>(form,"keepRevealedEnabled").Checked=true;
        Check(!Field<CheckBox>(form,"nearestCoastEnabled").Checked,
          "nearest coast starts disabled");
        Field<CheckBox>(form,"nearestCoastEnabled").Checked=true;
        Field<CheckBox>(form,"campOverlapEnabled").Checked=true;
        Check(!Field<CheckBox>(form,"constructionEnabled").Checked&&Field<TrackBar>(form,"constructionSlider").Maximum==200,
          "construction starts disabled with x20 maximum");
        Check(!Field<CheckBox>(form,"routesEnabled").Checked&&!Field<CheckBox>(form,"battleHullEnabled").Checked&&!Field<CheckBox>(form,"battleCrewEnabled").Checked&&!Field<CheckBox>(form,"battleSuppliesEnabled").Checked,"new options start disabled");
        Field<CheckBox>(form,"routesEnabled").Checked=true;Field<CheckBox>(form,"battleHullEnabled").Checked=true;Field<CheckBox>(form,"battleSuppliesEnabled").Checked=true;
        Field<CheckBox>(form,"walkEnabled").Checked=true;
        Field<TrackBar>(form,"walkSlider").Value=35;
        Field<CheckBox>(form,"constructionEnabled").Checked=true;
        Field<TrackBar>(form,"constructionSlider").Value=55;
        Check((bool)Call(form,"SaveSettings"),"save new configuration");
        string first=File.ReadAllText(Path.Combine(root,"settings.ini"));
        Check(first.Contains("TransportSteps=35")&&first.Contains("TransportEnabled=1"),"slider values written invariantly");
        Check(first.Contains("ConstructionSteps=55")&&first.Contains("ConstructionEnabled=1"),"construction settings written invariantly");
        Check(first.Contains("CampOverlapEnabled=1"),"camp overlap switch saved");
        Check(first.Contains("KeepRevealedEnabled=1"),"fog switch is saved independently");
        Check(first.Contains("NearestCoastEnabled=1")&&!first.Contains("AttackRadius"),"nearest coast switch saved without legacy radius");
        Check(File.ReadAllBytes(Path.Combine(root,"settings.ini"))[0]!=0xef,"configuration has no UTF8 BOM");
        Check(first.Contains("RoutesEnabled=1")&&first.Contains("BattleHullEnabled=1")&&first.Contains("BattleCrewEnabled=0")&&first.Contains("BattleSuppliesEnabled=1")&&!first.Contains("BattleProtectionEnabled")&&!first.Contains("Carry"),"new switches saved without retired cargo keys");
        string revision=Field<string>(form,"revision");
        Check((bool)Call(form,"SaveSettings")&&Field<string>(form,"revision")!=revision,"atomic replacement uses a new revision");
        Check(Directory.GetFiles(root,"*.tmp").Length==0,"atomic save leaves no temporary files");
        using(var reload=new TrainerForm(root)) {
          Check(Field<CheckBox>(reload,"routesEnabled").Checked&&Field<CheckBox>(reload,"battleHullEnabled").Checked&&!Field<CheckBox>(reload,"battleCrewEnabled").Checked&&Field<CheckBox>(reload,"battleSuppliesEnabled").Checked,"new options survive restart");
          Check(Field<CheckBox>(reload,"keepRevealedEnabled").Checked,"fog switch survives trainer restart");
          Check(Field<CheckBox>(reload,"nearestCoastEnabled").Checked,
            "attack setting survives restart");
          Check(Field<CheckBox>(reload,"campOverlapEnabled").Checked,"camp overlap survives restart");
          Check(Field<TrackBar>(reload,"walkSlider").Value==35&&Field<CheckBox>(reload,"walkEnabled").Checked,"settings survive restart");
          Check(Field<TrackBar>(reload,"constructionSlider").Value==55&&Field<CheckBox>(reload,"constructionEnabled").Checked,
            "construction factor survives restart");
        }
        for(int mask=0;mask<8;mask++) {
          Field<CheckBox>(form,"battleHullEnabled").Checked=(mask&1)!=0;
          Field<CheckBox>(form,"battleCrewEnabled").Checked=(mask&2)!=0;
          Field<CheckBox>(form,"battleSuppliesEnabled").Checked=(mask&4)!=0;
          Check((bool)Call(form,"SaveSettings"),"individual combination saves");
          using(var reload=new TrainerForm(root)) {
            Check(Field<CheckBox>(reload,"battleHullEnabled").Checked==((mask&1)!=0)&&
              Field<CheckBox>(reload,"battleCrewEnabled").Checked==((mask&2)!=0)&&
              Field<CheckBox>(reload,"battleSuppliesEnabled").Checked==((mask&4)!=0),"individual combination survives reload without changing its neighbors");
          }
        }
        Call(form,"ResetSettings");
        string reset=File.ReadAllText(Path.Combine(root,"settings.ini"));
        Check(reset.Contains("TransportEnabled=0")&&reset.Contains("RoutesEnabled=0")&&reset.Contains("BattleHullEnabled=0")&&reset.Contains("BattleCrewEnabled=0")&&reset.Contains("BattleSuppliesEnabled=0")&&reset.Contains("ShipsEnabled=0"),"reset immediately saves all disabled");
        Check(reset.Contains("TransportSteps=10")&&!reset.Contains("Carry")&&reset.Contains("ShipsSteps=10"),"reset stores vanilla factors");
        Check(reset.Contains("ConstructionEnabled=0")&&reset.Contains("ConstructionSteps=10"),"reset immediately disables construction and restores x1");
        Check(reset.Contains("CampOverlapEnabled=0"),"reset restores camp overlap restriction");
        Check(reset.Contains("KeepRevealedEnabled=0"),"reset restores normal region cover behavior");
        Check(reset.Contains("NearestCoastEnabled=0"),"reset disables nearest coast");
        var moduleStatus=form.GetType().GetMethod("ModuleStatus",BindingFlags.NonPublic|BindingFlags.Instance);
        var attackLabel=Field<Label>(form,"nearestCoastStatus");
        var pending=new Dictionary<string,string>{{"NearestCoastState","Waiting"},{"NativeNearestCoastEnabled","1"}};
        moduleStatus.Invoke(form,new object[]{attackLabel,pending,"NearestCoast"});
        Check(attackLabel.Text.Contains("Neuberechnung"),"pending world refresh is visible instead of false success");
        pending["NearestCoastState"]="Applied";pending["NativeAttackPoints"]="20";pending["NativeAttackEligiblePoints"]="0";
        moduleStatus.Invoke(form,new object[]{attackLabel,pending,"NearestCoast"});
        Check(attackLabel.Text.Contains("kein Küstenpunkt"),"zero eligible points offers refresh");
        pending["NativeAttackEligiblePoints"]="3";moduleStatus.Invoke(form,new object[]{attackLabel,pending,"NearestCoast"});
        Check(attackLabel.Text.Contains("3 / 20"),"last coverage measurement is shown");
        pending["NativeNearestCoastEnabled"]="0";moduleStatus.Invoke(form,new object[]{attackLabel,pending,"NearestCoast"});
        Check(attackLabel.Text.Contains("Deaktiviert"),"disabled state uses confirmed native switch");
        var fogLabel=Field<Label>(form,"keepRevealedStatus");
        var shipLabel=Field<Label>(form,"shipStatus");
        var shipStatus=new Dictionary<string,string>{{"ShipsState","Applied"},{"NativeShipCalls","0"}};
        moduleStatus.Invoke(form,new object[]{shipLabel,shipStatus,"Ships"});
        Check(shipLabel.Text.Contains("wartet auf Fahrtberechnung"),"ship status waits for native calculation");
        shipStatus["NativeShipCalls"]="12";
        moduleStatus.Invoke(form,new object[]{shipLabel,shipStatus,"Ships"});
        Check(shipLabel.Text.Contains("im Spiel prüfen")&&!shipLabel.Text.Contains("Limit 100"),"ship hook count is not presented as verified gameplay");
        shipStatus["ShipsState"]="Error";shipStatus["NativeError"]="UnsupportedGameBuild";
        moduleStatus.Invoke(form,new object[]{shipLabel,shipStatus,"Ships"});
        Check(shipLabel.Text.Contains("nicht unterstützt"),"ship module reports version lock failures");
        var routeStatus=new Dictionary<string,string>{{"RoutesState","Applied"},{"RoutesEnabled","0"}};
        var routeLabel=Field<Label>(form,"routesStatus");
        Field<CheckBox>(form,"routesEnabled").Checked=true;
        moduleStatus.Invoke(form,new object[]{routeLabel,routeStatus,"Routes"});
        Check(routeLabel.Text.Contains("Deaktiviert"),"unsaved route toggle cannot report backend success");
        routeStatus["RoutesEnabled"]="1";
        moduleStatus.Invoke(form,new object[]{routeLabel,routeStatus,"Routes"});
        Check(routeLabel.Text.Contains("angehoben"),"confirmed route setting is displayed");
        Field<CheckBox>(form,"routesEnabled").Checked=false;Call(form,"SaveSettings");
        var battleStatus=new Dictionary<string,string>{{"BattleProtectionState","Applied"},{"NativeBattleHullEnabled","1"},{"NativeBattleCrewEnabled","0"},{"NativeBattleSuppliesEnabled","1"},{"NativeBattleStatBlocks","2"}};
        var battleLabel=Field<Label>(form,"battleProtectionStatus");
        moduleStatus.Invoke(form,new object[]{battleLabel,battleStatus,"BattleProtection"});
        Check(battleLabel.Text.Contains("im Spiel prüfen"),"battle counter does not claim gameplay verification");
        Check(battleLabel.Text.Contains("Leben / Vorräte")&&!battleLabel.Text.Contains("Crew"),"status names only the confirmed protection switches");
        var fogStatus=new Dictionary<string,string>{{"KeepRevealedState","Applied"},{"NativeKeepRevealedEnabled","1"}};
        moduleStatus.Invoke(form,new object[]{fogLabel,fogStatus,"KeepRevealed"});
        Check(fogLabel.Text.Contains("wartet auf Regionenberechnung"),"unobserved fog calculations are not reported as tested");
        fogStatus["NativeFogKeepChecks"]="9";
        moduleStatus.Invoke(form,new object[]{fogLabel,fogStatus,"KeepRevealed"});
        Check(fogLabel.Text.Contains("Nebelverhalten im Spiel prüfen"),"fog runtime counter stays distinct from gameplay confirmation");
        fogStatus["NativeKeepRevealedEnabled"]="0";
        moduleStatus.Invoke(form,new object[]{fogLabel,fogStatus,"KeepRevealed"});
        Check(fogLabel.Text.Contains("Deaktiviert"),"fog disabled status uses native readback");
        Call(form,"RefreshGameStatus");
        if(args.Length>0) {
          form.ShowInTaskbar=false;form.StartPosition=FormStartPosition.Manual;
          form.Location=new Point(-20000,-20000);form.Show();Application.DoEvents();
          using(var image=new Bitmap(form.Width,form.Height)) {
            form.DrawToBitmap(image,new Rectangle(0,0,form.Width,form.Height));
            image.Save(args[0],System.Drawing.Imaging.ImageFormat.Png);
          }
          form.AutoScrollPosition=new Point(0,1452);Application.DoEvents();
          using(var image=new Bitmap(form.Width,form.Height)) {
            form.DrawToBitmap(image,new Rectangle(0,0,form.Width,form.Height));
            image.Save(Path.Combine(Path.GetDirectoryName(args[0]),Path.GetFileNameWithoutExtension(args[0])+"-bottom.png"),System.Drawing.Imaging.ImageFormat.Png);
          }
          form.Hide();
        }
      }
      File.WriteAllText(Path.Combine(root,"settings.ini"),"TransportSteps=NaN\nCarrySteps=Infinity\nShipsSteps=100000000000000000000\nTransportEnabled=garbage\n");
      using(var bad=new TrainerForm(root)) {
        Check(!Field<CheckBox>(bad,"keepRevealedEnabled").Checked,"legacy profile leaves fog option disabled");
        Check(!Field<CheckBox>(bad,"nearestCoastEnabled").Checked,
          "legacy profile keeps attack separation disabled");
        Check(!Field<CheckBox>(bad,"campOverlapEnabled").Checked,"legacy profile leaves camp overlap disabled");
        Check(Field<TrackBar>(bad,"walkSlider").Value==20&&!Field<CheckBox>(bad,"routesEnabled").Checked,"invalid numeric settings use safe defaults");
        Check(Field<TrackBar>(bad,"shipSlider").Value==100,"large finite value clamps without integer overflow");
        Check(!Field<CheckBox>(bad,"walkEnabled").Checked,"invalid enable value stays disabled");
        Check(!Field<CheckBox>(bad,"constructionEnabled").Checked&&Field<TrackBar>(bad,"constructionSlider").Value==20,
          "older profile loads with construction disabled");
      }
      File.WriteAllText(Path.Combine(root,"settings.ini"),"ConstructionEnabled=1\nConstructionSteps=999\nAttackRadiusEnabled=1\nAttackRadiusSteps=85\n");
      using(var bounded=new TrainerForm(root)) {
        Check(Field<TrackBar>(bounded,"constructionSlider").Value==200,"construction input clamps to x20");
        Check(Field<CheckBox>(bounded,"nearestCoastEnabled").Checked,"v0.6 enabled state migrates to nearest coast");
      }
      File.WriteAllText(Path.Combine(root,"settings.ini"),"NearestCoastEnabled=0\nAttackRadiusEnabled=1\nAttackRadiusSteps=85\n");
      using(var migrated=new TrainerForm(root)) {
        Check(!Field<CheckBox>(migrated,"nearestCoastEnabled").Checked,"explicit nearest coast switch overrides legacy profile");
        Call(migrated,"SaveSettings");
        Check(!File.ReadAllText(Path.Combine(root,"settings.ini")).Contains("AttackRadius"),"saving removes obsolete radius fields");
      }
      File.WriteAllText(Path.Combine(root,"settings.ini"),"BattleProtectionEnabled=1\n");
      using(var legacy=new TrainerForm(root)) {
        Check(Field<CheckBox>(legacy,"battleHullEnabled").Checked&&Field<CheckBox>(legacy,"battleCrewEnabled").Checked&&Field<CheckBox>(legacy,"battleSuppliesEnabled").Checked,"old combined protection enables all three switches");
      }
      File.WriteAllText(Path.Combine(root,"settings.ini"),"BattleProtectionEnabled=1\nBattleHullEnabled=0\nBattleCrewEnabled=1\nBattleSuppliesEnabled=0\n");
      using(var individual=new TrainerForm(root)) {
        Check(!Field<CheckBox>(individual,"battleHullEnabled").Checked&&Field<CheckBox>(individual,"battleCrewEnabled").Checked&&!Field<CheckBox>(individual,"battleSuppliesEnabled").Checked,"explicit individual switches override old combined protection");
        Call(individual,"SaveSettings");
        Check(!File.ReadAllText(Path.Combine(root,"settings.ini")).Contains("BattleProtectionEnabled"),"saving retires combined protection key");
      }
      DateTime now=DateTime.UtcNow;
      long epoch=(long)(now-new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc)).TotalSeconds;
      var d=new Dictionary<string,string>{{"Version","0.13.0"},{"Heartbeat",epoch.ToString()},{"Revision","r1"},{"Status","Applied"},{"NativeReady","1"},
        {"TransportState","Applied"},{"RoutesState","Applied"},{"BattleProtectionState","Applied"},{"ShipsState","Applied"},{"ConstructionState","Applied"},{"CampOverlapState","Applied"},{"NearestCoastState","Applied"},{"KeepRevealedState","Applied"}};
      Check(TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(-60),now),"recent heartbeat in this process accepted");
      Check(!TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(-60),now.AddSeconds(20)),"stale heartbeat rejected");
      Check(!TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(4),now),"previous process heartbeat rejected");
      Check(TrainerForm.IsApplied(d,"r1")&&!TrainerForm.IsApplied(d,"r2"),"only matching saved revision acknowledged");
      d.Remove("KeepRevealedState");Check(!TrainerForm.IsApplied(d,"r1"),"fog confirmation required for overall success");d["KeepRevealedState"]="Applied";
      d["Version"]="0.12.0";Check(!TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(-60),now),"older backend cannot acknowledge route or battle changes");d["Version"]="0.13.0";
      d["NearestCoastState"]="Waiting";Check(!TrainerForm.IsApplied(d,"r1"),"pending attack cache refresh blocks overall acknowledgement");d["NearestCoastState"]="Applied";
      d.Remove("CampOverlapState");Check(!TrainerForm.IsApplied(d,"r1"),"overlap must be confirmed before overall success");d["CampOverlapState"]="Applied";
      d.Remove("ConstructionState");Check(!TrainerForm.IsApplied(d,"r1"),"construction must be confirmed before overall success");d["ConstructionState"]="Applied";
      d["NativeReady"]="0";Check(!TrainerForm.IsApplied(d,"r1"),"asset writes alone cannot acknowledge native transport");d["NativeReady"]="1";
      d.Remove("ShipsState");Check(!TrainerForm.IsApplied(d,"r1"),"partial status file cannot report success");
      d["Heartbeat"]="9223372036854775807";Check(!TrainerForm.HasCurrentHeartbeat(d,now,now),"out-of-range status timestamp rejected");
      // This directory was just created by this test and contains only its own settings.
      foreach(string file in Directory.GetFiles(root))File.Delete(file);Directory.Delete(root);
      Console.WriteLine("UI: "+passed+" checks passed");return 0;
    }catch(Exception ex){Console.Error.WriteLine(ex);return 1;}
  }
}
