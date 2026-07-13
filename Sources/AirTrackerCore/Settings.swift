import Foundation

/// User-facing configuration, persisted as one JSON blob so the app, the CLI, and
/// import/export all share the same representation.
public struct TrackerSettings: Codable, Equatable, Sendable {
    public var openTrackHost: String = "127.0.0.1"
    public var openTrackPort: Int = 4242
    public var smoothing: Double = 0.18
    public var axis: AxisConfig = AxisConfig()
    public init() {}
}

public enum SettingsStore {
    public static let suiteName = "com.szilard.airtracker"
    private static let key = "settings"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public static func load() -> TrackerSettings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(TrackerSettings.self, from: data) else {
            return TrackerSettings()
        }
        return s
    }

    public static func save(_ settings: TrackerSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    public static func encode(_ settings: TrackerSettings) -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(settings)) ?? Data()
    }

    public static func decode(_ data: Data) -> TrackerSettings? {
        try? JSONDecoder().decode(TrackerSettings.self, from: data)
    }
}
