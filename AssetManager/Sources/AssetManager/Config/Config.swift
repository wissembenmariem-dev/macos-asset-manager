import Foundation

struct Thresholds: Codable {
    var ramPressureWarn: Double = 75
    var ramPressureCritical: Double = 88
    var swapUsedWarnGB: Double = 3
    var processRunawayCPU: Double = 200
    var processRunawayRAMGB: Double = 1.0
    var processRunawayDurationSec: Int = 30
}

struct AppConfig: Codable {
    var thresholds = Thresholds()
    var whitelistNeverThrottle: [String] = [
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.mail",
        "com.microsoft.Outlook",
        "us.zoom.xos"
    ]
    var whitelistNeverSuspend: [String] = [
        "com.microsoft.teams2",
        "com.tinyspeck.slackmacgap",
        "com.spotify.client",
        "com.apple.Music",
        "us.zoom.xos"
    ]
    var autoThrottleBackground: Bool = false
    var autoSuspendInactiveCometHelpers: Bool = false
    var pollIntervalActiveSec: Double = 2
    var pollIntervalIdleSec: Double = 5
}

final class ConfigStore {
    static let shared = ConfigStore()
    private let url: URL
    private(set) var config: AppConfig = AppConfig()

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("asset-manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("config.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            save()
            return
        }
        config = cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(config) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        mutate(&config)
        save()
    }
}
