import AppKit

/// Optional menu bar icon. It is hidden by default; wxShot is meant to live in the background and answer the shortcut.
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let onTakeScreenshot: () -> Void
    private let onTakeFullScreenScreenshot: () -> Void
    private let onOpenSettings: () -> Void

    init(
        onTakeScreenshot: @escaping () -> Void,
        onTakeFullScreenScreenshot: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onTakeScreenshot = onTakeScreenshot
        self.onTakeFullScreenScreenshot = onTakeFullScreenScreenshot
        self.onOpenSettings = onOpenSettings

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = false

        super.init()

        if let button = statusItem.button {
            button.image = Self.statusBarIcon()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
        }
        setupMenu()

        for name in [Notification.Name.languageDidChange, .hotkeyDidChange, .updateStateDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.setupMenu()
            }
        }
    }

    func setMenuBarVisible(_ visible: Bool) {
        statusItem.isVisible = visible
    }

    private func setupMenu() {
        let menu = NSMenu()

        let screenshotItem = NSMenuItem(title: L10n.takeScreenshot, action: #selector(takeScreenshot), keyEquivalent: "")
        screenshotItem.target = self
        screenshotItem.image = Self.menuIcon(systemName: "crop")
        HotkeyManager.applyToMenuItem(screenshotItem)
        menu.addItem(screenshotItem)

        let fullScreenItem = NSMenuItem(title: L10n.takeFullScreenScreenshot, action: #selector(takeFullScreenScreenshot), keyEquivalent: "")
        fullScreenItem.target = self
        fullScreenItem.image = Self.menuIcon(systemName: "display")
        HotkeyManager.applyFullScreenScreenshotToMenuItem(fullScreenItem)
        menu.addItem(fullScreenItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: L10n.settings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = Self.menuIcon(systemName: "gearshape")
        menu.addItem(settingsItem)

        #if !MAS
        menu.addItem(makeUpdateMenuItem())
        #endif

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: L10n.quitApp, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.image = Self.menuIcon(systemName: "power")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    fileprivate static func menuIcon(systemName: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    private static func statusBarIcon() -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "wxShot") ?? NSImage(size: size)
        image.size = size
        image.isTemplate = true
        return image
    }

    @objc private func takeScreenshot() { onTakeScreenshot() }
    @objc private func takeFullScreenScreenshot() { onTakeFullScreenScreenshot() }
    @objc private func openSettings() { onOpenSettings() }

    // MARK: - Updates (direct-download build only; the App Store updates the app itself)

    private func makeUpdateMenuItem() -> NSMenuItem {
        let item: NSMenuItem
        switch UpdateChecker.shared.state {
        case .available(let version):
            item = NSMenuItem(title: L10n.updateAvailableMenu(version), action: #selector(openReleasePage), keyEquivalent: "")
            item.image = Self.menuIcon(systemName: "arrow.down.circle.fill")
        case .checking:
            item = NSMenuItem(title: L10n.checkingForUpdatesMenu, action: nil, keyEquivalent: "")
            item.isEnabled = false
        default:
            item = NSMenuItem(title: L10n.checkForUpdatesMenu, action: #selector(checkForUpdates), keyEquivalent: "")
            item.image = Self.menuIcon(systemName: "arrow.triangle.2.circlepath")
        }
        item.target = self
        return item
    }

    @objc private func openReleasePage() {
        Self.downloadUpdateAndQuit()
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.check(manual: true) { state in
            Self.presentManualCheckResult(state)
        }
    }

    /// Shown after a background check. Recommended updates can be postponed or skipped; a required one (server
    /// `min_version`) only offers the download, and the app quits so an unsupported build is not used any further.
    static func presentBackgroundUpdatePrompt(version: String, required: Bool) {
        // The check fires while the capture overlay is on screen. A modal alert then sits under the overlay and
        // freezes it, so hold the prompt until the capture/editor is gone.
        if isCaptureActive() {
            if pendingUpdatePrompt == nil { SurvivalReporter.shared.count("update_prompt_deferred") }
            pendingUpdatePrompt = (version, required)
            return
        }
        pendingUpdatePrompt = nil
        SurvivalReporter.shared.count("update_prompt_shown")
        let alert = NSAlert()
        alert.messageText = L10n.wxUpdateTitle(version)
        alert.informativeText = required ? L10n.wxUpdateRequiredBody : L10n.wxUpdateBody
        alert.addButton(withTitle: L10n.wxUpdateButton)
        if !required {
            alert.addButton(withTitle: L10n.updateLaterButton)
            alert.addButton(withTitle: L10n.updateSkipButton)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            downloadUpdateAndQuit()
            return
        } else if response == .alertThirdButtonReturn {
            SurvivalReporter.shared.count("update_skip")
            UpdateChecker.shared.skipVersion()
        } else {
            SurvivalReporter.shared.count("update_later")
        }
        if required { NSApp.terminate(nil) }
    }

    /// Set by AppDelegate: true while a capture overlay or the editor is on screen.
    static var isCaptureActive: () -> Bool = { false }
    private static var pendingUpdatePrompt: (version: String, required: Bool)?
    static var hasPendingUpdatePrompt: Bool { pendingUpdatePrompt != nil }

    /// Called by AppDelegate when a capture ends; shows an update prompt that was held back during it.
    static func presentPendingUpdatePromptIfAny() {
        guard pendingUpdatePrompt != nil else { return }
        // Let the overlay finish closing (and the toast appear) first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let pending = pendingUpdatePrompt, !isCaptureActive() else { return }
            presentBackgroundUpdatePrompt(version: pending.version, required: pending.required)
        }
    }

    /// wxShot has no Dock icon and usually no menu bar icon, so a running copy cannot be quit by most users and
    /// Finder refuses to replace it ("in use"). Open the download, then quit so the new copy can be dragged in.
    static func downloadUpdateAndQuit() {
        SurvivalReporter.shared.count("update_download_quit")
        NSWorkspace.shared.open(UpdateChecker.shared.latestPageURL ?? UpdateChecker.fallbackPageURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { NSApp.terminate(nil) }
    }

    static func presentManualCheckResult(_ state: UpdateState) {
        let alert = NSAlert()
        switch state {
        case .available(let version):
            alert.messageText = L10n.wxUpdateTitle(version)
            alert.informativeText = L10n.wxUpdateBody
            alert.addButton(withTitle: L10n.wxUpdateButton)
            alert.addButton(withTitle: L10n.updateLaterButton)
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                downloadUpdateAndQuit()
            }
            return
        case .upToDate:
            alert.messageText = L10n.updateUpToDateTitle
            alert.informativeText = L10n.updateUpToDateBody(UpdateChecker.shared.currentVersion)
        case .failed:
            alert.messageText = L10n.updateFailedTitle
            alert.informativeText = L10n.updateFailedBody
        case .idle, .checking:
            return
        }
        alert.addButton(withTitle: L10n.updateOKButton)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
