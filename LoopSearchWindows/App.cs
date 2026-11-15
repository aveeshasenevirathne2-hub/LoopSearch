using System.Diagnostics;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Platform;
using Avalonia.Themes.Fluent;
using Avalonia.Threading;
using LoopSearch.Models;
using LoopSearch.Services;
using LoopSearch.UI;

namespace LoopSearch;

public sealed class LoopSearchApp : Application
{
    private TrayIcon? _trayIcon;
    private OverlayWindow? _activeOverlay;
    private OnboardingWindow? _onboarding;
    private SettingsWindow? _settings;
    private HowToUseWindow? _guide;
    private FeedbackWindow? _feedback;
    private AboutWindow? _about;
    private HotkeyWatcher? _hotkeyWatcher;

    public override void Initialize()
    {
        Styles.Add(new FluentTheme());
        RequestedThemeVariant = ThemePalette.IsDark
            ? Avalonia.Styling.ThemeVariant.Dark
            : Avalonia.Styling.ThemeVariant.Light;
    }

    public override void OnFrameworkInitializationCompleted()
    {
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.ShutdownMode = ShutdownMode.OnExplicitShutdown;

            SetupTrayIcon(desktop);
            StartHotkeyWatcher();

            AppSettings.Shared.SettingsChanged += () => Dispatcher.UIThread.Post(() =>
            {
                RequestedThemeVariant = ThemePalette.IsDark
                    ? Avalonia.Styling.ThemeVariant.Dark
                    : Avalonia.Styling.ThemeVariant.Light;
                RebuildTrayMenu(desktop);
            });
            AppSettings.Shared.HistoryChanged += () => Dispatcher.UIThread.Post(() => RebuildTrayMenu(desktop));
            AppSettings.Shared.ReopenHistoryRequested += entry => Dispatcher.UIThread.Post(() => ReopenHistoryEntry(entry));

            _ = FirebaseAuthService.Shared.InitializeAsync();
            _ = CheckUpdatesSilentlyAsync();

            if (!AppSettings.Shared.HasCompletedOnboarding)
            {
                ShowOnboarding();
            }
            else if (AppSettings.Shared.ShowWelcomeOnLaunch)
            {
                ToastWindow.ShowToast("LoopSearch Ready", $"Press {AppSettings.Shared.Hotkey.DisplayString} anytime");
            }
        }

