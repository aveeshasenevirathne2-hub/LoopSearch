using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace LoopSearch.Models;

public sealed class AppSettingsData
{
    public SelectionMode DefaultMode { get; set; } = SelectionMode.Box;
    public SearchEngine SearchEngine { get; set; } = SearchEngine.GoogleLens;
    public AppTheme AppTheme { get; set; } = AppTheme.Dark;
    public AppTheme WebResultsTheme { get; set; } = AppTheme.Dark;
    public VisualStylePreset VisualStyle { get; set; } = VisualStylePreset.Horizon;
    public GlowColorTheme GlowColorTheme { get; set; } = GlowColorTheme.Signature;
    public GlowIntensity GlowIntensity { get; set; } = GlowIntensity.Luminous;
    public MotionFeel MotionFeel { get; set; } = MotionFeel.Fluid;
    public bool SoundEffects { get; set; } = true;
    public bool HasCompletedOnboarding { get; set; } = false;
    public bool ShowWelcomeOnLaunch { get; set; } = true;
    public bool LaunchAtLogin { get; set; } = false;
    public bool KeepInTaskbar { get; set; } = true;
    public CustomHotkey Hotkey { get; set; } = CustomHotkey.Default;
    public string? EncryptedGeminiKeyBase64 { get; set; }
}

public sealed class AppSettings
{
    public const string CurrentAppVersion = "1.0.3";
    public const string GitHubRepo = "aveeshasenevirathne2-hub/LoopSearch";

    public static AppSettings Shared { get; } = new();

    private readonly string _settingsPath;
    private readonly object _lock = new();
    private AppSettingsData _data;

    public event Action? SettingsChanged;
    public event Action? HistoryChanged;
    public event Action<CaptureHistoryEntry>? ReopenHistoryRequested;

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public AppSettings(string? customDirectory = null)
    {
        var dir = customDirectory ?? AppPaths.DataDirectory;
        Directory.CreateDirectory(dir);
        _settingsPath = Path.Combine(dir, "settings.json");
        _data = LoadFromDisk();
    }

    private AppSettingsData LoadFromDisk()
    {
        try
        {
            if (File.Exists(_settingsPath))
            {
                var json = File.ReadAllText(_settingsPath);
                var loaded = JsonSerializer.Deserialize<AppSettingsData>(json, JsonOpts);
                if (loaded != null) return loaded;
            }
        }
        catch { /* fallback to defaults */ }
        return new AppSettingsData();
    }

    private void SaveAndNotify()
    {
        lock (_lock)
        {
            try
            {
                var json = JsonSerializer.Serialize(_data, JsonOpts);
                File.WriteAllText(_settingsPath, json);
            }
            catch { /* non-fatal */ }
        }
        SettingsChanged?.Invoke();
    }

    public SelectionMode DefaultMode
    {
        get => _data.DefaultMode;
        set { if (_data.DefaultMode != value) { _data.DefaultMode = value; SaveAndNotify(); } }
    }

    public SearchEngine SearchEngine
    {
        get => _data.SearchEngine;
        set { if (_data.SearchEngine != value) { _data.SearchEngine = value; SaveAndNotify(); } }
    }

    public AppTheme AppTheme
    {
        get => _data.AppTheme;
        set { if (_data.AppTheme != value) { _data.AppTheme = value; SaveAndNotify(); } }
    }

    public AppTheme WebResultsTheme
    {
        get => _data.WebResultsTheme;
        set { if (_data.WebResultsTheme != value) { _data.WebResultsTheme = value; SaveAndNotify(); } }
    }

    public VisualStylePreset VisualStyle
    {
        get => _data.VisualStyle;
        set { if (_data.VisualStyle != value) { _data.VisualStyle = value; SaveAndNotify(); } }
    }

    public GlowColorTheme GlowColorTheme
    {
        get => _data.GlowColorTheme;
        set { if (_data.GlowColorTheme != value) { _data.GlowColorTheme = value; SaveAndNotify(); } }
    }

    public GlowIntensity GlowIntensity
    {
        get => _data.GlowIntensity;
        set { if (_data.GlowIntensity != value) { _data.GlowIntensity = value; SaveAndNotify(); } }
    }

    public MotionFeel MotionFeel
    {
        get => _data.MotionFeel;
        set { if (_data.MotionFeel != value) { _data.MotionFeel = value; SaveAndNotify(); } }
    }

    public bool SoundEffects
    {
        get => _data.SoundEffects;
        set { if (_data.SoundEffects != value) { _data.SoundEffects = value; SaveAndNotify(); } }
    }

    public bool HasCompletedOnboarding
    {
        get => _data.HasCompletedOnboarding;
        set { if (_data.HasCompletedOnboarding != value) { _data.HasCompletedOnboarding = value; SaveAndNotify(); } }
    }

    public bool ShowWelcomeOnLaunch
    {
        get => _data.ShowWelcomeOnLaunch;
        set { if (_data.ShowWelcomeOnLaunch != value) { _data.ShowWelcomeOnLaunch = value; SaveAndNotify(); } }
    }

