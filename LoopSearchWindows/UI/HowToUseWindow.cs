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
        LiquidGlassUI.ConfigureWindowChrome(this, 600, 560, "How to Use LoopSearch");

        var rootGrid = new Grid();
        rootGrid.Children.Add(new HorizonBackgroundView());

        var stack = new StackPanel { Spacing = 12, Margin = new Thickness(24, 20) };

        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        header.Children.Add(LiquidGlassUI.CreateBrandBadge(40));
        var hText = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        hText.Children.Add(new TextBlock { Text = "How to Use LoopSearch", FontSize = 18, FontWeight = FontWeight.Bold, Foreground = ThemePalette.PrimaryBrush });
        hText.Children.Add(new TextBlock { Text = $"Global Shortcut: {AppSettings.Shared.Hotkey.DisplayString}", FontSize = 12, Foreground = ThemePalette.AccentCyanBrush });
        header.Children.Add(hText);
        stack.Children.Add(header);

        stack.Children.Add(MakeTipCard("1 · Box Selection", "Drag a rectangle around any product, chart, code, or UI element to run Google Lens visual search."));
        stack.Children.Add(MakeTipCard("2 · Freehand Loop", "Draw a freehand circle or lasso around anything on screen — just like Circle to Search."));
        stack.Children.Add(MakeTipCard("3 · Smart Tap & 4 · Text OCR", "Tap to auto-capture an area, or switch to Text mode to copy on-device OCR text, solve math, and open URLs."));
        stack.Children.Add(MakeTipCard("Results Sheet Power Tools", "Pin floating captures (📌), toggle Dark/Light results (☾/☀), ask AI follow-ups, or click the #HEX color swatch to copy."));

        var footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 6, 0, 0) };
        footer.Children.Add(LiquidGlassUI.CreateGlassButton("Studio Settings", () => { Close(); onOpenSettings(); }));
        footer.Children.Add(LiquidGlassUI.CreatePrimaryButton("Try a Capture Now", () => { Close(); onStartSearch(); }));
        stack.Children.Add(footer);

        rootGrid.Children.Add(stack);
        Content = rootGrid;
        Opened += (_, _) => LiquidGlassUI.AnimateWindowEntrance(this, stack);
    }

    private static Control MakeTipCard(string title, string desc)
    {
        var s = new StackPanel { Spacing = 3 };
        s.Children.Add(new TextBlock { Text = title, FontSize = 13.5, FontWeight = FontWeight.SemiBold, Foreground = ThemePalette.PrimaryBrush });
        s.Children.Add(new TextBlock { Text = desc, FontSize = 12, TextWrapping = TextWrapping.Wrap, Foreground = ThemePalette.SecondaryBrush });
        return LiquidGlassUI.CreateGlassCard(s, padding: new Thickness(14, 11), radius: 13);
    }
}
