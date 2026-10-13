import AppKit
import PermissionFlow

/// First-run welcome and permission guide. It is also what opens when the shortcut is pressed before screen recording
/// has been allowed.
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private let permissionStatus = NSTextField(labelWithString: "")
    private let grantButton = NSButton()
    private let startButton = NSButton()
    private var pollTimer: Timer?
    private lazy var permissionFlow = PermissionFlow.makeController(
        configuration: PermissionFlowConfiguration(
            requiredAppURLs: [Bundle.main.bundleURL],
            localeIdentifier: Defaults.language.lprojName
        )
    )

    var isVisible: Bool { window?.isVisible == true }

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "wxShot"
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        refreshPermission()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }
    }

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        permissionFlow.closePanel()
    }

    private func buildContent() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true

        let title = NSTextField(labelWithString: L10n.wxWelcomeTitle)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        let body = wrapping(L10n.wxWelcomeBody, size: 13, color: .labelColor)

        let step1 = NSTextField(labelWithString: L10n.wxStepPermission)
        step1.font = .systemFont(ofSize: 14, weight: .semibold)
        let step1Note = wrapping(L10n.wxStepPermissionNote, size: 11, color: .secondaryLabelColor)
        permissionStatus.font = .systemFont(ofSize: 13)
        grantButton.title = L10n.wxOpenSystemSettings
        grantButton.bezelStyle = .rounded
        grantButton.target = self
        grantButton.action = #selector(grantClicked)
        let permissionRow = NSStackView(views: [permissionStatus, grantButton])
        permissionRow.spacing = 12

        let shortcut = HotkeyManager.currentDisplayString() ?? "⌥A"
        let step2 = NSTextField(labelWithString: L10n.wxStepShortcut(shortcut))
        step2.font = .systemFont(ofSize: 14, weight: .semibold)
        let step2Note = wrapping(L10n.wxStepShortcutNote, size: 11, color: .secondaryLabelColor)

        startButton.title = L10n.wxStartButton
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.target = self
        startButton.action = #selector(startClicked)

        let stack = NSStackView(views: [icon, title, body, step1, step1Note, permissionRow, step2, step2Note, startButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(16, after: body)
        stack.setCustomSpacing(18, after: permissionRow)
        stack.setCustomSpacing(20, after: step2Note)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        window?.contentView = stack
        let fitting = stack.fittingSize
        window?.setContentSize(NSSize(width: 480, height: fitting.height))
    }

    private func wrapping(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        label.preferredMaxLayoutWidth = 424
        return label
    }

    private func refreshPermission() {
        let granted = AppPermissions.screenRecordingGranted
        permissionStatus.stringValue = (granted ? "✓ " : "⚠︎ ") + (granted ? L10n.wxPermissionStatusGranted : L10n.wxPermissionStatusMissing)
        permissionStatus.textColor = granted ? .systemGreen : .systemOrange
        grantButton.isHidden = granted
        startButton.isEnabled = granted
    }

    @objc private func grantClicked() {
        // Registers wxShot in the Screen Recording list, then walks the user through switching it on.
        _ = CGRequestScreenCaptureAccess()
        permissionFlow.setLocaleIdentifier(Defaults.language.lprojName)
        permissionFlow.authorize(
            pane: .screenRecording,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: window.map { $0.convertToScreen(grantButton.convert(grantButton.bounds, to: nil)) }
        )
    }

    @objc private func startClicked() {
        Defaults.onboardingCompleted = true
        window?.close()
        if AppPermissions.screenRecordingGranted {
            ScreenSnapshotProvider.shared.prewarm()
            OverlayWindowController.prewarmPresentationSurfaces()
        }
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }
}
