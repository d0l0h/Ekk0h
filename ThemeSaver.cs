// ThemeSaver.cs - animated screen savers that follow the app theme (starfield, mystify, rain, pipes, ribbons ...).
// Compiled together with ScreenSaver.cs. The colors come from splash-theme.txt, which the app rewrites whenever
// the theme changes, so the screen saver always matches the last theme picked.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;

abstract class ThemeEffect
{
    public int W, H;
    protected Dictionary<string, Color> pal = new Dictionary<string, Color>();
    protected string fontName = "Segoe UI";
    protected Random R = new Random();
    double last = -1;

    protected Color Pc(string key, int r, int g, int b) { Color c; if (pal.TryGetValue(key, out c)) return c; return Color.FromArgb(r, g, b); }
    protected static Color Al(Color c, int a) { if (a < 0) a = 0; if (a > 255) a = 255; return Color.FromArgb(a, c.R, c.G, c.B); }
    protected static Color Mix(Color a, Color b, double u)
    {
        if (u < 0) u = 0; if (u > 1) u = 1;
        return Color.FromArgb((int)(a.R + (b.R - a.R) * u), (int)(a.G + (b.G - a.G) * u), (int)(a.B + (b.B - a.B) * u));
    }
    protected static Color Hsv(double h, double s, double v)
    {
        h = h % 360; if (h < 0) h += 360;
        double c = v * s, x = c * (1 - Math.Abs((h / 60) % 2 - 1)), m = v - c, r = 0, g = 0, b = 0;
        if (h < 60) { r = c; g = x; } else if (h < 120) { r = x; g = c; } else if (h < 180) { g = c; b = x; }
        else if (h < 240) { g = x; b = c; } else if (h < 300) { r = x; b = c; } else { r = c; b = x; }
        return Color.FromArgb((int)((r + m) * 255), (int)((g + m) * 255), (int)((b + m) * 255));
    }
    protected void Back(Graphics g, Color top, Color bottom)
    {
        using (LinearGradientBrush b = new LinearGradientBrush(new Rectangle(0, 0, W, H + 1), top, bottom, 90f)) g.FillRectangle(b, 0, 0, W, H + 1);
    }
    protected static void Fill(Graphics g, Color c, float x, float y, float w, float h) { using (SolidBrush b = new SolidBrush(c)) g.FillRectangle(b, x, y, w, h); }
    protected static void Ell(Graphics g, Color c, float x, float y, float w, float h) { using (SolidBrush b = new SolidBrush(c)) g.FillEllipse(b, x, y, w, h); }

    public virtual void Init() { }
    public virtual void Dispose() { }
    protected abstract void Frame(Graphics g, double t, double dt);
    public void Draw(Graphics g, double t)
    {
        double dt = last < 0 ? 0.033 : Math.Min(0.1, t - last);
        last = t;
        Frame(g, t, dt);
    }

    static void LoadPalette(ThemeEffect e, string dir, out string style)
    {
        style = "";
        try
        {
            string f = Path.Combine(dir, "splash-theme.txt");
            if (!File.Exists(f)) return;
            foreach (string line in File.ReadAllLines(f))
            {
                int eq = line.IndexOf('=');
                if (eq < 1) continue;
                string k = line.Substring(0, eq).Trim(), v = line.Substring(eq + 1).Trim();
                if (k == "font") { if (v.Length > 0) e.fontName = v; continue; }
                if (k == "style") { style = v.ToLowerInvariant(); continue; }
                string[] p = v.Split(',');
                int a, b, c;
                if (p.Length == 3 && int.TryParse(p[0], out a) && int.TryParse(p[1], out b) && int.TryParse(p[2], out c)) e.pal[k] = Color.FromArgb(a, b, c);
            }
        }
        catch { }
    }

    // null = this theme has no animation of its own (the Wallpaper theme): use the wallpaper packs instead
    public static ThemeEffect Create(string dir, Size size)
    {
        ThemeEffect probe = new Starfield();
        string style;
        LoadPalette(probe, dir, out style);
        ThemeEffect e;
        switch (style)
        {
            case "wallpaper": return null;
            case "sleek": e = new Mystify(false); break;
            case "blueprint": e = new Draft(); break;
            case "matrix": e = new Rain(); break;
            case "retrowave": e = new Retro(); break;
            case "cyberpunk": e = new Pipes(); break;
            case "glitch": e = new Bounce(); break;
            case "kawaii": e = new Bubbles(); break;
            case "aurora": e = new Ribbons(); break;
            case "gothic": e = new Bats(); break;
            case "rgb": e = new Equalizer(); break;
            case "shinobi": e = new Blossoms(); break;
            default: e = new Starfield(); break;
        }
        e.pal = probe.pal; e.fontName = probe.fontName;
        e.W = Math.Max(1, size.Width); e.H = Math.Max(1, size.Height);
        e.Init();
        return e;
    }
}

