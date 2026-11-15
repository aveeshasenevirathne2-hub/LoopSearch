using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Avalonia.Threading;
using LoopSearch.Models;
using LoopSearch.Services;
using SelectionMode = LoopSearch.Models.SelectionMode;

namespace LoopSearch.UI;

public sealed class OverlayWindow : Window
{
    private readonly ScreenCaptureData _capture;
    private readonly Bitmap _frozenAvaloniaBitmap;
    private readonly OverlayCanvas _canvas;
    private readonly Border _pillBar;
    private readonly TextBlock _hintTitle;
    private readonly Button[] _modeButtons = new Button[4];
    private readonly Action _openSettingsAction;

    // Safe work-area insets in DIPs (protects against top/bottom/left/right Windows taskbar)
    private double _safeLeft = 16;
    private double _safeTop = 16;
    private double _safeRight = 16;
    private double _safeBottom = 16;

    private SelectionMode _mode;
    private bool _isDragging;
    private Point _dragStart;
    private Point _dragCurrent;
    private readonly List<Point> _freehandPoints = [];
    private Rect? _activeSelectionDip;
    private bool _isScanActive;

    // Results Sheet UI
    private Border? _resultsSheet;
    private Border? _orbOverlay;
    private WebView2Host? _webView;
    private TextBox? _followUpBox;
    private TextBlock? _ocrPreviewLabel;
    private TextBlock? _aiBannerLabel;
    private WrapPanel? _chipsPanel;
    private string? _lensBaseUrl;
    private string? _currentExternalUrl;
    private System.Drawing.Bitmap? _lastCroppedBmp;
    private byte[]? _lastJpegBytes;
    private VisionAnalysisResult? _lastVision;

    // Sheet drag & expand state
    private bool _isSheetExpanded;
    private Rect _dockedSheetFrame;
    private bool _isDraggingSheet;
    private Point _sheetDragOriginPointer;
    private Thickness _sheetDragStartMargin;

    public OverlayWindow(ScreenCaptureData capture, Action openSettingsAction, System.Drawing.Bitmap? preCroppedClipboard = null)
    {
        _capture = capture;
        _openSettingsAction = openSettingsAction;
        _mode = AppSettings.Shared.DefaultMode;

        using (var ms = new MemoryStream(VisionOcrService.EncodePng(capture.Bitmap)))
        {
            _frozenAvaloniaBitmap = new Bitmap(ms);
        }

        Topmost = true;
        ShowInTaskbar = false;
        SystemDecorations = SystemDecorations.None;
        ExtendClientAreaToDecorationsHint = true;
        ExtendClientAreaChromeHints = Avalonia.Platform.ExtendClientAreaChromeHints.NoChrome;
        ExtendClientAreaTitleBarHeightHint = 0;
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Transparent;
        CanResize = false;
        Cursor = new Cursor(StandardCursorType.Cross);
        WindowState = WindowState.Normal;
        Position = new PixelPoint(capture.VirtualX, capture.VirtualY);

        var rootGrid = new Grid();
        _canvas = new OverlayCanvas(this, _frozenAvaloniaBitmap);
        rootGrid.Children.Add(_canvas);

        // Floating Liquid Glass bottom pill toolbar
        var pillRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center
        };

        pillRow.Children.Add(LiquidGlassUI.CreateBrandBadge(30));

        var textStack = new StackPanel { Spacing = 0, Margin = new Thickness(4, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center };
        _hintTitle = new TextBlock
        {
            Text = _mode.HintText(),
            FontSize = 12,
            FontWeight = FontWeight.SemiBold,
            Foreground = Brushes.White
        };
        textStack.Children.Add(_hintTitle);
        textStack.Children.Add(new TextBlock
        {
            Text = "Press 1–4 to switch mode · Esc to cancel",
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.Parse("#A4C6F2"))
        });
        pillRow.Children.Add(textStack);