    public bool LaunchAtLogin
    {
        get => _data.LaunchAtLogin;
        set { if (_data.LaunchAtLogin != value) { _data.LaunchAtLogin = value; SaveAndNotify(); } }
    }

    public bool KeepInTaskbar
    {
        get => _data.KeepInTaskbar;
        set { if (_data.KeepInTaskbar != value) { _data.KeepInTaskbar = value; SaveAndNotify(); } }
    }

    public CustomHotkey Hotkey
    {
        get => _data.Hotkey;
        set { if (_data.Hotkey != value) { _data.Hotkey = value; SaveAndNotify(); } }
    }

    public string? GeminiApiKey
    {
        get => PrivateDataProtector.UnprotectString(_data.EncryptedGeminiKeyBase64);
        set
        {
            _data.EncryptedGeminiKeyBase64 = string.IsNullOrWhiteSpace(value)
                ? null
                : PrivateDataProtector.ProtectString(value.Trim());
            SaveAndNotify();
        }
    }

    public bool EffectiveIsDark(bool systemIsDark) => AppTheme switch
    {
        AppTheme.Dark => true,
        AppTheme.Light => false,
        _ => systemIsDark
    };

    public bool EffectiveWebIsDark(bool systemIsDark) => WebResultsTheme switch
    {
        AppTheme.Dark => true,
        AppTheme.Light => false,
        _ => systemIsDark
    };

    public void ResetToDefaults()
    {
        _data = new AppSettingsData { HasCompletedOnboarding = true };
        SaveAndNotify();
    }

    public void NotifyHistoryChanged() => HistoryChanged?.Invoke();
    public void RequestReopenHistory(CaptureHistoryEntry entry) => ReopenHistoryRequested?.Invoke(entry);

    public string BuildDiagnosticsReport(string? authStatusSummary = null)
    {
        var sb = new StringBuilder();
        sb.AppendLine($"LoopSearch Windows v{CurrentAppVersion}");
        sb.AppendLine($"OS: {RuntimeInformation.OSDescription} ({RuntimeInformation.ProcessArchitecture})");
        sb.AppendLine($"Default Mode: {DefaultMode.Title()}");
        sb.AppendLine($"Search Engine: {SearchEngine.Title()}");
        sb.AppendLine($"App Theme: {AppTheme.Title()} | Results Theme: {WebResultsTheme.Title()}");
        sb.AppendLine($"Visual Style: {VisualStyle.Title()} | Aura: {GlowColorTheme.Title()} | Glow: {GlowIntensity.Title()} | Motion: {MotionFeel.Title()}");
        sb.AppendLine($"Hotkey: {Hotkey.CompactString}");
        sb.AppendLine($"Launch at Login: {LaunchAtLogin} | Keep in Taskbar: {KeepInTaskbar}");
        if (!string.IsNullOrWhiteSpace(authStatusSummary))
            sb.AppendLine($"Account: {authStatusSummary}");
        return sb.ToString().TrimEnd();
    }
}

public static class AppPaths
{
    public static string DataDirectory
    {
        get
        {
            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrWhiteSpace(local))
                local = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "share");
            var dir = Path.Combine(local, "LoopSearch");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string HistoryDirectory
    {
        get
        {
            var dir = Path.Combine(DataDirectory, "history");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }
}

public static class PrivateDataProtector
{
    public static string? ProtectString(string? plain)
    {
        if (string.IsNullOrEmpty(plain)) return null;
        var bytes = Encoding.UTF8.GetBytes(plain);
        var protectedBytes = ProtectBytes(bytes);
        return Convert.ToBase64String(protectedBytes);
    }

    public static string? UnprotectString(string? base64)
    {
        if (string.IsNullOrWhiteSpace(base64)) return null;
        try
        {
            var bytes = Convert.FromBase64String(base64);
            var plain = UnprotectBytes(bytes);
            return Encoding.UTF8.GetString(plain);
        }
        catch
        {
            return null;
        }
    }

    public static byte[] ProtectBytes(byte[] plain)
    {
        if (OperatingSystem.IsWindows())
        {
            return ProtectedData.Protect(plain, null, DataProtectionScope.CurrentUser);
        }
        // Fallback obfuscation only used when unit-testing on non-Windows hosts
        return plain;
    }

    public static byte[] UnprotectBytes(byte[] protectedData)
    {
        if (OperatingSystem.IsWindows())
        {
            return ProtectedData.Unprotect(protectedData, null, DataProtectionScope.CurrentUser);
        }
        return protectedData;
    }
}

public sealed class CaptureHistoryEntry
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.UtcNow;
    public string ImagePath { get; set; } = "";
    public string Summary { get; set; } = "";
    public string ModeTitle { get; set; } = "Box";
    public string? DominantHex { get; set; }
    public string? OcrText { get; set; }
}