// ---- Galaxy: flying through a starfield
class Starfield : ThemeEffect
{
    float[] sx, sy, sz; int N = 520; Pen pen = new Pen(Color.White, 1f);
    public override void Init()
    {
        sx = new float[N]; sy = new float[N]; sz = new float[N];
        for (int i = 0; i < N; i++) { Reset(i); sz[i] = (float)R.NextDouble(); }
    }
    void Reset(int i) { sx[i] = (float)(R.NextDouble() * 2 - 1); sy[i] = (float)(R.NextDouble() * 2 - 1); sz[i] = 1f; }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Back(g, Pc("bgTop", 20, 14, 60), Pc("bgBottom", 4, 3, 16));
        Color a = Pc("accent", 146, 112, 255), c = Pc("cyan", 80, 222, 255), p = Pc("purple", 255, 112, 206);
        for (int k = 0; k < 3; k++)
        {
            float nx = (float)(W * (0.25 + 0.25 * k) + Math.Sin(t * 0.05 + k * 2) * W * 0.1), ny = (float)(H * (0.35 + 0.15 * k) + Math.Cos(t * 0.04 + k) * H * 0.1);
            Ell(g, Al(k == 0 ? a : (k == 1 ? p : c), 14), nx - W * 0.28f, ny - H * 0.28f, W * 0.56f, H * 0.56f);
        }
        float f = W * 0.5f, cx = W / 2f, cy = H / 2f, speed = 0.32f;
        for (int i = 0; i < N; i++)
        {
            float oz = sz[i];
            sz[i] -= (float)dt * speed;
            if (sz[i] <= 0.02f) { Reset(i); continue; }
            float px = cx + sx[i] / sz[i] * f * 0.5f, py = cy + sy[i] / sz[i] * f * 0.5f * (H / (float)W) * 1.6f;
            float qz = sz[i] + (float)dt * speed * 1.6f;
            float ox = cx + sx[i] / qz * f * 0.5f, oy = cy + sy[i] / qz * f * 0.5f * (H / (float)W) * 1.6f;
            if (px < -50 || px > W + 50 || py < -50 || py > H + 50) { Reset(i); continue; }
            float br = 1f - sz[i];
            pen.Color = Al(i % 3 == 0 ? c : (i % 3 == 1 ? Color.White : p), (int)(50 + 200 * br));
            pen.Width = 0.7f + 2.6f * br;
            g.DrawLine(pen, ox, oy, px, py);
        }
    }
    public override void Dispose() { pen.Dispose(); }
}

// ---- Sleek / Blueprint: the old "Mystify" bouncing polygons with fading trails
class Mystify : ThemeEffect
{
    bool grid; PointF[][] pts = new PointF[2][]; PointF[][] vel = new PointF[2][];
    List<PointF[]>[] hist = new List<PointF[]>[2]; double acc = 0; Pen pen = new Pen(Color.White, 2f);
    public Mystify(bool withGrid) { grid = withGrid; }
    public override void Init()
    {
        for (int k = 0; k < 2; k++)
        {
            pts[k] = new PointF[4]; vel[k] = new PointF[4]; hist[k] = new List<PointF[]>();
            for (int i = 0; i < 4; i++)
            {
                pts[k][i] = new PointF(R.Next(W), R.Next(H));
                double an = R.NextDouble() * Math.PI * 2; float sp = 160 + R.Next(160);
                vel[k][i] = new PointF((float)Math.Cos(an) * sp, (float)Math.Sin(an) * sp);
            }
        }
    }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Back(g, Pc("bgBottom", 8, 8, 18), Pc("bgBottom", 4, 4, 10));
        if (grid)
        {
            Color gc = Al(Pc("cyan", 80, 180, 255), 22);
            using (Pen gp = new Pen(gc, 1f))
            {
                for (int x = 0; x < W; x += 40) g.DrawLine(gp, x, 0, x, H);
                for (int y = 0; y < H; y += 40) g.DrawLine(gp, 0, y, W, y);
            }
        }
        for (int k = 0; k < 2; k++)
            for (int i = 0; i < 4; i++)
            {
                pts[k][i].X += vel[k][i].X * (float)dt; pts[k][i].Y += vel[k][i].Y * (float)dt;
                if (pts[k][i].X < 0 || pts[k][i].X > W) { vel[k][i].X = -vel[k][i].X; pts[k][i].X = Math.Max(0, Math.Min(W, pts[k][i].X)); }
                if (pts[k][i].Y < 0 || pts[k][i].Y > H) { vel[k][i].Y = -vel[k][i].Y; pts[k][i].Y = Math.Max(0, Math.Min(H, pts[k][i].Y)); }
            }
        acc += dt;
        if (acc > 0.045)
        {
            acc = 0;
            for (int k = 0; k < 2; k++) { hist[k].Add((PointF[])pts[k].Clone()); if (hist[k].Count > 16) hist[k].RemoveAt(0); }
        }
        Color c1 = Pc("accent", 146, 112, 255), c2 = Pc("cyan", 80, 222, 255), c3 = Pc("purple", 255, 112, 206);
        for (int k = 0; k < 2; k++)
        {
            Color baseC = k == 0 ? Mix(c1, c2, 0.5 + 0.5 * Math.Sin(t * 0.4)) : Mix(c3, c2, 0.5 + 0.5 * Math.Sin(t * 0.3 + 2));
            for (int h = 0; h < hist[k].Count; h++)
            {
                pen.Color = Al(baseC, 20 + 235 * (h + 1) / hist[k].Count);
                PointF[] p = hist[k][h];
                g.DrawPolygon(pen, p);
            }
        }
    }
    public override void Dispose() { pen.Dispose(); }
}

// ---- Digital Rain: falling glyph columns
class Rain : ThemeEffect
{
    int cell = 17, cols, rows; float[] y, sp; char[][] ch; Font f; string pool; SolidBrush br = new SolidBrush(Color.White);
    public override void Init()
    {
        cols = W / cell + 1; rows = H / cell + 40;
        y = new float[cols]; sp = new float[cols]; ch = new char[cols][];
        System.Text.StringBuilder sb = new System.Text.StringBuilder();
        for (int c = 0xFF66; c <= 0xFF9D; c++) sb.Append((char)c);
        sb.Append("0123456789:.=*+-<>");
        pool = sb.ToString();
        for (int i = 0; i < cols; i++)
        {
            y[i] = -R.Next(H * 2); sp[i] = 140 + R.Next(300); ch[i] = new char[rows];
            for (int j = 0; j < rows; j++) ch[i][j] = pool[R.Next(pool.Length)];
        }
        try { f = new Font("MS Gothic", 14f, FontStyle.Bold, GraphicsUnit.Pixel); } catch { f = new Font("Consolas", 14f, FontStyle.Bold, GraphicsUnit.Pixel); }
    }
    protected override void Frame(Graphics g, double t, double dt)
    {
        g.Clear(Pc("bgBottom", 2, 8, 4));
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        Color a = Pc("accent", 0, 255, 70);
        int trail = 16;
        for (int i = 0; i < cols; i++)
        {
            y[i] += sp[i] * (float)dt;
            int head = (int)(y[i] / cell);
            if (head - trail > H / cell) { y[i] = -R.Next(H); sp[i] = 140 + R.Next(300); continue; }
            if (head >= 0 && head < rows && R.Next(3) == 0) ch[i][head % rows] = pool[R.Next(pool.Length)];
            for (int k = 0; k < trail; k++)
            {
                int row = head - k;
                if (row < 0 || row * cell > H) continue;
                br.Color = k == 0 ? Color.FromArgb(235, 255, 235) : Al(a, (int)(240 * Math.Pow(1 - k / (double)trail, 1.5)));
                g.DrawString(ch[i][row % rows].ToString(), f, br, i * cell, row * cell);
            }
        }
    }
    public override void Dispose() { br.Dispose(); if (f != null) f.Dispose(); }
}

