import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Network
import Security
import ServiceManagement
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AfterSelectionAction: String, CaseIterable {
    case showPanel = "show_panel"
    case copyText = "copy_text"
    case search = "search"

    var title: String {
        switch self {
        case .showPanel: return "Show panel"
        case .copyText: return "Copy text"
        case .search: return "Search"
        }
    }
}

enum PanelDefaultTab: String, CaseIterable {
    case lens = "lens"
    case answer = "answer"
    case auto = "auto"

    var title: String {
        switch self {
        case .lens: return "Lens"
        case .answer: return "Answer"
        case .auto: return "Auto"
        }
    }
}

enum SelectionMode: String, CaseIterable {
    case rectangle = "Rectangle (Box)"
    case circle = "Freehand Lasso"
    case tap = "Smart Tap"
    case textOnly = "Instant Text (OCR)"

    var title: String { rawValue }

    var shortTitle: String {
        switch self {
        case .rectangle: return "Box"
        case .circle: return "Freehand"
        case .tap: return "Tap"
        case .textOnly: return "Text"
        }
    }

    var shortcutBadge: String {
        switch self {
        case .rectangle: return "1"
        case .circle: return "2"
        case .tap: return "3"
        case .textOnly: return "4"
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle.dashed"
        case .circle: return "lasso"
        case .tap: return "hand.point.up.left.fill"
        case .textOnly: return "text.viewfinder"
        }
    }

    var promptHint: String {
        switch self {
        case .rectangle: return "Drag a box around anything"
        case .circle: return "Draw a freehand loop around anything"
        case .tap: return "Tap any object or block to select"
        case .textOnly: return "Drag over text to copy instantly"
        }
    }
}

enum SearchEngine: String, CaseIterable {
    case googleLens = "google_lens"
    case google = "google"
    case perplexity = "perplexity"
    case bing = "bing"
    case aiExplain = "ai_explain"

    var title: String {
        switch self {
        case .googleLens: return "Google Lens"
        case .google: return "Google"
        case .perplexity: return "Perplexity"
        case .bing: return "Bing"
        case .aiExplain: return "Ask AI"
        }
    }

    /// Compact title for segmented controls so labels never clip.
    var shortTitle: String {
        switch self {
        case .googleLens: return "Lens"
        case .google: return "Google"
        case .perplexity: return "Perplexity"
        case .bing: return "Bing"
        case .aiExplain: return "Ask AI"
        }
    }

    var symbolName: String {
        switch self {
        case .googleLens: return "loopsearch.logo"
        case .google: return "magnifyingglass"
        case .perplexity: return "sparkles.rectangle.stack"
        case .bing: return "globe"
        case .aiExplain: return "wand.and.sparkles"
        }
    }

    func searchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        switch self {
        case .googleLens, .google:
            return URL(string: "https://www.google.com/search?q=\(encoded)")
        case .perplexity:
            return URL(string: "https://www.perplexity.ai/search?q=\(encoded)")
        case .bing:
            return URL(string: "https://www.bing.com/search?q=\(encoded)")
        case .aiExplain:
            let prompt = ("Explain this clearly and concisely: " + trimmed)
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? encoded
            return URL(string: "https://www.google.com/search?udm=50&q=\(prompt)")
        }
    }
}

enum AppTheme: String, CaseIterable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    var title: String { shortTitle }

    var shortTitle: String {
        switch self {
        case .system: return "System"
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var symbolName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }
}

enum VisualStylePreset: String, CaseIterable {
    case subtle = "subtle"
    case balanced = "balanced"
    case vivid = "vivid"

    var title: String { shortTitle }

    var shortTitle: String {
        switch self {
        case .subtle: return "Subtle"
        case .balanced: return "Balanced"
        case .vivid: return "Vivid"
        }
    }

    var symbolName: String {
        switch self {
        case .subtle: return "circle.dotted"
        case .balanced: return "sparkles"
        case .vivid: return "sun.max.circle.fill"
        }
    }
}

enum GlowColorTheme: String, CaseIterable {
    case signature = "signature"
    case spectrum = "spectrum"

    var title: String { shortTitle }

    var shortTitle: String {
        switch self {
        case .signature: return "Loop Aura"
        case .spectrum: return "Spectrum"
        }
    }

    var symbolName: String {
        switch self {
        case .signature: return "lasso.badge.sparkles"
        case .spectrum: return "rainbow"
        }
    }
}

enum GlowIntensity: String, CaseIterable {
    case subtle = "subtle"
    case luminous = "luminous"
    case vivid = "vivid"

    var title: String {
        switch self {
        case .subtle: return "Subtle"
        case .luminous: return "Balanced"
        case .vivid: return "Vivid"
        }
    }

    var shortTitle: String { title }

    var opacityMultiplier: Double {
        switch self {
        case .subtle: return 0.36
        case .luminous: return 0.68
        case .vivid: return 1.05
        }
    }
}

enum MotionFeel: String, CaseIterable {
    case snappy = "snappy"
    case fluid = "fluid"
    case cinematic = "cinematic"

    var title: String {
        switch self {
        case .snappy: return "Crisp"
        case .fluid: return "Smooth"
        case .cinematic: return "Fluid"
        }
    }

    var shortTitle: String { title }

    var durationScale: Double {
        switch self {
        case .snappy: return 0.78
        case .fluid: return 1.00
        case .cinematic: return 1.20
        }
    }
}

extension Notification.Name {
    static let circleToSearchSettingsChanged = Notification.Name("CircleToSearchSettingsChanged")
    static let circleToSearchHistoryChanged = Notification.Name("CircleToSearchHistoryChanged")
    static let circleToSearchReopenHistory = Notification.Name("CircleToSearchReopenHistory")
    static let loopSearchGuideClosed = Notification.Name("LoopSearchGuideClosed")
    static let loopSearchUpdateChanged = Notification.Name("LoopSearchUpdateChanged")
}

// MARK: - Private Encrypted Local Vault (User-only 0o700/0o600, avoids login Keychain prompts)

enum PrivateAppSupportVault {
    private static let keyFileName = "auth-key.bin"

