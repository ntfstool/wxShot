import Cocoa
import Carbon

final class HotkeyManager {

    static let shared = HotkeyManager()

    private(set) var isRecording: Bool = false

    private var hotKeyRef: EventHotKeyRef?
    private var quickPinHotKeyRef: EventHotKeyRef?
    private var fullScreenScreenshotHotKeyRef: EventHotKeyRef?
    private var callback: ((CaptureTriggerContext) -> Void)?
    private var quickPinCallback: (() -> Void)?
    private var fullScreenScreenshotCallback: (() -> Void)?
    private var eventHandlerRef: EventHandlerRef?

    private static let regularHotKeySignature: OSType = OSType(0x4341_5043) // 'CAPC'
    private static let regularHotKeyID: UInt32 = 1
    private static let fullScreenScreenshotHotKeyID: UInt32 = 11
    private static let quickPinHotKeyID: UInt32 = 18

    private init() {}

    deinit {
        unregister()
        unregisterQuickPin()
        unregisterFullScreenScreenshot()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    // MARK: - Registration

    /// Register the saved screenshot hotkey, if any. Caller's `callback` is invoked when fired.
    /// If no hotkey is saved (key code == 0 with no function-key fallback), this no-ops.
    func register(callback: @escaping (CaptureTriggerContext) -> Void) {
        self.callback = callback
        unregister()

        guard let (keyCode, modifiers) = currentHotkey() else { return }

        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.regularHotKeySignature, id: Self.regularHotKeyID)
        let status = RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref = ref {
            hotKeyRef = ref
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    /// Register the shortcut that selects a screen region and pins it directly.
    func registerQuickPin(callback: @escaping () -> Void) {
        quickPinCallback = callback
        unregisterQuickPin()

        guard let (keyCode, modifiers) = currentQuickPinHotkey() else { return }

        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.regularHotKeySignature, id: Self.quickPinHotKeyID)
        let status = RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            quickPinHotKeyRef = ref
        }
    }

    func unregisterQuickPin() {
        if let ref = quickPinHotKeyRef {
            UnregisterEventHotKey(ref)
            quickPinHotKeyRef = nil
        }
    }

    /// Register the saved full-screen screenshot hotkey, if any.
    func registerFullScreenScreenshot(callback: @escaping () -> Void) {
        self.fullScreenScreenshotCallback = callback
        unregisterFullScreenScreenshot()

        guard let (keyCode, modifiers) = currentFullScreenScreenshotHotkey() else { return }

        installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.regularHotKeySignature, id: Self.fullScreenScreenshotHotKeyID)
        let status = RegisterEventHotKey(
            keyCode, modifiers, id,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref = ref {
            fullScreenScreenshotHotKeyRef = ref
        }
    }

    func unregisterFullScreenScreenshot() {
        if let ref = fullScreenScreenshotHotKeyRef {
            UnregisterEventHotKey(ref)
            fullScreenScreenshotHotKeyRef = nil
        }
    }

    // MARK: - Recording lifecycle

    /// Called by Settings UI when the user starts capturing a new key combo.
    /// Suspends the active hotkey so the user's recorded keypress is not swallowed.
    func beginRecording() {
        isRecording = true
        unregister()
        unregisterQuickPin()
        unregisterFullScreenScreenshot()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    /// Called when recording finishes (saved or cancelled).
    func endRecording() {
        isRecording = false
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    // MARK: - Stored hotkey accessors

    /// The default shortcut, same muscle memory as WeChat's screenshot: ⌥A.
    static let defaultHotkey: (keyCode: UInt32, modifiers: UInt32) = (UInt32(kVK_ANSI_A), UInt32(optionKey))

    /// Returns (keyCode, carbonModifiers) for the screenshot hotkey: the saved one, or the default.
    func currentHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard Defaults.hasCustomScreenshotHotkey else { return Self.defaultHotkey }
        let kc = UInt32(Defaults.screenshotHotkeyKeyCode)
        let mods = UInt32(Defaults.screenshotHotkeyModifiers)
        // Require at least one modifier unless it is a standalone function key.
        guard mods != 0 || Self.isFunctionKey(kc) else { return Self.defaultHotkey }
        return (kc, mods)
    }

    /// Display string like "⌘⇧X" for the saved hotkey, or nil if not set.
    static func currentDisplayString() -> String? {
        guard let (kc, mods) = HotkeyManager.shared.currentHotkey() else { return nil }
        return modifierString(mods) + keyString(kc)
    }

    func currentQuickPinHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard Defaults.hasCustomQuickPinHotkey else { return nil }
        let kc = UInt32(Defaults.quickPinHotkeyKeyCode)
        let mods = UInt32(Defaults.quickPinHotkeyModifiers)
        guard mods != 0 || Self.isFunctionKey(kc) else { return nil }
        return (kc, mods)
    }

