using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Layout;
using Avalonia.Media;
using LoopSearch.Models;

namespace LoopSearch.UI;

public sealed class AboutWindow : Window
{
    public AboutWindow()
    {
        LiquidGlassUI.ConfigureWindowChrome(this, 420, 340, "About LoopSearch");

        var rootGrid = new Grid();
        rootGrid.Children.Add(new HorizonBackgroundView());

        var stack = new StackPanel
        {
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(24)
        };

        var badge = LiquidGlassUI.CreateBrandBadge(68);
        badge.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(badge);

        stack.Children.Add(new TextBlock
        {
            Text = "LoopSearch for Windows",
            FontSize = 19,
            FontWeight = FontWeight.Bold,
            HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = ThemePalette.PrimaryBrush
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"Version {AppSettings.CurrentAppVersion} · Liquid Glass Edition",
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
            Foreground = ThemePalette.AccentCyanBrush
        });
        stack.Children.Add(new TextBlock
        {
            Text = "Independent visual screen search utility powered by Windows WinRT OCR, Microsoft Edge WebView2, and Firebase Analytics.",
            FontSize = 11.5,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
            Foreground = ThemePalette.SecondaryBrush
        });

        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 0) };
        row.Children.Add(LiquidGlassUI.CreateGlassButton("GitHub Repo", () =>
        {
            Process.Start(new ProcessStartInfo($"https://github.com/{AppSettings.GitHubRepo}") { UseShellExecute = true });
        }));
        row.Children.Add(LiquidGlassUI.CreatePrimaryButton("Check Updates", async () =>
        {
            var upd = await AppUpdateChecker.CheckForUpdatesAsync();
            if (upd != null)
            {
                ToastWindow.ShowToast($"Update v{upd.Version} available!");
                Process.Start(new ProcessStartInfo(upd.ReleaseUrl) { UseShellExecute = true });
            }
            else
            {
                ToastWindow.ShowToast("Up to date", $"LoopSearch v{AppSettings.CurrentAppVersion}");
            }
        }));
        stack.Children.Add(row);

        rootGrid.Children.Add(stack);
        Content = rootGrid;
        Opened += (_, _) => LiquidGlassUI.AnimateWindowEntrance(this, stack);
    }
}
