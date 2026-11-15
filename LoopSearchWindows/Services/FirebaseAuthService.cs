using System.Diagnostics;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Web;
using LoopSearch.Models;

namespace LoopSearch.Services;

public sealed record FirebaseClientConfig(
    string ApiKey,
    string ProjectId,
    string DatabaseId,
    string AuthPageUrl,
    string AuthRequestUri)
{
    public static FirebaseClientConfig BuiltInDefault { get; } = new(
        ApiKey: "AIzaSyD67B6MnCvLwYB5xLQVH3IQdguetSe-Koc",
        ProjectId: "loopsearch-analytics-78e3",
        DatabaseId: "(default)",
        AuthPageUrl: "https://loopsearch-analytics-78e3.web.app/app-auth.html",
        AuthRequestUri: "https://loopsearch-analytics-78e3.web.app"
    );

    public string FirestoreCommitUrl =>
        $"https://firestore.googleapis.com/v1/projects/{ProjectId}/databases/{DatabaseId}/documents:commit";

    public string UserDocumentUrl(string uid) =>
        $"https://firestore.googleapis.com/v1/projects/{ProjectId}/databases/{DatabaseId}/documents/users/{Uri.EscapeDataString(uid)}";
}

public sealed class FirebaseUserSession
{
    public string Uid { get; set; } = "";
    public string Email { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string PhotoUrl { get; set; } = "";
    public string IdToken { get; set; } = "";
    public string RefreshToken { get; set; } = "";
    public DateTimeOffset ExpiresAt { get; set; }

    [JsonIgnore]
    public bool IsTokenFresh => DateTimeOffset.UtcNow < ExpiresAt.AddMinutes(-2);
}

public sealed class AnalyticsTelemetryEvent
{
    public string Id { get; set; } = Guid.NewGuid().ToString("D");
    public string EventType { get; set; } = "app_launch";
    public string DateKey { get; set; } = DateTimeOffset.UtcNow.ToString("yyyy-MM-dd");
    public string AppVersion { get; set; } = AppSettings.CurrentAppVersion;
    public string OsVersion { get; set; } = BuildOsVersionString();

    public static string BuildOsVersionString()
    {
        var ver = Environment.OSVersion.Version;
        if (ver.Major == 10 && ver.Build >= 22000)
            return $"Windows 11 ({ver.Major}.{ver.Minor}.{ver.Build})";
        return $"Windows {ver.Major}.{ver.Minor}.{ver.Build}";
    }
}

public static class FirestorePayloadBuilder
{
    public static object BuildCommitPayload(
        FirebaseClientConfig config,
        FirebaseUserSession session,
        AnalyticsTelemetryEvent evt,
        bool userExists)
    {
        var userDocName = $"projects/{config.ProjectId}/databases/{config.DatabaseId}/documents/users/{session.Uid}";
        var eventDocName = $"projects/{config.ProjectId}/databases/{config.DatabaseId}/documents/loginEvents/{evt.Id}";

        var userFields = new Dictionary<string, object>
        {
            ["uid"] = StringVal(session.Uid),
            ["email"] = StringVal(session.Email),
            ["displayName"] = StringVal(session.DisplayName),
            ["photoURL"] = StringVal(session.PhotoUrl),
            ["lastDateKey"] = StringVal(evt.DateKey),
            ["appVersion"] = StringVal(evt.AppVersion),
            ["osVersion"] = StringVal(evt.OsVersion),
            ["lastEventType"] = StringVal(evt.EventType)
        };

        var userTransforms = new List<object>
        {
            new { fieldPath = "lastSeenAt", setToServerValue = "REQUEST_TIME" },
            new { fieldPath = "lastLoginAt", setToServerValue = "REQUEST_TIME" }
        };
        if (userExists)
        {
            userTransforms.Add(new { fieldPath = "loginCount", increment = new { integerValue = "1" } });
        }
        else
        {
            userTransforms.Add(new { fieldPath = "firstSeenAt", setToServerValue = "REQUEST_TIME" });
            userFields["loginCount"] = new { integerValue = "1" };
        }

        var userWrite = new
        {
            update = new
            {
                name = userDocName,
                fields = userFields
            },
            updateTransforms = userTransforms
        };

        var eventFields = new Dictionary<string, object>
        {
            ["uid"] = StringVal(session.Uid),
            ["email"] = StringVal(session.Email),
            ["displayName"] = StringVal(session.DisplayName),
            ["photoURL"] = StringVal(session.PhotoUrl),
            ["dateKey"] = StringVal(evt.DateKey),
            ["appVersion"] = StringVal(evt.AppVersion),
            ["osVersion"] = StringVal(evt.OsVersion),
            ["eventType"] = StringVal(evt.EventType)
        };

        var eventWrite = new
        {
            update = new
            {
                name = eventDocName,
                fields = eventFields
            },
            updateTransforms = new object[]
            {
                new { fieldPath = "createdAt", setToServerValue = "REQUEST_TIME" }
            }
        };

        return new
        {
            writes = new object[] { userWrite, eventWrite }
        };
    }

