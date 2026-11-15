using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Platform;
using Avalonia.Threading;
using LoopSearch.Models;
using LoopSearch.Services;

namespace LoopSearch.UI;

public static class ThemePalette
{
    public static bool IsDark => AppSettings.Shared.EffectiveIsDark(NativeWin32.IsSystemDarkMode());
    public static bool IsWebDark => AppSettings.Shared.EffectiveWebIsDark(NativeWin32.IsSystemDarkMode());

    public static Color WindowBg => IsDark ? Color.Parse("#060912") : Color.Parse("#EFF4FB");
    public static Color CardFill => IsDark ? Color.FromArgb(196, 13, 21, 38) : Color.FromArgb(232, 255, 255, 255);
    public static Color CardSubtleFill => IsDark ? Color.FromArgb(156, 20, 30, 54) : Color.FromArgb(200, 236, 243, 253);
    public static Color CardBorder => IsDark ? Color.FromArgb(56, 128, 198, 255) : Color.FromArgb(68, 30, 80, 160);
    public static Color TopSpecular => IsDark ? Color.FromArgb(72, 255, 255, 255) : Color.FromArgb(200, 255, 255, 255);

    public static Color PrimaryText => IsDark ? Color.Parse("#F3F8FF") : Color.Parse("#0D1729");
    public static Color SecondaryText => IsDark ? Color.Parse("#A2B7D9") : Color.Parse("#4C6082");
    public static Color MutedText => IsDark ? Color.Parse("#7088AE") : Color.Parse("#6F83A4");

    public static Color HorizonBlue => Color.Parse("#0A54DC");
    public static Color HorizonCyan => Color.Parse("#4CD6FF");
    public static Color SuccessGreen => Color.Parse("#30D158");
    public static Color WarningAmber => Color.Parse("#FF9F0A");
    public static Color DangerRed => Color.Parse("#FF453A");

    public static IBrush PrimaryBrush => new SolidColorBrush(PrimaryText);
    public static IBrush SecondaryBrush => new SolidColorBrush(SecondaryText);
    public static IBrush MutedBrush => new SolidColorBrush(MutedText);
    public static IBrush AccentCyanBrush => new SolidColorBrush(HorizonCyan);

    public static LinearGradientBrush AccentButtonBrush => new()
    {
        StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
        EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
        GradientStops =
        {
            new GradientStop(Color.Parse("#1F85FF"), 0),
            new GradientStop(Color.Parse("#0C5BE6"), 0.55),
            new GradientStop(Color.Parse("#1BA8FF"), 1)
        }
    };

    public static LinearGradientBrush AuraGradientBrush(GlowColorTheme glow, double phase = 0)
    {
        double shift = 0.5 + 0.5 * Math.Sin(phase);
        if (glow == GlowColorTheme.Spectrum)
        {
            return new LinearGradientBrush
            {
                StartPoint = new RelativePoint(shift * 0.4, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1 - shift * 0.4, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#4285F4"), 0.0),
                    new GradientStop(Color.Parse("#A855F7"), 0.28),
                    new GradientStop(Color.Parse("#EA4335"), 0.54),
                    new GradientStop(Color.Parse("#FBBC05"), 0.78),
                    new GradientStop(Color.Parse("#34A853"), 1.0)
                }
            };
        }
        return new LinearGradientBrush
        {
            StartPoint = new RelativePoint(shift * 0.35, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(1 - shift * 0.35, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.Parse("#5CE1FF"), 0.0),
                new GradientStop(Color.Parse("#237BFF"), 0.5),
                new GradientStop(Color.Parse("#A2F2FF"), 1.0)
            }
        };
    }

    public static Bitmap? LoadBrandIcon()
    {
        try
        {
            using var stream = AssetLoader.Open(new Uri("avares://LoopSearch/Resources/AppIcon.png"));
            return new Bitmap(stream);
        }
        catch
        {
            return null;
        }
    }
}

public static class AppleMotion
{
    public static double EaseOutCubic(double t) => 1.0 - Math.Pow(1.0 - Math.Clamp(t, 0, 1), 3);

