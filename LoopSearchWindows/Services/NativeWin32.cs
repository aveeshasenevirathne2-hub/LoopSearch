using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using LoopSearch.Models;
using Microsoft.Win32;

namespace LoopSearch.Services;

public sealed record ScreenCaptureData(Bitmap Bitmap, int VirtualX, int VirtualY, int Width, int Height);

public static class NativeWin32
{
    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private const int SM_CXVIRTUALSCREEN = 78;
    private const int SM_CYVIRTUALSCREEN = 79;

    private const int SRCCOPY = 0x00CC0020;
    private const int CAPTUREBLT = 0x40000000;

    private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;
    private const int DWMWA_SYSTEMBACKDROP_TYPE = 38;
    private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;

    public const int WM_HOTKEY = 0x0312;
    private const uint MOD_NOREPEAT = 0x4000;

    [DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int nWidth, int nHeight);

    [DllImport("gdi32.dll")]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr hgdiobj);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    [DllImport("gdi32.dll")]
    private static extern bool BitBlt(IntPtr hdcDest, int nXDest, int nYDest, int nWidth, int nHeight,
        IntPtr hdcSrc, int nXSrc, int nYSrc, int dwRop);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }

    public static ScreenCaptureData CaptureActiveMonitor()
    {
        GetCursorPos(out var pt);
        var hMon = MonitorFromPoint(pt, 2 /* MONITOR_DEFAULTTONEAREST */);
        var mi = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        if (hMon != IntPtr.Zero && GetMonitorInfo(hMon, ref mi))
        {
            int x = mi.rcMonitor.Left;
            int y = mi.rcMonitor.Top;
            int w = Math.Max(1, mi.rcMonitor.Right - mi.rcMonitor.Left);
            int h = Math.Max(1, mi.rcMonitor.Bottom - mi.rcMonitor.Top);
            return CaptureRegion(x, y, w, h);
        }
        return CaptureVirtualScreen();
    }

    public static ScreenCaptureData CaptureVirtualScreen()
    {
        int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int w = Math.Max(1, GetSystemMetrics(SM_CXVIRTUALSCREEN));
        int h = Math.Max(1, GetSystemMetrics(SM_CYVIRTUALSCREEN));
        return CaptureRegion(x, y, w, h);
    }

    public static ScreenCaptureData CaptureRegion(int x, int y, int width, int height)
    {
        IntPtr hdcScreen = GetDC(IntPtr.Zero);
        IntPtr hdcMem = CreateCompatibleDC(hdcScreen);
        IntPtr hBitmap = CreateCompatibleBitmap(hdcScreen, width, height);
        IntPtr hOld = SelectObject(hdcMem, hBitmap);
        try
        {
            BitBlt(hdcMem, 0, 0, width, height, hdcScreen, x, y, SRCCOPY | CAPTUREBLT);
            using var raw = Image.FromHbitmap(hBitmap);
            var copy = new Bitmap(raw.Width, raw.Height, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(copy))
            {
                g.DrawImageUnscaled(raw, 0, 0);
            }
            return new ScreenCaptureData(copy, x, y, width, height);
        }
        finally
        {
            SelectObject(hdcMem, hOld);
            DeleteObject(hBitmap);
            DeleteDC(hdcMem);
            ReleaseDC(IntPtr.Zero, hdcScreen);
        }
    }

    public static void ApplyGlassWindowAttributes(IntPtr hwnd, bool isDark, bool useBackdrop = true)
    {
        if (hwnd == IntPtr.Zero || !OperatingSystem.IsWindows()) return;
        try
        {
            int darkVal = isDark ? 1 : 0;
            DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkVal, sizeof(int));

            int cornerPref = 2; // DWMWCP_ROUND
            DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref cornerPref, sizeof(int));

            if (useBackdrop && Environment.OSVersion.Version.Build >= 22621)
            {
                int backdrop = 3; // DWMSBT_TRANSIENTWINDOW (Acrylic)
                DwmSetWindowAttribute(hwnd, DWMWA_SYSTEMBACKDROP_TYPE, ref backdrop, sizeof(int));
            }
        }
        catch { }
    }

    public static bool IsSystemDarkMode()
    {
        if (!OperatingSystem.IsWindows()) return true;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var val = key?.GetValue("AppsUseLightTheme");
            if (val is int intVal) return intVal == 0;
        }
        catch { }
        return true;
    }

    public static void SetLaunchAtLogin(bool enabled)
    {
        if (!OperatingSystem.IsWindows()) return;
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", writable: true);
            if (key == null) return;
            if (enabled)
            {
                var exePath = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName;
                if (!string.IsNullOrWhiteSpace(exePath))
                    key.SetValue("LoopSearch", $"\"{exePath}\"");
            }
            else
            {
                key.DeleteValue("LoopSearch", throwOnMissingValue: false);
            }
        }
        catch { }
    }

    public static bool TryRegisterGlobalHotkey(IntPtr hwnd, int id, CustomHotkey hotkey)
    {
        if (hwnd == IntPtr.Zero || !hotkey.IsValid) return false;
        UnregisterHotKey(hwnd, id);
        return RegisterHotKey(hwnd, id, hotkey.Modifiers | MOD_NOREPEAT, hotkey.VirtualKey);
    }

    [DllImport("user32.dll")]
    private static extern bool MessageBeep(uint uType);

    public static void PlaySubtleSound(bool isSuccess)
    {
        if (!AppSettings.Shared.SoundEffects || !OperatingSystem.IsWindows()) return;
        try
        {
            if (isSuccess)
                MessageBeep(0x00000040); // MB_ICONASTERISK
        }
        catch { }
    }

    public static void CopyBitmapToClipboard(Bitmap bmp)
    {
        if (!OperatingSystem.IsWindows()) return;
        try
        {
            var thread = new Thread(() =>
            {
                try
                {
                    // Use Win32 OpenClipboard + CF_DIBV5 or CF_DIB
                    SetClipboardBitmapWin32(bmp);
                }
                catch { }
            });
            thread.SetApartmentState(ApartmentState.STA);
            thread.Start();
            thread.Join(500);
        }
        catch { }
    }

    [DllImport("user32.dll")] private static extern bool OpenClipboard(IntPtr hWndNewOwner);
    [DllImport("user32.dll")] private static extern bool EmptyClipboard();
    [DllImport("user32.dll")] private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);
    [DllImport("user32.dll")] private static extern bool CloseClipboard();
    [DllImport("user32.dll")] private static extern bool IsClipboardFormatAvailable(uint format);
    [DllImport("user32.dll")] private static extern IntPtr GetClipboardData(uint uFormat);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);
    [DllImport("kernel32.dll")] private static extern IntPtr GlobalLock(IntPtr hMem);
    [DllImport("kernel32.dll")] private static extern bool GlobalUnlock(IntPtr hMem);

    private const uint CF_DIB = 8;
    private const uint GMEM_MOVEABLE = 0x0002;

    private static void SetClipboardBitmapWin32(Bitmap bmp)
    {
        using var ms = new MemoryStream();
        bmp.Save(ms, ImageFormat.Bmp);
        var bmpBytes = ms.ToArray();
        // BMP file header is 14 bytes; CF_DIB expects BITMAPINFOHEADER onward
        if (bmpBytes.Length <= 14) return;
        int dibLen = bmpBytes.Length - 14;

        IntPtr hMem = GlobalAlloc(GMEM_MOVEABLE, (UIntPtr)dibLen);
        if (hMem == IntPtr.Zero) return;
        IntPtr ptr = GlobalLock(hMem);
        if (ptr == IntPtr.Zero) return;
        try
        {
            Marshal.Copy(bmpBytes, 14, ptr, dibLen);
        }
        finally
        {
            GlobalUnlock(hMem);
        }

        if (OpenClipboard(IntPtr.Zero))
        {
            try
            {
                EmptyClipboard();
                SetClipboardData(CF_DIB, hMem);
            }
            finally
            {
                CloseClipboard();
            }
        }
    }

    public static Bitmap? TryReadBitmapFromClipboard()
    {
        if (!OperatingSystem.IsWindows()) return null;
        Bitmap? result = null;
        var thread = new Thread(() =>
        {
            try
            {
                if (!IsClipboardFormatAvailable(CF_DIB)) return;
                if (!OpenClipboard(IntPtr.Zero)) return;
                try
                {
                    IntPtr hData = GetClipboardData(CF_DIB);
                    if (hData == IntPtr.Zero) return;
                    IntPtr ptr = GlobalLock(hData);
                    if (ptr == IntPtr.Zero) return;
                    try
                    {
                        int headerSize = Marshal.ReadInt32(ptr);
                        int width = Marshal.ReadInt32(ptr, 4);
                        int height = Marshal.ReadInt32(ptr, 8);
                        short bpp = Marshal.ReadInt16(ptr, 14);
                        int imageSize = Marshal.ReadInt32(ptr, 20);
                        int absH = Math.Abs(height);
                        int stride = ((width * bpp + 31) / 32) * 4;
                        if (imageSize <= 0) imageSize = stride * absH;
                        int totalDib = headerSize + imageSize;
                        byte[] fullBmp = new byte[14 + totalDib];
                        fullBmp[0] = (byte)'B';
                        fullBmp[1] = (byte)'M';
                        BitConverter.GetBytes(fullBmp.Length).CopyTo(fullBmp, 2);
                        BitConverter.GetBytes(14 + headerSize).CopyTo(fullBmp, 10);
                        Marshal.Copy(ptr, fullBmp, 14, totalDib);
                        using var ms = new MemoryStream(fullBmp);
                        result = new Bitmap(ms);
                    }
                    finally { GlobalUnlock(hData); }
                }
                finally { CloseClipboard(); }
            }
            catch { }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join(500);
        return result;
    }
}
