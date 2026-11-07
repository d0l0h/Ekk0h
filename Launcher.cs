// Launcher.cs - turns Ekk0h.ps1 into a normal Windows program (the script is built into the exe).
// It runs the script inside this process (no powershell.exe, no console window), so the app shows up
// in Task Manager as "Ekk0h" and has its own icon.
// Build it with Build-Exe.bat (uses the C# compiler that ships with Windows; nothing to install).
using System;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Collections.Generic;
using System.Windows.Forms;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

[assembly: AssemblyTitle("Ekk0h - Wallpaper Studio")]
[assembly: AssemblyProduct("Ekk0h - Wallpaper Studio")]
[assembly: AssemblyDescription("Multi-monitor wallpaper packs, lock screens and live wallpapers")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]


// A small loading window that appears the moment the exe starts, while PowerShell warms up.
// The script tells it to go away (named event) as soon as the real window is ready.
static class Splash
{
    static Thread t;
    static volatile bool stop;
    public static bool Stopped { get { return stop; } }
    public static void Start()
    {
        try
        {
            string tf = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "splash-theme.txt");
            if (File.Exists(tf)) foreach (string ln in File.ReadAllLines(tf)) if (ln.Trim() == "nosplash=1") return;
        }
        catch { }
        try
        {
            t = new Thread(Run);
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = true;
            t.Start();
        }
        catch { }
    }
    public static void Close() { stop = true; }
    static void Run()
    {
        try { Application.Run(new SplashForm()); } catch { }
    }
}

