using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using LoopSearch.Models;

namespace LoopSearch.UI;

public sealed class HowToUseWindow : Window
{
    public HowToUseWindow(Action onStartSearch, Action onOpenSettings)
    {
        var cards = new List<Control>();
        var stack = new StackPanel { Spacing = 10, Margin = new Thickness(24, 4, 24, 20) };

        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new Thickness(0, 0, 0, 4) };
        header.Children.Add(LiquidGlassUI.CreateBrandBadge(40));
        var hText = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        hText.Children.Add(new TextBlock { Text = "How to Use LoopSearch", FontSize = 18, FontWeight = FontWeight.Bold, Foreground = ThemePalette.PrimaryBrush });
        hText.Children.Add(new TextBlock { Text = $"Global Shortcut: {AppSettings.Shared.Hotkey.DisplayString}", FontSize = 12, Foreground = ThemePalette.AccentCyanBrush });
        header.Children.Add(hText);
        stack.Children.Add(header);

        cards.Add(MakeTipCard("1 · Box Selection", "Drag a rectangle around any product, chart, code, or UI element to run Google Lens visual search.", LiquidGlassIcons.BoxSelect));
        cards.Add(MakeTipCard("2 · Freehand Loop", "Draw a freehand circle or lasso around anything on screen — just like Circle to Search.", LiquidGlassIcons.FreehandLasso));
        cards.Add(MakeTipCard("3 · Smart Tap & 4 · Text OCR", "Tap to auto-capture an area, or switch to Text mode to copy on-device Windows OCR text, solve math, and open URLs.", LiquidGlassIcons.TextScan));
        cards.Add(MakeTipCard("Results Sheet Power Tools", "Drag the results header to move it, pin floating captures, toggle Dark/Light results, or click any #HEX color swatch to copy.", LiquidGlassIcons.Sparkle));

        foreach (var c in cards) stack.Children.Add(c);

        var footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 6, 0, 0) };
        footer.Children.Add(LiquidGlassUI.CreateGlassButton("Studio Settings", () => { Close(); onOpenSettings(); }, iconPath: LiquidGlassIcons.SettingsGear));
        footer.Children.Add(LiquidGlassUI.CreatePrimaryButton("Try a Capture Now", () => { Close(); onStartSearch(); }, iconPath: LiquidGlassIcons.SearchGlass));
        stack.Children.Add(footer);

        var shell = LiquidGlassUI.WrapBorderlessGlassShell(this, 600, 500, "How to Use LoopSearch", stack, showTitleInBar: false);
        Opened += (_, _) =>
        {
            AppleMotion.AnimateWindowEntrance(this, shell);
            AppleMotion.StaggeredCardsReveal(cards, baseDelay: 0.04, stepDelay: 0.05);
        };
    }

    private static Control MakeTipCard(string title, string desc, string iconPath)
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*") };
        row.Children.Add(new Border
        {
            Width = 30,
            Height = 30,
            CornerRadius = new CornerRadius(9),
            Background = new SolidColorBrush(Color.FromArgb(42, 35, 130, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(95, 92, 224, 255)),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 12, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Child = LiquidGlassIcons.StrokeIcon(iconPath, 14, ThemePalette.AccentCyanBrush, 1.8)
        });

        var s = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        s.Children.Add(new TextBlock { Text = title, FontSize = 13, FontWeight = FontWeight.SemiBold, Foreground = ThemePalette.PrimaryBrush });
        s.Children.Add(new TextBlock { Text = desc, FontSize = 11.5, TextWrapping = TextWrapping.Wrap, Foreground = ThemePalette.SecondaryBrush });
        Grid.SetColumn(s, 1);
        row.Children.Add(s);

        return LiquidGlassUI.CreateGlassCard(row, padding: new Thickness(14, 11), radius: 14);
    }
}