        var modes = new[] { SelectionMode.Box, SelectionMode.Freehand, SelectionMode.Tap, SelectionMode.Text };
        string[] modeIcons = [LiquidGlassIcons.BoxSelect, LiquidGlassIcons.FreehandLasso, LiquidGlassIcons.TapTarget, LiquidGlassIcons.TextScan];
        for (int i = 0; i < modes.Length; i++)
        {
            var m = modes[i];
            var modeContent = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
            modeContent.Children.Add(LiquidGlassIcons.StrokeIcon(modeIcons[i], 12, Brushes.White, 1.7));
            modeContent.Children.Add(new TextBlock
            {
                Text = $"{m.ShortcutDigit()} {m.Title()}",
                FontSize = 11.5,
                FontWeight = FontWeight.SemiBold,
                Foreground = Brushes.White
            });

            var btn = new Button
            {
                Content = modeContent,
                CornerRadius = new CornerRadius(10),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(10, 6),
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            btn.Click += (_, _) => SwitchMode(m);
            _modeButtons[i] = btn;
            pillRow.Children.Add(btn);
        }

        var settingsBtn = new Button
        {
            Content = LiquidGlassIcons.StrokeIcon(LiquidGlassIcons.SettingsGear, 13, Brushes.White, 1.7),
            Background = new SolidColorBrush(Color.FromArgb(38, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(45, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Width = 30,
            Height = 28,
            Padding = new Thickness(0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        ToolTip.SetTip(settingsBtn, "Studio Settings");
        settingsBtn.Click += (_, _) => CloseWithAnimation(() => _openSettingsAction());
        pillRow.Children.Add(settingsBtn);

        var closeBtn = new Button
        {
            Content = LiquidGlassIcons.StrokeIcon(LiquidGlassIcons.CloseX, 12, Brushes.White, 1.9),
            Background = new SolidColorBrush(Color.FromArgb(38, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(45, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(10),
            Width = 30,
            Height = 28,
            Padding = new Thickness(0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        closeBtn.Click += (_, _) => CloseWithAnimation();
        pillRow.Children.Add(closeBtn);

        var pillRim = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.FromArgb(120, 255, 255, 255), 0),
                new GradientStop(Color.FromArgb(150, 76, 214, 255), 1)
            }
        };

        _pillBar = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(228, 8, 13, 27)),
            BorderBrush = pillRim,
            BorderThickness = new Thickness(1.1),
            CornerRadius = new CornerRadius(20),
            Padding = new Thickness(10, 7),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 0, 28),
            Cursor = new Cursor(StandardCursorType.Arrow),
            Child = pillRow
        };
        rootGrid.Children.Add(_pillBar);

        Content = rootGrid;
        UpdateModeButtons();

        Opened += (_, _) =>
        {
            double scale = RenderScaling;
            Width = capture.Width / scale;
            Height = capture.Height / scale;

            // Compute taskbar-safe insets in DIPs
            _safeLeft = Math.Max(14, (capture.WorkX - capture.VirtualX) / scale + 14);
            _safeTop = Math.Max(14, (capture.WorkY - capture.VirtualY) / scale + 14);
            _safeRight = Math.Max(14, ((capture.VirtualX + capture.Width) - (capture.WorkX + capture.WorkWidth)) / scale + 14);
            _safeBottom = Math.Max(14, ((capture.VirtualY + capture.Height) - (capture.WorkY + capture.WorkHeight)) / scale + 14);
            _pillBar.Margin = new Thickness(0, 0, 0, _safeBottom + 10);

            // Force exact Win32 physical bounds on top of ALL windows including taskbar
            var handle = TryGetPlatformHandle()?.Handle ?? IntPtr.Zero;
            NativeWin32.ForceTopmostBounds(handle, capture.VirtualX, capture.VirtualY, capture.Width, capture.Height);

            Activate();
            Focus();

            // Play macOS-exact entrance animations: focus settle, upward wave sweep, spring pill!
            _canvas.PlayEntrance();
            AppleMotion.KineticHorizonSpring(_pillBar, delaySeconds: 0.04, fromY: 44, fromScale: 0.88, baseDurationMs: 460);

            if (preCroppedClipboard != null)
            {
                var centerRect = new Rect(Width * 0.28, Height * 0.24, Math.Min(360, Width * 0.35), Math.Min(260, Height * 0.35));
                _activeSelectionDip = centerRect;
                _canvas.TriggerSelectionCaptureEffects(centerRect, null);
                _ = ProcessCapturedBitmapAsync(preCroppedClipboard, centerRect);
            }
        };

        Closed += (_, _) =>
        {
            _canvas.Stop();
            _lastCroppedBmp?.Dispose();
            _capture.Bitmap.Dispose();
            _frozenAvaloniaBitmap.Dispose();
        };

        KeyDown += OnOverlayKeyDown;
        _canvas.PointerPressed += OnCanvasPointerPressed;
        _canvas.PointerMoved += OnCanvasPointerMoved;
        _canvas.PointerReleased += OnCanvasPointerReleased;
    }

    private void CloseWithAnimation(Action? afterClose = null)
    {
        _canvas.PlayExit();
        AppleMotion.KineticHorizonSpring(_pillBar, delaySeconds: 0, fromY: 0, fromScale: 1.0, baseDurationMs: 140);
        var t = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(160) };
        t.Tick += (_, _) =>
        {
            t.Stop();
            Close();
            afterClose?.Invoke();
        };
        t.Start();
    }

    private void SwitchMode(SelectionMode mode)
    {
        _mode = mode;
        _hintTitle.Text = mode.HintText();
        UpdateModeButtons();
        _canvas.InvalidateVisual();
    }

    private void UpdateModeButtons()
    {
        var modes = new[] { SelectionMode.Box, SelectionMode.Freehand, SelectionMode.Tap, SelectionMode.Text };
        for (int i = 0; i < modes.Length; i++)
        {
            bool active = modes[i] == _mode;
            _modeButtons[i].Background = active
                ? ThemePalette.AccentButtonBrush
                : new SolidColorBrush(Color.FromArgb(26, 255, 255, 255));
            _modeButtons[i].BorderBrush = active
                ? new SolidColorBrush(Color.FromArgb(165, 130, 224, 255))
                : Brushes.Transparent;
        }
    }

    private void OnOverlayKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            CloseWithAnimation();
            return;
        }
        if (_followUpBox != null && _followUpBox.IsFocused)
            return;

        switch (e.Key)
        {
            case Key.D1 or Key.NumPad1: SwitchMode(SelectionMode.Box); break;
            case Key.D2 or Key.NumPad2: SwitchMode(SelectionMode.Freehand); break;
            case Key.D3 or Key.NumPad3: SwitchMode(SelectionMode.Tap); break;
            case Key.D4 or Key.NumPad4: SwitchMode(SelectionMode.Text); break;
        }
    }

    private void OnCanvasPointerPressed(object? sender, PointerPressedEventArgs e)
    {
        if (!e.GetCurrentPoint(_canvas).Properties.IsLeftButtonPressed) return;
        var pt = e.GetPosition(_canvas);
        _isDragging = true;
        _isScanActive = false;
        _dragStart = pt;
        _dragCurrent = pt;
        _freehandPoints.Clear();
        _freehandPoints.Add(pt);
        _canvas.InvalidateVisual();
    }

    private void OnCanvasPointerMoved(object? sender, PointerEventArgs e)
    {
        if (!_isDragging) return;
        _dragCurrent = e.GetPosition(_canvas);
        if (_mode == SelectionMode.Freehand)
        {
            if (_freehandPoints.Count == 0 || Distance(_freehandPoints[^1], _dragCurrent) > 3)
                _freehandPoints.Add(_dragCurrent);
        }
        _canvas.InvalidateVisual();
    }

    private void OnCanvasPointerReleased(object? sender, PointerReleasedEventArgs e)
    {
        if (!_isDragging) return;
        _isDragging = false;
        _dragCurrent = e.GetPosition(_canvas);

        Rect selectionDip;
        IReadOnlyList<Point>? freehandSnap = null;
        if (_mode == SelectionMode.Tap)
        {
            double w = 220, h = 150;
            selectionDip = ClampRect(new Rect(_dragCurrent.X - w / 2, _dragCurrent.Y - h / 2, w, h));
        }
        else if (_mode == SelectionMode.Freehand && _freehandPoints.Count > 4)
        {
            freehandSnap = [.. _freehandPoints];
            double minX = freehandSnap.Min(p => p.X);
            double minY = freehandSnap.Min(p => p.Y);
            double maxX = freehandSnap.Max(p => p.X);
            double maxY = freehandSnap.Max(p => p.Y);
            selectionDip = ClampRect(new Rect(minX - 6, minY - 6, Math.Max(28, maxX - minX + 12), Math.Max(28, maxY - minY + 12)));
        }
        else
        {
            double x = Math.Min(_dragStart.X, _dragCurrent.X);
            double y = Math.Min(_dragStart.Y, _dragCurrent.Y);
            double w = Math.Abs(_dragCurrent.X - _dragStart.X);
            double h = Math.Abs(_dragCurrent.Y - _dragStart.Y);
            selectionDip = (w < 14 || h < 14)
                ? ClampRect(new Rect(_dragCurrent.X - 110, _dragCurrent.Y - 75, 220, 150))
                : ClampRect(new Rect(x, y, w, h));
        }

        _activeSelectionDip = selectionDip;
        _isScanActive = true;
        _canvas.TriggerSelectionCaptureEffects(selectionDip, freehandSnap);
        _ = CaptureAndSearchRectAsync(selectionDip);
    }

    private Rect ClampRect(Rect r)
    {
        double x = Math.Clamp(r.X, 0, Math.Max(0, Width - 16));
        double y = Math.Clamp(r.Y, 0, Math.Max(0, Height - 16));
        double w = Math.Clamp(r.Width, 16, Math.Max(16, Width - x));
        double h = Math.Clamp(r.Height, 16, Math.Max(16, Height - y));
        return new Rect(x, y, w, h);
    }

    private async Task CaptureAndSearchRectAsync(Rect selectionDip)
    {
        double scale = RenderScaling;
        int px = Math.Clamp((int)Math.Round(selectionDip.X * scale), 0, _capture.Bitmap.Width - 1);
        int py = Math.Clamp((int)Math.Round(selectionDip.Y * scale), 0, _capture.Bitmap.Height - 1);
        int pw = Math.Clamp((int)Math.Round(selectionDip.Width * scale), 8, _capture.Bitmap.Width - px);
        int ph = Math.Clamp((int)Math.Round(selectionDip.Height * scale), 8, _capture.Bitmap.Height - py);

        var cropRect = new System.Drawing.Rectangle(px, py, pw, ph);
        var cropped = _capture.Bitmap.Clone(cropRect, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        await ProcessCapturedBitmapAsync(cropped, selectionDip);
    }

    private async Task ProcessCapturedBitmapAsync(System.Drawing.Bitmap cropped, Rect selectionDip)
    {
        _lastCroppedBmp?.Dispose();
        _lastCroppedBmp = cropped;
        _lastJpegBytes = VisionOcrService.EncodeJpeg(cropped);
        NativeWin32.PlaySubtleSound(true);

        EnsureResultsSheet(selectionDip, cropped);
        SetLoading(true);

        var visionTask = VisionOcrService.AnalyzeBitmapAsync(cropped);
        var lensTask = AppSettings.Shared.SearchEngine == SearchEngine.GoogleLens
            ? GoogleLensService.UploadImageAsync(_lastJpegBytes)
            : Task.FromResult<LensUploadResult?>(null);

        _lastVision = await visionTask;
        UpdateVisionUi(_lastVision);

        var summary = !string.IsNullOrWhiteSpace(_lastVision.CleanPreview)
            ? _lastVision.CleanPreview
            : $"{_mode.Title()} selection ({cropped.Width}×{cropped.Height})";
        CaptureHistoryStore.Shared.Add(_lastJpegBytes, summary, _mode, _lastVision.DominantHex, _lastVision.OcrText);

        var engine = AppSettings.Shared.SearchEngine;
        if (engine == SearchEngine.GoogleLens)
        {
            var lensRes = await lensTask;
            if (lensRes != null)
            {
                _lensBaseUrl = lensRes.ResultsUrl;
                _currentExternalUrl = lensRes.ResultsUrl;
                _webView?.Navigate(lensRes.ResultsUrl, lensRes.Cookies, useMobileUa: true);
            }
            else if (!string.IsNullOrWhiteSpace(_lastVision.OcrText))
            {
                var fallback = SearchEngine.Google.BuildSearchUrl(_lastVision.OcrText);
                if (fallback != null)
                {
                    _currentExternalUrl = fallback;
                    _webView?.Navigate(fallback);
                }
            }
        }
        else
        {
            var query = !string.IsNullOrWhiteSpace(_lastVision.OcrText) ? _lastVision.OcrText : "visual search";
            var url = engine.BuildSearchUrl(query);
            if (url != null)
            {
                _currentExternalUrl = url;
                _webView?.Navigate(url);
            }
        }
    }

    private Rect ComputeSheetFrame(Rect sel)
    {
        double usableW = Math.Max(420, Width - _safeLeft - _safeRight);
        double usableH = Math.Max(420, Height - _safeTop - _safeBottom - 78);
        double sheetW = Math.Min(460, usableW * 0.45);
        sheetW = Math.Max(380, sheetW);
        double sheetH = Math.Min(700, usableH * 0.92);

        double rightSpace = (Width - _safeRight) - (sel.Right + 20);
        double leftSpace = (sel.Left - 20) - _safeLeft;
        double x = rightSpace >= sheetW
            ? sel.Right + 20
            : (leftSpace >= sheetW ? sel.Left - sheetW - 20 : Width - _safeRight - sheetW);
        x = Math.Clamp(x, _safeLeft, Math.Max(_safeLeft, Width - _safeRight - sheetW));
        double y = Math.Clamp(sel.Center.Y - sheetH / 2, _safeTop, Math.Max(_safeTop, Height - _safeBottom - 74 - sheetH));
        return new Rect(x, y, sheetW, sheetH);
    }

    private void EnsureResultsSheet(Rect selectionDip, System.Drawing.Bitmap previewBmp)
    {
        if (Content is not Grid rootGrid) return;
        if (_resultsSheet != null)
        {
            rootGrid.Children.Remove(_resultsSheet);
        }

        _isSheetExpanded = false;
        _dockedSheetFrame = ComputeSheetFrame(selectionDip);

        using var ms = new MemoryStream(VisionOcrService.EncodePng(previewBmp));
        var avPreview = new Bitmap(ms);

        // Grab handle + draggable header bar (zero ugly emojis — crisp monochrome vectors!)
        var header = new Grid
        {
            ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto,Auto,Auto,Auto,Auto"),
            Background = Brushes.Transparent,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        header.PointerPressed += (_, e) =>
        {
            if (e.GetCurrentPoint(this).Properties.IsLeftButtonPressed && _resultsSheet != null)
            {
                _isDraggingSheet = true;
                _sheetDragOriginPointer = e.GetPosition(this);
                _sheetDragStartMargin = _resultsSheet.Margin;
            }
        };
        header.PointerMoved += (_, e) =>
        {
            if (!_isDraggingSheet || _resultsSheet == null) return;
            var cur = e.GetPosition(this);
            var dx = cur.X - _sheetDragOriginPointer.X;
            var dy = cur.Y - _sheetDragOriginPointer.Y;
            double nx = Math.Clamp(_sheetDragStartMargin.Left + dx, _safeLeft, Math.Max(_safeLeft, Width - _safeRight - _resultsSheet.Width));
            double ny = Math.Clamp(_sheetDragStartMargin.Top + dy, _safeTop, Math.Max(_safeTop, Height - _safeBottom - _resultsSheet.Height));
            _resultsSheet.Margin = new Thickness(nx, ny, 0, 0);
        };
        header.PointerReleased += (_, _) => _isDraggingSheet = false;

        var backBtn = SmallIconBtn(LiquidGlassIcons.BackChevron, "Back", () => _webView?.GoBack());
        header.Children.Add(backBtn);

        var reloadBtn = SmallIconBtn(LiquidGlassIcons.ReloadArrow, "Reload", () => _webView?.Reload());
        Grid.SetColumn(reloadBtn, 1);
        reloadBtn.Margin = new Thickness(5, 0, 10, 0);
        header.Children.Add(reloadBtn);

        var titleText = new TextBlock
        {
            Text = AppSettings.Shared.SearchEngine.Title(),
            FontSize = 13,
            FontWeight = FontWeight.SemiBold,
            Foreground = ThemePalette.PrimaryBrush,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(titleText, 2);
        header.Children.Add(titleText);

        var themeToggle = SmallIconBtn(ThemePalette.IsWebDark ? LiquidGlassIcons.Moon : LiquidGlassIcons.Sun, "Toggle Dark/Light Results", async () =>
        {
            AppSettings.Shared.WebResultsTheme = ThemePalette.IsWebDark ? AppTheme.Light : AppTheme.Dark;
            if (_webView != null) await _webView.ApplyColorSchemeAsync();
        });
        Grid.SetColumn(themeToggle, 3);
        header.Children.Add(themeToggle);

        var pinBtn = SmallIconBtn(LiquidGlassIcons.Pin, "Pin Floating Capture", () =>
        {
            if (_lastCroppedBmp != null)
            {
                var clone = (System.Drawing.Bitmap)_lastCroppedBmp.Clone();
                new PinnedCaptureWindow(clone, _lastVision?.OcrText).Show();
            }
        });
        Grid.SetColumn(pinBtn, 4);
        pinBtn.Margin = new Thickness(5, 0, 0, 0);
        header.Children.Add(pinBtn);

        var expandBtn = SmallIconBtn(LiquidGlassIcons.ExpandArrows, "Expand / Restore Sheet", ToggleExpandSheet);
        Grid.SetColumn(expandBtn, 5);
        expandBtn.Margin = new Thickness(5, 0, 0, 0);
        header.Children.Add(expandBtn);

        var extBtn = SmallIconBtn(LiquidGlassIcons.ExternalArrow, "Open in Browser", () =>
        {
            if (!string.IsNullOrEmpty(_currentExternalUrl))
                Process.Start(new ProcessStartInfo(_currentExternalUrl) { UseShellExecute = true });
        });
        Grid.SetColumn(extBtn, 6);
        extBtn.Margin = new Thickness(5, 0, 0, 0);
        header.Children.Add(extBtn);

        var closeBtn = SmallIconBtn(LiquidGlassIcons.CloseX, "Close", () => CloseWithAnimation());
        Grid.SetColumn(closeBtn, 7);
        closeBtn.Margin = new Thickness(5, 0, 0, 0);
        header.Children.Add(closeBtn);

        // Hero Preview + Search Follow-up Bar
        var heroGrid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*"), Margin = new Thickness(0, 10, 0, 6) };
        heroGrid.Children.Add(new Border
        {
            Width = 56,
            Height = 44,
            CornerRadius = new CornerRadius(10),
            ClipToBounds = true,
            BorderBrush = new SolidColorBrush(Color.FromArgb(115, 92, 224, 255)),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 10, 0),
            Child = new Image { Source = avPreview, Stretch = Stretch.UniformToFill }
        });

        var searchRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        _followUpBox = new TextBox
        {
            Watermark = "Add to your search or ask AI...",
            FontSize = 12.5,
            CornerRadius = new CornerRadius(11),
            Padding = new Thickness(11, 7),
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(205, 16, 25, 46) : Color.FromArgb(228, 236, 243, 253)),
            Foreground = ThemePalette.PrimaryBrush,
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder)
        };
        _followUpBox.KeyDown += (_, e) =>
        {
            if (e.Key == Key.Enter) _ = SubmitFollowUpAsync();
        };
        searchRow.Children.Add(_followUpBox);

        var sendBtn = new Button
        {
            Content = LiquidGlassIcons.StrokeIcon(LiquidGlassIcons.SendArrowRight, 13.5, Brushes.White, 2.0),
            Background = ThemePalette.AccentButtonBrush,
            BorderBrush = new SolidColorBrush(Color.FromArgb(140, 135, 224, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(11),
            Width = 34,
            Height = 34,
            Padding = new Thickness(0),
            Margin = new Thickness(6, 0, 0, 0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        sendBtn.Click += (_, _) => _ = SubmitFollowUpAsync();
        Grid.SetColumn(sendBtn, 1);
        searchRow.Children.Add(sendBtn);

        Grid.SetColumn(searchRow, 1);
        heroGrid.Children.Add(searchRow);

        _ocrPreviewLabel = new TextBlock
        {
            Text = "Analyzing selection…",
            FontSize = 11.5,
            Foreground = ThemePalette.MutedBrush,
            TextTrimming = TextTrimming.CharacterEllipsis,
            MaxLines = 2,
            Margin = new Thickness(0, 0, 0, 6)
        };

        _chipsPanel = new WrapPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 6) };

        _aiBannerLabel = new TextBlock
        {
            IsVisible = false,
            TextWrapping = TextWrapping.Wrap,
            FontSize = 12,
            Foreground = ThemePalette.PrimaryBrush,
            Margin = new Thickness(0, 0, 0, 6)
        };

        // WebView2 + HorizonOrb luminous loading overlay!
        _webView = new WebView2Host();
        _webView.LoadingChanged += loading => Dispatcher.UIThread.Post(() => SetLoading(loading));

        var orbStack = new StackPanel
        {
            Spacing = 6,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        orbStack.Children.Add(new HorizonOrbControl { HorizontalAlignment = HorizontalAlignment.Center });
        orbStack.Children.Add(new TextBlock
        {
            Text = "Searching with Horizon Vision…",
            FontSize = 12,
            FontWeight = FontWeight.Medium,
            Foreground = ThemePalette.SecondaryBrush,
            HorizontalAlignment = HorizontalAlignment.Center
        });
        _orbOverlay = new Border
        {
            Background = new SolidColorBrush(ThemePalette.IsWebDark ? Color.FromArgb(235, 9, 14, 26) : Color.FromArgb(235, 245, 248, 253)),
            IsHitTestVisible = false,
            Child = orbStack
        };

        var webGrid = new Grid();
        webGrid.Children.Add(_webView);
        webGrid.Children.Add(_orbOverlay);

        var webOuterCard = new Border
        {
            CornerRadius = new CornerRadius(14),
            ClipToBounds = true,
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            Child = webGrid
        };

        var sheetDock = new DockPanel();
        var topSection = new StackPanel();
        topSection.Children.Add(header);
        topSection.Children.Add(heroGrid);
        topSection.Children.Add(_ocrPreviewLabel);
        topSection.Children.Add(_chipsPanel);
        topSection.Children.Add(_aiBannerLabel);

        DockPanel.SetDock(topSection, Dock.Top);
        sheetDock.Children.Add(topSection);
        sheetDock.Children.Add(webOuterCard);

        var sheetRim = new LinearGradientBrush
        {
            StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
            EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
            GradientStops =
            {
                new GradientStop(Color.FromArgb(110, 255, 255, 255), 0),
                new GradientStop(Color.FromArgb(50, 120, 175, 255), 0.35),
                new GradientStop(Color.FromArgb(185, 92, 224, 255), 1)
            }
        };

        _resultsSheet = new Border
        {
            Width = _dockedSheetFrame.Width,
            Height = _dockedSheetFrame.Height,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(_dockedSheetFrame.X, _dockedSheetFrame.Y, 0, 0),
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(242, 9, 14, 28) : Color.FromArgb(246, 248, 251, 255)),
            BorderBrush = sheetRim,
            BorderThickness = new Thickness(1.2),
            CornerRadius = new CornerRadius(20),
            Padding = new Thickness(14),
            Cursor = new Cursor(StandardCursorType.Arrow),
            Child = sheetDock
        };

        rootGrid.Children.Add(_resultsSheet);

        // Cognitive-mapped spatial spring entrance + staggered inner cascade!
        double dx = Math.Clamp((selectionDip.Center.X - _dockedSheetFrame.Center.X) * 0.22, -60, 60);
        AppleMotion.KineticHorizonSpring(_resultsSheet, delaySeconds: 0.02, fromY: 22, fromScale: 0.90, fromTiltDeg: dx * 0.02, baseDurationMs: 460);
        AppleMotion.StaggeredCardsReveal([header, heroGrid, _chipsPanel, webOuterCard], baseDelay: 0.04, stepDelay: 0.038);
    }

    private void ToggleExpandSheet()
    {
        if (_resultsSheet == null) return;
        _isSheetExpanded = !_isSheetExpanded;
        if (_isSheetExpanded)
        {
            double targetW = Math.Min(Width - _safeLeft - _safeRight, Math.Max(_dockedSheetFrame.Width + 180, 700));
            double targetH = Math.Min(Height - _safeTop - _safeBottom - 76, Math.Max(_dockedSheetFrame.Height + 140, 740));
            double nx = Math.Clamp(_dockedSheetFrame.Center.X - targetW / 2, _safeLeft, Width - _safeRight - targetW);
            double ny = Math.Clamp(_dockedSheetFrame.Center.Y - targetH / 2, _safeTop, Height - _safeBottom - 72 - targetH);
            _resultsSheet.Width = targetW;
            _resultsSheet.Height = targetH;
            _resultsSheet.Margin = new Thickness(nx, ny, 0, 0);
        }
        else
        {
            _resultsSheet.Width = _dockedSheetFrame.Width;
            _resultsSheet.Height = _dockedSheetFrame.Height;
            _resultsSheet.Margin = new Thickness(_dockedSheetFrame.X, _dockedSheetFrame.Y, 0, 0);
        }
        AppleMotion.KineticHorizonSpring(_resultsSheet, delaySeconds: 0, fromY: 0, fromScale: 0.97, baseDurationMs: 320);
    }

    private void SetLoading(bool loading)
    {
        if (_orbOverlay != null) _orbOverlay.IsVisible = loading;
        if (!loading && _isScanActive)
        {
            _isScanActive = false;
            _canvas.StopScanSweep();
        }
    }

    private void UpdateVisionUi(VisionAnalysisResult v)
    {
        if (_ocrPreviewLabel != null)
        {
            _ocrPreviewLabel.Text = !string.IsNullOrWhiteSpace(v.CleanPreview)
                ? v.CleanPreview
                : "Visual selection ready";
        }
        if (_chipsPanel == null) return;
        _chipsPanel.Children.Clear();

        _chipsPanel.Children.Add(MakeChip("Search", LiquidGlassIcons.SearchGlass, () =>
        {
            var q = !string.IsNullOrWhiteSpace(v.OcrText) ? v.OcrText : "search";
            var u = SearchEngine.Google.BuildSearchUrl(q);
            if (u != null) { _currentExternalUrl = u; _webView?.Navigate(u); }
        }));

        if (!string.IsNullOrWhiteSpace(v.OcrText))
        {
            _chipsPanel.Children.Add(MakeChip("Copy Text", LiquidGlassIcons.CopyDoc, async () =>
            {
                if (Clipboard != null) await Clipboard.SetTextAsync(v.OcrText);
                ToastWindow.ShowToast("Copied text to clipboard");
            }));
        }
        else
        {
            _chipsPanel.Children.Add(MakeChip("Copy Image", LiquidGlassIcons.CopyDoc, () =>
            {
                if (_lastCroppedBmp != null) NativeWin32.CopyBitmapToClipboard(_lastCroppedBmp);
                ToastWindow.ShowToast("Copied image to clipboard");
            }));
        }

        _chipsPanel.Children.Add(MakeChip("Explain", LiquidGlassIcons.Sparkle, () => _ = ExplainWithAiAsync(null)));

        if (!string.IsNullOrWhiteSpace(v.MathAnswer))
        {
            _chipsPanel.Children.Add(MakeChip($"= {v.MathAnswer}", null, async () =>
            {
                if (Clipboard != null) await Clipboard.SetTextAsync(v.MathAnswer);
                ToastWindow.ShowToast($"Copied {v.MathAnswer}");
            }));
        }

        if (!string.IsNullOrWhiteSpace(v.DetectedUrl))
        {
            _chipsPanel.Children.Add(MakeChip("Open Link", LiquidGlassIcons.LinkChain, () =>
            {
                Process.Start(new ProcessStartInfo(v.DetectedUrl) { UseShellExecute = true });
            }));
        }

        if (!string.IsNullOrWhiteSpace(v.DominantHex))
        {
            _chipsPanel.Children.Add(MakeChip(v.DominantHex, null, async () =>
            {
                if (Clipboard != null) await Clipboard.SetTextAsync(v.DominantHex);
                ToastWindow.ShowToast($"Copied color {v.DominantHex}");
            }, colorHex: v.DominantHex));
        }
    }

    private async Task SubmitFollowUpAsync()
    {
        var query = _followUpBox?.Text?.Trim();
        if (string.IsNullOrEmpty(query)) return;

        if (!string.IsNullOrEmpty(_lensBaseUrl))
        {
            var multi = GoogleLensService.BuildMultisearchUrl(_lensBaseUrl, query);
            if (multi != null)
            {
                _currentExternalUrl = multi;
                _webView?.Navigate(multi, useMobileUa: true);
                return;
            }
        }

        var askUrl = SearchEngine.AskAI.BuildSearchUrl(query);
        if (askUrl != null)
        {
            _currentExternalUrl = askUrl;
            _webView?.Navigate(askUrl);
        }
        await ExplainWithAiAsync(query);
    }

    private async Task ExplainWithAiAsync(string? userQuery)
    {
        var apiKey = AppSettings.Shared.GeminiApiKey;
        if (string.IsNullOrWhiteSpace(apiKey))
        {
            var q = string.IsNullOrWhiteSpace(userQuery)
                ? (!string.IsNullOrWhiteSpace(_lastVision?.OcrText) ? $"Explain this: {_lastVision.CleanPreview}" : "Explain this image")
                : userQuery;
            var url = SearchEngine.AskAI.BuildSearchUrl(q);
            if (url != null) { _currentExternalUrl = url; _webView?.Navigate(url); }
            return;
        }

        if (_lastJpegBytes == null || _aiBannerLabel == null) return;
        _aiBannerLabel.Text = "Thinking with Gemini Vision…";
        _aiBannerLabel.IsVisible = true;
        var answer = await TextInsightHelper.AskGeminiVisionAsync(_lastJpegBytes, userQuery, _lastVision?.OcrText ?? "", apiKey);
        _aiBannerLabel.Text = !string.IsNullOrWhiteSpace(answer) ? answer : "Could not get AI summary.";
    }

    private static Button SmallIconBtn(string pathData, string tooltip, Action onClick)
    {
        var b = new Button
        {
            Content = LiquidGlassIcons.StrokeIcon(pathData, 12.5, ThemePalette.PrimaryBrush, 1.75),
            Width = 28,
            Height = 28,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(9),
            Background = new SolidColorBrush(ThemePalette.CardSubtleFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalContentAlignment = VerticalAlignment.Center,
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        ToolTip.SetTip(b, tooltip);
        b.Click += (_, _) => onClick();
        return b;
    }

    private static Button MakeChip(string text, string? iconPath, Action onClick, string? colorHex = null)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5, VerticalAlignment = VerticalAlignment.Center };
        if (!string.IsNullOrEmpty(colorHex) && Color.TryParse(colorHex, out var swatch))
        {
            row.Children.Add(new Border
            {
                Width = 10,
                Height = 10,
                CornerRadius = new CornerRadius(5),
                Background = new SolidColorBrush(swatch),
                BorderBrush = Brushes.White,
                BorderThickness = new Thickness(0.9)
            });
        }
        else if (!string.IsNullOrEmpty(iconPath))
        {
            row.Children.Add(LiquidGlassIcons.StrokeIcon(iconPath, 11.5, ThemePalette.AccentCyanBrush, 1.75));
        }
        row.Children.Add(new TextBlock { Text = text, FontSize = 11, FontWeight = FontWeight.Medium, Foreground = ThemePalette.PrimaryBrush });

        var b = new Button
        {
            Content = row,
            Background = new SolidColorBrush(ThemePalette.CardSubtleFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(9, 5),
            Margin = new Thickness(0, 0, 6, 4),
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        b.Click += (_, _) => onClick();
        return b;
    }

    private static double Distance(Point a, Point b) => Math.Sqrt((a.X - b.X) * (a.X - b.X) + (a.Y - b.Y) * (a.Y - b.Y));

    private sealed class OverlayCanvas : Control
    {
        private readonly OverlayWindow _owner;
        private readonly Bitmap _frozenBmp;
        private readonly DispatcherTimer _animTimer;
        private readonly (double X, double Y, double R, double Spd, double Ph)[] _ambientStars;
        private readonly List<(double X, double Y, double Vx, double Vy, double Life, double Size)> _burstParticles = [];
        private readonly Random _rng = new(1337);

        private double _phase;
        private DateTime _entryStart = DateTime.UtcNow;
        private DateTime _captureStart = DateTime.MinValue;
        private bool _scanBeamActive;
        private double _scanProgress;
        private double _exitProgress;
        private bool _isExiting;
        private IReadOnlyList<Point>? _capturedFreehand;

        public OverlayCanvas(OverlayWindow owner, Bitmap frozenBmp)
        {
            _owner = owner;
            _frozenBmp = frozenBmp;
            _ambientStars = Enumerable.Range(0, 34)
                .Select(_ => (_rng.NextDouble(), _rng.NextDouble(), 1.1 + _rng.NextDouble() * 1.5, 1.0 + _rng.NextDouble() * 1.8, _rng.NextDouble() * Math.PI * 2))
                .ToArray();

            _animTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
            _animTimer.Tick += (_, _) =>
            {
                _phase += 0.045;
                if (_scanBeamActive) _scanProgress = (_scanProgress + 0.015) % 1.0;
                if (_isExiting) _exitProgress = Math.Min(1.0, _exitProgress + 0.12);
                UpdateParticles();
                InvalidateVisual();
            };
            _animTimer.Start();
        }

        public void PlayEntrance()
        {
            _entryStart = DateTime.UtcNow;
            _isExiting = false;
            _exitProgress = 0;
        }

        public void PlayExit()
        {
            _isExiting = true;
            _exitProgress = 0;
        }

        public void StopScanSweep() => _scanBeamActive = false;

        public void TriggerSelectionCaptureEffects(Rect rect, IReadOnlyList<Point>? freehand)
        {
            _captureStart = DateTime.UtcNow;
            _capturedFreehand = freehand;
            _scanBeamActive = true;
            _scanProgress = 0;

            // Spawn 18 sparkle burst particles around the perimeter!
            _burstParticles.Clear();
            for (int i = 0; i < 18; i++)
            {
                double perim = i / 18.0;
                Point pt = PointOnRectPerimeter(rect, perim);
                double dx = pt.X - rect.Center.X;
                double dy = pt.Y - rect.Center.Y;
                double len = Math.Max(1, Math.Sqrt(dx * dx + dy * dy));
                double speed = 0.8 + _rng.NextDouble() * 1.8;
                _burstParticles.Add((pt.X, pt.Y, (dx / len) * speed, (dy / len) * speed, 1.0, 2.2 + _rng.NextDouble() * 2.6));
            }
        }

        private void UpdateParticles()
        {
            for (int i = _burstParticles.Count - 1; i >= 0; i--)
            {
                var p = _burstParticles[i];
                double life = p.Life - 0.025;
                if (life <= 0)
                    _burstParticles.RemoveAt(i);
                else
                    _burstParticles[i] = (p.X + p.Vx, p.Y + p.Vy, p.Vx * 0.96, p.Vy * 0.96, life, p.Size);
            }
        }

        public void Stop() => _animTimer.Stop();

        public override void Render(DrawingContext context)
        {
            var bounds = Bounds;
            if (bounds.Width <= 0 || bounds.Height <= 0) return;

            double durScale = AppSettings.Shared.MotionFeel.DurationScale();
            double entryElapsed = (DateTime.UtcNow - _entryStart).TotalSeconds;
            double focusT = Math.Clamp(entryElapsed / (0.44 * durScale), 0, 1);
            double easeFocus = AppleMotion.EaseOutCubic(focusT);
            double cornerR = 18 * easeFocus * (1.0 - _exitProgress);

            // 1. Frozen screenshot with subtle desktop focus-settle scale
            double settleScale = (1.0 + 0.012 * (1.0 - easeFocus)) * (1.0 + 0.008 * _exitProgress);
            using (context.PushTransform(
                Matrix.CreateTranslation(-bounds.Width / 2, -bounds.Height / 2) *
                Matrix.CreateScale(settleScale, settleScale) *
                Matrix.CreateTranslation(bounds.Width / 2, bounds.Height / 2)))
            {
                context.DrawImage(_frozenBmp, new Rect(0, 0, _frozenBmp.PixelSize.Width, _frozenBmp.PixelSize.Height), bounds);
            }

            // 2. Smooth fade-in dim scrim
            byte dimAlpha = (byte)(64 * easeFocus * (1.0 - _exitProgress));
            context.FillRectangle(new SolidColorBrush(Color.FromArgb(dimAlpha, 4, 8, 20)), bounds);

            // 3. Upward Horizon Entry Wave Sweep (first 0.68s)
            double waveDur = 0.68 * durScale;
            if (entryElapsed < waveDur)
            {
                double wt = AppleMotion.EaseOutCubic(entryElapsed / waveDur);
                double bandH = bounds.Height * 0.28;
                double waveY = bounds.Height * (1.0 - wt) - bandH * 0.3;
                var waveBrush = new LinearGradientBrush
                {
                    StartPoint = new RelativePoint(0.5, 0, RelativeUnit.Relative),
                    EndPoint = new RelativePoint(0.5, 1, RelativeUnit.Relative),
                    GradientStops =
                    {
                        new GradientStop(Colors.Transparent, 0),
                        new GradientStop(Color.FromArgb((byte)(110 * (1 - wt)), 76, 214, 255), 0.5),
                        new GradientStop(Colors.Transparent, 1)
                    }
                };
                context.FillRectangle(waveBrush, new Rect(0, waveY, bounds.Width, bandH));
            }

            // 4. Twinkling Ambient 4-point Star Sparkles across backdrop
            foreach (var (sx, sy, sr, spd, ph) in _ambientStars)
            {
                double tw = Math.Pow(0.5 + 0.5 * Math.Sin(_phase * spd + ph), 2);
                byte alpha = (byte)(tw * 165 * easeFocus * (1.0 - _exitProgress));
                double px = sx * bounds.Width;
                double py = sy * bounds.Height;
                DrawFourPointStar(context, new Point(px, py), sr * (1.5 + tw * 1.4), Color.FromArgb(alpha, 200, 240, 255));
            }

            // 5. Outer Perimeter Horizon Aurora Glow
            var auraBrush = ThemePalette.AuraGradientBrush(AppSettings.Shared.GlowColorTheme, _phase);
            double mult = AppSettings.Shared.GlowIntensity.OpacityMultiplier();
            double pulse = 0.78 + 0.22 * Math.Sin(_phase * 1.4);
            double rimOpacity = easeFocus * (1.0 - _exitProgress) * pulse;
            context.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb((byte)(80 * rimOpacity * mult), 76, 214, 255)), 9), bounds.Deflate(4), cornerR, cornerR);
            context.DrawRectangle(null, new Pen(auraBrush, 2.4 * mult * rimOpacity), bounds.Deflate(2), cornerR, cornerR);

            // 6. Active Selection or Drag Trail
            Rect? activeRect = _owner._activeSelectionDip;
            bool isLiveDrag = _owner._isDragging;
            if (isLiveDrag)
            {
                if (_owner._mode == SelectionMode.Freehand && _owner._freehandPoints.Count > 1)
                {
                    DrawGlowingPolyline(context, _owner._freehandPoints, auraBrush, mult, pulse);
                    return;
                }
                double x = Math.Min(_owner._dragStart.X, _owner._dragCurrent.X);
                double y = Math.Min(_owner._dragStart.Y, _owner._dragCurrent.Y);
                double w = Math.Abs(_owner._dragCurrent.X - _owner._dragStart.X);
                double h = Math.Abs(_owner._dragCurrent.Y - _owner._dragStart.Y);
                activeRect = new Rect(x, y, w, h);
            }

            if (activeRect is { Width: > 4, Height: > 4 } sel)
            {
                double selCorner = Math.Clamp(Math.Min(sel.Width, sel.Height) * 0.14, 10, 18);

                // Crisp un-dimmed interior
                double sx = _frozenBmp.PixelSize.Width / bounds.Width;
                double sy = _frozenBmp.PixelSize.Height / bounds.Height;
                var srcRect = new Rect(sel.X * sx, sel.Y * sy, sel.Width * sx, sel.Height * sy);
                context.DrawImage(_frozenBmp, srcRect, sel);

                // Animated Interior Scan Sweep while searching
                if (_scanBeamActive)
                {
                    double beamX = sel.X + (_scanProgress * (sel.Width + 90)) - 90;
                    var clip = context.PushClip(new RoundedRect(sel, selCorner));
                    var beamBrush = new LinearGradientBrush
                    {
                        StartPoint = new RelativePoint(0, 0.5, RelativeUnit.Relative),
                        EndPoint = new RelativePoint(1, 0.5, RelativeUnit.Relative),
                        GradientStops =
                        {
                            new GradientStop(Colors.Transparent, 0),
                            new GradientStop(Color.FromArgb(95, 110, 232, 255), 0.5),
                            new GradientStop(Colors.Transparent, 1)
                        }
                    };
                    context.FillRectangle(beamBrush, new Rect(beamX, sel.Y, 90, sel.Height));
                    clip.Dispose();
                }

                // Multi-stop halo + hairline frame
                context.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb((byte)(105 * pulse), 76, 214, 255)), 9), sel, selCorner, selCorner);
                context.DrawRectangle(null, new Pen(auraBrush, 2.2), sel, selCorner, selCorner);

                if (!isLiveDrag && _capturedFreehand == null)
                {
                    // Shockwave Ripple (0.52s on release!)
                    double capSec = (DateTime.UtcNow - _captureStart).TotalSeconds;
                    if (capSec >= 0 && capSec < 0.52)
                    {
                        double rt = AppleMotion.EaseOutCubic(capSec / 0.52);
                        double grow = 1.0 + 0.10 * rt;
                        double rw = sel.Width * grow;
                        double rh = sel.Height * grow;
                        var ripRect = new Rect(sel.Center.X - rw / 2, sel.Center.Y - rh / 2, rw, rh);
                        byte ra = (byte)(Math.Sin(rt * Math.PI) * 200);
                        context.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb(ra, 120, 235, 255)), 3.2 - 2.4 * rt), ripRect, selCorner, selCorner);
                    }

