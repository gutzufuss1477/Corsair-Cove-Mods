using System;
using System.IO;
using System.Linq;
using System.Diagnostics;
using System.Drawing;
using System.Windows.Forms;
using System.Globalization;
using System.Collections.Generic;
using System.Reflection;
using System.Threading;
[assembly: AssemblyVersion("1.2.5.0")]
[assembly: AssemblyFileVersion("1.2.5.0")]
[assembly: AssemblyProduct("Corsair Cove QoL Trainer")]
namespace CoveQoLTrainer {
  internal static class Program {
    [STAThread] static int Main(string[] args) {
      Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
      if(args.Length>0&&args[0]=="--install-elevated")return Bootstrap.Elevated(args);
      bool first;
      using(var mutex=new Mutex(true,"Local\\CoveQoLTrainer.UI",out first)) {
        string data=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CorsairCoveQoL");
        string game=Bootstrap.FindGame();
        string code=Localization.Detect(game);
        try{string prefs=Path.Combine(data,"ui.ini");if(File.Exists(prefs)){var match=System.Text.RegularExpressions.Regex.Match(File.ReadAllText(prefs),@"(?m)^Language=([^\r\n]+)");if(match.Success&&match.Groups[1].Value!="auto")code=match.Groups[1].Value;}}catch{}
        var lang=new Localization(code);
        if(!first){MessageBox.Show(lang["already"],"Cove QoL Trainer");return 0;}
        if(!Bootstrap.Prepare(ref game,data,lang))return 1;
        Application.Run(new TrainerForm(data,game));return 0;
      }
    }
  }
  public sealed class TrainerForm:Form {
    readonly Color bg=Color.FromArgb(17,22,29),card=Color.FromArgb(26,33,43),line=Color.FromArgb(45,54,67);
    readonly Color ink=Color.FromArgb(235,240,247),muted=Color.FromArgb(150,164,183),accent=Color.FromArgb(66,190,178),warning=Color.FromArgb(245,184,101);
    readonly Font main=new Font("Segoe UI",9F),headline=new Font("Segoe UI Semibold",9F);
    readonly string settingsPath,statusPath,prefsPath,gameDirectory;
    readonly ToolTip tips=new ToolTip{AutoPopDelay=25000,InitialDelay=350,ReshowDelay=100};
    readonly Dictionary<Control,string> textKeys=new Dictionary<Control,string>();
    readonly Dictionary<Control,string> tipKeys=new Dictionary<Control,string>();
    readonly Dictionary<string,Label> states=new Dictionary<string,Label>();
    readonly List<CheckBox> switches=new List<CheckBox>();
    readonly List<TrackBar> sliders=new List<TrackBar>();
    readonly List<NumericUpDown> numbers=new List<NumericUpDown>();
    sealed class LayoutItem {
      internal Control Control;
      internal Rectangle Bounds;
      internal Font Font;
    }
    readonly List<LayoutItem> layoutItems=new List<LayoutItem>();
    readonly List<Font> layoutFonts=new List<Font>();
    bool arranging;
    float displayScale=1,lastFontScale=-1;
    CheckBox walkEnabled,routesEnabled,shipEnabled,constructionEnabled,campRadiusEnabled,campHousingEnabled,campOverlapEnabled,nearestCoastEnabled,keepRevealedEnabled;
    CheckBox battleHullEnabled,battleCrewEnabled,battleSuppliesEnabled,bridgesEnabled,warehouseEnabled;
    TrackBar bridgesSlider;
    ComboBox warehouseTypes;
    TrackBar walkSlider,shipSlider,constructionSlider,campRadiusSlider,campHousingSlider;
    Label status,saved;
    ComboBox language;
    System.Windows.Forms.Timer poll;
    Localization L;
    bool loading,dirty,translating;
    string revision="legacy";
    public TrainerForm():this(null,null){}
    public TrainerForm(string dataDirectory):this(dataDirectory,null){}
    public TrainerForm(string dataDirectory,string game) {
      gameDirectory=game;
      string data=dataDirectory??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"CorsairCoveQoL");
      settingsPath=Path.Combine(data,"settings.ini");statusPath=Path.Combine(data,"status.ini");prefsPath=Path.Combine(data,"ui.ini");
      string selected="auto";
      try{if(File.Exists(prefsPath))selected=Value(ReadIni(prefsPath),"Language","auto");}catch{}
      L=new Localization(selected=="auto"?Localization.Detect(game):selected);
      Text="Corsair Cove | QoL Trainer 1.2.5";
      Icon=Icon.ExtractAssociatedIcon(Application.ExecutablePath);
      // All resize geometry comes from one immutable 96-DPI layout. Mixing
      // repeated WinForms Scale calls and inherited fonts clipped the heading.
      AutoScaleMode=AutoScaleMode.None;
      ClientSize=new Size(880,602);AutoScroll=false;
      FormBorderStyle=FormBorderStyle.Sizable;MaximizeBox=true;StartPosition=FormStartPosition.CenterScreen;
      BackColor=bg;ForeColor=ink;Font=main;DoubleBuffered=true;
      Build();CaptureLayout(this);
      using(var graphics=CreateGraphics())displayScale=graphics.DpiX/96F;
      var area=Screen.FromControl(this).WorkingArea.Size;
      MinimumSize=SizeFromClientSize(new Size(Math.Min((int)Math.Round(800*displayScale),area.Width-40),Math.Min((int)Math.Round(550*displayScale),area.Height-80)));
      ClientSize=new Size((int)Math.Round(880*displayScale),(int)Math.Round(602*displayScale));
      FitToArea(area);ArrangeContent();LoadSettings();SetLanguage(selected,false);
      FormClosing+=(s,e)=>{if(dirty){var answer=MessageBox.Show(this,L["unsaved"],Text,MessageBoxButtons.YesNoCancel,MessageBoxIcon.Question);e.Cancel=answer==DialogResult.Cancel||(answer==DialogResult.Yes&&!SaveSettings());}};
      poll=new System.Windows.Forms.Timer{Interval=2000};poll.Tick+=(s,e)=>RefreshGameStatus();poll.Start();RefreshGameStatus();
    }
    Label LabelAt(Control parent,string text,int x,int y,int w,int h,Color color,Font font) {
      var label=new Label{Text=text,Location=new Point(x,y),Size=new Size(w,h),ForeColor=color,BackColor=Color.Transparent,Font=font,UseMnemonic=false,TextAlign=ContentAlignment.MiddleLeft};parent.Controls.Add(label);return label;
    }
    void Bind(Control control,string key,string tip){textKeys[control]=key;if(tip!=null)tipKeys[control]=tip;}
    Panel PanelAt(int x,int y,int w,int h) {
      var panel=new Panel{Location=new Point(x,y),Size=new Size(w,h),BackColor=card};
      panel.Paint+=(s,e)=>{using(var pen=new Pen(line))e.Graphics.DrawRectangle(pen,0,0,panel.Width-1,panel.Height-1);};Controls.Add(panel);return panel;
    }
    CheckBox Toggle(Control parent,string key,string tip,int x,int y,int width) {
      var chk=new CheckBox{Location=new Point(x,y),Size=new Size(width,30),ForeColor=ink,BackColor=Color.Transparent,UseMnemonic=false};
      chk.CheckedChanged+=(s,e)=>Changed();parent.Controls.Add(chk);switches.Add(chk);Bind(chk,key,tip);return chk;
    }
    void State(Control parent,string name,int x,int y) {
      var label=LabelAt(parent,"●",x,y,20,24,muted,main);states[name]=label;
    }
    void Speed(Panel panel,int row,string key,string name,int max,int initial,out CheckBox toggle,out TrackBar slider) {
      int y=28+row*51;
      toggle=Toggle(panel,key,key+"Tip",16,y,366);toggle.Height=24;State(panel,name,390,y);
      var track=new TrackBar{AutoSize=false,Minimum=10,Maximum=max,Value=initial,TickStyle=TickStyle.None,Location=new Point(18,y+25),Size=new Size(276,27),SmallChange=1,LargeChange=10};
      var number=new NumericUpDown{Minimum=1,Maximum=max/10m,Value=initial/10m,DecimalPlaces=1,Increment=0.1m,Location=new Point(320,y+24),Size=new Size(83,25),BackColor=bg,ForeColor=accent,BorderStyle=BorderStyle.FixedSingle,TextAlign=HorizontalAlignment.Right};
      LabelAt(panel,"×",301,y+23,18,25,accent,headline);
      track.ValueChanged+=(s,e)=>{number.Value=track.Value/10m;Changed();};
      number.ValueChanged+=(s,e)=>{track.Value=(int)(number.Value*10);Changed();};
      panel.Controls.Add(track);panel.Controls.Add(number);sliders.Add(track);numbers.Add(number);tipKeys[track]=key+"Tip";tipKeys[number]=key+"Tip";slider=track;
    }
    CheckBox MapToggle(Panel panel,int row,string key,string name) {
      int y=30+row*59;var chk=Toggle(panel,key,key+"Tip",16,y,366);State(panel,name,390,y+3);
      var hint=LabelAt(panel,"",34,y+29,370,25,muted,new Font("Segoe UI",8F));
      // A single short hint keeps the primary labels readable in every language.
      Bind(hint,key=="routes"?"routesTip":key+"Tip",key+"Tip");hint.AutoEllipsis=true;
      return chk;
    }
    Button Action(string key,int x,int width,bool primary,EventHandler click) {
      var b=new Button{Location=new Point(x,548),Size=new Size(width,36),FlatStyle=FlatStyle.Flat,ForeColor=primary?bg:ink,BackColor=primary?accent:card,UseMnemonic=false,Cursor=Cursors.Hand};
      b.FlatAppearance.BorderColor=line;b.FlatAppearance.BorderSize=primary?0:1;b.Click+=click;Controls.Add(b);Bind(b,key,null);return b;
    }
    void Build() {
      LabelAt(this,"CORSAIR COVE",18,7,320,48,ink,new Font("Segoe UI Semibold",22F));
      LabelAt(this,"QOL TRAINER  /  1.2.5",354,20,290,30,accent,new Font("Segoe UI Semibold",11F));
      language=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Location=new Point(662,22),Size=new Size(200,27),BackColor=card,ForeColor=ink,FlatStyle=FlatStyle.Flat};
      Controls.Add(language);language.SelectedIndexChanged+=(s,e)=>{if(!translating)SetLanguage(language.SelectedIndex==0?"auto":Localization.Codes[language.SelectedIndex-1],true);};
      status=LabelAt(this,"",20,55,840,27,muted,main);
      var left=PanelAt(18,94,416,346);var right=PanelAt(446,94,416,346);
      Bind(LabelAt(left,"",16,5,384,25,muted,headline),"speed",null);Bind(LabelAt(right,"",16,5,384,25,muted,headline),"map",null);
      Speed(left,0,"walk","Transport",100,20,out walkEnabled,out walkSlider);
      Speed(left,1,"ships","Ships",100,20,out shipEnabled,out shipSlider);
      Speed(left,2,"construction","Construction",200,20,out constructionEnabled,out constructionSlider);
      Speed(left,3,"range","CampRadius",5000,500,out campRadiusEnabled,out campRadiusSlider);
      Speed(left,4,"housing","CampHousing",1000,100,out campHousingEnabled,out campHousingSlider);
      Speed(left,5,"bridges","Bridges",100,30,out bridgesEnabled,out bridgesSlider);
      routesEnabled=MapToggle(right,0,"routes","Routes");campOverlapEnabled=MapToggle(right,1,"overlap","CampOverlap");
      nearestCoastEnabled=MapToggle(right,2,"coast","NearestCoast");keepRevealedEnabled=MapToggle(right,3,"fog","KeepRevealed");
      warehouseEnabled=Toggle(right,"warehouse","warehouseTip",16,268,366);State(right,"Warehouse",390,271);
      warehouseTypes=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Location=new Point(320,302),Size=new Size(83,27),BackColor=bg,ForeColor=accent,FlatStyle=FlatStyle.Flat};
      warehouseTypes.Items.AddRange(new object[]{"6","9"});warehouseTypes.SelectedIndex=1;warehouseTypes.SelectedIndexChanged+=(s,e)=>Changed();right.Controls.Add(warehouseTypes);tipKeys[warehouseTypes]="warehouseTip";
      Bind(LabelAt(right,"",34,302,275,27,muted,main),"goodsTypes","warehouseTip");
      var battle=PanelAt(18,452,844,72);Bind(LabelAt(battle,"",16,5,795,25,muted,headline),"battle","battleTip");
      battleHullEnabled=Toggle(battle,"hull","battleTip",18,33,245);battleCrewEnabled=Toggle(battle,"crew","battleTip",290,33,245);battleSuppliesEnabled=Toggle(battle,"supplies","battleTip",560,33,245);State(battle,"BattleProtection",810,37);
      saved=LabelAt(this,"",20,531,460,15,muted,new Font("Segoe UI",8F));
      Action("help",18,110,false,(s,e)=>ShowHelp());Action("reset",474,190,false,(s,e)=>ResetSettings());Action("save",676,186,true,(s,e)=>SaveSettings());
    }
    internal void SetLanguage(string code,bool persist) {
      translating=true;
      L=new Localization(code=="auto"?Localization.Detect(gameDirectory):code);
      foreach(var item in textKeys)item.Key.Text=L[item.Value];foreach(var item in tipKeys)tips.SetToolTip(item.Key,L[item.Value]);
      language.Items.Clear();language.Items.Add(L["auto"]);language.Items.AddRange(Localization.Names);
      language.SelectedIndex=code=="auto"?0:Array.IndexOf(Localization.Codes,L.Code)+1;tips.SetToolTip(language,L["language"]);
      translating=false;
      if(persist)try{Directory.CreateDirectory(Path.GetDirectoryName(prefsPath));File.WriteAllText(prefsPath,"Language="+code+"\n");}catch(Exception ex){MessageBox.Show(this,L["saveError"]+"\n"+ex.Message,Text);}
      saved.Text=L[dirty?"dirty":"saved"];RefreshGameStatus();
    }
    void ShowHelp() {
      using(var dialog=new Form{Text=L["help"],ClientSize=new Size(650,390),StartPosition=FormStartPosition.CenterParent,BackColor=bg,ForeColor=ink,Font=main,MinimizeBox=false,MaximizeBox=false}) {
        var body=new TextBox{Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,Dock=DockStyle.Fill,BackColor=card,ForeColor=ink,BorderStyle=BorderStyle.None};
        string license="";using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Notices.txt"))if(stream!=null)using(var reader=new StreamReader(stream))license=reader.ReadToEnd();
        body.Text=L["helpBody"]+"\r\n\r\nCorsair Cove QoL Trainer 1.2.5\r\n\r\n"+license;dialog.Controls.Add(body);dialog.ShowDialog(this);
      }
    }
    void Changed(){if(!loading&&saved!=null){dirty=true;saved.Text=L["dirty"];saved.ForeColor=warning;}}
    void RefreshLabels(){for(int i=0;i<sliders.Count;i++)numbers[i].Value=sliders[i].Value/10m;}
    void ResetSettings(){loading=true;foreach(var chk in switches)chk.Checked=false;foreach(var slider in sliders)slider.Value=10;warehouseTypes.SelectedIndex=1;loading=false;RefreshLabels();Changed();SaveSettings();}
    bool EnabledValue(Dictionary<string,string> data,string key,bool fallback){
      string s;
      if(!data.TryGetValue(key,out s))return fallback;
      if(s=="1"||s.Equals("true",StringComparison.OrdinalIgnoreCase))return true;
      if(s=="0"||s.Equals("false",StringComparison.OrdinalIgnoreCase))return false;
      return fallback;
    }
    int SliderValue(Dictionary<string,string> data,string key,int fallback,int min,int max){
      string s;float v;
      if(!data.TryGetValue(key,out s))return fallback;
      if(!float.TryParse(s,NumberStyles.Float,CultureInfo.InvariantCulture,out v)||float.IsNaN(v)||float.IsInfinity(v)||v!=Math.Floor(v))return fallback;
      return (int)Math.Max(min,Math.Min(max,v));
    }
    void LoadSettings(){
      loading=true;
      try{
        if(File.Exists(settingsPath)){
          Dictionary<string,string> d=ReadIni(settingsPath);
          revision=Value(d,"Revision","legacy");
          walkEnabled.Checked=EnabledValue(d,"TransportEnabled",false);
          warehouseEnabled.Checked=EnabledValue(d,"WarehouseEnabled",false);
          warehouseTypes.SelectedIndex=Value(d,"WarehouseTypes","9")=="6"?0:1;
          bridgesEnabled.Checked=EnabledValue(d,"BridgesEnabled",false);
          bridgesSlider.Value=SliderValue(d,"BridgesSteps",30,10,100);
          routesEnabled.Checked=EnabledValue(d,"RoutesEnabled",false);
          bool oldBattle=EnabledValue(d,"BattleProtectionEnabled",false);
          battleHullEnabled.Checked=EnabledValue(d,"BattleHullEnabled",oldBattle);
          battleCrewEnabled.Checked=EnabledValue(d,"BattleCrewEnabled",oldBattle);
          battleSuppliesEnabled.Checked=EnabledValue(d,"BattleSuppliesEnabled",oldBattle);
          shipEnabled.Checked=EnabledValue(d,"ShipsEnabled",false);
          constructionEnabled.Checked=EnabledValue(d,"ConstructionEnabled",false);
          keepRevealedEnabled.Checked=EnabledValue(d,"KeepRevealedEnabled",false);
          campRadiusEnabled.Checked=EnabledValue(d,"CampRadiusEnabled",false);
          campRadiusSlider.Value=SliderValue(d,"CampRadiusSteps",500,10,5000);
          campHousingEnabled.Checked=EnabledValue(d,"CampHousingEnabled",false);
          campHousingSlider.Value=SliderValue(d,"CampHousingSteps",100,10,1000);
          campOverlapEnabled.Checked=EnabledValue(d,"CampOverlapEnabled",false);
          nearestCoastEnabled.Checked=EnabledValue(d,d.ContainsKey("NearestCoastEnabled")?"NearestCoastEnabled":"AttackRadiusEnabled",false);
          walkSlider.Value=SliderValue(d,"TransportSteps",20,10,100);
          shipSlider.Value=SliderValue(d,"ShipsSteps",20,10,100);
          constructionSlider.Value=SliderValue(d,"ConstructionSteps",20,10,200);
        }
        RefreshLabels();
      }catch(Exception ex){
        MessageBox.Show(L["loadError"]+"\n"+ex.Message,"QoL Trainer",MessageBoxButtons.OK,MessageBoxIcon.Warning);
      }finally{loading=false;}
    }
    bool SaveSettings(){
      try{
        Directory.CreateDirectory(Path.GetDirectoryName(settingsPath));
        string next=Guid.NewGuid().ToString("N");
        string[] rows=new string[]{
          "; Corsair Cove QoL Trainer - live configuration, polled by UE4SS backend",
          "; integer steps prevent floating-point locale issues",
          "Revision="+next,
          "TransportEnabled="+(walkEnabled.Checked?"1":"0"),
          "TransportSteps="+walkSlider.Value,
          "WarehouseEnabled="+(warehouseEnabled.Checked?"1":"0"),
          "WarehouseTypes="+(warehouseTypes.SelectedIndex==0?"6":"9"),
          "BridgesEnabled="+(bridgesEnabled.Checked?"1":"0"),
          "BridgesSteps="+bridgesSlider.Value,
          "RoutesEnabled="+(routesEnabled.Checked?"1":"0"),
          "BattleHullEnabled="+(battleHullEnabled.Checked?"1":"0"),
          "BattleCrewEnabled="+(battleCrewEnabled.Checked?"1":"0"),
          "BattleSuppliesEnabled="+(battleSuppliesEnabled.Checked?"1":"0"),
          "ShipsEnabled="+(shipEnabled.Checked?"1":"0"),
          "ShipsSteps="+shipSlider.Value,
          "ConstructionEnabled="+(constructionEnabled.Checked?"1":"0"),
          "ConstructionSteps="+constructionSlider.Value,
          "CampRadiusEnabled="+(campRadiusEnabled.Checked?"1":"0"),
          "CampRadiusSteps="+campRadiusSlider.Value,
          "CampHousingEnabled="+(campHousingEnabled.Checked?"1":"0"),
          "CampHousingSteps="+campHousingSlider.Value,
          "CampOverlapEnabled="+(campOverlapEnabled.Checked?"1":"0"),
          "NearestCoastEnabled="+(nearestCoastEnabled.Checked?"1":"0"),
          "KeepRevealedEnabled="+(keepRevealedEnabled.Checked?"1":"0")
        };
        string temp=settingsPath+"."+next+".tmp";
        try {
          File.WriteAllLines(temp,rows,new System.Text.UTF8Encoding(false));
          if(File.Exists(settingsPath))File.Replace(temp,settingsPath,null);
          else File.Move(temp,settingsPath);
        } finally {if(File.Exists(temp))File.Delete(temp);}
        revision=next;dirty=false;
        saved.Text=L["saved"];
        saved.ForeColor=muted;
        RefreshGameStatus();
        return true;
      }catch(Exception ex){
        MessageBox.Show(L["saveError"]+"\n"+ex.Message,"QoL Trainer",MessageBoxButtons.OK,MessageBoxIcon.Error);
        return false;
      }
    }
    static Dictionary<string,string> ReadIni(string path){
      var data=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
      foreach(string row in File.ReadAllLines(path)) {
        string s=row.Trim();if(s.Length==0||s[0]=='#'||s[0]==';'||s[0]=='[')continue;
        int i=s.IndexOf('=');if(i<0)continue;
        data[s.Substring(0,i).Trim()]=s.Substring(i+1).Trim();
      }
      return data;
    }
    static string Value(Dictionary<string,string> d,string key,string fallback){string v;return d.TryGetValue(key,out v)?v:fallback;}
    internal static bool HasCurrentHeartbeat(Dictionary<string,string> d,DateTime started,DateTime now){
      long heartbeat;
      if(Value(d,"Version","")!="1.2.5"||!long.TryParse(Value(d,"Heartbeat",""),out heartbeat))return false;
      DateTime at;
      try {at=new DateTime(1970,1,1,0,0,0,DateTimeKind.Utc).AddSeconds(heartbeat);}catch{return false;}
      return at>=started.AddSeconds(-2)&&(now-at).TotalSeconds>=-2&&(now-at).TotalSeconds<15;
    }
    internal static bool IsApplied(Dictionary<string,string> d,string expectedRevision){
      if(Value(d,"Status","")!="Applied"||Value(d,"Revision","")!=expectedRevision||Value(d,"NativeReady","")!="1")return false;
      foreach(string name in new[]{"Transport","Routes","Ships","Construction","CampRadius","CampHousing","Warehouse","Bridges","CampOverlap","NearestCoast","KeepRevealed","BattleProtection"})
        if(Value(d,name+"State","")!="Applied")return false;
      return true;
    }

    void ModuleStatus(Label label,Dictionary<string,string> d,string name) {
      string state=Value(d,name+"State","Waiting");
      string detail=L[state=="Applied"?"applied":state=="Error"?"error":"pending"];
      label.ForeColor=state=="Applied"?accent:warning;
      if(name=="NearestCoast"&&state=="Applied"&&Value(d,"NativeNearestCoastEnabled","0")=="1") {
        if(Value(d,"NativeAttackEligiblePoints","0")=="0"){detail=L["noCoast"];label.ForeColor=warning;}
        else detail+=" · "+Value(d,"NativeAttackEligiblePoints","0")+" / "+Value(d,"NativeAttackPoints","0");
      }
      if(Value(d,"NativeError","").Contains("UnsupportedGameBuild"))detail=L["unsupported"];
      tips.SetToolTip(label,detail);label.AccessibleName=detail;
    }
    void DisconnectedModules(){foreach(var label in states.Values){label.ForeColor=muted;tips.SetToolTip(label,L["waiting"]);label.AccessibleName=L["waiting"];}}
    void RefreshGameStatus() {
      if(status==null)return;
      try {
        Process[] games=Process.GetProcessesByName("CorsairCove").Concat(Process.GetProcessesByName("CorsairCove-Win64-Shipping")).ToArray();
        DateTime started=DateTime.MaxValue;
        try{foreach(var game in games)try{if(game.StartTime.ToUniversalTime()<started)started=game.StartTime.ToUniversalTime();}catch{}}finally{foreach(var game in games)game.Dispose();}
        if(games.Length==0){status.Text="○  "+L["closed"];status.ForeColor=muted;DisconnectedModules();if(!dirty){saved.Text=L["saved"];saved.ForeColor=muted;}return;}
        var d=File.Exists(statusPath)?ReadIni(statusPath):new Dictionary<string,string>();
        if(!HasCurrentHeartbeat(d,started,DateTime.UtcNow)){status.Text="○  "+L["waiting"];status.ForeColor=muted;DisconnectedModules();return;}
        bool applied=IsApplied(d,revision);
        status.Text="●  "+L[Value(d,"Status","")=="ConfigError"?"configError":applied?"connected":"partial"];status.ForeColor=applied?accent:warning;
        if(Value(d,"Revision","")==revision)foreach(var item in states)ModuleStatus(item.Value,d,item.Key);else DisconnectedModules();
        if(!dirty){saved.Text=L[applied?"applied":"saved"];saved.ForeColor=applied?accent:muted;}
      }catch{status.Text=L["unavailable"];status.ForeColor=muted;DisconnectedModules();}
    }
    internal void FitToArea(Size available) {
      // Query the frame metrics independently: Windows may clamp an oversized
      // window before WinForms has reconciled its cached ClientSize.
      Size frame=SizeFromClientSize(Size.Empty);
      int borderWidth=frame.Width,borderHeight=frame.Height;
      ClientSize=new Size(Math.Min(ClientSize.Width,available.Width-24-borderWidth),Math.Min(ClientSize.Height,available.Height-24-borderHeight));
      ArrangeContent();
    }
    void CaptureLayout(Control parent) {
      foreach(Control child in parent.Controls) {
        layoutItems.Add(new LayoutItem{Control=child,Bounds=child.Bounds,Font=child.Font});
        if(child is Panel)CaptureLayout(child);
      }
    }
    void ArrangeContent() {
      if(arranging||layoutItems==null||layoutItems.Count==0||WindowState==FormWindowState.Minimized)return;
      arranging=true;SuspendLayout();
      var oldFonts=new List<Font>();
      try {
        float sx=ClientSize.Width/880F,sy=ClientSize.Height/602F;
        float fontScale=(float)Math.Round(Math.Min(sx,sy)/displayScale,3);
        bool fontsChanged=Math.Abs(fontScale-lastFontScale)>0.0001F;
        var fonts=new Dictionary<string,Font>();
        if(fontsChanged){oldFonts.AddRange(layoutFonts);layoutFonts.Clear();}
        foreach(var item in layoutItems) {
          Control control=item.Control;Rectangle r=item.Bounds;
          if(fontsChanged) {
            string key=item.Font.Name+"/"+item.Font.SizeInPoints.ToString(CultureInfo.InvariantCulture)+"/"+item.Font.Style;
            Font font;
            if(!fonts.TryGetValue(key,out font)){font=new Font(item.Font.FontFamily,item.Font.SizeInPoints*fontScale,item.Font.Style);fonts[key]=font;layoutFonts.Add(font);}
            control.Font=font;
          }
          control.Bounds=new Rectangle((int)Math.Round(r.X*sx),(int)Math.Round(r.Y*sy),(int)Math.Round(r.Width*sx),(int)Math.Round(r.Height*sy));
        }
        lastFontScale=fontScale;
      }finally{ResumeLayout(false);arranging=false;foreach(var font in oldFonts)font.Dispose();}
    }
    protected override void OnClientSizeChanged(EventArgs e){base.OnClientSizeChanged(e);ArrangeContent();}
    protected override void OnLoad(EventArgs e){base.OnLoad(e);FitToArea(Screen.FromControl(this).WorkingArea.Size);}
    protected override void Dispose(bool disposing){if(disposing){if(poll!=null)poll.Dispose();tips.Dispose();}base.Dispose(disposing);if(disposing){foreach(var font in layoutFonts)font.Dispose();layoutFonts.Clear();}}
  }
}