    /// <summary>
    /// Underdamped physics spring curve closely matching macOS CASpringAnimation(dampingRatio: ~0.82).
    /// </summary>
    public static double SpringCurve(double t, double damping = 0.82)
    {
        t = Math.Clamp(t, 0, 1);
        if (t >= 1) return 1.0;
        double omega = 10.5;
        double decay = Math.Exp(-damping * omega * t);
        double wd = omega * Math.Sqrt(Math.Max(0.01, 1.0 - damping * damping));
        return 1.0 - decay * (Math.Cos(wd * t) + (damping / Math.Sqrt(Math.Max(0.01, 1.0 - damping * damping))) * Math.Sin(wd * t));
    }

    public static void AnimateWindowEntrance(Window window, Control rootContent)
    {
        double scaleDur = 280 * AppSettings.Shared.MotionFeel.DurationScale();
        rootContent.Opacity = 0;
        rootContent.RenderTransformOrigin = RelativePoint.Center;
        var scale = new ScaleTransform(0.94, 0.94);
        var trans = new TranslateTransform(0, 12);
        var group = new TransformGroup();
        group.Children.Add(scale);
        group.Children.Add(trans);
        rootContent.RenderTransform = group;

        var start = DateTime.UtcNow;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        timer.Tick += (_, _) =>
        {
            double t = Math.Clamp((DateTime.UtcNow - start).TotalMilliseconds / scaleDur, 0, 1);
            double s = SpringCurve(t, 0.84);
            double e = EaseOutCubic(t);
            rootContent.Opacity = e;
            double sc = 0.94 + 0.06 * s;
            scale.ScaleX = sc;
            scale.ScaleY = sc;
            trans.Y = 12 * (1.0 - s);
            if (t >= 1) timer.Stop();
        };
        timer.Start();
    }

    public static void KineticHorizonSpring(
        Control view,
        double delaySeconds = 0,
        double fromY = 16,
        double fromScale = 0.95,
        double fromTiltDeg = 0,
        double baseDurationMs = 420)
    {
        double dur = Math.Max(140, baseDurationMs * AppSettings.Shared.MotionFeel.DurationScale());
        view.Opacity = 0;
        view.RenderTransformOrigin = RelativePoint.Center;
        var st = new ScaleTransform(fromScale, fromScale);
        var tt = new TranslateTransform(0, fromY);
        var rt = new RotateTransform(fromTiltDeg);
        var grp = new TransformGroup();
        grp.Children.Add(st);
        grp.Children.Add(rt);
        grp.Children.Add(tt);
        view.RenderTransform = grp;

        var birth = DateTime.UtcNow.AddSeconds(delaySeconds);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        timer.Tick += (_, _) =>
        {
            var elapsed = (DateTime.UtcNow - birth).TotalMilliseconds;
            if (elapsed < 0) return;
            double t = Math.Clamp(elapsed / dur, 0, 1);
            double spring = SpringCurve(t, 0.80);
            double alpha = EaseOutCubic(Math.Min(1, t * 1.4));
            view.Opacity = alpha;
            double s = fromScale + (1.0 - fromScale) * spring;
            st.ScaleX = s;
            st.ScaleY = s;
            tt.Y = fromY * (1.0 - spring);
            rt.Angle = fromTiltDeg * (1.0 - spring);
            if (t >= 1)
            {
                view.Opacity = 1;
                st.ScaleX = 1;
                st.ScaleY = 1;
                tt.Y = 0;
                rt.Angle = 0;
                timer.Stop();
            }
        };
        timer.Start();
    }

    public static void StaggeredCardsReveal(IReadOnlyList<Control> cards, double baseDelay = 0.03, double stepDelay = 0.048)
    {
        for (int i = 0; i < cards.Count; i++)
        {
            double tilt = (i % 2 == 0) ? -0.8 : 0.7;
            KineticHorizonSpring(cards[i], baseDelay + i * stepDelay, fromY: 16, fromScale: 0.965, fromTiltDeg: tilt, baseDurationMs: 420);
        }
    }
}

/// <summary>
/// Full macOS HorizonLightWellView port: drifting cyan-blue Horizon light well, counter-wave, glowing bottom rim, and ambient twinkling stars.
/// </summary>
public sealed class HorizonBackgroundView : Control
{
    private readonly DispatcherTimer _timer;
    private double _phase;
    private readonly (double X, double Y, double R, double Speed, double Phase)[] _stars;