// ---- Retrowave: the sun over a rolling grid
class Retro : ThemeEffect
{
    float[] stx = new float[70], sty = new float[70];
    public override void Init() { for (int i = 0; i < 70; i++) { stx[i] = (float)R.NextDouble(); sty[i] = (float)R.NextDouble(); } }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Back(g, Pc("bgTop", 42, 10, 94), Pc("bgBottom", 13, 2, 33));
        float hor = H * 0.62f, cx = W / 2f;
        Color sun = Pc("sunTop", 255, 214, 90), edge = Pc("accent", 255, 60, 170);
        for (int i = 0; i < 70; i++) Ell(g, Al(Color.White, (int)(60 + 160 * (0.5 + 0.5 * Math.Sin(t * 2 * (0.4 + stx[i]) + i)))), stx[i] * W, sty[i] * hor * 0.75f, 2.2f, 2.2f);
        float r = H * 0.21f, cy = hor - r * 0.55f + (float)Math.Sin(t * 0.3) * r * 0.06f;
        for (int k = 4; k >= 1; k--) Ell(g, Al(edge, 14), cx - r - k * 28, cy - r - k * 28, (r + k * 28) * 2, (r + k * 28) * 2);
        using (GraphicsPath gp = new GraphicsPath())
        {
            gp.AddEllipse(cx - r, cy - r, r * 2, r * 2);
            using (LinearGradientBrush sb = new LinearGradientBrush(new RectangleF(cx - r, cy - r, r * 2, r * 2), sun, Pc("sunBottom", 255, 60, 170), 90f)) g.FillPath(sb, gp);
            g.SetClip(gp);
            double off = (t * 0.25) % 1.0;
            for (int s = 0; s < 9; s++)
            {
                float u = (float)(((s + off) % 9) / 9.0);
                float sy2 = cy + r * (-0.1f + 1.1f * u), hh = 2f + 12f * u;
                Fill(g, Pc("bgBottom", 13, 2, 33), cx - r, sy2, r * 2, hh);
            }
            g.ResetClip();
        }
        Fill(g, Pc("bgBottom", 13, 2, 33), 0, hor, W, H - hor);
        using (Pen hp = new Pen(Al(edge, 220), 2f)) g.DrawLine(hp, 0, hor, W, hor);
        Color gl = Al(Pc("cyan", 0, 220, 255), 140);
        double sc = (t * 0.35) % 1.0;
        for (int i = 0; i < 14; i++)
        {
            double u = (i + sc) / 14.0;
            float y = hor + (float)((H - hor) * u * u);
            using (Pen p = new Pen(Al(gl, (int)(30 + 190 * u)), 1.2f + (float)u * 1.5f)) g.DrawLine(p, 0, y, W, y);
        }
        for (int j = -14; j <= 14; j++)
            using (Pen p = new Pen(Al(gl, 120), 1.2f)) g.DrawLine(p, cx + j * W * 0.015f, hor, cx + j * W * 0.12f, H);
    }
}

// ---- Cyberpunk: neon pipes growing across the screen
class Pipes : ThemeEffect
{
    class Pipe { public int x, y, dx, dy, len; public Color c; }
    Bitmap buf; Graphics gb; List<Pipe> pipes = new List<Pipe>(); int cell = 28; double clearAt = 45, stepAcc = 0;
    Color[] cols;
    public override void Init()
    {
        buf = new Bitmap(W, H); gb = Graphics.FromImage(buf); gb.SmoothingMode = SmoothingMode.AntiAlias;
        cols = new Color[] { Pc("accent", 252, 238, 10), Pc("purple", 255, 0, 110), Pc("cyan", 0, 232, 255) };
        Wipe();
    }
    void Wipe()
    {
        gb.Clear(Pc("bgBottom", 7, 6, 16));
        pipes.Clear();
        for (int i = 0; i < 6; i++) pipes.Add(Spawn());
    }
    Pipe Spawn()
    {
        Pipe p = new Pipe();
        p.x = R.Next(W / cell) * cell; p.y = R.Next(H / cell) * cell;
        int d = R.Next(4); p.dx = d == 0 ? 1 : (d == 1 ? -1 : 0); p.dy = d == 2 ? 1 : (d == 3 ? -1 : 0);
        p.c = cols[R.Next(cols.Length)]; p.len = 0;
        return p;
    }
    protected override void Frame(Graphics g, double t, double dt)
    {
        stepAcc += dt * 16;
        while (stepAcc >= 1)
        {
            stepAcc -= 1;
            for (int i = 0; i < pipes.Count; i++)
            {
                Pipe p = pipes[i];
                if (R.NextDouble() < 0.16)
                {
                    if (p.dx != 0) { p.dx = 0; p.dy = R.Next(2) == 0 ? 1 : -1; } else { p.dy = 0; p.dx = R.Next(2) == 0 ? 1 : -1; }
                }
                int nx = p.x + p.dx * cell, ny = p.y + p.dy * cell;
                using (Pen glow = new Pen(Al(p.c, 40), 16f)) { glow.StartCap = LineCap.Round; glow.EndCap = LineCap.Round; gb.DrawLine(glow, p.x, p.y, nx, ny); }
                using (Pen core = new Pen(Al(p.c, 235), 7f)) { core.StartCap = LineCap.Round; core.EndCap = LineCap.Round; gb.DrawLine(core, p.x, p.y, nx, ny); }
                using (Pen hi = new Pen(Al(Color.White, 150), 2f)) gb.DrawLine(hi, p.x, p.y - 1, nx, ny - 1);
                p.x = nx; p.y = ny; p.len++;
                if (p.x < -cell || p.x > W + cell || p.y < -cell || p.y > H + cell || p.len > 150) pipes[i] = Spawn();
            }
        }
        if (t > clearAt) { clearAt = t + 45; Wipe(); }
        g.DrawImageUnscaled(buf, 0, 0);
    }
    public override void Dispose() { if (gb != null) gb.Dispose(); if (buf != null) buf.Dispose(); }
}

