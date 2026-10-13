import AppKit

/// What wxShot can tell about the WeChat desktop app without any permission and without touching its data.
enum WeChatState: Equatable {
    case notRunning
    /// Running but only the small login window exists, so WeChat's own screenshot is unavailable.
    case loginScreen
    /// Running with its main window (visible or hidden), so WeChat's own screenshot is available.
    case loggedIn
}

/// How wxShot behaves while WeChat is running. wxShot always owns the shortcut when WeChat is not running.
enum WeChatPolicy: String, CaseIterable {
    /// Hand the shortcut to WeChat once it is logged in; keep it while WeChat sits on the login screen.
    case auto
    /// Always capture with wxShot, even while WeChat is logged in.
    case alwaysUs
    /// Hand the shortcut to WeChat whenever it is running.
    case yieldWhenRunning
}

extension Notification.Name {
    static let weChatStateDidChange = Notification.Name("wxshot.weChatStateDidChange")
}

/// Watches WeChat launching, quitting and switching windows. It uses workspace notifications only (no polling),
/// and reads window geometry from CGWindowList, which needs no Screen Recording permission.
final class WeChatMonitor {
    static let shared = WeChatMonitor()

    private static let bundleIdentifiers = ["com.tencent.xinWeChat"]
    private static let mainWindowMinSize = CGSize(width: 600, height: 450)

    private(set) var state: WeChatState = .notRunning
    private var observers: [NSObjectProtocol] = []
    private var refreshWorkItem: DispatchWorkItem?

    private init() {}

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let id = app.bundleIdentifier,
                      Self.bundleIdentifiers.contains(id) else { return }
                self?.scheduleRefresh()
            })
        }
        refresh()
    }

    /// WeChat creates and destroys its windows a moment after launch/activation, so settle before reading.
    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: item)
    }

    @discardableResult
    func refresh() -> WeChatState {
        let new = Self.currentState()
        if new != state {
            state = new
            NotificationCenter.default.post(name: .weChatStateDidChange, object: nil)
        }
        return new
    }

    var isRunning: Bool { state != .notRunning }

    /// Whether wxShot should own the screenshot shortcut right now.
    func shouldOwnShortcut(policy: WeChatPolicy = Defaults.weChatPolicy) -> Bool {
        switch state {
        case .notRunning:
            return true
        case .loginScreen:
            return policy != .yieldWhenRunning
        case .loggedIn:
            return policy == .alwaysUs
        }
    }

    private static func currentState() -> WeChatState {
        let apps = bundleIdentifiers.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        guard !apps.isEmpty else { return .notRunning }
        let pids = Set(apps.map { Int($0.processIdentifier) })
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int, pids.contains(pid),
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double else { continue }
            if width >= mainWindowMinSize.width && height >= mainWindowMinSize.height { return .loggedIn }
        }
        return .loginScreen
    }
}
