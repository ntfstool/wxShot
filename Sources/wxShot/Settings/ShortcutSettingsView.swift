import AppKit
import Carbon

/// One editable shortcut row in Settings. Backed either by a HotkeyManager
/// slot (global / overlay-level) or by an editor action binding.
private struct ShortcutRowSpec {
    enum Storage {
        case global(HotkeyManager.HotkeySlot)
        case editor(EditorShortcutAction)
    }

    let title: String
    let storage: Storage
    /// Editor bindings and the local (keyDown-matched) hotkeys may be a bare key.
    /// Carbon-registered hotkeys need a modifier or a function key.
    let allowsBareKey: Bool
}

/// The list shown in Settings → 快捷键: every shortcut wxShot actually acts on.
final class ShortcutSettingsView: NSStackView {

    private var rowViews: [ShortcutRowView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .vertical
        alignment = .leading
        spacing = 4
        rebuild()
        for name in [Notification.Name.hotkeyDidChange,
                     Notification.Name.editorShortcutsDidChange,
                     Notification.Name.languageDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                if name == .languageDidChange { self.rebuild() } else { self.refresh() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var specs: [ShortcutRowSpec] {
        var result: [ShortcutRowSpec] = [
            ShortcutRowSpec(title: L10n.fullScreenScreenshotShortcutHeader,
                            storage: .global(.fullScreenScreenshot),
                            allowsBareKey: false),
            ShortcutRowSpec(title: L10n.quickPinShortcutHeader,
                            storage: .global(.quickPin),
                            allowsBareKey: false),
            ShortcutRowSpec(title: L10n.clipboardShortcutHeader,
                            storage: .global(.clipboard),
                            allowsBareKey: true),
            ShortcutRowSpec(title: L10n.fileSaveShortcutHeader,
                            storage: .global(.fileSave),
                            allowsBareKey: true),
        ]
        for action in EditorShortcutAction.allCases {
            if case .toolbar(let item) = action, item == .save || item == .confirm { continue }
            guard action.defaultBinding != nil else { continue }
            result.append(ShortcutRowSpec(title: action.localizedTitle,
                                          storage: .editor(action),
                                          allowsBareKey: true))
        }
        return result
    }

    private func rebuild() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []
        for spec in specs {
            let row = ShortcutRowView(spec: spec) { [weak self] in self?.refresh() }
            rowViews.append(row)
            addArrangedSubview(row)
        }
        refresh()
    }

    private func refresh() {
        rowViews.forEach { $0.refreshDisplay() }
    }
}

/// A single name + current value + record/restore row.
private final class ShortcutRowView: NSStackView {

    private let spec: ShortcutRowSpec
    private let onChange: () -> Void

    private let nameLabel = NSTextField(labelWithString: "")
    private let valueBox = NSView()
    private let valueLabel = NSTextField(labelWithString: "")
    private let recordButton = NSButton()
    private let restoreButton = NSButton()
    private var monitor: Any?
    private var isRecording = false

    init(spec: ShortcutRowSpec, onChange: @escaping () -> Void) {
        self.spec = spec
        self.onChange = onChange
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 8
        alignment = .centerY

        nameLabel.stringValue = spec.title
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true

        valueBox.wantsLayer = true
        valueBox.layer?.cornerRadius = 5
        valueBox.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        valueBox.translatesAutoresizingMaskIntoConstraints = false
        valueBox.widthAnchor.constraint(equalToConstant: 102).isActive = true
        valueBox.heightAnchor.constraint(equalToConstant: 24).isActive = true

        valueLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueBox.addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.centerYAnchor.constraint(equalTo: valueBox.centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: valueBox.leadingAnchor, constant: 4),
            valueLabel.trailingAnchor.constraint(equalTo: valueBox.trailingAnchor, constant: -4),
        ])

        recordButton.bezelStyle = .rounded
        recordButton.controlSize = .small
        recordButton.title = L10n.toolbarSettingsShortcutRecord
        recordButton.target = self
        recordButton.action = #selector(recordClicked)

        restoreButton.bezelStyle = .rounded
        restoreButton.controlSize = .small
        restoreButton.title = L10n.toolbarSettingsShortcutRestore
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)

        [nameLabel, valueBox, recordButton, restoreButton].forEach(addArrangedSubview)
        refreshDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - State

    private var currentBinding: (keyCode: UInt32, modifiers: UInt32)? {
        switch spec.storage {
        case .global(let slot):
            return ShortcutStore.current(for: slot)
        case .editor(let action):
            return EditorShortcutRegistry.binding(for: action).map { ($0.keyCode, $0.modifiers) }
        }
    }

    private var hasCustomBinding: Bool {
        switch spec.storage {
        case .global(let slot):
            return ShortcutStore.hasCustom(slot)
        case .editor(let action):
            return EditorShortcutRegistry.hasOverride(for: action)
        }
    }

    func refreshDisplay() {
        // Recording owns the UI until it ends. Refreshing mid-recording used to
        // call finish -> .hotkeyDidChange -> refresh -> finish, recursing until
        // the stack overflowed (crash report recursion depth 2443).
        guard !isRecording else { return }
        recordButton.title = L10n.toolbarSettingsShortcutRecord

        let text: String
        if let binding = currentBinding, !(binding.keyCode == 0 && binding.modifiers == 0 && !hasCustomBinding) {
            text = HotkeyManager.modifierString(binding.modifiers) + HotkeyManager.keyString(binding.keyCode)
        } else {
            text = L10n.toolbarSettingsShortcutNone
        }
        valueLabel.stringValue = text
        restoreButton.isHidden = !hasCustomBinding
    }

    // MARK: - Recording

