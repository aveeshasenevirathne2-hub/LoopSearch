using System.Text.Json.Serialization;

namespace LoopSearch.Models;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SelectionMode
{
    Box,
    Freehand,
    Tap,
    Text
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum SearchEngine
{
    GoogleLens,
    Google,
    Perplexity,
    Bing,
    AskAI
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum AppTheme
{
    System,
    Dark,
    Light
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum VisualStylePreset
{
    Horizon,
    LiquidGlass
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum GlowColorTheme
{
    Signature,
    Spectrum
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum GlowIntensity
{
    Subtle,
    Luminous,
    Vivid
}

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum MotionFeel
{
    Snappy,
    Fluid,
    Cinematic
}

public static class EnumExtensions
{
    public static string Title(this SelectionMode mode) => mode switch
    {
        SelectionMode.Box => "Box",
        SelectionMode.Freehand => "Freehand",
        SelectionMode.Tap => "Tap",
        SelectionMode.Text => "Text",
        _ => "Box"
    };

    public static string ShortcutDigit(this SelectionMode mode) => mode switch
    {
        SelectionMode.Box => "1",
        SelectionMode.Freehand => "2",
        SelectionMode.Tap => "3",
        SelectionMode.Text => "4",
        _ => "1"
    };

    public static string HintText(this SelectionMode mode) => mode switch
    {
        SelectionMode.Box => "Drag a box around anything",
        SelectionMode.Freehand => "Draw a loop around anything",
        SelectionMode.Tap => "Click any object or word to capture",
        SelectionMode.Text => "Highlight or box text to copy & search",
        _ => "Drag a box around anything"
    };

    public static string Title(this SearchEngine engine) => engine switch
    {
        SearchEngine.GoogleLens => "Google Lens",
        SearchEngine.Google => "Google",
        SearchEngine.Perplexity => "Perplexity",
        SearchEngine.Bing => "Bing",
        SearchEngine.AskAI => "Ask AI",
        _ => "Google Lens"
    };

    public static string? BuildSearchUrl(this SearchEngine engine, string query, bool isVisual = false)
    {
        var trimmed = query.Trim();
        if (string.IsNullOrEmpty(trimmed)) return null;
        var encoded = Uri.EscapeDataString(trimmed);
        return engine switch
        {
            SearchEngine.GoogleLens or SearchEngine.Google => $"https://www.google.com/search?q={encoded}",
            SearchEngine.Perplexity => $"https://www.perplexity.ai/search?q={encoded}",
            SearchEngine.Bing => $"https://www.bing.com/search?q={encoded}",
            SearchEngine.AskAI => $"https://www.google.com/search?udm=50&q={encoded}",
            _ => $"https://www.google.com/search?q={encoded}"
        };
    }

    public static string Title(this AppTheme theme) => theme switch
    {
        AppTheme.System => "Auto",
        AppTheme.Dark => "Dark",
        AppTheme.Light => "Light",
        _ => "Auto"
    };

    public static string Title(this VisualStylePreset preset) => preset switch
    {
        VisualStylePreset.Horizon => "Horizon",
        VisualStylePreset.LiquidGlass => "Liquid Glass",
        _ => "Horizon"
    };

    public static string Title(this GlowColorTheme theme) => theme switch
    {
        GlowColorTheme.Signature => "Loop Aura",
        GlowColorTheme.Spectrum => "Spectrum",
        _ => "Loop Aura"
    };

    public static string Title(this GlowIntensity intensity) => intensity switch
    {
        GlowIntensity.Subtle => "Subtle",
        GlowIntensity.Luminous => "Balanced",
        GlowIntensity.Vivid => "Vivid",
        _ => "Balanced"
    };

    public static double OpacityMultiplier(this GlowIntensity intensity) => intensity switch
    {
        GlowIntensity.Subtle => 0.36,
        GlowIntensity.Luminous => 0.68,
        GlowIntensity.Vivid => 1.05,
        _ => 0.68
    };

    public static string Title(this MotionFeel feel) => feel switch
    {
        MotionFeel.Snappy => "Crisp",
        MotionFeel.Fluid => "Smooth",
        MotionFeel.Cinematic => "Fluid",
        _ => "Smooth"
    };

    public static double DurationScale(this MotionFeel feel) => feel switch
    {
        MotionFeel.Snappy => 0.78,
        MotionFeel.Fluid => 1.00,
        MotionFeel.Cinematic => 1.20,
        _ => 1.00
    };
}

/// <summary>
/// Cross-platform representation of a Windows global hotkey (Win32 VK + MOD_* flags).
/// </summary>
public sealed record CustomHotkey
{
    public const uint ModAlt = 0x0001;
    public const uint ModControl = 0x0002;
    public const uint ModShift = 0x0004;
    public const uint ModWin = 0x0008;

    public uint VirtualKey { get; init; } = 0x20; // VK_SPACE
    public uint Modifiers { get; init; } = ModControl | ModShift;

    public static CustomHotkey Default => new() { VirtualKey = 0x20, Modifiers = ModControl | ModShift };

    public static CustomHotkey[] Presets =>
    [
        new() { VirtualKey = 0x20, Modifiers = ModControl | ModShift }, // Ctrl+Shift+Space
        new() { VirtualKey = 0x20, Modifiers = ModAlt },              // Alt+Space
        new() { VirtualKey = 0x53, Modifiers = ModControl | ModAlt }, // Ctrl+Alt+S
        new() { VirtualKey = 0x53, Modifiers = ModControl | ModShift } // Ctrl+Shift+S
    ];

    public string DisplayString
    {
        get
        {
            var parts = new List<string>();
            if ((Modifiers & ModControl) != 0) parts.Add("Ctrl");
            if ((Modifiers & ModAlt) != 0) parts.Add("Alt");
            if ((Modifiers & ModShift) != 0) parts.Add("Shift");
            if ((Modifiers & ModWin) != 0) parts.Add("Win");
            parts.Add(VirtualKeyName(VirtualKey));
            return string.Join(" + ", parts);
        }
    }

    public string CompactString
    {
        get
        {
            var parts = new List<string>();
            if ((Modifiers & ModControl) != 0) parts.Add("Ctrl");
            if ((Modifiers & ModAlt) != 0) parts.Add("Alt");
            if ((Modifiers & ModShift) != 0) parts.Add("Shift");
            if ((Modifiers & ModWin) != 0) parts.Add("Win");
            parts.Add(VirtualKeyName(VirtualKey));
            return string.Join("+", parts);
        }
    }

    public bool IsValid => VirtualKey != 0 && Modifiers != 0;

    public static string VirtualKeyName(uint vk) => vk switch
    {
        0x20 => "Space",
        0x0D => "Enter",
        0x09 => "Tab",
        0x1B => "Esc",
        0x2E => "Del",
        >= 0x30 and <= 0x39 => ((char)vk).ToString(),
        >= 0x41 and <= 0x5A => ((char)vk).ToString(),
        >= 0x70 and <= 0x7B => $"F{vk - 0x6F}",
        0xC0 => "`",
        0xBD => "-",
        0xBB => "=",
        0xDB => "[",
        0xDD => "]",
        0xDC => "\\",
        0xBA => ";",
        0xDE => "'",
        0xBC => ",",
        0xBE => ".",
        0xBF => "/",
        _ => $"Key 0x{vk:X2}"
    };
}
