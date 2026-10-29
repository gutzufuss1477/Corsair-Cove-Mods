using System;
using System.IO;
using System.Drawing;
using System.Reflection;
using System.Collections.Generic;
using System.Windows.Forms;
using CoveQoLTrainer;

internal static class ReleaseTests {
  static int passed;
  static void Check(bool condition,string message){if(!condition)throw new Exception(message);passed++;Console.WriteLine("PASS "+message);}
  static T Field<T>(object o,string name){return (T)o.GetType().GetField(name,BindingFlags.NonPublic|BindingFlags.Instance).GetValue(o);}
  static object Call(object o,string name){return o.GetType().GetMethod(name,BindingFlags.NonPublic|BindingFlags.Instance).Invoke(o,null);}
  static void CheckLayout(Control parent) {
    foreach(Control c in parent.Controls) {
      Check(c.Left>=0&&c.Top>=0&&c.Right<=parent.ClientSize.Width+1&&c.Bottom<=parent.ClientSize.Height+1,"visible without scrolling: "+c.GetType().Name+" "+c.Bounds+" in "+parent.ClientSize);
      if(c is Panel)CheckLayout(c);
      if(c is CheckBox) {
        var size=TextRenderer.MeasureText(c.Text,c.Font,new Size(10000,10000),TextFormatFlags.SingleLine|TextFormatFlags.NoPadding);
        Check(size.Width+22<=c.Width,"translated checkbox fits: "+c.Text);
      }
      if(c is Label&&c.Text=="CORSAIR COVE") {
        var size=TextRenderer.MeasureText(c.Text,c.Font,new Size(10000,10000),TextFormatFlags.SingleLine);
        Check(size.Width<=c.Width&&size.Height<=c.Height,"full game title fits vertically and horizontally");
      }
    }
  }
  [STAThread] static int Main(string[] args){
    try {
      Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
      string root=Path.Combine(Path.GetTempPath(),"CoveQoLTests-"+Guid.NewGuid().ToString("N"));
      Directory.CreateDirectory(root);
      using(var form=new TrainerForm(root)) {
        Check(!Field<CheckBox>(form,"walkEnabled").Checked,"fresh profile starts disabled");
        Check(!Field<CheckBox>(form,"campHousingEnabled").Checked&&Field<TrackBar>(form,"campHousingSlider").Value==100&&Field<TrackBar>(form,"campHousingSlider").Maximum==1000,
          "housing starts disabled with x10 preset and x100 maximum");
        Check(!Field<CheckBox>(form,"warehouseEnabled").Checked&&!Field<CheckBox>(form,"bridgesEnabled").Checked,"warehouse and bridge extensions default off");
        Field<CheckBox>(form,"warehouseEnabled").Checked=true;Field<ComboBox>(form,"warehouseTypes").SelectedIndex=0;
        Field<CheckBox>(form,"bridgesEnabled").Checked=true;Field<TrackBar>(form,"bridgesSlider").Value=45;
        Field<CheckBox>(form,"campHousingEnabled").Checked=true;
        Field<TrackBar>(form,"campHousingSlider").Value=205;
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
        Check(first.Contains("WarehouseEnabled=1")&&first.Contains("WarehouseTypes=6")&&first.Contains("BridgesEnabled=1")&&first.Contains("BridgesSteps=45"),"warehouse selection and bridge factor save independently");
        Check(first.Contains("CampHousingEnabled=1")&&first.Contains("CampHousingSteps=205"),"housing saves independently as integer tenths");
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
          Check(Field<CheckBox>(reload,"warehouseEnabled").Checked&&Field<ComboBox>(reload,"warehouseTypes").SelectedIndex==0&&Field<CheckBox>(reload,"bridgesEnabled").Checked&&Field<TrackBar>(reload,"bridgesSlider").Value==45,"warehouse and bridge choices survive restart");
          Check(Field<CheckBox>(reload,"campHousingEnabled").Checked&&Field<TrackBar>(reload,"campHousingSlider").Value==205,"housing survives trainer restart");
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
        Check(reset.Contains("WarehouseEnabled=0")&&reset.Contains("BridgesEnabled=0")&&reset.Contains("BridgesSteps=10"),"reset disables new features and restores bridge factor");
        Check(reset.Contains("CampHousingEnabled=0")&&reset.Contains("CampHousingSteps=10"),"reset disables housing and restores x1");
        Check(reset.Contains("TransportEnabled=0")&&reset.Contains("RoutesEnabled=0")&&reset.Contains("BattleHullEnabled=0")&&reset.Contains("BattleCrewEnabled=0")&&reset.Contains("BattleSuppliesEnabled=0")&&reset.Contains("ShipsEnabled=0"),"reset immediately saves all disabled");
        Check(reset.Contains("TransportSteps=10")&&!reset.Contains("Carry")&&reset.Contains("ShipsSteps=10"),"reset stores vanilla factors");
        Check(reset.Contains("ConstructionEnabled=0")&&reset.Contains("ConstructionSteps=10"),"reset immediately disables construction and restores x1");
        Check(reset.Contains("CampOverlapEnabled=0"),"reset restores camp overlap restriction");
        Check(reset.Contains("KeepRevealedEnabled=0"),"reset restores normal region cover behavior");
        Check(reset.Contains("NearestCoastEnabled=0"),"reset disables nearest coast");
        Check(!form.AutoScroll,"main window never scrolls");
        Check(form.FormBorderStyle==FormBorderStyle.Sizable&&form.MaximizeBox,"window supports mouse resizing and maximize");
        Field<CheckBox>(form,"campRadiusEnabled").Checked=true;
        Field<TrackBar>(form,"campRadiusSlider").Value=750;
        Check((bool)Call(form,"SaveSettings"),"range setting saves");
        using(var reload=new TrainerForm(root))Check(Field<CheckBox>(reload,"campRadiusEnabled").Checked&&Field<TrackBar>(reload,"campRadiusSlider").Value==750,"range factor survives restart independently");
        var snapshot=File.ReadAllBytes(Path.Combine(root,"settings.ini"));
        Field<TrackBar>(form,"walkSlider").Value=55;
        foreach(string code in Localization.Codes) {
          form.SetLanguage(code,true);
          Check(Field<TrackBar>(form,"walkSlider").Value==55&&Field<bool>(form,"dirty"),"language change preserves unsaved edits: "+code);
          Check(File.ReadAllBytes(Path.Combine(root,"settings.ini")).Length==snapshot.Length,"language switch does not apply gameplay settings");
          CheckLayout(form);
          foreach(var size in new[]{new Size(800,520),new Size(1280,800),new Size(1000,570),new Size(880,570)}) {
            form.ClientSize=size;CheckLayout(form);
            Check(Field<TrackBar>(form,"walkSlider").Value==55&&Field<bool>(form,"dirty"),"resizing preserves unsaved edits");
            Check(System.Linq.Enumerable.SequenceEqual(File.ReadAllBytes(Path.Combine(root,"settings.ini")),snapshot),"resizing never writes gameplay settings");
          }
          if(args.Length>0) {
            form.ShowInTaskbar=false;form.StartPosition=FormStartPosition.Manual;form.Location=new Point(-20000,-20000);form.Show();Application.DoEvents();
            using(var image=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(image,new Rectangle(0,0,form.Width,form.Height));image.Save(Path.Combine(args[0],"trainer-"+code+".png"));}
            form.Hide();
          }
        }
        form.SetLanguage("de",false);Call(form,"ResetSettings");
        Check(!Field<CheckBox>(form,"campRadiusEnabled").Checked&&Field<TrackBar>(form,"campRadiusSlider").Value==10,"reset disables range and restores x1");
      }
      File.WriteAllText(Path.Combine(root,"settings.ini"),"TransportSteps=NaN\nCarrySteps=Infinity\nShipsSteps=100000000000000000000\nTransportEnabled=garbage\n");
      using(var bad=new TrainerForm(root)) {
        Check(!Field<CheckBox>(bad,"campHousingEnabled").Checked&&Field<TrackBar>(bad,"campHousingSlider").Value==100,"legacy profile safely leaves housing disabled");
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
      var d=new Dictionary<string,string>{{"Version","1.2.5"},{"Heartbeat",epoch.ToString()},{"Revision","r1"},{"Status","Applied"},{"NativeReady","1"},
        {"TransportState","Applied"},{"RoutesState","Applied"},{"BattleProtectionState","Applied"},{"ShipsState","Applied"},{"ConstructionState","Applied"},{"CampRadiusState","Applied"},{"CampHousingState","Applied"},{"WarehouseState","Applied"},{"BridgesState","Applied"},{"CampOverlapState","Applied"},{"NearestCoastState","Applied"},{"KeepRevealedState","Applied"}};
      Check(TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(-60),now),"recent heartbeat in this process accepted");
      Check(!TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(-60),now.AddSeconds(20)),"stale heartbeat rejected");
      Check(!TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(4),now),"previous process heartbeat rejected");
      Check(TrainerForm.IsApplied(d,"r1")&&!TrainerForm.IsApplied(d,"r2"),"only matching saved revision acknowledged");
      d.Remove("CampHousingState");Check(!TrainerForm.IsApplied(d,"r1"),"housing native acknowledgement is required for overall success");d["CampHousingState"]="Applied";
      d["Version"]="1.0.0";Check(!TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(-60),now),"old release backend cannot confirm new housing option");d["Version"]="1.2.5";
      d.Remove("KeepRevealedState");Check(!TrainerForm.IsApplied(d,"r1"),"fog confirmation required for overall success");d["KeepRevealedState"]="Applied";
      d["Version"]="0.12.0";Check(!TrainerForm.HasCurrentHeartbeat(d,now.AddSeconds(-60),now),"older backend cannot acknowledge route or battle changes");d["Version"]="1.2.5";
      d["NearestCoastState"]="Waiting";Check(!TrainerForm.IsApplied(d,"r1"),"pending attack cache refresh blocks overall acknowledgement");d["NearestCoastState"]="Applied";
      d.Remove("CampOverlapState");Check(!TrainerForm.IsApplied(d,"r1"),"overlap must be confirmed before overall success");d["CampOverlapState"]="Applied";
      d.Remove("ConstructionState");Check(!TrainerForm.IsApplied(d,"r1"),"construction must be confirmed before overall success");d["ConstructionState"]="Applied";
      d["NativeReady"]="0";Check(!TrainerForm.IsApplied(d,"r1"),"asset writes alone cannot acknowledge native transport");d["NativeReady"]="1";
      d.Remove("ShipsState");Check(!TrainerForm.IsApplied(d,"r1"),"partial status file cannot report success");
      d["Heartbeat"]="9223372036854775807";Check(!TrainerForm.HasCurrentHeartbeat(d,now,now),"out-of-range status timestamp rejected");
      d["ShipsState"]="Applied";d.Remove("CampRadiusState");Check(!TrainerForm.IsApplied(d,"r1"),"range confirmation required");
      foreach(float scale in new[]{1.25f,1.5f,2.0f})using(var form=new TrainerForm(root)) {
        form.SetLanguage("ru",false);form.ClientSize=new Size((int)(880*scale),(int)(570*scale));form.FitToArea(new Size(1920,1080));CheckLayout(form);
        Check(form.Width<=1920&&form.Height<=1080,"scaled window fits work area");
      }
      using(var form=new TrainerForm(root)) {
        form.SetLanguage("de",false);form.ClientSize=new Size(880,570);
        var controls=Field<System.Collections.Generic.Dictionary<Control,string>>(form,"textKeys");
        var bounds=new System.Collections.Generic.Dictionary<Control,Rectangle>();var fontSizes=new System.Collections.Generic.Dictionary<Control,float>();
        foreach(var item in controls){bounds[item.Key]=item.Key.Bounds;fontSizes[item.Key]=item.Key.Font.SizeInPoints;}
        for(int i=0;i<40;i++){form.ClientSize=new Size(1280,800);form.ClientSize=new Size(800,520);form.ClientSize=new Size(880,570);}
        foreach(var item in controls)Check(item.Key.Bounds==bounds[item.Key]&&Math.Abs(item.Key.Font.SizeInPoints-fontSizes[item.Key])<0.001F,"resize round trips do not accumulate font or geometry errors");
        if(args.Length>0) {
          form.ClientSize=new Size(1280,800);form.ShowInTaskbar=false;form.StartPosition=FormStartPosition.Manual;form.Location=new Point(-20000,-20000);form.Show();Application.DoEvents();
          using(var image=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(image,new Rectangle(0,0,form.Width,form.Height));image.Save(Path.Combine(args[0],"trainer-de-large.png"));}
          form.Hide();form.ClientSize=new Size(800,520);form.Show();Application.DoEvents();
          using(var image=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(image,new Rectangle(0,0,form.Width,form.Height));image.Save(Path.Combine(args[0],"trainer-de-small.png"));}
          form.Hide();
        }
      }
      Check(Localization.Normalize("tchinese")=="zh-Hant"&&Localization.Normalize("zh-TW")=="zh-Hant"&&Localization.Normalize("brazilian")=="pt-BR","Steam and Windows language variants map correctly");
      SetupTests.Run(Check);
      // This directory was just created by this test and contains only its own settings.
      foreach(string file in Directory.GetFiles(root))File.Delete(file);Directory.Delete(root);
      Console.WriteLine("UI: "+passed+" checks passed");return 0;
    }catch(Exception ex){Console.Error.WriteLine(ex);return 1;}
  }
}
