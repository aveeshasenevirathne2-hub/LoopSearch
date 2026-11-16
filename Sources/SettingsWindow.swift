import Cocoa

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var rootView: SettingsContentView?

    func show() {
        if let existing = window {
            rootView?.refreshFromSettings()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 590, height: 680)
        let win = SettingsKeyCaptureWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "LoopSearch Settings"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false

        let content = SettingsContentView(frame: rect)
        win.onKeyDown = { [weak content] event in
            content?.handleCapturedKeyEvent(event) ?? false
        }
        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
        self.rootView = content

        content.wantsLayer = true
        content.alphaValue = 0
        if let layer = content.layer {
            let start = AppleMotion.centeredTransform(
                bounds: rect,
                scale: 0.94,
                translation: CGPoint(x: 0, y: -12)
            )
            let spring = AppleMotion.spring(
                keyPath: "transform",
                from: start,
                to: CATransform3DIdentity,
                dampingRatio: 0.85,
                response: 0.38
            )
            layer.transform = CATransform3DIdentity
            layer.add(spring, forKey: "settingsOpenSpring")
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.24)
            ctx.timingFunction = AppleMotion.easeOut
            content.animator().alphaValue = 1.0
        }
        content.animateVisibleCardsIn()
    }

    func windowWillClose(_ notification: Notification) {
        rootView?.cancelShortcutRecording()
    }
}

@MainActor
private enum ShortcutCaptureResult {
    case cancelled
    case modifierOnly
    case missingModifiers
    case captured(keyCode: UInt32, carbonModifiers: UInt32, displayString: String)

    static func parse(_ event: NSEvent) -> ShortcutCaptureResult {
        if event.keyCode == 53 {
            return .cancelled
        }
        let ignoredKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if ignoredKeyCodes.contains(event.keyCode) {
            return .modifierOnly
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard !flags.isEmpty else {
            return .missingModifiers
        }
        let carbonMods = HotkeyManager.carbonModifiers(from: flags)
        let label = HotkeyManager.formatShortcut(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods)
        return .captured(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods, displayString: label)
    }
}

private final class SettingsKeyCaptureWindow: NSWindow {
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let onKeyDown, onKeyDown(event) {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
private func makeSupportButtonsRow(compact: Bool) -> NSStackView {
    let xBtn = LiquidGlassButton(
        title: "𝕏 @AveeshaSen",
        tooltip: "Follow Aveesha Senevirathne on X (https://x.com/AveeshaSen)",
        height: compact ? 24 : 25,
        style: .clear,
        foregroundColor: .labelColor,
        font: .systemFont(ofSize: 10.5, weight: .semibold)
    ) {
        NSWorkspace.shared.open(AppSettings.xProfileURL)
    }

    let starBtn = LiquidGlassButton(
        symbol: "star.fill",
        symbolPointSize: 9.5,
        symbolWeight: .semibold,
        title: "Star",
        tooltip: "Enjoying LoopSearch? Star the repository on GitHub",
        height: compact ? 24 : 25,
        style: .clear,
        foregroundColor: NSColor(red: 1.0, green: 0.82, blue: 0.34, alpha: 0.96),
        font: .systemFont(ofSize: 10.5, weight: .semibold)
    ) {
        NSWorkspace.shared.open(AppSettings.githubRepoURL)
    }

    let rateBtn = LiquidGlassButton(
        symbol: "sparkles.rectangle.stack",
        symbolPointSize: 9.5,
        symbolWeight: .semibold,
        title: compact ? "Rate" : "Rate & Feedback",
        tooltip: "Rate LoopSearch or suggest a new feature",
        height: compact ? 24 : 25,
        style: .clear,
        tintColor: NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.82),
        lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.90),
        foregroundColor: .white,
        font: .systemFont(ofSize: 10.5, weight: .semibold)
    ) {
        FeedbackWindowController.shared.show(isAutomaticMilestone: false)
    }

    let buttonsRow = NSStackView(views: [xBtn, starBtn, rateBtn])
    buttonsRow.orientation = .horizontal
    buttonsRow.alignment = .centerY
    buttonsRow.spacing = 6
    return buttonsRow
}

@MainActor
private func makeCreatorSupportCard(compact: Bool) -> NSView {
    let card = makeSettingsGlassCard(cornerRadius: 14)

    let title = NSTextField(labelWithString: "Made by Aveesha Senevirathne")
    title.font = .systemFont(ofSize: compact ? 12 : 12.5, weight: .semibold)
    title.textColor = .labelColor

    let subtitle = NSTextField(labelWithString: "Enjoying LoopSearch? Follow updates, star on GitHub, or rate & suggest features.")
    subtitle.font = .systemFont(ofSize: 10.5, weight: .regular)
    subtitle.textColor = .secondaryLabelColor
    subtitle.lineBreakMode = .byTruncatingTail

    let textCol = NSStackView(views: [title, subtitle])
    textCol.orientation = .vertical
    textCol.alignment = .leading
    textCol.spacing = 1.5
    textCol.setContentHuggingPriority(.defaultLow, for: .horizontal)
    textCol.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let spacer = NSView()
    spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

    let buttonsRow = makeSupportButtonsRow(compact: compact)

    let row = NSStackView(views: [textCol, spacer, buttonsRow])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 8
    row.translatesAutoresizingMaskIntoConstraints = false
    card.contentContainer.addSubview(row)

    NSLayoutConstraint.activate([
        row.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
        row.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
        row.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 10),
        row.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -10)
    ])

    return card
}

@MainActor
private func makeSettingsGlassCard(cornerRadius: CGFloat = 14) -> LiquidGlassSurfaceView {
    let card = LiquidGlassSurfaceView(
        cornerRadius: cornerRadius,
        style: .clear,
        tintColor: NSColor(red: 0.04, green: 0.055, blue: 0.10, alpha: 0.52),
        lightTintColor: NSColor.black.withAlphaComponent(0.035),
        useNativeGlass: false
    )
    card.horizonRimStrength = 0.08
    card.enableHoverGlow = true
    card.translatesAutoresizingMaskIntoConstraints = false
    return card
}

@MainActor
private final class SettingsContentView: NSView {
    private let glassCard: LiquidGlassSurfaceView = {
        let view = LiquidGlassSurfaceView(
            cornerRadius: 24,
            style: .regular,
            tintColor: NSColor(red: 0.022, green: 0.028, blue: 0.056, alpha: 0.94),
            lightTintColor: NSColor(white: 0.96, alpha: 0.92)
        )
        view.horizonGlowIntensity = 0.52
        view.horizonPoolHeightFraction = 0.30
        view.horizonRimStrength = 0.38
        view.horizonWellView.setContinuousWaveEnabled(true)
        return view
    }()
    private let headerAccentLayer = CAGradientLayer()
    private var mainStackRef: NSStackView?
    private weak var scrollViewRef: NSScrollView?
    private var headerRowRef: NSView?

    private var modeSegment: LiquidGlassSegmentedControl!
    private var engineSegment: LiquidGlassSegmentedControl!
    private var ocrToggle: LiquidGlassToggle!

    private var themeSegment: LiquidGlassSegmentedControl!
    private var webThemeSegment: LiquidGlassSegmentedControl!
    private var styleSegment: LiquidGlassSegmentedControl!
    private var paletteSegment: LiquidGlassSegmentedControl!
    private var starsToggle: LiquidGlassToggle!
    private var reduceMotionToggle: LiquidGlassToggle!

    private var apiKeyField: NSSecureTextField!
    private var apiKeyStatusLabel: NSTextField!

    private var hotkeyValueLabel: NSTextField!
    private var recordShortcutButton: LiquidGlassButton!
    private var presetButtons: [HotkeyPreset: LiquidGlassButton] = [:]
    private var shortcutWarningBanner: LiquidGlassSurfaceView!
    private var shortcutWarningLabel: NSTextField!

    private var launchAtLoginToggle: LiquidGlassToggle!
    private var hideDockToggle: LiquidGlassToggle!
    private var autoUpdateToggle: LiquidGlassToggle!
    private var permissionBadgeLabel: NSTextField!

    private var authAvatarView: NSImageView!
    private var authMonogramLabel: NSTextField!
    private var authNameLabel: NSTextField!
    private var authStatusLabel: NSTextField!
    private var authDetailLabel: NSTextField!
    private var authPrimaryBtn: LiquidGlassButton!
    private var authSignOutBtn: LiquidGlassButton!
    nonisolated(unsafe) private var authObserver: NSObjectProtocol?

    private var updateBannerCard: LiquidGlassSurfaceView!
    private var updateBannerTitleLabel: NSTextField!
    private var updateBannerDetailLabel: NSTextField!
    private var updateBannerActionBtn: LiquidGlassButton!
    private var updatesHeaderBtn: LiquidGlassButton!
    nonisolated(unsafe) private var updateObserver: NSObjectProtocol?

    private var historyCountLabel: NSTextField!
    private var historyListStack: NSStackView!
    private var clearInlineHistoryBtn: LiquidGlassButton!
    nonisolated(unsafe) private var historyObserver: NSObjectProtocol?

    private var isRecordingShortcut = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        setupGlassSurface()
        setupControls()