public sealed class CaptureHistoryStore
{
    public static CaptureHistoryStore Shared { get; } = new();
    private const int MaxEntries = 4;
    private readonly string _indexPath;
    private readonly List<CaptureHistoryEntry> _entries = [];

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    public CaptureHistoryStore(string? customDirectory = null)
    {
        var dir = customDirectory ?? AppPaths.HistoryDirectory;
        Directory.CreateDirectory(dir);
        _indexPath = Path.Combine(dir, "index.json");
        Load();
    }

    public IReadOnlyList<CaptureHistoryEntry> Entries => _entries.AsReadOnly();

    private void Load()
    {
        try
        {
            if (File.Exists(_indexPath))
            {
                var list = JsonSerializer.Deserialize<List<CaptureHistoryEntry>>(File.ReadAllText(_indexPath), JsonOpts);
                if (list != null)
                {
                    _entries.Clear();
                    _entries.AddRange(list.Where(e => File.Exists(e.ImagePath)).Take(MaxEntries));
                }
            }
        }
        catch { /* ignore corrupt history */ }
    }

    private void Save()
    {
        try
        {
            File.WriteAllText(_indexPath, JsonSerializer.Serialize(_entries, JsonOpts));
        }
        catch { /* ignore */ }
    }

    public CaptureHistoryEntry Add(byte[] jpegBytes, string summary, SelectionMode mode, string? dominantHex, string? ocrText)
    {
        var id = Guid.NewGuid().ToString("N");
        var dir = Path.GetDirectoryName(_indexPath)!;
        var imgPath = Path.Combine(dir, $"{id}.jpg");
        File.WriteAllBytes(imgPath, jpegBytes);

        var entry = new CaptureHistoryEntry
        {
            Id = id,
            Timestamp = DateTimeOffset.UtcNow,
            ImagePath = imgPath,
            Summary = string.IsNullOrWhiteSpace(summary) ? $"{mode.Title()} capture" : summary.Trim(),
            ModeTitle = mode.Title(),
            DominantHex = dominantHex,
            OcrText = ocrText
        };

        _entries.Insert(0, entry);
        while (_entries.Count > MaxEntries)
        {
            var removed = _entries[^1];
            _entries.RemoveAt(_entries.Count - 1);
            try { if (File.Exists(removed.ImagePath)) File.Delete(removed.ImagePath); } catch { }
        }
        Save();
        AppSettings.Shared.NotifyHistoryChanged();
        return entry;
    }

    public void Clear()
    {
        foreach (var entry in _entries)
        {
            try { if (File.Exists(entry.ImagePath)) File.Delete(entry.ImagePath); } catch { }
        }
        _entries.Clear();
        Save();
        AppSettings.Shared.NotifyHistoryChanged();
    }
}

public sealed record AppUpdateInfo(string Version, string ReleaseUrl, string? DownloadUrl, string Notes);

public static class AppUpdateChecker
{
    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
        c.DefaultRequestHeaders.UserAgent.ParseAdd($"LoopSearch-Windows/{AppSettings.CurrentAppVersion}");
        c.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        return c;
    }

    public static async Task<AppUpdateInfo?> CheckForUpdatesAsync()
    {
        try
        {
            var url = $"https://api.github.com/repos/{AppSettings.GitHubRepo}/releases/latest";
            using var resp = await Http.GetAsync(url);
            if (!resp.IsSuccessStatusCode) return null;

            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            var root = doc.RootElement;
            var tag = root.TryGetProperty("tag_name", out var tagEl) ? tagEl.GetString() ?? "" : "";
            var htmlUrl = root.TryGetProperty("html_url", out var htmlEl) ? htmlEl.GetString() ?? "" : "";
            var body = root.TryGetProperty("body", out var bodyEl) ? bodyEl.GetString() ?? "" : "";

            string? exeUrl = null;
            if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
            {
                foreach (var asset in assets.EnumerateArray())
                {
                    var name = asset.TryGetProperty("name", out var nEl) ? nEl.GetString() ?? "" : "";
                    if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase))
                    {
                        exeUrl = asset.TryGetProperty("browser_download_url", out var dEl) ? dEl.GetString() : null;
                        break;
                    }
                }
            }

            if (!IsVersionNewer(tag, AppSettings.CurrentAppVersion))
                return null;

            return new AppUpdateInfo(tag.TrimStart('v', 'V'), htmlUrl, exeUrl, body);
        }
        catch
        {
            return null;
        }
    }

    public static bool IsVersionNewer(string remoteTag, string currentVersion)
    {
        static int[] Parse(string v) => v
            .Trim()
            .TrimStart('v', 'V')
            .Split('.', StringSplitOptions.RemoveEmptyEntries)
            .Select(s => int.TryParse(new string(s.TakeWhile(char.IsDigit).ToArray()), out var n) ? n : 0)
            .ToArray();

        var r = Parse(remoteTag);
        var c = Parse(currentVersion);
        var len = Math.Max(r.Length, c.Length);
        for (int i = 0; i < len; i++)
        {
            int rv = i < r.Length ? r[i] : 0;
            int cv = i < c.Length ? c[i] : 0;
            if (rv != cv) return rv > cv;
        }
        return false;
    }
}
