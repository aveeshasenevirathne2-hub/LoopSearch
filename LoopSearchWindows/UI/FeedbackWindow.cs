using System.Diagnostics;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using Avalonia.Layout;
using Avalonia.Media;
using LoopSearch.Models;

namespace LoopSearch.UI;

public sealed class FeedbackWindow : Window
{
    private int _rating = 5;
    private string _category = "Feature Request";
    private readonly Button[] _stars = new Button[5];
    private readonly Button[] _catBtns = new Button[4];

    public FeedbackWindow()
    {
        var stack = new StackPanel { Spacing = 14, Margin = new Thickness(24, 6, 24, 22) };

        stack.Children.Add(new TextBlock
        {
            Text = "Rate & Suggest Feature",
            FontSize = 19,
            FontWeight = FontWeight.Bold,
            Foreground = ThemePalette.PrimaryBrush
        });
        stack.Children.Add(new TextBlock
        {
            Text = "Help shape LoopSearch for Windows. Your rating & notes open a pre-filled GitHub submission.",
            FontSize = 12,
            TextWrapping = TextWrapping.Wrap,
            Foreground = ThemePalette.SecondaryBrush
        });

        // Vector Stars (zero emoji variation!)
        var starRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        for (int i = 0; i < 5; i++)
        {
            int idx = i + 1;
            var b = new Button
            {
                Content = LiquidGlassIcons.FillIcon(LiquidGlassIcons.Star, 22, new SolidColorBrush(Color.Parse("#FFB84D"))),
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
                Padding = new Thickness(4),
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            b.Click += (_, _) => { _rating = idx; UpdateStars(); };
            _stars[i] = b;
            starRow.Children.Add(b);
        }
        stack.Children.Add(starRow);
        UpdateStars();

        string[] cats = ["Feature Request", "Bug Report", "UI & Motion", "Search Quality"];
        var catGrid = new UniformGrid { Columns = 2, Rows = 2 };
        for (int i = 0; i < cats.Length; i++)
        {
            string cat = cats[i];
            var b = new Button
            {
                Content = new TextBlock { Text = cat, FontSize = 12, HorizontalAlignment = HorizontalAlignment.Center },
                Margin = new Thickness(3),
                CornerRadius = new CornerRadius(10),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(8, 7),
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Center,
                Cursor = new Cursor(StandardCursorType.Hand)
            };
            b.Click += (_, _) => { _category = cat; UpdateCategories(cats); };
            _catBtns[i] = b;
            catGrid.Children.Add(b);
        }
        stack.Children.Add(catGrid);
        UpdateCategories(cats);

        var messageBox = new TextBox
        {
            Watermark = "Describe your idea or issue…",
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            Height = 110,
            FontSize = 12.5
        };
        stack.Children.Add(messageBox);

        var footer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right };
        footer.Children.Add(LiquidGlassUI.CreateGlassButton("Cancel", Close));
        footer.Children.Add(LiquidGlassUI.CreatePrimaryButton("Submit on GitHub", () =>
        {
            var title = Uri.EscapeDataString($"[Windows v{AppSettings.CurrentAppVersion}] [{_category}] ({_rating}/5★)");
            var body = Uri.EscapeDataString($"**Rating:** {_rating}/5\n**Category:** {_category}\n**Platform:** Windows ({Environment.OSVersion})\n\n**Notes:**\n{messageBox.Text ?? ""}");
            var url = $"https://github.com/{AppSettings.GitHubRepo}/issues/new?title={title}&body={body}";
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            Close();
        }, iconPath: LiquidGlassIcons.ExternalArrow));
        stack.Children.Add(footer);

        var shell = LiquidGlassUI.WrapBorderlessGlassShell(this, 500, 445, "Rate & Suggest Feature", stack, showTitleInBar: false);
        Opened += (_, _) => AppleMotion.AnimateWindowEntrance(this, shell);
    }

    private void UpdateStars()
    {
        for (int i = 0; i < 5; i++)
        {
            if (_stars[i].Content is Avalonia.Controls.Shapes.Path p)
                p.Fill = i < _rating ? new SolidColorBrush(Color.Parse("#FFB84D")) : ThemePalette.MutedBrush;
        }
    }

    private void UpdateCategories(string[] cats)
    {
        for (int i = 0; i < cats.Length; i++)
        {
            bool sel = cats[i] == _category;
            _catBtns[i].Background = sel ? ThemePalette.AccentButtonBrush : new SolidColorBrush(ThemePalette.CardSubtleFill);
            _catBtns[i].BorderBrush = new SolidColorBrush(sel ? Color.FromArgb(140, 116, 232, 255) : ThemePalette.CardBorder);
            if (_catBtns[i].Content is TextBlock tb)
            {
                tb.Foreground = sel ? Brushes.White : ThemePalette.PrimaryBrush;
                tb.FontWeight = sel ? FontWeight.SemiBold : FontWeight.Medium;
            }
        }
    }
}
