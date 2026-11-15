import AppKit
import ScreenCaptureKit

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case displayNotFound
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required. Please enable Circle to Search in System Settings > Privacy & Security > Screen & System Audio Recording."
        case .displayNotFound:
            return "Could not find the active display to capture."
        case .captureFailed:
            return "Failed to capture the screen."
        }
    }
}

enum ScreenCaptureService {
    private struct CachedDisplayFilter {
        let filter: SCContentFilter
        let width: Int
        let height: Int
    }

    @MainActor
    private static var filterCache: [CGDirectDisplayID: CachedDisplayFilter] = [:]

    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Pre-warms the ScreenCaptureKit display filter cache so the first hotkey press is instantaneous.
    @MainActor
    static func prewarm() {
        guard hasPermission else { return }
        Task { @MainActor in
            _ = try? await refreshFilterCache()
        }
    }

    @MainActor
    @discardableResult
    private static func refreshFilterCache() async throws -> [CGDirectDisplayID: CachedDisplayFilter] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.permissionDenied
        }

        let selfPID = ProcessInfo.processInfo.processIdentifier
        let excludedApps = content.applications.filter { $0.processID == selfPID }
        var updated: [CGDirectDisplayID: CachedDisplayFilter] = [:]
        for display in content.displays {
            let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
            updated[display.displayID] = CachedDisplayFilter(
                filter: filter,
                width: display.width,
                height: display.height
            )
        }
        filterCache = updated
        return updated
    }

    @MainActor
    static func activeScreen() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    @MainActor
    static func captureScreen(_ screen: NSScreen) async throws -> CGImage {
        let screenNumber = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? CGMainDisplayID()
        let scale = screen.backingScaleFactor
        let expectedW = Int(screen.frame.width)
        let expectedH = Int(screen.frame.height)

        if let cached = filterCache[screenNumber],
           cached.width == expectedW,
           cached.height == expectedH,
           let fastImage = try? await captureWithFilter(cached, scale: scale) {
            return fastImage
        }

        let refreshed = try await refreshFilterCache()
        guard let entry = refreshed[screenNumber] ?? refreshed.values.first else {
            throw ScreenCaptureError.displayNotFound
        }
        do {
            return try await captureWithFilter(entry, scale: scale)
        } catch {
            throw ScreenCaptureError.captureFailed
        }
    }

    private static func captureWithFilter(_ entry: CachedDisplayFilter, scale: CGFloat) async throws -> CGImage {
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(entry.width) * scale)
        config.height = Int(CGFloat(entry.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: entry.filter, configuration: config)
    }
}