                    // Snapping Glowing White/Cyan L-Corner Brackets (exact macOS animateCornerBrackets!)
                    double snapT = Math.Clamp(capSec / 0.34, 0, 1);
                    double bracketScale = 1.0 + 0.12 * (1.0 - AppleMotion.SpringCurve(snapT, 0.78));
                    double bracketAlpha = 0.74 + 0.26 * Math.Sin(_phase * 1.6);
                    DrawCornerBrackets(context, sel, selCorner, bracketScale, Color.FromArgb((byte)(255 * bracketAlpha), 225, 248, 255));
                }

                // Sparkle burst particles around selection
                foreach (var p in _burstParticles)
                {
                    DrawFourPointStar(context, new Point(p.X, p.Y), p.Size, Color.FromArgb((byte)(230 * p.Life), 215, 248, 255));
                }
            }
        }

        private static void DrawGlowingPolyline(DrawingContext ctx, IReadOnlyList<Point> pts, IBrush auraBrush, double mult, double pulse)
        {
            var geo = new StreamGeometry();
            using (var g = geo.Open())
            {
                g.BeginFigure(pts[0], false);
                for (int i = 1; i < pts.Count; i++) g.LineTo(pts[i]);
            }
            ctx.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromArgb((byte)(100 * mult * pulse), 76, 214, 255)), 11, lineCap: PenLineCap.Round), geo);
            ctx.DrawGeometry(null, new Pen(auraBrush, 3.4, lineCap: PenLineCap.Round), geo);
        }

        private static void DrawCornerBrackets(DrawingContext ctx, Rect rect, double cornerR, double scale, Color color)
        {
            double arm = Math.Min(24, Math.Min(rect.Width, rect.Height) * 0.28);
            double r = Math.Min(cornerR, arm * 0.72);
            var pen = new Pen(new SolidColorBrush(color), 2.8, lineCap: PenLineCap.Round, lineJoin: PenLineJoin.Round);

            using (ctx.PushTransform(
                Matrix.CreateTranslation(-rect.Center.X, -rect.Center.Y) *
                Matrix.CreateScale(scale, scale) *
                Matrix.CreateTranslation(rect.Center.X, rect.Center.Y)))
            {
                var geo = new StreamGeometry();
                using (var g = geo.Open())
                {
                    // Top-Left
                    g.BeginFigure(new Point(rect.Left, rect.Top + arm), false);
                    g.LineTo(new Point(rect.Left, rect.Top + r));
                    g.QuadraticBezierTo(new Point(rect.Left, rect.Top), new Point(rect.Left + r, rect.Top));
                    g.LineTo(new Point(rect.Left + arm, rect.Top));

                    // Top-Right
                    g.BeginFigure(new Point(rect.Right - arm, rect.Top), false);
                    g.LineTo(new Point(rect.Right - r, rect.Top));
                    g.QuadraticBezierTo(new Point(rect.Right, rect.Top), new Point(rect.Right, rect.Top + r));
                    g.LineTo(new Point(rect.Right, rect.Top + arm));

                    // Bottom-Right
                    g.BeginFigure(new Point(rect.Right, rect.Bottom - arm), false);
                    g.LineTo(new Point(rect.Right, rect.Bottom - r));
                    g.QuadraticBezierTo(new Point(rect.Right, rect.Bottom), new Point(rect.Right - r, rect.Bottom));
                    g.LineTo(new Point(rect.Right - arm, rect.Bottom));

                    // Bottom-Left
                    g.BeginFigure(new Point(rect.Left + arm, rect.Bottom), false);
                    g.LineTo(new Point(rect.Left + r, rect.Bottom));
                    g.QuadraticBezierTo(new Point(rect.Left, rect.Bottom), new Point(rect.Left, rect.Bottom - r));
                    g.LineTo(new Point(rect.Left, rect.Bottom - arm));
                }
                ctx.DrawGeometry(null, pen, geo);
            }
        }

        private static void DrawFourPointStar(DrawingContext ctx, Point c, double radius, Color color)
        {
            if (color.A < 8) return;
            var pen = new Pen(new SolidColorBrush(color), 1.1, lineCap: PenLineCap.Round);
            ctx.DrawLine(pen, new Point(c.X - radius, c.Y), new Point(c.X + radius, c.Y));
            ctx.DrawLine(pen, new Point(c.X, c.Y - radius), new Point(c.X, c.Y + radius));
            ctx.DrawEllipse(new SolidColorBrush(color), null, c, radius * 0.25, radius * 0.25);
        }

        private static Point PointOnRectPerimeter(Rect r, double t)
        {
            double p = (t % 1.0) * 4.0;
            if (p < 1) return new Point(r.Left + r.Width * p, r.Top);
            if (p < 2) return new Point(r.Right, r.Top + r.Height * (p - 1));
            if (p < 3) return new Point(r.Right - r.Width * (p - 2), r.Bottom);
            return new Point(r.Left, r.Bottom - r.Height * (p - 3));
        }
    }
}