// ---- Glitch: a logo bouncing off the screen edges, glitching on every hit
class Bounce : ThemeEffect
{
    float x = 100, y = 100, vx = 230, vy = 170; int ci = 0; SizeF sz = SizeF.Empty; Font f; double glitchUntil = 0;
    public override void Init() { try { f = new Font(fontName, Math.Max(40, H / 11), FontStyle.Bold, GraphicsUnit.Pixel); } catch { f = new Font("Arial Black", Math.Max(40, H / 11), FontStyle.Bold, GraphicsUnit.Pixel); } }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Back(g, Pc("bgTop", 20, 10, 36), Pc("bgBottom", 8, 4, 16));
        for (int yy = 0; yy < H; yy += 4) Fill(g, Color.FromArgb(26, 0, 0, 0), 0, yy, W, 1);
        string s = "EKK0H";
        if (sz.IsEmpty) sz = g.MeasureString(s, f, 2000, StringFormat.GenericTypographic);
        x += vx * (float)dt; y += vy * (float)dt;
        bool hit = false;
        if (x < 0) { x = 0; vx = Math.Abs(vx); hit = true; } if (x + sz.Width > W) { x = W - sz.Width; vx = -Math.Abs(vx); hit = true; }
        if (y < 0) { y = 0; vy = Math.Abs(vy); hit = true; } if (y + sz.Height > H) { y = H - sz.Height; vy = -Math.Abs(vy); hit = true; }
        if (hit) { ci++; glitchUntil = t + 0.35; }
        Color[] cs = new Color[] { Pc("accent", 255, 40, 120), Pc("cyan", 0, 240, 255), Pc("purple", 190, 90, 255), Color.White };
        Color main = cs[ci % cs.Length];
        bool gl = t < glitchUntil;
        float j = gl ? (float)(R.NextDouble() * 14 - 7) : 0;
        using (SolidBrush b1 = new SolidBrush(Al(Pc("accent", 255, 40, 120), 190))) g.DrawString(s, f, b1, x - 5 + j, y, StringFormat.GenericTypographic);
        using (SolidBrush b2 = new SolidBrush(Al(Pc("cyan", 0, 240, 255), 190))) g.DrawString(s, f, b2, x + 5 - j, y, StringFormat.GenericTypographic);
        using (SolidBrush b3 = new SolidBrush(main)) g.DrawString(s, f, b3, x, y, StringFormat.GenericTypographic);
        if (gl) for (int i = 0; i < 6; i++) Fill(g, Al(i % 2 == 0 ? cs[0] : cs[1], 120), 0, y + R.Next((int)sz.Height), W, 2 + R.Next(8));
        else if (R.Next(120) == 0) glitchUntil = t + 0.12;
    }
    public override void Dispose() { if (f != null) f.Dispose(); }
}

// ---- Kawaii: hearts, stars and bubbles drifting up
class Bubbles : ThemeEffect
{
    int N = 80; float[] px, py, ps, pp; int[] kind;
    public override void Init()
    {
        px = new float[N]; py = new float[N]; ps = new float[N]; pp = new float[N]; kind = new int[N];
        for (int i = 0; i < N; i++) { px[i] = (float)R.NextDouble(); py[i] = (float)R.NextDouble(); ps[i] = 0.4f + (float)R.NextDouble(); pp[i] = (float)(R.NextDouble() * 6.28); kind[i] = i % 3; }
    }
    static void Heart(Graphics g, Color c, float cx, float cy, float s)
    {
        PointF[] pts = new PointF[64];
        float k = s / 16f;
        for (int i = 0; i < 64; i++)
        {
            double t = i * Math.PI * 2 / 64;
            double hx = 16 * Math.Pow(Math.Sin(t), 3);
            double hy = 13 * Math.Cos(t) - 5 * Math.Cos(2 * t) - 2 * Math.Cos(3 * t) - Math.Cos(4 * t);
            pts[i] = new PointF(cx + (float)hx * k, cy - (float)hy * k);
        }
        using (SolidBrush b = new SolidBrush(c)) g.FillPolygon(b, pts);
        using (SolidBrush h = new SolidBrush(Color.FromArgb(110, 255, 255, 255))) g.FillEllipse(h, cx - 9 * k, cy - 11 * k, 6 * k, 4 * k);
    }
    static void StarShape(Graphics g, Color c, float cx, float cy, float r)
    {
        PointF[] p = new PointF[10];
        for (int i = 0; i < 10; i++) { double a = -Math.PI / 2 + i * Math.PI / 5; float rr = (i % 2 == 0) ? r : r * 0.45f; p[i] = new PointF(cx + (float)Math.Cos(a) * rr, cy + (float)Math.Sin(a) * rr); }
        using (SolidBrush b = new SolidBrush(c)) g.FillPolygon(b, p);
    }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Back(g, Pc("bgTop", 255, 214, 235), Pc("bgBottom", 255, 240, 248));
        Color[] cs = new Color[] { Pc("accent", 255, 120, 170), Pc("cyan", 120, 220, 255), Pc("purple", 190, 150, 255), Pc("orange", 255, 190, 120), Pc("sun", 255, 225, 120) };
        float sc = H / 700f;
        for (int i = 0; i < N; i++)
        {
            py[i] -= (float)dt * 0.06f * ps[i];
            if (py[i] < -0.1f) { py[i] = 1.1f; px[i] = (float)R.NextDouble(); }
            float x = px[i] * W + (float)Math.Sin(t * ps[i] + pp[i]) * 30 * sc, y = py[i] * H;
            float sz = (12 + ps[i] * 22) * sc * (float)(0.88 + 0.16 * Math.Sin(t * 3 + pp[i]));
            Color c = Al(cs[i % cs.Length], 170);
            if (kind[i] == 0) Heart(g, c, x, y, sz);
            else if (kind[i] == 1) StarShape(g, c, x, y, sz);
            else { using (Pen p = new Pen(Al(cs[i % cs.Length], 200), 2f)) g.DrawEllipse(p, x, y, sz * 1.5f, sz * 1.5f); Ell(g, Al(Color.White, 190), x + sz * 0.3f, y + sz * 0.25f, sz * 0.3f, sz * 0.3f); }
        }
    }
}

