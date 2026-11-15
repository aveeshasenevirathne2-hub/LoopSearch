using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace LoopSearch.Services;

public sealed record NormalizedTextBlock(string Text, double X, double Y, double Width, double Height);

public sealed record VisionAnalysisResult(
    string OcrText,
    string CleanPreview,
    string? DetectedUrl,
    string? MathAnswer,
    string? DominantHex,
    IReadOnlyList<NormalizedTextBlock> TextBlocks,
    bool IsLowInformation);

public static class MathEvaluator
{
    private static readonly Regex MathCandidateRegex = new(@"^[\d\s\+\-\*\/\(\)\.\^×÷]+$", RegexOptions.Compiled);

    public static string? TryEvaluate(string input)
    {
        if (string.IsNullOrWhiteSpace(input)) return null;
        var cleaned = input.Trim()
            .Replace("×", "*")
            .Replace("÷", "/")
            .Replace("=", "")
            .Trim();

        if (cleaned.Length < 3 || cleaned.Length > 80) return null;
        if (!MathCandidateRegex.IsMatch(cleaned)) return null;
        if (!cleaned.Any(c => c is '+' or '-' or '*' or '/' or '^')) return null;

        try
        {
            int pos = 0;
            double val = ParseExpression(cleaned, ref pos);
            SkipWhitespace(cleaned, ref pos);
            if (pos != cleaned.Length || double.IsNaN(val) || double.IsInfinity(val))
                return null;

            if (Math.Abs(val - Math.Round(val)) < 1e-9 && Math.Abs(val) < 1e14)
                return ((long)Math.Round(val)).ToString(CultureInfo.InvariantCulture);

            return Math.Round(val, 6).ToString("G", CultureInfo.InvariantCulture);
        }
        catch
        {
            return null;
        }
    }

    private static void SkipWhitespace(string s, ref int pos)
    {
        while (pos < s.Length && char.IsWhiteSpace(s[pos])) pos++;
    }

    private static double ParseExpression(string s, ref int pos)
    {
        double left = ParseTerm(s, ref pos);
        while (true)
        {
            SkipWhitespace(s, ref pos);
            if (pos >= s.Length) break;
            char op = s[pos];
            if (op is '+' or '-')
            {
                pos++;
                double right = ParseTerm(s, ref pos);
                left = op == '+' ? left + right : left - right;
            }
            else break;
        }
        return left;
    }

    private static double ParseTerm(string s, ref int pos)
    {
        double left = ParsePower(s, ref pos);
        while (true)
        {
            SkipWhitespace(s, ref pos);
            if (pos >= s.Length) break;
            char op = s[pos];
            if (op is '*' or '/')
            {
                pos++;
                double right = ParsePower(s, ref pos);
                if (op == '/' && Math.Abs(right) < 1e-12) throw new DivideByZeroException();
                left = op == '*' ? left * right : left / right;
            }
            else break;
        }
        return left;
    }

    private static double ParsePower(string s, ref int pos)
    {
        double baseVal = ParseUnary(s, ref pos);
        SkipWhitespace(s, ref pos);
        if (pos < s.Length && s[pos] == '^')
        {
            pos++;
            double exp = ParsePower(s, ref pos);
            return Math.Pow(baseVal, exp);
        }
        return baseVal;
    }

    private static double ParseUnary(string s, ref int pos)
    {
        SkipWhitespace(s, ref pos);
        if (pos < s.Length && s[pos] == '-')
        {
            pos++;
            return -ParseUnary(s, ref pos);
        }
        if (pos < s.Length && s[pos] == '+')
        {
            pos++;
            return ParseUnary(s, ref pos);
        }
        return ParsePrimary(s, ref pos);
    }

    private static double ParsePrimary(string s, ref int pos)
    {
        SkipWhitespace(s, ref pos);
        if (pos < s.Length && s[pos] == '(')
        {
            pos++;
            double val = ParseExpression(s, ref pos);
            SkipWhitespace(s, ref pos);
            if (pos >= s.Length || s[pos] != ')') throw new FormatException();
            pos++;
            return val;
        }

        int start = pos;
        while (pos < s.Length && (char.IsDigit(s[pos]) || s[pos] == '.')) pos++;
        if (pos == start) throw new FormatException();
        return double.Parse(s[start..pos], CultureInfo.InvariantCulture);
    }
}

