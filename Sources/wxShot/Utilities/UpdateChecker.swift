import AppKit
import Foundation

/// Outcome of an update check / install. Drives the menu bar item and the
/// About pane.
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(version: String)
    case failed
}

extension Notification.Name {
    static let updateStateDidChange = Notification.Name("wxshot.updateStateDidChange")
}

/// Checks https://ntfstool.com/wxshot-version.json for a newer wxShot version. It never downloads or
/// installs anything itself: an available update just opens the download page.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private static let versionURL = URL(string: "https://ntfstool.com/wxshot-version.json")!
    static let fallbackPageURL = URL(string: "https://ntfstool.com/wxshot/")!
    private let throttleKey = "lastUpdateCheckAt"
    private let skippedVersionKey = "skippedUpdateVersion"
    private let shortcutTriggerDayKey = "automaticUpdateCheckShortcutTriggerDay"
    private let shortcutTriggerCountKey = "automaticUpdateCheckShortcutTriggerCount"
    private let automaticCheckShortcutTriggerCount = 1

    private(set) var state: UpdateState = .idle {
        didSet {
            NotificationCenter.default.post(name: .updateStateDidChange, object: nil)
        }
    }

    /// Details of the latest release, populated by a successful check. Kept
    /// outside `UpdateState` so the enum stays trivially `Equatable`.
    private(set) var latestVersion: String?
    private(set) var latestPageURL: URL?
    /// True when the server's `min_version` is newer than this build: the update is mandatory.
    private(set) var isUpdateRequired = false

    private init() {}

    /// Running app version, e.g. "1.1.2".
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// The version the user chose to skip, if any.
    var skippedVersion: String? {
        UserDefaults.standard.string(forKey: skippedVersionKey)
    }

    /// True while a check or install is in flight — used to reject overlapping
    /// requests.
    private var isBusy: Bool {
        switch state {
        case .checking: return true
        default: return false
        }
    }

    /// Silent automatic check tied to real usage rather than app launch. The
    /// first screenshot-shortcut trigger of each local day checks ntfstool.com unless
    /// a check already ran today.
    func checkFromScreenshotShortcutIfDue() {
        let today = Self.dayKey(for: Date())
        let defaults = UserDefaults.standard
        var triggerCount = defaults.integer(forKey: shortcutTriggerCountKey)

        if defaults.string(forKey: shortcutTriggerDayKey) != today {
            defaults.set(today, forKey: shortcutTriggerDayKey)
            triggerCount = 0
        }

        triggerCount += 1
        defaults.set(triggerCount, forKey: shortcutTriggerCountKey)

        guard triggerCount == automaticCheckShortcutTriggerCount,
              !hasCheckedToday,
              !isBusy
        else { return }

        check(manual: false)
    }

    /// Once a day at launch, so a mandatory update (`min_version`) reaches people who never press the shortcut.
    func checkAtLaunchIfDue() {
        guard !hasCheckedToday, !isBusy else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, !self.isBusy else { return }
            self.check(manual: false)
        }
    }

    private var hasCheckedToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: throttleKey) as? Date else {
            return false
        }
        return Calendar.autoupdatingCurrent.isDateInToday(last)
    }

    /// Performs a check. `completion` fires on the main thread with the final
    /// state. Manual checks ignore the screenshot-shortcut gate and the
    /// skipped-version preference; a background check stays silent about a
    /// skipped version.
    func check(manual: Bool, completion: ((UpdateState) -> Void)? = nil) {
        guard !isBusy else {
            completion?(state)
            return
        }
        setState(.checking)

        var request = URLRequest(url: Self.versionURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("wxShot/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            guard let self = self else { return }

            // Record the attempt regardless of outcome so a failing network
            // doesn't retry on every screenshot shortcut trigger today.
            UserDefaults.standard.set(Date(), forKey: self.throttleKey)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["version"] as? String
            else {
                self.finish(.failed, completion: completion)
                return
            }

            let latest = Self.normalizeVersion(tag)
            guard !latest.isEmpty else {
                self.finish(.failed, completion: completion)
                return
            }
            let pageURL = (json["download"] as? String).flatMap(URL.init)
                ?? (json["url"] as? String).flatMap(URL.init)
                ?? Self.fallbackPageURL

            let minimum = (json["min_version"] as? String).map(Self.normalizeVersion) ?? ""
            let required = !minimum.isEmpty && Self.isVersion(minimum, newerThan: self.currentVersion)
            self.isUpdateRequired = required

            guard required || Self.shouldOfferRelease(latestVersion: latest,
                                          currentVersion: self.currentVersion,
                                          manual: manual,
                                          isDebugBuild: Self.isDebugBuild) else {
                self.finish(.upToDate, completion: completion)
                return
            }

            self.latestVersion = latest
            self.latestPageURL = pageURL

            // A background check stays quiet about a version the user skipped;
            // a manual check always reports it.
            if !manual, !required, latest == self.skippedVersion {
                self.finish(.upToDate, completion: completion)
            } else {
                self.finish(.available(version: latest), completion: completion)
                // A background check that finds an update tells the user once; a mandatory one cannot be dismissed.
                if !manual {
                    DispatchQueue.main.async { StatusBarController.presentBackgroundUpdatePrompt(version: latest, required: required) }
                }
            }
        }.resume()
    }

    /// Marks the latest release as skipped so future background checks ignore
    /// it, and resets the UI to the up-to-date state.
    func skipVersion() {
        guard let version = latestVersion else { return }
        UserDefaults.standard.set(version, forKey: skippedVersionKey)
        setState(.upToDate)
    }

    private func finish(_ newState: UpdateState, completion: ((UpdateState) -> Void)?) {
        DispatchQueue.main.async {
            self.state = newState
            completion?(newState)
        }
    }

    private func setState(_ newState: UpdateState) {
        if Thread.isMainThread {
            state = newState
        } else {
            DispatchQueue.main.async { self.state = newState }
        }
    }

    /// Strips a leading `release-v` / `v` from a version string, so "v1.1.2" becomes "1.1.2".
    static func normalizeVersion(_ raw: String) -> String {
        var v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.hasPrefix("release-v") {
            v.removeFirst("release-v".count)
        } else if v.hasPrefix("release-") {
            v.removeFirst("release-".count)
        }
        if v.hasPrefix("v") || v.hasPrefix("V") {
            v.removeFirst()
        }
        return v
    }

    /// Component-wise numeric comparison: "1.2.0" is newer than "1.1.9".
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let a = components(lhs)
        let b = components(rhs)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// A manual check can replace a locally built Debug app with the latest
    /// published Release even when their version numbers match or differ.
    static func shouldOfferRelease(latestVersion: String,
                                   currentVersion: String,
                                   manual: Bool,
                                   isDebugBuild: Bool) -> Bool {
        (manual && isDebugBuild)
            || isVersion(latestVersion, newerThan: currentVersion)
    }

    private static func dayKey(for date: Date) -> String {
        let components = Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    private static func components(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix(while: { $0.isNumber })) ?? 0 }
    }
}
