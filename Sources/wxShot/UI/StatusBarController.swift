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
        NSWorkspace.shared.open(UpdateChecker.shared.latestPageURL ?? UpdateChecker.fallbackPageURL)
    }

    @objc private func checkForUpdates() {
        UpdateChecker.shared.check(manual: true) { state in
            Self.presentManualCheckResult(state)
        }
    }

    /// Shown after a background check. Recommended updates can be postponed or skipped; a required one (server
    /// `min_version`) only offers the download, and the app quits so an unsupported build is not used any further.
    static func presentBackgroundUpdatePrompt(version: String, required: Bool) {
        let alert = NSAlert()
        alert.messageText = L10n.updateAvailableTitle(version)
        alert.informativeText = required ? L10n.wxUpdateRequiredBody : L10n.updateAvailableBody
        alert.addButton(withTitle: L10n.updateOpenPageButton)
        if !required {
            alert.addButton(withTitle: L10n.updateLaterButton)
            alert.addButton(withTitle: L10n.updateSkipButton)
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.open(UpdateChecker.shared.latestPageURL ?? UpdateChecker.fallbackPageURL)
        } else if response == .alertThirdButtonReturn {
            UpdateChecker.shared.skipVersion()
        }
        if required { NSApp.terminate(nil) }
    }

    static func presentManualCheckResult(_ state: UpdateState) {
        let alert = NSAlert()
        switch state {
        case .available(let version):
            alert.messageText = L10n.updateAvailableTitle(version)
            alert.informativeText = L10n.updateAvailableBody
            alert.addButton(withTitle: L10n.updateOpenPageButton)
            alert.addButton(withTitle: L10n.updateLaterButton)
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(UpdateChecker.shared.latestPageURL ?? UpdateChecker.fallbackPageURL)
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
