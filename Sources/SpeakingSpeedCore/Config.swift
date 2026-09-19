// User config: ~/.config/speaking-speed/config.json. Missing keys use defaults.
import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var frameS = 0.02
    /// Rates average over this many recent seconds: shorter responds faster but jitters more.
    public var windowS = 5.0
    /// Speech detection, pauses and run length look back this far.
    public var historyS = 30.0
    /// Converts syllables to words for display. Conversation averages about
    /// 1.4-1.5; formal reading runs higher (the fixture script is 1.69).
    public var syllablesPerWord = 1.5
    public var tickS = 0.5
    public var smoothFrames = 1
    public var speechMarginDB = 8.0
    /// If set, speech must also be within this many dB of the window's loud
    /// speech (99th percentile), as in de Jong & Wempe (they use 25).
    public var speechBelowPeakDB: Double? = 35
    /// If the window's loud level (99th percentile) is below this, nobody is
    /// talking into the mic: distant voices and room sound are not speech (dBFS).
    public var minLoudDB = -35.0
    public var minDipDB = 3.0
    public var minGapFrames = 4
    public var thresholds = Thresholds()
    /// Menu bar app starts listening as soon as it launches.
    public var listenOnLaunch = true
    public var sessionsDir = "~/.local/share/speaking-speed/sessions"

    public static let defaultPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/speaking-speed/config.json")

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        frameS = try c.decodeIfPresent(Double.self, forKey: .frameS) ?? d.frameS
        windowS = try c.decodeIfPresent(Double.self, forKey: .windowS) ?? d.windowS
        syllablesPerWord = try c.decodeIfPresent(Double.self, forKey: .syllablesPerWord) ?? d.syllablesPerWord
        historyS = try c.decodeIfPresent(Double.self, forKey: .historyS) ?? d.historyS
        tickS = try c.decodeIfPresent(Double.self, forKey: .tickS) ?? d.tickS
        smoothFrames = try c.decodeIfPresent(Int.self, forKey: .smoothFrames) ?? d.smoothFrames
        speechMarginDB = try c.decodeIfPresent(Double.self, forKey: .speechMarginDB) ?? d.speechMarginDB
        speechBelowPeakDB = try c.decodeIfPresent(Double.self, forKey: .speechBelowPeakDB) ?? d.speechBelowPeakDB
        minLoudDB = try c.decodeIfPresent(Double.self, forKey: .minLoudDB) ?? d.minLoudDB
        minDipDB = try c.decodeIfPresent(Double.self, forKey: .minDipDB) ?? d.minDipDB
        minGapFrames = try c.decodeIfPresent(Int.self, forKey: .minGapFrames) ?? d.minGapFrames
        thresholds = try c.decodeIfPresent(Thresholds.self, forKey: .thresholds) ?? d.thresholds
        listenOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .listenOnLaunch) ?? d.listenOnLaunch
        sessionsDir = try c.decodeIfPresent(String.self, forKey: .sessionsDir) ?? d.sessionsDir
    }

    /// Estimated words per minute for a rate in syllables per second.
    public func wordsPerMinute(_ syllablesPerSecond: Double) -> Double {
        syllablesPerSecond * 60 / syllablesPerWord
    }

    public var sessionsURL: URL {
        URL(fileURLWithPath: (sessionsDir as NSString).expandingTildeInPath)
    }

    public static func load(from url: URL = defaultPath) throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return Config() }
        return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL = defaultPath) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Write only what differs from the defaults, so later default changes still apply.
        func dict(_ c: Config) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(c)) as! [String: Any]
        }
        func changed(_ mine: [String: Any], _ base: [String: Any]) -> [String: Any] {
            mine.reduce(into: [:]) { out, kv in
                if let sub = kv.value as? [String: Any], let baseSub = base[kv.key] as? [String: Any] {
                    let d = changed(sub, baseSub)
                    if !d.isEmpty { out[kv.key] = d }
                } else if !((base[kv.key] as? NSObject)?.isEqual(kv.value) ?? false) {
                    out[kv.key] = kv.value
                }
            }
        }
        let diff = changed(try dict(self), try dict(Config()))
        try JSONSerialization.data(withJSONObject: diff, options: [.prettyPrinted, .sortedKeys])
            .write(to: url, options: .atomic)
    }
}
