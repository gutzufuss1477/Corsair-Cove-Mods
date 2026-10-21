using System;
using System.IO;
using System.Globalization;
using System.Collections.Generic;
using System.Reflection;
using System.Web.Script.Serialization;

namespace CoveQoLTrainer {
  public sealed class Localization {
    public static readonly string[] Codes={"en","de","fr","it","es","pt-BR","pl","ru","ja","ko","zh-Hans","zh-Hant"};
    public static readonly string[] Names={"English","Deutsch","Français","Italiano","Español","Português (Brasil)","Polski","Русский","日本語","한국어","简体中文","繁體中文"};
    readonly Dictionary<string,string> strings;
    public readonly string Code;
    public Localization(string code) {
      Code=Normalize(code);
      using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("Languages."+Code+".json"))
      using(var reader=new StreamReader(stream))strings=new JavaScriptSerializer().Deserialize<Dictionary<string,string>>(reader.ReadToEnd());
    }
    public string this[string key] { get {return strings[key];} }
    public static string Normalize(string code) {
      string value=(code??"").Replace('_','-').ToLowerInvariant();
      switch(value) {
        case "german":return "de";case "french":return "fr";case "italian":return "it";
        case "spanish":return "es";case "brazilian":return "pt-BR";case "polish":return "pl";
        case "russian":return "ru";case "japanese":return "ja";case "koreana":return "ko";
        case "schinese":return "zh-Hans";case "tchinese":return "zh-Hant";
      }
      if(value.StartsWith("zh"))return value.Contains("hant")||value.Contains("tw")||value.Contains("hk")||value.Contains("mo")?"zh-Hant":"zh-Hans";
      if(value.StartsWith("pt"))return "pt-BR";
      foreach(string c in Codes)if(value==c.ToLowerInvariant()||value.StartsWith(c.ToLowerInvariant()+"-"))return c;
      return "en";
    }
    public static string Detect(string gameDirectory) {
      if(!string.IsNullOrEmpty(gameDirectory)) {
        DirectoryInfo dir=new DirectoryInfo(gameDirectory);
        while(dir!=null) {
          string manifest=Path.Combine(dir.FullName,"appmanifest_1368140.acf");
          if(File.Exists(manifest)) {
            var match=System.Text.RegularExpressions.Regex.Match(File.ReadAllText(manifest),"\"language\"\\s*\"([^\"]+)\"");
            if(match.Success)return Normalize(match.Groups[1].Value);
          }
          dir=dir.Parent;
        }
      }
      return Normalize(CultureInfo.CurrentUICulture.Name);
    }
  }
}
