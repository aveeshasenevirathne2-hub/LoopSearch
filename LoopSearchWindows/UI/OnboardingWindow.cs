using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Threading;
using LoopSearch.Models;
using LoopSearch.Services;

namespace LoopSearch.UI;

public sealed class OnboardingWindow : Window
{
    private readonly Action _onStartFirstSearch;
    private readonly Action _onOpenGuide;
    private readonly Action _onHotkeyChanged;

    private bool _isRecordingHotkey;
    private Button? _recordHotkeyBtn;
    private TextBlock? _hotkeyBadgeLabel;
    private TextBlock? _authStatusLabel;
    private Button? _authActionBtn;

    public OnboardingWindow(Action onStartFirstSearch, Action onOpenGuide, Action onHotkeyChanged)
    {
        _onStartFirstSearch = onStartFirstSearch;
        _onOpenGuide = onOpenGuide;
        _onHotkeyChanged = onHotkeyChanged;

        var cards = new List<Control>();
        var mainStack = new StackPanel { Spacing = 9, Margin = new Thickness(22, 4, 22, 18) };

        // Header
        var hdr = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Margin = new Thickness(0, 0, 0, 4) };
        hdr.Children.Add(LiquidGlassUI.CreateBrandBadge(40));
        var hCol = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 1 };
        hCol.Children.Add(new TextBlock
        {
            Text = "Welcome to LoopSearch",
            FontSize = 19,
            FontWeight = FontWeight.Bold,
            Foreground = ThemePalette.PrimaryBrush
        });
        hCol.Children.Add(new TextBlock
        {
            Text = "Sign in with Google and configure visual screen search, instant OCR, and AI.",
            FontSize = 11.5,
            Foreground = ThemePalette.SecondaryBrush
        });
        hdr.Children.Add(hCol);
        mainStack.Children.Add(hdr);

        // Step 1: Google Sign-In
        var step1 = BuildStep1Account();
        cards.Add(step1);
        mainStack.Children.Add(step1);

        // Step 2: Windows Capture & Tray Access
        var step2 = BuildStep2CaptureStatus();
        cards.Add(step2);
        mainStack.Children.Add(step2);

        // Step 3: Global Shortcut Presets + Custom Recorder
        var step3 = BuildStep3Shortcut();
        cards.Add(step3);
        mainStack.Children.Add(step3);

        // Step 4: Theme, Results Browser & Startup Toggles
        var step4 = BuildStep4Appearance();
        cards.Add(step4);
        mainStack.Children.Add(step4);

        // Footer Actions
        var footer = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto"), Margin = new Thickness(0, 4, 0, 0) };
        var guideBtn = LiquidGlassUI.CreateGlassButton("How to Use Guide", () =>
        {
            AppSettings.Shared.HasCompletedOnboarding = true;
            Close();
            _onOpenGuide();
        }, height: 32);
        footer.Children.Add(guideBtn);

        var startBtn = LiquidGlassUI.CreatePrimaryButton("Start First Search", () =>
        {
            AppSettings.Shared.HasCompletedOnboarding = true;
            Close();
            _onStartFirstSearch();
        }, height: 34, iconPath: LiquidGlassIcons.SearchGlass);
        Grid.SetColumn(startBtn, 2);
        footer.Children.Add(startBtn);
        mainStack.Children.Add(footer);

        var shell = LiquidGlassUI.WrapBorderlessGlassShell(this, 636, 568, "Welcome to LoopSearch", mainStack, showTitleInBar: false);

        KeyDown += OnWindowKeyDown;
        Opened += (_, _) =>
        {
            AppleMotion.AnimateWindowEntrance(this, shell);
            AppleMotion.StaggeredCardsReveal(cards, baseDelay: 0.05, stepDelay: 0.055);
        };
    }

    private Border BuildStep1Account()
    {
        var auth = FirebaseAuthService.Shared;
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        row.Children.Add(MakeStepBadge("1"));

        var textCol = new StackPanel { Spacing = 2, Margin = new Thickness(10, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
        textCol.Children.Add(new TextBlock { Text = "Sign in with Google", FontSize = 13, FontWeight = FontWeight.SemiBold, Foreground = ThemePalette.PrimaryBrush });
        textCol.Children.Add(new TextBlock
        {
            Text = "Connect your Google account for LoopSearch Analytics & sync across setups.",
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Foreground = ThemePalette.SecondaryBrush
        });
        Grid.SetColumn(textCol, 1);
        row.Children.Add(textCol);

        var rightRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        _authStatusLabel = new TextBlock
        {
            Text = auth.IsSignedIn ? $"✓ {auth.CurrentSession?.DisplayName}" : "Optional",
            FontSize = 11,
            FontWeight = FontWeight.SemiBold,
            Foreground = new SolidColorBrush(auth.IsSignedIn ? ThemePalette.SuccessGreen : ThemePalette.WarningAmber),
            VerticalAlignment = VerticalAlignment.Center
        };
        rightRow.Children.Add(_authStatusLabel);

        _authActionBtn = LiquidGlassUI.CreatePrimaryButton(auth.IsSignedIn ? "Switch Account" : "Sign in with Google", async () =>
        {
            if (_authStatusLabel != null)
            {
                _authStatusLabel.Text = "Opening browser…";
                _authStatusLabel.Foreground = ThemePalette.AccentCyanBrush;
            }
            var (ok, err) = await auth.SignInWithGoogleAsync();
            Dispatcher.UIThread.Post(() =>
            {
                if (_authStatusLabel == null) return;
                if (ok)
                {
                    _authStatusLabel.Text = $"✓ {auth.CurrentSession?.DisplayName}";
                    _authStatusLabel.Foreground = new SolidColorBrush(ThemePalette.SuccessGreen);
                    if (_authActionBtn?.Content is StackPanel sp && sp.Children.OfType<TextBlock>().FirstOrDefault() is { } tb)
                        tb.Text = "Switch Account";
                }
                else
                {
                    _authStatusLabel.Text = err ?? "Cancelled";
                    _authStatusLabel.Foreground = new SolidColorBrush(ThemePalette.WarningAmber);
                }
            });
        }, height: 28);
        rightRow.Children.Add(_authActionBtn);
        Grid.SetColumn(rightRow, 2);
        row.Children.Add(rightRow);

        return LiquidGlassUI.CreateGlassCard(row, padding: new Thickness(14, 11), radius: 14);
    }

    private Border BuildStep2CaptureStatus()
    {
        var row = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        row.Children.Add(MakeStepBadge("2"));

        var textCol = new StackPanel { Spacing = 2, Margin = new Thickness(10, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
        textCol.Children.Add(new TextBlock { Text = "Screen Capture & System Tray Ready", FontSize = 13, FontWeight = FontWeight.SemiBold, Foreground = ThemePalette.PrimaryBrush });
        textCol.Children.Add(new TextBlock
        {
            Text = "Runs quietly in your System Tray (bottom-right taskbar ^) with native WinRT OCR & WebView2.",
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Foreground = ThemePalette.SecondaryBrush
        });
        Grid.SetColumn(textCol, 1);
        row.Children.Add(textCol);

        var badgePill = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(35, 48, 209, 88)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(110, 48, 209, 88)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(9, 4),
            VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock { Text = "✓ Ready on Windows", FontSize = 11, FontWeight = FontWeight.SemiBold, Foreground = new SolidColorBrush(ThemePalette.SuccessGreen) }
        };
        Grid.SetColumn(badgePill, 2);
        row.Children.Add(badgePill);

        return LiquidGlassUI.CreateGlassCard(row, padding: new Thickness(14, 11), radius: 14);
    }

    private Border BuildStep3Shortcut()
    {
        var vstack = new StackPanel { Spacing = 8 };
        var topRow = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto") };
        topRow.Children.Add(MakeStepBadge("3"));

        var textCol = new StackPanel { Spacing = 1, Margin = new Thickness(10, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
        textCol.Children.Add(new TextBlock { Text = "Choose or Record Global Shortcut", FontSize = 13, FontWeight = FontWeight.SemiBold, Foreground = ThemePalette.PrimaryBrush });
        textCol.Children.Add(new TextBlock { Text = "Pick a quick preset or record your own key combination from start.", FontSize = 11, Foreground = ThemePalette.SecondaryBrush });
        Grid.SetColumn(textCol, 1);
        topRow.Children.Add(textCol);

        _hotkeyBadgeLabel = new TextBlock
        {
            Text = AppSettings.Shared.Hotkey.CompactString,
            FontFamily = new FontFamily("Consolas, Cascadia Mono, monospace"),
            FontSize = 11.5,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.PrimaryBrush
        };
        var badgePill = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(40, 36, 144, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(110, 92, 214, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(10, 4),
            VerticalAlignment = VerticalAlignment.Center,
            Child = _hotkeyBadgeLabel
        };
        Grid.SetColumn(badgePill, 2);
        topRow.Children.Add(badgePill);
        vstack.Children.Add(topRow);

        var controlsRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        var presetsRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        foreach (var preset in CustomHotkey.Presets.Take(3))
        {
            var p = preset;
            presetsRow.Children.Add(LiquidGlassUI.CreateGlassButton(p.CompactString, () =>
            {
                _isRecordingHotkey = false;
                AppSettings.Shared.Hotkey = p;
                if (_hotkeyBadgeLabel != null) _hotkeyBadgeLabel.Text = p.CompactString;
                _onHotkeyChanged();
            }, height: 26));
        }
        controlsRow.Children.Add(presetsRow);

        _recordHotkeyBtn = LiquidGlassUI.CreatePrimaryButton("Record Custom…", () =>
        {
            _isRecordingHotkey = true;
            if (_recordHotkeyBtn?.Content is StackPanel sp && sp.Children.OfType<TextBlock>().FirstOrDefault() is { } tb)
                tb.Text = "Press modifier + key…";
        }, height: 26, iconPath: LiquidGlassIcons.Keyboard);
        Grid.SetColumn(_recordHotkeyBtn, 1);
        controlsRow.Children.Add(_recordHotkeyBtn);
        vstack.Children.Add(controlsRow);

        return LiquidGlassUI.CreateGlassCard(vstack, padding: new Thickness(14, 11), radius: 14);
    }

    private Border BuildStep4Appearance()
    {
        var vstack = new StackPanel { Spacing = 8 };
        var topRow = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*") };
        topRow.Children.Add(MakeStepBadge("4"));

        var textCol = new StackPanel { Spacing = 1, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        textCol.Children.Add(new TextBlock { Text = "Appearance, Results Browser & Visibility", FontSize = 13, FontWeight = FontWeight.SemiBold, Foreground = ThemePalette.PrimaryBrush });
        textCol.Children.Add(new TextBlock { Text = "Choose Dark / Light mode for LoopSearch and Google Lens results.", FontSize = 11, Foreground = ThemePalette.SecondaryBrush });
        Grid.SetColumn(textCol, 1);
        topRow.Children.Add(textCol);
        vstack.Children.Add(topRow);

        var themesGrid = new Grid { ColumnDefinitions = new ColumnDefinitions("*,12,*") };
        var appThemeCol = new StackPanel { Spacing = 3 };
        appThemeCol.Children.Add(new TextBlock { Text = "App Glass Theme", FontSize = 10.5, Foreground = ThemePalette.MutedBrush });
        appThemeCol.Children.Add(LiquidGlassUI.CreateSegmentedControl(["Auto", "Dark", "Light"], (int)AppSettings.Shared.AppTheme, i => AppSettings.Shared.AppTheme = (AppTheme)i));
        themesGrid.Children.Add(appThemeCol);

        var webThemeCol = new StackPanel { Spacing = 3 };
        webThemeCol.Children.Add(new TextBlock { Text = "Results Browser", FontSize = 10.5, Foreground = ThemePalette.MutedBrush });
        webThemeCol.Children.Add(LiquidGlassUI.CreateSegmentedControl(["Auto", "Dark", "Light"], (int)AppSettings.Shared.WebResultsTheme, i => AppSettings.Shared.WebResultsTheme = (AppTheme)i));
        Grid.SetColumn(webThemeCol, 2);
        themesGrid.Children.Add(webThemeCol);
        vstack.Children.Add(themesGrid);

        var togglesRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 18 };
        var launchCb = new CheckBox { Content = "Launch at Windows Login", IsChecked = AppSettings.Shared.LaunchAtLogin, FontSize = 11.5, Foreground = ThemePalette.PrimaryBrush };
        launchCb.IsCheckedChanged += (_, _) => { bool v = launchCb.IsChecked == true; AppSettings.Shared.LaunchAtLogin = v; NativeWin32.SetLaunchAtLogin(v); };
        togglesRow.Children.Add(launchCb);

        var taskbarCb = new CheckBox { Content = "Show in Taskbar when open", IsChecked = AppSettings.Shared.KeepInTaskbar, FontSize = 11.5, Foreground = ThemePalette.PrimaryBrush };
        taskbarCb.IsCheckedChanged += (_, _) => AppSettings.Shared.KeepInTaskbar = taskbarCb.IsChecked == true;
        togglesRow.Children.Add(taskbarCb);
        vstack.Children.Add(togglesRow);

        return LiquidGlassUI.CreateGlassCard(vstack, padding: new Thickness(14, 11), radius: 14);
    }

    private static Border MakeStepBadge(string number) => new()
    {
        Width = 24,
        Height = 24,
        CornerRadius = new CornerRadius(12),
        Background = ThemePalette.AccentButtonBrush,
        BorderBrush = new SolidColorBrush(Color.FromArgb(140, 145, 228, 255)),
        BorderThickness = new Thickness(1),
        VerticalAlignment = VerticalAlignment.Center,
        Child = new TextBlock
        {
            Text = number,
            FontSize = 11.5,
            FontWeight = FontWeight.Bold,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        }
    };

    private void OnWindowKeyDown(object? sender, KeyEventArgs e)
    {
        if (!_isRecordingHotkey) return;
        if (e.Key is Key.LeftCtrl or Key.RightCtrl or Key.LeftShift or Key.RightShift or Key.LeftAlt or Key.RightAlt or Key.LWin or Key.RWin)
            return;

        uint mods = 0;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Control)) mods |= CustomHotkey.ModControl;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Alt)) mods |= CustomHotkey.ModAlt;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Shift)) mods |= CustomHotkey.ModShift;
        if (e.KeyModifiers.HasFlag(KeyModifiers.Meta)) mods |= CustomHotkey.ModWin;

        uint vk = KeyToWin32Vk(e.Key);
        if (mods != 0 && vk != 0)
        {
            var hk = new CustomHotkey { VirtualKey = vk, Modifiers = mods };
            AppSettings.Shared.Hotkey = hk;
            _isRecordingHotkey = false;
            if (_hotkeyBadgeLabel != null) _hotkeyBadgeLabel.Text = hk.CompactString;
            if (_recordHotkeyBtn?.Content is StackPanel sp && sp.Children.OfType<TextBlock>().FirstOrDefault() is { } tb)
                tb.Text = "Record Custom…";
            _onHotkeyChanged();
            e.Handled = true;
        }
    }

    public static uint KeyToWin32Vk(Key key) => key switch
    {
        Key.Space => 0x20,
        Key.Enter => 0x0D,
        Key.Tab => 0x09,
        Key.Delete => 0x2E,
        >= Key.A and <= Key.Z => (uint)('A' + (key - Key.A)),
        >= Key.D0 and <= Key.D9 => (uint)('0' + (key - Key.D0)),
        >= Key.F1 and <= Key.F12 => (uint)(0x70 + (key - Key.F1)),
        _ => 0
    };
}
