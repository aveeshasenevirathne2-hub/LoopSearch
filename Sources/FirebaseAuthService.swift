import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Network
import Security

extension Notification.Name {
    static let loopSearchAuthChanged = Notification.Name("LoopSearchAuthStateChanged")
}

struct FirebaseAuthConfig: Equatable {
    var apiKey: String
    var projectID: String
    var databaseID: String
    var googleClientID: String
    var googleClientSecret: String
    var reversedClientScheme: String
    var authPageURL: String = ""

    var effectiveDatabaseID: String {
        let trimmed = databaseID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(default)" : trimmed
    }

    var isConfigured: Bool {
        let baseValid = !apiKey.isEmpty
            && !projectID.isEmpty
            && !Self.isPlaceholder(apiKey)
            && !Self.isPlaceholder(projectID)
        guard baseValid else { return false }

        let hasAuthBridge = !authPageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasDirectOAuth = !googleClientID.isEmpty && !Self.isPlaceholder(googleClientID)
        return hasAuthBridge || hasDirectOAuth
    }

    var shouldUseHostedBridgeFlow: Bool {
        !authPageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && googleClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var authRequestURI: String {
        if let url = URL(string: authPageURL),
           let scheme = url.scheme,
           let host = url.host,
           !scheme.isEmpty,
           !host.isEmpty {
            return "\(scheme)://\(host)"
        }
        return "http://localhost"
    }

    var shouldUseCustomSchemeFlow: Bool {
        let scheme = reversedClientScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty, googleClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return Self.bundleRegistersURLScheme(scheme)
    }

    /// Out-of-the-box public Firebase project configuration for hosted Google Sign-In.
    /// Contains no personal credentials or OAuth secrets; security is enforced by Firestore Rules.
    static let builtInDefault = FirebaseAuthConfig(
        apiKey: "AIzaSyD67B6MnCvLwYB5xLQVH3IQdguetSe-Koc",
        projectID: "loopsearch-analytics-78e3",
        databaseID: "(default)",
        googleClientID: "",
        googleClientSecret: "",
        reversedClientScheme: "",
        authPageURL: "https://loopsearch-analytics-78e3.web.app/app-auth.html"
    )

    static let empty = FirebaseAuthConfig(
        apiKey: "",
        projectID: "",
        databaseID: "(default)",
        googleClientID: "",
        googleClientSecret: "",
        reversedClientScheme: "",
        authPageURL: ""
    )

    static var localOverrideURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport
            .appendingPathComponent("LoopSearch", isDirectory: true)
            .appendingPathComponent("FirebaseConfig.plist")
    }

    static func load() -> FirebaseAuthConfig {
        if let local = load(from: localOverrideURL), local.isConfigured {
            return local
        }
        if let bundleURL = Bundle.main.url(forResource: "FirebaseConfig", withExtension: "plist"),
           let bundled = load(from: bundleURL),
           bundled.isConfigured {
            return bundled
        }
        return .builtInDefault
    }

    static func load(from url: URL) -> FirebaseAuthConfig? {
        guard let data = try? Data(contentsOf: url),
              let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }

        func clean(_ key: String) -> String {
            (raw[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let db = clean("DatabaseID")
        return FirebaseAuthConfig(
            apiKey: clean("APIKey"),
            projectID: clean("ProjectID"),
            databaseID: db.isEmpty ? "(default)" : db,
            googleClientID: clean("GoogleClientID"),
            googleClientSecret: clean("GoogleClientSecret"),
            reversedClientScheme: clean("ReversedClientScheme"),
            authPageURL: clean("AuthPageURL")
        )
    }

    static func saveLocalOverride(_ config: FirebaseAuthConfig) throws {
        let url = localOverrideURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dict: [String: String] = [
            "APIKey": config.apiKey,
            "ProjectID": config.projectID,
            "DatabaseID": config.effectiveDatabaseID,
            "GoogleClientID": config.googleClientID,
            "GoogleClientSecret": config.googleClientSecret,
            "ReversedClientScheme": config.reversedClientScheme,
            "AuthPageURL": config.authPageURL
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let upper = value.uppercased()
        return upper.hasPrefix("YOUR_") || upper.contains("<PROJECT") || upper.contains("REPLACE_ME")
    }

    private static func bundleRegistersURLScheme(_ scheme: String) -> Bool {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return false
        }
        let target = scheme.lowercased()
        for entry in urlTypes {
            if let schemes = entry["CFBundleURLSchemes"] as? [String],
               schemes.contains(where: { $0.lowercased() == target }) {
                return true
            }
        }
        return false
    }
}

struct FirebaseUserSession: Codable, Equatable {
    let uid: String
    var email: String
    var displayName: String
    var photoURL: String
    var idToken: String
    var refreshToken: String
    var expiresAt: Date
    var lastRecordedAt: Date?

    var isTokenExpiringSoon: Bool {
        Date().addingTimeInterval(300) >= expiresAt
    }

    var effectiveDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !email.isEmpty { return email.components(separatedBy: "@").first ?? email }
        return "Google User"
    }

    var initials: String {
        let parts = effectiveDisplayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let joined = String(parts).uppercased()
        return joined.isEmpty ? "G" : joined
    }
}

// Stores the signed-in session via PrivateAppSupportVault (AES-GCM encrypted, 0o600)
// instead of the legacy login Keychain, preventing macOS password prompts across ad-hoc updates.
private enum AuthSessionStorage {
    private static let fileName = "auth-session.bin"

