// ScreenSaver.cs - a Windows screen saver that plays your wallpaper packs, or an animation that matches the app theme (ThemeSaver.cs).
// Build-Exe.bat builds it as Ekk0h.scr.
// Right-click the .scr and choose Install (or pick it in Screen saver settings).
// It reads the WallpaperPacks folder that sits next to it, shows a random pack (one picture per
// screen, left to right), crossfades to another pack every few seconds, and quits on any key or click.
// Plain C# 5 so the compiler that ships with Windows can build it.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;
using Microsoft.Win32;
using System.Windows.Forms;

[assembly: AssemblyTitle("Ekk0h Screen Saver")]
[assembly: AssemblyProduct("Ekk0h - Wallpaper Studio")]
[assembly: AssemblyDescription("Shows your wallpaper packs as a screen saver")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

static class SaverMain
{
    public static string Dir;

    [STAThread]
    static int Main(string[] args)
    {
        Dir = AppDomain.CurrentDomain.BaseDirectory;
        string mode = "/s";
        if (args.Length > 0)
        {
            mode = args[0].Trim().ToLowerInvariant();
            if (mode.Length > 2 && (mode.StartsWith("/") || mode.StartsWith("-"))) mode = mode.Substring(0, 2).Replace('-', '/');
        }
        if (mode == "/p") return 0;   // tiny preview box in the settings window: not drawn
        if (mode == "/c")
        {
            MessageBox.Show("This screen saver shows the packs in your WallpaperPacks folder.\n\nChange how often it switches packs, and which packs it uses, with the gear icon in Wallpaper Control Center.",
                "Ekk0h Screen Saver", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 0;
        }
        try { System.Diagnostics.Process.GetCurrentProcess().PriorityClass = System.Diagnostics.ProcessPriorityClass.AboveNormal; } catch { }
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.Run(new SaverContext());
        return 0;
    }
}

class SaverContext : ApplicationContext
{
    List<SaverForm> forms = new List<SaverForm>();
    List<string> packs = new List<string>();
    Timer next = new Timer();
    Timer fade = new Timer();
    Random rnd = new Random();
    string lastPack = "";
    float t = 1f;
    List<Bitmap> fromImgs = new List<Bitmap>();
    List<Bitmap> toImgs = new List<Bitmap>();
    Dictionary<string, object> metaD = new Dictionary<string, object>();
    bool matchMode = true;       // Match Packs: every pack uses its own saver options
    bool globalMotion = true;
    int globalSecs = 30;
    bool fromMotion, toMotion;
    string[] packVideos;
    string[] packVideoFiles;
    bool wpfOk = true;
    bool shownOnce, lastSpecial;
    Timer videoDelay;
    DateTime packStart = DateTime.Now;
    int curSecs = 30;
    Timer motion = new Timer();


    static Dictionary<string, object> ReadJson(string file)
    {
        try
        {
            if (File.Exists(file))
            {
                object o = new JavaScriptSerializer().DeserializeObject(File.ReadAllText(file));
                Dictionary<string, object> d = o as Dictionary<string, object>;
                if (d != null) return d;
            }
        }
        catch { }
        return new Dictionary<string, object>();
    }

    // does this pack match the favorites / tags picked in settings? (no picks = everything)
    static bool Matches(string packName, List<string> src, Dictionary<string, object> meta)
    {
        if (src.Count == 0) return true;
        if (src.Contains("pack:" + packName)) return true;
        object e;
        if (!meta.TryGetValue(packName, out e)) return false;
        Dictionary<string, object> d = e as Dictionary<string, object>;
        if (d == null) return false;
        object fav;
        if (src.Contains("fav") && d.TryGetValue("fav", out fav) && fav is bool && (bool)fav) return true;
        object tags;
        if (d.TryGetValue("tags", out tags) && tags is string && src.Contains("tag:" + (string)tags)) return true;
        if (d.TryGetValue("tags", out tags) && tags is System.Collections.IEnumerable && !(tags is string))
        {
            foreach (object t in (System.Collections.IEnumerable)tags)
                if (t != null && src.Contains("tag:" + t.ToString())) return true;
        }
        return false;
    }

    static string Get(Dictionary<string, object> d, string key)
    {
        object o;
        if (d.TryGetValue(key, out o) && o != null) return o.ToString();
        return "";
    }

    // Match Packs = every pack's own options; Custom = one saver for everything (packs, pictures, videos or a theme animation)
    static void ResolveSaver(Dictionary<string, object> d, out string mode, out string source, out string play)
    {
        mode = "match"; source = "packs"; play = (Get(d, "SaverVideoPlay") == "loop") ? "loop" : "cycle";
        string sm = Get(d, "SaverMode");
        if (sm.Length > 0)
        {
            if (sm == "custom") mode = "custom";
            string ss = Get(d, "SaverSource");
            if (ss.Length > 0) source = ss;
            return;
        }
        string st = Get(d, "SaverStyle");   // older settings
        if (st == "photos") { mode = "custom"; source = "packs"; }
        else if (st == "videos") { mode = "custom"; source = "videos"; }
        else if (st == "loop") { mode = "custom"; source = "videos"; play = "loop"; }
        else if (st == "theme") { mode = "custom"; source = "theme"; }
    }

    public SaverContext()
    {
        string root = Path.Combine(SaverMain.Dir, "WallpaperPacks");
        Dictionary<string, object> settings = ReadJson(Path.Combine(SaverMain.Dir, "settings.json"));
        Dictionary<string, object> meta = ReadJson(Path.Combine(SaverMain.Dir, "packmeta.json"));
        metaD = meta;
        string mode, source, play;
        ResolveSaver(settings, out mode, out source, out play);
        matchMode = (mode == "match");
        object mo;
        if (settings.TryGetValue("SaverMotion", out mo) && mo != null && mo.ToString() == "0") globalMotion = false;
        List<string> src = new List<string>();
        object srcRaw;
        if (settings.TryGetValue("ScreensaverSrc", out srcRaw) && srcRaw != null)
            foreach (string part in srcRaw.ToString().Split('|')) if (part.Trim().Length > 0) src.Add(part.Trim());
        List<string> everything = new List<string>();
        try
        {
            if (Directory.Exists(root))
                foreach (string d in Directory.GetDirectories(root))
                    if (!Path.GetFileName(d).StartsWith("_") && ListImages(d).Count > 0)
                    {
                        everything.Add(d);
                        // Match Packs uses every pack that isn't switched off in its own options; the packs menu only applies to Custom
                        if (matchMode ? !SaverExcluded(Path.GetFileName(d)) : Matches(Path.GetFileName(d), src, meta)) packs.Add(d);
                    }
        }
        catch { }
        if (matchMode)
        {
            // Match Packs plays ONLY the pack that is in use on the desktop, with that pack's own saver options
            string cur = Get(settings, "LastPack");
            string curDir = cur.Length > 0 ? Path.Combine(root, cur) : "";
            if (curDir.Length > 0 && Directory.Exists(curDir)) { packs.Clear(); packs.Add(curDir); }
        }
        if (mode == "custom" && source == "pictures")
        {
            List<string> pics = new List<string>();
            foreach (string pp in Get(settings, "SaverPics").Split('|'))
                if (pp.Trim().Length > 0 && File.Exists(pp.Trim())) pics.Add(pp.Trim());
            if (pics.Count > 0) { packs.Clear(); packs.AddRange(pics); everything.Clear(); everything.AddRange(pics); }
        }
        if (packs.Count == 0) packs.AddRange(everything);   // nothing matched the picks: fall back to all packs
        try { File.WriteAllText(Path.Combine(SaverMain.Dir, "saver-log.txt"), ""); } catch { }
        Log("mode=" + mode + " source=" + source + " play=" + play + " match=" + matchMode + " packs=" + packs.Count);
        foreach (string lp in packs)
        {
            Dictionary<string, object> lsv = PackSaver(Path.GetFileName(lp));
            Log("  " + Path.GetFileName(lp) + (lsv == null ? "  (no saved saver options)" : "  type=" + Get(lsv, "type") + " include=" + Get(lsv, "include") + " seconds=" + Get(lsv, "seconds") + " motion=" + Get(lsv, "motion")));
        }

        // videos from the Animated folder (SaverStyle 'videos' = cycle them, 'loop' = repeat the first one)
        if (mode == "custom" && source == "videos")
        {
            List<string> vids = FindVideos(settings);
            if (vids.Count > 0)
            {
                bool loop = (play == "loop");
                string html = WriteVideoPage(vids, loop, "video");
                Screen[] vs = Screen.AllScreens;
                Array.Sort(vs, delegate(Screen a, Screen b) { return a.Bounds.X.CompareTo(b.Bounds.X); });
                for (int i = 0; i < vs.Length; i++)
                {
                    SaverForm f = new SaverForm(this, vs[i].Bounds);
                    f.UseVideo(html, vids, loop);
                    forms.Add(f);
                    f.Show();
                }
                if (forms.Count > 0) forms[0].Activate();
                StartInputWatch();
                return;
            }
        }

        // "Animated, matching the theme" instead of the wallpaper packs (not for the Wallpaper theme, which has no animation of its own)
        bool themeMode = false;
        string themeFile = "splash-theme.txt";
        if (Get(settings, "SaverTheme").Length > 0)
        {
            string tf = "saver-theme-" + Get(settings, "SaverTheme").Replace(" ", "") + ".txt";
            if (File.Exists(Path.Combine(SaverMain.Dir, tf))) themeFile = tf;
        }
        if (mode == "custom" && source == "theme")
        {
            ThemeEffect probe = ThemeEffect.Create(SaverMain.Dir, new Size(100, 100), themeFile);
            if (probe != null) { themeMode = true; probe.Dispose(); }
        }

        Screen[] scr = Screen.AllScreens;
        Array.Sort(scr, delegate(Screen a, Screen b) { return a.Bounds.X.CompareTo(b.Bounds.X); });
        for (int i = 0; i < scr.Length; i++)
        {
            SaverForm f = new SaverForm(this, scr[i].Bounds);
            if (themeMode) f.UseEffect(ThemeEffect.Create(SaverMain.Dir, scr[i].Bounds.Size, themeFile));
            forms.Add(f);
            f.Show();
        }
        if (forms.Count > 0) forms[0].Activate();
        StartInputWatch();   // the picture view takes mouse and keys itself, so watch for them here
        if (themeMode) return;

        int secs = 30;
        object secRaw;
        int parsed;
        if (settings.TryGetValue("ScreensaverSeconds", out secRaw) && secRaw != null && int.TryParse(secRaw.ToString(), out parsed))
            secs = Math.Max(5, Math.Min(3600, parsed));

        globalSecs = secs;
        curSecs = secs;
        next.Interval = secs * 1000;
        next.Tick += delegate { ShowNext(); };
        motion.Interval = 33;
        motion.Tick += delegate { if (toMotion && t >= 1f) Render(); };
        motion.Start();
        fade.Interval = 30;
        fade.Tick += delegate
        {
            t += 0.06f;
            if (t >= 1f) { t = 1f; fade.Stop(); DisposeList(fromImgs); ShowPackVideos(); }
            Render();
        };
        ShowNext();
        next.Start();
    }

    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int vk);
    Timer watch;
    Point watchStart;
    DateTime watchBorn = DateTime.Now;
    static void Log(string line)
    {
        try { File.AppendAllText(Path.Combine(SaverMain.Dir, "saver-log.txt"), DateTime.Now.ToString("HH:mm:ss ") + line + "\r\n"); } catch { }
    }

    void StartInputWatch()
    {
        if (watch != null) return;
        // the embedded player takes the mouse and keyboard, so watch for input directly
        watchStart = Cursor.Position;
        watchBorn = DateTime.Now;
        watch = new Timer();
        watch.Interval = 150;
        watch.Tick += delegate
        {
            if ((DateTime.Now - watchBorn).TotalMilliseconds < 900) { watchStart = Cursor.Position; return; }
            Point p = Cursor.Position;
            if (Math.Abs(p.X - watchStart.X) > 12 || Math.Abs(p.Y - watchStart.Y) > 12) { Quit(); return; }
            for (int vk = 1; vk < 255; vk++)
                if ((GetAsyncKeyState(vk) & 0x8000) != 0) { Quit(); return; }
        };
        watch.Start();
    }

    static List<string> FindVideos(Dictionary<string, object> settings)
    {
        List<string> all = new List<string>();
        string dir = Path.Combine(SaverMain.Dir, "Animated");
        try
        {
            if (Directory.Exists(dir))
                foreach (string f in Directory.GetFiles(dir))
                {
                    string e = Path.GetExtension(f).ToLowerInvariant();
                    if (e == ".mp4" || e == ".m4v" || e == ".mov") all.Add(f);
                }
        }
        catch { }
        all.Sort(StringComparer.OrdinalIgnoreCase);
        object raw;
        List<string> picked = new List<string>();
        if (settings.TryGetValue("ScreensaverVideos", out raw) && raw != null)
            foreach (string n in raw.ToString().Split('|'))
                foreach (string f in all)
                    if (string.Equals(Path.GetFileName(f), n.Trim(), StringComparison.OrdinalIgnoreCase)) { picked.Add(f); break; }
        return picked.Count > 0 ? picked : all;
    }

    static string WriteVideoPage(List<string> vids, bool loop, string name)
    {
        try
        {
            RegistryKey k = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_BROWSER_EMULATION");
            if (k != null) { k.SetValue(Path.GetFileName(Application.ExecutablePath), 11001, RegistryValueKind.DWord); k.Close(); }
            RegistryKey g2 = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Internet Explorer\Main\FeatureControl\FEATURE_GPU_RENDERING");
            if (g2 != null) { g2.SetValue(Path.GetFileName(Application.ExecutablePath), 1, RegistryValueKind.DWord); g2.Close(); }
        }
        catch { }
        StringBuilder list = new StringBuilder();
        for (int i = 0; i < vids.Count; i++)
        {
            if (i > 0) list.Append(",");
            list.Append("'").Append(new Uri(vids[i]).AbsoluteUri.Replace("'", "%27")).Append("'");
        }
        if (loop) { list.Length = 0; list.Append("'").Append(new Uri(vids[0]).AbsoluteUri.Replace("'", "%27")).Append("'"); }
        string page = "<!-- saved from url=(0014)about:internet -->\r\n<!DOCTYPE html><html><head><meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\">"
            + "<style>html,body{margin:0;padding:0;background:#000;overflow:hidden;width:100%;height:100%}video{position:absolute;left:0;top:0}</style></head>"
            + "<body><video id=\"v\" muted autoplay></video><script>"
            + "var L=[" + list + "],i=0,LOOP=" + (loop ? "true" : "false") + ",v=document.getElementById('v');"
            + "function fit(){var W=window.innerWidth||document.documentElement.clientWidth,H=window.innerHeight||document.documentElement.clientHeight,w=v.videoWidth,h=v.videoHeight;if(!w||!h)return;var s=Math.max(W/w,H/h);v.style.width=(w*s)+'px';v.style.height=(h*s)+'px';v.style.left=((W-w*s)/2)+'px';v.style.top=((H-h*s)/2)+'px';}"
            + "function go(){v.src=L[i];v.muted=true;v.play();}"
            + "v.addEventListener('loadedmetadata',fit);window.onresize=fit;"
            + "v.addEventListener('ended',function(){if(LOOP){v.currentTime=0;v.play();}else{i=(i+1)%L.length;go();}});"
            + "v.addEventListener('error',function(){if(L.length>1){i=(i+1)%L.length;go();}});"
            + "go();</script></body></html>";
        string file = Path.Combine(Path.GetTempPath(), "Ekk0h-saver-" + name + ".html");
        File.WriteAllText(file, page, new UTF8Encoding(false));
        return file;
    }

    public void Quit()
    {
        if (watch != null) { watch.Stop(); }
        next.Stop(); fade.Stop(); motion.Stop();
        if (videoDelay != null) videoDelay.Stop();
        foreach (SaverForm f in forms) { try { f.Hide(); } catch { } }
        DisposeList(fromImgs); DisposeList(toImgs);
        foreach (SaverForm f in forms) { try { f.Dispose(); } catch { } }
        ExitThread();
    }

    static void DisposeList(List<Bitmap> l)
    {
        foreach (Bitmap b in l) { try { if (b != null) b.Dispose(); } catch { } }
        l.Clear();
    }

    static List<string> ListImages(string dir)
    {
        List<string> r = new List<string>();
        try
        {
            foreach (string f in Directory.GetFiles(dir))
            {
                string e = Path.GetExtension(f).ToLowerInvariant();
                if (e == ".jpg" || e == ".jpeg" || e == ".png" || e == ".bmp") r.Add(f);
            }
        }
        catch { }
        r.Sort(StringComparer.OrdinalIgnoreCase);
        return r;
    }

    static Bitmap LoadCopy(string path)
    {
        try
        {
            using (FileStream fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite))
            using (Image im = Image.FromStream(fs, false, false))
                return new Bitmap(im);
        }
        catch { return null; }
    }

    // draws src so it fills w x h (cropping the overflow), from the part of src given by srcPart (or all of it)
    // premultiplied 32-bit bitmaps draw much faster than 24-bit ones
    static Bitmap Fast(Bitmap b)
    {
        Bitmap n = new Bitmap(b.Width, b.Height, PixelFormat.Format32bppPArgb);
        using (Graphics g = Graphics.FromImage(n))
        {
            g.CompositingMode = CompositingMode.SourceCopy;
            g.DrawImage(b, 0, 0, b.Width, b.Height);
        }
        b.Dispose();
        return n;
    }

    static Bitmap Cover(Bitmap src, int w, int h, RectangleF part)
    {
        Bitmap o = new Bitmap(w, h, PixelFormat.Format24bppRgb);
        using (Graphics g = Graphics.FromImage(o))
        {
            g.Clear(Color.Black);
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            float sw = part.Width, sh = part.Height;
            float scale = Math.Max(w / sw, h / sh);
            float cw = w / scale, ch = h / scale;
            RectangleF s = new RectangleF(part.X + (sw - cw) / 2f, part.Y + (sh - ch) / 2f, cw, ch);
            g.DrawImage(src, new RectangleF(0, 0, w, h), s, GraphicsUnit.Pixel);
        }
        return o;
    }

    Dictionary<string, object> PackSaver(string name)
    {
        object e, sv;
        if (metaD.TryGetValue(name, out e))
        {
            Dictionary<string, object> d = e as Dictionary<string, object>;
            if (d != null && d.TryGetValue("saver", out sv)) return sv as Dictionary<string, object>;
        }
        return null;
    }

    bool SaverExcluded(string name)
    {
        Dictionary<string, object> sv = PackSaver(name);
        object inc;
        return sv != null && sv.TryGetValue("include", out inc) && inc is bool && !(bool)inc;
    }

    // a pack built from one picture cut across several screens
    static bool IsLinkedPack(string dir)
    {
        try
        {
            Dictionary<string, object> pj = ReadJson(Path.Combine(dir, "pack.json"));
            object groups;
            if (!pj.TryGetValue("groups", out groups)) return false;
            System.Collections.IEnumerable list = groups as System.Collections.IEnumerable;
            if (list == null) return false;
            foreach (object g in list)
            {
                Dictionary<string, object> gd = g as Dictionary<string, object>;
                object sc;
                if (gd == null || !gd.TryGetValue("screens", out sc)) continue;
                int c = 0;
                System.Collections.IEnumerable sl = sc as System.Collections.IEnumerable;
                if (sl != null) foreach (object o in sl) c++;
                if (c > 1) return true;
            }
        }
        catch { }
        return false;
    }

    // screens of the pack that hold a video: play it on top once the fade is done
    void ShowPackVideos()
    {
        if (packVideos == null) return;
        bool any = false;
        for (int i = 0; i < packVideos.Length && i < forms.Count; i++)
            if (packVideos[i] != null) { forms[i].ShowVideo(packVideos[i], packVideoFiles[i]); any = true; }
        packVideos = null;
        if (any && watch == null) StartInputWatch();
    }

    void Render()
    {
        float p = 1f;
        if (curSecs > 0) p = (float)Math.Max(0.0, Math.Min(1.0, (DateTime.Now - packStart).TotalSeconds / curSecs));
        foreach (SaverForm f in forms) f.Blend(fromImgs, toImgs, t, fromMotion, toMotion, p);
    }

    bool ShowSpecial(Dictionary<string, object> sv, string kind)
    {
        int secs = globalSecs, sn;
        if (int.TryParse(Get(sv, "seconds"), out sn) && sn >= 5) secs = Math.Min(3600, sn);
        if (kind == "video")
        {
            string name = Get(sv, "video");
            string vf = Path.Combine(Path.Combine(SaverMain.Dir, "Animated"), name);
            if (name.Length == 0 || !File.Exists(vf)) return false;
            string html = WriteVideoPage(new List<string>(new string[] { vf }), true, "pv");
            foreach (SaverForm f in forms) { f.ClearEffect(); f.SetWpfVisible(false); f.ShowVideo(html, vf); }
            if (watch == null) StartInputWatch();
        }
        else
        {
            string th = Get(sv, "theme");
            string file = "saver-theme-" + th.Replace(" ", "") + ".txt";
            if (th.Length == 0 || !File.Exists(Path.Combine(SaverMain.Dir, file))) return false;
            ThemeEffect pr = ThemeEffect.Create(SaverMain.Dir, new Size(100, 100), file);
            if (pr == null) return false;
            pr.Dispose();
            foreach (SaverForm f in forms) { f.HideVideo(); f.ClearEffect(); f.SetWpfVisible(false); f.UseEffect(ThemeEffect.Create(SaverMain.Dir, f.Size, file)); }
        }
        packVideos = null; toMotion = false; fade.Stop();
        shownOnce = true; lastSpecial = true;
        curSecs = secs; next.Interval = secs * 1000;
        return true;
    }

    void ShowNext()
    {
        if (packs.Count == 0 || forms.Count == 0) return;
        if (matchMode && packs.Count == 1 && shownOnce && lastSpecial) return;   // a video / theme animation keeps playing
        string pick = packs[rnd.Next(packs.Count)];
        if (packs.Count > 1) { int guard = 0; while (pick == lastPack && guard++ < 10) pick = packs[rnd.Next(packs.Count)]; }
        lastPack = pick;
        Log("showing " + Path.GetFileName(pick));

        // a pack whose own saver option is a video or a theme animation
        if (matchMode)
        {
            Dictionary<string, object> sv0 = PackSaver(Path.GetFileName(pick));
            string kind0 = sv0 != null ? Get(sv0, "type") : "";
            if ((kind0 == "video" || kind0 == "theme") && ShowSpecial(sv0, kind0)) return;
        }
        foreach (SaverForm cf in forms) { cf.ClearEffect(); cf.SetWpfVisible(true); }
        shownOnce = true; lastSpecial = false;

        List<string> files;
        if (File.Exists(pick)) { files = new List<string>(); files.Add(pick); } else files = ListImages(pick);
        List<Bitmap> srcs = new List<Bitmap>();
        foreach (string f in files) { Bitmap b = LoadCopy(f); if (b != null) srcs.Add(b); }
        if (srcs.Count == 0) return;

        List<Bitmap> made = new List<Bitmap>();
        int n = forms.Count;
        Rectangle virt = forms[0].Bounds;
        foreach (SaverForm f in forms) virt = Rectangle.Union(virt, f.Bounds);
        bool pano = srcs.Count == 1 && n > 1 && (srcs[0].Width / (float)srcs[0].Height) > 2.2f;
        // per-pack saver options (Match Packs) or the Settings values
        int packSecs = globalSecs;
        bool wantMotion = globalMotion && (pano || IsLinkedPack(pick));
        if (matchMode)
        {
            Dictionary<string, object> sv = PackSaver(Path.GetFileName(pick));
            wantMotion = pano || IsLinkedPack(pick);
            if (sv != null)
            {
                object so, mo;
                int sn;
                if (sv.TryGetValue("seconds", out so) && so != null && int.TryParse(so.ToString(), out sn) && sn >= 5) packSecs = Math.Min(3600, sn);
                if (sv.TryGetValue("motion", out mo) && mo != null)
                {
                    string m = mo.ToString().ToLowerInvariant();
                    if (m == "on") wantMotion = true; else if (m == "off") wantMotion = false;
                }
            }
        }
        const float K = 1.15f;
        for (int i = 0; i < n; i++)
        {
            Rectangle b = forms[i].Bounds;
            Bitmap src = srcs[Math.Min(i, srcs.Count - 1)];
            if (srcs.Count == 1) src = srcs[0];
            RectangleF part = new RectangleF(0, 0, src.Width, src.Height);
            if (pano)
            {
                float fx = (b.X - virt.X) / (float)virt.Width;
                float fw = b.Width / (float)virt.Width;
                part = new RectangleF(fx * src.Width, 0, fw * src.Width, src.Height);
            }
            if (wantMotion) made.Add(Fast(Cover(src, (int)(b.Width * K), (int)(b.Height * K), part)));
            else made.Add(Fast(Cover(src, b.Width, b.Height, part)));
        }
        foreach (Bitmap s in srcs) s.Dispose();

        DisposeList(fromImgs);
        fromImgs.AddRange(toImgs);
        toImgs.Clear();
        toImgs.AddRange(made);
        foreach (SaverForm vf in forms) vf.HideVideo();
        packVideos = new string[n];
        packVideoFiles = new string[n];
        for (int vi = 0; vi < n; vi++)
        {
            string mp = Path.Combine(Path.Combine(pick, "_video"), "screen" + (vi + 1) + ".mp4");
            if (File.Exists(mp)) packVideoFiles[vi] = mp;
            if (File.Exists(mp)) packVideos[vi] = WriteVideoPage(new List<string>(new string[] { mp }), true, "screen" + (vi + 1));
        }
        if (wpfOk)
        {
            try
            {
                for (int wi = 0; wi < n && wi < toImgs.Count; wi++) forms[wi].ShowWpf(toImgs[wi], wantMotion, packSecs);
                DisposeList(toImgs); DisposeList(fromImgs);
                fade.Stop(); toMotion = false; fromMotion = false;
                curSecs = packSecs; packStart = DateTime.Now;
                next.Interval = packSecs * 1000;
                if (videoDelay == null) { videoDelay = new Timer(); videoDelay.Tick += delegate { videoDelay.Stop(); ShowPackVideos(); }; }
                videoDelay.Stop(); videoDelay.Interval = 1300; videoDelay.Start();
                return;
            }
            catch { wpfOk = false; foreach (SaverForm df in forms) df.DropWpf(); }
        }
        fromMotion = toMotion;
        toMotion = wantMotion;
        curSecs = packSecs;
        packStart = DateTime.Now;
        next.Interval = packSecs * 1000;
        t = 0f;
        fade.Start();
    }
}

