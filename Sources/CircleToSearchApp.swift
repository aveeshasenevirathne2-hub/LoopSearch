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
    private let menuBarArrowController = MenuBarArrowCalloutController()
    private var isOverlayOpen = false
    private var lastObservedSignedInState = FirebaseAuthService.shared.isSignedIn
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    nonisolated(unsafe) private var reopenHistoryObserver: NSObjectProtocol?
    nonisolated(unsafe) private var authObserver: NSObjectProtocol?
    nonisolated(unsafe) private var guideClosedObserver: NSObjectProtocol?
    nonisolated(unsafe) private var updateObserver: NSObjectProtocol?
    private var lastToastedUpdateVersion: String?

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

    @objc private func installAvailableUpdate() {
        AppUpdateChecker.shared.installOrOpenAvailableUpdate()
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                self?.showMenuBarArrowPointer(message: "LoopSearch lives here in your Menu Bar")
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

        guideClosedObserver = NotificationCenter.default.addObserver(
            forName: .loopSearchGuideClosed,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let place = AppSettings.shared.hideDockIcon ? "Menu Bar" : "Dock & Menu Bar"
                self.showMenuBarArrowPointer(
                    message: "Welcome to LoopSearch! Always ready in your \(place) — press \(AppSettings.shared.activeHotkeyDisplayString)"
                )
            }
        }

        updateObserver = NotificationCenter.default.addObserver(
            forName: .loopSearchUpdateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildMenu()
                if let update = AppUpdateChecker.shared.availableUpdate,
                   self.lastToastedUpdateVersion != update.version {
                    self.lastToastedUpdateVersion = update.version
                    self.toastController.show(
                        message: "Update available: LoopSearch v\(update.version) — click Updates in Studio or Menu Bar",
                        duration: 4.2
                    )
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isOverlayOpen else { return true }
        if !flag {
            if !FirebaseAuthService.shared.isSignedIn || !AppSettings.shared.hasCompletedOnboarding {
                openOnboarding()
            } else {
                openSettings()
            }
        }
        return true
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
        if let guideClosedObserver {
            NotificationCenter.default.removeObserver(guideClosedObserver)
        }
        if let updateObserver {
            NotificationCenter.default.removeObserver(updateObserver)
        }
    }

    private func showMenuBarArrowPointer(message: String) {
        let itemFrame = statusItem.button?.window?.frame
        menuBarArrowController.show(pointingAt: itemFrame, message: message)
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

        if let update = AppUpdateChecker.shared.availableUpdate {
            let updateNowItem = NSMenuItem(
                title: "Update Available: v\(update.version) — Install…",
                action: #selector(installAvailableUpdate),
                keyEquivalent: ""
            )
            updateNowItem.target = self
            updateNowItem.image = loopSymbolImage("loopsearch.logo", accessibility: "Update Available", pointSize: 12)
            menu.addItem(updateNowItem)
            menu.addItem(.separator())
        }

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

        let clipboardItem = NSMenuItem(
            title: "Search Clipboard Image…",
            action: #selector(searchClipboardImage),
            keyEquivalent: ""
        )
        clipboardItem.target = self
        menu.addItem(clipboardItem)

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

        // Results Browser Mode submenu (Auto / Dark / Light)
        let currentWebTheme = AppSettings.shared.webResultsTheme
        let webThemeMenu = NSMenu()
        for themeOption in AppTheme.allCases {
            let label = themeOption == .system ? "Auto (Match App)" : themeOption.title
            let item = NSMenuItem(
                title: label,
                action: #selector(selectWebResultsTheme(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = themeOption.rawValue
            item.state = (currentWebTheme == themeOption) ? .on : .off
            webThemeMenu.addItem(item)
        }
        let webThemeRoot = NSMenuItem(title: "Results Browser (\(currentWebTheme.title))", action: nil, keyEquivalent: "")
        webThemeRoot.submenu = webThemeMenu
        menu.addItem(webThemeRoot)

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

        let updatesTitle = AppUpdateChecker.shared.availableUpdate.map { "Install Update (v\($0.version))…" } ?? "Check for Updates…"
        let updatesAction: Selector = AppUpdateChecker.shared.availableUpdate != nil ? #selector(installAvailableUpdate) : #selector(checkForUpdates)
        let updatesItem = NSMenuItem(title: updatesTitle, action: updatesAction, keyEquivalent: "")
        updatesItem.target = self
        menu.addItem(updatesItem)

        let disclaimerItem = NSMenuItem(title: "Independent app • Not affiliated with Google", action: nil, keyEquivalent: "")
        disclaimerItem.isEnabled = false
        menu.addItem(disclaimerItem)

        menu.addItem(.separator())

        let dockVisibleItem = NSMenuItem(
            title: "Keep Icon in Dock",
            action: #selector(toggleKeepDockIcon),
            keyEquivalent: ""
        )
        dockVisibleItem.target = self
        dockVisibleItem.state = AppSettings.shared.hideDockIcon ? .off : .on
        menu.addItem(dockVisibleItem)

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

    @objc private func selectWebResultsTheme(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let theme = AppTheme(rawValue: raw) else { return }
        AppSettings.shared.webResultsTheme = theme
        rebuildMenu()
        toastController.show(message: "Results browser theme: \(theme.title)")
    }

    @objc private func toggleKeepDockIcon() {
        let shouldHide = !AppSettings.shared.hideDockIcon
        AppSettings.shared.hideDockIcon = shouldHide
        rebuildMenu()
        toastController.show(
            message: shouldHide ? "Dock icon hidden — find LoopSearch in Menu Bar" : "Dock icon visible",
            duration: 2.6
        )
    }

    @objc private func searchClipboardImage() {
        guard ensureSignedInOrPrompt() else { return }
        let pb = NSPasteboard.general
        guard let nsImage = NSImage(pasteboard: pb) else {
            toastController.show(message: "Copy an image or screenshot to clipboard first", duration: 2.8)
            return
        }
        var rect = NSRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            toastController.show(message: "Clipboard does not contain a readable image", duration: 2.8)
            return
        }
        let screen = ScreenCaptureService.activeScreen()
        Task { [weak self] in
            guard let self else { return }
            let bg: CGImage
            if ScreenCaptureService.hasPermission,
               let live = try? await ScreenCaptureService.captureScreen(screen) {
                bg = live
            } else if let ambient = self.makeAmbientBackdrop(for: screen) {
                bg = ambient
            } else {
                bg = cgImage
            }
            let selectionRect = self.centeredOverlayRect(for: cgImage, on: screen)
            self.presentOverlay(screenshot: bg, screen: screen, initialSelection: (image: cgImage, rect: selectionRect))
        }
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
                let rect = self.centeredOverlayRect(for: entry.cgImage, on: screen)
                self.presentOverlay(screenshot: bg, screen: screen, initialSelection: (image: entry.cgImage, rect: rect))
            } catch {
                self.showPermissionAlert(error: error)
            }
        }
    }

    private func centeredOverlayRect(for image: CGImage, on screen: NSScreen) -> CGRect {
        let w = min(max(180, CGFloat(image.width) * 0.5), screen.frame.width * 0.45)
        let h = min(max(120, CGFloat(image.height) * 0.5), screen.frame.height * 0.35)
        return CGRect(
            x: screen.frame.width * 0.5 - w * 0.5,
            y: screen.frame.height * 0.22,
            width: w,
            height: h
        )
    }

    private func presentOverlay(
        screenshot: CGImage,
        screen: NSScreen,
        initialSelection: (image: CGImage, rect: CGRect)? = nil
    ) {
        isOverlayOpen = true
        overlayController.show(
            screenshot: screenshot,
            screen: screen,
            selectionMode: selectionMode,
            initialSelection: initialSelection,
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
    }

    private func makeAmbientBackdrop(for screen: NSScreen) -> CGImage? {
        let scale = screen.backingScaleFactor
        let w = max(640, Int(screen.frame.width * scale))
        let h = max(480, Int(screen.frame.height * scale))
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let colors = [
            CGColor(red: 0.04, green: 0.06, blue: 0.12, alpha: 1),
            CGColor(red: 0.08, green: 0.15, blue: 0.28, alpha: 1)
        ] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: 0, y: CGFloat(h)),
                end: CGPoint(x: CGFloat(w), y: 0),
                options: []
            )
        }
        return ctx.makeImage()
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
                self.presentOverlay(screenshot: image, screen: screen)
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