// ---- Aurora: flowing ribbons of light
class Ribbons : ThemeEffect
{
    float[] sx, sy;
    public override void Init() { sx = new float[90]; sy = new float[90]; for (int i = 0; i < 90; i++) { sx[i] = (float)R.NextDouble(); sy[i] = (float)R.NextDouble() * 0.7f; } }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Back(g, Pc("bgTop", 6, 14, 34), Pc("bgBottom", 2, 6, 16));
        for (int i = 0; i < 90; i++) Ell(g, Al(Color.White, (int)(40 + 150 * (0.5 + 0.5 * Math.Sin(t * (0.6 + sx[i]) + i)))), sx[i] * W, sy[i] * H, 2f, 2f);
        Color[] cs = new Color[] { Pc("accent", 80, 255, 170), Pc("cyan", 80, 222, 255), Pc("purple", 190, 110, 255), Pc("ok", 90, 255, 150), Pc("accent", 80, 255, 170), Pc("cyan", 80, 222, 255) };
        int n = 70;
        for (int k = 0; k < 6; k++)
        {
            PointF[] poly = new PointF[(n + 1) * 2];
            for (int i = 0; i <= n; i++)
            {
                double u = i / (double)n, x = u * (W + 200) - 100;
                double cy = H * (0.42 + 0.05 * k - 0.1) + Math.Sin(u * 3.2 + t * (0.25 + 0.05 * k) + k * 1.3) * H * 0.12 + Math.Sin(u * 7.1 - t * 0.4 + k) * H * 0.04;
                double th = H * (0.07 + 0.05 * Math.Sin(u * 4 + t * 0.3 + k * 2));
                poly[i] = new PointF((float)x, (float)(cy - th));
                poly[2 * (n + 1) - 1 - i] = new PointF((float)x, (float)(cy + th));
            }
            using (SolidBrush b = new SolidBrush(Al(cs[k], 44))) g.FillPolygon(b, poly);
            PointF[] edge = new PointF[n + 1];
            for (int i = 0; i <= n; i++) edge[i] = poly[i];
            using (Pen p = new Pen(Al(cs[k], 150), 2f)) g.DrawLines(p, edge);
        }
    }
}

// ---- Gothic: bats flying across a moonlit sky (the screen-saver cousin of the flying toasters)
class Bats : ThemeEffect
{
    class B { public float x, y, vx, vy, s, ph; }
    List<B> bats = new List<B>();
    public override void Init() { for (int i = 0; i < 9; i++) { B b = new B(); Place(b, true); bats.Add(b); } }
    void Place(B b, bool anywhere)
    {
        b.s = (0.8f + (float)R.NextDouble() * 1.3f) * H / 700f;
        b.vx = -(110 + R.Next(130)) * b.s; b.vy = (25 + R.Next(55)) * b.s; b.ph = (float)(R.NextDouble() * 6);
        if (anywhere) { b.x = R.Next(W); b.y = R.Next(H); }
        else if (R.Next(2) == 0) { b.x = W + 60; b.y = R.Next(H / 2); } else { b.x = R.Next(W); b.y = -60; }
    }
    static void DrawBat(Graphics g, float x, float y, float sc, double t, Color c)
    {
        float f = (float)Math.Sin(t * 14);
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
            g.FillEllipse(b, x - 4 * sc, y - 9 * sc, 8 * sc, 18 * sc); g.FillEllipse(b, x - 4 * sc, y - 11 * sc, 8 * sc, 7 * sc);
        }
    }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Color ac = Pc("accent", 200, 40, 60);
        Back(g, Mix(Pc("bgTop", 34, 12, 20), ac, 0.25), Pc("bgBottom", 8, 3, 6));
        float mr = H * 0.13f, mx = W * 0.2f, my = H * 0.24f;
        for (int k = 6; k >= 1; k--) Ell(g, Al(ac, 12), mx - mr - k * 26, my - mr - k * 26, (mr + k * 26) * 2, (mr + k * 26) * 2);
        using (GraphicsPath m1 = new GraphicsPath()) using (GraphicsPath m2 = new GraphicsPath())
        {
            m1.AddEllipse(mx - mr, my - mr, mr * 2, mr * 2); m2.AddEllipse(mx - mr * 0.55f, my - mr * 1.15f, mr * 2, mr * 2);
            using (Region rg = new Region(m1)) { rg.Exclude(m2); using (SolidBrush b = new SolidBrush(Pc("sun", 235, 225, 200))) g.FillRegion(b, rg); }
        }
        for (int i = 0; i < 4; i++)
        {
            float fx = (float)(((t * (8 + i * 3) + i * 400) % (W + 600)) - 300);
            Ell(g, Al(Pc("sub", 160, 120, 120), 14), fx, H * (0.62f + i * 0.08f), 700, H * 0.12f);
        }
        foreach (B b in bats)
        {
            b.x += b.vx * (float)dt; b.y += b.vy * (float)dt + (float)Math.Sin(t * 2 + b.ph) * 0.7f;
            if (b.x < -80 || b.y > H + 80) Place(b, false);
            DrawBat(g, b.x, b.y, b.s, t + b.ph, Color.FromArgb(240, 6, 3, 8));
        }
    }
}

