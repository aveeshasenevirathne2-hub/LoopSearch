using Avalonia;
using Avalonia.Animation;
using Avalonia.Animation.Easings;
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

    public static Color WindowBg => IsDark ? Color.Parse("#090E1A") : Color.Parse("#EFF4FB");
    public static Color CardFill => IsDark ? Color.FromArgb(204, 17, 25, 43) : Color.FromArgb(228, 255, 255, 255);
    public static Color CardSubtleFill => IsDark ? Color.FromArgb(145, 23, 33, 56) : Color.FromArgb(190, 241, 246, 253);
    public static Color CardBorder => IsDark ? Color.FromArgb(46, 130, 192, 255) : Color.FromArgb(64, 30, 80, 160);
    public static Color TopSpecular => IsDark ? Color.FromArgb(52, 255, 255, 255) : Color.FromArgb(180, 255, 255, 255);

    public static Color PrimaryText => IsDark ? Color.Parse("#F1F6FF") : Color.Parse("#0D1729");
    public static Color SecondaryText => IsDark ? Color.Parse("#9DB2D4") : Color.Parse("#4C6082");
    public static Color MutedText => IsDark ? Color.Parse("#6E84A8") : Color.Parse("#7286A6");

    public static Color HorizonBlue => Color.Parse("#0A54DC");
    public static Color HorizonCyan => Color.Parse("#4CD6FF");
    public static Color SuccessGreen => Color.Parse("#2FD48B");
    public static Color WarningAmber => Color.Parse("#FFB84D");
    public static Color DangerRed => Color.Parse("#FF5C6A");

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
            new GradientStop(Color.Parse("#1976FF"), 0),
            new GradientStop(Color.Parse("#0A54DC"), 0.55),
            new GradientStop(Color.Parse("#149EFF"), 1)
        }
    };

    public static LinearGradientBrush AuraGradientBrush(GlowColorTheme glow)
    {
        if (glow == GlowColorTheme.Spectrum)
        {
            return new LinearGradientBrush
            {
                StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
                EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
                GradientStops =
                {
                    new GradientStop(Color.Parse("#4285F4"), 0.0),
                    new GradientStop(Color.Parse("#9B6BFF"), 0.28),
                    new GradientStop(Color.Parse("#EA4335"), 0.54),
                    new GradientStop(Color.Parse("#FBBC05"), 0.78),
                    new GradientStop(Color.Parse("#34A853"), 1.0)
                }
            };
        }
        return new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(1, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.Parse("#4CD6FF"), 0.0),
                new GradientStop(Color.Parse("#1E7BFF"), 0.5),
                new GradientStop(Color.Parse("#74E8FF"), 1.0)
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

/// <summary>
/// Renders the signature LoopSearch Horizon radial light well + animated ambient stars.
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
        _stars = Enumerable.Range(0, 24)
            .Select(_ => (rng.NextDouble(), rng.NextDouble(), 0.9 + rng.NextDouble() * 1.4, 0.7 + rng.NextDouble() * 1.4, rng.NextDouble() * Math.PI * 2))
            .ToArray();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(33) };
        _timer.Tick += (_, _) =>
        {
            _phase += 0.035;
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
        // Base background
        context.FillRectangle(new SolidColorBrush(ThemePalette.WindowBg), bounds);

        // Horizon radial light well at bottom center
        var center = new RelativePoint(0.5, 1.02, RelativeUnit.Relative);
        var wellBrush = new RadialGradientBrush
        {
            Center = center,
            GradientOrigin = center,
            RadiusX = new RelativeScalar(0.82, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(0.65, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(dark ? Color.FromArgb(128, 18, 128, 255) : Color.FromArgb(72, 40, 140, 255), 0.0),
                new GradientStop(dark ? Color.FromArgb(52, 10, 84, 220) : Color.FromArgb(28, 76, 214, 255), 0.45),
                new GradientStop(Colors.Transparent, 1.0)
            }
        };
        context.FillRectangle(wellBrush, bounds);

        // Top subtle cool sheen
        var topGlow = new RadialGradientBrush
        {
            Center = new RelativePoint(0.2, -0.1, RelativeUnit.Relative),
            GradientOrigin = new RelativePoint(0.2, -0.1, RelativeUnit.Relative),
            RadiusX = new RelativeScalar(0.65, RelativeUnit.Relative),
            RadiusY = new RelativeScalar(0.50, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(dark ? Color.FromArgb(36, 76, 214, 255) : Color.FromArgb(40, 255, 255, 255), 0.0),
                new GradientStop(Colors.Transparent, 1.0)
            }
        };
        context.FillRectangle(topGlow, bounds);

        // Subtle animated starfield in dark mode
        if (dark)
        {
            foreach (var (sx, sy, sr, spd, ph) in _stars)
            {
                double alpha = 0.14 + 0.24 * (0.5 + 0.5 * Math.Sin(_phase * spd + ph));
                var brush = new SolidColorBrush(Color.FromArgb((byte)(alpha * 255), 185, 225, 255));
                context.DrawEllipse(brush, null, new Point(sx * bounds.Width, sy * bounds.Height), sr, sr);
            }
        }
    }
}