class WmpHost : AxHost
{
    public WmpHost() : base("6BF52A52-394A-11D3-B153-00C04F79FAA6") { }
}

class SaverForm : Form
{
    SaverContext ctx;
    Bitmap shown;
    Point start = new Point(-1, -1);
    DateTime born = DateTime.Now;

    public SaverForm(SaverContext c, Rectangle bounds)
    {
        ctx = c;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.Manual;
        Bounds = bounds;
        BackColor = Color.Black;
        ShowInTaskbar = false;
        TopMost = true;
        Cursor.Hide();
        KeyDown += delegate { ctx.Quit(); };
        MouseDown += delegate { ctx.Quit(); };
        MouseMove += delegate(object s, MouseEventArgs e)
        {
            if ((DateTime.Now - born).TotalMilliseconds < 700) return;
            if (start.X < 0) { start = Cursor.Position; return; }
            Point p = Cursor.Position;
            if (Math.Abs(p.X - start.X) > 12 || Math.Abs(p.Y - start.Y) > 12) ctx.Quit();
        };
    }

    WebBrowser web;
    WmpHost wmp;
    object wmpOcx;
    Timer wmpPoll;
    List<string> wmpFiles;
    bool wmpLoop;
    int wmpIdx;

    public void HideVideo()
    {
        if (wmpPoll != null) { try { wmpPoll.Stop(); wmpPoll.Dispose(); } catch { } wmpPoll = null; }
        if (wmp != null)
        {
            try { if (wmpOcx != null) WmpCall(wmpOcx, "close"); } catch { }
            try { Controls.Remove(wmp); wmp.Dispose(); } catch { }
            wmp = null; wmpOcx = null;
        }
        if (web != null)
        {
            try { Controls.Remove(web); web.Dispose(); } catch { }
            web = null;
        }
    }

