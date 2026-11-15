using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using LoopSearch.Models;
using LoopSearch.Services;

namespace LoopSearch.UI;

public sealed class SettingsWindow : Window
{
    private readonly Action _onHotkeyChanged;
    private bool _isRecordingHotkey;
    private Button? _recordBtn;
    private TextBlock? _hotkeyLabel;

    public SettingsWindow(Action onHotkeyChanged)
    {
        _onHotkeyChanged = onHotkeyChanged;

        var cards = new List<Control>();
        var mainStack = new StackPanel { Spacing = 12, Margin = new Thickness(24, 4, 24, 22) };

        // Header
        var hdr = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new Thickness(0, 0, 0, 2) };
        hdr.Children.Add(LiquidGlassUI.CreateBrandBadge(40));
        var hText = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        hText.Children.Add(new TextBlock { Text = "Studio Settings", FontSize = 19, FontWeight = FontWeight.Bold, Foreground = ThemePalette.PrimaryBrush });
        hText.Children.Add(new TextBlock { Text = $"LoopSearch Windows v{AppSettings.CurrentAppVersion}", FontSize = 12, Foreground = ThemePalette.SecondaryBrush });
        hdr.Children.Add(hText);
        mainStack.Children.Add(hdr);

        var c1 = BuildAccountSection();
        var c2 = BuildCaptureSection();
        var c3 = BuildAppearanceSection();
        var c4 = BuildSystemSection();
        var c5 = BuildHistorySection();
        cards.AddRange([c1, c2, c3, c4, c5]);
        foreach (var c in cards) mainStack.Children.Add(c);

        var footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        footer.Children.Add(LiquidGlassUI.CreateGlassButton("Copy Diagnostics", async () =>
        {
            var auth = FirebaseAuthService.Shared;
            var authSummary = auth.IsSignedIn ? $"{auth.CurrentSession?.Email} (Last sync: {auth.LastAnalyticsSuccessAt?.ToString("u") ?? "pending"})" : "Signed out";
            var report = AppSettings.Shared.BuildDiagnosticsReport(authSummary);
            if (Clipboard != null) await Clipboard.SetTextAsync(report);
            ToastWindow.ShowToast("Copied diagnostics to clipboard");
        }, iconPath: LiquidGlassIcons.CopyDoc));
        footer.Children.Add(LiquidGlassUI.CreateGlassButton("Check for Updates", async () =>
        {
            var upd = await AppUpdateChecker.CheckForUpdatesAsync();
            if (upd != null)
            {
                ToastWindow.ShowToast($"Update v{upd.Version} available!", "Opening GitHub Releases…");
                Process.Start(new ProcessStartInfo(upd.ReleaseUrl) { UseShellExecute = true });
            }
            else
            {
                ToastWindow.ShowToast("LoopSearch is up to date", $"Running v{AppSettings.CurrentAppVersion}");
            }
        }));
        footer.Children.Add(LiquidGlassUI.CreateGlassButton("Reset Defaults", () =>
        {
            AppSettings.Shared.ResetToDefaults();
            _onHotkeyChanged();
            ToastWindow.ShowToast("Settings reset to defaults");
            Close();
        }));
        mainStack.Children.Add(footer);

        var scroll = new ScrollViewer { Content = mainStack };
        var shell = LiquidGlassUI.WrapBorderlessGlassShell(this, 668, 700, "LoopSearch Studio Settings", scroll, showTitleInBar: false, resizable: true);

