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
using System.Web.Script.Serialization;
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

    public SaverContext()
    {
        string root = Path.Combine(SaverMain.Dir, "WallpaperPacks");
        Dictionary<string, object> settings = ReadJson(Path.Combine(SaverMain.Dir, "settings.json"));
        Dictionary<string, object> meta = ReadJson(Path.Combine(SaverMain.Dir, "packmeta.json"));
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
                        if (Matches(Path.GetFileName(d), src, meta)) packs.Add(d);
                    }
        }
        catch { }
        if (packs.Count == 0) packs.AddRange(everything);   // nothing matched the picks: fall back to all packs

        // "Animated, matching the theme" instead of the wallpaper packs (not for the Wallpaper theme, which has no animation of its own)
        bool themeMode = false;
        object styleRaw;
        if (settings.TryGetValue("SaverStyle", out styleRaw) && styleRaw != null && styleRaw.ToString() == "theme")
        {
            ThemeEffect probe = ThemeEffect.Create(SaverMain.Dir, new Size(100, 100));
            if (probe != null) { themeMode = true; probe.Dispose(); }
        }

        Screen[] scr = Screen.AllScreens;
        Array.Sort(scr, delegate(Screen a, Screen b) { return a.Bounds.X.CompareTo(b.Bounds.X); });
        for (int i = 0; i < scr.Length; i++)
        {
            SaverForm f = new SaverForm(this, scr[i].Bounds);
            if (themeMode) f.UseEffect(ThemeEffect.Create(SaverMain.Dir, scr[i].Bounds.Size));
            forms.Add(f);
            f.Show();
        }
        if (forms.Count > 0) forms[0].Activate();
        if (themeMode) return;

        int secs = 30;
        object secRaw;
        int parsed;
        if (settings.TryGetValue("ScreensaverSeconds", out secRaw) && secRaw != null && int.TryParse(secRaw.ToString(), out parsed))
            secs = Math.Max(5, Math.Min(3600, parsed));

        next.Interval = secs * 1000;
        next.Tick += delegate { ShowNext(); };
        fade.Interval = 30;
        fade.Tick += delegate
        {
            t += 0.06f;
            if (t >= 1f) { t = 1f; fade.Stop(); DisposeList(fromImgs); }
            foreach (SaverForm f in forms) f.Blend(fromImgs, toImgs, t);
        };
        ShowNext();
        next.Start();
    }

    public void Quit()
    {
        next.Stop(); fade.Stop();
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

    void ShowNext()
    {
        if (packs.Count == 0 || forms.Count == 0) return;
        string pick = packs[rnd.Next(packs.Count)];
        if (packs.Count > 1) { int guard = 0; while (pick == lastPack && guard++ < 10) pick = packs[rnd.Next(packs.Count)]; }
        lastPack = pick;

        List<string> files = ListImages(pick);
        List<Bitmap> srcs = new List<Bitmap>();
        foreach (string f in files) { Bitmap b = LoadCopy(f); if (b != null) srcs.Add(b); }
        if (srcs.Count == 0) return;

        List<Bitmap> made = new List<Bitmap>();
        int n = forms.Count;
        Rectangle virt = forms[0].Bounds;
        foreach (SaverForm f in forms) virt = Rectangle.Union(virt, f.Bounds);
        bool pano = srcs.Count == 1 && n > 1 && (srcs[0].Width / (float)srcs[0].Height) > 2.2f;
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
            made.Add(Cover(src, b.Width, b.Height, part));
        }
        foreach (Bitmap s in srcs) s.Dispose();

        DisposeList(fromImgs);
        fromImgs.AddRange(toImgs);
        toImgs.Clear();
        toImgs.AddRange(made);
        t = 0f;
        fade.Start();
    }
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
        }
        base.Dispose(disposing);
    }

    public void Blend(List<Bitmap> prev, List<Bitmap> to, float t)
    {
        int idx = ctx_index();
        if (idx < 0 || idx >= to.Count) return;
        Bitmap b = new Bitmap(Width, Height, PixelFormat.Format24bppRgb);
        using (Graphics g = Graphics.FromImage(b))
        {
            g.Clear(Color.Black);
            if (idx < prev.Count && prev[idx] != null && t < 1f) g.DrawImage(prev[idx], 0, 0, Width, Height);
            ColorMatrix cm = new ColorMatrix();
            cm.Matrix33 = Math.Max(0f, Math.Min(1f, t));
            using (ImageAttributes ia = new ImageAttributes())
            {
                ia.SetColorMatrix(cm, ColorMatrixFlag.Default, ColorAdjustType.Bitmap);
                g.DrawImage(to[idx], new Rectangle(0, 0, Width, Height), 0, 0, to[idx].Width, to[idx].Height, GraphicsUnit.Pixel, ia);
            }
        }
        Bitmap old = shown;
        shown = b;
        Invalidate();
        if (old != null) old.Dispose();
    }

    int ctx_index()
    {
        Screen[] scr = Screen.AllScreens;
        Array.Sort(scr, delegate(Screen a, Screen b) { return a.Bounds.X.CompareTo(b.Bounds.X); });
        for (int i = 0; i < scr.Length; i++) if (scr[i].Bounds == Bounds) return i;
        return -1;
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        if (fx != null)
        {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            try { fx.Draw(e.Graphics, (DateTime.Now - born).TotalSeconds); } catch { }
            return;
        }
        e.Graphics.Clear(Color.Black);
        if (shown != null) e.Graphics.DrawImage(shown, 0, 0, Width, Height);
    }

    protected override bool IsInputKey(Keys keyData) { return true; }
}