// ---- RGB: a circular music-style equalizer
class Equalizer : ThemeEffect
{
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
    protected override void Frame(Graphics g, double t, double dt)
    {
        t *= 0.6;
        Back(g, Color.FromArgb(14, 14, 20), Color.FromArgb(4, 4, 8));
        float cx = W / 2f, cy = H / 2f, r0 = H * 0.2f, maxL = H * 0.26f;
        double kk = Math.Pow(Math.Max(0, Math.Sin(t * 2 * Math.PI * 2.1)), 5);
        for (int i = 0; i < 5; i++) { double a = t * 0.5 + i * 1.26; Ell(g, Al(Hsv(t * 70 + i * 72, 1, 1), (int)(10 + 14 * kk)), cx + (float)Math.Cos(a) * W * 0.12f - H * 0.4f, cy + (float)Math.Sin(a) * H * 0.1f - H * 0.4f, H * 0.8f, H * 0.8f); }
        int N = 96, half = N / 2;
        for (int i = 0; i < N; i++)
        {
            int idx = i < half ? i : N - 1 - i;
            float v = EqBar(t, idx, half);
            float cap = Math.Max(Math.Max(v, EqBar(t - 0.14, idx, half) - 0.04f), Math.Max(EqBar(t - 0.28, idx, half) - 0.08f, EqBar(t - 0.42, idx, half) - 0.12f));
            double ang = -Math.PI / 2 + (i + 0.5) * 2 * Math.PI / N;
            float ca = (float)Math.Cos(ang), sa = (float)Math.Sin(ang);
            Color c = Hsv(i * (360.0 / N) + t * 60, 1, 1);
            float rs = r0 + 10, re = rs + v * maxL;
            using (Pen p = new Pen(Al(c, 60), 12f)) g.DrawLine(p, cx + ca * rs, cy + sa * rs, cx + ca * re, cy + sa * re);
            using (Pen p = new Pen(Al(c, 240), 6f)) g.DrawLine(p, cx + ca * rs, cy + sa * rs, cx + ca * re, cy + sa * re);
            float rc = rs + cap * maxL + 8;
            using (Pen p = new Pen(Al(Color.White, 240), 4f)) g.DrawLine(p, cx + ca * rc, cy + sa * rc, cx + ca * (rc + 4), cy + sa * (rc + 4));
        }
        float pr = r0 + (float)(kk * 5);
        Ell(g, Color.FromArgb(240, 9, 9, 15), cx - pr, cy - pr, pr * 2, pr * 2);
        for (int i = 0; i < 72; i++)
            using (Pen rp = new Pen(Al(Hsv(i * 5 - t * 140, 1, 1), 235), 4f)) g.DrawArc(rp, cx - pr, cy - pr, pr * 2, pr * 2, (float)(i * 5.0 - 90), 5.2f);
    }
}

// ---- Shinobi: layered misty mountains under a big moon, blossoms drifting down
class Blossoms : ThemeEffect
{
    int N = 130; float[] px, py, ps, pr, pw;
    public override void Init()
    {
        px = new float[N]; py = new float[N]; ps = new float[N]; pr = new float[N]; pw = new float[N];
        for (int i = 0; i < N; i++) { px[i] = (float)R.NextDouble(); py[i] = (float)R.NextDouble(); ps[i] = 0.5f + (float)R.NextDouble(); pr[i] = (float)(R.NextDouble() * 6.28); pw[i] = (float)(R.NextDouble() * 6.28); }
    }
    float Ridge(float x, int layer)
    {
        double u = x / (double)W;
        double a = 1 - Math.Abs(Math.Sin(u * (2.2 + layer * 0.9) * Math.PI + layer * 1.7));
        double b = 1 - Math.Abs(Math.Sin(u * (5.1 + layer * 1.3) * Math.PI + layer * 0.6));
        double h = 0.72 * Math.Pow(a, 1.3) + 0.28 * Math.Pow(b, 1.6);
        float baseY = H * (0.50f + layer * 0.11f);
        return baseY - (float)h * H * (0.30f - layer * 0.03f) + H * 0.2f * 0.5f;
    }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Color moonC = Pc("sun", 255, 232, 205);
        Color top = Pc("bgTop", 52, 16, 40), bot = Pc("bgBottom", 12, 9, 14);
        Back(g, top, bot);
        float mr = H * 0.15f, mx = W * 0.70f, my = H * 0.26f;
        for (int k = 9; k >= 1; k--) Ell(g, Al(moonC, 7), mx - mr - k * 24, my - mr - k * 24, (mr + k * 24) * 2, (mr + k * 24) * 2);
        Ell(g, moonC, mx - mr, my - mr, mr * 2, mr * 2);
        Color tint = Mix(moonC, Pc("accent", 200, 30, 50), 0.35);
        Ell(g, Al(tint, 70), mx - mr * 0.45f, my - mr * 0.2f, mr * 0.5f, mr * 0.35f);
        Ell(g, Al(tint, 50), mx + mr * 0.1f, my - mr * 0.6f, mr * 0.3f, mr * 0.25f);
        // mountains: far ones pale and hazy, near ones dark, with drifting mist between them
        int layers = 5, cnt = 90;
        for (int layer = 0; layer < layers; layer++)
        {
            double depth = layer / (double)(layers - 1);
            Color fill = Mix(Mix(top, Pc("accent", 200, 30, 50), 0.28), bot, depth * 0.95);
            PointF[] hp = new PointF[cnt + 3];
            for (int i = 0; i <= cnt; i++) { float x = i * W / (float)cnt; hp[i] = new PointF(x, Ridge(x, layer)); }
            hp[cnt + 1] = new PointF(W, H + 2); hp[cnt + 2] = new PointF(0, H + 2);
            using (SolidBrush br = new SolidBrush(fill)) g.FillPolygon(br, hp);
            float my2 = H * (0.56f + layer * 0.1f);
            for (int m = 0; m < 3; m++)
            {
                float mxp = (float)(((t * (6 + layer * 3 + m * 2) + m * 700 + layer * 330) % (W + 1200)) - 600);
                Ell(g, Al(Mix(top, Color.White, 0.25), 26), mxp, my2 + m * 18, 900, H * 0.07f);
            }
        }
        Color pink = Pc("cyan", 255, 176, 200);
        for (int i = 0; i < N; i++)
        {
            py[i] += (float)dt * 0.07f * ps[i]; px[i] -= (float)dt * 0.05f * ps[i];
            if (py[i] > 1.05f) { py[i] = -0.05f; px[i] = (float)R.NextDouble() * 1.3f; }
            if (px[i] < -0.05f) px[i] += 1.15f;
            float x = px[i] * W + (float)Math.Sin(t * ps[i] + pw[i]) * 26, y = py[i] * H, sz = (6 + ps[i] * 7) * H / 700f;
            GraphicsState st = g.Save();
            g.TranslateTransform(x, y); g.RotateTransform((float)(pr[i] * 57.3 + t * 70 * ps[i]));
            Ell(g, Al(pink, 215), -sz, -sz * 0.55f, sz * 2, sz * 1.1f);
            g.Restore(st);
        }
    }
}