        base.OnFrameworkInitializationCompleted();
    }

    private void SetupTrayIcon(IClassicDesktopStyleApplicationLifetime desktop)
    {
        WindowIcon? icon = null;
        try
        {
            using var s = AssetLoader.Open(new Uri("avares://LoopSearch/Resources/AppIcon.png"));
            icon = new WindowIcon(s);
        }
        catch { }

        _trayIcon = new TrayIcon
        {
            Icon = icon,
            ToolTipText = $"LoopSearch ({AppSettings.Shared.Hotkey.DisplayString})",
            IsVisible = true
        };
        _trayIcon.Clicked += (_, _) => TriggerScreenSearch();
        RebuildTrayMenu(desktop);
    }

    private void RebuildTrayMenu(IClassicDesktopStyleApplicationLifetime desktop)
    {
        if (_trayIcon == null) return;
        _trayIcon.ToolTipText = $"LoopSearch ({AppSettings.Shared.Hotkey.DisplayString})";

        var menu = new NativeMenu();

        var searchItem = new NativeMenuItem($"Circle / Box Search ({AppSettings.Shared.Hotkey.CompactString})");
        searchItem.Click += (_, _) => TriggerScreenSearch();
        menu.Add(searchItem);

        var clipItem = new NativeMenuItem("Search Clipboard Image");
        clipItem.Click += (_, _) => TriggerClipboardSearch();
        menu.Add(clipItem);

        menu.Add(new NativeMenuItemSeparator());

        // Recent Captures submenu
        var recentParent = new NativeMenuItem("Recent Captures");
        var recentSub = new NativeMenu();
        var entries = CaptureHistoryStore.Shared.Entries;
        if (entries.Count == 0)
        {
            recentSub.Add(new NativeMenuItem("No recent captures") { IsEnabled = false });
        }
        else
        {
            foreach (var entry in entries)
            {
                var item = entry;
                var mi = new NativeMenuItem($"{item.ModeTitle}: {item.Summary}");
                mi.Click += (_, _) => ReopenHistoryEntry(item);
                recentSub.Add(mi);
            }
        }
        recentParent.Menu = recentSub;
        menu.Add(recentParent);

        menu.Add(new NativeMenuItemSeparator());

        var guideItem = new NativeMenuItem("How to Use…");
        guideItem.Click += (_, _) => ShowGuide();
        menu.Add(guideItem);

        var settingsItem = new NativeMenuItem("Studio Settings…");
        settingsItem.Click += (_, _) => ShowSettings();
        menu.Add(settingsItem);

        var feedbackItem = new NativeMenuItem("Rate & Suggest Feature…");
        feedbackItem.Click += (_, _) => ShowFeedback();
        menu.Add(feedbackItem);

        var aboutItem = new NativeMenuItem("About LoopSearch");
        aboutItem.Click += (_, _) => ShowAbout();
        menu.Add(aboutItem);

        menu.Add(new NativeMenuItemSeparator());

        var quitItem = new NativeMenuItem("Quit LoopSearch");
        quitItem.Click += (_, _) =>
        {
            _hotkeyWatcher?.Dispose();
            _trayIcon.IsVisible = false;
            desktop.Shutdown();
        };
        menu.Add(quitItem);

        _trayIcon.Menu = menu;
    }

    private void StartHotkeyWatcher()
    {
        if (!OperatingSystem.IsWindows()) return;
        _hotkeyWatcher = new HotkeyWatcher(() => Dispatcher.UIThread.Post(TriggerScreenSearch));
        _hotkeyWatcher.Start(AppSettings.Shared.Hotkey);
    }

    private void ReRegisterHotkey()
    {
        _hotkeyWatcher?.UpdateHotkey(AppSettings.Shared.Hotkey);
        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
            RebuildTrayMenu(desktop);
    }

    public void TriggerScreenSearch()
    {
        if (_activeOverlay != null)
        {
            _activeOverlay.Close();
            _activeOverlay = null;
            return;
        }

        var capture = NativeWin32.CaptureActiveMonitor();
        _activeOverlay = new OverlayWindow(capture, ShowSettings);
        _activeOverlay.Closed += (_, _) => _activeOverlay = null;
        _activeOverlay.Show();
    }

    private void TriggerClipboardSearch()
    {
        var bmp = NativeWin32.TryReadBitmapFromClipboard();
        if (bmp == null)
        {
            ToastWindow.ShowToast("No image in clipboard", "Copy an image first, then click Search Clipboard Image.");
            return;
        }
        if (_activeOverlay != null)
        {
            _activeOverlay.Close();
            _activeOverlay = null;
        }
        var screen = NativeWin32.CaptureActiveMonitor();
        _activeOverlay = new OverlayWindow(screen, ShowSettings, bmp);
        _activeOverlay.Closed += (_, _) => _activeOverlay = null;
        _activeOverlay.Show();
    }

    private void ReopenHistoryEntry(CaptureHistoryEntry entry)
    {
        if (!File.Exists(entry.ImagePath)) return;
        try
        {
            var bmp = new System.Drawing.Bitmap(entry.ImagePath);
            var screen = NativeWin32.CaptureActiveMonitor();
            _activeOverlay?.Close();
            _activeOverlay = new OverlayWindow(screen, ShowSettings, bmp);
            _activeOverlay.Closed += (_, _) => _activeOverlay = null;
            _activeOverlay.Show();
        }
        catch { }
    }

    private void ShowOnboarding()
    {
        if (_onboarding != null) { _onboarding.Activate(); return; }
        _onboarding = new OnboardingWindow(TriggerScreenSearch, ShowGuide, ReRegisterHotkey);
        _onboarding.Closed += (_, _) => _onboarding = null;
        _onboarding.Show();
    }

    private void ShowSettings()
    {
        if (_settings != null) { _settings.Activate(); return; }
        _settings = new SettingsWindow(ReRegisterHotkey);
        _settings.Closed += (_, _) => _settings = null;
        _settings.Show();
    }

    private void ShowGuide()
    {
        if (_guide != null) { _guide.Activate(); return; }
        _guide = new HowToUseWindow(TriggerScreenSearch, ShowSettings);
        _guide.Closed += (_, _) => _guide = null;
        _guide.Show();
    }

    private void ShowFeedback()
    {
        if (_feedback != null) { _feedback.Activate(); return; }
        _feedback = new FeedbackWindow();
        _feedback.Closed += (_, _) => _feedback = null;
        _feedback.Show();
    }

    private void ShowAbout()
    {
        if (_about != null) { _about.Activate(); return; }
        _about = new AboutWindow();
        _about.Closed += (_, _) => _about = null;
        _about.Show();
    }

    private static async Task CheckUpdatesSilentlyAsync()
    {
        await Task.Delay(3000);
        var upd = await AppUpdateChecker.CheckForUpdatesAsync();
        if (upd != null)
        {
            ToastWindow.ShowToast($"LoopSearch v{upd.Version} is available", "Open Settings → Check for Updates");
        }
    }

    private sealed class HotkeyWatcher : IDisposable
    {
        private const int HotkeyId = 0x4C53; // 'LS'
        private const int WM_APP_REBIND = 0x8001;
        private const int WM_QUIT = 0x0012;

        private readonly Action _onPressed;
        private Thread? _thread;
        private IntPtr _hwnd;
        private CustomHotkey _current = CustomHotkey.Default;
        private readonly ManualResetEventSlim _ready = new(false);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateWindowExW(uint exStyle, string cls, string name, uint style,
            int x, int y, int w, int h, IntPtr parent, IntPtr menu, IntPtr inst, IntPtr param);

        [DllImport("user32.dll")] private static extern bool DestroyWindow(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern bool PostMessageW(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] private static extern int GetMessageW(out MSG lpMsg, IntPtr hWnd, uint min, uint max);
        [DllImport("user32.dll")] private static extern bool TranslateMessage(ref MSG lpMsg);
        [DllImport("user32.dll")] private static extern IntPtr DispatchMessageW(ref MSG lpMsg);

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public NativeWin32.POINT pt;
        }

        public HotkeyWatcher(Action onPressed) => _onPressed = onPressed;

        public void Start(CustomHotkey initial)
        {
            _current = initial;
            _thread = new Thread(() =>
            {
                _hwnd = CreateWindowExW(0, "Message", "LoopSearchHotkeySink", 0, 0, 0, 0, 0,
                    new IntPtr(-3) /* HWND_MESSAGE */, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
                NativeWin32.TryRegisterGlobalHotkey(_hwnd, HotkeyId, _current);
                _ready.Set();

                while (GetMessageW(out var msg, IntPtr.Zero, 0, 0) > 0)
                {
                    if (msg.message == NativeWin32.WM_HOTKEY && msg.wParam.ToInt32() == HotkeyId)
                    {
                        _onPressed();
                    }
                    else if (msg.message == WM_APP_REBIND)
                    {
                        NativeWin32.TryRegisterGlobalHotkey(_hwnd, HotkeyId, _current);
                    }
                    else
                    {
                        TranslateMessage(ref msg);
                        DispatchMessageW(ref msg);
                    }
                }
                if (_hwnd != IntPtr.Zero)
                {
                    NativeWin32.UnregisterHotKey(_hwnd, HotkeyId);
                    DestroyWindow(_hwnd);
                    _hwnd = IntPtr.Zero;
                }
            })
            {
                IsBackground = true,
                Name = "LoopSearch-Hotkey"
            };
            _thread.Start();
            _ready.Wait(1000);
        }

        public void UpdateHotkey(CustomHotkey hotkey)
        {
            _current = hotkey;
            if (_hwnd != IntPtr.Zero)
                PostMessageW(_hwnd, WM_APP_REBIND, IntPtr.Zero, IntPtr.Zero);
        }

        public void Dispose()
        {
            if (_hwnd != IntPtr.Zero)
                PostMessageW(_hwnd, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