    public void ShowVideo(string htmlFile, string file)
    {
        List<string> one = new List<string>();
        one.Add(file);
        UseVideo(htmlFile, one, true);
        if (wmp != null) wmp.BringToFront(); else if (web != null) web.BringToFront();
    }

    static object WmpGet(object o, string name) { return o.GetType().InvokeMember(name, System.Reflection.BindingFlags.GetProperty, null, o, null); }
    static void WmpSet(object o, string name, object v) { o.GetType().InvokeMember(name, System.Reflection.BindingFlags.SetProperty, null, o, new object[] { v }); }
    static void WmpCall(object o, string name, params object[] a) { o.GetType().InvokeMember(name, System.Reflection.BindingFlags.InvokeMethod, null, o, a); }

    // Windows Media Player's control plays through the graphics card, which the embedded web page can't; the web page is the fallback
    bool TryWmp(List<string> files, bool loop)
    {
        try
        {
            wmpFiles = files; wmpLoop = loop; wmpIdx = 0;
            wmp = new WmpHost();
            wmp.Dock = DockStyle.Fill;
            Controls.Add(wmp);
            wmp.CreateControl();
            wmpOcx = wmp.GetOcx();
            if (wmpOcx == null) throw new InvalidOperationException();
            WmpSet(wmpOcx, "uiMode", "none");
            WmpSet(wmpOcx, "stretchToFit", true);
            WmpSet(wmpOcx, "enableContextMenu", false);
            object st = WmpGet(wmpOcx, "settings");
            WmpSet(st, "mute", true);
            WmpSet(st, "volume", 0);
            WmpCall(st, "setMode", "loop", loop);
            WmpSet(wmpOcx, "URL", files[0]);
            wmpPoll = new Timer();
            wmpPoll.Interval = 500;
            wmpPoll.Tick += delegate
            {
                try
                {
                    int ps = Convert.ToInt32(WmpGet(wmpOcx, "playState"));
                    if (ps == 8 || ps == 1)   // media ended / stopped
                    {
                        if (!wmpLoop) wmpIdx = (wmpIdx + 1) % wmpFiles.Count;
                        WmpSet(wmpOcx, "URL", wmpFiles[wmpIdx]);
                    }
                }
                catch { }
            };
            wmpPoll.Start();
            return true;
        }
        catch
        {
            HideVideo();
            return false;
        }
    }

