import AppKit

/// Asks once which app should own the screenshot shortcut, the first time WeChat is seen signed in while the user has
/// never picked a policy. Without it, the default `.auto` silently hands ⌥A back to WeChat and wxShot looks broken
/// (about half of installs had WeChat signed in at first launch).
enum WeChatChoicePrompt {
    private static let askedKey = "weChatChoiceAsked"
    private static var isShowing = false

    /// What the user answered, for the survival report: "wxshot", "wechat", or nil when never asked.
    static var answer: String? { Defaults.defaults.string(forKey: askedKey) }

    static func showIfNeeded() {
        guard !isShowing,
              answer == nil,
              Defaults.defaults.object(forKey: "weChatPolicy") == nil,
              Defaults.onboardingCompleted,
              AppPermissions.screenRecordingGranted,
              !OnboardingWindowController.shared.isVisible,
              WeChatMonitor.shared.state == .loggedIn else { return }
        // Let the triggering notification finish before running a modal alert.
        DispatchQueue.main.async { present() }
    }

    static func present() {
        guard !isShowing else { return }
        isShowing = true
        defer { isShowing = false }
        let shortcut = HotkeyManager.currentDisplayString() ?? "⌥A"
        let alert = NSAlert()
        alert.messageText = L10n.wxAskOwnerTitle(shortcut)
        alert.informativeText = L10n.wxAskOwnerBody
        alert.addButton(withTitle: L10n.wxAskUseWxShot)
        alert.addButton(withTitle: L10n.wxAskUseWeChat)
        NSApp.activate(ignoringOtherApps: true)
        let useWxShot = alert.runModal() == .alertFirstButtonReturn
        Defaults.defaults.set(useWxShot ? "wxshot" : "wechat", forKey: askedKey)
        Defaults.weChatPolicy = useWxShot ? .alwaysUs : .auto
        NotificationCenter.default.post(name: .hotkeyDidChange, object: nil)
    }
}
