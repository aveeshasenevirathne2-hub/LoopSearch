using System.Net;
using System.Runtime.InteropServices;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Platform;
using LoopSearch.Models;
using LoopSearch.Services;
using Microsoft.Web.WebView2.Core;

namespace LoopSearch.UI;

/// <summary>
/// Hosts Microsoft Edge WebView2 inside an Avalonia NativeControlHost for embedded Google Lens / Search / AI results.
/// </summary>
public sealed class WebView2Host : NativeControlHost
{
    private IntPtr _hostHwnd;
    private CoreWebView2Environment? _env;
    private CoreWebView2Controller? _controller;
    private CoreWebView2? _core;
    private string? _pendingUrl;
    private IReadOnlyList<Cookie>? _pendingCookies;
    private bool _pendingMobileUa;
    private bool _isDisposed;

    public event Action<bool>? LoadingChanged;
    public event Action<bool>? CanGoBackChanged;
    public event Action<string>? TitleOrUrlChanged;

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowExW(
        uint dwExStyle, string lpClassName, string lpWindowName, uint dwStyle,
        int x, int y, int nWidth, int nHeight,
        IntPtr hWndParent, IntPtr hMenu, IntPtr hInstance, IntPtr lpParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool MoveWindow(IntPtr hWnd, int x, int y, int nWidth, int nHeight, bool bRepaint);

    private const uint WS_CHILD = 0x40000000;
    private const uint WS_VISIBLE = 0x10000000;
    private const uint WS_CLIPCHILDREN = 0x02000000;

    protected override IPlatformHandle CreateNativeControlCore(IPlatformHandle parent)
    {
        if (OperatingSystem.IsWindows())
        {
            _hostHwnd = CreateWindowExW(
                0,
                "STATIC",
                "",
                WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN,
                0, 0, Math.Max(1, (int)Bounds.Width), Math.Max(1, (int)Bounds.Height),
                parent.Handle,
                IntPtr.Zero,
                IntPtr.Zero,
                IntPtr.Zero);

            _ = InitializeWebView2Async(_hostHwnd);
            return new PlatformHandle(_hostHwnd, "HWND");
        }
        return base.CreateNativeControlCore(parent);
    }

    protected override void DestroyNativeControlCore(IPlatformHandle control)
    {
        _isDisposed = true;
        try { _controller?.Close(); } catch { }
        _controller = null;
        _core = null;
        if (_hostHwnd != IntPtr.Zero && OperatingSystem.IsWindows())
        {
            DestroyWindow(_hostHwnd);
            _hostHwnd = IntPtr.Zero;
        }
        base.DestroyNativeControlCore(control);
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        var arranged = base.ArrangeOverride(finalSize);
        UpdateBounds(arranged);
        return arranged;
    }

    private void UpdateBounds(Size size)
    {
        if (!OperatingSystem.IsWindows() || _hostHwnd == IntPtr.Zero) return;
        double scale = VisualRoot?.RenderScaling ?? 1.0;
        int pw = Math.Max(1, (int)Math.Round(size.Width * scale));
        int ph = Math.Max(1, (int)Math.Round(size.Height * scale));
        MoveWindow(_hostHwnd, 0, 0, pw, ph, true);
        if (_controller != null)
        {
            _controller.Bounds = new System.Drawing.Rectangle(0, 0, pw, ph);
        }
    }

    private async Task InitializeWebView2Async(IntPtr hwnd)
    {
        try
        {
            var userDataDir = Path.Combine(AppPaths.DataDirectory, "WebView2");
            Directory.CreateDirectory(userDataDir);

            _env = await CoreWebView2Environment.CreateAsync(null, userDataDir);
            if (_isDisposed || hwnd == IntPtr.Zero) return;

            _controller = await _env.CreateCoreWebView2ControllerAsync(hwnd);
            if (_isDisposed)
            {
                _controller.Close();
                return;
            }

            _core = _controller.CoreWebView2;
            _controller.DefaultBackgroundColor = ThemePalette.IsWebDark
                ? System.Drawing.Color.FromArgb(255, 11, 16, 29)
                : System.Drawing.Color.FromArgb(255, 245, 248, 253);

            _core.Settings.AreDevToolsEnabled = false;
            _core.Settings.AreDefaultContextMenusEnabled = true;
            _core.Settings.IsStatusBarEnabled = false;

            _core.NavigationStarting += (_, _) =>
            {
                LoadingChanged?.Invoke(true);
            };
            _core.DOMContentLoaded += async (_, _) =>
            {
                await ApplyVisualScriptsAsync();
            };
            _core.NavigationCompleted += async (_, _) =>
            {
                await ApplyVisualScriptsAsync();
                LoadingChanged?.Invoke(false);
                CanGoBackChanged?.Invoke(_core?.CanGoBack ?? false);
                if (_core?.Source != null)
                    TitleOrUrlChanged?.Invoke(_core.Source);
            };

            UpdateBounds(Bounds.Size);

            if (!string.IsNullOrEmpty(_pendingUrl))
            {
                await NavigateInternalAsync(_pendingUrl, _pendingCookies, _pendingMobileUa);
                _pendingUrl = null;
                _pendingCookies = null;
            }
        }
        catch
        {
            LoadingChanged?.Invoke(false);
        }
    }

    public void Navigate(string url, IReadOnlyList<Cookie>? cookies = null, bool useMobileUa = false)
    {
        if (_core == null)
        {
            _pendingUrl = url;
            _pendingCookies = cookies;
            _pendingMobileUa = useMobileUa;
            return;
        }
        _ = NavigateInternalAsync(url, cookies, useMobileUa);
    }

    private async Task NavigateInternalAsync(string url, IReadOnlyList<Cookie>? cookies, bool useMobileUa)
    {
        if (_core == null) return;
        try
        {
            _core.Settings.UserAgent = useMobileUa
                ? GoogleLensService.MobileUserAgent
                : "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

            if (cookies != null && cookies.Count > 0)
            {
                var cm = _core.CookieManager;
                foreach (var c in cookies)
                {
                    try
                    {
                        var webCookie = cm.CreateCookie(c.Name, c.Value, string.IsNullOrEmpty(c.Domain) ? ".google.com" : c.Domain, string.IsNullOrEmpty(c.Path) ? "/" : c.Path);
                        webCookie.IsSecure = c.Secure;
                        cm.AddOrUpdateCookie(webCookie);
                    }
                    catch { }
                }
            }

            _core.Navigate(url);
        }
        catch { }
        await Task.CompletedTask;
    }

    public void GoBack()
    {
        if (_core?.CanGoBack == true) _core.GoBack();
    }

    public void Reload()
    {
        _core?.Reload();
    }

    public async Task ApplyColorSchemeAsync()
    {
        await ApplyVisualScriptsAsync();
    }

    private async Task ApplyVisualScriptsAsync()
    {
        if (_core == null) return;
        try
        {
            bool dark = ThemePalette.IsWebDark;
            if (_controller != null)
            {
                _controller.DefaultBackgroundColor = dark
                    ? System.Drawing.Color.FromArgb(255, 11, 16, 29)
                    : System.Drawing.Color.FromArgb(255, 245, 248, 253);
            }
            _core.Profile.PreferredColorScheme = dark
                ? CoreWebView2PreferredColorScheme.Dark
                : CoreWebView2PreferredColorScheme.Light;

            await _core.ExecuteScriptAsync(GoogleLensCleanUpScript);
            await _core.ExecuteScriptAsync(BuildColorSchemeScript(dark));
        }
        catch { }
    }

    private const string GoogleLensCleanUpScript = """
    (function() {
        if (location.pathname.indexOf('/sorry') === 0) return;
        var st = document.getElementById('cts-clean-style');
        if (!st) {
            st = document.createElement('style');
            st.id = 'cts-clean-style';
            st.textContent = `
                header, #searchform, form[action="/search"], [role="search"],
                div[data-hveid] input[aria-label*="Add to your search"],
                div[jscontroller] > div > a[aria-label="Google"],
                div[aria-label="Add to your search"],
                hr, [role="separator"] {
                    display: none !important;
                }
                body {
                    padding-top: 2px !important;
                    overflow-x: hidden !important;
                }
                div[data-attrid], div[data-hveid], section, c-wiz {
                    margin-bottom: 4px !important;
                }
                a, [role="button"], button, div[data-hveid] > div, g-card, .g {
                    transition: transform 0.20s cubic-bezier(0.22, 1, 0.36, 1),
                                box-shadow 0.22s ease,
                                background-color 0.18s ease,
                                border-color 0.18s ease,
                                opacity 0.18s ease !important;
                }
                a img {
                    transition: transform 0.24s cubic-bezier(0.22, 1, 0.36, 1),
                                filter 0.20s ease !important;
                }
                a:hover img {
                    transform: scale(1.028) !important;
                    filter: brightness(1.06) !important;
                }
                g-card:hover, div[jsaction] a:hover {
                    border-color: rgba(74, 194, 255, 0.34) !important;
                }
                button:hover, [role="button"]:hover {
                    opacity: 0.94 !important;
                }
            `;
            (document.head || document.documentElement).appendChild(st);
        }
        var walker = document.querySelectorAll('input, span, div');
        for (var i = 0; i < walker.length; i++) {
            var el = walker[i];
            var txt = (el.getAttribute('placeholder') || el.getAttribute('aria-label') || '').toLowerCase();
            if (txt.indexOf('add to your search') !== -1) {
                var box = el.closest('form') || el.closest('[role="search"]') || el.parentElement;
                if (box && box.offsetHeight < 120) {
                    box.style.setProperty('display', 'none', 'important');
                }
            }
        }
        var allDivs = document.querySelectorAll('div, section');
        for (var j = 0; j < allDivs.length; j++) {
            var d = allDivs[j];
            if (d.children.length === 0 && d.textContent.trim() === '' && d.offsetHeight >= 18 && d.offsetHeight <= 140) {
                var bg = window.getComputedStyle(d).backgroundImage;
                if (!bg || bg === 'none') {
                    d.style.setProperty('display', 'none', 'important');
                }
            }
        }
    })();
    """;

    private static string BuildColorSchemeScript(bool dark)
    {
        if (!dark)
        {
            return """
            (function() {
                document.documentElement.style.colorScheme = 'light';
                var st = document.getElementById('cts-theme-style');
                if (st) st.remove();
                var els = document.querySelectorAll('[data-cts-darkbg]');
                for (var i = 0; i < els.length; i++) {
                    els[i].style.removeProperty('background-color');
                    els[i].style.removeProperty('background-image');
                    els[i].style.removeProperty('color');
                    els[i].removeAttribute('data-cts-darkbg');
                }
            })();
            """;
        }

        return """
        (function() {
            document.documentElement.style.colorScheme = 'dark';
            var st = document.getElementById('cts-theme-style');
            if (!st) {
                st = document.createElement('style');
                st.id = 'cts-theme-style';
                st.textContent = `
                    html, body {
                        background: #0b101d !important;
                        color: #e9f1ff !important;
                    }
                    a { color: #7cc4ff !important; }
                    code, pre, kbd, samp, tt, mark {
                        background: #17233b !important;
                        color: #dbeafe !important;
                        border: 1px solid rgba(124, 196, 255, 0.20) !important;
                        border-radius: 5px !important;
                    }
                    hr { border-color: rgba(130, 175, 255, 0.16) !important; }
                `;
                (document.head || document.documentElement).appendChild(st);
            }
            var all = document.getElementsByTagName('*');
            var limit = Math.min(all.length, 1800);
            for (var i = 0; i < limit; i++) {
                var el = all[i];
                var tag = el.tagName;
                if (tag === 'IMG' || tag === 'VIDEO' || tag === 'CANVAS' || tag === 'SVG' || tag === 'PATH') continue;
                var cs = window.getComputedStyle(el);
                if (!cs) continue;
                var bg = cs.backgroundColor;
                if (bg && bg.indexOf('rgb') === 0) {
                    var m = bg.match(/\d+/g);
                    if (m && m.length >= 3) {
                        var a = m.length >= 4 ? parseFloat(m[3]) : 255;
                        var r = parseInt(m[0]), g = parseInt(m[1]), b = parseInt(m[2]);
                        var lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
                        if (a > 20 && lum > 175) {
                            el.style.setProperty('background-color', '#11192c', 'important');
                            el.style.setProperty('color', '#e9f1ff', 'important');
                            el.setAttribute('data-cts-darkbg', '1');
                        }
                    }
                }
                if (cs.backgroundImage && cs.backgroundImage.indexOf('gradient') !== -1 && cs.backgroundImage.indexOf('255') !== -1) {
                    el.style.setProperty('background-image', 'none', 'important');
                    el.style.setProperty('background-color', '#11192c', 'important');
                    el.setAttribute('data-cts-darkbg', '1');
                }
            }
        })();
        """;
    }
}