        historyObserver = NotificationCenter.default.addObserver(
            forName: .circleToSearchHistoryChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadHistoryList()
            }
        }

        authObserver = NotificationCenter.default.addObserver(
            forName: .loopSearchAuthChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAuthCard()
            }
        }

        updateObserver = NotificationCenter.default.addObserver(
            forName: .loopSearchUpdateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshUpdateBanner(animated: true)
            }
        }
    }

    deinit {
        if let historyObserver {
            NotificationCenter.default.removeObserver(historyObserver)
        }
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
        if let updateObserver {
            NotificationCenter.default.removeObserver(updateObserver)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        headerAccentLayer.frame = CGRect(x: 24, y: bounds.height - 3, width: bounds.width - 48, height: 2)
    }

    func refreshFromSettings() {
        let s = AppSettings.shared
        if let idx = SelectionMode.allCases.firstIndex(of: s.selectionMode) {
            modeSegment.setSelectedIndex(idx, animated: false)
        }
        if let idx = SearchEngine.allCases.firstIndex(of: s.searchEngine) {
            engineSegment.setSelectedIndex(idx, animated: false)
        }
        ocrToggle.isOn = s.showInlineOCR

        if let idx = AppTheme.allCases.firstIndex(of: s.theme) {
            themeSegment.setSelectedIndex(idx, animated: false)
        }
        if let idx = AppTheme.allCases.firstIndex(of: s.webResultsTheme) {
            webThemeSegment.setSelectedIndex(idx, animated: false)
        }
        if let idx = VisualStylePreset.allCases.firstIndex(of: s.visualStyle) {
            styleSegment.setSelectedIndex(idx, animated: false)
        }
        if let idx = GlowColorTheme.allCases.firstIndex(of: s.glowColorTheme) {
            paletteSegment.setSelectedIndex(idx, animated: false)
        }
        starsToggle.isOn = s.showAmbientStars
        reduceMotionToggle.isOn = s.reduceMotion
        launchAtLoginToggle.isOn = s.launchAtLogin
        hideDockToggle.isOn = s.hideDockIcon
        autoUpdateToggle.isOn = s.autoCheckForUpdates

        let existingKey = KeychainHelper.loadAPIKey()
        apiKeyField.stringValue = existingKey
        apiKeyStatusLabel.stringValue = existingKey.isEmpty
            ? "Using on-device Vision synthesis (add key for Gemini Flash cloud vision)"
            : "✓ Gemini API key saved in macOS Keychain"

        let granted = CGPreflightScreenCaptureAccess()
        permissionBadgeLabel.stringValue = granted ? "✓ Screen Recording Granted" : "⚠ Permission Needed"
        reloadHistoryList()
        refreshAuthCard()
        permissionBadgeLabel.textColor = granted ? .systemGreen : .systemOrange

        refreshHotkeyUI()

        glassCard.horizonWellView.setContinuousWaveEnabled(true)
        if let header = headerRowRef {
            AppleMotion.kineticHorizonSpring(
                view: header,
                fromTilt: -0.024,
                fromY: 14.0,
                fromScale: 0.96,
                dampingRatio: 0.84,
                response: 0.42,
                delay: 0.0,
                key: "settingsHeaderRise"
            )
        }
        if let stack = mainStackRef {
            for (i, sub) in stack.arrangedSubviews.prefix(8).enumerated() {
                AppleMotion.kineticHorizonSpring(
                    view: sub,
                    fromTilt: (i % 2 == 0) ? -0.022 : 0.020,
                    fromY: 16.0,
                    fromScale: 0.96,
                    dampingRatio: 0.84,
                    response: 0.44,
                    delay: 0.025 + Double(i) * 0.028,
                    key: "settingsRowRise_\(i)"
                )
            }
        }
    }

    private func setupGlassSurface() {
        glassCard.frame = bounds
        glassCard.autoresizingMask = [.width, .height]
        addSubview(glassCard)

        headerAccentLayer.colors = [
            NSColor.clear.cgColor,
            NSColor(red: 0.08, green: 0.42, blue: 0.94, alpha: 0.72).cgColor,
            NSColor(red: 0.18, green: 0.78, blue: 1.00, alpha: 0.78).cgColor,
            NSColor(red: 0.08, green: 0.36, blue: 0.86, alpha: 0.65).cgColor,
            NSColor.clear.cgColor
        ]
        headerAccentLayer.startPoint = CGPoint(x: 0, y: 0.5)
        headerAccentLayer.endPoint = CGPoint(x: 1, y: 0.5)
        glassCard.contentContainer.wantsLayer = true
        glassCard.contentContainer.layer?.addSublayer(headerAccentLayer)
    }

    private func setupControls() {
        let settings = AppSettings.shared
        let container = glassCard.contentContainer

        // Top Header Bar (Dual-weight "LoopSearch Studio" matching reference aesthetic)
        let logo = LoopBrandLogoView(size: 30)

        let titleLead = NSTextField(labelWithString: "LoopSearch")
        titleLead.font = .systemFont(ofSize: 18, weight: .regular)
        titleLead.textColor = .secondaryLabelColor

        let titleBold = NSTextField(labelWithString: "Studio")
        titleBold.font = .systemFont(ofSize: 18, weight: .bold)
        titleBold.textColor = .labelColor

        let titleRow = NSStackView(views: [titleLead, titleBold])
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 5

        let subtitleLabel = NSTextField(labelWithString: "Glass styling, motion and quick capture")
        subtitleLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor

        let titleStack = NSStackView(views: [titleRow, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let howToUseBtn = LiquidGlassButton(
            symbol: "book.pages",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Guide",
            tooltip: "Open quick How-to-Use guide",
            height: 26,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) {
            HowToUseWindowController.shared.show()
        }

        let welcomeBtn = LiquidGlassButton(
            symbol: "sparkles",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Setup",
            tooltip: "Open 3-Step Welcome Setup",
            height: 26,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) {
            OnboardingWindowController.shared.show()
        }

        let updatesBtn = LiquidGlassButton(
            symbol: "arrow.triangle.2.circlepath",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Updates",
            tooltip: "Check GitHub for updates",
            height: 26,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) {
            AppUpdateChecker.shared.installOrOpenAvailableUpdate()
        }
        updatesHeaderBtn = updatesBtn

        let aboutBtn = LiquidGlassButton(
            symbol: "info.circle",
            symbolPointSize: 11.5,
            symbolWeight: .medium,
            tooltip: "About LoopSearch",
            fixedSize: CGSize(width: 26, height: 26),
            style: .clear,
            foregroundColor: .labelColor
        ) {
            AboutWindowController.shared.show()
        }

        let topActionsGroup = LiquidGlassGroupView(spacing: 6)
        topActionsGroup.stackView.addArrangedSubview(howToUseBtn)
        topActionsGroup.stackView.addArrangedSubview(welcomeBtn)
        topActionsGroup.stackView.addArrangedSubview(updatesBtn)
        topActionsGroup.stackView.addArrangedSubview(aboutBtn)

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerRow = NSStackView(views: [logo, titleStack, headerSpacer, topActionsGroup])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(headerRow)
        headerRowRef = headerRow

        // Scrollable Settings Body
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        scrollViewRef = scrollView

        let docView = FlippedDocumentView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = docView

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(mainStack)
        mainStackRef = mainStack

        // Footer Bar
        let footerRow = makeFooterRow()
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(footerRow)

        NSLayoutConstraint.activate([
            headerRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            headerRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            headerRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            scrollView.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: footerRow.topAnchor, constant: -10),

            docView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            docView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),

            mainStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: 2),
            mainStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -8),

            footerRow.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 22),
            footerRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -22),
            footerRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        updateBannerCard = makeUpdateAvailableBanner()
        mainStack.addArrangedSubview(updateBannerCard)
        updateBannerCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // SECTION 0: GOOGLE ACCOUNT
        addSectionHeader("GOOGLE ACCOUNT", to: mainStack)
        let accountCard = makeGoogleAccountCard()
        mainStack.addArrangedSubview(accountCard)
        accountCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // SECTION 1: CAPTURE
        addSectionHeader("CAPTURE", to: mainStack)

        let modeOptions = SelectionMode.allCases.map {
            LiquidGlassSegmentedControl.Option(title: "\($0.shortcutBadge) \($0.shortTitle)", symbol: $0.symbolName)
        }
        modeSegment = LiquidGlassSegmentedControl(
            options: modeOptions,
            selectedIndex: SelectionMode.allCases.firstIndex(of: settings.selectionMode) ?? 0,
            height: 28,
            compact: true
        ) { idx in
            guard SelectionMode.allCases.indices.contains(idx) else { return }
            AppSettings.shared.selectionMode = SelectionMode.allCases[idx]
        }
        addRow(
            title: "Default Selection Mode",
            subtitle: "Press 1–4 in overlay or hold ⌥ to draw a Box",
            control: modeSegment,
            to: mainStack
        )

        // Shortened "Lens" pill label so it never clips
        let engineOptions = SearchEngine.allCases.map {
            LiquidGlassSegmentedControl.Option(title: $0.shortTitle, symbol: $0.symbolName)
        }
        engineSegment = LiquidGlassSegmentedControl(
            options: engineOptions,
            selectedIndex: SearchEngine.allCases.firstIndex(of: settings.searchEngine) ?? 0,
            height: 28,
            compact: true
        ) { idx in
            guard SearchEngine.allCases.indices.contains(idx) else { return }
            AppSettings.shared.searchEngine = SearchEngine.allCases[idx]
        }
        addRow(
            title: "Search Engine",
            subtitle: "Visual search & follow-up provider",
            control: engineSegment,
            to: mainStack
        )

        ocrToggle = LiquidGlassToggle(isOn: settings.showInlineOCR) { isOn in
            AppSettings.shared.showInlineOCR = isOn
        }
        addRow(
            title: "Live Text OCR Preview",
            subtitle: "Instant on-device text recognition & one-click copy",
            control: ocrToggle,
            to: mainStack
        )

        let afterOptions = AfterSelectionAction.allCases.map {
            LiquidGlassSegmentedControl.Option(title: $0.title, symbol: nil)
        }
        let afterSegment = LiquidGlassSegmentedControl(
            options: afterOptions,
            selectedIndex: AfterSelectionAction.allCases.firstIndex(of: settings.afterSelectionAction) ?? 0,
            height: 28,
            compact: true
        ) { idx in
            guard AfterSelectionAction.allCases.indices.contains(idx) else { return }
            AppSettings.shared.afterSelectionAction = AfterSelectionAction.allCases[idx]
        }
        addRow(
            title: "After Selection",
            subtitle: "Hold ⌥ Option on release anytime for quick Copy Text",
            control: afterSegment,
            to: mainStack
        )

        let panelTabOptions = PanelDefaultTab.allCases.map {
            LiquidGlassSegmentedControl.Option(title: $0.title, symbol: nil)
        }
        let panelTabSegment = LiquidGlassSegmentedControl(
            options: panelTabOptions,
            selectedIndex: PanelDefaultTab.allCases.firstIndex(of: settings.panelDefaultTab) ?? 0,
            height: 28,
            compact: true
        ) { idx in
            guard PanelDefaultTab.allCases.indices.contains(idx) else { return }
            AppSettings.shared.panelDefaultTab = PanelDefaultTab.allCases[idx]
        }
        addRow(
            title: "Panel Opens On",
            subtitle: "Default tab when results appear (remembered when changed)",
            control: panelTabSegment,
            to: mainStack
        )

        let blurToggle = LiquidGlassToggle(isOn: settings.blurOutsideSelectionBeforeSearch) { isOn in
            AppSettings.shared.blurOutsideSelectionBeforeSearch = isOn
        }
        addRow(
            title: "Blur Surroundings Before Search",
            subtitle: "Offer to blur everything outside your selection before uploading",
            control: blurToggle,
            to: mainStack
        )

        let syncToggle = LiquidGlassToggle(isOn: settings.enableEncryptedSync) { isOn in
            AppSettings.shared.enableEncryptedSync = isOn
            LocalSyncService.shared.startIfEnabled()
        }
        addRow(
            title: "Encrypted LAN Sync (Off by default)",
            subtitle: AppSettings.privacyStatement,
            control: syncToggle,
            to: mainStack
        )

        // SECTION 2: APPEARANCE & COMFORT
        addSectionHeader("APPEARANCE & COMFORT", to: mainStack)

        let themeOptions = AppTheme.allCases.map {
            LiquidGlassSegmentedControl.Option(title: $0.title, symbol: $0.symbolName)
        }
        themeSegment = LiquidGlassSegmentedControl(
            options: themeOptions,
            selectedIndex: AppTheme.allCases.firstIndex(of: settings.theme) ?? 0,
            height: 28,
            compact: true
        ) { idx in
            guard AppTheme.allCases.indices.contains(idx) else { return }
            AppSettings.shared.theme = AppTheme.allCases[idx]
        }
        addRow(
            title: "Appearance Theme",
            subtitle: "Follow macOS system setting or force Dark / Light glass",
            control: themeSegment,
            to: mainStack
        )

        webThemeSegment = LiquidGlassSegmentedControl(
            options: themeOptions,
            selectedIndex: AppTheme.allCases.firstIndex(of: settings.webResultsTheme) ?? 0,
            height: 28,
            compact: true
        ) { idx in
            guard AppTheme.allCases.indices.contains(idx) else { return }
            AppSettings.shared.webResultsTheme = AppTheme.allCases[idx]
        }
        addRow(
            title: "Results Browser Theme",
            subtitle: "Auto-match macOS/App theme or force Dark / Light Google Lens page",
            control: webThemeSegment,
            to: mainStack
        )

        let styleOptions = VisualStylePreset.allCases.map {
            LiquidGlassSegmentedControl.Option(title: $0.title, symbol: $0.symbolName)
        }
        styleSegment = LiquidGlassSegmentedControl(
            options: styleOptions,
            selectedIndex: VisualStylePreset.allCases.firstIndex(of: settings.visualStyle) ?? 1,
            height: 28,
            compact: true
        ) { idx in
            guard VisualStylePreset.allCases.indices.contains(idx) else { return }
            AppSettings.shared.visualStyle = VisualStylePreset.allCases[idx]
        }
        addRow(
            title: "Style (Glow & Motion)",
            subtitle: "Unified preset balancing border bloom and spring physics",
            control: styleSegment,
            to: mainStack
        )

        let paletteOptions = GlowColorTheme.allCases.map {
            LiquidGlassSegmentedControl.Option(title: $0.title, symbol: $0.symbolName)
        }
        paletteSegment = LiquidGlassSegmentedControl(
            options: paletteOptions,
            selectedIndex: GlowColorTheme.allCases.firstIndex(of: settings.glowColorTheme) ?? 0,
            height: 28,
            compact: true
        ) { idx in
            guard GlowColorTheme.allCases.indices.contains(idx) else { return }
            AppSettings.shared.glowColorTheme = GlowColorTheme.allCases[idx]
        }
        addRow(
            title: "Signature Glow Palette",
            subtitle: "Horizon Blue (Cobalt/Azure/Ice Cyan) or full RGB Spectrum",
            control: paletteSegment,
            to: mainStack
        )

        starsToggle = LiquidGlassToggle(isOn: settings.showAmbientStars) { isOn in
            AppSettings.shared.showAmbientStars = isOn
        }
        addRow(
            title: "Ambient Stardust",
            subtitle: "Soft twinkling particles around the selection trail",
            control: starsToggle,
            to: mainStack
        )

        reduceMotionToggle = LiquidGlassToggle(isOn: settings.reduceMotion) { isOn in
            AppSettings.shared.reduceMotion = isOn
        }
        addRow(
            title: "Reduce Motion & Comfort",
            subtitle: "Tones down glow bleed, particle trails, and spring bounce",
            control: reduceMotionToggle,
            to: mainStack
        )

        // SECTION 3: ASK AI (KEYCHAIN)
        addSectionHeader("ASK AI (KEYCHAIN)", to: mainStack)
        let aiCard = makeAskAICard()
        mainStack.addArrangedSubview(aiCard)
        aiCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // SECTION 4: GLOBAL SHORTCUT
        addSectionHeader("GLOBAL SHORTCUT", to: mainStack)
        let hotkeyCard = makeHotkeyCard(initialPreset: settings.hotkeyPreset)
        mainStack.addArrangedSubview(hotkeyCard)
        hotkeyCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // SECTION 5: SYSTEM & PRIVACY
        addSectionHeader("SYSTEM & PRIVACY", to: mainStack)

        launchAtLoginToggle = LiquidGlassToggle(isOn: settings.launchAtLogin) { isOn in
            AppSettings.shared.launchAtLogin = isOn
        }
        addRow(
            title: "Launch at Login",
            subtitle: "Start LoopSearch automatically when you sign in",
            control: launchAtLoginToggle,
            to: mainStack
        )

        hideDockToggle = LiquidGlassToggle(isOn: settings.hideDockIcon) { isOn in
            AppSettings.shared.hideDockIcon = isOn
        }
        addRow(
            title: "Menu Bar Mode (Hide Dock Icon)",
            subtitle: "Keep LoopSearch quietly in the top menu bar",
            control: hideDockToggle,
            to: mainStack
        )

        autoUpdateToggle = LiquidGlassToggle(isOn: settings.autoCheckForUpdates) { isOn in
            AppSettings.shared.autoCheckForUpdates = isOn
        }
        addRow(
            title: "Automatically Check for Updates",
            subtitle: "Check GitHub Releases on launch with 1-click install",
            control: autoUpdateToggle,
            to: mainStack
        )

        let permCard = makePermissionRow()
        mainStack.addArrangedSubview(permCard)
        permCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // SECTION 6: SEARCH HISTORY
        addSectionHeader("SEARCH HISTORY", to: mainStack)
        let historyCard = makeSearchHistoryCard()
        mainStack.addArrangedSubview(historyCard)
        historyCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // SECTION 7: CREATOR & SUPPORT
        addSectionHeader("CREATOR & SUPPORT", to: mainStack)
        let supportCard = makeCreatorSupportCard(compact: false)
        mainStack.addArrangedSubview(supportCard)
        supportCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        refreshAuthCard()
        refreshHotkeyUI()
        refreshUpdateBanner(animated: false)
    }

    func animateVisibleCardsIn() {
        layoutSubtreeIfNeeded()
        scrollViewRef?.contentView.scroll(.zero)
        if let contentView = scrollViewRef?.contentView {
            scrollViewRef?.reflectScrolledClipView(contentView)
        }
        guard let stack = mainStackRef else { return }
        let cards = stack.arrangedSubviews.filter { !$0.isHidden && $0 is LiquidGlassSurfaceView }
        AppleMotion.staggeredCardsReveal(Array(cards.prefix(7)), baseDelay: 0.02, stepDelay: 0.032)
    }

    private func makeUpdateAvailableBanner() -> LiquidGlassSurfaceView {
        let card = LiquidGlassSurfaceView(
            cornerRadius: 14,
            style: .regular,
            tintColor: NSColor(red: 0.07, green: 0.30, blue: 0.68, alpha: 0.30),
            lightTintColor: NSColor(red: 0.14, green: 0.46, blue: 0.94, alpha: 0.14)
        )
        card.horizonGlowIntensity = 0.72
        card.horizonPoolHeightFraction = 0.56
        card.horizonRimStrength = 0.95
        card.isHidden = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let logo = LoopBrandLogoView(size: 30)
        logo.translatesAutoresizingMaskIntoConstraints = false

        updateBannerTitleLabel = NSTextField(labelWithString: "Update Available")
        updateBannerTitleLabel.font = .systemFont(ofSize: 12.5, weight: .bold)
        updateBannerTitleLabel.textColor = .labelColor

        updateBannerDetailLabel = NSTextField(labelWithString: "A new version of LoopSearch is ready to install.")
        updateBannerDetailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        updateBannerDetailLabel.textColor = .secondaryLabelColor
        updateBannerDetailLabel.lineBreakMode = .byTruncatingTail

        let textCol = NSStackView(views: [updateBannerTitleLabel, updateBannerDetailLabel])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 1
        textCol.setContentHuggingPriority(.defaultLow, for: .horizontal)

        updateBannerActionBtn = LiquidGlassButton(
            symbol: "arrow.down.circle.fill",
            symbolPointSize: 11,
            symbolWeight: .semibold,
            title: "Install Update",
            tooltip: "Download and install the latest LoopSearch release",
            height: 28,
            minWidth: 118,
            style: .clear,
            foregroundColor: .white,
            font: .systemFont(ofSize: 11.5, weight: .semibold)
        ) {
            AppUpdateChecker.shared.installOrOpenAvailableUpdate()
        }
        updateBannerActionBtn.setSelectedAccent(true)
        updateBannerActionBtn.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [logo, textCol, updateBannerActionBtn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -10)
        ])

        return card
    }

    private func refreshUpdateBanner(animated: Bool) {
        if let update = AppUpdateChecker.shared.availableUpdate {
            updateBannerTitleLabel.stringValue = "Update Available — LoopSearch v\(update.version)"
            let noteSnippet = update.notes
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: "*", with: "")
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "New improvements and fixes ready to install."
            updateBannerDetailLabel.stringValue = "Current v\(AppUpdateChecker.currentVersion) • \(noteSnippet)"
            updateBannerActionBtn.title = "Install v\(update.version)"
            updatesHeaderBtn?.title = "Update v\(update.version)"
            updatesHeaderBtn?.setSelectedAccent(true)
            if updateBannerCard.isHidden {
                if animated {
                    AppleMotion.animateVisibility(updateBannerCard, visible: true, scale: 0.96, duration: 0.24)
                } else {
                    updateBannerCard.isHidden = false
                    updateBannerCard.alphaValue = 1.0
                }
            }
        } else {
            updatesHeaderBtn?.title = "Updates"
            updatesHeaderBtn?.setSelectedAccent(false)
            if !updateBannerCard.isHidden {
                if animated {
                    AppleMotion.animateVisibility(updateBannerCard, visible: false, scale: 0.96, duration: 0.20)
                } else {
                    updateBannerCard.isHidden = true
                }
            }
        }
    }

    private func makeGoogleAccountCard() -> NSView {
        let card = makeSettingsGlassCard(cornerRadius: 14)

        let avatarBox = NSView()
        avatarBox.wantsLayer = true
        avatarBox.layer?.cornerRadius = 18
        avatarBox.layer?.masksToBounds = true
        avatarBox.layer?.backgroundColor = NSColor(red: 0.10, green: 0.42, blue: 0.92, alpha: 0.24).cgColor
        avatarBox.layer?.borderWidth = 0.85
        avatarBox.layer?.borderColor = NSColor(red: 0.32, green: 0.82, blue: 1.0, alpha: 0.36).cgColor
        avatarBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            avatarBox.widthAnchor.constraint(equalToConstant: 36),
            avatarBox.heightAnchor.constraint(equalToConstant: 36)
        ])

        authMonogramLabel = NSTextField(labelWithString: "G")
        authMonogramLabel.font = .systemFont(ofSize: 14, weight: .bold)
        authMonogramLabel.textColor = NSColor(red: 0.42, green: 0.86, blue: 1.0, alpha: 1.0)
        authMonogramLabel.alignment = .center
        authMonogramLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarBox.addSubview(authMonogramLabel)

        authAvatarView = NSImageView()
        authAvatarView.imageScaling = .scaleProportionallyUpOrDown
        authAvatarView.translatesAutoresizingMaskIntoConstraints = false
        authAvatarView.isHidden = true
        avatarBox.addSubview(authAvatarView)

        NSLayoutConstraint.activate([
            authMonogramLabel.centerXAnchor.constraint(equalTo: avatarBox.centerXAnchor),
            authMonogramLabel.centerYAnchor.constraint(equalTo: avatarBox.centerYAnchor),
            authAvatarView.leadingAnchor.constraint(equalTo: avatarBox.leadingAnchor),
            authAvatarView.trailingAnchor.constraint(equalTo: avatarBox.trailingAnchor),
            authAvatarView.topAnchor.constraint(equalTo: avatarBox.topAnchor),
            authAvatarView.bottomAnchor.constraint(equalTo: avatarBox.bottomAnchor)
        ])

        authNameLabel = NSTextField(labelWithString: "Google Sign-In Required")
        authNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        authNameLabel.textColor = .labelColor
        authNameLabel.lineBreakMode = .byTruncatingTail

        authStatusLabel = NSTextField(labelWithString: "Required")
        authStatusLabel.font = .systemFont(ofSize: 10.5, weight: .bold)
        authStatusLabel.textColor = .systemOrange

        let nameRow = NSStackView(views: [authNameLabel, authStatusLabel])
        nameRow.orientation = .horizontal
        nameRow.alignment = .firstBaseline
        nameRow.spacing = 8

        authDetailLabel = NSTextField(labelWithString: "Sign in with Google to use LoopSearch.")
        authDetailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        authDetailLabel.textColor = .secondaryLabelColor
        authDetailLabel.lineBreakMode = .byTruncatingMiddle

        let textCol = NSStackView(views: [nameRow, authDetailLabel])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        textCol.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textCol.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        authPrimaryBtn = LiquidGlassButton(
            symbol: "person.crop.circle.badge.checkmark",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Sign in with Google",
            tooltip: "Sign in with your Google account",
            height: 26,
            minWidth: 140,
            style: .clear,
            tintColor: NSColor(red: 0.08, green: 0.38, blue: 0.86, alpha: 0.88),
            lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.92),
            foregroundColor: .white,
            font: .systemFont(ofSize: 11, weight: .semibold)
        ) {
            let auth = FirebaseAuthService.shared
            if auth.isSigningIn {
                auth.cancelSignIn()
                return
            }
            Task { @MainActor in
                _ = await FirebaseAuthService.shared.signInWithGoogle()
            }
        }

        authSignOutBtn = LiquidGlassButton(
            symbol: "rectangle.portrait.and.arrow.right",
            symbolPointSize: 10,
            symbolWeight: .medium,
            title: "Sign Out",
            tooltip: "Sign out of Google Account",
            height: 26,
            minWidth: 82,
            style: .clear,
            foregroundColor: .secondaryLabelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) {
            FirebaseAuthService.shared.signOut()
            OnboardingWindowController.shared.show()
        }

        authPrimaryBtn.setContentHuggingPriority(.required, for: .horizontal)
        authSignOutBtn.setContentHuggingPriority(.required, for: .horizontal)

        let actionRow = NSStackView(views: [authPrimaryBtn, authSignOutBtn])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 6
        actionRow.setContentHuggingPriority(.required, for: .horizontal)
        actionRow.setContentCompressionResistancePriority(.required, for: .horizontal)

        let accountSpacer = NSView()
        accountSpacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let row = NSStackView(views: [avatarBox, textCol, accountSpacer, actionRow])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            row.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -10)
        ])

        return card
    }

    private func refreshAuthCard() {
        let auth = FirebaseAuthService.shared

        if let session = auth.session {
            authNameLabel.stringValue = session.effectiveDisplayName
            authStatusLabel.stringValue = "✓ Signed In"
            authStatusLabel.textColor = .systemGreen
            authDetailLabel.stringValue = session.email.isEmpty ? "Authenticated via Google" : session.email
            authDetailLabel.textColor = .secondaryLabelColor
            authMonogramLabel.stringValue = session.initials

            if let img = auth.avatarImage {
                authAvatarView.image = img
                authAvatarView.isHidden = false
                authMonogramLabel.isHidden = true
            } else {
                authAvatarView.isHidden = true
                authMonogramLabel.isHidden = false
            }

            authPrimaryBtn.title = auth.isSigningIn ? "Cancel" : "Switch"
            authPrimaryBtn.setSelectedAccent(false)
            authSignOutBtn.isHidden = auth.isSigningIn
        } else {
            authAvatarView.isHidden = true
            authMonogramLabel.isHidden = false
            authMonogramLabel.stringValue = "G"
            authSignOutBtn.isHidden = true

            if auth.isSigningIn {
                authNameLabel.stringValue = "Waiting for Google Sign-In…"
                authStatusLabel.stringValue = "In Browser"
                authStatusLabel.textColor = NSColor(red: 0.36, green: 0.84, blue: 1.0, alpha: 1.0)
                authDetailLabel.stringValue = "Complete sign-in in your browser, then return here."
                authDetailLabel.textColor = .secondaryLabelColor
                authPrimaryBtn.title = "Cancel"
                authPrimaryBtn.setSelectedAccent(false)
            } else {
                authNameLabel.stringValue = "Google Sign-In Required"
                authStatusLabel.stringValue = "Required"
                authStatusLabel.textColor = .systemOrange
                if let err = auth.lastAuthError, !err.isEmpty {
                    authDetailLabel.stringValue = err
                    authDetailLabel.textColor = .systemOrange
                } else {
                    authDetailLabel.stringValue = "Sign in once (name & email only) — works offline afterward."
                    authDetailLabel.textColor = .secondaryLabelColor
                }
                authPrimaryBtn.title = "Sign in with Google"
                authPrimaryBtn.setSelectedAccent(true)
            }
        }
    }

    private func addSectionHeader(_ text: String, to stack: NSStackView) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10.5, weight: .bold)
        label.textColor = .secondaryLabelColor
        stack.addArrangedSubview(label)
    }

    private func addRow(
        title: String,
        subtitle: String,
        control: NSView,
        to stack: NSStackView
    ) {
        let card = makeSettingsGlassCard(cornerRadius: 14)
        card.heightAnchor.constraint(equalToConstant: 50).isActive = true

        let tLabel = NSTextField(labelWithString: title)
        tLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        tLabel.textColor = .labelColor

        let sLabel = NSTextField(labelWithString: subtitle)
        sLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        sLabel.textColor = .secondaryLabelColor
        sLabel.lineBreakMode = .byTruncatingTail

        let textStack = NSStackView(views: [tLabel, sLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [textStack, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: card.contentContainer.centerYAnchor)
        ])

        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeAskAICard() -> NSView {
        let card = makeSettingsGlassCard(cornerRadius: 14)

        let topTitle = NSTextField(labelWithString: "Gemini API Key (Optional — Stored in macOS Keychain)")
        topTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        topTitle.textColor = .labelColor

        let getKeyBtn = LiquidGlassButton(
            symbol: "arrow.up.right.square",
            symbolPointSize: 10,
            symbolWeight: .semibold,
            title: "Get API Key",
            tooltip: "Open Google AI Studio",
            height: 22,
            minWidth: 92,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 10.5, weight: .semibold)
        ) {
            if let url = URL(string: "https://aistudio.google.com/app/apikey") {
                NSWorkspace.shared.open(url)
            }
        }

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [topTitle, topSpacer, getKeyBtn])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY

        apiKeyField = NSSecureTextField()
        apiKeyField.placeholderString = "Paste AIzaSy... Gemini key (leave blank for on-device Vision)"
        apiKeyField.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        apiKeyField.stringValue = KeychainHelper.loadAPIKey()
        apiKeyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        apiKeyField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        apiKeyField.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true

        let saveBtn = LiquidGlassButton(
            symbol: "key.fill",
            symbolPointSize: 10,
            symbolWeight: .semibold,
            title: "Save to Keychain",
            tooltip: "Save API key securely in macOS Keychain",
            height: 25,
            minWidth: 118,
            style: .clear,
            tintColor: NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.84),
            lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.90),
            foregroundColor: .white,
            font: .systemFont(ofSize: 11, weight: .semibold)
        ) { [weak self] in
            guard let self else { return }
            let trimmed = self.apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            KeychainHelper.saveAPIKey(trimmed)
            self.apiKeyStatusLabel.stringValue = trimmed.isEmpty
                ? "Cleared key — using instant on-device Vision synthesis"
                : "✓ Saved securely in macOS Keychain"
        }

        let inputRow = NSStackView(views: [apiKeyField, saveBtn])
        inputRow.orientation = .horizontal
        inputRow.alignment = .centerY
        inputRow.spacing = 8

        let hasKey = !KeychainHelper.loadAPIKey().isEmpty
        apiKeyStatusLabel = NSTextField(labelWithString: hasKey
            ? "✓ Gemini API key saved in macOS Keychain"
            : "Works out-of-the-box with on-device Vision; add a key for Gemini 2.5 Flash vision answers.")
        apiKeyStatusLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        apiKeyStatusLabel.textColor = .secondaryLabelColor

        let policyNote = NSTextField(labelWithString: "Note: Google AI Studio keys require 18+ and free-tier prompts may be reviewed by Google.")
        policyNote.font = .systemFont(ofSize: 10.0, weight: .regular)
        policyNote.textColor = .tertiaryLabelColor

        let vStack = NSStackView(views: [topRow, inputRow, apiKeyStatusLabel, policyNote])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 6
        vStack.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(vStack)

        topRow.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
        inputRow.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            vStack.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            vStack.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 10),
            vStack.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -10)
        ])

        return card
    }

    private func makeHotkeyCard(initialPreset: HotkeyPreset) -> NSView {
        let card = makeSettingsGlassCard(cornerRadius: 14)

        let topTitle = NSTextField(labelWithString: "Activation Shortcut")
        topTitle.font = .systemFont(ofSize: 12.5, weight: .semibold)
        topTitle.textColor = .labelColor

        hotkeyValueLabel = NSTextField(labelWithString: initialPreset.title)
        hotkeyValueLabel.font = .monospacedSystemFont(ofSize: 12.0, weight: .bold)
        hotkeyValueLabel.textColor = NSColor(red: 0.42, green: 0.80, blue: 1.0, alpha: 1.0)

        recordShortcutButton = LiquidGlassButton(
            symbol: "record.circle",
            symbolPointSize: 11,
            symbolWeight: .semibold,
            title: "Record Shortcut…",
            tooltip: "Click and press any modifier + key combination",
            height: 25,
            minWidth: 148,
            style: .clear,
            tintColor: NSColor(red: 0.06, green: 0.20, blue: 0.44, alpha: 0.72),
            lightTintColor: NSColor(red: 0.84, green: 0.90, blue: 0.98, alpha: 0.80),
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .semibold)
        ) { [weak self] in
            self?.toggleShortcutRecording()
        }
        recordShortcutButton.setContentHuggingPriority(.required, for: .horizontal)
        hotkeyValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [topTitle, topSpacer, hotkeyValueLabel, recordShortcutButton])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        let presetsRow = NSStackView()
        presetsRow.orientation = .vertical
        presetsRow.alignment = .leading
        presetsRow.distribution = .fill
        presetsRow.spacing = 6

        let featuredPresets: [HotkeyPreset] = [.doubleTapCmd, .cmdShiftSpace, .doubleTapOption, .optionSpace]
        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.distribution = .fillEqually
        rowStack.spacing = 6
        for preset in featuredPresets {
            let btn = LiquidGlassButton(
                title: preset.title,
                tooltip: preset.subtitle,
                height: 26,
                style: .clear,
                foregroundColor: .secondaryLabelColor,
                font: .systemFont(ofSize: 11, weight: .medium)
            ) { [weak self] in
                self?.cancelShortcutRecording()
                AppSettings.shared.hotkeyPreset = preset
                self?.refreshHotkeyUI()
            }
            presetButtons[preset] = btn
            rowStack.addArrangedSubview(btn)
        }
        presetsRow.addArrangedSubview(rowStack)
        rowStack.widthAnchor.constraint(equalTo: presetsRow.widthAnchor).isActive = true

        // Common Shortcut Conflict Warning Banner
        shortcutWarningBanner = LiquidGlassSurfaceView(
            cornerRadius: 10,
            style: .clear,
            tintColor: NSColor.systemOrange.withAlphaComponent(0.14),
            lightTintColor: NSColor.systemOrange.withAlphaComponent(0.10)
        )
        shortcutWarningBanner.horizonRimStrength = 0.10
        shortcutWarningBanner.translatesAutoresizingMaskIntoConstraints = false
        shortcutWarningBanner.isHidden = true

        shortcutWarningLabel = NSTextField(labelWithString: "")
        shortcutWarningLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        shortcutWarningLabel.textColor = .labelColor
        shortcutWarningLabel.lineBreakMode = .byTruncatingTail
        shortcutWarningLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let useRecommendedBtn = LiquidGlassButton(
            title: "Use ⌘ + ⇧ + Space",
            tooltip: "Switch to recommended shortcut",
            height: 22,
            minWidth: 118,
            style: .clear,
            tintColor: NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.84),
            lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.90),
            foregroundColor: .white,
            font: .systemFont(ofSize: 10.5, weight: .semibold)
        ) { [weak self] in
            AppSettings.shared.hotkeyPreset = .cmdShiftSpace
            self?.refreshHotkeyUI()
        }

        let warnRow = NSStackView(views: [shortcutWarningLabel, useRecommendedBtn])
        warnRow.orientation = .horizontal
        warnRow.alignment = .centerY
        warnRow.spacing = 8
        warnRow.translatesAutoresizingMaskIntoConstraints = false
        shortcutWarningBanner.contentContainer.addSubview(warnRow)
        NSLayoutConstraint.activate([
            warnRow.leadingAnchor.constraint(equalTo: shortcutWarningBanner.contentContainer.leadingAnchor, constant: 10),
            warnRow.trailingAnchor.constraint(equalTo: shortcutWarningBanner.contentContainer.trailingAnchor, constant: -8),
            warnRow.topAnchor.constraint(equalTo: shortcutWarningBanner.contentContainer.topAnchor, constant: 5),
            warnRow.bottomAnchor.constraint(equalTo: shortcutWarningBanner.contentContainer.bottomAnchor, constant: -5)
        ])

        let vStack = NSStackView(views: [topRow, presetsRow, shortcutWarningBanner])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 8
        vStack.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(vStack)

        topRow.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
        presetsRow.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
        shortcutWarningBanner.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            vStack.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            vStack.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 10),
            vStack.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -10)
        ])

        return card
    }

    private func makePermissionRow() -> NSView {
        let card = makeSettingsGlassCard(cornerRadius: 14)
        card.heightAnchor.constraint(equalToConstant: 46).isActive = true

        let granted = CGPreflightScreenCaptureAccess()
        permissionBadgeLabel = NSTextField(labelWithString: granted ? "✓ Screen Recording Granted" : "⚠ Screen Recording Needed")
        permissionBadgeLabel.font = .systemFont(ofSize: 12.0, weight: .semibold)
        permissionBadgeLabel.textColor = granted ? .systemGreen : .systemOrange

        let openPrivacyBtn = LiquidGlassButton(
            symbol: "lock.shield",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Privacy Settings",
            tooltip: "Open macOS Screen Recording Settings",
            height: 25,
            minWidth: 118,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
            }
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [permissionBadgeLabel, spacer, openPrivacyBtn])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            row.centerYAnchor.constraint(equalTo: card.contentContainer.centerYAnchor)
        ])

        return card
    }

    private func makeSearchHistoryCard() -> NSView {
        let card = makeSettingsGlassCard(cornerRadius: 14)

        historyCountLabel = NSTextField(labelWithString: "Recent Searches (0)")
        historyCountLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        historyCountLabel.textColor = .labelColor

        clearInlineHistoryBtn = LiquidGlassButton(
            symbol: "trash",
            symbolPointSize: 10,
            symbolWeight: .medium,
            title: "Clear",
            tooltip: "Clear recent search history",
            height: 23,
            minWidth: 68,
            style: .clear,
            foregroundColor: .secondaryLabelColor,
            font: .systemFont(ofSize: 10.5, weight: .semibold)
        ) {
            CaptureHistoryStore.shared.clear()
        }

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [historyCountLabel, topSpacer, clearInlineHistoryBtn])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        historyListStack = NSStackView()
        historyListStack.orientation = .vertical
        historyListStack.alignment = .leading
        historyListStack.spacing = 7
        historyListStack.translatesAutoresizingMaskIntoConstraints = false

        let vStack = NSStackView(views: [topRow, historyListStack])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 8
        vStack.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(vStack)

        topRow.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true
        historyListStack.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            vStack.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            vStack.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            vStack.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 10),
            vStack.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -10)
        ])

        reloadHistoryList()
        return card
    }

    private func reloadHistoryList() {
        let items = CaptureHistoryStore.shared.items
        historyCountLabel.stringValue = "Recent Searches (\(items.count))"
        clearInlineHistoryBtn.isHidden = items.isEmpty

        historyListStack.arrangedSubviews.forEach { view in
            historyListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if items.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No recent searches yet — press your shortcut and circle anything on screen.")
            emptyLabel.font = .systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.lineBreakMode = .byWordWrapping
            emptyLabel.maximumNumberOfLines = 2
            historyListStack.addArrangedSubview(emptyLabel)
            return
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let now = Date()

        for (index, entry) in items.prefix(6).enumerated() {
            let rowCard = NSView()
            rowCard.wantsLayer = true
            rowCard.layer?.cornerRadius = 10
            rowCard.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.035).cgColor
            rowCard.layer?.borderWidth = 0.75
            rowCard.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
            rowCard.translatesAutoresizingMaskIntoConstraints = false
            rowCard.heightAnchor.constraint(equalToConstant: 46).isActive = true

            let thumb = NSImageView()
            thumb.image = NSImage(
                cgImage: entry.cgImage,
                size: NSSize(width: entry.cgImage.width, height: entry.cgImage.height)
            )
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.masksToBounds = true
            thumb.layer?.borderWidth = 0.6
            thumb.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            thumb.translatesAutoresizingMaskIntoConstraints = false
            thumb.widthAnchor.constraint(equalToConstant: 46).isActive = true
            thumb.heightAnchor.constraint(equalToConstant: 32).isActive = true

            let cleanText = entry.recognizedText
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let primaryTitle = cleanText.isEmpty
                ? "Visual region (\(entry.cgImage.width) × \(entry.cgImage.height))"
                : cleanText
            let titleLabel = NSTextField(labelWithString: primaryTitle)
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
            titleLabel.textColor = .labelColor
            titleLabel.lineBreakMode = .byTruncatingTail
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let relTime = formatter.localizedString(for: entry.timestamp, relativeTo: now)
            let hexPart = entry.dominantHex.isEmpty ? "" : " • \(entry.dominantHex)"
            let subtitleLabel = NSTextField(labelWithString: "\(relTime)\(hexPart)")
            subtitleLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byTruncatingTail

            let textStack = NSStackView(views: [titleLabel, subtitleLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 1.5
            textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 9
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            rowStack.addArrangedSubview(thumb)
            rowStack.addArrangedSubview(textStack)

            if !cleanText.isEmpty {
                let copyBtn = LiquidGlassButton(
                    symbol: "doc.on.doc",
                    symbolPointSize: 9.5,
                    symbolWeight: .medium,
                    title: "Copy",
                    tooltip: "Copy recognized text",
                    height: 23,
                    minWidth: 62,
                    style: .clear,
                    foregroundColor: .secondaryLabelColor,
                    font: .systemFont(ofSize: 10.5, weight: .medium)
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.recognizedText, forType: .string)
                }
                rowStack.addArrangedSubview(copyBtn)
            }

            let reopenBtn = LiquidGlassButton(
                symbol: "arrow.up.forward.square",
                symbolPointSize: 10,
                symbolWeight: .semibold,
                title: "Reopen",
                tooltip: "Reopen this visual search",
                height: 23,
                minWidth: 74,
                style: .clear,
                tintColor: NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.82),
                lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.90),
                foregroundColor: .white,
                font: .systemFont(ofSize: 10.5, weight: .semibold)
            ) {
                NotificationCenter.default.post(
                    name: .circleToSearchReopenHistory,
                    object: nil,
                    userInfo: ["index": index]
                )
            }
            rowStack.addArrangedSubview(reopenBtn)

            rowCard.addSubview(rowStack)
            NSLayoutConstraint.activate([
                rowStack.leadingAnchor.constraint(equalTo: rowCard.leadingAnchor, constant: 8),
                rowStack.trailingAnchor.constraint(equalTo: rowCard.trailingAnchor, constant: -8),
                rowStack.centerYAnchor.constraint(equalTo: rowCard.centerYAnchor)
            ])

            historyListStack.addArrangedSubview(rowCard)
            rowCard.widthAnchor.constraint(equalTo: historyListStack.widthAnchor).isActive = true
        }
    }

    private func makeFooterRow() -> NSView {
        let vStack = NSStackView()
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 6

        let privacyLine = NSTextField(labelWithString: "Selections are sent only to the search engine you pick • Independent app, not affiliated with Google LLC")
        privacyLine.font = .systemFont(ofSize: 10.5, weight: .regular)
        privacyLine.textColor = .secondaryLabelColor

        let resetBtn = LiquidGlassButton(
            symbol: "arrow.counterclockwise",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Reset to Defaults",
            tooltip: "Restore default LoopSearch settings",
            height: 25,
            minWidth: 126,
            style: .clear,
            foregroundColor: .secondaryLabelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) { [weak self] in
            AppSettings.shared.resetToDefaults()
            self?.refreshFromSettings()
        }

        let copyDiagBtn = LiquidGlassButton(
            symbol: "doc.on.doc",
            symbolPointSize: 10.5,
            symbolWeight: .medium,
            title: "Copy Diagnostics",
            tooltip: "Copy non-personal app & macOS diagnostics for support",
            height: 25,
            minWidth: 124,
            style: .clear,
            foregroundColor: .secondaryLabelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) { [weak self] in
            self?.copyDiagnosticsToPasteboard()
        }

        let clearHistBtn = LiquidGlassButton(
            symbol: "trash",
            symbolPointSize: 10.5,
            symbolWeight: .medium,
            title: "Clear History",
            tooltip: "Clear recent captures",
            height: 25,
            minWidth: 102,
            style: .clear,
            foregroundColor: .secondaryLabelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) {
            CaptureHistoryStore.shared.clear()
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bottomActions = NSStackView(views: [copyDiagBtn, spacer, resetBtn, clearHistBtn])
        bottomActions.orientation = .horizontal
        bottomActions.alignment = .centerY
        bottomActions.spacing = 8
        vStack.addArrangedSubview(privacyLine)
        vStack.addArrangedSubview(bottomActions)
        bottomActions.widthAnchor.constraint(equalTo: vStack.widthAnchor).isActive = true

        return vStack
    }

    // MARK: - Live Custom Shortcut Recording

    private func toggleShortcutRecording() {
        isRecordingShortcut.toggle()
        if isRecordingShortcut {
            recordShortcutButton.title = "Press keys… (Esc)"
            recordShortcutButton.setSelectedAccent(true)
            hotkeyValueLabel.stringValue = "Listening…"
        } else {
            refreshHotkeyUI()
        }
    }

    func cancelShortcutRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        refreshHotkeyUI()
    }

    private func copyDiagnosticsToPasteboard() {
        let s = AppSettings.shared
        let ver = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? AppUpdateChecker.currentVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let screenPerm = CGPreflightScreenCaptureAccess() ? "Granted" : "Not Granted"
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #elseif arch(x86_64)
            return "x86_64"
            #else
            return "unknown"
            #endif
        }()
        let report = """
        LoopSearch Diagnostics
        Version: \(ver) (build \(build)) [\(arch)]
        macOS: \(os)
        Screen Recording: \(screenPerm)
        Hotkey: \(s.activeHotkeyDisplayString) (custom=\(s.useCustomHotkey))
        App Theme: \(s.theme.rawValue) | Web Results Theme: \(s.webResultsTheme.rawValue)
        Selection Mode: \(s.selectionMode.rawValue) | Engine: \(s.searchEngine.rawValue)
        Dock Icon: \(s.hideDockIcon ? "Hidden" : "Visible") | Launch at Login: \(s.launchAtLogin)
        Signed In: \(FirebaseAuthService.shared.isSignedIn)
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(report, forType: .string)
        hotkeyValueLabel.stringValue = "Copied Diagnostics ✓"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, !self.isRecordingShortcut else { return }
            self.hotkeyValueLabel.stringValue = AppSettings.shared.activeHotkeyDisplayString
        }
    }

    func handleCapturedKeyEvent(_ event: NSEvent) -> Bool {
        guard isRecordingShortcut else { return false }

        switch ShortcutCaptureResult.parse(event) {
        case .cancelled:
            cancelShortcutRecording()
            return true
        case .modifierOnly:
            return true
        case .missingModifiers:
            NSSound.beep()
            return true
        case .captured(let keyCode, let carbonMods, let label):
            isRecordingShortcut = false
            AppSettings.shared.setCustomHotkey(
                keyCode: keyCode,
                carbonModifiers: carbonMods,
                displayString: label
            )
            refreshHotkeyUI()
            return true
        }
    }

    private func refreshHotkeyUI() {
        let settings = AppSettings.shared
        hotkeyValueLabel.stringValue = settings.activeHotkeyDisplayString
        recordShortcutButton.title = "Record Shortcut…"
        recordShortcutButton.setSelectedAccent(false)

        let activePreset = settings.useCustomHotkey ? nil : settings.hotkeyPreset
        for (preset, btn) in presetButtons {
            let isSelected = (preset == activePreset)
            btn.setSelectedAccent(isSelected)
            btn.alphaValue = 1.0
        }

        if let warning = activePreset?.commonUsageWarning {
            shortcutWarningLabel.stringValue = "⚠ \(warning)"
            shortcutWarningBanner.isHidden = false
        } else {
            shortcutWarningBanner.isHidden = true
        }
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - First-Run 4-Step Welcome Setup & Google Sign-In Gate

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private weak var contentViewRef: OnboardingContentView?
    private var didLaunchOverlay = false

    func dismiss() {
        didLaunchOverlay = true
        window?.close()
    }

    func show(onStartOverlay: (() -> Void)? = nil) {
        didLaunchOverlay = false
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            contentViewRef?.refreshAllState(animateCards: true)
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 556, height: 704)
        let win = SettingsKeyCaptureWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to LoopSearch"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false

        let content = OnboardingContentView(
            frame: rect,
            onFinish: { [weak self] tryNow in
                guard FirebaseAuthService.shared.isSignedIn else {
                    if tryNow {
                        Task { @MainActor in
                            _ = await FirebaseAuthService.shared.signInWithGoogle()
                        }
                    } else {
                        self?.didLaunchOverlay = false
                        self?.window?.close()
                    }
                    return
                }
                AppSettings.shared.hasCompletedOnboarding = true
                self?.didLaunchOverlay = tryNow
                self?.window?.close()
                if tryNow {
                    onStartOverlay?()
                }
            }
        )
        win.onKeyDown = { [weak content] event in
            content?.handleCapturedKeyEvent(event) ?? false
        }
        self.contentViewRef = content
        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
        content.animateCardsIn()
    }

    func windowWillClose(_ notification: Notification) {
        contentViewRef?.stopTransientActivity()
        if !didLaunchOverlay {
            NotificationCenter.default.post(name: .loopSearchGuideClosed, object: nil)
        }
        didLaunchOverlay = false
    }
}

@MainActor
private final class OnboardingContentView: NSView {
    private let onFinish: (Bool) -> Void
    private var authStatusLabel: NSTextField!
    private var authSubtitleLabel: NSTextField!
    private var authActionBtn: LiquidGlassButton!
    private var permStatusLabel: NSTextField!
    private var permGrantBtn: LiquidGlassButton!
    private var hotkeyValueLabel: NSTextField!
    private var recordHotkeyBtn: LiquidGlassButton!
    private var hotkeyHintLabel: NSTextField!
    private var presetButtons: [HotkeyPreset: LiquidGlassButton] = [:]
    private var appThemeSegment: LiquidGlassSegmentedControl!
    private var webThemeSegment: LiquidGlassSegmentedControl!
    private var keepDockToggle: LiquidGlassToggle!
    private var loginToggle: LiquidGlassToggle!
    private var stepCards: [NSView] = []
    private var doneBtn: LiquidGlassButton!
    private var tryBtn: LiquidGlassButton!
    private var isRecordingShortcut = false
    nonisolated(unsafe) private var permPollTimer: Timer?
    nonisolated(unsafe) private var authObserver: NSObjectProtocol?
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?

    init(frame frameRect: NSRect, onFinish: @escaping (Bool) -> Void) {
        self.onFinish = onFinish
        super.init(frame: frameRect)
        setupUI()
        refreshAllState(animateCards: false)
        authObserver = NotificationCenter.default.addObserver(
            forName: .loopSearchAuthChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshAuthStep()
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .circleToSearchSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshShortcutUI()
                self?.refreshAppearanceAndBehaviorUI()
            }
        }
        startPermissionPollingIfNeeded()
    }

    deinit {
        permPollTimer?.invalidate()
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func animateCardsIn() {
        AppleMotion.staggeredCardsReveal(stepCards, baseDelay: 0.03, stepDelay: 0.042)
    }

    func stopTransientActivity() {
        isRecordingShortcut = false
        permPollTimer?.invalidate()
        permPollTimer = nil
        refreshShortcutUI()
    }

    func refreshAllState(animateCards: Bool) {
        refreshAuthStep()
        refreshPermissionStatus()
        refreshShortcutUI()
        refreshAppearanceAndBehaviorUI()
        startPermissionPollingIfNeeded()
        if animateCards {
            animateCardsIn()
        }
    }

    func handleCapturedKeyEvent(_ event: NSEvent) -> Bool {
        guard isRecordingShortcut else { return false }

        switch ShortcutCaptureResult.parse(event) {
        case .cancelled:
            isRecordingShortcut = false
            refreshShortcutUI()
            return true
        case .modifierOnly:
            return true
        case .missingModifiers:
            NSSound.beep()
            return true
        case .captured(let keyCode, let carbonMods, let label):
            isRecordingShortcut = false
            AppSettings.shared.setCustomHotkey(
                keyCode: keyCode,
                carbonModifiers: carbonMods,
                displayString: label
            )
            refreshShortcutUI()
            return true
        }
    }

    private func startPermissionPollingIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else {
            permPollTimer?.invalidate()
            permPollTimer = nil
            return
        }
        guard permPollTimer == nil else { return }
        permPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissionStatus()
            }
        }
    }

    private func refreshPermissionStatus() {
        let granted = CGPreflightScreenCaptureAccess()
        permStatusLabel.stringValue = granted ? "✓ Granted" : "Needs Access"
        permStatusLabel.textColor = granted ? .systemGreen : .systemOrange
        permGrantBtn.title = granted ? "Open Settings" : "Grant Access"
        if granted {
            permPollTimer?.invalidate()
            permPollTimer = nil
        }
    }

    private func setupUI() {
        let card = LiquidGlassSurfaceView(
            cornerRadius: 24,
            style: .regular,
            tintColor: NSColor(red: 0.026, green: 0.034, blue: 0.072, alpha: 0.92),
            lightTintColor: NSColor(white: 0.96, alpha: 0.94)
        )
        card.horizonGlowIntensity = 0.88
        card.horizonPoolHeightFraction = 0.42
        card.horizonRimStrength = 1.20
        card.horizonWellView.setContinuousWaveEnabled(true)
        card.frame = bounds
        card.autoresizingMask = [.width, .height]
        addSubview(card)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -16)
        ])

        // Header
        let logo = LoopBrandLogoView(size: 38)
        let title = NSTextField(labelWithString: "Welcome to LoopSearch")
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .labelColor

        let sub = NSTextField(labelWithString: "Sign in with Google and set up visual screen search, instant OCR, and AI.")
        sub.font = .systemFont(ofSize: 12, weight: .regular)
        sub.textColor = .secondaryLabelColor

        let titleCol = NSStackView(views: [title, sub])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 2

        let headerRow = NSStackView(views: [logo, titleCol])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12
        stack.addArrangedSubview(headerRow)

        // Step 1: Google Sign-In (Required)
        let step1 = makeStepCard(
            number: "1",
            title: "Sign in with Google (Required)",
            subtitle: "Required before using LoopSearch capture & AI features.",
            subtitleLabelOut: { [weak self] lbl in self?.authSubtitleLabel = lbl }
        ) {
            authStatusLabel = NSTextField(labelWithString: "Required")
            authStatusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
            authStatusLabel.textColor = .systemOrange

            authActionBtn = LiquidGlassButton(
                symbol: "person.crop.circle.badge.checkmark",
                symbolPointSize: 10.5,
                symbolWeight: .semibold,
                title: "Sign in with Google",
                tooltip: "Authenticate with Google in your browser",
                height: 26,
                minWidth: 146,
                style: .clear,
                tintColor: NSColor(red: 0.08, green: 0.38, blue: 0.86, alpha: 0.88),
                lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.92),
                foregroundColor: .white,
                font: .systemFont(ofSize: 11, weight: .semibold)
            ) {
                let auth = FirebaseAuthService.shared
                if auth.isSigningIn {
                    auth.cancelSignIn()
                    return
                }
                Task { @MainActor in
                    _ = await FirebaseAuthService.shared.signInWithGoogle()
                }
            }

            let row = NSStackView(views: [authStatusLabel, authActionBtn])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6
            return row
        }
        stack.addArrangedSubview(step1)
        step1.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Step 2: Screen Recording Permission (with Quit & Reopen Dock/Menu Bar tip + live poll)
        let step2 = makeSettingsGlassCard(cornerRadius: 14)
        let step2Badge = makeStepBadge(number: "2")
        let step2Title = NSTextField(labelWithString: "Grant Screen Recording Permission")
        step2Title.font = .systemFont(ofSize: 13, weight: .semibold)
        step2Title.textColor = .labelColor

        let step2Sub = NSTextField(wrappingLabelWithString: "Needed to capture your screen. If macOS asks to Quit & Reopen, find LoopSearch in your Dock or top-right Menu Bar.")
        step2Sub.font = .systemFont(ofSize: 10.5, weight: .regular)
        step2Sub.textColor = .secondaryLabelColor
        step2Sub.maximumNumberOfLines = 2
        step2Sub.preferredMaxLayoutWidth = 278

        let step2TextCol = NSStackView(views: [step2Title, step2Sub])
        step2TextCol.orientation = .vertical
        step2TextCol.alignment = .leading
        step2TextCol.spacing = 2
        step2TextCol.setContentHuggingPriority(.defaultLow, for: .horizontal)
        step2TextCol.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let granted = CGPreflightScreenCaptureAccess()
        permStatusLabel = NSTextField(labelWithString: granted ? "✓ Granted" : "Needs Access")
        permStatusLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        permStatusLabel.textColor = granted ? .systemGreen : .systemOrange

        permGrantBtn = LiquidGlassButton(
            symbol: "lock.open.display",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: granted ? "Open Settings" : "Grant Access",
            tooltip: "Request Screen Recording permission",
            height: 26,
            minWidth: 108,
            style: .clear,
            tintColor: NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.84),
            lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.90),
            foregroundColor: .white,
            font: .systemFont(ofSize: 11, weight: .semibold)
        ) { [weak self] in
            let ok = CGRequestScreenCaptureAccess()
            self?.refreshPermissionStatus()
            self?.startPermissionPollingIfNeeded()
            if !ok, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }

        let permRightRow = NSStackView(views: [permStatusLabel, permGrantBtn])
        permRightRow.orientation = .horizontal
        permRightRow.alignment = .centerY
        permRightRow.spacing = 8

        let step2Spacer = NSView()
        step2Spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let step2Row = NSStackView(views: [step2Badge, step2TextCol, step2Spacer, permRightRow])
        step2Row.orientation = .horizontal
        step2Row.alignment = .centerY
        step2Row.spacing = 10
        step2Row.translatesAutoresizingMaskIntoConstraints = false
        step2.contentContainer.addSubview(step2Row)
        NSLayoutConstraint.activate([
            step2Row.leadingAnchor.constraint(equalTo: step2.contentContainer.leadingAnchor, constant: 14),
            step2Row.trailingAnchor.constraint(equalTo: step2.contentContainer.trailingAnchor, constant: -14),
            step2Row.topAnchor.constraint(equalTo: step2.contentContainer.topAnchor, constant: 10),
            step2Row.bottomAnchor.constraint(equalTo: step2.contentContainer.bottomAnchor, constant: -10)
        ])
        stack.addArrangedSubview(step2)
        step2.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Step 3: Global Shortcut (Presets + Record Custom Key Combo right on start)
        let step3 = makeSettingsGlassCard(cornerRadius: 14)
        let step3Badge = makeStepBadge(number: "3")
        let step3Title = NSTextField(labelWithString: "Choose or Record Global Shortcut")
        step3Title.font = .systemFont(ofSize: 13, weight: .semibold)
        step3Title.textColor = .labelColor

        hotkeyHintLabel = NSTextField(labelWithString: "Pick a quick preset or record your own key combo from start.")
        hotkeyHintLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        hotkeyHintLabel.textColor = .secondaryLabelColor
        hotkeyHintLabel.lineBreakMode = .byTruncatingTail

        let step3TextCol = NSStackView(views: [step3Title, hotkeyHintLabel])
        step3TextCol.orientation = .vertical
        step3TextCol.alignment = .leading
        step3TextCol.spacing = 1
        step3TextCol.setContentHuggingPriority(.defaultLow, for: .horizontal)
        step3TextCol.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let badgePill = NSView()
        badgePill.wantsLayer = true
        badgePill.layer?.cornerRadius = 8
        badgePill.layer?.backgroundColor = NSColor(red: 0.14, green: 0.56, blue: 1.0, alpha: 0.14).cgColor
        badgePill.layer?.borderWidth = 0.75
        badgePill.layer?.borderColor = NSColor(red: 0.34, green: 0.84, blue: 1.0, alpha: 0.34).cgColor
        badgePill.translatesAutoresizingMaskIntoConstraints = false

        hotkeyValueLabel = NSTextField(labelWithString: AppSettings.shared.activeHotkeyDisplayString)
        hotkeyValueLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        hotkeyValueLabel.textColor = .labelColor
        hotkeyValueLabel.alignment = .center
        hotkeyValueLabel.translatesAutoresizingMaskIntoConstraints = false
        badgePill.addSubview(hotkeyValueLabel)
        NSLayoutConstraint.activate([
            badgePill.heightAnchor.constraint(equalToConstant: 24),
            badgePill.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),
            hotkeyValueLabel.leadingAnchor.constraint(equalTo: badgePill.leadingAnchor, constant: 9),
            hotkeyValueLabel.trailingAnchor.constraint(equalTo: badgePill.trailingAnchor, constant: -9),
            hotkeyValueLabel.centerYAnchor.constraint(equalTo: badgePill.centerYAnchor)
        ])

        let step3HeaderSpacer = NSView()
        step3HeaderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let step3TopRow = NSStackView(views: [step3Badge, step3TextCol, step3HeaderSpacer, badgePill])
        step3TopRow.orientation = .horizontal
        step3TopRow.alignment = .centerY
        step3TopRow.spacing = 10

        presetButtons = [:]
        let presetList: [HotkeyPreset] = [.cmdShiftSpace, .optionSpace, .cmdShiftS]
        let presetBtns: [LiquidGlassButton] = presetList.map { preset in
            let btn = LiquidGlassButton(
                title: preset.title,
                tooltip: "Use \(preset.title)",
                height: 24,
                style: .clear,
                foregroundColor: .labelColor,
                font: .systemFont(ofSize: 10.5, weight: .semibold)
            ) { [weak self] in
                self?.isRecordingShortcut = false
                AppSettings.shared.hotkeyPreset = preset
                self?.refreshShortcutUI()
            }
            presetButtons[preset] = btn
            return btn
        }

        recordHotkeyBtn = LiquidGlassButton(
            symbol: "keyboard",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Record Custom…",
            tooltip: "Press your own custom key combination (e.g. ⌥S, ⌃⌥Space)",
            height: 24,
            minWidth: 122,
            style: .clear,
            tintColor: NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.84),
            lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.90),
            foregroundColor: .white,
            font: .systemFont(ofSize: 10.5, weight: .semibold)
        ) { [weak self] in
            self?.toggleShortcutRecording()
        }

        let step3ControlsSpacer = NSView()
        step3ControlsSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let step3ControlsRow = NSStackView(views: presetBtns + [step3ControlsSpacer, recordHotkeyBtn])
        step3ControlsRow.orientation = .horizontal
        step3ControlsRow.alignment = .centerY
        step3ControlsRow.spacing = 6

        let step3VStack = NSStackView(views: [step3TopRow, step3ControlsRow])
        step3VStack.orientation = .vertical
        step3VStack.alignment = .leading
        step3VStack.spacing = 8
        step3VStack.translatesAutoresizingMaskIntoConstraints = false
        step3.contentContainer.addSubview(step3VStack)
        NSLayoutConstraint.activate([
            step3VStack.leadingAnchor.constraint(equalTo: step3.contentContainer.leadingAnchor, constant: 14),
            step3VStack.trailingAnchor.constraint(equalTo: step3.contentContainer.trailingAnchor, constant: -14),
            step3VStack.topAnchor.constraint(equalTo: step3.contentContainer.topAnchor, constant: 10),
            step3VStack.bottomAnchor.constraint(equalTo: step3.contentContainer.bottomAnchor, constant: -10),
            step3TopRow.widthAnchor.constraint(equalTo: step3VStack.widthAnchor),
            step3ControlsRow.widthAnchor.constraint(equalTo: step3VStack.widthAnchor)
        ])
        stack.addArrangedSubview(step3)
        step3.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Step 4: App Theme, Results Browser Mode & Quick Visibility Toggles
        let step4 = makeSettingsGlassCard(cornerRadius: 14)
        let step4Badge = makeStepBadge(number: "4")
        let step4Title = NSTextField(labelWithString: "Appearance, Results Browser & Visibility")
        step4Title.font = .systemFont(ofSize: 13, weight: .semibold)
        step4Title.textColor = .labelColor

        let step4Sub = NSTextField(labelWithString: "Choose Dark / Light mode for LoopSearch and Google Lens results, and keep icon accessible.")
        step4Sub.font = .systemFont(ofSize: 10.5, weight: .regular)
        step4Sub.textColor = .secondaryLabelColor
        step4Sub.lineBreakMode = .byTruncatingTail

        let step4TextCol = NSStackView(views: [step4Title, step4Sub])
        step4TextCol.orientation = .vertical
        step4TextCol.alignment = .leading
        step4TextCol.spacing = 1
        step4TextCol.setContentHuggingPriority(.defaultLow, for: .horizontal)
        step4TextCol.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let step4TopRow = NSStackView(views: [step4Badge, step4TextCol])
        step4TopRow.orientation = .horizontal
        step4TopRow.alignment = .centerY
        step4TopRow.spacing = 10

        let themeOptions = AppTheme.allCases.map {
            LiquidGlassSegmentedControl.Option(title: $0.title, symbol: $0.symbolName)
        }

        let appThemeLabel = NSTextField(labelWithString: "App & Glass Theme")
        appThemeLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        appThemeLabel.textColor = .labelColor
        appThemeSegment = LiquidGlassSegmentedControl(
            options: themeOptions,
            selectedIndex: AppTheme.allCases.firstIndex(of: AppSettings.shared.theme) ?? 0,
            height: 24,
            compact: true
        ) { idx in
            guard AppTheme.allCases.indices.contains(idx) else { return }
            AppSettings.shared.theme = AppTheme.allCases[idx]
        }
        let appThemeSpacer = NSView()
        appThemeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let appThemeRow = NSStackView(views: [appThemeLabel, appThemeSpacer, appThemeSegment])
        appThemeRow.orientation = .horizontal
        appThemeRow.alignment = .centerY

        let webThemeLabel = NSTextField(labelWithString: "Results Browser Page")
        webThemeLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        webThemeLabel.textColor = .labelColor
        webThemeSegment = LiquidGlassSegmentedControl(
            options: themeOptions,
            selectedIndex: AppTheme.allCases.firstIndex(of: AppSettings.shared.webResultsTheme) ?? 0,
            height: 24,
            compact: true
        ) { idx in
            guard AppTheme.allCases.indices.contains(idx) else { return }
            AppSettings.shared.webResultsTheme = AppTheme.allCases[idx]
        }
        let webThemeSpacer = NSView()
        webThemeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let webThemeRow = NSStackView(views: [webThemeLabel, webThemeSpacer, webThemeSegment])
        webThemeRow.orientation = .horizontal
        webThemeRow.alignment = .centerY

        keepDockToggle = LiquidGlassToggle(isOn: !AppSettings.shared.hideDockIcon) { isOn in
            AppSettings.shared.hideDockIcon = !isOn
        }
        let keepDockLabel = NSTextField(labelWithString: "Keep in Dock (recommended)")
        keepDockLabel.font = .systemFont(ofSize: 11, weight: .medium)
        keepDockLabel.textColor = .secondaryLabelColor

        loginToggle = LiquidGlassToggle(isOn: AppSettings.shared.launchAtLogin) { isOn in
            AppSettings.shared.launchAtLogin = isOn
        }
        let loginLabel = NSTextField(labelWithString: "Launch at Login")
        loginLabel.font = .systemFont(ofSize: 11, weight: .medium)
        loginLabel.textColor = .secondaryLabelColor

        let behaviorSpacer = NSView()
        behaviorSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let behaviorRow = NSStackView(views: [keepDockToggle, keepDockLabel, behaviorSpacer, loginToggle, loginLabel])
        behaviorRow.orientation = .horizontal
        behaviorRow.alignment = .centerY
        behaviorRow.spacing = 7

        let step4VStack = NSStackView(views: [step4TopRow, appThemeRow, webThemeRow, behaviorRow])
        step4VStack.orientation = .vertical
        step4VStack.alignment = .leading
        step4VStack.spacing = 7
        step4VStack.translatesAutoresizingMaskIntoConstraints = false
        step4.contentContainer.addSubview(step4VStack)
        NSLayoutConstraint.activate([
            step4VStack.leadingAnchor.constraint(equalTo: step4.contentContainer.leadingAnchor, constant: 14),
            step4VStack.trailingAnchor.constraint(equalTo: step4.contentContainer.trailingAnchor, constant: -14),
            step4VStack.topAnchor.constraint(equalTo: step4.contentContainer.topAnchor, constant: 10),
            step4VStack.bottomAnchor.constraint(equalTo: step4.contentContainer.bottomAnchor, constant: -10),
            step4TopRow.widthAnchor.constraint(equalTo: step4VStack.widthAnchor),
            appThemeRow.widthAnchor.constraint(equalTo: step4VStack.widthAnchor),
            webThemeRow.widthAnchor.constraint(equalTo: step4VStack.widthAnchor),
            behaviorRow.widthAnchor.constraint(equalTo: step4VStack.widthAnchor)
        ])
        stack.addArrangedSubview(step4)
        step4.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let supportCard = makeCreatorSupportCard(compact: true)
        stack.addArrangedSubview(supportCard)
        supportCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        stepCards = [step1, step2, step3, step4, supportCard]

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(spacer)

        // Bottom Buttons
        let note = NSTextField(labelWithString: "Independent macOS app • Not affiliated with Google LLC")
        note.font = .systemFont(ofSize: 10.5, weight: .regular)
        note.textColor = .secondaryLabelColor

        doneBtn = LiquidGlassButton(
            title: "Close",
            tooltip: "Close welcome guide",
            height: 30,
            minWidth: 74,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 12, weight: .semibold)
        ) { [weak self] in
            self?.onFinish(false)
        }

        tryBtn = LiquidGlassButton(
            symbol: "sparkles",
            symbolPointSize: 11.5,
            symbolWeight: .semibold,
            title: "Sign In to Continue",
            tooltip: "Sign in with Google and start using LoopSearch",
            height: 30,
            minWidth: 168,
            style: .clear,
            tintColor: NSColor(red: 0.08, green: 0.38, blue: 0.86, alpha: 0.86),
            lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.92),
            foregroundColor: .white,
            font: .systemFont(ofSize: 12, weight: .semibold)
        ) { [weak self] in
            self?.onFinish(true)
        }

        let hSpacer = NSView()
        hSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [note, hSpacer, doneBtn, tryBtn])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func refreshAuthStep() {
        let auth = FirebaseAuthService.shared

        if let session = auth.session {
            authStatusLabel.stringValue = "✓ Signed In"
            authStatusLabel.textColor = .systemGreen
            let detail = session.email.isEmpty ? session.effectiveDisplayName : "\(session.effectiveDisplayName) (\(session.email))"
            authSubtitleLabel.stringValue = detail
            authSubtitleLabel.textColor = .secondaryLabelColor
            authActionBtn.title = auth.isSigningIn ? "Cancel" : "Switch"
            authActionBtn.setSelectedAccent(false)

            doneBtn.title = "Done"
            tryBtn.title = "Try LoopSearch Now"
            tryBtn.setSelectedAccent(true)
        } else if auth.isSigningIn {
            authStatusLabel.stringValue = "In Browser"
            authStatusLabel.textColor = NSColor(red: 0.36, green: 0.84, blue: 1.0, alpha: 1.0)
            authSubtitleLabel.stringValue = "Finish Google sign-in in your browser, then return here."
            authSubtitleLabel.textColor = .secondaryLabelColor
            authActionBtn.title = "Cancel"
            authActionBtn.setSelectedAccent(false)

            doneBtn.title = "Close"
            tryBtn.title = "Waiting for Sign-In…"
            tryBtn.setSelectedAccent(false)
        } else {
            authStatusLabel.stringValue = "Required"
            authStatusLabel.textColor = .systemOrange
            if let err = auth.lastAuthError, !err.isEmpty {
                authSubtitleLabel.stringValue = err
                authSubtitleLabel.textColor = .systemOrange
            } else {
                authSubtitleLabel.stringValue = "Sign in once (name & email only) — works offline afterward."
                authSubtitleLabel.textColor = .secondaryLabelColor
            }
            authActionBtn.title = "Sign in with Google"
            authActionBtn.setSelectedAccent(true)

            doneBtn.title = "Close"
            tryBtn.title = "Sign In to Continue"
            tryBtn.setSelectedAccent(true)
        }
    }

    private func toggleShortcutRecording() {
        isRecordingShortcut.toggle()
        if isRecordingShortcut {
            recordHotkeyBtn.title = "Press keys… (Esc)"
            recordHotkeyBtn.setSelectedAccent(true)
            hotkeyValueLabel.stringValue = "Listening…"
            hotkeyHintLabel.stringValue = "Hold ⌘/⌥/⌃/⇧ + a key (e.g. ⌥S). Press Esc to cancel."
            hotkeyHintLabel.textColor = .systemCyan
        } else {
            refreshShortcutUI()
        }
    }

    private func refreshShortcutUI() {
        let s = AppSettings.shared
        guard !isRecordingShortcut else { return }
        hotkeyValueLabel.stringValue = s.activeHotkeyDisplayString
        recordHotkeyBtn.title = "Record Custom…"
        recordHotkeyBtn.setSelectedAccent(s.useCustomHotkey)

        let activePreset = s.useCustomHotkey ? nil : s.hotkeyPreset
        for (preset, btn) in presetButtons {
            btn.setSelectedAccent(preset == activePreset)
        }

        if let warning = activePreset?.commonUsageWarning {
            hotkeyHintLabel.stringValue = "Tip: \(warning)"
            hotkeyHintLabel.textColor = .systemOrange
        } else if s.useCustomHotkey {
            hotkeyHintLabel.stringValue = "Custom shortcut active: \(s.activeHotkeyDisplayString) (click a preset to switch)"
            hotkeyHintLabel.textColor = .secondaryLabelColor
        } else {
            hotkeyHintLabel.stringValue = "Pick a quick preset or record your own key combo from start."
            hotkeyHintLabel.textColor = .secondaryLabelColor
        }
    }

    private func refreshAppearanceAndBehaviorUI() {
        let s = AppSettings.shared
        if let idx = AppTheme.allCases.firstIndex(of: s.theme) {
            appThemeSegment.setSelectedIndex(idx, animated: false)
        }
        if let idx = AppTheme.allCases.firstIndex(of: s.webResultsTheme) {
            webThemeSegment.setSelectedIndex(idx, animated: false)
        }
        keepDockToggle.isOn = !s.hideDockIcon
        loginToggle.isOn = s.launchAtLogin
    }

    private func makeStepBadge(number: String) -> NSView {
        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 12
        badge.layer?.backgroundColor = NSColor(red: 0.10, green: 0.42, blue: 0.92, alpha: 0.26).cgColor
        badge.layer?.borderWidth = 0.75
        badge.layer?.borderColor = NSColor(red: 0.30, green: 0.84, blue: 1.0, alpha: 0.30).cgColor
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .vertical)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .vertical)

        let badgeLabel = NSTextField(labelWithString: number)
        badgeLabel.font = .systemFont(ofSize: 12.5, weight: .bold)
        badgeLabel.textColor = NSColor(red: 0.30, green: 0.84, blue: 1.0, alpha: 1)
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 24),
            badge.heightAnchor.constraint(equalToConstant: 24),
            badgeLabel.centerXAnchor.constraint(equalTo: badge.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badge.centerYAnchor)
        ])
        return badge
    }

    private func makeStepCard(
        number: String,
        title: String,
        subtitle: String,
        subtitleLabelOut: ((NSTextField) -> Void)? = nil,
        rightView: () -> NSView
    ) -> NSView {
        let card = makeSettingsGlassCard(cornerRadius: 14)
        card.heightAnchor.constraint(equalToConstant: 68).isActive = true

        let badge = makeStepBadge(number: number)

        let tLabel = NSTextField(labelWithString: title)
        tLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        tLabel.textColor = .labelColor

        let sLabel = NSTextField(labelWithString: subtitle)
        sLabel.font = .systemFont(ofSize: 11, weight: .regular)
        sLabel.textColor = .secondaryLabelColor
        sLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabelOut?(sLabel)

        let textCol = NSStackView(views: [tLabel, sLabel])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 2
        textCol.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textCol.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let control = rightView()
        let row = NSStackView(views: [badge, textCol, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: card.contentContainer.centerYAnchor)
        ])

        return card
    }
}

// MARK: - Post-Sign-In "How to Use LoopSearch" Guide

@MainActor
final class HowToUseWindowController: NSObject, NSWindowDelegate {
    static let shared = HowToUseWindowController()

    private var window: NSWindow?
    private var startOverlayHandler: (() -> Void)?
    private var didLaunchOverlay = false
    private weak var contentRef: HowToUseContentView?

    func show(justSignedIn: Bool = false, onStartOverlay: (() -> Void)? = nil) {
        if let onStartOverlay {
            self.startOverlayHandler = onStartOverlay
        }
        didLaunchOverlay = false

        if let existing = window {
            let view = HowToUseContentView(
                frame: existing.contentLayoutRect,
                justSignedIn: justSignedIn,
                onOpenStudio: { [weak self] in
                    self?.didLaunchOverlay = true
                    self?.window?.close()
                    SettingsWindowController.shared.show()
                },
                onClose: { [weak self] tryNow in
                    self?.didLaunchOverlay = tryNow
                    self?.window?.close()
                    if tryNow {
                        self?.startOverlayHandler?()
                    }
                }
            )
            existing.contentView = view
            self.contentRef = view
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            view.animateCardsIn()
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 540, height: 616)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "How to Use LoopSearch"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.center()
        win.delegate = self
        win.isReleasedWhenClosed = false

        let view = HowToUseContentView(
            frame: rect,
            justSignedIn: justSignedIn,
            onOpenStudio: { [weak self] in
                self?.didLaunchOverlay = true
                self?.window?.close()
                SettingsWindowController.shared.show()
            },
            onClose: { [weak self] tryNow in
                self?.didLaunchOverlay = tryNow
                self?.window?.close()
                if tryNow {
                    self?.startOverlayHandler?()
                }
            }
        )
        win.contentView = view
        self.contentRef = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
        view.animateCardsIn()
    }

    func windowWillClose(_ notification: Notification) {
        contentRef?.stopPolling()
        if !didLaunchOverlay {
            NotificationCenter.default.post(name: .loopSearchGuideClosed, object: nil)
        }
        didLaunchOverlay = false
    }
}

@MainActor
private final class HowToUseContentView: NSView {
    private let justSignedIn: Bool
    private let onOpenStudio: () -> Void
    private let onClose: (Bool) -> Void
    private var permissionBanner: NSView?
    private var permissionLabel: NSTextField?
    private var guideCards: [NSView] = []
    nonisolated(unsafe) private var permPollTimer: Timer?

    init(
        frame frameRect: NSRect,
        justSignedIn: Bool,
        onOpenStudio: @escaping () -> Void,
        onClose: @escaping (Bool) -> Void
    ) {
        self.justSignedIn = justSignedIn
        self.onOpenStudio = onOpenStudio
        self.onClose = onClose
        super.init(frame: frameRect)
        setupUI()
        startPermissionPollingIfNeeded()
    }

    deinit {
        permPollTimer?.invalidate()
    }

    func animateCardsIn() {
        AppleMotion.staggeredCardsReveal(guideCards, baseDelay: 0.03, stepDelay: 0.042)
    }

    func stopPolling() {
        permPollTimer?.invalidate()
        permPollTimer = nil
    }

    private func startPermissionPollingIfNeeded() {
        guard permissionBanner != nil, !CGPreflightScreenCaptureAccess() else { return }
        permPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard CGPreflightScreenCaptureAccess() else { return }
                self?.permissionLabel?.stringValue = "✓ Screen Recording permission granted!"
                self?.permissionLabel?.textColor = .systemGreen
                self?.stopPolling()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        let card = LiquidGlassSurfaceView(
            cornerRadius: 24,
            style: .regular,
            tintColor: NSColor(red: 0.026, green: 0.034, blue: 0.072, alpha: 0.92),
            lightTintColor: NSColor(white: 0.96, alpha: 0.94)
        )
        card.horizonGlowIntensity = 0.88
        card.horizonPoolHeightFraction = 0.42
        card.horizonRimStrength = 1.20
        card.horizonWellView.setContinuousWaveEnabled(true)
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor),
            card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor),
            card.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -20)
        ])

        // Header
        let logo = LoopBrandLogoView(size: 40)
        let titleText = justSignedIn ? "You're Signed In!" : "How to Use LoopSearch"
        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 20, weight: .bold)
        title.textColor = .labelColor

        let signedDetail: String = {
            if justSignedIn, let session = FirebaseAuthService.shared.session {
                let name = session.effectiveDisplayName
                return session.email.isEmpty
                    ? "Welcome, \(name). Here is how to search anything on your screen."
                    : "Signed in as \(name) (\(session.email)). Here is how to get started."
            }
            return "Circle, box, tap, or extract text from anything on your Mac."
        }()
        let subtitle = NSTextField(wrappingLabelWithString: signedDetail)
        subtitle.font = .systemFont(ofSize: 12.5, weight: .regular)
        subtitle.textColor = .secondaryLabelColor

        let titleCol = NSStackView(views: [title, subtitle])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 2

        let header = NSStackView(views: [logo, titleCol])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        stack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let hotkey = AppSettings.shared.activeHotkeyDisplayString

        // 4 Clear How-To Cards
        let steps: [(symbol: String, title: String, body: String, badge: String)] = [
            (
                "command.square.fill",
                "1. Launch From Any App",
                "Press \(hotkey) anywhere, or click LoopSearch in your Dock or top-right menu bar.",
                hotkey
            ),
            (
                "lasso.sparkles",
                "2. Select Anything on Screen",
                "Draw a freehand loop or box, click a window/object in Tap mode, or drag over text to copy it.",
                "1 Box • 2 Loop • 3 Tap • 4 OCR"
            ),
            (
                "sparkle.magnifyingglass",
                "3. Search, Copy Text, or Ask AI",
                "Send your selection to Google Lens, Google, Perplexity, Bing, or Ask AI — or copy OCR text in one click.",
                "Lens • OCR • Ask AI"
            ),
            (
                "slider.horizontal.3",
                "4. Always Accessible & Customizable",
                "If windows close or Screen Recording asks to Quit & Reopen, LoopSearch stays in Dock & Menu Bar. Press ⌘, for Studio.",
                "Dock • Menu Bar • ⌘,"
            )
        ]

        guideCards = []
        for step in steps {
            let rowCard = makeGuideCard(
                symbol: step.symbol,
                title: step.title,
                body: step.body,
                badgeText: step.badge
            )
            stack.addArrangedSubview(rowCard)
            rowCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            guideCards.append(rowCard)
        }

        // Optional Screen Recording Banner if not granted yet
        if !CGPreflightScreenCaptureAccess() {
            let banner = makeSettingsGlassCard(cornerRadius: 12)
            banner.heightAnchor.constraint(equalToConstant: 46).isActive = true

            let label = NSTextField(labelWithString: "Screen Recording access is needed before your first capture.")
            label.font = .systemFont(ofSize: 11.5, weight: .medium)
            label.textColor = .systemOrange
            self.permissionLabel = label

            let grantBtn = LiquidGlassButton(
                symbol: "lock.open.display",
                symbolPointSize: 10.5,
                symbolWeight: .semibold,
                title: "Grant Access",
                tooltip: "Open macOS Screen Recording permission",
                height: 26,
                minWidth: 106,
                style: .clear,
                tintColor: NSColor(red: 0.08, green: 0.36, blue: 0.82, alpha: 0.86),
                lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.92),
                foregroundColor: .white,
                font: .systemFont(ofSize: 11, weight: .semibold)
            ) { [weak self] in
                let ok = CGRequestScreenCaptureAccess()
                self?.permissionLabel?.stringValue = ok
                    ? "✓ Screen Recording permission granted!"
                    : "Enable LoopSearch in System Settings → Screen Recording."
                self?.permissionLabel?.textColor = ok ? .systemGreen : .systemOrange
                if !ok, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }

            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let bRow = NSStackView(views: [label, spacer, grantBtn])
            bRow.orientation = .horizontal
            bRow.alignment = .centerY
            bRow.spacing = 8
            bRow.translatesAutoresizingMaskIntoConstraints = false
            banner.contentContainer.addSubview(bRow)
            NSLayoutConstraint.activate([
                bRow.leadingAnchor.constraint(equalTo: banner.contentContainer.leadingAnchor, constant: 12),
                bRow.trailingAnchor.constraint(equalTo: banner.contentContainer.trailingAnchor, constant: -12),
                bRow.centerYAnchor.constraint(equalTo: banner.contentContainer.centerYAnchor)
            ])
            self.permissionBanner = banner
            stack.addArrangedSubview(banner)
            banner.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            guideCards.append(banner)
        }

        let vSpacer = NSView()
        vSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.addArrangedSubview(vSpacer)

        // Footer Actions
        let studioBtn = LiquidGlassButton(
            symbol: "slider.horizontal.3",
            symbolPointSize: 11,
            symbolWeight: .medium,
            title: "Studio Settings",
            tooltip: "Open LoopSearch Studio",
            height: 30,
            minWidth: 122,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 12, weight: .medium)
        ) { [weak self] in
            self?.onOpenStudio()
        }

        let gotItBtn = LiquidGlassButton(
            title: "Got It",
            tooltip: "Close this guide",
            height: 30,
            minWidth: 78,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 12, weight: .semibold)
        ) { [weak self] in
            self?.onClose(false)
        }

        let tryNowBtn = LiquidGlassButton(
            symbol: "sparkles",
            symbolPointSize: 11.5,
            symbolWeight: .semibold,
            title: "Try LoopSearch Now",
            tooltip: "Launch selection overlay right now",
            height: 30,
            minWidth: 162,
            style: .clear,
            tintColor: NSColor(red: 0.08, green: 0.38, blue: 0.86, alpha: 0.88),
            lightTintColor: NSColor(red: 0.12, green: 0.44, blue: 0.94, alpha: 0.94),
            foregroundColor: .white,
            font: .systemFont(ofSize: 12, weight: .semibold)
        ) { [weak self] in
            self?.onClose(true)
        }

        let hSpacer = NSView()
        hSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [studioBtn, hSpacer, gotItBtn, tryNowBtn])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        stack.addArrangedSubview(footer)
        footer.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func makeGuideCard(symbol: String, title: String, body: String, badgeText: String) -> NSView {
        let card = makeSettingsGlassCard(cornerRadius: 14)
        card.heightAnchor.constraint(greaterThanOrEqualToConstant: 76).isActive = true

        let iconBox = NSView()
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 11
        iconBox.layer?.backgroundColor = NSColor(red: 0.10, green: 0.42, blue: 0.92, alpha: 0.22).cgColor
        iconBox.layer?.borderWidth = 0.75
        iconBox.layer?.borderColor = NSColor(red: 0.30, green: 0.84, blue: 1.0, alpha: 0.30).cgColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconBox.widthAnchor.constraint(equalToConstant: 32),
            iconBox.heightAnchor.constraint(equalToConstant: 32)
        ])

        let imgView = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold)) {
            imgView.image = img
        }
        imgView.contentTintColor = NSColor(red: 0.34, green: 0.86, blue: 1.0, alpha: 1.0)
        imgView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(imgView)
        NSLayoutConstraint.activate([
            imgView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            imgView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor)
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 6
        pill.layer?.backgroundColor = NSColor(red: 0.16, green: 0.48, blue: 0.96, alpha: 0.16).cgColor
        pill.translatesAutoresizingMaskIntoConstraints = false

        let pillLabel = NSTextField(labelWithString: badgeText)
        pillLabel.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        pillLabel.textColor = NSColor(red: 0.38, green: 0.84, blue: 1.0, alpha: 0.95)
        pillLabel.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(pillLabel)
        NSLayoutConstraint.activate([
            pillLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            pillLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
            pillLabel.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2),
            pillLabel.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2)
        ])

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let topRow = NSStackView(views: [titleLabel, spacer, pill])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 8

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        bodyLabel.textColor = .secondaryLabelColor

        let textCol = NSStackView(views: [topRow, bodyLabel])
        textCol.orientation = .vertical
        textCol.alignment = .leading
        textCol.spacing = 4
        topRow.widthAnchor.constraint(equalTo: textCol.widthAnchor).isActive = true

        let row = NSStackView(views: [iconBox, textCol])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 10),
            row.bottomAnchor.constraint(equalTo: card.contentContainer.bottomAnchor, constant: -10)
        ])

        return card
    }
}

// MARK: - About LoopSearch Window ("Not affiliated with Google")

@MainActor
final class AboutWindowController: NSObject {
    static let shared = AboutWindowController()

    private var window: NSWindow?
    private var checkUpdatesBtnRef: LiquidGlassButton?
    private var updateStatusLabelRef: NSTextField?
    nonisolated(unsafe) private var updateObserver: NSObjectProtocol?

    deinit {
        if let updateObserver {
            NotificationCenter.default.removeObserver(updateObserver)
        }
    }

    private func refreshUpdateUI() {
        guard let btn = checkUpdatesBtnRef, let badge = updateStatusLabelRef else { return }
        if let update = AppUpdateChecker.shared.availableUpdate {
            btn.title = "Update Available: Install v\(update.version)"
            btn.setSelectedAccent(true)
            badge.stringValue = "New version v\(update.version) ready on GitHub Releases"
            badge.textColor = NSColor(red: 0.36, green: 0.86, blue: 1.0, alpha: 1.0)
            badge.isHidden = false
            AppleMotion.springPop(btn, scale: 1.04)
        } else {
            btn.title = "Check for Updates"
            btn.setSelectedAccent(false)
            badge.isHidden = true
        }
    }

    func show() {
        if let existing = window {
            refreshUpdateUI()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 404, height: 376)
        let win = NSWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "About LoopSearch"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.center()
        win.isReleasedWhenClosed = false

        let card = LiquidGlassSurfaceView(
            cornerRadius: 22,
            style: .regular,
            tintColor: NSColor(red: 0.024, green: 0.032, blue: 0.068, alpha: 0.94),
            lightTintColor: NSColor(white: 0.96, alpha: 0.94)
        )
        card.horizonGlowIntensity = 0.95
        card.horizonPoolHeightFraction = 0.44
        card.horizonRimStrength = 1.25
        card.horizonWellView.setContinuousWaveEnabled(true)
        card.frame = rect

        let logo = LoopBrandLogoView(size: 52)
        let name = NSTextField(labelWithString: "LoopSearch")
        name.font = .systemFont(ofSize: 20, weight: .bold)
        name.textColor = .labelColor

        let ver = NSTextField(labelWithString: "Version \(AppUpdateChecker.currentVersion) • Native macOS Visual Screen Search")
        ver.font = .systemFont(ofSize: 11.5, weight: .medium)
        ver.textColor = .secondaryLabelColor

        let updateStatus = NSTextField(labelWithString: "")
        updateStatus.font = .systemFont(ofSize: 11, weight: .semibold)
        updateStatus.alignment = .center
        updateStatus.isHidden = true
        updateStatusLabelRef = updateStatus

        let desc = NSTextField(labelWithString: "Draw a box, freehand loop, or tap anything on screen for instant on-device Vision OCR, AI answers, subject lifting, and visual search.")
        desc.font = .systemFont(ofSize: 11.5, weight: .regular)
        desc.textColor = .labelColor
        desc.alignment = .center
        desc.maximumNumberOfLines = 3
        desc.cell?.wraps = true
        desc.preferredMaxLayoutWidth = 320

        let credit = NSTextField(labelWithString: "Made by Aveesha Senevirathne")
        credit.font = .systemFont(ofSize: 11.5, weight: .semibold)
        credit.textColor = NSColor(red: 0.42, green: 0.82, blue: 1.0, alpha: 1.0)

        let supportButtons = makeSupportButtonsRow(compact: true)

        let checkUpdatesBtn = LiquidGlassButton(
            symbol: "arrow.triangle.2.circlepath",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Check for Updates",
            tooltip: "Check GitHub Releases for a newer version",
            height: 27,
            style: .clear,
            foregroundColor: .labelColor,
            font: .systemFont(ofSize: 11, weight: .medium)
        ) {
            AppUpdateChecker.shared.installOrOpenAvailableUpdate()
        }
        checkUpdatesBtnRef = checkUpdatesBtn

        let disclaimer = NSTextField(labelWithString: "Independent macOS application • Not affiliated with, endorsed by, or sponsored by Google LLC.")
        disclaimer.font = .systemFont(ofSize: 10.5, weight: .semibold)
        disclaimer.textColor = .secondaryLabelColor
        disclaimer.alignment = .center
        disclaimer.maximumNumberOfLines = 2
        disclaimer.cell?.wraps = true
        disclaimer.preferredMaxLayoutWidth = 336

        let stack = NSStackView(views: [logo, name, ver, updateStatus, credit, desc, supportButtons, checkUpdatesBtn, disclaimer])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: card.contentContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: card.contentContainer.centerYAnchor, constant: 4),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: card.contentContainer.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: card.contentContainer.trailingAnchor, constant: -20)
        ])

        win.contentView = card
        refreshUpdateUI()
        if updateObserver == nil {
            updateObserver = NotificationCenter.default.addObserver(
                forName: .loopSearchUpdateChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshUpdateUI()
                }
            }
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
        AppleMotion.staggeredCardsReveal([logo, name, credit, desc, supportButtons, checkUpdatesBtn], baseDelay: 0.02, stepDelay: 0.03)
    }
}

// MARK: - Rate & Feature Suggestion Window (Auto-Prompt after 5 Uses + Menu Action)

@MainActor
final class FeedbackWindowController {
    static let shared = FeedbackWindowController()

    private var window: NSWindow?
    private var selectedStars: Int = 5
    private var selectedCategory: String = "Feature Idea"
    private var starButtons: [LiquidGlassButton] = []
    private var categoryButtons: [String: LiquidGlassButton] = [:]
    private var ratingCaptionLabel: NSTextField!
    private var notesTextView: NSTextView!
    private var isAutomaticPrompt = false
    private var onToastCallback: ((String) -> Void)?

    private init() {}

    func show(isAutomaticMilestone: Bool, onToast: ((String) -> Void)? = nil) {
        self.isAutomaticPrompt = isAutomaticMilestone
        self.onToastCallback = onToast
        self.selectedStars = max(1, min(5, AppSettings.shared.lastSubmittedStarRating == 0 ? 5 : AppSettings.shared.lastSubmittedStarRating))
        self.selectedCategory = "Feature Idea"

        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            refreshUI()
            return
        }

        let rect = NSRect(x: 0, y: 0, width: 470, height: 425)
        let win = SettingsKeyCaptureWindow(
            contentRect: rect,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Rate LoopSearch & Suggest a Feature"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isOpaque = false
        win.backgroundColor = .clear
        win.isReleasedWhenClosed = false
        win.center()

        win.onKeyDown = { [weak self] event in
            if event.keyCode == 53 {
                self?.dismissWindow(markDeferred: true)
                return true
            }
            return false
        }

        let card = LiquidGlassSurfaceView(
            cornerRadius: 22,
            style: .regular,
            tintColor: NSColor(red: 0.024, green: 0.032, blue: 0.068, alpha: 0.94),
            lightTintColor: NSColor(white: 0.96, alpha: 0.94)
        )
        card.horizonGlowIntensity = 0.95
        card.horizonPoolHeightFraction = 0.42
        card.horizonRimStrength = 1.25
        card.horizonWellView.setContinuousWaveEnabled(true)
        card.frame = rect

        let logo = LoopBrandLogoView(size: 40)

        let headingText = isAutomaticMilestone ? "Enjoying LoopSearch?" : "Rate & Suggest a Feature"
        let heading = NSTextField(labelWithString: headingText)
        heading.font = .systemFont(ofSize: 18, weight: .bold)
        heading.textColor = .labelColor

        let uses = max(AppSettings.shared.searchUsageCount, 5)
        let subText = isAutomaticMilestone
            ? "You've run \(uses) visual searches! Rate LoopSearch or share what feature we should build next."
            : "Your star rating and feature suggestions directly shape future LoopSearch updates."
        let subLabel = NSTextField(labelWithString: subText)
        subLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        subLabel.textColor = .secondaryLabelColor
        subLabel.maximumNumberOfLines = 2
        subLabel.cell?.wraps = true
        subLabel.preferredMaxLayoutWidth = 370

        let titleCol = NSStackView(views: [heading, subLabel])
        titleCol.orientation = .vertical
        titleCol.alignment = .leading
        titleCol.spacing = 2

        let headerRow = NSStackView(views: [logo, titleCol])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 12

        // Interactive 1-5 star bar inside glass card
        let starCard = makeSettingsGlassCard(cornerRadius: 14)
        starButtons = (1...5).map { idx in
            LiquidGlassButton(
                symbol: "star.fill",
                symbolPointSize: 15,
                symbolWeight: .semibold,
                tooltip: "Rate \(idx) out of 5 stars",
                fixedSize: NSSize(width: 36, height: 34),
                style: .clear,
                foregroundColor: NSColor(red: 1.0, green: 0.82, blue: 0.34, alpha: 1.0)
            ) { [weak self] in
                guard let self else { return }
                self.selectedStars = idx
                self.refreshUI()
                if self.starButtons.indices.contains(idx - 1) {
                    AppleMotion.springPop(self.starButtons[idx - 1], scale: 1.16, dampingRatio: 0.60, response: 0.28)
                }
            }
        }
        let starsRow = NSStackView(views: starButtons)
        starsRow.orientation = .horizontal
        starsRow.alignment = .centerY
        starsRow.spacing = 6

        ratingCaptionLabel = NSTextField(labelWithString: "")
        ratingCaptionLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        ratingCaptionLabel.textColor = NSColor(red: 1.0, green: 0.84, blue: 0.40, alpha: 1.0)

        let starStack = NSStackView(views: [starsRow, ratingCaptionLabel])
        starStack.orientation = .vertical
        starStack.alignment = .centerX
        starStack.spacing = 6
        starStack.translatesAutoresizingMaskIntoConstraints = false
        starCard.contentContainer.addSubview(starStack)
        NSLayoutConstraint.activate([
            starStack.centerXAnchor.constraint(equalTo: starCard.contentContainer.centerXAnchor),
            starStack.topAnchor.constraint(equalTo: starCard.contentContainer.topAnchor, constant: 10),
            starStack.bottomAnchor.constraint(equalTo: starCard.contentContainer.bottomAnchor, constant: -10)
        ])

        // Category picker (equal width pills)
        categoryButtons = [:]
        let categories = ["Feature Idea", "App Rating", "Bug Report"]
        let catViews = categories.map { cat -> LiquidGlassButton in
            let btn = LiquidGlassButton(
                title: cat,
                height: 28,
                style: .clear,
                font: .systemFont(ofSize: 11, weight: .semibold)
            ) { [weak self] in
                self?.selectedCategory = cat
                self?.refreshUI()
            }
            btn.setContentHuggingPriority(.defaultLow, for: .horizontal)
            categoryButtons[cat] = btn
            return btn
        }
        let catRow = NSStackView(views: catViews)
        catRow.orientation = .horizontal
        catRow.alignment = .centerY
        catRow.distribution = .fillEqually
        catRow.spacing = 8
        for idx in 1..<catViews.count {
            catViews[idx].widthAnchor.constraint(equalTo: catViews[0].widthAnchor).isActive = true
        }

        // Suggestion input box
        let inputCard = makeSettingsGlassCard(cornerRadius: 14)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = .labelColor
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.string = ""
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        self.notesTextView = textView

        let placeholderLabel = NSTextField(labelWithString: "Suggest a feature, tell us what you love, or report an issue (no personal data included)...")
        placeholderLabel.font = .systemFont(ofSize: 11, weight: .regular)
        placeholderLabel.textColor = .secondaryLabelColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        inputCard.contentContainer.addSubview(scrollView)
        inputCard.contentContainer.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            inputCard.heightAnchor.constraint(equalToConstant: 110),
            scrollView.leadingAnchor.constraint(equalTo: inputCard.contentContainer.leadingAnchor, constant: 4),
            scrollView.trailingAnchor.constraint(equalTo: inputCard.contentContainer.trailingAnchor, constant: -4),
            scrollView.topAnchor.constraint(equalTo: inputCard.contentContainer.topAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: inputCard.contentContainer.bottomAnchor, constant: -22),
            placeholderLabel.leadingAnchor.constraint(equalTo: inputCard.contentContainer.leadingAnchor, constant: 12),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: inputCard.contentContainer.trailingAnchor, constant: -12),
            placeholderLabel.bottomAnchor.constraint(equalTo: inputCard.contentContainer.bottomAnchor, constant: -6)
        ])

        // Bottom actions
        let laterTitle = isAutomaticMilestone ? "Later" : "Close"
        let laterBtn = LiquidGlassButton(title: laterTitle, height: 30, style: .clear) { [weak self] in
            self?.dismissWindow(markDeferred: true)
        }

        let neverAskBtn = LiquidGlassButton(title: "Don't Ask", height: 30, style: .clear) { [weak self] in
            AppSettings.shared.markFeedbackCompleted(stars: self?.selectedStars ?? 0)
            self?.dismissWindow(markDeferred: false)
        }
        neverAskBtn.isHidden = !isAutomaticMilestone

        let starGitHubBtn = LiquidGlassButton(
            symbol: "star.fill",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Star on GitHub",
            tooltip: "Open LoopSearch on GitHub to drop a star",
            height: 30,
            style: .clear,
            foregroundColor: NSColor(red: 1.0, green: 0.82, blue: 0.34, alpha: 0.96),
            font: .systemFont(ofSize: 11.5, weight: .semibold)
        ) { [weak self] in
            AppSettings.shared.markFeedbackCompleted(stars: self?.selectedStars ?? 5)
            NSWorkspace.shared.open(AppSettings.githubRepoURL)
            self?.onToastCallback?("Thank you for supporting LoopSearch!")
            self?.dismissWindow(markDeferred: false)
        }

        let sendBtn = LiquidGlassButton(
            symbol: "paperplane.fill",
            symbolPointSize: 10.5,
            symbolWeight: .semibold,
            title: "Send Feedback",
            tooltip: "Opens pre-filled GitHub Feedback form with your rating & suggestion",
            height: 30,
            style: .clear,
            font: .systemFont(ofSize: 11.5, weight: .semibold)
        ) { [weak self] in
            self?.submitFeedback()
        }
        sendBtn.setSelectedAccent(true)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let footer = NSStackView(views: [laterBtn, neverAskBtn, spacer, starGitHubBtn, sendBtn])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8

        let root = NSStackView(views: [headerRow, starCard, catRow, inputCard, footer])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        card.contentContainer.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: card.contentContainer.topAnchor, constant: 20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: card.contentContainer.bottomAnchor, constant: -16),
            starCard.widthAnchor.constraint(equalTo: root.widthAnchor),
            catRow.widthAnchor.constraint(equalTo: root.widthAnchor),
            inputCard.widthAnchor.constraint(equalTo: root.widthAnchor),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor)
        ])

        win.contentView = card
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        win.makeFirstResponder(textView)
        self.window = win
        refreshUI()
        AppleMotion.staggeredCardsReveal([starCard, catRow, inputCard], baseDelay: 0.03, stepDelay: 0.04)
    }

    private func refreshUI() {
        let captions = [
            1: "1 / 5 — Needs work",
            2: "2 / 5 — Could be better",
            3: "3 / 5 — Pretty good",
            4: "4 / 5 — Really like it!",
            5: "5 / 5 — Love LoopSearch!"
        ]
        ratingCaptionLabel.stringValue = captions[selectedStars] ?? "5 / 5 — Love LoopSearch!"

        for (idx, btn) in starButtons.enumerated() {
            let starNum = idx + 1
            let active = starNum <= selectedStars
            btn.setSelectedAccent(active)
            btn.alphaValue = active ? 1.0 : 0.45
        }

        for (cat, btn) in categoryButtons {
            btn.setSelectedAccent(cat == selectedCategory)
        }
    }

    private func submitFeedback() {
        let stars = String(repeating: "★", count: selectedStars) + String(repeating: "☆", count: 5 - selectedStars)
        let note = notesTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let appVer = AppUpdateChecker.currentVersion

        let issueTitle = "[\(selectedCategory)] \(selectedStars)/5 Rating"
            + (note.isEmpty ? "" : ": \(String(note.prefix(60)))")
        let issueBody = """
        **Rating:** \(stars) (\(selectedStars)/5)
        **Category:** \(selectedCategory)
        **App Version:** LoopSearch \(appVer)
        **macOS:** \(osVer)

        **Suggestion / Review:**
        \(note.isEmpty ? "_Enjoying LoopSearch!_" : note)
        """

        if var comps = URLComponents(url: AppSettings.githubIssuesNewURL, resolvingAgainstBaseURL: false) {
            comps.queryItems = [
                URLQueryItem(name: "title", value: issueTitle),
                URLQueryItem(name: "body", value: issueBody)
            ]
            if let url = comps.url {
                NSWorkspace.shared.open(url)
            }
        }

        AppSettings.shared.markFeedbackCompleted(stars: selectedStars)
        onToastCallback?("Thanks for rating LoopSearch (\(selectedStars)/5)!")
        dismissWindow(markDeferred: false)
    }

    private func dismissWindow(markDeferred: Bool) {
        if markDeferred && isAutomaticPrompt {
            AppSettings.shared.markFeedbackPromptDeferred()
        }
        window?.orderOut(nil)
        window = nil
    }
}
