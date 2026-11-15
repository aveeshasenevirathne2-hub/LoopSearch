import AppKit

@main
struct CircleToSearchEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(AppSettings.shared.hideDockIcon ? .accessory : .regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private let overlayController = OverlayWindowController()
    private let toastController = ToastWindowController()
    private var isOverlayOpen = false
    private var lastObservedSignedInState = FirebaseAuthService.shared.isSignedIn
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    nonisolated(unsafe) private var reopenHistoryObserver: NSObjectProtocol?
    nonisolated(unsafe) private var authObserver: NSObjectProtocol?

    private var selectionMode: SelectionMode {
        get { AppSettings.shared.selectionMode }
        set { AppSettings.shared.selectionMode = newValue }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openOnboarding() {
        OnboardingWindowController.shared.show { [weak self] in
            self?.triggerCircleToSearch()
        }
    }

    @objc private func openHowToUse() {
        HowToUseWindowController.shared.show(justSignedIn: false) { [weak self] in
            self?.triggerCircleToSearch()
        }
    }

    @objc private func openAbout() {
        AboutWindowController.shared.show()
    }

    @objc private func openFeedback() {
        FeedbackWindowController.shared.show(isAutomaticMilestone: false) { [weak self] msg in
            self?.toastController.show(message: msg, duration: 2.8)
        }
    }

    private func handleOverlayClosed() {
        isOverlayOpen = false
        guard AppSettings.shared.shouldPromptForFeedback else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            FeedbackWindowController.shared.show(isAutomaticMilestone: true) { [weak self] msg in
                self?.toastController.show(message: msg, duration: 2.8)
            }
        }
    }

    @objc private func checkForUpdates() {
        AppUpdateChecker.shared.checkForUpdates(interactive: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.shared.applyAppAppearance()
        AppSettings.shared.applyDockPolicy()
        ScreenCaptureService.prewarm()

        setupStatusItem()
        hotkeyManager = HotkeyManager { [weak self] in
            self?.triggerCircleToSearch()
        }
        rebuildMenu()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .circleToSearchSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let s = AppSettings.shared
                if s.useCustomHotkey {
                    self.hotkeyManager.applyCustomHotkey(
                        keyCode: s.customKeyCode,
                        carbonModifiers: s.customCarbonModifiers
                    )
                } else {
                    self.hotkeyManager.preset = s.hotkeyPreset
                }
                self.rebuildMenu()
            }
        }

        reopenHistoryObserver = NotificationCenter.default.addObserver(
            forName: .circleToSearchReopenHistory,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let index = note.userInfo?["index"] as? Int else { return }
            Task { @MainActor [weak self] in
                self?.reopenHistoryEntry(at: index)
            }
        }

        authObserver = NotificationCenter.default.addObserver(
            forName: .loopSearchAuthChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildMenu()
                let isNowSignedIn = FirebaseAuthService.shared.isSignedIn
                if !self.lastObservedSignedInState && isNowSignedIn {
                    self.lastObservedSignedInState = true
                    if !AppSettings.shared.hasSeenHowToUseGuide {
                        AppSettings.shared.hasSeenHowToUseGuide = true
                        AppSettings.shared.hasCompletedOnboarding = true
                        OnboardingWindowController.shared.dismiss()
                        HowToUseWindowController.shared.show(justSignedIn: true) { [weak self] in
                            self?.triggerCircleToSearch()
                        }
                    }
                } else {
                    self.lastObservedSignedInState = isNowSignedIn
                }
            }
        }

        Task { @MainActor [weak self] in
            let wasSignedIn = FirebaseAuthService.shared.isSignedIn
            await FirebaseAuthService.shared.restoreAndSyncOnLaunch()
            self?.rebuildMenu()
            if wasSignedIn && !FirebaseAuthService.shared.isSignedIn {
                self?.toastController.show(message: "Session expired — please sign in with Google", duration: 3.0)
                OnboardingWindowController.shared.show { [weak self] in
                    self?.triggerCircleToSearch()
                }
            }
        }

        if !AppSettings.shared.hasCompletedOnboarding || !FirebaseAuthService.shared.isSignedIn {
            OnboardingWindowController.shared.show { [weak self] in
                self?.triggerCircleToSearch()
            }
        } else {
            toastController.show(
                message: "LoopSearch ready — press \(AppSettings.shared.activeHotkeyDisplayString)",
                duration: 2.8
            )
        }

        if AppSettings.shared.autoCheckForUpdates {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                AppUpdateChecker.shared.checkForUpdates(interactive: false)
            }
        }
    }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let reopenHistoryObserver {
            NotificationCenter.default.removeObserver(reopenHistoryObserver)
        }
        if let authObserver {
            NotificationCenter.default.removeObserver(authObserver)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "lasso.badge.sparkles", accessibilityDescription: "LoopSearch")
                ?? NSImage(systemSymbolName: "sparkle.magnifyingglass", accessibilityDescription: "LoopSearch")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "LoopSearch — Visual Screen Search (Not affiliated with Google)"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let triggerTitle = FirebaseAuthService.shared.isSignedIn
            ? "Start LoopSearch (\(AppSettings.shared.activeHotkeyDisplayString))"
            : "Start LoopSearch (Sign In Required)"
        let triggerItem = NSMenuItem(
            title: triggerTitle,
            action: #selector(triggerFromMenu),
            keyEquivalent: ""
        )
        triggerItem.target = self
        menu.addItem(triggerItem)

        if let session = FirebaseAuthService.shared.session {
            let accountMenu = NSMenu()
            if !session.email.isEmpty {
                let emailItem = NSMenuItem(title: session.email, action: nil, keyEquivalent: "")
                emailItem.isEnabled = false
                accountMenu.addItem(emailItem)
                accountMenu.addItem(.separator())
            }
            let switchItem = NSMenuItem(title: "Switch Google Account…", action: #selector(switchGoogleAccount), keyEquivalent: "")
            switchItem.target = self
            accountMenu.addItem(switchItem)

            let signOutItem = NSMenuItem(title: "Sign Out", action: #selector(signOutGoogleAccount), keyEquivalent: "")
            signOutItem.target = self
            accountMenu.addItem(signOutItem)

            let accountRoot = NSMenuItem(title: "Account: \(session.effectiveDisplayName)", action: nil, keyEquivalent: "")
            accountRoot.submenu = accountMenu
            menu.addItem(accountRoot)
        } else {
            let signInItem = NSMenuItem(
                title: "Sign In with Google… (Required)",
                action: #selector(openSignInGate),
                keyEquivalent: ""
            )
            signInItem.target = self
            menu.addItem(signInItem)
        }

        menu.addItem(.separator())

        // Hotkey submenu
        let hotkeyMenu = NSMenu()
        for preset in HotkeyPreset.allCases {
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(selectHotkeyPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = (!AppSettings.shared.useCustomHotkey && hotkeyManager.preset == preset) ? .on : .off
            hotkeyMenu.addItem(item)
        }
        let conflictSuffix = hotkeyManager.carbonRegistrationError == noErr ? "" : " [Conflict]"
        let hotkeyRoot = NSMenuItem(
            title: "Keyboard Shortcut (\(AppSettings.shared.activeHotkeyDisplayString))\(conflictSuffix)",
            action: nil,
            keyEquivalent: ""
        )
        hotkeyRoot.submenu = hotkeyMenu
        menu.addItem(hotkeyRoot)

        // Selection Mode submenu
        let modeMenu = NSMenu()
        for mode in SelectionMode.allCases {
            let item = NSMenuItem(
                title: "\(mode.shortcutBadge) — \(mode.title)",
                action: #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (selectionMode == mode) ? .on : .off
            modeMenu.addItem(item)
        }
        let modeRoot = NSMenuItem(title: "Selection Mode (\(selectionMode.shortTitle))", action: nil, keyEquivalent: "")
        modeRoot.submenu = modeMenu
        menu.addItem(modeRoot)

        // Search Engine submenu
        let currentEngine = AppSettings.shared.searchEngine
        let engineMenu = NSMenu()
        for engine in SearchEngine.allCases {
            let item = NSMenuItem(
                title: engine.title,
                action: #selector(selectSearchEngine(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = engine.rawValue
            item.state = (currentEngine == engine) ? .on : .off
            engineMenu.addItem(item)
        }
        let engineRoot = NSMenuItem(title: "Search Engine (\(currentEngine.shortTitle))", action: nil, keyEquivalent: "")
        engineRoot.submenu = engineMenu
        menu.addItem(engineRoot)

        // Capture History submenu
        let historyItems = CaptureHistoryStore.shared.items
        let historyMenu = NSMenu()
        if historyItems.isEmpty {
            let emptyItem = NSMenuItem(title: "No captures yet", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            for (index, entry) in historyItems.enumerated() {
                let snippet = entry.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let shortLabel = snippet.isEmpty
                    ? "Visual Capture (\(entry.dominantHex.isEmpty ? "Image" : entry.dominantHex))"
                    : String(snippet.prefix(34)) + (snippet.count > 34 ? "…" : "")
                let item = NSMenuItem(
                    title: "\(formatter.string(from: entry.timestamp)) — \(shortLabel)",
                    action: #selector(reopenHistoryCapture(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                let thumb = NSImage(cgImage: entry.cgImage, size: NSSize(width: 28, height: 20))
                item.image = thumb
                historyMenu.addItem(item)
            }
            historyMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear Capture History", action: #selector(clearCaptureHistory), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
        }
        let historyRoot = NSMenuItem(
            title: "Capture History (\(historyItems.count))",
            action: nil,
            keyEquivalent: ""
        )
        historyRoot.submenu = historyMenu
        menu.addItem(historyRoot)

        if PinnedCaptureManager.shared.count > 0 {
            let unpinAllItem = NSMenuItem(
                title: "Close All Pinned Captures (\(PinnedCaptureManager.shared.count))",
                action: #selector(closeAllPinnedCaptures),
                keyEquivalent: ""
            )
            unpinAllItem.target = self
            menu.addItem(unpinAllItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let onboardingItem = NSMenuItem(title: "Welcome Setup Guide...", action: #selector(openOnboarding), keyEquivalent: "")
        onboardingItem.target = self
        menu.addItem(onboardingItem)

        let howToUseItem = NSMenuItem(title: "How to Use LoopSearch…", action: #selector(openHowToUse), keyEquivalent: "")
        howToUseItem.target = self
        menu.addItem(howToUseItem)

        let aboutItem = NSMenuItem(title: "About LoopSearch", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let rateItem = NSMenuItem(title: "Rate & Suggest Feature…", action: #selector(openFeedback), keyEquivalent: "")
        rateItem.target = self
        menu.addItem(rateItem)

        let updatesItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        let disclaimerItem = NSMenuItem(title: "Independent app • Not affiliated with Google", action: nil, keyEquivalent: "")
        disclaimerItem.isEnabled = false
        menu.addItem(disclaimerItem)

        menu.addItem(.separator())

        let hasScreenPerm = ScreenCaptureService.hasPermission
        let screenPermItem = NSMenuItem(
            title: hasScreenPerm ? "✓ Screen Recording: Granted" : "Grant Screen Recording Permission...",
            action: hasScreenPerm ? nil : #selector(openScreenRecordingSettings),
            keyEquivalent: ""
        )
        screenPermItem.target = self
        menu.addItem(screenPermItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LoopSearch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func triggerFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.triggerCircleToSearch()
        }
    }

    @objc private func openSignInGate() {
        OnboardingWindowController.shared.show { [weak self] in
            self?.triggerCircleToSearch()
        }
    }

    @objc private func switchGoogleAccount() {
        Task { @MainActor [weak self] in
            let ok = await FirebaseAuthService.shared.signInWithGoogle()
            if ok, let email = FirebaseAuthService.shared.session?.email {
                self?.toastController.show(message: "Signed in as \(email)")
            } else if let err = FirebaseAuthService.shared.lastAuthError {
                self?.toastController.show(message: err, duration: 3.2)
            }
        }
    }

    @objc private func signOutGoogleAccount() {
        FirebaseAuthService.shared.signOut()
        rebuildMenu()
        toastController.show(message: "Signed out of Google Account")
        OnboardingWindowController.shared.show { [weak self] in
            self?.triggerCircleToSearch()
        }
    }

    @objc private func selectHotkeyPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let preset = HotkeyPreset(rawValue: raw) else { return }
        AppSettings.shared.hotkeyPreset = preset
        hotkeyManager.preset = preset
        rebuildMenu()
        if hotkeyManager.carbonRegistrationError != noErr {
            toastController.show(
                message: "\(preset.title) is already used by macOS or another app — pick another shortcut",
                duration: 3.2
            )
        } else {
            toastController.show(message: "Global shortcut set to \(preset.title)")
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SelectionMode(rawValue: raw) else { return }
        selectionMode = mode
        rebuildMenu()
    }

    @objc private func selectSearchEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let engine = SearchEngine(rawValue: raw) else { return }
        AppSettings.shared.searchEngine = engine
        rebuildMenu()
        toastController.show(message: "Default search engine: \(engine.title)")
    }

    @objc private func reopenHistoryCapture(_ sender: NSMenuItem) {
        reopenHistoryEntry(at: sender.tag)
    }

    private func reopenHistoryEntry(at index: Int) {
        guard ensureSignedInOrPrompt() else { return }
        let items = CaptureHistoryStore.shared.items
        guard items.indices.contains(index) else { return }
        let entry = items[index]
        let screen = ScreenCaptureService.activeScreen()
        Task { [weak self] in
            guard let self else { return }
            do {
                let bg = try await ScreenCaptureService.captureScreen(screen)
                let w = min(max(180, CGFloat(entry.cgImage.width) * 0.5), screen.frame.width * 0.45)
                let h = min(max(120, CGFloat(entry.cgImage.height) * 0.5), screen.frame.height * 0.35)
                let rect = CGRect(
                    x: screen.frame.width * 0.5 - w * 0.5,
                    y: screen.frame.height * 0.22,
                    width: w,
                    height: h
                )
                self.isOverlayOpen = true
                self.overlayController.show(
                    screenshot: bg,
                    screen: screen,
                    selectionMode: self.selectionMode,
                    initialSelection: (image: entry.cgImage, rect: rect),
                    onShowToast: { [weak self] msg in
                        self?.toastController.show(message: msg, duration: 2.6)
                    },
                    onOpenSettings: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.openSettings()
                        }
                    },
                    onClose: { [weak self] in
                        self?.handleOverlayClosed()
                    }
                )
            } catch {
                self.showPermissionAlert(error: error)
            }
        }
    }

    @objc private func clearCaptureHistory() {
        CaptureHistoryStore.shared.clear()
        rebuildMenu()
        toastController.show(message: "Capture history cleared")
    }

    @objc private func closeAllPinnedCaptures() {
        PinnedCaptureManager.shared.closeAll()
        rebuildMenu()
        toastController.show(message: "Closed all pinned captures")
    }

    @objc private func openScreenRecordingSettings() {
        ScreenCaptureService.openSystemSettings()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func triggerCircleToSearch() {
        if isOverlayOpen {
            overlayController.close()
            return
        }

        guard ensureSignedInOrPrompt() else { return }

        let screen = ScreenCaptureService.activeScreen()
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await ScreenCaptureService.captureScreen(screen)
                self.isOverlayOpen = true
                self.overlayController.show(
                    screenshot: image,
                    screen: screen,
                    selectionMode: self.selectionMode,
                    onShowToast: { [weak self] msg in
                        self?.toastController.show(message: msg, duration: 2.6)
                    },
                    onOpenSettings: { [weak self] in
                        Task { @MainActor [weak self] in
                            self?.openSettings()
                        }
                    },
                    onClose: { [weak self] in
                        self?.handleOverlayClosed()
                    }
                )
            } catch {
                self.showPermissionAlert(error: error)
            }
        }
    }

    private func showPermissionAlert(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            ScreenCaptureService.openSystemSettings()
        }
    }

    @discardableResult
    private func ensureSignedInOrPrompt() -> Bool {
        if FirebaseAuthService.shared.isSignedIn {
            return true
        }
        toastController.show(message: "Sign in with Google required to use LoopSearch", duration: 2.8)
        OnboardingWindowController.shared.show { [weak self] in
            self?.triggerCircleToSearch()
        }
        return false
    }
}

@MainActor
private final class ToastWindowController {
    private var window: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func show(message: String, duration: TimeInterval = 2.4) {
        dismissTask?.cancel()
        window?.orderOut(nil)

        let screen = ScreenCaptureService.activeScreen()
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let width: CGFloat = min(520, max(230, textWidth + 68))
        let height: CGFloat = 42
        let origin = NSPoint(
            x: screen.frame.midX - width / 2,
            y: screen.visibleFrame.minY + 36
        )

        let win = NSWindow(
            contentRect: NSRect(origin: origin, size: NSSize(width: width, height: height)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .transient]

        let pill = LiquidGlassSurfaceView(
            cornerRadius: height / 2,
            style: .regular,
            tintColor: NSColor(red: 0.028, green: 0.036, blue: 0.078, alpha: 0.90),
            lightTintColor: NSColor(white: 0.96, alpha: 0.90)
        )
        pill.horizonGlowIntensity = 0.85
        pill.horizonPoolHeightFraction = 0.62
        pill.horizonRimStrength = 1.18
        pill.frame = NSRect(x: 0, y: 0, width: width, height: height)
        pill.wantsLayer = true

        let icon = LoopBrandLogoView(size: 18)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.required, for: .horizontal)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.contentContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: pill.contentContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: pill.contentContainer.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: pill.contentContainer.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: pill.contentContainer.trailingAnchor, constant: -16)
        ])

        win.contentView = pill
        win.alphaValue = 0
        win.orderFrontRegardless()
        self.window = win

        let targetFrame = win.frame
        var startFrame = targetFrame
        startFrame.origin.y -= 16
        win.setFrame(startFrame, display: false)

        if let pillLayer = pill.layer {
            let startXform = AppleMotion.centeredTransform(bounds: pill.bounds, scale: 0.90, rotationZ: -0.025)
            let spring = AppleMotion.spring(
                keyPath: "transform",
                from: startXform,
                to: CATransform3DIdentity,
                dampingRatio: 0.76,
                response: 0.36
            )
            pillLayer.transform = CATransform3DIdentity
            pillLayer.add(spring, forKey: "toastPop")
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.32)
            ctx.timingFunction = AppleMotion.easeOut
            win.animator().setFrame(targetFrame, display: true)
            win.animator().alphaValue = 1.0
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let activeWin = self.window, activeWin === win else { return }
            var exitFrame = activeWin.frame
            exitFrame.origin.y -= 10
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppleMotion.duration(0.22)
                ctx.timingFunction = AppleMotion.easeIn
                activeWin.animator().setFrame(exitFrame, display: true)
                activeWin.animator().alphaValue = 0.0
            }
            guard !Task.isCancelled, self.window === win else { return }
            win.orderOut(nil)
            self.window = nil
        }
    }
}
