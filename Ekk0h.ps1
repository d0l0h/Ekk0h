# Ekk0h.ps1
# A small desktop app for swapping multi-monitor wallpaper packs.
#
#   Packs:     folders inside "WallpaperPacks" (next to this script). Images are
#              applied left-to-right across your monitors in filename order.
#              A pack with 1 image uses it on every monitor.
#   Animated:  video files in the "Animated" folder, played through the free
#              Lively Wallpaper app (installed separately).
#
# Run:            powershell -ExecutionPolicy Bypass -File Ekk0h.ps1
# Make shortcuts: ... -Install   (Desktop shortcuts: Ctrl+Alt+W = app, Ctrl+Alt+R = random pack)
# Random only:    ... -Random    (applies a random pack and exits, no window)

param(
    [switch]$Install,
    [switch]$Random,
    [switch]$Tray,
    [string]$Root = (Join-Path $PSScriptRoot "WallpaperPacks"),
    [string]$AnimRoot = (Join-Path $PSScriptRoot "Animated")
)

# ---------------------------------------------------------------- shortcuts
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------- app icon (drawn in code)
function New-IconBitmap([int]$size) {
    $bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $s = [single]$size

    # rounded dark-purple tile
    $inset = $s * 0.03
    $ts = $s - 2 * $inset
    $d = $ts * 0.38
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($inset, $inset, $d, $d, 180, 90)
    $path.AddArc(($inset + $ts - $d), $inset, $d, $d, 270, 90)
    $path.AddArc(($inset + $ts - $d), ($inset + $ts - $d), $d, $d, 0, 90)
    $path.AddArc($inset, ($inset + $ts - $d), $d, $d, 90, 90)
    $path.CloseFigure()
    $tile = New-Object System.Drawing.RectangleF(0, 0, $s, $s)
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($tile, [System.Drawing.Color]::FromArgb(255, 42, 10, 94), [System.Drawing.Color]::FromArgb(255, 18, 4, 31), [single]90)
    $g.FillPath($bg, $path)

    # three slanted screens that fade like an echo (the last one is the sunset)
    $k = [math]::Tan(10 * [math]::PI / 180)
    $u = $s / 512.0
    $mk = {
        param($x0, $y0, $w, $h)
        $pts = @()
        foreach ($c in @(@($x0, $y0), @(($x0 + $w), $y0), @(($x0 + $w), ($y0 + $h)), @($x0, ($y0 + $h)))) {
            $pts += New-Object System.Drawing.PointF([single](($c[0] + 46 - $k * $c[1]) * $u), [single]($c[1] * $u))
        }
        , $pts
    }
    $p1 = & $mk 96 150 96 200
    $p2 = & $mk 206 130 96 240
    $p3 = & $mk 316 110 96 280
    $pw = [single][math]::Max(1.4, 10 * $u)
    if ($size -lt 32) {
        $br1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, 0, 240, 255))
        $br2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190, 0, 240, 255))
        $g.FillPolygon($br1, [System.Drawing.PointF[]]$p1)
        $g.FillPolygon($br2, [System.Drawing.PointF[]]$p2)
        $br1.Dispose(); $br2.Dispose()
    } else {
        $pn1 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 0, 240, 255), $pw)
        $pn2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(165, 0, 240, 255), $pw)
        $pn1.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round; $pn2.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawPolygon($pn1, [System.Drawing.PointF[]]$p1)
        $g.DrawPolygon($pn2, [System.Drawing.PointF[]]$p2)
        $pn1.Dispose(); $pn2.Dispose()
    }
    $sunRect = New-Object System.Drawing.RectangleF(0, [single](110 * $u), $s, [single](280 * $u))
    $sun = New-Object System.Drawing.Drawing2D.LinearGradientBrush($sunRect, [System.Drawing.Color]::FromArgb(255, 255, 179, 71), [System.Drawing.Color]::FromArgb(255, 255, 41, 117), [single]90)
    $g.FillPolygon($sun, [System.Drawing.PointF[]]$p3)
    if ($size -ge 48) {
        $line = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 255, 41, 117))
        $g.FillRectangle($line, [single](60 * $u), [single](420 * $u), [single](392 * $u), [single](8 * $u))
        $line.Dispose()
    }

    $bg.Dispose(); $sun.Dispose(); $path.Dispose(); $g.Dispose()
    return $bmp
}

function Save-AppIcon([string]$icoPath) {
    $sizes = @(16, 32, 48, 256)
    $pngs = @()
    foreach ($sz in $sizes) {
        $bmp = New-IconBitmap $sz
        $ms = New-Object System.IO.MemoryStream
        $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngs += , ($ms.ToArray())
        $bmp.Dispose(); $ms.Dispose()
    }
    $fs = [System.IO.File]::Create($icoPath)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        if ($sizes[$i] -ge 256) { $dim = 0 } else { $dim = $sizes[$i] }
        $bw.Write([byte]$dim); $bw.Write([byte]$dim); $bw.Write([byte]0); $bw.Write([byte]0)
        $bw.Write([uint16]1); $bw.Write([uint16]32)
        $bw.Write([uint32]$pngs[$i].Length); $bw.Write([uint32]$offset)
        $offset += $pngs[$i].Length
    }
    for ($i = 0; $i -lt $pngs.Count; $i++) { $bw.Write([byte[]]$pngs[$i]) }
    $bw.Close(); $fs.Close()
}

# the exe this app is running from (null when it was started as a plain .ps1 through powershell.exe)
function Get-AppExe {
    try {
        $p = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
        if ([IO.Path]::GetFileName($p) -notmatch '^(powershell|pwsh|powershell_ise)\.exe$') { return $p }
    } catch { }
    return $null
}

if ($Install) {
    $icoPath = Join-Path $PSScriptRoot "ControlCenter.ico"
    if (-not (Get-AppExe) -and -not (Test-Path -LiteralPath $icoPath)) { Save-AppIcon $icoPath }

    # Silent launcher: starts the app with no console window flashing open.
    $vbsPath = Join-Path $PSScriptRoot "Launch.vbs"
    $vbs = @(
        'Set sh = CreateObject("WScript.Shell")',
        'Set fso = CreateObject("Scripting.FileSystemObject")',
        'dir = fso.GetParentFolderName(WScript.ScriptFullName)',
        'extra = ""',
        'If WScript.Arguments.Count > 0 Then extra = " -Random"',
        'sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\Ekk0h.ps1""" & extra, 0, False'
    )
    if (-not (Get-AppExe)) { Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII }
    $wscript = Join-Path $env:WINDIR "System32\wscript.exe"
    $shell = New-Object -ComObject WScript.Shell
    $desk = [Environment]::GetFolderPath("Desktop")

    $lnk = $shell.CreateShortcut((Join-Path $desk "Ekk0h.lnk"))
    $appExe = Get-AppExe
    if ($appExe) { $lnk.TargetPath = $appExe; $lnk.Arguments = "" }
    else { $lnk.TargetPath = $wscript; $lnk.Arguments = "`"$vbsPath`"" }
    $lnk.WorkingDirectory = $PSScriptRoot
    $lnk.Hotkey = "CTRL+ALT+W"
    $lnk.IconLocation = $(if ($appExe) { "$appExe,0" } else { "$icoPath,0" })
    $lnk.Save()

    Write-Host "Created Desktop shortcut:"
    Write-Host "  Ekk0h  (Ctrl+Alt+W)"
    Write-Host "Keep them on the Desktop and don't move this folder, or the hotkeys stop working."
    return
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

if (-not ('DpiHelper' -as [type])) {
    Add-Type @"
using System.Runtime.InteropServices;
public static class DpiHelper {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
}

if (-not ('IDesktopWallpaper' -as [type])) {
    Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct WPRECT { public int Left, Top, Right, Bottom; }

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"),
 InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IDesktopWallpaper {
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID,
                      [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetMonitorDevicePathAt(uint monitorIndex);
    uint GetMonitorDevicePathCount();
    WPRECT GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    void SetBackgroundColor(uint color);
    uint GetBackgroundColor();
    void SetPosition(int position);
    int GetPosition();
}

[ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
public class DesktopWallpaperClass { }

public static class WallpaperHelper {
    // Images go left-to-right across the monitors, by physical position.
    public static int Apply(string[] images) { return Apply(images, null); }

    // skip[i] = true leaves screen i (left-to-right, 0-based) exactly as it is.
    public static int Apply(string[] images, bool[] skip) {
        IDesktopWallpaper wp = (IDesktopWallpaper)new DesktopWallpaperClass();
        uint count = wp.GetMonitorDevicePathCount();
        List<KeyValuePair<int, string>> list = new List<KeyValuePair<int, string>>();
        for (uint i = 0; i < count; i++) {
            try {
                string id = wp.GetMonitorDevicePathAt(i);
                if (string.IsNullOrEmpty(id)) continue;
                WPRECT r = wp.GetMonitorRECT(id);
                list.Add(new KeyValuePair<int, string>(r.Left, id));
            } catch { }
        }
        list.Sort(delegate(KeyValuePair<int, string> a, KeyValuePair<int, string> b) {
            return a.Key.CompareTo(b.Key);
        });
        wp.SetPosition(4); // Fill
        for (int i = 0; i < list.Count; i++) {
            if (skip != null && i < skip.Length && skip[i]) continue;
            wp.SetWallpaper(list[i].Value, images[i % images.Length]);
        }
        return list.Count;
    }
}
"@
}

if (-not ('DarkTitle' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class DarkTitle {
    [DllImport("dwmapi.dll")]
    static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

    public static void Apply(IntPtr hwnd) {
        try {
            int on = 1;
            if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4);
            int caption = (33 << 16) | (2 << 8) | 13;       // matches the app background
            DwmSetWindowAttribute(hwnd, 35, ref caption, 4);
            int text = (255 << 16) | (233 << 8) | 242;
            DwmSetWindowAttribute(hwnd, 36, ref text, 4);
        } catch { }
    }

    public static void Custom(IntPtr hwnd, bool dark, int cap, int txt) {
        try {
            int on = dark ? 1 : 0;
            if (DwmSetWindowAttribute(hwnd, 20, ref on, 4) != 0) DwmSetWindowAttribute(hwnd, 19, ref on, 4);
            DwmSetWindowAttribute(hwnd, 35, ref cap, 4);
            DwmSetWindowAttribute(hwnd, 36, ref txt, 4);
        } catch { }
    }
}

public static class AppId {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    public static void Set(string id) { try { SetCurrentProcessExplicitAppUserModelID(id); } catch { } }
}
"@
}

# Which physical monitor (by its Windows device path) sits behind each screen name.
$script:monMapOk = $true
if (-not ('MonitorMap' -as [type])) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class MonitorMap {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplayDevices(string device, uint index, ref DISPLAY_DEVICE dd, uint flags);

    // Returns pairs like  \\.\DISPLAY1|DISPLAY\DELA0B2\5&1a2b3c&0&UID256
    public static string[] Pairs() {
        List<string> res = new List<string>();
        for (uint i = 0; i < 32; i++) {
            DISPLAY_DEVICE a = new DISPLAY_DEVICE(); a.cb = Marshal.SizeOf(a);
            if (!EnumDisplayDevices(null, i, ref a, 0)) break;
            for (uint j = 0; j < 8; j++) {
                DISPLAY_DEVICE m = new DISPLAY_DEVICE(); m.cb = Marshal.SizeOf(m);
                if (!EnumDisplayDevices(a.DeviceName, j, ref m, 1)) break;
                res.Add(a.DeviceName + "|" + m.DeviceID);
            }
        }
        return res.ToArray();
    }
}
"@
    } catch { $script:monMapOk = $false }
}

# Windows' own thumbnail for a video/gif (same one Explorer shows). Optional: if it
# can't compile, the Animated tab just shows "No preview".
$script:thumbOk = $true
if (-not ('ShellThumb' -as [type])) {
    try {
        Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;

public static class ShellThumb {
    [StructLayout(LayoutKind.Sequential)]
    struct THUMBSIZE { public int cx, cy; }

    [ComImport, Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellItemImageFactory {
        [PreserveSig] int GetImage(THUMBSIZE size, int flags, out IntPtr phbm);
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    static extern void SHCreateItemFromParsingName(string path, IntPtr pbc, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out IShellItemImageFactory ppv);

    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);

    // Returns null when Windows has no thumbnail for the file.
    public static Bitmap Get(string path, int w, int h) {
        Guid iid = new Guid("bcc18b79-ba16-442f-80c4-8a59c30c463b");
        IShellItemImageFactory f = null;
        try {
            SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out f);
            THUMBSIZE sz = new THUMBSIZE(); sz.cx = w; sz.cy = h;
            IntPtr hbm;
            int hr = f.GetImage(sz, 8, out hbm);   // 8 = thumbnail only (no generic icon)
            if (hr != 0 || hbm == IntPtr.Zero) return null;
            Bitmap tmp = Image.FromHbitmap(hbm);
            Bitmap copy = new Bitmap(tmp);
            tmp.Dispose();
            DeleteObject(hbm);
            return copy;
        } catch { return null; }
        finally { if (f != null) Marshal.ReleaseComObject(f); }
    }
}
"@
    } catch { $script:thumbOk = $false }
}

# Pixel effects used after upscaling: mix the AI result with a plain resize, and add film grain.
$script:fxOk = $true
if (-not ('ImageFx' -as [type])) {
    try {
        Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class ImageFx {
    static byte[] ReadPixels(Bitmap b, out int stride) {
        Rectangle r = new Rectangle(0, 0, b.Width, b.Height);
        BitmapData d = b.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        stride = d.Stride;
        byte[] px = new byte[stride * b.Height];
        Marshal.Copy(d.Scan0, px, 0, px.Length);
        b.UnlockBits(d);
        return px;
    }

    static Bitmap FromPixels(byte[] px, int w, int h) {
        Bitmap o = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        Rectangle r = new Rectangle(0, 0, w, h);
        BitmapData d = o.LockBits(r, ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(px, 0, d.Scan0, px.Length);
        o.UnlockBits(d);
        return o;
    }

    // result = weightA * a + (1 - weightA) * b   (both bitmaps must be the same size)
    public static Bitmap Blend(Bitmap a, Bitmap b, double weightA) {
        if (a.Width != b.Width || a.Height != b.Height) throw new ArgumentException("size mismatch");
        int sa, sb;
        byte[] pa = ReadPixels(a, out sa);
        byte[] pb = ReadPixels(b, out sb);
        double wb = 1.0 - weightA;
        for (int i = 0; i < pa.Length; i++) {
            pa[i] = (byte)(pa[i] * weightA + pb[i] * wb + 0.5);
        }
        return FromPixels(pa, a.Width, a.Height);
    }

    // Soft luminance noise, like film grain. sigma is in 0-255 steps (3 = light, 10 = strong).
    public static Bitmap Grain(Bitmap src, double sigma) {
        int stride;
        byte[] p = ReadPixels(src, out stride);
        Random rnd = new Random();
        for (int i = 0; i + 3 < p.Length; i += 4) {
            double n = (rnd.NextDouble() + rnd.NextDouble() + rnd.NextDouble() - 1.5) * 2.0 * sigma;
            for (int c = 0; c < 3; c++) {
                double v = p[i + c] + n;
                if (v < 0) v = 0; if (v > 255) v = 255;
                p[i + c] = (byte)(v + 0.5);
            }
        }
        return FromPixels(p, src.Width, src.Height);
    }
}
"@
    } catch { $script:fxOk = $false }
}

$ImageExt = '\.(jpg|jpeg|png|bmp)$'
$VideoExt = '\.(mp4|webm|gif|mkv|mov|avi)$'
$SettingsPath = Join-Path $PSScriptRoot "settings.json"

# version shown in Settings > About, and the GitHub "owner/repo" the update check looks at
$script:AppVersion = '1.1.0'
$script:UpdateRepo = 'd0l0h/Ekk0h'
$script:nowPlaying = $null
$script:storeLively = $null
$script:physOn = $null
$script:raiseOverride = $null
$script:posOverride = $null
$script:mapFix = $null
$script:mapOffX = 0.0
$script:mapOffY = 0.0
$script:layoutDirty = $false
$script:mapRects = @{}
$script:mapScale = 1.0
$script:physLayout = $null
$script:edidSizes = $null
$script:dispSig = ''
$script:animThumbs = @{}
$script:currentPack = $null
$script:exiting = $false
$script:thumbCache = @{}
$script:lblStatus = $null
$script:lbPacks = $null

# ---------------------------------------------------------------- helpers
# short idle comments for the footer, so the footer art stays visible
$script:quips = @(
    'Does anyone read these?', 'Pixels, assemble.', 'Fresh pixels, still warm.', 'Shuffle responsibly.',
    'Your desktop called. Bored.', 'Now 100% more wallpaper.', 'Ctrl+Q when you are done.',
    'Have you tried more monitors?', 'Beep boop. Wallpaper.', 'Making walls less blank.',
    'Right-click a card. Go on.', 'Drag a picture in. It likes that.', 'Bezels: the final boss.',
    'Four monitors is a lifestyle.', 'Still faster than choosing one.', 'Try the Builder. Really.',
    'Pinned screens stay put.', 'This is the footer. Hi.', 'Ctrl+Alt+R feels lucky.',
    'Thirteen themes. Pick a side.'
)
$script:quipIdx = -1
$script:quipShown = $false
$script:statusAt = [Environment]::TickCount - 30000
function Show-Quip {
    if (-not $script:lblStatus) { return }
    $script:quipIdx = ($script:quipIdx + 1) % $script:quips.Count
    $txt = $script:quips[$script:quipIdx]
    # now and then, on Digital Rain only, a hint at the secret
    if ($script:themeHdr -eq 'matrix' -and $script:pillState -eq 0 -and (Get-Random -Maximum 6) -eq 0) {
        $txt = @('Three letters wake the one. Say them in order.', 'The One has a name. Spell it.', 'Not a word, not a prayer. Just three keys.', 'Who is the chosen one? Say it with your keyboard.')[(Get-Random -Maximum 4)]
    }
    $script:lblStatus.Text = $txt
    $script:quipShown = $true
    $script:statusAt = [Environment]::TickCount
}
function Set-Status([string]$msg) {
    $script:quipShown = $false
    $script:statusAt = [Environment]::TickCount
    if ($script:lblStatus) {
        $script:lblStatus.Text = $msg
        [System.Windows.Forms.Application]::DoEvents()
    } else {
        Write-Host $msg
    }
}

function Get-NaturalSorted($items) {
    $items | Sort-Object { [regex]::Replace($_.Name, '\d+', { param($m) $m.Value.PadLeft(8, '0') }) }
}

function Get-Packs {
    if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root | Out-Null }
    @(Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name)
}

function Get-PackImages([string]$dir) {
    @(Get-NaturalSorted @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $_.Extension -match $ImageExt }))
}

function Get-AnimatedFiles {
    if (-not (Test-Path -LiteralPath $AnimRoot)) { New-Item -ItemType Directory -Path $AnimRoot | Out-Null }
    @(Get-ChildItem -LiteralPath $AnimRoot -File | Where-Object { $_.Extension -match $VideoExt } | Sort-Object Name)
}

function Get-SafeName([string]$n) {
    $bad = [IO.Path]::GetInvalidFileNameChars()
    $clean = -join ($n.ToCharArray() | Where-Object { $bad -notcontains $_ })
    $clean.Trim()
}

function Get-NewPackDir([string]$name) {
    $name = Get-SafeName $name
    if (-not $name) { return $null }
    if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root | Out-Null }
    $dir = Join-Path $Root $name
    $n = 2
    while (Test-Path -LiteralPath $dir) { $dir = Join-Path $Root "$name $n"; $n++ }
    New-Item -ItemType Directory -Path $dir | Out-Null
    return $dir
}

function Read-ImageFromFile([string]$path) {
    # Loads into memory so the file is never locked.
    $bytes = [IO.File]::ReadAllBytes($path)
    $ms = New-Object IO.MemoryStream(, $bytes)
    $img = [System.Drawing.Image]::FromStream($ms)
    return @{ Image = $img; Stream = $ms }
}

function New-Thumb([string]$path, [int]$w, [int]$h) {
    try {
        $loaded = Read-ImageFromFile $path
        $img = $loaded.Image
        $bmp = New-Object System.Drawing.Bitmap($w, $h)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $scale = [math]::Max($w / $img.Width, $h / $img.Height)
        $sw = [float]($w / $scale); $sh = [float]($h / $scale)
        $sx = [float](($img.Width - $sw) / 2); $sy = [float](($img.Height - $sh) / 2)
        $dest = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
        $g.DrawImage($img, $dest, $sx, $sy, $sw, $sh, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose(); $img.Dispose(); $loaded.Stream.Dispose()
        return $bmp
    } catch { return $null }
}

# ---------------------------------------------------------------- Lively (animated)
# Small settings file (settings.json next to this script): Lively location, last
# "Play on" target and sound level.
function Get-Settings {
    $s = @{ LivelyPath = ""; AnimTarget = "All Monitors"; AnimSound = "Muted"; UpModel = "Auto Soft"; UpMix = "60%"; UpGrain = "Light"; PhysMatch = "1"; DispAlignMode = "Auto" }
    try {
        if (Test-Path -LiteralPath $SettingsPath) {
            $j = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) {
                if ($null -ne $p.Value -and "$($p.Value)" -ne "") { $s[$p.Name] = [string]$p.Value }
            }
        }
    } catch { }
    return $s
}

function Save-Setting([string]$key, [string]$value) {
    $s = Get-Settings
    $s[$key] = $value
    try { ($s | ConvertTo-Json) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8 } catch { }
}

function Remove-Setting([string]$key) {
    $s = Get-Settings
    if (-not $s.ContainsKey($key)) { return }
    $s.Remove($key)
    try { ($s | ConvertTo-Json) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8 } catch { }
}

function Get-LivelyPath {
    # 1) a location you picked with "Locate..."
    $saved = (Get-Settings).LivelyPath
    if ($saved -and (Test-Path -LiteralPath $saved)) { return $saved }
    # 2) the usual install spots
    $cands = @(
        "$env:LOCALAPPDATA\Programs\Lively Wallpaper\Lively.exe",
        "$env:ProgramFiles\Lively Wallpaper\Lively.exe",
        "${env:ProgramFiles(x86)}\Lively Wallpaper\Lively.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\Lively.exe"
    )
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    # 3) the uninstall registry entry (covers custom install folders)
    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($r in $roots) {
        try {
            foreach ($k in (Get-ChildItem -Path $r -ErrorAction Stop)) {
                $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
                if ($p -and $p.DisplayName -like 'Lively Wallpaper*' -and $p.InstallLocation) {
                    $c = Join-Path $p.InstallLocation 'Lively.exe'
                    if (Test-Path -LiteralPath $c) { return $c }
                }
            }
        } catch { }
    }
    # 4) Microsoft Store version: its launcher is an "app execution alias" on PATH
    $cmd = Get-Command Lively.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    if ($null -eq $script:storeLively) {
        $script:storeLively = ""
        try {
            $pkg = Get-AppxPackage -Name '*LivelyWallpaper*' -ErrorAction Stop | Select-Object -First 1
            if ($pkg) {
                # the Store version keeps its core program in a Build folder (the root holds only the UI)
                foreach ($rel in @('Build\Lively.exe', 'Lively.exe')) {
                    $c = Join-Path $pkg.InstallLocation $rel
                    if (Test-Path -LiteralPath $c) { $script:storeLively = $c; break }
                }
            }
        } catch { }
    }
    if ($script:storeLively) { return $script:storeLively }
    # 5) the separate command-line utility, if it's on PATH
    $cmd = Get-Command livelycu.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

# Sends one command to Lively (it hands it to the running app) and pauses briefly.
function Invoke-Lively([string[]]$argList, [int]$wait = 600) {
    $lively = Get-LivelyPath
    if (-not $lively) { return $false }
    Start-Process -FilePath $lively -ArgumentList $argList -WindowStyle Hidden
    Start-Sleep -Milliseconds $wait
    return $true
}

# ---- which number does Lively use for each screen? (its "--monitor" numbers don't follow Windows' DISPLAY numbers)
function Get-LivelyLogFile {
    $dirs = @()
    foreach ($p in @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA "Packages") -Filter "*LivelyWallpaper*" -Directory -ErrorAction SilentlyContinue)) {
        $dirs += (Join-Path $p.FullName "LocalCache\Local\Lively Wallpaper\logs")
    }
    $dirs += (Join-Path $env:LOCALAPPDATA "Lively Wallpaper\logs")
    $best = $null
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $f = Get-ChildItem -LiteralPath $d -Filter *.txt -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($f -and (-not $best -or $f.LastWriteTime -gt $best.LastWriteTime)) { $best = $f }
    }
    return $best
}

function Read-LogFrom([string]$path, [long]$offset) {
    try {
        $fs = New-Object System.IO.FileStream($path, 'Open', 'Read', 'ReadWrite')
        try {
            [void]$fs.Seek($offset, 'Begin')
            $sr = New-Object System.IO.StreamReader($fs)
            return $sr.ReadToEnd()
        } finally { $fs.Dispose() }
    } catch { return "" }
}

# Returns @{ WindowsDisplayNumber = LivelyScreenNumber }. Worked out once by sending a tiny picture to each Lively
# screen number and reading which monitor Lively says it used, then remembered until your monitors change.
function Get-LivelyMonitorMap {
    $sig = Get-DisplaySignature
    $saved = [string](Get-Settings).LivelyMap
    $map = @{}
    if ($saved -and $saved.StartsWith("$sig|")) {
        foreach ($pair in ($saved.Substring($sig.Length + 1) -split ',')) {
            if ($pair -match '^(\d+)=(\d+)$') { $map[[int]$Matches[1]] = [int]$Matches[2] }
        }
        if ($map.Count -gt 0) { return $map }
    }
    $log = Get-LivelyLogFile
    if (-not $log) { return @{} }
    $n = @(Get-DisplayList).Count
    $png = Join-Path ([IO.Path]::GetTempPath()) "wcc_probe.png"
    try {
        $bmp = New-Object System.Drawing.Bitmap 64, 64
        $gg = [System.Drawing.Graphics]::FromImage($bmp); $gg.Clear([System.Drawing.Color]::Black); $gg.Dispose()
        $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    } catch { return @{} }
    Set-Status "Checking how Lively numbers your screens (they flash black for a moment)..."
    for ($m = 1; $m -le $n; $m++) {
        [void](Invoke-Lively @("closewp", "--monitor", "-1") 500)
        $log = Get-LivelyLogFile
        $off = $log.Length
        [void](Invoke-Lively @("setwp", "--file", ('"{0}"' -f $png), "--monitor", "$m") 300)
        $k = $null
        for ($t = 0; $t -lt 20 -and -not $k; $t++) {
            Start-Sleep -Milliseconds 300
            [System.Windows.Forms.Application]::DoEvents()
            $mm = [regex]::Matches((Read-LogFrom $log.FullName $off), 'Sending wallpaper\(Screen\):\s*\\\\\.\\DISPLAY(\d+)')
            if ($mm.Count -gt 0) { $k = [int]$mm[$mm.Count - 1].Groups[1].Value }
        }
        if ($k) { $map[$k] = $m }
    }
    [void](Invoke-Lively @("closewp", "--monitor", "-1") 600)
    Remove-Item -LiteralPath $png -Force -ErrorAction SilentlyContinue
    if ($map.Count -eq $n) {
        Save-Setting "LivelyMap" ($sig + "|" + ((@($map.Keys | Sort-Object) | ForEach-Object { "$_=$($map[$_])" }) -join ","))
    }
    return $map
}

function ConvertTo-LivelyNum([int]$win, $map) {
    if ($map -and $map.ContainsKey($win)) { return [int]$map[$win] }
    return $win
}

function Test-LivelyRunning {
    return [bool](Get-Process -Name 'Lively' -ErrorAction SilentlyContinue)
}

function Stop-Animated([switch]$KeepPinned) {
    if (-not (Test-LivelyRunning)) { return }
    $pins = @()
    if ($KeepPinned) { $pins = @(Get-PinnedScreens) }
    if ($pins.Count -eq 0) {
        [void](Invoke-Lively @("closewp", "--monitor", "-1") 900)
        $script:nowPlaying = $null
    } else {
        $lmap = Get-LivelyMonitorMap
        foreach ($d in (Get-DisplayList)) {
            if ($pins -contains [int]$d.Index) { continue }
            if ($d.WinNum -gt 0) { $m = ConvertTo-LivelyNum $d.WinNum $lmap } else { $m = $d.Index }
            [void](Invoke-Lively @("closewp", "--monitor", "$m") 900)
        }
    }
    if ($script:lblNow) { Update-NowPlaying }
}

function Show-LivelyMissing {
    [void][System.Windows.Forms.MessageBox]::Show(
        "Lively Wallpaper wasn't found.`n`nInstall the free Lively Wallpaper app (use the Get Lively button) and open it once. If it's already installed, use the Locate button to point at Lively.exe.",
        "Lively not found", 'OK', 'Information')
}

function Get-SoundLevel {
    $choice = "Muted"
    if ($script:cmbSound -and $script:cmbSound.SelectedItem) { $choice = [string]$script:cmbSound.SelectedItem }
    switch ($choice) {
        "Quiet"  { return 20 }
        "Medium" { return 50 }
        "Loud"   { return 100 }
        default  { return 0 }
    }
}

# ---------------------------------------------------------------- video cuts (one video lined up across your screens)
function Find-Ffmpeg {
    $sp = [string](Get-Settings).FfmpegPath
    if ($sp -and (Test-Path -LiteralPath $sp)) { return $sp }
    foreach ($c in @((Join-Path $PSScriptRoot "Tools\ffmpeg\ffmpeg.exe"), (Join-Path $PSScriptRoot "Tools\ffmpeg.exe"), (Join-Path $PSScriptRoot "Tools\ffmpeg\bin\ffmpeg.exe"))) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    # an unzipped release build usually sits in its own folder, e.g. Tools\ffmpeg\ffmpeg-8.0-essentials_build\bin
    try {
        foreach ($d in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "Tools") -Directory -ErrorAction SilentlyContinue)) {
            foreach ($sd in @(Get-ChildItem -LiteralPath $d.FullName -Directory -ErrorAction SilentlyContinue)) {
                $c2 = Join-Path (Join-Path $sd.FullName "bin") "ffmpeg.exe"
                if (Test-Path -LiteralPath $c2) { return $c2 }
            }
        }
    } catch { }
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    try {
        $lv = Get-LivelyPath
        if ($lv) {
            $f = Get-ChildItem -LiteralPath (Split-Path $lv -Parent) -Filter ffmpeg.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($f) { return $f.FullName }
        }
    } catch { }
    return $null
}

function Show-FfmpegMissing {
    $tdir0 = Join-Path $PSScriptRoot "Tools\ffmpeg"
    $srcNote = ""
    if ((Test-Path -LiteralPath (Join-Path $tdir0 "libavcodec")) -or (Test-Path -LiteralPath (Join-Path $tdir0 "configure"))) {
        $srcNote = "`n`nThe Tools\ffmpeg folder holds ffmpeg's SOURCE CODE, which can't be used. You need the ready-made program (ffmpeg.exe) instead."
    }
    $a = [System.Windows.Forms.MessageBox]::Show(
        "Cutting a video needs a free tool called ffmpeg, and ffmpeg.exe wasn't found.$srcNote`n`n1. Download 'ffmpeg-release-essentials.zip' from gyan.dev.`n2. Unzip it and copy ffmpeg.exe (from its bin folder) into the Tools\ffmpeg folder next to this app.`n`nOpen the download page and that folder now?",
        "ffmpeg needed", 'YesNo', 'Information')
    if ($a -eq 'Yes') {
        $tdir = Join-Path $PSScriptRoot "Tools\ffmpeg"
        if (-not (Test-Path -LiteralPath $tdir)) { New-Item -ItemType Directory -Path $tdir -Force | Out-Null }
        Start-Process explorer.exe -ArgumentList ('"' + $tdir + '"')
        Start-Process "https://www.gyan.dev/ffmpeg/builds/"
    }
}

function Get-VideoCutDir([string]$file) {
    return (Join-Path (Join-Path $AnimRoot "_cuts") ([IO.Path]::GetFileNameWithoutExtension($file)))
}

function Start-AnimatedCut([string]$cutDir) {
    if (-not (Get-LivelyPath)) { Show-LivelyMissing; return $false }
    $name = Split-Path $cutDir -Leaf
    $script:form.Cursor = 'WaitCursor'
    try {
        if (-not (Test-LivelyRunning)) {
            Set-Status "Starting Lively..."
            [void](Invoke-Lively @("app", "--showApp", "false") 4000)
        }
        [void](Invoke-Lively @("app", "--volume", "$(Get-SoundLevel)") 300)
        [void](Invoke-Lively @("app", "--layout", "per") 500)
        $lmap = Get-LivelyMonitorMap
        foreach ($d in (Get-DisplayList)) {
            $f = Join-Path $cutDir ("screen{0}.mp4" -f $d.Index)
            if (-not (Test-Path -LiteralPath $f)) { continue }
            if ($d.WinNum -gt 0) { $m = ConvertTo-LivelyNum $d.WinNum $lmap } else { $m = $d.Index }
            Set-Status "Starting $name on screen $($d.Index)..."
            [void](Invoke-Lively @("setwp", "--file", "`"$f`"", "--monitor", "$m") 1500)
        }
        $script:nowPlaying = "$name (cut to your screens)"
        Update-NowPlaying
        Set-Status "Animated: $name, cut across your screens."
    } finally {
        $script:form.Cursor = 'Default'
    }
    return $true
}

# Cuts a video to your screens' real layout (one video file per screen) and plays it.
# With $reposition (or no cut yet) it asks where to put the screens over the video first.
function Invoke-VideoCut([string]$file, [bool]$reposition) {
    $ff = Find-Ffmpeg
    if (-not $ff) { Show-FfmpegMissing; return $false }
    $cutDir = Get-VideoCutDir $file
    $cj = Join-Path $cutDir "cut.json"
    $have = ((Test-Path -LiteralPath $cj) -and (@(Get-ChildItem -LiteralPath $cutDir -Filter "screen*.mp4" -ErrorAction SilentlyContinue).Count -gt 0))
    if ($have -and -not $reposition) { return (Start-AnimatedCut $cutDir) }
    $state = $null
    if (Test-Path -LiteralPath $cj) { try { $state = Get-Content -LiteralPath $cj -Raw | ConvertFrom-Json } catch { } }

    $frame = Join-Path ([IO.Path]::GetTempPath()) ("wcc_frame_{0}.png" -f ([guid]::NewGuid().ToString("N")))
    $script:form.Cursor = 'WaitCursor'
    Set-Status "Reading a picture from the video..."
    try {
        [void](Start-Process -FilePath $ff -ArgumentList @("-y", "-ss", "1", "-i", ('"{0}"' -f $file), "-frames:v", "1", ('"{0}"' -f $frame)) -WindowStyle Hidden -Wait)
        if (-not (Test-Path -LiteralPath $frame)) {
            [void](Start-Process -FilePath $ff -ArgumentList @("-y", "-i", ('"{0}"' -f $file), "-frames:v", "1", ('"{0}"' -f $frame)) -WindowStyle Hidden -Wait)
        }
    } finally { $script:form.Cursor = 'Default' }
    if (-not (Test-Path -LiteralPath $frame)) { Set-Status "Couldn't read a picture from that video."; return $false }

    $lay = Get-PhysicalLayout
    $sub = Get-SubLayout $lay @($lay.Items | ForEach-Object { $_.Index })
    $ld = Read-ImageFromFile $frame
    $vw = $ld.Image.Width; $vh = $ld.Image.Height
    $init = $null
    if ($state) { $init = @{ Zoom = [double]$state.zoom; Cx = [double]$state.cx; Cy = [double]$state.cy } }
    $cut = Show-Cutter $ld.Image $sub $init "Position your screens on the video" "Cut" $script:form
    $ld.Image.Dispose(); $ld.Stream.Dispose()
    Remove-Item -LiteralPath $frame -Force -ErrorAction SilentlyContinue
    if (-not $cut) { Set-Status "Cancelled."; return $false }

    $box = Get-CutBox $sub $vw $vh @{ zoom = $cut.Zoom; cx = $cut.CxF; cy = $cut.CyF }
    Stop-Animated
    New-Item -ItemType Directory -Path $cutDir -Force | Out-Null
    foreach ($old in @(Get-ChildItem -LiteralPath $cutDir -Filter "screen*.mp4" -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $old.FullName -Force -ErrorAction SilentlyContinue }
    $script:form.Cursor = 'WaitCursor'
    try {
        $first = $true
        $done = 0
        $total = $sub.Items.Count
        foreach ($it in $sub.Items) {
            $done++
            $cw = [int][math]::Max(2, [math]::Round($it.PW * $box.K))
            $chh = [int][math]::Max(2, [math]::Round($it.PH * $box.K))
            $cx = [int][math]::Max(0, [math]::Round($box.X + $it.L * $box.K))
            $cy = [int][math]::Max(0, [math]::Round($box.Y + ($it.T - $sub.MinY) * $box.K))
            if ($cx + $cw -gt $vw) { $cw = $vw - $cx }
            if ($cy + $chh -gt $vh) { $chh = $vh - $cy }
            $out = Join-Path $cutDir ("screen{0}.mp4" -f $it.Index)
            $vf = "crop={0}:{1}:{2}:{3},scale={4}:{5}:flags=lanczos,setsar=1" -f $cw, $chh, $cx, $cy, $it.D.EW, $it.D.EH
            if ($it.D.Turn -gt 0) { $vf += "," + (Get-TurnVf $it.D.Turn) }
            $args2 = @("-y", "-i", ('"{0}"' -f $file), "-vf", ('"{0}"' -f $vf)) + (Get-VideoEncArgs)
            if ($first) { $args2 += @("-c:a", "aac", "-b:a", "160k") } else { $args2 += @("-an") }
            $args2 += @("-movflags", "+faststart", ('"{0}"' -f $out))
            Set-Status "Cutting screen $done of $total (long videos take a while)..."
            [System.Windows.Forms.Application]::DoEvents()
            $p = Start-Process -FilePath $ff -ArgumentList $args2 -WindowStyle Hidden -Wait -PassThru
            if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $out)) { Set-Status "ffmpeg couldn't cut screen $($it.Index)."; return $false }
            $first = $false
        }
        $info = @{ source = [IO.Path]::GetFileName($file); zoom = $cut.Zoom; cx = $cut.CxF; cy = $cut.CyF }
        ($info | ConvertTo-Json) | Set-Content -LiteralPath $cj -Encoding UTF8
    } finally {
        $script:form.Cursor = 'Default'
    }
    return (Start-AnimatedCut $cutDir)
}

function Start-Animated([string]$file, [string]$target) {
    if (-not (Get-LivelyPath)) { Show-LivelyMissing; return }
    if ($target -like 'Cut*') { [void](Invoke-VideoCut $file $false); return }
    $name = [IO.Path]::GetFileName($file)
    $script:form.Cursor = 'WaitCursor'
    try {
        if (-not (Test-LivelyRunning)) {
            Set-Status "Starting Lively..."
            [void](Invoke-Lively @("app", "--showApp", "false") 4000)
        }
        [void](Invoke-Lively @("app", "--volume", "$(Get-SoundLevel)") 300)

        if ($target -like 'Span*') {
            Set-Status "Spanning $name across all monitors..."
            [void](Invoke-Lively @("app", "--layout", "span") 500)
            [void](Invoke-Lively @("setwp", "--file", "`"$file`"") 1500)
        } else {
            [void](Invoke-Lively @("app", "--layout", "per") 500)
            $lmap = Get-LivelyMonitorMap
            $pick = [regex]::Match($target, '^Display (\d+)')
            if ($pick.Success) {
                $targets = @(ConvertTo-LivelyNum ([int]$pick.Groups[1].Value) $lmap)
            } else {
                $targets = @(Get-DisplayList | ForEach-Object { if ($_.WinNum -gt 0) { ConvertTo-LivelyNum $_.WinNum $lmap } else { $_.Index } })
            }
            foreach ($m in $targets) {
                Set-Status "Starting $name on monitor $m..."
                [void](Invoke-Lively @("setwp", "--file", "`"$file`"", "--monitor", "$m") 1500)
            }
        }
        $script:nowPlaying = $name
        Update-NowPlaying
        Set-Status "Animated: $name"
    } finally {
        $script:form.Cursor = 'Default'
    }
}

function Get-AnimTarget {
    if ($script:cmbMon -and $script:cmbMon.SelectedItem) { return [string]$script:cmbMon.SelectedItem }
    return "All Monitors"
}

function Add-AnimFiles([string[]]$paths) {
    if (-not (Test-Path -LiteralPath $AnimRoot)) { New-Item -ItemType Directory -Path $AnimRoot | Out-Null }
    $added = 0; $skipped = 0
    foreach ($f in $paths) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf) -or ([IO.Path]::GetExtension($f) -notmatch $VideoExt)) { $skipped++; continue }
        $dest = Join-Path $AnimRoot ([IO.Path]::GetFileName($f))
        if (Test-Path -LiteralPath $dest) { $skipped++; continue }
        Set-Status "Copying $([IO.Path]::GetFileName($f))..."
        Copy-Item -LiteralPath $f -Destination $dest
        $added++
    }
    Update-AnimList
    $msg = "Added $added video(s)."
    if ($skipped -gt 0) { $msg += " Skipped $skipped (not a video, or already in the folder)." }
    Set-Status $msg
}

function Remove-SelectedAnim {
    $name = $script:lbAnim.SelectedItem
    if (-not $name) { Set-Status "Pick a video to remove first."; return }
    $ok = [System.Windows.Forms.MessageBox]::Show(
        "Move '$name' to the Recycle Bin?`n`nThis only removes it from the Animated folder. Lively keeps its own imported copy.",
        "Remove video", 'YesNo', 'Warning')
    if ($ok -ne 'Yes') { return }
    try {
        $idx = $script:lbAnim.SelectedIndex
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile((Join-Path $AnimRoot $name), 'OnlyErrorDialogs', 'SendToRecycleBin')
        $script:animThumbs = @{}
        Update-AnimList
        if ($script:lbAnim.Items.Count -gt 0) { $script:lbAnim.SelectedIndex = [math]::Min($idx, $script:lbAnim.Items.Count - 1) }
        Set-Status "Moved '$name' to the Recycle Bin."
    } catch {
        Set-Status "Couldn't remove: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- applying packs
# ---------------------------------------------------------------- pinned screens (left alone when a pack is applied)
function Get-PinnedScreens {
    $st = Get-Settings
    if ([string]$st.PinOn -ne '1') { return @() }
    $n = @(Get-DisplayList).Count
    $out = @()
    foreach ($t in ([string]$st.PinScreens -split ',')) {
        $v = 0
        if ([int]::TryParse($t.Trim(), [ref]$v) -and $v -ge 1 -and $v -le $n -and $out -notcontains $v) { $out += $v }
    }
    return $out
}

function Set-Pack([string]$dir) {
    try {
        $images = @(Get-PackImages $dir)
        if ($images.Count -eq 0) { Set-Status "No images in that pack."; return $false }

        $pins = @(Get-PinnedScreens)
        $count = @(Get-DisplayList).Count
        if ($pins.Count -gt 0 -and $pins.Count -ge $count) {
            Set-Status "Every screen is pinned, so nothing changed. Unpin a screen first."
            return $false
        }
        $skip = New-Object 'bool[]' ([math]::Max(1, $count))
        foreach ($p in $pins) { if ($p -ge 1 -and $p -le $skip.Length) { $skip[$p - 1] = $true } }

        Stop-Animated -KeepPinned

        $paths = [string[]]@($images | ForEach-Object { $_.FullName })
        [void][WallpaperHelper]::Apply($paths, $skip)
        $script:currentPack = Split-Path $dir -Leaf
        try { Save-Setting 'LastPack' $script:currentPack } catch { }
        if ($pins.Count -gt 0) { Set-Status "Applied: $($script:currentPack) (pinned: $($pins -join ', ') kept)" }
        else { Set-Status "Applied: $($script:currentPack)" }
        try { Update-WallpaperTheme } catch { }
        if ($script:gridCanvas) { $script:gridCanvas.Invalidate() }
        try { Start-PackVideos $dir } catch { Set-Status "Applied, but the video part failed: $($_.Exception.Message)" }
        try { Update-PackLock $script:currentPack } catch { }
        return $true
    } catch {
        Set-Status "Couldn't apply: $($_.Exception.Message)"
        return $false
    }
}

# what auto-shuffle may pick from: tokens 'fav' and 'tag:name' (empty = every pack)
function Get-ShuffleSources {
    $st = Get-Settings
    $out = @()
    foreach ($t in ([string]$st.ShuffleSrc -split '\|')) { if ($t.Trim()) { $out += $t.Trim() } }
    if ($out.Count -eq 0 -and [string]$st.ShuffleFav -eq '1') { $out = @('fav') }
    return $out
}

function Invoke-RandomPack([switch]$Auto) {
    $packs = @(Get-Packs | Where-Object { @(Get-PackImages $_.FullName).Count -gt 0 })
    if ($packs.Count -eq 0) { Set-Status "No packs with images yet."; return }
    if ($Auto) {
        $src = @(Get-ShuffleSources)
        if ($src.Count -gt 0) {
            $packs = @($packs | Where-Object {
                $m = Get-PackMetaFor $_.Name
                $ok = ($src -contains 'fav' -and $m.fav)
                if (-not $ok) { foreach ($t in @($m.tags)) { if ($src -contains ('tag:' + $t)) { $ok = $true; break } } }
                $ok
            })
            if ($packs.Count -eq 0) { Set-Status "Auto-shuffle has nothing to pick: no packs match your Shuffle from choices."; return }
        }
    }
    $choices = @($packs | Where-Object { $_.Name -ne $script:currentPack })
    if ($choices.Count -eq 0) { $choices = $packs }
    $pick = $choices | Get-Random
    if (Set-Pack $pick.FullName) {
        if ($script:lbPacks -and $script:lbPacks.Items.Contains($pick.Name)) { $script:lbPacks.SelectedItem = $pick.Name }
    }
}

if ($Random) { Invoke-RandomPack; return }

# ---------------------------------------------------------------- adding / fixing packs

function Remove-SelectedPack {
    $name = $script:lbPacks.SelectedItem
    if (-not $name) { Set-Status "Pick a pack to delete first."; return }
    $ok = [System.Windows.Forms.MessageBox]::Show(
        "Move the pack '$name' to the Recycle Bin?`n`nYou can restore it from the Recycle Bin if you change your mind.",
        "Delete pack", 'YesNo', 'Warning')
    if ($ok -ne 'Yes') { return }
    try {
        $idx = $script:lbPacks.SelectedIndex
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory((Join-Path $Root $name), 'OnlyErrorDialogs', 'SendToRecycleBin')
        if ($script:currentPack -eq $name) { $script:currentPack = $null }
        $script:thumbCache = @{}
        Update-PackList $null
        if ($script:lbPacks.Items.Count -gt 0) {
            $script:lbPacks.SelectedIndex = [math]::Min($idx, $script:lbPacks.Items.Count - 1)
        }
        Set-Status "Moved '$name' to the Recycle Bin."
    } catch {
        Set-Status "Couldn't delete: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- AI upscaling (Real-ESRGAN)
$ToolsRoot = Join-Path $PSScriptRoot "Tools"

function Find-Upscaler {
    $sp = [string](Get-Settings).UpscalerPath
    if ($sp -and (Test-Path -LiteralPath $sp)) { return $sp }
    if (-not (Test-Path -LiteralPath $ToolsRoot)) { return $null }
    $exe = Get-ChildItem -LiteralPath $ToolsRoot -Filter "realesrgan-ncnn-vulkan.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) { return $exe.FullName }
    return $null
}

function Confirm-Upscaler {
    $exe = Find-Upscaler
    if ($exe) { return $exe }
    $dir = Join-Path $ToolsRoot "realesrgan"
    $ok = [System.Windows.Forms.MessageBox]::Show(
        "The free Real-ESRGAN upscaler isn't set up yet.`n`nClick Yes to open its download (a zip file) and the folder where it goes. Extract the zip's contents into that folder, then click the upscale button again.`n`nIt needs a GPU with Vulkan support (nearly all recent NVIDIA, AMD and Intel GPUs have it).",
        "Set up the upscaler", 'YesNo', 'Information')
    if ($ok -eq 'Yes') {
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Start-Process explorer.exe -ArgumentList "`"$dir`""
        Start-Process "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip"
    }
    return $null
}


# ---------------------------------------------------------------- optional add-ons (extra programs the app can use)
# ffmpeg = video cuts, upscale = Real-ESRGAN AI upscaler, lively = animated wallpapers.
# Features that need one stay hidden until it is found (and switched on in Settings > Add-ons).
$script:addonCache = @{}
function Clear-AddonCache { $script:addonCache = @{} }
function Get-AddonInfo([string]$id) {
    if ($script:addonCache.ContainsKey($id)) { return $script:addonCache[$id] }
    $path = $null; $ok = $false; $detail = ''
    try {
        switch ($id) {
            'ffmpeg' {
                $path = Find-Ffmpeg
                if ($path) {
                    try {
                        $psi = New-Object System.Diagnostics.ProcessStartInfo -ArgumentList $path, '-version'
                        $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.CreateNoWindow = $true
                        $p = [System.Diagnostics.Process]::Start($psi)
                        $line = [string]$p.StandardOutput.ReadLine()
                        [void]$p.WaitForExit(4000)
                        if ($line -match 'ffmpeg version\s+(\S+)') { $ok = $true; $detail = $Matches[1] }
                    } catch { }
                }
            }
            'upscale' {
                $path = Find-Upscaler
                if ($path) {
                    $md = Join-Path (Split-Path $path -Parent) 'models'
                    if ((Test-Path -LiteralPath $md) -and @(Get-ChildItem -LiteralPath $md -Filter *.param -ErrorAction SilentlyContinue).Count -gt 0) { $ok = $true; $detail = 'models found' }
                    else { $detail = 'models folder missing' }
                }
            }
            'lively' {
                $path = Get-LivelyPath
                if ($path) { $ok = $true }
            }
        }
    } catch { }
    $r = [pscustomobject]@{ Id = $id; Path = $path; Found = [bool]$path; Ok = $ok; Detail = $detail }
    $script:addonCache[$id] = $r
    return $r
}
# found, working and not switched off in Settings
function Test-AddonOn([string]$id) {
    if ([string](Get-Settings)["AddonOff_$id"] -eq '1') { return $false }
    return [bool](Get-AddonInfo $id).Ok
}

# Downloads and unpacks ffmpeg or the upscaler into Tools\. $report gets short progress text.
function Install-Addon([string]$id, [scriptblock]$report) {
    $urls = @{
        ffmpeg  = 'https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip'
        upscale = 'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesrgan-ncnn-vulkan-20220424-windows.zip'
    }
    $dests = @{ ffmpeg = (Join-Path $ToolsRoot 'ffmpeg'); upscale = (Join-Path $ToolsRoot 'realesrgan') }
    if (-not $urls.ContainsKey($id)) { return "Nothing to download for this one." }
    $zip = Join-Path ([IO.Path]::GetTempPath()) ("ekk0h_{0}.zip" -f $id)
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
        $script:dlDone = $false; $script:dlErr = $null; $script:dlPct = 0
        $wc = New-Object System.Net.WebClient
        $wc.Add_DownloadProgressChanged({ param($s, $e) $script:dlPct = $e.ProgressPercentage })
        $wc.Add_DownloadFileCompleted({ param($s, $e) if ($e.Error) { $script:dlErr = $e.Error.Message }; $script:dlDone = $true })
        $wc.DownloadFileAsync([Uri]$urls[$id], $zip)
        while (-not $script:dlDone) {
            & $report ("Downloading " + $script:dlPct + "%")
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 60
        }
        $wc.Dispose()
        if ($script:dlErr) { return "Download failed: " + $script:dlErr }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $dest = $dests[$id]
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $root = [IO.Path]::GetFullPath($dest).TrimEnd('\') + '\'
        $za = [IO.Compression.ZipFile]::OpenRead($zip)
        try {
            $n = $za.Entries.Count; $i = 0
            foreach ($en in $za.Entries) {
                $i++
                $target = [IO.Path]::GetFullPath((Join-Path $dest $en.FullName))
                if (-not $target.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }
                if ($en.FullName.EndsWith('/')) { New-Item -ItemType Directory -Path $target -Force | Out-Null; continue }
                New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($en, $target, $true)
                if ($i % 15 -eq 0) { & $report ("Unpacking " + [int](100 * $i / $n) + "%"); [System.Windows.Forms.Application]::DoEvents() }
            }
        } finally { $za.Dispose() }
        return $null
    } catch {
        return "Couldn't install: " + $_.Exception.Message
    } finally {
        try { if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force } } catch { }
    }
}

# Every connected display, left to right (the order packs are applied in).
# A screen that is physically turned (e.g. a monitor standing on its side) while Windows still
# shows it as landscape. Turn = quarter-turns clockwise (0-3). The layout and cuts treat the
# screen as turned, and each piece is rotated back so it looks right on the real monitor.
function Set-ScreenTurn([string]$device, [int]$turn) {
    Save-Setting ("Turn_" + ($device -replace '[^A-Za-z0-9]', '')) ([string]$turn)
}
function Get-TurnVf([int]$turn) {
    switch ($turn) { 1 { return "transpose=2" } 2 { return "hflip,vflip" } 3 { return "transpose=1" } default { return "" } }
}
function Rotate-ForTurn($bmp, [int]$turn) {
    switch ($turn) {
        1 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
        2 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
        3 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
    }
}

function Get-DisplayList {
    $screens = @([System.Windows.Forms.Screen]::AllScreens | Sort-Object { $_.Bounds.X }, { $_.Bounds.Y })
    $list = @()
    $setNow = Get-Settings
    for ($i = 0; $i -lt $screens.Count; $i++) {
        $sc = $screens[$i]
        $turn = 0
        $tv = $setNow[("Turn_" + (($sc.DeviceName) -replace '[^A-Za-z0-9]', ''))]
        if ($tv -match '^[0-3]$') { $turn = [int]$tv }
        $rw = [int]$sc.Bounds.Width; $rh = [int]$sc.Bounds.Height
        if ($turn % 2 -eq 1) { $ew = $rh; $eh = $rw } else { $ew = $rw; $eh = $rh }
        $num = 0
        if ($sc.DeviceName -match 'DISPLAY(\d+)') { $num = [int]$Matches[1] }
        $list += [pscustomobject]@{
            Index   = $i + 1
            WinNum  = $num
            Device  = $sc.DeviceName
            X       = [int]$sc.Bounds.X
            Y       = [int]$sc.Bounds.Y
            W       = [int]$sc.Bounds.Width
            H       = [int]$sc.Bounds.Height
            Primary = [bool]$sc.Primary
            Turn    = $turn
            EW      = $ew
            EH      = $eh
        }
    }
    return $list
}

# ---------------------------------------------------------------- physical screen sizes
# Used to line a picture up across bezels and across screens of different sizes.
function Get-DisplayKey($d) {
    return ("Disp_" + ((("{0}_{1}x{2}" -f $d.Device, $d.W, $d.H)) -replace '[^A-Za-z0-9]', ''))
}

# Panel sizes as reported by the monitors themselves (EDID), in centimetres.
function Get-DetectedSizes {
    if ($null -ne $script:edidSizes) { return $script:edidSizes }
    $list = @()
    try {
        foreach ($m in @(Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBasicDisplayParams -ErrorAction Stop)) {
            $wc = [double]$m.MaxHorizontalImageSize
            $hc = [double]$m.MaxVerticalImageSize
            $key = ([string]$m.InstanceName) -replace '_\d+$', ''
            # the first detailed timing in the monitor's EDID gives the size in millimetres (whole cm is too coarse)
            try {
                $reg = "HKLM:\SYSTEM\CurrentControlSet\Enum\$key\Device Parameters"
                $edid = [byte[]](Get-ItemProperty -LiteralPath $reg -Name EDID -ErrorAction Stop).EDID
                if ($edid.Count -ge 69 -and ($edid[54] -ne 0 -or $edid[55] -ne 0)) {
                    $wmm = $edid[66] + (($edid[68] -shr 4) * 256)
                    $hmm = $edid[67] + (($edid[68] -band 15) * 256)
                    if ($wmm -gt 50 -and $hmm -gt 30) { $wc = $wmm / 10.0; $hc = $hmm / 10.0 }
                }
            } catch { }
            if ($wc -gt 3 -and $hc -gt 3) { $list += [pscustomobject]@{ WCm = $wc; HCm = $hc; Key = $key; Used = $false } }
        }
    } catch { }
    $script:edidSizes = $list
    return $list
}

# Best guess at each screen's diagonal (inches), matching monitors to screens by shape.
function Get-DetectedDiagonals($ds) {
    $res = @{}
    $pool = @(Get-DetectedSizes)
    foreach ($e in $pool) { $e.Used = $false }

    # 1) exact: which monitor is plugged into which screen
    $byDev = @{}
    if ($script:monMapOk) {
        try {
            foreach ($pair in [MonitorMap]::Pairs()) {
                $bits = $pair -split '\|', 2
                if ($bits.Count -lt 2) { continue }
                $id = ($bits[1] -replace '^\\\\\?\\', '') -replace '#', '\'
                $cut = $id.IndexOf('\{')
                if ($cut -gt 0) { $id = $id.Substring(0, $cut) }
                if (-not $byDev.ContainsKey($bits[0])) { $byDev[$bits[0]] = $id }
            }
        } catch { }
    }
    foreach ($d in $ds) {
        if (-not $byDev.ContainsKey($d.Device)) { continue }
        foreach ($e in $pool) {
            if ($e.Used) { continue }
            if ($e.Key -ieq $byDev[$d.Device]) {
                $e.Used = $true
                $res[$d.Index] = [math]::Round([math]::Sqrt($e.WCm * $e.WCm + $e.HCm * $e.HCm) / 2.54, 1)
                break
            }
        }
    }

    # 2) anything left: closest shape
    foreach ($d in $ds) {
        if ($res.ContainsKey($d.Index)) { continue }
        $a = $d.W / [double]$d.H
        $best = $null
        $bestDiff = 1000.0
        foreach ($e in $pool) {
            if ($e.Used) { continue }
            $diff = [math]::Abs(($e.WCm / $e.HCm) - $a)
            if ($diff -lt $bestDiff) { $bestDiff = $diff; $best = $e }
        }
        if ($best -and $bestDiff -lt 0.12) {
            $best.Used = $true
            $res[$d.Index] = [math]::Round([math]::Sqrt($best.WCm * $best.WCm + $best.HCm * $best.HCm) / 2.54, 1)
        }
    }
    return $res
}

function Get-DefaultDiagonal($d) {
    if ($d.W -ge 3000) { return 32.0 }
    if ($d.W -ge 2400) { return 27.0 }
    return 24.0
}

function Get-DisplayPhysical($d, $detected) {
    $saved = (Get-Settings)[(Get-DisplayKey $d)]
    if ($saved) {
        $parts = ([string]$saved) -split '\|'
        if ($parts.Count -ge 3) {
            $inv = [Globalization.CultureInfo]::InvariantCulture
            return @{
                Diag  = [double]::Parse($parts[0], $inv)
                Bezel = [double]::Parse($parts[1], $inv)
                Raise = [double]::Parse($parts[2], $inv)
                Auto  = $false
            }
        }
    }
    if ($detected.ContainsKey($d.Index)) { $diag = $detected[$d.Index]; $auto = $true }
    else { $diag = Get-DefaultDiagonal $d; $auto = $false }
    return @{ Diag = [double]$diag; Bezel = 7.0; Raise = 0.0; Auto = $auto }
}

function Save-DisplayPhysical($d, [double]$diag, [double]$bezel, [double]$raise) {
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $v = "{0}|{1}|{2}" -f $diag.ToString($inv), $bezel.ToString($inv), $raise.ToString($inv)
    Save-Setting (Get-DisplayKey $d) $v
}

function Get-PosKey($d) { return ("Pos_" + ((("{0}_{1}x{2}" -f $d.Device, $d.W, $d.H)) -replace '[^A-Za-z0-9]', '')) }

# Positions you dragged and saved (mm). Only used when every screen has one.
function Get-SavedPositions($ds) {
    $set = Get-Settings
    $res = @{}
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($d in $ds) {
        $v = $set[(Get-PosKey $d)]
        if (-not $v) { return $null }
        $parts = ([string]$v) -split '\|'
        if ($parts.Count -lt 2) { return $null }
        $res[$d.Index] = @{ L = [double]::Parse($parts[0], $inv); T = [double]::Parse($parts[1], $inv) }
    }
    return $res
}

function Save-LayoutPositions {
    $lay = Get-PhysicalLayout
    $inv = [Globalization.CultureInfo]::InvariantCulture
    foreach ($it in $lay.Items) {
        Save-Setting (Get-PosKey $it.D) ("{0}|{1}" -f ([double]$it.L).ToString($inv), ([double]$it.T).ToString($inv))
    }
    $script:posOverride = $null
    $script:layoutDirty = $false
    Reset-PhysLayout
}

function Clear-LayoutPositions {
    foreach ($d in (Get-DisplayList)) { Save-Setting (Get-PosKey $d) "" }
    $script:posOverride = $null
    $script:layoutDirty = $false
    Reset-PhysLayout
}

function Undo-LayoutChanges {
    $script:posOverride = $null
    $script:layoutDirty = $false
    Reset-PhysLayout
}

function Reset-PhysLayout { $script:physLayout = $null }

function Test-PhysMatch {
    if ($null -eq $script:physOn) { $script:physOn = ((Get-Settings).PhysMatch -ne "0") }
    return $script:physOn
}

function Set-PhysMatch([bool]$on) {
    $script:physOn = $on
    $script:physLayout = $null
    if ($on) { $v = "1" } else { $v = "0" }
    Save-Setting "PhysMatch" $v
}

# Lays your screens out in millimetres, left to right, with the bezels as gaps between them.
# Everything a slice needs comes from this: where each screen sits and how big it really is.
function Get-PhysicalLayout {
    if ($script:physLayout) { return $script:physLayout }
    $ds = @(Get-DisplayList)

    if (-not (Test-PhysMatch)) {
        # plain pixel layout, exactly as Windows has it
        $minX = ($ds | Measure-Object -Property X -Minimum).Minimum
        $minY0 = ($ds | Measure-Object -Property Y -Minimum).Minimum
        $pitems = @()
        foreach ($d in $ds) {
            $pitems += [pscustomobject]@{ Index = $d.Index; D = $d; L = [double]($d.X - $minX); T = [double]($d.Y - $minY0); PW = [double]$d.EW; PH = [double]$d.EH; Diag = 0.0; Bezel = 0.0; Raise = 0.0; Auto = $false }
        }
        $pr = ($pitems | ForEach-Object { $_.L + $_.PW } | Measure-Object -Maximum).Maximum
        $pb = ($pitems | ForEach-Object { $_.T + $_.PH } | Measure-Object -Maximum).Maximum
        $script:physLayout = @{ Items = $pitems; BW = [double]$pr; BH = [double]$pb; MinL = 0.0; MinY = 0.0; Ppm = 1.0 }
        return $script:physLayout
    }

    $detected = Get-DetectedDiagonals $ds
    $align = (Get-Settings).DispAlignMode
    $info = @{}
    foreach ($d in $ds) {
        $p = Get-DisplayPhysical $d $detected
        if ($script:raiseOverride -and $script:raiseOverride.ContainsKey($d.Index)) { $p.Raise = [double]$script:raiseOverride[$d.Index] }
        $a = $d.EW / [double]$d.EH
        $ph = $p.Diag * 25.4 / [math]::Sqrt(1.0 + $a * $a)
        $info[$d.Index] = @{ P = $p; PH = $ph; PW = ($ph * $a) }
    }

    # screens that sit over each other in Windows share a column
    $cols = @()
    foreach ($d in $ds) {
        $placed = $false
        foreach ($c in $cols) {
            $ov = [math]::Min($c.MaxX, $d.X + $d.W) - [math]::Max($c.MinX, $d.X)
            if ($ov -gt 0.5 * [math]::Min(($c.MaxX - $c.MinX), $d.W)) {
                $c.Members += $d
                $c.MinX = [math]::Min($c.MinX, $d.X)
                $c.MaxX = [math]::Max($c.MaxX, $d.X + $d.W)
                $placed = $true
                break
            }
        }
        if (-not $placed) { $cols += @{ Members = @($d); MinX = $d.X; MaxX = ($d.X + $d.W) } }
    }

    if ($align -eq "Auto" -or -not $align) {
        $cb = @(); $ct = @()
        foreach ($c in $cols) {
            $cb += [int](($c.Members | ForEach-Object { $_.Y + $_.H } | Measure-Object -Maximum).Maximum)
            $ct += [int](($c.Members | ForEach-Object { $_.Y } | Measure-Object -Minimum).Minimum)
        }
        if (@($cb | Select-Object -Unique).Count -eq 1) { $align = "Bottom" }
        elseif (@($ct | Select-Object -Unique).Count -eq 1) { $align = "Top" }
        else { $align = "Center" }
    }

    $items = @()
    $edge = 0.0
    $prevB = 0.0
    $firstCol = $true
    foreach ($c in $cols) {
        $mem = @($c.Members | Sort-Object { $_.Y })
        $cw = 0.0; $maxBez = 0.0
        foreach ($d in $mem) {
            $cw = [math]::Max($cw, $info[$d.Index].PW)
            $maxBez = [math]::Max($maxBez, $info[$d.Index].P.Bezel)
        }
        if ($firstCol) { $left = 0.0 } else { $left = $edge + $prevB + $maxBez }
        $firstCol = $false
        $cursorY = 0.0
        $prevBez = 0.0
        $firstM = $true
        $colItems = @()
        foreach ($d in $mem) {
            $inf = $info[$d.Index]
            if ($firstM) { $ty = 0.0 } else { $ty = $cursorY + $prevBez + $inf.P.Bezel }
            $firstM = $false
            $cursorY = $ty + $inf.PH
            $prevBez = $inf.P.Bezel
            $colItems += [pscustomobject]@{
                Index = $d.Index; D = $d; L = ($left + ($cw - $inf.PW) / 2.0); T = $ty; PW = $inf.PW; PH = $inf.PH
                Diag = $inf.P.Diag; Bezel = $inf.P.Bezel; Raise = $inf.P.Raise; Auto = $inf.P.Auto
            }
        }
        switch ($align) {
            "Top"    { $off = 0.0 }
            "Bottom" { $off = -$cursorY }
            default  { $off = -$cursorY / 2.0 }
        }
        foreach ($it in $colItems) { $it.T = $it.T + $off - $it.Raise; $items += $it }
        $edge = $left + $cw
        $prevB = $maxBez
    }

    # positions you placed by hand win over the automatic ones
    $saved = Get-SavedPositions $ds
    foreach ($it in $items) {
        if ($script:posOverride -and $script:posOverride.ContainsKey($it.Index)) {
            $it.L = [double]$script:posOverride[$it.Index].L; $it.T = [double]$script:posOverride[$it.Index].T
        } elseif ($saved) {
            $it.L = [double]$saved[$it.Index].L; $it.T = [double]$saved[$it.Index].T
        }
    }

    $minL = ($items | ForEach-Object { $_.L } | Measure-Object -Minimum).Minimum
    $maxR = ($items | ForEach-Object { $_.L + $_.PW } | Measure-Object -Maximum).Maximum
    $minY = ($items | ForEach-Object { $_.T } | Measure-Object -Minimum).Minimum
    $maxY = ($items | ForEach-Object { $_.T + $_.PH } | Measure-Object -Maximum).Maximum
    $ppm = ($items | ForEach-Object { $_.D.EW / $_.PW } | Measure-Object -Maximum).Maximum
    $script:physLayout = @{ Items = $items; BW = [double]($maxR - $minL); BH = [double]($maxY - $minY); MinL = [double]$minL; MinY = [double]$minY; Ppm = [double]$ppm }
    return $script:physLayout
}

# ---------------------------------------------------------------- pack recipes (so a pack can be re-cut later)
# A pack can keep its original pictures in "_source" plus a "pack.json" that says which screens
# each picture covers and how it was positioned. That is what Reposition uses.
function Get-SubLayout($lay, $indices) {
    $idx = @($indices | ForEach-Object { [int]$_ })
    $its = @($lay.Items | Where-Object { $idx -contains $_.Index })
    if ($its.Count -eq 0) { return $null }
    # screens left out of the middle of the group (they show something else) are closed up,
    # so the remaining screens sit next to each other on the picture
    $lo = ($idx | Measure-Object -Minimum).Minimum; $hi = ($idx | Measure-Object -Maximum).Maximum
    $shift = @{}
    foreach ($it in $its) { $shift[$it.Index] = 0.0 }
    foreach ($r in @($lay.Items | Where-Object { $_.Index -gt $lo -and $_.Index -lt $hi -and $idx -notcontains $_.Index })) {
        $rr = $r.L + $r.PW
        $overlap = $false
        foreach ($j in $its) { if ($j.L -lt $rr - 1 -and ($j.L + $j.PW) -gt $r.L + 1) { $overlap = $true } }
        if ($overlap) { continue }
        $nx = @($lay.Items | Where-Object { $_.Index -gt $r.Index } | Sort-Object Index | Select-Object -First 1)
        $gap = 0.0
        if ($nx.Count -gt 0) { $gap = [math]::Max(0.0, $nx[0].L - $rr) }
        foreach ($j in $its) { if ($j.L -ge $rr - 1) { $shift[$j.Index] = $shift[$j.Index] + $r.PW + $gap } }
    }
    $Ls = @{}
    foreach ($it in $its) { $Ls[$it.Index] = $it.L - $shift[$it.Index] }
    $minL = ($its | ForEach-Object { $Ls[$_.Index] } | Measure-Object -Minimum).Minimum
    $minT = ($its | ForEach-Object { $_.T } | Measure-Object -Minimum).Minimum
    $maxR = ($its | ForEach-Object { $Ls[$_.Index] + $_.PW } | Measure-Object -Maximum).Maximum
    $maxB = ($its | ForEach-Object { $_.T + $_.PH } | Measure-Object -Maximum).Maximum
    $ppm = ($its | ForEach-Object { $_.D.EW / $_.PW } | Measure-Object -Maximum).Maximum
    $new = @()
    foreach ($it in $its) {
        $new += [pscustomobject]@{ Index = $it.Index; D = $it.D; L = ($Ls[$it.Index] - $minL); T = $it.T; PW = $it.PW; PH = $it.PH; Diag = $it.Diag; Bezel = $it.Bezel; Raise = $it.Raise; Auto = $it.Auto }
    }
    return @{ Items = $new; BW = [double]($maxR - $minL); BH = [double]($maxB - $minT); MinL = 0.0; MinY = [double]$minT; Ppm = [double]$ppm }
}

# Where the cutter sits on a picture of w x h: scale and top-left, in picture pixels.
function Get-CutBox($sub, [double]$w, [double]$h, $g) {
    $k0 = [math]::Min($w / $sub.BW, $h / $sub.BH)
    $z = [double]$g.zoom
    if ($z -le 0) { $z = 1.0 }
    $k = $k0 * $z
    $hw = $sub.BW * $k / 2; $hh = $sub.BH * $k / 2
    $cx = [math]::Max($hw, [math]::Min($w - $hw, [double]$g.cx * $w))
    $cy = [math]::Max($hh, [math]::Min($h - $hh, [double]$g.cy * $h))
    return @{ K = $k; X = ($cx - $hw); Y = ($cy - $hh) }
}

function Get-Recipe([string]$dir) {
    $p = Join-Path $dir "pack.json"
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        if (-not $j.groups) { return $null }
        $groups = @()
        foreach ($g in @($j.groups)) {
            $groups += @{
                screens = @($g.screens | ForEach-Object { [int]$_ })
                source = [string]$g.source
                up = [bool]$g.up
                zoom = [double]$g.zoom
                cx = [double]$g.cx
                cy = [double]$g.cy
                type = $(if ($g.type) { [string]$g.type } else { 'image' })
                vpath = [string]$g.vpath
                over = [bool]$g.over
                rot = [int]$g.rot
                t0 = [double]$g.t0
                t1 = [double]$g.t1
                blend = [bool]$g.blend
            }
        }
        return $groups
    } catch { return $null }
}

function Save-Recipe([string]$dir, $groups) {
    $list = @()
    foreach ($g in $groups) { $t = 'image'; if ($g.type) { $t = [string]$g.type }; $list += @{ screens = @($g.screens); source = [string]$g.source; up = [bool]$g.up; zoom = [double]$g.zoom; cx = [double]$g.cx; cy = [double]$g.cy; type = $t; vpath = [string]$g.vpath; over = [bool]$g.over; rot = [int]$g.rot; t0 = [double]$g.t0; t1 = [double]$g.t1; blend = [bool]$g.blend } }
    $obj = @{ version = 1; groups = $list }
    ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath (Join-Path $dir "pack.json") -Encoding UTF8
}

function Clear-ScreenFile([string]$dir, [int]$idx) {
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue)) {
        if ($f.BaseName -eq [string]$idx -and $f.Extension -match $ImageExt) { Remove-Item -LiteralPath $f.FullName -Force }
    }
}

# Video quality (Builder dropdown): Fast / Balanced / Max
function Get-VideoEncArgs {
    $q = [string](Get-Settings).VideoQuality
    switch ($q) {
        'Fast' { $pr = 'veryfast'; $crf = '20' }
        'Max'  { $pr = 'slow'; $crf = '12' }
        default { $pr = 'medium'; $crf = '14' }
    }
    return @("-c:v", "libx264", "-preset", $pr, "-crf", $crf, "-pix_fmt", "yuv420p")
}
# ffmpeg filter that turns the picture by 90/180/270 degrees clockwise (applied before cropping)
function Get-RotFilter([int]$rot) {
    switch ($rot) {
        90  { return "transpose=1" }
        180 { return "hflip,vflip" }
        270 { return "transpose=2" }
        default { return "" }
    }
}
function Get-VideoFramePath([string]$ff, [string]$file, [int]$rot = 0) {
    $frame = Join-Path ([IO.Path]::GetTempPath()) ("wcc_frame_{0}.png" -f ([guid]::NewGuid().ToString("N")))
    $rf = Get-RotFilter $rot
    $vfa = @()
    if ($rf) { $vfa = @("-vf", $rf) }
    [void](Start-Process -FilePath $ff -ArgumentList (@("-y", "-ss", "1", "-i", ('"{0}"' -f $file)) + $vfa + @("-frames:v", "1", ('"{0}"' -f $frame))) -WindowStyle Hidden -Wait)
    if (-not (Test-Path -LiteralPath $frame)) {
        [void](Start-Process -FilePath $ff -ArgumentList (@("-y", "-i", ('"{0}"' -f $file)) + $vfa + @("-frames:v", "1", ('"{0}"' -f $frame))) -WindowStyle Hidden -Wait)
    }
    if (Test-Path -LiteralPath $frame) { return $frame }
    return $null
}

# Cuts a video for one group of screens into _video\screenN.mp4 (one file per screen).
function Write-GroupVideo([string]$ff, [string]$file, $sub, $g, [string]$dir) {
    $rot = [int]$g.rot
    $rf = Get-RotFilter $rot
    $t0 = [double]$g.t0; $t1 = [double]$g.t1
    $pre = @()
    if ($t0 -gt 0) { $pre += @("-ss", ("{0:0.###}" -f $t0)) }
    if ($t1 -gt $t0) { $pre += @("-t", ("{0:0.###}" -f ($t1 - $t0))) }
    $fp = Get-VideoFramePath $ff $file $rot
    if (-not $fp) { throw "Couldn't read a picture from the video." }
    $ld = Read-ImageFromFile $fp
    $vw = $ld.Image.Width; $vh = $ld.Image.Height
    $ld.Image.Dispose(); $ld.Stream.Dispose()
    Remove-Item -LiteralPath $fp -Force -ErrorAction SilentlyContinue
    $box = Get-CutBox $sub $vw $vh $g
    $vdir = Join-Path $dir "_video"
    New-Item -ItemType Directory -Path $vdir -Force | Out-Null
    $first = $true
    foreach ($it in $sub.Items) {
        $cw = [int][math]::Max(2, [math]::Round($it.PW * $box.K))
        $chh = [int][math]::Max(2, [math]::Round($it.PH * $box.K))
        $cx = [int][math]::Max(0, [math]::Round($box.X + $it.L * $box.K))
        $cy = [int][math]::Max(0, [math]::Round($box.Y + ($it.T - $sub.MinY) * $box.K))
        if ($cx + $cw -gt $vw) { $cw = $vw - $cx }
        if ($cy + $chh -gt $vh) { $chh = $vh - $cy }
        $out = Join-Path $vdir ("screen{0}.mp4" -f $it.Index)
        $vf = "crop={0}:{1}:{2}:{3},scale={4}:{5}:flags=lanczos,setsar=1" -f $cw, $chh, $cx, $cy, $it.D.EW, $it.D.EH
        if ($it.D.Turn -gt 0) { $vf += "," + (Get-TurnVf $it.D.Turn) }
        if ($rf) { $vf = $rf + "," + $vf }
        $a2 = @("-y") + $pre + @("-i", ('"{0}"' -f $file), "-vf", ('"{0}"' -f $vf)) + (Get-VideoEncArgs)
        if ($first) { $a2 += @("-c:a", "aac", "-b:a", "160k") } else { $a2 += @("-an") }
        $a2 += @("-movflags", "+faststart", ('"{0}"' -f $out))
        Set-Status "Cutting video for screen $($it.Index) (long videos take a while)..."
        [System.Windows.Forms.Application]::DoEvents()
        $p = Start-Process -FilePath $ff -ArgumentList $a2 -WindowStyle Hidden -Wait -PassThru
        if ($p.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $out)) { throw "ffmpeg couldn't cut the video for screen $($it.Index)." }
        $first = $false
    }
}

# Plays a pack's video screens through Lively (the pictures are already on the other screens).
function Start-PackVideos([string]$dir) {
    $rec = Get-Recipe $dir
    if (-not $rec) { return }
    $files = @{}
    foreach ($g in @($rec)) {
        if ($g.type -ne 'video') { continue }
        foreach ($s in $g.screens) {
            $f = Join-Path (Join-Path $dir "_video") ("screen{0}.mp4" -f $s)
            if (Test-Path -LiteralPath $f) { $files[[int]$s] = $f }
        }
    }
    if ($files.Count -eq 0) { return }
    if (-not (Get-LivelyPath)) { Show-LivelyMissing; return }
    if (-not (Test-LivelyRunning)) {
        Set-Status "Starting Lively..."
        [void](Invoke-Lively @("app", "--showApp", "false") 4000)
    }
    [void](Invoke-Lively @("app", "--volume", "$(Get-SoundLevel)") 300)
    [void](Invoke-Lively @("app", "--layout", "per") 500)
    $lmap = Get-LivelyMonitorMap
    $pins = @(Get-PinnedScreens)
    foreach ($d in (Get-DisplayList)) {
        if (-not $files.ContainsKey([int]$d.Index)) { continue }
        if ($pins -contains [int]$d.Index) { continue }
        if ($d.WinNum -gt 0) { $m = ConvertTo-LivelyNum $d.WinNum $lmap } else { $m = $d.Index }
        [void](Invoke-Lively @("setwp", "--file", ('"{0}"' -f $files[[int]$d.Index]), "--monitor", "$m") 1500)
    }
    if ($pins.Count -eq 0) { $script:nowPlaying = "video in pack " + (Split-Path $dir -Leaf) }
    if ($script:lblNow) { Update-NowPlaying }
}

# Cuts one picture into the pieces for the screens of one group (straight crops at full quality).
function Write-GroupNative([string]$srcFile, $sub, $g, [string]$dir) {
    $ld = Read-ImageFromFile $srcFile
    $src = $ld.Image
    try {
        $box = Get-CutBox $sub $src.Width $src.Height $g
        $sigma = Get-GrainSigma
        foreach ($it in $sub.Items) {
            $sx = $box.X + $it.L * $box.K
            $sy = $box.Y + ($it.T - $sub.MinY) * $box.K
            $sw = $it.PW * $box.K
            $sh = $it.PH * $box.K
            $dw = [int][math]::Max(1, [math]::Round($sw))
            $dh = [int][math]::Max(1, [math]::Round($sh))
            $bmp = New-Object System.Drawing.Bitmap($dw, $dh)
            $gr = [System.Drawing.Graphics]::FromImage($bmp)
            $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gr.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $dest = New-Object System.Drawing.Rectangle(0, 0, $dw, $dh)
            $gr.DrawImage($src, $dest, [single]$sx, [single]$sy, [single]$sw, [single]$sh, [System.Drawing.GraphicsUnit]::Pixel)
            $gr.Dispose()
            if ($it.D.Turn -gt 0) { Rotate-ForTurn $bmp $it.D.Turn }
            if ($sigma -gt 0 -and $script:fxOk) {
                $grainy = [ImageFx]::Grain($bmp, $sigma)
                $bmp.Dispose()
                $bmp = $grainy
            }
            Clear-ScreenFile $dir $it.Index
            $bmp.Save((Join-Path $dir ("{0}.png" -f $it.Index)), [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        }
    } finally {
        $src.Dispose(); $ld.Stream.Dispose()
    }
}

# Same, but the framed area is first upscaled with the AI model and fitted to the screens' pixels.
function Write-GroupAI([string]$exe, [string]$srcFile, $sub, $g, [string]$dir) {
    $ld = Read-ImageFromFile $srcFile
    $src = $ld.Image
    $tmpCrop = $null
    try {
        $box = Get-CutBox $sub $src.Width $src.Height $g
        $ow = $src.Width; $oh = $src.Height
        $cw = [int][math]::Max(1, [math]::Round($sub.BW * $box.K))
        $chh = [int][math]::Max(1, [math]::Round($sub.BH * $box.K))
        $cx = [int][math]::Max(0, [math]::Min($ow - 1, [math]::Round($box.X)))
        $cy = [int][math]::Max(0, [math]::Min($oh - 1, [math]::Round($box.Y)))
        if ($cx + $cw -gt $ow) { $cw = $ow - $cx }
        if ($cy + $chh -gt $oh) { $chh = $oh - $cy }
        $crop = New-Object System.Drawing.Bitmap($cw, $chh, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $cg = [System.Drawing.Graphics]::FromImage($crop)
        $cg.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $cw, $chh)), (New-Object System.Drawing.Rectangle($cx, $cy, $cw, $chh)), [System.Drawing.GraphicsUnit]::Pixel)
        $cg.Dispose()
        $tmpCrop = Join-Path ([IO.Path]::GetTempPath()) ("wcc_crop_{0}.png" -f ([guid]::NewGuid().ToString("N")))
        $crop.Save($tmpCrop, [System.Drawing.Imaging.ImageFormat]::Png)
        $crop.Dispose()

        $totalW = [int][math]::Ceiling($sub.BW * $sub.Ppm)
        $sliceH = [int][math]::Ceiling($sub.BH * $sub.Ppm)
        $need = [math]::Max($totalW / [double]$cw, $sliceH / [double]$chh)
        $upPath = Invoke-Upscale $exe $tmpCrop $need
        $ai = Read-ImageFromFile $upPath
        $orig = Read-ImageFromFile $tmpCrop
        $fit = Complete-Upscale $orig.Image $ai.Image $totalW $sliceH
        $ai.Image.Dispose(); $ai.Stream.Dispose()
        $orig.Image.Dispose(); $orig.Stream.Dispose()
        Remove-Item -LiteralPath $upPath -Force -ErrorAction SilentlyContinue
        foreach ($it in $sub.Items) {
            $sw = [int]$it.D.EW; $sh = [int]$it.D.EH
            $fx = [int][math]::Round($it.L * $sub.Ppm)
            $fy = [int][math]::Round(($it.T - $sub.MinY) * $sub.Ppm)
            $fw = [int][math]::Round($it.PW * $sub.Ppm)
            $fh = [int][math]::Round($it.PH * $sub.Ppm)
            if ($fx + $fw -gt $totalW) { $fw = $totalW - $fx }
            if ($fy + $fh -gt $sliceH) { $fh = $sliceH - $fy }
            $slice = New-Object System.Drawing.Bitmap($sw, $sh, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $gr = [System.Drawing.Graphics]::FromImage($slice)
            $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gr.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $gr.DrawImage($fit, (New-Object System.Drawing.Rectangle(0, 0, $sw, $sh)), (New-Object System.Drawing.Rectangle($fx, $fy, $fw, $fh)), [System.Drawing.GraphicsUnit]::Pixel)
            $gr.Dispose()
            if ($it.D.Turn -gt 0) { Rotate-ForTurn $slice $it.D.Turn }
            Clear-ScreenFile $dir $it.Index
            Save-Bitmap-Png $slice (Join-Path $dir ("{0}.png" -f $it.Index))
            $slice.Dispose()
        }
        $fit.Dispose()
    } finally {
        $src.Dispose(); $ld.Stream.Dispose()
        if ($tmpCrop) { Remove-Item -LiteralPath $tmpCrop -Force -ErrorAction SilentlyContinue }
    }
}

# A turned copy of a source picture (90 / 180 / 270 degrees), used while a pack is cut.
function New-RotatedCopy([string]$path, [int]$deg) {
    try {
        $ld = Read-ImageFromFile $path
        try {
            $bmp = New-Object System.Drawing.Bitmap($ld.Image)
            switch ($deg) {
                90  { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
                180 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
                270 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
            }
            $out = Join-Path ([IO.Path]::GetTempPath()) ("ekk0h_turn_" + [guid]::NewGuid().ToString("N") + ".png")
            $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
            return $out
        } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
    } catch { return $null }
}

# Writes every screen's picture for a pack from its recipe. Screens in a group without a picture go black.
function Render-Recipe([string]$dir, $groups, [string]$exe) {
    $lay = Get-PhysicalLayout
    $count = $lay.Items.Count
    $blendScr = @(); $srcScr = @()
    foreach ($g in $groups) {
        $scr = @($g.screens | Where-Object { $_ -ge 1 -and $_ -le $count })
        if ($scr.Count -eq 0) { continue }
        if ($g.source -and $g.type -ne 'video') { $srcScr += $scr }
        elseif (-not $g.source -and $g.type -ne 'video' -and $g.blend) { $blendScr += $scr }
        $sub = Get-SubLayout $lay $scr
        if ($g.over) {
            foreach ($s1 in $scr) { Remove-Item -LiteralPath (Join-Path (Join-Path $dir "_video") ("screen{0}.mp4" -f $s1)) -Force -ErrorAction SilentlyContinue }
        }
        if (-not $g.source) {
            foreach ($it in $sub.Items) {
                Clear-ScreenFile $dir $it.Index
                New-BlackImage (Join-Path $dir ("{0}.png" -f $it.Index)) $it.D.W $it.D.H
            }
            if ($g.type -eq 'video' -and $g.vpath -and (Test-Path -LiteralPath $g.vpath)) {
                $ff = Find-Ffmpeg
                if ($ff) { Write-GroupVideo $ff $g.vpath $sub $g $dir }
            }
            continue
        }
        $f = Join-Path (Join-Path $dir "_source") $g.source
        $tmpRot = $null
        if ([int]$g.rot -ne 0) { $tmpRot = New-RotatedCopy $f ([int]$g.rot); if ($tmpRot) { $f = $tmpRot } }
        try {
            if ($g.up -and $exe) { Write-GroupAI $exe $f $sub $g $dir } else { Write-GroupNative $f $sub $g $dir }
        } finally { if ($tmpRot) { Remove-Item -LiteralPath $tmpRot -Force -ErrorAction SilentlyContinue } }
    }
    if ($blendScr.Count -gt 0 -and $srcScr.Count -gt 0) { Write-BlendScreens $dir $lay $blendScr $srcScr }
}

# ---------------------------------------------------------------- blend empty screens
# Samples a vertical strip of colors from the left or right edge of a finished screen picture.
function Get-EdgeColors([string]$dir, [int]$idx, [bool]$rightEdge, [int]$rows = 24) {
    $f = Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq [string]$idx -and $_.Extension -match $ImageExt } | Select-Object -First 1
    if (-not $f) { return $null }
    $ld = Read-ImageFromFile $f.FullName
    try {
        $sm = New-Object System.Drawing.Bitmap(48, 48, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gr = [System.Drawing.Graphics]::FromImage($sm)
        $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gr.DrawImage($ld.Image, (New-Object System.Drawing.Rectangle(0, 0, 48, 48)))
        $gr.Dispose()
        $cols = @()
        $x0 = 0; if ($rightEdge) { $x0 = 43 }
        for ($r = 0; $r -lt $rows; $r++) {
            $y = [int][math]::Min(47, [math]::Floor($r * 48 / $rows))
            $rs = 0; $gs = 0; $bs = 0; $n = 0
            for ($yy = [math]::Max(0, $y - 1); $yy -le [math]::Min(47, $y + 1); $yy++) {
                for ($xx = $x0; $xx -lt ($x0 + 5); $xx++) { $c = $sm.GetPixel($xx, $yy); $rs += $c.R; $gs += $c.G; $bs += $c.B; $n++ }
            }
            $cols += , @(($rs / $n), ($gs / $n), ($bs / $n))
        }
        $sm.Dispose()
        return $cols
    } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
}

# Empty screens get a soft gradient that continues the colors of the pictures beside them.
function Write-BlendScreens([string]$dir, $lay, [int[]]$blendScr, [int[]]$srcScr) {
    $items = @{}
    foreach ($it in $lay.Items) { $items[[int]$it.Index] = $it }
    $edgeCache = @{}
    foreach ($b in ($blendScr | Sort-Object)) {
        $me = $items[[int]$b]
        if (-not $me) { continue }
        $left = $null; $right = $null
        foreach ($s in $srcScr) {
            $o = $items[[int]$s]
            if (-not $o) { continue }
            if (($o.L + $o.PW) -le ($me.L + 1)) { if (-not $left -or $o.L -gt $left.L) { $left = $o } }
            elseif ($o.L -ge ($me.L + $me.PW - 1)) { if (-not $right -or $o.L -lt $right.L) { $right = $o } }
        }
        if (-not $left -and -not $right) { continue }
        $lc = $null; $rc = $null
        if ($left)  { $k = "R$($left.Index)";  if (-not $edgeCache.ContainsKey($k)) { $edgeCache[$k] = Get-EdgeColors $dir $left.Index $true };  $lc = $edgeCache[$k] }
        if ($right) { $k = "L$($right.Index)"; if (-not $edgeCache.ContainsKey($k)) { $edgeCache[$k] = Get-EdgeColors $dir $right.Index $false }; $rc = $edgeCache[$k] }
        if (-not $lc -and -not $rc) { continue }
        $rows = 24; $cols = 64
        $tiny = New-Object System.Drawing.Bitmap($cols, $rows, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $xl = 0.0; $xr = 0.0
        if ($left) { $xl = $left.L + $left.PW }
        if ($right) { $xr = $right.L }
        for ($x = 0; $x -lt $cols; $x++) {
            $px = $me.L + ($x + 0.5) / $cols * $me.PW
            if ($lc -and $rc) { $t = ($px - $xl) / [math]::Max(1.0, ($xr - $xl)) }
            elseif ($lc) { $t = [math]::Min(1.0, ($px - $xl) / [math]::Max(1.0, $me.PW * 2.5)) }
            else { $t = 1.0 - [math]::Min(1.0, ($xr - $px) / [math]::Max(1.0, $me.PW * 2.5)) }
            $t = [math]::Max(0.0, [math]::Min(1.0, $t))
            $t = $t * $t * (3 - 2 * $t)
            for ($y = 0; $y -lt $rows; $y++) {
                if ($lc -and $rc) { $a = $lc[$y]; $c2 = $rc[$y]; $r = $a[0] + ($c2[0] - $a[0]) * $t; $g2 = $a[1] + ($c2[1] - $a[1]) * $t; $bl = $a[2] + ($c2[2] - $a[2]) * $t }
                elseif ($lc) { $a = $lc[$y]; $f = 1.0 - 0.45 * $t; $r = $a[0] * $f; $g2 = $a[1] * $f; $bl = $a[2] * $f }
                else { $a = $rc[$y]; $f = 1.0 - 0.45 * (1.0 - $t); $r = $a[0] * $f; $g2 = $a[1] * $f; $bl = $a[2] * $f }
                $tiny.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, [int][math]::Max(0, [math]::Min(255, $r)), [int][math]::Max(0, [math]::Min(255, $g2)), [int][math]::Max(0, [math]::Min(255, $bl))))
            }
        }
        $sw = [int]$me.D.EW; $sh = [int]$me.D.EH
        $big = New-Object System.Drawing.Bitmap($sw, $sh, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $gr = [System.Drawing.Graphics]::FromImage($big)
        $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $gr.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $gr.DrawImage($tiny, (New-Object System.Drawing.Rectangle(0, 0, $sw, $sh)), (New-Object System.Drawing.Rectangle(0, 0, $cols, $rows)), [System.Drawing.GraphicsUnit]::Pixel)
        $gr.Dispose(); $tiny.Dispose()
        if ($me.D.Turn -gt 0) { Rotate-ForTurn $big $me.D.Turn }
        Clear-ScreenFile $dir $me.Index
        Save-Bitmap-Png $big (Join-Path $dir ("{0}.png" -f $me.Index))
        $big.Dispose()
    }
}



# ---------------------------------------------------------------- refit existing panorama packs
function Get-SeamDiff($a, $b) {
    $rows = 48
    $tot = 0.0
    for ($r = 0; $r -lt $rows; $r++) {
        $ya = [int][math]::Min($a.Height - 1, [math]::Floor($r * $a.Height / $rows))
        $yb = [int][math]::Min($b.Height - 1, [math]::Floor($r * $b.Height / $rows))
        $pa = $a.GetPixel($a.Width - 1, $ya)
        $pb = $b.GetPixel(0, $yb)
        $tot += ([math]::Abs($pa.R - $pb.R) + [math]::Abs($pa.G - $pb.G) + [math]::Abs($pa.B - $pb.B)) / 3.0
    }
    return $tot / $rows
}

# Finds packs that look like one picture cut into pieces, re-joins them and cuts them again
# to match your real screen sizes. Originals are kept in a "_original" folder inside the pack.
# Does this pack look like one picture cut into one piece per screen?
function Test-PanoramaPack($imgs, [int]$n) {
    if ($imgs.Count -ne $n -or $n -lt 2) { return $false }
    $bmps = @()
    $ok = $true
    try {
        foreach ($f in $imgs) {
            $ld = Read-ImageFromFile $f.FullName
            $bmps += New-Object System.Drawing.Bitmap($ld.Image)
            $ld.Image.Dispose(); $ld.Stream.Dispose()
        }
        $h0 = $bmps[0].Height
        foreach ($b in $bmps) { if ([math]::Abs($b.Height - $h0) -gt 2) { $ok = $false } }
        if ($ok) {
            for ($i = 0; $i -lt $bmps.Count - 1; $i++) { if ((Get-SeamDiff $bmps[$i] $bmps[$i + 1]) -gt 24) { $ok = $false } }
        }
    } catch { $ok = $false }
    foreach ($b in $bmps) { $b.Dispose() }
    return $ok
}

# Joins a cut-up panorama pack back into one picture (kept in _source, pieces kept in _original).
function Convert-PackToPanorama([string]$dir) {
    $imgs = @(Get-PackImages $dir)
    $loaded = @()
    $tw = 0
    foreach ($f in $imgs) { $ld = Read-ImageFromFile $f.FullName; $loaded += $ld; $tw += $ld.Image.Width }
    $h = $loaded[0].Image.Height
    $pano = New-Object System.Drawing.Bitmap($tw, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($pano)
    $x = 0
    foreach ($ld in $loaded) { $g.DrawImage($ld.Image, $x, 0, $ld.Image.Width, $h); $x += $ld.Image.Width }
    $g.Dispose()
    foreach ($ld in $loaded) { $ld.Image.Dispose(); $ld.Stream.Dispose() }
    $srcDir = Join-Path $dir "_source"
    $orig = Join-Path $dir "_original"
    New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
    New-Item -ItemType Directory -Path $orig -Force | Out-Null
    foreach ($f in $imgs) { Move-Item -LiteralPath $f.FullName -Destination $orig }
    $pano.Save((Join-Path $srcDir "g1.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $pano.Dispose()
    return @{ screens = @(1..$imgs.Count); source = "g1.png"; up = $false; zoom = 1.0; cx = 0.5; cy = 0.5 }
}

# Finds packs that look like one picture cut into pieces, joins them and cuts them again to match
# your real screen sizes. They become packs you can Reposition. Pieces are kept in "_original".
function Convert-PanoramaPacks {
    $n = @(Get-DisplayList).Count
    if ($n -lt 2) { Set-Status "Needs two or more screens."; return 0 }
    $found = @()
    foreach ($p in (Get-Packs)) {
        if (Test-Path -LiteralPath (Join-Path $p.FullName "_original")) { continue }
        if (Test-Path -LiteralPath (Join-Path $p.FullName "pack.json")) { continue }
        if (Test-PanoramaPack @(Get-PackImages $p.FullName) $n) { $found += $p }
    }
    if ($found.Count -eq 0) { Set-Status "No panorama packs to refit (already done, or none look like cut-up panoramas)."; return 0 }
    $names = ($found | ForEach-Object { $_.Name }) -join "`n"
    $ans = [System.Windows.Forms.MessageBox]::Show(
        "These packs look like panoramas cut into pieces:`n`n$names`n`nRe-cut them to match your screens' real sizes? The original pieces are kept in an _original folder inside each pack.",
        "Refit packs", 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return 0 }
    $script:form.Cursor = 'WaitCursor'
    $done = 0
    try {
        foreach ($p in $found) {
            Set-Status "Refitting $($p.Name)..."
            $g = Convert-PackToPanorama $p.FullName
            Render-Recipe $p.FullName @($g) $null
            Save-Recipe $p.FullName @($g)
            $done++
        }
    } catch {
        Set-Status "Refit stopped: $($_.Exception.Message)"
    } finally {
        $script:form.Cursor = 'Default'
    }
    if ($done -gt 0) { Set-Status "Refit $done pack(s) to your real screen sizes. You can adjust them in the Builder tab." }
    return $done
}

# Crops the image to the target shape (centered) and resizes it to exactly $w x $h.
function Save-Bitmap-Png([System.Drawing.Bitmap]$bmp, [string]$path) {
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Resize-Cover([System.Drawing.Image]$img, [int]$w, [int]$h) {
    $scale = [math]::Max($w / $img.Width, $h / $img.Height)
    $sw = [double]($w / $scale)
    $sh = [double]($h / $scale)
    $sx = ($img.Width - $sw) / 2
    $sy = ($img.Height - $sh) / 2
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $dest = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $g.DrawImage($img, $dest, [single]$sx, [single]$sy, [single]$sw, [single]$sh, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    return $bmp
}

# Runs the anime model (4x) on one image and returns the path of the upscaled PNG (a temp file).
# ---- upscale settings (the three dropdowns on the Builder tab)
function Get-ModelChoices {
    $exe = Find-Upscaler
    $all = @("Auto Soft", "Soft x2", "Soft x3", "Soft x4", "Anime x4", "Photo x4")
    if (-not $exe) { return @("Auto Soft", "Anime x4") }
    $dir = Join-Path (Split-Path $exe -Parent) "models"
    $has = {
        param($base)
        (Test-Path -LiteralPath (Join-Path $dir "$base.param")) -and (Test-Path -LiteralPath (Join-Path $dir "$base.bin"))
    }
    $soft2 = & $has "realesr-animevideov3-x2"
    $soft3 = & $has "realesr-animevideov3-x3"
    $soft4 = & $has "realesr-animevideov3-x4"
    $choices = @()
    if ($soft2 -and $soft3 -and $soft4) { $choices += "Auto Soft" }
    if ($soft2) { $choices += "Soft x2" }
    if ($soft3) { $choices += "Soft x3" }
    if ($soft4) { $choices += "Soft x4" }
    if (& $has "realesrgan-x4plus-anime") { $choices += "Anime x4" }
    if (& $has "realesrgan-x4plus") { $choices += "Photo x4" }
    if ($choices.Count -eq 0) { $choices = @("Anime x4") }
    return $choices
}

function Get-SelectedModel([double]$need) {
    $choice = "Auto Soft"
    if ($script:cmbModel -and $script:cmbModel.SelectedItem) { $choice = [string]$script:cmbModel.SelectedItem }
    switch ($choice) {
        "Anime x4" { return @{ Name = "realesrgan-x4plus-anime"; Scale = 4 } }
        "Photo x4" { return @{ Name = "realesrgan-x4plus"; Scale = 4 } }
        "Soft x2"  { return @{ Name = "realesr-animevideov3"; Scale = 2 } }
        "Soft x3"  { return @{ Name = "realesr-animevideov3"; Scale = 3 } }
        "Soft x4"  { return @{ Name = "realesr-animevideov3"; Scale = 4 } }
        default {
            # smallest soft scale that covers what this image needs
            $sc = [int][math]::Min(4, [math]::Max(2, [math]::Ceiling($need)))
            return @{ Name = "realesr-animevideov3"; Scale = $sc }
        }
    }
}

# How much of the AI result to keep (the rest is a plain resize of your original).
function Get-MixAmount {
    $choice = "60%"
    if ($script:cmbMix -and $script:cmbMix.SelectedItem) { $choice = [string]$script:cmbMix.SelectedItem }
    return ([double]($choice.TrimEnd('%')) / 100.0)
}

function Get-GrainSigma {
    $choice = "Light"
    if ($script:cmbGrain -and $script:cmbGrain.SelectedItem) { $choice = [string]$script:cmbGrain.SelectedItem }
    switch ($choice) {
        "Light"  { return 3.0 }
        "Medium" { return 6.0 }
        "Strong" { return 10.0 }
        default  { return 0.0 }
    }
}

# Fits the result to w x h, mixes some of the plain resize back in, then adds grain.
# $ai may be $null (image was already big enough): then only the grain applies.
function Complete-Upscale([System.Drawing.Image]$orig, $ai, [int]$w, [int]$h) {
    if ($ai) { $fit = Resize-Cover $ai $w $h } else { $fit = Resize-Cover $orig $w $h }
    $mix = Get-MixAmount
    if ($ai -and $mix -lt 1.0 -and $script:fxOk) {
        $plain = Resize-Cover $orig $w $h
        $mixed = [ImageFx]::Blend($fit, $plain, $mix)
        $fit.Dispose(); $plain.Dispose()
        $fit = $mixed
    }
    $sigma = Get-GrainSigma
    if ($sigma -gt 0 -and $script:fxOk) {
        $grainy = [ImageFx]::Grain($fit, $sigma)
        $fit.Dispose()
        $fit = $grainy
    }
    return $fit
}

function Invoke-Upscale([string]$exe, [string]$inPath, [double]$need = 4) {
    $tmp = Join-Path $env:TEMP "wcc-upscale"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $tin  = Join-Path $tmp "in.png"
    $tout = Join-Path $tmp "out.png"
    $terr = Join-Path $tmp "err.txt"
    Remove-Item -LiteralPath $tout, $terr -Force -ErrorAction SilentlyContinue

    $loaded = Read-ImageFromFile $inPath
    $loaded.Image.Save($tin, [System.Drawing.Imaging.ImageFormat]::Png)
    $loaded.Image.Dispose(); $loaded.Stream.Dispose()

    $models = Join-Path (Split-Path $exe -Parent) "models"
    $model = Get-SelectedModel $need
    $argList = @("-i", "`"$tin`"", "-o", "`"$tout`"", "-n", $model.Name, "-s", "$($model.Scale)", "-m", "`"$models`"")
    $p = Start-Process -FilePath $exe -ArgumentList $argList -WindowStyle Hidden -PassThru -RedirectStandardError $terr
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $p.HasExited) {
        Set-Status ("AI upscaling... {0}s (big images can take a few minutes)" -f [int]$sw.Elapsed.TotalSeconds)
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.Application]::DoEvents()
    }
    if (-not (Test-Path -LiteralPath $tout)) {
        $err = ""
        if (Test-Path -LiteralPath $terr) { $err = (Get-Content -LiteralPath $terr -Tail 3) -join " " }
        throw "The upscaler didn't produce an image. $err"
    }
    Remove-Item -LiteralPath $tin -Force -ErrorAction SilentlyContinue
    return $tout
}



# Keeps every pack's pictures named 1, 2, 3... in their current order. Runs by itself.
function Repair-PackNames {
    foreach ($p in (Get-Packs)) {
        try {
            $imgs = @(Get-PackImages $p.FullName)
            if ($imgs.Count -eq 0) { continue }
            $ok = $true
            for ($i = 0; $i -lt $imgs.Count; $i++) { if ($imgs[$i].BaseName -ne [string]($i + 1)) { $ok = $false } }
            if ($ok) { continue }
            $temps = @()
            for ($i = 0; $i -lt $imgs.Count; $i++) {
                $tmpName = "__tmp_{0}{1}" -f $i, $imgs[$i].Extension
                Rename-Item -LiteralPath $imgs[$i].FullName -NewName $tmpName
                $temps += [pscustomobject]@{ Path = (Join-Path $p.FullName $tmpName); Ext = $imgs[$i].Extension }
            }
            for ($i = 0; $i -lt $temps.Count; $i++) {
                Rename-Item -LiteralPath $temps[$i].Path -NewName ("{0}{1}" -f ($i + 1), $temps[$i].Ext)
            }
        } catch { }
    }
}

# ---------------------------------------------------------------- themes
# Every theme is a table of colors (R,G,B) plus a few style switches. Set-Theme turns one
# into the $script:c* palette the rest of the app paints with. Anything a theme leaves out is
# worked out from its main colors.
#   Shape: chamfer | cyber | soft | round | square      Hdr: header artwork kind
#   Fx: none | flat | glitch | tick                      Anim: header animates (rain, glitch)
$script:ThemeNames = @('Retrowave', 'Cyberpunk', 'Digital Rain', 'Sleek', 'Glitch', 'Kawaii', 'Aurora', 'Gothic', 'RGB', 'Blueprint', 'Galaxy', 'Shinobi', 'Wallpaper')
$script:Themes = @{
    'Retrowave' = @{
        Bg = @(13, 2, 33); Panel = @(24, 9, 52); Panel2 = @(46, 18, 96); Hover = @(84, 34, 150)
        Text = @(240, 230, 255); Dim = @(156, 134, 206)
        Accent = @(255, 41, 117); AccentHover = @(255, 110, 160); AccentDown = @(200, 25, 90)
        Cyan = @(0, 240, 255); Purple = @(150, 50, 255); Orange = @(255, 150, 60); Sun = @(255, 214, 90)
        Danger = @(60, 8, 44); DangerHover = @(130, 18, 78); DangerB = @(88, 12, 62)
        BtnA = @(36, 12, 78); BtnB = @(60, 24, 118); Head = @(0, 214, 230)
        SelA = @(110, 30, 170); SelText = @(205, 252, 255); Track = @(34, 14, 76)
        MenuBack = @(26, 8, 56); MenuSel = @(110, 24, 140); Inner = @(30, 8, 62); BoxTop = @(52, 16, 100)
        Sky = @(86, 14, 120); Ground = @(18, 3, 42); DlgA = @(18, 5, 44); DlgB = @(40, 10, 78)
        StatB = @(48, 8, 90); StatText = @(150, 235, 245); Ok = @(120, 255, 190)
        T1B = @(255, 150, 200); T2A = @(0, 240, 255); T2B = @(160, 120, 255)
        Shape = 'chamfer'; Hdr = 'retro'; Fx = 'none'; Anim = $true
        Fonts = @('Bahnschrift', 'Segoe UI Semibold'); TFonts = @('Bahnschrift', 'Segoe UI Semibold'); TStyle = 'Bold, Italic'; TSize = 21
    }
    'Cyberpunk' = @{
        Bg = @(7, 6, 16); Panel = @(16, 14, 30); Panel2 = @(30, 26, 52); Hover = @(58, 48, 92)
        Text = @(238, 240, 255); Dim = @(140, 138, 176)
        Accent = @(252, 238, 10); AccentHover = @(255, 247, 110); AccentDown = @(196, 184, 0)
        Cyan = @(0, 232, 255); Purple = @(255, 0, 110); Orange = @(255, 140, 0); Sun = @(255, 160, 0)
        Danger = @(52, 0, 24); DangerHover = @(120, 0, 52); DangerEdge = @(255, 0, 110); DangerTxt = @(255, 120, 170)
        BtnA = @(26, 22, 46); BtnB = @(44, 38, 76); Head = @(0, 232, 255)
        SelA = @(96, 84, 4); SelText = @(255, 250, 200); Sky = @(52, 8, 70); StatB = @(40, 10, 52)
        PrimTxt = @(14, 10, 0); T1B = @(252, 238, 10); T2A = @(0, 232, 255); T2B = @(255, 0, 110); TShadow = @(255, 0, 110)
        Shape = 'cyber'; Hdr = 'cyber'; Fx = 'none'; Anim = $true
        Fonts = @('Bahnschrift', 'Segoe UI Semibold'); TFonts = @('Bahnschrift', 'Segoe UI Black'); TStyle = 'Bold'; TSize = 21
    }
    'Digital Rain' = @{
        Bg = @(0, 8, 2); Panel = @(3, 20, 6); Panel2 = @(7, 38, 12); Hover = @(14, 74, 24)
        Text = @(180, 255, 190); Dim = @(70, 160, 90)
        Accent = @(0, 255, 65); AccentHover = @(150, 255, 170); AccentDown = @(0, 170, 40)
        Cyan = @(0, 255, 160); Purple = @(0, 130, 50); Orange = @(170, 255, 0); Sun = @(190, 255, 60)
        Danger = @(30, 0, 0); DangerHover = @(90, 6, 6); DangerEdge = @(255, 60, 60); DangerTxt = @(255, 130, 130)
        SelA = @(0, 96, 32); SelText = @(215, 255, 220); Sky = @(0, 44, 12); StatB = @(4, 34, 10)
        PrimTxt = @(0, 14, 3); CyanTxt = @(0, 14, 3); Ok = @(0, 255, 100)
        T1A = @(200, 255, 210); T1B = @(0, 255, 65); T2A = @(0, 255, 160); T2B = @(0, 150, 60); TShadow = @(0, 130, 50)
        Shape = 'square'; Hdr = 'matrix'; Fx = 'tick'; Anim = $true
        Fonts = @('Consolas', 'Lucida Console'); TFonts = @('OCR A Extended', 'Courier New', 'Consolas'); TStyle = 'Bold'; TSize = 20
    }
    'Sleek' = @{
        Bg = @(17, 18, 21); Panel = @(26, 28, 33); Panel2 = @(38, 41, 48); Hover = @(56, 60, 70)
        Text = @(236, 238, 242); Dim = @(138, 144, 156)
        Accent = @(64, 156, 255); AccentHover = @(120, 190, 255); AccentDown = @(36, 110, 214)
        Cyan = @(122, 132, 150); Purple = @(84, 92, 108); Orange = @(96, 112, 255); Sun = @(96, 112, 255)
        Danger = @(46, 22, 26); DangerHover = @(96, 36, 44); DangerEdge = @(235, 87, 87); DangerTxt = @(255, 140, 140)
        BtnA = @(34, 37, 43); BtnB = @(44, 48, 56); Head = @(110, 170, 240)
        SelA = @(36, 76, 134); SelText = @(255, 255, 255); Sky = @(30, 34, 44); StatB = @(30, 33, 40)
        CyanTxt = @(255, 255, 255); Ok = @(110, 230, 160); Radius = 5
        T1A = @(255, 255, 255); T1B = @(206, 212, 226); T2A = @(64, 156, 255); T2B = @(64, 156, 255); TShadowA = 0
        Shape = 'soft'; Hdr = 'sleek'; Fx = 'flat'; Anim = $true
        Fonts = @('Segoe UI Semibold', 'Segoe UI'); TFonts = @('Segoe UI Light', 'Segoe UI'); TStyle = 'Regular'; TSize = 22
    }
    'Glitch' = @{
        Bg = @(6, 0, 0); Panel = @(17, 5, 6); Panel2 = @(34, 9, 11); Hover = @(72, 14, 18)
        Text = @(244, 230, 230); Dim = @(176, 120, 122)
        Accent = @(255, 28, 40); AccentHover = @(255, 96, 96); AccentDown = @(180, 8, 18)
        Cyan = @(214, 218, 226); Purple = @(140, 14, 22); Orange = @(255, 100, 30); Sun = @(255, 60, 50)
        Danger = @(30, 0, 0); DangerHover = @(100, 0, 8); DangerEdge = @(170, 24, 30); DangerTxt = @(255, 120, 120)
        SelA = @(110, 12, 18); SelText = @(255, 235, 235); Sky = @(52, 0, 8); StatB = @(40, 6, 10)
        CyanTxt = @(10, 0, 0); T1B = @(255, 70, 70); T2A = @(214, 218, 226); T2B = @(255, 28, 40); TShadow = @(140, 14, 22)
        Shape = 'square'; Hdr = 'glitch'; Fx = 'glitch'; Anim = $true
        Fonts = @('Bahnschrift', 'Segoe UI Semibold'); TFonts = @('Bahnschrift', 'Consolas'); TStyle = 'Bold'; TSize = 21
    }
    'Kawaii' = @{
        Light = $true
        Bg = @(255, 238, 245); Panel = @(255, 225, 238); Panel2 = @(255, 206, 226); Hover = @(255, 182, 212)
        Text = @(98, 40, 80); Dim = @(168, 96, 146)
        Accent = @(255, 98, 160); AccentHover = @(255, 140, 188); AccentDown = @(220, 60, 125)
        Cyan = @(120, 190, 255); Purple = @(196, 150, 255); Orange = @(255, 168, 120); Sun = @(255, 224, 110)
        Danger = @(255, 214, 220); DangerHover = @(255, 170, 185); DangerB = @(255, 192, 204); DangerEdge = @(226, 60, 100); DangerTxt = @(190, 30, 70)
        BtnA = @(255, 238, 246); BtnB = @(255, 216, 234); Head = @(214, 70, 150)
        SelA = @(255, 190, 218); SelText = @(98, 40, 80); Track = @(255, 200, 222)
        MenuBack = @(255, 236, 244); MenuSel = @(255, 198, 224); Inner = @(255, 248, 252); BoxTop = @(255, 238, 246)
        Sky = @(255, 196, 228); Ground = @(255, 214, 232); DlgA = @(255, 240, 247); DlgB = @(255, 214, 232)
        StatB = @(255, 206, 226); StatText = @(140, 50, 110); Ok = @(20, 150, 90)
        CyanTxt = @(80, 40, 120); T1A = @(255, 255, 255); T1B = @(255, 98, 160); T2A = @(120, 180, 255); T2B = @(190, 140, 255); TShadow = @(160, 100, 210)
        Shape = 'round'; Hdr = 'kawaii'; Fx = 'none'; Anim = $true
        Fonts = @('Trebuchet MS', 'Segoe UI Semibold'); TFonts = @('Segoe Print', 'Trebuchet MS'); TStyle = 'Bold'; TSize = 19
    }
    'Aurora' = @{
        Bg = @(4, 8, 20); Panel = @(10, 17, 36); Panel2 = @(18, 32, 62); Hover = @(30, 58, 100)
        Text = @(226, 240, 255); Dim = @(122, 150, 190)
        Accent = @(52, 224, 168); AccentHover = @(130, 250, 205); AccentDown = @(24, 160, 120)
        Cyan = @(100, 190, 255); Purple = @(140, 100, 250); Orange = @(255, 140, 200); Sun = @(180, 255, 170)
        Danger = @(44, 8, 28); DangerHover = @(104, 20, 64); DangerEdge = @(255, 110, 160); DangerTxt = @(255, 150, 190)
        SelA = @(24, 84, 100); SelText = @(220, 255, 245); Sky = @(10, 56, 78); StatB = @(14, 40, 62)
        PrimTxt = @(2, 22, 18); T1B = @(130, 250, 205); T2A = @(100, 190, 255); T2B = @(190, 140, 255); TShadow = @(24, 160, 120)
        Shape = 'soft'; Hdr = 'aurora'; Fx = 'none'; Anim = $true; Radius = 9
        Fonts = @('Segoe UI Semibold', 'Segoe UI'); TFonts = @('Segoe UI Semibold', 'Segoe UI'); TStyle = 'Bold'; TSize = 21
    }

    'Gothic' = @{
        Bg = @(10, 6, 8); Panel = @(22, 12, 16); Panel2 = @(44, 20, 28); Hover = @(86, 30, 44)
        Text = @(232, 222, 214); Dim = @(150, 128, 120)
        Accent = @(176, 16, 40); AccentHover = @(214, 60, 70); AccentDown = @(120, 8, 24)
        Cyan = @(196, 160, 84); Purple = @(110, 46, 78); Orange = @(150, 96, 44); Sun = @(212, 175, 90)
        Danger = @(30, 0, 6); DangerHover = @(84, 6, 20); DangerEdge = @(176, 16, 40); DangerTxt = @(224, 110, 110)
        SelA = @(96, 20, 36); SelText = @(245, 232, 215); Sky = @(46, 10, 26); StatB = @(40, 14, 22)
        PrimTxt = @(246, 236, 224); CyanTxt = @(24, 12, 4); Head = @(212, 175, 90)
        T1A = @(244, 236, 224); T1B = @(212, 175, 90); T2A = @(214, 60, 70); T2B = @(150, 20, 40); TShadow = @(0, 0, 0)
        Shape = 'gothic'; Hdr = 'gothic'; Fx = 'none'; Anim = $true
        Fonts = @('Palatino Linotype', 'Georgia'); TFonts = @('Palatino Linotype', 'Georgia'); TStyle = 'Bold'; TSize = 21
    }
    'RGB' = @{
        Bg = @(9, 9, 13); Panel = @(19, 19, 28); Panel2 = @(32, 32, 48); Hover = @(54, 54, 82)
        Text = @(240, 242, 255); Dim = @(140, 146, 176)
        Accent = @(255, 50, 130); AccentHover = @(255, 120, 180); AccentDown = @(200, 24, 100)
        Cyan = @(0, 255, 200); Purple = @(140, 80, 255); Orange = @(255, 200, 0); Sun = @(255, 220, 40)
        Danger = @(44, 8, 20); DangerHover = @(100, 16, 44); DangerEdge = @(255, 70, 90); DangerTxt = @(255, 140, 150)
        SelA = @(60, 40, 120); SelText = @(255, 255, 255); Sky = @(26, 20, 48); StatB = @(26, 22, 44)
        PrimTxt = @(255, 255, 255); CyanTxt = @(6, 10, 14)
        T1A = @(255, 255, 255); T1B = @(0, 255, 200); T2A = @(255, 200, 0); T2B = @(255, 50, 130); TShadow = @(140, 80, 255)
        Shape = 'soft'; Hdr = 'rgb'; Fx = 'none'; Anim = $true; Radius = 8
        Fonts = @('Bahnschrift', 'Segoe UI Semibold'); TFonts = @('Bahnschrift', 'Segoe UI Semibold'); TStyle = 'Bold'; TSize = 21
    }
    'Blueprint' = @{
        Bg = @(8, 34, 80); Panel = @(12, 46, 104); Panel2 = @(20, 64, 132); Hover = @(36, 92, 170)
        Text = @(228, 242, 255); Dim = @(140, 178, 224)
        Accent = @(255, 196, 40); AccentHover = @(255, 222, 120); AccentDown = @(205, 150, 10)
        Cyan = @(130, 210, 255); Purple = @(96, 150, 230); Orange = @(255, 150, 50); Sun = @(255, 214, 90)
        Danger = @(60, 20, 44); DangerHover = @(120, 30, 60); DangerEdge = @(255, 120, 130); DangerTxt = @(255, 170, 170)
        SelA = @(40, 100, 180); SelText = @(255, 255, 255); Sky = @(14, 58, 124); StatB = @(14, 54, 116)
        PrimTxt = @(8, 30, 70); CyanTxt = @(8, 30, 70); Ok = @(140, 255, 200)
        T1A = @(255, 255, 255); T1B = @(190, 226, 255); T2A = @(255, 214, 90); T2B = @(255, 150, 50); TShadow = @(6, 24, 60)
        Shape = 'square'; Hdr = 'blueprint'; Fx = 'tick'; Anim = $true
        Fonts = @('Consolas', 'Lucida Console'); TFonts = @('Consolas', 'Lucida Console'); TStyle = 'Bold'; TSize = 20
    }
    'Galaxy' = @{
        Bg = @(6, 4, 24); Panel = @(14, 10, 42); Panel2 = @(30, 22, 74); Hover = @(62, 46, 124)
        Text = @(232, 230, 255); Dim = @(150, 146, 208)
        Accent = @(146, 112, 255); AccentHover = @(190, 164, 255); AccentDown = @(100, 70, 210)
        Cyan = @(80, 222, 255); Purple = @(255, 112, 206); Orange = @(255, 176, 96); Sun = @(255, 228, 150)
        Danger = @(52, 8, 44); DangerHover = @(112, 22, 76); DangerEdge = @(255, 112, 206); DangerTxt = @(255, 170, 226)
        SelA = @(72, 52, 156); SelText = @(242, 240, 255); Sky = @(26, 14, 74); StatB = @(18, 12, 54)
        PrimTxt = @(10, 6, 34); CyanTxt = @(6, 10, 34); Ok = @(120, 255, 205)
        T1A = @(255, 255, 255); T1B = @(204, 192, 255); T2A = @(110, 232, 255); T2B = @(255, 132, 214); TShadow = @(70, 36, 160)
        Shape = 'round'; Hdr = 'galaxy'; Fx = 'none'; Anim = $true
        Fonts = @('Segoe UI Semibold', 'Segoe UI'); TFonts = @('Agency FB', 'OCR A Extended', 'Bahnschrift', 'Segoe UI Semibold'); TStyle = 'Bold'; TSize = 25
    }
    'Shinobi' = @{
        Bg = @(12, 9, 14); Panel = @(26, 20, 30); Panel2 = @(50, 36, 52); Hover = @(92, 58, 74)
        Text = @(242, 232, 232); Dim = @(176, 152, 160)
        Accent = @(214, 40, 66); AccentHover = @(250, 102, 122); AccentDown = @(150, 20, 42)
        Cyan = @(255, 170, 198); Purple = @(160, 92, 140); Orange = @(255, 150, 96); Sun = @(255, 238, 204)
        Danger = @(44, 8, 18); DangerHover = @(104, 18, 36); DangerEdge = @(250, 102, 122); DangerTxt = @(255, 160, 170)
        SelA = @(120, 30, 52); SelText = @(255, 240, 240); Sky = @(52, 16, 40); StatB = @(34, 12, 26)
        PrimTxt = @(255, 255, 255); CyanTxt = @(40, 8, 20); Ok = @(150, 255, 190)
        T1A = @(255, 255, 255); T1B = @(255, 204, 214); T2A = @(255, 170, 198); T2B = @(214, 40, 66); TShadow = @(120, 10, 30)
        Shape = 'chamfer'; Hdr = 'shinobi'; Fx = 'none'; Anim = $true
        Fonts = @('Bahnschrift', 'Segoe UI Semibold'); TFonts = @('Yu Mincho', 'MS Mincho', 'Yu Gothic', 'Segoe UI Black'); TStyle = 'Bold'; TSize = 22
    }
}
$script:themeName = 'Retrowave'
$script:themeShape = 'chamfer'; $script:themeHdr = 'retro'; $script:themeFx = 'none'
$script:themeAnim = $false; $script:themeLight = $false; $script:themeRadius = 6
$script:themeFonts = @('Bahnschrift', 'Segoe UI Semibold')
$script:titleFonts = @('Bahnschrift', 'Segoe UI Semibold'); $script:titleStyle = 'Bold, Italic'; $script:titleSize = 21
$script:titleFamily = $null
$script:hdrPhase = 0

function Set-Theme([string]$name) {
    if ($name -eq 'Wallpaper') { try { $script:Themes['Wallpaper'] = New-WallpaperTheme } catch { $name = 'Retrowave' } }
    if (-not $script:Themes.ContainsKey($name)) { $name = 'Retrowave' }
    $script:themeName = $name
    $t = $script:Themes[$name]
    $mk = { param($a) [System.Drawing.Color]::FromArgb([int]$a[0], [int]$a[1], [int]$a[2]) }
    $get = { param($key, $def) if ($t.ContainsKey($key)) { & $mk $t[$key] } else { $def } }
    $black = [System.Drawing.Color]::Black
    $white = [System.Drawing.Color]::White

    $script:cBg = & $mk $t.Bg;  $script:cPanel = & $mk $t.Panel;  $script:cPanel2 = & $mk $t.Panel2;  $script:cHover = & $mk $t.Hover
    $script:cText = & $mk $t.Text;  $script:cDim = & $mk $t.Dim
    $script:cAccent = & $mk $t.Accent;  $script:cAccentHover = & $mk $t.AccentHover;  $script:cAccentDown = & $mk $t.AccentDown
    $script:cCyan = & $mk $t.Cyan;  $script:cPurple = & $mk $t.Purple;  $script:cOrange = & $mk $t.Orange;  $script:cSun = & $mk $t.Sun
    $script:cDanger = & $mk $t.Danger;  $script:cDangerHover = & $mk $t.DangerHover

    $script:cDangerB    = & $get 'DangerB'    (Get-Blend $script:cDanger $script:cDangerHover 0.4)
    $script:cDangerEdge = & $get 'DangerEdge' $script:cAccent
    $script:cDangerTxt  = & $get 'DangerTxt'  $script:cAccentHover
    $script:cBtnA       = & $get 'BtnA'       (Get-Blend $script:cPanel $script:cPanel2 0.55)
    $script:cBtnB       = & $get 'BtnB'       (Get-Blend $script:cPanel2 $script:cHover 0.37)
    $script:cHead       = & $get 'Head'       $script:cCyan
    $script:cSelA       = & $get 'SelA'       $script:cHover
    $script:cSelText    = & $get 'SelText'    $script:cText
    $script:cTrack      = & $get 'Track'      (Get-Blend $script:cBg $script:cPanel2 0.7)
    $script:cMenuBack   = & $get 'MenuBack'   $script:cPanel
    $script:cMenuSel    = & $get 'MenuSel'    $script:cHover
    $script:cInner      = & $get 'Inner'      (Get-Blend $script:cBg $script:cPanel2 0.35)
    $script:cBoxTop     = & $get 'BoxTop'     (Get-Blend $script:cPanel2 $script:cHover 0.2)
    $script:cSky        = & $get 'Sky'        (Get-Blend $script:cBg $script:cAccent 0.15)
    $script:cGround     = & $get 'Ground'     (Get-Blend $script:cBg $black 0.15)
    $script:cDlgA       = & $get 'DlgA'       (Get-Blend $script:cBg $script:cPanel 0.4)
    $script:cDlgB       = & $get 'DlgB'       (Get-Blend $script:cPanel $script:cPanel2 0.5)
    $script:cStatB      = & $get 'StatB'      $script:cDlgB
    $script:cStatText   = & $get 'StatText'   (Get-Blend $script:cText $script:cCyan 0.3)
    $script:cOk         = & $get 'Ok'         ([System.Drawing.Color]::FromArgb(120, 255, 190))
    $script:cPrimTxt    = & $get 'PrimTxt'    $white
    $script:cCyanTxt    = & $get 'CyanTxt'    $script:cBg
    $script:cT1A        = & $get 'T1A'        $white
    $script:cT1B        = & $get 'T1B'        (Get-Blend $script:cText $script:cAccentHover 0.5)
    $script:cT2A        = & $get 'T2A'        $script:cCyan
    $script:cT2B        = & $get 'T2B'        (Get-Blend $script:cCyan $script:cPurple 0.6)
    $script:cTShadow    = & $get 'TShadow'    $script:cPurple
    $script:cBarBg      = Get-Blend $script:cBg $script:cPanel 0.5
    $script:titleShadowA = 170
    if ($t.ContainsKey('TShadowA')) { $script:titleShadowA = [int]$t.TShadowA }

    $script:themeShape = [string]$t.Shape
    $script:themeHdr = [string]$t.Hdr
    $script:themeFx = [string]$t.Fx
    $script:themeAnim = [bool]$t.Anim
    $script:themeLight = [bool]$t.Light
    $script:themeRadius = 6
    if ($t.ContainsKey('Radius')) { $script:themeRadius = [int]$t.Radius }
    $script:themeFonts = $t.Fonts
    $script:titleFonts = $t.TFonts
    $script:titleStyle = [string]$t.TStyle
    $script:titleSize = [single]$t.TSize
    $script:retroFamily = $null
    $script:titleFamily = $null
    $script:pillState = 0; $script:pillT0 = [Environment]::TickCount
    Write-SplashTheme
    if (Get-Command Start-AudioReact -ErrorAction SilentlyContinue) {
        if ($script:themeHdr -eq 'rgb') { Start-AudioReact } else { Stop-AudioReact }
    }
}

# the loading window in the exe starts before PowerShell is ready, so it reads its colors from this little file
function Write-SplashTheme {
    try {
        $rgb = { param($x) ("{0},{1},{2}" -f $x.R, $x.G, $x.B) }
        $letters = $script:cCyan
        if ($script:themeLight) { $letters = $script:cText }
        $lines = @(
            ("bgTop=" + (& $rgb $script:cPanel2)), ("bgBottom=" + (& $rgb $script:cBg)),
            ("edge=" + (& $rgb $script:cAccent)), ("sunTop=" + (& $rgb $script:cSun)), ("sunBottom=" + (& $rgb $script:cAccent)),
            ("letters=" + (& $rgb $letters)), ("zero=" + (& $rgb $script:cAccent)), ("sub=" + (& $rgb $script:cDim)),
            ("bar1=" + (& $rgb $script:cAccent)), ("bar2=" + (& $rgb $script:cCyan)), ("cut=" + (& $rgb $script:cBg)),
            ("font=" + (Get-FirstFont $script:titleFonts 'Arial Black')),
            ("text=" + (& $rgb $script:cText)), ("light=" + $(if ($script:themeLight) { '1' } else { '0' })),
            ("style=" + $script:themeName.ToLowerInvariant().Replace("digital rain", "matrix")),
            ("nosplash=" + $(if ([string](Get-Settings).NoSplash -eq '1') { '1' } else { '0' })),
            ("accent=" + (& $rgb $script:cAccent)), ("cyan=" + (& $rgb $script:cCyan)), ("purple=" + (& $rgb $script:cPurple)),
            ("orange=" + (& $rgb $script:cOrange)), ("sun=" + (& $rgb $script:cSun)), ("ok=" + (& $rgb $script:cOk))
        )
        Set-Content -LiteralPath (Join-Path $PSScriptRoot 'splash-theme.txt') -Value $lines -Encoding ASCII
    } catch { }
}

# Applies the theme's colors to a window's title bar (dark or light).
function Set-TitleBar($hwnd) {
    try {
        $c = $script:cBg; $x = $script:cText
        $cap = ([int]$c.B -shl 16) -bor ([int]$c.G -shl 8) -bor [int]$c.R
        $txt = ([int]$x.B -shl 16) -bor ([int]$x.G -shl 8) -bor [int]$x.R
        [DarkTitle]::Custom($hwnd, (-not $script:themeLight), $cap, $txt)
    } catch { }
}

function Get-FirstFont([string[]]$names, [string]$fallback = 'Segoe UI') {
    $installed = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }
    foreach ($f in $names) { if ($installed -contains $f) { return $f } }
    return $fallback
}

function Restart-App {
    $vbs = Join-Path $PSScriptRoot "Launch.vbs"
    $appExe = Get-AppExe
    if ($appExe) {
        $cmd = 'ping -n 3 127.0.0.1 >nul & start "" "' + $appExe + '"'
    } elseif (Test-Path -LiteralPath $vbs) {
        $cmd = 'ping -n 3 127.0.0.1 >nul & start "" wscript.exe "' + $vbs + '"'
    } else {
        $cmd = 'ping -n 3 127.0.0.1 >nul & start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $PSCommandPath + '"'
    }
    try { Start-Process -FilePath "cmd.exe" -ArgumentList "/c $cmd" -WindowStyle Hidden } catch { }
    $script:exiting = $true
    $script:form.Close()
}

# ---------------------------------------------------------------- theme made from your wallpaper
function Get-DesktopWallpaperPath {
    try {
        $p = [string](Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction Stop).WallPaper
        if ($p -and (Test-Path -LiteralPath $p)) { return $p }
    } catch { }
    $t = Join-Path $env:APPDATA 'Microsoft\Windows\Themes\TranscodedWallpaper'
    if (Test-Path -LiteralPath $t) { return $t }
    return $null
}

function ConvertFrom-Hsl([double]$h, [double]$s, [double]$l) {
    $h = (($h % 360) + 360) % 360
    $c = (1 - [math]::Abs(2 * $l - 1)) * $s
    $x = $c * (1 - [math]::Abs((($h / 60) % 2) - 1))
    $m = $l - $c / 2
    switch ([int][math]::Floor($h / 60)) {
        0 { $r = $c; $g = $x; $b = 0 }
        1 { $r = $x; $g = $c; $b = 0 }
        2 { $r = 0; $g = $c; $b = $x }
        3 { $r = 0; $g = $x; $b = $c }
        4 { $r = $x; $g = 0; $b = $c }
        default { $r = $c; $g = 0; $b = $x }
    }
    return @([int][math]::Round(($r + $m) * 255), [int][math]::Round(($g + $m) * 255), [int][math]::Round(($b + $m) * 255))
}

# Looks at the colors of the current desktop picture and builds a palette around its two main hues.
function New-WallpaperTheme {
    $hue1 = 280.0; $hue2 = 130.0; $avgL = 0.3
    $path = $null
    try {
        $cp = [string]$script:currentPack
        if (-not $cp) { $cp = [string](Get-Settings).LastPack }
        if ($cp -and (Test-Path -LiteralPath (Join-Path $Root $cp))) {
            $im = @(Get-PackImages (Join-Path $Root $cp))
            if ($im.Count -gt 0) { $path = $im[[int][math]::Floor(($im.Count - 1) / 2)].FullName }
        }
    } catch { }
    if (-not $path) { $path = Get-DesktopWallpaperPath }
    if ($script:wpHdrImg) { try { $script:wpHdrImg.Dispose() } catch { }; $script:wpHdrImg = $null }
    if ($path) {
        try {
            $bytes = [IO.File]::ReadAllBytes($path)
            $ms = New-Object IO.MemoryStream(, $bytes)
            $img = [System.Drawing.Image]::FromStream($ms)
            $bmp = New-Object System.Drawing.Bitmap(40, 40, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $gr = [System.Drawing.Graphics]::FromImage($bmp)
            $gr.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
            $gr.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, 40, 40)))
            $gr.Dispose()
            # soft strip of the picture for the header (small on purpose: stretching it blurs it)
            try {
                $hw = 235; $hh2 = 27
                $strip = New-Object System.Drawing.Bitmap($hw, $hh2, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
                $g2 = [System.Drawing.Graphics]::FromImage($strip)
                $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
                $sw0 = [double]$img.Width; $sh0 = [double]$img.Height
                $dr0 = $hw / [double]$hh2
                if (($sw0 / $sh0) -gt $dr0) { $cw0 = $sh0 * $dr0; $srcR = New-Object System.Drawing.RectangleF([single](($sw0 - $cw0) / 2), [single]0, [single]$cw0, [single]$sh0) }
                else { $ch0 = $sw0 / $dr0; $srcR = New-Object System.Drawing.RectangleF([single]0, [single](($sh0 - $ch0) / 2), [single]$sw0, [single]$ch0) }
                $g2.DrawImage($img, (New-Object System.Drawing.RectangleF([single]0, [single]0, [single]$hw, [single]$hh2)), $srcR, [System.Drawing.GraphicsUnit]::Pixel)
                $g2.Dispose()
                $script:wpHdrImg = $strip
            } catch { }
            $img.Dispose(); $ms.Dispose()
            $wt = New-Object 'double[]' 12; $sn = New-Object 'double[]' 12; $cs = New-Object 'double[]' 12
            $lum = 0.0
            for ($y = 0; $y -lt 40; $y++) {
                for ($x = 0; $x -lt 40; $x++) {
                    $c = $bmp.GetPixel($x, $y)
                    $l = $c.GetBrightness(); $sat = $c.GetSaturation(); $hh = $c.GetHue()
                    $lum += $l
                    if ($sat -gt 0.25 -and $l -gt 0.15 -and $l -lt 0.9) {
                        $bk = [int][math]::Floor($hh / 30) % 12
                        $w = $sat * (1 - [math]::Abs($l - 0.5))
                        $wt[$bk] += $w
                        $sn[$bk] += $w * [math]::Sin($hh * [math]::PI / 180)
                        $cs[$bk] += $w * [math]::Cos($hh * [math]::PI / 180)
                    }
                }
            }
            $bmp.Dispose()
            $avgL = $lum / 1600.0
            $best = 0
            for ($i = 1; $i -lt 12; $i++) { if ($wt[$i] -gt $wt[$best]) { $best = $i } }
            if ($wt[$best] -gt 1.0) {
                $hue1 = [math]::Atan2($sn[$best], $cs[$best]) * 180 / [math]::PI
                $b2 = -1
                for ($i = 0; $i -lt 12; $i++) {
                    $d = [math]::Abs($i - $best); if ($d -gt 6) { $d = 12 - $d }
                    if ($d -ge 2 -and ($b2 -lt 0 -or $wt[$i] -gt $wt[$b2])) { $b2 = $i }
                }
                if ($b2 -ge 0 -and $wt[$b2] -gt 0.12 * $wt[$best]) { $hue2 = [math]::Atan2($sn[$b2], $cs[$b2]) * 180 / [math]::PI }
                else { $hue2 = $hue1 + 150 }
            }
        } catch { }
    }
    $t = @{
        Bg = (ConvertFrom-Hsl $hue1 0.5 0.055); Panel = (ConvertFrom-Hsl $hue1 0.45 0.11); Panel2 = (ConvertFrom-Hsl $hue1 0.42 0.2); Hover = (ConvertFrom-Hsl $hue1 0.4 0.3)
        Text = (ConvertFrom-Hsl $hue1 0.3 0.94); Dim = (ConvertFrom-Hsl $hue1 0.25 0.7)
        Accent = (ConvertFrom-Hsl $hue1 0.85 0.58); AccentHover = (ConvertFrom-Hsl $hue1 0.9 0.72); AccentDown = (ConvertFrom-Hsl $hue1 0.8 0.42)
        Cyan = (ConvertFrom-Hsl $hue2 0.85 0.62); Purple = (ConvertFrom-Hsl ($hue2 + 40) 0.6 0.55)
        Orange = (ConvertFrom-Hsl ($hue1 + 35) 0.9 0.6); Sun = (ConvertFrom-Hsl ($hue1 + 55) 0.9 0.7)
        Danger = (ConvertFrom-Hsl 340 0.6 0.12); DangerHover = (ConvertFrom-Hsl 340 0.6 0.28); DangerEdge = (ConvertFrom-Hsl 350 0.85 0.62); DangerTxt = (ConvertFrom-Hsl 350 0.9 0.78)
        Sky = (ConvertFrom-Hsl $hue1 0.55 0.2); PrimTxt = @(255, 255, 255)
        Shape = 'round'; Hdr = 'wallpaper'; Fx = 'none'; Anim = $true; Radius = 10
        Fonts = @('Segoe UI Semibold', 'Segoe UI'); TFonts = @('Segoe UI Semibold', 'Segoe UI'); TStyle = 'Bold'; TSize = 21
    }
    return $t
}
# ---------------------------------------------------------------- UI
[void][DpiHelper]::SetProcessDPIAware()
[System.Windows.Forms.Application]::EnableVisualStyles()

$gfxProbe = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
$script:dpiScale = $gfxProbe.DpiX / 96.0
$gfxProbe.Dispose()

$script:retroFamily  = $null

function Get-RetroFont([single]$size, [string]$style = 'Bold') {
    if ($null -eq $script:retroFamily) {
        $script:retroFamily = "Segoe UI"
        $installed = (New-Object System.Drawing.Text.InstalledFontCollection).Families | ForEach-Object { $_.Name }
        foreach ($f in $script:themeFonts) {
            if ($installed -contains $f) { $script:retroFamily = $f; break }
        }
    }
    return (New-Object System.Drawing.Font($script:retroFamily, $size, [System.Drawing.FontStyle]$style))
}

function Set-DoubleBuffered($c) {
    try { $c.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($c, $true, $null) } catch { }
}

function Get-Blend($a, $b, [double]$t) {
    return [System.Drawing.Color]::FromArgb(255,
        [int]($a.R + ($b.R - $a.R) * $t),
        [int]($a.G + ($b.G - $a.G) * $t),
        [int]($a.B + ($b.B - $a.B) * $t))
}

$savedTheme = [string](Get-Settings).Theme
if ($savedTheme -eq 'Matrix') { $savedTheme = 'Digital Rain'; Save-Setting 'Theme' $savedTheme }
Set-Theme $savedTheme

# ---------------------------------------------------------------- neon buttons
# Corner-clipped shape (top-left and bottom-right) with a gradient fill and a neon edge.
function New-ChamferPath([single]$w, [single]$h, [single]$c) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $pts = [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF(($c + 0.5), 0.5)),
        (New-Object System.Drawing.PointF(($w - 1.5), 0.5)),
        (New-Object System.Drawing.PointF(($w - 1.5), ($h - 1.5 - $c))),
        (New-Object System.Drawing.PointF(($w - 1.5 - $c), ($h - 1.5))),
        (New-Object System.Drawing.PointF(0.5, ($h - 1.5))),
        (New-Object System.Drawing.PointF(0.5, ($c + 0.5)))
    )
    $p.AddPolygon($pts)
    return $p
}

function New-ThemePath([single]$w, [single]$h, [single]$c) {
    switch ($script:themeShape) {
        'cyber' {
            $k = [single][math]::Min(14, [math]::Floor([double]($h / 2.4)))
            $p = New-Object System.Drawing.Drawing2D.GraphicsPath
            $pts = [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF(0.5, 0.5)),
                (New-Object System.Drawing.PointF(($w - 1.5 - $k), 0.5)),
                (New-Object System.Drawing.PointF(($w - 1.5), ($k + 0.5))),
                (New-Object System.Drawing.PointF(($w - 1.5), ($h - 1.5))),
                (New-Object System.Drawing.PointF(($k + 0.5), ($h - 1.5))),
                (New-Object System.Drawing.PointF(0.5, ($h - 1.5 - $k)))
            )
            $p.AddPolygon($pts)
            return $p
        }
        'gothic' {
            $k = [single][math]::Min(12, [math]::Floor([double]($h / 2.2)))
            $p = New-Object System.Drawing.Drawing2D.GraphicsPath
            $pts = [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF(($k + 0.5), 0.5)),
                (New-Object System.Drawing.PointF(($w - 1.5 - $k), 0.5)),
                (New-Object System.Drawing.PointF(($w - 1.5), ($h / 2))),
                (New-Object System.Drawing.PointF(($w - 1.5 - $k), ($h - 1.5))),
                (New-Object System.Drawing.PointF(($k + 0.5), ($h - 1.5))),
                (New-Object System.Drawing.PointF(0.5, ($h / 2)))
            )
            $p.AddPolygon($pts)
            return $p
        }
        'soft' {
            $r = New-Object System.Drawing.RectangleF(0.5, 0.5, ($w - 2), ($h - 2))
            return (New-RoundPath $r ([single][math]::Min($script:themeRadius, $h / 2 - 1)))
        }
        'round' {
            $r = New-Object System.Drawing.RectangleF(0.5, 0.5, ($w - 2), ($h - 2))
            return (New-RoundPath $r ([single]($h / 2 - 1)))
        }
        'square' {
            $p = New-Object System.Drawing.Drawing2D.GraphicsPath
            $p.AddRectangle((New-Object System.Drawing.RectangleF(0.5, 0.5, ($w - 2), ($h - 2))))
            return $p
        }
        default { return (New-ChamferPath $w $h $c) }
    }
}

function Invoke-NeonButtonPaint($b, $e) {
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $st = $b.Tag
    $w = [single]$b.ClientSize.Width
    $h = [single]$b.ClientSize.Height
    if ($w -lt 4 -or $h -lt 4) { return }
    $g.Clear($script:cBg)

    $border = $null
    $angle = [single]90
    switch ($st.Kind) {
        'primary' { $c1 = $script:cAccent; $c2 = $script:cOrange; $txt = $script:cPrimTxt; $angle = [single]0; $glow = $script:cAccent }
        'cyan'    { $c1 = $script:cCyan; $c2 = $script:cPurple; $txt = $script:cCyanTxt; $angle = [single]0; $glow = $script:cCyan }
        'danger'  { $c1 = $script:cDanger; $c2 = $script:cDangerB; $border = $script:cDangerEdge; $txt = $script:cDangerTxt; $glow = $script:cDangerEdge }
        default   { $c1 = $script:cBtnA; $c2 = $script:cBtnB; $border = $script:cCyan; $txt = $script:cText; $glow = $script:cCyan }
    }
    if ($border -and $script:themeFx -eq 'rgb') { $border = Get-HueColor (($script:hdrPhase * 9 + $b.Left / 2.0 + $b.Top) % 360) }
    $white = [System.Drawing.Color]::White
    $black = [System.Drawing.Color]::Black
    if ($st.Down) { $c1 = Get-Blend $c1 $black 0.28; $c2 = Get-Blend $c2 $black 0.28 }
    elseif ($st.Hover) { $c1 = Get-Blend $c1 $white 0.16; $c2 = Get-Blend $c2 $white 0.16 }

    $chamfer = [math]::Min(10, [math]::Floor([double]($h / 3)))
    $path = New-ThemePath $w $h $chamfer
    $flat = ($script:themeFx -eq 'flat')
    if ($st.Hover -and -not $st.Down -and -not $flat) {
        $gp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70, $glow), 5)
        $gp.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawPath($gp, $path)
        $gp.Dispose()
    }
    $rect = New-Object System.Drawing.RectangleF(0, 0, $w, $h)
    $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, $angle)
    $g.FillPath($fill, $path)
    $fill.Dispose()
    if ($border) {
        if ($st.Hover) { $bc = Get-Blend $border $white 0.35 } else { $bc = $border }
        $pen = New-Object System.Drawing.Pen($bc, 1.6)
        $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
        $g.DrawPath($pen, $path)
        $pen.Dispose()
    } elseif (-not $flat) {
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, $white), 1)
        # glossy top edge, kept inside this theme's button shape
        $sx0 = [single]($chamfer + 2); $sx1 = [single]($w - 3)
        switch ($script:themeShape) {
            'round'  { $rr = [math]::Floor([double]($h / 2 - 1)); $sx0 = [single]($rr + 2); $sx1 = [single]($w - $rr - 3) }
            'soft'   { $rr = [math]::Min([double]$script:themeRadius, [double]($h / 2 - 1)); $sx0 = [single]($rr + 2); $sx1 = [single]($w - $rr - 3) }
            'square' { $sx0 = [single]3; $sx1 = [single]($w - 4) }
            'cyber'  { $kk = [math]::Min(14, [math]::Floor([double]($h / 2.4))); $sx0 = [single]4; $sx1 = [single]($w - $kk - 4) }
            'gothic' { $kk = [math]::Min(12, [math]::Floor([double]($h / 2.2))); $sx0 = [single]($kk + 4); $sx1 = [single]($w - $kk - 4) }
        }
        if ($sx1 -gt $sx0) { $g.DrawLine($pen, $sx0, [single]1.5, $sx1, [single]1.5) }
        $pen.Dispose()
    }
    if ($script:themeFx -eq 'glitch' -and ($st.Hover -or $st.Down)) {
        # RGB-split ghost outlines
        $g1 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, $script:cAccent), 1.4)
        $g2 = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(130, 0, 255, 235), 1.4)
        $g.TranslateTransform(2, 0); $g.DrawPath($g1, $path); $g.ResetTransform()
        $g.TranslateTransform(-2, 0); $g.DrawPath($g2, $path); $g.ResetTransform()
        $g1.Dispose(); $g2.Dispose()
    }
    if ($script:themeFx -eq 'tick') {
        $tp = New-Object System.Drawing.Pen($script:cAccent, 2)
        $g.DrawLine($tp, 0, 0, 7, 0); $g.DrawLine($tp, 0, 0, 0, 7)
        $g.DrawLine($tp, ($w - 1), ($h - 1), ($w - 8), ($h - 1)); $g.DrawLine($tp, ($w - 1), ($h - 1), ($w - 1), ($h - 8))
        $tp.Dispose()
    }

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $sf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $label = $b.Text.ToUpper()
    $tr = New-Object System.Drawing.RectangleF(2, 0, ($w - 4), $h)
    if ($st.Kind -eq 'primary' -and -not $flat -and -not $script:themeLight -and $script:cPrimTxt.R -gt 200) {
        $sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 60, 0, 40))
        $tr2 = New-Object System.Drawing.RectangleF(3, 1, ($w - 4), $h)
        $g.DrawString($label, $b.Font, $sb, $tr2, $sf)
        $sb.Dispose()
    }
    $tb = New-Object System.Drawing.SolidBrush($txt)
    $g.DrawString($label, $b.Font, $tb, $tr, $sf)
    $tb.Dispose(); $sf.Dispose(); $path.Dispose()
}

function Set-NeonButton($b, [string]$kind) {
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $script:cBg
    $b.FlatAppearance.MouseOverBackColor = $script:cBg
    $b.FlatAppearance.MouseDownBackColor = $script:cBg
    $b.UseVisualStyleBackColor = $false
    $b.Cursor = 'Hand'
    $b.Font = Get-RetroFont 10
    $b.Tag = @{ Kind = $kind; Hover = $false; Down = $false }
    Set-DoubleBuffered $b
    $b.Add_MouseEnter({ param($s, $e) $s.Tag.Hover = $true; $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.Hover = $false; $s.Tag.Down = $false; $s.Invalidate() })
    $b.Add_MouseDown({ param($s, $e) $s.Tag.Down = $true; $s.Invalidate() })
    $b.Add_MouseUp({ param($s, $e) $s.Tag.Down = $false; $s.Invalidate() })
    $b.Add_Paint({ param($s, $e) Invoke-NeonButtonPaint $s $e })
}

function New-Btn([string]$text, [int]$x, [int]$y, [int]$w, [string]$kind = 'normal', [int]$h = 34) {
    if ($h -gt 34) { $h = 34 }
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    Set-NeonButton $b $kind
    return $b
}

# ---------------------------------------------------------------- labels, lists, frames
function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$dim = $false, [int]$size = 10) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    if ($dim) { $l.ForeColor = $script:cDim } else { $l.ForeColor = $script:cText }
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = New-Object System.Drawing.Font("Segoe UI", $size)
    return $l
}

function New-Heading([string]$text, [int]$x, [int]$y, [int]$w = 300) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = "// " + $text.ToUpper()
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, 20)
    $l.ForeColor = $script:cHead
    $l.BackColor = [System.Drawing.Color]::Transparent
    $l.Font = Get-RetroFont 9
    return $l
}

function Set-NeonFrame($pb) {
    $pb.Add_Paint({
        param($s, $e)
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, $script:cPurple), 2)
        $e.Graphics.DrawRectangle($pen, 1, 1, ($s.Width - 3), ($s.Height - 3))
        $pen.Dispose()
    })
}

function Invoke-ListItemDraw($lb, $e) {
    if ($e.Index -lt 0) { return }
    $sel = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
    $g = $e.Graphics
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    if ($sel) {
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($e.Bounds, $script:cSelA, $script:cPanel, [single]0)
        $g.FillRectangle($gb, $e.Bounds)
        $gb.Dispose()
        $ab = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle($e.Bounds.X, $e.Bounds.Y, 4, $e.Bounds.Height)), $script:cAccent, $script:cOrange, [single]90)
        $g.FillRectangle($ab, $e.Bounds.X, $e.Bounds.Y, 4, $e.Bounds.Height)
        $ab.Dispose()
        $tcol = $script:cSelText
    } else {
        $bb = New-Object System.Drawing.SolidBrush($script:cPanel)
        $g.FillRectangle($bb, $e.Bounds)
        $bb.Dispose()
        $sp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40, $script:cPurple), 1)
        $g.DrawLine($sp, $e.Bounds.X + 12, $e.Bounds.Bottom - 1, $e.Bounds.Right - 12, $e.Bounds.Bottom - 1)
        $sp.Dispose()
        $tcol = $script:cText
    }
    $tb = New-Object System.Drawing.SolidBrush($tcol)
    $textW = $e.Bounds.Width - 24
    if ($lb.Tag -and $lb.Tag.Bar) { $textW = $lb.Width - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth - 16 - 18 }
    $rect = New-Object System.Drawing.RectangleF(($e.Bounds.X + 16), $e.Bounds.Y, $textW, $e.Bounds.Height)
    $sf = New-Object System.Drawing.StringFormat
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $sf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
    $sf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
    $g.DrawString([string]$lb.Items[$e.Index], $lb.Font, $tb, $rect, $sf)
    $sf.Dispose()
    $tb.Dispose()
    if ($lb.Tag -and $lb.Tag.Bar) { Sync-ThemedBar $lb }
}

function New-StyledList([int]$x, [int]$y, [int]$w, [int]$h) {
    $lb = New-Object System.Windows.Forms.ListBox
    $lb.Location = New-Object System.Drawing.Point($x, $y)
    $lb.Size = New-Object System.Drawing.Size($w, $h)
    $lb.BackColor = $script:cPanel
    $lb.ForeColor = $script:cText
    $lb.BorderStyle = 'None'
    $lb.Font = Get-RetroFont 11 'Regular'
    $lb.DrawMode = 'OwnerDrawFixed'
    $lb.ItemHeight = [int](38 * $script:dpiScale)
    $lb.IntegralHeight = $false
    $lb.Add_DrawItem({ param($s, $e) Invoke-ListItemDraw $s $e })
    return $lb
}

# ---------------------------------------------------------------- themed scrollbar
# The list's own (system gray) scrollbar is clipped away and replaced by a slim neon one.
function New-RoundPath([System.Drawing.RectangleF]$r, [single]$rad) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = [single]($rad * 2)
    if ($d -gt $r.Width) { $d = $r.Width }
    if ($d -gt $r.Height) { $d = $r.Height }
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc(($r.Right - $d), $r.Y, $d, $d, 270, 90)
    $p.AddArc(($r.Right - $d), ($r.Bottom - $d), $d, $d, 0, 90)
    $p.AddArc($r.X, ($r.Bottom - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

function Sync-ThemedBar($lb) {
    $st = $lb.Tag
    if (-not $st -or -not $st.Bar) { return }
    $vis = [math]::Max(1, [int][math]::Floor($lb.ClientSize.Height / [math]::Max(1, $lb.ItemHeight)))
    $cnt = $lb.Items.Count
    if ($st.Top -ne $lb.TopIndex -or $st.Count -ne $cnt -or $st.Vis -ne $vis) {
        $st.Top = $lb.TopIndex; $st.Count = $cnt; $st.Vis = $vis
        $st.Bar.Visible = ($cnt -gt $vis)
        $st.Bar.Invalidate()
    }
}

function Get-BarThumb($lb, [int]$barH) {
    $st = $lb.Tag
    $cnt = [math]::Max(1, $st.Count)
    $th = [int][math]::Max(34, $barH * $st.Vis / $cnt)
    if ($th -gt $barH) { $th = $barH }
    $maxTop = [math]::Max(1, $cnt - $st.Vis)
    $ty = [int](($barH - $th) * $lb.TopIndex / $maxTop)
    return @{ Y = $ty; H = $th }
}

function Set-ThemedBarLayout($lb) {
    $st = $lb.Tag
    $sbw = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    $visW = $lb.Width - $sbw
    if ($visW -lt 20) { return }
    $lb.Region = New-Object System.Drawing.Region((New-Object System.Drawing.Rectangle(0, 0, $visW, $lb.Height)))
    $bw = [int][math]::Round(12 * $script:dpiScale)
    $st.Bar.Size = New-Object System.Drawing.Size($bw, $lb.Height)
    $st.Bar.Location = New-Object System.Drawing.Point(($lb.Left + $visW - $bw - 2), $lb.Top)
    $st.Bar.BringToFront()
}

function Add-ThemedScroll($lb, $parent) {
    $bar = New-Object System.Windows.Forms.Panel
    $bar.BackColor = $script:cPanel
    $bar.Visible = $false
    $bar.Cursor = 'Hand'
    Set-DoubleBuffered $bar
    $lb.Tag = @{ Bar = $bar; Top = -1; Count = -1; Vis = -1; Hover = $false; Drag = $false; DragOff = 0 }
    $bar.Tag = $lb
    $lb.Width = $lb.Width + 17        # room for the system bar, which is then clipped away
    $parent.Controls.Add($bar)
    Set-ThemedBarLayout $lb

    $bar.Add_Paint({
        param($s, $e)
        $lb = $s.Tag; $st = $lb.Tag
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear($script:cPanel)
        if ($st.Count -le $st.Vis) { return }
        $cx = $s.Width / 2.0
        $trackW = [single]4
        $tr = New-Object System.Drawing.RectangleF([single]($cx - $trackW / 2), 4, $trackW, [single]($s.Height - 8))
        $tp = New-RoundPath $tr 2
        $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, $script:cTrack))
        $g.FillPath($tb, $tp)
        $tb.Dispose(); $tp.Dispose()
        $t = Get-BarThumb $lb $s.Height
        $thumbW = [single]6
        if ($st.Hover -or $st.Drag) { $thumbW = [single]8 }
        $rect = New-Object System.Drawing.RectangleF([single]($cx - $thumbW / 2), [single]($t.Y + 1), $thumbW, [single]([math]::Max(8, $t.H - 2)))
        $path = New-RoundPath $rect 3
        if ($st.Hover -or $st.Drag) {
            $gp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, $script:cAccent), 4)
            $g.DrawPath($gp, $path)
            $gp.Dispose()
        }
        $c1 = $script:cAccent; $c2 = $script:cPurple
        if ($st.Drag) { $c1 = $script:cAccentHover; $c2 = $script:cCyan }
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, [single]90)
        $g.FillPath($gb, $path)
        $gb.Dispose(); $path.Dispose()
    })
    $bar.Add_MouseEnter({ param($s, $e) $s.Tag.Tag.Hover = $true; $s.Invalidate() })
    $bar.Add_MouseLeave({ param($s, $e) $s.Tag.Tag.Hover = $false; $s.Invalidate() })
    $bar.Add_MouseDown({
        param($s, $e)
        $lb = $s.Tag; $st = $lb.Tag
        $t = Get-BarThumb $lb $s.Height
        $maxTop = [math]::Max(0, $st.Count - $st.Vis)
        if ($e.Y -ge $t.Y -and $e.Y -le ($t.Y + $t.H)) {
            $st.Drag = $true
            $st.DragOff = $e.Y - $t.Y
        } elseif ($e.Y -lt $t.Y) {
            $lb.TopIndex = [math]::Max(0, $lb.TopIndex - $st.Vis)
        } else {
            $lb.TopIndex = [math]::Min($maxTop, $lb.TopIndex + $st.Vis)
        }
        Sync-ThemedBar $lb
        $s.Invalidate()
    })
    $bar.Add_MouseMove({
        param($s, $e)
        $lb = $s.Tag; $st = $lb.Tag
        if (-not $st.Drag) { return }
        $t = Get-BarThumb $lb $s.Height
        $room = [math]::Max(1, $s.Height - $t.H)
        $maxTop = [math]::Max(0, $st.Count - $st.Vis)
        $frac = [math]::Min(1.0, [math]::Max(0.0, ($e.Y - $st.DragOff) / $room))
        $lb.TopIndex = [int][math]::Round($frac * $maxTop)
        Sync-ThemedBar $lb
        $s.Invalidate()
    })
    $bar.Add_MouseUp({ param($s, $e) $s.Tag.Tag.Drag = $false; $s.Invalidate() })
    $bar.Add_MouseWheel({
        param($s, $e)
        $lb = $s.Tag; $st = $lb.Tag
        $maxTop = [math]::Max(0, $st.Count - $st.Vis)
        if ($e.Delta -gt 0) { $lb.TopIndex = [math]::Max(0, $lb.TopIndex - 3) } else { $lb.TopIndex = [math]::Min($maxTop, $lb.TopIndex + 3) }
        Sync-ThemedBar $lb
    })
    $lb.Add_Resize({ param($s, $e) Set-ThemedBarLayout $s; Sync-ThemedBar $s })
    $lb.Add_MouseWheel({ param($s, $e) Sync-ThemedBar $s })
    $lb.Add_SelectedIndexChanged({ param($s, $e) Sync-ThemedBar $s })
    $lb.Add_KeyUp({ param($s, $e) Sync-ThemedBar $s })
}

# ---------------------------------------------------------------- neon controls (drop list, tick box, number spinner)
# If this fails to compile the app just falls back to the plain Windows controls.
$script:neonOk = $true
if (-not ('NeonCombo' -as [type])) {
    try {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using System.Runtime.InteropServices;

public class NeonCombo : ComboBox {
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr w, IntPtr l);
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x020A && !DroppedDown) {
            if (Parent != null) SendMessage(Parent.Handle, m.Msg, m.WParam, m.LParam);
            return;
        }
        base.WndProc(ref m);
    }
    public Color BoxTop = Color.FromArgb(52, 16, 100);
    public Color ItemBack = Color.FromArgb(26, 8, 56);
    public Color ItemSel = Color.FromArgb(110, 24, 140);
    public Color BoxBack = Color.FromArgb(34, 10, 70);
    public Color BoxText = Color.White;
    public Color Edge = Color.FromArgb(0, 240, 255);
    public Color Hot = Color.FromArgb(255, 41, 117);
    bool over;

    public NeonCombo() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        DropDownStyle = ComboBoxStyle.DropDownList;
        DrawMode = DrawMode.OwnerDrawFixed;
        ItemHeight = 22;
    }
    protected override void OnMouseEnter(EventArgs e) { over = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { over = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnDropDown(EventArgs e) { Invalidate(); base.OnDropDown(e); }
    protected override void OnDropDownClosed(EventArgs e) { Invalidate(); base.OnDropDownClosed(e); }
    protected override void OnSelectedIndexChanged(EventArgs e) { Invalidate(); base.OnSelectedIndexChanged(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle full = new Rectangle(0, 0, Width, Height);
        Color edge = (over || DroppedDown || Focused) ? Hot : Edge;
        using (LinearGradientBrush b = new LinearGradientBrush(full, BoxTop, BoxBack, 90f)) { g.FillRectangle(b, full); }
        using (Pen p = new Pen(edge, 1f)) { g.DrawRectangle(p, 0, 0, Width - 1, Height - 1); }
        int cx = Width - 16;
        int cy = Height / 2;
        using (Pen p = new Pen(edge, 2f)) {
            p.StartCap = LineCap.Round; p.EndCap = LineCap.Round;
            g.DrawLines(p, new Point[] { new Point(cx - 5, cy - 2), new Point(cx, cy + 3), new Point(cx + 5, cy - 2) });
        }
        string txt = "";
        if (SelectedIndex >= 0 && SelectedItem != null) { txt = GetItemText(SelectedItem); }
        TextRenderer.DrawText(g, txt, Font, new Rectangle(8, 0, Math.Max(10, Width - 30), Height), BoxText,
            TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }

    protected override void OnDrawItem(DrawItemEventArgs e) {
        if (e.Index < 0) { return; }
        bool sel = (e.State & DrawItemState.Selected) != 0;
        Color back = sel ? ItemSel : ItemBack;
        using (SolidBrush b = new SolidBrush(back)) { e.Graphics.FillRectangle(b, e.Bounds); }
        if (sel) { using (SolidBrush a = new SolidBrush(Hot)) { e.Graphics.FillRectangle(a, e.Bounds.X, e.Bounds.Y, 3, e.Bounds.Height); } }
        TextRenderer.DrawText(e.Graphics, GetItemText(Items[e.Index]), Font,
            new Rectangle(e.Bounds.X + 8, e.Bounds.Y, Math.Max(10, e.Bounds.Width - 8), e.Bounds.Height), BoxText,
            TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix);
    }
}

public class NeonCheck : CheckBox {
    public Color Inner = Color.FromArgb(30, 8, 62);
    public Color Edge = Color.FromArgb(0, 240, 255);
    public Color Hot = Color.FromArgb(255, 41, 117);
    public Color Sun = Color.FromArgb(255, 150, 40);
    bool over;

    public NeonCheck() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        AutoSize = true;
    }
    public override Size GetPreferredSize(Size proposedSize) {
        Size t = TextRenderer.MeasureText(Text == null ? "" : Text, Font);
        return new Size(18 + 10 + t.Width + 12, Math.Max(24, t.Height + 6));
    }
    protected override void OnMouseEnter(EventArgs e) { over = true; Invalidate(); base.OnMouseEnter(e); }
    protected override void OnMouseLeave(EventArgs e) { over = false; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnCheckedChanged(EventArgs e) { Invalidate(); base.OnCheckedChanged(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.None;
        g.PixelOffsetMode = PixelOffsetMode.Half;
        using (SolidBrush bg = new SolidBrush(Parent != null ? Parent.BackColor : BackColor)) { g.FillRectangle(bg, -1, -1, Width + 2, Height + 2); }
        g.SmoothingMode = SmoothingMode.AntiAlias;
        int size = 18;
        int y = (Height - size) / 2;
        Rectangle box = new Rectangle(1, y, size, size);
        Color edge = (over || Focused) ? Hot : Edge;
        if (Checked) {
            using (LinearGradientBrush b = new LinearGradientBrush(box, Hot, Sun, 90f)) { g.FillRectangle(b, box); }
        } else {
            using (SolidBrush b = new SolidBrush(Inner)) { g.FillRectangle(b, box); }
        }
        using (Pen p = new Pen(edge, 1.5f)) { g.DrawRectangle(p, box); }
        if (Checked) {
            using (Pen p = new Pen(Color.White, 2.2f)) {
                p.StartCap = LineCap.Round; p.EndCap = LineCap.Round; p.LineJoin = LineJoin.Round;
                g.DrawLines(p, new Point[] { new Point(box.X + 4, box.Y + 9), new Point(box.X + 8, box.Y + 13), new Point(box.X + 14, box.Y + 5) });
            }
        }
        using (StringFormat sf = new StringFormat(StringFormat.GenericTypographic)) {
            sf.LineAlignment = StringAlignment.Center;
            sf.Alignment = StringAlignment.Near;
            sf.Trimming = StringTrimming.EllipsisCharacter;
            sf.FormatFlags = StringFormatFlags.NoWrap | StringFormatFlags.LineLimit;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            using (SolidBrush tb = new SolidBrush(ForeColor)) {
                g.DrawString(Text, Font, tb, new RectangleF(size + 10, 0, Math.Max(10, Width - size - 10), Height), sf);
            }
        }
    }
}

public class NeonSpin : Control {
    public Color BoxTop = Color.FromArgb(52, 16, 100);
    public decimal Minimum = 0;
    public decimal Maximum = 100;
    public decimal Increment = 1;
    public int DecimalPlaces = 0;
    public Color Edge = Color.FromArgb(0, 240, 255);
    public Color Hot = Color.FromArgb(255, 41, 117);
    public Color BoxBack = Color.FromArgb(34, 10, 70);
    public event EventHandler ValueChanged;
    decimal val = 0;
    int hotZone = 0;
    int heldDir = 0;
    Timer rep;

    public NeonSpin() {
        SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.Selectable | ControlStyles.ResizeRedraw, true);
        TabStop = true;
        Size = new Size(100, 28);
        rep = new Timer();
        rep.Interval = 400;
        rep.Tick += delegate { rep.Interval = 70; Step(heldDir); };
    }

    public decimal Value {
        get { return val; }
        set {
            decimal v = Math.Max(Minimum, Math.Min(Maximum, value));
            v = Math.Round(v, DecimalPlaces);
            if (v != val) {
                val = v;
                Invalidate();
                if (ValueChanged != null) { ValueChanged(this, EventArgs.Empty); }
            } else { Invalidate(); }
        }
    }
    void Step(int dir) { Value = val + dir * Increment; }

    protected override bool IsInputKey(Keys keyData) {
        if (keyData == Keys.Up || keyData == Keys.Down || keyData == Keys.Left || keyData == Keys.Right) { return true; }
        return base.IsInputKey(keyData);
    }
    protected override void OnKeyDown(KeyEventArgs e) {
        if (e.KeyCode == Keys.Up || e.KeyCode == Keys.Right) { Step(1); e.Handled = true; }
        else if (e.KeyCode == Keys.Down || e.KeyCode == Keys.Left) { Step(-1); e.Handled = true; }
        base.OnKeyDown(e);
    }
    protected override void OnMouseWheel(MouseEventArgs e) {
        if (e.Delta > 0) { Step(1); } else { Step(-1); }
        base.OnMouseWheel(e);
    }
    const int BTN = 20;
    int ZoneAt(int x) {
        if (x < BTN) { return -1; }
        if (x > Width - BTN) { return 1; }
        return 0;
    }
    protected override void OnMouseDown(MouseEventArgs e) {
        Focus();
        int z = ZoneAt(e.X);
        if (z != 0) {
            heldDir = z;
            Step(z);
            rep.Interval = 400;
            rep.Start();
        }
        base.OnMouseDown(e);
    }
    protected override void OnMouseUp(MouseEventArgs e) { rep.Stop(); base.OnMouseUp(e); }
    protected override void OnMouseMove(MouseEventArgs e) {
        int z = ZoneAt(e.X);
        if (z != hotZone) { hotZone = z; Invalidate(); }
        base.OnMouseMove(e);
    }
    protected override void OnMouseLeave(EventArgs e) { rep.Stop(); hotZone = 0; Invalidate(); base.OnMouseLeave(e); }
    protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
    protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

    protected override void OnPaint(PaintEventArgs e) {
        Graphics g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        Rectangle full = new Rectangle(0, 0, Width, Height);
        using (LinearGradientBrush b = new LinearGradientBrush(full, BoxTop, BoxBack, 90f)) { g.FillRectangle(b, full); }
        Color edge = Focused ? Hot : Edge;
        using (Pen p = new Pen(edge, 1f)) { g.DrawRectangle(p, 0, 0, Width - 1, Height - 1); }
        int h = Height;
        int bw = BTN;
        if (hotZone == -1) { using (SolidBrush b = new SolidBrush(Color.FromArgb(90, Hot))) { g.FillRectangle(b, 1, 1, bw - 1, h - 2); } }
        if (hotZone == 1) { using (SolidBrush b = new SolidBrush(Color.FromArgb(90, Hot))) { g.FillRectangle(b, Width - bw, 1, bw - 1, h - 2); } }
        using (Pen p = new Pen(hotZone == -1 ? Color.White : Edge, 1.6f)) { g.DrawLine(p, bw / 2 - 3, h / 2, bw / 2 + 3, h / 2); }
        int rx = Width - bw / 2;
        using (Pen p = new Pen(hotZone == 1 ? Color.White : Edge, 1.6f)) {
            g.DrawLine(p, rx - 3, h / 2, rx + 3, h / 2);
            g.DrawLine(p, rx, h / 2 - 3, rx, h / 2 + 3);
        }
        using (Pen p = new Pen(Color.FromArgb(70, Edge), 1f)) {
            g.DrawLine(p, bw, 5, bw, h - 6);
            g.DrawLine(p, Width - bw, 5, Width - bw, h - 6);
        }
        TextRenderer.DrawText(g, val.ToString("F" + DecimalPlaces), Font, new Rectangle(bw, 0, Math.Max(10, Width - 2 * bw), Height), ForeColor,
            TextFormatFlags.VerticalCenter | TextFormatFlags.HorizontalCenter | TextFormatFlags.NoPrefix);
    }
}
"@
    } catch { $script:neonOk = $false }
}

$script:menuOk = $true
if (-not ('NeonMenuColors' -as [type])) {
    try {
        Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System.Drawing;
using System.Windows.Forms;

public class NeonMenuColors : ProfessionalColorTable {
    public static Color Back = Color.FromArgb(26, 8, 56);
    public static Color Sel = Color.FromArgb(110, 24, 140);
    public static Color Edge = Color.FromArgb(0, 240, 255);
    public static Color Hot = Color.FromArgb(255, 41, 117);
    public static Color Sep = Color.FromArgb(70, 40, 120);
    public override Color MenuItemSelected { get { return Sel; } }
    public override Color MenuItemSelectedGradientBegin { get { return Sel; } }
    public override Color MenuItemSelectedGradientEnd { get { return Sel; } }
    public override Color MenuItemBorder { get { return Hot; } }
    public override Color MenuBorder { get { return Edge; } }
    public override Color ToolStripDropDownBackground { get { return Back; } }
    public override Color ImageMarginGradientBegin { get { return Back; } }
    public override Color ImageMarginGradientMiddle { get { return Back; } }
    public override Color ImageMarginGradientEnd { get { return Back; } }
    public override Color SeparatorDark { get { return Sep; } }
    public override Color SeparatorLight { get { return Sep; } }
}
"@
    } catch { $script:menuOk = $false }
}

function New-NeonMenu {
    $m = New-Object System.Windows.Forms.ContextMenuStrip
    if ($script:menuOk) {
        [NeonMenuColors]::Back = $script:cMenuBack; [NeonMenuColors]::Sel = $script:cMenuSel
        [NeonMenuColors]::Edge = $script:cCyan; [NeonMenuColors]::Hot = $script:cAccent
        [NeonMenuColors]::Sep = $script:cHover
        $m.Renderer = New-Object System.Windows.Forms.ToolStripProfessionalRenderer((New-Object NeonMenuColors))
    }
    $m.BackColor = $script:cMenuBack
    $m.ForeColor = $script:cText
    $m.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $m.ShowImageMargin = $false
    return $m
}

# A small themed message window, used by the "?" buttons for the longer explanations.
function Show-Help([string]$title, [string]$text) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $title
    $dlg.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $dlg.AutoScaleMode = 'Dpi'
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:cBg
    $dlg.ForeColor = $script:cText
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    if ($script:appIcon) { $dlg.Icon = $script:appIcon }
    $dlg.Add_HandleCreated({ param($s, $e) Set-TitleBar $s.Handle })
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.AutoSize = $true
    $lbl.MaximumSize = New-Object System.Drawing.Size(440, 0)
    $lbl.Location = New-Object System.Drawing.Point(24, 20)
    $lbl.ForeColor = $script:cText
    $lbl.Text = $text
    $dlg.Controls.Add($lbl)
    $dlg.ClientSize = New-Object System.Drawing.Size(488, ($lbl.PreferredHeight + 96))
    $ok = New-Btn "Got it" 164 ($dlg.ClientSize.Height - 56) 150 'primary' 36
    $ok.DialogResult = 'OK'
    $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $ok
    [void]$dlg.ShowDialog($script:form)
    $dlg.Dispose()
}

# Small round "?" that opens the longer explanation.
function New-HelpButton([int]$x, [int]$y, [string]$title, [string]$text) {
    $b = New-Object System.Windows.Forms.Button
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size(24, 24)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $script:cBg
    $b.FlatAppearance.MouseDownBackColor = $script:cBg
    $b.BackColor = $script:cBg
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.Tag = @{ Hot = $false; Title = $title; Text = $text }
    $b.Add_MouseEnter({ param($s, $e) $s.Tag.Hot = $true; $s.Invalidate() })
    $b.Add_MouseLeave({ param($s, $e) $s.Tag.Hot = $false; $s.Invalidate() })
    $b.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        if ($s.Tag.Hot) { $c = $script:cAccent } else { $c = $script:cCyan }
        $pen = New-Object System.Drawing.Pen($c, 1.6)
        $g.DrawEllipse($pen, 2, 2, 19, 19)
        $pen.Dispose()
        $f = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $br = New-Object System.Drawing.SolidBrush($c)
        $g.DrawString("?", $f, $br, (New-Object System.Drawing.RectangleF(2, 2, 20, 20)), $sf)
        $br.Dispose(); $f.Dispose(); $sf.Dispose()
    })
    $b.Add_Click({ param($s, $e) Show-Help $s.Tag.Title $s.Tag.Text })
    return $b
}

function New-StyledCombo([int]$x, [int]$y, [int]$w) {
    if ($script:neonOk) {
        $c = New-Object NeonCombo
        $c.BoxBack = $script:cPanel2
        $c.BoxTop = $script:cBoxTop
        $c.ItemBack = $script:cMenuBack
        $c.ItemSel = $script:cMenuSel
        $c.BoxText = $script:cText
        $c.Edge = $script:cCyan
        $c.Hot = $script:cAccent
    } else {
        $c = New-Object System.Windows.Forms.ComboBox
        $c.DropDownStyle = 'DropDownList'
        $c.FlatStyle = 'Flat'
        $c.BackColor = $script:cPanel2
        $c.ForeColor = $script:cText
        $c.Add_MouseWheel({ param($s,$e) if (-not $s.DroppedDown) { $e.Handled = $true } })
    }
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, 26)
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    return $c
}

function New-NeonCheck([string]$text, [int]$x, [int]$y, [int]$w, [int]$h = 28) {
    if ($script:neonOk) {
        $c = New-Object NeonCheck
        $c.Edge = $script:cCyan
        $c.Hot = $script:cAccent
        $c.Sun = $script:cOrange
        $c.Inner = $script:cInner
    } else {
        $c = New-Object System.Windows.Forms.CheckBox
    }
    $c.Text = $text
    $c.Location = New-Object System.Drawing.Point($x, $y)
    $c.Size = New-Object System.Drawing.Size($w, $h)
    $c.ForeColor = $script:cText
    $c.BackColor = $script:cBg
    $c.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    return $c
}

function New-NeonSpin([int]$x, [int]$y, [int]$w, [decimal]$min, [decimal]$max, [int]$dec, [decimal]$inc) {
    if ($script:neonOk) {
        $n = New-Object NeonSpin
        $n.Edge = $script:cCyan
        $n.Hot = $script:cAccent
        $n.BoxBack = $script:cPanel2
        $n.BoxTop = $script:cBoxTop
    } else {
        $n = New-Object System.Windows.Forms.NumericUpDown
        $n.BackColor = $script:cPanel2
        $n.BorderStyle = 'FixedSingle'
    }
    $n.Location = New-Object System.Drawing.Point($x, $y)
    $n.Size = New-Object System.Drawing.Size($w, 26)
    $n.Minimum = $min; $n.Maximum = $max; $n.DecimalPlaces = $dec; $n.Increment = $inc
    $n.ForeColor = $script:cText
    $n.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    return $n
}

# ---------------------------------------------------------------- header art (one painter per theme)
function Get-Rnd([double]$n) {
    $v = [math]::Sin($n * 12.9898 + 78.233) * 43758.5453
    return ($v - [math]::Floor($v))
}
function Get-Alpha([int]$a, $c) { return [System.Drawing.Color]::FromArgb([int][math]::Max(0, [math]::Min(255, $a)), $c) }
function New-RectF($x, $y, $w, $h) { return (New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$w, [single]$h)) }
function New-SolidBr($c) { return (New-Object System.Drawing.SolidBrush($c)) }
function New-VGrad($rect, $c1, $c2) { return (New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, [single]90)) }

# Digital Rain: falling green glyphs (animated).
function Invoke-HdrMatrix($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    if ($null -eq $script:mxChars) {
        $script:mxFontName = Get-FirstFont @('MS Gothic', 'Consolas') 'Consolas'
        $chars = ''
        if ($script:mxFontName -eq 'MS Gothic') { for ($c = 0xFF66; $c -le 0xFF9D; $c++) { $chars += [string][char]$c } }
        $script:mxChars = $chars + '0123456789ABCDEFZ:.=*+-<>'
    }
    $font = New-Object System.Drawing.Font($script:mxFontName, 9)
    $levels = @()
    for ($a = 0; $a -lt 8; $a++) { $levels += , (New-SolidBr (Get-Alpha ([int](255 * [math]::Pow(1 - $a / 8.0, 1.6) + 12)) $script:cAccent)) }
    $head = New-SolidBr ([System.Drawing.Color]::FromArgb(220, 255, 225))
    $ph = $script:hdrPhase
    $len = $script:mxChars.Length
    $cols = [int]($w / 13)
    for ($c = 0; $c -lt $cols; $c++) {
        if ((Get-Rnd ($c * 3 + 1)) -lt 0.25) { continue }
        $speed = 1 + [int][math]::Floor((Get-Rnd ($c * 5 + 2)) * 3)
        $trail = 5 + [int][math]::Floor((Get-Rnd ($c * 7 + 3)) * 7)
        $span = [int]($h / 11) + $trail + 2
        $headRow = ([int][math]::Floor($ph * $speed * 0.5) + [int][math]::Floor((Get-Rnd ($c * 11 + 4)) * $span)) % $span
        for ($k = 0; $k -lt $trail; $k++) {
            $row = $headRow - $k
            if ($row -lt 0) { continue }
            $py = $row * 11 - 4
            if ($py -gt $h) { continue }
            $gi = [int][math]::Floor((Get-Rnd ($c * 131 + $row * 17 + [math]::Floor($ph / 6))) * $len)
            $br = $levels[[math]::Min(7, [int]($k * 8 / $trail))]
            if ($k -eq 0) { $br = $head }
            $g.DrawString([string]$script:mxChars[$gi], $font, $br, [single]($c * 13 + 2), [single]$py)
        }
    }
    foreach ($b in $levels) { $b.Dispose() }
    $head.Dispose(); $font.Dispose()
    # keep the title readable
    $dk = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF 0 0 560 $h), (Get-Alpha 215 $script:cBg), (Get-Alpha 0 $script:cBg), [single]0)
    $g.FillRectangle($dk, (New-RectF 0 0 560 $h)); $dk.Dispose()
    $sl = New-Object System.Drawing.Pen((Get-Alpha 26 ([System.Drawing.Color]::Black)), 1)
    for ($y = 0; $y -lt $h; $y += 3) { $g.DrawLine($sl, 0, $y, $w, $y) }
    $sl.Dispose()
    $ln = New-Object System.Drawing.Pen((Get-Alpha 200 $script:cAccent), 2)
    $g.DrawLine($ln, 0, ($h - 1), $w, ($h - 1)); $ln.Dispose()
}

# Glitch: scanlines, corrupted slices, RGB split (animated).
function Invoke-HdrGlitch($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    $sh1 = New-SolidBr (Get-Alpha 55 $script:cAccent)
    $sh2 = New-SolidBr (Get-Alpha 30 $script:cAccent)
    $g.FillPolygon($sh1, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(($w - 300), 0)), (New-Object System.Drawing.PointF(($w - 150), 0)), (New-Object System.Drawing.PointF(($w - 235), $h)), (New-Object System.Drawing.PointF(($w - 385), $h))))
    $g.FillPolygon($sh2, [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(($w - 120), 0)), (New-Object System.Drawing.PointF(($w - 60), 0)), (New-Object System.Drawing.PointF(($w - 135), $h)), (New-Object System.Drawing.PointF(($w - 195), $h))))
    $sh1.Dispose(); $sh2.Dispose()
    # barcode
    $bc = New-SolidBr (Get-Alpha 120 $script:cText)
    $bx = $w - 130
    for ($k = 0; $k -lt 22; $k++) { $bw = 1 + [int]((Get-Rnd ($k + 7)) * 3); $g.FillRectangle($bc, [single]$bx, 8, [single]$bw, 14); $bx += $bw + 2 }
    $bc.Dispose()
    $ph = $script:hdrPhase
    $burst = (($ph % 11) -lt 4)
    $n = 1; if ($burst) { $n = 8 }
    if ((Get-GlitchEvent) -gt 0) { $burst = $true; $n = 16 }
    for ($k = 0; $k -lt $n; $k++) {
        $sd = $k * 13 + [math]::Floor($ph / 2)
        if ((Get-Rnd $sd) -lt 0.35 -and $k -gt 0) { continue }
        $gx = (Get-Rnd ($sd + 1)) * $w; $gy = (Get-Rnd ($sd + 2)) * ($h - 8)
        $gw = 40 + (Get-Rnd ($sd + 3)) * 280; $gh = 2 + (Get-Rnd ($sd + 4)) * 7
        switch ($k % 3) {
            0 { $col = Get-Alpha 130 $script:cAccent }
            1 { $col = [System.Drawing.Color]::FromArgb(95, 0, 255, 235) }
            2 { $col = Get-Alpha 75 ([System.Drawing.Color]::White) }
        }
        $gb = New-SolidBr $col
        $g.FillRectangle($gb, [single]$gx, [single]$gy, [single]$gw, [single]$gh); $gb.Dispose()
    }
    if ($burst) {
        $tl = New-Object System.Drawing.Pen((Get-Alpha 70 ([System.Drawing.Color]::White)), 1)
        $ty = (Get-Rnd ($ph + 77)) * $h
        $g.DrawLine($tl, 0, [single]$ty, $w, [single]$ty); $tl.Dispose()
    }
    $sl = New-Object System.Drawing.Pen((Get-Alpha 34 ([System.Drawing.Color]::Black)), 1)
    for ($y = 0; $y -lt $h; $y += 3) { $g.DrawLine($sl, 0, $y, $w, $y) }
    $sl.Dispose()
    $f = New-Object System.Drawing.Font("Consolas", 8)
    $tb = New-SolidBr (Get-Alpha 170 $script:cAccent)
    $g.DrawString("ERR_0x7F // SIGNAL LOST", $f, $tb, ($w - 200), ($h - 30))
    $tb.Dispose(); $f.Dispose()
    $rl = New-Object System.Drawing.Pen($script:cAccent, 2)
    $x = 0; $i = 0
    while ($x -lt $w) {
        $seg = 30 + (Get-Rnd ($i + 3)) * 150
        $g.DrawLine($rl, [single]$x, ($h - 1), [single]([math]::Min($w, $x + $seg)), ($h - 1))
        $x += $seg + 4 + (Get-Rnd ($i + 9)) * 10; $i++
    }
    $rl.Dispose()
}

function New-HeartPoints([double]$cx, [double]$cy, [double]$s) {
    $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    for ($t = 0.0; $t -lt 6.283; $t += 0.25) {
        $hx = 16 * [math]::Pow([math]::Sin($t), 3)
        $hy = -(13 * [math]::Cos($t) - 5 * [math]::Cos(2 * $t) - 2 * [math]::Cos(3 * $t) - [math]::Cos(4 * $t))
        $pts.Add((New-Object System.Drawing.PointF([single]($cx + $hx * $s / 16), [single]($cy + $hy * $s / 16))))
    }
    return $pts.ToArray()
}
function New-SparklePoints([double]$cx, [double]$cy, [double]$r) {
    $q = $r * 0.25
    return [System.Drawing.PointF[]]@(
        (New-Object System.Drawing.PointF([single]$cx, [single]($cy - $r))), (New-Object System.Drawing.PointF([single]($cx + $q), [single]($cy - $q))),
        (New-Object System.Drawing.PointF([single]($cx + $r), [single]$cy)), (New-Object System.Drawing.PointF([single]($cx + $q), [single]($cy + $q))),
        (New-Object System.Drawing.PointF([single]$cx, [single]($cy + $r))), (New-Object System.Drawing.PointF([single]($cx - $q), [single]($cy + $q))),
        (New-Object System.Drawing.PointF([single]($cx - $r), [single]$cy)), (New-Object System.Drawing.PointF([single]($cx - $q), [single]($cy - $q))))
}
function Invoke-Cloud($g, [double]$cx, [double]$cy, [double]$s) {
    $b = New-SolidBr ([System.Drawing.Color]::FromArgb(235, 255, 255, 255))
    $g.FillEllipse($b, [single]($cx - 22 * $s), [single]($cy - 8 * $s), [single](44 * $s), [single](18 * $s))
    $g.FillEllipse($b, [single]($cx - 14 * $s), [single]($cy - 17 * $s), [single](24 * $s), [single](22 * $s))
    $g.FillEllipse($b, [single]($cx - 2 * $s), [single]($cy - 13 * $s), [single](22 * $s), [single](20 * $s))
    $b.Dispose()
}

function Get-HueColor([double]$deg, [int]$a = 255) {
    $hh = (($deg % 360) + 360) % 360 / 60.0
    $i = [int][math]::Floor($hh); $f = $hh - $i
    $t = [int](255 * $f); $q = [int](255 * (1 - $f))
    switch ($i) {
        0 { return [System.Drawing.Color]::FromArgb($a, 255, $t, 0) }
        1 { return [System.Drawing.Color]::FromArgb($a, $q, 255, 0) }
        2 { return [System.Drawing.Color]::FromArgb($a, 0, 255, $t) }
        3 { return [System.Drawing.Color]::FromArgb($a, 0, $q, 255) }
        4 { return [System.Drawing.Color]::FromArgb($a, $t, 0, 255) }
        default { return [System.Drawing.Color]::FromArgb($a, 255, 0, $q) }
    }
}

function Invoke-HdrWallpaper($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $bgb = New-SolidBr $script:cBg
    $g.FillRectangle($bgb, $full); $bgb.Dispose()
    if ($script:wpHdrImg) {
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $g.DrawImage($script:wpHdrImg, 0, 0, $w, $h)
    }
    $side = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, (Get-Alpha 215 $script:cBg), (Get-Alpha 90 $script:cBg), [single]0)
    $g.FillRectangle($side, $full); $side.Dispose()
    $fade = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, (Get-Alpha 0 $script:cBg), (Get-Alpha 235 $script:cBg), [single]90)
    $g.FillRectangle($fade, $full); $fade.Dispose()
    $ac = New-Object System.Drawing.Pen($script:cAccent, 2)
    $g.DrawLine($ac, 0, ($h - 1), $w, ($h - 1)); $ac.Dispose()
}
function Invoke-HdrTitle($g, [string]$t1, [string]$t2) {
    if ($script:themeFx -eq 'glitch') {
        $gev = Get-GlitchEvent
        if ($gev -gt 0) { $t1 = Get-ScrambledText $t1 $gev; if ($t2) { $t2 = Get-ScrambledText $t2 $gev } }
    }
    if (-not $script:titleFamily) { $script:titleFamily = Get-FirstFont $script:titleFonts }
    $font = $null
    try { $font = New-Object System.Drawing.Font($script:titleFamily, $script:titleSize, [System.Drawing.FontStyle]$script:titleStyle) } catch {
        try { $font = New-Object System.Drawing.Font($script:titleFamily, $script:titleSize, [System.Drawing.FontStyle]::Regular) } catch { $font = New-Object System.Drawing.Font("Segoe UI", $script:titleSize, [System.Drawing.FontStyle]::Bold) }
    }
    $fmt = [System.Drawing.StringFormat]::GenericTypographic
    $x1 = [single]24
    $ty = [single]8
    $sz1 = $g.MeasureString($t1, $font, 2000, $fmt)
    $x2 = [single]($x1 + $sz1.Width + 14)
    $sz2 = $null
    if ($t2) { $sz2 = $g.MeasureString($t2, $font, 2000, $fmt) }
    if ($script:titleShadowA -gt 0) {
        $shadow = New-SolidBr (Get-Alpha $script:titleShadowA $script:cTShadow)
        $g.DrawString($t1, $font, $shadow, ($x1 + 2), ($ty + 2), $fmt)
        if ($t2) { $g.DrawString($t2, $font, $shadow, ($x2 + 2), ($ty + 2), $fmt) }
        $shadow.Dispose()
    }
    if ($script:themeFx -eq 'glitch') {
        $ca = New-SolidBr ([System.Drawing.Color]::FromArgb(150, 0, 255, 235))
        $cr = New-SolidBr (Get-Alpha 170 $script:cAccent)
        $off = 2; if (($script:hdrPhase % 11) -lt 4) { $off = 4 }
        foreach ($tx in @(@($t1, $x1), @($t2, $x2))) {
            if (-not $tx[0]) { continue }
            $g.DrawString($tx[0], $font, $ca, ($tx[1] - $off), $ty, $fmt)
            $g.DrawString($tx[0], $font, $cr, ($tx[1] + $off), ($ty + 1), $fmt)
        }
        $ca.Dispose(); $cr.Dispose()
    }
    $b1 = New-VGrad (New-RectF $x1 $ty $sz1.Width $sz1.Height) $script:cT1A $script:cT1B
    $g.DrawString($t1, $font, $b1, $x1, $ty, $fmt)
    $b1.Dispose()
    if ($t2) {
        $b2 = New-VGrad (New-RectF $x2 $ty $sz2.Width $sz2.Height) $script:cT2A $script:cT2B
        $g.DrawString($t2, $font, $b2, $x2, $ty, $fmt)
        $b2.Dispose()
        if ($script:themeHdr -eq 'matrix' -and (($script:hdrPhase % 8) -lt 4)) {
            $cur = New-SolidBr $script:cAccent
            $g.FillRectangle($cur, [single]($x2 + $sz2.Width + 4), [single]($ty + 4), [single]10, [single]($sz2.Height - 8)); $cur.Dispose()
        }
    }
    $font.Dispose()
}

function Invoke-HdrTabs($g, $tabs, [int]$active) {
    if (-not $tabs) { return }
    $tf = Get-RetroFont 11 'Bold'
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center
    $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    $ul2 = $script:cCyan
    if ($script:themeHdr -eq 'sleek') { $ul2 = $script:cAccent }
    $actCol = [System.Drawing.Color]::White
    if ($script:themeLight) { $actCol = $script:cAccentDown }
    for ($i = 0; $i -lt $tabs.Count; $i++) {
        $tb = $tabs[$i]
        if ($tb.Hidden) { continue }
        $rect = New-RectF $tb.X 52 $tb.W 28
        if ($i -eq $active) {
            $col = $actCol
            $ul = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF $tb.X 79 $tb.W 3), $script:cAccent, $ul2, [single]0)
            $g.FillRectangle($ul, $tb.X, 79, $tb.W, 3)
            $ul.Dispose()
        } else {
            $col = $script:cDim
        }
        $brush = New-SolidBr $col
        $g.DrawString($tb.Text, $tf, $brush, $rect, $sf)
        $brush.Dispose()
    }
    $sf.Dispose(); $tf.Dispose()
}

function Invoke-RetroHeaderPaint($g, [int]$w, [int]$h, [string]$t1, [string]$t2, $tabs, [int]$active) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    switch ($script:themeHdr) {
        'cyber'  { Invoke-HdrCyberA $g $w $h }
        'matrix' { Invoke-HdrMatrix $g $w $h }
        'sleek'  { Invoke-HdrSleekA $g $w $h }
        'wallpaper' { Invoke-HdrWallpaper $g $w $h }
        'glitch' { Invoke-HdrGlitch $g $w $h }
        'kawaii' { Invoke-HdrKawaiiA $g $w $h }
        'aurora' { Invoke-HdrAuroraA $g $w $h }
        'gothic' { Invoke-HdrGothicA $g $w $h }
        'rgb'    { Invoke-HdrRgbA $g $w $h }
        'blueprint' { Invoke-HdrBlueprintA $g $w $h }
        'galaxy' { Invoke-HdrGalaxyA $g $w $h }
        'shinobi' { Invoke-HdrShinobiA $g $w $h }
        default  { Invoke-HdrRetroA $g $w $h }
    }
    if ($script:themeHdr -eq 'shinobi' -and $t2 -like '*WALLPAPER*') {
        # "wallpaper workshop" in kanji, built from code points so the file encoding can't garble it
        $t2 = '// ' + [string][char]0x58C1 + [string][char]0x7D19 + [string][char]0x5DE5 + [string][char]0x623F
    }
    Invoke-HdrTitle $g $t1 $t2
    Invoke-HdrTabs $g $tabs $active
}

# ---------------------------------------------------------------- footer (status bar) art, one per theme
function Invoke-StatusPaint($g, [int]$w, [int]$h) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = New-RectF 0 0 $w $h
    $bg = New-VGrad $rect $script:cBg $script:cStatB
    $g.FillRectangle($bg, $rect); $bg.Dispose()
    $acc = $script:cAccent; $cy = $script:cCyan
    $ft = Get-FtrT
    switch ($script:themeHdr) {
        'cyber' {
            # hazard stripe along the top, scanlines below
            $y = New-SolidBr (Get-Alpha 220 $acc)
            for ($x = -10; $x -lt ($w + 10); $x += 16) {
                $pts = @((New-Object System.Drawing.PointF([single]$x, [single]6)), (New-Object System.Drawing.PointF([single]($x + 8), [single]6)), (New-Object System.Drawing.PointF([single]($x + 14), [single]0)), (New-Object System.Drawing.PointF([single]($x + 6), [single]0)))
                $g.FillPolygon($y, $pts)
            }
            $y.Dispose()
            $sp = New-Object System.Drawing.Pen((Get-Alpha 28 $cy), 1)
            for ($yy = 10; $yy -lt $h; $yy += 4) { $g.DrawLine($sp, 0, $yy, $w, $yy) }
            $sp.Dispose()
            $b = New-SolidBr (Get-Alpha 200 $script:cPurple); $g.FillRectangle($b, ($w - 120), ($h - 5), 120, 5); $b.Dispose()
        }
        'matrix' {
            $f = Get-RetroFont 8 'Regular'
            $br = New-SolidBr (Get-Alpha 70 $acc)
            $chars = '01ABCDEF<>/\{}$#%&=+*'
            $seed = 7
            for ($x = 4; $x -lt $w; $x += 13) {
                for ($yy = 8; $yy -lt $h; $yy += 11) {
                    $seed = ($seed * 1103515245 + 12345) -band 0x7fffffff
                    if (($seed % 5) -ne 0) { continue }
                    $g.DrawString([string]$chars[$seed % $chars.Length], $f, $br, [single]$x, [single]$yy)
                }
            }
            $br.Dispose(); $f.Dispose()
            $lp = New-Object System.Drawing.Pen((Get-Alpha 200 $acc), 1); $g.DrawLine($lp, 0, 1, $w, 1); $lp.Dispose()
        }
        'sleek' {
            $lp = New-Object System.Drawing.Pen((Get-Alpha 90 $script:cDim), 1)
            $g.DrawLine($lp, 0, 0, $w, 0); $lp.Dispose()
            $ap = New-Object System.Drawing.Pen((Get-Alpha 220 $acc), 2); $g.DrawLine($ap, 0, 1, 90, 1); $ap.Dispose()
        }
        'glitch' {
            $seed = 11 + [int][math]::Floor($ft * 6)
            for ($i = 0; $i -lt 14; $i++) {
                $seed = ($seed * 1103515245 + 12345) -band 0x7fffffff
                $x = $seed % $w; $seed = ($seed * 1103515245 + 12345) -band 0x7fffffff
                $yy = 4 + ($seed % ($h - 8)); $len = 40 + ($seed % 160)
                $c = if ($i % 2 -eq 0) { $acc } else { $cy }
                $b = New-SolidBr (Get-Alpha 70 $c); $g.FillRectangle($b, $x, $yy, $len, 2); $b.Dispose()
            }
            $p1 = New-Object System.Drawing.Pen((Get-Alpha 230 $acc), 2); $g.DrawLine($p1, 0, 1, ($w * 0.62), 1); $p1.Dispose()
            $p2 = New-Object System.Drawing.Pen((Get-Alpha 230 $cy), 2); $g.DrawLine($p2, ($w * 0.58), 4, $w, 4); $p2.Dispose()
        }
        'kawaii' {
            # scalloped edge and a few hearts and stars
            $sb = New-SolidBr (Get-Alpha 150 $acc)
            for ($x = 0; $x -lt ($w + 16); $x += 16) { $g.FillEllipse($sb, [single]($x - 8), [single](-8 + [math]::Sin($x * 0.12 + $ft * 2.4) * 1.8), 16, 14) }
            $sb.Dispose()
            $cols = @($acc, $cy, $script:cPurple, $script:cOrange)
            for ($i = 0; $i -lt 9; $i++) {
                $x = 60 + $i * 95 + [math]::Sin($ft * 0.8 + $i) * 5; $yy = 24 + (($i * 7) % 12) + [math]::Sin($ft * 1.6 + $i) * 3
                if ($i % 2 -eq 0) {
                    $pts = New-HeartPoints $x $yy (6 * (1 + 0.16 * [math]::Sin($ft * 3 + $i)))
                    $b = New-SolidBr (Get-Alpha 130 $cols[$i % 4]); $g.FillPolygon($b, $pts); $b.Dispose()
                } else {
                    $pts = New-SparklePoints $x $yy (5 * (0.6 + 0.6 * [math]::Abs([math]::Sin($ft * 2 + $i))))
                    $b = New-SolidBr (Get-Alpha 150 $cols[$i % 4]); $g.FillPolygon($b, $pts); $b.Dispose()
                }
            }
        }
        'aurora' {
            for ($k = 0; $k -lt 3; $k++) {
                $c = @($cy, $acc, $script:cPurple)[$k]
                $pts = @()
                for ($x = 0; $x -le $w; $x += 20) { $pts += (New-Object System.Drawing.PointF([single]$x, [single](12 + $k * 6 + [math]::Sin($x / 70.0 + $k * 1.7 + $ft * (0.5 + 0.25 * $k)) * (6 + 2 * [math]::Sin($ft * 0.4 + $k))))) }
                $pen = New-Object System.Drawing.Pen((Get-Alpha 70 $c), 6)
                $g.DrawCurve($pen, $pts); $pen.Dispose()
                $pen2 = New-Object System.Drawing.Pen((Get-Alpha 150 $c), 1.5)
                $g.DrawCurve($pen2, $pts); $pen2.Dispose()
            }
            $lp = New-Object System.Drawing.Pen((Get-Alpha 160 $cy), 1); $g.DrawLine($lp, 0, 0, $w, 0); $lp.Dispose()
        }
        'gothic' {
            # black lace with red doily medallions
            $blk = New-VGrad $rect ([System.Drawing.Color]::FromArgb(8, 3, 5)) ([System.Drawing.Color]::FromArgb(42, 4, 10))
            $g.FillRectangle($blk, $rect); $blk.Dispose()
            $red = [System.Drawing.Color]::FromArgb(214, 24, 40)
            $lp = New-Object System.Drawing.Pen((Get-Alpha 230 $red), 1.2)
            $lp2 = New-Object System.Drawing.Pen((Get-Alpha 140 $red), 1)
            $darkB = New-SolidBr ([System.Drawing.Color]::FromArgb(10, 3, 6))
            $redB = New-SolidBr (Get-Alpha 230 $red)
            $cyy = $h / 2.0
            $r = [math]::Min(13.0, $h / 2.0 - 3)
            $step = $r * 4.4
            # scalloped lace edges, top and bottom
            for ($x = -4; $x -lt ($w + 8); $x += 7) {
                $g.DrawArc($lp2, [single]$x, [single]-3.5, 7, 7, 0, 180)
                $g.DrawArc($lp2, [single]$x, [single]($h - 3.5), 7, 7, 180, 180)
            }
            for ($cx = $step / 2; $cx -lt ($w + $step); $cx += $step) {
                # links to the next medallion, with a small diamond between
                $mx = $cx + $step / 2
                $g.DrawLine($lp2, [single]($cx + $r + 5), [single]$cyy, [single]($mx - 4), [single]$cyy)
                $g.DrawLine($lp2, [single]($mx + 4), [single]$cyy, [single]($cx + $step - $r - 5), [single]$cyy)
                $dm = [System.Drawing.PointF[]]@((Pt $mx ($cyy - 4)), (Pt ($mx + 4) $cyy), (Pt $mx ($cyy + 4)), (Pt ($mx - 4) $cyy))
                $g.FillPolygon($redB, $dm)
                # the medallion: backing disc, rim, scallops, eight-petal rosette, centre
                $g.FillEllipse($darkB, [single]($cx - $r), [single]($cyy - $r), [single](2 * $r), [single](2 * $r))
                $g.DrawEllipse($lp, [single]($cx - $r), [single]($cyy - $r), [single](2 * $r), [single](2 * $r))
                for ($k = 0; $k -lt 12; $k++) {
                    $a = $k * [math]::PI / 6
                    $g.DrawEllipse($lp2, [single]($cx + ($r + 1.5) * [math]::Cos($a) - 2), [single]($cyy + ($r + 1.5) * [math]::Sin($a) - 2), 4, 4)
                }
                $pr = $r * 0.36
                for ($k = 0; $k -lt 8; $k++) {
                    $a = $k * [math]::PI / 4
                    $g.DrawEllipse($lp, [single]($cx + $r * 0.52 * [math]::Cos($a) - $pr), [single]($cyy + $r * 0.52 * [math]::Sin($a) - $pr), [single](2 * $pr), [single](2 * $pr))
                }
                $g.FillEllipse($redB, [single]($cx - $r * 0.2), [single]($cyy - $r * 0.2), [single]($r * 0.4), [single]($r * 0.4))
            }
            $lp.Dispose(); $lp2.Dispose(); $darkB.Dispose(); $redB.Dispose()
        }
        'rgb' {
            # rainbow strip along the top edge that flares on the beat, with a soft glow under it
            $bt = [double]$script:rgbBeat
            $cb = New-SolidBr ([System.Drawing.Color]::White); $gb = New-SolidBr ([System.Drawing.Color]::White)
            for ($x = 0; $x -lt $w; $x += 6) {
                $hu = $x * 0.45 + $ft * 32
                $cb.Color = Get-HueColor $hu 255
                $g.FillRectangle($cb, $x, 0, 6, 3)
                $gb.Color = Get-HueColor $hu ([int](36 + 90 * $bt))
                $g.FillRectangle($gb, $x, 3, 6, [int](10 + 8 * $bt))
            }
            $cb.Dispose(); $gb.Dispose()
        }
        'blueprint' {
            $gp = New-Object System.Drawing.Pen((Get-Alpha 38 $script:cText), 1)
            for ($x = 0; $x -lt $w; $x += 12) { $g.DrawLine($gp, $x, 0, $x, $h) }
            for ($yy = 0; $yy -lt $h; $yy += 12) { $g.DrawLine($gp, 0, $yy, $w, $yy) }
            $gp.Dispose()
            $tp = New-Object System.Drawing.Pen((Get-Alpha 180 $script:cText), 1)
            $g.DrawLine($tp, 0, 1, $w, 1)
            for ($x = 0; $x -lt $w; $x += 60) { $g.DrawLine($tp, $x, 1, $x, 8) }
            $tp.Dispose()
            # a scan line sweeps the sheet with a crosshair and a trail of lit grid
            $sx = ($ft * 70) % ($w + 100) - 50
            $tr = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF ($sx - 90) 0 90 $h), (Get-Alpha 0 $acc), (Get-Alpha 46 $acc), [single]0)
            $g.FillRectangle($tr, (New-RectF ($sx - 90) 0 90 $h)); $tr.Dispose()
            $sp = New-Object System.Drawing.Pen((Get-Alpha 200 $acc), 1)
            $g.DrawLine($sp, [single]$sx, 0, [single]$sx, $h)
            $cyp = $h / 2.0 + [math]::Sin($ft * 1.3) * 9
            $g.DrawLine($sp, [single]($sx - 8), [single]$cyp, [single]($sx + 8), [single]$cyp)
            $g.DrawEllipse($sp, [single]($sx - 4), [single]($cyp - 4), 8, 8); $sp.Dispose()
        }
        'galaxy' {
            $sb = New-SolidBr ([System.Drawing.Color]::White)
            for ($i = 0; $i -lt 70; $i++) {
                $sb.Color = Get-Alpha ([int](40 + (Get-Rnd ($i + 3)) * 160)) ([System.Drawing.Color]::White)
                $g.FillRectangle($sb, [single]((Get-Rnd ($i + 40)) * $w), [single]((Get-Rnd ($i + 90)) * ($h - 4)), [single]1.4, [single]1.4)
            }
            $sb.Dispose()
            $nb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF 0 0 $w 3), (Get-Alpha 0 $script:cAccent), (Get-Alpha 0 $script:cAccent), [single]0)
            $cb = New-Object System.Drawing.Drawing2D.ColorBlend(3)
            $cb.Colors = [System.Drawing.Color[]]@((Get-Alpha 0 $cy), (Get-Alpha 230 $acc), (Get-Alpha 0 $script:cPurple))
            $cb.Positions = [single[]]@(0.0, 0.5, 1.0)
            $nb.InterpolationColors = $cb
            $g.FillRectangle($nb, (New-RectF 0 0 $w 3)); $nb.Dispose()
            # a small UFO cruising along, bobbing, with blinking lights
            $ut = Get-HdrT
            $ux = (($ut * 16 + 200) % ($w + 120)) - 60; $uy = $h * 0.55 + [math]::Sin($ut * 1.7) * 2
            $gl = New-SolidBr (Get-Alpha 30 $cy); $g.FillEllipse($gl, [single]($ux - 14), [single]($uy - 9), 28, 18); $gl.Dispose()
            $dm = New-SolidBr (Get-Alpha 200 $cy); $g.FillEllipse($dm, [single]($ux - 4.5), [single]($uy - 8), 9, 9); $dm.Dispose()
            $sc = New-SolidBr ([System.Drawing.Color]::FromArgb(205, 210, 228)); $g.FillEllipse($sc, [single]($ux - 11), [single]($uy - 3), 22, 7); $sc.Dispose()
            $un = New-SolidBr ([System.Drawing.Color]::FromArgb(120, 126, 156)); $g.FillEllipse($un, [single]($ux - 7), [single]($uy + 1.5), 14, 4); $un.Dispose()
            for ($k = -1; $k -le 1; $k++) {
                $on = 0.5 + 0.5 * [math]::Sin($ut * 5 + $k * 2.1)
                $lb = New-SolidBr (Get-Alpha ([int](90 + 165 * $on)) $script:cSun); $g.FillEllipse($lb, [single]($ux + $k * 6.5 - 1.2), [single]($uy - 0.4), 2.4, 2.4); $lb.Dispose()
            }
        }
        'shinobi' {
            # moonlit bamboo grove with a mist glow; the ninja runs across it (see Invoke-StatusExtra)
            $mist = New-VGrad $rect (Get-Alpha 0 $cy) (Get-Alpha 44 $cy)
            $g.FillRectangle($mist, $rect); $mist.Dispose()
            $stalk = New-SolidBr ([System.Drawing.Color]::FromArgb(150, 12, 28, 20))
            $hiB = New-SolidBr ([System.Drawing.Color]::FromArgb(46, 120, 200, 150))
            $leaf = New-SolidBr ([System.Drawing.Color]::FromArgb(150, 22, 54, 34))
            $nodeP = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 5, 12, 8), 1)
            $x = 10; $i = 0
            while ($x -lt $w) {
                $sw = 4 + [int]((Get-Rnd ($i + 3)) * 4)
                $g.FillRectangle($stalk, [single]$x, 0, [single]$sw, $h)
                $g.FillRectangle($hiB, [single]($x + 1), 0, [single]1.3, $h)
                for ($ny = 6 + [int]((Get-Rnd ($i + 9)) * 8); $ny -lt $h; $ny += 13) {
                    $g.DrawLine($nodeP, [single]($x - 0.5), [single]$ny, [single]($x + $sw + 0.5), [single]$ny)
                    if ((Get-Rnd ($i * 17 + $ny)) -gt 0.72) {
                        $lf = [System.Drawing.PointF[]]@((Pt ($x + $sw) $ny), (Pt ($x + $sw + 15) ($ny - 6)), (Pt ($x + $sw + 5) ($ny + 1)))
                        $g.FillPolygon($leaf, $lf)
                    }
                }
                $x += 38 + (Get-Rnd ($i + 21)) * 60; $i++
            }
            $stalk.Dispose(); $hiB.Dispose(); $leaf.Dispose(); $nodeP.Dispose()
            $sp = New-Object System.Drawing.Pen((Get-Alpha 230 $acc), 2); $g.DrawLine($sp, 0, 1, ($w * 0.42), 1)
            $sp.Width = 1; $sp.Color = Get-Alpha 130 $script:cText; $g.DrawLine($sp, ($w * 0.42), 1, $w, 1); $sp.Dispose()
            $gr = New-SolidBr ([System.Drawing.Color]::FromArgb(235, 6, 3, 7)); $g.FillRectangle($gr, 0, ($h - 5), $w, 5); $gr.Dispose()
            $pb = New-SolidBr (Get-Alpha 170 ([System.Drawing.Color]::FromArgb(255, 176, 200)))
            for ($i = 0; $i -lt 40; $i++) { $g.FillEllipse($pb, [single]((Get-Rnd ($i + 5)) * $w), [single]($h - 5 + (Get-Rnd ($i + 15)) * 3), 3.4, 1.8) }
            $pb.Dispose()
        }
        'wallpaper' {
            $cs = @($acc, $cy, $script:cPurple, $script:cOrange)
            for ($i = 0; $i -lt 4; $i++) {
                $b = New-SolidBr (Get-Alpha ([int](34 + 14 * [math]::Sin($ft * 0.6 + $i))) $cs[$i])
                $g.FillEllipse($b, [single](40 + $i * 240 + [math]::Sin($ft * 0.35 + $i * 1.6) * 45), [single](-30 + [math]::Sin($ft * 0.5 + $i) * 8), 260, 90)
                $b.Dispose()
            }
            $lp = New-Object System.Drawing.Pen((Get-Alpha 120 $script:cText), 1); $g.DrawLine($lp, 0, 0, $w, 0); $lp.Dispose()
        }
        default {
            $gp = New-Object System.Drawing.Pen((Get-Alpha 60 $acc), 1)
            for ($i = -16; $i -le 16; $i++) { $g.DrawLine($gp, [single]($w / 2 + $i * 12), 0, [single]($w / 2 + $i * 60), $h) }
            foreach ($f in @(0.2, 0.45, 0.75)) { $g.DrawLine($gp, 0, [single]($h * $f), $w, [single]($h * $f)) }
            $gp.Dispose()
            $p1 = New-Object System.Drawing.Pen($acc, 2); $g.DrawLine($p1, 0, 1, $w, 1); $p1.Dispose()
            $p2 = New-Object System.Drawing.Pen((Get-Alpha 130 $cy), 1); $g.DrawLine($p2, 0, 4, $w, 4); $p2.Dispose()
        }
    }    if (Get-Command Invoke-StatusExtra -ErrorAction SilentlyContinue) { Invoke-StatusExtra $g $w $h }
}
# ---------------------------------------------------------------- animated header art
# Each theme paints a cached still layer (cheap, drawn once per size/theme) and then its moving parts on top.
# Time comes from a stopwatch so the speed does not depend on the frame rate.
$script:hdrClock = [System.Diagnostics.Stopwatch]::StartNew()
$script:hdrLayers = @{}
$script:pauseHdr = $false; $script:pauseFtr = $false; $script:frozenHdr = 3.0; $script:frozenFtr = 3.0
function Get-HdrT { if ($script:pauseHdr) { return $script:frozenHdr }; return $script:hdrClock.Elapsed.TotalSeconds }
function Get-FtrT { if ($script:pauseFtr) { return $script:frozenFtr }; return $script:hdrClock.Elapsed.TotalSeconds }
function Set-AnimPause([bool]$hdr, [bool]$ftr) {
    # pausing freezes the picture on the frame it was showing; resuming carries on from real time
    if ($hdr -and -not $script:pauseHdr) { $script:frozenHdr = $script:hdrClock.Elapsed.TotalSeconds }
    if ($ftr -and -not $script:pauseFtr) { $script:frozenFtr = $script:hdrClock.Elapsed.TotalSeconds }
    $script:pauseHdr = $hdr; $script:pauseFtr = $ftr
    try { $script:pnlHeader.Invalidate(); $script:pnlStatus.Invalidate() } catch { }
}
function Pt([double]$x, [double]$y) { return (New-Object System.Drawing.PointF([single]$x, [single]$y)) }
function New-PenA($c, [double]$w) { return (New-Object System.Drawing.Pen($c, [single]$w)) }
function Smooth([double]$u) { if ($u -lt 0) { $u = 0 }; if ($u -gt 1) { $u = 1 }; return ($u * $u * (3 - 2 * $u)) }

function Get-HdrLayer([string]$name, [int]$w, [int]$h, [string]$painter) {
    $key = "$($script:themeName)|$w|$h|$($script:cBg.ToArgb())|$($script:cAccent.ToArgb())|$($script:cCyan.ToArgb())"
    $e = $script:hdrLayers[$name]
    if ($e -and $e.Key -eq $key) { return $e.Bmp }
    if ($e) { try { $e.Bmp.Dispose() } catch { } }
    $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppPArgb)
    $gb = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gb.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $gb.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        & $painter $gb $w $h
    } finally { $gb.Dispose() }
    $script:hdrLayers[$name] = @{ Key = $key; Bmp = $bmp }
    return $bmp
}
function Show-HdrLayer($g, [string]$name, [int]$w, [int]$h, [string]$painter) {
    $bmp = Get-HdrLayer $name $w $h $painter
    $g.DrawImage($bmp, 0, 0, $w, $h)
}

# ================================================================ RETROWAVE: the sun sinks and rises, slats roll down it, the grid rolls toward you
function Invoke-PaintRetroBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    $horizon = [single]($h - 12)
    $ground = New-SolidBr $script:cGround
    $g.FillRectangle($ground, 0, $horizon, $w, ($h - $horizon)); $ground.Dispose()
    $gridPen = New-Object System.Drawing.Pen((Get-Alpha 150 $script:cAccent), 1)
    $vx = $w / 2
    for ($i = -16; $i -le 16; $i++) { $g.DrawLine($gridPen, [single]($vx + $i * 7), $horizon, [single]($vx + $i * 40), [single]$h) }
    $gridPen.Dispose()
}
function Invoke-HdrRetroA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'retro.back' $w $h 'Invoke-PaintRetroBack'
    $horizon = [single]($h - 12); $r = [single]($h * 0.56); $cx = [single]($w - 130)
    # twinkling stars
    $star = New-SolidBr ([System.Drawing.Color]::White)
    for ($i = 0; $i -lt 26; $i++) {
        $sx = ($i * 97 + 31) % $w; $sy = ($i * 53 + 7) % [math]::Max(10, ($horizon - 34))
        $a = [int](60 + 140 * (0.5 + 0.5 * [math]::Sin($t * (0.8 + ($i % 5) * 0.35) + $i)))
        $star.Color = Get-Alpha $a ([System.Drawing.Color]::White)
        $g.FillRectangle($star, [single]$sx, [single]$sy, [single]1.6, [single]1.6)
    }
    $star.Dispose()
    # the sun slowly sinks into the horizon and comes back up
    $dip = $r * 0.30 * (0.5 + 0.5 * [math]::Sin($t * 0.30))
    $cy = $horizon + $dip
    $g.SetClip((New-RectF 0 0 $w $horizon))
    foreach ($hl in @(@(1.7, 16), @(1.4, 22), @(1.18, 30))) {
        $hb = New-SolidBr (Get-Alpha $hl[1] $script:cAccent)
        $g.FillEllipse($hb, [single]($cx - $r * $hl[0]), [single]($cy - $r * $hl[0]), [single]($r * 2 * $hl[0]), [single]($r * 2 * $hl[0])); $hb.Dispose()
    }
    $g.ResetClip()
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddEllipse([single]($cx - $r), [single]($cy - $r), [single](2 * $r), [single](2 * $r))
    $reg = New-Object System.Drawing.Region($path)
    $period = 9.0; $f = ($t * 3.2) % $period
    for ($k = 0; $k -lt 10; $k++) {
        $yb = $horizon - 3 - $k * $period + $f
        $th = [math]::Max(0.8, 4.5 - 0.75 * ($k - $f / $period))
        $reg.Exclude((New-RectF ($cx - $r - 2) ($yb - $th) (2 * $r + 4) $th))
    }
    $reg.Intersect((New-RectF 0 0 $w $horizon))
    $g.SetClip($reg, [System.Drawing.Drawing2D.CombineMode]::Replace)
    $sunRect = New-RectF ($cx - $r) ($cy - $r) (2 * $r) (2 * $r)
    $sun = New-VGrad $sunRect $script:cSun $script:cAccent
    $g.FillEllipse($sun, $sunRect)
    $g.ResetClip()
    $sun.Dispose(); $reg.Dispose(); $path.Dispose()
    # rolling grid lines and the glowing horizon
    $gp = New-Object System.Drawing.Pen((Get-Alpha 150 $script:cAccent), 1)
    $ph = ($t * 0.45) % 1.0
    for ($k = 0; $k -lt 4; $k++) {
        $u = ($k + $ph) / 4.0
        $y = $horizon + 1 + 10.5 * $u * $u
        $g.DrawLine($gp, 0, [single]$y, $w, [single]$y)
    }
    $gp.Dispose()
    $glow = New-Object System.Drawing.Pen((Get-Alpha 230 $script:cCyan), 2)
    $g.DrawLine($glow, 0, $horizon, $w, $horizon); $glow.Dispose()
}

# ================================================================ CYBERPUNK: a close-up of a rainy night market, flickering neon, string lights, lanterns
$script:cyberSigns = @(
    @{ x = 0.50; y = 12; w = 48; h = 17; t = 'RAMEN'; c = 'cyan';   s = 1; v = $false },
    @{ x = 0.65; y = 8;  w = 52; h = 17; t = 'CYBER'; c = 'pink';   s = 4; v = $false },
    @{ x = 0.77; y = 34; w = 40; h = 15; t = '24H';   c = 'yellow'; s = 5; v = $false },
    @{ x = 0.91; y = 6;  w = 13; h = 46; t = 'HOTEL'; c = 'pink';   s = 7; v = $true }
)
$script:cyberAnt = @()
function Invoke-PaintCyberBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    # a faint glow where the city meets the sky
    $haze = New-VGrad (New-RectF 0 ($h * 0.35) $w ($h * 0.65)) (Get-Alpha 0 $script:cPurple) (Get-Alpha 110 $script:cPurple)
    $g.FillRectangle($haze, (New-RectF 0 ($h * 0.35) $w ($h * 0.65))); $haze.Dispose()
    $base = $h - 6
    $ant = @()
    # far towers: hazy, with stepped crowns and antennas
    $far = New-SolidBr (Get-Blend $script:cBg $script:cSky 0.62)
    $farPen = New-Object System.Drawing.Pen((Get-Blend $script:cBg $script:cSky 0.62), 1)
    $x = -6; $i = 0
    while ($x -lt $w) {
        $bw = 14 + [int]((Get-Rnd ($i + 1)) * 24); $bh = $h * (0.42 + (Get-Rnd ($i + 50)) * 0.36)
        $g.FillRectangle($far, [single]$x, [single]($base - $bh), [single]$bw, [single]$bh)
        if ((Get-Rnd ($i + 60)) -gt 0.45) { $g.FillRectangle($far, [single]($x + 3), [single]($base - $bh - 6), [single]($bw - 6), [single]6) }
        if ((Get-Rnd ($i + 70)) -gt 0.72) {
            $ax = $x + $bw / 2; $ay = $base - $bh - 6
            $g.DrawLine($farPen, [single]$ax, [single]$ay, [single]$ax, [single]($ay - 12)); $ant += , @($ax, ($ay - 12))
        }
        $x += $bw - 3; $i++
    }
    $far.Dispose(); $farPen.Dispose()
    # middle towers: darker, rim-lit on one side, sparse windows
    $mid = New-SolidBr (Get-Blend $script:cBg ([System.Drawing.Color]::Black) 0.25)
    $winY = New-SolidBr (Get-Alpha 170 $script:cAccent)
    $winC = New-SolidBr (Get-Alpha 150 $script:cCyan)
    $x = 4; $i = 0
    while ($x -lt $w) {
        $bw = 22 + [int]((Get-Rnd ($i + 200)) * 28); $bh = $h * (0.34 + (Get-Rnd ($i + 300)) * 0.34)
        $top = $base - $bh
        $g.FillRectangle($mid, [single]$x, [single]$top, [single]$bw, [single]$bh)
        $cr = (Get-Rnd ($i + 310))
        if ($cr -gt 0.5) { $g.FillRectangle($mid, [single]($x + 4), [single]($top - 5), [single]($bw - 8), [single]5) }
        if ($cr -gt 0.8) {
            $sl = [System.Drawing.PointF[]]@((Pt $x $top), (Pt ($x + $bw) ($top - 9)), (Pt ($x + $bw) $top)); $g.FillPolygon($mid, $sl)
        }
        $rc = $script:cCyan; if ((Get-Rnd ($i + 320)) -gt 0.5) { $rc = $script:cPurple }
        $rim = New-Object System.Drawing.Pen((Get-Alpha 120 $rc), 1)
        $g.DrawLine($rim, [single]($x + 0.5), [single]$top, [single]($x + 0.5), [single]$base); $rim.Dispose()
        for ($wy = $top + 6; $wy -lt ($base - 10); $wy += 6) {
            for ($wx = $x + 4; $wx -lt ($x + $bw - 3); $wx += 5) {
                $rv = Get-Rnd ($wx * 3 + $wy * 7)
                if ($rv -gt 0.9) { $g.FillRectangle($winY, [single]$wx, [single]$wy, [single]2.5, [single]3) }
                elseif ($rv -lt 0.05) { $g.FillRectangle($winC, [single]$wx, [single]$wy, [single]2.5, [single]3) }
            }
        }
        $x += $bw + 2; $i++
    }
    $mid.Dispose()
    # near blocks: nearly black, neon trim down the edges, lit window bands, rooftop units
    $near = New-SolidBr (Get-Blend $script:cBg ([System.Drawing.Color]::Black) 0.7)
    $band = New-SolidBr (Get-Alpha 90 $script:cAccent)
    $x = -10; $i = 0
    while ($x -lt $w) {
        $bw = 30 + [int]((Get-Rnd ($i + 400)) * 40); $bh = $h * (0.16 + (Get-Rnd ($i + 450)) * 0.28)
        $top = $base - $bh
        $g.FillRectangle($near, [single]$x, [single]$top, [single]$bw, [single]$bh)
        if ((Get-Rnd ($i + 460)) -gt 0.5) { $g.FillRectangle($near, [single]($x + 6), [single]($top - 4), [single]10, [single]4) }
        if ((Get-Rnd ($i + 470)) -gt 0.55) {
            $tc = $script:cPurple; if ((Get-Rnd ($i + 480)) -gt 0.5) { $tc = $script:cCyan }
            $glow = New-Object System.Drawing.Pen((Get-Alpha 50 $tc), 4)
            $g.DrawLine($glow, [single]($x + $bw - 1), [single]$top, [single]($x + $bw - 1), [single]$base); $glow.Dispose()
            $tp = New-Object System.Drawing.Pen((Get-Alpha 200 $tc), 1)
            $g.DrawLine($tp, [single]($x + $bw - 1), [single]$top, [single]($x + $bw - 1), [single]$base)
            $g.DrawLine($tp, [single]$x, [single]$top, [single]($x + $bw), [single]$top); $tp.Dispose()
        }
        for ($by = $top + 7; $by -lt ($base - 8); $by += 11) {
            if ((Get-Rnd ($i * 13 + $by)) -gt 0.55) { $g.FillRectangle($band, [single]($x + 4), [single]$by, [single]($bw - 8), [single]2) }
        }
        $x += $bw + 3; $i++
    }
    $near.Dispose(); $band.Dispose(); $winY.Dispose(); $winC.Dispose()
    $script:cyberAnt = $ant
    # power lines
    $wp = New-Object System.Drawing.Pen((Get-Alpha 150 ([System.Drawing.Color]::Black)), 1)
    $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    for ($x = 0; $x -le $w; $x += 12) { $pts.Add((Pt $x (22 + 9 * [math]::Sin($x / 130.0)))) }
    $g.DrawLines($wp, $pts.ToArray()); $wp.Dispose()
    # hazard stripe
    $g.FillRectangle((New-SolidBr ([System.Drawing.Color]::FromArgb(10, 8, 0))), 0, $base, $w, 6)
    $yb = New-SolidBr $script:cAccent
    $g.SetClip((New-RectF 0 $base $w 6))
    for ($sx = -8; $sx -lt $w; $sx += 16) {
        $pp = [System.Drawing.PointF[]]@((Pt $sx $base), (Pt ($sx + 8) $base), (Pt ($sx + 2) $h), (Pt ($sx - 6) $h))
        $g.FillPolygon($yb, $pp)
    }
    $g.ResetClip(); $yb.Dispose()
    $cl = New-Object System.Drawing.Pen((Get-Alpha 200 $script:cCyan), 1)
    $g.DrawLine($cl, 0, ($base - 1), $w, ($base - 1)); $cl.Dispose()
}
function Get-Flicker([double]$seed, [double]$t) {
    $k = [math]::Floor($t * 9)
    $r = Get-Rnd ($k * 0.37 + $seed * 11.1)
    $slow = Get-Rnd ([math]::Floor($t / 3.0) + $seed * 5.3)
    if ($slow -gt 0.68) {
        if ($r -gt 0.55) { return 0.10 } elseif ($r -gt 0.3) { return 0.55 } else { return 1.0 }
    }
    if ($r -gt 0.975) { return 0.3 }
    return 1.0
}
function Invoke-HdrCyberA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'cyber.back' $w $h 'Invoke-PaintCyberBack'
    $base = $h - 6
    # cars streaking by in three lanes, glowing trails behind them
    $lanes = @(@(8.0, 0.0, 0.40, 1), @(11.0, 4.0, 0.55, -1), @(6.5, 2.0, 0.68, 1))
    $ln = 0
    foreach ($l in $lanes) {
        $cyc = [math]::Floor(($t + $l[1]) / $l[0]); $u = ((($t + $l[1]) % $l[0]) / $l[0]) * 2.2
        if ($u -lt 1.0) {
            $dir = $l[3]
            if (($cyc % 2) -eq 1) { $dir = -$dir }
            $col = $(if ($dir -eq 1) { $script:cCyan } else { $script:cPurple })
            $hx = $(if ($dir -eq 1) { -40 + $u * ($w + 80) } else { $w + 40 - $u * ($w + 80) })
            $ly = $h * $l[2]
            for ($k = 0; $k -lt 9; $k++) {
                $pn = New-Object System.Drawing.Pen((Get-Alpha ([int](210 - $k * 22)) $col), [single](2.4 - $k * 0.14))
                $g.DrawLine($pn, [single]($hx - $dir * $k * 9), [single]$ly, [single]($hx - $dir * ($k + 1) * 9), [single]$ly); $pn.Dispose()
            }
            $hb = New-SolidBr (Get-Alpha 255 ([System.Drawing.Color]::White)); $g.FillEllipse($hb, [single]($hx - 1.5), [single]($ly - 1.5), 3, 3); $hb.Dispose()
        }
        $ln++
    }
    # antenna lights blink
    $ai = 0
    foreach ($an in $script:cyberAnt) {
        $on = 0.5 + 0.5 * [math]::Sin($t * 2.2 + $ai * 1.7)
        $ab = New-SolidBr (Get-Alpha ([int](40 + 215 * $on)) ([System.Drawing.Color]::FromArgb(255, 60, 60)))
        $g.FillEllipse($ab, [single]($an[0] - 1.5), [single]($an[1] - 1.5), 3, 3); $ab.Dispose()
        $ai++
    }
    # string lights along a sagging wire, with a chasing glow, and swaying lanterns
    $x0 = $w * 0.40
    $wp = New-Object System.Drawing.Pen((Get-Alpha 130 ([System.Drawing.Color]::Black)), 1)
    $bulbCols = @($script:cAccent, $script:cPurple, $script:cCyan)
    $i = 0
    for ($x = $x0; $x -lt $w; $x += 22) {
        $seg = (($x - $x0) % 154) / 154.0
        $y = 4 + 6 * [math]::Sin($seg * [math]::PI)
        $a = 0.55 + 0.45 * [math]::Sin($t * 4.2 - $i * 0.9)
        $c = $bulbCols[$i % 3]
        $gb = New-SolidBr (Get-Alpha ([int](40 * $a)) $c); $g.FillEllipse($gb, [single]($x - 5), [single]($y - 4), 10, 10); $gb.Dispose()
        $bb = New-SolidBr (Get-Alpha ([int](120 + 135 * $a)) $c); $g.FillEllipse($bb, [single]($x - 1.6), [single]($y - 1), 3.2, 3.6); $bb.Dispose()
        $i++
    }
    $wp.Dispose()
    $li = 0
    foreach ($lx in @(0.44, 0.60, 0.84)) {
        $sw = [math]::Sin($t * 1.3 + $li * 1.9) * 2.0
        $x = $lx * $w; $seg = (($x - $x0) % 154) / 154.0; $y = 4 + 6 * [math]::Sin($seg * [math]::PI)
        $lp = New-Object System.Drawing.Pen((Get-Alpha 160 ([System.Drawing.Color]::Black)), 1)
        $g.DrawLine($lp, [single]$x, [single]$y, [single]($x + $sw), [single]($y + 9)); $lp.Dispose()
        $fl = 0.75 + 0.25 * [math]::Sin($t * 6 + $li * 2.3) * [math]::Sin($t * 2.1 + $li)
        $gb = New-SolidBr (Get-Alpha ([int](46 * $fl)) $script:cOrange); $g.FillEllipse($gb, [single]($x + $sw - 8), [single]($y + 2), 16, 20); $gb.Dispose()
        $lb = New-SolidBr (Get-Alpha ([int](240 * $fl)) $script:cOrange); $g.FillEllipse($lb, [single]($x + $sw - 3.5), [single]($y + 8), 7, 9); $lb.Dispose()
        $li++
    }
    # neon signs
    if (-not $script:cyberFont) { $script:cyberFont = New-Object System.Drawing.Font("Consolas", 8, [System.Drawing.FontStyle]::Bold) }
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = [System.Drawing.StringAlignment]::Center; $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
    foreach ($s in $script:cyberSigns) {
        $b = Get-Flicker $s.s $t
        $col = $script:cCyan; if ($s.c -eq 'pink') { $col = $script:cPurple } elseif ($s.c -eq 'yellow') { $col = $script:cAccent }
        $sx = $s.x * $w
        $rc = New-RectF $sx $s.y $s.w $s.h
        $bk = New-SolidBr (Get-Alpha 150 $script:cBg); $g.FillRectangle($bk, $rc); $bk.Dispose()
        $gl = New-SolidBr (Get-Alpha ([int](34 * $b)) $col)
        $g.FillRectangle($gl, (New-RectF ($sx - 4) ($s.y - 4) ($s.w + 8) ($s.h + 8))); $gl.Dispose()
        $pn = New-Object System.Drawing.Pen((Get-Alpha ([int](40 + 215 * $b)) $col), 1.5)
        $g.DrawRectangle($pn, [single]$sx, [single]$s.y, [single]$s.w, [single]$s.h); $pn.Dispose()
        $txt = $s.t
        if ($s.v) { $txt = ($txt.ToCharArray() -join "`n") }
        $tbr = New-SolidBr (Get-Alpha ([int](50 + 205 * $b)) $col)
        $fnt = $script:cyberFont
        $g.DrawString($txt, $fnt, $tbr, (New-RectF $sx $s.y $s.w $s.h), $sf); $tbr.Dispose()
    }
    $sf.Dispose()
    # rain
    $rain = New-Object System.Drawing.Pen((Get-Alpha 46 $script:cCyan), 1)
    for ($k = 0; $k -lt 60; $k++) {
        $sp = 150 + (Get-Rnd ($k + 77)) * 110
        $ry = ((Get-Rnd ($k + 950)) * ($h - 8) + $t * $sp) % ($h - 8)
        $rx = (Get-Rnd ($k + 900)) * ($w + 40) - $ry * 0.35
        $g.DrawLine($rain, [single]$rx, [single]$ry, [single]($rx - 4), [single]($ry + 12))
    }
    $rain.Dispose()
    $f = New-Object System.Drawing.Font("Consolas", 8)
    $tb = New-SolidBr (Get-Alpha 150 $script:cCyan)
    $g.DrawString("// NIGHT CITY LINK : ONLINE", $f, $tb, 24, ($h - 17))
    $tb.Dispose(); $f.Dispose()
}

# ================================================================ SLEEK: a very slow lava lamp
function Invoke-PaintSleekBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, $script:cBg, $script:cSky, [single]25)
    $g.FillRectangle($bg, $full); $bg.Dispose()
    $dot = New-SolidBr (Get-Alpha 40 $script:cDim)
    for ($ix = 0; $ix -lt 16; $ix++) { for ($iy = 0; $iy -lt 6; $iy++) { $g.FillRectangle($dot, [single]($w - 250 + $ix * 14), [single](10 + $iy * 14), [single]2, [single]2) } }
    $dot.Dispose()
}
function Invoke-HdrSleekA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'sleek.back' $w $h 'Invoke-PaintSleekBack'
    $cols = @($script:cAccent, $script:cCyan, $script:cPurple)
    $g.SetClip((New-RectF 0 0 $w $h))
    for ($i = 0; $i -lt 8; $i++) {
        $c = $cols[$i % 3]
        $cx = $w * (0.06 + 0.88 * ($i / 7.0)) + [math]::Sin($t * (0.045 + 0.007 * $i) + $i * 1.7) * 90
        $cy = 26 + [math]::Sin($t * (0.035 + 0.009 * $i) + $i * 2.3) * 34
        $r = (50 + ($i % 3) * 16) * (1 + 0.14 * [math]::Sin($t * 0.07 + $i))
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddEllipse([single]($cx - $r), [single]($cy - $r * 0.8), [single](2 * $r), [single](1.6 * $r))
        $pb = New-Object System.Drawing.Drawing2D.PathGradientBrush($p)
        $pb.CenterColor = Get-Alpha 58 $c
        $pb.SurroundColors = [System.Drawing.Color[]]@((Get-Alpha 0 $c))
        $g.FillPath($pb, $p)
        $pb.Dispose(); $p.Dispose()
    }
    $g.ResetClip()
    $hl = New-Object System.Drawing.Pen($script:cPanel2, 1)
    $g.DrawLine($hl, 0, ($h - 1), $w, ($h - 1)); $hl.Dispose()
    $ac = New-Object System.Drawing.Pen($script:cAccent, 2)
    $g.DrawLine($ac, 0, ($h - 1), 120, ($h - 1)); $ac.Dispose()
}

# ================================================================ KAWAII: shimmering rainbow, floating hearts, twinkling sparkles
function Invoke-PaintKawaiiBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cSky $script:cBg
    $g.FillRectangle($sky, $full); $sky.Dispose()
}
function Invoke-PaintKawaiiFront($g, [int]$w, [int]$h) {
    $cx = $w - 130; $base = $h - 8
    Invoke-Cloud $g ($cx - 57) ($base + 2) 1.25
    Invoke-Cloud $g ($cx + 57) ($base + 2) 1.25
    Invoke-Cloud $g ($w * 0.56) 30 0.8
    Invoke-Cloud $g ($w * 0.30) ($h - 10) 0.7
    $bl = New-Object System.Drawing.Pen((Get-Alpha 255 $script:cAccent), 2)
    $g.DrawLine($bl, 0, ($h - 1), $w, ($h - 1)); $bl.Dispose()
}
function Invoke-HdrKawaiiA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'kawaii.back' $w $h 'Invoke-PaintKawaiiBack'
    $cx = $w - 130; $base = $h - 8
    $cols = @(@(255, 120, 150), @(255, 176, 120), @(255, 230, 120), @(150, 230, 170), @(130, 200, 255), @(190, 150, 255))
    for ($i = 0; $i -lt 6; $i++) {
        $r = 72 - $i * 6
        $al = [int](210 + 30 * [math]::Sin($t * 2.0 - $i * 0.7))
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($al, $cols[$i][0], $cols[$i][1], $cols[$i][2]), 6)
        $g.DrawArc($pen, [single]($cx - $r), [single]($base - $r), [single](2 * $r), [single](2 * $r), 180, 180)
        $pen.Dispose()
        # a bright glint that rides along the band
        $s0 = 180 + ((($t * 38 + $i * 14) % 200) / 200.0) * 150
        $gp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 255, 255, 255), 5)
        $g.DrawArc($gp, [single]($cx - $r), [single]($base - $r), [single](2 * $r), [single](2 * $r), [single]$s0, 22)
        $gp.Dispose()
    }
    Show-HdrLayer $g 'kawaii.front' $w $h 'Invoke-PaintKawaiiFront'
    # hearts drift upward, sway and pulse
    $hc = @($script:cAccent, $script:cPurple, $script:cCyan)
    for ($i = 0; $i -lt 11; $i++) {
        $sp = 0.06 + (Get-Rnd ($i + 3)) * 0.05
        $u = (($t * $sp) + (Get-Rnd ($i + 21))) % 1.0
        $x = (0.30 + 0.66 * (Get-Rnd ($i + 40))) * $w + [math]::Sin($t * 0.9 + $i * 1.3) * 9
        $y = ($h + 8) - $u * ($h + 24)
        $a = [int](215 * [math]::Sin($u * [math]::PI))
        $sz = (8 + (Get-Rnd ($i + 60)) * 7) * (1 + 0.10 * [math]::Sin($t * 3 + $i))
        $hb = New-SolidBr (Get-Alpha $a $hc[$i % 3])
        $g.FillPolygon($hb, (New-HeartPoints $x $y ($sz * 1.1)))
        $hb.Dispose()
    }
    # sparkles twinkle
    $spk = @(@(0.46, 20, 6), @(0.70, 40, 4), @(0.80, 16, 5), @(0.57, 70, 4), @(0.96, 52, 5), @(0.28, 58, 4), @(0.64, 52, 5))
    $k = 0
    foreach ($sp in $spk) {
        $tw = 0.25 + 0.75 * [math]::Abs([math]::Sin($t * 1.8 + $k * 1.1))
        $sb = New-SolidBr ([System.Drawing.Color]::FromArgb([int](245 * $tw), 255, 255, 255))
        $g.FillPolygon($sb, (New-SparklePoints ($sp[0] * $w) $sp[1] ($sp[2] * (0.6 + 0.6 * $tw)))); $sb.Dispose()
        $k++
    }
}

# ================================================================ AURORA: curtains of rays, near and far layers sliding at different speeds
function Invoke-PaintAuroraBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    for ($i = 0; $i -lt 60; $i++) {
        $sb = New-SolidBr (Get-Alpha ([int](50 + (Get-Rnd ($i + 1)) * 150)) ([System.Drawing.Color]::White))
        $g.FillRectangle($sb, [single]((Get-Rnd ($i + 40)) * $w), [single]((Get-Rnd ($i + 90)) * ($h * 0.7)), [single]1.4, [single]1.4)
        $sb.Dispose()
    }
}
function Invoke-PaintAuroraFront($g, [int]$w, [int]$h) {
    $mt = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    $mt.Add((Pt 0 $h))
    for ($x = 0; $x -le ($w + 22); $x += 22) {
        $my = $h - 8 - (Get-Rnd ($x / 22 + 5)) * 14 - 5 * [math]::Sin($x / 90.0)
        $mt.Add((Pt $x $my))
    }
    $mt.Add((Pt ($w + 22) $h))
    $mb = New-SolidBr $script:cBg
    $g.FillPolygon($mb, $mt.ToArray()); $mb.Dispose()
}
function Invoke-HdrAuroraA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'aurora.back' $w $h 'Invoke-PaintAuroraBack'
    # the ribbons: they wave, drift and slowly brighten and dim
    $rib = @(
        @{ C = $script:cAccent; B = 0.22; A = 14; L = 170; P = 0.4; Len = 0.62; S = 0.32 },
        @{ C = $script:cCyan;   B = 0.34; A = 10; L = 120; P = 2.1; Len = 0.45; S = 0.45 },
        @{ C = $script:cPurple; B = 0.16; A = 12; L = 230; P = 4.0; Len = 0.55; S = 0.24 }
    )
    foreach ($r in $rib) {
        $top = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $bot = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $len = $h * $r.Len
        $ph = $t * $r.S
        for ($x = 0; $x -le ($w + 8); $x += 8) {
            $y1 = $h * $r.B + $r.A * [math]::Sin($x / $r.L + $r.P + $ph) + $r.A * 0.5 * [math]::Sin($x / ($r.L * 0.45) + $r.P * 2 - $ph * 1.4)
            $y2 = $y1 + $len * (0.7 + 0.3 * [math]::Sin($x / $r.L * 0.7 + $r.P - $ph * 0.8))
            $top.Add((Pt $x $y1)); $bot.Add((Pt $x $y2))
        }
        $bot.Reverse()
        $all = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $all.AddRange($top); $all.AddRange($bot)
        $pulse = 0.78 + 0.22 * [math]::Sin($t * 0.5 + $r.P * 2)
        $gy = $h * $r.B - $r.A * 1.6
        $gr = New-RectF 0 $gy $w ($len + $r.A * 3.2)
        $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($gr, (Get-Alpha 0 $r.C), (Get-Alpha 0 $r.C), [single]90)
        $cb = New-Object System.Drawing.Drawing2D.ColorBlend(4)
        $cb.Colors = [System.Drawing.Color[]]@((Get-Alpha 0 $r.C), (Get-Alpha ([int](150 * $pulse)) $r.C), (Get-Alpha ([int](55 * $pulse)) $r.C), (Get-Alpha 0 $r.C))
        $cb.Positions = [single[]]@(0.0, 0.14, 0.55, 1.0)
        $br.InterpolationColors = $cb
        $g.FillPolygon($br, $all.ToArray())
        $br.Dispose()
    }
    # a few stars twinkle on top
    $sb = New-SolidBr ([System.Drawing.Color]::White)
    for ($i = 0; $i -lt 14; $i++) {
        $sb.Color = Get-Alpha ([int](80 + 170 * (0.5 + 0.5 * [math]::Sin($t * (1.0 + (Get-Rnd ($i + 5))) + $i * 2))))  ([System.Drawing.Color]::White)
        $g.FillRectangle($sb, [single]((Get-Rnd ($i + 40)) * $w), [single]((Get-Rnd ($i + 90)) * ($h * 0.7)), [single]1.8, [single]1.8)
    }
    $sb.Dispose()
    Show-HdrLayer $g 'aurora.front' $w $h 'Invoke-PaintAuroraFront'
}

# ================================================================ GOTHIC: cathedral nave, stained glass, rose window, candles, a bat that flies and perches
function New-ArchPath([double]$xl, [double]$xr, [double]$ys, [double]$ya) {
    $xm = ($xl + $xr) / 2.0
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $dx = $xm - $xl; $dy = $ys - $ya
    $p.AddBezier((Pt $xl $ys), (Pt $xl ($ys - $dy * 0.75)), (Pt ($xm - $dx * 0.35) ($ya + 1)), (Pt $xm $ya))
    $p.AddBezier((Pt $xm $ya), (Pt ($xm + $dx * 0.35) ($ya + 1)), (Pt $xr ($ys - $dy * 0.75)), (Pt $xr $ys))
    return $p
}
$script:gothCandles = @(0.05, 0.12, 0.20, 0.29, 0.37, 0.44, 0.50, 0.57, 0.63, 0.70, 0.77, 0.85, 0.92, 0.97)
function Invoke-PaintGothicBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $wall = New-VGrad $full (Get-Blend $script:cBg $script:cHover 0.35) $script:cBg
    $g.FillRectangle($wall, $full); $wall.Dispose()
    $stone = Get-Blend $script:cBg $script:cDim 0.35
    $dark = [System.Drawing.Color]::FromArgb(8, 4, 8)
    $glass = @(,@(104, 14, 24, 190, 40, 52))
    $bay = 118
    for ($k = 0; $k -lt 9; $k++) {
        $xl = $k * $bay - 10; $xr = $xl + $bay; $xm = ($xl + $xr) / 2.0
        # window
        $wp = New-ArchPath ($xm - 17) ($xm + 17) 44 18
        $wp.AddLine((Pt ($xm + 17) 44), (Pt ($xm + 17) 84)); $wp.AddLine((Pt ($xm + 17) 84), (Pt ($xm - 17) 84)); $wp.CloseFigure()
        $gc = $glass[0]
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF ($xm - 17) 18 34 66), [System.Drawing.Color]::FromArgb(215, $gc[0], $gc[1], $gc[2]), [System.Drawing.Color]::FromArgb(215, $gc[3], $gc[4], $gc[5]), [single]90)
        $g.FillPath($gb, $wp); $gb.Dispose()
        $mp = New-Object System.Drawing.Pen((Get-Alpha 220 $dark), 1.4)
        $g.DrawPath($mp, $wp)
        $g.DrawLine($mp, [single]$xm, 20, [single]$xm, 84)
        $g.DrawLine($mp, [single]($xm - 17), 46, [single]($xm + 17), 46); $g.DrawLine($mp, [single]($xm - 17), 64, [single]($xm + 17), 64)
        $mp.Dispose(); $wp.Dispose()
        # arch ribs
        $ap = New-ArchPath ($xl + 7) ($xr - 7) 40 6
        $rp = New-Object System.Drawing.Pen((Get-Alpha 235 $stone), 3.2)
        $g.DrawPath($rp, $ap); $rp.Dispose(); $ap.Dispose()
    }
    # pillars
    $pb = New-SolidBr (Get-Blend $stone $dark 0.45)
    $pl = New-SolidBr (Get-Alpha 70 ([System.Drawing.Color]::White))
    for ($k = 0; $k -le 9; $k++) {
        $px = $k * $bay - 10 - 7
        $g.FillRectangle($pb, [single]$px, 0, 14, $h)
        $g.FillRectangle($pl, [single]($px + 2), 0, 2, $h)
    }
    $pb.Dispose(); $pl.Dispose()
    # the title side stays dim so the name reads
    $dim = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF 0 0 480 $h), (Get-Alpha 175 $script:cBg), (Get-Alpha 0 $script:cBg), [single]0)
    $g.FillRectangle($dim, (New-RectF 0 0 480 $h)); $dim.Dispose()
    # stone ledge with the candle bodies
    $ly = $h - 11
    $lb = New-VGrad (New-RectF 0 $ly $w 11) (Get-Blend $stone $dark 0.3) $dark
    $g.FillRectangle($lb, (New-RectF 0 $ly $w 11)); $lb.Dispose()
    $hp = New-Object System.Drawing.Pen((Get-Alpha 200 $stone), 1); $g.DrawLine($hp, 0, $ly, $w, $ly); $hp.Dispose()
    $wax = New-SolidBr ([System.Drawing.Color]::FromArgb(236, 226, 196))
    $waxs = New-SolidBr ([System.Drawing.Color]::FromArgb(170, 150, 120))
    $i = 0
    foreach ($cf in $script:gothCandles) {
        $ch = 6 + [int]((Get-Rnd ($i + 5)) * 6)
        $cx = [int]($cf * $w)
        $g.FillRectangle($wax, $cx, ($ly - $ch), 4, $ch)
        $g.FillRectangle($waxs, ($cx + 3), ($ly - $ch), 1, $ch)
        $i++
    }
    $wax.Dispose(); $waxs.Dispose()
}
function Invoke-DrawBat($g, [double]$x, [double]$y, [double]$flap, [bool]$perched, $brush) {
    if ($perched) {
        $g.FillEllipse($brush, [single]($x - 4.2), [single]($y - 6), 8.4, 13)      # folded wings and body
        $g.FillEllipse($brush, [single]($x - 2.4), [single]($y + 5), 4.8, 4.8)    # head, hanging down
        $g.FillPolygon($brush, [System.Drawing.PointF[]]@((Pt ($x - 2.6) ($y + 7.5)), (Pt ($x - 3.6) ($y + 11.5)), (Pt ($x - 0.8) ($y + 9))))
        $g.FillPolygon($brush, [System.Drawing.PointF[]]@((Pt ($x + 2.6) ($y + 7.5)), (Pt ($x + 3.6) ($y + 11.5)), (Pt ($x + 0.8) ($y + 9))))
        $fp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(20, 10, 20), 1.2)
        $g.DrawLine($fp, [single]$x, [single]($y - 6), [single]$x, [single]($y - 9)); $fp.Dispose()
        return
    }
    foreach ($sx in @(-1, 1)) {
        $pts = [System.Drawing.PointF[]]@(
            (Pt ($x + $sx * 2) ($y - 2)), (Pt ($x + $sx * 8) ($y - 6 + $flap * 7)), (Pt ($x + $sx * 15) ($y - 3 + $flap * 11)),
            (Pt ($x + $sx * 12) ($y + 1 + $flap * 7)), (Pt ($x + $sx * 9) ($y + 0.5 + $flap * 5)), (Pt ($x + $sx * 6) ($y + 3 + $flap * 3)), (Pt ($x + $sx * 2) ($y + 3)))
        $g.FillPolygon($brush, $pts)
    }
    $g.FillEllipse($brush, [single]($x - 2.6), [single]($y - 4), 5.2, 10)
    $g.FillEllipse($brush, [single]($x - 2.2), [single]($y - 7.5), 4.4, 4.4)
    $g.FillPolygon($brush, [System.Drawing.PointF[]]@((Pt ($x - 2.2) ($y - 6)), (Pt ($x - 3.4) ($y - 10)), (Pt ($x - 0.6) ($y - 7.4))))
    $g.FillPolygon($brush, [System.Drawing.PointF[]]@((Pt ($x + 2.2) ($y - 6)), (Pt ($x + 3.4) ($y - 10)), (Pt ($x + 0.6) ($y - 7.4))))
}
function Invoke-HdrGothicA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'gothic.back' $w $h 'Invoke-PaintGothicBack'
    $ly = $h - 11
    # candles
    $i = 0
    foreach ($cf in $script:gothCandles) {
        $ch = 6 + [int]((Get-Rnd ($i + 5)) * 6)
        $cx = [int]($cf * $w) + 2; $cy = $ly - $ch
        $fl = 0.72 + 0.28 * [math]::Sin($t * (7 + ($i % 4)) + $i * 2.1) * [math]::Sin($t * 3.1 + $i)
        $sway = [math]::Sin($t * 4.3 + $i * 1.7) * 0.9
        $gl = New-SolidBr (Get-Alpha ([int](26 * $fl)) $script:cSun); $g.FillEllipse($gl, [single]($cx - 15), [single]($cy - 18), 30, 30); $gl.Dispose()
        $gl2 = New-SolidBr (Get-Alpha ([int](48 * $fl)) $script:cOrange); $g.FillEllipse($gl2, [single]($cx - 7), [single]($cy - 11), 14, 17); $gl2.Dispose()
        $fh = 5 + 2.2 * $fl
        $fo = New-SolidBr (Get-Alpha 235 $script:cOrange)
        $g.FillPolygon($fo, [System.Drawing.PointF[]]@((Pt ($cx - 1.9) ($cy - 1)), (Pt ($cx + $sway) ($cy - 1 - $fh * 1.5)), (Pt ($cx + 1.9) ($cy - 1)), (Pt $cx ($cy + 1)))); $fo.Dispose()
        $fi = New-SolidBr ([System.Drawing.Color]::FromArgb(255, 252, 200))
        $g.FillPolygon($fi, [System.Drawing.PointF[]]@((Pt ($cx - 0.9) ($cy - 1)), (Pt ($cx + $sway * 0.6) ($cy - 1 - $fh)), (Pt ($cx + 0.9) ($cy - 1)), (Pt $cx $cy))); $fi.Dispose()
        $i++
    }
    # the bat: hangs, flies across, hangs, flies back
    $ax = 0.40 * $w; $bx = 0.69 * $w; $py = 6
    $cyc = 18.0; $c = $t % $cyc
    $bat = New-SolidBr ([System.Drawing.Color]::FromArgb(6, 3, 6))
    if ($c -lt 5) { Invoke-DrawBat $g $ax ($py + 7) 0 $true $bat }
    elseif ($c -lt 9) {
        $u = Smooth (($c - 5) / 4.0)
        $x = $ax + ($bx - $ax) * $u
        $y = ($py + 7) + 22 * [math]::Sin($u * [math]::PI) + 3 * [math]::Sin($u * 18)
        Invoke-DrawBat $g $x $y ([math]::Sin($t * 17)) $false $bat
    }
    elseif ($c -lt 14) { Invoke-DrawBat $g $bx ($py + 7) 0 $true $bat }
    else {
        $u = Smooth (($c - 14) / 4.0)
        $x = $bx + ($ax - $bx) * $u
        $y = ($py + 7) + 28 * [math]::Sin($u * [math]::PI) + 3 * [math]::Sin($u * 16)
        Invoke-DrawBat $g $x $y ([math]::Sin($t * 17)) $false $bat
    }
    $bat.Dispose()
    # low fog
    $fog = New-VGrad (New-RectF 0 ($h * 0.62) $w ($h * 0.38)) (Get-Alpha 0 $script:cHover) (Get-Alpha 70 $script:cHover)
    $g.FillRectangle($fog, (New-RectF 0 ($h * 0.62) $w ($h * 0.38))); $fog.Dispose()
    $gl = New-Object System.Drawing.Pen((Get-Alpha 200 $script:cCyan), 2)
    $g.DrawLine($gl, 0, ($h - 1), $w, ($h - 1)); $gl.Dispose()
}

# ================================================================ BLUEPRINT: a floor plan and a gear draw themselves, hold, fade, repeat
function Get-BpStrokes([int]$w) {
    if ($script:bpStrokes -and $script:bpW -eq $w) { return $script:bpStrokes }
    $list = New-Object System.Collections.ArrayList
    $ox = $w - 590; $oy = 12
    [void]$list.Add(@((Pt $ox $oy), (Pt ($ox + 250) $oy), (Pt ($ox + 250) ($oy + 62)), (Pt $ox ($oy + 62)), (Pt $ox $oy)))
    [void]$list.Add(@((Pt ($ox + 120) $oy), (Pt ($ox + 120) ($oy + 38))))
    [void]$list.Add(@((Pt ($ox + 120) ($oy + 38)), (Pt ($ox + 250) ($oy + 38))))
    [void]$list.Add(@((Pt ($ox + 150) ($oy - 3)), (Pt ($ox + 210) ($oy - 3))))
    [void]$list.Add(@((Pt ($ox + 150) ($oy + 3)), (Pt ($ox + 210) ($oy + 3))))
    [void]$list.Add(@((Pt ($ox + 60) ($oy + 62)), (Pt ($ox + 60) ($oy + 40))))
    $arc = @(); for ($a = 0; $a -le 90; $a += 10) { $r = $a * [math]::PI / 180; $arc += (Pt ($ox + 60 + 22 * [math]::Sin($r)) ($oy + 62 - 22 * [math]::Cos($r))) }
    [void]$list.Add($arc)
    [void]$list.Add(@((Pt ($ox + 190) ($oy + 62)), (Pt ($ox + 190) ($oy + 50)), (Pt ($ox + 230) ($oy + 50)), (Pt ($ox + 230) ($oy + 62))))
    $gx = $w - 140; $gy = 46
    $gear = @()
    for ($i = 0; $i -lt 12; $i++) {
        $a0 = $i * 2 * [math]::PI / 12
        foreach ($d in @(@(-0.26, 23), @(-0.15, 31), @(0.15, 31), @(0.26, 23))) { $gear += (Pt ($gx + $d[1] * [math]::Cos($a0 + $d[0])) ($gy + $d[1] * [math]::Sin($a0 + $d[0]))) }
    }
    $gear += $gear[0]
    [void]$list.Add($gear)
    foreach ($rad in @(15, 7)) { $cc = @(); for ($a = 0; $a -le 360; $a += 20) { $r = $a * [math]::PI / 180; $cc += (Pt ($gx + $rad * [math]::Cos($r)) ($gy + $rad * [math]::Sin($r))) }; [void]$list.Add($cc) }
    [void]$list.Add(@((Pt ($gx - 40) $gy), (Pt ($gx + 40) $gy)))
    [void]$list.Add(@((Pt $gx ($gy - 38)), (Pt $gx ($gy + 38))))
    $out = @()
    foreach ($s in $list) {
        $len = 0.0; for ($i = 1; $i -lt $s.Count; $i++) { $len += [math]::Sqrt([math]::Pow($s[$i].X - $s[$i - 1].X, 2) + [math]::Pow($s[$i].Y - $s[$i - 1].Y, 2)) }
        $out += , @{ P = $s; L = $len }
    }
    $script:bpStrokes = $out; $script:bpW = $w
    return $out
}
function Invoke-PaintBlueprintBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    $mi = New-Object System.Drawing.Pen((Get-Alpha 22 ([System.Drawing.Color]::White)), 1)
    $ma = New-Object System.Drawing.Pen((Get-Alpha 52 ([System.Drawing.Color]::White)), 1)
    for ($x = 0; $x -le $w; $x += 10) { if (($x % 50) -eq 0) { $g.DrawLine($ma, $x, 0, $x, $h) } else { $g.DrawLine($mi, $x, 0, $x, $h) } }
    for ($y = 0; $y -le $h; $y += 10) { if (($y % 50) -eq 0) { $g.DrawLine($ma, 0, $y, $w, $y) } else { $g.DrawLine($mi, 0, $y, $w, $y) } }
    $mi.Dispose(); $ma.Dispose()
    $wp = New-Object System.Drawing.Pen((Get-Alpha 190 ([System.Drawing.Color]::White)), 1.3)
    $dy = $h - 14; $x1 = $w - 330; $x2 = $w - 20
    $g.DrawLine($wp, $x1, $dy, $x2, $dy)
    $g.DrawLine($wp, $x1, ($dy - 5), $x1, ($dy + 5)); $g.DrawLine($wp, $x2, ($dy - 5), $x2, ($dy + 5))
    $g.DrawLine($wp, $x1, $dy, ($x1 + 7), ($dy - 3)); $g.DrawLine($wp, $x1, $dy, ($x1 + 7), ($dy + 3))
    $g.DrawLine($wp, $x2, $dy, ($x2 - 7), ($dy - 3)); $g.DrawLine($wp, $x2, $dy, ($x2 - 7), ($dy + 3))
    $wp.Dispose()
    $f = New-Object System.Drawing.Font("Consolas", 8)
    $tb = New-SolidBr (Get-Alpha 210 ([System.Drawing.Color]::White))
    $bk = New-SolidBr $script:cBg
    $g.FillRectangle($bk, ($x1 + 130), ($dy - 8), 50, 14)
    $g.DrawString("940 mm", $f, $tb, ($x1 + 132), ($dy - 8))
    $g.DrawString("SCALE 1:1   REV 10", $f, $tb, ($w - 200), 2)
    $tb.Dispose(); $bk.Dispose(); $f.Dispose()
    $bl = New-Object System.Drawing.Pen((Get-Alpha 150 ([System.Drawing.Color]::White)), 1)
    $g.DrawLine($bl, 0, ($h - 1), $w, ($h - 1)); $bl.Dispose()
}
function Invoke-HdrBlueprintA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'blueprint.back' $w $h 'Invoke-PaintBlueprintBack'
    $strokes = Get-BpStrokes $w
    $total = 0.0; foreach ($s in $strokes) { $total += $s.L }
    $speed = 170.0
    $draw = $total / $speed; $hold = 4.0; $fade = 1.5; $rest = 0.6
    $c = $t % ($draw + $hold + $fade + $rest)
    $remain = [math]::Min($total, $c * $speed)
    $alpha = 200
    if ($c -gt ($draw + $hold)) { $alpha = [int](200 * [math]::Max(0.0, 1.0 - ($c - $draw - $hold) / $fade)) }
    if ($c -gt ($draw + $hold + $fade)) { return }
    $wp = New-Object System.Drawing.Pen((Get-Alpha $alpha ([System.Drawing.Color]::White)), 1.3)
    $tip = $null
    foreach ($s in $strokes) {
        if ($remain -le 0) { break }
        if ($remain -ge $s.L) { $g.DrawLines($wp, [System.Drawing.PointF[]]$s.P); $remain -= $s.L; continue }
        $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $pts.Add($s.P[0]); $acc = 0.0
        for ($i = 1; $i -lt $s.P.Count; $i++) {
            $a = $s.P[$i - 1]; $b = $s.P[$i]
            $seg = [math]::Sqrt([math]::Pow($b.X - $a.X, 2) + [math]::Pow($b.Y - $a.Y, 2))
            if ($acc + $seg -le $remain) { $pts.Add($b); $acc += $seg; continue }
            $f = 0; if ($seg -gt 0) { $f = ($remain - $acc) / $seg }
            $pts.Add((Pt ($a.X + ($b.X - $a.X) * $f) ($a.Y + ($b.Y - $a.Y) * $f))); break
        }
        if ($pts.Count -gt 1) { $g.DrawLines($wp, $pts.ToArray()) }
        $tip = $pts[$pts.Count - 1]
        $remain = 0
    }
    $wp.Dispose()
    if ($tip -and $c -lt $draw) {
        $cp = New-Object System.Drawing.Pen((Get-Alpha 230 $script:cAccent), 1)
        $g.DrawLine($cp, [single]($tip.X - 7), $tip.Y, [single]($tip.X + 7), $tip.Y)
        $g.DrawLine($cp, $tip.X, [single]($tip.Y - 7), $tip.X, [single]($tip.Y + 7)); $cp.Dispose()
        $ab = New-SolidBr (Get-Alpha 255 $script:cAccent); $g.FillEllipse($ab, [single]($tip.X - 2), [single]($tip.Y - 2), 4, 4); $ab.Dispose()
    }
}

# ================================================================ GALAXY: spinning galaxies, twinkling stars, comets and a floating astronaut
function Invoke-PaintGalaxyBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    foreach ($n in @(@(0.80, 50, 150, $script:cPurple), @(0.52, 80, 110, $script:cAccent), @(0.30, 30, 90, $script:cCyan), @(0.95, 20, 90, $script:cAccent))) {
        $p = New-Object System.Drawing.Drawing2D.GraphicsPath
        $p.AddEllipse([single]($n[0] * $w - $n[2]), [single]($n[1] - $n[2] * 0.4), [single](2 * $n[2]), [single]($n[2] * 0.8))
        $pb = New-Object System.Drawing.Drawing2D.PathGradientBrush($p)
        $pb.CenterColor = Get-Alpha 46 $n[3]
        $pb.SurroundColors = [System.Drawing.Color[]]@((Get-Alpha 0 $n[3]))
        $g.FillPath($pb, $p); $pb.Dispose(); $p.Dispose()
    }
    $sb = New-SolidBr ([System.Drawing.Color]::White)
    for ($i = 0; $i -lt 110; $i++) {
        $sb.Color = Get-Alpha ([int](50 + (Get-Rnd ($i + 3)) * 170)) ([System.Drawing.Color]::White)
        $sz = 1.0 + (Get-Rnd ($i + 9)) * 1.1
        $g.FillRectangle($sb, [single]((Get-Rnd ($i + 40)) * $w), [single]((Get-Rnd ($i + 90)) * ($h - 4)), [single]$sz, [single]$sz)
    }
    $sb.Dispose()
}
function Invoke-PaintGalaxyDisk($g, [int]$w, [int]$h) {
    $S = $w; $c = $S / 2.0; $p = $script:galP
    $halo = New-Object System.Drawing.Drawing2D.GraphicsPath
    $halo.AddEllipse([single]2, [single]2, [single]($S - 4), [single]($S - 4))
    $hb = New-Object System.Drawing.Drawing2D.PathGradientBrush($halo)
    $hb.CenterColor = Get-Alpha 70 $p.c2
    $hb.SurroundColors = [System.Drawing.Color[]]@((Get-Alpha 0 $p.c2))
    $g.FillPath($hb, $halo); $hb.Dispose(); $halo.Dispose()
    $br = New-SolidBr ([System.Drawing.Color]::White)
    for ($arm = 0; $arm -lt 2; $arm++) {
        for ($k = 0; $k -lt 150; $k++) {
            $f = $k / 150.0; $r = 3 + $f * ($c - 5)
            $ang = $arm * [math]::PI + $f * 4.4 + ((Get-Rnd ($k + $p.seed + $arm * 7)) - 0.5) * 0.5
            $sp = ((Get-Rnd ($k * 1.7 + $p.seed)) - 0.5) * (2 + $f * 9)
            $x = $c + [math]::Cos($ang) * $r + $sp; $y = $c + [math]::Sin($ang) * $r + $sp * 0.6
            $col = Get-Blend $p.c1 $p.c2 ([math]::Min(1.0, $f * 1.3))
            $br.Color = Get-Alpha ([int](235 * [math]::Pow(1 - $f * 0.8, 1.2))) $col
            $d = 1.2 + (Get-Rnd ($k + 33 + $arm)) * 1.3
            $g.FillEllipse($br, [single]($x - $d / 2), [single]($y - $d / 2), [single]$d, [single]$d)
        }
    }
    $br.Dispose()
    $core = New-Object System.Drawing.Drawing2D.GraphicsPath
    $core.AddEllipse([single]($c - $S * 0.17), [single]($c - $S * 0.17), [single]($S * 0.34), [single]($S * 0.34))
    $cb = New-Object System.Drawing.Drawing2D.PathGradientBrush($core)
    $cb.CenterColor = [System.Drawing.Color]::FromArgb(235, 255, 244, 214)
    $cb.SurroundColors = [System.Drawing.Color[]]@((Get-Alpha 0 $p.c1))
    $g.FillPath($cb, $core); $cb.Dispose(); $core.Dispose()
}
function Invoke-DrawAstronaut($g, [double]$x, [double]$y, [double]$ang, [double]$t) {
    $st = $g.Save()
    $g.TranslateTransform([single]$x, [single]$y); $g.RotateTransform([single]$ang); $g.ScaleTransform(0.85, 0.85)
    $white = New-SolidBr ([System.Drawing.Color]::FromArgb(240, 240, 250))
    $shade = New-SolidBr ([System.Drawing.Color]::FromArgb(168, 174, 205))
    $sw = [math]::Sin($t * 1.6) * 3
    $lp = New-PenA ([System.Drawing.Color]::FromArgb(240, 240, 250)) 4.6
    $lp.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $lp.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.FillRectangle($shade, -10, -6, 20, 17)                                   # backpack
    $g.DrawLine($lp, -3, 10, [single](-4 - $sw * 0.5), [single](19 + $sw))      # legs
    $g.DrawLine($lp, 3, 10, [single](4 + $sw * 0.5), [single](19 - $sw))
    $boot = New-SolidBr ([System.Drawing.Color]::FromArgb(70, 76, 110))
    $g.FillEllipse($boot, [single](-7.5 - $sw * 0.5), [single](18 + $sw), 7, 5)
    $g.FillEllipse($boot, [single](0.5 + $sw * 0.5), [single](18 - $sw), 7, 5); $boot.Dispose()
    $g.FillRectangle($white, -6.5, -4, 13, 15)                                  # torso
    $pa = [int](130 + 125 * [math]::Abs([math]::Sin($t * 2.4)))
    $pb = New-SolidBr (Get-Alpha $pa $script:cAccent); $g.FillRectangle($pb, -3.5, 1, 7, 3.2); $pb.Dispose()
    $g.DrawLine($lp, -6, -2, [single](-13), [single](3 + $sw))                  # arms
    $g.DrawLine($lp, 6, -2, [single](13), [single](3 - $sw))
    $gl = New-SolidBr $script:cCyan
    $g.FillEllipse($gl, [single](-15.5), [single](1 + $sw), 5, 5); $g.FillEllipse($gl, [single](10.5), [single](1 - $sw), 5, 5); $gl.Dispose()
    $g.FillEllipse($white, -8, -18, 16, 16)                                     # helmet
    $vb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF -5.5 -15.5 11 9), [System.Drawing.Color]::FromArgb(255, 18, 24, 70), [System.Drawing.Color]::FromArgb(255, 60, 90, 170), [single]90)
    $g.FillEllipse($vb, -5.5, -15.5, 11, 9); $vb.Dispose()
    $hi = New-SolidBr ([System.Drawing.Color]::FromArgb(150, 255, 255, 255)); $g.FillEllipse($hi, -3.8, -14.4, 4.2, 2.4); $hi.Dispose()
    $lp.Dispose(); $white.Dispose(); $shade.Dispose()
    $g.Restore($st)
}
function Invoke-DrawSatellite($g, [double]$x, [double]$y, [double]$ang, [double]$t) {
    $st = $g.Save()
    $g.TranslateTransform([single]$x, [single]$y); $g.RotateTransform([single]$ang)
    $panel = New-SolidBr ([System.Drawing.Color]::FromArgb(230, 40, 70, 150))
    $body = New-SolidBr ([System.Drawing.Color]::FromArgb(235, 200, 204, 220))
    $gold = New-SolidBr ([System.Drawing.Color]::FromArgb(235, 214, 170, 70))
    $gp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 150, 190, 255), 0.7)
    foreach ($sx in @(-1, 1)) {
        $px = $(if ($sx -lt 0) { -19 } else { 7 })
        $g.FillRectangle($panel, [single]$px, [single]-3.5, [single]12, [single]7)
        for ($k = 1; $k -lt 4; $k++) { $g.DrawLine($gp, [single]($px + $k * 3), [single]-3.5, [single]($px + $k * 3), [single]3.5) }
        $g.DrawLine($gp, [single]$px, 0, [single]($px + 12), 0)
    }
    $arm = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(200, 170, 174, 190), 1)
    $g.DrawLine($arm, -7, 0, -5, 0); $g.DrawLine($arm, 5, 0, 7, 0); $arm.Dispose()
    $g.FillRectangle($body, [single]-5, [single]-4, 10, 8)
    $g.FillRectangle($gold, [single]-5, [single]-1.5, 10, 3)
    $g.DrawLine($gp, 0, -4, 0, -8); $g.FillEllipse($body, [single]-2.5, [single]-10.5, 5, 3)   # dish
    $blink = [math]::Sin($t * 3.0)
    if ($blink -gt 0.55) { $lb = New-SolidBr ([System.Drawing.Color]::FromArgb(255, 255, 70, 70)); $g.FillEllipse($lb, [single]-1.2, [single]4.5, 2.4, 2.4); $lb.Dispose() }
    $panel.Dispose(); $body.Dispose(); $gold.Dispose(); $gp.Dispose()
    $g.Restore($st)
}
function Invoke-HdrGalaxyA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'galaxy.back' $w $h 'Invoke-PaintGalaxyBack'
    # twinkle
    $sb = New-SolidBr ([System.Drawing.Color]::White)
    for ($i = 0; $i -lt 30; $i++) {
        $a = 0.5 + 0.5 * [math]::Sin($t * (0.9 + (Get-Rnd ($i + 5)) * 2.2) + $i * 1.9)
        $sb.Color = Get-Alpha ([int](40 + 215 * $a)) ([System.Drawing.Color]::White)
        $sz = 1.4 + 1.3 * $a
        $g.FillRectangle($sb, [single]((Get-Rnd ($i + 300)) * $w), [single]((Get-Rnd ($i + 400)) * ($h - 6)), [single]$sz, [single]$sz)
    }
    $sb.Dispose()
    # galaxies
    $oldI = $g.InterpolationMode
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
    $defs = @(
        @{ n = 'galaxy.g1'; S = 130; x = ($w - 190); y = 46; tilt = -22; sq = 0.42; spin = 2.2; seed = 3;  c1 = [System.Drawing.Color]::FromArgb(255, 220, 160); c2 = $script:cCyan },
        @{ n = 'galaxy.g2'; S = 84;  x = ($w * 0.50); y = 62; tilt = 18;  sq = 0.50; spin = -3.0; seed = 11; c1 = [System.Drawing.Color]::FromArgb(255, 200, 220); c2 = $script:cPurple },
        @{ n = 'galaxy.g3'; S = 56;  x = ($w * 0.37); y = 22; tilt = -8;  sq = 0.38; spin = 4.0; seed = 19; c1 = [System.Drawing.Color]::FromArgb(230, 230, 255); c2 = $script:cAccent }
    )
    foreach ($d in $defs) {
        $script:galP = $d
        $bmp = Get-HdrLayer $d.n $d.S $d.S 'Invoke-PaintGalaxyDisk'
        $st = $g.Save()
        $g.TranslateTransform([single]$d.x, [single]$d.y); $g.RotateTransform([single]$d.tilt); $g.ScaleTransform(1, [single]$d.sq); $g.RotateTransform([single]($t * $d.spin))
        $g.DrawImage($bmp, [single](-$d.S / 2), [single](-$d.S / 2), [single]$d.S, [single]$d.S)
        $g.Restore($st)
    }
    $g.InterpolationMode = $oldI
    # comets
    $comets = @(
        @{ per = 11.0; off = 2.0; y0 = 8;  dy = 34; sz = 1.0; c = [System.Drawing.Color]::FromArgb(255, 255, 255); tail = $script:cCyan },
        @{ per = 17.0; off = 9.0; y0 = 40; dy = 22; sz = 0.7; c = [System.Drawing.Color]::FromArgb(255, 235, 200); tail = $script:cPurple }
    )
    foreach ($cm in $comets) {
        $u = ((($t + $cm.off) % $cm.per) / $cm.per) * 1.7
        if ($u -ge 1.0) { continue }
        $hx = $w * (1.06 - $u * 1.12); $hy = $cm.y0 + $u * $cm.dy
        $vx = 1.0; $vy = -($cm.dy / ($w * 1.12))
        for ($k = 0; $k -lt 16; $k++) {
            $a = [int]((170 - $k * 10) * $cm.sz)
            $pn = New-PenA (Get-Alpha $a $cm.tail) ((3.0 - $k * 0.15) * $cm.sz)
            $pn.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $pn.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
            $g.DrawLine($pn, [single]($hx + $vx * $k * 7), [single]($hy + $vy * $k * 7), [single]($hx + $vx * ($k + 1) * 7), [single]($hy + $vy * ($k + 1) * 7)); $pn.Dispose()
        }
        $gb = New-SolidBr (Get-Alpha 60 $cm.tail); $g.FillEllipse($gb, [single]($hx - 6 * $cm.sz), [single]($hy - 6 * $cm.sz), [single](12 * $cm.sz), [single](12 * $cm.sz)); $gb.Dispose()
        $hb = New-SolidBr $cm.c; $g.FillEllipse($hb, [single]($hx - 2 * $cm.sz), [single]($hy - 2 * $cm.sz), [single](4 * $cm.sz), [single](4 * $cm.sz)); $hb.Dispose()
    }
    # a satellite creeps the other way, high up
    $sx = ($w + 60) - (($t * 7 + 300) % ($w + 120))
    Invoke-DrawSatellite $g $sx (14 + 3 * [math]::Sin($t * 0.2)) (-10 + 4 * [math]::Sin($t * 0.3)) $t
    # the astronaut drifts across, turning slowly
    $ax = (($t * 15 + 140) % ($w + 160)) - 80
    $ay = 30 + 10 * [math]::Sin($t * 0.55)
    $aa = 28 * [math]::Sin($t * 0.4) + $t * 2.0
    Invoke-DrawAstronaut $g $ax $ay $aa $t
    $gl = New-Object System.Drawing.Pen((Get-Alpha 160 $script:cAccent), 1)
    $g.DrawLine($gl, 0, ($h - 1), $w, ($h - 1)); $gl.Dispose()
}

# ================================================================ SHINOBI: moonlit torii, a katana standing in the ground, falling cherry blossoms
function Get-SakuraColor { return [System.Drawing.Color]::FromArgb(255, 176, 200) }
function Invoke-PaintShinobiBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
    $sb = New-SolidBr ([System.Drawing.Color]::White)
    for ($i = 0; $i -lt 28; $i++) {
        $sb.Color = Get-Alpha ([int](40 + (Get-Rnd ($i + 3)) * 130)) ([System.Drawing.Color]::White)
        $g.FillRectangle($sb, [single]((Get-Rnd ($i + 40)) * $w), [single]((Get-Rnd ($i + 90)) * ($h * 0.5)), [single]1.3, [single]1.3)
    }
    $sb.Dispose()
    # moon
    $mx = $w * 0.64; $my = 38; $mr = 21
    foreach ($ha in @(@(2.2, 12), @(1.6, 20), @(1.25, 34))) {
        $hb = New-SolidBr (Get-Alpha $ha[1] $script:cSun)
        $g.FillEllipse($hb, [single]($mx - $mr * $ha[0]), [single]($my - $mr * $ha[0]), [single]($mr * 2 * $ha[0]), [single]($mr * 2 * $ha[0])); $hb.Dispose()
    }
    $mb = New-SolidBr $script:cSun; $g.FillEllipse($mb, [single]($mx - $mr), [single]($my - $mr), [single](2 * $mr), [single](2 * $mr)); $mb.Dispose()
    $cr = New-SolidBr (Get-Alpha 40 ([System.Drawing.Color]::FromArgb(150, 120, 110)))
    $g.FillEllipse($cr, [single]($mx - 9), [single]($my - 8), 8, 8); $g.FillEllipse($cr, [single]($mx + 2), [single]($my + 1), 10, 10); $cr.Dispose()
    # two ranges of hills
    foreach ($L in @(@(0.55, 14, 0.5, 71), @(0.9, 10, 0.2, 80))) {
        $pts = New-Object System.Collections.Generic.List[System.Drawing.PointF]
        $pts.Add((Pt 0 $h))
        for ($x = 0; $x -le ($w + 20); $x += 20) {
            $y = $L[3] - $L[1] * (0.5 + 0.5 * [math]::Sin($x / 70.0 * $L[0] + $L[2] * 9)) - 6 * [math]::Sin($x / 23.0 + $L[2])
            $pts.Add((Pt $x $y))
        }
        $pts.Add((Pt ($w + 20) $h))
        $hbr = New-SolidBr (Get-Blend $script:cSky ([System.Drawing.Color]::Black) $L[2])
        $g.FillPolygon($hbr, $pts.ToArray()); $hbr.Dispose()
    }
    # torii gate in front of the moon
    $red = [System.Drawing.Color]::FromArgb(196, 30, 48)
    $rb = New-SolidBr $red; $bkb = New-SolidBr ([System.Drawing.Color]::FromArgb(14, 8, 12))
    $gx = $mx; $top = 24; $gnd = $h - 12
    $g.FillRectangle($rb, [single]($gx - 31), [single]($top + 4), 5, [single]($gnd - $top - 4))
    $g.FillRectangle($rb, [single]($gx + 26), [single]($top + 4), 5, [single]($gnd - $top - 4))
    $g.FillRectangle($rb, [single]($gx - 36), [single]($top + 18), 72, 4)           # nuki
    $g.FillRectangle($bkb, [single]($gx - 29), [single]($top + 4), 3, 5)
    $kp = [System.Drawing.PointF[]]@((Pt ($gx - 49) ($top - 1)), (Pt ($gx - 38) ($top + 5)), (Pt ($gx + 38) ($top + 5)), (Pt ($gx + 49) ($top - 1)), (Pt ($gx + 46) ($top - 5)), (Pt ($gx + 36) ($top + 1)), (Pt ($gx - 36) ($top + 1)), (Pt ($gx - 46) ($top - 5)))
    $g.FillPolygon($bkb, $kp)
    $g.FillRectangle($rb, [single]($gx - 38), [single]($top + 5), 76, 3)
    $g.FillRectangle($bkb, [single]($gx - 3), [single]($top + 8), 6, 10)
    $rb.Dispose(); $bkb.Dispose()
    # cherry branch, top right
    $bp = New-PenA ([System.Drawing.Color]::FromArgb(40, 22, 28)) 4
    $bp.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $bp.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $main = [System.Drawing.PointF[]]@((Pt ($w + 6) 4), (Pt ($w - 70) 10), (Pt ($w - 150) 16), (Pt ($w - 215) 14))
    $g.DrawCurve($bp, $main)
    $bp.Width = 2.2
    $g.DrawCurve($bp, [System.Drawing.PointF[]]@((Pt ($w - 70) 10), (Pt ($w - 95) 24), (Pt ($w - 110) 31)))
    $g.DrawCurve($bp, [System.Drawing.PointF[]]@((Pt ($w - 150) 16), (Pt ($w - 165) 4), (Pt ($w - 180) 0)))
    $bp.Dispose()
    $sk = Get-SakuraColor
    $bl = New-SolidBr $sk; $bl2 = New-SolidBr ([System.Drawing.Color]::FromArgb(255, 226, 236))
    for ($i = 0; $i -lt 44; $i++) {
        $f = (Get-Rnd ($i + 5))
        $bx = $w + 4 - $f * 220; $by = 8 + 8 * [math]::Sin($f * 3) + ((Get-Rnd ($i + 77)) - 0.4) * 22
        $r = 2.4 + (Get-Rnd ($i + 21)) * 2.6
        $g.FillEllipse($bl, [single]($bx - $r), [single]($by - $r), [single](2 * $r), [single](2 * $r))
        $g.FillEllipse($bl2, [single]($bx - $r * 0.4), [single]($by - $r * 0.4), [single]($r * 0.8), [single]($r * 0.8))
    }
    $bl.Dispose(); $bl2.Dispose()
    # ground
    $gb = New-VGrad (New-RectF 0 ($h - 12) $w 12) ([System.Drawing.Color]::FromArgb(22, 14, 18)) ([System.Drawing.Color]::FromArgb(6, 3, 5))
    $g.FillRectangle($gb, (New-RectF 0 ($h - 12) $w 12)); $gb.Dispose()
    $gp = New-Object System.Drawing.Pen((Get-Alpha 120 $script:cDim), 1)
    for ($x = 0; $x -lt $w; $x += 5) { $hh = 2 + (Get-Rnd ($x * 0.3)) * 5; $g.DrawLine($gp, $x, ($h - 12), ($x + 1), ($h - 12 - $hh)) }
    $gp.Dispose()
    $pb = New-SolidBr (Get-Alpha 170 $sk)
    for ($i = 0; $i -lt 60; $i++) { $g.FillEllipse($pb, [single]((Get-Rnd ($i + 600)) * $w), [single]($h - 10 + (Get-Rnd ($i + 700)) * 8), 3.2, 1.8) }
    $pb.Dispose()
    # the katana, blade in the earth, hilt up
    $kx = $w * 0.80; $kb = $h - 10
    $st = $g.Save()
    $g.TranslateTransform([single]$kx, [single]$kb); $g.RotateTransform(7)
    $bladeB = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF -2.2 -28 4.4 30), [System.Drawing.Color]::FromArgb(236, 240, 248), [System.Drawing.Color]::FromArgb(130, 138, 156), [single]0)
    $g.FillPolygon($bladeB, [System.Drawing.PointF[]]@((Pt -2.0 0), (Pt -1.8 -28), (Pt 1.8 -28), (Pt 2.2 0))); $bladeB.Dispose()
    $hp = New-Object System.Drawing.Pen((Get-Alpha 200 ([System.Drawing.Color]::White)), 0.8); $g.DrawLine($hp, 0.4, -27, 0.5, -2); $hp.Dispose()
    $tsu = New-SolidBr ([System.Drawing.Color]::FromArgb(206, 168, 70)); $g.FillEllipse($tsu, -6.5, -30.5, 13, 4.5); $tsu.Dispose()
    $tk = New-SolidBr ([System.Drawing.Color]::FromArgb(26, 20, 26)); $g.FillRectangle($tk, -2.6, -64, 5.2, 34); $tk.Dispose()
    $wr = New-Object System.Drawing.Pen((Get-Alpha 235 $red), 1)
    for ($yy = -62; $yy -lt -32; $yy += 5) { $g.DrawLine($wr, -2.6, $yy, 0, ($yy + 3)); $g.DrawLine($wr, 0, ($yy + 3), 2.6, $yy); $g.DrawLine($wr, -2.6, ($yy + 5), 0, ($yy + 2)); $g.DrawLine($wr, 0, ($yy + 2), 2.6, ($yy + 5)) }
    $wr.Dispose()
    $ka = New-SolidBr ([System.Drawing.Color]::FromArgb(206, 168, 70)); $g.FillRectangle($ka, -3.4, -67, 6.8, 3.6); $ka.Dispose()
    $g.Restore($st)
}
function Invoke-HdrShinobiA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    Show-HdrLayer $g 'shinobi.back' $w $h 'Invoke-PaintShinobiBack'
    # moon breathes
    $mx = $w * 0.64; $my = 38
    $pa = [int](10 + 10 * (0.5 + 0.5 * [math]::Sin($t * 0.8)))
    $mb = New-SolidBr (Get-Alpha $pa $script:cSun); $g.FillEllipse($mb, [single]($mx - 40), [single]($my - 40), 80, 80); $mb.Dispose()
    # drifting ground mist
    foreach ($m in @(@(0.0, 0.07, 240), @(0.5, 0.05, 300))) {
        $x = (($t * 7 * $m[1] * 10 + $m[0] * $w) % ($w + 400)) - 300
        $fb = New-SolidBr (Get-Alpha 26 ([System.Drawing.Color]::White))
        $g.FillEllipse($fb, [single]$x, [single]($h - 22), [single]$m[2], 22); $fb.Dispose()
    }
    # glint sliding along the blade now and then
    $kx = $w * 0.80; $kb = $h - 10
    $gc = ($t % 6.0)
    if ($gc -lt 1.0) {
        $st = $g.Save(); $g.TranslateTransform([single]$kx, [single]$kb); $g.RotateTransform(7)
        $yy = -2 - 24 * $gc
        $gb = New-SolidBr (Get-Alpha ([int](230 * [math]::Sin($gc * [math]::PI))) ([System.Drawing.Color]::White))
        $g.FillRectangle($gb, -2, [single]$yy, 4, 3); $gb.Dispose()
        $g.Restore($st)
    }
    # falling blossoms, blown toward the left
    $pk = Get-SakuraColor
    $pb = New-SolidBr $pk
    for ($i = 0; $i -lt 42; $i++) {
        $per = 7 + (Get-Rnd ($i + 3)) * 6
        $u = (($t / $per) + (Get-Rnd ($i + 11))) % 1.0
        $x = (Get-Rnd ($i + 21)) * ($w + 260) - 260 * $u + [math]::Sin($t * 1.1 + $i) * 12
        $y = -6 + $u * ($h + 2)
        $a = [int](225 * [math]::Min(1.0, [math]::Min($u * 10, (1 - $u) * 10)))
        if ($a -le 0 -or $x -lt -8 -or $x -gt ($w + 8)) { continue }
        $pb.Color = Get-Alpha $a $pk
        $pw = 1.8 + 3.6 * [math]::Abs([math]::Cos($t * 2.6 + $i * 1.3))
        $g.FillEllipse($pb, [single]$x, [single]$y, [single]$pw, 3.2)
    }
    $pb.Dispose()
    $ap = New-Object System.Drawing.Pen((Get-Alpha 220 $script:cAccent), 2)
    $g.DrawLine($ap, 0, ($h - 1), $w, ($h - 1)); $ap.Dispose()
}

# ================================================================ FOOTER EXTRAS (drawn on top of each theme's footer art)
function Start-Pills { if ($script:pillState -eq 0) { $script:pillState = 1; $script:pillT1 = Get-HdrT } }
function Get-PillRects([int]$w, [int]$h) {
    return @(@(($w / 2.0 - 24), ($h / 2.0)), @(($w / 2.0 + 24), ($h / 2.0)))
}
function Invoke-DrawPill($g, [double]$x, [double]$y, [double]$ang, $c1, $c2, [double]$glowA) {
    $st = $g.Save()
    $g.TranslateTransform([single]$x, [single]$y); $g.RotateTransform([single]$ang)
    $gb = New-SolidBr (Get-Alpha ([int]$glowA) $c1); $g.FillEllipse($gb, -22, -12, 44, 24); $gb.Dispose()
    $rp = New-RoundPath (New-RectF -13 -5.5 26 11) 5.5
    $gr = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF -13 -5.5 26 11), $c1, $c2, [single]90)
    $g.FillPath($gr, $rp); $gr.Dispose()
    $hi = New-SolidBr ([System.Drawing.Color]::FromArgb(110, 255, 255, 255))
    $g.FillRectangle($hi, [single]-10, [single]-4, 20, 2.2); $hi.Dispose()
    $ol = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 0, 0, 0), 1); $g.DrawPath($ol, $rp); $ol.Dispose()
    $rp.Dispose()
    $g.Restore($st)
}
function Invoke-DrawRetroCar($g, [double]$x, [double]$y, [double]$t) {
    $st = $g.Save()
    $g.TranslateTransform([single]$x, [single]$y)
    $sl = New-Object System.Drawing.Pen((Get-Alpha 90 $script:cCyan), 1)
    foreach ($ly in @(-9, -6, -3)) { $g.DrawLine($sl, [single](-52 - $ly * -2), [single]$ly, [single](-80 - $ly * -2), [single]$ly) }
    $sl.Dispose()
    $ug = New-SolidBr (Get-Alpha 70 $script:cCyan); $g.FillEllipse($ug, -46, -2, 92, 6); $ug.Dispose()
    $bm = New-SolidBr (Get-Alpha 26 $script:cSun)
    $g.FillPolygon($bm, [System.Drawing.PointF[]]@((Pt 46 -6), (Pt 100 -13), (Pt 100 0))); $bm.Dispose()
    $body = [System.Drawing.PointF[]]@((Pt 47 -4.5), (Pt 42 -7), (Pt 22 -9.5), (Pt 8 -15), (Pt -12 -15), (Pt -31 -11.5), (Pt -46 -10), (Pt -47.5 -3), (Pt -44 -1.2), (Pt 44 -1.2))
    $bb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-RectF -48 -16 96 15), $script:cAccentHover, $script:cAccentDown, [single]90)
    $g.FillPolygon($bb, $body); $bb.Dispose()
    $sp = New-Object System.Drawing.Pen((Get-Alpha 235 $script:cCyan), 1.3); $g.DrawLine($sp, -44, -6.2, 44, -6.2); $sp.Dispose()
    $gl = New-SolidBr ([System.Drawing.Color]::FromArgb(230, 24, 10, 46))
    $g.FillPolygon($gl, [System.Drawing.PointF[]]@((Pt 19 -9.8), (Pt 8 -14), (Pt -11 -14), (Pt -22 -10.6))); $gl.Dispose()
    $hl = New-SolidBr ([System.Drawing.Color]::FromArgb(70, 255, 255, 255)); $g.FillPolygon($hl, [System.Drawing.PointF[]]@((Pt 8 -14), (Pt 1 -14), (Pt -6 -10.4), (Pt 2 -10.4))); $hl.Dispose()
    $tl = New-SolidBr ([System.Drawing.Color]::FromArgb(255, 255, 40, 60)); $g.FillRectangle($tl, [single]-47.5, [single]-8.5, 3, 3.5); $tl.Dispose()
    $tg = New-SolidBr ([System.Drawing.Color]::FromArgb(60, 255, 40, 60)); $g.FillEllipse($tg, -52, -11, 10, 9); $tg.Dispose()
    $hd = New-SolidBr ([System.Drawing.Color]::FromArgb(255, 255, 240, 170)); $g.FillEllipse($hd, [single]41, [single]-7, 4, 2.6); $hd.Dispose()
    $arch = New-SolidBr $script:cBg; $tire = New-SolidBr ([System.Drawing.Color]::FromArgb(14, 12, 18)); $rim = New-SolidBr ([System.Drawing.Color]::FromArgb(210, 214, 226))
    $spk = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90, 94, 110), 1)
    foreach ($wx in @(-29, 29)) {
        $g.FillEllipse($arch, [single]($wx - 7.2), -12.6, 14.4, 14.4)
        $g.FillEllipse($tire, [single]($wx - 5.6), -11, 11.2, 11.2)
        $g.FillEllipse($rim, [single]($wx - 3.2), -8.6, 6.4, 6.4)
        for ($k = 0; $k -lt 3; $k++) {
            $a = $t * 14 + $k * [math]::PI / 3
            $g.DrawLine($spk, [single]($wx - 3 * [math]::Cos($a)), [single](-5.4 - 3 * [math]::Sin($a)), [single]($wx + 3 * [math]::Cos($a)), [single](-5.4 + 3 * [math]::Sin($a)))
        }
    }
    $arch.Dispose(); $tire.Dispose(); $rim.Dispose(); $spk.Dispose()
    $g.Restore($st)
}
function Invoke-DrawNinja($g, [double]$x, [double]$y, [double]$t) {
    $ph = $t * 7.5
    $hop = [math]::Abs([math]::Sin($ph)) * 2.2
    $st = $g.Save()
    $g.TranslateTransform([single]$x, [single]($y - $hop))
    $body = [System.Drawing.Color]::FromArgb(255, 9, 5, 11)
    $lp = New-PenA $body 3.3; $lp.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $lp.EndCap = [System.Drawing.Drawing2D.LineCap]::Round; $lp.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    # scarf streaming behind, in red
    $sc = New-Object System.Collections.Generic.List[System.Drawing.PointF]
    for ($k = 0; $k -lt 8; $k++) { $sc.Add((Pt (-1.5 - $k * 3.6) (-19.5 + [math]::Sin($t * 12 - $k * 0.9) * 0.6 * $k))) }
    $rp = New-PenA $script:cAccent 2.4; $rp.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $rp.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLines($rp, $sc.ToArray()); $rp.Dispose()
    # sword across the back
    $sw = New-PenA ([System.Drawing.Color]::FromArgb(255, 52, 52, 62)) 1.5
    $g.DrawLine($sw, -3, -12, 5, -25); $sw.Dispose()
    $hr = New-PenA $script:cAccent 2; $g.DrawLine($hr, 4.4, -23.8, 5.8, -26); $hr.Dispose()
    # legs
    foreach ($o in @(0, [math]::PI)) {
        $a = [math]::Sin($ph + $o) * 0.95
        $kx = -1 + [math]::Sin($a) * 5; $ky = -9 + [math]::Cos($a) * 4.6
        $fx = $kx - 2.6 + [math]::Sin($a) * 3.2; $fy = -1 - $(if ([math]::Cos($ph + $o) -gt 0) { 0 } else { 3.5 })
        $g.DrawLine($lp, -1, -9, [single]$kx, [single]$ky); $g.DrawLine($lp, [single]$kx, [single]$ky, [single]$fx, [single]$fy)
    }
    # torso leaning forward, arms pumping
    $tp = New-PenA $body 5.4; $tp.StartCap = [System.Drawing.Drawing2D.LineCap]::Round; $tp.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawLine($tp, 1, -16, -1, -9); $tp.Dispose()
    foreach ($o in @(0, [math]::PI)) {
        $a = [math]::Sin($ph + $o)
        $g.DrawLine($lp, 1, -15, [single](1 + $a * 6.5), [single](-10 + [math]::Cos($ph + $o) * 1.6))
    }
    # head with a pale eye slit
    $hb = New-SolidBr $body; $g.FillEllipse($hb, 0.2, -24, 7.4, 7.4); $hb.Dispose()
    $ep = New-PenA ([System.Drawing.Color]::FromArgb(255, 255, 176, 200)) 1; $g.DrawLine($ep, 4, -20.6, 7, -20.8); $ep.Dispose()
    $lp.Dispose()
    $g.Restore($st)
}
function Invoke-DrawFootStar($g, [double]$x, [double]$y, [double]$r, [double]$ang, [bool]$trail) {
    if ($trail) {
        for ($k = 4; $k -ge 1; $k--) {
            $tb = New-SolidBr ([System.Drawing.Color]::FromArgb([int](46 - $k * 8), 200, 210, 230))
            $g.FillEllipse($tb, [single]($x - $k * 11 - $r * 0.5), [single]($y - $r * 0.5), [single]($r), [single]($r)); $tb.Dispose()
        }
    }
    $pts = New-Object 'System.Drawing.PointF[]' 8
    for ($i = 0; $i -lt 8; $i++) {
        $a = $ang + $i * [math]::PI / 4
        $rr = if ($i % 2 -eq 0) { $r } else { $r * 0.36 }
        $pts[$i] = Pt ($x + [math]::Cos($a) * $rr) ($y + [math]::Sin($a) * $rr)
    }
    $sb = New-SolidBr ([System.Drawing.Color]::FromArgb(255, 196, 206, 222)); $g.FillPolygon($sb, $pts); $sb.Dispose()
    $op = New-PenA ([System.Drawing.Color]::FromArgb(255, 40, 44, 60)) 1; $g.DrawPolygon($op, $pts); $op.Dispose()
    $cb = New-SolidBr ([System.Drawing.Color]::FromArgb(255, 20, 16, 24)); $g.FillEllipse($cb, [single]($x - $r * 0.16), [single]($y - $r * 0.16), [single]($r * 0.32), [single]($r * 0.32)); $cb.Dispose()
}
function Invoke-DrawLog($g, [double]$x, [double]$y, [double]$deg, [int]$alpha) {
    # a short log standing on its end; it pivots about its bottom-right corner as it topples forward
    $st = $g.Save()
    $g.TranslateTransform([single]($x + 7), [single]$y); $g.RotateTransform([single]$deg)
    $wood = New-SolidBr ([System.Drawing.Color]::FromArgb($alpha, 104, 66, 38))
    $g.FillRectangle($wood, -14, -34, 14, 34); $wood.Dispose()
    $dk = New-PenA ([System.Drawing.Color]::FromArgb($alpha, 62, 38, 22)) 1.2
    for ($k = 6; $k -lt 34; $k += 8) { $g.DrawLine($dk, -13, [single](-$k), -1, [single](-$k + 1.5)) }
    $g.DrawRectangle($dk, -14, -34, 14, 34); $dk.Dispose()
    $cut = New-SolidBr ([System.Drawing.Color]::FromArgb($alpha, 196, 150, 98)); $g.FillEllipse($cut, -14, -37, 14, 6); $cut.Dispose()
    $g.Restore($st)
}
function Invoke-ShinobiPuff($g, [double]$cx, [double]$cy, [double]$pu, [double]$scale) {
    for ($k = 0; $k -lt 6; $k++) {
        $an = $k * 1.05
        $r = (5 + $pu * 15) * $scale
        $sb = New-SolidBr (Get-Alpha ([int](150 * (1 - $pu))) ([System.Drawing.Color]::FromArgb(170, 170, 180)))
        $g.FillEllipse($sb, [single]($cx + [math]::Cos($an) * $pu * 14 * $scale - $r), [single]($cy + [math]::Sin($an) * $pu * 7 * $scale - $r), [single](2 * $r), [single](2 * $r)); $sb.Dispose()
    }
}
function Invoke-StatusExtra($g, [int]$w, [int]$h) {
    $t = Get-FtrT
    switch ($script:themeHdr) {
        'retro' {
            $x = (($t * 38) % ($w + 240)) - 110
            Invoke-DrawRetroCar $g $x ($h - 7) $t
        }
        'cyber' {
            if (-not $script:cyberTickFont) { $script:cyberTickFont = New-Object System.Drawing.Font("Consolas", 7) }
            $msg = "// NEURAL LINK STABLE // UPLINK 99.8% // 0x7F3A9C // NIGHT CITY ONLINE // SIGNAL CLEAR // "
            if (-not $script:cyberTickW) { $script:cyberTickW = $g.MeasureString($msg, $script:cyberTickFont).Width }
            $off = ($t * 26) % $script:cyberTickW
            $tb = New-SolidBr (Get-Alpha 105 $script:cCyan)
            $big = $msg * 4
            $g.DrawString($big, $script:cyberTickFont, $tb, [single](-$off), [single]($h - 12)); $tb.Dispose()
            # a patrol drone sweeping a red scan beam
            $dx = ($w + 70) - (($t * 34 + 300) % ($w + 140)); $dy = 15 + [math]::Sin($t * 2.2) * 3
            $st = $g.Save(); $g.TranslateTransform([single]$dx, [single]$dy)
            $bm = New-SolidBr (Get-Alpha 26 ([System.Drawing.Color]::FromArgb(255, 40, 60))); $g.FillPolygon($bm, [System.Drawing.PointF[]]@((Pt 0 2), (Pt -13 ($h - $dy)), (Pt 13 ($h - $dy)))); $bm.Dispose()
            $bd = New-SolidBr ([System.Drawing.Color]::FromArgb(230, 18, 14, 34)); $g.FillEllipse($bd, -8, -3, 16, 6); $bd.Dispose()
            $op = New-Object System.Drawing.Pen((Get-Alpha 220 $script:cCyan), 1); $g.DrawEllipse($op, -8, -3, 16, 6)
            $g.DrawLine($op, -13, -3.5, -5, -3.5); $g.DrawLine($op, 5, -3.5, 13, -3.5); $op.Dispose()
            $rb = New-SolidBr (Get-Alpha ([int](120 + 135 * (0.5 + 0.5 * [math]::Sin($t * 6)))) ([System.Drawing.Color]::FromArgb(255, 50, 60))); $g.FillEllipse($rb, -1.8, -1.2, 3.6, 3.6); $rb.Dispose()
            $rot = New-SolidBr (Get-Alpha 90 $script:cCyan); $g.FillEllipse($rot, -15, -5.4, 11, 1.6); $g.FillEllipse($rot, 4, -5.4, 11, 1.6); $rot.Dispose()
            $g.Restore($st)
        }
        'shinobi' {
            $u = ($t % 13.0) / 13.0
            $ny = $h - 6
            $span = $w + 60
            $nx = -30 + $u * $span
            $uC = 0.42; $uR = 0.57
            $cxp = -30 + $uC * $span
            # the ninja runs the whole length; he is only missing while he is a log
            if ($u -lt $uC -or $u -ge $uR) { Invoke-DrawNinja $g $nx $ny $t }
            # a throwing star chases him from behind, faster, closing the gap
            if ($u -ge 0.08 -and $u -lt $uC) {
                $gap = 300 * (1 - ($u - 0.08) / ($uC - 0.08))
                Invoke-DrawFootStar $g ($nx - 6 - $gap) ($ny - 15) 7 ($t * 26) $true
            }
            # caught: poof, and a log drops in his place with the star stuck in it
            if ($u -ge $uC -and $u -lt 0.54) { Invoke-ShinobiPuff $g $cxp ($ny - 12) (($u - $uC) / 0.12) 1.0 }
            if ($u -ge ($uC + 0.01) -and $u -lt 0.66) {
                $lu = ($u - ($uC + 0.01)) / 0.09
                if ($lu -gt 1) { $lu = 1 }
                $deg = 90 * $lu * $lu
                if ($lu -ge 1) { $deg = 90 - [math]::Abs([math]::Sin(($u - 0.52) * 90)) * 6 * [math]::Max(0, (0.58 - $u) / 0.06) }
                $al = 255
                if ($u -gt 0.6) { $al = [int](255 * (0.66 - $u) / 0.06) }
                if ($al -gt 0) {
                    Invoke-DrawLog $g $cxp $ny $deg $al
                    if ($lu -ge 1) { Invoke-DrawFootStar $g ($cxp + 8) ($ny - 8) 6 0.4 $false }
                }
            }
            # he pops back out a little further along and keeps running
            if ($u -ge $uR -and $u -lt 0.67) { Invoke-ShinobiPuff $g $nx ($ny - 12) (($u - $uR) / 0.10) 0.7 }
        }
        'matrix' {
            if ($script:pillState -ge 1) {
                $rest = Get-PillRects $w $h
                $u0 = ($t - $script:pillT1) / 1.5
                $items = @(@(0, -28.0, [System.Drawing.Color]::FromArgb(255, 235, 40, 40), [System.Drawing.Color]::FromArgb(255, 120, 8, 12), 0.0), @(1, 24.0, [System.Drawing.Color]::FromArgb(255, 50, 120, 255), [System.Drawing.Color]::FromArgb(255, 10, 36, 130), 0.25))
                foreach ($it in $items) {
                    $uu = [math]::Max(0.0, [math]::Min(1.0, ($u0 - $it[4]) / 0.8))
                    $ease = 1 - [math]::Pow(1 - $uu, 3)
                    $bounce = 0; if ($uu -ge 1) { $bounce = 0 } else { $bounce = [math]::Sin($uu * [math]::PI) * -2 }
                    $x = $rest[$it[0]][0]; $y = -16 + ($rest[$it[0]][1] + 16) * $ease + $bounce
                    $pulse = 40 + 30 * (0.5 + 0.5 * [math]::Sin($t * 2.5 + $it[0] * 2))
                    $ga = $(if ($uu -ge 1) { $pulse } else { 24 })
                    Invoke-DrawPill $g $x $y ($it[1] + 14 * (1 - $ease) * $(if ($it[0] -eq 0) { 1 } else { -1 })) $it[2] $it[3] $ga
                }
                if ($script:pillState -eq 1 -and $u0 -gt 1.4) { $script:pillState = 2 }
            }
        }
        'glitch' { Invoke-GlitchFooter $g $w $h }
        'sleek' {
            # the logo in white and blue, centred in the footer
            $sc = 0.075; $k = [math]::Tan(10 * [math]::PI / 180)
            $cx = $w / 2.0; $cy = $h / 2.0
            $dx = $cx - 259 * $sc; $dy = $cy - 250 * $sc
            $rects = @(@(96, 150, 96, 200), @(206, 130, 96, 240), @(316, 110, 96, 280))
            for ($n = 0; $n -lt 3; $n++) {
                $r = $rects[$n]
                $cs = @(@($r[0], $r[1]), @(($r[0] + $r[2]), $r[1]), @(($r[0] + $r[2]), ($r[1] + $r[3])), @($r[0], ($r[1] + $r[3])))
                $pts = New-Object 'System.Drawing.PointF[]' 4
                for ($i = 0; $i -lt 4; $i++) { $pts[$i] = Pt ($dx + ($cs[$i][0] + 46 - $k * $cs[$i][1]) * $sc) ($dy + $cs[$i][1] * $sc) }
                if ($n -lt 2) {
                    $pn = New-Object System.Drawing.Pen((Get-Alpha $(if ($n -eq 0) { 110 } else { 190 }) ([System.Drawing.Color]::White)), 1.4)
                    $pn.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round; $g.DrawPolygon($pn, $pts); $pn.Dispose()
                } else {
                    $bb = New-RectF ($pts[0].X - 6) $pts[0].Y 24 ($pts[3].Y - $pts[0].Y)
                    $fb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bb, [System.Drawing.Color]::White, $script:cAccent, [single]90)
                    $g.FillPolygon($fb, $pts); $fb.Dispose()
                }
            }
        }
    }
}

# ================================================================ GLITCH extras: a rare "system failure" event and a pixel gremlin in the footer
function Get-GlitchEvent { $c = (Get-FtrT) % 13.0; if ($c -lt 0.55) { return (1.0 - $c / 0.55) }; return 0.0 }
function Get-ScrambledText([string]$s, [double]$k) {
    $chars = '#$%&@!?<>/\|01XZ'
    $ph = [int][math]::Floor((Get-FtrT) * 14)
    $sb = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($ch -ne ' ' -and (Get-Rnd ($i * 7 + $ph)) -lt ($k * 0.7)) { [void]$sb.Append($chars[[int][math]::Floor((Get-Rnd ($i * 3 + $ph + 1)) * $chars.Length)]) } else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}
$script:gremA = @('..#.....#..', '...#...#...', '..#######..', '.##.###.##.', '###########', '#.#######.#', '#.#.....#.#', '...##.##...')
$script:gremB = @('..#.....#..', '#..#...#..#', '#.#######.#', '###.###.###', '###########', '.#########.', '..#.....#..', '.#.......#.')
function Invoke-DrawGremlin($g, [double]$x, [double]$y, [int]$frame, $color) {
    $rows = $(if ($frame -eq 0) { $script:gremA } else { $script:gremB })
    $b = New-SolidBr $color
    for ($r = 0; $r -lt 8; $r++) {
        $row = $rows[$r]
        for ($c = 0; $c -lt 11; $c++) { if ($row[$c] -eq '#') { $g.FillRectangle($b, [single]($x + $c * 2), [single]($y + $r * 2), 2, 2) } }
    }
    $b.Dispose()
}
function Invoke-GlitchFooter($g, [int]$w, [int]$h) {
    $t = Get-FtrT
    $ev = Get-GlitchEvent
    # the gremlin patrols the footer in jerky steps, throws RGB-split afterimages, and teleports during a failure
    $span = $w + 80
    $px = ([math]::Floor(($t * 52) / 6) * 6) % $span - 40
    if ($ev -gt 0) { $px = (Get-Rnd ([math]::Floor($t * 14))) * $w }
    $py = ($h - 18) / 2.0 + [math]::Sin($t * 3) * 2
    $fr = [int]([math]::Floor($t * 4) % 2)
    $split = 3 + 6 * $ev
    Invoke-DrawGremlin $g ($px - $split) $py $fr ([System.Drawing.Color]::FromArgb(110, 0, 255, 235))
    Invoke-DrawGremlin $g ($px + $split) $py $fr (Get-Alpha 110 $script:cAccent)
    Invoke-DrawGremlin $g $px $py $fr ([System.Drawing.Color]::FromArgb(235, 235, 240, 245))
    $eye = New-SolidBr $script:cBg; $g.FillRectangle($eye, [single]($px + 6), [single]($py + 6), 2, 2); $g.FillRectangle($eye, [single]($px + 14), [single]($py + 6), 2, 2); $eye.Dispose()
    if ($ev -gt 0) {
        $ph = [int][math]::Floor($t * 14)
        for ($k = 0; $k -lt 8; $k++) {
            $bx = (Get-Rnd ($ph + $k * 3)) * $w; $by = (Get-Rnd ($ph + $k * 5 + 1)) * ($h - 6); $bw = 60 + (Get-Rnd ($ph + $k)) * 300
            $c = $(if ($k % 2 -eq 0) { Get-Alpha ([int](150 * $ev)) $script:cAccent } else { [System.Drawing.Color]::FromArgb([int](120 * $ev), 0, 255, 235) })
            $bb = New-SolidBr $c; $g.FillRectangle($bb, [single]$bx, [single]$by, [single]$bw, [single](2 + (Get-Rnd ($ph + $k * 7)) * 6)); $bb.Dispose()
        }
        $f = New-Object System.Drawing.Font("Consolas", 9, [System.Drawing.FontStyle]::Bold)
        $tb = New-SolidBr (Get-Alpha ([int](230 * $ev)) ([System.Drawing.Color]::White))
        $g.DrawString("SYSTEM FAILURE // REBOOTING REALITY", $f, $tb, [single]((Get-Rnd ($ph + 9)) * 40 + 180), [single]($h - 18)); $tb.Dispose(); $f.Dispose()
    }
}
# ---------------------------------------------------------------- RGB: music-reactive equalizer
# Listens to what the PC is playing (the standard "loopback" of the default output, levels only, nothing is recorded or stored)
# and turns it into bars. If that can't start, the bars dance to a built-in beat instead.
$script:audioSrc = @'
using System;
using System.Runtime.InteropServices;
using System.Threading;

public static class AudioTap
{
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumeratorCom { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(int dataFlow, int stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid iid, int clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        [PreserveSig] int OpenPropertyStore(int access, out IntPtr props);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int state);
    }

    [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioClient
    {
        [PreserveSig] int Initialize(int shareMode, int streamFlags, long bufferDuration, long periodicity, IntPtr format, IntPtr sessionGuid);
        [PreserveSig] int GetBufferSize(out int frames);
        [PreserveSig] int GetStreamLatency(out long latency);
        [PreserveSig] int GetCurrentPadding(out int padding);
        [PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closest);
        [PreserveSig] int GetMixFormat(out IntPtr format);
        [PreserveSig] int GetDevicePeriod(out long defaultPeriod, out long minPeriod);
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
        [PreserveSig] int Reset();
        [PreserveSig] int SetEventHandle(IntPtr handle);
        [PreserveSig] int GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }

    [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioCaptureClient
    {
        [PreserveSig] int GetBuffer(out IntPtr data, out int frames, out int flags, out long devPos, out long qpcPos);
        [PreserveSig] int ReleaseBuffer(int frames);
        [PreserveSig] int GetNextPacketSize(out int frames);
    }

    const int RING = 8192;
    static float[] ring = new float[RING];
    static int wpos = 0;
    static readonly object lk = new object();
    static Thread th;
    static volatile bool run = false;
    static int lastData = 0;
    static double agc = 0.01;
    public static string Status = "off";
    public static int SampleRate = 48000;

    public static void Start()
    {
        if (run) return;
        run = true;
        Status = "starting";
        th = new Thread(Loop);
        th.IsBackground = true;
        th.Name = "Ekk0hAudio";
        th.Start();
    }

    public static void Stop() { run = false; }

    static void Loop()
    {
        try { Capture(); }
        catch (Exception ex) { Status = "error: " + ex.Message; }
        run = false;
    }

    static void Capture()
    {
        IMMDeviceEnumerator en = (IMMDeviceEnumerator)new MMDeviceEnumeratorCom();
        IMMDevice dev;
        if (en.GetDefaultAudioEndpoint(0, 1, out dev) != 0) { Status = "no output device"; return; }
        Guid iidAc = new Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
        object o;
        if (dev.Activate(ref iidAc, 23, IntPtr.Zero, out o) != 0) { Status = "activate failed"; return; }
        IAudioClient ac = (IAudioClient)o;
        IntPtr fmt;
        if (ac.GetMixFormat(out fmt) != 0) { Status = "no mix format"; return; }
        short tag = Marshal.ReadInt16(fmt, 0);
        int ch = Marshal.ReadInt16(fmt, 2);
        int rate = Marshal.ReadInt32(fmt, 4);
        int bits = Marshal.ReadInt16(fmt, 14);
        bool isFloat = (tag == 3);
        if (tag == unchecked((short)0xFFFE)) { isFloat = (Marshal.ReadInt32(fmt, 24) == 3); }
        if (ch < 1) ch = 2;
        SampleRate = rate;
        int hr = ac.Initialize(0, 0x00020000, 10000000L, 0L, fmt, IntPtr.Zero);
        if (hr != 0) { Status = "init failed 0x" + hr.ToString("X"); return; }
        Guid iidCc = new Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317");
        object o2;
        if (ac.GetService(ref iidCc, out o2) != 0) { Status = "no capture service"; return; }
        IAudioCaptureClient cc = (IAudioCaptureClient)o2;
        if (ac.Start() != 0) { Status = "start failed"; return; }
        Status = "listening";
        float[] f32 = new float[8192];
        short[] i16 = new short[8192];
        while (run)
        {
            int pk;
            if (cc.GetNextPacketSize(out pk) != 0) break;
            while (pk > 0 && run)
            {
                IntPtr data; int frames; int flags; long dp; long qp;
                if (cc.GetBuffer(out data, out frames, out flags, out dp, out qp) != 0) { run = false; break; }
                int n = frames * ch;
                if ((flags & 2) != 0 || n <= 0 || n > 8192)
                {
                    if (n > 0 && n <= 8192) PushSilence(frames);
                }
                else if (isFloat && bits == 32)
                {
                    Marshal.Copy(data, f32, 0, n);
                    lock (lk) { for (int f = 0; f < frames; f++) { float s = 0; for (int c = 0; c < ch; c++) s += f32[f * ch + c]; ring[wpos] = s / ch; wpos = (wpos + 1) & (RING - 1); } }
                    lastData = Environment.TickCount;
                }
                else if (bits == 16)
                {
                    Marshal.Copy(data, i16, 0, n);
                    lock (lk) { for (int f = 0; f < frames; f++) { float s = 0; for (int c = 0; c < ch; c++) s += i16[f * ch + c]; ring[wpos] = s / (ch * 32768f); wpos = (wpos + 1) & (RING - 1); } }
                    lastData = Environment.TickCount;
                }
                cc.ReleaseBuffer(frames);
                if (cc.GetNextPacketSize(out pk) != 0) { pk = 0; }
            }
            Thread.Sleep(10);
        }
        ac.Stop();
        Status = "stopped";
    }

    static void PushSilence(int frames)
    {
        lock (lk) { for (int f = 0; f < frames; f++) { ring[wpos] = 0f; wpos = (wpos + 1) & (RING - 1); } }
    }

    // Fills dst with 0..1 levels, low notes first. Returns false when nothing has been playing lately.
    public static bool GetBands(double[] dst)
    {
        int nb = dst.Length;
        bool live = run && Status == "listening" && unchecked(Environment.TickCount - lastData) < 700;
        if (!live) { for (int i = 0; i < nb; i++) dst[i] = 0; return false; }
        const int N = 2048;
        double[] re = new double[N];
        double[] im = new double[N];
        lock (lk) { int start = (wpos - N) & (RING - 1); for (int i = 0; i < N; i++) re[i] = ring[(start + i) & (RING - 1)]; }
        for (int i = 0; i < N; i++) re[i] *= 0.5 - 0.5 * Math.Cos(2 * Math.PI * i / (N - 1));
        Fft(re, im);
        double binHz = (double)SampleRate / N;
        double lo = 40.0, hi = Math.Min(14000.0, SampleRate / 2.0 - 100);
        double[] raw = new double[nb];
        double cur = 0;
        for (int b = 0; b < nb; b++)
        {
            double f0 = lo * Math.Pow(hi / lo, (double)b / nb);
            double f1 = lo * Math.Pow(hi / lo, (double)(b + 1) / nb);
            int k0 = (int)Math.Floor(f0 / binHz); int k1 = (int)Math.Ceiling(f1 / binHz);
            if (k0 < 1) k0 = 1; if (k1 <= k0) k1 = k0 + 1; if (k1 > N / 2) k1 = N / 2;
            double m = 0;
            for (int k = k0; k < k1; k++) { double mag = Math.Sqrt(re[k] * re[k] + im[k] * im[k]) / (N / 4.0); if (mag > m) m = mag; }
            m *= 0.7 + 1.1 * ((double)b / nb);
            raw[b] = m; if (m > cur) cur = m;
        }
        agc = Math.Max(Math.Max(agc * 0.9985, cur), 0.004);
        for (int b = 0; b < nb; b++) { double v = Math.Sqrt(raw[b] / agc); if (v > 1) v = 1; dst[b] = v; }
        return true;
    }

    static void Fft(double[] re, double[] im)
    {
        int n = re.Length;
        for (int i = 1, j = 0; i < n; i++)
        {
            int bit = n >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) { double t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
        }
        for (int len = 2; len <= n; len <<= 1)
        {
            double ang = -2 * Math.PI / len;
            double wr = Math.Cos(ang), wi = Math.Sin(ang);
            for (int i = 0; i < n; i += len)
            {
                double cr = 1, ci = 0;
                for (int k = 0; k < len / 2; k++)
                {
                    int a = i + k, b = i + k + len / 2;
                    double xr = re[b] * cr - im[b] * ci, xi = re[b] * ci + im[b] * cr;
                    re[b] = re[a] - xr; im[b] = im[a] - xi;
                    re[a] += xr; im[a] += xi;
                    double ncr = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = ncr;
                }
            }
        }
    }
}
'@

$script:audioOn = $false
$script:audioFailed = $false
$script:rgbN = 48
$script:rgbRaw = New-Object 'double[]' 48
$script:rgbCur = New-Object 'double[]' 48
$script:rgbPeak = New-Object 'double[]' 48
$script:rgbAvgBass = 0.0
$script:rgbBeat = 0.0
$script:rgbLastBeat = 0.0

function Start-AudioReact {
    if ($script:audioOn) { return }
    try { if ((Get-Settings).RgbAudio -eq '0') { return } } catch { }
    try {
        if (-not ('AudioTap' -as [type])) { Add-Type -TypeDefinition $script:audioSrc -Language CSharp }
        [AudioTap]::Start()
        $script:audioOn = $true
        $script:audioFailed = $false
    } catch {
        $script:audioFailed = $true
        try { Add-Content -LiteralPath (Join-Path $PSScriptRoot 'run-log.txt') -Value ("audio: " + $_.Exception.Message) } catch { }
    }
}
function Stop-AudioReact {
    if (-not $script:audioOn) { return }
    try { [AudioTap]::Stop() } catch { }
    $script:audioOn = $false
}

function Invoke-PaintRgbBack($g, [int]$w, [int]$h) {
    $full = New-RectF 0 0 $w $h
    $sky = New-VGrad $full $script:cBg $script:cSky
    $g.FillRectangle($sky, $full); $sky.Dispose()
}
function Invoke-HdrRgbA($g, [int]$w, [int]$h) {
    $t = Get-HdrT
    $n = $script:rgbN
    Show-HdrLayer $g 'rgb.back' $w $h 'Invoke-PaintRgbBack'
    $live = $false
    if ($script:audioOn) { try { $live = [AudioTap]::GetBands($script:rgbRaw) } catch { $live = $false } }
    $demo = ($script:audioFailed -or -not $script:audioOn)
    $kick = [math]::Pow(0.5 + 0.5 * [math]::Sin($t * 4.0 * [math]::PI), 5)
    for ($i = 0; $i -lt $n; $i++) {
        if ($live) { $target = $script:rgbRaw[$i] }
        elseif ($demo) {
            $bw = [math]::Exp(-$i / 9.0)
            $target = 0.10 + 0.70 * ($kick * $bw + 0.40 * [math]::Abs([math]::Sin($t * 3.1 + $i * 0.55)) * ($i / $n) + 0.15 * [math]::Abs([math]::Sin($t * 1.3 + $i * 0.2)))
        }
        else { $target = 0.04 + 0.05 * (0.5 + 0.5 * [math]::Sin($t * 1.6 + $i * 0.35)) }
        if ($target -gt 1) { $target = 1 }
        $script:rgbRaw[$i] = $target
        $cur = $script:rgbCur[$i]
        if ($target -gt $cur) { $cur = $cur + ($target - $cur) * 0.7 } else { $cur = [math]::Max($target, $cur - 0.055) }
        $script:rgbCur[$i] = $cur
        $pk = $script:rgbPeak[$i] - 0.012
        if ($cur -gt $pk) { $pk = $cur }
        $script:rgbPeak[$i] = $pk
    }
    # beat: the low bands jump above their recent average
    $bass = 0.0; for ($i = 0; $i -lt 6; $i++) { $bass += $script:rgbRaw[$i] }; $bass = $bass / 6.0
    if ($bass -gt ($script:rgbAvgBass * 1.3 + 0.12) -and ($t - $script:rgbLastBeat) -gt 0.2) { $script:rgbBeat = 1.0; $script:rgbLastBeat = $t }
    $script:rgbAvgBass = $script:rgbAvgBass * 0.92 + $bass * 0.08
    $script:rgbBeat = $script:rgbBeat * 0.86
    $beat = $script:rgbBeat
    $hueBase = $t * 36
    if ($beat -gt 0.02) {
        $fb = New-SolidBr (Get-HueColor ($hueBase + 200) ([int](46 * $beat)))
        $g.FillRectangle($fb, 0, 0, $w, $h); $fb.Dispose()
    }
    $bwid = $w / [double]$n
    $maxH = $h * 0.80
    $glow = New-SolidBr ([System.Drawing.Color]::White)
    $body = New-SolidBr ([System.Drawing.Color]::White)
    $capB = New-SolidBr ([System.Drawing.Color]::White)
    for ($i = 0; $i -lt $n; $i++) {
        $x = $i * $bwid
        $v = $script:rgbCur[$i]
        $bh = 2 + $v * $maxH
        $y = $h - 5 - $bh
        $fade = [math]::Max(0.0, [math]::Min(1.0, ($x - 260) / 420.0))
        $hue = $i / $n * 300 + $hueBase
        $glow.Color = Get-HueColor $hue ([int](26 + 30 * $fade + 40 * $beat))
        $g.FillRectangle($glow, [single]($x - 2), [single]($y - 4), [single]($bwid + 3), [single]($bh + 8))
        $body.Color = Get-HueColor $hue ([int](70 + 130 * $fade))
        $g.FillRectangle($body, [single]($x + 1), [single]$y, [single]($bwid - 3), [single]$bh)
        $capB.Color = Get-HueColor ($hue + 20) ([int](130 + 120 * $fade))
        $g.FillRectangle($capB, [single]($x + 1), [single]$y, [single]($bwid - 3), [single]2.4)
        $py = $h - 5 - (2 + $script:rgbPeak[$i] * $maxH) - 4
        if ($py -lt ($y - 3)) { $g.FillRectangle($capB, [single]($x + 1), [single]$py, [single]($bwid - 3), [single]1.6) }
    }
    $glow.Dispose(); $body.Dispose(); $capB.Dispose()
    # LED look: thin dark lines across all the bars
    $lp = New-Object System.Drawing.Pen((Get-Alpha 150 $script:cBg), 1)
    for ($yy = 8; $yy -lt ($h - 4); $yy += 4) { $g.DrawLine($lp, 0, $yy, $w, $yy) }
    $lp.Dispose()
    # light strip along the bottom that flares on the beat
    for ($x = 0; $x -lt $w; $x += 8) {
        $sb = New-SolidBr (Get-HueColor ($x / $w * 300 + $hueBase) ([int](170 + 85 * $beat)))
        $g.FillRectangle($sb, [single]$x, [single]($h - 3), 8, 3); $sb.Dispose()
    }
}

# ---------------------------------------------------------------- display helpers (map + identify)
function Get-DisplaySignature {
    return (([System.Windows.Forms.Screen]::AllScreens | ForEach-Object { "$($_.Bounds.X),$($_.Bounds.Y),$($_.Bounds.Width),$($_.Bounds.Height)" }) -join ';')
}

# Draws every screen to scale in its real position, with the selected pack on it.
function Invoke-MapPaint($panel, $e) {
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $w = $panel.ClientSize.Width
    $h = $panel.ClientSize.Height
    $full = New-Object System.Drawing.RectangleF(0, 0, $w, $h)
    $bgb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, $script:cDlgA, $script:cDlgB, [single]90)
    $g.FillRectangle($bgb, $full)
    $bgb.Dispose()
    $gp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(34, $script:cPurple), 1)
    for ($gx = 0; $gx -lt $w; $gx += 24) { $g.DrawLine($gp, $gx, 0, $gx, $h) }
    for ($gy = 0; $gy -lt $h; $gy += 24) { $g.DrawLine($gp, 0, $gy, $w, $gy) }
    $gp.Dispose()

    $ds = @(Get-DisplayList)
    if ($ds.Count -eq 0) { return }
    # geometry in "units": real millimetres when matching physical size, otherwise pixels
    $lay = Get-PhysicalLayout
    $fix = $null
    if ($panel -eq $script:pnlMap) { $fix = $script:mapFix }
    if ($fix) { $mL = $fix.MinL; $mT = $fix.MinY } else { $mL = $lay.MinL; $mT = $lay.MinY }
    $geo = @{}
    foreach ($it in $lay.Items) { $geo[$it.Index] = @{ X = ($it.L - $mL); Y = ($it.T - $mT); W = $it.PW; H = $it.PH; Diag = $it.Diag } }
    $bw = [double]$lay.BW; $bh = [double]$lay.BH
    if ($panel -eq $script:pnlPrev) { $pad = 6.0 } else { $pad = 24.0 }
    if ($fix) {
        $scale = $fix.Scale; $offX = $fix.OffX; $offY = $fix.OffY
    } else {
        $scale = [math]::Min(($w - 2 * $pad) / $bw, ($h - 2 * $pad) / $bh)
        $offX = ($w - $bw * $scale) / 2
        $offY = ($h - $bh * $scale) / 2
    }
    if ($panel -eq $script:pnlMap) { $script:mapOffX = $offX; $script:mapOffY = $offY }

    # the pack currently selected on the Packs tab
    $imgs = @()
    $sel = $script:lbPacks.SelectedItem
    if ($panel.Tag -is [string] -and $panel.Tag) { $sel = [string]$panel.Tag }
    if (-not $sel -and $panel -eq $script:pnlMap -and $script:currentPack -and (Test-Path -LiteralPath (Join-Path $Root $script:currentPack))) { $sel = [string]$script:currentPack }
    if ($sel) { $imgs = @(Get-PackImages (Join-Path $Root $sel)) }

    $clean = ($panel -eq $script:pnlPrev)
    $numFont = $null
    $isMap = ($panel -eq $script:pnlMap)
    if ($isMap) { $script:mapRects = @{}; $script:mapScale = $scale }
    foreach ($d in $ds) {
        $gm = $geo[$d.Index]
        $rx = [single]($offX + $gm.X * $scale)
        $ry = [single]($offY + $gm.Y * $scale)
        $rw = [single]($gm.W * $scale)
        $rh = [single]($gm.H * $scale)
        $rect = New-Object System.Drawing.RectangleF(($rx + 2), ($ry + 2), ($rw - 4), ($rh - 4))
        if ($isMap) { $script:mapRects[$d.Index] = $rect }
        $ri = New-Object System.Drawing.Rectangle([int]$rect.X, [int]$rect.Y, [int]$rect.Width, [int]$rect.Height)

        $drewImage = $false
        if ($imgs.Count -gt 0) {
            $f = $imgs[($d.Index - 1) % $imgs.Count]
            $tw = 480
            $th = [int][math]::Max(60, 480 * $d.H / $d.W)
            $key = "$($f.FullName)|$($f.Length)|map$tw`x$th"
            if (-not $script:thumbCache.ContainsKey($key)) { $script:thumbCache[$key] = New-Thumb $f.FullName $tw $th }
            $t = $script:thumbCache[$key]
            if ($t) { $g.DrawImage($t, $ri); $drewImage = $true }
        }
        if (-not $drewImage) {
            $fb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, (Get-Blend $script:cPanel2 $script:cHover 0.5), $script:cHover, [single]90)
            $g.FillRectangle($fb, $rect)
            $fb.Dispose()
        }

        if ($clean) {
            # Packs-tab preview: just the picture, no names, numbers or tint
            $tp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(160, $script:cCyan), 1)
            $g.DrawRectangle($tp, $rect.X, $rect.Y, $rect.Width, $rect.Height)
            $tp.Dispose()
            continue
        }
        $isSel = ($panel -eq $script:pnlMap -and $script:cmbPhysScreen -and ($script:cmbPhysScreen.SelectedIndex + 1) -eq $d.Index)
        if ($isSel) { $bc = $script:cAccent } else { $bc = $script:cCyan }
        if ($isSel) { $gw = 10 } else { $gw = 6 }
        if ($isSel) { $bpw = 3 } else { $bpw = 2 }
        $bp = New-Object System.Drawing.Pen($bc, $bpw)
        $g.DrawRectangle($bp, $rect.X, $rect.Y, $rect.Width, $rect.Height)
        $bp.Dispose()

        # big position number (screen 1 = leftmost)
        $nsz = [single][math]::Max(14, [math]::Min(54, $rect.Height * 0.46))
        $numFont = Get-RetroFont $nsz 'Bold, Italic'
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, 0, 0, 0))
        $shRect = New-Object System.Drawing.RectangleF(($rect.X + 1), ($rect.Y + 1), $rect.Width, $rect.Height)
        $g.DrawString([string]$d.Index, $numFont, $sh, $shRect, $sf)
        $nb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $g.DrawString([string]$d.Index, $numFont, $nb, $rect, $sf)
        $sh.Dispose(); $nb.Dispose(); $sf.Dispose(); $numFont.Dispose()

        # caption strip along the bottom of the screen (long text ends in ...)
        $cf = Get-RetroFont 8 'Bold'
        $tag = "$($d.W)x$($d.H)"
        if ($gm.Diag -gt 0) { $tag += ("  {0:0.#} in" -f $gm.Diag) }
        if ($d.Primary) { $tag += "  MAIN" }
        $cb = New-Object System.Drawing.SolidBrush($script:cText)
        $csf = New-Object System.Drawing.StringFormat
        $csf.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
        $csf.FormatFlags = [System.Drawing.StringFormatFlags]::NoWrap
        $capRect = New-Object System.Drawing.RectangleF(($rect.X + 6), ($rect.Bottom - 17), [math]::Max(10, $rect.Width - 12), 15)
        $g.DrawString($tag, $cf, $cb, $capRect, $csf)
        $csf.Dispose(); $cb.Dispose(); $cf.Dispose()
    }
}

# Flashes a big number on every screen so you can tell which is which.
function Show-Identify {
    if ($script:identTimer) { $script:identTimer.Stop() }
    if ($script:identForms) { foreach ($f in $script:identForms) { try { $f.Close() } catch { } } }
    $script:identForms = @()
    foreach ($d in (Get-DisplayList)) {
        $f = New-Object System.Windows.Forms.Form
        $f.FormBorderStyle = 'None'
        $f.StartPosition = 'Manual'
        $f.ShowInTaskbar = $false
        $f.TopMost = $true
        $f.BackColor = $script:cBg
        $cw = 420; $ch = 270
        $f.Bounds = New-Object System.Drawing.Rectangle(($d.X + [int](($d.W - $cw) / 2)), ($d.Y + [int](($d.H - $ch) / 2)), $cw, $ch)
        $f.Tag = $d
        $f.Add_Paint({
            param($s, $e)
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
            $d = $s.Tag
            $rect = New-Object System.Drawing.RectangleF(0, 0, $s.ClientSize.Width, $s.ClientSize.Height)
            $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $script:cBg, $script:cDlgB, [single]90)
            $g.FillRectangle($bg, $rect)
            $bg.Dispose()
            $pen = New-Object System.Drawing.Pen($script:cCyan, 4)
            $g.DrawRectangle($pen, 3, 3, ($s.ClientSize.Width - 7), ($s.ClientSize.Height - 7))
            $pen.Dispose()
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $big = Get-RetroFont 110 'Bold, Italic'
            $sr = New-Object System.Drawing.RectangleF(4, 8, $s.ClientSize.Width, 190)
            $shb = New-Object System.Drawing.SolidBrush($script:cAccent)
            $g.DrawString([string]$d.Index, $big, $shb, $sr, $sf)
            $wr = New-Object System.Drawing.RectangleF(0, 4, $s.ClientSize.Width, 190)
            $wb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $g.DrawString([string]$d.Index, $big, $wb, $wr, $sf)
            $small = Get-RetroFont 12 'Bold'
            $txt = "DISPLAY $($d.WinNum)   $($d.W) x $($d.H)"
            if ($d.Primary) { $txt += "   MAIN" }
            $cb = New-Object System.Drawing.SolidBrush($script:cCyan)
            $cr = New-Object System.Drawing.RectangleF(0, 200, $s.ClientSize.Width, 40)
            $g.DrawString($txt, $small, $cb, $cr, $sf)
            $big.Dispose(); $small.Dispose(); $shb.Dispose(); $wb.Dispose(); $cb.Dispose(); $sf.Dispose()
        })
        $script:identForms += $f
        $f.Show()
    }
    $script:identTimer = New-Object System.Windows.Forms.Timer
    $script:identTimer.Interval = 2400
    $script:identTimer.Add_Tick({
        $script:identTimer.Stop()
        foreach ($f in $script:identForms) { try { $f.Close() } catch { } }
        $script:identForms = @()
    })
    $script:identTimer.Start()
}

# Dropped items can be pictures or folders of pictures; returns the picture files in name order.
function Expand-ImagePaths([string[]]$paths) {
    $out = @()
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            $out += @(Get-PackImages $p)
        } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $f = Get-Item -LiteralPath $p
            if ($f.Name -match $ImageExt) { $out += $f }
        }
    }
    if ($out.Count -eq 0) { return @() }
    return @(Get-NaturalSorted $out)
}

function New-BlackImage([string]$path, [int]$w, [int]$h) {
    $bmp = New-Object System.Drawing.Bitmap($w, $h)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Black)
    $g.Dispose()
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# ---------------------------------------------------------------- cookie cutter (position the screens over the photo)
# Shows your screens, at real size and spacing, as cutters over the picture. Drag to move them,
# mouse wheel to resize. Everything outside the cutters (including the bezel gaps) is dimmed.
function Show-Cutter($img, $lay, $init = $null, [string]$title = "Position your screens", [string]$okText = "Slice", $owner = $null) {
    $script:cutImg = $img
    $script:cutLay = $lay
    $iw = [double]$img.Width; $ih = [double]$img.Height
    $script:cutK0 = [math]::Min($iw / $lay.BW, $ih / $lay.BH)
    $script:cutZoom = 1.0
    $script:cutCx = $iw / 2
    $script:cutCy = $ih / 2
    $script:cutDrag = $false

    $dlgW = 860
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $title
    $dlg.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $dlg.AutoScaleMode = 'Dpi'
    $dlg.ClientSize = New-Object System.Drawing.Size($dlgW, 560)
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:cBg
    $dlg.ForeColor = $script:cText
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    $dlg.Icon = $script:appIcon
    $dlg.Add_HandleCreated({ param($s, $e) Set-TitleBar $s.Handle })

    $hdr = New-Object System.Windows.Forms.Panel
    $hdr.Location = New-Object System.Drawing.Point(0, 0)
    $hdr.Size = New-Object System.Drawing.Size($dlgW, 84)
    Set-DoubleBuffered $hdr
    $hdr.Add_Paint({ param($s, $e) Invoke-RetroHeaderPaint $e.Graphics $s.ClientSize.Width $s.ClientSize.Height "CUT" "PHOTO" $null 0 })
    $dlg.Controls.Add($hdr)
    $dlg.Controls.Add((New-Label "Drag to move your screens over the photo. Mouse wheel makes them bigger or smaller. Only the bright parts become wallpaper - the dim parts hide behind the bezels." 24 94 812 40 $true 9))

    $cv = New-Object System.Windows.Forms.Panel
    $cv.Location = New-Object System.Drawing.Point(24, 138)
    $cv.Size = New-Object System.Drawing.Size(812, 360)
    $cv.BackColor = [System.Drawing.Color]::Black
    Set-DoubleBuffered $cv
    try { $cv.GetType().GetMethod('SetStyle', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($cv, @([System.Windows.Forms.ControlStyles]::Selectable, $true)) } catch { }
    $script:cutCanvas = $cv
    $dlg.Controls.Add($cv)

    $cv.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $img = $script:cutImg; $lay = $script:cutLay
        $cw = $s.ClientSize.Width; $ch = $s.ClientSize.Height
        $sc = [math]::Min($cw / [double]$img.Width, $ch / [double]$img.Height)
        $ox = ($cw - $img.Width * $sc) / 2
        $oy = ($ch - $img.Height * $sc) / 2
        $full = New-Object System.Drawing.RectangleF([single]$ox, [single]$oy, [single]($img.Width * $sc), [single]($img.Height * $sc))
        $g.DrawImage($img, $full)
        $dim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(165, 6, 0, 20))
        $g.FillRectangle($dim, $full)
        $dim.Dispose()
        $k = $script:cutK0 * $script:cutZoom
        $bx = $script:cutCx - $lay.BW * $k / 2
        $by = $script:cutCy - $lay.BH * $k / 2
        $nf = Get-RetroFont 22 'Bold, Italic'
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $pen = New-Object System.Drawing.Pen($script:cAccent, 2)
        foreach ($it in $lay.Items) {
            $rx = [single]($ox + ($bx + $it.L * $k) * $sc)
            $ry = [single]($oy + ($by + ($it.T - $lay.MinY) * $k) * $sc)
            $rw = [single]($it.PW * $k * $sc)
            $rh = [single]($it.PH * $k * $sc)
            $r = New-Object System.Drawing.RectangleF($rx, $ry, $rw, $rh)
            $state = $g.Save()
            $g.SetClip($r)
            $g.DrawImage($img, $full)
            $g.Restore($state)
            $g.DrawRectangle($pen, $rx, $ry, $rw, $rh)
            $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, $script:cPurple))
            $rs = New-Object System.Drawing.RectangleF(($rx + 2), ($ry + 2), $rw, $rh)
            $g.DrawString([string]$it.Index, $nf, $sh, $rs, $sf)
            $g.DrawString([string]$it.Index, $nf, [System.Drawing.Brushes]::White, $r, $sf)
            $sh.Dispose()
        }
        $pen.Dispose(); $nf.Dispose(); $sf.Dispose()
    })

    $script:cutClamp = {
        $img = $script:cutImg; $lay = $script:cutLay
        $k = $script:cutK0 * $script:cutZoom
        $hw = $lay.BW * $k / 2; $hh = $lay.BH * $k / 2
        $script:cutCx = [math]::Max($hw, [math]::Min($img.Width - $hw, $script:cutCx))
        $script:cutCy = [math]::Max($hh, [math]::Min($img.Height - $hh, $script:cutCy))
    }
    if ($init) {
        $script:cutZoom = [math]::Max(0.2, [math]::Min(1.0, [double]$init.Zoom))
        $script:cutCx = [double]$init.Cx * $iw
        $script:cutCy = [double]$init.Cy * $ih
        & $script:cutClamp
    }
    $cv.Add_MouseDown({
        param($s, $e)
        $script:cutDrag = $true
        $s.Focus()
        $script:cutMx = $e.X; $script:cutMy = $e.Y
        $s.Cursor = [System.Windows.Forms.Cursors]::SizeAll
    })
    $cv.Add_MouseMove({
        param($s, $e)
        if (-not $script:cutDrag) { return }
        $img = $script:cutImg
        $sc = [math]::Min($s.ClientSize.Width / [double]$img.Width, $s.ClientSize.Height / [double]$img.Height)
        $script:cutCx += ($e.X - $script:cutMx) / $sc
        $script:cutCy += ($e.Y - $script:cutMy) / $sc
        $script:cutMx = $e.X; $script:cutMy = $e.Y
        & $script:cutClamp
        $s.Invalidate()
    })
    $cv.Add_MouseUp({ param($s, $e) $script:cutDrag = $false; $s.Cursor = [System.Windows.Forms.Cursors]::Default })
    $cv.Add_MouseWheel({
        param($s, $e)
        if ($e.Delta -gt 0) { $f = 1.08 } else { $f = 1 / 1.08 }
        $script:cutZoom = [math]::Max(0.2, [math]::Min(1.0, $script:cutZoom * $f))
        & $script:cutClamp
        $s.Invalidate()
    })
    $cv.Add_MouseEnter({ param($s, $e) $s.Focus() })

    $btnOk = New-Btn $okText 24 508 150 'primary' 40
    $btnOk.DialogResult = 'OK'
    $btnReset = New-Btn "Reset" 190 508 150 'normal' 40
    $btnReset.Add_Click({
        $script:cutZoom = 1.0
        $script:cutCx = $script:cutImg.Width / 2
        $script:cutCy = $script:cutImg.Height / 2
        $script:cutCanvas.Invalidate()
    })
    $btnCancel = New-Btn "Cancel" 686 508 150 'danger' 40
    $btnCancel.DialogResult = 'Cancel'
    foreach ($b in @($btnOk, $btnReset, $btnCancel)) { $dlg.Controls.Add($b) }
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel

    if (-not $owner) { $owner = $script:form }
    $res = $dlg.ShowDialog($owner)
    $dlg.Dispose()
    if ($res -ne 'OK') { return $null }
    $k = $script:cutK0 * $script:cutZoom
    return @{ K = $k; OffX = ($script:cutCx - $lay.BW * $k / 2); OffY = ($script:cutCy - $lay.BH * $k / 2); Zoom = $script:cutZoom; CxF = ($script:cutCx / $iw); CyF = ($script:cutCy / $ih) }
}


function Rename-SelectedPack {
    $name = $script:lbPacks.SelectedItem
    if (-not $name) { Set-Status "Pick a pack first."; return }
    $new = [Microsoft.VisualBasic.Interaction]::InputBox("New name for this pack:", "Rename pack", [string]$name)
    if (-not $new) { return }
    $safe = Get-SafeName $new
    if (-not $safe) { Set-Status "That name can't be used."; return }
    if ($safe -eq $name) { return }
    $target = Join-Path $Root $safe
    if (Test-Path -LiteralPath $target) { Set-Status "A pack called '$safe' already exists."; return }
    try {
        Rename-Item -LiteralPath (Join-Path $Root $name) -NewName $safe
        if ($script:currentPack -eq $name) { $script:currentPack = $safe }
        Move-PackMeta ([string]$name) $safe
        $script:thumbCache = @{}
        Update-PackList $safe
        Set-Status "Renamed '$name' to '$safe'."
    } catch {
        Set-Status "Couldn't rename: $($_.Exception.Message)"
    }
}

# ================================================================ BUILDER TAB (model, painting, actions)
# One picture/video "slot" per group of linked screens. A slot can also hold "over" slots:
# a different picture or video on a single screen inside a panorama (the rest of the panorama stays).
$script:btData = @{}
$script:btLinks = @()
$script:btSel = 1
$script:btPack = $null
$script:btDirty = $false
$script:btLinkPts = @()
$script:btCache = @{}
$script:btSrcMap = $null
$script:btKeep = @()

function New-BtSlot { return @{ type = 'none'; path = ''; up = $false; zoom = 1.0; cx = 0.5; cy = 0.5; over = @{}; rot = 0; t0 = 0.0; t1 = 0.0 } }

function Reset-Bt {
    $script:btData = @{}
    $script:btLinks = @()
    $script:btSel = 1
    $script:btPack = $null
    $script:btDirty = $false
    $script:btCache = @{}
    Sync-Bt
    if ($script:txtBtName) { $script:txtBtName.Text = "" }
    Clear-BtHistory
}

function Get-BtGroups {
    $n = @(Get-DisplayList).Count
    $out = @()
    $s = 1
    while ($s -le $n) {
        $e = $s
        while ($e -lt $n -and $script:btLinks[$e - 1]) { $e++ }
        $out += , @{ Lead = $s; Screens = @($s..$e) }
        $s = $e + 1
    }
    return $out
}

function Get-BtGroupOf([int]$screen) {
    foreach ($g in @(Get-BtGroups)) { if ($g.Screens -contains $screen) { return $g } }
    return @{ Lead = 1; Screens = @(1) }
}

function Get-BtLeader([int]$screen) { return [int](Get-BtGroupOf $screen).Lead }

function Sync-Bt {
    $n = @(Get-DisplayList).Count
    $links = New-Object 'bool[]' ([math]::Max(0, $n - 1))
    for ($i = 0; $i -lt $links.Length; $i++) { if ($i -lt $script:btLinks.Count) { $links[$i] = [bool]$script:btLinks[$i] } }
    $script:btLinks = $links
    $new = @{}
    foreach ($grp in @(Get-BtGroups)) {
        if ($script:btData.ContainsKey($grp.Lead)) { $sl = $script:btData[$grp.Lead] } else { $sl = New-BtSlot }
        if (-not $sl.over) { $sl.over = @{} }
        foreach ($k in @($sl.over.Keys)) { if ($grp.Screens -notcontains [int]$k -or $grp.Screens.Count -lt 2) { $sl.over.Remove($k) } }
        $new[$grp.Lead] = $sl
    }
    $script:btData = $new
    if ($script:btSel -lt 1) { $script:btSel = 1 }
    if ($script:btSel -gt $n) { $script:btSel = [math]::Max(1, $n) }
}

# What is shown on a screen: its own alternate picture if it has one, else its group's.
function Get-BtTarget([int]$screen) {
    $grp = Get-BtGroupOf $screen
    $sl = $script:btData[$grp.Lead]
    if ($sl -and $sl.over -and $sl.over.ContainsKey($screen)) {
        return @{ Slot = $sl.over[$screen]; Screens = @($screen); IsOver = $true; Group = $grp; Parent = $sl }
    }
    $cut = @($grp.Screens | Where-Object { -not ($sl -and $sl.over -and $sl.over.ContainsKey([int]$_)) })
    if ($cut.Count -eq 0) { $cut = @($grp.Screens) }
    return @{ Slot = $sl; Screens = $cut; IsOver = $false; Group = $grp; Parent = $sl }
}

function Get-BtPreview($slot) {
    if (-not $slot -or $slot.type -eq 'none' -or -not $slot.path) { return $null }
    $key = [string]$slot.path + '|' + [string][int]$slot.rot
    if ($script:btCache.ContainsKey($key)) { return $script:btCache[$key] }
    $bmp = $null
    try {
        if ($slot.type -eq 'video') {
            if ($script:thumbOk) { $bmp = [ShellThumb]::Get($slot.path, 640, 360) }
            if ($bmp) {
                switch ([int]$slot.rot) {
                    90  { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
                    180 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
                    270 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
                }
            }
        } elseif (Test-Path -LiteralPath $slot.path) {
            $ld = Read-ImageFromFile $slot.path
            $w = $ld.Image.Width; $h = $ld.Image.Height
            $sc = [math]::Min(1.0, 1600.0 / [math]::Max($w, $h))
            $bmp = New-Object System.Drawing.Bitmap ([int][math]::Max(1, [math]::Round($w * $sc))), ([int][math]::Max(1, [math]::Round($h * $sc)))
            $gg = [System.Drawing.Graphics]::FromImage($bmp)
            $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $gg.DrawImage($ld.Image, 0, 0, $bmp.Width, $bmp.Height)
            $gg.Dispose(); $ld.Image.Dispose(); $ld.Stream.Dispose()
            switch ([int]$slot.rot) {
                90  { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate90FlipNone) }
                180 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate180FlipNone) }
                270 { $bmp.RotateFlip([System.Drawing.RotateFlipType]::Rotate270FlipNone) }
            }
        }
    } catch { $bmp = $null }
    $script:btCache[$key] = $bmp
    return $bmp
}

# Big view, like the cutter: the picture for the selected screen with the screens laid over it.
# Bright parts become wallpaper, dim parts hide behind the bezels. Drag to move, wheel to zoom.
function Invoke-BtSrcPaint($g, [int]$W, [int]$H) {
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Black)
    $script:btSrcMap = $null
    $script:btChips = @(); $script:btFrames = @(); $script:btLinkPts = @()
    Sync-Bt
    $barH = 58
    $PH = $H - $barH
    $lay = Get-PhysicalLayout
    $items = @($lay.Items | Sort-Object Index)
    if ($items.Count -eq 0) { return }
    $t = Get-BtTarget $script:btSel
    $bmp = Get-BtPreview $t.Slot
    $fnt = New-Object System.Drawing.Font("Segoe UI", 10)
    $fntB = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $fntS = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
    $dim = New-Object System.Drawing.SolidBrush ($script:cDim)
    $txt = New-Object System.Drawing.SolidBrush ($script:cText)

    # ---- the picture with the screens laid over it
    if (-not $bmp) {
        if ($t.Slot.type -eq 'video') { $m = "Video selected - no preview available." }
        else { $m = "Drop a picture or video here, or on a screen below`nThen drag the screens over it and scroll to zoom" }
        $g.DrawString($m, $fnt, $dim, (New-Object System.Drawing.RectangleF 0, 0, $W, $PH), $sf)
    } else {
        $sub = Get-SubLayout $lay $t.Screens
        $sc = [math]::Min($W / $bmp.Width, $PH / $bmp.Height)
        $ox = ($W - $bmp.Width * $sc) / 2; $oy = ($PH - $bmp.Height * $sc) / 2
        $dest = New-Object System.Drawing.RectangleF ([single]$ox), ([single]$oy), ([single]($bmp.Width * $sc)), ([single]($bmp.Height * $sc))
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $g.DrawImage($bmp, $dest)
        $shade = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(165, 0, 0, 0))
        $g.FillRectangle($shade, $dest)
        $shade.Dispose()
        $box = Get-CutBox $sub $bmp.Width $bmp.Height $t.Slot
        $pen = New-Object System.Drawing.Pen ($script:cAccent), 2
        $nf = New-Object System.Drawing.Font("Segoe UI", 20, ([System.Drawing.FontStyle]::Bold -bor [System.Drawing.FontStyle]::Italic))
        $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $purp = New-Object System.Drawing.SolidBrush ($script:cPurple)
        foreach ($it in $sub.Items) {
            $sx = $box.X + $it.L * $box.K; $sy = $box.Y + ($it.T - $sub.MinY) * $box.K
            $sw = $it.PW * $box.K; $sh = $it.PH * $box.K
            $r = New-Object System.Drawing.RectangleF ([single]($ox + $sx * $sc)), ([single]($oy + $sy * $sc)), ([single]($sw * $sc)), ([single]($sh * $sc))
            $srcR = New-Object System.Drawing.RectangleF ([single]$sx), ([single]$sy), ([single]$sw), ([single]$sh)
            $g.DrawImage($bmp, $r, $srcR, [System.Drawing.GraphicsUnit]::Pixel)
            if ($it.Index -eq $script:btSel) { $pen.Width = 3 } else { $pen.Width = 2 }
            $g.DrawRectangle($pen, $r.X, $r.Y, $r.Width, $r.Height)
            $g.DrawString([string]$it.Index, $nf, $purp, (New-Object System.Drawing.RectangleF ($r.X + 2), ($r.Y + 2), $r.Width, $r.Height), $sf)
            $g.DrawString([string]$it.Index, $nf, $white, $r, $sf)
            $script:btFrames += , @{ Screen = [int]$it.Index; R = $r }
        }
        $pen.Dispose(); $nf.Dispose(); $white.Dispose(); $purp.Dispose()
        $fx = $ox + $box.X * $sc; $fy = $oy + $box.Y * $sc
        $fw = $sub.BW * $box.K * $sc; $fh = $sub.BH * $box.K * $sc
        $script:btSrcMap = @{ Sc = $sc; W = $bmp.Width; H = $bmp.Height; Ox = $ox; Oy = $oy; Fx = $fx; Fy = $fy; Fw = $fw; Fh = $fh; Bw = $sub.BW; Bh = $sub.BH; K0 = [math]::Min($bmp.Width / $sub.BW, $bmp.Height / $sub.BH) }
        # corner handles: drag one to resize the whole set of screens over the picture
        $hb = New-Object System.Drawing.SolidBrush ($script:cAccent)
        $hp = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 1.5
        foreach ($c in @(@($fx, $fy), @(($fx + $fw), $fy), @($fx, ($fy + $fh)), @(($fx + $fw), ($fy + $fh)))) {
            $g.FillRectangle($hb, [single]($c[0] - 6), [single]($c[1] - 6), 12, 12)
            $g.DrawRectangle($hp, [single]($c[0] - 6), [single]($c[1] - 6), 12, 12)
        }
        $hb.Dispose(); $hp.Dispose()
    }

    # ---- the screen bar: every screen, what it shows, + to link
    $barBr = New-Object System.Drawing.SolidBrush ($script:cBarBg)
    $g.FillRectangle($barBr, 0, $PH, $W, $barH)
    $barBr.Dispose()
    $ln = New-Object System.Drawing.Pen ($script:cPurple), 1
    $g.DrawLine($ln, 0, $PH, $W, $PH)
    $ln.Dispose()
    $chipH = 38
    $cy0 = $PH + ($barH - $chipH) / 2
    $totalW = 0
    $cw = @{}
    foreach ($it in $items) { $cw[$it.Index] = [math]::Min(96.0, [math]::Max(40.0, $chipH * $it.PW / $it.PH)); $totalW += $cw[$it.Index] }
    $linkW = 30
    $totalW += $linkW * ($items.Count - 1)
    $x = ($W - $totalW) / 2
    $selGroup = Get-BtGroupOf $script:btSel
    $panelBr = New-Object System.Drawing.SolidBrush ($script:cPanel)
    $chipRects = @{}
    for ($i = 0; $i -lt $items.Count; $i++) {
        $it = $items[$i]
        $s = $it.Index
        $r = New-Object System.Drawing.RectangleF ([single]$x), ([single]$cy0), ([single]$cw[$s]), ([single]$chipH)
        $chipRects[$s] = $r
        $ct = Get-BtTarget $s
        $cb = Get-BtPreview $ct.Slot
        $g.FillRectangle($panelBr, $r)
        if ($cb) {
            $csub = Get-SubLayout $lay $ct.Screens
            $cbox = Get-CutBox $csub $cb.Width $cb.Height $ct.Slot
            $ci = $csub.Items | Where-Object { $_.Index -eq $s } | Select-Object -First 1
            if ($ci) {
                $src = New-Object System.Drawing.RectangleF ([single]($cbox.X + $ci.L * $cbox.K)), ([single]($cbox.Y + ($ci.T - $csub.MinY) * $cbox.K)), ([single]($ci.PW * $cbox.K)), ([single]($ci.PH * $cbox.K))
                $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
                $g.DrawImage($cb, $r, $src, [System.Drawing.GraphicsUnit]::Pixel)
            }
        } elseif ($ct.Slot.type -eq 'video') {
            $g.DrawString("VIDEO", $fntS, $txt, $r, $sf)
        } else {
            $g.DrawString("empty", $fntS, $dim, $r, $sf)
        }
        if ($s -eq $script:btSel) { $pen = New-Object System.Drawing.Pen ($script:cAccent), 3 }
        elseif ($selGroup.Screens -contains $s) { $pen = New-Object System.Drawing.Pen ($script:cAccent), 1.5 }
        else { $pen = New-Object System.Drawing.Pen ($script:cCyan), 1.2 }
        $g.DrawRectangle($pen, $r.X, $r.Y, $r.Width, $r.Height)
        $pen.Dispose()
        # number, and badges
        $nb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(200, 0, 0, 0))
        $g.FillRectangle($nb, $r.Right - 14, $r.Bottom - 15, 14, 15)
        $nb.Dispose()
        $g.DrawString([string]$s, $fntS, $txt, (New-Object System.Drawing.RectangleF ($r.Right - 14), ($r.Bottom - 15), 14, 15), $sf)
        $badge = @()
        if ($ct.IsOver) { $badge += "ALT" }
        if ($ct.IsOver -or $ct.Group.Lead -eq $s) {
            if ($ct.Slot.type -eq 'video') { $badge += "VIDEO" }
            if ($ct.Slot.type -eq 'image' -and $ct.Slot.up) { $badge += "AI" }
        }
        if ($badge.Count -gt 0) {
            $bt = $badge -join "+"
            $bw = [single](8 + 5.4 * $bt.Length)
            $bb = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(225, $script:cAccent))
            $g.FillRectangle($bb, $r.X + 2, $r.Y + 2, $bw, 13)
            $bb.Dispose()
            $btxt = New-Object System.Drawing.SolidBrush ($script:cPrimTxt)
            $g.DrawString($bt, $fntS, $btxt, (New-Object System.Drawing.RectangleF ($r.X + 2), ($r.Y + 2), $bw, 13), $sf)
            $btxt.Dispose()
        }
        $script:btChips += , @{ Screen = [int]$s; R = $r }
        $x += $cw[$s]
        if ($i -lt $items.Count - 1) {
            $mx = $x + $linkW / 2; $my = $cy0 + $chipH / 2
            $linked = [bool]$script:btLinks[$i]
            if ($linked) { $fill = New-Object System.Drawing.SolidBrush ($script:cAccent) } else { $fill = New-Object System.Drawing.SolidBrush ($script:cBg) }
            $pen = New-Object System.Drawing.Pen ($script:cCyan), 1.6
            $g.FillEllipse($fill, [single]($mx - 10), [single]($my - 10), 20, 20)
            $g.DrawEllipse($pen, [single]($mx - 10), [single]($my - 10), 20, 20)
            $lbl = "+"; if ($linked) { $lbl = "=" }
            $g.DrawString($lbl, $fntB, $txt, (New-Object System.Drawing.RectangleF ([single]($mx - 10)), ([single]($my - 11)), 20, 20), $sf)
            $pen.Dispose(); $fill.Dispose()
            $script:btLinkPts += , @{ I = $i; X = $mx; Y = $my }
            $x += $linkW
        }
    }
    $panelBr.Dispose()
    $fnt.Dispose(); $fntB.Dispose(); $fntS.Dispose(); $sf.Dispose(); $dim.Dispose(); $txt.Dispose()
}

function Get-BtText {
    $t = Get-BtTarget $script:btSel
    $slot = $t.Slot
    $what = "empty"
    if ($slot.type -eq 'image') { $what = "picture: " + (Split-Path $slot.path -Leaf) }
    if ($slot.type -eq 'video') { $what = "video: " + (Split-Path $slot.path -Leaf) }
    if ($t.IsOver) { return "Screen $($script:btSel) - own $what  (in the panorama on screens $($t.Group.Screens[0])-$($t.Group.Screens[-1]))" }
    if ($t.Screens.Count -gt 1) {
        $extra = ""
        if ($slot.over.Count -gt 0) { $extra = "  +$($slot.over.Count) own" }
        return "Screens $($t.Screens[0])-$($t.Screens[-1]) - $what$extra   (Picture/Video here replaces only screen $($script:btSel))"
    }
    return "Screen $($script:btSel) - $what"
}

# Reads a picture's or video's pixel size (cached). Videos are read from ffmpeg's text output.
function Get-BtSourceSize($slot) {
    if (-not $slot -or -not $slot.path -or -not (Test-Path -LiteralPath $slot.path)) { return $null }
    if (-not $script:btDims) { $script:btDims = @{} }
    $k = [string]$slot.path
    if ($script:btDims.ContainsKey($k)) { return $script:btDims[$k] }
    $dim = $null
    try {
        if ($slot.type -eq 'image') {
            $fs = [IO.File]::OpenRead($slot.path)
            try { $im = [System.Drawing.Image]::FromStream($fs, $false, $false); $dim = @($im.Width, $im.Height); $im.Dispose() } finally { $fs.Dispose() }
        } elseif ($slot.type -eq 'video') {
            $ff = Find-Ffmpeg
            if ($ff) {
                $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
                try { $o = (& $ff -hide_banner -i $slot.path 2>&1 | Out-String) } finally { $ErrorActionPreference = $old }
                $m = [regex]::Match($o, 'Video:.*?(\d{2,5})x(\d{2,5})')
                if ($m.Success) { $dim = @([int]$m.Groups[1].Value, [int]$m.Groups[2].Value) }
            }
        }
    } catch { $dim = $null }
    $script:btDims[$k] = $dim
    return $dim
}
function Get-BtSizeWarn($t) {
    try {
        if (-not $t -or -not $t.Slot -or $t.Slot.type -eq 'none') { return "" }
        $d = Get-BtSourceSize $t.Slot
        if (-not $d) { return "" }
        $w = [double]$d[0]; $h = [double]$d[1]
        if (([int]$t.Slot.rot -eq 90 -or [int]$t.Slot.rot -eq 270)) { $tmp = $w; $w = $h; $h = $tmp }
        $ds = @(Get-DisplayList)
        $needW = 0.0; $needH = 0.0
        foreach ($sc in $t.Screens) {
            $dd = $ds | Where-Object { [int]$_.Index -eq [int]$sc } | Select-Object -First 1
            if ($dd) { $needW += $dd.W; $needH = [math]::Max($needH, $dd.H) }
        }
        if ($needW -le 0) { return "" }
        $z = [math]::Max(0.2, [double]$t.Slot.zoom)
        $needW = $needW / $z; $needH = $needH / $z
        if ($w -lt 0.85 * $needW -and $h -lt 0.85 * $needH -or $w -lt 0.6 * $needW -or $h -lt 0.6 * $needH) {
            return ("   -  Small source: {0}x{1} for about {2}x{3} of screen - it will look soft." -f [int]$w, [int]$h, [int]$needW, [int]$needH)
        }
    } catch { }
    return ""
}

function Update-BtInfo {
    if (-not $script:lblBtSel) { return }
    Sync-Bt
    $t = Get-BtTarget $script:btSel
    $script:lblBtSel.Text = (Get-BtText) + (Get-BtSizeWarn $t)
    $script:loadingBt = $true
    $isVid = ($t.Slot.type -eq 'video')
    $script:numBtT0.Value = [decimal][math]::Min(86400, [math]::Max(0, [double]$t.Slot.t0))
    $script:numBtT1.Value = [decimal][math]::Min(86400, [math]::Max(0, [double]$t.Slot.t1))
    foreach ($c in @($script:numBtT0, $script:numBtT1)) { $c.Enabled = $isVid }
    $hasPic = ($t.Slot.type -ne 'none')
    foreach ($c in @($script:btnBtRotL, $script:btnBtRotR)) { $c.Enabled = $hasPic }
    $script:lblBtRot.Text = $(if ($hasPic) { "turned {0} deg" -f [int]$t.Slot.rot } else { "" })
    $script:chkBtUp.Checked = [bool]$t.Slot.up
    $script:chkBtUp.Enabled = ($t.Slot.type -eq 'image')
    $script:loadingBt = $false
    $script:btnBtClear.Enabled = ($t.Slot.type -ne 'none')
    if ($script:pnlBt) { $script:pnlBt.Invalidate() }
    if ($script:pnlBtSrc) { $script:pnlBtSrc.Invalidate() }
}

# Puts one file on a screen. Empty group: fills the whole group. Panorama with a picture already:
# only this screen gets the new file. Returns the next screen to fill.
function Set-BtPlace([int]$screen, [string]$path) {
    Sync-Bt
    $grp = Get-BtGroupOf $screen
    $parent = $script:btData[$grp.Lead]
    $slot = New-BtSlot
    $video = ([IO.Path]::GetExtension($path) -match $VideoExt)
    $slot.path = $path
    if ($video) { $slot.type = 'video' } else { $slot.type = 'image' }
    $script:btDirty = $true
    if ($grp.Screens.Count -gt 1 -and $parent.type -ne 'none') {
        if ($parent.over.ContainsKey($screen)) { $slot.up = [bool]$parent.over[$screen].up -and -not $video }
        $parent.over[$screen] = $slot
        return ($screen + 1)
    }
    $slot.up = [bool]$parent.up -and -not $video
    $slot.over = $parent.over
    $script:btData[$grp.Lead] = $slot
    return ($grp.Screens[-1] + 1)
}

# Drop/picked files go on screens in order, starting at screen $start.
function Add-BtFiles([string[]]$paths, [int]$start = -1) {
    $files = @()
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            $files += @(Get-PackImages $p | ForEach-Object { $_.FullName })
            $files += @(Get-ChildItem -LiteralPath $p -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match $VideoExt } | Sort-Object Name | ForEach-Object { $_.FullName })
        } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $ext = [IO.Path]::GetExtension($p)
            if ($ext -match $ImageExt -or $ext -match $VideoExt) { $files += $p }
        }
    }
    if ($files.Count -eq 0) { Set-Status "Nothing usable there (pictures: jpg, png, bmp - videos: mp4, webm, gif, mkv, mov, avi)."; return }
    Sync-Bt
    $n = @(Get-DisplayList).Count
    $cur = $start
    if ($cur -lt 1) { $cur = 1 }
    $first = $cur; $placed = 0
    foreach ($f in $files) {
        if ($cur -gt $n) { break }
        $cur = Set-BtPlace $cur $f
        $placed++
    }
    $script:btSel = [math]::Min($first, $n)
    if ($placed -lt $files.Count) { Set-Status "Placed $placed of $($files.Count) files - there are only that many screens." } else { Set-Status "Placed $placed file(s). Drag the screens over the picture below to set the cut." }
    Update-BtInfo
}

function Switch-BtLink([int]$i) {
    if ($i -lt 0 -or $i -ge $script:btLinks.Count) { return }
    $script:btLinks[$i] = -not $script:btLinks[$i]
    Sync-Bt
    $script:btSel = $i + 1
    $script:btDirty = $true
    Update-BtInfo
}

function Invoke-BtPosition {
    $t = Get-BtTarget $script:btSel
    $slot = $t.Slot
    if (-not $slot -or $slot.type -eq 'none') { Set-Status "Add a picture or video to this spot first."; return }
    $lay = Get-PhysicalLayout
    $sub = Get-SubLayout $lay $t.Screens
    $file = $slot.path; $tmp = $null
    if ($slot.type -eq 'video') {
        $ff = Find-Ffmpeg
        if (-not $ff) { Show-FfmpegMissing; return }
        $script:form.Cursor = 'WaitCursor'
        try { $tmp = Get-VideoFramePath $ff $slot.path ([int]$slot.rot) } finally { $script:form.Cursor = 'Default' }
        if (-not $tmp) { Set-Status "Couldn't read a picture from that video."; return }
        $file = $tmp
    }
    try {
        $ld = Read-ImageFromFile $file
        $cut = Show-Cutter $ld.Image $sub @{ Zoom = $slot.zoom; Cx = $slot.cx; Cy = $slot.cy } "Position your screens" "OK" $script:form
        $ld.Image.Dispose(); $ld.Stream.Dispose()
    } finally { if ($tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
    if (-not $cut) { return }
    $slot.zoom = $cut.Zoom; $slot.cx = $cut.CxF; $slot.cy = $cut.CyF
    $script:btDirty = $true
    Update-BtInfo
}

function ConvertFrom-BtRecipeGroup($g, [string]$dir) {
    $slot = New-BtSlot
    $slot.zoom = $g.zoom; $slot.cx = $g.cx; $slot.cy = $g.cy; $slot.up = [bool]$g.up
    if ($g.type -eq 'video' -and $g.vpath) { $slot.type = 'video'; $slot.path = $g.vpath; $slot.up = $false; $slot.rot = [int]$g.rot; $slot.t0 = [double]$g.t0; $slot.t1 = [double]$g.t1 }
    elseif ($g.source) { $slot.type = 'image'; $slot.path = Join-Path (Join-Path $dir "_source") $g.source; $slot.rot = [int]$g.rot }
    return $slot
}

function Load-BtFromPack([string]$name) {
    $dir = Join-Path $Root $name
    if (-not (Test-Path -LiteralPath $dir)) { return }
    Reset-Bt
    $n = @(Get-DisplayList).Count
    $groups = Get-Recipe $dir
    $script:loadingBt = $true
    if ($script:chkBtBlend) { $script:chkBtBlend.Checked = (@(@($groups) | Where-Object { $_ -and $_.blend }).Count -gt 0) }
    $script:loadingBt = $false
    $links = New-Object 'bool[]' ([math]::Max(0, $n - 1))
    $data = @{}
    $overs = @()
    if ($groups) {
        foreach ($g in @($groups)) {
            $scr = @($g.screens | Where-Object { $_ -ge 1 -and $_ -le $n } | Sort-Object)
            if ($scr.Count -eq 0) { continue }
            if ($g.over) { $overs += , @{ Screen = [int]$scr[0]; G = $g }; continue }
            for ($k = $scr[0]; $k -lt $scr[-1]; $k++) { $links[$k - 1] = $true }
            $data[[int]$scr[0]] = ConvertFrom-BtRecipeGroup $g $dir
        }
    } else {
        $imgs = @(Get-PackImages $dir)
        if ($imgs.Count -eq 0) { Set-Status "That pack has no pictures."; return }
        if (Test-PanoramaPack $imgs $n) {
            $ans = [System.Windows.Forms.MessageBox]::Show("This pack looks like one panorama that was cut into pieces.`n`nJoin the pieces back into one picture so it can be repositioned here? (The pieces are kept in an _original folder.)", "Load pack", 'YesNo', 'Question')
            if ($ans -ne 'Yes') { return }
            $script:form.Cursor = 'WaitCursor'
            try { $g1 = Convert-PackToPanorama $dir } finally { $script:form.Cursor = 'Default' }
            for ($k = 0; $k -lt $n - 1; $k++) { $links[$k] = $true }
            $slot = New-BtSlot
            $slot.type = 'image'; $slot.path = Join-Path (Join-Path $dir "_source") $g1.source
            $slot.zoom = $g1.zoom; $slot.cx = $g1.cx; $slot.cy = $g1.cy
            $data[1] = $slot
        } else {
            for ($k = 0; $k -lt [math]::Min($imgs.Count, $n); $k++) {
                $slot = New-BtSlot
                $slot.type = 'image'; $slot.path = $imgs[$k].FullName
                $data[$k + 1] = $slot
            }
        }
    }
    $script:btLinks = $links
    $script:btData = $data
    Sync-Bt
    foreach ($o in $overs) {
        $lead = Get-BtLeader $o.Screen
        $og = Get-BtGroupOf $o.Screen
        if ($og.Screens.Count -ge 2 -and $script:btData[$lead].type -ne 'none') { $script:btData[$lead].over[$o.Screen] = ConvertFrom-BtRecipeGroup $o.G $dir }
        else { $keepOver = $script:btData[$lead].over; $ns = ConvertFrom-BtRecipeGroup $o.G $dir; $ns.over = $keepOver; $script:btData[$lead] = $ns }
    }
    $script:btPack = $name
    $script:btSel = 1
    $script:btDirty = $false
    if ($script:txtBtName) { $script:txtBtName.Text = $name }
    Update-BtInfo
    Clear-BtHistory
    Set-Status "Loaded '$name' into the builder."
}

# Slot -> recipe group (copies the picture into the pack's _source folder).
function ConvertTo-BtRecipeGroup($slot, $screens, [string]$dir, [string]$srcDir, [bool]$isOver) {
    $g = @{ screens = @($screens); source = ''; up = $false; zoom = [double]$slot.zoom; cx = [double]$slot.cx; cy = [double]$slot.cy; type = 'image'; vpath = ''; over = $isOver; rot = 0; t0 = 0.0; t1 = 0.0; blend = $false }
    if ($slot.type -eq 'none' -and $script:chkBtBlend) { $g.blend = [bool]$script:chkBtBlend.Checked }
    if ($slot.type -eq 'image' -and (Test-Path -LiteralPath $slot.path)) {
        $full = [IO.Path]::GetFullPath($slot.path)
        $parent = Split-Path $full -Parent
        $srcFull = [IO.Path]::GetFullPath($srcDir)
        $already = $script:btKeep | Where-Object { $_.From -eq $full } | Select-Object -First 1
        if ($already) {
            $g.source = $already.To
        } elseif ($parent -eq $srcFull) {
            $g.source = Split-Path $full -Leaf
            $script:btKeep += , @{ From = $full; To = $g.source }
        } else {
            $fn = "src_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + [IO.Path]::GetExtension($full).ToLower()
            if ($parent -eq [IO.Path]::GetFullPath($dir)) { Move-Item -LiteralPath $full -Destination (Join-Path $srcDir $fn) -Force }
            else { Copy-Item -LiteralPath $full -Destination (Join-Path $srcDir $fn) -Force }
            $g.source = $fn
            $script:btKeep += , @{ From = $full; To = $fn }
        }
        $g.up = [bool]$slot.up
        $g.rot = [int]$slot.rot
    } elseif ($slot.type -eq 'video') {
        $g.type = 'video'; $g.vpath = [string]$slot.path; $g.rot = [int]$slot.rot; $g.t0 = [double]$slot.t0; $g.t1 = [double]$slot.t1
    }
    return $g
}

function Save-BtPack {
    Sync-Bt
    $name = Get-SafeName ([string]$script:txtBtName.Text)
    if (-not $name) { Set-Status "Give the pack a name first."; return }
    $groups = @(Get-BtGroups)
    $all = @()
    foreach ($grp in $groups) {
        $sl = $script:btData[$grp.Lead]
        $all += , $sl
        foreach ($k in @($sl.over.Keys)) { $all += , $sl.over[$k] }
    }
    if (@($all | Where-Object { $_.type -ne 'none' }).Count -eq 0) { Set-Status "Add at least one picture or video first."; return }
    $exe = $null
    if (@($all | Where-Object { $_.type -eq 'image' -and $_.up }).Count -gt 0 -and (Test-AddonOn 'upscale')) { $exe = Confirm-Upscaler; if (-not $exe) { return } }
    if (@($all | Where-Object { $_.type -eq 'video' }).Count -gt 0) { if (-not (Find-Ffmpeg)) { Show-FfmpegMissing; return } }
    $askLock = -not (Test-Path -LiteralPath (Join-Path (Join-Path (Join-Path $Root $name) '_lock') 'lock.json'))
    $pickLock = $false
    if ($askLock) {
        $q = [System.Windows.Forms.MessageBox]::Show("No lock screen has been chosen for this pack.`n`nSave without selecting a lock screen?`n`nYes = save now (Windows' default lock screen is used)`nNo = save, then choose a lock screen", "Lock screen", 'YesNo', 'Question')
        if ($q -ne 'Yes') { $pickLock = $true }
    }
    $inPlace = ($script:btPack -and $name -eq $script:btPack -and (Test-Path -LiteralPath (Join-Path $Root $name)))
    $script:form.Cursor = 'WaitCursor'
    $dir = $null; $created = $false
    try {
        if ($inPlace) { $dir = Join-Path $Root $name } else { $dir = Get-NewPackDir $name; $created = $true }
        if (-not $dir) { Set-Status "That name can't be used."; return }
        if (Test-Path -LiteralPath (Join-Path $dir "_video")) {
            try { Stop-Animated } catch { }
            Remove-Item -LiteralPath (Join-Path $dir "_video") -Recurse -Force -ErrorAction SilentlyContinue
        }
        $srcDir = Join-Path $dir "_source"
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
        $script:btKeep = @()
        $rec = @(); $overRec = @()
        foreach ($grp in $groups) {
            $sl = $script:btData[$grp.Lead]
            $baseScr = @($grp.Screens | Where-Object { -not $sl.over.ContainsKey([int]$_) })
            if ($baseScr.Count -eq 0) { $baseScr = @($grp.Screens) }
            $rec += , (ConvertTo-BtRecipeGroup $sl $baseScr $dir $srcDir $false)
            foreach ($k in @($sl.over.Keys | Sort-Object)) {
                $overRec += , (ConvertTo-BtRecipeGroup $sl.over[$k] @([int]$k) $dir $srcDir $true)
            }
        }
        $rec = @($rec) + @($overRec)
        $keepNames = @($script:btKeep | ForEach-Object { $_.To })
        foreach ($f in @(Get-ChildItem -LiteralPath $srcDir -File -ErrorAction SilentlyContinue)) {
            if ($keepNames -notcontains $f.Name) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
        }
        Set-Status "Building '$(Split-Path $dir -Leaf)' (upscaling and video cuts can take a while)..."
        Render-Recipe $dir $rec $exe
        Save-Recipe $dir $rec
        $final = Split-Path $dir -Leaf
        $script:thumbCache = @{}
        Update-PackList $final
        $script:btPack = $final
        $script:txtBtName.Text = $final
        $script:btDirty = $false
        # the saved pictures now live in _source, so point the builder there
        Load-BtFromPack $final
        Set-Status "Saved pack '$final'."
        if ($script:chkBtApply.Checked) { [void](Set-Pack $dir) }
        if ($pickLock) { Show-LockPanel $true }
    } catch {
        Set-Status "Couldn't build the pack: $($_.Exception.Message)"
        if ($created -and $dir -and (Test-Path -LiteralPath $dir)) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    } finally {
        $script:form.Cursor = 'Default'
    }
}


# Which corner handle (if any) is under the mouse. Returns @{ Corner; AX; AY } with the opposite corner as anchor.
function Get-BtHandle([int]$x, [int]$y) {
    $m = $script:btSrcMap
    if (-not $m) { return $null }
    $l = $m.Fx; $t = $m.Fy; $r = $m.Fx + $m.Fw; $bt = $m.Fy + $m.Fh
    $cs = @(
        @{ Corner = 'TL'; X = $l; Y = $t; AX = $r; AY = $bt },
        @{ Corner = 'TR'; X = $r; Y = $t; AX = $l; AY = $bt },
        @{ Corner = 'BL'; X = $l; Y = $bt; AX = $r; AY = $t },
        @{ Corner = 'BR'; X = $r; Y = $bt; AX = $l; AY = $t })
    foreach ($c in $cs) { if ([math]::Abs($x - $c.X) -le 9 -and [math]::Abs($y - $c.Y) -le 9) { return $c } }
    return $null
}

# Resizes the set of screens from a dragged corner, keeping the opposite corner fixed.
function Set-BtResize([int]$x, [int]$y, $anchor, $slot) {
    $m = $script:btSrcMap
    $dx = [math]::Abs($x - $anchor.AX); $dy = [math]::Abs($y - $anchor.AY)
    $wPx = [math]::Max($dx, $dy * $m.Bw / $m.Bh)
    $k = $wPx / $m.Sc / $m.Bw
    $zoom = [math]::Max(0.2, [math]::Min(1.0, $k / $m.K0))
    $k = $zoom * $m.K0
    $wPx = $k * $m.Bw * $m.Sc; $hPx = $k * $m.Bh * $m.Sc
    if ($x -ge $anchor.AX) { $left = $anchor.AX } else { $left = $anchor.AX - $wPx }
    if ($y -ge $anchor.AY) { $top = $anchor.AY } else { $top = $anchor.AY - $hPx }
    $cxPx = $left + $wPx / 2; $cyPx = $top + $hPx / 2
    $slot.zoom = $zoom
    $slot.cx = [math]::Max(0.0, [math]::Min(1.0, (($cxPx - $m.Ox) / $m.Sc) / $m.W))
    $slot.cy = [math]::Max(0.0, [math]::Min(1.0, (($cyPx - $m.Oy) / $m.Sc) / $m.H))
}
# ---------------------------------------------------------------- GPU saver (auto-pause live wallpapers)
# Lively's wallpaper players are frozen (suspended) while a full-screen app is in front, and
# thawed again afterwards. A frozen player uses no GPU and almost no CPU; the last frame stays up.
$script:probeOk = $true
if (-not ('WinProbe' -as [type])) {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class WinProbe {
    [DllImport("shell32.dll")] static extern int SHQueryUserNotificationState(out int state);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
    [DllImport("user32.dll")] static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] static extern int GetClassName(IntPtr h, StringBuilder sb, int max);
    [DllImport("ntdll.dll")] static extern int NtSuspendProcess(IntPtr h);
    [DllImport("ntdll.dll")] static extern int NtResumeProcess(IntPtr h);
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    // 2 = a full-screen app, 3 = a full-screen Direct3D game, 4 = presentation mode
    public static int Notif() {
        try { int s; if (SHQueryUserNotificationState(out s) == 0) return s; } catch { }
        return 0;
    }
    public static string Foreground(out int pid, out bool zoomed) {
        pid = 0; zoomed = false;
        try {
            IntPtr h = GetForegroundWindow();
            if (h == IntPtr.Zero) return "";
            GetWindowThreadProcessId(h, out pid);
            zoomed = IsZoomed(h);
            StringBuilder sb = new StringBuilder(128);
            GetClassName(h, sb, 128);
            return sb.ToString();
        } catch { return ""; }
    }
    public static bool Suspend(int pid) {
        IntPtr h = OpenProcess(0x800, false, pid);
        if (h == IntPtr.Zero) return false;
        try { return NtSuspendProcess(h) == 0; } finally { CloseHandle(h); }
    }
    public static bool Resume(int pid) {
        IntPtr h = OpenProcess(0x800, false, pid);
        if (h == IntPtr.Zero) return false;
        try { return NtResumeProcess(h) == 0; } finally { CloseHandle(h); }
    }
}
"@
    } catch { $script:probeOk = $false }
}

$script:pauseMode = 'Off'
$script:pauseBattery = $false
$script:wpPaused = $false
$script:wpPausedPids = @{}

# The processes that actually draw the video wallpapers.
function Get-WpPlayers {
    $list = @()
    try {
        $list = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Lively.Player*' })
        if ($list.Count -eq 0) {
            $core = @(Get-Process -Name 'Lively' -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($core.Count -gt 0) {
                $kids = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId = {0}" -f $core[0].Id) -ErrorAction SilentlyContinue)
                foreach ($k in $kids) {
                    $nm = [IO.Path]::GetFileNameWithoutExtension([string]$k.Name)
                    if ($nm -match '(?i)ui|watchdog|crash|update|setup') { continue }
                    $pr = Get-Process -Id $k.ProcessId -ErrorAction SilentlyContinue
                    if ($pr) { $list += $pr }
                }
            }
        }
    } catch { }
    return $list
}

function Get-PauseReason {
    if ($script:manualPause -and $script:probeOk) { return 'you paused them with the hotkey' }
    if (($script:pauseMode -eq 'Off' -and -not $script:pauseBattery) -or -not $script:probeOk) { return '' }
    try {
        if ($script:pauseBattery) {
            $ps = [System.Windows.Forms.SystemInformation]::PowerStatus
            if ($ps.PowerLineStatus -eq [System.Windows.Forms.PowerLineStatus]::Offline) { return 'running on battery' }
        }
        $st = [WinProbe]::Notif()
        if ($st -eq 2 -or $st -eq 3 -or $st -eq 4) { return 'a full-screen app or game is in front' }
        if ($script:pauseMode -eq 'Maximized') {
            $pid2 = 0; $zoomed = $false
            $cls = [WinProbe]::Foreground([ref]$pid2, [ref]$zoomed)
            if ($zoomed -and $pid2 -ne $PID -and $cls -notin @('Progman', 'WorkerW', 'Shell_TrayWnd', 'Shell_SecondaryTrayWnd')) { return 'a window is maximized' }
        }
    } catch { }
    return ''
}

function Set-PauseLabel([string]$text) {
    if ($script:lblPauseState) { $script:lblPauseState.Text = $text }
}

function Suspend-WpPlayers {
    $n = 0
    foreach ($p in (Get-WpPlayers)) {
        if ($script:wpPausedPids.ContainsKey($p.Id)) { continue }
        if ([WinProbe]::Suspend($p.Id)) { $script:wpPausedPids[$p.Id] = $true; $n++ }
    }
    return $n
}

# Thaws everything frozen by this app (and, with -All, any Lively player, e.g. left over from a crash).
function Resume-WpPlayers([switch]$All) {
    foreach ($id in @($script:wpPausedPids.Keys)) { try { [void][WinProbe]::Resume([int]$id) } catch { } }
    $script:wpPausedPids = @{}
    if ($All) { foreach ($p in (Get-WpPlayers)) { try { [void][WinProbe]::Resume($p.Id) } catch { } } }
}

function Update-AutoPause {
    if (-not $script:probeOk) { return }
    $reason = Get-PauseReason
    if ($reason) {
        if (-not $script:wpPaused) {
            $n = Suspend-WpPlayers
            if ($n -gt 0) {
                $script:wpPaused = $true
                Set-PauseLabel "Paused - $reason"
                Set-Status "Live wallpapers paused ($reason)."
            } else {
                Set-PauseLabel "Waiting - no live wallpaper is running"
            }
        } else {
            [void](Suspend-WpPlayers)   # catches a player started while paused
        }
    } else {
        if ($script:wpPaused) {
            Resume-WpPlayers
            $script:wpPaused = $false
            Set-Status "Live wallpapers resumed."
        }
        if ($script:pauseMode -eq 'Off' -and -not $script:pauseBattery) { Set-PauseLabel "" } else { Set-PauseLabel "Watching - plays normally" }
    }
}

function Set-AutoPauseMode([string]$mode, [bool]$battery) {
    $script:pauseMode = $mode
    $script:pauseBattery = $battery
    if ($mode -eq 'Off' -and -not $battery) {
        if ($script:wpPaused) { Resume-WpPlayers; $script:wpPaused = $false }
        Set-PauseLabel ""
    } else { Update-AutoPause }
}

# ---------------------------------------------------------------- live theme switching
function Get-PaletteMap {
    $m = @{}
    foreach ($n in @('cBg', 'cPanel', 'cPanel2', 'cHover', 'cText', 'cDim', 'cAccent', 'cAccentHover', 'cAccentDown', 'cCyan', 'cPurple', 'cOrange', 'cSun', 'cDanger', 'cDangerHover', 'cStatText')) {
        $v = Get-Variable -Scope Script -Name $n -ValueOnly -ErrorAction SilentlyContinue
        if ($null -eq $v) { continue }
        $k = $v.ToArgb()
        if (-not $m.ContainsKey($k)) { $m[$k] = $n }
    }
    return $m
}

function Update-ControlColors($parent, $old) {
    foreach ($c in $parent.Controls) {
        try {
            $tn = $c.GetType().Name
            $b = $c.BackColor
            if ($b.A -eq 255 -and $old.ContainsKey($b.ToArgb())) { $c.BackColor = (Get-Variable -Scope Script -Name $old[$b.ToArgb()] -ValueOnly) }
            $f = $c.ForeColor
            if ($f.A -eq 255 -and $old.ContainsKey($f.ToArgb())) { $c.ForeColor = (Get-Variable -Scope Script -Name $old[$f.ToArgb()] -ValueOnly) }
            if ($tn -eq 'Label' -and $c.Text.StartsWith('// ')) { $c.ForeColor = $script:cHead; $c.Font = Get-RetroFont 9 }
            elseif ($tn -eq 'Button' -and $c.Tag -is [hashtable] -and $c.Tag.ContainsKey('Kind')) { $c.BackColor = $script:cBg; $c.Font = Get-RetroFont ([single]$c.Font.Size) }
            elseif ($tn -eq 'NeonCombo') {
                $c.BoxBack = $script:cPanel2; $c.BoxTop = $script:cBoxTop; $c.ItemBack = $script:cMenuBack; $c.ItemSel = $script:cMenuSel
                $c.BoxText = $script:cText; $c.Edge = $script:cCyan; $c.Hot = $script:cAccent
            }
            elseif ($tn -eq 'NeonCheck') { $c.Edge = $script:cCyan; $c.Hot = $script:cAccent; $c.Sun = $script:cOrange; $c.Inner = $script:cInner }
            elseif ($tn -eq 'NeonSpin') { $c.Edge = $script:cCyan; $c.Hot = $script:cAccent; $c.BoxBack = $script:cPanel2; $c.BoxTop = $script:cBoxTop }
            if ($c.Controls.Count -gt 0) { Update-ControlColors $c $old }
            $c.Invalidate()
        } catch { }
    }
}

# When the Wallpaper theme is on, re-read the colors whenever a different pack is applied.
function Update-WallpaperTheme {
    if ($script:themeName -ne 'Wallpaper' -or -not $script:pnlHeader -or -not $script:form) { return }
    $old = Get-PaletteMap
    Set-Theme 'Wallpaper'
    $script:form.BackColor = $script:cBg
    $script:form.ForeColor = $script:cText
    Update-ControlColors $script:form $old
    $script:pnlHeader.Invalidate()
    $script:form.Invalidate($true)
    if ($script:gridCanvas) { $script:gridCanvas.Invalidate() }
}

function Switch-ThemeLive([string]$name) {
    $old = Get-PaletteMap
    Set-Theme $name
    Save-Setting 'Theme' $name
    $script:form.BackColor = $script:cBg
    $script:form.ForeColor = $script:cText
    Update-ControlColors $script:form $old
    Set-TitleBar $script:form.Handle
    $script:pnlHeader.Invalidate()
    $script:form.Invalidate($true)
    try { Update-LivelyStatus } catch { }
    Show-Quip
}

# ---------------------------------------------------------------- pack export / import
function Export-SelectedPack {
    $sel = [string]$script:lbPacks.SelectedItem
    if (-not $sel) { Set-Status "Select a pack to export first."; return }
    $dir = Join-Path $Root $sel
    if (-not (Test-Path -LiteralPath $dir)) { return }
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "Wallpaper pack (zip)|*.zip"
    $dlg.FileName = $sel + ".zip"
    $dlg.Title = "Export pack '$sel'"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    try {
        $script:form.Cursor = 'WaitCursor'
        Set-Status "Zipping '$sel'..."
        [System.Windows.Forms.Application]::DoEvents()
        if (Test-Path -LiteralPath $dlg.FileName) { Remove-Item -LiteralPath $dlg.FileName -Force }
        Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $dlg.FileName -CompressionLevel Optimal
        Set-Status "Exported '$sel' to $($dlg.FileName)."
    } catch { Set-Status "Couldn't export: $($_.Exception.Message)" } finally { $script:form.Cursor = 'Default' }
}

function Import-PackZip {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Wallpaper pack (zip)|*.zip"
    $dlg.Title = "Import a pack"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $name = [IO.Path]::GetFileNameWithoutExtension($dlg.FileName)
    $dir = $null
    try {
        $script:form.Cursor = 'WaitCursor'
        $dir = Get-NewPackDir $name
        if (-not $dir) { Set-Status "That name can't be used."; return }
        Expand-Archive -LiteralPath $dlg.FileName -DestinationPath $dir -Force
        # a zip made by zipping the folder itself has one folder inside - lift it out
        $kids = @(Get-ChildItem -LiteralPath $dir -Force)
        if ($kids.Count -eq 1 -and $kids[0].PSIsContainer -and $kids[0].Name -notmatch '^_') {
            $inner = $kids[0].FullName
            foreach ($i in @(Get-ChildItem -LiteralPath $inner -Force)) { Move-Item -LiteralPath $i.FullName -Destination $dir -Force }
            Remove-Item -LiteralPath $inner -Recurse -Force -ErrorAction SilentlyContinue
        }
        $script:thumbCache = @{}
        Update-PackList (Split-Path $dir -Leaf)
        Set-Status "Imported '$(Split-Path $dir -Leaf)'. If your screens differ from the original, open it in the Builder and save it again to refit."
    } catch {
        Set-Status "Couldn't import: $($_.Exception.Message)"
        if ($dir -and (Test-Path -LiteralPath $dir)) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
    } finally { $script:form.Cursor = 'Default' }
}

# ---------------------------------------------------------------- start with Windows
function Get-StartupLinkPath { return (Join-Path ([Environment]::GetFolderPath('Startup')) "Ekk0h.lnk") }
function Get-OldStartupLinkPath { return (Join-Path ([Environment]::GetFolderPath('Startup')) "Wallpaper Control Center.lnk") }
function Test-StartWithWindows { return ((Test-Path -LiteralPath (Get-StartupLinkPath)) -or (Test-Path -LiteralPath (Get-OldStartupLinkPath))) }
function Set-StartWithWindows([bool]$on) {
    $lnkPath = Get-StartupLinkPath
    Remove-Item -LiteralPath (Get-OldStartupLinkPath) -Force -ErrorAction SilentlyContinue
    if (-not $on) { Remove-Item -LiteralPath $lnkPath -Force -ErrorAction SilentlyContinue; return }
    $vbsPath = Join-Path $PSScriptRoot "LaunchTray.vbs"
    $vbs = @(
        'Set sh = CreateObject("WScript.Shell")',
        'Set fso = CreateObject("Scripting.FileSystemObject")',
        'dir = fso.GetParentFolderName(WScript.ScriptFullName)',
        'sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & dir & "\Ekk0h.ps1"" -Tray", 0, False'
    )
    if (-not (Get-AppExe)) { Set-Content -LiteralPath $vbsPath -Value $vbs -Encoding ASCII }
    $shell = New-Object -ComObject WScript.Shell
    $lnk = $shell.CreateShortcut($lnkPath)
    $appExe = Get-AppExe
    if ($appExe) { $lnk.TargetPath = $appExe; $lnk.Arguments = "--tray" }
    else { $lnk.TargetPath = (Join-Path $env:WINDIR "System32\wscript.exe"); $lnk.Arguments = "`"$vbsPath`"" }
    $lnk.WorkingDirectory = $PSScriptRoot
    $ico = Join-Path $PSScriptRoot "ControlCenter.ico"
    if ($appExe) { $lnk.IconLocation = "$appExe,0" }
    elseif (Test-Path -LiteralPath $ico) { $lnk.IconLocation = "$ico,0" }
    $lnk.Save()
}

# ---------------------------------------------------------------- schedule (packs by time of day)
$script:schedNames = @('Morning', 'Day', 'Evening', 'Night')
$script:schedLast = -1

function Get-SchedBlock {
    $s = Get-Settings
    $hours = @()
    for ($i = 1; $i -le 4; $i++) {
        $h = 0
        if (-not [int]::TryParse([string]$s["SchedH$i"], [ref]$h)) { $h = @(6, 10, 17, 22)[$i - 1] }
        $hours += [int][math]::Max(0, [math]::Min(23, $h))
    }
    $now = (Get-Date).Hour
    $best = -1; $bestH = -1
    for ($i = 0; $i -lt 4; $i++) { if ($hours[$i] -le $now -and $hours[$i] -gt $bestH) { $best = $i; $bestH = $hours[$i] } }
    if ($best -lt 0) { $mx = -1; for ($i = 0; $i -lt 4; $i++) { if ($hours[$i] -gt $mx) { $mx = $hours[$i]; $best = $i } } }
    return $best
}

function Invoke-Schedule([bool]$force = $false) {
    $s = Get-Settings
    if ($s.SchedOn -ne '1') { return }
    $b = Get-SchedBlock
    if ($b -lt 0) { return }
    if (-not $force -and $b -eq $script:schedLast) { return }
    $script:schedLast = $b
    $pk = [string]$s["SchedP$($b + 1)"]
    if (-not $pk -or $pk -eq '(Keep Current)') { return }
    $dir = Join-Path $Root $pk
    if (-not (Test-Path -LiteralPath $dir)) { return }
    Set-Status "Schedule: $($script:schedNames[$b]) - applying '$pk'..."
    [void](Set-Pack $dir)
}

function Update-SchedStatus {
    if (-not $script:lblSchedNow) { return }
    $s = Get-Settings
    if ($s.SchedOn -ne '1') { $script:lblSchedNow.Text = "Schedule is off."; return }
    $b = Get-SchedBlock
    $pk = [string]$s["SchedP$($b + 1)"]
    if (-not $pk) { $pk = '(Keep Current)' }
    $script:lblSchedNow.Text = "Right now: $($script:schedNames[$b]) block - $pk"
}

# ================================================================ PACKS THUMBNAIL GRID
# Each pack becomes a card: slanted strips with a slice of every screen's picture, or just the
# center screen when the pack is one wide panorama. Favorites and tags live in packmeta.json,
# thumbnails are cached in the Thumbs folder.
$script:gridOk = $false
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @"
using System.Windows.Forms;
public class GridCanvas : Panel {
    public GridCanvas() {
        SetStyle(ControlStyles.Selectable | ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
        TabStop = true;
    }
}
"@
    $script:gridOk = $true
} catch {
    try { $null = [GridCanvas]; $script:gridOk = $true } catch { $script:gridOk = $false }
}

$script:GridDir = Join-Path $PSScriptRoot "Thumbs"
$script:MetaPath = Join-Path $PSScriptRoot "packmeta.json"
$script:gridThumbs = @{}
$script:gridQueue = New-Object System.Collections.ArrayList
$script:gridItems = @()
$script:packMeta = $null
$script:gridHitName = $null
$script:gridScroll = 0
$script:gridDrag = $null
$script:GT_W = 196
$script:GT_H = 110
$script:GC_CAP = 46
$script:GC_GX = 12
$script:GC_GY = 14
$script:GC_MX = 10
$script:GC_COLS = 3

function Write-GridLog([string]$msg) {
    try { Add-Content -LiteralPath (Join-Path $PSScriptRoot "grid-log.txt") -Value ("{0}  {1}" -f (Get-Date -Format 's'), $msg) } catch { }
}

# ---------------------------------------------------------------- favorites + tags
function Get-PackMeta {
    if ($null -ne $script:packMeta) { return $script:packMeta }
    $m = @{}
    try {
        if (Test-Path -LiteralPath $script:MetaPath) {
            $j = Get-Content -LiteralPath $script:MetaPath -Raw | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) {
                $tg = @()
                foreach ($t in @($p.Value.tags)) { if ($t) { $tg += [string]$t } }
                $e = @{ fav = [bool]$p.Value.fav; tags = $tg; thumb = [string]$p.Value.thumb }
                if ($p.Value.saver) {
                    $sv = @{}
                    foreach ($q in $p.Value.saver.PSObject.Properties) { $sv[$q.Name] = $q.Value }
                    $e.saver = $sv
                }
                $m[$p.Name] = $e
            }
        }
    } catch { }
    $script:packMeta = $m
    return $m
}
function Save-PackMeta {
    try { ($script:packMeta | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $script:MetaPath -Encoding UTF8 } catch { }
}
function Get-PackMetaFor([string]$name) {
    $m = Get-PackMeta
    if ($m.ContainsKey($name)) { return $m[$name] }
    return @{ fav = $false; tags = @(); thumb = '' }
}
# per-pack screen saver options (used when the saver style is Match Packs)
function Get-PackSaver([string]$name) {
    $r = @{ include = $true; seconds = 0; motion = 'auto'; type = 'pack'; video = ''; theme = '' }
    $e = Get-PackMetaFor $name
    if ($e.ContainsKey('saver') -and $e.saver) {
        $sv = $e.saver
        if ($sv.ContainsKey('include')) { $r.include = [bool]$sv.include }
        if ($sv.ContainsKey('seconds')) { $r.seconds = [int]$sv.seconds }
        if ($sv.ContainsKey('motion') -and $sv.motion) { $r.motion = [string]$sv.motion }
        if ($sv.ContainsKey('type') -and $sv.type) { $r.type = [string]$sv.type }
        if ($sv.ContainsKey('video') -and $sv.video) { $r.video = [string]$sv.video }
        if ($sv.ContainsKey('theme') -and $sv.theme) { $r.theme = [string]$sv.theme }
    }
    return $r
}
function Set-PackSaver([string]$name, $opt) {
    $m = Get-PackMeta
    $e = Get-PackMetaFor $name
    $e.saver = @{ include = [bool]$opt.include; seconds = [int]$opt.seconds; motion = [string]$opt.motion; type = [string]$opt.type; video = [string]$opt.video; theme = [string]$opt.theme }
    $m[$name] = $e
    Save-PackMeta
}
function Set-PackFav([string]$name, [bool]$fav) {
    $m = Get-PackMeta
    $e = Get-PackMetaFor $name
    $e.fav = $fav
    $m[$name] = $e
    Save-PackMeta
}
function Set-PackTags([string]$name, [string[]]$tags) {
    $m = Get-PackMeta
    $e = Get-PackMetaFor $name
    $clean = @()
    foreach ($t in $tags) {
        $x = ([string]$t).Trim().TrimStart('#').ToLower()
        if ($x -and ($clean -notcontains $x)) { $clean += $x }
    }
    $e.tags = $clean
    $m[$name] = $e
    Save-PackMeta
}
function Set-PackThumbMode([string]$name, [string]$mode) {
    if (-not $name) { return }
    $m = Get-PackMeta
    $e = Get-PackMetaFor $name
    $e.thumb = $mode
    $m[$name] = $e
    Save-PackMeta
    Request-GridThumbs
    if ($script:gridCanvas) { $script:gridCanvas.Invalidate() }
}
function Move-PackMeta([string]$old, [string]$new) {
    $m = Get-PackMeta
    if ($m.ContainsKey($old)) { $m[$new] = $m[$old]; $m.Remove($old); Save-PackMeta }
}

# ---------------------------------------------------------------- thumbnails
function Get-PackSig([string]$dir) {
    $files = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match $ImageExt -or $_.Name -eq 'pack.json' })
    $t = [long]0
    foreach ($f in $files) { $t = ($t + $f.LastWriteTimeUtc.Ticks + $f.Length) % [long]9007199254740881 }
    $tm = ([string](Get-PackMetaFor (Split-Path $dir -Leaf)).thumb) -replace '[^a-z0-9]', ''
    if ($tm) { return ("v3_{0}_{1}_{2}" -f $files.Count, $t, $tm) }
    return ("v3_{0}_{1}" -f $files.Count, $t)
}

function Add-CoverDraw($gr, $img, [single]$dx, [single]$dy, [single]$dw, [single]$dh) {
    $sw = [single]$img.Width; $sh = [single]$img.Height
    $dr = $dw / $dh; $sr = $sw / $sh
    if ($sr -gt $dr) {
        $cw = $sh * $dr
        $src = New-Object System.Drawing.RectangleF([single](($sw - $cw) / 2), [single]0, [single]$cw, [single]$sh)
    } else {
        $ch = $sw / $dr
        $src = New-Object System.Drawing.RectangleF([single]0, [single](($sh - $ch) / 2), [single]$sw, [single]$ch)
    }
    $dest = New-Object System.Drawing.RectangleF($dx, $dy, $dw, $dh)
    $gr.DrawImage($img, $dest, $src, [System.Drawing.GraphicsUnit]::Pixel)
}

function New-PackThumbBmp([string]$dir, [int]$W = 0, [int]$H = 0) {
    if ($W -gt 0 -and $H -gt 0) { $TW = $W; $TH = $H } else { $TW = $script:GT_W * 2; $TH = $script:GT_H * 2 }
    $imgs = @(Get-PackImages $dir)
    $rec = Get-Recipe $dir
    $video = $false; $pano = $false
    if ($rec) {
        foreach ($g in @($rec)) {
            if ($g.type -eq 'video') { $video = $true }
            elseif (@($g.screens).Count -ge 2 -and @($g.screens).Count -ge $imgs.Count -and $imgs.Count -ge 2) { $pano = $true }
        }
    } elseif ($imgs.Count -ge 2) {
        $pano = Test-PanoramaPack $imgs $imgs.Count
    }
    $bmp = New-Object System.Drawing.Bitmap($TW, $TH)
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gr.SmoothingMode = 'AntiAlias'
        $gr.InterpolationMode = 'HighQualityBilinear'
        $gr.Clear([System.Drawing.Color]::FromArgb(255, 26, 26, 32))
        $n = [math]::Min($imgs.Count, 6)
        if ($n -eq 0) { return @{ Bmp = $bmp; Pano = $false; Video = $video; Count = 0 } }
        $tm = [string](Get-PackMetaFor (Split-Path $dir -Leaf)).thumb
        $tmode = 'auto'
        if ($tm -match '^screen(\d+)$' -and [int]$Matches[1] -le $imgs.Count) { $tmode = 'screen'; $si = [int]$Matches[1] - 1 }
        elseif ($tm -eq 'pano' -and (Get-PackPano $dir)) { $tmode = 'pano' }
        elseif ($tm -eq 'compiled' -and $n -ge 2) { $tmode = 'compiled' }
        if ($tmode -eq 'screen') {
            try {
                $ld = Read-ImageFromFile $imgs[$si].FullName
                try { Add-CoverDraw $gr $ld.Image 0 0 $TW $TH } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
            } catch { Write-GridLog ("image failed {0}: {1}" -f $imgs[$si].FullName, $_.Exception.Message) }
        } elseif ($tmode -eq 'pano') {
            try {
                $pp = Get-PackPano $dir
                $ld = Read-ImageFromFile $pp.File
                try {
                    $k = [math]::Min($TW / [double]$ld.Image.Width, $TH / [double]$ld.Image.Height)
                    $dw = [single]($ld.Image.Width * $k); $dh = [single]($ld.Image.Height * $k)
                    $gr.DrawImage($ld.Image, [single](($TW - $dw) / 2), [single](($TH - $dh) / 2), $dw, $dh)
                } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
            } catch { Write-GridLog ("panorama failed: " + $_.Exception.Message) }
        } elseif ($tmode -ne 'compiled' -and ($pano -or $n -eq 1)) {
            if ($pano) { $mid = $imgs[[int][math]::Floor(($imgs.Count - 1) / 2)] } else { $mid = $imgs[0] }
            try {
                $ld = Read-ImageFromFile $mid.FullName
                try { Add-CoverDraw $gr $ld.Image 0 0 $TW $TH } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
            } catch { Write-GridLog ("image failed {0}: {1}" -f $mid.FullName, $_.Exception.Message) }
        } else {
            $slant = $TH * 0.22
            $gap = 10.0
            for ($i = 0; $i -lt $n; $i++) {
                if ($i -eq 0) { $lt = 0.0; $lb = 0.0 }
                else { $xb = $i * $TW / $n; $lt = $xb + $slant / 2 + $gap / 2; $lb = $xb - $slant / 2 + $gap / 2 }
                if ($i -eq $n - 1) { $rt = [double]$TW; $rb = [double]$TW }
                else { $xb = ($i + 1) * $TW / $n; $rt = $xb + $slant / 2 - $gap / 2; $rb = $xb - $slant / 2 - $gap / 2 }
                $pts = [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF([single]$lt, 0)),
                    (New-Object System.Drawing.PointF([single]$rt, 0)),
                    (New-Object System.Drawing.PointF([single]$rb, [single]$TH)),
                    (New-Object System.Drawing.PointF([single]$lb, [single]$TH)))
                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                $path.AddPolygon($pts)
                $bx = [math]::Min($lt, $lb); $bw = [math]::Max($rt, $rb) - $bx
                try {
                    $ld = Read-ImageFromFile $imgs[$i].FullName
                    try {
                        $gr.SetClip($path)
                        Add-CoverDraw $gr $ld.Image ([single]$bx) 0 ([single]$bw) ([single]$TH)
                        $gr.ResetClip()
                    } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
                } catch { $gr.ResetClip(); Write-GridLog ("image failed {0}: {1}" -f $imgs[$i].FullName, $_.Exception.Message) }
                $path.Dispose()
            }
        }
    } finally { $gr.Dispose() }
    return @{ Bmp = $bmp; Pano = $pano; Video = $video; Count = $imgs.Count }
}

# makes sure the in-memory thumbnail for a pack is current; returns $true when it changed
# a small dark label sized to its text; returns its width
function Add-GridBadge($g, [string]$text, [single]$x, [single]$y, $back, $fore) {
    $w = [single]([math]::Ceiling($g.MeasureString($text, $script:gFBadge).Width) + 2)
    $g.FillRectangle($back, $x, $y, $w, [single]15)
    $g.DrawString($text, $script:gFBadge, $fore, [single]($x + 1), $y)
    return $w
}

function Update-GridThumb([string]$name) {
    $dir = Join-Path $Root $name
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    $sig = Get-PackSig $dir
    $cur = $script:gridThumbs[$name]
    if ($cur -and $cur.Sig -eq $sig) { return $false }
    if (-not (Test-Path -LiteralPath $script:GridDir)) { [void](New-Item -ItemType Directory -Path $script:GridDir -Force) }
    $prefix = "{0}.{1}.F" -f $name, $sig
    $hit = $null
    foreach ($f in @(Get-ChildItem -LiteralPath $script:GridDir -File -ErrorAction SilentlyContinue)) {
        if ($f.Name.StartsWith($prefix) -and $f.Name -match '\.F([01])([01])_(\d+)\.png$') { $hit = @{ File = $f; P = ($Matches[1] -eq '1'); V = ($Matches[2] -eq '1'); N = [int]$Matches[3] }; break }
    }
    $bmp = $null; $pano = $false; $video = $false; $cnt = 0
    if ($hit) {
        try {
            $ld = Read-ImageFromFile $hit.File.FullName
            $bmp = New-Object System.Drawing.Bitmap($ld.Image)
            $ld.Image.Dispose(); $ld.Stream.Dispose()
            $pano = $hit.P; $video = $hit.V; $cnt = $hit.N
        } catch { $bmp = $null }
    }
    if (-not $bmp) {
        $r = New-PackThumbBmp $dir
        $bmp = $r.Bmp; $pano = $r.Pano; $video = $r.Video; $cnt = $r.Count
        try {
            foreach ($f in @(Get-ChildItem -LiteralPath $script:GridDir -File -ErrorAction SilentlyContinue)) {
                if ($f.Name.StartsWith("$name.") -and $f.Name -match '\.v\d+_.*\.F[01][01]_\d+\.png$') { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
            }
            $bmp.Save((Join-Path $script:GridDir ("{0}{1}{2}_{3}.png" -f $prefix, [int]$pano, [int]$video, $cnt)), [System.Drawing.Imaging.ImageFormat]::Png)
        } catch { }
    }
    if ($cur -and $cur.Bmp) { $cur.Bmp.Dispose() }
    $script:gridThumbs[$name] = @{ Sig = $sig; Bmp = $bmp; Pano = $pano; Video = $video; Count = $cnt }
    return $true
}

function Request-GridThumbs {
    $script:gridQueue.Clear()
    foreach ($n in @($script:gridItems)) { [void]$script:gridQueue.Add([string]$n) }
    foreach ($n in $script:lbPacks.Items) { if ($script:gridQueue -notcontains [string]$n) { [void]$script:gridQueue.Add([string]$n) } }
    foreach ($k in @($script:gridThumbs.Keys)) {
        if (-not $script:lbPacks.Items.Contains($k)) {
            $e = $script:gridThumbs[$k]; if ($e.Bmp) { $e.Bmp.Dispose() }
            $script:gridThumbs.Remove($k)
        }
    }
    if ($script:gridTimer) { $script:gridTimer.Start() }
}

# ---------------------------------------------------------------- list the cards that pass the filters
function Get-GridItems {
    $favOnly = ($script:chkGridFav -and $script:chkGridFav.Checked)
    $tag = ''
    if ($script:cmbGridTag -and $script:cmbGridTag.SelectedIndex -gt 0) { $tag = [string]$script:cmbGridTag.SelectedItem }
    $names = @()
    foreach ($n in $script:lbPacks.Items) {
        $name = [string]$n
        $e = Get-PackMetaFor $name
        if ($favOnly -and -not $e.fav) { continue }
        if ($tag -and (@($e.tags) -notcontains $tag)) { continue }
        $names += $name
    }
    $sort = ''
    if ($script:cmbGridSort) { $sort = [string]$script:cmbGridSort.SelectedItem }
    if ($sort -eq 'Newest') {
        $names = @($names | Sort-Object -Property @{ Expression = { (Get-Item -LiteralPath (Join-Path $Root $_)).LastWriteTime }; Descending = $true })
    } elseif ($sort -eq 'Favorites First') {
        $names = @($names | Sort-Object -Property @{ Expression = { -not (Get-PackMetaFor $_).fav } }, @{ Expression = { $_ } })
    }
    return $names
}

function Update-GridTags {
    if (-not $script:cmbGridTag) { return }
    $keep = ''
    if ($script:cmbGridTag.SelectedIndex -gt 0) { $keep = [string]$script:cmbGridTag.SelectedItem }
    $all = @{}
    foreach ($n in $script:lbPacks.Items) { foreach ($t in @((Get-PackMetaFor ([string]$n)).tags)) { $all[$t] = 1 } }
    $script:gridBusy = $true
    $script:cmbGridTag.Items.Clear()
    [void]$script:cmbGridTag.Items.Add("All Tags")
    foreach ($t in ($all.Keys | Sort-Object)) { [void]$script:cmbGridTag.Items.Add([string]$t) }
    if ($keep -and $script:cmbGridTag.Items.Contains($keep)) { $script:cmbGridTag.SelectedItem = $keep } else { $script:cmbGridTag.SelectedIndex = 0 }
    $script:gridBusy = $false
}

# ---------------------------------------------------------------- scrolling (own themed scrollbar)
function Get-GridMetrics {
    $ch = $script:GT_H + $script:GC_CAP
    $rows = [int][math]::Ceiling(@($script:gridItems).Count / [double]$script:GC_COLS)
    $content = 6 + $rows * ($ch + $script:GC_GY)
    $view = $script:gridCanvas.ClientSize.Height
    return @{ Content = $content; View = $view; Max = [math]::Max(0, $content - $view) }
}

function Set-GridScroll([double]$v) {
    if (-not $script:gridCanvas) { return }
    $m = Get-GridMetrics
    $v = [math]::Max(0, [math]::Min($m.Max, $v))
    if ([int]$v -ne [int]$script:gridScroll) { $script:gridScroll = [int]$v; $script:gridCanvas.Invalidate() }
}

# track and thumb rectangles (null when everything fits)
function Get-GridBar {
    $m = Get-GridMetrics
    if ($m.Max -le 0) { return $null }
    $w = $script:gridCanvas.ClientSize.Width
    $trackX = $w - 16; $trackY = 4; $trackH = $script:gridCanvas.ClientSize.Height - 8
    $thumbH = [math]::Max(34, [math]::Round($trackH * $m.View / [double]$m.Content))
    $thumbY = $trackY + ($trackH - $thumbH) * ($script:gridScroll / [double]$m.Max)
    return @{ TX = $trackX; TY = $trackY; TW = 10; TH = $trackH; BY = [single]$thumbH; BYpos = [single]$thumbY; Max = $m.Max }
}

function Refresh-Grid {
    if (-not $script:gridCanvas) { return }
    $script:gridItems = @(Get-GridItems)
    $m = Get-GridMetrics
    if ($script:gridScroll -gt $m.Max) { $script:gridScroll = [int]$m.Max }
    if ($script:lblCount) {
        $n = $script:lbPacks.Items.Count
        $shown = @($script:gridItems).Count
        if ($shown -ne $n) { $script:lblCount.Text = "$shown of $n packs" }
        elseif ($n -eq 1) { $script:lblCount.Text = "1 pack" }
        else { $script:lblCount.Text = "$n packs" }
    }
    $script:gridCanvas.Invalidate()
}

function Get-GridHit($pt) {
    $cy = $pt.Y + $script:gridScroll
    $cw = $script:GT_W; $ch = $script:GT_H + $script:GC_CAP
    $col = [int][math]::Floor(($pt.X - $script:GC_MX) / ($cw + $script:GC_GX))
    $row = [int][math]::Floor(($cy - 6) / ($ch + $script:GC_GY))
    if ($col -lt 0 -or $col -ge $script:GC_COLS -or $row -lt 0) { return $null }
    $x = $script:GC_MX + $col * ($cw + $script:GC_GX)
    $y = 6 + $row * ($ch + $script:GC_GY)
    if ($pt.X -gt $x + $cw -or $cy -gt $y + $ch) { return $null }
    $ix = $row * $script:GC_COLS + $col
    if ($ix -ge @($script:gridItems).Count) { return $null }
    $star = ($pt.X -ge $x + $cw - 34 -and $cy -le $y + 34)
    return @{ Name = [string]$script:gridItems[$ix]; Star = $star }
}

function Show-SelectedInGrid {
    if (-not $script:gridCanvas) { return }
    $sel = [string]$script:lbPacks.SelectedItem
    $ix = [array]::IndexOf($script:gridItems, $sel)
    if ($ix -lt 0) { return }
    $ch = $script:GT_H + $script:GC_CAP
    $row = [int][math]::Floor($ix / $script:GC_COLS)
    $y = 6 + $row * ($ch + $script:GC_GY)
    $view = $script:gridCanvas.ClientSize.Height
    if ($y -lt $script:gridScroll) { Set-GridScroll ($y - 6) }
    elseif ($y + $ch -gt $script:gridScroll + $view) { Set-GridScroll ($y + $ch + 6 - $view) }
}

# fills the "Edit thumbnail" submenu for the selected pack: each screen, Compiled, Panorama (panoramas only), Automatic
function Update-ThumbMenu {
    $name = [string]$script:lbPacks.SelectedItem
    if (-not $name -or -not $script:miThumb) { return }
    $imgs = @(Get-PackImages (Join-Path $Root $name))
    $cur = [string](Get-PackMetaFor $name).thumb
    $t = $script:gridThumbs[$name]
    $isPano = [bool]($t -and $t.Pano)
    $script:miThumb.DropDownItems.Clear()
    try {
        $dd = $script:miThumb.DropDown
        $dd.BackColor = $script:cMenuBack; $dd.ForeColor = $script:cText
        $dd.Font = New-Object System.Drawing.Font("Segoe UI", 10)
        if ($dd -is [System.Windows.Forms.ToolStripDropDownMenu]) { $dd.ShowImageMargin = $false; $dd.ShowCheckMargin = $true }
    } catch { }
    $opts = @()
    for ($i = 1; $i -le [math]::Min($imgs.Count, 6); $i++) { $opts += , @{ Text = "Screen $i"; Mode = "screen$i" } }
    if ($imgs.Count -ge 2) { $opts += , @{ Text = "Compiled"; Mode = "compiled" } }
    if ($isPano) { $opts += , @{ Text = "Panorama"; Mode = "pano" } }
    $opts += , @{ Text = "Automatic"; Mode = "" }
    foreach ($o in $opts) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($o.Text)
        $mi.Tag = [string]$o.Mode
        $mi.ForeColor = $script:cText; $mi.BackColor = $script:cMenuBack
        $mi.Checked = ($cur -eq [string]$o.Mode)
        $mi.Add_Click({ param($s, $e) Set-PackThumbMode ([string]$script:lbPacks.SelectedItem) ([string]$s.Tag) })
        [void]$script:miThumb.DropDownItems.Add($mi)
    }
}

function Edit-PackTags {
    $name = [string]$script:lbPacks.SelectedItem
    if (-not $name) { return }
    $cur = (@((Get-PackMetaFor $name).tags) -join ', ')
    $txt = [Microsoft.VisualBasic.Interaction]::InputBox("Tags for '$name', separated by commas (for example: city, night, warm):", "Pack tags", $cur)
    if ($null -eq $txt) { return }
    Set-PackTags $name @($txt -split ',')
    Update-GridTags
    Refresh-Grid
    Set-Status "Tags saved for '$name'."
}
function Switch-PackFav {
    $name = [string]$script:lbPacks.SelectedItem
    if (-not $name) { return }
    Set-PackFav $name (-not (Get-PackMetaFor $name).fav)
    Refresh-Grid
}

# ---------------------------------------------------------------- build the controls (called from the main UI file)
function New-PackGrid($parent) {
    $pnl = New-Object System.Windows.Forms.Panel
    $pnl.Location = New-Object System.Drawing.Point(0, 0)
    $pnl.Size = New-Object System.Drawing.Size(656, 492)
    $pnl.BackColor = $script:cBg
    $script:pnlGrid = $pnl
    $parent.Controls.Add($pnl)

    $script:chkGridFav = New-NeonCheck "Favorites Only" 24 4 150 28
    $script:cmbGridTag = New-StyledCombo 182 4 130
    [void]$script:cmbGridTag.Items.Add("All Tags"); $script:cmbGridTag.SelectedIndex = 0
    $script:cmbGridSort = New-StyledCombo 320 4 140
    foreach ($o in @("A-Z", "Newest", "Favorites First")) { [void]$script:cmbGridSort.Items.Add($o) }
    $script:cmbGridSort.SelectedIndex = 0
    $script:lblCount = New-Label "" 470 8 130 22 $true 9
    $hb = New-HelpButton 626 5 "Pack grid" "Each card shows a slice of every screen's picture, cut into slanted strips. If the pack is one wide panorama, the card shows the center screen's picture instead.`n`nClick a card to select it, double-click to apply it.`nClick the star to mark a favorite.`nRight-click for tags, Edit thumbnail (pick which screen, the compiled strips or the panorama to show on the card), setting it as your Windows lock screen, rename, open folder and delete.`nArrow keys move, Enter applies, Delete removes.`n`nUse 'Favorites only', the tag list and the sort list to narrow things down. Favorites and tags are kept in packmeta.json; pictures are cached in the Thumbs folder (safe to delete)."
    foreach ($c in @($script:chkGridFav, $script:cmbGridTag, $script:cmbGridSort, $script:lblCount, $hb)) { $pnl.Controls.Add($c) }

    if ($script:gridOk) { $cv = New-Object GridCanvas } else { $cv = New-Object System.Windows.Forms.Panel }
    $cv.Location = New-Object System.Drawing.Point(0, 38)
    $cv.Size = New-Object System.Drawing.Size(656, 418)
    $cv.AutoScroll = $false
    $cv.BackColor = $script:cBg
    $script:gridCanvas = $cv
    $pnl.Controls.Add($cv)

    $script:lblGridHint = New-Label "Click = select  |  Double-click = apply  |  Star = favorite  |  Right-click = more" 24 464 620 22 $true 9
    $pnl.Controls.Add($script:lblGridHint)

    $script:gridTimer = New-Object System.Windows.Forms.Timer
    $script:gridTimer.Interval = 15
    $script:gridTimer.Add_Tick({
        try {
            if ($script:gridQueue.Count -eq 0) { $script:gridTimer.Stop(); return }
            $swatch = [System.Diagnostics.Stopwatch]::StartNew()
            $changed = $false
            while ($script:gridQueue.Count -gt 0 -and $swatch.ElapsedMilliseconds -lt 90) {
                $n = [string]$script:gridQueue[0]
                $script:gridQueue.RemoveAt(0)
                try {
                    if (Update-GridThumb $n) { $changed = $true; if ($swatch.ElapsedMilliseconds -gt 40) { break } }
                } catch {
                    Write-GridLog ("thumb failed for '{0}': {1} at {2}" -f $n, $_.Exception.Message, $_.InvocationInfo.PositionMessage)
                    $script:gridThumbs[$n] = @{ Sig = 'fail'; Bmp = $null; Pano = $false; Video = $false; Count = 0; Failed = $true }
                    $changed = $true
                }
            }
            if ($changed) { $script:gridCanvas.Invalidate() }
        } catch { Write-GridLog ("timer: " + $_.Exception.Message); $script:gridTimer.Stop() }
    })

    $script:gFName = Get-RetroFont 9 'Bold'
    $script:gFSmall = New-Object System.Drawing.Font("Segoe UI", 8)
    $script:gFBadge = New-Object System.Drawing.Font("Segoe UI", 7, [System.Drawing.FontStyle]::Bold)

    $cv.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'
        $g.InterpolationMode = 'HighQualityBicubic'
        $off = -$script:gridScroll
        $g.Clear($script:cBg)
        $cw = $script:GT_W; $th = $script:GT_H; $ch = $th + $script:GC_CAP
        $sel = [string]$script:lbPacks.SelectedItem
        $items = @($script:gridItems)
        if ($items.Count -eq 0) {
            $br = New-Object System.Drawing.SolidBrush($script:cDim)
            $g.DrawString("No packs to show here.", $script:gFSmall, $br, 28, 14)
            $br.Dispose()
            return
        }
        $g.TranslateTransform(0, $off)
        $pPanel = New-Object System.Drawing.SolidBrush($script:cPanel)
        $pPanel2 = New-Object System.Drawing.SolidBrush($script:cPanel2)
        $bText = New-Object System.Drawing.SolidBrush($script:cText)
        $bSel = New-Object System.Drawing.SolidBrush($script:cSelText)
        $bDim = New-Object System.Drawing.SolidBrush($script:cDim)
        $bShade = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170, 0, 0, 0))
        $bWhite = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $bStar = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 208, 64))
        $bBadge = New-Object System.Drawing.SolidBrush($script:cAccent)
        $penSel = New-Object System.Drawing.Pen($script:cAccent, 3)
        $penEdge = New-Object System.Drawing.Pen($script:cPurple, 1)
        $penStarEdge = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 190, 130, 0), 1)
        $penStarOff = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255, 235, 235, 235), 1.5)
        for ($i = 0; $i -lt $items.Count; $i++) {
            $col = $i % $script:GC_COLS; $row = [int][math]::Floor($i / $script:GC_COLS)
            $x = $script:GC_MX + $col * ($cw + $script:GC_GX)
            $y = 6 + $row * ($ch + $script:GC_GY)
            if ($y + $off + $ch -lt 0 -or $y + $off -gt $s.ClientSize.Height) { continue }
            $name = [string]$items[$i]
            $isSel = ($name -eq $sel)
            $g.FillRectangle($pPanel, $x, $y, $cw, $ch)
            $t = $script:gridThumbs[$name]
            if ($t -and $t.Bmp) {
                $g.DrawImage($t.Bmp, $x, $y, $cw, $th)
            } else {
                $g.FillRectangle($pPanel2, $x, $y, $cw, $th)
                if ($t -and $t.Failed) { $g.DrawString("no preview", $script:gFSmall, $bDim, $x + $cw / 2 - 28, $y + $th / 2 - 8) }
                else { $g.DrawString("...", $script:gFName, $bDim, $x + $cw / 2 - 8, $y + $th / 2 - 8) }
            }
            $meta = Get-PackMetaFor $name
            # star: a drawn 5-point star centered in a dark box
            $bxs = $x + $cw - 32; $bys = $y + 6
            $g.FillRectangle($bShade, $bxs, $bys, 26, 26)
            $scx = $bxs + 13.0; $scy = $bys + 13.5
            $sp = New-Object 'System.Drawing.PointF[]' 10
            for ($k = 0; $k -lt 10; $k++) {
                $ang = [math]::PI * ($k * 36 - 90) / 180.0
                if ($k % 2 -eq 0) { $rr = 9.5 } else { $rr = 4.2 }
                $sp[$k] = New-Object System.Drawing.PointF([single]($scx + $rr * [math]::Cos($ang)), [single]($scy + $rr * [math]::Sin($ang)))
            }
            if ($meta.fav) { $g.FillPolygon($bStar, $sp); $g.DrawPolygon($penStarEdge, $sp) }
            else { $g.DrawPolygon($penStarOff, $sp) }
            # badges
            $bx = $x + 6
            if ($t -and $t.Video) { $bx += (Add-GridBadge $g "VIDEO" $bx ($y + $th - 20) $bShade $bWhite) + 4 }
            if ($t -and $t.Pano) { $bx += (Add-GridBadge $g "PANORAMA" $bx ($y + $th - 20) $bShade $bWhite) + 4 }
            if ($script:currentPack -eq $name) { [void](Add-GridBadge $g "ON SCREEN" ($x + 6) ($y + 6) $bBadge $bWhite) }
            # caption
            $nb = $bText; if ($isSel) { $nb = $bSel }
            $rf = New-Object System.Drawing.RectangleF(($x + 8), ($y + $th + 4), ($cw - 16), 20)
            $sf = New-Object System.Drawing.StringFormat
            $sf.Trimming = 'EllipsisCharacter'; $sf.FormatFlags = 'NoWrap'
            $g.DrawString($name, $script:gFName, $nb, $rf, $sf)
            $sub = ''
            if ($t) { if ($t.Count -eq 1) { $sub = "1 image" } else { $sub = "$($t.Count) images" } }
            if (@($meta.tags).Count -gt 0) { $sub = (@($meta.tags | ForEach-Object { '#' + $_ }) -join ' ') + "   " + $sub }
            $rf2 = New-Object System.Drawing.RectangleF(($x + 8), ($y + $th + 25), ($cw - 16), 18)
            $g.DrawString($sub, $script:gFSmall, $bDim, $rf2, $sf)
            $sf.Dispose()
            if ($isSel) { $g.DrawRectangle($penSel, $x + 1, $y + 1, $cw - 2, $ch - 2) } else { $g.DrawRectangle($penEdge, $x, $y, $cw - 1, $ch - 1) }
        }
        foreach ($o in @($pPanel, $pPanel2, $bText, $bSel, $bDim, $bShade, $bWhite, $bStar, $bBadge, $penSel, $penEdge, $penStarEdge, $penStarOff)) { $o.Dispose() }

        # themed scrollbar
        $g.ResetTransform()
        $bar = Get-GridBar
        if ($bar) {
            $trk = New-Object System.Drawing.SolidBrush((Get-Blend $script:cBg $script:cPanel2 0.9))
            if ($script:gridDrag) { $thc = $script:cAccent } else { $thc = $script:cPurple }
            $thb = New-Object System.Drawing.SolidBrush($thc)
            $pth = New-Object System.Drawing.Drawing2D.GraphicsPath
            $r = 5.0; $x0 = [single]$bar.TX; $w0 = [single]$bar.TW
            $pth.AddArc($x0, [single]$bar.TY, $w0, $r * 2, 180, 180)
            $pth.AddArc($x0, [single]($bar.TY + $bar.TH - $r * 2), $w0, $r * 2, 0, 180)
            $pth.CloseFigure()
            $g.FillPath($trk, $pth)
            $pth.Dispose()
            $pt2 = New-Object System.Drawing.Drawing2D.GraphicsPath
            $pt2.AddArc($x0, $bar.BYpos, $w0, $r * 2, 180, 180)
            $pt2.AddArc($x0, [single]($bar.BYpos + $bar.BY - $r * 2), $w0, $r * 2, 0, 180)
            $pt2.CloseFigure()
            $g.FillPath($thb, $pt2)
            $pt2.Dispose(); $trk.Dispose(); $thb.Dispose()
        }
    })

    $cv.Add_MouseDown({
        param($s, $e)
        try { [void]$s.Focus() } catch { }
        $bar = Get-GridBar
        if ($bar -and $e.Button -eq 'Left' -and $e.X -ge $bar.TX - 4) {
            if ($e.Y -ge $bar.BYpos -and $e.Y -le $bar.BYpos + $bar.BY) {
                $script:gridDrag = @{ Y = $e.Y; Start = $script:gridScroll }
                $s.Invalidate()
            } elseif ($e.Y -lt $bar.BYpos) { Set-GridScroll ($script:gridScroll - $s.ClientSize.Height * 0.9) }
            else { Set-GridScroll ($script:gridScroll + $s.ClientSize.Height * 0.9) }
            $script:gridHitName = $null
            return
        }
        $hit = Get-GridHit $e.Location
        $script:gridHitName = $null
        if (-not $hit) { return }
        $script:gridHitName = $hit.Name
        if ($script:lbPacks.Items.Contains($hit.Name)) { $script:lbPacks.SelectedItem = $hit.Name }
        if ($e.Button -eq 'Left' -and $hit.Star) { Switch-PackFav }
    })
    $cv.Add_MouseMove({
        param($s, $e)
        if (-not $script:gridDrag) { return }
        $bar = Get-GridBar
        if (-not $bar) { return }
        $room = $bar.TH - $bar.BY
        if ($room -le 0) { return }
        Set-GridScroll ($script:gridDrag.Start + ($e.Y - $script:gridDrag.Y) * $bar.Max / $room)
    })
    $cv.Add_MouseUp({ param($s, $e) if ($script:gridDrag) { $script:gridDrag = $null; $s.Invalidate() } })
    $cv.Add_MouseWheel({ param($s, $e) Set-GridScroll ($script:gridScroll - ($e.Delta / 120.0) * 60) })
    $cv.Add_Resize({ Refresh-Grid })
    $cv.Add_MouseDoubleClick({
        param($s, $e)
        if ($e.Button -ne 'Left') { return }
        $hit = Get-GridHit $e.Location
        if ($hit -and -not $hit.Star) { [void](Set-Pack (Join-Path $Root $hit.Name)); $script:gridCanvas.Invalidate() }
    })
    $cv.Add_MouseEnter({ param($s, $e) try { if ([System.Windows.Forms.Form]::ActiveForm -eq $script:form) { [void]$s.Focus() } } catch { } })

    $ctx = New-NeonMenu
    [void]$ctx.Items.Add("Apply", $null, { if ($script:lbPacks.SelectedItem) { [void](Set-Pack (Join-Path $Root $script:lbPacks.SelectedItem)); $script:gridCanvas.Invalidate() } })
    [void]$ctx.Items.Add("Favorite / unfavorite", $null, { Switch-PackFav })
    [void]$ctx.Items.Add("Edit tags...", $null, { Edit-PackTags })
    $script:miThumb = New-Object System.Windows.Forms.ToolStripMenuItem("Edit thumbnail")
    [void]$ctx.Items.Add($script:miThumb)
    [void]$ctx.Items.Add("-")
    [void]$ctx.Items.Add("Set as lock screen", $null, { Set-PackAsLockScreen })
    [void]$ctx.Items.Add("Rename...", $null, { Rename-SelectedPack })
    [void]$ctx.Items.Add("Open folder", $null, { if ($script:lbPacks.SelectedItem) { Start-Process explorer.exe -ArgumentList ('"' + (Join-Path $Root $script:lbPacks.SelectedItem) + '"') } })
    [void]$ctx.Items.Add("Delete", $null, { Remove-SelectedPack })
    $ctx.Add_Opening({ param($s, $e) if (-not $script:gridHitName) { $e.Cancel = $true } else { Update-ThumbMenu } })
    $cv.ContextMenuStrip = $ctx

    $script:chkGridFav.Add_CheckedChanged({ if (-not $script:gridBusy) { $script:gridScroll = 0; Refresh-Grid } })
    $script:cmbGridTag.Add_SelectedIndexChanged({ if (-not $script:gridBusy) { $script:gridScroll = 0; Refresh-Grid } })
    $script:cmbGridSort.Add_SelectedIndexChanged({ if (-not $script:gridBusy) { $script:gridScroll = 0; Refresh-Grid } })
    $tt.SetToolTip($script:chkGridFav, "Only show packs you've starred")
    $tt.SetToolTip($script:cmbGridTag, "Only show packs with this tag (right-click a card > Edit tags)")
    $tt.SetToolTip($script:cmbGridSort, "How the cards are ordered")
}

# ================================================================ GLOBAL HOTKEYS
$script:hotOk = $false
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class HotKeyWindow : NativeWindow, IDisposable {
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h, int id, uint mod, uint vk);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h, int id);
    public event EventHandler Pressed;
    public int LastId;
    public HotKeyWindow() { CreateHandle(new CreateParams()); }
    public bool Add(int id, uint mod, uint vk) { return RegisterHotKey(Handle, id, mod | 0x4000, vk); }
    public void Remove(int id) { UnregisterHotKey(Handle, id); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) { LastId = m.WParam.ToInt32(); if (Pressed != null) Pressed(this, EventArgs.Empty); }
        base.WndProc(ref m);
    }
    public void Dispose() { for (int i = 1; i <= 8; i++) UnregisterHotKey(Handle, i); DestroyHandle(); }
}
"@
    $script:hotOk = $true
} catch {
    try { $null = [HotKeyWindow]; $script:hotOk = $true } catch { $script:hotOk = $false }
}
$script:hotWin = $null
$script:manualPause = $false
$script:lockLastPick = ''

# next (+1) / previous (-1) pack, in the same order as the Packs list
function Step-Pack([int]$dir) {
    $names = @()
    foreach ($p in (Get-Packs)) { if (@(Get-PackImages $p.FullName).Count -gt 0) { $names += $p.Name } }
    if ($names.Count -eq 0) { Set-Status "No packs with images yet."; return }
    $ix = [array]::IndexOf($names, [string]$script:currentPack)
    if ($ix -lt 0) { if ($dir -gt 0) { $ix = -1 } else { $ix = 0 } }
    $nx = (($ix + $dir) % $names.Count + $names.Count) % $names.Count
    $pick = $names[$nx]
    if (Set-Pack (Join-Path $Root $pick)) {
        if ($script:lbPacks -and $script:lbPacks.Items.Contains($pick)) { $script:lbPacks.SelectedItem = $pick }
    }
}

function Switch-ManualPause {
    if (-not $script:probeOk) { Set-Status "Pausing isn't available on this PC."; return }
    $script:manualPause = -not $script:manualPause
    if ($script:manualPause) { Set-Status "Live wallpapers paused (hotkey). Press it again to resume." } else { Set-Status "Live wallpapers resumed." }
    Update-AutoPause
}

function Disable-Hotkeys {
    if ($script:hotWin) { try { $script:hotWin.Dispose() } catch { }; $script:hotWin = $null }
}
function Enable-Hotkeys {
    Disable-Hotkeys
    if (-not $script:hotOk) { return "Hotkeys aren't available here." }
    $w = New-Object HotKeyWindow
    $w.add_Pressed({
        param($s, $e)
        try {
            switch ($s.LastId) {
                1 { Step-Pack 1 }
                2 { Step-Pack -1 }
                3 { Switch-ManualPause }
                4 { Invoke-RandomPack }
            }
        } catch { }
    })
    $failed = @()
    # Ctrl+Alt = 3. Right, Left, P, R
    if (-not $w.Add(1, 3, 0x27)) { $failed += 'Right' }
    if (-not $w.Add(2, 3, 0x25)) { $failed += 'Left' }
    if (-not $w.Add(3, 3, 0x50)) { $failed += 'P' }
    if (-not $w.Add(4, 3, 0x52)) { $failed += 'R' }
    $script:hotWin = $w
    if ($failed.Count -gt 0) { return "Some hotkeys are taken by another program: Ctrl+Alt+" + ($failed -join ', ') }
    return ""
}

# ================================================================ BUILDER UNDO / REDO
$script:btUndo = New-Object System.Collections.ArrayList
$script:btRedo = New-Object System.Collections.ArrayList
$script:uhSnap = $null
$script:uhKey = ''
$script:uhPrev = ''

function Copy-Deep($o) {
    if ($o -is [hashtable]) {
        $h = @{}
        foreach ($k in @($o.Keys)) { $h[$k] = Copy-Deep $o[$k] }
        return $h
    }
    if ($o -is [bool[]]) { return , ([bool[]]$o.Clone()) }
    return $o
}
function Get-StateStr($o) {
    if ($o -is [hashtable]) {
        $sb = New-Object System.Text.StringBuilder
        foreach ($k in ($o.Keys | Sort-Object { [string]$_ })) { [void]$sb.Append([string]$k).Append('=').Append((Get-StateStr $o[$k])).Append(';') }
        return '{' + $sb.ToString() + '}'
    }
    return [string]$o
}
function Get-BtStateKey {
    return ((Get-StateStr $script:btData) + '|' + (@($script:btLinks | ForEach-Object { if ($_) { '1' } else { '0' } }) -join ''))
}
function New-BtSnapshot {
    return @{ Data = (Copy-Deep $script:btData); Links = [bool[]]@($script:btLinks); Sel = [int]$script:btSel }
}
function Clear-BtHistory {
    $script:btUndo.Clear(); $script:btRedo.Clear()
    try { $script:uhSnap = New-BtSnapshot; $script:uhKey = Get-BtStateKey; $script:uhPrev = $script:uhKey } catch { }
    Update-UndoButtons
}
function Update-UndoButtons {
    if ($script:btnBtUndo) { $script:btnBtUndo.Enabled = ($script:btUndo.Count -gt 0); $script:btnBtUndo.Invalidate() }
    if ($script:btnBtRedo) { $script:btnBtRedo.Enabled = ($script:btRedo.Count -gt 0); $script:btnBtRedo.Invalidate() }
}
function Restore-BtSnapshot($snap) {
    $script:btData = Copy-Deep $snap.Data
    $script:btLinks = [bool[]]@($snap.Links)
    $script:btSel = [int]$snap.Sel
    Sync-Bt
    $script:btDirty = $true
    $script:uhSnap = New-BtSnapshot; $script:uhKey = Get-BtStateKey; $script:uhPrev = $script:uhKey
    if ($script:pnlBt) { $script:pnlBt.Invalidate() }
    Update-BtInfo
    Update-UndoButtons
}
function Invoke-BtUndo {
    if ($script:btUndo.Count -eq 0) { Set-Status "Nothing to undo."; return }
    $cur = $script:uhSnap
    $snap = $script:btUndo[$script:btUndo.Count - 1]
    $script:btUndo.RemoveAt($script:btUndo.Count - 1)
    if ($cur) { [void]$script:btRedo.Add($cur) }
    Restore-BtSnapshot $snap
    Set-Status "Undone."
}
function Invoke-BtRedo {
    if ($script:btRedo.Count -eq 0) { Set-Status "Nothing to redo."; return }
    $cur = $script:uhSnap
    $snap = $script:btRedo[$script:btRedo.Count - 1]
    $script:btRedo.RemoveAt($script:btRedo.Count - 1)
    if ($cur) { [void]$script:btUndo.Add($cur) }
    Restore-BtSnapshot $snap
    Set-Status "Redone."
}
# called by a timer: records a history step once the layout has settled (so a whole drag is one step)
function Update-BtHistory {
    if ($script:activeTab -ne 3 -or $script:loadingBt) { return }
    $k = Get-BtStateKey
    if ($k -ne $script:uhPrev) { $script:uhPrev = $k; return }
    if ($k -eq $script:uhKey) { return }
    if ($script:uhSnap) {
        [void]$script:btUndo.Add($script:uhSnap)
        while ($script:btUndo.Count -gt 60) { $script:btUndo.RemoveAt(0) }
    }
    $script:btRedo.Clear()
    $script:uhSnap = New-BtSnapshot
    $script:uhKey = $k
    Update-UndoButtons
}

# ================================================================ BUILDER QUICK LINKS (right-click menu)
function Set-BtLinkPattern([bool[]]$pat) {
    $n = @(Get-DisplayList).Count
    $links = New-Object 'bool[]' ([math]::Max(0, $n - 1))
    for ($i = 0; $i -lt $links.Length; $i++) { if ($i -lt $pat.Length) { $links[$i] = $pat[$i] } }
    $script:btLinks = $links
    Sync-Bt
    $script:btDirty = $true
}
function Invoke-BtLayout([string]$name) {
    $n = @(Get-DisplayList).Count
    if ($n -lt 2) { Set-Status "You need at least two screens to link."; return }
    $pat = New-Object 'bool[]' ($n - 1)
    if ($true) {
        switch ($name) {
            "Every screen separate" { }
            "One panorama across all" { for ($i = 0; $i -lt $pat.Length; $i++) { $pat[$i] = $true } }
            "Same picture on every screen" {
                $src = $null
                $lead = Get-BtLeader $script:btSel
                if ($script:btData.ContainsKey($lead)) { $src = Copy-Deep $script:btData[$lead] }
                if (-not $src -or $src.type -eq 'none') { Set-Status "Put a picture or video on a screen first, select it, then pick this layout."; return }
                Set-BtLinkPattern $pat
                foreach ($grp in @(Get-BtGroups)) {
                    $c = Copy-Deep $src
                    $c.over = @{}; $c.zoom = 1.0; $c.cx = 0.5; $c.cy = 0.5
                    $script:btData[$grp.Lead] = $c
                }
                if ($script:pnlBt) { $script:pnlBt.Invalidate() }
                Update-BtInfo
                Set-Status "Same picture on every screen."
                return
            }
        }
        Set-BtLinkPattern $pat
        Set-Status $(if ($name -eq "One panorama across all") { "All screens linked into one panorama." } else { "All screens unlinked." })
    }
    if ($script:pnlBt) { $script:pnlBt.Invalidate() }
    Update-BtInfo
}

# ---------------------------------------------------------------- Windows lock screen (the picture behind the sign-in / lock page)
function Set-LockScreenImage([string]$file) {
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        [void][Windows.System.UserProfile.LockScreen, Windows.System.UserProfile, ContentType = WindowsRuntime]
        [void][Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
        $gen = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
        $op = [Windows.Storage.StorageFile]::GetFileFromPathAsync($file)
        $t1 = $gen.MakeGenericMethod([Windows.Storage.StorageFile]).Invoke($null, @($op))
        if (-not $t1.Wait(15000)) { throw "Windows didn't respond in time." }
        $sf = $t1.Result
        $act = [Windows.System.UserProfile.LockScreen]::SetImageFileAsync($sf)
        $actM = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' } | Select-Object -First 1
        $t2 = $actM.Invoke($null, @($act))
        if (-not $t2.Wait(15000)) { throw "Windows didn't respond in time." }
        return $true
    } catch {
        $m = $_.Exception.Message
        if ($_.Exception.InnerException) { $m = $_.Exception.InnerException.Message }
        Set-Status "Couldn't set the lock screen: $m"
        return $false
    }
}

# ---------------------------------------------------------------- per-pack lock screen setup
# The lock screen shows ONE picture (on the main screen only), so it is built here:
#   thumb   = the same picture as the pack's thumbnail card (default)
#   screens = every screen's picture side by side, as they are on your desktop
#   custom  = a picture you choose (copied into the pack's _lock folder)
# the panorama a pack was built from in the Builder (plus where its screens sit on it)
function Get-PackPano([string]$dir) {
    try {
        $rec = Get-Recipe $dir
        if (-not $rec) { return $null }
        foreach ($g in @($rec)) {
            if ($g.type -eq 'video' -or $g.over -or -not $g.source) { continue }
            if (@($g.screens).Count -lt 2) { continue }
            $f = Join-Path (Join-Path $dir '_source') ([string]$g.source)
            if (Test-Path -LiteralPath $f) {
                # follow the Builder's Rotate R / Rotate L for this picture
                $rot = 0; try { $rot = ((([int]$g.rot) % 360) + 360) % 360 } catch { }
                if ($rot -ne 0) {
                    if (-not $script:panoRotCache) { $script:panoRotCache = @{} }
                    $key = "$f|$rot|" + (Get-Item -LiteralPath $f).LastWriteTimeUtc.Ticks
                    $rf = $script:panoRotCache[$key]
                    if (-not $rf -or -not (Test-Path -LiteralPath $rf)) { $rf = New-RotatedCopy $f $rot; if ($rf) { $script:panoRotCache[$key] = $rf } }
                    if ($rf) { $f = $rf }
                }
                $z = [double]$g.zoom; if ($z -le 0) { $z = 1.0 }
                $cx = 0.5; $cy = 0.5
                if ($null -ne $g.cx) { $cx = [double]$g.cx }
                if ($null -ne $g.cy) { $cy = [double]$g.cy }
                return @{ File = $f; Cx = $cx; Cy = $cy; Z = $z }
            }
        }
    } catch { }
    return $null
}

function Get-LockCfg([string]$dir) {
    $cfg = @{ mode = 'none'; file = ''; auto = $false; screen = 1; pano = $false; cx = 0.5; cy = 0.5; z = 1.0 }
    $geoSet = $false; $found = $false
    try {
        $f = Join-Path (Join-Path $dir '_lock') 'lock.json'
        if (Test-Path -LiteralPath $f) {
            $found = $true
            $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
            if ($j.mode -in @('none', 'thumb', 'screens', 'screen', 'cycle', 'custom', 'pano')) { $cfg.mode = [string]$j.mode }
            if ($j.file) { $cfg.file = [string]$j.file }
            $cfg.auto = [bool]$j.auto
            $cfg.pano = [bool]$j.pano
            if ($j.screen) { $cfg.screen = [math]::Max(1, [int]$j.screen) }
            if ($null -ne $j.fx -and $null -ne $j.fy -and $null -ne $j.fz) { $cfg.cx = [double]$j.fx; $cfg.cy = [double]$j.fy; $cfg.z = [double]$j.fz; $geoSet = $true }
        }
    } catch { }
    $pp = Get-PackPano $dir
    if ($pp) {
        # a pack built from a panorama starts out using that panorama, positioned like in the Builder
        if (-not $found) { $cfg.mode = 'pano' }
        if (-not $geoSet) {
            # start the frame where the main screen sits on the panorama in the Builder
            $dm = Get-ImageDims $pp.File
            if ($dm) {
                $grp = Get-LockGroupGeo $dm.W $dm.H @{ cx = $pp.Cx; cy = $pp.Cy; z = $pp.Z }
                $pi = 0
                foreach ($d in (Get-DisplayList)) { if ($d.Primary) { $pi = [int]$d.Index - 1 } }
                if ($grp -and $pi -lt $grp.Cells.Count) {
                    $cell = $grp.Cells[$pi]
                    $ps = Get-PrimarySize
                    $gw0 = [math]::Min($dm.W, $dm.H * $ps.W / $ps.H)
                    $cfg.cx = ($cell.X + $cell.W / 2) / $dm.W
                    $cfg.cy = ($grp.Top + $grp.H / 2) / $dm.H
                    $cfg.z = [math]::Max(0.2, [math]::Min(1.0, $cell.W / $gw0))
                }
            }
        }
    }
    return $cfg
}

function Save-LockCfg([string]$dir, $cfg) {
    try {
        $d = Join-Path $dir '_lock'
        if (-not (Test-Path -LiteralPath $d)) { [void](New-Item -ItemType Directory -Path $d -Force) }
        ([pscustomobject]@{ mode = [string]$cfg.mode; file = [string]$cfg.file; auto = [bool]$cfg.auto; screen = [int]$cfg.screen; pano = [bool]$cfg.pano; fx = [double]$cfg.cx; fy = [double]$cfg.cy; fz = [double]$cfg.z } | ConvertTo-Json) | Set-Content -LiteralPath (Join-Path $d 'lock.json') -Encoding UTF8
    } catch { Set-Status "Couldn't save the lock screen setup: $($_.Exception.Message)" }
}

# (used only to turn a Builder layout into a single lock frame) where the whole group of screens sits on a panorama
function Get-LockGroupGeo([double]$iw, [double]$ih, $cfg) {
    $ds = @(Get-DisplayList)
    if ($ds.Count -eq 0) { return $null }
    $hmax = [double](($ds | Measure-Object -Property H -Maximum).Maximum)
    $ws = @(); $total = 0.0
    foreach ($d in $ds) { $w = $d.W * $hmax / $d.H; $ws += $w; $total += $w }
    $aspect = $total / $hmax
    $gw0 = [math]::Min($iw, $ih * $aspect)
    $z = [math]::Max(0.2, [math]::Min(1.0, [double]$cfg.z))
    $gw = $gw0 * $z; $gh = $gw / $aspect
    $cx = [math]::Max($gw / 2, [math]::Min($iw - $gw / 2, [double]$cfg.cx * $iw))
    $cy = [math]::Max($gh / 2, [math]::Min($ih - $gh / 2, [double]$cfg.cy * $ih))
    $left = $cx - $gw / 2; $top = $cy - $gh / 2
    $cells = @(); $x = $left
    foreach ($w in $ws) { $cw = $w / $total * $gw; $cells += , @{ X = $x; W = $cw }; $x += $cw }
    return @{ Left = $left; Top = $top; W = $gw; H = $gh; Cells = $cells }
}

# the lock screen is ONE screen's picture: a single frame (main screen's shape) sliding over the panorama
function Get-LockGeo([double]$iw, [double]$ih, $cfg) {
    $ps = Get-PrimarySize
    $aspect = [double]$ps.W / [double]$ps.H
    $gw0 = [math]::Min($iw, $ih * $aspect)
    $z = [math]::Max(0.2, [math]::Min(1.0, [double]$cfg.z))
    $gw = $gw0 * $z; $gh = $gw / $aspect
    $cx = [math]::Max($gw / 2, [math]::Min($iw - $gw / 2, [double]$cfg.cx * $iw))
    $cy = [math]::Max($gh / 2, [math]::Min($ih - $gh / 2, [double]$cfg.cy * $ih))
    return @{ Left = $cx - $gw / 2; Top = $cy - $gh / 2; W = $gw; H = $gh }
}

$script:panoDims = @{}
function Get-ImageDims([string]$file) {
    if ($script:panoDims.ContainsKey($file)) { return $script:panoDims[$file] }
    try {
        $ld = Read-ImageFromFile $file
        try { $d = @{ W = [double]$ld.Image.Width; H = [double]$ld.Image.Height } } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
        $script:panoDims[$file] = $d
        return $d
    } catch { return $null }
}

# draws part of a picture (source rectangle) so it fills the destination, cropping the overflow evenly
function Add-CoverDrawRect($gr, $img, [double]$sx, [double]$sy, [double]$sw, [double]$sh, [single]$dx, [single]$dy, [single]$dw, [single]$dh) {
    $dr = $dw / $dh; $sr = $sw / $sh
    if ($sr -gt $dr) { $nw = $sh * $dr; $sx += ($sw - $nw) / 2; $sw = $nw }
    else { $nh = $sw / $dr; $sy += ($sh - $nh) / 2; $sh = $nh }
    $src = New-Object System.Drawing.RectangleF([single]$sx, [single]$sy, [single]$sw, [single]$sh)
    $dest = New-Object System.Drawing.RectangleF($dx, $dy, $dw, $dh)
    $gr.DrawImage($img, $dest, $src, [System.Drawing.GraphicsUnit]::Pixel)
}

# draws one picture (or one screen's cell of a panorama picture) over the whole bitmap
function Add-LockPicture($bmp, [string]$file, $cfg, [bool]$usePano) {
    $W = $bmp.Width; $H = $bmp.Height
    $gr = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $gr.InterpolationMode = 'HighQualityBicubic'
        $gr.Clear([System.Drawing.Color]::Black)
        $ld = Read-ImageFromFile $file
        try {
            $iw = [double]$ld.Image.Width; $ih = [double]$ld.Image.Height
            $sx = 0.0; $sy = 0.0; $sw = $iw; $sh = $ih
            if ($usePano) {
                $geo = Get-LockGeo $iw $ih $cfg
                if ($geo) { $sx = $geo.Left; $sw = $geo.W; $sy = $geo.Top; $sh = $geo.H }
            }
            Add-CoverDrawRect $gr $ld.Image $sx $sy $sw $sh 0 0 ([single]$W) ([single]$H)
        } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
    } finally { $gr.Dispose() }
}

function New-LockBmp([string]$dir, $cfg, [int]$W, [int]$H) {
    $mode = [string]$cfg.mode
    if ($mode -eq 'none') { return $null }
    $imgs = @(Get-PackImages $dir)
    if ($mode -eq 'custom') {
        $cf = Join-Path (Join-Path $dir '_lock') ([string]$cfg.file)
        if ($cfg.file -and (Test-Path -LiteralPath $cf)) {
            $bmp = New-Object System.Drawing.Bitmap($W, $H)
            Add-LockPicture $bmp $cf $cfg ([bool]$cfg.pano)
            return $bmp
        }
        $mode = 'thumb'
    }
    if ($mode -eq 'pano') {
        $pp = Get-PackPano $dir
        if ($pp) {
            $bmp = New-Object System.Drawing.Bitmap($W, $H)
            Add-LockPicture $bmp $pp.File $cfg $true
            return $bmp
        }
        $mode = 'thumb'
    }
    if ($mode -eq 'screen' -and $imgs.Count -gt 0) {
        $bmp = New-Object System.Drawing.Bitmap($W, $H)
        Add-LockPicture $bmp $imgs[([math]::Max(1, [int]$cfg.screen) - 1) % $imgs.Count].FullName $cfg $false
        return $bmp
    }
    if ($mode -eq 'cycle' -and $imgs.Count -gt 0) {
        $pool = @($imgs | Where-Object { $_.FullName -ne $script:lockLastPick })
        if ($pool.Count -eq 0) { $pool = $imgs }
        $pick = $pool | Get-Random
        $script:lockLastPick = $pick.FullName
        $bmp = New-Object System.Drawing.Bitmap($W, $H)
        Add-LockPicture $bmp $pick.FullName $cfg $false
        return $bmp
    }
    if ($mode -eq 'screens') {
        $ds = @(Get-DisplayList)
        $bmp = New-Object System.Drawing.Bitmap($W, $H)
        $gr = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $gr.InterpolationMode = 'HighQualityBicubic'
            $gr.Clear([System.Drawing.Color]::Black)
            if ($imgs.Count -gt 0 -and $ds.Count -gt 0) {
                $hmax = [double](($ds | Measure-Object -Property H -Maximum).Maximum)
                $total = 0.0
                foreach ($d in $ds) { $total += $d.W * $hmax / $d.H }
                $sc = [math]::Min($W / $total, $H / $hmax)
                $x = ($W - $total * $sc) / 2.0
                $y = ($H - $hmax * $sc) / 2.0
                for ($i = 0; $i -lt $ds.Count; $i++) {
                    $d = $ds[$i]
                    $dw = $d.W * $hmax / $d.H * $sc
                    $dh = $hmax * $sc
                    try {
                        $ld = Read-ImageFromFile $imgs[$i % $imgs.Count].FullName
                        try { Add-CoverDraw $gr $ld.Image ([single]$x) ([single]$y) ([single]$dw) ([single]$dh) } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
                    } catch { }
                    $x += $dw
                }
            }
        } finally { $gr.Dispose() }
        return $bmp
    }
    $r = New-PackThumbBmp $dir $W $H
    return $r.Bmp
}

function Get-PrimarySize {
    $W = 1920; $H = 1080
    foreach ($d in (Get-DisplayList)) { if ($d.Primary) { $W = $d.W; $H = $d.H } }
    return @{ W = $W; H = $H }
}

# puts Windows' own stock lock picture back (used when a pack has no lock screen chosen)
function Restore-DefaultLockScreen {
    $cands = @(
        (Join-Path $env:windir 'Web\Screen\img100.jpg'),
        (Join-Path $env:windir 'Web\Screen\img105.jpg'),
        (Join-Path $env:windir 'Web\Screen\img102.jpg'),
        (Join-Path $env:windir 'Web\Wallpaper\Windows\img0.jpg'))
    foreach ($c in $cands) {
        if (Test-Path -LiteralPath $c) {
            if (Set-LockScreenImage $c) { try { Save-Setting 'LockSetByApp' '0' } catch { }; return $true }
            return $false
        }
    }
    Set-Status "Couldn't find Windows' default lock screen picture. Set it in Settings > Personalization > Lock screen."
    return $false
}

# builds the lock picture for a pack (using its saved setup) and hands it to Windows
function Apply-PackLockScreen([string]$name) {
    $dir = Join-Path $Root $name
    if (-not (Test-Path -LiteralPath $dir)) { Set-Status "That pack wasn't found."; return $false }
    $cfg = Get-LockCfg $dir
    if ($cfg.mode -eq 'none') { return (Restore-DefaultLockScreen) }
    if (@(Get-PackImages $dir).Count -eq 0) { Set-Status "No images in that pack."; return $false }
    try {
        $ps = Get-PrimarySize
        $bmp = New-LockBmp $dir $cfg $ps.W $ps.H
        $out = Join-Path $env:TEMP ("WallpaperCC_lock_{0}.png" -f [DateTime]::Now.Ticks)
        try { $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
        $ok = Set-LockScreenImage $out
        if ($ok) { try { Save-Setting 'LockSetByApp' '1' } catch { } }
        foreach ($f in @(Get-ChildItem -LiteralPath $env:TEMP -Filter 'WallpaperCC_lock_*.png' -ErrorAction SilentlyContinue)) {
            if ($f.FullName -ne $out) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
        }
        return $ok
    } catch {
        Set-Status "Couldn't build the lock screen picture: $($_.Exception.Message)"
        return $false
    }
}

# called after a pack is applied: the lock screen follows the pack
function Update-PackLock([string]$name) {
    $gs = Get-Settings
    if ([string]$gs.LockMode -eq 'custom') {
        $pic = [string]$gs.LockPic
        if ([string]$gs.LockCustom -eq 'picture' -and $pic -and (Test-Path -LiteralPath $pic)) {
            try {
                $ps = Get-PrimarySize
                $bmp = New-Object System.Drawing.Bitmap($ps.W, $ps.H)
                Add-LockPicture $bmp $pic @{ cx = 0.5; cy = 0.5; z = 1.0; screen = 1; pano = $false } $false
                $out = Join-Path $env:TEMP ("WallpaperCC_lock_{0}.png" -f [DateTime]::Now.Ticks)
                try { $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png) } finally { $bmp.Dispose() }
                if (Set-LockScreenImage $out) { Save-Setting 'LockSetByApp' '1' }
            } catch { }
        } elseif ([string]$gs.LockSetByApp -eq '1') { [void](Restore-DefaultLockScreen) }
        return
    }
    $dir = Join-Path $Root $name
    $cfg = Get-LockCfg $dir
    if ($cfg.mode -eq 'none') {
        if ([string](Get-Settings).LockSetByApp -eq '1') { [void](Restore-DefaultLockScreen) }
    } else { [void](Apply-PackLockScreen $name) }
}

function Set-PackAsLockScreen {
    $name = [string]$script:lbPacks.SelectedItem
    if (-not $name) { Set-Status "Click a pack first."; return }
    $isNone = ((Get-LockCfg (Join-Path $Root $name)).mode -eq 'none')
    if (Apply-PackLockScreen $name) {
        if ($isNone) { Set-Status "'$name' has no lock screen chosen, so Windows' default was restored. Pick one under Builder > Lock screen." }
        else { Set-Status "Lock screen set from '$name'. Press Win+L to see it. (If it doesn't change, set Personalization > Lock screen to 'Picture'.)" }
    }
}


# ---------------------------------------------------------------- "random picture each lock"
# A hidden window listens for Windows' lock / unlock notices and counts them; a timer then
# swaps the lock picture. (Falls back to watching the lock screen process if that isn't available.)
$script:sessOk = $false
try {
    Add-Type -ReferencedAssemblies System.Windows.Forms -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public class SessionWatch : NativeWindow, IDisposable {
    [DllImport("wtsapi32.dll")] static extern bool WTSRegisterSessionNotification(IntPtr h, int flags);
    [DllImport("wtsapi32.dll")] static extern bool WTSUnRegisterSessionNotification(IntPtr h);
    public int Locks;
    public int Unlocks;
    public SessionWatch() { CreateHandle(new CreateParams()); WTSRegisterSessionNotification(Handle, 0); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x02B1) {
            int w = m.WParam.ToInt32();
            if (w == 7) Locks++;
            else if (w == 8) Unlocks++;
        }
        base.WndProc(ref m);
    }
    public void Dispose() { try { WTSUnRegisterSessionNotification(Handle); } catch { } DestroyHandle(); }
}
"@
    $script:sessOk = $true
} catch {
    try { $null = [SessionWatch]; $script:sessOk = $true } catch { $script:sessOk = $false }
}
$script:sessWin = $null
if ($script:sessOk) { try { $script:sessWin = New-Object SessionWatch } catch { $script:sessWin = $null } }
$script:sessL = 0; $script:sessU = 0
$script:wasLocked = $false

function Test-CycleLockActive {
    if (-not $script:currentPack) { return $false }
    $dir = Join-Path $Root $script:currentPack
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    return ((Get-LockCfg $dir).mode -eq 'cycle')
}

function Update-CycleLock {
    $changed = $false
    if ($script:sessWin) {
        $l = $script:sessWin.Locks; $u = $script:sessWin.Unlocks
        if ($l -ne $script:sessL -or $u -ne $script:sessU) { $changed = $true }
        $script:sessL = $l; $script:sessU = $u
    } else {
        $locked = [bool](Get-Process -Name 'LogonUI' -ErrorAction SilentlyContinue)
        if ($script:wasLocked -and -not $locked) { $changed = $true }
        $script:wasLocked = $locked
    }
    if ($changed -and (Test-CycleLockActive)) { [void](Apply-PackLockScreen $script:currentPack) }
}
# ---------------------------------------------------------------- settings window (gear icon in the header)
# Screen saver options + the Windows power / display settings that go with it.

$script:SaverExe = Join-Path $PSScriptRoot "Ekk0h.scr"
# the screen saver is built into the exe; this writes it out next to the exe the first time it is needed
function Get-SaverPath {
    if (Test-Path -LiteralPath $script:SaverExe) { return $script:SaverExe }
    try {
        $st = [System.Reflection.Assembly]::GetEntryAssembly().GetManifestResourceStream('Ekk0h.scr')
        if ($st) {
            $fs = [IO.File]::Create($script:SaverExe)
            try { $st.CopyTo($fs) } finally { $fs.Dispose(); $st.Dispose() }
            return $script:SaverExe
        }
    } catch { }
    return $null
}

try {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class SaverSys {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, IntPtr vparam, uint winIni);
    public static void Apply(bool active, int seconds) {
        SystemParametersInfo(0x000F, (uint)seconds, IntPtr.Zero, 3);          // SPI_SETSCREENSAVETIMEOUT
        SystemParametersInfo(0x0011, active ? 1u : 0u, IntPtr.Zero, 3);       // SPI_SETSCREENSAVEACTIVE
    }
}
"@ -ErrorAction Stop
} catch { }

function Get-SaverSourceText {
    $st = Get-Settings
    $parts = @()
    foreach ($t in ([string]$st.ScreensaverSrc -split '\|')) {
        $t = $t.Trim()
        if ($t -eq 'fav') { $parts += 'Favorites' } elseif ($t.StartsWith('tag:')) { $parts += ('#' + $t.Substring(4)) } elseif ($t.StartsWith('pack:')) { $parts += $t.Substring(5) }
    }
    if ($parts.Count -eq 0) { return "All packs" }
    $txt = ($parts -join ', ')
    if ($txt.Length -gt 24) { $txt = ($parts.Count.ToString() + " selections") }
    return $txt
}

function Get-AllPackTags {
    $tags = @{}
    foreach ($e in (Get-PackMeta).Values) { foreach ($t in @($e.tags)) { if ($t) { $tags[[string]$t] = 1 } } }
    return @($tags.Keys | Sort-Object)
}

function Show-SaverSourceMenu($anchor) {
    $st = Get-Settings
    $src = @(([string]$st.ScreensaverSrc -split '\|') | Where-Object { $_.Trim() })
    $m = New-NeonMenu
    $m.ShowCheckMargin = $true
    $mk = {
        param($text, $tag, $on)
        $it = New-Object System.Windows.Forms.ToolStripMenuItem($text)
        $it.Tag = $tag; $it.CheckOnClick = $true; $it.Checked = $on
        $it
    }
    $items = @()
    $items += & $mk "All packs" 'all' ($src.Count -eq 0)
    $items += & $mk "Favorites" 'fav' ($src -contains 'fav')
    $tags = @(Get-AllPackTags)
    foreach ($t in $tags) { $items += & $mk ('#' + $t) ('tag:' + $t) ($src -contains ('tag:' + $t)) }
    $selPack = ''
    try { $selPack = [string]$script:lbPacks.SelectedItem } catch { }
    foreach ($e1 in $src) { if ($e1.StartsWith('pack:') -and $e1 -ne ('pack:' + $selPack)) { $items += & $mk ('Pack: ' + $e1.Substring(5)) $e1 $true } }
    if ($selPack) { $items += & $mk ('Selected Pack: ' + $selPack) ('pack:' + $selPack) ($src -contains ('pack:' + $selPack)) }
    foreach ($it in $items) {
        $it.Add_Click({
            param($s, $e)
            $menu = $s.Owner
            if ([string]$s.Tag -eq 'all') {
                foreach ($o in $menu.Items) { if ($o -ne $s) { $o.Checked = $false } }
                $s.Checked = $true
            } else {
                $any = $false
                foreach ($o in $menu.Items) { if ([string]$o.Tag -ne 'all' -and $o.Checked) { $any = $true } }
                foreach ($o in $menu.Items) { if ([string]$o.Tag -eq 'all') { $o.Checked = (-not $any) } }
            }
            $sel = @()
            foreach ($o in $menu.Items) { if ([string]$o.Tag -ne 'all' -and $o.Checked) { $sel += [string]$o.Tag } }
            Save-Setting 'ScreensaverSrc' ($sel -join '|')
            if ($script:btnSaverSrc) { $script:btnSaverSrc.Text = "Packs: " + (Get-SaverSourceText) }
        })
        [void]$m.Items.Add($it)
    }
    if ($tags.Count -eq 0) {
        $hint = New-Object System.Windows.Forms.ToolStripMenuItem("(no tags yet: right-click a card > Edit tags)")
        $hint.Enabled = $false
        [void]$m.Items.Add($hint)
    }
    $m.Add_Closing({ param($s, $e) if ($e.CloseReason -eq 'ItemClicked') { $e.Cancel = $true } })
    $m.Show($anchor, (New-Object System.Drawing.Point(0, $anchor.Height)))
}

# ---- Windows power settings (powercfg). Values are minutes, 0 = never.
function Get-PowerMinutes([string]$sub, [string]$setting, [bool]$ac) {
    try {
        $o = (& powercfg /query SCHEME_CURRENT $sub $setting 2>$null | Out-String)
        $key = if ($ac) { 'Current AC Power Setting Index' } else { 'Current DC Power Setting Index' }
        $m = [regex]::Match($o, $key + ':\s*0x([0-9a-fA-F]+)')
        if ($m.Success) { return [int]([Convert]::ToInt64($m.Groups[1].Value, 16) / 60) }
    } catch { }
    return -1
}
function Set-PowerMinutes([string]$kind, [bool]$ac, [int]$mins) {
    $suffix = if ($ac) { 'ac' } else { 'dc' }
    try { & powercfg /change ("{0}-timeout-{1}" -f $kind, $suffix) $mins 2>$null | Out-Null } catch { }
}
function Test-HasBattery {
    try { return (@(Get-CimInstance -ClassName Win32_Battery -ErrorAction Stop).Count -gt 0) } catch { return $false }
}

$script:powerLabels = @("Never", "1 Minute", "2 Minutes", "3 Minutes", "5 Minutes", "10 Minutes", "15 Minutes", "20 Minutes", "30 Minutes", "45 Minutes", "1 Hour", "2 Hours", "3 Hours", "5 Hours")
$script:powerMins   = @(0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 120, 180, 300)

function New-PowerCombo([int]$x, [int]$y, [string]$sub, [string]$setting, [string]$kind, [bool]$ac) {
    $c = New-StyledCombo $x $y 170
    foreach ($l in $script:powerLabels) { [void]$c.Items.Add($l) }
    $cur = Get-PowerMinutes $sub $setting $ac
    $idx = [array]::IndexOf($script:powerMins, $cur)
    if ($idx -lt 0 -and $cur -gt 0) { [void]$c.Items.Add(("{0} minutes" -f $cur)); $idx = $c.Items.Count - 1 }
    if ($idx -ge 0) { $c.SelectedIndex = $idx }
    $c.Tag = @{ Kind = $kind; Ac = $ac }
    $c.Add_SelectedIndexChanged({
        param($s, $e)
        $i = $s.SelectedIndex
        if ($i -ge 0 -and $i -lt $script:powerMins.Count) { Set-PowerMinutes $s.Tag.Kind $s.Tag.Ac $script:powerMins[$i] }
    })
    return $c
}


# ---- add-ons section of the settings window
$script:addonDefs = @(
    @{ Id = 'ffmpeg';  Name = 'ffmpeg (video cuts)';      Url = $null;                                              Size = 'about 100 MB' },
    @{ Id = 'upscale'; Name = 'AI upscaler (Real-ESRGAN)'; Url = $null;                                              Size = 'about 45 MB' },
    @{ Id = 'lively';  Name = 'Lively (animated)';        Url = 'https://www.rocksdanister.com/lively/';            Size = '' }
)

function Update-AddonRow($row) {
    $info = Get-AddonInfo $row.Id
    $off = ([string](Get-Settings)["AddonOff_$($row.Id)"] -eq '1')
    $row.Loading = $true
    try { $row.Check.Checked = -not $off } finally { $row.Loading = $false }
    if ($info.Ok) {
        $txt = [string][char]0x2713 + " Ready"
        $row.Status.Text = $txt
        $row.Status.ForeColor = $script:cOk
        $row.Get.Visible = $false
        $row.Check.Enabled = $true
    } elseif ($info.Found) {
        $row.Status.Text = "! " + $info.Detail
        $row.Status.ForeColor = $script:cOrange
        $row.Get.Visible = ($row.Id -ne 'lively')
        $row.Check.Enabled = $false
    } else {
        $row.Status.Text = "Not installed"
        $row.Status.ForeColor = $script:cDim
        $row.Get.Visible = $true
        $row.Check.Enabled = $false
    }
    if ($info.Path) { $script:addonTip.SetToolTip($row.Status, [string]$info.Path) } else { $script:addonTip.SetToolTip($row.Status, "Not found") }
}

function Add-AddonRows($dlg, [int]$x0, [int]$y) {
    $script:addonTip = New-Object System.Windows.Forms.ToolTip
    $script:addonRows = @()
    foreach ($def in $script:addonDefs) {
        $row = @{ Id = $def.Id; Loading = $false; Def = $def }
        $chk = New-NeonCheck $def.Name $x0 ($y + 1) 210 28
        $st = New-Label "" ($x0 + 214) ($y + 5) 96 22 $true 9
        $get = New-Btn "Get" ($x0 + 312) $y 50 'cyan' 28
        $loc = New-Btn "Locate" ($x0 + 366) $y 60 'normal' 28
        $get.Font = Get-RetroFont 8; $loc.Font = Get-RetroFont 8
        $row.Check = $chk; $row.Status = $st; $row.Get = $get; $row.Loc = $loc
        $chk.Tag = $row; $get.Tag.Row = $row; $loc.Tag.Row = $row
        $chk.Add_CheckedChanged({
            param($s, $e)
            $r = $s.Tag
            if ($r.Loading) { return }
            if ($s.Checked) { Save-Setting ("AddonOff_" + $r.Id) "" } else { Save-Setting ("AddonOff_" + $r.Id) "1" }
            try { Update-AddonVisibility } catch { }
        })
        $get.Add_Click({
            param($s, $e)
            $r = $s.Tag.Row
            if ($r.Def.Url) { try { Start-Process $r.Def.Url } catch { }; $r.Status.Text = "Install it, then press Locate"; return }
            $q = [System.Windows.Forms.MessageBox]::Show("Download $($r.Def.Name) ($($r.Def.Size)) from its official page and set it up inside this app's Tools folder?", "Download", 'YesNo', 'Question')
            if ($q -ne 'Yes') { return }
            $s.Enabled = $false; $r.Loc.Enabled = $false
            $r.Status.ForeColor = $script:cCyan
            try {
                $err = Install-Addon $r.Id { param($t) $r.Status.Text = $t }.GetNewClosure()
            } finally { $s.Enabled = $true; $r.Loc.Enabled = $true }
            Clear-AddonCache
            if ($err) { $r.Status.Text = "Failed"; $r.Status.ForeColor = $script:cOrange; [void][System.Windows.Forms.MessageBox]::Show($err, "Download", 'OK', 'Warning') }
            foreach ($x in $script:addonRows) { Update-AddonRow $x }
            try { Update-AddonVisibility } catch { }
        })
        $loc.Add_Click({
            param($s, $e)
            $r = $s.Tag.Row
            $d = New-Object System.Windows.Forms.OpenFileDialog
            $d.Filter = "Programs|*.exe"
            switch ($r.Id) {
                'ffmpeg'  { $d.Title = "Find ffmpeg.exe"; $key = 'FfmpegPath' }
                'upscale' { $d.Title = "Find realesrgan-ncnn-vulkan.exe"; $key = 'UpscalerPath' }
                default   { $d.Title = "Find Lively.exe"; $key = 'LivelyPath' }
            }
            if ($d.ShowDialog() -eq 'OK') { Save-Setting $key $d.FileName }
            Clear-AddonCache
            foreach ($x in $script:addonRows) { Update-AddonRow $x }
            try { Update-AddonVisibility } catch { }
        })
        foreach ($c in @($chk, $st, $get, $loc)) { $dlg.Controls.Add($c) }
        $script:addonRows += , $row
        Update-AddonRow $row
        $y += 30
    }
}

# ---------------------------------------------------------------- About, updates and settings backup
function Get-UpdateInfo {
    $repo = [string]$script:UpdateRepo
    if (-not $repo) { return @{ State = 'norepo' } }
    try {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'Ekk0h-update-check'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 8
        $tag = ([string]$r.tag_name) -replace '^[vV]', ''
        $latest = $null; $mine = [version]$script:AppVersion
        if (-not [version]::TryParse($tag, [ref]$latest)) { return @{ State = 'error'; Msg = "Couldn't read the version '$tag'." } }
        if ($latest -gt $mine) { return @{ State = 'new'; Tag = $tag; Url = [string]$r.html_url } }
        return @{ State = 'current'; Tag = $tag; Url = [string]$r.html_url }
    } catch {
        $m = $_.Exception.Message
        if ($m -match '404') { return @{ State = 'none' } }
        return @{ State = 'error'; Msg = $m }
    }
}

function Export-AppSettings([string]$path) {
    $machine = @('LivelyPath', 'FfmpegPath', 'UpscalerPath')
    $set = [ordered]@{}
    foreach ($k in ((Get-Settings).Keys | Sort-Object)) { if ($machine -notcontains $k) { $set[$k] = [string](Get-Settings)[$k] } }
    $meta = $null
    try { if (Test-Path -LiteralPath $script:MetaPath) { $meta = Get-Content -LiteralPath $script:MetaPath -Raw | ConvertFrom-Json } } catch { }
    $obj = [ordered]@{ app = 'Ekk0h'; version = $script:AppVersion; exported = (Get-Date).ToString('s'); settings = $set; packmeta = $meta }
    ($obj | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $path -Encoding UTF8
}

function Import-AppSettings([string]$path) {
    $j = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if (-not $j -or $j.app -ne 'Ekk0h' -or -not $j.settings) { throw "That file isn't an Ekk0h settings backup." }
    # keep a copy of what is there now
    $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    if (Test-Path -LiteralPath $SettingsPath) { Copy-Item -LiteralPath $SettingsPath -Destination (Join-Path $PSScriptRoot "settings.before-import-$stamp.json") -Force }
    if (Test-Path -LiteralPath $script:MetaPath) { Copy-Item -LiteralPath $script:MetaPath -Destination (Join-Path $PSScriptRoot "packmeta.before-import-$stamp.json") -Force }
    $keep = @('LivelyPath', 'FfmpegPath', 'UpscalerPath')
    $cur = Get-Settings
    $new = [ordered]@{}
    foreach ($p in $j.settings.PSObject.Properties) { $new[[string]$p.Name] = [string]$p.Value }
    foreach ($k in $keep) { if ($cur.ContainsKey($k)) { $new[$k] = [string]$cur[$k] } }
    ($new | ConvertTo-Json) | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    if ($j.packmeta) { ($j.packmeta | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $script:MetaPath -Encoding UTF8 }
}

function Show-AboutDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "About, updates and backup"
    $dlg.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $dlg.AutoScaleMode = 'Dpi'
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:cBg; $dlg.ForeColor = $script:cText
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    if ($script:appIcon) { $dlg.Icon = $script:appIcon }
    $dlg.Add_HandleCreated({ param($s, $e) Set-TitleBar $s.Handle })
    $dlg.ClientSize = New-Object System.Drawing.Size(460, 436)

    $t = New-Label "EKK0H // WALLPAPER STUDIO" 24 14 420 28 $false 13
    $t.Font = Get-RetroFont 13 'Bold, Italic'
    $dlg.Controls.Add($t)
    $dlg.Controls.Add((New-Label ("Version " + $script:AppVersion) 24 44 300 22 $true 9))

    $dlg.Controls.Add((New-Heading "Updates" 24 80 300))
    $btnChk = New-Btn "Check for updates" 24 108 170 'cyan' 30
    $btnChk.Font = Get-RetroFont 8
    $btnRel = New-Btn "Open release page" 202 108 170 'normal' 30
    $btnRel.Font = Get-RetroFont 8
    $btnRel.Visible = $false
    $lblUp = New-Label "" 24 144 412 40 $true 9
    $dlg.Controls.Add($btnChk); $dlg.Controls.Add($btnRel); $dlg.Controls.Add($lblUp)
    $btnChk.Add_Click({
        $dlg.Cursor = 'WaitCursor'; $lblUp.Text = "Checking..."; [System.Windows.Forms.Application]::DoEvents()
        try { $r = Get-UpdateInfo } finally { $dlg.Cursor = 'Default' }
        $btnRel.Visible = $false
        switch ($r.State) {
            'norepo'  { $lblUp.Text = "Update checking switches on once the project is published on GitHub." }
            'none'    { $lblUp.Text = "No releases have been published yet." }
            'current' { $lblUp.Text = "You're up to date (latest is " + $r.Tag + ")."; $lblUp.ForeColor = $script:cOk }
            'new'     { $lblUp.Text = "A new version is available: " + $r.Tag + "."; $lblUp.ForeColor = $script:cAccent; $btnRel.Tag.Url = $r.Url; $btnRel.Visible = $true }
            default   { $lblUp.Text = "Couldn't check: " + $r.Msg; $lblUp.ForeColor = $script:cOrange }
        }
    }.GetNewClosure())
    $btnRel.Add_Click({ param($s, $e) try { Start-Process ([string]$s.Tag.Url) } catch { } })

    $dlg.Controls.Add((New-Heading "Backup" 24 196 300))
    $btnExp = New-Btn "Export settings..." 24 224 170 'normal' 30
    $btnImp = New-Btn "Import settings..." 202 224 170 'normal' 30
    $btnExp.Font = Get-RetroFont 8; $btnImp.Font = Get-RetroFont 8
    $lblBk = New-Label "Saves your options, schedule, favorites and tags to one file (not the pictures)." 24 260 412 52 $true 9
    $dlg.Controls.Add($btnExp); $dlg.Controls.Add($btnImp); $dlg.Controls.Add($lblBk)
    $dlg.Controls.Add((New-Heading "Setup" 24 318 300))
    $btnWiz = New-Btn "Run setup again..." 24 346 170 'normal' 30
    $btnWiz.Font = Get-RetroFont 8
    $dlg.Controls.Add($btnWiz)
    $btnWiz.Add_Click({ Show-SetupWizard })
    $btnExp.Add_Click({
        $sd = New-Object System.Windows.Forms.SaveFileDialog
        $sd.Filter = "Ekk0h settings|*.json"; $sd.FileName = "Ekk0h-settings.json"; $sd.Title = "Export settings"
        if ($sd.ShowDialog() -ne 'OK') { return }
        try { Export-AppSettings $sd.FileName; $lblBk.Text = "Saved to " + $sd.FileName; $lblBk.ForeColor = $script:cOk }
        catch { $lblBk.Text = "Couldn't export: " + $_.Exception.Message; $lblBk.ForeColor = $script:cOrange }
    }.GetNewClosure())
    $btnImp.Add_Click({
        $od = New-Object System.Windows.Forms.OpenFileDialog
        $od.Filter = "Ekk0h settings|*.json"; $od.Title = "Import settings"
        if ($od.ShowDialog() -ne 'OK') { return }
        $q = [System.Windows.Forms.MessageBox]::Show("Replace your current options, schedule, favorites and tags with the ones in this file?`n`nYour current ones are kept as 'before-import' copies in the app folder.", "Import settings", 'YesNo', 'Question')
        if ($q -ne 'Yes') { return }
        try {
            Import-AppSettings $od.FileName
            $r = [System.Windows.Forms.MessageBox]::Show("Imported. Restart now to use them?", "Import settings", 'YesNo', 'Question')
            if ($r -eq 'Yes') { $dlg.Close(); Restart-App; $script:exiting = $true; $script:form.Close() }
            else { $lblBk.Text = "Imported. Restart the app to apply."; $lblBk.ForeColor = $script:cOk }
        } catch { $lblBk.Text = "Couldn't import: " + $_.Exception.Message; $lblBk.ForeColor = $script:cOrange }
    }.GetNewClosure())

    $ok = New-Btn "Close" 160 ($dlg.ClientSize.Height - 46) 140 'primary' 34
    $ok.DialogResult = 'OK'
    $dlg.Controls.Add($ok)
    $dlg.AcceptButton = $ok; $dlg.CancelButton = $ok
    [void]$dlg.ShowDialog($script:form)
    $dlg.Dispose()
}

function Add-WheelHook($c, $wheel) {
    try { $c.Add_MouseWheel($wheel) } catch { }
    foreach ($k in $c.Controls) { Add-WheelHook $k $wheel }
}

function Get-SetScrollThumb($sc) {
    $th = [int][math]::Max(34, $sc.ViewH * $sc.ViewH / ($sc.ViewH + $sc.Range))
    $ty = [int](($sc.ViewH - $th) * $sc.Off / $sc.Range)
    return @{ Y = $ty; H = $th }
}

function Set-SetScroll($sc, [double]$v) {
    $v = [int][math]::Max(0, [math]::Min($sc.Range, $v))
    $sc.Off = $v
    $sc.Dlg.Top = $sc.Base - $v
    $sc.Bar.Invalidate()
}

# The whole tab (both columns) scrolls together with a bar drawn in the theme instead of the system bar.
function Add-SettingsScroll($parent, $dlg, [int]$baseTop) {
    $parent.AutoScroll = $false
    $viewH = [int]$parent.Height
    $kids = @(); foreach ($k in $parent.Controls) { $kids += $k }
    $contentH = $viewH
    foreach ($k in $kids) { if ($k.Bottom + 10 -gt $contentH) { $contentH = $k.Bottom + 10 } }
    $range = [int]($contentH - $viewH)
    if ($range -le 0) { return }
    $inner = New-Object System.Windows.Forms.Panel
    $inner.Location = New-Object System.Drawing.Point(0, 0)
    $inner.Size = New-Object System.Drawing.Size($parent.Width, $contentH)
    $inner.BackColor = $script:cBg
    foreach ($k in $kids) { $inner.Controls.Add($k) }
    $parent.Controls.Add($inner)
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Location = New-Object System.Drawing.Point(($parent.Width - 14), 0)
    $bar.Size = New-Object System.Drawing.Size(12, $viewH)
    $bar.BackColor = $script:cBg
    $bar.Cursor = 'Hand'
    Set-DoubleBuffered $bar
    $parent.Controls.Add($bar)
    $bar.BringToFront()
    $sc = @{ Off = 0; Range = $range; Drag = $false; DragY = 0; DragOff = 0; Hover = $false; ViewH = $viewH; Base = 0; Dlg = $inner; Bar = $bar }
    $bar.Tag = $sc
    $script:setScroll = $sc
    $bar.Add_Paint({
        param($s, $e)
        $sc = $s.Tag
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.Clear($script:cBg)
        $cx = $s.Width / 2.0
        $tr = New-Object System.Drawing.RectangleF([single]($cx - 2), 4, [single]4, [single]($s.Height - 8))
        $tp = New-RoundPath $tr 2
        $tb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, $script:cTrack))
        $g.FillPath($tb, $tp); $tb.Dispose(); $tp.Dispose()
        $t = Get-SetScrollThumb $sc
        $w = [single]6
        if ($sc.Hover -or $sc.Drag) { $w = [single]8 }
        $rect = New-Object System.Drawing.RectangleF([single]($cx - $w / 2), [single]($t.Y + 1), $w, [single]([math]::Max(8, $t.H - 2)))
        $path = New-RoundPath $rect 3
        $c1 = $script:cAccent; $c2 = $script:cPurple
        if ($sc.Drag) { $c1 = $script:cAccentHover; $c2 = $script:cCyan }
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, [single]90)
        $g.FillPath($gb, $path); $gb.Dispose(); $path.Dispose()
    })
    $bar.Add_MouseEnter({ param($s, $e) $s.Tag.Hover = $true; $s.Invalidate() })
    $bar.Add_MouseLeave({ param($s, $e) $s.Tag.Hover = $false; $s.Invalidate() })
    $bar.Add_MouseDown({
        param($s, $e)
        $sc = $s.Tag
        $t = Get-SetScrollThumb $sc
        if ($e.Y -ge $t.Y -and $e.Y -le ($t.Y + $t.H)) { $sc.Drag = $true; $sc.DragY = $e.Y; $sc.DragOff = $sc.Off }
        elseif ($e.Y -lt $t.Y) { Set-SetScroll $sc ($sc.Off - 120) }
        else { Set-SetScroll $sc ($sc.Off + 120) }
        $s.Invalidate()
    })
    $bar.Add_MouseMove({
        param($s, $e)
        $sc = $s.Tag
        if (-not $sc.Drag) { return }
        $t = Get-SetScrollThumb $sc
        $track = [math]::Max(1, $sc.ViewH - $t.H)
        Set-SetScroll $sc ($sc.DragOff + ($e.Y - $sc.DragY) * $sc.Range / $track)
    })
    $bar.Add_MouseUp({ param($s, $e) $s.Tag.Drag = $false; $s.Invalidate() })
    $wheel = { param($s, $e) $sc = $script:setScroll; if ($sc) { Set-SetScroll $sc ($sc.Off - [int]($e.Delta / 120) * 48) } }
    Add-WheelHook $inner $wheel
    $bar.Add_MouseWheel($wheel)
    $parent.Add_MouseWheel($wheel)
    try { $inner.GetType().GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($inner, @([System.Windows.Forms.ControlStyles]::Selectable, $true)) } catch { }
    $inner.TabStop = $true
    $inner.Add_MouseEnter({ try { if (-not ($script:form.ActiveControl -is [System.Windows.Forms.TextBoxBase])) { [void]$script:setScroll.Dlg.Focus() } } catch { } })
}

function Get-SaverCfg($st) {
    $c = @{ Mode = 'match'; Source = 'packs'; Play = 'cycle'; Theme = [string]$st.SaverTheme }
    if ([string]$st.SaverVideoPlay -eq 'loop') { $c.Play = 'loop' }
    if ([string]$st.SaverMode) {
        if ([string]$st.SaverMode -eq 'custom') { $c.Mode = 'custom' }
        if ([string]$st.SaverSource) { $c.Source = [string]$st.SaverSource }
    } else {
        switch ([string]$st.SaverStyle) {
            'photos' { $c.Mode = 'custom'; $c.Source = 'packs' }
            'videos' { $c.Mode = 'custom'; $c.Source = 'videos' }
            'loop'   { $c.Mode = 'custom'; $c.Source = 'videos'; $c.Play = 'loop' }
            'theme'  { $c.Mode = 'custom'; $c.Source = 'theme' }
        }
    }
    return $c
}

# writes the colours of any theme to saver-theme.txt so the screen saver can use that theme's animation
function Write-SaverThemeFile([string]$name) {
    try {
        if (-not $script:Themes.ContainsKey($name)) { return }
        $t = $script:Themes[$name]
        $rgb = { param($x) ("{0},{1},{2}" -f [int]$x[0], [int]$x[1], [int]$x[2]) }
        $letters = $t.Cyan
        if ($t.Light) { $letters = $t.Text }
        $ok = @(120, 255, 190); if ($t.ContainsKey('Ok')) { $ok = $t.Ok }
        $lines = @(
            ("bgTop=" + (& $rgb $t.Panel2)), ("bgBottom=" + (& $rgb $t.Bg)),
            ("edge=" + (& $rgb $t.Accent)), ("sunTop=" + (& $rgb $t.Sun)), ("sunBottom=" + (& $rgb $t.Accent)),
            ("letters=" + (& $rgb $letters)), ("zero=" + (& $rgb $t.Accent)), ("sub=" + (& $rgb $t.Dim)),
            ("bar1=" + (& $rgb $t.Accent)), ("bar2=" + (& $rgb $t.Cyan)), ("cut=" + (& $rgb $t.Bg)),
            ("font=" + (Get-FirstFont $t.TFonts 'Arial Black')),
            ("text=" + (& $rgb $t.Text)), ("light=" + $(if ($t.Light) { '1' } else { '0' })),
            ("style=" + $name.ToLowerInvariant().Replace("digital rain", "matrix")),
            ("nosplash=1"),
            ("accent=" + (& $rgb $t.Accent)), ("cyan=" + (& $rgb $t.Cyan)), ("purple=" + (& $rgb $t.Purple)),
            ("orange=" + (& $rgb $t.Orange)), ("sun=" + (& $rgb $t.Sun)), ("ok=" + (& $rgb $ok))
        )
        Set-Content -LiteralPath (Join-Path $PSScriptRoot ('saver-theme-' + ($name -replace '\s', '') + '.txt')) -Value $lines -Encoding ASCII
    } catch { }
}

# the pop-out's preview panel registers itself here; every saver control calls this after a change
$script:saverPrevPanel = $null
function Invoke-SaverChanged {
    try { if ($script:saverPrevPanel -and -not $script:saverPrevPanel.IsDisposed) { $script:saverPrevPanel.Invalidate() } } catch { }
}

function Invoke-SaverPreviewPaint($panel, $e) {
    $ps = $script:packSaverState
    if (-not $ps) { return }
    $g = $e.Graphics
    $fs = New-Object System.Drawing.Font("Segoe UI", 8)
    $w = $panel.ClientSize.Width; $h = $panel.ClientSize.Height
    $cap = ''
    $secs = [int]$ps.Secs
    if ($secs -le 0) { $secs = 30; try { if ((Get-Settings).ScreensaverSeconds) { $secs = [int](Get-Settings).ScreensaverSeconds } } catch { } }
    if ($ps.Type -eq 'pack') {
        if (-not $ps.Include) { $cap = "$($ps.Pack) - left out of the screen saver" }
        else { $cap = "$($ps.Pack) - pictures, $secs s, pan/zoom $($ps.Motion)" }
        Invoke-MapPaint $panel $e
    } else {
        $full = New-Object System.Drawing.RectangleF(0, 0, $w, $h)
        $bgb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full, $script:cDlgA, $script:cDlgB, [single]90)
        $g.FillRectangle($bgb, $full); $bgb.Dispose()
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $tb = New-Object System.Drawing.SolidBrush($script:cText)
        $db = New-Object System.Drawing.SolidBrush($script:cDim)
        if ($ps.Type -eq 'video') {
            if ($ps.Video) { $cap = "$($ps.Pack) - video: $($ps.Video), $secs s" } else { $cap = "$($ps.Pack) - no video chosen yet" }
            $big = New-Object System.Drawing.Font("Segoe UI", 30, [System.Drawing.FontStyle]::Bold)
            $g.DrawString([string][char]0x25B6, $big, $tb, [single]($w / 2 - 26), [single]($h / 2 - 44))
            $big.Dispose()
            $g.DrawString("Plays muted, full screen on every monitor", $fs, $db, 16, 16)
        } else {
            $tn = [string]$ps.Theme
            $cap = "$($ps.Pack) - $tn animation, $secs s"
            if ($tn -and $script:Themes.ContainsKey($tn)) {
                $t2 = $script:Themes[$tn]
                $mk = { param($a) [System.Drawing.Color]::FromArgb([int]$a[0], [int]$a[1], [int]$a[2]) }
                $r = New-Object System.Drawing.RectangleF(10, 10, ($w - 20), ($h - 50))
                $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, (& $mk $t2.Panel2), (& $mk $t2.Bg), [single]90)
                $g.FillRectangle($gb, $r); $gb.Dispose()
                for ($i = 0; $i -lt 6; $i++) {
                    if ($i % 2) { $col = $t2.Accent } else { $col = $t2.Cyan }
                    $pb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, (& $mk $col)))
                    $g.FillRectangle($pb, [single](24 + $i * 62), [single]($h - 90 - ($i * 9 % 40)), 36, [single](24 + ($i * 9 % 40)))
                    $pb.Dispose()
                }
                $f2 = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
                $nb = New-Object System.Drawing.SolidBrush((& $mk $t2.Text))
                $g.DrawString($tn, $f2, $nb, 24, 20)
                $f2.Dispose(); $nb.Dispose()
            } else { $g.DrawString("Pick a theme", $fs, $db, 16, 16); $cap = "$($ps.Pack) - no theme chosen yet" }
        }
        $tb.Dispose(); $db.Dispose()
    }
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $strip = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190, 0, 0, 0))
    $g.FillRectangle($strip, 0, ($h - 28), $w, 28)
    $strip.Dispose()
    $cb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.DrawString($cap, $fs, $cb, 8, ($h - 24))
    $cb.Dispose()
    $pen = New-Object System.Drawing.Pen($script:cCyan, 1)
    $g.DrawRectangle($pen, 0, 0, ($w - 1), ($h - 1))
    $pen.Dispose()
    $fs.Dispose()
}
$script:packSaverState = $null

function Add-LockControls($dlg, [int]$y0) {
    $stL = Get-Settings
    $dlg.Controls.Add((New-Heading "Lock screen" 24 $y0 300))
    $dlg.Controls.Add((New-HelpButton 436 ($y0 - 2) "Lock screen" "Mode:`n- Match Packs: the lock screen follows the pack in use, with the lock screen options saved with that pack (use the Lock screen button in the Builder).`n- Custom: one lock screen for every pack, set here.`n`nCustom can be Windows' default lock screen or a picture you choose. The change happens the next time a pack is applied."))
    $dlg.Controls.Add((New-Label "Mode" 24 ($y0 + 36) 130 22 $true 9))
    $cmbLMode = New-StyledCombo 160 ($y0 + 32) 286
    foreach ($o in @("Match Packs", "Custom")) { [void]$cmbLMode.Items.Add($o) }
    $cmbLMode.SelectedIndex = $(if ([string]$stL.LockMode -eq 'custom') { 1 } else { 0 })
    $dlg.Controls.Add($cmbLMode)
    $lblLNote = New-Label "The lock screen follows the pack in use, using the options saved with that pack." 24 ($y0 + 72) 422 40 $true 9
    $dlg.Controls.Add($lblLNote)
    $lblLSrc = New-Label "Picture" 24 ($y0 + 72) 130 22 $true 9
    $cmbLSrc = New-StyledCombo 160 ($y0 + 68) 286
    foreach ($o in @("Windows Default", "My Own Picture")) { [void]$cmbLSrc.Items.Add($o) }
    $cmbLSrc.SelectedIndex = $(if ([string]$stL.LockCustom -eq 'picture') { 1 } else { 0 })
    $btnLPic = New-Btn "Choose Picture..." 160 ($y0 + 102) 190 'normal' 30
    $btnLPic.Font = Get-RetroFont 8
    $lblLFile = New-Label "" 24 ($y0 + 138) 422 22 $true 9
    foreach ($c in @($lblLSrc, $cmbLSrc, $btnLPic, $lblLFile)) { $dlg.Controls.Add($c) }
    $upd = {
        $custom = ($cmbLMode.SelectedIndex -eq 1)
        $lblLNote.Visible = (-not $custom)
        $lblLSrc.Visible = $custom; $cmbLSrc.Visible = $custom
        $pic = ($custom -and $cmbLSrc.SelectedIndex -eq 1)
        $btnLPic.Visible = $pic; $lblLFile.Visible = $pic
        $f = [string](Get-Settings).LockPic
        $lblLFile.Text = $(if ($f) { [IO.Path]::GetFileName($f) } else { "No picture chosen yet." })
    }.GetNewClosure()
    & $upd
    $cmbLMode.Add_SelectedIndexChanged({ Save-Setting 'LockMode' $(if ($cmbLMode.SelectedIndex -eq 1) { 'custom' } else { 'match' }); & $upd }.GetNewClosure())
    $cmbLSrc.Add_SelectedIndexChanged({ Save-Setting 'LockCustom' $(if ($cmbLSrc.SelectedIndex -eq 1) { 'picture' } else { 'default' }); & $upd }.GetNewClosure())
    $btnLPic.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Title = "Pick a lock screen picture"
        $d.Filter = "Pictures|*.jpg;*.jpeg;*.png;*.bmp|All files|*.*"
        if ($d.ShowDialog() -eq 'OK') { Save-Setting 'LockPic' $d.FileName; & $upd }
    }.GetNewClosure())
}

function Add-SaverControls($dlg, $st) {
    $cfg = Get-SaverCfg $st
    $dlg.Controls.Add((New-Heading "Screen saver" 24 16 300))
    $dlg.Controls.Add((New-HelpButton 436 14 "Screen saver" "Mode:`n- Match Packs: the screen saver plays the pack in use, with the screen saver options saved with that pack (use the Screen saver button in the Builder to set them).`n- Custom: one screen saver for everything, whatever pack is in use.`n`nCustom sources:`n- Pack Media: your wallpaper packs (all, favorites, tags or one pack), fading from one to the next. Panoramas can slowly pan and zoom.`n- Pictures: pictures you choose.`n- Videos: videos from the Animated tab, cycled or looped.`n- Theme Animation: the animation of any theme, whatever theme the app uses.`n`nAny key or mouse move ends the screen saver. Windows starts it after the idle time below."))

    $dlg.Controls.Add((New-Label "Mode" 24 52 130 22 $true 9))
    $cmbMode = New-StyledCombo 160 48 286
    foreach ($o in @("Match Packs", "Custom")) { [void]$cmbMode.Items.Add($o) }
    $cmbMode.SelectedIndex = $(if ($cfg.Mode -eq 'custom') { 1 } else { 0 })
    $dlg.Controls.Add($cmbMode)
    $lblNote = New-Label "The pack in use plays with the screen saver options saved with it. Set them per pack with the Screen saver button in the Builder." 24 90 422 60 $true 9
    $dlg.Controls.Add($lblNote)
    $lblSrc = New-Label "Source" 24 90 130 22 $true 9
    $cmbSource = New-StyledCombo 160 86 286
    $srcKeys = @('packs', 'pictures', 'videos', 'theme')
    foreach ($o in @("Pack Media", "Pictures", "Videos", "Theme Animation")) { [void]$cmbSource.Items.Add($o) }
    $cmbSource.SelectedIndex = [math]::Max(0, [array]::IndexOf($srcKeys, $cfg.Source))
    $dlg.Controls.Add($lblSrc); $dlg.Controls.Add($cmbSource)

    # options that follow the source
    $lblSec = New-Label "Change Every" 24 130 130 22 $true 9
    $numSec = New-NeonSpin 160 128 70 5 3600 0 5
    $v = 30; try { if ($st.ScreensaverSeconds) { $v = [int]$st.ScreensaverSeconds } } catch { }
    $numSec.Value = [decimal][math]::Max(5, [math]::Min(3600, $v))
    $lblSecs = New-Label "seconds" 238 130 90 22 $true 9
    $numSec.Add_ValueChanged({ Save-Setting 'ScreensaverSeconds' ([string][int]$numSec.Value); Invoke-SaverChanged }.GetNewClosure())
    $script:btnSaverSrc = New-Btn ("Packs: " + (Get-SaverSourceText)) 24 162 300 'normal' 30
    $script:btnSaverSrc.Font = Get-RetroFont 8
    $script:btnSaverSrc.Add_Click({ Show-SaverSourceMenu $script:btnSaverSrc })
    $btnSrc = $script:btnSaverSrc

    $btnPics = New-Btn "Pictures..." 24 162 200 'normal' 30
    $btnPics.Font = Get-RetroFont 8
    $btnPicsClear = New-Btn "Clear" 232 162 92 'normal' 30
    $btnPicsClear.Font = Get-RetroFont 8
    $lblPics = New-Label "" 332 168 120 22 $true 8
    $updPics = { $n = @(([string](Get-Settings).SaverPics -split '\|') | Where-Object { $_.Trim() }).Count; $lblPics.Text = "$n chosen" }.GetNewClosure()
    $btnPics.Add_Click({
        $d = New-Object System.Windows.Forms.OpenFileDialog
        $d.Filter = "Pictures|*.jpg;*.jpeg;*.png;*.bmp;*.gif"
        $d.Multiselect = $true
        if ($d.ShowDialog() -eq 'OK' -and $d.FileNames.Count -gt 0) { Save-Setting 'SaverPics' ($d.FileNames -join '|'); & $updPics; Invoke-SaverChanged }
    }.GetNewClosure())
    $btnPicsClear.Add_Click({ Save-Setting 'SaverPics' ''; & $updPics; Invoke-SaverChanged }.GetNewClosure())
    & $updPics

    $btnVids = New-Btn "Videos..." 24 162 200 'normal' 30
    $btnVids.Font = Get-RetroFont 8
    $btnVids.Add_Click({ Show-SaverVideoPicker; Invoke-SaverChanged })
    $lblPlay = New-Label "Play" 24 130 130 22 $true 9
    $cmbPlay = New-StyledCombo 160 126 286
    foreach ($o in @("Cycle Videos", "Loop First Video")) { [void]$cmbPlay.Items.Add($o) }
    $cmbPlay.SelectedIndex = $(if ($cfg.Play -eq 'loop') { 1 } else { 0 })
    $cmbPlay.Add_SelectedIndexChanged({ Save-Setting 'SaverVideoPlay' $(if ($cmbPlay.SelectedIndex -eq 1) { 'loop' } else { 'cycle' }); Invoke-SaverChanged }.GetNewClosure())

    $lblTheme = New-Label "Theme" 24 130 130 22 $true 9
    $cmbTheme = New-StyledCombo 160 126 286
    [void]$cmbTheme.Items.Add("Current Theme")
    foreach ($tn in $script:ThemeNames) { if ($tn -ne 'Wallpaper') { [void]$cmbTheme.Items.Add($tn) } }
    $curTheme = [string]$st.SaverTheme
    if ($curTheme -and $cmbTheme.Items.Contains($curTheme)) { $cmbTheme.SelectedItem = $curTheme } else { $cmbTheme.SelectedIndex = 0 }
    $cmbTheme.Add_SelectedIndexChanged({
        if ($cmbTheme.SelectedIndex -le 0) { Save-Setting 'SaverTheme' '' }
        else { $nm = [string]$cmbTheme.SelectedItem; Write-SaverThemeFile $nm; Save-Setting 'SaverTheme' $nm }
        Invoke-SaverChanged
    }.GetNewClosure())

    $chkMotion = New-NeonCheck "Slow Pan/Zoom On Panoramas" 24 198 340 28
    $chkMotion.Checked = ([string]$st.SaverMotion -ne '0')
    $chkMotion.Add_CheckedChanged({ Save-Setting 'SaverMotion' $(if ($chkMotion.Checked) { '1' } else { '0' }); Invoke-SaverChanged }.GetNewClosure())

    foreach ($c in @($lblSec, $numSec, $lblSecs, $btnSrc, $btnPics, $btnPicsClear, $lblPics, $btnVids, $lblPlay, $cmbPlay, $lblTheme, $cmbTheme, $chkMotion)) { $dlg.Controls.Add($c) }

    $syncMode = {
        $custom = ($cmbMode.SelectedIndex -eq 1)
        $k = $srcKeys[[math]::Max(0, $cmbSource.SelectedIndex)]
        $lblNote.Visible = (-not $custom)
        $lblSrc.Visible = $custom; $cmbSource.Visible = $custom
        $timed = $custom -and ($k -eq 'packs' -or $k -eq 'pictures')
        $lblSec.Visible = $timed; $numSec.Visible = $timed; $lblSecs.Visible = $timed
        $chkMotion.Visible = $timed
        $btnSrc.Visible = ($custom -and $k -eq 'packs')
        $btnPics.Visible = ($custom -and $k -eq 'pictures'); $btnPicsClear.Visible = $btnPics.Visible; $lblPics.Visible = $btnPics.Visible
        $btnVids.Visible = ($custom -and $k -eq 'videos'); $lblPlay.Visible = $btnVids.Visible; $cmbPlay.Visible = $btnVids.Visible
        $lblTheme.Visible = ($custom -and $k -eq 'theme'); $cmbTheme.Visible = $lblTheme.Visible
    }.GetNewClosure()
    $cmbMode.Add_SelectedIndexChanged({
        Save-Setting 'SaverMode' $(if ($cmbMode.SelectedIndex -eq 1) { 'custom' } else { 'match' })
        Save-Setting 'SaverSource' $srcKeys[[math]::Max(0, $cmbSource.SelectedIndex)]
        & $syncMode; Invoke-SaverChanged
    }.GetNewClosure())
    $cmbSource.Add_SelectedIndexChanged({
        Save-Setting 'SaverSource' $srcKeys[[math]::Max(0, $cmbSource.SelectedIndex)]
        & $syncMode; Invoke-SaverChanged
    }.GetNewClosure())
    & $syncMode
    $tt.SetToolTip($cmbMode, "Match Packs: each pack's own screen saver options. Custom: one screen saver for everything.")
    $tt.SetToolTip($cmbSource, "What the custom screen saver plays")
    $tt.SetToolTip($btnVids, "Choose which videos from the Animated tab to play (none ticked = all of them)")
    $tt.SetToolTip($btnPics, "Choose the pictures to show (wide ones pan and zoom like panoramas)")
    $tt.SetToolTip($chkMotion, "Slowly pans and zooms panorama pictures. Ordinary pictures stay still.")

    $dlg.Controls.Add((New-Label "Start After Idle For" 24 238 190 22 $true 9))
    $numIdle = New-NeonSpin 220 236 70 1 240 0 1
    $idleMin = 5
    try { $t = (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveTimeOut -ErrorAction Stop).ScreenSaveTimeOut; if ([int]$t -ge 60) { $idleMin = [int]($t / 60) } } catch { }
    $numIdle.Value = [decimal][math]::Max(1, [math]::Min(240, $idleMin))
    $dlg.Controls.Add($numIdle)
    $dlg.Controls.Add((New-Label "minutes" 296 238 90 22 $true 9))

    $chkUse = New-NeonCheck "Use This Screen Saver" 24 272 300 28
    $cur = ''; try { $cur = [string](Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'SCRNSAVE.EXE' -ErrorAction Stop).'SCRNSAVE.EXE' } catch { }
    $chkUse.Checked = ($cur -and ([System.IO.Path]::GetFileName($cur) -ieq 'Ekk0h.scr'))
    $dlg.Controls.Add($chkUse)
    $chkLock = New-NeonCheck "Ask For My Password When It Ends" 24 302 340 28
    $sec = '0'; try { $sec = [string](Get-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'ScreenSaverIsSecure' -ErrorAction Stop).ScreenSaverIsSecure } catch { }
    $chkLock.Checked = ($sec -eq '1')
    $dlg.Controls.Add($chkLock)

    $lblSaver = New-Label "" 24 332 420 22 $true 9
    $dlg.Controls.Add($lblSaver)
    $applySaver = {
        $k = 'HKCU:\Control Panel\Desktop'
        try {
            if ($chkUse.Checked) {
                $saver = Get-SaverPath
                if (-not $saver) {
                    $chkUse.Checked = $false
                    $lblSaver.Text = "The screen saver file isn't available in this copy."
                    return
                }
                Set-ItemProperty -Path $k -Name 'SCRNSAVE.EXE' -Value $saver
                Set-ItemProperty -Path $k -Name 'ScreenSaveActive' -Value '1'
                Set-ItemProperty -Path $k -Name 'ScreenSaveTimeOut' -Value ([string]([int]$numIdle.Value * 60))
                Set-ItemProperty -Path $k -Name 'ScreenSaverIsSecure' -Value $(if ($chkLock.Checked) { '1' } else { '0' })
                try { [SaverSys]::Apply($true, ([int]$numIdle.Value * 60)) } catch { }
                $lblSaver.Text = "Saved. It starts after {0} idle minute(s)." -f [int]$numIdle.Value
            } else {
                Set-ItemProperty -Path $k -Name 'ScreenSaveActive' -Value '0'
                try { [SaverSys]::Apply($false, ([int]$numIdle.Value * 60)) } catch { }
                $lblSaver.Text = "Screen saver turned off."
            }
        } catch { $lblSaver.Text = "Couldn't change that setting: " + $_.Exception.Message }
    }.GetNewClosure()
    $chkUse.Add_CheckedChanged($applySaver)
    $chkLock.Add_CheckedChanged({ if ($chkUse.Checked) { & $applySaver } }.GetNewClosure())
    $numIdle.Add_ValueChanged({ if ($chkUse.Checked) { & $applySaver } }.GetNewClosure())

    $btnPrev = New-Btn "Preview" 24 362 120 'normal' 30
    $btnPrev.Add_Click({
        $saver = Get-SaverPath
        if ($saver) { Start-Process -FilePath $saver -ArgumentList "/s" }
        else { $lblSaver.Text = "The screen saver file isn't available in this copy." }
    }.GetNewClosure())
    $dlg.Controls.Add($btnPrev)
}

function Build-SettingsContent($parent) {
    $st = Get-Settings
    $hasBat = Test-HasBattery
    $dlg = New-Object System.Windows.Forms.Panel
    $dlg.Location = New-Object System.Drawing.Point(0, -14)
    $dlg.BackColor = $script:cBg
    $dlg.Size = New-Object System.Drawing.Size(470, $(if ($hasBat) { 830 } else { 740 }))
    $parent.Controls.Add($dlg)

    Add-SaverControls $dlg $st
    Add-LockControls $dlg 420

    # ---- power and display
    $y = 550
    $dlg.Controls.Add((New-Heading "Power and display" 24 $y 300))
    $dlg.Controls.Add((New-HelpButton 436 ($y - 2) "Power and display" "These change your Windows power plan, the same settings as Settings > System > Power.`n`n'Turn off the display' blanks the screens after that much idle time. 'Put the PC to sleep' is Windows sleep mode; choose Never to turn it off.`n`nThe buttons below open the matching Windows settings pages."))
    $y += 38
    $dlg.Controls.Add((New-Label "Turn Off The Display" 24 ($y + 2) 190 22 $true 9))
    $dlg.Controls.Add((New-PowerCombo 220 $y 'SUB_VIDEO' 'VIDEOIDLE' 'monitor' $true))
    if ($hasBat) {
        $dlg.Controls.Add((New-Label "...On Battery" 24 ($y + 36) 190 22 $true 9))
        $dlg.Controls.Add((New-PowerCombo 220 ($y + 34) 'SUB_VIDEO' 'VIDEOIDLE' 'monitor' $false))
        $y += 34
    }
    $y += 38
    $dlg.Controls.Add((New-Label "Put The PC To Sleep" 24 ($y + 2) 190 22 $true 9))
    $dlg.Controls.Add((New-PowerCombo 220 $y 'SUB_SLEEP' 'STANDBYIDLE' 'standby' $true))
    if ($hasBat) {
        $dlg.Controls.Add((New-Label "...On Battery" 24 ($y + 36) 190 22 $true 9))
        $dlg.Controls.Add((New-PowerCombo 220 ($y + 34) 'SUB_SLEEP' 'STANDBYIDLE' 'standby' $false))
        $y += 34
    }
    $y += 50
    $links = @(
        @("Display", "ms-settings:display"), @("Power & sleep", "ms-settings:powersleep"),
        @("Lock screen", "ms-settings:lockscreen"), @("Night light", "ms-settings:nightlight"))
    $bx = 24
    foreach ($l in $links) {
        $b = New-Btn $l[0] $bx $y 102 'normal' 30
        $b.Font = Get-RetroFont 8
        $b.Tag.Url = $l[1]
        $b.Add_Click({ param($s, $e) try { Start-Process ([string]$s.Tag.Url) } catch { } })
        $dlg.Controls.Add($b)
        $bx += 108
    }

    $btnAbout = New-Btn "About, updates and backup..." 24 ($y + 40) 300 'normal' 30
    $btnAbout.Font = Get-RetroFont 8
    $btnAbout.Add_Click({ Show-AboutDialog })
    $dlg.Controls.Add($btnAbout)

    $btnSaveSet = New-Btn "SAVE SETTINGS" 24 ($y + 84) 300 'primary' 34
    $btnSaveSet.Add_Click({
        try { Invoke-SaverChanged } catch { }
        Set-Status "Settings saved."
        if ($script:activeTab -eq 4) { Switch-Tab $script:prevTab }
    })
    $dlg.Controls.Add($btnSaveSet)

    $dlg.Size = New-Object System.Drawing.Size(470, ($y + 84 + 34 + 40))
    Add-SettingsScroll $parent $dlg -14
}

# gear in the header: opens (or closes) the Settings page
function Show-SettingsWindow {
    if ($script:activeTab -eq 4) { Switch-Tab $script:prevTab }
    else { $script:prevTab = $script:activeTab; Switch-Tab 4 }
}

function Show-SaverDialog {
    $pk = [string]$script:btPack
    if (-not $pk) { Set-Status "Save this pack first (give it a name and press Save), then set its screen saver."; return }
    $o = Get-PackSaver $pk
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Screen Saver"
    $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    $f.BackColor = $script:cBg; $f.ForeColor = $script:cText
    $f.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    if ($script:appIcon) { $f.Icon = $script:appIcon }
    $f.Add_HandleCreated({ param($s, $e) Set-TitleBar $s.Handle })
    $f.ClientSize = New-Object System.Drawing.Size(960, 360)

    $typeKeys = @('pack', 'video', 'theme')
    $ps = @{ Pack = $pk; Type = $o.type; Video = $o.video; Theme = $o.theme; Secs = $o.seconds; Motion = $o.motion; Include = [bool]$o.include }
    $script:packSaverState = $ps

    $f.Controls.Add((New-Heading "Screen saver" 24 16 436))
    $f.Controls.Add((New-HelpButton 436 14 "Pack screen saver" "These options belong to this pack. They are used when the screen saver mode on the Settings tab is Match Packs. Custom mode on the Settings tab ignores them.`n`nPlays: Pack Media shows this pack's pictures (panoramas can slowly pan and zoom). Video plays a video from the Animated tab. Theme Animation plays a theme's animation.`n`nSeconds On Screen: how long this pack stays before the next one (0 = the Settings tab value)."))
    $f.Controls.Add((New-Label $pk 24 40 436 22 $true 10))

    $f.Controls.Add((New-Heading "Plays" 24 82 436))
    $cmbType = New-StyledCombo 24 106 422
    foreach ($x in @("Pack Media", "Video", "Theme Animation")) { [void]$cmbType.Items.Add($x) }
    $cmbType.SelectedIndex = [math]::Max(0, [array]::IndexOf($typeKeys, [string]$o.type))
    $f.Controls.Add($cmbType)

    $f.Controls.Add((New-Heading "Options" 24 154 436))
    $f.Controls.Add((New-Label "Seconds On Screen" 24 186 160 22 $true 9))
    $numS = New-NeonSpin 190 184 80 0 3600 0 5
    $numS.Value = [decimal][math]::Max(0, [math]::Min(3600, [int]$o.seconds))
    $f.Controls.Add($numS)
    $f.Controls.Add((New-Label "0 = Settings Tab Value" 282 188 170 22 $true 8))

    $lblM = New-Label "Slow Pan/Zoom" 24 226 160 22 $true 9
    $cmbM = New-StyledCombo 190 222 256
    foreach ($x in @("Auto", "On", "Off")) { [void]$cmbM.Items.Add($x) }
    $cmbM.SelectedItem = (Get-Culture).TextInfo.ToTitleCase([string]$o.motion)
    if ($cmbM.SelectedIndex -lt 0) { $cmbM.SelectedIndex = 0 }

    $lblV = New-Label "Video" 24 226 160 22 $true 9
    $cmbV = New-StyledCombo 190 222 256
    foreach ($v in @(Get-AnimatedFiles)) {
        $ext = [IO.Path]::GetExtension($v.Name).ToLower()
        if ($ext -eq '.mp4' -or $ext -eq '.m4v' -or $ext -eq '.mov') { [void]$cmbV.Items.Add($v.Name) }
    }
    if ($o.video -and $cmbV.Items.Contains([string]$o.video)) { $cmbV.SelectedItem = [string]$o.video } elseif ($cmbV.Items.Count -gt 0) { $cmbV.SelectedIndex = 0 }

    $lblT = New-Label "Theme" 24 226 160 22 $true 9
    $cmbT = New-StyledCombo 190 222 256
    foreach ($tn in $script:ThemeNames) { if ($tn -ne 'Wallpaper') { [void]$cmbT.Items.Add($tn) } }
    if ($o.theme -and $cmbT.Items.Contains([string]$o.theme)) { $cmbT.SelectedItem = [string]$o.theme } else { $cmbT.SelectedIndex = 0 }
    foreach ($c in @($lblM, $cmbM, $lblV, $cmbV, $lblT, $cmbT)) { $f.Controls.Add($c) }

    $chkInc = New-NeonCheck "Include In Screen Saver" 24 264 300 28
    $chkInc.Checked = [bool]$o.include
    $f.Controls.Add($chkInc)

    $pv = New-Object System.Windows.Forms.Panel
    $pv.Location = New-Object System.Drawing.Point(500, 46)
    $pv.Size = New-Object System.Drawing.Size(436, 260)
    $pv.Tag = $pk
    Set-DoubleBuffered $pv
    $pv.Add_Paint({ param($s, $e) Invoke-SaverPreviewPaint $s $e })
    $f.Controls.Add((New-Heading "Preview" 500 16 436))
    $f.Controls.Add($pv)
    $script:saverPrevPanel = $pv

    $sync = {
        $ps.Type = $typeKeys[[math]::Max(0, $cmbType.SelectedIndex)]
        $ps.Secs = [int]$numS.Value
        $ps.Motion = $cmbM.SelectedItem.ToString().ToLower()
        $ps.Video = [string]$cmbV.SelectedItem
        $ps.Theme = [string]$cmbT.SelectedItem
        $ps.Include = [bool]$chkInc.Checked
        $lblM.Visible = ($ps.Type -eq 'pack'); $cmbM.Visible = $lblM.Visible
        $lblV.Visible = ($ps.Type -eq 'video'); $cmbV.Visible = $lblV.Visible
        $lblT.Visible = ($ps.Type -eq 'theme'); $cmbT.Visible = $lblT.Visible
        $pv.Invalidate()
    }.GetNewClosure()
    $cmbType.Add_SelectedIndexChanged($sync); $cmbM.Add_SelectedIndexChanged($sync); $cmbV.Add_SelectedIndexChanged($sync); $cmbT.Add_SelectedIndexChanged($sync)
    $numS.Add_ValueChanged($sync); $chkInc.Add_CheckedChanged($sync)
    & $sync

    $ok = New-Btn "Save" 24 308 120 'cyan' 32
    $cancel = New-Btn "Cancel" 152 308 120 'normal' 32
    $f.Controls.Add($ok); $f.Controls.Add($cancel)
    $ok.Tag.Dlg = $f; $cancel.Tag.Dlg = $f
    $ok.Add_Click({
        param($s, $e)
        $d = $s.Tag.Dlg
        $p = $script:packSaverState
        if ($p.Type -eq 'theme' -and $p.Theme) { Write-SaverThemeFile ([string]$p.Theme) }
        Set-PackSaver $p.Pack @{ include = $p.Include; seconds = $p.Secs; motion = $p.Motion; type = $p.Type; video = $p.Video; theme = $p.Theme }
        $d.Close()
    })
    $cancel.Add_Click({ param($s, $e) $s.Tag.Dlg.Close() })
    try { [void]$f.ShowDialog($script:form) } finally { $script:saverPrevPanel = $null; $script:packSaverState = $null; $f.Dispose() }
}

function Show-SaverVideoPicker {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Screen Saver Videos"
    $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    $f.BackColor = $script:cBg; $f.ForeColor = $script:cText
    $f.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    if ($script:appIcon) { $f.Icon = $script:appIcon }
    $f.Add_HandleCreated({ param($s, $e) Set-TitleBar $s.Handle })
    $f.ClientSize = New-Object System.Drawing.Size(440, 420)
    $f.Controls.Add((New-Heading "Videos" 24 14 392))
    $f.Controls.Add((New-Label "Click videos to select them. Nothing selected = all of them. Loop repeats the first one. The saver plays mp4, m4v and mov files." 24 44 392 40 $true 9))
    $clb = New-StyledList 24 90 392 250
    $clb.SelectionMode = 'MultiSimple'
    $f.Controls.Add($clb)
    Add-ThemedScroll $clb $f
    $picked = @(([string](Get-Settings).ScreensaverVideos -split '\|') | Where-Object { $_.Trim() })
    foreach ($v in @(Get-AnimatedFiles)) {
        $ext = [IO.Path]::GetExtension($v.Name).ToLower()
        if ($ext -eq '.mp4' -or $ext -eq '.m4v' -or $ext -eq '.mov') {
            $ix = $clb.Items.Add($v.Name)
            if ($picked -contains $v.Name) { $clb.SetSelected($ix, $true) }
        }
    }
    Sync-ThemedBar $clb
    $msg = New-Label "" 24 346 392 22 $true 9
    if ($clb.Items.Count -eq 0) { $msg.Text = "No mp4 videos in the Animated tab yet." }
    $f.Controls.Add($msg)
    $ok = New-Btn "Save" 24 374 120 'cyan' 32
    $cancel = New-Btn "Cancel" 152 374 120 'normal' 32
    $f.Controls.Add($ok); $f.Controls.Add($cancel)
    $f.Tag = @{ List = $clb }
    $ok.Tag.Dlg = $f; $cancel.Tag.Dlg = $f
    $ok.Add_Click({
        param($s, $e)
        $d = $s.Tag.Dlg
        $names = @(); foreach ($i in $d.Tag.List.SelectedItems) { $names += [string]$i }
        Save-Setting 'ScreensaverVideos' ($names -join '|')
        $d.Close()
    })
    $cancel.Add_Click({ param($s, $e) $s.Tag.Dlg.Close() })
    try { [void]$f.ShowDialog($script:form) } finally { $f.Dispose() }
}
# ---------------------------------------------------------------- first-run setup wizard
# Five short pages: welcome, theme, optional add-ons, startup options, finish. Runs once on first launch
# (and again from Settings > About). It reuses the same add-on rows and options as the Settings page.
function New-WizCard([int]$x, [int]$y, [int]$w, [int]$h, [string]$kind, [string]$title, [string]$text) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $script:cBg
    $p.Tag = @{ Kind = $kind; Title = $title; Text = $text }
    Set-DoubleBuffered $p
    $p.Add_Paint({
        param($s, $e)
        $kind = [string]$s.Tag.Kind; $title = [string]$s.Tag.Title; $text = [string]$s.Tag.Text
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
        $rc = New-Object System.Drawing.RectangleF(1, 1, ($s.Width - 3), ($s.Height - 3))
        $path = New-RoundPath $rc 10
        $b1 = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)), $script:cPanel2, $script:cPanel, [single]90)
        $g.FillPath($b1, $path); $b1.Dispose()
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, $script:cCyan), 1.5)
        $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
        $ac = New-Object System.Drawing.SolidBrush($script:cAccent)
        $cy = New-Object System.Drawing.SolidBrush($script:cCyan)
        $pu = New-Object System.Drawing.SolidBrush($script:cPurple)
        $cx = [single]($s.Width / 2)
        if ($kind -eq 'packs') {
            $g.FillRectangle($pu, ($cx - 30), 30, 40, 28); $g.FillRectangle($cy, ($cx - 22), 24, 40, 28); $g.FillRectangle($ac, ($cx - 14), 18, 40, 28)
        } elseif ($kind -eq 'screens') {
            $g.FillRectangle($pu, ($cx - 46), 28, 28, 22); $g.FillRectangle($ac, ($cx - 14), 22, 28, 22); $g.FillRectangle($cy, ($cx + 18), 28, 28, 22)
            $g.FillRectangle($ac, ($cx - 4), 44, 8, 6)
        } else {
            $g.FillEllipse($ac, ($cx - 24), 16, 48, 48)
            $tri = [System.Drawing.PointF[]]@((New-Object System.Drawing.PointF(($cx - 7), 28)), (New-Object System.Drawing.PointF(($cx - 7), 52)), (New-Object System.Drawing.PointF(($cx + 13), 40)))
            $wb = New-Object System.Drawing.SolidBrush($script:cBg); $g.FillPolygon($wb, $tri); $wb.Dispose()
        }
        $ac.Dispose(); $cy.Dispose(); $pu.Dispose()
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Center'
        $tb = New-Object System.Drawing.SolidBrush($script:cText)
        $db = New-Object System.Drawing.SolidBrush($script:cDim)
        $g.DrawString($title, (Get-RetroFont 11), $tb, (New-Object System.Drawing.RectangleF(8, 78, ($s.Width - 16), 24)), $sf)
        $g.DrawString($text, (New-Object System.Drawing.Font("Segoe UI", 9)), $db, (New-Object System.Drawing.RectangleF(12, 106, ($s.Width - 24), 70)), $sf)
        $tb.Dispose(); $db.Dispose(); $sf.Dispose()
    })
    return $p
}

function New-ThemeTile([string]$name, [int]$x, [int]$y, [int]$w, [int]$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $script:cBg
    $p.Cursor = [System.Windows.Forms.Cursors]::Hand
    $p.Tag = @{ Name = $name }
    Set-DoubleBuffered $p
    $p.Add_Paint({
        param($s, $e)
        $name = [string]$s.Tag.Name
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
        $t = $script:Themes[$name]
        $c1 = [System.Drawing.Color]::FromArgb(40, 40, 52); $c2 = [System.Drawing.Color]::FromArgb(90, 90, 110)
        $a = $script:cAccent; $b = $script:cCyan; $tx = [System.Drawing.Color]::White
        if ($t -and $t.Bg -and $t.Panel2) {
            $c1 = [System.Drawing.Color]::FromArgb($t.Bg[0], $t.Bg[1], $t.Bg[2]); $c2 = [System.Drawing.Color]::FromArgb($t.Panel2[0], $t.Panel2[1], $t.Panel2[2])
            $a = [System.Drawing.Color]::FromArgb($t.Accent[0], $t.Accent[1], $t.Accent[2]); $b = [System.Drawing.Color]::FromArgb($t.Cyan[0], $t.Cyan[1], $t.Cyan[2])
            $tx = [System.Drawing.Color]::FromArgb($t.Text[0], $t.Text[1], $t.Text[2])
        }
        $rc = New-Object System.Drawing.RectangleF(2, 2, ($s.Width - 5), ($s.Height - 5))
        $path = New-RoundPath $rc 8
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)), $c1, $c2, [single]0)
        $g.FillPath($gb, $path); $gb.Dispose()
        $sel = ($script:themeName -eq $name)
        $pen = New-Object System.Drawing.Pen($(if ($sel) { $script:cAccent } else { [System.Drawing.Color]::FromArgb(110, $script:cDim) }), $(if ($sel) { 3 } else { 1 }))
        $g.DrawPath($pen, $path); $pen.Dispose(); $path.Dispose()
        $ab = New-Object System.Drawing.SolidBrush($a); $bb = New-Object System.Drawing.SolidBrush($b)
        $g.FillRectangle($ab, 10, 9, 22, 5); $g.FillRectangle($bb, 10, 17, 14, 4)
        $g.FillEllipse($ab, ($s.Width - 24), 9, 10, 10)
        $ab.Dispose(); $bb.Dispose()
        $tb = New-Object System.Drawing.SolidBrush($tx)
        $g.DrawString($name, (New-Object System.Drawing.Font("Segoe UI Semibold", 9)), $tb, 9, ($s.Height - 24))
        $tb.Dispose()
    })
    $p.Add_Click({ param($s, $e) Invoke-WizPick ([string]$s.Tag.Name) })
    return $p
}

function Update-WizPage {
    $w = $script:wiz
    for ($i = 0; $i -lt $w.Pages.Count; $i++) { $w.Pages[$i].Visible = ($i -eq $w.Idx) }
    $w.Banner.Invalidate()
    $w.Back.Enabled = ($w.Idx -gt 0)
    $w.Skip.Visible = ($w.Idx -lt ($w.Pages.Count - 1))
    $w.Next.Text = $(if ($w.Idx -eq ($w.Pages.Count - 1)) { "Finish" } else { "Next" })
}

function Invoke-WizPick([string]$nm) {
    try {
        $w = $script:wiz
        $old = Get-PaletteMap
        $script:cmbTheme.SelectedItem = $nm
        $w.Dlg.BackColor = $script:cBg; $w.Dlg.ForeColor = $script:cText
        Update-ControlColors $w.Dlg $old
        $w.Banner.Invalidate()
        foreach ($tl in $w.Tiles) { $tl.Invalidate() }
        Set-TitleBar $w.Dlg.Handle
    } catch { }
}

function Complete-Wizard {
    $w = $script:wiz
    # carry the choices over to the main window's own options (they save themselves)
    try { if ([bool]$script:chkStartWin.Checked -ne [bool]$w.Start.Checked) { $script:chkStartWin.Checked = $w.Start.Checked } } catch { }
    try { if ([bool]$script:chkHot.Checked -ne [bool]$w.Hot.Checked) { $script:chkHot.Checked = $w.Hot.Checked } } catch { }
    try { if ([bool]$script:chkLoadScr.Checked -ne [bool]$w.Load.Checked) { $script:chkLoadScr.Checked = $w.Load.Checked } } catch { }
    $w.Dlg.Close()
}

function Show-SetupWizard {
    $savedRows = $script:addonRows; $savedTip = $script:addonTip
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Ekk0h setup"
    $dlg.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
    $dlg.AutoScaleMode = 'Dpi'
    $dlg.StartPosition = 'CenterParent'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false; $dlg.MinimizeBox = $false; $dlg.ShowInTaskbar = $false
    $dlg.BackColor = $script:cBg; $dlg.ForeColor = $script:cText
    $dlg.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    if ($script:appIcon) { $dlg.Icon = $script:appIcon }
    $dlg.Add_HandleCreated({ param($s, $e) Set-TitleBar $s.Handle })
    $dlg.ClientSize = New-Object System.Drawing.Size(560, 436)

    $titles = @('Welcome', 'Pick a look', 'Optional add-ons', 'Startup', 'All set')
    $banner = New-Object System.Windows.Forms.Panel
    $banner.Location = New-Object System.Drawing.Point(0, 0)
    $banner.Size = New-Object System.Drawing.Size(560, 84)
    $banner.BackColor = $script:cPanel
    $banner.Tag = $titles
    Set-DoubleBuffered $banner
    $banner.Add_Paint({
        param($s, $e)
        $titles = $s.Tag; $wz = $script:wiz
        $g = $e.Graphics
        $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
        $r = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
        $gb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($r, $script:cPanel2, $script:cBg, [single]0)
        $g.FillRectangle($gb, $r); $gb.Dispose()
        $sp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(22, $script:cAccent), 8)
        for ($i = -2; $i -lt 12; $i++) { $g.DrawLine($sp, ($i * 60 + 200), $s.Height, ($i * 60 + 260), 0) }
        $sp.Dispose()
        $f = Get-RetroFont 24 'Bold, Italic'
        $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, $script:cCyan))
        $ab = New-Object System.Drawing.SolidBrush($script:cAccent)
        $g.DrawString("EKK0H", $f, $sh, 26, 8); $g.DrawString("EKK0H", $f, $ab, 23, 5)
        $sh.Dispose(); $ab.Dispose()
        $db = New-Object System.Drawing.SolidBrush($script:cDim); $tb = New-Object System.Drawing.SolidBrush($script:cText)
        $g.DrawString("WALLPAPER STUDIO  /  SETUP", (Get-RetroFont 8), $db, 26, 50)
        $sf = New-Object System.Drawing.StringFormat; $sf.Alignment = 'Far'
        $g.DrawString($titles[$wz.Idx], (Get-RetroFont 14 'Bold, Italic'), $tb, (New-Object System.Drawing.RectangleF(300, 16, 238, 30)), $sf)
        $db.Dispose(); $tb.Dispose(); $sf.Dispose()
        for ($i = 0; $i -lt $titles.Count; $i++) {
            $dx = 538 - ($titles.Count - 1 - $i) * 22
            if ($i -le $wz.Idx) { $br = New-Object System.Drawing.SolidBrush($script:cAccent) } else { $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(110, $script:cDim)) }
            $g.FillEllipse($br, ($dx - 14), 56, 12, 12); $br.Dispose()
        }
        $lp = New-Object System.Drawing.Pen($script:cAccent, 3); $g.DrawLine($lp, 0, 82, $s.Width, 82); $lp.Dispose()
    })
    $dlg.Controls.Add($banner)
    $pages = @()
    for ($i = 0; $i -lt $titles.Count; $i++) {
        $p = New-Object System.Windows.Forms.Panel
        $p.Location = New-Object System.Drawing.Point(0, 90)
        $p.Size = New-Object System.Drawing.Size(560, 286)
        $p.BackColor = $script:cBg
        $p.Visible = $false
        $dlg.Controls.Add($p)
        $pages += $p
    }

    # 1: welcome
    $pages[0].Controls.Add((New-Label "Welcome. This takes about a minute, and every choice can be changed later." 24 6 512 26 $false 10))
    $pages[0].Controls.Add((New-WizCard 24 40 160 190 'packs' "Wallpaper packs" "Turn folders of pictures into packs and switch between them in one click."))
    $pages[0].Controls.Add((New-WizCard 200 40 160 190 'screens' "Every screen" "Each pack is split across all of your monitors, sized to fit each one."))
    $pages[0].Controls.Add((New-WizCard 376 40 160 190 'video' "Video and live" "Cut one video across your screens, or run a live wallpaper."))
    $pages[0].Controls.Add((New-Label "Next: pick a look." 24 244 512 24 $true 9))

    # 2: theme (click a tile; the whole window re-colors)
    $pages[1].Controls.Add((New-Label "Click a look. You can change it any time from the picker in the bottom-right corner." 24 6 512 24 $true 9))
    $tiles = New-Object System.Collections.ArrayList
    $ti = 0
    foreach ($tn in $script:ThemeNames) {
        $tl = New-ThemeTile $tn (24 + ($ti % 4) * 129) (36 + [math]::Floor($ti / 4) * 54) 123 48
        $pages[1].Controls.Add($tl); [void]$tiles.Add($tl)
        $ti++
    }

    # 3: add-ons (same rows as Settings; the Settings rows are put back when this closes)
    $pages[2].Controls.Add((New-Label "These optional programs unlock extra features. Skip any you don't need. They're also in Settings." 24 6 512 44 $true 10))
    Add-AddonRows $pages[2] 24 58
    $pages[2].Controls.Add((New-Label "ffmpeg cuts a video across your screens. The AI upscaler sharpens pictures in the Builder. Get downloads and sets up the first two for you; Lively is installed separately." 24 160 512 70 $true 9))

    # 4: startup options
    $wzStart = New-NeonCheck "Start With Windows (Hidden In The Tray)" 24 14 500
    $wzHot = New-NeonCheck "Global Hotkeys (Ctrl+Alt+Right / Left, P, R)" 24 50 500
    $wzLoad = New-NeonCheck "Show The Loading Screen When The App Starts" 24 86 500
    $wzStart.Checked = [bool]$script:chkStartWin.Checked
    $wzHot.Checked = [bool]$script:chkHot.Checked
    $wzLoad.Checked = [bool]$script:chkLoadScr.Checked
    foreach ($c in @($wzStart, $wzHot, $wzLoad)) { $pages[3].Controls.Add($c) }
    $pages[3].Controls.Add((New-Label "Hotkeys: Ctrl+Alt+Right / Left = next / previous pack, P = pause live wallpapers, R = random pack." 24 130 512 50 $true 9))

    # 5: finish
    $pages[4].Controls.Add((New-Label "You're ready." 24 8 512 26 $false 11))
    $pages[4].Controls.Add((New-Label "To make your first pack, drag pictures from your desktop onto the main window, or open the Builder tab. Right-click a pack card for more options." 24 48 512 70 $true 10))
    $pages[4].Controls.Add((New-Label "Settings > About has update checks and a backup of your options." 24 130 512 40 $true 10))

    $btnBack = New-Btn "Back" 24 388 100 'normal' 32
    $btnSkip = New-Btn "Skip setup" 230 388 110 'normal' 32
    $btnNext = New-Btn "Next" 436 388 100 'primary' 32
    foreach ($b in @($btnBack, $btnSkip, $btnNext)) { $b.Font = Get-RetroFont 9; $dlg.Controls.Add($b) }

    $script:wiz = @{
        Idx = 0; Titles = $titles; Dlg = $dlg; Banner = $banner; Pages = $pages; Tiles = $tiles
        Back = $btnBack; Skip = $btnSkip; Next = $btnNext; Start = $wzStart; Hot = $wzHot; Load = $wzLoad
        SavedRows = $savedRows; SavedTip = $savedTip
    }
    $btnBack.Add_Click({ $w = $script:wiz; if ($w.Idx -gt 0) { $w.Idx--; Update-WizPage } })
    $btnSkip.Add_Click({ $script:wiz.Dlg.Close() })
    $btnNext.Add_Click({
        $w = $script:wiz
        if ($w.Idx -lt ($w.Pages.Count - 1)) { $w.Idx++; Update-WizPage; return }
        Complete-Wizard
    })
    $dlg.Add_FormClosed({
        $w = $script:wiz
        Save-Setting 'WizardDone' '1'
        $script:addonRows = $w.SavedRows; $script:addonTip = $w.SavedTip
        try { Clear-AddonCache; foreach ($r in @($script:addonRows)) { Update-AddonRow $r }; Update-AddonVisibility } catch { }
    })
    Update-WizPage
    [void]$dlg.ShowDialog($script:form)
}

# ---------------------------------------------------------------- loading window hand-off
function Close-Splash {
    try {
        $sp = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::ManualReset, "Local\Ekk0h_SplashClose")
        [void]$sp.Set()
        $sp.Dispose()
    } catch { }
}
# ---------------------------------------------------------------- only one window
$script:instNew = $false
$script:instMutex = New-Object System.Threading.Mutex($true, "Local\WallpaperControlCenter_Main", [ref]$script:instNew)
$script:showEvt = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, "Local\WallpaperControlCenter_Show")
if (-not $script:instNew) {
    # already running: ask that copy to come to the front, then quit
    [void]$script:showEvt.Set()
    Close-Splash
    exit
}

$script:startTray = [bool]$Tray

# ---------------------------------------------------------------- window icon
$icoFile = Join-Path $PSScriptRoot "ControlCenter.ico"
$script:appIcon = $null
$script:trayIcon = $null
try {
    if (Test-Path -LiteralPath $icoFile) {
        $script:appIcon  = New-Object System.Drawing.Icon($icoFile, 32, 32)
        $script:trayIcon = New-Object System.Drawing.Icon($icoFile, 16, 16)
    } elseif (Get-AppExe) {
        # no loose icon file: use the program's own icon
        $script:appIcon  = [System.Drawing.Icon]::ExtractAssociatedIcon((Get-AppExe))
        $script:trayIcon = New-Object System.Drawing.Icon($script:appIcon, 16, 16)
    }
} catch {
    $script:appIcon = $null
    $script:trayIcon = $null
}
if (-not $script:appIcon) {
    $iconBmp = New-IconBitmap 32
    $script:appIcon = [System.Drawing.Icon]::FromHandle($iconBmp.GetHicon())
}
if (-not $script:trayIcon) { $script:trayIcon = $script:appIcon }

# ---------------------------------------------------------------- the window
# own taskbar identity, so the taskbar shows this app's icon instead of PowerShell's
try { [AppId]::Set("WallpaperControlCenter.App") } catch { }
$form = New-Object System.Windows.Forms.Form
$script:form = $form
$form.Text = "Ekk0h - Wallpaper Studio"
$form.AutoScaleDimensions = New-Object System.Drawing.SizeF(96, 96)
$form.AutoScaleMode = 'Dpi'
$form.ClientSize = New-Object System.Drawing.Size(940, 650)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $script:cBg
$form.ForeColor = $script:cText
$form.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Icon = $script:appIcon

$tt = New-Object System.Windows.Forms.ToolTip
$tt.InitialDelay = 400

# ---- header: sun, horizon, grid, title and tabs, all painted
$script:tabs = @(
    @{ Text = "PACKS";    X = 24;  W = 92;  Hidden = $false },
    @{ Text = "ANIMATED"; X = 124; W = 118; Hidden = $false },
    @{ Text = "DISPLAY"; X = 250; W = 112; Hidden = $false },
    @{ Text = "BUILDER";  X = 370; W = 108; Hidden = $false },
    @{ Text = "SETTINGS"; X = 486; W = 118; Hidden = $true }
)
$script:activeTab = 0
$script:prevTab = 0
$script:settingsBuilt = $false
$pnlHeader = New-Object System.Windows.Forms.Panel
$script:pnlHeader = $pnlHeader
$pnlHeader.Location = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size = New-Object System.Drawing.Size(940, 100)
Set-DoubleBuffered $pnlHeader
$pnlHeader.Add_Paint({
    param($s, $e)
    Invoke-RetroHeaderPaint $e.Graphics $s.ClientSize.Width $s.ClientSize.Height "EKK0H" "// WALLPAPER STUDIO" $script:tabs $script:activeTab
    # small gear (settings) in the top-right corner
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $gc = if ($script:gearHot -or $script:activeTab -eq 4) { $script:cAccent } else { $script:cCyan }
    $gp = New-Object System.Drawing.Pen($gc, 2.0)
    $cx = 918.0; $cy = 24.0
    for ($k = 0; $k -lt 8; $k++) {
        $a = $k * [math]::PI / 4
        $g.DrawLine($gp, [single]($cx + [math]::Cos($a) * 7.5), [single]($cy + [math]::Sin($a) * 7.5), [single]($cx + [math]::Cos($a) * 11), [single]($cy + [math]::Sin($a) * 11))
    }
    $g.DrawEllipse($gp, [single]($cx - 7.5), [single]($cy - 7.5), [single]15, [single]15)
    $g.DrawEllipse($gp, [single]($cx - 3), [single]($cy - 3), [single]6, [single]6)
    $gp.Dispose()
})
$script:gearHot = $false
function Test-GearHit([int]$x, [int]$y) { return ($x -ge 902 -and $x -le 934 -and $y -ge 8 -and $y -le 40) }
# animated headers (digital rain, glitch) tick slowly and only while the window is showing
if ($true) {
    $script:animTimer = New-Object System.Windows.Forms.Timer
    $script:animTimer.Interval = 70
    $script:animTimer.Add_Tick({
        if ($script:themeAnim -and $script:form.Visible -and $script:form.WindowState -ne 'Minimized') {
            $ph = [int]($script:hdrClock.Elapsed.TotalSeconds / 0.13)
            $steady = @('matrix', 'glitch') -contains $script:themeHdr
            if ((-not $steady) -or $ph -ne $script:hdrPhase) {
                $newPh = ($ph -ne $script:hdrPhase)
                $script:hdrPhase = $ph
                if ($script:themeHdr -ne 'wallpaper' -and -not $script:pauseHdr) { $script:pnlHeader.Invalidate() }
                if ($script:themeHdr -eq 'matrix' -and $script:pillState -eq 0 -and ([Environment]::TickCount - $script:pillT0) -gt 75000) { Start-Pills }
                $fa = (@('rgb', 'galaxy', 'retro', 'cyber', 'shinobi', 'aurora', 'kawaii', 'blueprint', 'wallpaper', 'glitch') -contains $script:themeHdr) -or ($script:themeHdr -eq 'matrix' -and $script:pillState -ge 1)
                if ($fa -and -not $script:pauseFtr -and ($newPh -or -not $steady)) { $script:pnlStatus.Invalidate() }
            }
        }
    })
    $script:animTimer.Start()
}
if ($script:themeHdr -eq 'rgb') { Start-AudioReact }
function Get-TabAt([int]$x, [int]$y) {
    if ($y -lt 50 -or $y -gt 84) { return -1 }
    for ($i = 0; $i -lt $script:tabs.Count; $i++) {
        $t = $script:tabs[$i]
        if ($t.Hidden) { continue }
        if ($x -ge $t.X -and $x -le ($t.X + $t.W)) { return $i }
    }
    return -1
}
$pnlHeader.Add_MouseMove({
    param($s, $e)
    $gh = Test-GearHit $e.X $e.Y
    if ($gh -ne $script:gearHot) { $script:gearHot = $gh; $s.Invalidate() }
    if ($gh -or ((Get-TabAt $e.X $e.Y) -ge 0)) { $s.Cursor = 'Hand' } else { $s.Cursor = 'Default' }
})
$pnlHeader.Add_MouseLeave({ if ($script:gearHot) { $script:gearHot = $false; $script:pnlHeader.Invalidate() } })
$pnlHeader.Add_MouseClick({
    param($s, $e)
    if (Test-GearHit $e.X $e.Y) { Show-SettingsWindow; return }
    $i = Get-TabAt $e.X $e.Y
    if ($i -ge 0) { Switch-Tab $i }
})
$form.Controls.Add($pnlHeader)

# ---- status bar with a little floor grid
$pnlStatus = New-Object System.Windows.Forms.Panel
$script:pnlStatus = $pnlStatus
$pnlStatus.Location = New-Object System.Drawing.Point(0, 606)
$pnlStatus.Size = New-Object System.Drawing.Size(940, 44)
Set-DoubleBuffered $pnlStatus
$pnlStatus.Add_Paint({
    param($s, $e)
    Invoke-StatusPaint $e.Graphics $s.ClientSize.Width $s.ClientSize.Height
})
function Invoke-PillClick([int]$x, [int]$y) {
    if ($script:themeHdr -ne 'matrix' -or $script:pillState -ne 2) { return }
    $rest = Get-PillRects $script:pnlStatus.ClientSize.Width $script:pnlStatus.ClientSize.Height
    for ($i = 0; $i -lt 2; $i++) {
        if ([math]::Abs($x - $rest[$i][0]) -lt 24 -and [math]::Abs($y - $rest[$i][1]) -lt 18) {
            if ($i -eq 0) { Set-Status "You picked the red pill. Let's see how deep this goes." }
            else { Set-Status "You picked the blue pill. Back to normal." }
            $script:pillState = 0; $script:pillT0 = [Environment]::TickCount + 60000   # a long wait before it shows again
            $script:pnlStatus.Invalidate()
            return
        }
    }
}
$pnlStatus.Add_MouseClick({ param($s, $e) Invoke-PillClick $e.X $e.Y })
$form.Controls.Add($pnlStatus)
$script:lblStatus = New-Label "Ready." 24 12 620 26 $false 10
$script:lblStatus.ForeColor = $script:cStatText
$script:lblStatus.Font = Get-RetroFont 10 'Regular'
$pnlStatus.Controls.Add($script:lblStatus)
# the text label covers the middle of the footer, so clicks on it count as footer clicks
$script:lblStatus.Add_MouseClick({ param($s, $e) Invoke-PillClick ($e.X + $s.Left) ($e.Y + $s.Top) })
$script:quipTimer = New-Object System.Windows.Forms.Timer
$script:quipTimer.Interval = 5000
$script:quipTimer.Add_Tick({
    if (-not $script:form.Visible) { return }
    $age = [Environment]::TickCount - $script:statusAt
    if ((-not $script:quipShown -and $age -gt 20000) -or ($script:quipShown -and $age -gt 25000)) { Show-Quip }
})
$script:quipTimer.Start()

# ---- theme picker (footer, right side)
$lblTheme = New-Label "THEME" 654 14 56 22 $true 9
$lblTheme.Font = Get-RetroFont 9 'Bold'
$lblTheme.ForeColor = $script:cDim
$pnlStatus.Controls.Add($lblTheme)
$script:themeInit = $true
$script:cmbTheme = New-StyledCombo 716 8 200
foreach ($tn in $script:ThemeNames) { [void]$script:cmbTheme.Items.Add($tn) }
$script:cmbTheme.SelectedItem = $script:themeName
$script:themeInit = $false
$tt.SetToolTip($script:cmbTheme, "Change how the whole panel looks. Wallpaper builds a theme from the colors of your current desktop picture (pick another theme and Wallpaper again to re-match).")
$script:cmbTheme.Add_SelectedIndexChanged({
    if ($script:themeInit) { return }
    $n = [string]$script:cmbTheme.SelectedItem
    if (-not $n -or $n -eq $script:themeName) { return }
    try {
        $script:form.SuspendLayout()
        Switch-ThemeLive $n
    } catch {
        Save-Setting 'Theme' $n
        $ans = [System.Windows.Forms.MessageBox]::Show("Theme set to $n, but it couldn't be applied live.`n`nRestart the control center now to see it?", "Theme", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        if ($ans -eq [System.Windows.Forms.DialogResult]::Yes) { Restart-App }
    } finally { $script:form.ResumeLayout($true) }
})
$pnlStatus.Controls.Add($script:cmbTheme)

# ================================================================ PACKS TAB
$pnlPacks = New-Object System.Windows.Forms.Panel
$script:pnlPacks = $pnlPacks
$pnlPacks.Location = New-Object System.Drawing.Point(0, 108)
$pnlPacks.Size = New-Object System.Drawing.Size(940, 492)
$pnlPacks.BackColor = $script:cBg
$form.Controls.Add($pnlPacks)

# hidden pack model: the grid reads and selects packs through this list (never shown)
$lbPacks = New-Object System.Windows.Forms.ListBox
$lbPacks.Visible = $false
$lbPacks.Size = New-Object System.Drawing.Size(10, 10)
$script:lbPacks = $lbPacks
$pnlPacks.Controls.Add($lbPacks)
[void]$lbPacks.Handle

# left: the thumbnail grid (toolbar, cards, themed scrollbar)
New-PackGrid $pnlPacks

# right: pack name, one preview per connected screen (built by Build-PreviewBoxes), buttons
$script:lblPackName = New-Label "" 668 0 248 28 $false 13
$script:lblPackName.Font = Get-RetroFont 13 'Bold, Italic'
$pnlPacks.Controls.Add($script:lblPackName)
$script:lblInfo = New-Label "" 668 28 248 34 $true 9
$pnlPacks.Controls.Add($script:lblInfo)
$script:pnlPrev = $null

# two columns of buttons, each 120 x 32
$btnRandom    = New-Btn "Random" 668 152 120 'normal' 30
$btnExport    = New-Btn "Export" 796 152 120 'normal' 30
$btnNewPack   = New-Btn "New pack" 668 186 120 'cyan' 30
$btnImport    = New-Btn "Import" 796 186 120 'normal' 30
$btnOpenPacks = New-Btn "Folder" 668 220 248 'normal' 30
foreach ($b in @($btnRandom, $btnExport, $btnNewPack, $btnImport, $btnOpenPacks)) { $pnlPacks.Controls.Add($b) }

# auto-shuffle
$pnlPacks.Controls.Add((New-Heading "Auto shuffle" 668 260 218))
$chkShuffle = New-NeonCheck "Auto-Shuffle Every" 668 284 160 28
$script:chkShuffle = $chkShuffle
$pnlPacks.Controls.Add($chkShuffle)
$numMin = New-NeonSpin 832 286 56 1 1440 0 1
$numMin.Value = 30
$script:numMin = $numMin
$pnlPacks.Controls.Add($numMin)
$pnlPacks.Controls.Add((New-Label "min" 892 290 30 22 $true 9))
$script:btnShuffleSrc = New-Btn "Shuffle from: All packs" 668 312 248 'normal' 28
$script:btnShuffleSrc.Font = Get-RetroFont 8
$pnlPacks.Controls.Add($script:btnShuffleSrc)
$tt.SetToolTip($script:btnShuffleSrc, "Choose which packs auto-shuffle picks from: everything, favorites, and/or packs with certain tags")

# pin screens: pinned screens are left alone when a pack is applied
$pnlPacks.Controls.Add((New-Heading "Pin screens" 668 354 218))
$pnlPacks.Controls.Add((New-HelpButton 892 352 "Pin screens" "Pinned screens keep whatever they are showing (a picture or a live video) whenever a pack is applied. This covers every way a pack changes: Apply, Random, Auto-shuffle, the Schedule, the tray menu and hotkeys.`n`nTurn on 'Keep pinned screens as they are', then tick the numbers of the screens to pin. Screens are numbered left to right, the same order packs are laid out.`n`nIf every screen is pinned, nothing changes until you unpin one."))
$script:chkPinOn = New-NeonCheck "Only Change Unpinned Screens" 668 376 248 28
$pnlPacks.Controls.Add($script:chkPinOn)
$script:pnlPins = New-Object System.Windows.Forms.Panel
$script:pnlPins.Location = New-Object System.Drawing.Point(668, 406)
$script:pnlPins.Size = New-Object System.Drawing.Size(248, 54)
$script:pnlPins.BackColor = $script:cBg
$pnlPacks.Controls.Add($script:pnlPins)

# upscale settings (the dropdowns live on the Builder tab)
$cmbModel = New-StyledCombo 796 302 120
$script:cmbModel = $cmbModel
foreach ($o in (Get-ModelChoices)) { [void]$cmbModel.Items.Add($o) }

$cmbMix = New-StyledCombo 796 376 120
$script:cmbMix = $cmbMix
foreach ($o in @("100%", "75%", "60%", "40%", "25%")) { [void]$cmbMix.Items.Add($o) }

$cmbGrain = New-StyledCombo 796 452 120
$script:cmbGrain = $cmbGrain
foreach ($o in @("Off", "Light", "Medium", "Strong")) { [void]$cmbGrain.Items.Add($o) }

# remembered from last time
$upSaved = Get-Settings
if ($cmbModel.Items.Contains($upSaved.UpModel)) { $cmbModel.SelectedItem = $upSaved.UpModel } else { $cmbModel.SelectedIndex = 0 }
if ($cmbMix.Items.Contains($upSaved.UpMix)) { $cmbMix.SelectedItem = $upSaved.UpMix } else { $cmbMix.SelectedItem = "60%" }
if ($cmbGrain.Items.Contains($upSaved.UpGrain)) { $cmbGrain.SelectedItem = $upSaved.UpGrain } else { $cmbGrain.SelectedItem = "Light" }

$tt.SetToolTip($btnRandom, "Apply a random pack")
$tt.SetToolTip($btnNewPack, "Pick your pictures, arrange them across your screens and save them as a pack")
$tt.SetToolTip($cmbModel, "Which AI model Upscale and Up + slice use. Auto Soft picks the gentlest one that's big enough for each image. Anime x4 is stronger and looks more 'redrawn'.")
$tt.SetToolTip($cmbMix, "How much of the AI result to keep. Lower mixes in more of a plain resize of your original, so the AI changes are less visible.")
$tt.SetToolTip($cmbGrain, "Fine film grain added to slices and upscaled images. It hides plastic smoothness and makes soft images look intentional.")
$tt.SetToolTip($btnOpenPacks, "Open the WallpaperPacks folder in Explorer")
$tt.SetToolTip($chkShuffle, "With shuffle on, closing the window keeps it running in the tray (bottom-right, near the clock). Right-click the tray icon to exit.")

$tt.SetToolTip($script:chkPinOn, "When on, the ticked screens below are left alone whenever a pack is applied")

# ================================================================ ANIMATED TAB
$pnlAnim = New-Object System.Windows.Forms.Panel
$script:pnlAnim = $pnlAnim
$pnlAnim.Location = New-Object System.Drawing.Point(0, 108)
$pnlAnim.Size = New-Object System.Drawing.Size(940, 492)
$pnlAnim.BackColor = $script:cBg
$pnlAnim.Visible = $false
$form.Controls.Add($pnlAnim)

# left: video list (drag video files onto it to add them)
$pnlAnim.Controls.Add((New-Heading "Video wallpapers" 24 0 250))
$lbAnim = New-StyledList 24 24 400 410
$script:lbAnim = $lbAnim
$lbAnim.AllowDrop = $true
$pnlAnim.Controls.Add($lbAnim)
Add-ThemedScroll $lbAnim $pnlAnim
$script:lblAnimCount = New-Label "" 24 440 400 22 $true 9
$pnlAnim.Controls.Add($script:lblAnimCount)

# right, top: preview + details
$script:pbAnim = New-Object System.Windows.Forms.PictureBox
$script:pbAnim.Location = New-Object System.Drawing.Point(450, 0)
$script:pbAnim.Size = New-Object System.Drawing.Size(220, 124)
$script:pbAnim.SizeMode = 'Zoom'
$script:pbAnim.BackColor = $script:cPanel
Set-NeonFrame $script:pbAnim
$pnlAnim.Controls.Add($script:pbAnim)

$script:lblAnimName = New-Label "" 686 0 230 46 $false 11
$script:lblAnimName.Font = Get-RetroFont 11 'Bold'
$pnlAnim.Controls.Add($script:lblAnimName)
$script:lblAnimInfo = New-Label "" 686 48 230 20 $true 9
$pnlAnim.Controls.Add($script:lblAnimInfo)
$script:lblNow = New-Label "" 686 76 230 48 $false 9
$script:lblNow.ForeColor = $script:cAccentHover
$pnlAnim.Controls.Add($script:lblNow)

# right, middle: where + sound, then the main actions
$pnlAnim.Controls.Add((New-Heading "Play on" 450 146 227))
$cmbMon = New-StyledCombo 450 168 227
$script:cmbMon = $cmbMon
$script:rebuildingMon = $false
$pnlAnim.Controls.Add($cmbMon)

$pnlAnim.Controls.Add((New-Heading "Sound" 689 146 227))
$cmbSound = New-StyledCombo 689 168 227
$script:cmbSound = $cmbSound
foreach ($o in @("Muted", "Quiet", "Medium", "Loud")) { [void]$cmbSound.Items.Add($o) }
$cmbSound.SelectedIndex = 0
$pnlAnim.Controls.Add($cmbSound)
$savedSettings = Get-Settings
if ($cmbSound.Items.Contains($savedSettings.AnimSound)) { $cmbSound.SelectedItem = $savedSettings.AnimSound }

$btnPlay       = New-Btn "Play" 450 214 150 'primary' 40
$btnRandomAnim = New-Btn "Random" 608 214 150 'normal' 40
$btnStopAnim   = New-Btn "Stop" 766 214 150 'danger' 40
foreach ($b in @($btnPlay, $btnRandomAnim, $btnStopAnim)) { $pnlAnim.Controls.Add($b) }

# right, lower: library + Lively
$pnlAnim.Controls.Add((New-Heading "Library" 450 266 300))
$btnAddAnim    = New-Btn "Add" 450 288 150 'normal' 40
$btnOpenAnim   = New-Btn "Folder" 608 288 150 'normal' 40
$btnRemoveAnim = New-Btn "Remove" 766 288 150 'danger' 40
foreach ($b in @($btnAddAnim, $btnOpenAnim, $btnRemoveAnim)) { $pnlAnim.Controls.Add($b) }

$pnlAnim.Controls.Add((New-Heading "Lively (plays the videos)" 450 340 300))
$script:lblLively = New-Label "" 450 362 150 40 $false 10
$script:lblLively.Font = Get-RetroFont 11 'Bold'
$script:lblLively.TextAlign = 'MiddleLeft'
$pnlAnim.Controls.Add($script:lblLively)
$btnLocateLively = New-Btn "Locate" 608 362 150 'normal' 40
$btnGetLively    = New-Btn "Get app" 766 362 150 'normal' 40
foreach ($b in @($btnLocateLively, $btnGetLively)) { $pnlAnim.Controls.Add($b) }
$pnlAnim.Controls.Add((New-Label "Display numbers are Windows' own (see the Displays tab). Applying a regular pack stops animated wallpapers." 450 404 466 32 $true 9))

# GPU saver: freeze live wallpapers while something else needs the GPU
$pnlAnim.Controls.Add((New-Heading "GPU saver" 450 440 150))
$script:lblPauseState = New-Label "" 676 442 240 20 $true 9
$pnlAnim.Controls.Add($script:lblPauseState)
$pnlAnim.Controls.Add((New-HelpButton 604 434 "GPU saver" ("Live wallpapers keep using your graphics card even while you play a game. The GPU saver freezes them (the last frame stays on the desktop, and they use almost no GPU or CPU) while something else is in front, then thaws them automatically.`n`n" +
    "- Full-Screen Apps: games, full-screen video and presentations.`n" +
    "- Any Maximized Window: also freezes them whenever a maximized window covers the desktop - the biggest saver.`n" +
    "- Also pause on battery: freezes them whenever a laptop is unplugged.`n`n" +
    "The app has to keep running for this: close it to the tray (bottom-right, near the clock) instead of exiting. If the app is closed or stops, wallpapers are thawed again.")))
$script:cmbPause = New-StyledCombo 450 460 227
foreach ($o in @("Off", "Full-Screen Apps", "Any Maximized Window")) { [void]$script:cmbPause.Items.Add($o) }
$pm = [string](Get-Settings).AutoPause
$script:cmbPause.SelectedIndex = $(if ($pm -eq 'Maximized') { 2 } elseif ($pm -eq 'Fullscreen') { 1 } else { 0 })
$pnlAnim.Controls.Add($script:cmbPause)
$script:chkPauseBat = New-NeonCheck "Also Pause On Battery" 689 462 227 28
$script:chkPauseBat.Checked = ((Get-Settings).PauseBattery -eq '1')
$pnlAnim.Controls.Add($script:chkPauseBat)
$tt.SetToolTip($script:cmbPause, "When live wallpapers freeze to save your GPU")

$tt.SetToolTip($lbAnim, "Drag video files here to add them")
$tt.SetToolTip($cmbMon, "All Monitors: the same video on each screen. Span: one video stretched across all screens. Cut To My Screens: the video is cut to your real screen sizes and spacing so it lines up across them (needs ffmpeg). Right-click a video to reposition its cut.")
$tt.SetToolTip($cmbSound, "Wallpaper volume (applies to all Lively wallpapers)")
$tt.SetToolTip($btnPlay, "Play the selected video (double-click a video does the same)")
$tt.SetToolTip($btnRandomAnim, "Play a random video from the list")
$tt.SetToolTip($btnStopAnim, "Stop animated wallpapers")
$tt.SetToolTip($btnAddAnim, "Copy video files into the Animated folder")
$tt.SetToolTip($btnOpenAnim, "Open the Animated folder in Explorer")
$tt.SetToolTip($btnRemoveAnim, "Move the selected video to the Recycle Bin")
$tt.SetToolTip($btnLocateLively, "Point the app at Lively.exe if it can't find it on its own")
$tt.SetToolTip($btnGetLively, "Open the Lively Wallpaper page (free)")

# ================================================================ DISPLAYS TAB
$pnlDisp = New-Object System.Windows.Forms.Panel
$script:pnlDisp = $pnlDisp
$pnlDisp.Location = New-Object System.Drawing.Point(0, 108)
$pnlDisp.Size = New-Object System.Drawing.Size(940, 492)
$pnlDisp.BackColor = $script:cBg
$pnlDisp.Visible = $false
$form.Controls.Add($pnlDisp)

# the screens, big and in the middle of the tab
$pnlMap = New-Object System.Windows.Forms.Panel
$script:pnlMap = $pnlMap
$pnlMap.Location = New-Object System.Drawing.Point(24, 0)
$pnlMap.Size = New-Object System.Drawing.Size(892, 270)
Set-DoubleBuffered $pnlMap
$pnlMap.Add_Paint({ param($s, $e) Invoke-MapPaint $s $e })
$pnlDisp.Controls.Add($pnlMap)

# ---- save / undo for moved screens
$script:btnSaveLayout = New-Btn "Save changes" 608 404 150 'primary' 32
$script:btnUndoLayout = New-Btn "Undo" 766 404 150 'normal' 32
$script:btnSaveLayout.Visible = $false
$script:btnUndoLayout.Visible = $false
$pnlDisp.Controls.Add($script:btnSaveLayout)
$pnlDisp.Controls.Add($script:btnUndoLayout)

function Set-LayoutDirty([bool]$d) {
    $script:layoutDirty = $d
    $script:btnSaveLayout.Visible = $d
    $script:btnUndoLayout.Visible = $d
}

# true = fine to carry on (saved or discarded), false = stay where you are
function Confirm-LayoutPending {
    if (-not $script:layoutDirty) { return $true }
    $a = [System.Windows.Forms.MessageBox]::Show("You moved your screens on the map.`n`nSave these changes?", "Save changes", 'YesNoCancel', 'Question')
    if ($a -eq 'Yes') { Save-LayoutPositions; Set-LayoutDirty $false; $script:pnlMap.Invalidate(); Update-Preview; Set-Status "Screen layout saved."; return $true }
    if ($a -eq 'No') { Undo-LayoutChanges; Set-LayoutDirty $false; $script:pnlMap.Invalidate(); Update-Preview; return $true }
    return $false
}

# ---- drag a screen anywhere on the map: side by side, stacked above one another, or swapped over
$script:dragIdx = 0
$script:dragMoved = $false
function Get-MapHit([int]$x, [int]$y) {
    foreach ($k in @($script:mapRects.Keys)) {
        $r = $script:mapRects[$k]
        if ($r.Contains([single]$x, [single]$y)) { return [int]$k }
    }
    return 0
}

# Nudges a dropped screen so its edges meet its neighbours (a bezel apart) or line up with them.
function Get-SnappedPos([int]$idx, [double]$L, [double]$T) {
    $lay = Get-PhysicalLayout
    $me = $lay.Items | Where-Object { $_.Index -eq $idx } | Select-Object -First 1
    $bestX = 22.0; $dx = 0.0; $bestY = 22.0; $dy = 0.0
    foreach ($o in $lay.Items) {
        if ($o.Index -eq $idx) { continue }
        $gap = $me.Bezel + $o.Bezel
        $cx = @((($o.L + $o.PW + $gap) - $L), (($o.L - $gap - $me.PW) - $L), ($o.L - $L), (($o.L + $o.PW) - ($L + $me.PW)), (($o.L + $o.PW / 2) - ($L + $me.PW / 2)))
        foreach ($c in $cx) { if ([math]::Abs($c) -lt $bestX) { $bestX = [math]::Abs($c); $dx = $c } }
        $cy = @((($o.T + $o.PH + $gap) - $T), (($o.T - $gap - $me.PH) - $T), ($o.T - $T), (($o.T + $o.PH) - ($T + $me.PH)), (($o.T + $o.PH / 2) - ($T + $me.PH / 2)))
        foreach ($c in $cy) { if ([math]::Abs($c) -lt $bestY) { $bestY = [math]::Abs($c); $dy = $c } }
    }
    return @{ L = ($L + $dx); T = ($T + $dy) }
}

$pnlMap.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne 'Left') { return }
    [void]$s.Focus()
    $hit = Get-MapHit $e.X $e.Y
    if ($hit -le 0) { return }
    if ($script:cmbPhysScreen.SelectedIndex -ne ($hit - 1)) { $script:cmbPhysScreen.SelectedIndex = ($hit - 1) }
    $s.Invalidate()
    if (-not (Test-PhysMatch)) { return }
    $lay = Get-PhysicalLayout
    $script:preOverride = $script:posOverride
    $ov = @{}
    foreach ($it in $lay.Items) {
        $ov[$it.Index] = @{ L = [double]$it.L; T = [double]$it.T }
        if ($it.Index -eq $hit) { $script:dragL = [double]$it.L; $script:dragT = [double]$it.T }
    }
    $script:posOverride = $ov
    $script:mapFix = @{ Scale = $script:mapScale; OffX = $script:mapOffX; OffY = $script:mapOffY; MinL = $lay.MinL; MinY = $lay.MinY }
    $script:dragIdx = $hit
    $script:dragX0 = $e.X
    $script:dragY0 = $e.Y
    $script:dragMoved = $false
    $s.Capture = $true
})
$pnlMap.Add_MouseMove({
    param($s, $e)
    if ($script:dragIdx -gt 0) {
        if (([math]::Abs($e.X - $script:dragX0) + [math]::Abs($e.Y - $script:dragY0)) -gt 4) { $script:dragMoved = $true }
        if ($script:dragMoved) {
            $sc = [double]$script:mapFix.Scale
            $script:posOverride[$script:dragIdx] = @{ L = ($script:dragL + ($e.X - $script:dragX0) / $sc); T = ($script:dragT + ($e.Y - $script:dragY0) / $sc) }
            Reset-PhysLayout
            $s.Invalidate()
        }
    } elseif (Get-MapHit $e.X $e.Y) {
        if (Test-PhysMatch) { $s.Cursor = [System.Windows.Forms.Cursors]::SizeAll } else { $s.Cursor = [System.Windows.Forms.Cursors]::Hand }
    } else {
        $s.Cursor = [System.Windows.Forms.Cursors]::Default
    }
})
$pnlMap.Add_MouseUp({
    param($s, $e)
    if ($script:dragIdx -le 0) { return }
    $s.Capture = $false
    $idx = $script:dragIdx
    $script:dragIdx = 0
    $script:mapFix = $null
    if ($script:dragMoved) {
        Reset-PhysLayout
        $noSnap = ([string](Get-Settings).NoSnap -eq '1') -or (([System.Windows.Forms.Control]::ModifierKeys -band [System.Windows.Forms.Keys]::Alt) -ne 0)
        if (-not $noSnap) {
            $snap = Get-SnappedPos $idx $script:posOverride[$idx].L $script:posOverride[$idx].T
            $script:posOverride[$idx] = @{ L = $snap.L; T = $snap.T }
        }
        Set-LayoutDirty $true
        Set-Status "Screens moved. Click Save changes to keep this layout."
    } else {
        $script:posOverride = $script:preOverride
    }
    Reset-PhysLayout
    $s.Invalidate()
    Update-Preview
})
# arrow keys nudge the picked screen 1 mm (Shift = 10 mm) so a layout can be fine-tuned precisely
try { $pnlMap.GetType().GetMethod('SetStyle', [Reflection.BindingFlags]'Instance,NonPublic').Invoke($pnlMap, @([System.Windows.Forms.ControlStyles]::Selectable, $true)) } catch { }
$pnlMap.TabStop = $true
$pnlMap.Add_PreviewKeyDown({
    param($s, $e)
    if (@('Left', 'Right', 'Up', 'Down') -contains [string]$e.KeyCode) { $e.IsInputKey = $true }
})
$pnlMap.Add_KeyDown({
    param($s, $e)
    $k = [string]$e.KeyCode
    if (@('Left', 'Right', 'Up', 'Down') -notcontains $k) { return }
    $e.Handled = $true; $e.SuppressKeyPress = $true
    if (-not (Test-PhysMatch)) { Set-Status "Turn on 'Match real size when slicing' to position screens."; return }
    $idx = $script:cmbPhysScreen.SelectedIndex + 1
    if ($idx -le 0) { return }
    $lay = Get-PhysicalLayout
    $ov = @{}
    foreach ($it in $lay.Items) { $ov[$it.Index] = @{ L = [double]$it.L; T = [double]$it.T } }
    if (-not $ov.ContainsKey($idx)) { return }
    $step = 1.0
    if ($e.Shift) { $step = 10.0 }
    if ($k -eq 'Left') { $ov[$idx].L -= $step } elseif ($k -eq 'Right') { $ov[$idx].L += $step }
    elseif ($k -eq 'Up') { $ov[$idx].T -= $step } else { $ov[$idx].T += $step }
    $script:posOverride = $ov
    Reset-PhysLayout
    Set-LayoutDirty $true
    Set-Status ("Screen {0} moved {1} mm. Click Save changes to keep this layout." -f $idx, $step)
    $s.Invalidate()
    Update-Preview
})
$script:btnSaveLayout.Add_Click({
    Save-LayoutPositions
    Set-LayoutDirty $false
    $script:pnlMap.Invalidate()
    Update-Preview
    Set-Status "Screen layout saved."
})
$script:btnUndoLayout.Add_Click({
    Undo-LayoutChanges
    Set-LayoutDirty $false
    $script:pnlMap.Invalidate()
    Update-Preview
    Set-Status "Changes undone."
})

# ---- real screen sizes (for seamless slicing)
$pnlDisp.Controls.Add((New-Heading "Real size" 24 280 300))
foreach ($lbl in @(@("Screen", 24, 200), @("Diagonal (In)", 236, 100), @("Bezel (Mm)", 346, 90))) {
    $pnlDisp.Controls.Add((New-Label $lbl[0] $lbl[1] 308 $lbl[2] 16 $true 8))
}
$cmbPhysScreen = New-StyledCombo 24 326 200
$script:cmbPhysScreen = $cmbPhysScreen
$pnlDisp.Controls.Add($cmbPhysScreen)
$numDiag = New-NeonSpin 236 326 100 7 100 1 0.5
$numBezel = New-NeonSpin 346 326 90 0 60 1 1
$script:numDiag = $numDiag; $script:numBezel = $numBezel
foreach ($c in @($numDiag, $numBezel)) { $pnlDisp.Controls.Add($c) }

$pnlDisp.Controls.Add((New-Label "Alignment" 24 366 200 16 $true 8))
$cmbAlign = New-StyledCombo 24 384 200
$script:cmbAlign = $cmbAlign
foreach ($o in @("Auto", "Center", "Top", "Bottom")) { [void]$cmbAlign.Items.Add($o) }
$cmbAlign.SelectedItem = (Get-Settings).DispAlignMode
if (-not $cmbAlign.SelectedItem) { $cmbAlign.SelectedItem = "Auto" }
$pnlDisp.Controls.Add($cmbAlign)

$chkPhys = New-NeonCheck "Match Real Size When Slicing" 236 384 300 28
$script:chkPhys = $chkPhys
$chkPhys.Checked = (Test-PhysMatch)
$pnlDisp.Controls.Add($chkPhys)

$chkSnap = New-NeonCheck "Snap Screens To Each Other" 236 410 300 26
$script:chkSnap = $chkSnap
$chkSnap.Checked = ([string](Get-Settings).NoSnap -ne '1')
$chkSnap.Add_CheckedChanged({ Save-Setting 'NoSnap' $(if ($script:chkSnap.Checked) { '' } else { '1' }) })
$pnlDisp.Controls.Add($chkSnap)

# short hint + a ? for the full explanation
$pnlDisp.Controls.Add((New-Label "Drag screens to match your desk. Hold Alt to skip snapping. Arrow keys nudge 1 mm." 24 442 520 20 $true 9))
$pnlDisp.Controls.Add((New-HelpButton 552 440 "Screens and real size" ("Screen sizes are read from your monitors when possible. Check them against the label or box and fix any that are off - slices are only as accurate as these numbers.`n`nDiagonal: the size as sold, e.g. 27.`nBezel: the plastic edge on each side of the screen, in millimetres (5-15 is typical). The picture carries on behind it, so lines meet up across screens.`n`nDrag a screen on the map to place it where it really sits: next to the others, above one, or swapped over. Edges snap to their neighbours. When you let go, click Save changes to keep the layout (or Undo).`n`nAlign: how screens of different heights line up when you haven't dragged them. Picking one clears your dragged positions.`n`nSnapping: hold Alt while dropping a screen to skip it, or untick Snap Screens To Each Other. With a screen selected, the arrow keys nudge it 1 mm (hold Shift for 10 mm).`n`nMatch real size: on = slices follow your real sizes and bezels. Off = a simple split by pixels.`n`nScreen numbers: packs fill screens left to right; screen 1 is the leftmost one, whatever Windows calls it. For videos, 'Display' numbers are Windows' own.")))

$pnlDisp.Controls.Add((New-Heading "Screens" 608 280 308))
$btnIdentify    = New-Btn "Identify" 608 308 150 'cyan' 40
$btnRefreshDisp = New-Btn "Refresh" 766 308 150 'normal' 40
$btnWinDisp     = New-Btn "Settings" 608 356 150 'normal' 40
$btnRefit       = New-Btn "Refit packs" 766 356 150 'normal' 40
foreach ($b in @($btnIdentify, $btnRefreshDisp, $btnWinDisp, $btnRefit)) { $pnlDisp.Controls.Add($b) }
$pnlDisp.Controls.Add((New-Label "Screen Rotation" 608 442 120 16 $true 8))
$pnlDisp.Controls.Add((New-HelpButton 732 438 "Turn a screen" "For a monitor that stands on its side (a vertical monitor). Pick the screen on the map or under Real size, then choose which way it is turned.`n`nThe map flips that screen to portrait, and the Builder and cutter size and cut its piece that way, even next to landscape screens. The piece is rotated back so it looks upright on the real monitor.`n`nTurned right = the top of the screen faces your right. Turned left = faces your left.`n`nIf you already rotated the screen in Windows (Settings > Display > Orientation), leave this on Normal - the map follows Windows on its own. After changing it, use Refit packs for panoramas you already made."))
$cmbOrient = New-StyledCombo 608 462 220
$script:cmbOrient = $cmbOrient
foreach ($o in @("Normal", "Turned Right", "Upside Down", "Turned Left")) { [void]$cmbOrient.Items.Add($o) }
$cmbOrient.SelectedIndex = 0
$pnlDisp.Controls.Add($cmbOrient)
$btnTurn = New-Btn "Turn" 836 462 80 'cyan' 28
$pnlDisp.Controls.Add($btnTurn)
$tt.SetToolTip($cmbOrient, "Which way the picked screen is physically turned")
$tt.SetToolTip($btnTurn, "Flip the picked screen on the map and in the cutter")
$tt.SetToolTip($cmbPhysScreen, "Pick a screen, then set its size")
$tt.SetToolTip($numDiag, "Screen diagonal in inches (as sold, e.g. 27)")
$tt.SetToolTip($numBezel, "Plastic edge on each side of the screen, in millimetres. Typical: 5-15")
$tt.SetToolTip($cmbAlign, "How screens of different heights line up vertically. Picking one clears your dragged positions.")
$tt.SetToolTip($chkPhys, "On: slices follow your real screen sizes and bezels so the picture lines up across screens. Off: simple split by pixels.")
$tt.SetToolTip($btnRefit, "Re-cut your existing panorama packs to match your real screen sizes (originals are kept)")
$tt.SetToolTip($btnIdentify, "Flash a big number on every screen")
$tt.SetToolTip($btnRefreshDisp, "Re-read your screens (also happens when you return to this window)")
$tt.SetToolTip($btnWinDisp, "Open Windows display settings to rearrange or add screens")
$tt.SetToolTip($script:btnSaveLayout, "Keep the screen positions you just dragged")
$tt.SetToolTip($script:btnUndoLayout, "Put the screens back where they were")

# ================================================================ BUILDER TAB
$pnlBuild = New-Object System.Windows.Forms.Panel
$script:pnlBuild = $pnlBuild
$pnlBuild.Location = New-Object System.Drawing.Point(0, 108)
$pnlBuild.Size = New-Object System.Drawing.Size(940, 492)
$pnlBuild.BackColor = $script:cBg
$pnlBuild.Visible = $false
$form.Controls.Add($pnlBuild)

# one field: the picture with your screens over it, plus a bar with every screen (drop files, link with +)
$pnlBtSrc = New-Object System.Windows.Forms.Panel
$script:pnlBtSrc = $pnlBtSrc
$pnlBtSrc.Location = New-Object System.Drawing.Point(24, 0)
$pnlBtSrc.Size = New-Object System.Drawing.Size(892, 246)
$script:pnlBt = $pnlBtSrc
$pnlBtSrc.BackColor = [System.Drawing.Color]::Black
$pnlBtSrc.AllowDrop = $true
$pnlBtSrc.Cursor = [System.Windows.Forms.Cursors]::SizeAll
Set-DoubleBuffered $pnlBtSrc
$pnlBtSrc.Add_Paint({ param($s, $e) Invoke-BtSrcPaint $e.Graphics $s.ClientSize.Width $s.ClientSize.Height })
$pnlBuild.Controls.Add($pnlBtSrc)

$script:lblBtSel = New-Label "" 24 252 860 22 $false 10
$pnlBuild.Controls.Add($script:lblBtSel)
$pnlBuild.Controls.Add((New-HelpButton 892 251 "Builder help" ("The Builder lays out a whole pack.`n`n" +
    "- Big field: the selected picture with your screens laid over it. Drag to move the screens over the photo, scroll to zoom, or drag a corner square to resize the screens over the photo. Bright parts become wallpaper.`n" +
    "- Bar at the bottom: every screen and what it shows. Click one to select it. Drag pictures or videos from your desktop onto a screen (or the field) to place them; several files fill the screens in order.`n" +
    "- A screen that has its own picture or video is taken out of the panorama cut, so the other screens get more room on the photo.`n" +
    "- Click the + between two screens to link them: one picture (a panorama) is then cut across all linked screens. Click = to unlink.`n" +
    "- To put a different picture or video on ONE screen of a panorama, select that screen and use Picture... / Video... or drop the file on it. The panorama stays on the other screens (the screen shows ALT). Clear on that screen removes the swap.`n" +
    "- To replace the whole panorama, select a screen without a swap, press Clear, then add the new picture.`n" +
    "- Upscale (AI) sharpens the selected picture when you save, using the Model, AI amount and Grain settings on the Upscale row. Upscale all turns it on for every picture.`n" +
    "- Videos are cut with ffmpeg (Tools\ffmpeg) and played by Lively when the pack is applied.`n" +
    "- Load pack opens the pack selected on the Packs tab, including its original picture. Saving with the same name updates that pack; a new name makes a new one.`n" +
    "- Right-click a screen for quick actions.")))

$btnBtPic   = New-Btn "Picture..." 24 278 130 'normal' 32
$btnBtVid   = New-Btn "Video..." 162 278 130 'normal' 32
$btnBtClear = New-Btn "Clear" 300 278 130 'normal' 32
$script:btnBtClear = $btnBtClear
$btnBtLock  = New-Btn "Lock screen" 438 278 130 'cyan' 32
$btnBtSaver = New-Btn "Screen saver" 576 278 140 'cyan' 32
$tt.SetToolTip($btnBtSaver, "Open the screen saver settings")
foreach ($b in @($btnBtPic, $btnBtVid, $btnBtClear, $btnBtLock, $btnBtSaver)) { $pnlBuild.Controls.Add($b) }
$tt.SetToolTip($btnBtLock, "Choose the Windows lock screen picture for the selected pack")
$script:chkBtUp = New-NeonCheck "Upscale (AI)" 24 351 128 28
$script:chkBtUpAll = New-NeonCheck "Upscale All" 156 351 108 28
$pnlBuild.Controls.Add($script:chkBtUp)
$pnlBuild.Controls.Add($script:chkBtUpAll)

# video options (own row)
$pnlBuild.Controls.Add((New-Heading "Selected media" 24 380 300))
$pnlBuild.Controls.Add((New-Heading "Video settings" 358 380 300))
$script:btnBtRotR = New-Btn "Rotate R" 130 402 100 'normal' 28
$script:btnBtRotL = New-Btn "Rotate L" 24 402 100 'normal' 28
$script:btnBtRotL.Font = Get-RetroFont 8; $script:btnBtRotR.Font = Get-RetroFont 8
$pnlBuild.Controls.Add($script:btnBtRotL); $pnlBuild.Controls.Add($script:btnBtRotR)
$script:lblBtRot = New-Label "" 238 407 110 22 $true 9
$pnlBuild.Controls.Add($script:lblBtRot)
$pnlBuild.Controls.Add((New-Label "Start (s)" 358 407 54 22 $true 9))
$script:numBtT0 = New-NeonSpin 414 402 66 0 86400 1 1
$pnlBuild.Controls.Add($script:numBtT0)
$pnlBuild.Controls.Add((New-Label "End (s)" 488 407 44 22 $true 9))
$script:numBtT1 = New-NeonSpin 534 402 66 0 86400 1 1
$pnlBuild.Controls.Add($script:numBtT1)
$script:chkBtBlend = New-NeonCheck "Blend Empty Screens" 24 315 200 28
$pnlBuild.Controls.Add($script:chkBtBlend)
$pnlBuild.Controls.Add((New-Label "Click the + between screens to link them into one panorama. Right-click a screen for more." 236 320 640 22 $true 9))
$pnlBuild.Controls.Add((New-HelpButton 892 380 "Selected media and video settings" ("Rotate R / Rotate L: spin the selected picture or video in 90 degree steps. A video is turned while it is cut, in the same pass, so there is no extra quality loss.`n`n" +
    "Start / End: play only part of the video (seconds). End 0 means to the end. The part loops in Lively.`n`n" +
    "Video quality: Fast makes smaller files quickly, Balanced is the default, Max keeps the most detail but takes the longest and makes bigger files.")))
$script:btnBtRotL.Add_Click({
    $sl = (Get-BtTarget $script:btSel).Slot
    if ($sl -and $sl.type -ne 'none') { $sl.rot = (([int]$sl.rot - 90) + 360) % 360; $script:btDirty = $true; Update-BtInfo } else { Set-Status "Pick a picture or video first." }
})
$script:btnBtRotR.Add_Click({
    $sl = (Get-BtTarget $script:btSel).Slot
    if ($sl -and $sl.type -ne 'none') { $sl.rot = ([int]$sl.rot + 90) % 360; $script:btDirty = $true; Update-BtInfo } else { Set-Status "Pick a picture or video first." }
})
$script:numBtT0.Add_ValueChanged({
    if ($script:loadingBt) { return }
    $sl = (Get-BtTarget $script:btSel).Slot
    if ($sl -and $sl.type -eq 'video') { $sl.t0 = [double]$script:numBtT0.Value; $script:btDirty = $true }
})
$script:numBtT1.Add_ValueChanged({
    if ($script:loadingBt) { return }
    $sl = (Get-BtTarget $script:btSel).Slot
    if ($sl -and $sl.type -eq 'video') { $sl.t1 = [double]$script:numBtT1.Value; $script:btDirty = $true }
})
$script:chkBtBlend.Add_CheckedChanged({ if (-not $script:loadingBt) { $script:btDirty = $true } })

# undo / redo + layout presets
$script:btnBtUndo = New-Btn "Undo" 724 278 90 'normal' 32
$script:btnBtRedo = New-Btn "Redo" 822 278 94 'normal' 32
$script:btnBtUndo.Font = Get-RetroFont 8; $script:btnBtRedo.Font = Get-RetroFont 8
$pnlBuild.Controls.Add($script:btnBtUndo); $pnlBuild.Controls.Add($script:btnBtRedo)
$pnlBuild.Controls.Add((New-HelpButton 892 316 "Linking, undo and blending" ("Blend empty screens: screens with no picture or video get a soft gradient that continues the colors of the pictures next to them, so the desktop looks like one extended background instead of black gaps. It uses pictures only (not videos), and it is made when you save the pack.`n`nUndo / Redo: step back and forward through your changes in the Builder (pictures, positions, zoom, links). Ctrl+Z and Ctrl+Y do the same. History starts fresh when you load a pack or start a new one.`n`nLinking screens: click the + between two screens to cut one picture across them, click = to unlink. Right-click a screen for Link all, Unlink all, or Same picture on every screen.")))
$tt.SetToolTip($script:btnBtUndo, "Undo the last change in the Builder (Ctrl+Z)")
$tt.SetToolTip($script:btnBtRedo, "Redo (Ctrl+Y)")
$script:btnBtUndo.Add_Click({ Invoke-BtUndo })
$script:btnBtRedo.Add_Click({ Invoke-BtRedo })
$script:btHistTimer = New-Object System.Windows.Forms.Timer
$script:btHistTimer.Interval = 300
$script:btHistTimer.Add_Tick({ try { Update-BtHistory } catch { } })
$script:btHistTimer.Start()

$pnlBuild.Controls.Add((New-Label "Pack Name" 24 446 74 22 $true 9))
$script:txtBtName = New-Object System.Windows.Forms.TextBox
$script:txtBtName.Location = New-Object System.Drawing.Point(102, 442)
$script:txtBtName.Size = New-Object System.Drawing.Size(200, 26)
$script:txtBtName.BackColor = $script:cPanel
$script:txtBtName.ForeColor = $script:cText
$script:txtBtName.BorderStyle = 'FixedSingle'
$script:txtBtName.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$pnlBuild.Controls.Add($script:txtBtName)
$btnBtSave = New-Btn "Save pack" 312 440 120 'primary' 32
$btnBtLoad = New-Btn "Load pack" 440 440 120 'normal' 32
$btnBtNew  = New-Btn "New" 568 440 84 'normal' 32
foreach ($b in @($btnBtSave, $btnBtLoad, $btnBtNew)) { $pnlBuild.Controls.Add($b) }
$script:chkBtApply = New-NeonCheck "Apply After Saving" 668 442 200 28
$pnlBuild.Controls.Add($script:chkBtApply)

# upscale settings (used by Upscale (AI) here and by Upscale / Up + slice on the Packs tab)
$pnlBuild.Controls.Add((New-Label "Model" 276 356 46 22 $true 9))
$cmbModel.Location = New-Object System.Drawing.Point(324, 352)
$cmbModel.Width = 130
$pnlBuild.Controls.Add($cmbModel)
$pnlBuild.Controls.Add((New-Label "AI Amount" 466 356 68 22 $true 9))
$cmbMix.Location = New-Object System.Drawing.Point(536, 352)
$cmbMix.Width = 84
$pnlBuild.Controls.Add($cmbMix)
$pnlBuild.Controls.Add((New-Label "Grain" 632 356 40 22 $true 9))
$cmbGrain.Location = New-Object System.Drawing.Point(674, 352)
$cmbGrain.Width = 84
$pnlBuild.Controls.Add($cmbGrain)
$pnlBuild.Controls.Add((New-Label "Quality" 612 407 48 22 $true 9))
$script:cmbVidQ = New-StyledCombo 662 402 120
foreach ($o in @("Fast", "Balanced", "Max")) { [void]$script:cmbVidQ.Items.Add($o) }
$vq = [string](Get-Settings).VideoQuality
if ($script:cmbVidQ.Items.Contains($vq)) { $script:cmbVidQ.SelectedItem = $vq } else { $script:cmbVidQ.SelectedItem = "Balanced" }
$script:cmbVidQ.Add_SelectedIndexChanged({ Save-Setting 'VideoQuality' ([string]$script:cmbVidQ.SelectedItem) })
$pnlBuild.Controls.Add($script:cmbVidQ)
$tt.SetToolTip($script:cmbVidQ, "How carefully videos are re-encoded when cut for your screens. Max keeps the most detail but is slower and makes bigger files.")
Reset-Bt

# ---------------------------------------------------------------- add-ons: hide features whose program is missing
$script:upCtl = @($pnlBuild.Controls | Where-Object { $_ -isnot [System.Windows.Forms.Panel] -and $_.Top -ge 349 -and $_.Top -le 358 -and $_.Height -lt 40 })
$script:vidCtl = @($pnlBuild.Controls | Where-Object { $_ -isnot [System.Windows.Forms.Panel] -and $_.Top -ge 385 -and $_.Top -le 395 -and $_.Height -lt 40 }) + @($btnBtVid)
# remembers where each Builder control sat, so rows can close up when the upscale / video rows are hidden
$script:btOrigTop = @{}
foreach ($c in $pnlBuild.Controls) { $script:btOrigTop[$c] = [int]$c.Top }
function Update-BuilderLayout([bool]$showUp, [bool]$showVid) {
    # rows, bottom to top: (name of row, original top range, gap above it, visible?)
    $rows = @(
        @{ Lo = 385; Hi = 395; Gap = 53; Show = $showVid },
        @{ Lo = 349; Hi = 358; Gap = 36; Show = $showUp },
        @{ Lo = 312; Hi = 322; Gap = 36; Show = $true },
        @{ Lo = 276; Hi = 280; Gap = 37; Show = $true },
        @{ Lo = 249; Hi = 254; Gap = 26; Show = $true }
    )
    $y = 440      # the pack-name row stays at the bottom
    $delta = @()
    $origY = 440
    foreach ($r in $rows) {
        $origY = $origY - $r.Gap
        if ($r.Show) { $y = $y - $r.Gap } else { $y = $y }
        $r.NewY = $y; $r.OrigY = $origY
    }
    foreach ($c in $pnlBuild.Controls) {
        if (-not $script:btOrigTop.ContainsKey($c)) { continue }
        $ot = $script:btOrigTop[$c]
        if ($c -is [System.Windows.Forms.Panel]) { continue }
        foreach ($r in $rows) {
            if ($ot -ge $r.Lo -and $ot -le $r.Hi) { $c.Top = $ot + ($r.NewY - $r.OrigY); break }
        }
    }
    $lblTop = $rows[4].NewY
    $h = [math]::Max(246, $lblTop - 6)
    if ($script:pnlBtSrc.Height -ne $h) { $script:pnlBtSrc.Height = $h; $script:pnlBtSrc.Invalidate() }
}

function Update-AddonVisibility {
    $up = Test-AddonOn 'upscale'
    foreach ($c in $script:upCtl) { $c.Visible = $up }
    $liv = Test-AddonOn 'lively'
    $vid = ($liv -and (Test-AddonOn 'ffmpeg'))
    foreach ($c in $script:vidCtl) { $c.Visible = $vid }
    Update-BuilderLayout $up $vid
    $script:tabs[1].Hidden = (-not $liv)
    $x = 24
    foreach ($t in $script:tabs) { if ($t.Hidden) { continue }; $t.X = $x; $x += $t.W + 8 }
    $script:pnlHeader.Invalidate()
    if (-not $liv -and $script:activeTab -eq 1) { Switch-Tab 0 }
}

# ---------------------------------------------------------------- lock screen setup (covers the Builder while open)
$script:lockShown = $false
$script:lockBusy = $false
$script:lockBmp = $null
$script:lockLive = $null
$script:lockNoteExtra = ''
$pnlLock = New-Object System.Windows.Forms.Panel
$script:pnlLock = $pnlLock
$pnlLock.Location = New-Object System.Drawing.Point(0, 0)
$pnlLock.Size = New-Object System.Drawing.Size(940, 492)
$pnlLock.BackColor = $script:cBg
$pnlLock.Visible = $false
$pnlBuild.Controls.Add($pnlLock)

$pnlLock.Controls.Add((New-Heading "Lock screen" 24 16 400))
$script:lblLockPack = New-Label "" 24 40 420 22 $true 10
$pnlLock.Controls.Add($script:lblLockPack)
$pnlLock.Controls.Add((New-HelpButton 440 14 "Lock screen" ("The Windows lock screen (what you see at boot and after Win+L) shows one picture, and only on your main screen. This page decides what that picture is for the pack selected on the Packs tab.`n`n" +
    "- Windows Default: no custom lock screen for this pack. This is the default.`n- Pack Thumbnail: the same picture as the pack's card on the Packs tab (a slice of every screen, or the center screen for a panorama).`n" +
    "- All Screens: every screen's picture side by side, so you see everything that is on your desktop.`n" +
    "- My Own Picture: any picture you choose, just for this pack.`n- One Screen: the picture from just one screen of the pack, chosen in the box beside it.`n- Random Picture: a different picture from the pack each time the lock screen is set.`n- Panorama: if the pack was built from one wide picture in the Builder, that picture is used, shown with one screen-shaped frame. Drag the frame to choose which part becomes the lock screen, drag a corner square (or scroll) to resize it.`n`n" +
    "The lock screen follows your packs: whenever a pack is applied (Apply, Random, shuffle, Schedule), its lock screen is set too. A pack with 'Windows Default' puts Windows' own lock screen back. 'Set Lock Screen Now' sends it to Windows right away.`n`n" +
    "If nothing changes, open Settings > Personalization > Lock screen and set it to 'Picture' (not Windows Spotlight).")))
$pnlLock.Controls.Add((New-Heading "Shows" 24 82 400))
$script:cmbLockMode = New-StyledCombo 24 110 340
foreach ($o in @("Windows Default", "Pack Thumbnail", "All Screens", "One Screen", "Random Picture", "My Own Picture", "Panorama")) { [void]$script:cmbLockMode.Items.Add($o) }
$script:cmbLockMode.SelectedIndex = 0
$pnlLock.Controls.Add($script:cmbLockMode)

$script:pnlLockPrev = New-Object System.Windows.Forms.Panel
$script:pnlLockPrev.Location = New-Object System.Drawing.Point(488, 46)
$script:pnlLockPrev.Size = New-Object System.Drawing.Size(448, 252)
Set-DoubleBuffered $script:pnlLockPrev
$script:lockEdit = $null
$script:lockDrag = $null
$script:pnlLockPrev.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.Clear($script:cPanel2)
    $PW = $s.ClientSize.Width; $PH = $s.ClientSize.Height
    if ($script:lockEdit) {
        $img = $script:lockEdit.Img
        $iw = [double]$img.Width; $ih = [double]$img.Height
        $sc = [math]::Min($PW / $iw, $PH / $ih)
        $ox = ($PW - $iw * $sc) / 2; $oy = ($PH - $ih * $sc) / 2
        $script:lockEdit.Sc = $sc; $script:lockEdit.Ox = $ox; $script:lockEdit.Oy = $oy
        $g.InterpolationMode = 'HighQualityBilinear'
        $g.DrawImage($img, [single]$ox, [single]$oy, [single]($iw * $sc), [single]($ih * $sc))
        $geo = Get-LockGeo $iw $ih $script:lockLive
        if ($geo) {
            $gx = [single]($ox + $geo.Left * $sc); $gy = [single]($oy + $geo.Top * $sc)
            $gw = [single]($geo.W * $sc); $gh = [single]($geo.H * $sc)
            $dim = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(150, 0, 0, 0))
            $path = New-Object System.Drawing.Drawing2D.GraphicsPath
            $path.AddRectangle((New-Object System.Drawing.RectangleF([single]$ox, [single]$oy, [single]($iw * $sc), [single]($ih * $sc))))
            $path.AddRectangle((New-Object System.Drawing.RectangleF($gx, $gy, $gw, $gh)))
            $g.FillPath($dim, $path)
            $path.Dispose(); $dim.Dispose()
            $penA = New-Object System.Drawing.Pen($script:cAccent, 3)
            $g.DrawRectangle($penA, $gx, $gy, $gw, $gh)
            $penA.Dispose()
            $hb = New-Object System.Drawing.SolidBrush($script:cAccent)
            $hp = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 1.5)
            foreach ($pt in @(@($gx, $gy), @(($gx + $gw), $gy), @($gx, ($gy + $gh)), @(($gx + $gw), ($gy + $gh)))) {
                $g.FillRectangle($hb, [single]($pt[0] - 5), [single]($pt[1] - 5), 10, 10)
                $g.DrawRectangle($hp, [single]($pt[0] - 5), [single]($pt[1] - 5), 10, 10)
            }
            $hb.Dispose(); $hp.Dispose()
        }
    }
    elseif ($script:lockBmp) { $g.DrawImage($script:lockBmp, 0, 0, $PW, $PH) }
    else { $br = New-Object System.Drawing.SolidBrush($script:cDim); $g.DrawString("Windows default lock screen (nothing custom)", $script:gFSmall, $br, 12, 12); $br.Dispose() }
    $pen = New-Object System.Drawing.Pen($script:cCyan, 1)
    $g.DrawRectangle($pen, 0, 0, $PW - 1, $PH - 1)
    $pen.Dispose()
})
# which corner of the lock frame (if any) is under the mouse; returns the opposite corner as anchor (panel pixels)
function Get-LockHandle([int]$x, [int]$y) {
    if (-not $script:lockEdit) { return $null }
    $img = $script:lockEdit.Img; $sc = $script:lockEdit.Sc
    $geo = Get-LockGeo ([double]$img.Width) ([double]$img.Height) $script:lockLive
    if (-not $geo) { return $null }
    $l = $script:lockEdit.Ox + $geo.Left * $sc; $t = $script:lockEdit.Oy + $geo.Top * $sc
    $r = $l + $geo.W * $sc; $b = $t + $geo.H * $sc
    $cs = @(
        @{ X = $l; Y = $t; AX = $r; AY = $b; Cur = 'SizeNWSE' },
        @{ X = $r; Y = $t; AX = $l; AY = $b; Cur = 'SizeNESW' },
        @{ X = $l; Y = $b; AX = $r; AY = $t; Cur = 'SizeNESW' },
        @{ X = $r; Y = $b; AX = $l; AY = $t; Cur = 'SizeNWSE' })
    foreach ($c in $cs) { if ([math]::Abs($x - $c.X) -le 9 -and [math]::Abs($y - $c.Y) -le 9) { return $c } }
    return $null
}

$script:pnlLockPrev.Add_MouseDown({
    param($s, $e)
    if (-not $script:lockEdit -or $e.Button -ne 'Left') { return }
    $h = Get-LockHandle $e.X $e.Y
    if ($h) { $script:lockDrag = @{ Mode = 'size'; AX = $h.AX; AY = $h.AY } }
    else { $script:lockDrag = @{ Mode = 'move'; X = $e.X; Y = $e.Y; Cx = [double]$script:lockLive.cx; Cy = [double]$script:lockLive.cy } }
})
$script:pnlLockPrev.Add_MouseMove({
    param($s, $e)
    if (-not $script:lockEdit) { return }
    $img = $script:lockEdit.Img; $sc = $script:lockEdit.Sc
    if (-not $script:lockDrag) {
        $h = Get-LockHandle $e.X $e.Y
        if ($h) { $s.Cursor = [System.Windows.Forms.Cursors]::($h.Cur) } else { $s.Cursor = [System.Windows.Forms.Cursors]::SizeAll }
        return
    }
    if ($script:lockDrag.Mode -eq 'move') {
        $script:lockLive.cx = [math]::Max(0.0, [math]::Min(1.0, $script:lockDrag.Cx + (($e.X - $script:lockDrag.X) / $sc) / $img.Width))
        $script:lockLive.cy = [math]::Max(0.0, [math]::Min(1.0, $script:lockDrag.Cy + (($e.Y - $script:lockDrag.Y) / $sc) / $img.Height))
    } else {
        $ps = Get-PrimarySize
        $asp = [double]$ps.W / [double]$ps.H
        $iw = [double]$img.Width; $ih = [double]$img.Height
        $gw0 = [math]::Min($iw, $ih * $asp)
        $ax = $script:lockDrag.AX; $ay = $script:lockDrag.AY
        $dx = [math]::Abs($e.X - $ax); $dy = [math]::Abs($e.Y - $ay)
        $wPx = [math]::Max($dx, $dy * $asp)
        $z = [math]::Max(0.2, [math]::Min(1.0, ($wPx / $sc) / $gw0))
        $wPx = $z * $gw0 * $sc; $hPx = $wPx / $asp
        if ($e.X -ge $ax) { $left = $ax } else { $left = $ax - $wPx }
        if ($e.Y -ge $ay) { $top = $ay } else { $top = $ay - $hPx }
        $script:lockLive.z = $z
        $script:lockLive.cx = [math]::Max(0.0, [math]::Min(1.0, ((($left + $wPx / 2) - $script:lockEdit.Ox) / $sc) / $iw))
        $script:lockLive.cy = [math]::Max(0.0, [math]::Min(1.0, ((($top + $hPx / 2) - $script:lockEdit.Oy) / $sc) / $ih))
    }
    $s.Invalidate()
})
$script:pnlLockPrev.Add_MouseUp({
    param($s, $e)
    if ($script:lockDrag) { $script:lockDrag = $null; Save-LockPanel }
})
$script:pnlLockPrev.Add_MouseWheel({
    param($s, $e)
    if (-not $script:lockEdit) { return }
    $z = [double]$script:lockLive.z * [math]::Pow(1.1, -($e.Delta / 120.0))
    $script:lockLive.z = [math]::Max(0.2, [math]::Min(1.0, $z))
    $s.Invalidate()
    Save-LockPanel
})
$script:pnlLockPrev.Add_MouseEnter({ param($s, $e) try { if ($script:lockEdit) { [void]$s.Focus() } } catch { } })
$pnlLock.Controls.Add((New-Heading "Preview" 488 16 448))
$pnlLock.Controls.Add($script:pnlLockPrev)

$script:lblLockNote = New-Label "" 24 150 440 62 $true 9
$pnlLock.Controls.Add($script:lblLockNote)
$pnlLock.Controls.Add((New-Heading "Options" 24 214 400))
$pnlLock.Controls.Add((New-Label "Screen" 24 250 56 22 $true 9))
$script:cmbLockScreen = New-StyledCombo 84 246 100
$pnlLock.Controls.Add($script:cmbLockScreen)
$script:chkLockPano = New-NeonCheck "Cut One Screen From a Panorama Picture" 24 284 440 28
$script:btnLockPic = New-Btn "Choose Picture..." 24 284 190 'normal' 32
$pnlLock.Controls.Add($script:btnLockPic)
$script:btnLockNow = New-Btn "SAVE" 24 332 220 'primary' 36
$pnlLock.Controls.Add($script:btnLockNow)
$script:btnLockSpot = New-Btn "Use Windows Spotlight..." 24 378 220 'normal' 32
$pnlLock.Controls.Add($script:btnLockSpot)
$script:btnLockBack = New-Btn "Close" 488 396 120 'normal' 32
$pnlLock.Controls.Add($script:btnLockBack)

$script:lockModes = @('none', 'thumb', 'screens', 'screen', 'cycle', 'custom', 'pano')
function Update-LockPanel {
    $name = [string]$script:btPack
    $script:lockBusy = $true
    try {
        if (-not $name) {
            $script:lblLockPack.Text = ""
            $script:lblLockNote.Text = "Save this pack in the Builder first (or load one), then set its lock screen here."
            if ($script:lockBmp) { $script:lockBmp.Dispose(); $script:lockBmp = $null }
            $script:pnlLockPrev.Invalidate()
            return
        }
        $dir = Join-Path $Root $name
        $cfg = Get-LockCfg $dir
        $script:lblLockPack.Text = $name
        $script:cmbLockMode.SelectedIndex = [math]::Max(0, [array]::IndexOf($script:lockModes, [string]$cfg.mode))
        $script:chkLockPano.Checked = $false
        $nScr = [math]::Max(1, @(Get-DisplayList).Count)
        $script:cmbLockScreen.Items.Clear()
        for ($i = 1; $i -le $nScr; $i++) { [void]$script:cmbLockScreen.Items.Add([string]$i) }
        $script:cmbLockScreen.SelectedIndex = [math]::Max(0, [math]::Min($nScr - 1, [int]$cfg.screen - 1))
        $script:btnLockPic.Enabled = ($cfg.mode -eq 'custom')
        $script:chkLockPano.Enabled = $true
        $script:cmbLockScreen.Enabled = ($cfg.mode -eq 'screen')
        switch ([string]$cfg.mode) {
            'none'    { $script:lblLockNote.Text = "No lock screen chosen for this pack. Applying it puts Windows' default lock screen back (if this app changed it before)." }
            'screens' { $script:lblLockNote.Text = "Every screen's picture side by side, so the lock screen shows what is on your whole desktop. Windows only shows it on your main screen." }
            'screen'  { $script:lblLockNote.Text = "Just one screen's picture from this pack. Pick the screen number (left to right) below." }
            'pano'    { $script:lblLockNote.Text = "The panorama this pack was built from. The bright frame is one screen's worth of it, and that part becomes the lock screen. Drag the frame to move it, drag a corner square (or scroll) to resize it." }
            'cycle'   { $script:lblLockNote.Text = "A different picture from this pack each time you lock. The control center picks the next one when you unlock, so it has to stay running in the tray." }
            'custom'  { if ($cfg.file) { $script:lblLockNote.Text = "Your own picture for this pack. Tick 'panorama' to choose one screen's part of a wide picture by sliding a frame over it." } else { $script:lblLockNote.Text = "Click Choose picture... to pick a picture for this pack." } }
            default   { $script:lblLockNote.Text = "The same picture as this pack's card on the Packs tab. Windows only shows it on your main screen." }
        }
        # panorama editor: the pack's own panorama (or your picture, cut as a panorama) with the screens laid over it
        $editFile = $null
        if ($cfg.mode -eq 'pano') { $pp = Get-PackPano $dir; if ($pp) { $editFile = $pp.File } }
        elseif ($cfg.mode -eq 'custom' -and $cfg.pano -and $cfg.file) {
            $cf = Join-Path (Join-Path $dir '_lock') ([string]$cfg.file)
            if (Test-Path -LiteralPath $cf) { $editFile = $cf }
        }
        $script:lockLive = $cfg
        if ($editFile) {
            if (-not $script:lockEdit -or $script:lockEdit.File -ne $editFile) {
                if ($script:lockEdit) { $script:lockEdit.Img.Dispose(); $script:lockEdit = $null }
                try {
                    $ld = Read-ImageFromFile $editFile
                    try {
                        $mw = [math]::Min(1100, $ld.Image.Width)
                        $mh = [int][math]::Max(1, [math]::Round($ld.Image.Height * $mw / $ld.Image.Width))
                        $sm = New-Object System.Drawing.Bitmap($mw, $mh)
                        $gg = [System.Drawing.Graphics]::FromImage($sm)
                        $gg.InterpolationMode = 'HighQualityBicubic'
                        $gg.DrawImage($ld.Image, 0, 0, $mw, $mh)
                        $gg.Dispose()
                        $script:lockEdit = @{ File = $editFile; Img = $sm; Sc = 1.0; Ox = 0.0; Oy = 0.0 }
                    } finally { $ld.Image.Dispose(); $ld.Stream.Dispose() }
                } catch { $script:lockEdit = $null }
            }
            $script:pnlLockPrev.Cursor = [System.Windows.Forms.Cursors]::SizeAll
            if ($script:lockEdit) { $script:lockNoteExtra = " Drag the frame to move it, drag a corner square to resize it (or scroll). What is inside the frame becomes the lock screen." }
        } else {
            if ($script:lockEdit) { $script:lockEdit.Img.Dispose(); $script:lockEdit = $null }
            $script:pnlLockPrev.Cursor = [System.Windows.Forms.Cursors]::Default
        }
        $old = $script:lockBmp
        $script:lockBmp = $null
        if (-not $script:lockEdit) {
            try { $script:lockBmp = New-LockBmp $dir $cfg 512 288 } catch { $script:lockBmp = $null }
        }
        if ($old) { $old.Dispose() }
        if ($script:lockEdit) { $script:lblLockNote.Text = $script:lblLockNote.Text + $script:lockNoteExtra }
        $script:cmbLockScreen.Enabled = ($cfg.mode -eq 'screen')
        $script:pnlLockPrev.Invalidate()
    } finally { $script:lockBusy = $false }
}

function Save-LockPanel {
    if ($script:lockBusy) { return }
    $name = [string]$script:btPack
    if (-not $name) { return }
    $dir = Join-Path $Root $name
    $cfg = Get-LockCfg $dir
    $cfg.mode = $script:lockModes[[math]::Max(0, $script:cmbLockMode.SelectedIndex)]
    $cfg.pano = [bool]$script:chkLockPano.Checked
    $cfg.screen = [math]::Max(1, $script:cmbLockScreen.SelectedIndex + 1)
    if ($script:lockLive) { $cfg.cx = [double]$script:lockLive.cx; $cfg.cy = [double]$script:lockLive.cy; $cfg.z = [double]$script:lockLive.z }
    Save-LockCfg $dir $cfg
}

function Select-LockPicture {
    $name = [string]$script:btPack
    if (-not $name) { return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Pick a lock screen picture"
    $dlg.Filter = "Pictures|*.jpg;*.jpeg;*.png;*.bmp|All files|*.*"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }
    try {
        $dir = Join-Path $Root $name
        $ld = Join-Path $dir '_lock'
        if (-not (Test-Path -LiteralPath $ld)) { [void](New-Item -ItemType Directory -Path $ld -Force) }
        foreach ($f in @(Get-ChildItem -LiteralPath $ld -Filter 'custom.*' -ErrorAction SilentlyContinue)) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
        $fn = 'custom' + [IO.Path]::GetExtension($dlg.FileName).ToLower()
        Copy-Item -LiteralPath $dlg.FileName -Destination (Join-Path $ld $fn) -Force
        $cfg = Get-LockCfg $dir
        $cfg.mode = 'custom'; $cfg.file = $fn
        Save-LockCfg $dir $cfg
        Update-LockPanel
    } catch { Set-Status "Couldn't use that picture: $($_.Exception.Message)" }
}

$script:lockForm = $null
function Show-LockPanel([bool]$on) {
    if (-not $on) {
        if ($script:lockForm) { try { $script:lockForm.Close() } catch { } }
        return
    }
    if ($script:lockForm) { return }
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Lock Screen"
    $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false; $f.MinimizeBox = $false; $f.ShowInTaskbar = $false
    $f.BackColor = $script:cBg; $f.ForeColor = $script:cText
    $f.Font = New-Object System.Drawing.Font("Segoe UI", 10)
    if ($script:appIcon) { $f.Icon = $script:appIcon }
    $f.Add_HandleCreated({ param($s, $e) Set-TitleBar $s.Handle })
    $f.ClientSize = New-Object System.Drawing.Size(960, 440)
    $script:lockForm = $f
    $script:pnlBuild.Controls.Remove($script:pnlLock)
    $script:pnlLock.Dock = 'Fill'
    $script:pnlLock.Visible = $true
    $f.Controls.Add($script:pnlLock)
    $script:lockShown = $true
    Update-LockPanel
    try { [void]$f.ShowDialog($script:form) }
    finally {
        $script:lockShown = $false
        $f.Controls.Remove($script:pnlLock)
        $script:pnlLock.Dock = 'None'
        $script:pnlLock.Visible = $false
        $script:pnlBuild.Controls.Add($script:pnlLock)
        $script:lockForm = $null
        $f.Dispose()
    }
}

$btnBtLock.Add_Click({
    if (-not $script:btPack) { Set-Status "Save this pack first (give it a name and press Save), then set its lock screen."; return }
    Show-LockPanel $true
})
$btnBtSaver.Add_Click({ Show-SaverDialog })
$script:btnLockBack.Add_Click({ Show-LockPanel $false })
$script:cmbLockMode.Add_SelectedIndexChanged({
    if ($script:lockBusy) { return }
    Save-LockPanel
    $nm = [string]$script:btPack
    $needPic = $false
    if ($nm -and $script:lockModes[$script:cmbLockMode.SelectedIndex] -eq 'custom') { if (-not (Get-LockCfg (Join-Path $Root $nm)).file) { $needPic = $true } }
    Update-LockPanel
    if ($needPic) { Select-LockPicture }
})
$script:chkLockPano.Add_CheckedChanged({
    if ($script:lockBusy) { return }
    $nm = [string]$script:btPack
    if (-not $nm) { return }
    if ($script:chkLockPano.Checked -and $script:lockModes[$script:cmbLockMode.SelectedIndex] -ne 'custom') {
        $script:lockBusy = $true; $script:cmbLockMode.SelectedIndex = [array]::IndexOf($script:lockModes, 'custom'); $script:lockBusy = $false
    }
    Save-LockPanel
    $needPic = ($script:chkLockPano.Checked -and -not (Get-LockCfg (Join-Path $Root $nm)).file)
    Update-LockPanel
    if ($needPic) { Select-LockPicture }
})
$script:cmbLockScreen.Add_SelectedIndexChanged({ if ($script:lockBusy) { return }; Save-LockPanel; Update-LockPanel })
$script:btnLockPic.Add_Click({ Select-LockPicture })
$script:btnLockNow.Add_Click({
    $nm = [string]$script:btPack
    if (-not $nm) { Set-Status "Save or load a pack in the Builder first."; return }
    Save-LockPanel
    Set-Status "Lock screen saved for '$nm'. It is used when this pack is applied."
    Show-LockPanel $false
})
$tt.SetToolTip($script:btnLockNow, "Save this pack's lock screen options. They take effect when the pack is applied")
$script:btnLockSpot.Add_Click({
    try {
        $k = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        Set-ItemProperty -Path $k -Name 'RotatingLockScreenEnabled' -Value 1 -Type DWord
        Set-ItemProperty -Path $k -Name 'RotatingLockScreenOverlayEnabled' -Value 1 -Type DWord
        Save-Setting 'LockSetByApp' '0'
    } catch { }
    try { Start-Process 'ms-settings:lockscreen' } catch { }
    Set-Status "Windows only lets you switch this yourself: in the Settings window that just opened, set 'Personalize your lock screen' to 'Windows spotlight'."
})
$tt.SetToolTip($script:btnLockSpot, "Open Windows' lock screen settings so you can switch back to Windows Spotlight (Windows doesn't let apps flip that switch)")

# ---------------------------------------------------------------- display-aware refreshing
function Build-PreviewBoxes {
    if (-not $script:pnlPrev) {
        $pv = New-Object System.Windows.Forms.Panel
        $pv.Location = New-Object System.Drawing.Point(668, 66)
        $pv.Size = New-Object System.Drawing.Size(248, 80)
        Set-DoubleBuffered $pv
        $pv.Add_Paint({ param($s, $e) Invoke-MapPaint $s $e })
        $script:pnlPacks.Controls.Add($pv)
        $script:pnlPrev = $pv
    }
    $script:pnlPrev.Invalidate()
}

# ---------------------------------------------------------------- pinned screens
function Save-PinScreens {
    if ($script:pinBusy) { return }
    $ids = @()
    foreach ($c in @($script:pinChecks)) { if ($c.Checked) { $ids += [int]$c.Tag } }
    Save-Setting 'PinScreens' ($ids -join ',')
    $n = @(Get-DisplayList).Count
    if ($script:chkPinOn.Checked -and $ids.Count -ge $n -and $n -gt 0) { Set-Status "Every screen is pinned, so packs won't change anything until you unpin one." }
}

function Update-PinBoxes {
    if (-not $script:pnlPins) { return }
    $script:pinBusy = $true
    try {
        $saved = @()
        foreach ($t in ([string](Get-Settings).PinScreens -split ',')) { $v = 0; if ([int]::TryParse($t.Trim(), [ref]$v)) { $saved += $v } }
        foreach ($c in @($script:pnlPins.Controls)) { $script:pnlPins.Controls.Remove($c); $c.Dispose() }
        $script:pinChecks = @()
        $ds = @(Get-DisplayList)
        for ($i = 0; $i -lt $ds.Count -and $i -lt 6; $i++) {
            $cx = ($i % 4) * 62
            $cy = [int][math]::Floor($i / 4) * 26
            $c = New-NeonCheck ([string]$ds[$i].Index) $cx $cy 56 26
            $c.Tag = [int]$ds[$i].Index
            $c.Checked = ($saved -contains [int]$ds[$i].Index)
            $c.Add_CheckedChanged({ Save-PinScreens })
            $script:pnlPins.Controls.Add($c)
            $script:pinChecks += $c
        }
    } finally { $script:pinBusy = $false }
}

function Update-MonitorLists {
    $script:rebuildingMon = $true
    try {
        $keep = [string]$script:cmbMon.SelectedItem
        if (-not $keep) { $keep = (Get-Settings).AnimTarget }
        $script:cmbMon.Items.Clear()
        [void]$script:cmbMon.Items.Add("All Monitors")
        [void]$script:cmbMon.Items.Add("Span Across Monitors")
        [void]$script:cmbMon.Items.Add("Cut To My Screens")
        foreach ($d in (Get-DisplayList)) {
            $num = $d.WinNum
            if ($num -le 0) { $num = $d.Index }
            $label = "Display $num - $($d.W)x$($d.H)"
            if ($d.Primary) { $label += " (Main)" }
            [void]$script:cmbMon.Items.Add($label)
        }
        if ($script:cmbMon.Items.Contains($keep)) { $script:cmbMon.SelectedItem = $keep } else { $script:cmbMon.SelectedIndex = 0 }
    } finally {
        $script:rebuildingMon = $false
    }
    Update-PinBoxes
}

# ---------------------------------------------------------------- real size editing
function Update-PhysScreenList {
    $script:loadingPhys = $true
    try {
        $keep = $script:cmbPhysScreen.SelectedIndex
        $script:cmbPhysScreen.Items.Clear()
        foreach ($d in (Get-DisplayList)) { [void]$script:cmbPhysScreen.Items.Add(("{0} - {1}x{2}" -f $d.Index, $d.W, $d.H)) }
        if ($script:cmbPhysScreen.Items.Count -gt 0) {
            if ($keep -lt 0 -or $keep -ge $script:cmbPhysScreen.Items.Count) { $keep = 0 }
            $script:cmbPhysScreen.SelectedIndex = $keep
        }
    } finally { $script:loadingPhys = $false }
    Update-PhysFields
}

function Update-PhysFields {
    $i = $script:cmbPhysScreen.SelectedIndex
    $ds = @(Get-DisplayList)
    if ($i -lt 0 -or $i -ge $ds.Count) { return }
    $p = Get-DisplayPhysical $ds[$i] (Get-DetectedDiagonals $ds)
    $script:loadingPhys = $true
    try {
        $script:numDiag.Value = [decimal][math]::Min(100, [math]::Max(7, $p.Diag))
        $script:numBezel.Value = [decimal][math]::Min(60, [math]::Max(0, $p.Bezel))
    } finally { $script:loadingPhys = $false }
}

function Save-PhysFields {
    if ($script:loadingPhys) { return }
    $i = $script:cmbPhysScreen.SelectedIndex
    $ds = @(Get-DisplayList)
    if ($i -lt 0 -or $i -ge $ds.Count) { return }
    $p = Get-DisplayPhysical $ds[$i] (Get-DetectedDiagonals $ds)
    Save-DisplayPhysical $ds[$i] ([double]$script:numDiag.Value) ([double]$script:numBezel.Value) $p.Raise
    Reset-PhysLayout
    $script:pnlMap.Invalidate()
    Update-Preview
}

function Update-DisplayText { }

function Update-Displays([bool]$force) {
    $sig = Get-DisplaySignature
    if (-not $force -and $sig -eq $script:dispSig) { return }
    $script:dispSig = $sig
    if ($script:layoutDirty) { Undo-LayoutChanges; Set-LayoutDirty $false }
    Build-PreviewBoxes
    Reset-PhysLayout
    $script:edidSizes = $null
    Update-MonitorLists
    Update-PhysScreenList
    Update-DisplayText
    Update-Preview
    $script:pnlMap.Invalidate()
    Set-Status "Screens updated: $(@(Get-DisplayList).Count) detected."
}

# ---------------------------------------------------------------- list refreshing
function Update-Preview {
    if ($script:pnlMap) { $script:pnlMap.Invalidate() }
    if ($script:pnlPrev) { $script:pnlPrev.Invalidate() }
    if ($script:gridCanvas) { $script:gridCanvas.Invalidate(); Show-SelectedInGrid }
    if ($script:lockShown -and $script:activeTab -eq 3) { Update-LockPanel }
    $name = $script:lbPacks.SelectedItem
    if (-not $name) {
        if ($script:lbPacks.Items.Count -gt 0) {
            $script:lblPackName.Text = "No pack selected"
            $script:lblInfo.Text = "Click a pack to see it here."
        } else {
            $script:lblPackName.Text = "No packs yet"
            $script:lblInfo.Text = "Use New pack to make your first one."
        }
        return
    }
    $imgs = @(Get-PackImages (Join-Path $Root $name))
    $script:lblPackName.Text = [string]$name
    $n = @(Get-DisplayList).Count
    if ($imgs.Count -eq 1) { $word = "image" } else { $word = "images" }
    if ($n -eq 1) { $sw = "screen" } else { $sw = "screens" }
    $script:lblInfo.Text = "$($imgs.Count) $word, applied left to right across $n $sw"
}

function Update-PackList([string]$select) {
    Repair-PackNames
    $script:lbPacks.Items.Clear()
    foreach ($p in (Get-Packs)) { [void]$script:lbPacks.Items.Add($p.Name) }
    if ($select -and $script:lbPacks.Items.Contains($select)) { $script:lbPacks.SelectedItem = $select }
    elseif ($script:lbPacks.Items.Count -gt 0) { $script:lbPacks.SelectedIndex = 0 }
    Update-GridTags
    Refresh-Grid
    Request-GridThumbs
    Update-Preview
}

function Update-NowPlaying {
    if ($script:nowPlaying) { $script:lblNow.Text = "Now playing:`n$($script:nowPlaying)" }
    else { $script:lblNow.Text = "" }
}

function Update-AnimPreview {
    $name = $script:lbAnim.SelectedItem
    if (-not $name) {
        $script:lblAnimName.Text = "No videos yet"
        $script:lblAnimInfo.Text = "Click Add videos or drag files onto the list."
        $script:pbAnim.Image = $null
        return
    }
    $path = Join-Path $AnimRoot $name
    $script:lblAnimName.Text = [string]$name
    try {
        $fi = Get-Item -LiteralPath $path
        $script:lblAnimInfo.Text = "{0}  -  {1:N1} MB" -f $fi.Extension.TrimStart('.').ToUpper(), ($fi.Length / 1MB)
        $key = "$path|$($fi.Length)"
        if (-not $script:animThumbs.ContainsKey($key)) {
            $bmp = $null
            if ($script:thumbOk) { $bmp = [ShellThumb]::Get($path, 440, 248) }
            $script:animThumbs[$key] = $bmp
        }
        $script:pbAnim.Image = $script:animThumbs[$key]
    } catch {
        $script:pbAnim.Image = $null
    }
}

function Update-AnimList {
    $keep = $script:lbAnim.SelectedItem
    $script:lbAnim.Items.Clear()
    foreach ($f in (Get-AnimatedFiles)) { [void]$script:lbAnim.Items.Add($f.Name) }
    $n = $script:lbAnim.Items.Count
    if ($keep -and $script:lbAnim.Items.Contains($keep)) { $script:lbAnim.SelectedItem = $keep }
    elseif ($n -gt 0) { $script:lbAnim.SelectedIndex = 0 }
    if ($n -eq 1) { $word = "video" } else { $word = "videos" }
    $script:lblAnimCount.Text = "$n $word  -  mp4, webm, gif, mkv, mov, avi"
    Sync-ThemedBar $script:lbAnim
    Update-AnimPreview
}

function Update-LivelyStatus {
    $p = Get-LivelyPath
    if ($p) {
        $script:lblLively.Text = "READY"
        $script:lblLively.ForeColor = $script:cOk
        $tt.SetToolTip($script:lblLively, $p)
    } else {
        $script:lblLively.Text = "NOT FOUND"
        $script:lblLively.ForeColor = $script:cAccentHover
        $tt.SetToolTip($script:lblLively, "Install Lively, or use Locate... to point at Lively.exe")
    }
}

# ---------------------------------------------------------------- timer + tray
$timer = New-Object System.Windows.Forms.Timer
$script:timer = $timer
$timer.Add_Tick({ Invoke-RandomPack -Auto })

function Update-Timer {
    if ($script:chkShuffle.Checked) {
        $script:timer.Interval = [int]($script:numMin.Value * 60000)
        $script:timer.Start()
        Set-Status "Auto-shuffle on: every $($script:numMin.Value) minute(s)."
    } else {
        $script:timer.Stop()
        Set-Status "Auto-shuffle off."
    }
}

function Show-Main {
    if (-not $script:form.Visible) { try { Switch-Tab 0 } catch { } }
    $script:form.Show()
    $script:form.WindowState = 'Normal'
    $script:form.Activate()
}

$notify = New-Object System.Windows.Forms.NotifyIcon
$script:notify = $notify
$notify.Icon = $script:trayIcon
$notify.Text = "Ekk0h - Wallpaper Studio"
$notify.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add("Open", $null, { Show-Main })
[void]$menu.Items.Add("Next pack", $null, { Step-Pack 1 })
[void]$menu.Items.Add("Previous pack", $null, { Step-Pack -1 })
[void]$menu.Items.Add("Random pack", $null, { Invoke-RandomPack })
[void]$menu.Items.Add("Pause / resume live wallpapers", $null, { Switch-ManualPause })
[void]$menu.Items.Add("Screen saver: preview", $null, {
    $scr = Get-SaverPath
    if ($scr) { Start-Process -FilePath $scr -ArgumentList "/s" }
    else { [void][System.Windows.Forms.MessageBox]::Show("The screen saver file isn't available in this copy.", "Screen saver", 'OK', 'Information') }
})
[void]$menu.Items.Add("Screen saver: settings...", $null, {
    Show-Main
    if ($script:activeTab -ne 4) { $script:prevTab = $script:activeTab; Switch-Tab 4 }
})
[void]$menu.Items.Add("Restart (load an updated version)", $null, { Restart-App })
[void]$menu.Items.Add("Exit", $null, { $script:exiting = $true; $script:form.Close() })
$notify.ContextMenuStrip = $menu
$notify.Add_DoubleClick({ Show-Main })

# ---------------------------------------------------------------- events
function Switch-Tab([int]$i) {
    if ($script:activeTab -eq 2 -and $i -ne 2) { if (-not (Confirm-LayoutPending)) { return } }
    $script:activeTab = $i
    $script:pnlPacks.Visible = ($i -eq 0)
    if ($i -eq 0) { Request-GridThumbs; Refresh-Grid }
    $script:pnlAnim.Visible = ($i -eq 1)
    $script:pnlDisp.Visible = ($i -eq 2)
    $script:pnlBuild.Visible = ($i -eq 3)
    $script:pnlSched.Visible = ($i -eq 4)
    $script:pnlHeader.Invalidate()
    if ($i -eq 4) {
        if (-not $script:settingsBuilt) { $script:settingsBuilt = $true; Build-SettingsContent $script:pnlSched }
        Update-SchedPacks; Update-SchedStatus
        foreach ($r in @($script:addonRows)) { Update-AddonRow $r }
    }
    if ($script:lockShown) { Show-LockPanel $false }
    if ($i -eq 3) {
        Sync-Bt
        # the Builder always starts blank; use Load pack to bring a pack in
        Update-BtInfo
    }
    if ($i -eq 2) { Update-Displays $false; $script:pnlMap.Invalidate() }
}

$lbPacks.Add_SelectedIndexChanged({ Update-Preview })
$btnRandom.Add_Click({ Invoke-RandomPack })
$btnExport.Add_Click({ Export-SelectedPack })
$btnImport.Add_Click({ Import-PackZip })
$tt.SetToolTip($btnExport, "Save the selected pack as one zip file you can share or back up")
$tt.SetToolTip($btnImport, "Add a pack from a zip made with Export")

$btnNewPack.Add_Click({
    if ($script:btDirty) {
        $a = [System.Windows.Forms.MessageBox]::Show("The Builder has unsaved changes. Start a new pack anyway?", "New pack", 'YesNo', 'Question')
        if ($a -ne 'Yes') { Switch-Tab 3; return }
    }
    Reset-Bt
    Switch-Tab 3
    Update-BtInfo
})
$btnOpenPacks.Add_Click({ if (-not (Test-Path -LiteralPath $Root)) { New-Item -ItemType Directory -Path $Root | Out-Null }; Start-Process explorer.exe -ArgumentList "`"$Root`"" })

$cmbModel.Add_SelectedIndexChanged({ if ($script:cmbModel.SelectedItem) { Save-Setting "UpModel" ([string]$script:cmbModel.SelectedItem) } })
$cmbMix.Add_SelectedIndexChanged({ if ($script:cmbMix.SelectedItem) { Save-Setting "UpMix" ([string]$script:cmbMix.SelectedItem) } })
$cmbGrain.Add_SelectedIndexChanged({ if ($script:cmbGrain.SelectedItem) { Save-Setting "UpGrain" ([string]$script:cmbGrain.SelectedItem) } })

$chkShuffle.Add_CheckedChanged({ Update-Timer })
$numMin.Add_ValueChanged({ if ($script:chkShuffle.Checked) { Update-Timer } })

$lbAnim.Add_SelectedIndexChanged({ Update-AnimPreview })
$btnPlay.Add_Click({
    if ($script:lbAnim.SelectedItem) { Start-Animated (Join-Path $AnimRoot $script:lbAnim.SelectedItem) (Get-AnimTarget) }
    else { Set-Status "Add or pick a video first." }
})
$lbAnim.Add_DoubleClick({
    if ($script:lbAnim.SelectedItem) { Start-Animated (Join-Path $AnimRoot $script:lbAnim.SelectedItem) (Get-AnimTarget) }
})
$lbAnim.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Delete') { Remove-SelectedAnim } })
$ctxAnim = New-NeonMenu
[void]$ctxAnim.Items.Add("Play", $null, { if ($script:lbAnim.SelectedItem) { Start-Animated (Join-Path $AnimRoot $script:lbAnim.SelectedItem) (Get-AnimTarget) } })
[void]$ctxAnim.Items.Add("Cut To My Screens...", $null, { if ($script:lbAnim.SelectedItem) { [void](Invoke-VideoCut (Join-Path $AnimRoot $script:lbAnim.SelectedItem) $true) } })
[void]$ctxAnim.Items.Add("-")
[void]$ctxAnim.Items.Add("Remove", $null, { Remove-SelectedAnim })
$ctxAnim.Add_Opening({ param($s, $e) if (-not $script:lbAnim.SelectedItem) { $e.Cancel = $true } })
$lbAnim.ContextMenuStrip = $ctxAnim
$lbAnim.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq 'Right') {
        $ix = $s.IndexFromPoint($e.X, $e.Y)
        if ($ix -ge 0) { $s.SelectedIndex = $ix }
    }
})
$btnRandomAnim.Add_Click({
    $files = @(Get-AnimatedFiles)
    if ($files.Count -eq 0) { Set-Status "No videos in the Animated folder yet."; return }
    $choices = @($files | Where-Object { $_.Name -ne $script:nowPlaying })
    if ($choices.Count -eq 0) { $choices = $files }
    $pick = $choices | Get-Random
    $script:lbAnim.SelectedItem = $pick.Name
    Start-Animated $pick.FullName (Get-AnimTarget)
})
$btnStopAnim.Add_Click({ Stop-Animated; Update-NowPlaying; Set-Status "Animated wallpapers stopped." })
$btnAddAnim.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Multiselect = $true
    $dlg.Filter = "Videos|*.mp4;*.webm;*.gif;*.mkv;*.mov;*.avi"
    $dlg.Title = "Pick animated wallpaper files to add"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    Add-AnimFiles $dlg.FileNames
})
$btnOpenAnim.Add_Click({ [void](Get-AnimatedFiles); Start-Process explorer.exe -ArgumentList "`"$AnimRoot`"" })
$btnRemoveAnim.Add_Click({ Remove-SelectedAnim })
$btnGetLively.Add_Click({ Start-Process "https://github.com/rocksdanister/lively" })
$btnLocateLively.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Lively|Lively.exe;livelycu.exe|Programs|*.exe"
    $dlg.Title = "Find Lively.exe"
    if ($dlg.ShowDialog() -ne 'OK') { return }
    Save-Setting "LivelyPath" $dlg.FileName
    Update-LivelyStatus
    Set-Status "Using Lively at: $($dlg.FileName)"
})
$cmbMon.Add_SelectedIndexChanged({
    if (-not $script:rebuildingMon -and $script:cmbMon.SelectedItem) { Save-Setting "AnimTarget" ([string]$script:cmbMon.SelectedItem) }
})
$cmbSound.Add_SelectedIndexChanged({
    Save-Setting "AnimSound" ([string]$script:cmbSound.SelectedItem)
    if (Test-LivelyRunning) { [void](Invoke-Lively @("app", "--volume", "$(Get-SoundLevel)") 100) }
})

# drag video files onto the list to add them
$lbAnim.Add_DragEnter({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' }
})
$lbAnim.Add_DragDrop({
    param($s, $e)
    Add-AnimFiles ([string[]]$e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
})

# drop pictures anywhere on the window: the pack builder opens with them already placed on your screens
$form.AllowDrop = $true
$script:pendingDrop = $null
$script:dropTimer = New-Object System.Windows.Forms.Timer
$script:dropTimer.Interval = 60
$script:dropTimer.Add_Tick({
    $script:dropTimer.Stop()
    $files = $script:pendingDrop
    $script:pendingDrop = $null
    if ($files) {
        $was = $script:activeTab
        $script:btSkipLoad = $true; Switch-Tab 3; $script:btSkipLoad = $false
        if ($was -ne 3 -and -not $script:btDirty) { Reset-Bt }
        Add-BtFiles $files -1
    }
})
$form.Add_DragEnter({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' }
})
$form.Add_DragDrop({
    param($s, $e)
    $paths = [string[]]$e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    $vids = @($paths | Where-Object { (Test-Path -LiteralPath $_ -PathType Leaf) -and ([IO.Path]::GetExtension($_) -match $VideoExt) })
    if ($script:activeTab -eq 1 -and $vids.Count -gt 0) { Add-AnimFiles $vids; return }
    $imgs = @(Expand-ImagePaths $paths)
    if ($imgs.Count -gt 0 -or ($script:activeTab -eq 3 -and $vids.Count -gt 0)) {
        $script:pendingDrop = [string[]]$paths
        $script:dropTimer.Start()      # open the builder after the drop finishes, so Explorer isn't left waiting
        return
    }
    if ($vids.Count -gt 0) { Switch-Tab 1; Add-AnimFiles $vids; return }
    Set-Status "Drop pictures (jpg, png, bmp) to make a pack, or videos on the Animated tab."
})


# ---- builder tab events
$script:btDrag = $null
$pnlBtSrc.Add_MouseEnter({ $script:pnlBtSrc.Focus() | Out-Null })
$pnlBtSrc.Add_MouseDown({
    param($s, $e)
    if ($e.Button -eq 'Left') {
        $hd = Get-BtHandle $e.X $e.Y
        if ($hd) { $script:btDrag = @{ Mode = 'size'; Anchor = $hd }; return }
    }
    foreach ($lp in $script:btLinkPts) {
        if ([math]::Abs($e.X - $lp.X) -le 12 -and [math]::Abs($e.Y - $lp.Y) -le 12) {
            if ($e.Button -eq 'Left') { Switch-BtLink ([int]$lp.I); $s.Refresh() }
            return
        }
    }
    $h = Get-BtHit $e.X $e.Y
    if ($h) {
        $script:btSel = [int]$h.Screen
        Update-BtInfo
        $s.Refresh()
        if ($e.Button -eq 'Right') { $script:ctxBt.Show($s, (New-Object System.Drawing.Point($e.X, $e.Y))); return }
        if ($h.Chip) { return }
    }
    $t = Get-BtTarget $script:btSel
    if ($e.Button -eq 'Left' -and $t.Slot.type -ne 'none' -and $script:btSrcMap) { $script:btDrag = @{ X = $e.X; Y = $e.Y; Cx = [double]$t.Slot.cx; Cy = [double]$t.Slot.cy } }
})
$pnlBtSrc.Add_MouseMove({
    param($s, $e)
    if (-not $script:btDrag -or -not $script:btSrcMap) {
        $hv = Get-BtHandle $e.X $e.Y
        if ($hv) { if ($hv.Corner -eq 'TL' -or $hv.Corner -eq 'BR') { $s.Cursor = [System.Windows.Forms.Cursors]::SizeNWSE } else { $s.Cursor = [System.Windows.Forms.Cursors]::SizeNESW } }
        else { $s.Cursor = [System.Windows.Forms.Cursors]::SizeAll }
        return
    }
    $sl = (Get-BtTarget $script:btSel).Slot
    $m = $script:btSrcMap
    if ($script:btDrag.Mode -eq 'size') {
        Set-BtResize $e.X $e.Y $script:btDrag.Anchor $sl
        $script:btDirty = $true
        $script:pnlBtSrc.Invalidate()
        return
    }
    $sl.cx = [math]::Max(0.0, [math]::Min(1.0, $script:btDrag.Cx + ($e.X - $script:btDrag.X) / ($m.Sc * $m.W)))
    $sl.cy = [math]::Max(0.0, [math]::Min(1.0, $script:btDrag.Cy + ($e.Y - $script:btDrag.Y) / ($m.Sc * $m.H)))
    $script:btDirty = $true
    $script:pnlBtSrc.Invalidate(); $script:pnlBt.Invalidate()
})
$pnlBtSrc.Add_MouseUp({ $script:btDrag = $null })
$pnlBtSrc.Add_MouseWheel({
    param($s, $e)
    $sl = (Get-BtTarget $script:btSel).Slot
    if (-not $sl -or $sl.type -eq 'none') { return }
    $z = [double]$sl.zoom; if ($z -le 0) { $z = 1.0 }
    if ($e.Delta -gt 0) { $z = $z * 1.1 } else { $z = $z / 1.1 }
    $sl.zoom = [math]::Max(0.2, [math]::Min(1.0, $z))
    $script:btDirty = $true
    $script:pnlBtSrc.Invalidate(); $script:pnlBt.Invalidate()
})
$pnlBtSrc.Add_DragEnter({ param($s, $e) if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' } })
$script:btDropPaths = $null; $script:btDropScreen = -1
$script:btDropTimer = New-Object System.Windows.Forms.Timer
$script:btDropTimer.Interval = 60
$script:btDropTimer.Add_Tick({
    $script:btDropTimer.Stop()
    $p = $script:btDropPaths; $script:btDropPaths = $null
    if ($p) { Add-BtFiles $p $script:btDropScreen }
})
function Get-BtHit([int]$x, [int]$y) {
    foreach ($h in $script:btChips) { if ($h.R.Contains([single]$x, [single]$y)) { return @{ Screen = $h.Screen; Chip = $true } } }
    foreach ($h in $script:btFrames) { if ($h.R.Contains([single]$x, [single]$y)) { return @{ Screen = $h.Screen; Chip = $false } } }
    return $null
}
$pnlBtSrc.Add_DragDrop({
    param($s, $e)
    $pt = $s.PointToClient([System.Windows.Forms.Cursor]::Position)
    $h = Get-BtHit $pt.X $pt.Y
    $script:btDropScreen = $script:btSel
    if ($h) { $script:btDropScreen = [int]$h.Screen }
    $script:btDropPaths = [string[]]$e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    $script:btDropTimer.Start()
})
$script:ctxBt = New-NeonMenu
[void]$script:ctxBt.Items.Add("Picture...", $null, { $script:btnBtPicRef.PerformClick() })
[void]$script:ctxBt.Items.Add("Video...", $null, { $script:btnBtVidRef.PerformClick() })
[void]$script:ctxBt.Items.Add("Clear", $null, { $script:btnBtClear.PerformClick() })
[void]$script:ctxBt.Items.Add("-")
[void]$script:ctxBt.Items.Add("Link all screens (one panorama)", $null, { Invoke-BtLayout "One panorama across all" })
[void]$script:ctxBt.Items.Add("Unlink all screens", $null, { Invoke-BtLayout "Every screen separate" })
[void]$script:ctxBt.Items.Add("Same picture on every screen", $null, { Invoke-BtLayout "Same picture on every screen" })
$script:btnBtPicRef = $btnBtPic; $script:btnBtVidRef = $btnBtVid
$btnBtPic.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Images|*.jpg;*.jpeg;*.png;*.bmp"
    $dlg.Multiselect = $true
    $dlg.Title = "Pick picture(s) for the selected screen"
    if ($dlg.ShowDialog() -eq 'OK') { Add-BtFiles ([string[]]$dlg.FileNames) $script:btSel }
})
$btnBtVid.Add_Click({
    if (-not $script:btnBtVidRef.Visible) { Set-Status "Videos need ffmpeg and Lively - see Settings (gear) > Add-ons."; return }
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "Videos|*.mp4;*.webm;*.gif;*.mkv;*.mov;*.avi"
    $dlg.Title = "Pick a video for the selected screen"
    if (Test-Path -LiteralPath $AnimRoot) { $dlg.InitialDirectory = $AnimRoot }
    if ($dlg.ShowDialog() -eq 'OK') { Add-BtFiles ([string[]]@($dlg.FileName)) $script:btSel }
})
$btnBtClear.Add_Click({
    $t = Get-BtTarget $script:btSel
    if ($t.IsOver) { $t.Parent.over.Remove([int]$script:btSel) }
    else {
        $keep = $t.Slot.over
        $new = New-BtSlot
        $new.over = $keep
        $script:btData[$t.Group.Lead] = $new
    }
    $script:btDirty = $true
    Update-BtInfo
})
$script:chkBtUp.Add_CheckedChanged({
    if ($script:loadingBt) { return }
    $sl = (Get-BtTarget $script:btSel).Slot
    if ($sl -and $sl.type -eq 'image') { $sl.up = [bool]$script:chkBtUp.Checked; $script:btDirty = $true; $script:pnlBt.Invalidate() }
})
$script:chkBtUpAll.Add_CheckedChanged({
    foreach ($k in @($script:btData.Keys)) {
        $sl = $script:btData[$k]
        if ($sl.type -eq 'image') { $sl.up = [bool]$script:chkBtUpAll.Checked }
        foreach ($ok in @($sl.over.Keys)) { if ($sl.over[$ok].type -eq 'image') { $sl.over[$ok].up = [bool]$script:chkBtUpAll.Checked } }
    }
    $script:btDirty = $true
    Update-BtInfo
})
$btnBtSave.Add_Click({ Save-BtPack })
$btnBtLoad.Add_Click({
    $sel = [string]$script:lbPacks.SelectedItem
    if (-not $sel) { Set-Status "Pick a pack on the Packs tab first, then press Load pack."; return }
    Load-BtFromPack $sel
})
$btnBtNew.Add_Click({ Reset-Bt; Update-BtInfo })

$btnIdentify.Add_Click({ Show-Identify })
$btnRefit.Add_Click({ [void](Convert-PanoramaPacks); Update-PackList ([string]$script:lbPacks.SelectedItem) })
$cmbPhysScreen.Add_SelectedIndexChanged({ if (-not $script:loadingPhys) { Update-PhysFields }; $script:pnlMap.Invalidate() })
$numDiag.Add_ValueChanged({ Save-PhysFields })
$numBezel.Add_ValueChanged({ Save-PhysFields })
$cmbAlign.Add_SelectedIndexChanged({
    if ($script:cmbAlign.SelectedItem) {
        Save-Setting "DispAlignMode" ([string]$script:cmbAlign.SelectedItem)
        # choosing an alignment re-lines everything up, so clear any hand-dragged heights
        Clear-LayoutPositions
        Set-LayoutDirty $false
        $dsA = @(Get-DisplayList)
        $detA = Get-DetectedDiagonals $dsA
        foreach ($dA in $dsA) {
            $pA = Get-DisplayPhysical $dA $detA
            Save-DisplayPhysical $dA $pA.Diag $pA.Bezel 0
        }
        Reset-PhysLayout
        Update-PhysFields
        $script:pnlMap.Invalidate()
    }
})
$chkPhys.Add_CheckedChanged({ Set-PhysMatch $script:chkPhys.Checked; $script:pnlMap.Invalidate() })
$btnRefreshDisp.Add_Click({ if (Confirm-LayoutPending) { Update-Displays $true } })
$btnWinDisp.Add_Click({ Start-Process "ms-settings:display" })

function Get-PickedDisplay {
    $i = $script:cmbPhysScreen.SelectedIndex
    $list = @(Get-DisplayList)
    if ($i -lt 0 -or $i -ge $list.Count) { return $null }
    return $list[$i]
}
function Sync-OrientCombo {
    $d = Get-PickedDisplay
    if ($d) { $script:cmbOrient.SelectedIndex = [int]$d.Turn }
}
$cmbPhysScreen.Add_SelectedIndexChanged({ try { Sync-OrientCombo } catch { } })
$btnTurn.Add_Click({
    $d = Get-PickedDisplay
    if (-not $d) { return }
    if (-not (Confirm-LayoutPending)) { return }
    Set-ScreenTurn $d.Device $script:cmbOrient.SelectedIndex
    Clear-LayoutPositions
    Update-Displays $true
    Sync-OrientCombo
    Set-Status ("Screen {0} set to: {1}. Use Refit packs for panoramas you already made." -f $d.Index, $script:cmbOrient.SelectedItem)
})


# ================================================================ SCHEDULE TAB
$pnlSched = New-Object System.Windows.Forms.Panel
$script:pnlSched = $pnlSched
$pnlSched.Location = New-Object System.Drawing.Point(0, 108)
$pnlSched.Size = New-Object System.Drawing.Size(940, 492)
$pnlSched.BackColor = $script:cBg
$pnlSched.Visible = $false
$form.Controls.Add($pnlSched)

$pnlSched.AutoScroll = $true
$pnlSched.Controls.Add((New-Heading "Pack schedule" 490 0 300))
$pnlSched.Controls.Add((New-HelpButton 892 -2 "Schedule" ("Play different packs at different times of day.`n`nEach block runs from its start hour until the next block starts (hours are 0-23 on your clock, so 22 is 10 pm). The pack is applied when a block begins, and once when the app starts. Choose (keep current) for a block that should change nothing.`n`nThe app has to be running, so close it to the tray instead of exiting. Auto-shuffle on the Packs tab still works too, and simply changes the pack until the next block starts.")))
$script:chkSchedOn = New-NeonCheck "Use The Schedule" 490 22 190 28
$pnlSched.Controls.Add($script:chkSchedOn)
$pnlSched.Controls.Add((New-Label "Each block runs until the next one starts." 690 27 226 22 $true 8))

$script:numSchedH = @(); $script:cmbSchedP = @()
$defH = @(6, 10, 17, 22)
$ss = Get-Settings
for ($i = 0; $i -lt 4; $i++) {
    $y = 52 + $i * 27
    $lb = New-Label $script:schedNames[$i] 490 ($y + 3) 74 24 $false 10
    $lb.Font = Get-RetroFont 10
    $pnlSched.Controls.Add($lb)
    $sp = New-NeonSpin 568 $y 64 0 23 0 1
    $hv = 0
    if (-not [int]::TryParse([string]$ss["SchedH$($i + 1)"], [ref]$hv)) { $hv = $defH[$i] }
    $sp.Value = [decimal]$hv
    $pnlSched.Controls.Add($sp)
    $pnlSched.Controls.Add((New-Label "o'clock" 638 ($y + 5) 50 22 $true 9))
    $cb = New-StyledCombo 690 $y 226
    $pnlSched.Controls.Add($cb)
    $script:numSchedH += $sp; $script:cmbSchedP += $cb
}
$script:lblSchedNow = New-Label "" 490 162 426 22 $false 9
$script:lblSchedNow.ForeColor = $script:cAccentHover
$pnlSched.Controls.Add($script:lblSchedNow)
$btnSchedNow = New-Btn "Apply now" 490 186 130 'primary' 30
$pnlSched.Controls.Add($btnSchedNow)

$pnlSched.Controls.Add((New-Heading "Startup" 490 222 300))
$script:chkHot = New-NeonCheck "Global Hotkeys (Work From The Tray)" 490 244 420 28
$script:chkHot.Checked = ([string](Get-Settings).Hotkeys -eq '1')
$pnlSched.Controls.Add($script:chkHot)
$pnlSched.Controls.Add((New-Label "Ctrl+Alt+Right/Left = next/previous pack, P = pause, R = random" 490 270 426 20 $true 8))
$script:chkStartWin = New-NeonCheck "Start With Windows (Hidden In The Tray)" 490 290 420 28
$script:chkStartWin.Checked = (Test-StartWithWindows)
$pnlSched.Controls.Add($script:chkStartWin)
$script:chkLoadScr = New-NeonCheck "Show The Loading Screen" 490 316 420 28
$script:chkLoadScr.Checked = ([string](Get-Settings).NoSplash -ne '1')
$pnlSched.Controls.Add($script:chkLoadScr)
$script:chkLoadScr.Add_CheckedChanged({
    Save-Setting 'NoSplash' $(if ($script:chkLoadScr.Checked) { '' } else { '1' })
    Write-SplashTheme
    Set-Status $(if ($script:chkLoadScr.Checked) { "The loading screen will show at startup." } else { "The loading screen is off. The window appears when the app is ready." })
})

$script:chkPauseHdr = New-NeonCheck "Pause Header Animation" 490 344 215 28
$script:chkPauseFtr = New-NeonCheck "Pause Footer Animation" 708 344 215 28
$script:chkPauseHdr.Checked = ([string](Get-Settings).PauseHdr -eq '1')
$script:chkPauseFtr.Checked = ([string](Get-Settings).PauseFtr -eq '1')
$pnlSched.Controls.Add($script:chkPauseHdr); $pnlSched.Controls.Add($script:chkPauseFtr)
Set-AnimPause $script:chkPauseHdr.Checked $script:chkPauseFtr.Checked
foreach ($pc in @($script:chkPauseHdr, $script:chkPauseFtr)) {
    $pc.Add_CheckedChanged({
        Save-Setting 'PauseHdr' $(if ($script:chkPauseHdr.Checked) { '1' } else { '' })
        Save-Setting 'PauseFtr' $(if ($script:chkPauseFtr.Checked) { '1' } else { '' })
        Set-AnimPause $script:chkPauseHdr.Checked $script:chkPauseFtr.Checked
        Set-Status $(if ($script:chkPauseHdr.Checked -or $script:chkPauseFtr.Checked) { "Animation paused. The picture holds still until you turn it back on." } else { "Animations are running." })
    })
}

$pnlSched.Controls.Add((New-Heading "Add-ons" 490 376 300))
$pnlSched.Controls.Add((New-HelpButton 892 374 "Add-ons" "Extra programs some features need. A feature stays hidden until its program is found and switched on here.`nGet downloads and sets it up for you (ffmpeg and the upscaler go in this app's Tools folder). If you already have one, use Locate to point at it. A green tick means it was found and checked.`n`nffmpeg: cutting videos for your screens. AI upscaler: sharper pictures in the Builder. Lively: animated wallpapers (it's installed separately)."))
Add-AddonRows $pnlSched 490 402

$script:loadingSched = $true
$script:chkSchedOn.Checked = ($ss.SchedOn -eq '1')
$script:loadingSched = $false

function Update-SchedPacks {
    $script:loadingSched = $true
    try {
        $s = Get-Settings
        for ($i = 0; $i -lt 4; $i++) {
            $cb = $script:cmbSchedP[$i]
            $want = [string]$s["SchedP$($i + 1)"]
            if (-not $want) { $want = '(Keep Current)' }
            $cb.Items.Clear()
            [void]$cb.Items.Add('(Keep Current)')
            foreach ($pk in $script:lbPacks.Items) { [void]$cb.Items.Add([string]$pk) }
            if ($cb.Items.Contains($want)) { $cb.SelectedItem = $want } else { $cb.SelectedIndex = 0 }
        }
    } finally { $script:loadingSched = $false }
}
$script:chkSchedOn.Add_CheckedChanged({
    if ($script:loadingSched) { return }
    Save-Setting 'SchedOn' $(if ($script:chkSchedOn.Checked) { '1' } else { '0' })
    $script:schedLast = -1
    if ($script:chkSchedOn.Checked) { Invoke-Schedule $true }
    Update-SchedStatus
})
for ($i = 0; $i -lt 4; $i++) {
    $script:numSchedH[$i].Tag = $i + 1
    $script:cmbSchedP[$i].Tag = $i + 1
    $script:numSchedH[$i].Add_ValueChanged({ param($s, $e); if ($script:loadingSched) { return }; Save-Setting ("SchedH" + $s.Tag) ([string][int]$s.Value); Update-SchedStatus })
    $script:cmbSchedP[$i].Add_SelectedIndexChanged({ param($s, $e) if ($script:loadingSched) { return }; if ($s.SelectedItem) { Save-Setting ("SchedP" + $s.Tag) ([string]$s.SelectedItem); Update-SchedStatus } })
}
$btnSchedNow.Add_Click({ Invoke-Schedule $true; Update-SchedStatus })
$script:chkHot.Add_CheckedChanged({
    try {
        Save-Setting 'Hotkeys' $(if ($script:chkHot.Checked) { '1' } else { '0' })
        if ($script:chkHot.Checked) {
            $msg = Enable-Hotkeys
            if ($msg) { Set-Status $msg } else { Set-Status "Hotkeys on: Ctrl+Alt+Right / Left / P / R." }
        } else { Disable-Hotkeys; Set-Status "Hotkeys off." }
    } catch { Set-Status "Couldn't change hotkeys: $($_.Exception.Message)" }
})
$tt.SetToolTip($script:chkHot, "Ctrl+Alt+Right / Left: next / previous pack. Ctrl+Alt+P: pause or resume live wallpapers. Ctrl+Alt+R: random pack.")
$script:chkStartWin.Add_CheckedChanged({
    try { Set-StartWithWindows ([bool]$script:chkStartWin.Checked); Set-Status $(if ($script:chkStartWin.Checked) { "Will start with Windows, hidden in the tray." } else { "Won't start with Windows." }) }
    catch { Set-Status "Couldn't change startup: $($_.Exception.Message)" }
})
$tt.SetToolTip($btnSchedNow, "Apply the pack for the current time block right now")
$script:schedTimer = New-Object System.Windows.Forms.Timer
$script:schedTimer.Interval = 60000
$script:schedTimer.Add_Tick({ try { Invoke-Schedule $false; Update-SchedStatus } catch { } })
$script:schedTimer.Start()

# ---------------------------------------------------------------- GPU saver wiring
function Sync-AutoPause {
    $mode = @('Off', 'Fullscreen', 'Maximized')[[math]::Max(0, $script:cmbPause.SelectedIndex)]
    Save-Setting 'AutoPause' $mode
    Save-Setting 'PauseBattery' $(if ($script:chkPauseBat.Checked) { '1' } else { '0' })
    Set-AutoPauseMode $mode ([bool]$script:chkPauseBat.Checked)
}
$script:cmbPause.Add_SelectedIndexChanged({ Sync-AutoPause })
$script:chkPauseBat.Add_CheckedChanged({ Sync-AutoPause })
$script:pauseTimer = New-Object System.Windows.Forms.Timer
$script:pauseTimer.Interval = 2000
$script:pauseTimer.Add_Tick({ try { Update-AutoPause } catch { } })
$script:pauseTimer.Start()

function Test-KeepRunning {
    if ($script:chkShuffle.Checked) { return $true }
    if ($script:pauseMode -ne 'Off' -or $script:pauseBattery) { return $true }
    if ((Get-Settings).SchedOn -eq '1') { return $true }
    if ($script:hotWin) { return $true }
    if (Test-CycleLockActive) { return $true }
    return $false
}

$script:lockPoll = New-Object System.Windows.Forms.Timer
$script:lockPoll.Interval = 1500
$script:lockPoll.Add_Tick({ try { Update-CycleLock } catch { } })
$script:lockPoll.Start()

$form.Add_Activated({ Update-Displays $false })
$form.Add_FormClosing({
    param($s, $e)
    if ($script:layoutDirty -and -not (Confirm-LayoutPending)) { $e.Cancel = $true; return }
    if (-not $script:exiting -and (Test-KeepRunning) -and $e.CloseReason -eq 'UserClosing') {
        $ans = [System.Windows.Forms.MessageBox]::Show("Auto-shuffle, schedule or another background feature is on.`n`nYES = quit the app completely`nNO = keep it running in the tray`nCANCEL = stay open", "Close Ekk0h", 'YesNoCancel', 'Question')
        if ($ans -eq 'Yes') { $script:exiting = $true; return }
        $e.Cancel = $true
        if ($ans -eq 'Cancel') { return }
        $script:form.Hide()
        $script:notify.ShowBalloonTip(2500, "Ekk0h", "Still running in the tray (shuffle, schedule or GPU saver). Right-click the icon to exit.", 'Info')
    }
})

$form.KeyPreview = $true
$form.Add_KeyDown({ param($s, $e) if ($e.Control -and $e.KeyCode -eq 'Q') { $script:exiting = $true; $script:form.Close() } })
$form.Add_KeyDown({
    param($s, $e)
    if ($script:themeHdr -eq 'matrix' -and $script:pillState -eq 0 -and -not $e.Control) {
        $script:neoSeq = ([string]$script:neoSeq + [string]$e.KeyCode)
        if ($script:neoSeq.Length -gt 3) { $script:neoSeq = $script:neoSeq.Substring($script:neoSeq.Length - 3) }
        if ($script:neoSeq -eq 'NEO') { $script:neoSeq = ''; Start-Pills }
    }
})
$form.Add_HandleCreated({ Set-TitleBar $script:form.Handle })

# ---------------------------------------------------------------- go
$script:dispSig = Get-DisplaySignature
Build-PreviewBoxes
Update-MonitorLists
Update-PhysScreenList
Update-DisplayText
Update-PackList $null
try { Remove-Setting 'PackGrid' } catch { }
# start with nothing selected; a pack already in use still shows on the Displays preview
try {
    $lp = [string](Get-Settings).LastPack
    if ($lp -and (Test-Path -LiteralPath (Join-Path $Root $lp))) { $script:currentPack = $lp }
} catch { }
if ($script:currentPack -and $script:lbPacks.Items.Contains([string]$script:currentPack)) { $script:lbPacks.SelectedItem = [string]$script:currentPack } else { $script:lbPacks.SelectedIndex = -1 }
Update-Preview
# ---- "Shuffle from" picker (favorites and tags, any combination)
function Update-ShuffleButton {
    $src = @(Get-ShuffleSources)
    $parts = @()
    if ($src -contains 'fav') { $parts += 'Favorites' }
    foreach ($t in $src) { if ($t.StartsWith('tag:')) { $parts += ('#' + $t.Substring(4)) } }
    if ($parts.Count -eq 0) { $txt = "All packs" } else { $txt = ($parts -join ', ') }
    if ($txt.Length -gt 26) { $txt = ($parts.Count.ToString() + " selections") }
    $script:btnShuffleSrc.Text = "Shuffle from: $txt"
    $script:btnShuffleSrc.Invalidate()
}
function Show-ShuffleMenu {
    $src = @(Get-ShuffleSources)
    $m = New-NeonMenu
    $m.ShowCheckMargin = $true
    $items = @()
    $mkItem = {
        param($text, $tag, $on)
        $it = New-Object System.Windows.Forms.ToolStripMenuItem($text)
        $it.Tag = $tag; $it.CheckOnClick = $true; $it.Checked = $on
        $it
    }
    $items += & $mkItem "All packs" 'all' ($src.Count -eq 0)
    $items += & $mkItem "Favorites" 'fav' ($src -contains 'fav')
    $tags = @{}
    foreach ($n in $script:lbPacks.Items) { foreach ($t in @((Get-PackMetaFor ([string]$n)).tags)) { $tags[$t] = 1 } }
    foreach ($t in ($tags.Keys | Sort-Object)) { $items += & $mkItem ('#' + $t) ('tag:' + $t) ($src -contains ('tag:' + $t)) }
    foreach ($it in $items) {
        $it.Add_Click({
            param($s, $e)
            $menu = $s.Owner
            if ([string]$s.Tag -eq 'all') {
                foreach ($o in $menu.Items) { if ($o -ne $s) { $o.Checked = $false } }
                $s.Checked = $true
            } else {
                $any = $false
                foreach ($o in $menu.Items) { if ([string]$o.Tag -ne 'all' -and $o.Checked) { $any = $true } }
                foreach ($o in $menu.Items) { if ([string]$o.Tag -eq 'all') { $o.Checked = (-not $any) } }
            }
            $sel = @()
            foreach ($o in $menu.Items) { if ([string]$o.Tag -ne 'all' -and $o.Checked) { $sel += [string]$o.Tag } }
            Save-Setting 'ShuffleSrc' ($sel -join '|')
            Save-Setting 'ShuffleFav' '0'
            Update-ShuffleButton
        })
        [void]$m.Items.Add($it)
    }
    if ($tags.Count -eq 0) {
        $hint = New-Object System.Windows.Forms.ToolStripMenuItem("(no tags yet: right-click a card > Edit tags)")
        $hint.Enabled = $false
        [void]$m.Items.Add($hint)
    }
    # stay open while ticking several entries
    $m.Add_Closing({ param($s, $e) if ($e.CloseReason -eq 'ItemClicked') { $e.Cancel = $true } })
    $m.Show($script:btnShuffleSrc, (New-Object System.Drawing.Point(0, $script:btnShuffleSrc.Height)))
}
$script:btnShuffleSrc.Add_Click({ Show-ShuffleMenu })
Update-ShuffleButton
try { $script:chkPinOn.Checked = ([string](Get-Settings).PinOn -eq '1') } catch { }
$script:chkPinOn.Add_CheckedChanged({ Save-Setting 'PinOn' $(if ($script:chkPinOn.Checked) { '1' } else { '0' }); Save-PinScreens })
Update-AnimList
Update-LivelyStatus
Update-NowPlaying
$form.KeyPreview = $true
$form.Add_KeyDown({
    param($s, $e)
    try {
        $ctl = $script:form.ActiveControl
        $typing = ($ctl -is [System.Windows.Forms.TextBox] -or $ctl -is [System.Windows.Forms.NumericUpDown])
        if ($e.Control -and $script:activeTab -eq 3 -and -not $typing) {
            if ($e.KeyCode -eq 'Z') { $e.SuppressKeyPress = $true; Invoke-BtUndo }
            elseif ($e.KeyCode -eq 'Y') { $e.SuppressKeyPress = $true; Invoke-BtRedo }
        } elseif ($script:activeTab -eq 0 -and $script:gridCanvas -and -not $typing) {
            if ($e.KeyCode -eq 'Delete') { $e.SuppressKeyPress = $true; Remove-SelectedPack }
            elseif ($e.KeyCode -eq 'Return') { $e.SuppressKeyPress = $true; if ($script:lbPacks.SelectedItem) { [void](Set-Pack (Join-Path $Root $script:lbPacks.SelectedItem)) } }
            elseif ($e.KeyCode -in @('Left', 'Right', 'Up', 'Down')) {
                $e.SuppressKeyPress = $true
                $items = @($script:gridItems)
                if ($items.Count -gt 0) {
                    $ix = [array]::IndexOf($items, [string]$script:lbPacks.SelectedItem)
                    if ($ix -lt 0) { $ix = 0 }
                    else {
                        switch ([string]$e.KeyCode) { 'Left' { $ix-- } 'Right' { $ix++ } 'Up' { $ix -= $script:GC_COLS } 'Down' { $ix += $script:GC_COLS } }
                    }
                    $ix = [math]::Max(0, [math]::Min($items.Count - 1, $ix))
                    $script:lbPacks.SelectedItem = $items[$ix]
                }
            }
        }
    } catch { }
})
Switch-Tab 0
Resume-WpPlayers -All
Set-AutoPauseMode ([string]@('Off', 'Fullscreen', 'Maximized')[[math]::Max(0, $script:cmbPause.SelectedIndex)]) ([bool]$script:chkPauseBat.Checked)
try { Invoke-Schedule $true } catch { }
try { if ($script:chkHot.Checked) { $hm = Enable-Hotkeys; if ($hm) { Set-Status $hm } } } catch { }
Set-Status "Ready. Tip: drag pictures from your desktop onto this window to make a pack."

$showTimer = New-Object System.Windows.Forms.Timer
$showTimer.Interval = 500
$showTimer.Add_Tick({
    if ($script:showEvt.WaitOne(0)) {
        if (-not $script:form.Visible) { try { Switch-Tab 0 } catch { } }
        $script:form.Show()
        if ($script:form.WindowState -eq 'Minimized') { $script:form.WindowState = 'Normal' }
        $script:form.Activate()
    }
})
$showTimer.Start()

# first run: offer the setup wizard once the window is up
if (-not $script:startTray -and [string](Get-Settings).WizardDone -ne '1') {
    $script:wizTimer = New-Object System.Windows.Forms.Timer
    $script:wizTimer.Interval = 1200
    $script:wizTimer.Add_Tick({
        $script:wizTimer.Stop()
        try { if ($script:form.Visible) { Show-SetupWizard } } catch { Write-AppLog ("setup wizard: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber + " " + $_.InvocationInfo.Line.Trim()) }
    })
    $form.Add_Shown({ $script:wizTimer.Start() })
}

if ($script:startTray) {
    $form.WindowState = 'Minimized'
    $form.ShowInTaskbar = $false
    $form.Add_Shown({ $script:form.Hide(); $script:form.ShowInTaskbar = $true })
}
function Write-AppLog([string]$text) {
    try { Add-Content -LiteralPath (Join-Path $PSScriptRoot "run-log.txt") -Value ((Get-Date -Format s) + "  " + $text) } catch { }
}
$script:lastErrDlg = [DateTime]::MinValue
function Show-ErrorDialog([string]$what) {
    Write-AppLog $what
    if (([DateTime]::Now - $script:lastErrDlg).TotalSeconds -lt 30) { return }
    $script:lastErrDlg = [DateTime]::Now
    $short = $what; if ($short.Length -gt 400) { $short = $short.Substring(0, 400) + "..." }
    $r = [System.Windows.Forms.MessageBox]::Show("Something went wrong, but the app can usually keep going.`n`n$short`n`nThe details were saved to run-log.txt.`n`nYES = keep going`nNO = open the log file", "Ekk0h", 'YesNo', 'Warning')
    if ($r -eq 'No') { try { Start-Process notepad.exe -ArgumentList ('"' + (Join-Path $PSScriptRoot "run-log.txt") + '"') } catch { } }
}
try {
    [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
    [System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) try { Show-ErrorDialog ([string]$e.Exception.ToString()) } catch { } })
} catch { }
try { Update-AddonVisibility } catch { }
$form.Add_Shown({ Close-Splash })
[System.Windows.Forms.Application]::Run($form)
try { Resume-WpPlayers -All } catch { }
try { Disable-Hotkeys } catch { }

$timer.Stop()
$notify.Visible = $false
$notify.Dispose()