public static class ColorAnalyzer
{
    /// <summary>
    /// Computes the most representative vibrant hex color from a tightly sampled 32-bit BGRA pixel buffer.
    /// </summary>
    public static (string? DominantHex, bool IsLowInfo) AnalyzeBgraPixels(ReadOnlySpan<byte> bgra, int width, int height)
    {
        if (bgra.Length < 4 || width <= 0 || height <= 0)
            return (null, true);

        int totalPixels = Math.Min(width * height, bgra.Length / 4);
        int step = Math.Max(1, totalPixels / 256);

        long rSum = 0, gSum = 0, bSum = 0, count = 0;
        double minLum = 1.0, maxLum = 0.0;
        double bestScore = -1.0;
        byte bestR = 0, bestG = 0, bestB = 0;

        for (int idx = 0; idx < totalPixels; idx += step)
        {
            int o = idx * 4;
            byte b = bgra[o];
            byte g = bgra[o + 1];
            byte r = bgra[o + 2];

            double rn = r / 255.0, gn = g / 255.0, bn = b / 255.0;
            double maxC = Math.Max(rn, Math.Max(gn, bn));
            double minC = Math.Min(rn, Math.Min(gn, bn));
            double delta = maxC - minC;
            double lum = 0.2126 * rn + 0.7152 * gn + 0.0722 * bn;

            if (lum < minLum) minLum = lum;
            if (lum > maxLum) maxLum = lum;

            rSum += r;
            gSum += g;
            bSum += b;
            count++;

            double sat = maxC > 0 ? delta / maxC : 0;
            // Favor saturated mid-tone pixels over pure white/black backgrounds
            double lumWeight = 1.0 - Math.Abs(lum - 0.52) * 1.1;
            double score = sat * 1.8 + Math.Max(0, lumWeight) * 0.45;
            if (score > bestScore && delta > 0.08)
            {
                bestScore = score;
                bestR = r;
                bestG = g;
                bestB = b;
            }
        }

        if (count == 0) return (null, true);

        bool isLowInfo = (maxLum - minLum) < 0.055;
        if (bestScore < 0)
        {
            bestR = (byte)(rSum / count);
            bestG = (byte)(gSum / count);
            bestB = (byte)(bSum / count);
        }

        return ($"#{bestR:X2}{bestG:X2}{bestB:X2}", isLowInfo);
    }
}

public static class TextInsightHelper
{
    private static readonly Regex UrlRegex = new(@"https?://[^\s<>""'\)\]]+", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(14) };

    public static string? ExtractFirstUrl(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var m = UrlRegex.Match(text);
        return m.Success ? m.Value.TrimEnd('.', ',', ';', ')') : null;
    }

    public static string MakeCleanPreview(string text, int maxLength = 160)
    {
        if (string.IsNullOrWhiteSpace(text)) return "";
        var normalized = Regex.Replace(text.Trim(), @"\s+", " ");
        return normalized.Length <= maxLength ? normalized : normalized[..(maxLength - 1)] + "…";
    }

    public static async Task<string?> AskGeminiVisionAsync(byte[] jpegBytes, string? userQuery, string ocrText, string apiKey)
    {
        if (string.IsNullOrWhiteSpace(apiKey) || jpegBytes.Length == 0) return null;

        string prompt;
        if (!string.IsNullOrWhiteSpace(userQuery))
            prompt = $"Answer concisely in 1 to 2 sentences about this screen selection: {userQuery.Trim()}";
        else if (!string.IsNullOrWhiteSpace(ocrText))
            prompt = "Explain what this selected screen snippet means or does in 1 to 2 concise sentences.";
        else
            prompt = "Identify and explain what is shown in this screen selection in 1 to 2 concise sentences.";

        var payload = new
        {
            contents = new[]
            {
                new
                {
                    parts = new object[]
                    {
                        new { text = prompt },
                        new
                        {
                            inline_data = new
                            {
                                mime_type = "image/jpeg",
                                data = Convert.ToBase64String(jpegBytes)
                            }
                        }
                    }
                }
            },
            generationConfig = new
            {
                maxOutputTokens = 160,
                temperature = 0.2
            }
        };

        try
        {
            var url = $"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key={Uri.EscapeDataString(apiKey)}";
            using var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            using var resp = await Http.PostAsync(url, content);
            if (!resp.IsSuccessStatusCode) return null;

            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            var root = doc.RootElement;
            if (root.TryGetProperty("candidates", out var cands) && cands.GetArrayLength() > 0)
            {
                var first = cands[0];
                if (first.TryGetProperty("content", out var cont) &&
                    cont.TryGetProperty("parts", out var parts) &&
                    parts.GetArrayLength() > 0 &&
                    parts[0].TryGetProperty("text", out var txt))
                {
                    return txt.GetString()?.Trim();
                }
            }
            return null;
        }
        catch
        {
            return null;
        }
    }
}