    static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LoopSearch", isDirectory: true)
    }

    private static func ensurePrivateDirectory() throws -> URL {
        let dir = directoryURL
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        return dir
    }

    private static func loadOrCreateSymmetricKey() throws -> SymmetricKey {
        let dir = try ensurePrivateDirectory()
        let keyURL = dir.appendingPathComponent(keyFileName)
        if let raw = try? Data(contentsOf: keyURL), raw.count == 32 {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
            return SymmetricKey(data: raw)
        }
        let freshKey = SymmetricKey(size: .bits256)
        let keyData = freshKey.withUnsafeBytes { Data($0) }
        try keyData.write(to: keyURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        return freshKey
    }

    static func saveEncrypted(_ data: Data, fileName: String) {
        guard let dir = try? ensurePrivateDirectory(),
              let key = try? loadOrCreateSymmetricKey(),
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else {
            return
        }
        let targetURL = dir.appendingPathComponent(fileName)
        try? combined.write(to: targetURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
    }

    static func loadEncrypted(fileName: String) -> Data? {
        let dir = directoryURL
        let keyURL = dir.appendingPathComponent(keyFileName)
        let targetURL = dir.appendingPathComponent(fileName)
        guard let combined = try? Data(contentsOf: targetURL),
              let keyData = try? Data(contentsOf: keyURL),
              keyData.count == 32,
              let box = try? AES.GCM.SealedBox(combined: combined) else {
            return nil
        }
        return try? AES.GCM.open(box, using: SymmetricKey(data: keyData))
    }

    static func remove(fileName: String) {
        try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(fileName))
    }
}

// MARK: - Private Storage Helper for Optional AI API Key

enum KeychainHelper {
    private static let fileName = "ai-key.bin"

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            PrivateAppSupportVault.remove(fileName: fileName)
            return
        }
        PrivateAppSupportVault.saveEncrypted(data, fileName: fileName)
    }

    static func loadAPIKey() -> String {
        guard let data = PrivateAppSupportVault.loadEncrypted(fileName: fileName),
              let str = String(data: data, encoding: .utf8) else {
            return ""
        }
        return str
    }

    private static let historyKeyFileName = "history-key.bin"

    static func loadOrCreateHistoryKey() -> SymmetricKey {
        if let raw = PrivateAppSupportVault.loadEncrypted(fileName: historyKeyFileName),
           raw.count == 32 {
            return SymmetricKey(data: raw)
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        PrivateAppSupportVault.saveEncrypted(keyData, fileName: historyKeyFileName)
        return key
    }
}

// MARK: - AI Explanation Streaming Service (Keychain Gemini API + On-Device Fallback)

enum AIService {
    static func generateExplanation(
        for image: CGImage,
        recognizedText: String,
        classificationLabels: [String],
        prompt: String
    ) async -> String {
        await generateExplanation(
            image: image,
            ocrText: recognizedText,
            mathSolution: nil,
            classificationLabels: classificationLabels,
            detectedURL: nil,
            userQuery: prompt
        )
    }

    static func generateExplanation(
        image: CGImage,
        ocrText: String,
        ocrConfidence: Double = 1.0,
        mathSolution: (expression: String, result: String)?,
        classificationLabels: [String],
        detectedURL: URL?,
        userQuery: String?
    ) async -> String {
        let cleanOCR = ocrText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let hasStrongSignal = (cleanOCR.count >= 6 && ocrConfidence >= 0.45) || !classificationLabels.isEmpty || mathSolution != nil || detectedURL != nil

        let apiKey = KeychainHelper.loadAPIKey()
        if !hasStrongSignal && (userQuery?.isEmpty ?? true) {
            return "Not sure what this is. Check Lens results."
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if SystemLanguageModel.default.isAvailable {
                do {
                    let session = LanguageModelSession(
                        instructions: """
                        You summarize or explain a screen capture in 1-3 concise sentences.
                        Rules: Strictly use ONLY the provided OCR text and image labels. NEVER invent names, brands, dates, or places not present in OCR text.
                        If the text/labels are weak or uncertain, reply with exactly: Not sure what this is. Check Lens results.
                        """
                    )
                    let context = [
                        cleanOCR.isEmpty ? nil : "OCR Text: \(cleanOCR)",
                        classificationLabels.isEmpty ? nil : "Image Labels: \(classificationLabels.joined(separator: ", "))",
                        mathSolution.map { "Math: \($0.expression) = \($0.result)" }
                    ].compactMap { $0 }.joined(separator: "\n")
                    let instruction = (userQuery?.isEmpty == false) ? userQuery! : "Explain what this is based on the OCR text and image labels."
                    let options = GenerationOptions(temperature: 0.0)
                    let response = try await session.respond(to: "\(instruction)\n\(context)", options: options)
                    let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { return text }
                } catch {}
            }
        }
        #endif

        if !apiKey.isEmpty {
            if let remote = await callGeminiVision(image: image, userQuery: userQuery, ocrText: cleanOCR, classificationLabels: classificationLabels, apiKey: apiKey) {
                return remote
            }
        }

        // Fallback when neither FoundationModels nor Gemini key is available: factual OCR/smart detections only.
        var parts: [String] = []
        if let math = mathSolution {
            parts.append("\(math.expression) = \(math.result)")
        }
        if let url = detectedURL {
            parts.append(url.host ?? url.absoluteString)
        }
        if !cleanOCR.isEmpty && ocrConfidence >= 0.52 {
            let summary = cleanOCR.count > 160 ? String(cleanOCR.prefix(158)) + "…" : cleanOCR
            parts.append(summary)
        }
        if parts.isEmpty {
            return "Not sure what this is. Check Lens results."
        }
        return parts.joined(separator: " · ")
    }