        KeyDown += OnSettingsKeyDown;
        Opened += (_, _) =>
        {
            AppleMotion.AnimateWindowEntrance(this, shell);
            AppleMotion.StaggeredCardsReveal(cards, baseDelay: 0.04, stepDelay: 0.045);
        };
    }

    private Control BuildAccountSection()
    {
        var auth = FirebaseAuthService.Shared;
        var s = new StackPanel { Spacing = 8 };
        s.Children.Add(SectionTitle("Account & LoopSearch Analytics"));

        var status = new TextBlock
        {
            Text = auth.IsSignedIn
                ? $"✓ Signed in as {auth.CurrentSession?.DisplayName} · {auth.CurrentSession?.Email}"
                : "Not signed in. Sign in with Google to sync with LoopSearch Analytics.",
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground = auth.IsSignedIn ? new SolidColorBrush(ThemePalette.SuccessGreen) : ThemePalette.SecondaryBrush
        };
        s.Children.Add(status);

        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(LiquidGlassUI.CreatePrimaryButton(auth.IsSignedIn ? "Switch Google Account" : "Sign in with Google", async () =>
        {
            status.Text = "Waiting for browser Google Sign-In…";
            status.Foreground = ThemePalette.AccentCyanBrush;
            var (ok, err) = await auth.SignInWithGoogleAsync();
            Dispatcher.UIThread.Post(() =>
            {
                if (ok)
                {
                    status.Foreground = new SolidColorBrush(ThemePalette.SuccessGreen);
                    status.Text = $"✓ Signed in as {auth.CurrentSession?.DisplayName} · {auth.CurrentSession?.Email}";
                }
                else
                {
                    status.Foreground = new SolidColorBrush(ThemePalette.WarningAmber);
                    status.Text = err ?? "Sign-in cancelled.";
                }
            });
        }, height: 30));

        if (auth.IsSignedIn)
        {
            row.Children.Add(LiquidGlassUI.CreateGlassButton("Sync Now", async () =>
            {
                auth.EnqueueEvent("manual_sync");
                await auth.FlushPendingEventsAsync();
                ToastWindow.ShowToast("Analytics synced", auth.LastAnalyticsError ?? "Sent to LoopSearch Analytics");
            }, height: 30));

            row.Children.Add(LiquidGlassUI.CreateGlassButton("Sign Out", () =>
            {
                auth.SignOut();
                status.Foreground = ThemePalette.SecondaryBrush;
                status.Text = "Signed out.";
            }, height: 30));
        }
        s.Children.Add(row);

        return LiquidGlassUI.CreateGlassCard(s);
    }

    private Control BuildCaptureSection()
    {
        var s = new StackPanel { Spacing = 10 };
        s.Children.Add(SectionTitle("Capture & Search"));

        _hotkeyLabel = new TextBlock
        {
            Text = $"Global Shortcut: {AppSettings.Shared.Hotkey.DisplayString}",
            FontSize = 12.5,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.AccentCyanBrush
        };
        s.Children.Add(_hotkeyLabel);

        var presetRow = new WrapPanel { Orientation = Orientation.Horizontal };
        foreach (var preset in CustomHotkey.Presets)
        {
            var p = preset;
            var btn = LiquidGlassUI.CreateGlassButton(p.CompactString, () =>
            {
                AppSettings.Shared.Hotkey = p;
                _hotkeyLabel.Text = $"Global Shortcut: {p.DisplayString}";
                _onHotkeyChanged();
            }, height: 28);
            btn.Margin = new Thickness(0, 0, 6, 6);
            presetRow.Children.Add(btn);
        }
        _recordBtn = LiquidGlassUI.CreatePrimaryButton("Record Custom…", () =>
        {
            _isRecordingHotkey = true;
            if (_recordBtn?.Content is StackPanel sp && sp.Children.OfType<TextBlock>().FirstOrDefault() is { } tb)
                tb.Text = "Press modifier + key…";
        }, height: 28, iconPath: LiquidGlassIcons.Keyboard);
        presetRow.Children.Add(_recordBtn);
        s.Children.Add(presetRow);

        s.Children.Add(Row("Default Mode", LiquidGlassUI.CreateSegmentedControl(
            ["Box", "Freehand", "Tap", "Text"],
            (int)AppSettings.Shared.DefaultMode,
            idx => AppSettings.Shared.DefaultMode = (LoopSearch.Models.SelectionMode)idx)));

        s.Children.Add(Row("Search Engine", LiquidGlassUI.CreateSegmentedControl(
            ["Lens", "Google", "Perplexity", "Bing", "Ask AI"],
            (int)AppSettings.Shared.SearchEngine,
            idx => AppSettings.Shared.SearchEngine = (SearchEngine)idx)));

        return LiquidGlassUI.CreateGlassCard(s);
    }

    private Control BuildAppearanceSection()
    {
        var s = new StackPanel { Spacing = 10 };
        s.Children.Add(SectionTitle("Appearance & Liquid Glass"));

        s.Children.Add(Row("App Glass Theme", LiquidGlassUI.CreateSegmentedControl(
            ["Auto", "Dark", "Light"],
            (int)AppSettings.Shared.AppTheme,
            idx => AppSettings.Shared.AppTheme = (AppTheme)idx)));

        s.Children.Add(Row("Results Browser", LiquidGlassUI.CreateSegmentedControl(
            ["Auto", "Dark", "Light"],
            (int)AppSettings.Shared.WebResultsTheme,
            idx => AppSettings.Shared.WebResultsTheme = (AppTheme)idx)));

        s.Children.Add(Row("Aura Palette", LiquidGlassUI.CreateSegmentedControl(
            ["Loop Aura", "Spectrum"],
            (int)AppSettings.Shared.GlowColorTheme,
            idx => AppSettings.Shared.GlowColorTheme = (GlowColorTheme)idx)));

        s.Children.Add(Row("Glow Intensity", LiquidGlassUI.CreateSegmentedControl(
            ["Subtle", "Balanced", "Vivid"],
            (int)AppSettings.Shared.GlowIntensity,
            idx => AppSettings.Shared.GlowIntensity = (GlowIntensity)idx)));

        s.Children.Add(Row("Motion Feel", LiquidGlassUI.CreateSegmentedControl(
            ["Crisp", "Smooth", "Fluid"],
            (int)AppSettings.Shared.MotionFeel,
            idx => AppSettings.Shared.MotionFeel = (MotionFeel)idx)));

        return LiquidGlassUI.CreateGlassCard(s);
    }

    private Control BuildSystemSection()
    {
        var s = new StackPanel { Spacing = 8 };
        s.Children.Add(SectionTitle("System & AI Follow-ups"));

        var launchCb = new CheckBox
        {
            Content = "Launch LoopSearch at Windows login",
            IsChecked = AppSettings.Shared.LaunchAtLogin,
            Foreground = ThemePalette.PrimaryBrush,
            FontSize = 12
        };
        launchCb.IsCheckedChanged += (_, _) =>
        {
            bool v = launchCb.IsChecked == true;
            AppSettings.Shared.LaunchAtLogin = v;
            NativeWin32.SetLaunchAtLogin(v);
        };
        s.Children.Add(launchCb);

        var welcomeCb = new CheckBox
        {
            Content = "Show Ready toast when starting LoopSearch",
            IsChecked = AppSettings.Shared.ShowWelcomeOnLaunch,
            Foreground = ThemePalette.PrimaryBrush,
            FontSize = 12
        };
        welcomeCb.IsCheckedChanged += (_, _) => AppSettings.Shared.ShowWelcomeOnLaunch = welcomeCb.IsChecked == true;
        s.Children.Add(welcomeCb);

        var soundCb = new CheckBox
        {
            Content = "Play subtle capture sound",
            IsChecked = AppSettings.Shared.SoundEffects,
            Foreground = ThemePalette.PrimaryBrush,
            FontSize = 12
        };
        soundCb.IsCheckedChanged += (_, _) => AppSettings.Shared.SoundEffects = soundCb.IsChecked == true;
        s.Children.Add(soundCb);

        var keyRow = new Grid { ColumnDefinitions = new ColumnDefinitions("165,*,Auto"), Margin = new Thickness(0, 4, 0, 0) };
        keyRow.Children.Add(new TextBlock
        {
            Text = "Gemini API Key (Optional)",
            FontSize = 12,
            Foreground = ThemePalette.SecondaryBrush,
            VerticalAlignment = VerticalAlignment.Center
        });
        var keyBox = new TextBox
        {
            Watermark = "AIza... (encrypted with Windows DPAPI)",
            PasswordChar = '•',
            Text = AppSettings.Shared.GeminiApiKey ?? "",
            FontSize = 12
        };
        Grid.SetColumn(keyBox, 1);
        keyRow.Children.Add(keyBox);
        var saveKeyBtn = LiquidGlassUI.CreateGlassButton("Save", () =>
        {
            AppSettings.Shared.GeminiApiKey = keyBox.Text;
            ToastWindow.ShowToast("Gemini API key updated");
        }, height: 30);
        saveKeyBtn.Margin = new Thickness(6, 0, 0, 0);
        Grid.SetColumn(saveKeyBtn, 2);
        keyRow.Children.Add(saveKeyBtn);
        s.Children.Add(keyRow);

        return LiquidGlassUI.CreateGlassCard(s);
    }

    private Control BuildHistorySection()
    {
        var s = new StackPanel { Spacing = 8 };
        var top = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        top.Children.Add(SectionTitle("Recent Captures"));
        var clearBtn = LiquidGlassUI.CreateGlassButton("Clear", () =>
        {
            CaptureHistoryStore.Shared.Clear();
            ToastWindow.ShowToast("Cleared recent captures");
        }, height: 26);
        Grid.SetColumn(clearBtn, 1);
        top.Children.Add(clearBtn);
        s.Children.Add(top);

        var entries = CaptureHistoryStore.Shared.Entries;
        if (entries.Count == 0)
        {
            s.Children.Add(new TextBlock { Text = "No recent captures yet.", FontSize = 12, Foreground = ThemePalette.MutedBrush });
        }
        else
        {
            foreach (var entry in entries)
            {
                var item = entry;
                var b = LiquidGlassUI.CreateGlassButton($"{item.ModeTitle} · {item.Summary}", () =>
                {
                    Close();
                    AppSettings.Shared.RequestReopenHistory(item);
                }, height: 30);
                b.HorizontalAlignment = HorizontalAlignment.Stretch;
                b.HorizontalContentAlignment = HorizontalAlignment.Left;
                s.Children.Add(b);
            }
        }
        return LiquidGlassUI.CreateGlassCard(s);
    }

    private static TextBlock SectionTitle(string title) => new()
    {
        Text = title,
        FontSize = 14,
        FontWeight = FontWeight.SemiBold,
        Foreground = ThemePalette.PrimaryBrush
    };

    private static Control Row(string label, Control ctrl)
    {
        var g = new Grid { ColumnDefinitions = new ColumnDefinitions("155,*") };
        g.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 12,
            Foreground = ThemePalette.SecondaryBrush,
            VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetColumn(ctrl, 1);
        g.Children.Add(ctrl);
        return g;
    }

    private void OnSettingsKeyDown(object? sender, KeyEventArgs e)
    {
        if (!_isRecordingHotkey) return;
        if (e.Key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
            return;

        uint mods = 0;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Control)) mods |= CustomHotkey.ModControl;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Alt)) mods |= CustomHotkey.ModAlt;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Shift)) mods |= CustomHotkey.ModShift;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Meta)) mods |= CustomHotkey.ModWin;

        uint vk = OnboardingWindow.KeyToWin32Vk(e.Key);
        if (mods != 0 && vk != 0)
        {
            var hk = new CustomHotkey { VirtualKey = vk, Modifiers = mods };
            AppSettings.Shared.Hotkey = hk;
            _isRecordingHotkey = false;
            if (_hotkeyLabel != null) _hotkeyLabel.Text = $"Global Shortcut: {hk.DisplayString}";
            if (_recordBtn?.Content is StackPanel sp && sp.Children.OfType<TextBlock>().FirstOrDefault() is { } tb)
                tb.Text = "Record Custom…";
            _onHotkeyChanged();
            e.Handled = true;
        }
    }
}