    public void UseVideo(string htmlFile, List<string> files, bool loop)
    {
        HideVideo();
        if (TryWmp(files, loop)) return;
        web = new WebBrowser();
        web.Dock = DockStyle.Fill;
        web.ScrollBarsEnabled = false;
        web.ScriptErrorsSuppressed = true;
        web.IsWebBrowserContextMenuEnabled = false;
        web.WebBrowserShortcutsEnabled = false;
        web.AllowWebBrowserDrop = false;
        Controls.Add(web);
        web.Navigate(new Uri(htmlFile).AbsoluteUri);
    }

    WpfView wpf;
    public void ShowWpf(Bitmap bmp, bool moving, int secs)
    {
        if (wpf == null)
        {
            wpf = new WpfView();
            wpf.Dock = DockStyle.Fill;
            Controls.Add(wpf);
            wpf.SendToBack();
        }
        wpf.Visible = true;
        wpf.ShowImage(bmp, moving, secs, Width, Height);
    }
    public void SetWpfVisible(bool v) { if (wpf != null) wpf.Visible = v; }
    public void DropWpf()
    {
        if (wpf == null) return;
        try { Controls.Remove(wpf); wpf.Dispose(); } catch { }
        wpf = null;
    }
    public void ClearEffect()
    {
        if (fxTimer != null) { fxTimer.Stop(); fxTimer.Dispose(); fxTimer = null; }
        if (fx != null) { fx.Dispose(); fx = null; Invalidate(); }
    }

