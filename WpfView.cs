// WpfView.cs - draws saver pictures with WPF so the slow pan/zoom runs on the graphics card.
// Part of the screen saver (built together with ScreenSaver.cs). Plain C# 5.
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms.Integration;
using Wpf = System.Windows;
using WpfC = System.Windows.Controls;
using WpfM = System.Windows.Media;
using WpfA = System.Windows.Media.Animation;
using WpfI = System.Windows.Media.Imaging;

class WpfView : ElementHost
{
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr h);

    WpfC.Canvas root = new WpfC.Canvas();
    Random rnd = new Random();

    public WpfView()
    {
        root.Background = WpfM.Brushes.Black;
        root.ClipToBounds = true;
        Child = root;
        BackColor = Color.Black;
    }

    // fades the picture in over the old one; when 'moving', the picture is oversized and slowly zooms and drifts for 'secs'
    public void ShowImage(Bitmap bmp, bool moving, int secs, int w, int h)
    {
        IntPtr hb = bmp.GetHbitmap();
        WpfI.BitmapSource bs;
        try
        {
            bs = System.Windows.Interop.Imaging.CreateBitmapSourceFromHBitmap(hb, IntPtr.Zero, Wpf.Int32Rect.Empty, WpfI.BitmapSizeOptions.FromEmptyOptions());
            bs.Freeze();
        }
        finally { DeleteObject(hb); }

        double dpi = 96;
        using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) dpi = g.DpiX;
        double k = 96.0 / dpi;

        WpfC.Image img = new WpfC.Image();
        img.Source = bs;
        img.Stretch = WpfM.Stretch.Fill;
        img.Width = bmp.Width * k;
        img.Height = bmp.Height * k;
        WpfM.RenderOptions.SetBitmapScalingMode(img, WpfM.BitmapScalingMode.Linear);
        WpfC.Canvas.SetLeft(img, -(img.Width - w * k) / 2);
        WpfC.Canvas.SetTop(img, -(img.Height - h * k) / 2);
        img.RenderTransformOrigin = new Wpf.Point(0.5, 0.5);
        WpfM.ScaleTransform sc = new WpfM.ScaleTransform(1, 1);
        WpfM.TranslateTransform tr = new WpfM.TranslateTransform(0, 0);
        WpfM.TransformGroup tg = new WpfM.TransformGroup();
        tg.Children.Add(sc);
        tg.Children.Add(tr);
        img.RenderTransform = tg;
        img.Opacity = 0;
        root.Children.Add(img);

        WpfA.DoubleAnimation fade = new WpfA.DoubleAnimation(0, 1, new Wpf.Duration(TimeSpan.FromSeconds(1.0)));
        WpfC.Image keep = img;
        fade.Completed += delegate
        {
            List<Wpf.UIElement> old = new List<Wpf.UIElement>();
            foreach (Wpf.UIElement u in root.Children) if (u != keep) old.Add(u);
            foreach (Wpf.UIElement u in old) root.Children.Remove(u);
        };
        img.BeginAnimation(Wpf.UIElement.OpacityProperty, fade);

        if (moving)
        {
            Wpf.Duration d = new Wpf.Duration(TimeSpan.FromSeconds(Math.Max(5, secs)));
            double dx = (rnd.Next(2) == 0 ? -1 : 1) * w * k * 0.04;
            double dy = (rnd.Next(2) == 0 ? -1 : 1) * h * k * 0.015;
            sc.BeginAnimation(WpfM.ScaleTransform.ScaleXProperty, new WpfA.DoubleAnimation(1.0, 1.08, d));
            sc.BeginAnimation(WpfM.ScaleTransform.ScaleYProperty, new WpfA.DoubleAnimation(1.0, 1.08, d));
            tr.BeginAnimation(WpfM.TranslateTransform.XProperty, new WpfA.DoubleAnimation(-dx, dx, d));
            tr.BeginAnimation(WpfM.TranslateTransform.YProperty, new WpfA.DoubleAnimation(-dy, dy, d));
        }
    }
}