    private static func callGeminiVision(
        image: CGImage,
        userQuery: String?,
        ocrText: String,
        classificationLabels: [String],
        apiKey: String
    ) async -> String? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else {
            return nil
        }
        let base64Image = jpegData.base64EncodedString()
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=\(apiKey)") else {
            return nil
        }

        let contextBlock = [
            ocrText.isEmpty ? nil : "OCR: \(ocrText)",
            classificationLabels.isEmpty ? nil : "Labels: \(classificationLabels.joined(separator: ", "))"
        ].compactMap { $0 }.joined(separator: "\n")

        let prompt: String
        if let q = userQuery, !q.isEmpty {
            prompt = "Answer concisely in 1 to 3 sentences at temperature 0. Never invent names, dates, or places not supported by the image or OCR. If unsure, say: Not sure what this is. Check Lens results.\nQuestion: \(q)\n\(contextBlock)"
        } else {
            prompt = "Explain this selection concisely in 1 to 3 sentences. Never invent names, dates, or places not clearly supported by the image or OCR. If unsure, say: Not sure what this is. Check Lens results.\n\(contextBlock)"
        }

        let payload: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        [
                            "inline_data": [
                                "mime_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "maxOutputTokens": 160,
                "temperature": 0.0
            ]
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 12
        req.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                return nil
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let selectionMode = "selection_mode"
        static let searchEngine = "search_engine"
        static let afterSelectionAction = "after_selection_action"
        static let panelDefaultTab = "panel_default_tab"
        static let panelTabWasCustomized = "panel_tab_was_customized"
        static let blurOutsideSelectionBeforeSearch = "blur_outside_selection_before_search"
        static let historyRetentionDays = "history_retention_days"
        static let enableEncryptedSync = "enable_encrypted_sync"
        static let appTheme = "app_theme"
        static let webResultsTheme = "web_results_theme"
        static let visualStyle = "visual_style_preset"
        static let glowColorTheme = "glow_color_theme"
        static let glowIntensity = "glow_intensity"
        static let motionFeel = "motion_feel"
        static let showAmbientStars = "show_ambient_stars"
        static let showInlineOCR = "show_inline_ocr"
        static let reduceMotion = "reduce_motion"
        static let hideDockIcon = "hide_dock_icon"
        static let autoCheckForUpdates = "auto_check_for_updates"
        static let hasShownFirstToolbarHint = "has_shown_first_toolbar_hint"
        static let hasCompletedOnboarding = "has_completed_onboarding"
        static let hasSeenHowToUseGuide = "has_seen_how_to_use_guide"
        static let searchUsageCount = "search_usage_count"
        static let lastFeedbackPromptUsageCount = "last_feedback_prompt_usage_count"
        static let hasSubmittedFeedback = "has_submitted_feedback"
        static let lastSubmittedStarRating = "last_submitted_star_rating"
    }

    static let privacyStatement = "Your screen never leaves your device unless you press Search or enable encrypted sync."

    static let githubRepoURL = URL(string: "https://github.com/aveeshasenevirathne2-hub/LoopSearch")!
    static let githubIssuesNewURL = URL(string: "https://github.com/aveeshasenevirathne2-hub/LoopSearch/issues/new")!
    static let xProfileURL = URL(string: "https://x.com/AveeshaSen")!

    var selectionMode: SelectionMode {
        didSet {
            defaults.set(selectionMode.rawValue, forKey: Keys.selectionMode)
            notifyChanged()
        }
    }

    var searchEngine: SearchEngine {
        didSet {
            defaults.set(searchEngine.rawValue, forKey: Keys.searchEngine)
            notifyChanged()
        }
    }

    var afterSelectionAction: AfterSelectionAction {
        didSet {
            defaults.set(afterSelectionAction.rawValue, forKey: Keys.afterSelectionAction)
            notifyChanged()
        }
    }

    var panelDefaultTab: PanelDefaultTab {
        didSet {
            defaults.set(panelDefaultTab.rawValue, forKey: Keys.panelDefaultTab)
            panelTabWasCustomized = true
            notifyChanged()
        }
    }

    var panelTabWasCustomized: Bool {
        didSet {
            defaults.set(panelTabWasCustomized, forKey: Keys.panelTabWasCustomized)
        }
    }

    var blurOutsideSelectionBeforeSearch: Bool {
        didSet {
            defaults.set(blurOutsideSelectionBeforeSearch, forKey: Keys.blurOutsideSelectionBeforeSearch)
            notifyChanged()
        }
    }

    var historyRetentionDays: Int {
        didSet {
            defaults.set(historyRetentionDays, forKey: Keys.historyRetentionDays)
            notifyChanged()
        }
    }

    var enableEncryptedSync: Bool {
        didSet {
            defaults.set(enableEncryptedSync, forKey: Keys.enableEncryptedSync)
            notifyChanged()
        }
    }

    var theme: AppTheme {
        didSet {
            defaults.set(theme.rawValue, forKey: Keys.appTheme)
            applyAppAppearance()
            notifyChanged()
        }
    }

    /// Controls embedded browser results appearance (`system` = Auto-detect App/macOS Dark/Light mode).
    var webResultsTheme: AppTheme {
        didSet {
            defaults.set(webResultsTheme.rawValue, forKey: Keys.webResultsTheme)
            notifyChanged()
        }
    }

    var visualStyle: VisualStylePreset {
        didSet {
            defaults.set(visualStyle.rawValue, forKey: Keys.visualStyle)
            switch visualStyle {
            case .subtle:
                glowIntensity = .subtle
                motionFeel = .snappy
            case .balanced:
                glowIntensity = .luminous
                motionFeel = .fluid
            case .vivid:
                glowIntensity = .vivid
                motionFeel = .cinematic
            }
            notifyChanged()
        }
    }

    nonisolated(unsafe) static var cachedIsSignaturePalette: Bool = true

    var glowColorTheme: GlowColorTheme {
        didSet {
            Self.cachedIsSignaturePalette = (glowColorTheme == .signature)
            defaults.set(glowColorTheme.rawValue, forKey: Keys.glowColorTheme)
            notifyChanged()
        }
    }

    var glowIntensity: GlowIntensity {
        didSet {
            defaults.set(glowIntensity.rawValue, forKey: Keys.glowIntensity)
            notifyChanged()
        }
    }

    var motionFeel: MotionFeel {
        didSet {
            defaults.set(motionFeel.rawValue, forKey: Keys.motionFeel)
            notifyChanged()
        }
    }

    var showAmbientStars: Bool {
        didSet {
            defaults.set(showAmbientStars, forKey: Keys.showAmbientStars)
            notifyChanged()
        }
    }

    var showInlineOCR: Bool {
        didSet {
            defaults.set(showInlineOCR, forKey: Keys.showInlineOCR)
            notifyChanged()
        }
    }

    var reduceMotion: Bool {
        didSet {
            defaults.set(reduceMotion, forKey: Keys.reduceMotion)
            notifyChanged()
        }
    }

    var effectiveReduceMotion: Bool {
        reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var hideDockIcon: Bool {
        didSet {
            defaults.set(hideDockIcon, forKey: Keys.hideDockIcon)
            applyDockPolicy()
            notifyChanged()
        }
    }

    var autoCheckForUpdates: Bool {
        didSet {
            defaults.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates)
            notifyChanged()
        }
    }

    var launchAtLogin: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Ignore registration error on unsigned/dev builds
            }
            notifyChanged()
        }
    }

    var hasShownFirstToolbarHint: Bool {
        didSet {
            defaults.set(hasShownFirstToolbarHint, forKey: Keys.hasShownFirstToolbarHint)
        }
    }

    var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    var hasSeenHowToUseGuide: Bool {
        didSet {
            defaults.set(hasSeenHowToUseGuide, forKey: Keys.hasSeenHowToUseGuide)
        }
    }

    var searchUsageCount: Int {
        didSet {
            defaults.set(searchUsageCount, forKey: Keys.searchUsageCount)
        }
    }

    var lastFeedbackPromptUsageCount: Int {
        didSet {
            defaults.set(lastFeedbackPromptUsageCount, forKey: Keys.lastFeedbackPromptUsageCount)
        }
    }

    var hasSubmittedFeedback: Bool {
        didSet {
            defaults.set(hasSubmittedFeedback, forKey: Keys.hasSubmittedFeedback)
        }
    }

    var lastSubmittedStarRating: Int {
        didSet {
            defaults.set(lastSubmittedStarRating, forKey: Keys.lastSubmittedStarRating)
        }
    }

    var shouldPromptForFeedback: Bool {
        guard !hasSubmittedFeedback, searchUsageCount >= 5 else { return false }
        if lastFeedbackPromptUsageCount == 0 { return true }
        return (searchUsageCount - lastFeedbackPromptUsageCount) >= 10
    }

    func recordCompletedSearchUse() {
        searchUsageCount += 1
    }

    func markFeedbackPromptDeferred() {
        lastFeedbackPromptUsageCount = searchUsageCount
    }

    func markFeedbackCompleted(stars: Int) {
        hasSubmittedFeedback = true
        lastSubmittedStarRating = max(0, min(5, stars))
        lastFeedbackPromptUsageCount = searchUsageCount
    }

    var hotkeyPreset: HotkeyPreset {
        get {
            defaults.string(forKey: "hotkeyPreset").flatMap(HotkeyPreset.init(rawValue:)) ?? .doubleTapCmd
        }
        set {
            defaults.set(newValue.rawValue, forKey: "hotkeyPreset")
            defaults.set(false, forKey: "use_custom_hotkey")
            notifyChanged()
        }
    }

    var useCustomHotkey: Bool {
        defaults.bool(forKey: "use_custom_hotkey")
    }

    var customKeyCode: UInt32 {
        UInt32(defaults.integer(forKey: "custom_key_code"))
    }

    var customCarbonModifiers: UInt32 {
        UInt32(defaults.integer(forKey: "custom_carbon_modifiers"))
    }

    var activeHotkeyDisplayString: String {
        if useCustomHotkey, let customLabel = defaults.string(forKey: "custom_hotkey_display"), !customLabel.isEmpty {
            return customLabel
        }
        return hotkeyPreset.title
    }

    func setCustomHotkey(keyCode: UInt32, carbonModifiers: UInt32, displayString: String) {
        defaults.set(Int(keyCode), forKey: "custom_key_code")
        defaults.set(Int(carbonModifiers), forKey: "custom_carbon_modifiers")
        defaults.set(displayString, forKey: "custom_hotkey_display")
        defaults.set(true, forKey: "use_custom_hotkey")
        notifyChanged()
    }

    private init() {
        if let raw = defaults.string(forKey: Keys.selectionMode),
           let mode = SelectionMode(rawValue: raw) {
            self.selectionMode = mode
        } else {
            self.selectionMode = .rectangle
        }

        if let raw = defaults.string(forKey: Keys.searchEngine),
           let engine = SearchEngine(rawValue: raw) {
            self.searchEngine = engine
        } else {
            self.searchEngine = .googleLens
        }

        if let rawAfter = defaults.string(forKey: Keys.afterSelectionAction),
           let action = AfterSelectionAction(rawValue: rawAfter) {
            self.afterSelectionAction = action
        } else {
            self.afterSelectionAction = .showPanel
        }
        let wasCustomized = defaults.bool(forKey: Keys.panelTabWasCustomized)
        self.panelTabWasCustomized = wasCustomized
        if wasCustomized,
           let rawTab = defaults.string(forKey: Keys.panelDefaultTab),
           let tab = PanelDefaultTab(rawValue: rawTab) {
            self.panelDefaultTab = tab
        } else {
            self.panelDefaultTab = .lens
        }
        self.blurOutsideSelectionBeforeSearch = defaults.object(forKey: Keys.blurOutsideSelectionBeforeSearch) != nil
            ? defaults.bool(forKey: Keys.blurOutsideSelectionBeforeSearch)
            : true
        let savedRetention = defaults.integer(forKey: Keys.historyRetentionDays)
        self.historyRetentionDays = savedRetention > 0 ? savedRetention : 30
        self.enableEncryptedSync = defaults.bool(forKey: Keys.enableEncryptedSync)

        if let raw = defaults.string(forKey: Keys.appTheme),
           let loadedTheme = AppTheme(rawValue: raw) {
            self.theme = loadedTheme
        } else {
            self.theme = .system
        }

        if let raw = defaults.string(forKey: Keys.webResultsTheme),
           let loadedWebTheme = AppTheme(rawValue: raw) {
            self.webResultsTheme = loadedWebTheme
        } else {
            self.webResultsTheme = .system
        }

        if let raw = defaults.string(forKey: Keys.visualStyle),
           let preset = VisualStylePreset(rawValue: raw) {
            self.visualStyle = preset
        } else {
            self.visualStyle = .balanced
        }

        if let raw = defaults.string(forKey: Keys.glowColorTheme),
           let colorTheme = GlowColorTheme(rawValue: raw) {
            self.glowColorTheme = colorTheme
        } else {
            self.glowColorTheme = .signature
        }
        Self.cachedIsSignaturePalette = (self.glowColorTheme == .signature)

        if let raw = defaults.string(forKey: Keys.glowIntensity),
           let glow = GlowIntensity(rawValue: raw) {
            self.glowIntensity = glow
        } else {
            self.glowIntensity = .luminous
        }

        if let raw = defaults.string(forKey: Keys.motionFeel),
           let feel = MotionFeel(rawValue: raw) {
            self.motionFeel = feel
        } else {
            self.motionFeel = .fluid
        }

        if defaults.object(forKey: Keys.showAmbientStars) != nil {
            self.showAmbientStars = defaults.bool(forKey: Keys.showAmbientStars)
        } else {
            self.showAmbientStars = true
        }

        if defaults.object(forKey: Keys.showInlineOCR) != nil {
            self.showInlineOCR = defaults.bool(forKey: Keys.showInlineOCR)
        } else {
            self.showInlineOCR = true
        }

        if defaults.object(forKey: Keys.reduceMotion) != nil {
            self.reduceMotion = defaults.bool(forKey: Keys.reduceMotion)
        } else {
            self.reduceMotion = false
        }

        if defaults.object(forKey: Keys.hideDockIcon) != nil {
            self.hideDockIcon = defaults.bool(forKey: Keys.hideDockIcon)
        } else {
            self.hideDockIcon = true
        }

        if defaults.object(forKey: Keys.autoCheckForUpdates) != nil {
            self.autoCheckForUpdates = defaults.bool(forKey: Keys.autoCheckForUpdates)
        } else {
            self.autoCheckForUpdates = true
        }

        self.hasShownFirstToolbarHint = defaults.bool(forKey: Keys.hasShownFirstToolbarHint)
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.hasSeenHowToUseGuide = defaults.bool(forKey: Keys.hasSeenHowToUseGuide)
        self.searchUsageCount = defaults.integer(forKey: Keys.searchUsageCount)
        self.lastFeedbackPromptUsageCount = defaults.integer(forKey: Keys.lastFeedbackPromptUsageCount)
        self.hasSubmittedFeedback = defaults.bool(forKey: Keys.hasSubmittedFeedback)
        self.lastSubmittedStarRating = defaults.integer(forKey: Keys.lastSubmittedStarRating)
    }

    func applyAppAppearance() {
        NSApp?.appearance = theme.nsAppearance
    }

    func applyDockPolicy() {
        NSApp?.setActivationPolicy(hideDockIcon ? .accessory : .regular)
    }

    func resetToDefaults() {
        selectionMode = .rectangle
        searchEngine = .googleLens
        theme = .system
        webResultsTheme = .system
        visualStyle = .balanced
        glowColorTheme = .signature
        glowIntensity = .luminous
        motionFeel = .fluid
        showAmbientStars = true
        showInlineOCR = true
        reduceMotion = false
        hideDockIcon = false
        autoCheckForUpdates = true
        hotkeyPreset = .cmdShiftSpace
    }

    private func notifyChanged() {
        NotificationCenter.default.post(name: .circleToSearchSettingsChanged, object: nil)
    }
}

