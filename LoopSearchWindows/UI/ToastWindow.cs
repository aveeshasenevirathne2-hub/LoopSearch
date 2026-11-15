using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;

namespace LoopSearch.UI;

public sealed class ToastWindow : Window
{
    public ToastWindow(string message, string subtitle = "")
    {
        Topmost = true;
        ShowInTaskbar = false;
        SystemDecorations = SystemDecorations.None;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        CanResize = false;
        SizeToContent = SizeToContent.WidthAndHeight;

        var stack = new StackPanel { Spacing = 2 };
        stack.Children.Add(new TextBlock
        {
            Text = message,
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.PrimaryBrush
        });
        if (!string.IsNullOrWhiteSpace(subtitle))
        {
            stack.Children.Add(new TextBlock
            {
                Text = subtitle,
                FontSize = 11.5,
                Foreground = ThemePalette.SecondaryBrush
            });
        }

        var card = new Border
        {
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(238, 15, 23, 42) : Color.FromArgb(242, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(130, 76, 214, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(16, 10),
            Margin = new Thickness(12),
            Child = stack
        };

        Content = card;
        Opened += (_, _) =>
        {
            if (Screens.Primary != null)
            {
                var work = Screens.Primary.WorkingArea;
                var scale = Screens.Primary.Scaling;
                Position = new PixelPoint(
                    work.X + (int)((work.Width - Width * scale) / 2),
                    work.Y + (int)(26 * scale));
            }
            var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2.4) };
            t.Tick += (_, _) => { t.Stop(); Close(); };
            t.Start();
        };
    }

    public static void ShowToast(string message, string subtitle = "")
    {
        Dispatcher.UIThread.Post(() =>
        {
            var w = new ToastWindow(message, subtitle);
            w.Show();
        });
    }
}
