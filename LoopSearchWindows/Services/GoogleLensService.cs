using System.Net;
using System.Net.Http.Headers;

namespace LoopSearch.Services;

public sealed record LensUploadResult(string ResultsUrl, IReadOnlyList<Cookie> Cookies);

public static class GoogleLensService
{
    public const string MobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1";

    public static async Task<LensUploadResult?> UploadImageAsync(byte[] jpegBytes, CancellationToken ct = default)
    {
        var cookies = new CookieContainer();
        using var handler = new HttpClientHandler
        {
            AllowAutoRedirect = false,
            CookieContainer = cookies,
            UseCookies = true
        };
        using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(20) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd(MobileUserAgent);
        client.DefaultRequestHeaders.Referrer = new Uri("https://lens.google.com/");
        client.DefaultRequestHeaders.TryAddWithoutValidation("Origin", "https://lens.google.com");

        using var form = new MultipartFormDataContent();
        var imageContent = new ByteArrayContent(jpegBytes);
        imageContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        form.Add(imageContent, "encoded_image", "search.jpg");

        try
        {
            using var response = await client.PostAsync("https://lens.google.com/v3/upload", form, ct);
            var status = (int)response.StatusCode;
            if (status >= 300 && status < 400 && response.Headers.Location != null)
            {
                var redirect = response.Headers.Location.IsAbsoluteUri
                    ? response.Headers.Location.ToString()
                    : new Uri(new Uri("https://lens.google.com"), response.Headers.Location).ToString();

                var capturedCookies = cookies.GetCookies(new Uri("https://lens.google.com")).Cast<Cookie>().ToList();
                return new LensUploadResult(redirect, capturedCookies);
            }
            return null;
        }
        catch
        {
            return null;
        }
    }

    public static string? BuildMultisearchUrl(string baseUrl, string query)
    {
        var trimmed = query.Trim();
        if (string.IsNullOrEmpty(trimmed)) return null;
        if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri)) return null;
        var builder = new UriBuilder(uri);
        var q = System.Web.HttpUtility.ParseQueryString(builder.Query);
        q["q"] = trimmed;
        builder.Query = q.ToString();
        return builder.Uri.ToString();
    }
}