// MARK: - Capture History Store (Menu Bar History)

struct CaptureHistoryItem: Identifiable {
    let id: UUID
    let timestamp: Date
    let cgImage: CGImage
    var recognizedText: String
    var dominantHex: String

    init(id: UUID = UUID(), timestamp: Date = Date(), cgImage: CGImage, recognizedText: String = "", dominantHex: String = "") {
        self.id = id
        self.timestamp = timestamp
        self.cgImage = cgImage
        self.recognizedText = recognizedText
        self.dominantHex = dominantHex
    }
}

private struct PersistedHistoryEntry: Codable {
    let id: UUID
    let timestamp: TimeInterval
    let pngData: Data
    var recognizedText: String
    var dominantHex: String
}

@MainActor
final class CaptureHistoryStore {
    static let shared = CaptureHistoryStore()
    private(set) var items: [CaptureHistoryItem] = []
    private var searchIndex: [UUID: String] = [:]
    private let maxItems = 40
    private static let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    private static let encryptedFileName = "history.enc.json"

    private init() {
        loadFromEncryptedDisk()
    }

    func record(cgImage: CGImage, recognizedText: String = "", dominantHex: String = "") {
        let boundedImage = Self.capDimensionForHistory(cgImage, maxDimension: 1200)
        let entry = CaptureHistoryItem(
            timestamp: Date(),
            cgImage: boundedImage,
            recognizedText: recognizedText,
            dominantHex: dominantHex
        )
        items.insert(entry, at: 0)
        searchIndex[entry.id] = "\(recognizedText) \(dominantHex)".lowercased()
        pruneExpiredAndExcess()
        persistToEncryptedDisk()
        AppSettings.shared.recordCompletedSearchUse()
        NotificationCenter.default.post(name: .circleToSearchHistoryChanged, object: nil)
    }