    private static object StringVal(string? value) => new { stringValue = value ?? "" };
}

public sealed class FirebaseAuthService
{
    public static FirebaseAuthService Shared { get; } = new();

    private readonly FirebaseClientConfig _config = FirebaseClientConfig.BuiltInDefault;
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(20) };
    private readonly string _sessionPath;
    private readonly string _pendingQueuePath;
    private readonly List<AnalyticsTelemetryEvent> _pendingQueue = [];
    private readonly SemaphoreSlim _syncLock = new(1, 1);

    private static readonly JsonSerializerOptions JsonOpts = new() { WriteIndented = true };

    public FirebaseUserSession? CurrentSession { get; private set; }
    public bool IsSignedIn => CurrentSession != null && !string.IsNullOrEmpty(CurrentSession.Uid);
    public string? LastAnalyticsError { get; private set; }
    public DateTimeOffset? LastAnalyticsSuccessAt { get; private set; }

    public event Action? StateChanged;

    public FirebaseAuthService(string? customDataDir = null)
    {
        var dir = customDataDir ?? AppPaths.DataDirectory;
        Directory.CreateDirectory(dir);
        _sessionPath = Path.Combine(dir, "auth-session.bin");
        _pendingQueuePath = Path.Combine(dir, "pending-analytics.bin");
        LoadSession();
        LoadPendingQueue();
    }

    public async Task InitializeAsync()
    {
        if (!IsSignedIn) return;
        EnqueueEvent("app_launch");
        await FlushPendingEventsAsync();
    }