    @objc private func recordClicked() {
        if isRecording {
            finishRecording()
            refreshDisplay()
            return
        }
        isRecording = true
        recordButton.title = L10n.shortcutCancel
        valueLabel.stringValue = L10n.shortcutWaiting

        // Install the monitor first: beginRecording() posts a notification, and
        // re-registering must not race with our own state.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleRecordedKey(event) ?? event
        }
        // Suspend registered Carbon hotkeys so their key press reaches us.
        HotkeyManager.shared.beginRecording()
    }

    /// Ends recording exactly once. State flips BEFORE endRecording() so the
    /// resulting .hotkeyDidChange callbacks cannot re-enter and recurse.
    private func finishRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyManager.shared.endRecording()
    }

    private func handleRecordedKey(_ event: NSEvent) -> NSEvent? {
        let modifiers = HotkeyManager.carbonModifiers(from: event.modifierFlags)

        if event.keyCode == UInt16(kVK_Escape), modifiers == 0 {
            finishRecording()
            refreshDisplay()
            return nil
        }

        let keyCode = UInt32(event.keyCode)
        if modifiers == 0 && !spec.allowsBareKey && !HotkeyManager.isFunctionKey(keyCode) {
            finishRecording()
            refreshDisplay()
            alert(L10n.shortcutNeedsModifierTitle, L10n.shortcutNeedsModifier)
            return nil
        }

        if let message = conflictMessage(keyCode: keyCode, modifiers: modifiers) {
            finishRecording()
            refreshDisplay()
            alert(L10n.shortcutConflictTitle, message)
            return nil
        }

        apply(keyCode: keyCode, modifiers: modifiers)
        finishRecording()
        refreshDisplay()
        onChange()
        return nil
    }

    private func conflictMessage(keyCode: UInt32, modifiers: UInt32) -> String? {
        switch spec.storage {
        case .global(let slot):
            return HotkeyManager.shared.hotkeyConflictMessage(
                forKeyCode: keyCode,
                modifiers: modifiers,
                assigningTo: slot
            )
        case .editor(let action):
            let binding = EditorShortcutBinding(keyCode: keyCode, modifiers: modifiers)
            if binding.keyCode == UInt32(kVK_Escape) { return L10n.editorShortcutReserved }
            if let message = EditorShortcutRegistry.validationMessage(for: binding, assigningTo: action) {
                return message
            }
            return nil
        }
    }

    private func apply(keyCode: UInt32, modifiers: UInt32) {
        switch spec.storage {
        case .global(let slot):
            ShortcutStore.store(keyCode: keyCode, modifiers: modifiers, for: slot)
        case .editor(let action):
            EditorShortcutRegistry.setBinding(
                EditorShortcutBinding(keyCode: keyCode, modifiers: modifiers),
                for: action
            )
        }
    }

    @objc private func restoreClicked() {
        finishRecording()
        switch spec.storage {
        case .global(let slot):
            ShortcutStore.clear(slot)
        case .editor(let action):
            EditorShortcutRegistry.restoreDefault(for: action)
        }
        refreshDisplay()
        onChange()
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

/// Reads and writes the HotkeyManager slots through UserDefaults, then asks
/// AppDelegate to re-register whatever is now bound.
private enum ShortcutStore {

    static func current(for slot: HotkeyManager.HotkeySlot) -> (keyCode: UInt32, modifiers: UInt32)? {
        switch slot {
        case .screenshot: return HotkeyManager.shared.currentHotkey()
        case .quickPin: return HotkeyManager.shared.currentQuickPinHotkey()
        case .fullScreenScreenshot: return HotkeyManager.shared.currentFullScreenScreenshotHotkey()
        case .clipboard: return HotkeyManager.shared.currentClipboardHotkey()
        case .fileSave: return HotkeyManager.shared.currentFileSaveHotkey()
        }
    }

    static func hasCustom(_ slot: HotkeyManager.HotkeySlot) -> Bool {
        switch slot {
        case .screenshot: return Defaults.hasCustomScreenshotHotkey
        case .quickPin: return Defaults.hasCustomQuickPinHotkey
        case .fullScreenScreenshot: return Defaults.hasCustomFullScreenScreenshotHotkey
        case .clipboard: return Defaults.hasCustomClipboardHotkey
        case .fileSave: return Defaults.hasCustomFileSaveHotkey
        }
    }

    static func store(keyCode: UInt32, modifiers: UInt32, for slot: HotkeyManager.HotkeySlot) {
        switch slot {
        case .screenshot:
            Defaults.screenshotHotkeyKeyCode = Int(keyCode)
            Defaults.screenshotHotkeyModifiers = Int(modifiers)
        case .quickPin:
            Defaults.quickPinHotkeyKeyCode = Int(keyCode)
            Defaults.quickPinHotkeyModifiers = Int(modifiers)
        case .fullScreenScreenshot:
            Defaults.fullScreenScreenshotHotkeyKeyCode = Int(keyCode)
            Defaults.fullScreenScreenshotHotkeyModifiers = Int(modifiers)
        case .clipboard:
            Defaults.clipboardHotkeyKeyCode = Int(keyCode)
            Defaults.clipboardHotkeyModifiers = Int(modifiers)
        case .fileSave:
            Defaults.fileSaveHotkeyKeyCode = Int(keyCode)
            Defaults.fileSaveHotkeyModifiers = Int(modifiers)
        }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    static func clear(_ slot: HotkeyManager.HotkeySlot) {
        switch slot {
        case .screenshot: Defaults.clearScreenshotHotkey()
        case .quickPin: Defaults.clearQuickPinHotkey()
        case .fullScreenScreenshot: Defaults.clearFullScreenScreenshotHotkey()
        case .clipboard: Defaults.clearClipboardHotkey()
        case .fileSave: Defaults.clearFileSaveHotkey()
        }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }
}
