import AppKit
import Carbon

/// Shows the current screenshot shortcut and lets the user record another one.
/// While recording, the global hotkey is suspended so the key press is not swallowed.
final class ShortcutRecorderView: NSStackView {
    private let field = NSTextField(labelWithString: "")
    private let fieldBox = NSView()
    private let setButton = NSButton()
    private let restoreButton = NSButton()
    private var monitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        orientation = .horizontal
        spacing = 10
        alignment = .centerY

        field.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        field.alignment = .center
        field.translatesAutoresizingMaskIntoConstraints = false
        fieldBox.wantsLayer = true
        fieldBox.layer?.cornerRadius = 6
        fieldBox.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        fieldBox.translatesAutoresizingMaskIntoConstraints = false
        fieldBox.addSubview(field)
        NSLayoutConstraint.activate([
            fieldBox.widthAnchor.constraint(equalToConstant: 96),
            fieldBox.heightAnchor.constraint(equalToConstant: 28),
            field.centerYAnchor.constraint(equalTo: fieldBox.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: fieldBox.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: fieldBox.trailingAnchor, constant: -4),
        ])

        setButton.bezelStyle = .rounded
        setButton.target = self
        setButton.action = #selector(setClicked)
        restoreButton.title = L10n.shortcutRestore
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)

        [fieldBox, setButton, restoreButton].forEach(addArrangedSubview)
        refresh()
        NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.restoreButton.title = L10n.shortcutRestore
            self?.refresh()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func cancelRecording() {
        guard monitor != nil else { return }
        stopRecording()
    }

    private func refresh() {
        setButton.title = L10n.shortcutSet
        field.stringValue = HotkeyManager.currentDisplayString() ?? ""
        restoreButton.isHidden = !Defaults.hasCustomScreenshotHotkey
    }

    @objc private func setClicked() {
        if monitor != nil {
            stopRecording()
            return
        }
        HotkeyManager.shared.beginRecording()
        setButton.title = L10n.shortcutCancel
        field.stringValue = L10n.shortcutWaiting
        restoreButton.isHidden = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let pressed = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if event.keyCode == UInt16(kVK_Escape) && pressed.isEmpty {
                self.stopRecording()
                return nil
            }
            let modifiers = HotkeyManager.carbonModifiers(from: event.modifierFlags)
            let keyCode = UInt32(event.keyCode)
            if modifiers == 0 && !HotkeyManager.isFunctionKey(keyCode) {
                self.stopRecording()
                self.alert(L10n.shortcutNeedsModifierTitle, L10n.shortcutNeedsModifier)
                return nil
            }
            if let conflict = HotkeyManager.shared.hotkeyConflictMessage(forKeyCode: keyCode, modifiers: modifiers, assigningTo: .screenshot) {
                self.stopRecording()
                self.alert(L10n.shortcutConflictTitle, conflict)
                return nil
            }
            Defaults.screenshotHotkeyKeyCode = Int(keyCode)
            Defaults.screenshotHotkeyModifiers = Int(modifiers)
            self.stopRecording()
            return nil
        }
    }

    @objc private func restoreClicked() {
        cancelRecording()
        Defaults.clearScreenshotHotkey()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
        refresh()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        HotkeyManager.shared.endRecording()
        refresh()
    }

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
