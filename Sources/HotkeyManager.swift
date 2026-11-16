import AppKit
import Carbon

enum HotkeyPreset: String, CaseIterable, Identifiable {
    case cmdShiftSpace = "cmdShiftSpace"
    case doubleTapCmd = "doubleTapCmd"
    case doubleTapOption = "doubleTapOption"
    case optionSpace = "optionSpace"
    case cmdShiftS = "cmdShiftS"
    case cmdShiftG = "cmdShiftG"
    case ctrlShiftSpace = "ctrlShiftSpace"
    case cmdRightArrow = "cmdRightArrow"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cmdShiftSpace: return "⌘ + ⇧ + Space"
        case .doubleTapCmd: return "Double-Tap ⌘"
        case .doubleTapOption: return "Double-Tap ⌥"
        case .optionSpace: return "⌥ + Space"
        case .cmdShiftS: return "⌘ + ⇧ + S"
        case .cmdShiftG: return "⌘ + ⇧ + G"
        case .ctrlShiftSpace: return "⌃ + ⇧ + Space"
        case .cmdRightArrow: return "⌘ + →"
        }
    }

    var subtitle: String {
        commonUsageWarning ?? "Activate LoopSearch (\(title))"
    }

    var commonUsageWarning: String? {
        switch self {
        case .cmdRightArrow:
            return "Warning: ⌘ + → is macOS’s standard “Jump to End of Line” key in text editors. Consider ⌘⇧Space or Double-Tap ⌘."
        case .cmdShiftG:
            return "Note: ⌘ + ⇧ + G is used for “Find Previous” or “Go to Folder” in Finder and browsers."
        case .optionSpace:
            return "Note: ⌥ + Space is sometimes used by Raycast, Alfred, or non-breaking space."
        default:
            return nil
        }
    }

    var isModifierDoubleTap: Bool {
        self == .doubleTapCmd || self == .doubleTapOption
    }

    var keyCode: UInt32 {
        switch self {
        case .cmdRightArrow: return UInt32(kVK_RightArrow)
        case .cmdShiftSpace, .optionSpace, .ctrlShiftSpace, .doubleTapCmd, .doubleTapOption:
            return UInt32(kVK_Space)
        case .cmdShiftS: return UInt32(kVK_ANSI_S)
        case .cmdShiftG: return UInt32(kVK_ANSI_G)
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .cmdRightArrow, .doubleTapCmd:
            return UInt32(cmdKey)
        case .cmdShiftSpace, .cmdShiftS, .cmdShiftG:
            return UInt32(cmdKey | shiftKey)
        case .optionSpace, .doubleTapOption:
            return UInt32(optionKey)
        case .ctrlShiftSpace:
            return UInt32(controlKey | shiftKey)
        }
    }
}

@MainActor
final class HotkeyManager {
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private var globalFlagsMonitor: Any?
    nonisolated(unsafe) private var localFlagsMonitor: Any?
    nonisolated(unsafe) private var globalKeyMonitor: Any?
    nonisolated(unsafe) private var localKeyMonitor: Any?

    private let onTrigger: () -> Void
    private var lastTriggerTime: Date = .distantPast
    private var lastModifierReleaseTime: TimeInterval = 0
    private var modifierDownTimestamp: TimeInterval = 0
    private var modifierWasCleanTap = false

    private(set) var carbonRegistrationError: OSStatus = noErr

    var preset: HotkeyPreset {
        didSet {
            UserDefaults.standard.set(preset.rawValue, forKey: "hotkeyPreset")
            registerActiveHotKey()
        }
    }

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger

        let savedPreset = UserDefaults.standard.string(forKey: "hotkeyPreset")
            .flatMap(HotkeyPreset.init(rawValue:)) ?? .doubleTapCmd
        self.preset = savedPreset

