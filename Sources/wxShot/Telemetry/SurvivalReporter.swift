import Foundation

/// Anonymous "is it still alive" reporting. Nothing about screenshots, files, windows or the clipboard is ever sent.
///
/// A report is sent only at install-age checkpoints (day 0, 1, 2, 3, 7, 14, 30, then every 30 days), so each install
/// produces a handful of events in its whole life. That is enough for D1/D7/D30 retention and keeps the server's
/// D1 write budget tiny. Users can switch it off in Settings.
final class SurvivalReporter {
    static let shared = SurvivalReporter()

    /// Install-age days at which a report is due.
    private static let checkpoints = [0, 1, 2, 3, 7, 14, 30]
    private static let endpoint = URL(string: "https://ntfstool.com/api/app_logs")!
    private static let appID = "wxshot"

    private let sessionID = UUID().uuidString.lowercased()
    private var timer: Timer?

    private init() {}

    private var isAllowed: Bool {
        Defaults.telemetryEnabled && ProcessInfo.processInfo.environment["WXSHOT_TELEMETRY"] != "0"
    }

    func start() {
        _ = Defaults.installDate
        reportIfDue()
        // The app lives in the background for weeks; look again every few hours.
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.reportIfDue()
        }
        timer?.tolerance = 600
    }

    /// Feature counters, reported as totals since the previous report and then reset.
    func count(_ feature: String) {
        guard isAllowed else { return }
        var counters = Defaults.defaults.dictionary(forKey: "usageCounters") as? [String: Int] ?? [:]
        counters[feature, default: 0] += 1
        Defaults.defaults.set(counters, forKey: "usageCounters")
    }

    private func reportIfDue() {
        guard isAllowed else { return }
        let ageDays = Calendar.current.dateComponents([.day], from: Defaults.installDate, to: Date()).day ?? 0
        let lastSent = Defaults.defaults.object(forKey: "lastReportCheckpoint") as? Int ?? -1
        guard let due = Self.dueCheckpoint(ageDays: ageDays, lastSent: lastSent) else { return }

        let counters = Defaults.defaults.dictionary(forKey: "usageCounters") as? [String: Int] ?? [:]
        let payload: [String: Any] = [
            "age_days": ageDays,
            "checkpoint": due,
            "wechat": Self.describe(WeChatMonitor.shared.state),
            "wechat_policy": Defaults.weChatPolicy.rawValue,
            "owns_shortcut": WeChatMonitor.shared.shouldOwnShortcut(),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "locale": Locale.preferredLanguages.first ?? "",
            "usage": counters,
        ]
        let event: [String: Any] = [
            "level": "info",
            "event": due == 0 ? "first_open" : "daily_active",
            "message": "",
            "app_id": Self.appID,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            "session_id": sessionID,
            "device_id": Defaults.installID,
            "platform": "macos",
            "payload": payload,
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
        ]
        send(event) { success in
            guard success else { return }
            Defaults.defaults.set(due, forKey: "lastReportCheckpoint")
            Defaults.defaults.removeObject(forKey: "usageCounters")
        }
    }

    /// The newest checkpoint that has passed and has not been reported yet, if any.
    static func dueCheckpoint(ageDays: Int, lastSent: Int) -> Int? {
        var candidates = checkpoints
        if ageDays > 30 { candidates.append(contentsOf: stride(from: 60, through: ageDays, by: 30)) }
        return candidates.filter { $0 <= ageDays && $0 > lastSent }.max()
    }

    private static func describe(_ state: WeChatState) -> String {
        switch state {
        case .notRunning: return "not_running"
        case .loginScreen: return "login_screen"
        case .loggedIn: return "logged_in"
        }
    }

    private func send(_ event: [String: Any], completion: @escaping (Bool) -> Void) {
        guard let body = try? JSONSerialization.data(withJSONObject: ["events": [event]]) else { return completion(false) }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
}