    static func currentQuickPinDisplayString() -> String? {
        guard let (kc, mods) = HotkeyManager.shared.currentQuickPinHotkey() else { return nil }
        return modifierString(mods) + keyString(kc)
    }

    /// Returns (keyCode, carbonModifiers) for the saved full-screen screenshot
    /// hotkey.
    func currentFullScreenScreenshotHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard Defaults.hasCustomFullScreenScreenshotHotkey else { return nil }
        let kc = UInt32(Defaults.fullScreenScreenshotHotkeyKeyCode)
        let mods = UInt32(Defaults.fullScreenScreenshotHotkeyModifiers)
        guard mods != 0 || Self.isFunctionKey(kc) else { return nil }
        return (kc, mods)
    }

    /// Display string for the full-screen screenshot hotkey, or nil if not set.
    static func currentFullScreenScreenshotDisplayString() -> String? {
        guard let (kc, mods) = HotkeyManager.shared.currentFullScreenScreenshotHotkey() else { return nil }
        return modifierString(mods) + keyString(kc)
    }

    /// Returns (keyCode, carbonModifiers) for the saved copy-to-clipboard
    /// hotkey, or nil when the user hasn't bound one (the default is
    /// "double-tap ⌘", handled separately by `KeyMonitor`).
    /// Bare (no-modifier) values are allowed here — the clipboard hotkey is
    /// matched locally against keyDown events inside the editor, not registered
    /// as a global Carbon hotkey, so it won't intercept ordinary typing.
    func currentClipboardHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard Defaults.hasCustomClipboardHotkey else { return nil }
        let kc = UInt32(Defaults.clipboardHotkeyKeyCode)
        let mods = UInt32(Defaults.clipboardHotkeyModifiers)
        return (kc, mods)
    }

    /// Display string for the saved clipboard hotkey, or nil if not set.
    static func currentClipboardDisplayString() -> String? {
        guard let (kc, mods) = HotkeyManager.shared.currentClipboardHotkey() else { return nil }
        return modifierString(mods) + keyString(kc)
    }

    /// Returns true when the given keyDown event matches the user's
    /// copy-to-clipboard hotkey. Returns false when no custom hotkey is set —
    /// the default (double-tap ⌘) is detected via `KeyMonitor`, not keyDown.
    static func eventMatchesClipboardHotkey(_ event: NSEvent) -> Bool {
        guard let (kc, m) = HotkeyManager.shared.currentClipboardHotkey() else { return false }
        return matches(event: event, keyCode: kc, modifiers: m)
    }

    /// Returns (keyCode, carbonModifiers) for the save-to-file hotkey. Falls
    /// back to ⌘S when the user hasn't bound a custom one.
    func currentFileSaveHotkey() -> (keyCode: UInt32, modifiers: UInt32) {
        if Defaults.hasCustomFileSaveHotkey {
            return (UInt32(Defaults.fileSaveHotkeyKeyCode),
                    UInt32(Defaults.fileSaveHotkeyModifiers))
        }
        return (UInt32(kVK_ANSI_S), UInt32(cmdKey))
    }

    /// Display string for the save-to-file hotkey (default or custom).
    static func currentFileSaveDisplayString() -> String {
        let (kc, mods) = HotkeyManager.shared.currentFileSaveHotkey()
        return modifierString(mods) + keyString(kc)
    }

    /// Returns true when the given keyDown event matches the save-to-file
    /// hotkey (custom or the ⌘S default).
    static func eventMatchesFileSaveHotkey(_ event: NSEvent) -> Bool {
        let (kc, m) = HotkeyManager.shared.currentFileSaveHotkey()
        return matches(event: event, keyCode: kc, modifiers: m)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let activeMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let mods = flags.intersection(activeMask)
        var carbonMods: UInt32 = 0
        if mods.contains(.command) { carbonMods |= UInt32(cmdKey) }
        if mods.contains(.shift)   { carbonMods |= UInt32(shiftKey) }
        if mods.contains(.option)  { carbonMods |= UInt32(optionKey) }
        if mods.contains(.control) { carbonMods |= UInt32(controlKey) }
        return carbonMods
    }

    private static func matches(event: NSEvent, keyCode: UInt32, modifiers: UInt32) -> Bool {
        UInt32(event.keyCode) == keyCode
            && carbonModifiers(from: event.modifierFlags) == modifiers
    }

    // MARK: - Conflict detection

    /// A user-configurable hotkey slot in Settings.
    enum HotkeySlot {
        case screenshot
        case quickPin
        case fullScreenScreenshot
        case clipboard
        case fileSave
    }

    /// Returns a localized message describing the existing binding a candidate
    /// `(keyCode, modifiers)` would collide with, or nil when it is free to assign.
    func hotkeyConflictMessage(forKeyCode keyCode: UInt32,
                               modifiers: UInt32,
                               assigningTo slot: HotkeySlot? = nil) -> String? {
        if slot != .screenshot, let (kc, m) = currentHotkey(), kc == keyCode, m == modifiers {
            return L10n.shortcutConflictScreenshot
        }
        if slot != .quickPin, let (kc, m) = currentQuickPinHotkey(), kc == keyCode, m == modifiers {
            return L10n.shortcutConflictQuickPin
        }
        if slot != .fullScreenScreenshot, let (kc, m) = currentFullScreenScreenshotHotkey(), kc == keyCode, m == modifiers {
            return L10n.shortcutConflictFullScreenScreenshot
        }
        if slot != .clipboard, let (kc, m) = currentClipboardHotkey(), kc == keyCode, m == modifiers {
            return L10n.shortcutConflictClipboard
        }
        if slot != .fileSave {
            let (kc, m) = currentFileSaveHotkey()
            if kc == keyCode, m == modifiers {
                return L10n.shortcutConflictFileSave
            }
        }
        return nil
    }

    // MARK: - Event handler

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }

                if hkID.id == HotkeyManager.regularHotKeyID {
                    guard let callback = mgr.callback else { return noErr }
                    let context = CaptureTriggerContext(
                        source: .keyboardShortcut,
                        eventUptime: GetEventTime(eventRef)
                    )
                    context.mark(.carbonEventReceived)
                    MainRunLoopScheduler.perform {
                        context.mark(.mainRunLoopCallback)
                        callback(context)
                    }
                    return noErr
                }

                let callback: (() -> Void)?
                switch hkID.id {
                case HotkeyManager.quickPinHotKeyID:
                    callback = mgr.quickPinCallback
                case HotkeyManager.fullScreenScreenshotHotKeyID:
                    callback = mgr.fullScreenScreenshotCallback
                default:
                    callback = nil
                }
                if let callback {
                    MainRunLoopScheduler.perform(callback)
                }
                return noErr
            },
            1, &spec, selfPtr, &eventHandlerRef
        )
    }

    // MARK: - Keycode helpers

    static func isFunctionKey(_ keyCode: UInt32) -> Bool {
        let codes: Set<UInt32> = [
            UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4),
            UInt32(kVK_F5), UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8),
            UInt32(kVK_F9), UInt32(kVK_F10), UInt32(kVK_F11), UInt32(kVK_F12),
            UInt32(kVK_F13), UInt32(kVK_F14), UInt32(kVK_F15), UInt32(kVK_F16),
            UInt32(kVK_F17), UInt32(kVK_F18), UInt32(kVK_F19), UInt32(kVK_F20),
        ]
        return codes.contains(keyCode)
    }

    static func modifierString(_ m: UInt32) -> String {
        var s = ""
        if m & UInt32(controlKey) != 0 { s += "\u{2303}" }
        if m & UInt32(optionKey) != 0  { s += "\u{2325}" }
        if m & UInt32(shiftKey) != 0   { s += "\u{21E7}" }
        if m & UInt32(cmdKey) != 0     { s += "\u{2318}" }
        return s
    }

    static func keyString(_ keyCode: UInt32) -> String {
        if let mapped = keyMap[keyCode] { return mapped }
        return "Key \(keyCode)"
    }

    // MARK: - NSMenuItem integration

    /// Apply the saved hotkey to a menu item via the native keyEquivalent system.
    /// When no custom hotkey is set, renders "⌘⌘" (double-tap ⌘) by using ⌘
    /// as both the modifier mask and the key character — AppKit displays them
    /// as two glyphs side-by-side in the shortcut column. The binding can't
    /// fire from a real keystroke since ⌘ can't be pressed as a key while held
    /// as a modifier, so it functions purely as a visual hint.
    static func applyToMenuItem(_ item: NSMenuItem) {
        item.attributedTitle = nil

        guard let (kc, mods) = HotkeyManager.shared.currentHotkey() else {
            item.keyEquivalent = "\u{2318}"
            item.keyEquivalentModifierMask = .command
            return
        }

        apply(keyCode: kc, modifiers: mods, to: item)
    }

    static func applyFullScreenScreenshotToMenuItem(_ item: NSMenuItem) {
        item.attributedTitle = nil
        guard let (kc, mods) = HotkeyManager.shared.currentFullScreenScreenshotHotkey() else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        apply(keyCode: kc, modifiers: mods, to: item)
    }

    private static func apply(keyCode kc: UInt32, modifiers mods: UInt32, to item: NSMenuItem) {
        var flags: NSEvent.ModifierFlags = []
        if mods & UInt32(cmdKey) != 0     { flags.insert(.command) }
        if mods & UInt32(shiftKey) != 0   { flags.insert(.shift) }
        if mods & UInt32(optionKey) != 0  { flags.insert(.option) }
        if mods & UInt32(controlKey) != 0 { flags.insert(.control) }

        let key: String
        if let special = menuKeyCharMap[kc] {
            key = special
        } else {
            let display = keyString(kc)
            guard !display.hasPrefix("Key ") else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
                return
            }
            key = display.lowercased()
        }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = flags
    }

    private static let menuKeyCharMap: [UInt32: String] = [
        UInt32(kVK_F1): "\u{F704}", UInt32(kVK_F2): "\u{F705}", UInt32(kVK_F3): "\u{F706}",
        UInt32(kVK_F4): "\u{F707}", UInt32(kVK_F5): "\u{F708}", UInt32(kVK_F6): "\u{F709}",
        UInt32(kVK_F7): "\u{F70A}", UInt32(kVK_F8): "\u{F70B}", UInt32(kVK_F9): "\u{F70C}",
        UInt32(kVK_F10): "\u{F70D}", UInt32(kVK_F11): "\u{F70E}", UInt32(kVK_F12): "\u{F70F}",
        UInt32(kVK_F13): "\u{F710}", UInt32(kVK_F14): "\u{F711}", UInt32(kVK_F15): "\u{F712}",
        UInt32(kVK_F16): "\u{F713}", UInt32(kVK_F17): "\u{F714}", UInt32(kVK_F18): "\u{F715}",
        UInt32(kVK_F19): "\u{F716}", UInt32(kVK_F20): "\u{F717}",
        UInt32(kVK_Space): " ", UInt32(kVK_Return): "\r", UInt32(kVK_Tab): "\t",
        UInt32(kVK_Delete): "\u{7F}", UInt32(kVK_ForwardDelete): "\u{F728}",
        UInt32(kVK_Escape): "\u{1B}",
        UInt32(kVK_LeftArrow): "\u{F702}", UInt32(kVK_RightArrow): "\u{F703}",
        UInt32(kVK_UpArrow): "\u{F700}", UInt32(kVK_DownArrow): "\u{F701}",
        UInt32(kVK_Home): "\u{F729}", UInt32(kVK_End): "\u{F72B}",
        UInt32(kVK_PageUp): "\u{F72C}", UInt32(kVK_PageDown): "\u{F72D}",
    ]

    private static let keyMap: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_ANSI_Minus): "-", UInt32(kVK_ANSI_Equal): "=",
        UInt32(kVK_ANSI_LeftBracket): "[", UInt32(kVK_ANSI_RightBracket): "]",
        UInt32(kVK_ANSI_Backslash): "\\", UInt32(kVK_ANSI_Semicolon): ";",
        UInt32(kVK_ANSI_Quote): "'", UInt32(kVK_ANSI_Comma): ",",
        UInt32(kVK_ANSI_Period): ".", UInt32(kVK_ANSI_Slash): "/",
        UInt32(kVK_ANSI_Grave): "`",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15",
        UInt32(kVK_F16): "F16", UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18",
        UInt32(kVK_F19): "F19", UInt32(kVK_F20): "F20",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Delete): "Delete", UInt32(kVK_ForwardDelete): "Fwd Del",
        UInt32(kVK_Escape): "Esc",
        UInt32(kVK_LeftArrow): "\u{2190}", UInt32(kVK_RightArrow): "\u{2192}",
        UInt32(kVK_UpArrow): "\u{2191}", UInt32(kVK_DownArrow): "\u{2193}",
        UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "PgUp", UInt32(kVK_PageDown): "PgDn",
    ]
}