    static func save(_ session: FirebaseUserSession) {
        guard let plaintext = try? JSONEncoder().encode(session) else { return }
        PrivateAppSupportVault.saveEncrypted(plaintext, fileName: fileName)
    }

    static func load() -> FirebaseUserSession? {
        guard let plaintext = PrivateAppSupportVault.loadEncrypted(fileName: fileName) else { return nil }
        return try? JSONDecoder().decode(FirebaseUserSession.self, from: plaintext)
    }

    static func clear() {
        PrivateAppSupportVault.remove(fileName: fileName)
    }
}

private struct PendingTelemetryEvent: Codable, Equatable {
    let id: String
    let uid: String
    let eventType: String
    let dateKey: String
    let appVersion: String
    let osVersion: String
}

private enum PendingTelemetryStorage {
    private static let maxQueuedEvents = 50

    private static var queueFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LoopSearch", isDirectory: true)
            .appendingPathComponent("pending-telemetry.json")
    }

    static func load() -> [PendingTelemetryEvent] {
        guard let data = try? Data(contentsOf: queueFileURL),
              let decoded = try? JSONDecoder().decode([PendingTelemetryEvent].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ events: [PendingTelemetryEvent]) {
        let dir = queueFileURL.deletingLastPathComponent()
        if events.isEmpty {
            try? FileManager.default.removeItem(at: queueFileURL)
            return
        }
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: queueFileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: queueFileURL.path)
    }

    static func enqueue(_ event: PendingTelemetryEvent) {
        var existing = load()
        guard !existing.contains(where: { $0.id == event.id }) else { return }
        existing.append(event)
        if existing.count > maxQueuedEvents {
            existing = Array(existing.suffix(maxQueuedEvents))
        }
        save(existing)
    }

    static func remove(id: String) {
        let remaining = load().filter { $0.id != id }
        save(remaining)
    }

    static func clear(for uid: String? = nil) {
        guard let uid else {
            save([])
            return
        }
        save(load().filter { $0.uid != uid })
    }
}

private struct PKCEChallenge {
    let codeVerifier: String
    let codeChallenge: String
    let state: String

    init() {
        self.codeVerifier = Self.randomBase64URL(byteCount: 48)
        let hash = SHA256.hash(data: Data(codeVerifier.utf8))
        self.codeChallenge = Data(hash).base64URLEncodedString()
        self.state = Self.randomBase64URL(byteCount: 24)
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

enum AuthFlowError: LocalizedError {
    case notConfigured
    case cancelled
    case stateMismatch
    case missingAuthorizationCode
    case providerDenied(String)
    case httpError(Int, String)
    case invalidResponse(String)
    case listenerFailed(String)
    case sessionRevoked

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Firebase Sign-In is not configured yet. Add FirebaseConfig.plist to enable Google Sign-In."
        case .cancelled:
            return "Google Sign-In was cancelled."
        case .stateMismatch:
            return "OAuth security state verification failed. Please try signing in again."
        case .missingAuthorizationCode:
            return "Google did not return an authorization code."
        case .providerDenied(let msg):
            return "Google Sign-In declined: \(msg)"
        case .httpError(let code, let body):
            return "Authentication request failed (HTTP \(code)): \(body)"
        case .invalidResponse(let detail):
            return "Unexpected authentication response: \(detail)"
        case .listenerFailed(let detail):
            return "Could not start local OAuth callback listener: \(detail)"
        case .sessionRevoked:
            return "Your session expired or was revoked. Please sign in with Google again."
        }
    }
}

