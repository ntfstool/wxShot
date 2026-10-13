import AppKit
import PermissionFlow

/// The whole settings surface: one short page, no tabs.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    var onMenuBarToggle: ((Bool) -> Void)?

    private let recorder = ShortcutRecorderView()
    private let weChatStatusLabel = NSTextField(labelWithString: "")
    private let ownerLabel = NSTextField(labelWithString: "")
    private var policyButtons: [WeChatPolicy: NSButton] = [:]
    private let permissionLabel = NSTextField(labelWithString: "")
    private let permissionButton = NSButton()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let menuBarCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let telemetryCheckbox = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let languagePopup = NSPopUpButton()
    private var refreshTimer: Timer?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        refreshAll()

        NotificationCenter.default.addObserver(forName: .weChatStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshWeChatSection()
        }
        NotificationCenter.default.addObserver(forName: .hotkeyDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refreshWeChatSection()
        }
        NotificationCenter.default.addObserver(forName: .languageDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.buildContent()
            self?.refreshAll()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func showAsSettings() {
        refreshAll()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        // The permission can change while the window is open; look again every couple of seconds.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermission()
            WeChatMonitor.shared.refresh()
        }
    }

    func windowWillClose(_ notification: Notification) {
        recorder.cancelRecording()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Building

    private func buildContent() {
        window?.title = L10n.wxSettingsWindowTitle

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)

        stack.addArrangedSubview(header())

        stack.addArrangedSubview(sectionTitle(L10n.wxSectionShortcut))
        stack.addArrangedSubview(recorder)
        stack.addArrangedSubview(note(L10n.wxShortcutDefaultNote))

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionTitle(L10n.wxSectionWeChat))
        weChatStatusLabel.font = .systemFont(ofSize: 12)
        weChatStatusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(weChatStatusLabel)
        policyButtons = [:]
        for (policy, title) in [(WeChatPolicy.auto, L10n.wxPolicyAuto),
                                (.alwaysUs, L10n.wxPolicyAlways),
                                (.yieldWhenRunning, L10n.wxPolicyYield)] {
            let button = NSButton(radioButtonWithTitle: title, target: self, action: #selector(policyChanged(_:)))
            policyButtons[policy] = button
            stack.addArrangedSubview(button)
        }
        ownerLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(ownerLabel)
        stack.addArrangedSubview(note(L10n.wxPolicyHint))

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionTitle(L10n.permissionsHeader))
        permissionLabel.font = .systemFont(ofSize: 13)
        permissionButton.title = L10n.wxOpenSystemSettings
        permissionButton.bezelStyle = .rounded
        permissionButton.target = self
        permissionButton.action = #selector(openPermissionSettings)
        let permissionRow = NSStackView(views: [permissionLabel, permissionButton])
        permissionRow.spacing = 12
        stack.addArrangedSubview(permissionRow)

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionTitle(L10n.wxSectionGeneral))
        launchAtLoginCheckbox.title = L10n.launchAtLogin
        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginChanged)
        menuBarCheckbox.title = L10n.showMenuBarIcon
        menuBarCheckbox.target = self
        menuBarCheckbox.action = #selector(menuBarChanged)
        telemetryCheckbox.title = L10n.wxTelemetryToggle
        telemetryCheckbox.target = self
        telemetryCheckbox.action = #selector(telemetryChanged)
        [launchAtLoginCheckbox, menuBarCheckbox, telemetryCheckbox].forEach(stack.addArrangedSubview)
        stack.addArrangedSubview(note(L10n.wxTelemetryHint))

        languagePopup.removeAllItems()
        for language in AppLanguage.allCases { languagePopup.addItem(withTitle: language.displayName) }
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged)
        stack.addArrangedSubview(languagePopup)

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(sectionTitle(L10n.wxSectionFeedback))
        stack.addArrangedSubview(note(L10n.wxFeedbackHint))
        let feedbackButton = NSButton(title: L10n.wxFeedbackButton, target: self, action: #selector(sendFeedback))
        feedbackButton.bezelStyle = .rounded
        stack.addArrangedSubview(feedbackButton)

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(footer())

        window?.contentView = stack
        // Let the window fit its content height.
        let fitting = stack.fittingSize
        window?.setContentSize(NSSize(width: 520, height: fitting.height))
    }

    private func header() -> NSView {
        let name = NSTextField(labelWithString: "wxShot")
        name.font = .systemFont(ofSize: 22, weight: .semibold)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let versionLabel = NSTextField(labelWithString: "v\(version)")
        versionLabel.textColor = .secondaryLabelColor
        let row = NSStackView(views: [name, versionLabel])
        row.alignment = .firstBaseline
        row.spacing = 8
        return row
    }

    private func footer() -> NSView {
        let links = NSStackView()
        links.spacing = 14
        links.addArrangedSubview(linkButton(L10n.wxAboutWebsite, "https://ntfstool.com/wxshot/"))
        links.addArrangedSubview(linkButton(L10n.wxAboutSource, "https://github.com/ntfstool/wxShot"))
        links.addArrangedSubview(linkButton("⭐ " + L10n.wxStarOnGitHub, "https://github.com/ntfstool/wxShot"))
        #if !MAS
        let update = NSButton(title: L10n.checkForUpdatesMenu, target: self, action: #selector(checkForUpdates))
        update.bezelStyle = .rounded
        links.addArrangedSubview(update)
        #endif
        return links
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 470
        return label
    }

    private func divider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 472).isActive = true
        return box
    }

    private func linkButton(_ title: String, _ url: String) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        button.isBordered = false
        button.contentTintColor = .linkColor
        button.identifier = NSUserInterfaceItemIdentifier(url)
        return button
    }

    // MARK: - Refresh

    private func refreshAll() {
        refreshWeChatSection()
        refreshPermission()
        launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        menuBarCheckbox.state = Defaults.showMenuBar ? .on : .off
        telemetryCheckbox.state = Defaults.telemetryEnabled ? .on : .off
        if let index = AppLanguage.allCases.firstIndex(of: Defaults.language) { languagePopup.selectItem(at: index) }
    }

    private func refreshWeChatSection() {
        let state = WeChatMonitor.shared.state
        switch state {
        case .notRunning: weChatStatusLabel.stringValue = L10n.wxWeChatStatusNotRunning
        case .loginScreen: weChatStatusLabel.stringValue = L10n.wxWeChatStatusLoginScreen
        case .loggedIn: weChatStatusLabel.stringValue = L10n.wxWeChatStatusLoggedIn
        }
        for (policy, button) in policyButtons { button.state = policy == Defaults.weChatPolicy ? .on : .off }
        let owner = WeChatMonitor.shared.shouldOwnShortcut() ? "wxShot" : L10n.wxOwnerWeChat
        ownerLabel.stringValue = L10n.wxShortcutOwner(owner)
    }

    private func refreshPermission() {
        let granted = AppPermissions.screenRecordingGranted
        permissionLabel.stringValue = (granted ? "✓ " : "⚠︎ ") + (granted ? L10n.wxPermissionStatusGranted : L10n.wxPermissionStatusMissing)
        permissionLabel.textColor = granted ? .labelColor : .systemOrange
        permissionButton.isHidden = granted
    }

    // MARK: - Actions

    @objc private func policyChanged(_ sender: NSButton) {
        guard let policy = policyButtons.first(where: { $0.value === sender })?.key else { return }
        Defaults.weChatPolicy = policy
        refreshWeChatSection()
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }

    @objc private func openPermissionSettings() {
        OnboardingWindowController.shared.show()
    }

    @objc private func launchAtLoginChanged() {
        let desired = launchAtLoginCheckbox.state == .on
        if !LaunchAtLogin.setEnabled(desired) {
            launchAtLoginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        }
    }

    @objc private func menuBarChanged() {
        Defaults.showMenuBar = menuBarCheckbox.state == .on
        onMenuBarToggle?(Defaults.showMenuBar)
    }

    @objc private func telemetryChanged() {
        Defaults.telemetryEnabled = telemetryCheckbox.state == .on
    }

    @objc private func languageChanged() {
        let index = languagePopup.indexOfSelectedItem
        guard AppLanguage.allCases.indices.contains(index) else { return }
        Defaults.language = AppLanguage.allCases[index]
    }

    /// Collects free-form feedback and hands it to the user's mail app (no server, nothing is uploaded by wxShot).
    @objc private func sendFeedback() {
        let alert = NSAlert()
        alert.messageText = L10n.wxFeedbackTitle
        alert.informativeText = L10n.wxFeedbackInfo
        alert.addButton(withTitle: L10n.wxFeedbackSend)
        alert.addButton(withTitle: L10n.tipCancel)
        alert.addButton(withTitle: L10n.wxFeedbackGitHub)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 130))
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 6)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 130))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = textView

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let body = "\(text)\n\n--\nwxShot \(version)\nmacOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
            var components = URLComponents(string: "mailto:service@ntfstool.com")!
            components.queryItems = [URLQueryItem(name: "subject", value: "wxShot feedback"), URLQueryItem(name: "body", value: body)]
            // Keep a copy: a Mac without a configured mail app silently ignores mailto links.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            if let url = components.url { NSWorkspace.shared.open(url) }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(URL(string: "https://github.com/ntfstool/wxShot/issues")!)
        default:
            break
        }
    }

    @objc private func openLink(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    #if !MAS
    @objc private func checkForUpdates() {
        UpdateChecker.shared.check(manual: true) { state in
            StatusBarController.presentManualCheckResult(state)
        }
    }
    #endif
}