class SplashForm : Form
{
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    static Dictionary<string, Color> pal = new Dictionary<string, Color>();
    static string fontName = "Arial Black";
    static string style = "retrowave";
    static bool light = false;
    static Color Pc(string key, int r, int g, int b)
    {
        Color c;
        if (pal.TryGetValue(key, out c)) return c;
        return Color.FromArgb(r, g, b);
    }
    static void LoadTheme()
    {
        try
        {
            string f = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "splash-theme.txt");
            if (!File.Exists(f)) return;
            foreach (string line in File.ReadAllLines(f))
            {
                int eq = line.IndexOf('=');
                if (eq < 1) continue;
                string k = line.Substring(0, eq).Trim();
                string v = line.Substring(eq + 1).Trim();
                if (k == "font") { if (v.Length > 0) fontName = v; continue; }
                if (k == "style") { style = v.ToLowerInvariant(); continue; }
                if (k == "light") { light = (v == "1"); continue; }
                string[] p = v.Split(',');
                if (p.Length == 3) pal[k] = Color.FromArgb(int.Parse(p[0]), int.Parse(p[1]), int.Parse(p[2]));
            }
        }
        catch { }
    }

    EventWaitHandle done;
    System.Windows.Forms.Timer tick = new System.Windows.Forms.Timer();
    DateTime born = DateTime.Now;
    DateTime closeAt = DateTime.MaxValue;
    Font fBig, fSub, fMono, fMonoBig, fSerif, fLight, fHack, fMid;
    StringFormat tf = StringFormat.GenericTypographic;
    // rain columns + floating bits (state for the animated themes)
    float[] colY = new float[60]; float[] colSp = new float[60]; int[] colSeed = new int[60];
    float[] px = new float[40]; float[] py = new float[40]; float[] ps = new float[40]; float[] pp = new float[40];

    // Looks like the real window (same size, same place, same title bar) so the app seems to load in place.
    public SplashForm()
    {
        LoadTheme();
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        Text = "Ekk0h - Wallpaper Studio";
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(940, 650);
        ShowInTaskbar = false;
        BackColor = Pc("bgBottom", 13, 2, 33);
        try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
        try { done = new EventWaitHandle(false, EventResetMode.ManualReset, "Local\\Ekk0h_SplashClose"); } catch { }
        fBig = MakeFont(fontName, 66f, FontStyle.Bold);
        fSub = MakeFont("Segoe UI", 17f, FontStyle.Bold);
        fMono = MakeFont("Consolas", 17f, FontStyle.Bold);
        fMonoBig = MakeFont("Consolas", 64f, FontStyle.Bold);
        fSerif = MakeFont("Georgia", 62f, FontStyle.Bold);
        fLight = MakeFont("Segoe UI Light", 60f, FontStyle.Regular);
        fHack = MakeFont("Consolas", 13f, FontStyle.Regular);
        fMid = MakeFont(fontName, 46f, FontStyle.Bold);
        Random r = new Random(7);
        for (int i = 0; i < colY.Length; i++) { colY[i] = (float)(r.NextDouble() * -650); colSp[i] = 3f + (float)r.NextDouble() * 6f; colSeed[i] = r.Next(1000); }
        for (int i = 0; i < px.Length; i++) { px[i] = (float)r.NextDouble(); py[i] = (float)r.NextDouble(); ps[i] = 0.4f + (float)r.NextDouble(); pp[i] = (float)(r.NextDouble() * 6.28); }
        tick.Interval = 30;
        tick.Tick += delegate { Step(); };
        tick.Start();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        try
        {
            int on = light ? 0 : 1;
            if (DwmSetWindowAttribute(Handle, 20, ref on, 4) != 0) DwmSetWindowAttribute(Handle, 19, ref on, 4);
            Color c = Pc("bgBottom", 13, 2, 33); Color x = Pc("text", 240, 230, 255);
            int cap = (c.B << 16) | (c.G << 8) | c.R;
            int txt = (x.B << 16) | (x.G << 8) | x.R;
            DwmSetWindowAttribute(Handle, 35, ref cap, 4);
            DwmSetWindowAttribute(Handle, 36, ref txt, 4);
        }
        catch { }
    }

    void Step()
    {
        double age = (DateTime.Now - born).TotalSeconds;
        bool finish = Splash.Stopped || age > 90 || (done != null && done.WaitOne(0));
        if (finish && closeAt == DateTime.MaxValue)
            closeAt = DateTime.Now.AddMilliseconds(age > 0.8 ? 180 : (0.8 - age) * 1000 + 180);
        if (DateTime.Now >= closeAt)
        {
            tick.Stop();
            try { if (done != null) done.Close(); } catch { }
            Close();
            return;
        }
        Invalidate();
    }

    // ------------------------------------------------------------------ small drawing helpers
    static Font MakeFont(string name, float px, FontStyle st)
    {
        try { return new Font(name, px, st, GraphicsUnit.Pixel); }
        catch { return new Font("Arial", px, st, GraphicsUnit.Pixel); }
    }
    static Color Al(Color c, int a) { if (a < 0) a = 0; if (a > 255) a = 255; return Color.FromArgb(a, c.R, c.G, c.B); }
    static void Fill(Graphics g, Color c, float x, float y, float w, float h)
    {
        using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, x, y, w, h);
    }
    static void Ln(Graphics g, Color c, float w, float x1, float y1, float x2, float y2)
    {
        using (Pen p = new Pen(c, w)) g.DrawLine(p, x1, y1, x2, y2);
    }
    static void Ell(Graphics g, Color c, float x, float y, float w, float h)
    {
        using (SolidBrush b = new SolidBrush(c)) g.FillEllipse(b, x, y, w, h);
    }
    static void Ring(Graphics g, Color c, float w, float x, float y, float d)
    {
        using (Pen p = new Pen(c, w)) g.DrawEllipse(p, x, y, d, d);
    }
    float Txt(Graphics g, string s, Font f, Color c, float x, float y)
    {
        using (SolidBrush b = new SolidBrush(c)) g.DrawString(s, f, b, x, y, tf);
        return g.MeasureString(s, f, 2000, tf).Width;
    }
    float Wid(Graphics g, string s, Font f) { return g.MeasureString(s, f, 2000, tf).Width; }
    void TxtC(Graphics g, string s, Font f, Color c, float cx, float y)
    {
        float w = Wid(g, s, f);
        Txt(g, s, f, c, cx - w / 2f, y);
    }
    // letter-spaced centered text
    void Spaced(Graphics g, string s, Font f, Color c, float cx, float y, float gap)
    {
        float total = 0; float[] w = new float[s.Length];
        for (int i = 0; i < s.Length; i++) { w[i] = (s[i] == ' ' ? f.Size * 0.4f : Wid(g, s[i].ToString(), f)) + gap; total += w[i]; }
        float x = cx - (total - gap) / 2f;
        for (int i = 0; i < s.Length; i++) { Txt(g, s[i].ToString(), f, c, x, y); x += w[i]; }
    }
    // "EKK0H" with the zero in its own color, centered
    void Title(Graphics g, Font f, Color main, Color zero, float cx, float y, float gap)
    {
        string[] parts = new string[] { "E", "K", "K", "0", "H" };
        float total = 0; float[] w = new float[5];
        for (int i = 0; i < 5; i++) { w[i] = Wid(g, parts[i], f) + gap; total += w[i]; }
        float x = cx - (total - gap) / 2f;
        for (int i = 0; i < 5; i++) { Txt(g, parts[i], f, i == 3 ? zero : main, x, y); x += w[i]; }
    }
    void Loading(Graphics g, Font f, Color c, float cx, float y, double t)
    {
        int dots = (int)((t * 1000 / 350) % 4);
        float lw = Wid(g, "Loading...", f);
        Txt(g, "Loading" + new string('.', dots), f, c, cx - lw / 2f, y);
    }
    // sweeping bar
    void Bar(Graphics g, Color c1, Color c2, Color track, float cx, float y, float w, float h, double t)
    {
        Fill(g, track, cx - w / 2f, y, w, h);
        double ph = (t * 1000 % 1400) / 1400.0;
        float segW = w * 0.34f;
        float sx = (cx - w / 2f) - segW + (float)((w + segW) * ph);
        float left = Math.Max(cx - w / 2f, sx), right = Math.Min(cx + w / 2f, sx + segW);
        if (right - left > 2)
        {
            using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(sx, y, segW, h), c1, c2, 0f))
                g.FillRectangle(lb, left, y, right - left, h);
        }
    }
    static Color Hsv(double h, double s, double v)
    {
        h = h % 360; if (h < 0) h += 360;
        double c = v * s, x = c * (1 - Math.Abs((h / 60) % 2 - 1)), m = v - c, r = 0, gg = 0, b = 0;
        if (h < 60) { r = c; gg = x; } else if (h < 120) { r = x; gg = c; } else if (h < 180) { gg = c; b = x; }
        else if (h < 240) { gg = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
        return Color.FromArgb((int)((r + m) * 255), (int)((gg + m) * 255), (int)((b + m) * 255));
    }
    // the app-icon mark: three slanted screens that fade like an echo
    void ScreensMark(Graphics g, float cx, float cy, float sc, Color edge, Color top, Color bottom)
    {
        float k = (float)Math.Tan(10 * Math.PI / 180);
        float[][] rects = new float[][] { new float[] { 96, 150, 96, 200 }, new float[] { 206, 130, 96, 240 }, new float[] { 316, 110, 96, 280 } };
        float dx = cx - 259f * sc, dy = cy - 250f * sc;
        for (int n = 0; n < 3; n++)
        {
            float[] r = rects[n];
            PointF[] p = new PointF[4];
            float[][] c = new float[][] { new float[] { r[0], r[1] }, new float[] { r[0] + r[2], r[1] }, new float[] { r[0] + r[2], r[1] + r[3] }, new float[] { r[0], r[1] + r[3] } };
            for (int i = 0; i < 4; i++) p[i] = new PointF(dx + (c[i][0] + 46 - k * c[i][1]) * sc, dy + c[i][1] * sc);
            if (n < 2)
            {
                using (Pen pen = new Pen(Al(edge, n == 0 ? 90 : 165), Math.Max(2f, 10f * sc)))
                { pen.LineJoin = LineJoin.Round; g.DrawPolygon(pen, p); }
            }
            else
            {
                RectangleF bb = new RectangleF(p[0].X - 40, p[0].Y, 200 * sc, p[3].Y - p[0].Y);
                using (LinearGradientBrush lb = new LinearGradientBrush(bb, top, bottom, 90f)) g.FillPolygon(lb, p);
            }
        }
    }
    static void Heart(Graphics g, Color c, float cx, float cy, float s)
    {
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddArc(cx - s, cy - s * 0.9f, s, s, 150, 210);
            gp.AddArc(cx, cy - s * 0.9f, s, s, 180, 210);
            gp.AddLine(cx + s * 0.93f, cy + s * 0.05f, cx, cy + s * 1.05f);
            gp.AddLine(cx, cy + s * 1.05f, cx - s * 0.93f, cy + s * 0.05f);
            gp.CloseFigure();
            using (SolidBrush b = new SolidBrush(c)) g.FillPath(b, gp);
        }
    }
    static void Star(Graphics g, Color c, float cx, float cy, float r)
    {
        PointF[] p = new PointF[10];
        for (int i = 0; i < 10; i++)
        {
            double a = -Math.PI / 2 + i * Math.PI / 5; float rr = (i % 2 == 0) ? r : r * 0.45f;
            p[i] = new PointF(cx + (float)Math.Cos(a) * rr, cy + (float)Math.Sin(a) * rr);
        }
        using (SolidBrush b = new SolidBrush(c)) g.FillPolygon(b, p);
    }
    static void VGrad(Graphics g, Color top, Color bottom, int W, int H)
    {
        using (LinearGradientBrush bg = new LinearGradientBrush(new Rectangle(0, 0, W, H), top, bottom, 90f))
            g.FillRectangle(bg, 0, 0, W, H);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
        int W = ClientSize.Width, H = ClientSize.Height;
        double t = (DateTime.Now - born).TotalMilliseconds / 1000.0;
        try
        {
            switch (style)
            {
                case "cyberpunk": SceneCyber(g, W, H, t); break;
                case "matrix": SceneMatrix(g, W, H, t); break;
                case "sleek": SceneSleek(g, W, H, t); break;
                case "glitch": SceneGlitch(g, W, H, t); break;
                case "kawaii": SceneKawaii(g, W, H, t); break;
                case "aurora": SceneAurora(g, W, H, t); break;
                case "gothic": SceneGothic(g, W, H, t); break;
                case "rgb": SceneRgb(g, W, H, t); break;
                case "blueprint": SceneBlueprint(g, W, H, t); break;
                case "galaxy": SceneGalaxy(g, W, H, t); break;
                case "shinobi": SceneShinobi(g, W, H, t); break;
                case "wallpaper": SceneWallpaper(g, W, H, t); break;
                default: SceneRetro(g, W, H, t); break;
            }
        }
        catch { }
    }

    // ------------------------------------------------------------------ RETROWAVE: sunset over a scrolling grid
    void SceneRetro(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 42, 10, 94), Pc("bgBottom", 13, 2, 33), W, H);
        float cx = W / 2f, hor = H * 0.64f;
        for (int i = 0; i < px.Length; i++)
        {
            float a = (float)(0.5 + 0.5 * Math.Sin(t * 2 * ps[i] + pp[i]));
            Ell(g, Al(Color.White, (int)(40 + 150 * a)), px[i] * W, py[i] * hor * 0.7f, 2.4f, 2.4f);
        }
        float sr = 120f;
        RectangleF sun = new RectangleF(cx - sr, hor - sr * 1.55f, sr * 2, sr * 2);
        using (LinearGradientBrush sb = new LinearGradientBrush(sun, Pc("sunTop", 255, 179, 71), Pc("sunBottom", 255, 41, 117), 90f))
            g.FillEllipse(sb, sun);
        using (GraphicsPath clip = new GraphicsPath())
        {
            clip.AddEllipse(sun);
            Region old = g.Clip; g.SetClip(clip);
            Color cut = Pc("cut", 13, 2, 33);
            float off = (float)((t * 14) % 26);
            for (int i = 0; i < 6; i++) { float y = sun.Y + sun.Height * 0.52f + i * 26 + off; Fill(g, cut, sun.X, y, sun.Width, 3 + i * 2.2f); }
            g.Clip = old;
        }
        Fill(g, Pc("bgBottom", 13, 2, 33), 0, hor, W, H - hor);
        Color ac = Pc("accent", 255, 41, 117);
        Ln(g, Al(ac, 220), 2f, 0, hor, W, hor);
        for (int i = -14; i <= 14; i++) Ln(g, Al(ac, 130), 1.3f, cx, hor, cx + i * 130f, H);
        for (int k = 0; k < 9; k++)
        {
            double f = (k + (t * 0.45) % 1.0) / 9.0;
            float y = hor + (H - hor) * (float)(f * f);
            Ln(g, Al(ac, (int)(60 + 140 * f)), 1.3f, 0, y, W, y);
        }
        Title(g, fBig, Pc("letters", 0, 240, 255), ac, cx, 46, 4);
        Spaced(g, "// WALLPAPER STUDIO", fSub, Pc("sub", 207, 198, 255), cx, 124, 5);
        Bar(g, ac, Pc("bar2", 0, 240, 255), Color.FromArgb(90, 0, 0, 0), cx, H - 62, W, 6, t);
        Loading(g, fSub, Pc("text", 240, 230, 255), cx, H - 44, t);
    }

    // ------------------------------------------------------------------ CYBERPUNK: angular frame, hazard bar, glitch flicker
    static float Flick(double t, int seed)
    {
        double v = Math.Sin(t * (9 + seed % 5) + seed * 2.1) + Math.Sin(t * 23 + seed);
        if (v > 1.55) return 0.12f;
        if (((int)(t * 3 + seed * 1.7)) % 11 == 0 && ((int)(t * 30 + seed)) % 3 == 0) return 0.2f;
        return 1f;
    }
    void NeonSign(Graphics g, string txt, Color c, float x, float y, float w, float h, double t, int seed)
    {
        float f = Flick(t, seed);
        for (int k = 3; k >= 1; k--) Fill(g, Al(c, (int)(18 * f)), x - k * 5, y - k * 5, w + k * 10, h + k * 10);
        Fill(g, Color.FromArgb(200, 8, 6, 16), x, y, w, h);
        using (Pen p = new Pen(Al(c, (int)(255 * f)), 3f)) g.DrawRectangle(p, x, y, w, h);
        float tw = Wid(g, txt, fMono);
        Txt(g, txt, fMono, Al(c, (int)(90 * f)), x + (w - tw) / 2f - 1, y + (h - 24) / 2f + 1);
        Txt(g, txt, fMono, Al(Color.White, (int)(255 * f)), x + (w - tw) / 2f, y + (h - 24) / 2f);
    }
    void SceneCyber(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 30, 26, 52), Pc("bgBottom", 7, 6, 16), W, H);
        Color yel = Pc("accent", 252, 238, 10), mag = Pc("purple", 255, 0, 110), cy = Pc("cyan", 0, 232, 255);
        float cx = W / 2f, cyy = H / 2f - 30;
        // haze glow behind the skyline
        Ell(g, Al(mag, 26), cx - 380, H - 420, 760, 320);
        // far skyline, windows flickering
        Random r = new Random(11);
        float x = -20; int bi = 0;
        while (x < W)
        {
            float bw = 46 + r.Next(70), bh = 90 + r.Next(210);
            float top = H - 120 - bh;
            Fill(g, Color.FromArgb(255, 16, 14, 32), x, top, bw, bh);
            Fill(g, Al(mag, 40), x, top, bw, 2);
            for (float wy = top + 8; wy < H - 130; wy += 12)
                for (float wx = x + 6; wx < x + bw - 8; wx += 11)
                {
                    int h2 = (int)(wx * 7 + wy * 13 + bi * 31);
                    if (h2 % 5 > 1) continue;
                    float fl = ((h2 % 7) == 0) ? Flick(t, h2 % 40) : 1f;
                    Color wc = (h2 % 3 == 0) ? cy : ((h2 % 3 == 1) ? yel : mag);
                    Fill(g, Al(wc, (int)(150 * fl)), wx, wy, 5, 6);
                }
            x += bw + 3 + r.Next(8); bi++;
        }
        // flying-car light trails across the sky lanes
        for (int i = 0; i < 6; i++)
        {
            double sp = 0.22 + (i % 3) * 0.09;
            double u = ((t * sp + i * 0.37) % 1.0);
            bool right = (i % 2 == 0);
            float lx = right ? (float)(u * (W + 300) - 150) : (float)(W + 150 - u * (W + 300));
            float ly = 70 + i * 34;
            float len = 110 + (i % 3) * 50;
            Color tc = right ? mag : cy;
            for (int k = 0; k < 6; k++)
            {
                float a0 = right ? lx - len * k / 6f : lx + len * k / 6f;
                float a1 = right ? lx - len * (k + 1) / 6f : lx + len * (k + 1) / 6f;
                Ln(g, Al(tc, 220 - k * 35), 3f, a0, ly, a1, ly);
            }
            Ell(g, Al(Color.White, 230), lx - 3, ly - 3, 6, 6);
        }
        // near buildings on both sides with a few neon signs
        Fill(g, Color.FromArgb(255, 10, 8, 20), 0, 40, 80, H - 40);
        Fill(g, Color.FromArgb(255, 10, 8, 20), W - 80, 40, 80, H - 40);
        Fill(g, Al(yel, 90), 80, 40, 3, H - 40); Fill(g, Al(cy, 90), W - 83, 40, 3, H - 40);
        NeonSign(g, "RAMEN", mag, 14, 208, 112, 40, t, 3);
        NeonSign(g, "HOTEL", cy, W - 124, 330, 108, 40, t, 8);
        NeonSign(g, "24H", yel, 18, 408, 82, 34, t, 14);
        // title panel
        PointF[] fr = new PointF[] { new PointF(130, 160), new PointF(W - 190, 160), new PointF(W - 130, 220), new PointF(W - 130, H - 190), new PointF(190, H - 190), new PointF(130, H - 250) };
        using (SolidBrush pb = new SolidBrush(Color.FromArgb(150, 6, 5, 14))) g.FillPolygon(pb, fr);
        using (Pen p = new Pen(Al(yel, 200), 3f)) g.DrawPolygon(p, fr);
        Fill(g, yel, 130, 150, 120, 8); Fill(g, mag, W - 250, H - 198, 120, 8);
        int fr2 = (int)(t * 8);
        float jit = (fr2 % 11 == 0) ? 10f : 0f;
        Matrix old = g.Transform; Matrix m = new Matrix(1, 0, -0.22f, 1, 0, 0);
        g.MultiplyTransform(m);
        Title(g, fBig, Al(mag, 210), Al(mag, 210), cx + 6 + jit + 66, cyy - 46 + 5, 6);
        Title(g, fBig, Color.White, yel, cx + jit + 66, cyy - 46, 6);
        g.Transform = old;
        Fill(g, yel, cx - 150, cyy + 50, 300, 30);
        TxtC(g, "WALLPAPER STUDIO", fMono, Color.Black, cx, cyy + 54);
        TxtC(g, "SYSTEM BOOT // LOADING", fMono, Al(cy, (int)(255 * Flick(t, 21))), cx, cyy + 110);
        // wet street with speeding tail lights and reflections
        Fill(g, Color.FromArgb(255, 6, 5, 12), 0, H - 100, W, 100);
        for (int i = 0; i < 9; i++)
        {
            double sp = 0.35 + (i % 4) * 0.12;
            double u = ((t * sp + i * 0.23) % 1.0);
            bool right = (i % 2 == 1);
            float lx = right ? (float)(u * (W + 400) - 200) : (float)(W + 200 - u * (W + 400));
            float ly = H - 84 + (i % 5) * 13;
            float len = 160 + (i % 3) * 70;
            Color tc = right ? Color.FromArgb(255, 60, 60) : Color.FromArgb(255, 245, 200);
            for (int k = 0; k < 8; k++)
            {
                float a0 = right ? lx - len * k / 8f : lx + len * k / 8f;
                float a1 = right ? lx - len * (k + 1) / 8f : lx + len * (k + 1) / 8f;
                Ln(g, Al(tc, 230 - k * 28), 4f, a0, ly, a1, ly);
                Ln(g, Al(tc, 50 - k * 6), 6f, a0, ly + 9, a1, ly + 9);
            }
        }
        // hazard bar
        float hx = 0, hy = H - 120, hw = W, hh = 16;
        Fill(g, Color.FromArgb(160, 0, 0, 0), hx, hy, hw, hh);
        double ph = (t * 1000 % 1600) / 1600.0;
        float seg = W * 0.3f, sx = hx - seg + (float)((hw + seg) * ph);
        Region old2 = g.Clip; g.SetClip(new RectangleF(hx, hy, hw, hh));
        for (int i = -2; i < (int)(seg / 16) + 4; i++)
        {
            float xx = sx + i * 16;
            if (xx + 16 < hx || xx > hx + hw || xx < sx || xx > sx + seg) continue;
            PointF[] st = new PointF[] { new PointF(xx, hy + hh), new PointF(xx + 8, hy + hh), new PointF(xx + 16, hy), new PointF(xx + 8, hy) };
            using (SolidBrush b = new SolidBrush(yel)) g.FillPolygon(b, st);
        }
        g.Clip = old2;
        // rain
        for (int i = 0; i < 70; i++)
        {
            float ry = (float)(((i * 53) % H + t * (520 + (i % 5) * 90)) % H);
            float rx = (((i * 131) % W) - ry * 0.25f + W * 2) % W;
            Ln(g, Al(cy, 45), 1f, rx, ry, rx - 4, ry + 16);
        }
        for (int y = 0; y < H; y += 4) Fill(g, Color.FromArgb(22, 0, 0, 0), 0, y, W, 1);
    }


    // ------------------------------------------------------------------ DIGITAL RAIN: falling glyphs + typed boot line
    void SceneMatrix(Graphics g, int W, int H, double t)
    {
        Fill(g, Pc("bgBottom", 0, 8, 2), 0, 0, W, H);
        Color gr = Pc("accent", 0, 255, 65);
        string chars = "0123456789ABCDEF<>/\\{}$#%&=+*";
        int cols = W / 16;
        for (int i = 0; i < cols && i < colY.Length * 1; i++)
        {
            float x = i * 16f;
            colY[i] += colSp[i];
            if (colY[i] - 20 * 16 > H) { colY[i] = (float)(-100 - (i * 37) % 300); }
            for (int j = 0; j < 20; j++)
            {
                float y = colY[i] - j * 16f;
                if (y < -16 || y > H) continue;
                int idx = (colSeed[i] + j * 7 + (int)(t * 6 + j)) % chars.Length;
                Color c = j == 0 ? Color.FromArgb(220, 255, 220) : Al(gr, 230 - j * 11);
                Txt(g, chars[idx].ToString(), fMono, c, x, y);
            }
        }
        // second set of columns using the same state, offset, to fill the width
        for (int i = 0; i < colY.Length; i++)
        {
            float x = (colY.Length + i) * 16f; if (x > W) break;
            float yy = colY[(i * 7) % colY.Length] * 0.8f + 90;
            for (int j = 0; j < 14; j++)
            {
                float y = ((yy - j * 16f) % (H + 300)); if (y < -16 || y > H) continue;
                Txt(g, chars[(colSeed[i] + j * 5 + (int)(t * 5)) % chars.Length].ToString(), fMono, Al(gr, 200 - j * 14), x, y);
            }
        }
        float cx = W / 2f, cy = H / 2f;
        Fill(g, Color.FromArgb(215, 0, 6, 1), cx - 290, cy - 130, 580, 260);
        using (Pen p = new Pen(Al(gr, 220), 2f)) g.DrawRectangle(p, cx - 290, cy - 130, 580, 260);
        string full = "EKK0H";
        int n = Math.Min(full.Length, (int)(t * 3.5));
        string shown = full.Substring(0, n);
        bool cur = ((int)(t * 2.5) % 2) == 0;
        float tw = Wid(g, full, fMonoBig);
        float x0 = cx - tw / 2f;
        Txt(g, shown, fMonoBig, Pc("letters", 180, 255, 190), x0, cy - 95);
        if (cur) Fill(g, gr, x0 + Wid(g, shown, fMonoBig) + 4, cy - 90, 26, 58);
        TxtC(g, "> WALLPAPER STUDIO", fMono, gr, cx, cy - 10);
        int blocks = (int)((t * 6) % 21);
        string bar = "[" + new string('#', blocks) + new string('-', 20 - blocks) + "]";
        TxtC(g, bar, fMono, gr, cx, cy + 30);
        TxtC(g, "loading" + new string('.', (int)((t * 3) % 4)), fMono, Al(gr, 190), cx, cy + 68);
    }

    // ------------------------------------------------------------------ SLEEK: quiet, one spinner
    void SceneSleek(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 38, 41, 48), Pc("bgBottom", 17, 18, 21), W, H);
        float cx = W / 2f, cy = H / 2f - 85;
        Color ac = Pc("accent", 64, 156, 255);
        float a0 = (float)((t * 280) % 360);
        using (Pen back = new Pen(Al(Pc("sub", 138, 144, 156), 50), 3f)) g.DrawEllipse(back, cx - 46, cy - 46, 92, 92);
        using (Pen p = new Pen(ac, 3f)) { p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; g.DrawArc(p, cx - 46, cy - 46, 92, 92, a0, 110f + (float)(60 * Math.Sin(t * 3))); }
        Ell(g, Al(ac, 255), cx - 4, cy - 4, 8, 8);
        Spaced(g, "EKK0H", fLight, Pc("text", 236, 238, 242), cx, cy + 80, 18);
        Spaced(g, "WALLPAPER STUDIO", fSub, Pc("sub", 138, 144, 156), cx, cy + 160, 7);
        float fade = (float)(0.5 + 0.5 * Math.Sin(t * 2.2));
        TxtC(g, "Loading", fSub, Al(Pc("sub", 138, 144, 156), (int)(90 + 140 * fade)), cx, H - 70);
    }

    // ------------------------------------------------------------------ GLITCH: RGB-split title, tearing bars
    void HackBoxes(Graphics g, int W, int H, double t, Color a, Color c)
    {
        string[][] pool = new string[][] {
            new string[] { "root@ekk0h:~# ./inject --desktop", "[ OK ] handshake complete", "[ OK ] unpacking wallpapers", "> ACCESS GRANTED" },
            new string[] { "SCANNING PORTS", "22 ...... CLOSED", "80 ...... OPEN", "443 ..... OPEN", "!! FIREWALL BYPASSED" },
            new string[] { "decrypt --key 0xDEADBEEF", "0x00 4E 45 4F 3A 20 57 41", "0x08 4C 4C 50 41 50 45 52", "checksum ....... OK" },
            new string[] { "sudo make me a sandwich", "user is not in the sudoers", "file. this incident will", "be reported." },
            new string[] { "UPLOADING PAYLOAD", "[##########......] 62%", "packets: 48213", "ETA 00:00:02" },
            new string[] { "!! WARNING !!", "UNAUTHORIZED ACCESS", "TRACE IN PROGRESS...", "just kidding :)" },
            new string[] { "ping 127.0.0.1", "reply: time<1ms", "reply: time<1ms", "there is no place like home" }
        };
        for (int i = 0; i < 7; i++)
        {
            double per = 3.3 + (i % 3) * 0.45;
            double tt = t + i * 0.93;
            int cyc = (int)(tt / per);
            double age = tt - cyc * per;
            Random rr = new Random(cyc * 31 + i * 7 + 5);
            string[] ln = pool[rr.Next(pool.Length)];
            float bw = 262, bh = 26 + ln.Length * 16;
            float bx = 30 + rr.Next(Math.Max(1, W - 330)), by = 24 + rr.Next(Math.Max(1, H - 190));
            double fade = age > per - 0.4 ? (per - age) / 0.4 : 1.0;
            if (fade <= 0) continue;
            bool warn = ln[0].StartsWith("!!");
            Color bc = warn ? a : (i % 2 == 0 ? c : a);
            if (age < 0.18)
            {
                // pop-in flicker: a bare outline snaps open
                float gw = bw * (float)(age / 0.18);
                using (Pen pp = new Pen(Al(bc, 200), 2f)) g.DrawRectangle(pp, bx, by, gw, bh);
                continue;
            }
            int al = (int)(255 * fade);
            Fill(g, Color.FromArgb((int)(205 * fade), 6, 4, 14), bx, by, bw, bh);
            Fill(g, Al(bc, (int)(110 * fade)), bx, by, bw, 14);
            Txt(g, "> term_" + (cyc % 90 + 10), fHack, Al(Color.White, al), bx + 4, by);
            using (Pen pp = new Pen(Al(bc, al), 1.5f)) g.DrawRectangle(pp, bx, by, bw, bh);
            int chars = (int)((age - 0.18) * 42);
            Region oc = g.Clip; g.SetClip(new RectangleF(bx, by + 14, bw, bh - 14));
            for (int k = 0; k < ln.Length && chars > 0; k++)
            {
                string sline = ln[k].Length <= chars ? ln[k] : ln[k].Substring(0, chars);
                Color tc = (ln[k].StartsWith("!!") || ln[k].StartsWith("> ACCESS")) ? a : c;
                bool cursor = chars < ln[k].Length && ((int)(age * 10) % 2 == 0);
                Txt(g, sline + (cursor ? "_" : ""), fHack, Al(tc, al), bx + 6, by + 18 + k * 16);
                chars -= ln[k].Length;
            }
            g.Clip = oc;
        }
    }
    void SceneGlitch(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 20, 10, 36), Pc("bgBottom", 8, 4, 16), W, H);
        Random r = new Random((int)(t * 14));
        Color a = Pc("accent", 255, 40, 120), c = Pc("cyan", 0, 240, 255);
        float cx = W / 2f, cy = H / 2f - 60;
        for (int i = 0; i < 26; i++) Fill(g, Al(r.Next(2) == 0 ? a : c, 12 + r.Next(30)), r.Next(W), r.Next(H), 40 + r.Next(260), 1 + r.Next(3));
        HackBoxes(g, W, H, t, a, c);
        bool burst = r.Next(5) == 0;
        float j = burst ? 16f : 4f;
        float jx = (float)(r.NextDouble() * 2 - 1) * j, jy = (float)(r.NextDouble() * 2 - 1) * j * 0.4f;
        Title(g, fBig, Al(a, 200), Al(a, 200), cx - j - 3 + jx, cy + jy, 8);
        Title(g, fBig, Al(c, 200), Al(c, 200), cx + j + 3 - jx, cy - jy, 8);
        Title(g, fBig, Color.White, Pc("zero", 255, 40, 120), cx, cy, 8);
        if (burst)
        {
            for (int i = 0; i < 4; i++)
            {
                float y = cy + r.Next(70); float h2 = 3 + r.Next(10);
                Fill(g, Al(r.Next(2) == 0 ? a : c, 150), 0, y, W, h2);
            }
        }
        if (r.Next(8) != 0) Spaced(g, "// WALLPAPER STUDIO", fSub, Pc("sub", 207, 198, 255), cx, cy + 100, 5);
        float bx = cx - 190, by = H - 120;
        for (int i = 0; i < 24; i++)
        {
            bool on = r.Next(100) < (int)(30 + 60 * ((t * 0.5) % 1.0));
            Fill(g, on ? (r.Next(3) == 0 ? c : a) : Al(Color.White, 25), bx + i * 16, by + (on ? r.Next(-3, 3) : 0), 12, 10);
        }
        TxtC(g, "LOADING" + new string('.', (int)((t * 3) % 4)), fMono, Pc("text", 240, 230, 255), cx, by + 24);
    }


    // ------------------------------------------------------------------ KAWAII: floating hearts, bouncy letters
    void SceneKawaii(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 255, 214, 235), Pc("bgBottom", 255, 240, 248), W, H);
        Color[] cs = new Color[] { Pc("accent", 255, 120, 170), Pc("cyan", 120, 220, 255), Pc("purple", 190, 150, 255), Pc("orange", 255, 190, 120), Pc("sun", 255, 225, 120) };
        float cx = W / 2f, cy = H / 2f - 20;
        // rainbow arc, each band shimmering in turn
        Color[] rb = new Color[] { Color.FromArgb(255, 120, 150), Color.FromArgb(255, 176, 110), Color.FromArgb(255, 232, 120), Color.FromArgb(140, 224, 150), Color.FromArgb(120, 200, 255), Color.FromArgb(180, 150, 255) };
        for (int k = 0; k < rb.Length; k++)
        {
            float R = 330 - k * 17 + (float)Math.Sin(t * 1.4) * 4f;
            int al = (int)(150 + 80 * Math.Sin(t * 3 - k * 0.6));
            using (Pen p = new Pen(Al(rb[k], al), 17f)) g.DrawArc(p, cx - R, 340 - R, R * 2, R * 2, 180f, 180f);
        }
        // drifting clouds
        for (int i = 0; i < 5; i++)
        {
            float span = W + 300;
            float x = (float)(((i * 0.23 + t * (0.012 + i * 0.004)) % 1.0) * span) - 150;
            float y = 60 + i * 95 + (float)Math.Sin(t * 0.7 + i) * 6;
            float s = 0.7f + (i % 3) * 0.25f;
            Color cc = Al(Color.White, 215);
            Ell(g, cc, x, y + 14 * s, 90 * s, 36 * s); Ell(g, cc, x + 22 * s, y, 54 * s, 46 * s); Ell(g, cc, x + 50 * s, y + 10 * s, 56 * s, 40 * s);
        }
        // hearts, stars and bubbles floating up, twinkling
        for (int i = 0; i < px.Length; i++)
        {
            float y = (float)(((py[i] - t * 0.05 * ps[i]) % 1.0 + 1.0) % 1.0) * (H + 60) - 30;
            float x = px[i] * W + (float)Math.Sin(t * ps[i] + pp[i]) * 24;
            Color c = Al(cs[i % cs.Length], 150);
            float sz = (9 + ps[i] * 12) * (float)(0.85 + 0.2 * Math.Sin(t * 4 + pp[i]));
            if (i % 3 == 0) Heart(g, c, x, y, sz); else if (i % 3 == 1) Star(g, c, x, y, sz); else Ell(g, c, x, y, sz, sz);
        }
        for (int i = 0; i < 14; i++)
        {
            float tw = (float)Math.Max(0, Math.Sin(t * 3 + i * 1.9));
            Star(g, Al(Color.White, (int)(230 * tw)), 40 + ((i * 197) % (W - 80)), 40 + ((i * 89) % (H - 120)), 3 + 5 * tw);
        }
        Fill(g, Al(Color.White, 165), cx - 270, cy - 140, 540, 290);
        using (Pen p = new Pen(Al(cs[0], 200), 4f)) g.DrawRectangle(p, cx - 270, cy - 140, 540, 290);
        for (int i = 0; i < 4; i++)
        {
            float bx = (i % 2 == 0) ? cx - 270 : cx + 270, by = (i < 2) ? cy - 140 : cy + 150;
            Heart(g, cs[i], bx, by, 11 + (float)Math.Sin(t * 4 + i) * 2.5f);
        }
        string[] ch = new string[] { "E", "K", "K", "0", "H" };
        float total = 0; float[] w = new float[5];
        for (int i = 0; i < 5; i++) { w[i] = Wid(g, ch[i], fBig) + 6; total += w[i]; }
        float x0 = cx - total / 2f;
        for (int i = 0; i < 5; i++)
        {
            float bob = (float)(Math.Abs(Math.Sin(t * 3 + i * 0.6)) * -16);
            Txt(g, ch[i], fBig, Al(Color.White, 190), x0 + 2, cy - 88 + bob + 3);
            Txt(g, ch[i], fBig, cs[(i * 2) % cs.Length], x0, cy - 90 + bob);
            x0 += w[i];
        }
        Spaced(g, "WALLPAPER STUDIO", fSub, Pc("text", 120, 70, 110), cx, cy + 22, 6);
        // a little cat mascot: bouncing, blinking, with blush
        float hop = (float)(Math.Abs(Math.Sin(t * 3.2)) * -14);
        float mx = cx, my = cy + 84 + hop;
        Color fur = Color.FromArgb(255, 250, 244), ink = Color.FromArgb(90, 50, 80);
        PointF[] e1 = new PointF[] { new PointF(mx - 34, my + 4), new PointF(mx - 30, my - 20), new PointF(mx - 12, my - 4) };
        PointF[] e2 = new PointF[] { new PointF(mx + 34, my + 4), new PointF(mx + 30, my - 20), new PointF(mx + 12, my - 4) };
        using (SolidBrush fb = new SolidBrush(fur)) { g.FillPolygon(fb, e1); g.FillPolygon(fb, e2); }
        PointF[] i1 = new PointF[] { new PointF(mx - 29, my - 2), new PointF(mx - 28, my - 13), new PointF(mx - 19, my - 4) };
        PointF[] i2 = new PointF[] { new PointF(mx + 29, my - 2), new PointF(mx + 28, my - 13), new PointF(mx + 19, my - 4) };
        using (SolidBrush ib = new SolidBrush(Al(cs[0], 200))) { g.FillPolygon(ib, i1); g.FillPolygon(ib, i2); }
        Ell(g, fur, mx - 38, my - 8, 76, 54);
        using (Pen op = new Pen(Al(cs[0], 160), 2f)) g.DrawEllipse(op, mx - 38, my - 8, 76, 54);
        bool blink = (t % 3.4) < 0.14;
        if (blink) { Ln(g, ink, 2.2f, mx - 20, my + 16, mx - 10, my + 16); Ln(g, ink, 2.2f, mx + 10, my + 16, mx + 20, my + 16); }
        else { Ell(g, ink, mx - 20, my + 9, 9, 12); Ell(g, ink, mx + 11, my + 9, 9, 12); Ell(g, Color.White, mx - 17, my + 11, 3, 3); Ell(g, Color.White, mx + 14, my + 11, 3, 3); }
        Ell(g, Al(cs[0], 130), mx - 32, my + 22, 14, 8); Ell(g, Al(cs[0], 130), mx + 18, my + 22, 14, 8);
        using (Pen mp = new Pen(ink, 2f)) { g.DrawArc(mp, mx - 8, my + 20, 8, 8, 0, 180); g.DrawArc(mp, mx, my + 20, 8, 8, 0, 180); }
        Heart(g, cs[0], mx - 82, my + 22 + hop * 0.3f, 10); Heart(g, cs[2], mx + 82, my + 22 + hop * 0.3f, 10);
        TxtC(g, "Loading" + new string('.', (int)((t * 2.5) % 4)), fSub, Pc("text", 120, 70, 110), cx, H - 70);
    }


    // ------------------------------------------------------------------ AURORA: flowing light ribbons
    void SceneAurora(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 10, 18, 44), Pc("bgBottom", 3, 6, 20), W, H);
        for (int i = 0; i < px.Length; i++)
            Ell(g, Al(Color.White, (int)(40 + 120 * (0.5 + 0.5 * Math.Sin(t * ps[i] + pp[i])))), px[i] * W, py[i] * H * 0.6f, 2f, 2f);
        Color[] rc = new Color[] { Pc("cyan", 0, 255, 190), Pc("accent", 90, 160, 255), Pc("purple", 170, 90, 255), Pc("ok", 120, 255, 190) };
        for (int n = 0; n < 4; n++)
        {
            PointF[] top = new PointF[41]; PointF[] bot = new PointF[41];
            for (int i = 0; i <= 40; i++)
            {
                float x = i * W / 40f;
                float y = H * 0.28f + n * 34f + (float)(Math.Sin(i * 0.28 + t * (0.7 + n * 0.2) + n) * 46 + Math.Sin(i * 0.11 - t * 0.5 + n * 2) * 30);
                top[i] = new PointF(x, y);
                bot[i] = new PointF(x, y + 170 + (float)(Math.Sin(i * 0.2 + t + n) * 30));
            }
            using (GraphicsPath gp = new GraphicsPath())
            {
                gp.AddLines(top);
                Array.Reverse(bot);
                gp.AddLines(bot);
                gp.CloseFigure();
                using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(0, H * 0.2f, W, H * 0.6f), Al(rc[n], 0), Al(rc[n], 0), 90f))
                {
                    ColorBlend cb = new ColorBlend(3);
                    cb.Colors = new Color[] { Al(rc[n], 0), Al(rc[n], 120), Al(rc[n], 0) };
                    cb.Positions = new float[] { 0f, 0.45f, 1f };
                    lb.InterpolationColors = cb;
                    g.FillPath(lb, gp);
                }
            }
        }
        float cx = W / 2f, cy = H / 2f - 20;
        for (int k = 3; k >= 1; k--) Title(g, fBig, Al(Pc("cyan", 0, 255, 190), 22), Al(Pc("cyan", 0, 255, 190), 22), cx, cy - 40 - k * 2, 4 + k * 2);
        Title(g, fBig, Color.White, Pc("cyan", 0, 255, 190), cx, cy - 40, 4);
        Spaced(g, "WALLPAPER STUDIO", fSub, Pc("sub", 190, 210, 255), cx, cy + 50, 8);
        float pr = (float)(14 + 5 * Math.Sin(t * 3));
        Ring(g, Al(Pc("cyan", 0, 255, 190), 200), 2f, cx - pr, H - 100 - pr, pr * 2);
        Ell(g, Al(Pc("cyan", 0, 255, 190), 255), cx - 4, H - 104, 8, 8);
    }

    // ------------------------------------------------------------------ GOTHIC: moon, ornate frame, embers
    static void Bat(Graphics g, float x, float y, float sc, double t, Color c)
    {
        float f = (float)Math.Sin(t * 16);
        using (SolidBrush b = new SolidBrush(c))
        {
            for (int sd = -1; sd <= 1; sd += 2)
            {
                PointF[] w = new PointF[] {
                    new PointF(x + sd * 2 * sc, y - 2 * sc), new PointF(x + sd * 13 * sc, y - 12 * sc - f * 10 * sc), new PointF(x + sd * 28 * sc, y - 6 * sc - f * 16 * sc),
                    new PointF(x + sd * 21 * sc, y + 1 * sc - f * 7 * sc), new PointF(x + sd * 15 * sc, y + 6 * sc - f * 3 * sc), new PointF(x + sd * 9 * sc, y + 1 * sc), new PointF(x + sd * 2 * sc, y + 6 * sc) };
                g.FillPolygon(b, w);
                PointF[] ear = new PointF[] { new PointF(x + sd * 1.5f * sc, y - 9 * sc), new PointF(x + sd * 3.5f * sc, y - 15 * sc), new PointF(x + sd * 5 * sc, y - 8 * sc) };
                g.FillPolygon(b, ear);
            }
            g.FillEllipse(b, x - 4 * sc, y - 9 * sc, 8 * sc, 18 * sc);
            g.FillEllipse(b, x - 4 * sc, y - 11 * sc, 8 * sc, 7 * sc);
        }
        Ell(g, Color.FromArgb(255, 80, 60), x - 2.5f * sc, y - 9 * sc, 1.6f * sc, 1.6f * sc); Ell(g, Color.FromArgb(255, 80, 60), x + 1f * sc, y - 9 * sc, 1.6f * sc, 1.6f * sc);
    }
    void Candle(Graphics g, float x, float baseY, float h, double t, int seed)
    {
        Color og = Color.FromArgb(255, 160, 60);
        float fx = x + (float)Math.Sin(t * 9 + seed) * 1.6f;
        float fh = 17f + 3.5f * (float)Math.Sin(t * 13 + seed * 3) + 2f * (float)Math.Sin(t * 29 + seed);
        float top = baseY - h;
        float gl = 0.8f + 0.2f * (float)Math.Sin(t * 11 + seed * 2);
        Ell(g, Al(og, (int)(16 * gl)), fx - 60, top - fh - 40, 120, 120);
        Ell(g, Al(og, (int)(30 * gl)), fx - 30, top - fh - 14, 60, 60);
        using (LinearGradientBrush wb = new LinearGradientBrush(new RectangleF(x - 6, top, 12, h), Color.FromArgb(245, 235, 215), Color.FromArgb(150, 130, 112), 0f)) g.FillRectangle(wb, x - 6, top, 12, h);
        Fill(g, Color.FromArgb(235, 225, 205), x - 7, top + 6 + seed % 4, 3, 12 + seed % 7);
        Ln(g, Color.FromArgb(40, 30, 30), 1.5f, x, top, x + (float)Math.Sin(t * 9 + seed) * 0.8f, top - 5);
        Ell(g, Al(og, 235), fx - 5, top - fh, 10, fh + 2);
        Ell(g, Color.FromArgb(255, 235, 150), fx - 2.6f, top - fh * 0.62f, 5.2f, fh * 0.62f);
    }
    void SceneGothic(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 34, 12, 20), Pc("bgBottom", 8, 3, 6), W, H);
        float cx = W / 2f;
        Color ac = Pc("accent", 200, 40, 60), tx = Pc("text", 235, 220, 210), dim = Pc("sub", 160, 120, 120);
        float glow = 0.85f + 0.15f * (float)Math.Sin(t * 5.3) * (float)Math.Sin(t * 2.1 + 1);
        // tall pointed-arch window with the moon showing through, candle light breathing on the glass
        float wx = cx - 100, wy = 46, ww = 200, wh = 236;
        using (GraphicsPath ar = new GraphicsPath())
        {
            ar.AddLine(wx, wy + wh, wx, wy + 90);
            ar.AddBezier(wx, wy + 90, wx, wy + 36, cx - 22, wy + 14, cx, wy);
            ar.AddBezier(cx, wy, cx + 22, wy + 14, wx + ww, wy + 36, wx + ww, wy + 90);
            ar.AddLine(wx + ww, wy + 90, wx + ww, wy + wh);
            ar.CloseFigure();
            for (int k = 4; k >= 1; k--) using (Pen gp = new Pen(Al(ac, (int)(12 * glow)), k * 7f)) g.DrawPath(gp, ar);
            g.SetClip(ar);
            using (LinearGradientBrush wb = new LinearGradientBrush(new RectangleF(wx, wy, ww, wh), Color.FromArgb(90, 14, 24), Color.FromArgb(24, 6, 10), 90f)) g.FillRectangle(wb, wx, wy, ww, wh);
            using (GraphicsPath m1 = new GraphicsPath())
            using (GraphicsPath m2 = new GraphicsPath())
            {
                m1.AddEllipse(cx - 12, wy + 40, 80, 80); m2.AddEllipse(cx + 12, wy + 28, 76, 76);
                using (Region rg = new Region(m1)) { rg.Exclude(m2); using (SolidBrush mb = new SolidBrush(Pc("sun", 235, 225, 200))) g.FillRegion(mb, rg); }
            }
            for (int ci = 0; ci < 3; ci++)
                for (int rj = 0; rj < 4; rj++)
                {
                    float fl = 0.5f + 0.5f * (float)Math.Sin(t * 2.2 + ci * 1.3 + rj * 0.9);
                    Fill(g, Al(ac, (int)((30 + 50 * fl) * glow)), wx + 4 + ci * (ww - 8) / 3f, wy + 70 + rj * 40, (ww - 8) / 3f - 3, 36);
                }
            using (Pen mp = new Pen(Al(dim, 200), 3f))
            {
                g.DrawLine(mp, cx, wy, cx, wy + wh);
                g.DrawLine(mp, wx + ww / 3f, wy + 50, wx + ww / 3f, wy + wh); g.DrawLine(mp, wx + 2 * ww / 3f, wy + 50, wx + 2 * ww / 3f, wy + wh);
                for (int rj = 0; rj < 4; rj++) g.DrawLine(mp, wx, wy + 70 + rj * 40, wx + ww, wy + 70 + rj * 40);
                g.DrawEllipse(mp, cx - 16, wy + 36, 32, 32);
            }
            g.ResetClip();
            using (Pen op = new Pen(Al(dim, 230), 5f)) g.DrawPath(op, ar);
        }
        // double frame with corner diamonds
        using (Pen p1 = new Pen(Al(dim, 200), 2f)) g.DrawRectangle(p1, 30, 30, W - 60, H - 60);
        using (Pen p2 = new Pen(Al(dim, 110), 1f)) g.DrawRectangle(p2, 42, 42, W - 84, H - 84);
        float[][] cr = new float[][] { new float[] { 30, 30 }, new float[] { W - 30, 30 }, new float[] { 30, H - 30 }, new float[] { W - 30, H - 30 } };
        foreach (float[] c in cr)
        {
            PointF[] d = new PointF[] { new PointF(c[0], c[1] - 10), new PointF(c[0] + 10, c[1]), new PointF(c[0], c[1] + 10), new PointF(c[0] - 10, c[1]) };
            using (SolidBrush b = new SolidBrush(ac)) g.FillPolygon(b, d);
        }
        // rising embers
        for (int i = 0; i < px.Length; i++)
        {
            float y = (float)(((py[i] - t * 0.06 * ps[i]) % 1.0 + 1.0) % 1.0) * H;
            float x = px[i] * W + (float)Math.Sin(t * ps[i] + pp[i]) * 14;
            Ell(g, Al(ac, (int)(40 + 110 * (1 - y / H))), x, y, 3f, 3f);
        }
        Spaced(g, "EKK0H", fSerif, tx, cx, 292, 14);
        Spaced(g, "· WALLPAPER STUDIO ·", fSub, dim, cx, 374, 9);
        // candles at both sides, flames flickering
        Fill(g, Color.FromArgb(255, 30, 22, 24), 88, H - 94, 100, 8); Fill(g, Color.FromArgb(255, 30, 22, 24), W - 188, H - 94, 100, 8);
        Candle(g, 108, H - 94, 74, t, 1); Candle(g, 138, H - 94, 104, t, 4); Candle(g, 168, H - 94, 58, t, 7);
        Candle(g, W - 168, H - 94, 62, t, 10); Candle(g, W - 138, H - 94, 98, t, 13); Candle(g, W - 108, H - 94, 70, t, 16);
        // loading line with a flame-red diamond
        float lx = cx - 170, ly = H - 150;
        Ln(g, Al(dim, 160), 1.5f, lx, ly, lx + 340, ly);
        float dxp = lx + (float)((t * 0.5) % 1.0) * 340;
        PointF[] dm = new PointF[] { new PointF(dxp, ly - 8), new PointF(dxp + 8, ly), new PointF(dxp, ly + 8), new PointF(dxp - 8, ly) };
        using (SolidBrush b = new SolidBrush(ac)) g.FillPolygon(b, dm);
        TxtC(g, "Loading" + new string('.', (int)((t * 2.5) % 4)), fSub, dim, cx, ly + 22);
        // the bat, lazily circling the window
        Bat(g, cx + 350 * (float)Math.Sin(t * 0.45), 130 + 55 * (float)Math.Sin(t * 0.9), 1.25f, t, Color.FromArgb(240, 8, 4, 8));
    }


    static float EqBar(double t, int i, int n)
    {
        double kick = Math.Pow(Math.Max(0, Math.Sin(t * 2 * Math.PI * 2.1)), 5);
        double snare = Math.Pow(Math.Max(0, Math.Sin(t * 2 * Math.PI * 1.05 + 1.2)), 8);
        double u = (double)i / n;
        double lowW = Math.Max(0, 1 - u * 2.2), midW = Math.Exp(-Math.Pow((u - 0.5) * 3, 2)), hiW = Math.Max(0, (u - 0.45) * 1.8);
        double wob = 0.5 + 0.5 * Math.Sin(t * 5.3 + i * 0.9) * Math.Cos(t * 2.7 - i * 0.37);
        double v = 0.14 + 0.22 * wob + 0.62 * (lowW * kick + midW * snare * 0.8 + hiW * (0.5 + 0.5 * Math.Sin(t * 17 + i * 2.3)) * 0.35);
        return (float)Math.Max(0.04, Math.Min(1.0, v));
    }
    void SceneRgb(Graphics g, int W, int H, double t)
    {
        t *= 0.5;   // half speed
        VGrad(g, Color.FromArgb(14, 14, 20), Color.FromArgb(5, 5, 9), W, H);
        float cx = W / 2f, cyc = 262f, r0 = 152f, maxL = 92f;
        double kk = Math.Pow(Math.Max(0, Math.Sin(t * 2 * Math.PI * 2.1)), 5);
        // ambient bloom that breathes with the beat
        for (int i = 0; i < 5; i++)
        {
            double hu = t * 70 + i * 72;
            float a = (float)(t * 0.5 + i * 1.26);
            Ell(g, Al(Hsv(hu, 1, 1), (int)(12 + 16 * kk)), cx + (float)Math.Cos(a) * 130 - 170, cyc + (float)Math.Sin(a) * 90 - 170, 340, 340);
        }
        // a shockwave ring on every beat
        double wp = (t * 2.1) % 1.0;
        using (Pen wpn = new Pen(Al(Hsv(t * 120, 1, 1), (int)(110 * (1 - wp))), 3f)) { float wr = r0 + 6 + (float)wp * 120; g.DrawEllipse(wpn, cx - wr, cyc - wr, wr * 2, wr * 2); }
        // radial equalizer: 72 bars fanning out from the circle, mirrored left/right
        int N = 72, half = N / 2;
        for (int i = 0; i < N; i++)
        {
            int idx = i < half ? i : N - 1 - i;
            float v = EqBar(t, idx, half);
            float cap = Math.Max(Math.Max(v, EqBar(t - 0.14, idx, half) - 0.04f), Math.Max(EqBar(t - 0.28, idx, half) - 0.08f, EqBar(t - 0.42, idx, half) - 0.12f));
            double ang = -Math.PI / 2 + (i + 0.5) * 2 * Math.PI / N;
            float ca = (float)Math.Cos(ang), sa = (float)Math.Sin(ang);
            Color c = Hsv(i * (360.0 / N) + t * 60, 1, 1);
            float rs = r0 + 8, re = rs + v * maxL;
            Ln(g, Al(c, 60), 9f, cx + ca * rs, cyc + sa * rs, cx + ca * re, cyc + sa * re);
            Ln(g, Al(c, 240), 5f, cx + ca * rs, cyc + sa * rs, cx + ca * re, cyc + sa * re);
            float rc = rs + cap * maxL + 7;
            Ln(g, Al(Color.White, 240), 4f, cx + ca * rc, cyc + sa * rc, cx + ca * (rc + 3), cyc + sa * (rc + 3));
        }
        // the centre disc with a glowing rim, pulsing a little on the kick
        float pr = r0 + (float)(kk * 4);
        for (int k = 4; k >= 1; k--) Ring(g, Al(Hsv(t * 120, 1, 1), 16 + (int)(20 * kk)), k * 5f, cx - pr - k, cyc - pr - k, (pr + k) * 2);
        Ell(g, Color.FromArgb(240, 9, 9, 15), cx - pr, cyc - pr, pr * 2, pr * 2);
        for (int i = 0; i < 72; i++)
        {
            double a0 = i * 5.0, aa = Math.PI * (a0 - 90) / 180;
            using (Pen rp = new Pen(Al(Hsv(i * 5 - t * 140, 1, 1), 235), 3f)) g.DrawArc(rp, cx - pr, cyc - pr, pr * 2, pr * 2, (float)(a0 - 90), 5.2f);
        }
        Title(g, fMid, Color.White, Hsv(t * 130, 1, 1), cx, cyc - 44, 4);
        Spaced(g, "WALLPAPER STUDIO", fSub, Pc("sub", 200, 200, 220), cx, cyc + 26, 5);
        // loading: a rainbow light strip with a bright runner
        float bx = cx - 260, by = H - 96;
        for (int i = 0; i < 52; i++) Fill(g, Al(Hsv(i * 7 - t * 200, 1, 1), 150), bx + i * 10, by, 8, 8);
        double ph = (t * 0.8) % 1.0;
        for (int i = 0; i < 52; i++)
        {
            double d = Math.Abs(i / 52.0 - ph); if (d > 0.5) d = 1 - d;
            if (d < 0.07) Fill(g, Al(Color.White, (int)(235 * (1 - d / 0.07))), bx + i * 10, by, 8, 8);
        }
        TxtC(g, "Loading" + new string('.', (int)((t * 3) % 4)), fSub, Pc("text", 235, 235, 240), cx, by + 24);
    }

    // ------------------------------------------------------------------ BLUEPRINT: drafting sheet that draws itself
    void SceneBlueprint(Graphics g, int W, int H, double t)
    {
        Color bgc = Pc("bgBottom", 16, 54, 110);
        Fill(g, bgc, 0, 0, W, H);
        Color ln = Pc("text", 220, 235, 255);
        for (int x = 0; x < W; x += 20) Ln(g, Al(ln, x % 100 == 0 ? 48 : 18), 1f, x, 0, x, H);
        for (int y = 0; y < H; y += 20) Ln(g, Al(ln, y % 100 == 0 ? 48 : 18), 1f, 0, y, W, y);
        float cx = W / 2f, cy = 230f;
        double prog = (t * 0.35) % 1.0;
        using (Pen p = new Pen(Al(ln, 230), 2f)) g.DrawArc(p, cx - 110, cy - 110, 220, 220, -90f, (float)(prog * 360));
        using (Pen p = new Pen(Al(ln, 110), 1f)) { g.DrawEllipse(p, cx - 128, cy - 128, 256, 256); g.DrawLine(p, cx - 150, cy, cx + 150, cy); g.DrawLine(p, cx, cy - 150, cx, cy + 150); }
        ScreensMark(g, cx, cy, 0.42f, ln, ln, ln);
        Ln(g, Al(ln, 170), 1.2f, cx - 128, cy + 150, cx + 128, cy + 150);
        Ln(g, Al(ln, 170), 1.2f, cx - 128, cy + 143, cx - 128, cy + 157);
        Ln(g, Al(ln, 170), 1.2f, cx + 128, cy + 143, cx + 128, cy + 157);
        TxtC(g, "256 PX", fMono, Al(ln, 200), cx, cy + 160);
        Txt(g, "REV 1.0", fMono, Al(ln, 190), 70, 66);
        Txt(g, "SCALE 1:1", fMono, Al(ln, 190), W - 190, 66);
        Txt(g, "DWG NO. EKK-0H", fMono, Al(ln, 190), 70, H - 80);
        TxtC(g, "EKK0H", fMonoBig, ln, cx, cy + 192);
        Ln(g, Al(ln, 200), 2f, cx - 150, cy + 262, cx + 150, cy + 262);
        TxtC(g, "WALLPAPER STUDIO", fMono, Al(ln, 220), cx, cy + 272);
        TxtC(g, "DRAWING... " + ((int)(prog * 100)).ToString() + "%", fMono, Al(ln, 220), cx, H - 70);
    }

    // ------------------------------------------------------------------ GALAXY: a UFO in the middle of the screen, planets and stars rushing past
    void Planet(Graphics g, float cx, float cy, float r, Color c, bool ring)
    {
        Color lt = Color.FromArgb(Math.Min(255, c.R + 80), Math.Min(255, c.G + 80), Math.Min(255, c.B + 80));
        Color dk = Color.FromArgb(c.R / 5, c.G / 5, c.B / 5);
        GraphicsState st = g.Save();
        g.TranslateTransform(cx, cy); g.RotateTransform(-16f);
        if (ring) using (Pen rp = new Pen(Al(lt, 120), Math.Max(2f, r * 0.09f))) g.DrawArc(rp, -r * 1.75f, -r * 0.42f, r * 3.5f, r * 0.84f, 180f, 180f);
        g.Restore(st);
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddEllipse(cx - r, cy - r, r * 2, r * 2);
            using (PathGradientBrush pg = new PathGradientBrush(gp))
            {
                pg.CenterColor = lt;
                pg.CenterPoint = new PointF(cx - r * 0.38f, cy - r * 0.38f);
                pg.SurroundColors = new Color[] { dk };
                g.FillPath(pg, gp);
            }
            g.SetClip(gp);
            for (int i = 0; i < 4; i++)
                Fill(g, Al(c, 46), cx - r, cy - r * 0.7f + i * r * 0.42f, r * 2, r * 0.13f);
            using (SolidBrush sh = new SolidBrush(Color.FromArgb(120, 0, 0, 10))) g.FillEllipse(sh, cx - r * 0.35f, cy - r * 1.1f, r * 2f, r * 2.2f);
            g.ResetClip();
        }
        if (ring)
        {
            st = g.Save();
            g.TranslateTransform(cx, cy); g.RotateTransform(-16f);
            using (Pen rp = new Pen(Al(lt, 170), Math.Max(2f, r * 0.09f))) g.DrawArc(rp, -r * 1.75f, -r * 0.42f, r * 3.5f, r * 0.84f, 0f, 180f);
            g.Restore(st);
        }
    }

    void SceneGalaxy(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 30, 20, 80), Pc("bgBottom", 6, 4, 24), W, H);
        Color ac = Pc("accent", 146, 112, 255), cy2 = Pc("cyan", 80, 222, 255), pu = Pc("purple", 255, 112, 206), sn = Pc("sun", 255, 228, 150), og = Pc("orange", 255, 176, 96);
        // stars rushing by as speed streaks (faster ones are longer and brighter)
        for (int pass = 0; pass < 2; pass++)
            for (int i = 0; i < px.Length; i++)
            {
                float spd = 300f + ps[i] * 800f * (pass == 0 ? 1f : 0.6f);
                float len = 10f + spd * 0.10f;
                float x = (float)(((px[i] * (W + 300)) - t * spd) % (W + 300));
                if (x < 0) x += W + 300;
                float y = (pass == 0 ? py[i] : pp[i] / 6.3f) * H;
                Ln(g, Al(Color.White, (int)(40 + 90 * (ps[i] - 0.3f))), 1.4f, x - 150, y, x - 150 + len, y);
            }
        // planets, sliding past at different speeds (far = slow, near = fast)
        float[][] pl = new float[][] {
            new float[] { 36f, 120f, 70f, 0.35f, 3f, 0f },
            new float[] { 56f, 520f, 120f, 0.62f, 1f, 0f },
            new float[] { 100f, 190f, 210f, 0.05f, 0f, 1f },
            new float[] { 150f, 540f, 330f, 0.78f, 2f, 1f }
        };
        Color[] pc = new Color[] { ac, cy2, pu, og };
        for (int i = 0; i < pl.Length; i++)
        {
            if (pl[i][0] >= 100f && pl[i][0] < 120f) continue;   // drawn later, in front of the UFO
            float r = pl[i][0], span = W + 4 * r;
            double pos = ((pl[i][3] * span - t * pl[i][2]) % span + span) % span;
            Planet(g, (float)pos - 2 * r, pl[i][1], r, pc[(int)pl[i][4]], pl[i][5] > 0.5f);
        }
        // the UFO, centre of the screen, rocking and bobbing, engines trailing back
        float ux = W / 2f, uy = 345f + (float)Math.Sin(t * 1.7) * 7f;
        GraphicsState st = g.Save();
        g.TranslateTransform(ux, uy); g.RotateTransform((float)(Math.Sin(t * 1.1) * 3.5));
        for (int j = 0; j < 5; j++)
        {
            float yj = (j - 2) * 11f, ln = 80f + 70f * (float)(0.5 + 0.5 * Math.Sin(t * 9 + j * 1.7));
            Ln(g, Al(cy2, 120), 3f, -135 - ln, yj, -135, yj);
            Ln(g, Al(Color.White, 150), 1.4f, -135 - ln * 0.5f, yj, -135, yj);
        }
        float fl = (float)(0.7 + 0.3 * Math.Sin(t * 14));
        Ell(g, Al(cy2, (int)(34 * fl)), -125, 14, 250, 80);
        Ell(g, Al(sn, (int)(60 * fl)), -70, 22, 140, 44);
        using (LinearGradientBrush hb = new LinearGradientBrush(new RectangleF(-130, -6, 260, 52), Color.FromArgb(214, 220, 238), Color.FromArgb(60, 66, 104), 90f)) g.FillEllipse(hb, -130, -6, 260, 52);
        using (LinearGradientBrush ub = new LinearGradientBrush(new RectangleF(-82, -30, 164, 44), Color.FromArgb(236, 240, 250), Color.FromArgb(120, 128, 166), 90f)) g.FillEllipse(ub, -82, -30, 164, 44);
        // dome with a little pilot inside
        Ell(g, Color.FromArgb(120, 230, 120), -15, -48, 30, 28);
        Ell(g, Color.FromArgb(10, 20, 10), -11, -40, 8, 12); Ell(g, Color.FromArgb(10, 20, 10), 3, -40, 8, 12);
        using (LinearGradientBrush db = new LinearGradientBrush(new RectangleF(-50, -70, 100, 70), Color.FromArgb(150, 200, 245, 255), Color.FromArgb(40, 120, 170, 230), 90f)) g.FillEllipse(db, -50, -70, 100, 78);
        Ell(g, Al(Color.White, 150), -30, -58, 22, 9);
        for (int i = 0; i < 9; i++)
        {
            double on = 0.5 + 0.5 * Math.Sin(t * 8 - i * 0.8);
            Color lc = (i % 2 == 0) ? sn : pu;
            Ell(g, Al(lc, (int)(70 + 185 * on)), -108 + i * 27f - 5, 15, 10, 10);
        }
        g.Restore(st);
        // foreground planets pass in front of the UFO
        for (int i = 0; i < pl.Length; i++)
        {
            if (!(pl[i][0] >= 100f && pl[i][0] < 120f)) continue;
            float r = pl[i][0], span = W + 4 * r;
            double pos = ((pl[i][3] * span - t * pl[i][2]) % span + span) % span;
            Planet(g, (float)pos - 2 * r, pl[i][1], r, pc[(int)pl[i][4]], pl[i][5] > 0.5f);
        }
        float cx = W / 2f;
        for (int k = 3; k >= 1; k--) Title(g, fBig, Al(ac, 20), Al(pu, 20), cx, 62 - k * 2, 4 + k * 2);
        Title(g, fBig, Color.White, pu, cx, 62, 4);
        Spaced(g, "WALLPAPER STUDIO", fSub, Pc("sub", 180, 176, 230), cx, 156, 8);
        Bar(g, ac, cy2, Al(Color.White, 24), cx, H - 90, W - 160f, 6f, t);
        Loading(g, fSub, Pc("sub", 180, 176, 230), cx, H - 70, t);
    }

    static void Kunai(Graphics g, float x, float y, float L, Color steel, Color cord)
    {
        GraphicsState st = g.Save();
        g.TranslateTransform(x, y);
        PointF[] blade = new PointF[] { new PointF(L * 0.55f, 0), new PointF(L * 0.2f, -L * 0.11f), new PointF(-L * 0.05f, -L * 0.05f), new PointF(-L * 0.05f, L * 0.05f), new PointF(L * 0.2f, L * 0.11f) };
        using (LinearGradientBrush lb = new LinearGradientBrush(new RectangleF(-L * 0.05f, -L * 0.11f, L * 0.6f, L * 0.22f), Color.FromArgb(246, 248, 252), steel, 90f)) g.FillPolygon(lb, blade);
        Ln(g, Al(Color.White, 200), 1.2f, L * 0.5f, 0, -L * 0.02f, 0);
        Fill(g, Color.FromArgb(26, 20, 26), -L * 0.42f, -L * 0.035f, L * 0.4f, L * 0.07f);
        for (int i = 0; i < 4; i++) Ln(g, cord, 2f, -L * 0.40f + i * L * 0.09f, -L * 0.035f, -L * 0.36f + i * L * 0.09f, L * 0.035f);
        using (Pen p = new Pen(steel, 2.5f)) g.DrawEllipse(p, -L * 0.58f, -L * 0.09f, L * 0.16f, L * 0.18f);
        g.Restore(st);
    }

    // ------------------------------------------------------------------ SHINOBI: moon, torii, a katana in the earth, falling blossoms
    void SceneShinobi(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 52, 16, 40), Pc("bgBottom", 12, 9, 14), W, H);
        Color red = Pc("accent", 214, 40, 66), sak = Pc("cyan", 255, 170, 198), moon = Pc("sun", 255, 238, 204);
        for (int i = 0; i < px.Length; i++) Ell(g, Al(Color.White, (int)(30 + 120 * (0.5 + 0.5 * Math.Sin(t * ps[i] + pp[i])))), px[i] * W, py[i] * H * 0.45f, 2f, 2f);
        float mx = W / 2f, my = 170f;
        g.SetClip(new RectangleF(0, 0, W, 318f));
        for (int k = 4; k >= 1; k--) Ell(g, Al(moon, 10 + k * 5 + (int)(4 * Math.Sin(t))), mx - 62 - k * 18, my - 62 - k * 18, 124 + k * 36, 124 + k * 36);
        g.ResetClip();
        Ell(g, moon, mx - 62, my - 62, 124, 124);
        Ell(g, Al(Color.FromArgb(150, 120, 110), 50), mx - 28, my - 24, 26, 26);
        Ell(g, Al(Color.FromArgb(150, 120, 110), 50), mx + 8, my + 6, 32, 32);
        float gnd = H - 150f;
        for (int L = 0; L < 2; L++)
        {
            PointF[] hp = new PointF[41];
            for (int i = 0; i <= 38; i++)
            {
                float x = i * W / 38f;
                hp[i] = new PointF(x, gnd - 20 - L * 12 - 34 * (float)(0.5 + 0.5 * Math.Sin(i * 0.5 + L * 2.2)) - 10 * (float)Math.Sin(i * 1.3 + L));
            }
            hp[39] = new PointF(W, H); hp[40] = new PointF(0, H);
            using (SolidBrush b = new SolidBrush(Color.FromArgb(L == 0 ? 36 : 18, L == 0 ? 14 : 8, L == 0 ? 30 : 16))) g.FillPolygon(b, hp);
        }
        // torii
        float top = my - 100f, fl = 330f;
        Fill(g, red, mx - 100, top + 10, 14, fl - top - 10); Fill(g, red, mx + 86, top + 10, 14, fl - top - 10);
        Fill(g, red, mx - 118, top + 54, 236, 12);
        Fill(g, Color.FromArgb(14, 8, 12), mx - 8, top + 22, 16, 32);
        using (SolidBrush b = new SolidBrush(Color.FromArgb(14, 8, 12)))
            g.FillPolygon(b, new PointF[] { new PointF(mx - 160, top - 6), new PointF(mx - 126, top + 16), new PointF(mx + 126, top + 16), new PointF(mx + 160, top - 6), new PointF(mx + 150, top - 18), new PointF(mx + 120, top), new PointF(mx - 120, top), new PointF(mx - 150, top - 18) });
        Fill(g, red, mx - 126, top + 16, 252, 8);
        Ell(g, Color.FromArgb(14, 8, 12), mx - 180, fl - 12, 360, 40);
        Ell(g, Al(sak, 16), mx - 220, fl - 18, 440, 36);
        Fill(g, Color.FromArgb(6, 3, 5), 0, gnd, W, H - gnd);
        // katana
        float kx = mx + 230, kb = gnd + 18;
        GraphicsState st = g.Save();
        g.TranslateTransform(kx, kb); g.RotateTransform(7f);
        using (LinearGradientBrush bb = new LinearGradientBrush(new RectangleF(-7, -90, 14, 92), Color.FromArgb(240, 244, 250), Color.FromArgb(120, 128, 148), 0f))
            g.FillPolygon(bb, new PointF[] { new PointF(-6, 0), new PointF(-5, -90), new PointF(5, -90), new PointF(7, 0) });
        Ln(g, Al(Color.White, 200), 1.5f, 1, -86, 1.5f, -6);
        Ell(g, Color.FromArgb(206, 168, 70), -20, -98, 40, 14);
        Fill(g, Color.FromArgb(26, 20, 26), -8, -200, 16, 106);
        for (int y = -196; y < -100; y += 14) { Ln(g, red, 2f, -8, y, 0, y + 8); Ln(g, red, 2f, 0, y + 8, 8, y); Ln(g, red, 2f, -8, y + 14, 0, y + 6); Ln(g, red, 2f, 0, y + 6, 8, y + 14); }
        Fill(g, Color.FromArgb(206, 168, 70), -10, -208, 20, 10);
        g.Restore(st);
        // blossoms
        for (int i = 0; i < 40; i++)
        {
            double per = 7 + ps[i] * 5;
            double u = (t / per + px[i]) % 1.0;
            float x = (float)(((py[i] * (W + 400)) - 400 * u) + Math.Sin(t * 1.1 + i) * 20);
            float y = (float)(-10 + u * (H + 20));
            int a = (int)(230 * Math.Min(1.0, Math.Min(u * 10, (1 - u) * 10)));
            float pw = 5f + 9f * (float)Math.Abs(Math.Cos(t * 2.4 + i));
            Ell(g, Al(sak, a), x, y, pw, 8f);
        }
        float cx = W / 2f;
        for (int k = 2; k >= 1; k--) Title(g, fBig, Al(red, 30), Al(red, 30), cx, 290 - k * 2, 4 + k * 2);
        Title(g, fBig, Color.White, red, cx, 290, 4);
        using (Font jf = MakeFont("Yu Mincho", 24f, FontStyle.Bold))
            Spaced(g, "\u58C1\u7D19\u5DE5\u623F", jf, Pc("sub", 214, 188, 196), cx, 382, 18);
        // loading "bar": a kunai flies along the bottom, lighting the track behind it
        float bx0 = 80f, bx1 = W - 80f, by = H - 90f;
        Fill(g, Al(Color.White, 22), bx0, by - 1, bx1 - bx0, 2);
        double kp = (t * 0.42) % 1.2;
        float kxp = bx0 + (bx1 - bx0) * (float)Math.Min(1.0, kp);
        Ln(g, Al(red, 210), 2f, bx0, by, kxp, by);
        for (int i = 0; i < 8; i++)
            Ln(g, Al(sak, 150 - i * 18), Math.Max(1f, 3f - i * 0.3f), kxp - 34 - i * 15, by + ((i % 2 == 0) ? -3f : 3f), kxp - 50 - i * 15, by + ((i % 2 == 0) ? -3f : 3f));
        Kunai(g, kxp, by, 50f, Color.FromArgb(150, 158, 176), red);
        Loading(g, fSub, Pc("sub", 214, 188, 196), cx, H - 70, t);
    }

    // ------------------------------------------------------------------ WALLPAPER: drifting color blobs behind a glass card
    void SceneWallpaper(Graphics g, int W, int H, double t)
    {
        VGrad(g, Pc("bgTop", 40, 40, 60), Pc("bgBottom", 14, 14, 24), W, H);
        Color[] cs = new Color[] { Pc("accent", 255, 120, 90), Pc("cyan", 90, 200, 255), Pc("purple", 160, 110, 255), Pc("orange", 255, 170, 80), Pc("sun", 255, 220, 120) };
        for (int i = 0; i < 6; i++)
        {
            float x = W * (0.2f + 0.6f * (float)(0.5 + 0.5 * Math.Sin(t * (0.25 + i * 0.07) + i * 1.7)));
            float y = H * (0.2f + 0.6f * (float)(0.5 + 0.5 * Math.Cos(t * (0.21 + i * 0.05) + i * 2.3)));
            float r = 150 + i * 22;
            using (GraphicsPath gp = new GraphicsPath())
            {
                gp.AddEllipse(x - r, y - r, r * 2, r * 2);
                using (PathGradientBrush pg = new PathGradientBrush(gp))
                {
                    pg.CenterColor = Al(cs[i % cs.Length], 150);
                    pg.SurroundColors = new Color[] { Al(cs[i % cs.Length], 0) };
                    g.FillPath(pg, gp);
                }
            }
        }
        float cx = W / 2f, cy = H / 2f - 20;
        Fill(g, Al(Color.White, 34), cx - 280, cy - 170, 560, 340);
        using (Pen p = new Pen(Al(Color.White, 90), 2f)) g.DrawRectangle(p, cx - 280, cy - 170, 560, 340);
        ScreensMark(g, cx, cy - 80, 0.3f, Color.White, Al(Color.White, 255), Al(Color.White, 190));
        Title(g, fBig, Color.White, Pc("accent", 255, 120, 90), cx, cy - 8, 6);
        Spaced(g, "WALLPAPER STUDIO", fSub, Al(Color.White, 220), cx, cy + 76, 8);
        Bar(g, Color.White, Pc("accent", 255, 120, 90), Al(Color.White, 50), cx, cy + 126, 300, 5, t);
        Loading(g, fSub, Al(Color.White, 220), cx, cy + 138, t);
    }
}

