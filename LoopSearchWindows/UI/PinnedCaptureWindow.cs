using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using LoopSearch.Services;

namespace LoopSearch.UI;

public sealed class PinnedCaptureWindow : Window
{
    public PinnedCaptureWindow(System.Drawing.Bitmap croppedBitmap, string? ocrText)
    {
        Topmost = true;
        ShowInTaskbar = false;
        SystemDecorations = SystemDecorations.None;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        CanResize = true;

        double aspect = croppedBitmap.Width / (double)Math.Max(1, croppedBitmap.Height);
        double targetW = Math.Clamp(croppedBitmap.Width, 220, 440);
        double targetH = Math.Clamp(targetW / Math.Max(0.25, aspect), 140, 420) + 40;
        Width = targetW + 16;
        Height = targetH + 16;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var pngBytes = VisionOcrService.EncodePng(croppedBitmap);
        using var ms = new MemoryStream(pngBytes);
        var avBmp = new Bitmap(ms);

        var header = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto,Auto"),
            Margin = new Thickness(10, 6, 8, 4)
        };

        header.Children.Add(new TextBlock
        {
            Text = "Pinned Capture",
            FontSize = 11.5,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.SecondaryBrush,
            VerticalAlignment = VerticalAlignment.Center
        });

        var copyBtn = LiquidGlassUI.CreateGlassButton("Copy", () =>
        {
            NativeWin32.CopyBitmapToClipboard(croppedBitmap);
            ToastWindow.ShowToast("Copied pinned image to clipboard");
        }, height: 24, iconPath: LiquidGlassIcons.CopyDoc);
        Grid.SetColumn(copyBtn, 2);
        copyBtn.Margin = new Thickness(0, 0, 6, 0);
        header.Children.Add(copyBtn);

        var closeBtn = new Button
        {
            Content = LiquidGlassIcons.StrokeIcon(LiquidGlassIcons.CloseX, 11, ThemePalette.PrimaryBrush, 1.8),
            Width = 24,
            Height = 24,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(12),
            Background = new SolidColorBrush(ThemePalette.CardSubtleFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center
        };
        closeBtn.Click += (_, _) => Close();
        Grid.SetColumn(closeBtn, 3);
        header.Children.Add(closeBtn);

        header.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed)
                BeginMoveDrag(e);
        };

        var body = new DockPanel();
        DockPanel.SetDock(header, Dock.Top);
        body.Children.Add(header);
        body.Children.Add(new Border
        {
            Margin = new Thickness(8, 0, 8, 8),
            CornerRadius = new CornerRadius(10),
            ClipToBounds = true,
            Child = new Image { Source = avBmp, Stretch = Stretch.Uniform }
        });

        var card = LiquidGlassUI.CreateGlassCard(body, padding: new Thickness(0), radius: 14);
        card.Margin = new Thickness(8);
        card.BorderBrush = new SolidColorBrush(Color.FromArgb(145, 76, 214, 255));
        Content = card;
    }
}
