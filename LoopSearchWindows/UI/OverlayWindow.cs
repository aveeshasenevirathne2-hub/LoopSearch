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

    private SelectionMode _mode;
    private bool _isDragging;
    private Point _dragStart;
    private Point _dragCurrent;
    private readonly List<Point> _freehandPoints = [];
    private Rect? _activeSelectionDip;

    // Results Sheet UI
    private Border? _resultsSheet;
    private WebView2Host? _webView;
    private TextBox? _followUpBox;
    private TextBlock? _ocrPreviewLabel;
    private TextBlock? _aiBannerLabel;
    private Border? _loadingBar;
    private WrapPanel? _chipsPanel;
    private string? _lensBaseUrl;
    private string? _currentExternalUrl;
    private System.Drawing.Bitmap? _lastCroppedBmp;
    private byte[]? _lastJpegBytes;
    private VisionAnalysisResult? _lastVision;

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
        TransparencyLevelHint = [WindowTransparencyLevel.Transparent];
        Background = Brushes.Black;
        CanResize = false;
        Cursor = new Cursor(StandardCursorType.Cross);

        // Position precisely over captured monitor/virtual screen
        Position = new PixelPoint(capture.VirtualX, capture.VirtualY);
        WindowState = WindowState.Normal;

        var rootGrid = new Grid();
        _canvas = new OverlayCanvas(this, _frozenAvaloniaBitmap);
        rootGrid.Children.Add(_canvas);

        // Bottom floating Liquid Glass pill bar
        var pillRow = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 6,
            VerticalAlignment = VerticalAlignment.Center
        };

        pillRow.Children.Add(LiquidGlassUI.CreateBrandBadge(28));

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
            Foreground = new SolidColorBrush(Color.Parse("#A4C2EC"))
        });
        pillRow.Children.Add(textStack);

        var modes = new[] { SelectionMode.Box, SelectionMode.Freehand, SelectionMode.Tap, SelectionMode.Text };
        for (int i = 0; i < modes.Length; i++)
        {
            var m = modes[i];
            var btn = new Button
            {
                Content = new TextBlock
                {
                    Text = $"{m.ShortcutDigit()} {m.Title()}",
                    FontSize = 11.5,
                    FontWeight = FontWeight.SemiBold,
                    Foreground = Brushes.White
                },
                CornerRadius = new CornerRadius(9),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(10, 5),
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            btn.Click += (_, _) => SwitchMode(m);
            _modeButtons[i] = btn;
            pillRow.Children.Add(btn);
        }

        var settingsBtn = new Button
        {
            Content = new TextBlock { Text = "⚙", FontSize = 13, Foreground = Brushes.White },
            Background = new SolidColorBrush(Color.FromArgb(45, 255, 255, 255)),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(9, 4),
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        ToolTip.SetTip(settingsBtn, "Studio Settings");
        settingsBtn.Click += (_, _) =>
        {
            Close();
            _openSettingsAction();
        };
        pillRow.Children.Add(settingsBtn);

        var closeBtn = new Button
        {
            Content = new TextBlock { Text = "×", FontSize = 15, FontWeight = FontWeight.Bold, Foreground = Brushes.White },
            Background = new SolidColorBrush(Color.FromArgb(45, 255, 255, 255)),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(9, 2),
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        closeBtn.Click += (_, _) => Close();
        pillRow.Children.Add(closeBtn);

        _pillBar = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(215, 11, 18, 34)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(115, 76, 214, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(10, 7),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 0, 34),
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
            Activate();
            Focus();

            if (preCroppedClipboard != null)
            {
                var centerRect = new Rect(Width * 0.28, Height * 0.25, Math.Min(360, Width * 0.35), Math.Min(260, Height * 0.35));
                _activeSelectionDip = centerRect;
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
                : new SolidColorBrush(Color.FromArgb(30, 255, 255, 255));
            _modeButtons[i].BorderBrush = active
                ? new SolidColorBrush(Color.FromArgb(140, 116, 232, 255))
                : Brushes.Transparent;
        }
    }

    private void OnOverlayKeyDown(object? sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Close();
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
        if (_mode == SelectionMode.Tap)
        {
            double w = 220, h = 150;
            selectionDip = ClampRect(new Rect(_dragCurrent.X - w / 2, _dragCurrent.Y - h / 2, w, h));
        }
        else if (_mode == SelectionMode.Freehand && _freehandPoints.Count > 4)
        {
            double minX = _freehandPoints.Min(p => p.X);
            double minY = _freehandPoints.Min(p => p.Y);
            double maxX = _freehandPoints.Max(p => p.X);
            double maxY = _freehandPoints.Max(p => p.Y);
            selectionDip = ClampRect(new Rect(minX - 6, minY - 6, Math.Max(28, maxX - minX + 12), Math.Max(28, maxY - minY + 12)));
        }
        else
        {
            double x = Math.Min(_dragStart.X, _dragCurrent.X);
            double y = Math.Min(_dragStart.Y, _dragCurrent.Y);
            double w = Math.Abs(_dragCurrent.X - _dragStart.X);
            double h = Math.Abs(_dragCurrent.Y - _dragStart.Y);
            if (w < 14 || h < 14)
            {
                // Treat tiny click as smart tap
                selectionDip = ClampRect(new Rect(_dragCurrent.X - 110, _dragCurrent.Y - 75, 220, 150));
            }
            else
            {
                selectionDip = ClampRect(new Rect(x, y, w, h));
            }
        }

        _activeSelectionDip = selectionDip;
        _canvas.InvalidateVisual();
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

        // Run local Windows OCR + Color + Math analysis in parallel with Google Lens upload
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

    private void EnsureResultsSheet(Rect selectionDip, System.Drawing.Bitmap previewBmp)
    {
        if (Content is not Grid rootGrid) return;

        double sheetW = 430;
        double sheetH = Math.Min(Height - 96, 660);

        // Position beside the selection if space allows, otherwise dock nicely on the right
        double rightSpace = Width - (selectionDip.Right + 24);
        double leftSpace = selectionDip.Left - 24;
        double xPos = rightSpace >= sheetW
            ? selectionDip.Right + 18
            : (leftSpace >= sheetW ? selectionDip.Left - sheetW - 18 : Width - sheetW - 24);
        double yPos = Math.Clamp(selectionDip.Top - 20, 22, Math.Max(22, Height - sheetH - 86));

        if (_resultsSheet != null)
        {
            rootGrid.Children.Remove(_resultsSheet);
        }

        // Convert preview bitmap
        using var ms = new MemoryStream(VisionOcrService.EncodePng(previewBmp));
        var avPreview = new Bitmap(ms);

        // Header bar
        var header = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,Auto,*,Auto,Auto,Auto,Auto") };

        var backBtn = SmallIconBtn("‹", () => _webView?.GoBack());
        header.Children.Add(backBtn);

        var reloadBtn = SmallIconBtn("↻", () => _webView?.Reload());
        Grid.SetColumn(reloadBtn, 1);
        reloadBtn.Margin = new Thickness(4, 0, 8, 0);
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

        var themeToggle = SmallIconBtn(ThemePalette.IsWebDark ? "☾" : "☀", async () =>
        {
            AppSettings.Shared.WebResultsTheme = ThemePalette.IsWebDark ? AppTheme.Light : AppTheme.Dark;
            if (_webView != null) await _webView.ApplyColorSchemeAsync();
        });
        ToolTip.SetTip(themeToggle, "Toggle Web Results Dark/Light");
        Grid.SetColumn(themeToggle, 3);
        header.Children.Add(themeToggle);

        var pinBtn = SmallIconBtn("📌", () =>
        {
            if (_lastCroppedBmp != null)
            {
                var clone = (System.Drawing.Bitmap)_lastCroppedBmp.Clone();
                new PinnedCaptureWindow(clone, _lastVision?.OcrText).Show();
            }
        });
        ToolTip.SetTip(pinBtn, "Pin Floating Capture");
        Grid.SetColumn(pinBtn, 4);
        pinBtn.Margin = new Thickness(4, 0, 0, 0);
        header.Children.Add(pinBtn);

        var extBtn = SmallIconBtn("↗", () =>
        {
            if (!string.IsNullOrEmpty(_currentExternalUrl))
                Process.Start(new ProcessStartInfo(_currentExternalUrl) { UseShellExecute = true });
        });
        ToolTip.SetTip(extBtn, "Open in Browser");
        Grid.SetColumn(extBtn, 5);
        extBtn.Margin = new Thickness(4, 0, 0, 0);
        header.Children.Add(extBtn);

        var closeBtn = SmallIconBtn("×", Close);
        Grid.SetColumn(closeBtn, 6);
        closeBtn.Margin = new Thickness(4, 0, 0, 0);
        header.Children.Add(closeBtn);

        // Search + Preview card
        var previewGrid = new Grid { ColumnDefinitions = new ColumnDefinitions("Auto,*"), Margin = new Thickness(0, 8, 0, 6) };
        previewGrid.Children.Add(new Border
        {
            Width = 54,
            Height = 44,
            CornerRadius = new CornerRadius(9),
            ClipToBounds = true,
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(0, 0, 10, 0),
            Child = new Image { Source = avPreview, Stretch = Stretch.UniformToFill }
        });

        var searchRow = new Grid { ColumnDefinitions = new ColumnDefinitions("*,Auto") };
        _followUpBox = new TextBox
        {
            Watermark = "Add to your search or ask AI...",
            FontSize = 12.5,
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(10, 6),
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(200, 18, 28, 48) : Color.FromArgb(220, 236, 243, 253)),
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
            Content = new TextBlock { Text = "→", FontWeight = FontWeight.Bold, FontSize = 13, Foreground = Brushes.White },
            Background = ThemePalette.AccentButtonBrush,
            CornerRadius = new CornerRadius(10),
            Width = 32,
            Height = 32,
            Margin = new Thickness(6, 0, 0, 0),
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        sendBtn.Click += (_, _) => _ = SubmitFollowUpAsync();
        Grid.SetColumn(sendBtn, 1);
        searchRow.Children.Add(sendBtn);

        Grid.SetColumn(searchRow, 1);
        previewGrid.Children.Add(searchRow);

        _ocrPreviewLabel = new TextBlock
        {
            Text = "Analyzing selection…",
            FontSize = 11,
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

        _loadingBar = new Border
        {
            Height = 2.5,
            CornerRadius = new CornerRadius(2),
            Background = ThemePalette.AccentButtonBrush,
            Margin = new Thickness(0, 0, 0, 4),
            IsVisible = false
        };

        _webView = new WebView2Host();
        _webView.LoadingChanged += loading => Dispatcher.UIThread.Post(() => SetLoading(loading));

        var sheetDock = new DockPanel();
        var topSection = new StackPanel();
        topSection.Children.Add(header);
        topSection.Children.Add(previewGrid);
        topSection.Children.Add(_ocrPreviewLabel);
        topSection.Children.Add(_chipsPanel);
        topSection.Children.Add(_aiBannerLabel);
        topSection.Children.Add(_loadingBar);

        DockPanel.SetDock(topSection, Dock.Top);
        sheetDock.Children.Add(topSection);
        sheetDock.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(12),
            ClipToBounds = true,
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            Child = _webView
        });

        _resultsSheet = new Border
        {
            Width = sheetW,
            Height = sheetH,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(xPos, yPos, 0, 0),
            Background = new SolidColorBrush(ThemePalette.IsDark ? Color.FromArgb(242, 12, 18, 33) : Color.FromArgb(245, 248, 251, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(125, 76, 214, 255)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(18),
            Padding = new Thickness(12),
            Child = sheetDock
        };

        rootGrid.Children.Add(_resultsSheet);
        LiquidGlassUI.AnimateWindowEntrance(this, _resultsSheet);
    }

    private void SetLoading(bool loading)
    {
        if (_loadingBar != null) _loadingBar.IsVisible = loading;
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

        _chipsPanel.Children.Add(MakeChip("Search", () =>
        {
            var q = !string.IsNullOrWhiteSpace(v.OcrText) ? v.OcrText : "search";
            var u = SearchEngine.Google.BuildSearchUrl(q);
            if (u != null) { _currentExternalUrl = u; _webView?.Navigate(u); }
        }));

        if (!string.IsNullOrWhiteSpace(v.OcrText))
        {
            _chipsPanel.Children.Add(MakeChip("Copy Text", async () =>
            {
                if (Clipboard != null) await Clipboard.SetTextAsync(v.OcrText);
                ToastWindow.ShowToast("Copied text to clipboard");
            }));
        }
        else
        {
            _chipsPanel.Children.Add(MakeChip("Copy Image", () =>
            {
                if (_lastCroppedBmp != null) NativeWin32.CopyBitmapToClipboard(_lastCroppedBmp);
                ToastWindow.ShowToast("Copied image to clipboard");
            }));
        }

        _chipsPanel.Children.Add(MakeChip("✦ Explain", () => _ = ExplainWithAiAsync(null)));

        if (!string.IsNullOrWhiteSpace(v.MathAnswer))
        {
            _chipsPanel.Children.Add(MakeChip($"= {v.MathAnswer}", async () =>
            {
                if (Clipboard != null) await Clipboard.SetTextAsync(v.MathAnswer);
                ToastWindow.ShowToast($"Copied {v.MathAnswer}");
            }));
        }

        if (!string.IsNullOrWhiteSpace(v.DetectedUrl))
        {
            _chipsPanel.Children.Add(MakeChip("Open Link ↗", () =>
            {
                Process.Start(new ProcessStartInfo(v.DetectedUrl) { UseShellExecute = true });
            }));
        }

        if (!string.IsNullOrWhiteSpace(v.DominantHex))
        {
            _chipsPanel.Children.Add(MakeChip(v.DominantHex, async () =>
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
        _aiBannerLabel.Text = "✦ Thinking…";
        _aiBannerLabel.IsVisible = true;
        var answer = await TextInsightHelper.AskGeminiVisionAsync(_lastJpegBytes, userQuery, _lastVision?.OcrText ?? "", apiKey);
        _aiBannerLabel.Text = !string.IsNullOrWhiteSpace(answer) ? $"✦ {answer}" : "Could not get AI summary.";
    }

    private static Button SmallIconBtn(string symbol, Action onClick)
    {
        var b = new Button
        {
            Content = new TextBlock
            {
                Text = symbol,
                FontSize = 13,
                FontWeight = FontWeight.SemiBold,
                Foreground = ThemePalette.PrimaryBrush,
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            },
            Width = 26,
            Height = 26,
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(8),
            Background = new SolidColorBrush(ThemePalette.CardSubtleFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            Cursor = new Cursor(StandardCursorType.Hand)
        };
        b.Click += (_, _) => onClick();
        return b;
    }

    private static Button MakeChip(string text, Action onClick, string? colorHex = null)
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
                BorderThickness = new Thickness(0.8)
            });
        }
        row.Children.Add(new TextBlock { Text = text, FontSize = 11, FontWeight = FontWeight.Medium, Foreground = ThemePalette.PrimaryBrush });

        var b = new Button
        {
            Content = row,
            Background = new SolidColorBrush(ThemePalette.CardSubtleFill),
            BorderBrush = new SolidColorBrush(ThemePalette.CardBorder),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(8, 4),
            Margin = new Thickness(0, 0, 5, 4),
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
        private double _pulsePhase;

        public OverlayCanvas(OverlayWindow owner, Bitmap frozenBmp)
        {
            _owner = owner;
            _frozenBmp = frozenBmp;
            _animTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(16) };
            _animTimer.Tick += (_, _) =>
            {
                _pulsePhase += 0.08;
                InvalidateVisual();
            };
            _animTimer.Start();
        }

        public void Stop() => _animTimer.Stop();

        public override void Render(DrawingContext context)
        {
            var bounds = Bounds;
            if (bounds.Width <= 0 || bounds.Height <= 0) return;

            // 1. Frozen screenshot
            context.DrawImage(_frozenBmp, new Rect(0, 0, _frozenBmp.PixelSize.Width, _frozenBmp.PixelSize.Height), bounds);

            // 2. Subtle atmospheric scrim
            context.FillRectangle(new SolidColorBrush(Color.FromArgb(46, 5, 10, 22)), bounds);

            // 3. Horizon edge rim glow (matches macOS screenshot 2 & 8!)
            var auraBrush = ThemePalette.AuraGradientBrush(AppSettings.Shared.GlowColorTheme);
            double mult = AppSettings.Shared.GlowIntensity.OpacityMultiplier();
            double pulse = 0.72 + 0.28 * Math.Sin(_pulsePhase);
            var edgePen = new Pen(auraBrush, 3.2 * mult * pulse);
            context.DrawRectangle(null, edgePen, bounds.Deflate(2), 14, 14);

            // 4. Active selection or live drag trail
            Rect? activeRect = _owner._activeSelectionDip;
            if (_owner._isDragging)
            {
                if (_owner._mode == SelectionMode.Freehand && _owner._freehandPoints.Count > 1)
                {
                    var geo = new StreamGeometry();
                    using (var ctx = geo.Open())
                    {
                        ctx.BeginFigure(_owner._freehandPoints[0], false);
                        for (int i = 1; i < _owner._freehandPoints.Count; i++)
                            ctx.LineTo(_owner._freehandPoints[i]);
                    }
                    context.DrawGeometry(null, new Pen(new SolidColorBrush(Color.FromArgb(95, 76, 214, 255)), 9, lineCap: PenLineCap.Round), geo);
                    context.DrawGeometry(null, new Pen(auraBrush, 3.2, lineCap: PenLineCap.Round), geo);
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
                // Draw bright un-dimmed interior of selection
                double sx = _frozenBmp.PixelSize.Width / bounds.Width;
                double sy = _frozenBmp.PixelSize.Height / bounds.Height;
                var srcRect = new Rect(sel.X * sx, sel.Y * sy, sel.Width * sx, sel.Height * sy);
                context.DrawImage(_frozenBmp, srcRect, sel);

                // Outer glow + crisp glowing border
                context.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb((byte)(100 * pulse), 76, 214, 255)), 8), sel, 12, 12);
                context.DrawRectangle(null, new Pen(auraBrush, 2.4), sel, 12, 12);
            }
        }
    }
}
