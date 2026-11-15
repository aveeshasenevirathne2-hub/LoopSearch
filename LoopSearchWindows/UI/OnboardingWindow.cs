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
    private int _step;
    private readonly ContentControl _stepContainer = new();
    private readonly Border[] _dots = new Border[4];
    private readonly Button _backBtn;
    private readonly Button _nextBtn;
    private readonly Action _onStartFirstSearch;
    private readonly Action _onOpenGuide;
    private readonly Action _onHotkeyChanged;

    private bool _isRecordingHotkey;
    private Button? _recordHotkeyBtn;
    private TextBlock? _hotkeyDisplayLabel;

    public OnboardingWindow(Action onStartFirstSearch, Action onOpenGuide, Action onHotkeyChanged)
    {
        _onStartFirstSearch = onStartFirstSearch;
        _onOpenGuide = onOpenGuide;
        _onHotkeyChanged = onHotkeyChanged;

        LiquidGlassUI.ConfigureWindowChrome(this, 620, 560, "Welcome to LoopSearch");

        var rootGrid = new Grid();
        rootGrid.Children.Add(new HorizonBackgroundView());

        var mainDock = new DockPanel { Margin = new Thickness(26, 22, 26, 20) };

        // Top header
        var topRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 14)
        };
        topRow.Children.Add(LiquidGlassUI.CreateBrandBadge(42));
        var titleCol = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        titleCol.Children.Add(new TextBlock
        {
            Text = "LoopSearch",
            FontSize = 20,
            FontWeight = FontWeight.Bold,
            Foreground = ThemePalette.PrimaryBrush
        });
        titleCol.Children.Add(new TextBlock
        {
            Text = "Circle, box, or tap anything on your Windows screen",
            FontSize = 12,
            Foreground = ThemePalette.SecondaryBrush
        });
        topRow.Children.Add(titleCol);
        DockPanel.SetDock(topRow, Dock.Top);
        mainDock.Children.Add(topRow);

        // Bottom nav
        var navGrid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*,Auto"), Margin = new Thickness(0, 14, 0, 0) };
        _backBtn = LiquidGlassUI.CreateGlassButton("Back", () =>
        {
            if (_step > 0) { _step--; RenderStep(); }
        });
        navGrid.Children.Add(_backBtn);

        var dotsRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 8,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        for (int i = 0; i < 4; i++)
        {
            _dots[i] = new Border { Width = 8, Height = 8, CornerRadius = new CornerRadius(4) };
            dotsRow.Children.Add(_dots[i]);
        }
        Grid.SetColumn(dotsRow, 1);
        navGrid.Children.Add(dotsRow);

        _nextBtn = LiquidGlassUI.CreatePrimaryButton("Continue", () =>
        {
            if (_step < 3)
            {
                _step++;
                RenderStep();
            }
            else
            {
                AppSettings.Shared.HasCompletedOnboarding = true;
                Close();
                _onStartFirstSearch();
            }
        });
        Grid.SetColumn(_nextBtn, 2);
        navGrid.Children.Add(_nextBtn);

        DockPanel.SetDock(navGrid, Dock.Bottom);
        mainDock.Children.Add(navGrid);

        mainDock.Children.Add(_stepContainer);
        rootGrid.Children.Add(mainDock);
        Content = rootGrid;

        KeyDown += OnWindowKeyDown;
        Opened += (_, _) => LiquidGlassUI.AnimateWindowEntrance(this, mainDock);
        RenderStep();
    }

    private void RenderStep()
    {
        _isRecordingHotkey = false;
        _backBtn.IsVisible = _step > 0;
        if (_nextBtn.Content is TextBlock nb)
            nb.Text = _step == 3 ? "Start First Search" : "Continue";

        for (int i = 0; i < _dots.Length; i++)
        {
            bool active = i == _step;
            _dots[i].Width = active ? 22 : 8;
            _dots[i].Background = active ? ThemePalette.AccentButtonBrush : new SolidColorBrush(ThemePalette.CardBorder);
        }

        _stepContainer.Content = _step switch
        {
            0 => BuildAccountStep(),
            1 => BuildHotkeyStep(),
            2 => BuildThemeAndSystemStep(),
            _ => BuildReadyStep()
        };
    }

    private Control BuildAccountStep()
    {
        var auth = FirebaseAuthService.Shared;
        var cardStack = new StackPanel { Spacing = 14 };
        cardStack.Children.Add(new TextBlock
        {
            Text = "Step 1 · Sign in with Google",
            FontSize = 16,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.PrimaryBrush
        });
        cardStack.Children.Add(new TextBlock
        {
            Text = "Connect your Google account to sync usage with LoopSearch Analytics and unlock seamless updates across your devices.",
            FontSize = 12.5,
            TextWrapping = TextWrapping.Wrap,
            Foreground = ThemePalette.SecondaryBrush
        });

        var statusLabel = new TextBlock
        {
            Text = auth.IsSignedIn
                ? $"Signed in as {auth.CurrentSession?.DisplayName} ({auth.CurrentSession?.Email})"
                : "Not signed in yet (you can also sign in later from Settings).",
            FontSize = 12,
            Foreground = auth.IsSignedIn ? new SolidColorBrush(ThemePalette.SuccessGreen) : ThemePalette.MutedBrush,
            TextWrapping = TextWrapping.Wrap
        };
        cardStack.Children.Add(statusLabel);

        var btnRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var signInBtn = LiquidGlassUI.CreatePrimaryButton(auth.IsSignedIn ? "Switch Google Account" : "Sign in with Google", async () =>
        {
            statusLabel.Text = "Opening browser for Google Sign-In…";
            var (ok, err) = await auth.SignInWithGoogleAsync();
            Dispatcher.UIThread.Post(() =>
            {
                if (ok)
                {
                    statusLabel.Foreground = new SolidColorBrush(ThemePalette.SuccessGreen);
                    statusLabel.Text = $"Signed in as {auth.CurrentSession?.DisplayName} ({auth.CurrentSession?.Email})";
                }
                else
                {
                    statusLabel.Foreground = new SolidColorBrush(ThemePalette.WarningAmber);
                    statusLabel.Text = err ?? "Sign-in cancelled.";
                }
            });
        });
        btnRow.Children.Add(signInBtn);

        if (auth.IsSignedIn)
        {
            btnRow.Children.Add(LiquidGlassUI.CreateGlassButton("Sign Out", () =>
            {
                auth.SignOut();
                RenderStep();
            }));
        }
        cardStack.Children.Add(btnRow);

        return LiquidGlassUI.CreateGlassCard(cardStack, padding: new Thickness(20));
    }

    private Control BuildHotkeyStep()
    {
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(new TextBlock
        {
            Text = "Step 2 · Set Your Global Shortcut",
            FontSize = 16,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.PrimaryBrush
        });
        stack.Children.Add(new TextBlock
        {
            Text = "Trigger LoopSearch from anywhere on Windows — even when minimized to the System Tray.",
            FontSize = 12.5,
            TextWrapping = TextWrapping.Wrap,
            Foreground = ThemePalette.SecondaryBrush
        });

        _hotkeyDisplayLabel = new TextBlock
        {
            Text = $"Active Shortcut: {AppSettings.Shared.Hotkey.DisplayString}",
            FontSize = 14,
            FontWeight = FontWeight.Bold,
            Foreground = ThemePalette.AccentCyanBrush
        };
        stack.Children.Add(_hotkeyDisplayLabel);

        var presetsWrap = new WrapPanel { Orientation = Orientation.Horizontal };
        foreach (var preset in CustomHotkey.Presets)
        {
            var p = preset;
            var b = LiquidGlassUI.CreateGlassButton(p.CompactString, () =>
            {
                AppSettings.Shared.Hotkey = p;
                _hotkeyDisplayLabel.Text = $"Active Shortcut: {p.DisplayString}";
                _onHotkeyChanged();
            }, height: 30);
            b.Margin = new Thickness(0, 0, 8, 8);
            presetsWrap.Children.Add(b);
        }
        stack.Children.Add(presetsWrap);

        _recordHotkeyBtn = LiquidGlassUI.CreatePrimaryButton("Record Custom Shortcut…", () =>
        {
            _isRecordingHotkey = true;
            if (_recordHotkeyBtn?.Content is TextBlock tb)
                tb.Text = "Press modifier + key (e.g. Ctrl+Shift+Space)…";
        });
        stack.Children.Add(_recordHotkeyBtn);

        return LiquidGlassUI.CreateGlassCard(stack, padding: new Thickness(20));
    }

    private Control BuildThemeAndSystemStep()
    {
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(new TextBlock
        {
            Text = "Step 3 · Appearance & Startup",
            FontSize = 16,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.PrimaryBrush
        });

        stack.Children.Add(LabeledRow("App Glass Theme", LiquidGlassUI.CreateSegmentedControl(
            ["Auto", "Dark", "Light"],
            (int)AppSettings.Shared.AppTheme,
            idx => AppSettings.Shared.AppTheme = (AppTheme)idx)));

        stack.Children.Add(LabeledRow("Results Browser Theme", LiquidGlassUI.CreateSegmentedControl(
            ["Auto", "Dark", "Light"],
            (int)AppSettings.Shared.WebResultsTheme,
            idx => AppSettings.Shared.WebResultsTheme = (AppTheme)idx)));

        stack.Children.Add(LabeledRow("Selection Glow", LiquidGlassUI.CreateSegmentedControl(
            ["Loop Aura", "Spectrum"],
            (int)AppSettings.Shared.GlowColorTheme,
            idx => AppSettings.Shared.GlowColorTheme = (GlowColorTheme)idx)));

        var startupCheck = new CheckBox
        {
            Content = "Launch LoopSearch automatically when Windows starts",
            IsChecked = AppSettings.Shared.LaunchAtLogin,
            Foreground = ThemePalette.PrimaryBrush,
            FontSize = 12.5
        };
        startupCheck.IsCheckedChanged += (_, _) =>
        {
            bool val = startupCheck.IsChecked == true;
            AppSettings.Shared.LaunchAtLogin = val;
            NativeWin32.SetLaunchAtLogin(val);
        };
        stack.Children.Add(startupCheck);

        var taskbarCheck = new CheckBox
        {
            Content = "Keep quick settings accessible in System Tray (and Taskbar when open)",
            IsChecked = AppSettings.Shared.KeepInTaskbar,
            Foreground = ThemePalette.PrimaryBrush,
            FontSize = 12.5
        };
        taskbarCheck.IsCheckedChanged += (_, _) => AppSettings.Shared.KeepInTaskbar = taskbarCheck.IsChecked == true;
        stack.Children.Add(taskbarCheck);

        return LiquidGlassUI.CreateGlassCard(stack, padding: new Thickness(20));
    }

    private Control BuildReadyStep()
    {
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(new TextBlock
        {
            Text = "You're All Set!",
            FontSize = 18,
            FontWeight = FontWeight.Bold,
            Foreground = ThemePalette.PrimaryBrush
        });
        stack.Children.Add(new TextBlock
        {
            Text = $"Press {AppSettings.Shared.Hotkey.DisplayString} anytime (or click the LoopSearch System Tray icon) to freeze your screen and circle, box, tap, or copy text.",
            FontSize = 12.5,
            TextWrapping = TextWrapping.Wrap,
            Foreground = ThemePalette.SecondaryBrush
        });

        var guideBtn = LiquidGlassUI.CreateGlassButton("View How-To Guide", () =>
        {
            AppSettings.Shared.HasCompletedOnboarding = true;
            Close();
            _onOpenGuide();
        });
        guideBtn.HorizontalAlignment = HorizontalAlignment.Left;
        stack.Children.Add(guideBtn);

        return LiquidGlassUI.CreateGlassCard(stack, padding: new Thickness(20));
    }

    private static Control LabeledRow(string label, Control control)
    {
        var grid = new Grid { ColumnDefinitions = new ColumnDefinitions("170,*"), Margin = new Thickness(0, 2) };
        grid.Children.Add(new TextBlock
        {
            Text = label,
            FontSize = 12.5,
            Foreground = ThemePalette.SecondaryBrush,
            VerticalAlignment = VerticalAlignment.Center
        });
        Grid.SetColumn(control, 1);
        grid.Children.Add(control);
        return grid;
    }

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
            if (_hotkeyDisplayLabel != null)
                _hotkeyDisplayLabel.Text = $"Active Shortcut: {hk.DisplayString}";
            if (_recordHotkeyBtn?.Content is TextBlock tb)
                tb.Text = "Record Custom Shortcut…";
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