/// Animated curved-arrow callout pointing directly at LoopSearch's Menu Bar status icon on first launch & setup completion.
@MainActor
private final class MenuBarArrowCalloutController {
    private var window: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(pointingAt statusItemRect: NSRect?, message: String) {
        dismissTask?.cancel()
        window?.orderOut(nil)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width: CGFloat = 310
        let height: CGFloat = 118
        let targetX: CGFloat
        let targetY: CGFloat
        if let rect = statusItemRect {
            targetX = max(screen.frame.minX + 16, min(screen.frame.maxX - width - 14, rect.maxX - width + 32))
            targetY = rect.minY - height - 4
        } else {
            targetX = screen.visibleFrame.maxX - width - 22
            targetY = screen.visibleFrame.maxY - height - 6
        }

        let panel = NSPanel(
            contentRect: NSRect(x: targetX, y: targetY, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.ignoresMouseEvents = false

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true

        // Curved animated cyan/blue arrow pointing up-right toward the Menu Bar icon
        let arrowHost = NSView(frame: NSRect(x: width - 86, y: height - 56, width: 64, height: 54))
        arrowHost.wantsLayer = true
        let arrowLayer = CAShapeLayer()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10, y: 6))
        path.addQuadCurve(to: CGPoint(x: 44, y: 48), control: CGPoint(x: 8, y: 42))
        // Arrowhead
        path.move(to: CGPoint(x: 34, y: 40))
        path.addLine(to: CGPoint(x: 44, y: 48))
        path.addLine(to: CGPoint(x: 49, y: 35))
        arrowLayer.path = path
        arrowLayer.strokeColor = NSColor(red: 0.08, green: 0.64, blue: 1.0, alpha: 0.98).cgColor
        arrowLayer.fillColor = NSColor.clear.cgColor
        arrowLayer.lineWidth = 4.2
        arrowLayer.lineCap = .round
        arrowLayer.lineJoin = .round
        arrowLayer.shadowColor = NSColor(red: 0.22, green: 0.74, blue: 0.97, alpha: 0.8).cgColor
        arrowLayer.shadowRadius = 8
        arrowLayer.shadowOpacity = 0.7
        arrowLayer.shadowOffset = .zero
        arrowHost.layer?.addSublayer(arrowLayer)

        let drawAnim = CABasicAnimation(keyPath: "strokeEnd")
        drawAnim.fromValue = 0.0
        drawAnim.toValue = 1.0
        drawAnim.duration = 0.55
        drawAnim.timingFunction = AppleMotion.easeOut
        arrowLayer.add(drawAnim, forKey: "arrowDraw")

        let pulseAnim = CABasicAnimation(keyPath: "transform.translation.y")
        pulseAnim.fromValue = 0
        pulseAnim.toValue = 4
        pulseAnim.duration = 0.9
        pulseAnim.autoreverses = true
        pulseAnim.repeatCount = .infinity
        pulseAnim.timingFunction = AppleMotion.easeInOut
        arrowHost.layer?.add(pulseAnim, forKey: "arrowFloat")

        let card = LiquidGlassSurfaceView(cornerRadius: 16, style: .regular, tintColor: NSColor.systemBlue.withAlphaComponent(0.18))
        card.frame = NSRect(x: 0, y: 0, width: width - 16, height: 64)
        let logo = LoopBrandLogoView(size: 24)
        logo.translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12.0, weight: .semibold)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        card.contentContainer.addSubview(logo)
        card.contentContainer.addSubview(label)
        NSLayoutConstraint.activate([
            logo.leadingAnchor.constraint(equalTo: card.contentContainer.leadingAnchor, constant: 12),
            logo.centerYAnchor.constraint(equalTo: card.contentContainer.centerYAnchor),
            logo.widthAnchor.constraint(equalToConstant: 24),
            logo.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: logo.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: card.contentContainer.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: card.contentContainer.centerYAnchor)
        ])

        root.addSubview(card)
        root.addSubview(arrowHost)
        panel.contentView = root
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        window = panel

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = AppleMotion.duration(0.28)
            ctx.timingFunction = AppleMotion.easeOut
            panel.animator().alphaValue = 1.0
        }

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 6_500_000_000)
            guard !Task.isCancelled, self.window === panel else { return }
            await NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = AppleMotion.duration(0.24)
                ctx.timingFunction = AppleMotion.easeIn
                panel.animator().alphaValue = 0.0
            }
            guard !Task.isCancelled, self.window === panel else { return }
            panel.orderOut(nil)
            self.window = nil
        }
    }
}