static class Program
{
    static void Log(string dir, string text)
    {
        try { File.AppendAllText(Path.Combine(dir, "run-log.txt"), DateTime.Now.ToString("s") + "  " + text + Environment.NewLine); }
        catch { }
    }

    [STAThread]
    static int Main(string[] args)
    {
        bool quiet = false;
        foreach (string a0 in args) { string n0 = a0.TrimStart('-', '/').ToLowerInvariant(); if (n0 == "tray" || n0 == "install") quiet = true; }
        if (!quiet) Splash.Start();
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(dir, "Ekk0h.ps1");
        // the script is built into this program; a copy sitting next to it (if any) wins, so an edited script loads without a rebuild
        string scriptText = null;
        try
        {
            if (File.Exists(script)) scriptText = File.ReadAllText(script, Encoding.UTF8);
            else
            {
                using (Stream rs0 = Assembly.GetExecutingAssembly().GetManifestResourceStream("Ekk0h.ps1"))
                    if (rs0 != null) using (StreamReader sr = new StreamReader(rs0, Encoding.UTF8, true)) scriptText = sr.ReadToEnd();
            }
        }
        catch { }
        if (scriptText == null)
        {
            Splash.Close();
            MessageBox.Show("This copy of Ekk0h is incomplete (the program script is missing). Please download it again.",
                "Ekk0h", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        DateTime started = DateTime.Now;
        try
        {
            InitialSessionState iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Bypass;
            using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.ApartmentState = ApartmentState.STA;
                rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
                rs.Open();
                // text run from memory has no script path of its own, so point those two at the folder / file instead
                rs.SessionStateProxy.SetVariable("EkkRoot", dir.TrimEnd('\\'));
                rs.SessionStateProxy.SetVariable("EkkScript", script);
                scriptText = scriptText.Replace("$PSScriptRoot", "$global:EkkRoot").Replace("$PSCommandPath", "$global:EkkScript");
                using (PowerShell ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript(scriptText);
                    foreach (string a in args)
                    {
                        string n = a.TrimStart('-', '/').ToLowerInvariant();
                        if (n == "tray") ps.AddParameter("Tray");
                        else if (n == "random") ps.AddParameter("Random");
                        else if (n == "install") ps.AddParameter("Install");
                    }
                    ps.Invoke();
                    Splash.Close();
                    if (ps.Streams.Error.Count > 0)
                    {
                        StringBuilder sb = new StringBuilder();
                        foreach (ErrorRecord er in ps.Streams.Error) sb.AppendLine(er.ToString());
                        Log(dir, "script errors: " + sb.ToString());
                        // if the app ended almost at once, it never really started: say so instead of vanishing
                        if ((DateTime.Now - started).TotalSeconds < 8)
                        {
                            string first = ps.Streams.Error[0].ToString();
                            if (first.Length > 500) first = first.Substring(0, 500) + "...";
                            if (MessageBox.Show("The control center closed right after starting.\n\n" + first + "\n\nDetails were written to run-log.txt.\n\nOpen the log file now?",
                                "Ekk0h", MessageBoxButtons.YesNo, MessageBoxIcon.Error) == DialogResult.Yes)
                            {
                                try { System.Diagnostics.Process.Start("notepad.exe", "\"" + Path.Combine(dir, "run-log.txt") + "\""); } catch { }
                            }
                        }
                    }
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            Exception inner = ex;
            while (inner.InnerException != null) inner = inner.InnerException;
            Log(dir, "failed to start: " + inner.ToString());
            Splash.Close();
            if (MessageBox.Show("The control center couldn't start.\n\n" + inner.Message + "\n\nDetails were written to run-log.txt.\n\nOpen the log file now?",
                "Ekk0h", MessageBoxButtons.YesNo, MessageBoxIcon.Error) == DialogResult.Yes)
            {
                try { System.Diagnostics.Process.Start("notepad.exe", "\"" + Path.Combine(dir, "run-log.txt") + "\""); } catch { }
            }
            return 1;
        }
    }
}