    func search(query: String) -> [CaptureHistoryItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { (searchIndex[$0.id] ?? "").contains(q) }
    }

    private func pruneExpiredAndExcess() {
        let days = max(1, AppSettings.shared.historyRetentionDays)
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400.0)
        items.removeAll { $0.timestamp < cutoff }
        if items.count > maxItems {
            items.removeLast(items.count - maxItems)
        }
        let validIDs = Set(items.map(\.id))
        searchIndex = searchIndex.filter { validIDs.contains($0.key) }
    }

    private func persistToEncryptedDisk() {
        let encoded: [PersistedHistoryEntry] = items.compactMap { item in
            let rep = NSBitmapImageRep(cgImage: item.cgImage)
            guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
            return PersistedHistoryEntry(
                id: item.id,
                timestamp: item.timestamp.timeIntervalSince1970,
                pngData: png,
                recognizedText: item.recognizedText,
                dominantHex: item.dominantHex
            )
        }
        guard let json = try? JSONEncoder().encode(encoded) else { return }
        let key = KeychainHelper.loadOrCreateHistoryKey()
        guard let sealed = try? AES.GCM.seal(json, using: key),
              let combined = sealed.combined else { return }
        let url = historyFileURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? combined.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private func loadFromEncryptedDisk() {
        let url = historyFileURL()
        guard let data = try? Data(contentsOf: url) else { return }
        let key = KeychainHelper.loadOrCreateHistoryKey()
        guard let box = try? AES.GCM.SealedBox(combined: data),
              let plain = try? AES.GCM.open(box, using: key),
              let decoded = try? JSONDecoder().decode([PersistedHistoryEntry].self, from: plain) else {
            return
        }
        items = decoded.compactMap { row in
            guard let img = NSImage(data: row.pngData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return CaptureHistoryItem(
                id: row.id,
                timestamp: Date(timeIntervalSince1970: row.timestamp),
                cgImage: img,
                recognizedText: row.recognizedText,
                dominantHex: row.dominantHex
            )
        }
        for item in items {
            searchIndex[item.id] = "\(item.recognizedText) \(item.dominantHex)".lowercased()
        }
        pruneExpiredAndExcess()
    }

    private func historyFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("LoopSearch", isDirectory: true).appendingPathComponent(Self.encryptedFileName)
    }

    private static func capDimensionForHistory(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let w = CGFloat(image.width)
        let h = CGFloat(image.height)
        let scale = min(1.0, maxDimension / max(w, h))
        guard scale < 0.99 else { return image }
        let targetW = max(1, Int((w * scale).rounded()))
        let targetH = max(1, Int((h * scale).rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        return ctx.makeImage() ?? image
    }

    func updateLatestText(_ text: String, dominantHex: String) {
        guard !items.isEmpty else { return }
        items[0].recognizedText = text
        items[0].dominantHex = dominantHex
        searchIndex[items[0].id] = "\(text) \(dominantHex)".lowercased()
        persistToEncryptedDisk()
        NotificationCenter.default.post(name: .circleToSearchHistoryChanged, object: nil)
    }

    func clear() {
        items.removeAll()
        searchIndex.removeAll()
        try? FileManager.default.removeItem(at: historyFileURL())
        NotificationCenter.default.post(name: .circleToSearchHistoryChanged, object: nil)
    }
}

/// Optional LAN E2E-encrypted LoopSearch capture & history sync (off by default, never syncs system clipboard).
@MainActor
final class LocalSyncService {
    static let shared = LocalSyncService()
    private(set) var pairingCode: String = ""
    private var listener: NWListener?
    private var browser: NWBrowser?
    private(set) var discoveredPeers: [String] = []

    func startIfEnabled() {
        guard AppSettings.shared.enableEncryptedSync else {
            stop()
            return
        }
        if pairingCode.isEmpty {
            pairingCode = String(format: "%06d", Int.random(in: 100_000...999_999))
        }
        if listener == nil, let listener = try? NWListener(using: .tcp) {
            listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: "_loopsearch-sync._tcp")
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        }
        if browser == nil {
            let b = NWBrowser(for: .bonjour(type: "_loopsearch-sync._tcp", domain: nil), using: .tcp)
            b.browseResultsChangedHandler = { [weak self] results, _ in
                let names = results.compactMap { res -> String? in
                    if case let .service(name, _, _, _) = res.endpoint { return name }
                    return nil
                }
                Task { @MainActor in self?.discoveredPeers = names }
            }
            b.start(queue: .global(qos: .utility))
            self.browser = b
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil
        discoveredPeers.removeAll()
    }
}

// MARK: - Floating Pin-to-Screen Manager

@MainActor
final class PinnedCaptureManager {
    static let shared = PinnedCaptureManager()
    private var controllers: [UUID: PinnedCaptureWindowController] = [:]

    func pin(image: CGImage, initialRect: CGRect, onToast: @escaping (String) -> Void) {
        let id = UUID()
        let controller = PinnedCaptureWindowController(
            id: id,
            image: image,
            initialRect: initialRect,
            onToast: onToast,
            onClose: { [weak self] closedID in
                self?.controllers.removeValue(forKey: closedID)
            }
        )
        controllers[id] = controller
        controller.show()
    }

    func closeAll() {
        for (_, c) in controllers {
            c.close()
        }
        controllers.removeAll()
    }

    var count: Int { controllers.count }
}

@MainActor
final class PinnedCaptureWindowController: NSObject {
    private let id: UUID
    private let cgImage: CGImage
    private let onToast: (String) -> Void
    private let onClose: (UUID) -> Void
    private var panel: NSPanel?

    init(
        id: UUID,
        image: CGImage,
        initialRect: CGRect,
        onToast: @escaping (String) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.id = id
        self.cgImage = image
        self.onToast = onToast
        self.onClose = onClose
        super.init()

        let clampedW = max(160, min(460, initialRect.width))
        let clampedH = max(110, min(380, initialRect.height))
        let frame = NSRect(
            x: initialRect.midX - clampedW / 2,
            y: initialRect.midY - clampedH / 2,
            width: clampedW,
            height: clampedH
        )

        let win = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isFloatingPanel = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = LiquidGlassSurfaceView(
            cornerRadius: 16,
            style: .regular,
            tintColor: NSColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 0.80)
        )
        root.frame = NSRect(origin: .zero, size: frame.size)
        root.autoresizingMask = [.width, .height]

        let imgView = NSImageView(image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
        imgView.imageScaling = .scaleProportionallyUpOrDown
        imgView.wantsLayer = true
        imgView.layer?.cornerRadius = 12
        imgView.layer?.masksToBounds = true
        imgView.translatesAutoresizingMaskIntoConstraints = false
        root.contentContainer.addSubview(imgView)

        let copyBtn = LiquidGlassButton(
            symbol: "doc.on.doc",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            tooltip: "Copy Image",
            fixedSize: CGSize(width: 26, height: 26),
            style: .regular
        ) { [weak self] in
            self?.copyImage()
        }

        let liftBtn = LiquidGlassButton(
            symbol: "wand.and.stars",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            tooltip: "Copy Subject Sticker",
            fixedSize: CGSize(width: 26, height: 26),
            style: .regular
        ) { [weak self] in
            self?.liftSticker()
        }

        let closeBtn = LiquidGlassButton(
            symbol: "xmark",
            symbolPointSize: 10,
            symbolWeight: .bold,
            tooltip: "Unpin",
            fixedSize: CGSize(width: 26, height: 26),
            style: .regular
        ) { [weak self] in
            self?.close()
        }

        let bar = NSStackView(views: [copyBtn, liftBtn, closeBtn])
        bar.orientation = .horizontal
        bar.spacing = 4
        bar.translatesAutoresizingMaskIntoConstraints = false
        root.contentContainer.addSubview(bar)

        NSLayoutConstraint.activate([
            imgView.leadingAnchor.constraint(equalTo: root.contentContainer.leadingAnchor, constant: 6),
            imgView.trailingAnchor.constraint(equalTo: root.contentContainer.trailingAnchor, constant: -6),
            imgView.topAnchor.constraint(equalTo: root.contentContainer.topAnchor, constant: 6),
            imgView.bottomAnchor.constraint(equalTo: root.contentContainer.bottomAnchor, constant: -6),

            bar.topAnchor.constraint(equalTo: root.contentContainer.topAnchor, constant: 10),
            bar.trailingAnchor.constraint(equalTo: root.contentContainer.trailingAnchor, constant: -10)
        ])

        win.contentView = root
        self.panel = win
    }

    func show() {
        panel?.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
        onClose(id)
    }

    private func copyImage() {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
        onToast("Pinned image copied to clipboard")
    }

    private func liftSticker() {
        let source = cgImage
        let toast = onToast
        Task { @MainActor in
            if let lifted = await VisionAnalyzer.liftSubject(from: source) {
                let rep = NSBitmapImageRep(cgImage: lifted)
                if let png = rep.representation(using: .png, properties: [:]) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setData(png, forType: .png)
                    toast("Subject sticker copied with transparent background!")
                }
            } else {
                toast("Could not isolate a foreground subject")
            }
        }
    }
}

// MARK: - App Update Checker (GitHub Releases)

@MainActor
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()

    struct AvailableUpdate: Equatable {
        let version: String
        let releaseTitle: String
        let notes: String
        let dmgURL: URL?
        let releasePageURL: URL
    }

    static let githubReleasesPageURL = URL(string: "https://github.com/aveeshasenevirathne2-hub/LoopSearch/releases")!
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/aveeshasenevirathne2-hub/LoopSearch/releases/latest")!
    private static let skippedVersionKey = "skipped_update_version"

    private(set) var availableUpdate: AvailableUpdate?
    private var isChecking = false
    private var isInstalling = false
    private var progressPanel: UpdateProgressWindow?

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.3"
    }

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
        let tag_name: String
        let name: String?
        let html_url: String
        let body: String?
        let assets: [Asset]?
    }

    func installOrOpenAvailableUpdate() {
        guard let update = availableUpdate else {
            checkForUpdates(interactive: true)
            return
        }
        if let dmgURL = update.dmgURL {
            Task { @MainActor [weak self] in
                await self?.downloadAndInstallUpdate(from: dmgURL, version: update.version, fallbackURL: update.releasePageURL)
            }
        } else {
            NSWorkspace.shared.open(update.releasePageURL)
        }
    }

    func checkForUpdates(interactive: Bool = true) {
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isChecking = false }
            await self.performCheck(interactive: interactive)
        }
    }

    private func performCheck(interactive: Bool) async {
        var req = URLRequest(url: Self.latestReleaseAPIURL)
        req.timeoutInterval = 12
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("LoopSearch/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0

            if status == 404 {
                if availableUpdate != nil {
                    availableUpdate = nil
                    NotificationCenter.default.post(name: .loopSearchUpdateChanged, object: nil)
                }
                if interactive {
                    presentUpToDateAlert(message: "You're running LoopSearch v\(Self.currentVersion). No newer GitHub release is published yet.")
                }
                return
            }

            guard (200...299).contains(status) else {
                if interactive {
                    presentErrorAlert(details: "GitHub Releases returned HTTP \(status).")
                }
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = Self.normalizeVersion(release.tag_name)
            let localVersion = Self.normalizeVersion(Self.currentVersion)

            if Self.isVersion(remoteVersion, newerThan: localVersion) {
                let dmgURL = release.assets?
                    .first(where: { $0.name.lowercased().hasSuffix(".dmg") })
                    .flatMap { URL(string: $0.browser_download_url) }
                    .flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
                let releaseURL = URL(string: release.html_url) ?? Self.githubReleasesPageURL

                let update = AvailableUpdate(
                    version: remoteVersion,
                    releaseTitle: release.name ?? "LoopSearch v\(remoteVersion)",
                    notes: release.body ?? "",
                    dmgURL: dmgURL,
                    releasePageURL: releaseURL
                )
                availableUpdate = update
                NotificationCenter.default.post(name: .loopSearchUpdateChanged, object: update)

                let skipped = UserDefaults.standard.string(forKey: Self.skippedVersionKey)
                if !interactive, skipped == remoteVersion {
                    return
                }

                presentUpdateAvailableAlert(
                    version: remoteVersion,
                    releaseTitle: update.releaseTitle,
                    notes: update.notes,
                    dmgURL: dmgURL,
                    releasePageURL: releaseURL
                )
            } else {
                if availableUpdate != nil {
                    availableUpdate = nil
                    NotificationCenter.default.post(name: .loopSearchUpdateChanged, object: nil)
                }
                if interactive {
                    presentUpToDateAlert(message: "You're running the latest version of LoopSearch (v\(Self.currentVersion)).")
                }
            }
        } catch {
            if interactive {
                presentErrorAlert(details: error.localizedDescription)
            }
        }
    }

    private func presentUpdateAvailableAlert(
        version: String,
        releaseTitle: String,
        notes: String,
        dmgURL: URL?,
        releasePageURL: URL
    ) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "LoopSearch v\(version) is Available"
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = trimmedNotes.isEmpty ? "A new release (\(releaseTitle)) is ready on GitHub." : String(trimmedNotes.prefix(360))
        alert.informativeText = "Current version: v\(Self.currentVersion)\n\n\(preview)"

        if let dmgURL {
            alert.addButton(withTitle: "Install & Relaunch")
            alert.addButton(withTitle: "View on GitHub")
            alert.addButton(withTitle: "Skip v\(version)")
            alert.addButton(withTitle: "Later")

            let choice = alert.runModal()
            if choice == .alertFirstButtonReturn {
                Task { @MainActor [weak self] in
                    await self?.downloadAndInstallUpdate(from: dmgURL, version: version, fallbackURL: releasePageURL)
                }
            } else if choice == .alertSecondButtonReturn {
                NSWorkspace.shared.open(releasePageURL)
            } else if choice == .alertThirdButtonReturn {
                UserDefaults.standard.set(version, forKey: Self.skippedVersionKey)
            }
        } else {
            alert.addButton(withTitle: "Download Update")
            alert.addButton(withTitle: "Skip v\(version)")
            alert.addButton(withTitle: "Later")

            let choice = alert.runModal()
            if choice == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasePageURL)
            } else if choice == .alertSecondButtonReturn {
                UserDefaults.standard.set(version, forKey: Self.skippedVersionKey)
            }
        }
    }

    private func downloadAndInstallUpdate(from dmgURL: URL, version: String, fallbackURL: URL) async {
        guard !isInstalling else { return }
        isInstalling = true
        let panel = UpdateProgressWindow(version: version)
        self.progressPanel = panel
        panel.show(status: "Downloading LoopSearch v\(version)…", fraction: 0.12)

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent("loopsearch-update-\(UUID().uuidString)", isDirectory: true)
        let mountDir = workDir.appendingPathComponent("mnt", isDirectory: true)
        let stagedApp = workDir.appendingPathComponent("LoopSearch.app", isDirectory: true)
        let localDMG = workDir.appendingPathComponent("LoopSearch.dmg")

        do {
            try fm.createDirectory(at: mountDir, withIntermediateDirectories: true)

            let (downloadedTempURL, response) = try await URLSession.shared.download(from: dmgURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 200
            guard (200...299).contains(statusCode) else {
                throw NSError(domain: "LoopSearchUpdate", code: statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "GitHub download returned HTTP \(statusCode)."
                ])
            }
            try fm.moveItem(at: downloadedTempURL, to: localDMG)

            panel.update(status: "Verifying & mounting update package…", fraction: 0.52)
            try await runProcess("/usr/bin/hdiutil", args: [
                "attach", localDMG.path,
                "-nobrowse", "-readonly",
                "-mountpoint", mountDir.path
            ])

            defer {
                _ = try? Self.runProcessSync("/usr/bin/hdiutil", args: ["detach", "-force", mountDir.path])
            }

            let mountedApp = mountDir.appendingPathComponent("LoopSearch.app", isDirectory: true)
            guard fm.fileExists(atPath: mountedApp.appendingPathComponent("Contents/Info.plist").path) else {
                throw NSError(domain: "LoopSearchUpdate", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Downloaded DMG does not contain LoopSearch.app."
                ])
            }

            panel.update(status: "Verifying application signature…", fraction: 0.70)
            try await runProcess("/usr/bin/codesign", args: [
                "--verify", "--deep", "--strict", mountedApp.path
            ])

            panel.update(status: "Preparing installation…", fraction: 0.85)
            try await runProcess("/usr/bin/ditto", args: [mountedApp.path, stagedApp.path])

            let destinationApp = Self.resolveInstallDestinationURL()
            let destParent = destinationApp.deletingLastPathComponent().path
            guard fm.isWritableFile(atPath: destParent) else {
                throw NSError(domain: "LoopSearchUpdate", code: 13, userInfo: [
                    NSLocalizedDescriptionKey: "Cannot write to \(destParent). Move LoopSearch.app to Applications and retry."
                ])
            }

            panel.update(status: "Installing LoopSearch v\(version) & relaunching…", fraction: 1.0)
            try Self.spawnSelfReplaceAndRelaunch(
                stagedAppPath: stagedApp.path,
                destinationAppPath: destinationApp.path,
                workDirPath: workDir.path,
                currentPID: ProcessInfo.processInfo.processIdentifier
            )

            NSApp.terminate(nil)
        } catch {
            try? fm.removeItem(at: workDir)
            panel.close()
            self.progressPanel = nil
            self.isInstalling = false

            NSApp.activate(ignoringOtherApps: true)
            let errAlert = NSAlert()
            errAlert.alertStyle = .warning
            errAlert.messageText = "Automatic Update Failed"
            errAlert.informativeText = "\(error.localizedDescription)\n\nYou can still download the update manually from GitHub Releases."
            errAlert.addButton(withTitle: "Open GitHub Release")
            errAlert.addButton(withTitle: "Cancel")
            if errAlert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(fallbackURL)
            }
        }
    }

    private static func resolveInstallDestinationURL() -> URL {
        let bundleURL = Bundle.main.bundleURL
        let path = bundleURL.path
        if path.hasSuffix(".app"), !path.hasPrefix("/Volumes/") {
            return bundleURL
        }
        return URL(fileURLWithPath: "/Applications/LoopSearch.app")
    }

    private func runProcess(_ launchPath: String, args: [String]) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.runProcessSync(launchPath, args: args)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func runProcessSync(_ launchPath: String, args: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = pipe
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NSError(domain: "LoopSearchProcess", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: errText.isEmpty ? "\(launchPath) exited with status \(proc.terminationStatus)." : errText
            ])
        }
    }

    private static func spawnSelfReplaceAndRelaunch(
        stagedAppPath: String,
        destinationAppPath: String,
        workDirPath: String,
        currentPID: Int32
    ) throws {
        let script = """
        PID="$1"
        SRC="$2"
        DST="$3"
        WORK="$4"
        BACKUP="${DST}.backup.$$"
        i=0
        while kill -0 "$PID" 2>/dev/null && [ $i -lt 50 ]; do
            sleep 0.15
            i=$((i+1))
        done
        if [ -e "$DST" ]; then
            mv "$DST" "$BACKUP" || exit 1
        fi
        if mv "$SRC" "$DST"; then
            rm -rf "$BACKUP" "$WORK"
            /usr/bin/xattr -dr com.apple.quarantine "$DST" 2>/dev/null || true
            /usr/bin/open -n "$DST"
        else
            [ -e "$BACKUP" ] && mv "$BACKUP" "$DST"
            exit 1
        fi
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", script, "loopsearch-updater", String(currentPID), stagedAppPath, destinationAppPath, workDirPath]
        try proc.run()
    }

    private func presentUpToDateAlert(message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "LoopSearch is Up to Date"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "GitHub Releases")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(Self.githubReleasesPageURL)
        }
    }

    private func presentErrorAlert(details: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText = "\(details)\n\nYou can also check GitHub Releases directly."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Releases Page")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(Self.githubReleasesPageURL)
        }
    }

    static func normalizeVersion(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.lowercased().hasPrefix("v") {
            cleaned.removeFirst()
        }
        return cleaned
    }

    static func isVersion(_ remote: String, newerThan local: String) -> Bool {
        let rParts = remote.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let lParts = local.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let count = max(rParts.count, lParts.count)
        for i in 0..<count {
            let rv = i < rParts.count ? rParts[i] : 0
            let lv = i < lParts.count ? lParts[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}

@MainActor
private final class UpdateProgressWindow {
    private let window: NSWindow
    private let statusLabel: NSTextField
    private let progressBar: NSProgressIndicator

    init(version: String) {
        let rect = NSRect(x: 0, y: 0, width: 380, height: 122)
        window = NSWindow(
            contentRect: rect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Updating LoopSearch"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()

        let container = NSView(frame: rect)
        let titleLabel = NSTextField(labelWithString: "Installing LoopSearch v\(version)")
        titleLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        statusLabel = NSTextField(labelWithString: "Preparing…")
        statusLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        progressBar = NSProgressIndicator()
        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0.08
        progressBar.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(titleLabel)
        container.addSubview(statusLabel)
        container.addSubview(progressBar)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),

            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            progressBar.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 14)
        ])

        window.contentView = container
    }

    func show(status: String, fraction: Double) {
        update(status: status, fraction: fraction)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func update(status: String, fraction: Double) {
        statusLabel.stringValue = status
        progressBar.doubleValue = min(1.0, max(0.0, fraction))
    }

    func close() {
        window.orderOut(nil)
    }
}