/// Ephemeral localhost (127.0.0.1) HTTP callback listener for Google Desktop OAuth PKCE flow.
private final class LoopbackOAuthServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.local.LoopSearch.oauthLoopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var activeConnections: [NWConnection] = []
    private var didResumeStart = false
    private var isSettled = false

    func startAndWaitForReady() async throws -> URL {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)

        let nwListener = try NWListener(using: params)
        self.listener = nwListener

        return try await withCheckedThrowingContinuation { cont in
            nwListener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard !self.didResumeStart else { return }
                    self.didResumeStart = true
                    if let port = nwListener.port?.rawValue,
                       let redirectURL = URL(string: "http://127.0.0.1:\(port)/oauth2/callback") {
                        cont.resume(returning: redirectURL)
                    } else {
                        cont.resume(throwing: AuthFlowError.listenerFailed("Missing bound loopback port."))
                    }
                case .failed(let error):
                    if !self.didResumeStart {
                        self.didResumeStart = true
                        cont.resume(throwing: AuthFlowError.listenerFailed(error.localizedDescription))
                    } else {
                        self.finishLocked(with: .failure(AuthFlowError.listenerFailed(error.localizedDescription)))
                    }
                case .cancelled:
                    if !self.didResumeStart {
                        self.didResumeStart = true
                        cont.resume(throwing: AuthFlowError.cancelled)
                    } else {
                        self.finishLocked(with: .failure(AuthFlowError.cancelled))
                    }
                default:
                    break
                }
            }

            nwListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            nwListener.start(queue: self.queue)
        }
    }

    func waitForCallback() async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: AuthFlowError.cancelled)
                    return
                }
                if self.isSettled {
                    cont.resume(throwing: AuthFlowError.cancelled)
                    return
                }
                self.continuation = cont
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            self?.finishLocked(with: .failure(AuthFlowError.cancelled))
        }
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 32768) { [weak self] chunk, _, isComplete, _ in
            guard let self else { return }
            var combined = buffer
            if let chunk { combined.append(chunk) }

            if let headerEnd = combined.range(of: Data("\r\n\r\n".utf8)) {
                let headerText = String(data: combined[..<headerEnd.lowerBound], encoding: .utf8) ?? ""
                self.processHTTPRequest(headerText, on: connection)
                return
            }

            if combined.count > 32768 || isComplete {
                let headerText = String(data: combined, encoding: .utf8) ?? ""
                self.processHTTPRequest(headerText, on: connection)
                return
            }

            self.receiveRequest(on: connection, buffer: combined)
        }
    }

    private func processHTTPRequest(_ request: String, on connection: NWConnection) {
        let firstLine = request.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        let rawTarget = parts.count >= 2 ? String(parts[1]) : "/"

        // Browser may request /favicon.ico separately; answer 204 without settling the auth flow.
        if rawTarget.hasPrefix("/favicon.ico") {
            let emptyResp = "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(emptyResp.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let callbackURL = URL(string: "http://127.0.0.1\(rawTarget)")
        let items = callbackURL.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        let hasError = items.contains { $0.name == "error" }
        let html = Self.resultHTML(success: !hasError)
        let bodyData = Data(html.utf8)
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        var payload = Data(headers.utf8)
        payload.append(bodyData)

        connection.send(content: payload, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            guard let self else { return }
            if let callbackURL, rawTarget.contains("/oauth2/callback") {
                self.finish(with: .success(callbackURL))
            } else {
                self.finish(with: .failure(AuthFlowError.missingAuthorizationCode))
            }
        })
    }

    private func finish(with result: Result<URL, Error>) {
        queue.async { [weak self] in
            self?.finishLocked(with: result)
        }
    }

    private func finishLocked(with result: Result<URL, Error>) {
        guard !isSettled else { return }
        isSettled = true

        let cont = continuation
        continuation = nil

        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        for conn in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()

        cont?.resume(with: result)
    }

    private static func resultHTML(success: Bool) -> String {
        let title = success ? "Signed in to LoopSearch" : "Sign-In Not Completed"
        let subtitle = success
            ? "You can close this tab and return to LoopSearch."
            : "Google Sign-In did not complete. Return to LoopSearch to try again."
        let accent = success ? "#38bdf8" : "#fb923c"
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8" />
        <title>\(title)</title>
        <style>
          body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
                 background:#060a14; color:#eef4ff; font-family:-apple-system,BlinkMacSystemFont,sans-serif; }
          .card { max-width:420px; padding:32px; border-radius:22px; text-align:center;
                  background:rgba(16,24,42,0.88); border:1px solid rgba(110,180,255,0.22);
                  box-shadow:0 24px 60px rgba(0,0,0,0.55); }
          .dot { width:14px; height:14px; border-radius:50%; background:\(accent);
                 margin:0 auto 16px; box-shadow:0 0 18px \(accent); }
          h1 { margin:0 0 8px; font-size:20px; font-weight:700; }
          p { margin:0; color:#9bb0d0; font-size:14px; line-height:1.5; }
        </style>
        </head>
        <body>
          <div class="card">
            <div class="dot"></div>
            <h1>\(title)</h1>
            <p>\(subtitle)</p>
          </div>
          <script>setTimeout(function(){ window.close(); }, 1600);</script>
        </body>
        </html>
        """
    }
}

@MainActor
private final class AuthWindowAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthWindowAnchorProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) ?? ASPresentationAnchor()
    }
}

@MainActor
final class FirebaseAuthService {
    static let shared = FirebaseAuthService()

    private(set) var config: FirebaseAuthConfig
    private(set) var session: FirebaseUserSession?
    private(set) var isSigningIn = false
    private(set) var lastAuthError: String?
    private(set) var avatarImage: NSImage?

    private var activeLoopbackServer: LoopbackOAuthServer?
    private var activeWebAuthSession: ASWebAuthenticationSession?
    private var hasSyncedThisLaunch = false
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "com.local.LoopSearch.auth.network")
    private var isFlushingTelemetry = false

    var isConfigured: Bool { config.isConfigured }
    var isSignedIn: Bool { session != nil }

    private init() {
        self.config = FirebaseAuthConfig.load()
        self.session = AuthSessionStorage.load()
        if let photoURL = session?.photoURL, !photoURL.isEmpty {
            loadAvatarIfNeeded(from: photoURL)
        }
        startNetworkRecoveryMonitor()
    }

    private func startNetworkRecoveryMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.flushPendingTelemetryIfNeeded()
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    func reloadConfig() {
        config = FirebaseAuthConfig.load()
        notifyAuthChanged()
    }

    func installConfigOverride(_ newConfig: FirebaseAuthConfig) throws {
        try FirebaseAuthConfig.saveLocalOverride(newConfig)
        config = FirebaseAuthConfig.load()
        lastAuthError = nil
        notifyAuthChanged()
    }

    func installConfigFile(at sourceURL: URL) throws {
        guard let parsed = FirebaseAuthConfig.load(from: sourceURL), parsed.isConfigured else {
            throw AuthFlowError.invalidResponse("Selected plist is missing APIKey, ProjectID, or GoogleClientID.")
        }
        try installConfigOverride(parsed)
    }

    func restoreAndSyncOnLaunch() async {
        guard config.isConfigured, var active = session else { return }
        do {
            active = try await ensureFreshIDToken(for: active)
            if !hasSyncedThisLaunch {
                hasSyncedThisLaunch = true
                await syncOrQueueLoginTelemetry(session: active, eventType: "session_resume")
            }
            await flushPendingTelemetryIfNeeded()
        } catch AuthFlowError.sessionRevoked {
            signOut(errorMessage: AuthFlowError.sessionRevoked.localizedDescription)
        } catch {
            // Keep existing local session on transient offline startup and queue resume telemetry once per launch.
            if !hasSyncedThisLaunch {
                hasSyncedThisLaunch = true
                enqueueTelemetryEvent(uid: active.uid, eventType: "session_resume")
            }
        }
    }

    @discardableResult
    func signInWithGoogle() async -> Bool {
        guard !isSigningIn else { return false }
        config = FirebaseAuthConfig.load()
        guard config.isConfigured else {
            lastAuthError = AuthFlowError.notConfigured.localizedDescription
            notifyAuthChanged()
            return false
        }

        isSigningIn = true
        lastAuthError = nil
        notifyAuthChanged()

        defer {
            isSigningIn = false
            activeLoopbackServer = nil
            activeWebAuthSession = nil
            notifyAuthChanged()
        }

        do {
            let pkce = PKCEChallenge()
            var signedSession: FirebaseUserSession

            if config.shouldUseHostedBridgeFlow {
                signedSession = try await signInViaHostedBridge(state: pkce.state)
            } else {
                let (callbackURL, redirectURI): (URL, String)
                if config.shouldUseCustomSchemeFlow {
                    let scheme = config.reversedClientScheme
                    let rURI = "\(scheme):/oauth2redirect"
                    let authURL = try buildGoogleAuthURL(redirectURI: rURI, pkce: pkce)
                    callbackURL = try await runCustomSchemeSession(authURL: authURL, scheme: scheme)
                    redirectURI = rURI
                } else {
                    let server = LoopbackOAuthServer()
                    activeLoopbackServer = server
                    let redirectURL = try await server.startAndWaitForReady()
                    redirectURI = redirectURL.absoluteString
                    let authURL = try buildGoogleAuthURL(redirectURI: redirectURI, pkce: pkce)
                    NSWorkspace.shared.open(authURL)
                    callbackURL = try await waitWithTimeout(seconds: 300, onTimeout: {
                        server.cancel()
                    }) {
                        try await server.waitForCallback()
                    }
                }

                let code = try extractVerifiedAuthCode(from: callbackURL, expectedState: pkce.state)
                let googleIDToken = try await exchangeCodeForGoogleIDToken(
                    code: code,
                    redirectURI: redirectURI,
                    codeVerifier: pkce.codeVerifier
                )
                signedSession = try await signInToFirebase(
                    idpPostBody: "id_token=\(Self.urlComponentEncode(googleIDToken))&providerId=google.com",
                    requestURI: "http://localhost"
                )
            }

            if signedSession.email.isEmpty || signedSession.displayName.isEmpty {
                if let profile = try? await lookupFirebaseProfile(idToken: signedSession.idToken) {
                    if !profile.email.isEmpty { signedSession.email = profile.email }
                    if !profile.displayName.isEmpty { signedSession.displayName = profile.displayName }
                    if !profile.photoURL.isEmpty { signedSession.photoURL = profile.photoURL }
                }
            }
            signedSession.lastRecordedAt = Date()

            AuthSessionStorage.save(signedSession)
            self.session = signedSession
            self.hasSyncedThisLaunch = true
            self.loadAvatarIfNeeded(from: signedSession.photoURL)
            notifyAuthChanged()

            NSApp.activate(ignoringOtherApps: true)

            // Record interactive login in Firestore (or queue locally if connectivity drops right after OAuth).
            let capturedSession = signedSession
            Task { [weak self] in
                await self?.syncOrQueueLoginTelemetry(session: capturedSession, eventType: "interactive_sign_in")
                await self?.flushPendingTelemetryIfNeeded()
            }
            return true
        } catch AuthFlowError.cancelled {
            lastAuthError = nil
            return false
        } catch {
            lastAuthError = error.localizedDescription
            return false
        }
    }

    func cancelSignIn() {
        activeLoopbackServer?.cancel()
        activeWebAuthSession?.cancel()
        isSigningIn = false
        notifyAuthChanged()
    }

    func signOut(errorMessage: String? = nil) {
        let uid = session?.uid
        AuthSessionStorage.clear()
        PendingTelemetryStorage.clear(for: uid)
        session = nil
        avatarImage = nil
        hasSyncedThisLaunch = false
        lastAuthError = errorMessage
        notifyAuthChanged()
    }

    private func notifyAuthChanged() {
        NotificationCenter.default.post(name: .loopSearchAuthChanged, object: nil)
    }

    private func loadAvatarIfNeeded(from urlString: String) {
        guard let url = URL(string: urlString), url.scheme == "https" else { return }
        Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = NSImage(data: data) {
                    self?.avatarImage = image
                    self?.notifyAuthChanged()
                }
            } catch {
                // Non-fatal; fallback monogram renders automatically.
            }
        }
    }

    // MARK: - Google OAuth PKCE

    private func buildGoogleAuthURL(redirectURI: String, pkce: PKCEChallenge) throws -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.googleClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = components.url else {
            throw AuthFlowError.invalidResponse("Failed to construct Google OAuth URL.")
        }
        return url
    }

    private func runCustomSchemeSession(authURL: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            let webSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: scheme
            ) { url, error in
                if let url {
                    cont.resume(returning: url)
                } else if let nsErr = error as NSError?,
                          nsErr.domain == ASWebAuthenticationSessionErrorDomain,
                          nsErr.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    cont.resume(throwing: AuthFlowError.cancelled)
                } else {
                    cont.resume(throwing: error ?? AuthFlowError.cancelled)
                }
            }
            webSession.presentationContextProvider = AuthWindowAnchorProvider.shared
            webSession.prefersEphemeralWebBrowserSession = false
            self.activeWebAuthSession = webSession
            if !webSession.start() {
                cont.resume(throwing: AuthFlowError.listenerFailed("ASWebAuthenticationSession refused to start."))
            }
        }
    }

    private func waitWithTimeout<T: Sendable>(
        seconds: TimeInterval,
        onTimeout: @escaping @Sendable () -> Void,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                onTimeout()
                throw AuthFlowError.cancelled
            }
            guard let first = try await group.next() else {
                throw AuthFlowError.cancelled
            }
            group.cancelAll()
            return first
        }
    }

    private func extractVerifiedAuthCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
            throw AuthFlowError.invalidResponse("Callback URL contained no parameters.")
        }
        if let err = items.first(where: { $0.name == "error" })?.value {
            if err == "access_denied" { throw AuthFlowError.cancelled }
            throw AuthFlowError.providerDenied(err)
        }
        let returnedState = items.first(where: { $0.name == "state" })?.value ?? ""
        guard !returnedState.isEmpty, returnedState == expectedState else {
            throw AuthFlowError.stateMismatch
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw AuthFlowError.missingAuthorizationCode
        }
        return code
    }

    private func exchangeCodeForGoogleIDToken(
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) async throws -> String {
        var params: [(String, String)] = [
            ("code", code),
            ("client_id", config.googleClientID),
            ("redirect_uri", redirectURI),
            ("code_verifier", codeVerifier),
            ("grant_type", "authorization_code")
        ]
        if !config.googleClientSecret.isEmpty {
            params.append(("client_secret", config.googleClientSecret))
        }

        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formURLEncode(params)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw AuthFlowError.httpError(status, msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String,
              !idToken.isEmpty else {
            throw AuthFlowError.invalidResponse("Google token response missing id_token.")
        }
        return idToken
    }

    // MARK: - Hosted Firebase Auth Bridge & Identity Toolkit

    private func signInViaHostedBridge(state: String) async throws -> FirebaseUserSession {
        let server = LoopbackOAuthServer()
        activeLoopbackServer = server
        let redirectURL = try await server.startAndWaitForReady()
        guard let port = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)?.port else {
            throw AuthFlowError.listenerFailed("Missing bound loopback port.")
        }

        guard var bridgeComponents = URLComponents(string: config.authPageURL) else {
            throw AuthFlowError.invalidResponse("Invalid AuthPageURL.")
        }
        var queryItems = bridgeComponents.queryItems ?? []
        queryItems.append(URLQueryItem(name: "port", value: String(port)))
        queryItems.append(URLQueryItem(name: "state", value: state))
        bridgeComponents.queryItems = queryItems

        guard let bridgeURL = bridgeComponents.url else {
            throw AuthFlowError.invalidResponse("Failed to construct sign-in URL.")
        }

        NSWorkspace.shared.open(bridgeURL)
        let callbackURL = try await waitWithTimeout(seconds: 300, onTimeout: {
            server.cancel()
        }) {
            try await server.waitForCallback()
        }

        guard let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
            throw AuthFlowError.invalidResponse("Callback URL contained no parameters.")
        }
        if let err = items.first(where: { $0.name == "error" })?.value {
            if err == "access_denied" || err == "cancelled" { throw AuthFlowError.cancelled }
            throw AuthFlowError.providerDenied(err)
        }
        let returnedState = items.first(where: { $0.name == "state" })?.value ?? ""
        guard !returnedState.isEmpty, returnedState == state else {
            throw AuthFlowError.stateMismatch
        }

        if let idToken = items.first(where: { $0.name == "id_token" })?.value, !idToken.isEmpty {
            return try await signInToFirebase(
                idpPostBody: "id_token=\(Self.urlComponentEncode(idToken))&providerId=google.com",
                requestURI: config.authRequestURI
            )
        }
        if let accessToken = items.first(where: { $0.name == "access_token" })?.value, !accessToken.isEmpty {
            return try await signInToFirebase(
                idpPostBody: "access_token=\(Self.urlComponentEncode(accessToken))&providerId=google.com",
                requestURI: config.authRequestURI
            )
        }
        if let refreshToken = items.first(where: { $0.name == "refresh_token" })?.value, !refreshToken.isEmpty {
            return try await signInWithFirebaseRefreshToken(refreshToken)
        }
        throw AuthFlowError.missingAuthorizationCode
    }

    private func signInToFirebase(idpPostBody: String, requestURI: String) async throws -> FirebaseUserSession {
        let endpoint = "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=\(config.apiKey)"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "postBody": idpPostBody,
            "requestUri": requestURI,
            "returnIdpCredential": true,
            "returnSecureToken": true
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let msg = Self.extractFirebaseErrorMessage(from: data) ?? "HTTP \(status)"
            throw AuthFlowError.httpError(status, msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uid = json["localId"] as? String, !uid.isEmpty,
              let idToken = json["idToken"] as? String, !idToken.isEmpty,
              let refreshToken = json["refreshToken"] as? String, !refreshToken.isEmpty else {
            throw AuthFlowError.invalidResponse("Firebase signInWithIdp missing user credentials.")
        }

        let expiresIn = TimeInterval(json["expiresIn"] as? String ?? "3600") ?? 3600
        return FirebaseUserSession(
            uid: uid,
            email: json["email"] as? String ?? "",
            displayName: json["displayName"] as? String ?? json["fullName"] as? String ?? "",
            photoURL: json["photoUrl"] as? String ?? "",
            idToken: idToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(max(60, expiresIn)),
            lastRecordedAt: nil
        )
    }

    private func signInWithFirebaseRefreshToken(_ refreshToken: String) async throws -> FirebaseUserSession {
        let endpoint = "https://securetoken.googleapis.com/v1/token?key=\(config.apiKey)"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formURLEncode([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken)
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["id_token"] as? String, !idToken.isEmpty,
              let uid = json["user_id"] as? String, !uid.isEmpty else {
            let msg = Self.extractFirebaseErrorMessage(from: data) ?? "Token exchange failed (HTTP \(status))"
            throw AuthFlowError.httpError(status, msg)
        }

        let nextRefresh = (json["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
        let expiresIn = TimeInterval(json["expires_in"] as? String ?? "3600") ?? 3600
        let profile = try await lookupFirebaseProfile(idToken: idToken)
        return FirebaseUserSession(
            uid: uid,
            email: profile.email,
            displayName: profile.displayName,
            photoURL: profile.photoURL,
            idToken: idToken,
            refreshToken: nextRefresh,
            expiresAt: Date().addingTimeInterval(max(60, expiresIn)),
            lastRecordedAt: nil
        )
    }

    private func ensureFreshIDToken(for current: FirebaseUserSession) async throws -> FirebaseUserSession {
        guard current.isTokenExpiringSoon else { return current }

        let endpoint = "https://securetoken.googleapis.com/v1/token?key=\(config.apiKey)"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.formURLEncode([
            ("grant_type", "refresh_token"),
            ("refresh_token", current.refreshToken)
        ])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 || status == 403 {
            let errText = Self.extractFirebaseErrorMessage(from: data)?.uppercased() ?? ""
            if errText.contains("TOKEN_EXPIRED")
                || errText.contains("INVALID_REFRESH_TOKEN")
                || errText.contains("USER_DISABLED")
                || errText.contains("USER_NOT_FOUND") {
                throw AuthFlowError.sessionRevoked
            }
            throw AuthFlowError.httpError(status, errText)
        }
        guard (200...299).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newIDToken = json["id_token"] as? String, !newIDToken.isEmpty else {
            throw AuthFlowError.invalidResponse("Token refresh response invalid.")
        }

        var updated = current
        updated.idToken = newIDToken
        if let newRefresh = json["refresh_token"] as? String, !newRefresh.isEmpty {
            updated.refreshToken = newRefresh
        }
        let expiresIn = TimeInterval(json["expires_in"] as? String ?? "3600") ?? 3600
        updated.expiresAt = Date().addingTimeInterval(max(60, expiresIn))

        if let refreshedProfile = try? await lookupFirebaseProfile(idToken: newIDToken) {
            if !refreshedProfile.email.isEmpty { updated.email = refreshedProfile.email }
            if !refreshedProfile.displayName.isEmpty { updated.displayName = refreshedProfile.displayName }
            if !refreshedProfile.photoURL.isEmpty { updated.photoURL = refreshedProfile.photoURL }
        }

        AuthSessionStorage.save(updated)
        self.session = updated
        notifyAuthChanged()
        return updated
    }

    private func lookupFirebaseProfile(idToken: String) async throws -> (email: String, displayName: String, photoURL: String) {
        let endpoint = "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=\(config.apiKey)"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["idToken": idToken])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let users = json["users"] as? [[String: Any]],
              let first = users.first else {
            throw AuthFlowError.invalidResponse("accounts:lookup failed")
        }
        return (
            first["email"] as? String ?? "",
            first["displayName"] as? String ?? "",
            first["photoUrl"] as? String ?? ""
        )
    }

    // MARK: - Firestore REST Telemetry & Offline Queue

    private func makeTelemetryEvent(uid: String, eventType: String) -> PendingTelemetryEvent {
        let appVer = String((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.2").prefix(40))
        let osVerInfo = ProcessInfo.processInfo.operatingSystemVersion
        let osVer = String("macOS \(osVerInfo.majorVersion).\(osVerInfo.minorVersion).\(osVerInfo.patchVersion)".prefix(60))
        return PendingTelemetryEvent(
            id: UUID().uuidString.lowercased(),
            uid: uid,
            eventType: eventType,
            dateKey: Self.utcDateKey(),
            appVersion: appVer,
            osVersion: osVer
        )
    }

    private func enqueueTelemetryEvent(uid: String, eventType: String) {
        PendingTelemetryStorage.enqueue(makeTelemetryEvent(uid: uid, eventType: eventType))
    }

    private func syncOrQueueLoginTelemetry(session current: FirebaseUserSession, eventType: String) async {
        let event = makeTelemetryEvent(uid: current.uid, eventType: eventType)
        do {
            try await commitTelemetryEvent(event, session: current)
        } catch AuthFlowError.sessionRevoked {
            signOut(errorMessage: AuthFlowError.sessionRevoked.localizedDescription)
        } catch {
            PendingTelemetryStorage.enqueue(event)
        }
    }

    func flushPendingTelemetryIfNeeded() async {
        guard config.isConfigured, let active = session, !isFlushingTelemetry else { return }
        let pending = PendingTelemetryStorage.load().filter { $0.uid == active.uid }
        guard !pending.isEmpty else { return }

        isFlushingTelemetry = true
        defer { isFlushingTelemetry = false }

        for event in pending {
            guard let latestSession = self.session, latestSession.uid == event.uid else { break }
            do {
                try await commitTelemetryEvent(event, session: latestSession)
                PendingTelemetryStorage.remove(id: event.id)
            } catch AuthFlowError.sessionRevoked {
                signOut(errorMessage: AuthFlowError.sessionRevoked.localizedDescription)
                break
            } catch {
                // Still offline or transient server error; keep remaining events queued for next reconnect.
                break
            }
        }
    }

    private func commitTelemetryEvent(_ event: PendingTelemetryEvent, session current: FirebaseUserSession) async throws {
        let fresh = try await ensureFreshIDToken(for: current)
        let dbEncoded = Self.urlComponentEncode(config.effectiveDatabaseID)
        let uidEncoded = Self.urlComponentEncode(fresh.uid)
        let baseDocPath = "projects/\(config.projectID)/databases/\(config.effectiveDatabaseID)/documents"
        let baseURL = "https://firestore.googleapis.com/v1/projects/\(config.projectID)/databases/\(dbEncoded)/documents"

        let userExists = try await checkUserDocumentExists(
            url: URL(string: "\(baseURL)/users/\(uidEncoded)")!,
            idToken: fresh.idToken
        )

        let emailVal = String(fresh.email.prefix(320))
        let nameVal = String(fresh.effectiveDisplayName.prefix(200))
        let rawPhoto = fresh.photoURL
        let photoVal = (rawPhoto.hasPrefix("https://") || rawPhoto.hasPrefix("http://"))
            ? String(rawPhoto.prefix(2048))
            : ""

        let userWrite: [String: Any]
        if userExists {
            userWrite = [
                "update": [
                    "name": "\(baseDocPath)/users/\(fresh.uid)",
                    "fields": [
                        "uid": ["stringValue": fresh.uid],
                        "email": ["stringValue": emailVal],
                        "displayName": ["stringValue": nameVal],
                        "photoURL": ["stringValue": photoVal],
                        "lastDateKey": ["stringValue": event.dateKey],
                        "appVersion": ["stringValue": event.appVersion],
                        "osVersion": ["stringValue": event.osVersion],
                        "lastEventType": ["stringValue": event.eventType]
                    ]
                ],
                "updateMask": [
                    "fieldPaths": ["uid", "email", "displayName", "photoURL", "lastDateKey", "appVersion", "osVersion", "lastEventType"]
                ],
                "currentDocument": ["exists": true],
                "updateTransforms": [
                    ["fieldPath": "loginCount", "increment": ["integerValue": "1"]],
                    ["fieldPath": "lastSeenAt", "setToServerValue": "REQUEST_TIME"],
                    ["fieldPath": "lastLoginAt", "setToServerValue": "REQUEST_TIME"]
                ]
            ]
        } else {
            userWrite = [
                "update": [
                    "name": "\(baseDocPath)/users/\(fresh.uid)",
                    "fields": [
                        "uid": ["stringValue": fresh.uid],
                        "email": ["stringValue": emailVal],
                        "displayName": ["stringValue": nameVal],
                        "photoURL": ["stringValue": photoVal],
                        "lastDateKey": ["stringValue": event.dateKey],
                        "loginCount": ["integerValue": "1"],
                        "appVersion": ["stringValue": event.appVersion],
                        "osVersion": ["stringValue": event.osVersion],
                        "lastEventType": ["stringValue": event.eventType]
                    ]
                ],
                "currentDocument": ["exists": false],
                "updateTransforms": [
                    ["fieldPath": "firstSeenAt", "setToServerValue": "REQUEST_TIME"],
                    ["fieldPath": "lastSeenAt", "setToServerValue": "REQUEST_TIME"],
                    ["fieldPath": "lastLoginAt", "setToServerValue": "REQUEST_TIME"]
                ]
            ]
        }

        let eventWrite: [String: Any] = [
            "update": [
                "name": "\(baseDocPath)/loginEvents/\(event.id)",
                "fields": [
                    "uid": ["stringValue": fresh.uid],
                    "email": ["stringValue": emailVal],
                    "displayName": ["stringValue": nameVal],
                    "photoURL": ["stringValue": photoVal],
                    "dateKey": ["stringValue": event.dateKey],
                    "appVersion": ["stringValue": event.appVersion],
                    "osVersion": ["stringValue": event.osVersion],
                    "eventType": ["stringValue": event.eventType]
                ]
            ],
            "currentDocument": ["exists": false],
            "updateTransforms": [
                ["fieldPath": "createdAt", "setToServerValue": "REQUEST_TIME"]
            ]
        ]

        var commitReq = URLRequest(url: URL(string: "\(baseURL):commit")!)
        commitReq.httpMethod = "POST"
        commitReq.setValue("Bearer \(fresh.idToken)", forHTTPHeaderField: "Authorization")
        commitReq.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        commitReq.httpBody = try JSONSerialization.data(withJSONObject: ["writes": [userWrite, eventWrite]])

        let (respData, resp) = try await URLSession.shared.data(for: commitReq)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let msg = String(data: respData, encoding: .utf8) ?? ""
            throw AuthFlowError.httpError(status, msg)
        }

        if var latest = self.session, latest.uid == fresh.uid {
            latest.lastRecordedAt = Date()
            AuthSessionStorage.save(latest)
            self.session = latest
        }
    }

    private func checkUserDocumentExists(url: URL, idToken: String) async throws -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (_, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return true }
        if status == 404 { return false }
        throw AuthFlowError.httpError(status, "Failed to read user document status.")
    }

    // MARK: - Formatting Helpers

    private static func utcDateKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func urlComponentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=/:#?@!$'()*,;")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func formURLEncode(_ pairs: [(String, String)]) -> Data {
        let joined = pairs
            .map { "\(urlComponentEncode($0.0))=\(urlComponentEncode($0.1))" }
            .joined(separator: "&")
        return Data(joined.utf8)
    }

    private static func extractFirebaseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let err = json["error"] as? [String: Any], let msg = err["message"] as? String {
            return msg
        }
        return json["error"] as? String ?? json["error_description"] as? String
    }
}