        installCarbonHandler()
        installModifierTapMonitors()
        registerActiveHotKey()
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let globalFlagsMonitor { NSEvent.removeMonitor(globalFlagsMonitor) }
        if let localFlagsMonitor { NSEvent.removeMonitor(localFlagsMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    private func fireTrigger() {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) > 0.25 else { return }
        lastTriggerTime = now
        onTrigger()
    }

    private func installModifierTapMonitors() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleFlagsChanged(event)
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.modifierWasCleanTap = false
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.modifierWasCleanTap = false
            }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard preset.isModifierDoubleTap else { return }
        let targetFlag: NSEvent.ModifierFlags = (preset == .doubleTapCmd) ? .command : .option
        let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let flags = event.modifierFlags.intersection(relevantModifiers)
        let now = ProcessInfo.processInfo.systemUptime

        if flags == targetFlag {
            modifierDownTimestamp = now
            modifierWasCleanTap = true
        } else if flags.isEmpty {
            guard modifierWasCleanTap, (now - modifierDownTimestamp) < 0.35 else {
                modifierWasCleanTap = false
                return
            }
            modifierWasCleanTap = false
            if (now - lastModifierReleaseTime) < 0.45 {
                lastModifierReleaseTime = 0
                fireTrigger()
            } else {
                lastModifierReleaseTime = now
            }
        } else {
            modifierWasCleanTap = false
        }
    }

    private func installCarbonHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.fireTrigger()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )
    }

    private func registerActiveHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if preset.isModifierDoubleTap {
            carbonRegistrationError = noErr
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x43545331), id: 1) // 'CTS1'
        carbonRegistrationError = RegisterEventHotKey(
            preset.keyCode,
            preset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func applyCustomHotkey(keyCode: UInt32, carbonModifiers: UInt32) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        let hotKeyID = EventHotKeyID(signature: OSType(0x43545331), id: 1)
        carbonRegistrationError = RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        return mods
    }

    static func formatShortcut(keyCode: UInt32, carbonModifiers: UInt32) -> String {
        var parts: [String] = []
        if (carbonModifiers & UInt32(controlKey)) != 0 { parts.append("⌃") }
        if (carbonModifiers & UInt32(optionKey)) != 0 { parts.append("⌥") }
        if (carbonModifiers & UInt32(shiftKey)) != 0 { parts.append("⇧") }
        if (carbonModifiers & UInt32(cmdKey)) != 0 { parts.append("⌘") }

        let keyName: String
        switch Int(keyCode) {
        case kVK_Space: keyName = "Space"
        case kVK_Return: keyName = "↩"
        case kVK_Tab: keyName = "⇥"
        case kVK_RightArrow: keyName = "→"
        case kVK_LeftArrow: keyName = "←"
        case kVK_UpArrow: keyName = "↑"
        case kVK_DownArrow: keyName = "↓"
        case kVK_ANSI_A: keyName = "A"
        case kVK_ANSI_B: keyName = "B"
        case kVK_ANSI_C: keyName = "C"
        case kVK_ANSI_D: keyName = "D"
        case kVK_ANSI_E: keyName = "E"
        case kVK_ANSI_F: keyName = "F"
        case kVK_ANSI_G: keyName = "G"
        case kVK_ANSI_H: keyName = "H"
        case kVK_ANSI_I: keyName = "I"
        case kVK_ANSI_J: keyName = "J"
        case kVK_ANSI_K: keyName = "K"
        case kVK_ANSI_L: keyName = "L"
        case kVK_ANSI_M: keyName = "M"
        case kVK_ANSI_N: keyName = "N"
        case kVK_ANSI_O: keyName = "O"
        case kVK_ANSI_P: keyName = "P"
        case kVK_ANSI_Q: keyName = "Q"
        case kVK_ANSI_R: keyName = "R"
        case kVK_ANSI_S: keyName = "S"
        case kVK_ANSI_T: keyName = "T"
        case kVK_ANSI_U: keyName = "U"
        case kVK_ANSI_V: keyName = "V"
        case kVK_ANSI_W: keyName = "W"
        case kVK_ANSI_X: keyName = "X"
        case kVK_ANSI_Y: keyName = "Y"
        case kVK_ANSI_Z: keyName = "Z"
        default: keyName = "Key \(keyCode)"
        }
        parts.append(keyName)
        return parts.joined(separator: " + ")
    }
}