public static class LiquidGlassUI
{
    public static Border CreateGlassCard(Control child, Thickness? padding = null, double radius = 16, bool subtle = false)
    {
        return new Border
        {
            Background = new SolidColorBrush(subtle ? ThemePalette.CardSubtleFill : ThemePalette.CardFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(radius),
            Padding = padding ?? new Thickness(16),
            Child = child
        };
    }

    public static Button CreatePrimaryButton(string text, Action onClick, double height = 36)
    {
        var btn = new Button
        {
            Content = new TextBlock
            {
                Text = text,
                FontWeight = FontWeight.SemiBold,
                FontSize = 13,
                Foreground = Brushes.White,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            },
            Background = ThemePalette.AccentButtonBrush,
            BorderThickness = new Thickness(1),
            BorderBrush = new SolidColorBrush(Color.FromArgb(100, 120, 215, 255)),
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

    public static Button CreateGlassButton(string text, Action onClick, double height = 34)
    {
        var btn = new Button
        {
            Content = new TextBlock
            {
                Text = text,
                FontWeight = FontWeight.Medium,
                FontSize = 12.5,
                Foreground = ThemePalette.PrimaryBrush,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            },
            Background = new SolidColorBrush(ThemePalette.CardSubtleFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Height = height,
            Padding = new Thickness(14, 0),
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
                    FontSize = 12,
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center
                },
                CornerRadius = new CornerRadius(8),
                BorderThickness = new Thickness(0),
                Padding = new Thickness(10, 6),
                Margin = new Thickness(2),
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
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(165, 11, 17, 30) : Color.FromArgb(170, 224, 234, 248)),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(2),
            Child = grid
        };
    }

    public static Control CreateBrandBadge(double size = 48)
    {
        var bmp = ThemePalette.LoadBrandIcon();
        var inner = bmp != null
            ? (Control)new Image { Source = bmp, Width = size, Height = size, Stretch = Stretch.UniformToFill }
            : new Border { Width = size, Height = size, Background = ThemePalette.AccentButtonBrush };

        return new Border
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size * 0.24),
            ClipToBounds = true,
            BorderBrush = new SolidColorBrush(Color.FromArgb(110, 76, 214, 255)),
            BorderThickness = new Thickness(1),
            Child = inner
        };
    }

    public static void AnimateWindowEntrance(Window window, Control rootContent)
    {
        double scaleDur = 240 * AppSettings.Shared.MotionFeel.DurationScale();
        rootContent.Opacity = 0;
        rootContent.RenderTransformOrigin = RelativePoint.Center;
        var st = new ScaleTransform(0.95, 0.95);
        rootContent.RenderTransform = st;

        var start = DateTime.UtcNow;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
        timer.Tick += (_, _) =>
        {
            double t = Math.Clamp((DateTime.UtcNow - start).TotalMilliseconds / scaleDur, 0, 1);
            // Cubic ease out
            double ease = 1 - Math.Pow(1 - t, 3);
            rootContent.Opacity = ease;
            double s = 0.95 + 0.05 * ease;
            st.ScaleX = s;
            st.ScaleY = s;
            if (t >= 1) timer.Stop();
        };
        timer.Start();
    }

    public static void ConfigureWindowChrome(Window window, double width, double height, string title, bool resizable = false)
    {
        window.Title = title;
        window.Width = width;
        window.Height = height;
        window.CanResize = resizable;
        window.WindowStartupLocation = WindowStartupLocation.CenterScreen;
        window.Background = new SolidColorBrush(ThemePalette.WindowBg);
        window.ExtendClientAreaToDecorationsHint = false;

        window.Opened += (_, _) =>
        {
            var handle = window.TryGetPlatformHandle()?.Handle ?? IntPtr.Zero;
            NativeWin32.ApplyGlassWindowAttributes(handle, ThemePalette.IsDark, useBackdrop: true);
        };
    }
}