    public async Task<(bool Success, string? Error)> SignInWithGoogleAsync(CancellationToken ct = default)
    {
        try
        {
            var port = FindAvailableLoopbackPort();
            var state = GenerateStateToken();
            var authUrl = $"{_config.AuthPageUrl}?port={port}&state={Uri.EscapeDataString(state)}";

            using var listener = new HttpListener();
            listener.Prefixes.Add($"http://127.0.0.1:{port}/");
            listener.Start();

            Process.Start(new ProcessStartInfo(authUrl) { UseShellExecute = true });

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromMinutes(4));

            Dictionary<string, string>? callbackParams = null;
            while (!timeoutCts.IsCancellationRequested)
            {
                var getContextTask = listener.GetContextAsync();
                var completed = await Task.WhenAny(getContextTask, Task.Delay(Timeout.Infinite, timeoutCts.Token));
                if (completed != getContextTask)
                {
                    return (false, "Sign-in timed out. Please try again.");
                }

                var ctx = await getContextTask;
                var reqUrl = ctx.Request.Url;
                var query = reqUrl != null ? HttpUtility.ParseQueryString(reqUrl.Query) : null;

                if (reqUrl?.AbsolutePath == "/oauth2/callback" || (query != null && (query["id_token"] != null || query["access_token"] != null || query["error"] != null)))
                {
                    var respHtml = """
                        <!doctype html><html><head><meta charset="utf-8"><title>LoopSearch Sign-In</title>
                        <style>body{background:#090e1a;color:#eef4ff;font-family:-apple-system,Segoe UI,sans-serif;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
                        .card{background:rgba(20,30,52,.86);border:1px solid rgba(110,185,255,.28);border-radius:18px;padding:28px 34px;text-align:center;max-width:380px}
                        h2{margin:0 0 8px;font-size:19px}p{margin:0;color:#9eb5d9;font-size:13.5px}</style></head>
                        <body><div class="card"><h2>Signed in to LoopSearch</h2><p>You can close this browser tab and return to LoopSearch.</p></div></body></html>
                        """;
                    var buf = Encoding.UTF8.GetBytes(respHtml);
                    ctx.Response.ContentType = "text/html; charset=utf-8";
                    ctx.Response.ContentLength64 = buf.Length;
                    await ctx.Response.OutputStream.WriteAsync(buf);
                    ctx.Response.Close();

                    callbackParams = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    if (query != null)
                    {
                        foreach (string? k in query.AllKeys)
                        {
                            if (k != null) callbackParams[k] = query[k] ?? "";
                        }
                    }
                    break;
                }
                else
                {
                    ctx.Response.StatusCode = 204;
                    ctx.Response.Close();
                }
            }

            if (callbackParams == null)
                return (false, "Sign-in was cancelled.");

            if (callbackParams.TryGetValue("error", out var err) && !string.IsNullOrEmpty(err))
                return (false, err);

            if (!callbackParams.TryGetValue("state", out var returnedState) || returnedState != state)
                return (false, "OAuth state mismatch. Please retry.");

            callbackParams.TryGetValue("id_token", out var googleIdToken);
            callbackParams.TryGetValue("access_token", out var googleAccessToken);

            var session = await ExchangeGoogleTokenWithFirebaseAsync(googleIdToken, googleAccessToken);
            if (session == null)
                return (false, "Could not verify Google account with Firebase.");

            CurrentSession = session;
            SaveSession();
            EnqueueEvent("interactive_sign_in");
            StateChanged?.Invoke();

            _ = Task.Run(() => FlushPendingEventsAsync());
            return (true, null);
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    public void SignOut()
    {
        CurrentSession = null;
        try { if (File.Exists(_sessionPath)) File.Delete(_sessionPath); } catch { }
        StateChanged?.Invoke();
    }

    public void EnqueueEvent(string eventType)
    {
        lock (_pendingQueue)
        {
            _pendingQueue.Add(new AnalyticsTelemetryEvent { EventType = eventType });
            if (_pendingQueue.Count > 25)
                _pendingQueue.RemoveRange(0, _pendingQueue.Count - 25);
            SavePendingQueue();
        }
    }

    public async Task FlushPendingEventsAsync()
    {
        if (!IsSignedIn) return;
        await _syncLock.WaitAsync();
        try
        {
            if (CurrentSession == null) return;
            if (!CurrentSession.IsTokenFresh)
            {
                var refreshed = await RefreshIdTokenAsync(CurrentSession);
                if (!refreshed) return;
            }

            List<AnalyticsTelemetryEvent> snapshot;
            lock (_pendingQueue)
            {
                if (_pendingQueue.Count == 0) return;
                snapshot = [.. _pendingQueue];
            }

            foreach (var evt in snapshot)
            {
                var ok = await CommitSingleEventAsync(CurrentSession!, evt);
                if (ok)
                {
                    lock (_pendingQueue)
                    {
                        _pendingQueue.RemoveAll(e => e.Id == evt.Id);
                        SavePendingQueue();
                    }
                    LastAnalyticsSuccessAt = DateTimeOffset.UtcNow;
                    LastAnalyticsError = null;
                }
                else
                {
                    break;
                }
            }
            StateChanged?.Invoke();
        }
        finally
        {
            _syncLock.Release();
        }
    }

    private async Task<FirebaseUserSession?> ExchangeGoogleTokenWithFirebaseAsync(string? idToken, string? accessToken)
    {
        var parts = new List<string>();
        if (!string.IsNullOrEmpty(idToken)) parts.Add($"id_token={Uri.EscapeDataString(idToken)}");
        if (!string.IsNullOrEmpty(accessToken)) parts.Add($"access_token={Uri.EscapeDataString(accessToken)}");
        parts.Add("providerId=google.com");

        var payload = new
        {
            postBody = string.Join("&", parts),
            requestUri = _config.AuthRequestUri,
            returnIdpCredential = true,
            returnSecureToken = true
        };

        var url = $"https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key={_config.ApiKey}";
        using var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        using var resp = await _http.PostAsync(url, content);
        var body = await resp.Content.ReadAsStringAsync();
        if (!resp.IsSuccessStatusCode) return null;

        using var doc = JsonDocument.Parse(body);
        var root = doc.RootElement;
        var expiresIn = int.TryParse(root.TryGetProperty("expiresIn", out var exp) ? exp.GetString() : "3600", out var sec) ? sec : 3600;

        return new FirebaseUserSession
        {
            Uid = root.TryGetProperty("localId", out var uidEl) ? uidEl.GetString() ?? "" : "",
            Email = root.TryGetProperty("email", out var emEl) ? emEl.GetString() ?? "" : "",
            DisplayName = root.TryGetProperty("displayName", out var dnEl) ? dnEl.GetString() ?? "" : "",
            PhotoUrl = root.TryGetProperty("photoUrl", out var phEl) ? phEl.GetString() ?? "" : "",
            IdToken = root.TryGetProperty("idToken", out var idEl) ? idEl.GetString() ?? "" : "",
            RefreshToken = root.TryGetProperty("refreshToken", out var rfEl) ? rfEl.GetString() ?? "" : "",
            ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(expiresIn)
        };
    }

    private async Task<bool> RefreshIdTokenAsync(FirebaseUserSession session)
    {
        if (string.IsNullOrEmpty(session.RefreshToken)) return false;
        try
        {
            var url = $"https://securetoken.googleapis.com/v1/token?key={_config.ApiKey}";
            using var form = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["grant_type"] = "refresh_token",
                ["refresh_token"] = session.RefreshToken
            });
            using var resp = await _http.PostAsync(url, form);
            if (!resp.IsSuccessStatusCode) return false;

            using var doc = JsonDocument.Parse(await resp.Content.ReadAsStringAsync());
            var root = doc.RootElement;
            if (root.TryGetProperty("id_token", out var idEl))
                session.IdToken = idEl.GetString() ?? session.IdToken;
            if (root.TryGetProperty("refresh_token", out var rfEl))
                session.RefreshToken = rfEl.GetString() ?? session.RefreshToken;
            var expiresIn = int.TryParse(root.TryGetProperty("expires_in", out var expEl) ? expEl.GetString() : "3600", out var sec) ? sec : 3600;
            session.ExpiresAt = DateTimeOffset.UtcNow.AddSeconds(expiresIn);
            SaveSession();
            return true;
        }
        catch
        {
            return false;
        }
    }

    private async Task<bool> CommitSingleEventAsync(FirebaseUserSession session, AnalyticsTelemetryEvent evt)
    {
        try
        {
            bool userExists = false;
            using (var getReq = new HttpRequestMessage(HttpMethod.Get, _config.UserDocumentUrl(session.Uid)))
            {
                getReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.IdToken);
                using var getResp = await _http.SendAsync(getReq);
                userExists = getResp.IsSuccessStatusCode;
            }

            var payload = FirestorePayloadBuilder.BuildCommitPayload(_config, session, evt, userExists);
            using var req = new HttpRequestMessage(HttpMethod.Post, _config.FirestoreCommitUrl);
            req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", session.IdToken);
            req.Content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

            using var resp = await _http.SendAsync(req);
            if (!resp.IsSuccessStatusCode)
            {
                LastAnalyticsError = $"HTTP {(int)resp.StatusCode}";
                return false;
            }
            return true;
        }
        catch (Exception ex)
        {
            LastAnalyticsError = ex.Message;
            return false;
        }
    }

    private void LoadSession()
    {
        try
        {
            if (!File.Exists(_sessionPath)) return;
            var protectedBytes = File.ReadAllBytes(_sessionPath);
            var plain = PrivateDataProtector.UnprotectBytes(protectedBytes);
            CurrentSession = JsonSerializer.Deserialize<FirebaseUserSession>(Encoding.UTF8.GetString(plain));
        }
        catch
        {
            CurrentSession = null;
        }
    }

    private void SaveSession()
    {
        try
        {
            if (CurrentSession == null) return;
            var json = JsonSerializer.Serialize(CurrentSession, JsonOpts);
            var protectedBytes = PrivateDataProtector.ProtectBytes(Encoding.UTF8.GetBytes(json));
            File.WriteAllBytes(_sessionPath, protectedBytes);
        }
        catch { }
    }

    private void LoadPendingQueue()
    {
        try
        {
            if (!File.Exists(_pendingQueuePath)) return;
            var protectedBytes = File.ReadAllBytes(_pendingQueuePath);
            var plain = PrivateDataProtector.UnprotectBytes(protectedBytes);
            var items = JsonSerializer.Deserialize<List<AnalyticsTelemetryEvent>>(Encoding.UTF8.GetString(plain));
            if (items != null) _pendingQueue.AddRange(items);
        }
        catch { }
    }

    private void SavePendingQueue()
    {
        try
        {
            var json = JsonSerializer.Serialize(_pendingQueue, JsonOpts);
            var protectedBytes = PrivateDataProtector.ProtectBytes(Encoding.UTF8.GetBytes(json));
            File.WriteAllBytes(_pendingQueuePath, protectedBytes);
        }
        catch { }
    }

    public static int FindAvailableLoopbackPort()
    {
        using var tcp = new TcpListener(IPAddress.Loopback, 0);
        tcp.Start();
        return ((IPEndPoint)tcp.LocalEndpoint).Port;
    }

    public static string GenerateStateToken()
    {
        var bytes = RandomNumberGenerator.GetBytes(24);
        return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
    }
}
