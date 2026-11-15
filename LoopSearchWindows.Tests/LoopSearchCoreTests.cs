using System.Text.Json;
using LoopSearch.Models;
using LoopSearch.Services;
using Xunit;

namespace LoopSearch.Tests;

public class LoopSearchCoreTests
{
    [Fact]
    public void FirebaseClientConfig_MatchesLoopSearchAnalyticsProject()
    {
        var cfg = FirebaseClientConfig.BuiltInDefault;
        Assert.Equal("loopsearch-analytics-78e3", cfg.ProjectId);
        Assert.Equal("https://loopsearch-analytics-78e3.web.app/app-auth.html", cfg.AuthPageUrl);
        Assert.Equal("https://loopsearch-analytics-78e3.web.app", cfg.AuthRequestUri);
        Assert.Contains("documents:commit", cfg.FirestoreCommitUrl);
    }

    [Fact]
    public void FirestorePayloadBuilder_GeneratesValidUserAndEventWrites()
    {
        var cfg = FirebaseClientConfig.BuiltInDefault;
        var session = new FirebaseUserSession
        {
            Uid = "user-123",
            Email = "test@example.com",
            DisplayName = "Test User",
            PhotoUrl = "https://example.com/p.png",
            IdToken = "tok",
            RefreshToken = "ref",
            ExpiresAt = DateTimeOffset.UtcNow.AddHours(1)
        };
        var evt = new AnalyticsTelemetryEvent
        {
            Id = "evt-456",
            EventType = "interactive_sign_in",
            DateKey = "2026-11-15",
            AppVersion = "1.0.3",
            OsVersion = "Windows 11 (10.0.22631)"
        };

        var payload = FirestorePayloadBuilder.BuildCommitPayload(cfg, session, evt, userExists: false);
        var json = JsonSerializer.Serialize(payload);

        using var doc = JsonDocument.Parse(json);
        var writes = doc.RootElement.GetProperty("writes");
        Assert.Equal(2, writes.GetArrayLength());

        var userDoc = writes[0].GetProperty("update");
        Assert.EndsWith("/documents/users/user-123", userDoc.GetProperty("name").GetString());
        Assert.Equal("Windows 11 (10.0.22631)", userDoc.GetProperty("fields").GetProperty("osVersion").GetProperty("stringValue").GetString());
        Assert.Equal("1", userDoc.GetProperty("fields").GetProperty("loginCount").GetProperty("integerValue").GetString());

        var eventDoc = writes[1].GetProperty("update");
        Assert.EndsWith("/documents/loginEvents/evt-456", eventDoc.GetProperty("name").GetString());
        Assert.Equal("interactive_sign_in", eventDoc.GetProperty("fields").GetProperty("eventType").GetProperty("stringValue").GetString());
    }

    [Fact]
    public void CustomHotkey_DisplaysReadableModifiersAndKey()
    {
        var def = CustomHotkey.Default;
        Assert.True(def.IsValid);
        Assert.Equal("Ctrl + Shift + Space", def.DisplayString);
        Assert.Equal("Ctrl+Shift+Space", def.CompactString);

        var altSpace = new CustomHotkey { Modifiers = CustomHotkey.ModAlt, VirtualKey = 0x20 };
        Assert.Equal("Alt+Space", altSpace.CompactString);
    }

    [Fact]
    public void SearchEngine_BuildsExpectedUrls()
    {
        Assert.Equal("https://www.google.com/search?q=coffee%20mug", SearchEngine.Google.BuildSearchUrl("coffee mug"));
        Assert.Equal("https://www.perplexity.ai/search?q=quantum", SearchEngine.Perplexity.BuildSearchUrl("quantum"));
        Assert.Equal("https://www.bing.com/search?q=test", SearchEngine.Bing.BuildSearchUrl("test"));
        Assert.Equal("https://www.google.com/search?udm=50&q=explain%20this", SearchEngine.AskAI.BuildSearchUrl("explain this"));
    }

    [Fact]
    public void GoogleLensService_BuildsMultisearchUrl()
    {
        var url = GoogleLensService.BuildMultisearchUrl("https://lens.google.com/search?p=abc123", "price in usd");
        Assert.NotNull(url);
        Assert.Contains("p=abc123", url);
        Assert.Contains("q=price", url);
    }

    [Fact]
    public void MathEvaluator_EvaluatesExpressionsSafely()
    {
        Assert.Equal("288", MathEvaluator.TryEvaluate("24 * 12"));
        Assert.Equal("50", MathEvaluator.TryEvaluate("(100 + 50) / 3 ="));
        Assert.Equal("256", MathEvaluator.TryEvaluate("2^8"));
        Assert.Null(MathEvaluator.TryEvaluate("hello world"));
        Assert.Null(MathEvaluator.TryEvaluate("10 / 0"));
    }

    [Fact]
    public void ColorAnalyzer_ExtractsVibrantHexAndDetectsLowInfo()
    {
        // 4 vibrant cyan pixels (#4CD6FF in BGRA = FF, D6, 4C, FF)
        byte[] vibrant = new byte[16];
        for (int i = 0; i < 4; i++)
        {
            vibrant[i * 4 + 0] = 0xFF;
            vibrant[i * 4 + 1] = 0xD6;
            vibrant[i * 4 + 2] = 0x4C;
            vibrant[i * 4 + 3] = 0xFF;
        }
        var (hex, lowInfo) = ColorAnalyzer.AnalyzeBgraPixels(vibrant, 2, 2);
        Assert.Equal("#4CD6FF", hex);
        Assert.True(lowInfo);
    }

    [Fact]
    public void AppUpdateChecker_ComparesSemanticVersionsCorrectly()
    {
        Assert.True(AppUpdateChecker.IsVersionNewer("v1.0.4", "1.0.3"));
        Assert.True(AppUpdateChecker.IsVersionNewer("1.1.0", "1.0.3"));
        Assert.False(AppUpdateChecker.IsVersionNewer("v1.0.3", "1.0.3"));
        Assert.False(AppUpdateChecker.IsVersionNewer("1.0.2", "1.0.3"));
    }

    [Fact]
    public void AppSettings_PersistsAndResetsCleanly()
    {
        var tempDir = Path.Combine(Path.GetTempPath(), "loopsearch-tests-" + Guid.NewGuid().ToString("N"));
        try
        {
            var settings = new AppSettings(tempDir);
            settings.AppTheme = AppTheme.Light;
            settings.WebResultsTheme = AppTheme.Dark;
            settings.SearchEngine = SearchEngine.Perplexity;
            settings.Hotkey = new CustomHotkey { Modifiers = CustomHotkey.ModControl | CustomHotkey.ModAlt, VirtualKey = 0x53 };

            var reloaded = new AppSettings(tempDir);
            Assert.Equal(AppTheme.Light, reloaded.AppTheme);
            Assert.Equal(AppTheme.Dark, reloaded.WebResultsTheme);
            Assert.Equal(SearchEngine.Perplexity, reloaded.SearchEngine);
            Assert.Equal("Ctrl+Alt+S", reloaded.Hotkey.CompactString);

            reloaded.ResetToDefaults();
            Assert.Equal(AppTheme.Dark, reloaded.AppTheme);
            Assert.Equal(SearchEngine.GoogleLens, reloaded.SearchEngine);
            Assert.True(reloaded.HasCompletedOnboarding);
        }
        finally
        {
            if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
        }
    }
}