// ---- Blueprint: a drafting sheet - a spinning wireframe part, meshing gears, dimension lines drawn in, and a title block
class Draft : ThemeEffect
{
    Font f, fs;
    public override void Init()
    {
        try { f = new Font("Consolas", Math.Max(11, H / 60), FontStyle.Regular, GraphicsUnit.Pixel); fs = new Font("Consolas", Math.Max(9, H / 80), FontStyle.Regular, GraphicsUnit.Pixel); }
        catch { f = new Font("Courier New", 12, FontStyle.Regular, GraphicsUnit.Pixel); fs = new Font("Courier New", 10, FontStyle.Regular, GraphicsUnit.Pixel); }
    }
    static double Sweep(double tt, double start, double dur) { return Math.Max(0, Math.Min(1, (tt - start) / dur)); }
    static void Gear(Graphics g, Pen pen, float cx, float cy, float r, int teeth, double rot)
    {
        float ro = r * 1.12f, ri = r * 0.88f;
        PointF[] pts = new PointF[teeth * 4];
        for (int i = 0; i < teeth; i++)
        {
            double a0 = rot + i * 2 * Math.PI / teeth, w = 2 * Math.PI / teeth;
            double[] ang = new double[] { a0, a0 + w * 0.12, a0 + w * 0.42, a0 + w * 0.54 };
            float[] rad = new float[] { ri, ro, ro, ri };
            for (int k = 0; k < 4; k++) pts[i * 4 + k] = new PointF(cx + (float)Math.Cos(ang[k]) * rad[k], cy + (float)Math.Sin(ang[k]) * rad[k]);
        }
        g.DrawPolygon(pen, pts);
        g.DrawEllipse(pen, cx - r * 0.25f, cy - r * 0.25f, r * 0.5f, r * 0.5f);
        for (int i = 0; i < 5; i++)
        {
            double a = rot + i * 2 * Math.PI / 5;
            g.DrawLine(pen, cx + (float)Math.Cos(a) * r * 0.25f, cy + (float)Math.Sin(a) * r * 0.25f, cx + (float)Math.Cos(a) * r * 0.7f, cy + (float)Math.Sin(a) * r * 0.7f);
        }
        g.DrawEllipse(pen, cx - r * 0.7f, cy - r * 0.7f, r * 1.4f, r * 1.4f);
    }
    void Dim(Graphics g, Pen pen, Brush tb, float x1, float y1, float x2, float y2, double p, string label, bool vertical)
    {
        float ex = x1 + (x2 - x1) * (float)p, ey = y1 + (y2 - y1) * (float)p;
        g.DrawLine(pen, x1, y1, ex, ey);
        float a = 7;
        if (vertical) { g.DrawLine(pen, x1 - 10, y1, x1 + 10, y1); g.DrawLine(pen, x1 - 10, ey, x1 + 10, ey); g.DrawLine(pen, x1, y1, x1 - 3, y1 + a); g.DrawLine(pen, x1, y1, x1 + 3, y1 + a); }
        else { g.DrawLine(pen, x1, y1 - 10, x1, y1 + 10); g.DrawLine(pen, ex, ey - 10, ex, ey + 10); g.DrawLine(pen, x1, y1, x1 + a, y1 - 3); g.DrawLine(pen, x1, y1, x1 + a, y1 + 3); }
        if (p >= 1)
        {
            if (vertical) { g.DrawLine(pen, x2, y2, x2 - 3, y2 - a); g.DrawLine(pen, x2, y2, x2 + 3, y2 - a); g.DrawString(label, fs, tb, x1 + 8, (y1 + y2) / 2 - 6); }
            else { g.DrawLine(pen, x2, y2, x2 - a, y2 - 3); g.DrawLine(pen, x2, y2, x2 - a, y2 + 3); g.DrawString(label, fs, tb, (x1 + x2) / 2 - 24, y1 - 18); }
        }
    }
    protected override void Frame(Graphics g, double t, double dt)
    {
        Color paperA = Pc("bgTop", 24, 78, 150), paperB = Pc("bgBottom", 12, 46, 100);
        Back(g, paperA, paperB);
        Color ink = Mix(Pc("cyan", 150, 210, 255), Color.White, 0.7);
        using (Pen mn = new Pen(Al(ink, 22), 1f)) using (Pen mj = new Pen(Al(ink, 54), 1f))
        {
            for (int x = 0; x < W; x += 24) g.DrawLine((x % 120 == 0) ? mj : mn, x, 0, x, H);
            for (int y = 0; y < H; y += 24) g.DrawLine((y % 120 == 0) ? mj : mn, 0, y, W, y);
        }
        double T = 36, tt = t % T;
        double fade = Math.Min(1, Math.Min(tt / 1.2, (T - tt) / 1.5));
        int al = (int)(255 * fade);
        using (Pen pen = new Pen(Al(ink, al), 2f)) using (Pen thin = new Pen(Al(ink, (int)(al * 0.7)), 1.2f)) using (SolidBrush tb = new SolidBrush(Al(ink, al)))
        using (Pen cl = new Pen(Al(ink, (int)(al * 0.55)), 1.2f))
        {
            cl.DashStyle = DashStyle.DashDotDot;
            // sheet border
            g.DrawRectangle(pen, 18, 18, W - 36, H - 36);
            g.DrawRectangle(thin, 28, 28, W - 56, H - 56);

            // wireframe part (a cube with a ring through it)
            float cx = W * 0.30f, cy = H * 0.46f, sz = H * 0.2f;
            double ax = t * 0.5, ay = t * 0.7;
            double[,] v = new double[8, 3];
            for (int i = 0; i < 8; i++) { v[i, 0] = (i & 1) == 0 ? -1 : 1; v[i, 1] = (i & 2) == 0 ? -1 : 1; v[i, 2] = (i & 4) == 0 ? -1 : 1; }
            PointF[] pp = new PointF[8];
            for (int i = 0; i < 8; i++)
            {
                double x = v[i, 0], y = v[i, 1], z = v[i, 2];
                double x1 = x * Math.Cos(ay) + z * Math.Sin(ay), z1 = -x * Math.Sin(ay) + z * Math.Cos(ay);
                double y1 = y * Math.Cos(ax) - z1 * Math.Sin(ax), z2 = y * Math.Sin(ax) + z1 * Math.Cos(ax);
                double k = 1.0 / (3.2 - z2 * 0.5);
                pp[i] = new PointF(cx + (float)(x1 * k * sz * 1.9), cy + (float)(y1 * k * sz * 1.9));
            }
            double dr = Sweep(tt, 0.8, 4);
            int[,] edges = new int[,] { {0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7} };
            for (int e = 0; e < 12; e++)
            {
                double pe = Math.Max(0, Math.Min(1, dr * 12 - e));
                if (pe <= 0) continue;
                PointF a = pp[edges[e, 0]], b = pp[edges[e, 1]];
                g.DrawLine(pen, a.X, a.Y, a.X + (b.X - a.X) * (float)pe, a.Y + (b.Y - a.Y) * (float)pe);
            }
            // centre lines and a bore circle
            double dc = Sweep(tt, 3.5, 2);
            g.DrawLine(cl, cx - sz * 1.9f * (float)dc, cy, cx + sz * 1.9f * (float)dc, cy);
            g.DrawLine(cl, cx, cy - sz * 1.9f * (float)dc, cx, cy + sz * 1.9f * (float)dc);
            g.DrawArc(thin, cx - sz * 0.55f, cy - sz * 0.55f, sz * 1.1f, sz * 1.1f, 0, (float)(360 * dc));
            // dimension lines
            Dim(g, thin, tb, cx - sz * 1.4f, cy + sz * 2.15f, cx + sz * 1.4f, cy + sz * 2.15f, Sweep(tt, 6, 2), "240.00", false);
            Dim(g, thin, tb, cx - sz * 2.35f, cy - sz * 1.4f, cx - sz * 2.35f, cy + sz * 1.4f, Sweep(tt, 7.5, 2), "240.00", true);
            if (Sweep(tt, 9, 1) > 0) g.DrawString("R 60.00", fs, tb, cx + sz * 0.45f, cy - sz * 0.9f);

            // meshing gears
            float rA = H * 0.15f, rB = rA * 10f / 16f, gx = W * 0.70f, gy = H * 0.40f;
            double rot = t * 0.4;
            double dg = Sweep(tt, 2, 3);
            if (dg > 0)
            {
                Gear(g, pen, gx, gy, rA, 16, rot);
                Gear(g, pen, gx + rA + rB, gy, rB, 10, -rot * 16.0 / 10.0 + Math.PI / 10);
                g.DrawLine(cl, gx - rA * 1.3f, gy, gx + rA + rB + rB * 1.3f, gy);
                g.DrawEllipse(cl, gx - rA, gy - rA, rA * 2, rA * 2);
                g.DrawEllipse(cl, gx + rA - 0f, gy - rB, rB * 2, rB * 2);
                Dim(g, thin, tb, gx - rA, gy + rA * 1.55f, gx + rA + rB * 2, gy + rA * 1.55f, Sweep(tt, 8, 2), "DIA 96.00", false);
                g.DrawString("Z=16  M=6", fs, tb, gx - rA * 0.5f, gy - rA * 1.55f);
                g.DrawString("Z=10  M=6", fs, tb, gx + rA + rB - 30, gy - rA * 1.2f);
            }

            // title block
            float bw = Math.Min(W * 0.34f, 520), bh = H * 0.13f, bx = W - 28 - bw, by = H - 28 - bh;
            g.DrawRectangle(pen, bx, by, bw, bh);
            g.DrawLine(thin, bx, by + bh * 0.5f, bx + bw, by + bh * 0.5f);
            g.DrawLine(thin, bx + bw * 0.55f, by + bh * 0.5f, bx + bw * 0.55f, by + bh);
            g.DrawString("EKK0H  WALLPAPER STUDIO", f, tb, bx + 10, by + bh * 0.12f);
            g.DrawString("DWG NO. 0451   SCALE 1:1", fs, tb, bx + 10, by + bh * 0.58f);
            g.DrawString("SHEET 1 OF 1   REV " + (char)('A' + (int)(t / T) % 6), fs, tb, bx + bw * 0.55f + 10, by + bh * 0.58f);
            // a pencil tick that follows the sweep along the bottom edge
            float tx = 28 + (float)((tt / T) * (W - 56));
            g.DrawLine(thin, tx, H - 40, tx, H - 28);
        }
    }
    public override void Dispose() { if (f != null) f.Dispose(); if (fs != null) fs.Dispose(); }
}