    public HorizonBackgroundView()
    {
        IsHitTestVisible = false;
        var rng = new Random(42);
        _stars = Enumerable.Range(0, 28)
            .Select(_ => (rng.NextDouble(), rng.NextDouble(), 0.9 + rng.NextDouble() * 1.4, 0.7 + rng.NextDouble() * 1.5, rng.NextDouble() * Math.PI * 2))
            .ToArray();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(28) };
        _timer.Tick += (_, _) =>
        {
            _phase += 0.032;
            InvalidateVisual();
        };
    }

    protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        _timer.Start();
    }

    protected override void OnDetachedFromVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnDetachedFromVisualTree(e);
        _timer.Stop();
    }

    public override void Render(DrawingContext context)
    {
        var bounds = Bounds;
        if (bounds.Width <= 0 || bounds.Height <= 0) return;

        bool dark = ThemePalette.IsDark;
        context.FillRectangle(new SolidColorBrush(ThemePalette.WindowBg), bounds);

        // Drifting radial Horizon light well (matching macOS gpuHorizonDrift + gpuHorizonTide)
        double driftX = 0.5 + 0.08 * Math.Sin(_phase * 0.75);
        double tideY = 0.62 + 0.06 * Math.Sin(_phase * 0.92);
        var center1 = new RelativePoint(driftX, 1.03, RelativeUnit.Relative);
        var primaryWell = new RadialGradientBrush
        {
            Center = center1,
            GradientOrigin = center1,
            RadiusX = new RelativeScalar(0.84, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(tideY, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(dark ? Color.FromArgb(148, 28, 178, 255) : Color.FromArgb(88, 35, 145, 255), 0.0),
                new GradientStop(dark ? Color.FromArgb(95, 10, 86, 225) : Color.FromArgb(42, 76, 214, 255), 0.38),
                new GradientStop(dark ? Color.FromArgb(32, 8, 36, 110) : Color.FromArgb(12, 76, 214, 255), 0.72),
                new GradientStop(Colors.Transparent, 1.0)
            }
        };
        context.FillRectangle(primaryWell, bounds);

        // Secondary counter-drifting luminous pool
        double driftX2 = 0.5 - 0.11 * Math.Sin(_phase * 0.58 + 1.2);
        var center2 = new RelativePoint(driftX2, 1.06, RelativeUnit.Relative);
        var secondaryWell = new RadialGradientBrush
        {
            Center = center2,
            GradientOrigin = center2,
            RadiusX = new RelativeScalar(0.55, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(0.42, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(dark ? Color.FromArgb(92, 165, 244, 255) : Color.FromArgb(62, 135, 225, 255), 0.0),
                new GradientStop(Colors.Transparent, 1.0)
            }
        };
        context.FillRectangle(secondaryWell, bounds);

        // Soft top-left specular sheen
        var topSheen = new RadialGradientBrush
        {
            Center = new RelativePoint(0.18, -0.05, RelativeUnit.Relative),
            GradientOrigin = new RelativePoint(0.18, -0.05, RelativeUnit.Relative),
            RadiusX = new RelativeScalar(0.68, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(0.45, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(dark ? Color.FromArgb(44, 120, 215, 255) : Color.FromArgb(60, 255, 255, 255), 0.0),
                new GradientStop(Colors.Transparent, 1.0)
            }
        };
        context.FillRectangle(topSheen, bounds);

        // Ambient twinkling star sparkles
        if (dark)
        {
            foreach (var (sx, sy, sr, spd, ph) in _stars)
            {
                double tw = 0.5 + 0.5 * Math.Sin(_phase * spd + ph);
                double alpha = 0.10 + 0.36 * Math.Pow(tw, 2);
                double cx = sx * bounds.Width;
                double cy = sy * bounds.Height * 0.88;
                var b = new SolidColorBrush(Color.FromArgb((byte)(alpha * 255), 205, 238, 255));
                context.DrawEllipse(b, null, new Point(cx, cy), sr, sr);
                if (tw > 0.72)
                {
                    var arm = sr * (1.8 + tw * 1.4);
                    var pen = new Pen(new SolidColorBrush(Color.FromArgb((byte)(alpha * 180), 215, 245, 255)), 0.75);
                    context.DrawLine(pen, new Point(cx - arm, cy), new Point(cx + arm, cy));
                    context.DrawLine(pen, new Point(cx, cy - arm), new Point(cx, cy + arm));
                }
            }
        }
    }
}

/// <summary>
/// Full macOS HorizonOrb port: breathing radial aura, staggered expanding sonar ripples, rotating comet ring, counter shimmer, and crisp white lens core.
/// </summary>
public sealed class HorizonOrbControl : Control
{
    private readonly DispatcherTimer _timer;
    private double _t;
    private readonly Geometry _lensGeo = Geometry.Parse(LiquidGlassIcons.SearchGlass);

    public HorizonOrbControl()
    {
        Width = 96;
        Height = 96;
        IsHitTestVisible = false;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        _timer.Tick += (_, _) =>
        {
            _t += 0.016;
            InvalidateVisual();
        };
    }

    protected override void OnAttachedToVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnAttachedToVisualTree(e);
        _timer.Start();
    }

    protected override void OnDetachedFromVisualTree(VisualTreeAttachmentEventArgs e)
    {
        base.OnDetachedFromVisualTree(e);
        _timer.Stop();
    }

    public override void Render(DrawingContext ctx)
    {
        double cx = Bounds.Width / 2;
        double cy = Bounds.Height / 2;
        var center = new Point(cx, cy);

        // 1. Breathing radial blue aura
        double auraScale = 1.0 + 0.09 * Math.Sin(_t * 2.8);
        double auraAlpha = 0.72 + 0.28 * Math.Sin(_t * 2.8);
        var auraBrush = new RadialGradientBrush
        {
            Center = RelativePoint.Center,
            GradientOrigin = RelativePoint.Center,
            GradientStops =
            {
                new GradientStop(Color.FromArgb((byte)(145 * auraAlpha), 28, 175, 255), 0.0),
                new GradientStop(Color.FromArgb((byte)(62 * auraAlpha), 10, 92, 240), 0.52),
                new GradientStop(Colors.Transparent, 1.0)
            }
        };
        ctx.DrawEllipse(auraBrush, null, center, 44 * auraScale, 44 * auraScale);

        // 2. Three staggered sonar ripple rings
        for (int i = 0; i < 3; i++)
        {
            double prog = ((_t / 2.4) + i / 3.0) % 1.0;
            double r = 24 + prog * 21;
            byte a = (byte)(Math.Sin(prog * Math.PI) * 90);
            ctx.DrawEllipse(null, new Pen(new SolidColorBrush(Color.FromArgb(a, 110, 224, 255)), 1.2), center, r, r);
        }

        // 3. Rotating comet arc (outer 31pt radius)
        double cometAngle = _t * 3.4;
        DrawArc(ctx, center, 29, cometAngle, cometAngle + 2.2, Color.FromArgb(245, 225, 250, 255), 2.4);
        DrawArc(ctx, center, 29, cometAngle - 1.5, cometAngle + 0.1, Color.FromArgb(145, 45, 185, 255), 2.2);

        // 4. Counter-rotating inner shimmer arc
        double innerAngle = -_t * 2.0;
        DrawArc(ctx, center, 25, innerAngle, innerAngle + 1.4, Color.FromArgb(130, 145, 232, 255), 1.1);

        // 5. Deep obsidian-navy glass core
        ctx.DrawEllipse(
            new SolidColorBrush(Color.FromArgb(242, 4, 9, 24)),
            new Pen(new SolidColorBrush(Color.FromArgb(150, 68, 198, 255)), 1.25),
            center, 22, 22);

        // 6. Core radial glow
        ctx.DrawEllipse(
            new RadialGradientBrush
            {
                Center = RelativePoint.Center,
                GradientOrigin = RelativePoint.Center,
                GradientStops =
                {
                    new GradientStop(Color.FromArgb(75, 40, 165, 255), 0.0),
                    new GradientStop(Colors.Transparent, 1.0)
                }
            },
            null, center, 20, 20);

        // 7. Crisp white Magnifying Glass vector in center
        var pen = new Pen(new SolidColorBrush(Color.FromArgb(245, 242, 251, 255)), 2.1, lineCap: PenLineCap.Round);
        using (ctx.PushTransform(Matrix.CreateTranslation(cx - 12, cy - 12)))
        {
            ctx.DrawGeometry(null, pen, _lensGeo);
        }
    }

    private static void DrawArc(DrawingContext ctx, Point c, double r, double startRad, double endRad, Color color, double width)
    {
        var geo = new StreamGeometry();
        using (var g = geo.Open())
        {
            int steps = 20;
            for (int i = 0; i <= steps; i++)
            {
                double a = startRad + (endRad - startRad) * (i / (double)steps);
                var pt = new Point(c.X + Math.Cos(a) * r, c.Y + Math.Sin(a) * r);
                if (i == 0) g.BeginFigure(pt, false);
                else g.LineTo(pt);
            }
        }
        ctx.DrawGeometry(null, new Pen(new SolidColorBrush(color), width, lineCap: PenLineCap.Round), geo);
    }
}

public static class LiquidGlassUI
{
    public static Border CreateGlassCard(Control child, Thickness? padding = null, double radius = 15, bool subtle = false)
    {
        return new Border
        {
            Background = new SolidColorBrush(subtle ? ThemePalette.CardSubtleFill : ThemePalette.CardFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(radius),
            Padding = padding ?? new Thickness(15, 13),
            Child = child
        };
    }

    public static Button CreatePrimaryButton(string text, Action onClick, double height = 34, string? iconPath = null)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        if (!string.IsNullOrEmpty(iconPath))
            row.Children.Add(LiquidGlassIcons.StrokeIcon(iconPath, 13, Brushes.White, 1.9));
        row.Children.Add(new TextBlock
        {
            Text = text,
            FontWeight = FontWeight.SemiBold,
            FontSize = 12.5,
            Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center
        });

        var btn = new Button
        {
            Content = row,
            Background = ThemePalette.AccentButtonBrush,
            BorderThickness = new Thickness(1),
            BorderBrush = new SolidColorBrush(Color.FromArgb(135, 135, 224, 255)),
            CornerRadius = new CornerRadius(10),
            Height = height,
            Padding = new Thickness(16, 0),
            Cursor = new Cursor(StandardCursorType.Hand),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
        btn.Click += (_, _) => onClick();
        return btn;
    }

    public static Button CreateGlassButton(string text, Action onClick, double height = 32, string? iconPath = null)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
        if (!string.IsNullOrEmpty(iconPath))
            row.Children.Add(LiquidGlassIcons.StrokeIcon(iconPath, 12.5, ThemePalette.PrimaryBrush, 1.7));
        row.Children.Add(new TextBlock
        {
            Text = text,
            FontWeight = FontWeight.Medium,
            FontSize = 12,
            Foreground = ThemePalette.PrimaryBrush,
            VerticalAlignment = VerticalAlignment.Center
        });

        var btn = new Button
        {
            Content = row,
            Background = new SolidColorBrush(ThemePalette.CardSubtleFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(9),
            Height = height,
            Padding = new Thickness(13, 0),
            Cursor = new Cursor(StandardCursorType.Hand),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
        btn.Click += (_, _) => onClick();
        return btn;
    }

    public static Control CreateSegmentedControl(IReadOnlyList<string> labels, int selectedIndex, Action<int> onChanged)
    {
        var grid = new UniformGrid { Columns = labels.Count, Rows = 1 };
        var buttons = new List<Button>();

        void Refresh(int active)
        {
            for (int i = 0; i < buttons.Count; i++)
            {
                bool sel = i == active;
                buttons[i].Background = sel ? ThemePalette.AccentButtonBrush : Brushes.Transparent;
                buttons[i].BorderBrush = sel ? new SolidColorBrush(Color.FromArgb(115, 130, 220, 255)) : Brushes.Transparent;
                buttons[i].BorderThickness = new Thickness(1);
                if (buttons[i].Content is TextBlock tb)
                {
                    tb.Foreground = sel ? Brushes.White : ThemePalette.SecondaryBrush;
                    tb.FontWeight = sel ? FontWeight.SemiBold : FontWeight.Medium;
                }
            }
        }

        for (int i = 0; i < labels.Count; i++)
        {
            int idx = i;
            var btn = new Button
            {
                Content = new TextBlock
                {
                    Text = labels[i],
                    FontSize = 11.5,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                },
                CornerRadius = new CornerRadius(7),
                Padding = new Thickness(8, 5),
                Margin = new Thickness(1.5),
                Cursor = new Cursor(StandardCursorType.Hand),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Center
            };
            btn.Click += (_, _) =>
            {
                Refresh(idx);
                onChanged(idx);
            };
            buttons.Add(btn);
            grid.Children.Add(btn);
        }

        Refresh(Math.Clamp(selectedIndex, 0, Math.Max(0, labels.Count - 1)));

        return new Border
        {
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(180, 9, 14, 26) : Color.FromArgb(185, 224, 234, 248)),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(2),
            Child = grid
        };
    }

    public static Control CreateBrandBadge(double size = 40)
    {
        var bmp = ThemePalette.LoadBrandIcon();
        var inner = bmp != null
            ? (Control)new Image { Source = bmp, Width = size, Height = size, Stretch = Stretch.UniformToFill }
            : new Border { Width = size, Height = size, Background = ThemePalette.AccentButtonBrush };

        return new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size * 0.25),
            ClipToBounds = true,
            BorderBrush = new SolidColorBrush(Color.FromArgb(135, 92, 224, 255)),
            BorderThickness = new Thickness(1),
            Child = inner
        };
    }

    public static void AnimateWindowEntrance(Window window, Control rootContent) =>
        AppleMotion.AnimateWindowEntrance(window, rootContent);

    /// <summary>
    /// Creates a sleek borderless 22px rounded Liquid Glass window shell matching macOS windows (no standard Win32 frame).
    /// </summary>
    public static Border WrapBorderlessGlassShell(
        Window window,
        double width,
        double height,
        string windowTitle,
        Control innerBody,
        bool showTitleInBar = true,
        bool resizable = false)
    {
        window.Title = windowTitle;
        window.Width = width;
        window.Height = height;
        window.CanResize = resizable;
        window.ShowInTaskbar = AppSettings.Shared.KeepInTaskbar;
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        window.SystemDecorations = SystemDecorations.None;
        window.ExtendClientAreaToDecorationsHint = true;
        window.ExtendClientAreaChromeHints = ExtendClientAreaChromeHints.NoChrome;
        window.ExtendClientAreaTitleBarHeightHint = 0;
        window.TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        window.Background = Brushes.Transparent;

        window.Opened += (_, _) =>
        {
            var handle = window.TryGetPlatformHandle()?.Handle ?? IntPtr.Zero;
            NativeWin32.ApplyGlassWindowAttributes(handle, ThemePalette.IsDark, useBackdrop: false);
        };

        var shellGrid = new Grid();
        shellGrid.Children.Add(new HorizonBackgroundView());

        var dock = new DockPanel();

        // Subtle draggable custom top bar with close button (zero Win32 caption chrome!)
        var dragHeader = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("*,Auto"),
            Height = 32,
            Margin = new Thickness(18, 8, 12, 0),
            Background = Brushes.Transparent,
            Cursor = new Cursor(StandardCursorType.Arrow)
        };
        dragHeader.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(window).Properties.IsLeftButtonPressed)
                window.BeginMoveDrag(e);
        };

        if (showTitleInBar)
        {
            dragHeader.Children.Add(new TextBlock
            {
                Text = windowTitle,
                FontSize = 11.5,
                FontWeight = FontWeight.Medium,
                Foreground = ThemePalette.MutedBrush,
                VerticalAlignment = VerticalAlignment.Center
            });
        }

        var closeBtn = new Button
        {
            Content = LiquidGlassIcons.StrokeIcon(LiquidGlassIcons.CloseX, 11.5, ThemePalette.SecondaryBrush, 1.9),
            Width = 26,
            Height = 26,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(13),
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(45, 255, 255, 255) : Color.FromArgb(30, 0, 0, 0)),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            Cursor = new Cursor(StandardCursorType.Hand),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
        closeBtn.Click += (_, _) => window.Close();
        Grid.SetColumn(closeBtn, 1);
        dragHeader.Children.Add(closeBtn);

        DockPanel.SetDock(dragHeader, Dock.Top);
        dock.Children.Add(dragHeader);
        dock.Children.Add(innerBody);
        shellGrid.Children.Add(dock);

        // Luminous bottom-lit Horizon rim perimeter gradient border
        var rimBrush = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.FromArgb(115, 255, 255, 255), 0.0),
                new GradientStop(Color.FromArgb(45, 148, 163, 184), 0.25),
                new GradientStop(Color.FromArgb(85, 56, 130, 246), 0.72),
                new GradientStop(Color.FromArgb(195, 92, 224, 255), 1.0)
            }
        };

        var outerFrame = new Border
        {
            CornerRadius = new CornerRadius(22),
            ClipToBounds = true,
            BorderBrush = rimBrush,
            BorderThickness = new Thickness(1.25),
            Child = shellGrid
        };

        window.Content = outerFrame;
        return outerFrame;
    }
}