    ThemeEffect fx;
    Timer fxTimer;
    public void UseEffect(ThemeEffect e)
    {
        fx = e;
        fxTimer = new Timer();
        fxTimer.Interval = 33;
        fxTimer.Tick += delegate { Invalidate(); };
        fxTimer.Start();
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            if (fxTimer != null) { fxTimer.Stop(); fxTimer.Dispose(); }
            if (fx != null) { fx.Dispose(); fx = null; }
            HideVideo();
        }
        base.Dispose(disposing);
    }

    // part of a (possibly oversized) picture to show: slow zoom-in plus a gentle drift as p goes 0 -> 1
    static RectangleF View(Bitmap bmp, bool moving, float p)
    {
        if (!moving) return new RectangleF(0, 0, bmp.Width, bmp.Height);
        float frac = (1f / 1.15f) / (1f + 0.08f * p);
        float vw = bmp.Width * frac, vh = bmp.Height * frac;
        float x = (bmp.Width - vw) * (0.25f + 0.5f * p);
        float y = (bmp.Height - vh) * (0.5f + 0.15f * (0.5f - p));
        return new RectangleF(x, y, vw, vh);
    }

    List<Bitmap> bPrev, bTo;
    float bt = 1f, bp;
    bool bpm, btm;
    public void Blend(List<Bitmap> prev, List<Bitmap> to, float t, bool prevMoving, bool toMoving, float p)
    {
        bPrev = prev; bTo = to; bt = t; bpm = prevMoving; btm = toMoving; bp = p;
        Invalidate();
    }

    int myIdx = -2;
    int ctx_index()
    {
        if (myIdx != -2) return myIdx;
        Screen[] scr = Screen.AllScreens;
        Array.Sort(scr, delegate(Screen a, Screen b) { return a.Bounds.X.CompareTo(b.Bounds.X); });
        myIdx = -1;
        for (int i = 0; i < scr.Length; i++) if (scr[i].Bounds == Bounds) { myIdx = i; break; }
        return myIdx;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (fx != null)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            try { fx.Draw(e.Graphics, (DateTime.Now - born).TotalSeconds); } catch { }
            return;
        }
        Graphics g = e.Graphics;
        g.Clear(Color.Black);
        if (bTo == null) return;
        int idx = ctx_index();
        if (idx < 0 || idx >= bTo.Count || bTo[idx] == null) return;
        g.SmoothingMode = SmoothingMode.None;
        g.CompositingQuality = CompositingQuality.HighSpeed;
        g.InterpolationMode = InterpolationMode.Bilinear;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        Rectangle dest = new Rectangle(0, 0, Width, Height);
        if (bPrev != null && idx < bPrev.Count && bPrev[idx] != null && bt < 1f)
        {
            RectangleF pv = View(bPrev[idx], bpm, 1f);
            g.DrawImage(bPrev[idx], dest, pv.X, pv.Y, pv.Width, pv.Height, GraphicsUnit.Pixel);
        }
        RectangleF tv = View(bTo[idx], btm, bp);
        if (bt >= 1f) g.DrawImage(bTo[idx], dest, tv.X, tv.Y, tv.Width, tv.Height, GraphicsUnit.Pixel);
        else
        {
            ColorMatrix cm = new ColorMatrix();
            cm.Matrix33 = Math.Max(0f, Math.Min(1f, bt));
            using (ImageAttributes ia = new ImageAttributes())
            {
                ia.SetColorMatrix(cm, ColorMatrixFlag.Default, ColorAdjustType.Bitmap);
                g.DrawImage(bTo[idx], dest, (int)tv.X, (int)tv.Y, (int)tv.Width, (int)tv.Height, GraphicsUnit.Pixel, ia);
            }
        }
    }

    protected override bool IsInputKey(Keys keyData) { return true; }
}
