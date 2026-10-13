import Foundation

extension Defaults {
    static var weChatPolicy: WeChatPolicy {
        get { WeChatPolicy(rawValue: defaults.string(forKey: "weChatPolicy") ?? "") ?? .auto }
        set { defaults.set(newValue.rawValue, forKey: "weChatPolicy") }
    }

    /// Anonymous survival statistics (install id, version, OS, language, WeChat running state). On by default, can be turned off.
    static var telemetryEnabled: Bool {
        get { defaults.object(forKey: "telemetryEnabled") == nil ? true : defaults.bool(forKey: "telemetryEnabled") }
        set { defaults.set(newValue, forKey: "telemetryEnabled") }
    }

    static var onboardingCompleted: Bool {
        get { defaults.bool(forKey: "onboardingCompleted") }
        set { defaults.set(newValue, forKey: "onboardingCompleted") }
    }

    /// Random id created on first launch; not derived from hardware, account or any file.
    static var installID: String {
        if let id = defaults.string(forKey: "installID") { return id }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: "installID")
        return id
    }

    static var installDate: Date {
        if let date = defaults.object(forKey: "installDate") as? Date { return date }
        let date = Date()
        defaults.set(date, forKey: "installDate")
        return date
    }
}
