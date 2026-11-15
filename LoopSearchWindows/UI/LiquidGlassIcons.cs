using Avalonia.Controls;
using Avalonia.Media;
using PathShape = Avalonia.Controls.Shapes.Path;

namespace LoopSearch.UI;

/// <summary>
/// Crisp monochrome SVG path icons matching Apple SF Symbols across the macOS version (zero system emojis).
/// </summary>
public static class LiquidGlassIcons
{
    public static PathShape Create(string pathData, double size = 14, IBrush? fill = null, IBrush? stroke = null, double strokeThickness = 1.6)
    {
        var shape = new PathShape
        {
            Data = Geometry.Parse(pathData),
            Width = size,
            Height = size,
            Stretch = Stretch.Uniform,
            Fill = fill,
            Stroke = stroke,
            StrokeThickness = strokeThickness,
            StrokeLineCap = PenLineCap.Round,
            StrokeJoin = PenLineJoin.Round,
            IsHitTestVisible = false
        };
        return shape;
    }

    public static PathShape StrokeIcon(string pathData, double size = 13.5, IBrush? color = null, double thickness = 1.75)
        => Create(pathData, size, fill: null, stroke: color ?? ThemePalette.PrimaryBrush, strokeThickness: thickness);

    public static PathShape FillIcon(string pathData, double size = 13.5, IBrush? color = null)
        => Create(pathData, size, fill: color ?? ThemePalette.PrimaryBrush, stroke: null, strokeThickness: 0);

    // Navigation & Window Chrome
    public const string BackChevron = "M15 4 L7 12 L15 20";
    public const string ReloadArrow = "M20 11 A8 8 0 1 0 18.2 16.5 M20 4 V11 H13";
    public const string CloseX = "M6 6 L18 18 M18 6 L6 18";
    public const string SendArrowRight = "M5 12 H19 M13 6 L19 12 L13 18";
    public const string ExternalArrow = "M14 4 H20 V10 M10 14 L20 4 M19 14 V19 A1 1 0 0 1 18 20 H5 A1 1 0 0 1 4 19 V6 A1 1 0 0 1 5 5 H10";
    public const string ExpandArrows = "M15 4 H20 V9 M9 20 H4 V15 M20 4 L14 10 M4 20 L10 14";
    public const string CollapseArrows = "M19 9 H15 V5 M5 15 H9 V19 M20 4 L15 9 M4 20 L9 15";

    // Theme, Pin & Actions
    public const string Moon = "M20.5 14.5 A8.5 8.5 0 1 1 9.5 3.5 A6.8 6.8 0 0 0 20.5 14.5 Z";
    public const string Sun = "M12 7 A5 5 0 1 0 12 17 A5 5 0 1 0 12 7 Z M12 2 V4 M12 20 V22 M4.9 4.9 L6.3 6.3 M17.7 17.7 L19.1 19.1 M2 12 H4 M20 12 H22 M4.9 19.1 L6.3 17.7 M17.7 6.3 L19.1 4.9";
    public const string Pin = "M14 4 L20 10 L17 13 L17 16 L15 18 L11 14 L5 20 L10 13 L6 9 L8 7 L11 7 Z";
    public const string SearchGlass = "M10.5 3.5 A7 7 0 1 0 10.5 17.5 A7 7 0 1 0 10.5 3.5 Z M15.6 15.6 L20.5 20.5";
    public const string BoxSelect = "M4 8 V5 A1 1 0 0 1 5 4 H8 M16 4 H19 A1 1 0 0 1 20 5 V8 M20 16 V19 A1 1 0 0 1 19 20 H16 M8 20 H5 A1 1 0 0 1 4 19 V16";
    public const string FreehandLasso = "M12 4 C17.5 4 21 7.2 21 11.2 C21 15.2 16.8 18 11.5 18 C7.2 18 3.5 15.4 3.5 11.6 C3.5 7.9 7.2 4 12 4 Z M11.5 18 C11.5 20 13 21.5 15 21.5";
    public const string TapTarget = "M12 3 A9 9 0 1 0 12 21 A9 9 0 1 0 12 3 Z M12 8 A4 4 0 1 0 12 16 A4 4 0 1 0 12 8 Z";
    public const string TextScan = "M4 6 H20 M4 12 H16 M4 18 H12";
    public const string SettingsGear = "M12 8.5 A3.5 3.5 0 1 0 12 15.5 A3.5 3.5 0 1 0 12 8.5 Z M19.4 15 L21 13.8 V10.2 L19.4 9 L19.9 7 L17.3 4.4 L15.3 4.9 L14 3.2 H10 L8.7 4.9 L6.7 4.4 L4.1 7 L4.6 9 L3 10.2 V13.8 L4.6 15 L4.1 17 L6.7 19.6 L8.7 19.1 L10 20.8 H14 L15.3 19.1 L17.3 19.6 L19.9 17 Z";
    public const string CopyDoc = "M9 9 H19 A1.5 1.5 0 0 1 20.5 10.5 V19.5 A1.5 1.5 0 0 1 19 21 H10.5 A1.5 1.5 0 0 1 9 19.5 V9 Z M5 15 H4.5 A1.5 1.5 0 0 1 3 13.5 V4.5 A1.5 1.5 0 0 1 4.5 3 H13.5 A1.5 1.5 0 0 1 15 4.5 V5";
    public const string Sparkle = "M12 2 L14.4 9.6 L22 12 L14.4 14.4 L12 22 L9.6 14.4 L2 12 L9.6 9.6 Z";
    public const string LinkChain = "M10 13 A4.5 4.5 0 0 0 16.5 13 L19 10.5 A4.5 4.5 0 0 0 12.6 4.1 L11 5.7 M14 11 A4.5 4.5 0 0 0 7.5 11 L5 13.5 A4.5 4.5 0 0 0 11.4 19.9 L13 18.3";
    public const string Star = "M12 2.5 L14.9 8.6 L21.6 9.5 L16.7 14.2 L17.9 20.9 L12 17.7 L6.1 20.9 L7.3 14.2 L2.4 9.5 L9.1 8.6 Z";
    public const string Keyboard = "M3 7 A2 2 0 0 1 5 5 H19 A2 2 0 0 1 21 7 V17 A2 2 0 0 1 19 19 H5 A2 2 0 0 1 3 17 Z M7 10 H8 M11 10 H12 M15 10 H16 M8 14 H16";
    public const string MonitorCheck = "M3 5 A2 2 0 0 1 5 3 H19 A2 2 0 0 1 21 5 V15 A2 2 0 0 1 19 17 H5 A2 2 0 0 1 3 15 Z M8 21 H16 M12 17 V21 M9 10 L11 12 L15 8";
}
