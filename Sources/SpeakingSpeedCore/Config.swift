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
    /// Show the "pause" nudge after this long talking without a real pause.
    public var runNudgeS = 15.0
    /// Red "slow down" when the slow average is at or above this many words per minute.
    /// Separate from the calibrated zones: conversation runs faster than read-aloud.
    public var slowDownWPM = 220.0
    /// Seconds of voice in the rate window before it counts as speaking (ignores key clicks).
    public var minSpeechS = 1.0
    /// The slow average starts afresh after this long without speech.
    public var trendResetS = 10.0
    /// Time constant of the slow rate average that drives the "slow down" cue.
    public var trendTauS = 25.0
    /// Seconds of speech before the slow average counts.
    public var trendWarmupS = 10.0
    /// Minimum gap between floating nudges; the dot still changes.
    public var nudgeCooldownS = 30.0
    /// Calls with less of your speech than this are not summarised.
    public var minConversationS = 10.0
    /// Show the live words-per-minute number next to the dot.
    public var showNumberInMenuBar = false
    /// Show a small floating pill near the top of the screen for nudges.
    public var floatingNudge = true
    public var conversationsLog = "~/.local/share/speaking-speed/conversations.jsonl"
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
        runNudgeS = try c.decodeIfPresent(Double.self, forKey: .runNudgeS) ?? d.runNudgeS
        trendTauS = try c.decodeIfPresent(Double.self, forKey: .trendTauS) ?? d.trendTauS
        trendWarmupS = try c.decodeIfPresent(Double.self, forKey: .trendWarmupS) ?? d.trendWarmupS
        nudgeCooldownS = try c.decodeIfPresent(Double.self, forKey: .nudgeCooldownS) ?? d.nudgeCooldownS
        minConversationS = try c.decodeIfPresent(Double.self, forKey: .minConversationS) ?? d.minConversationS
        showNumberInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showNumberInMenuBar) ?? d.showNumberInMenuBar
        floatingNudge = try c.decodeIfPresent(Bool.self, forKey: .floatingNudge) ?? d.floatingNudge
        slowDownWPM = try c.decodeIfPresent(Double.self, forKey: .slowDownWPM) ?? d.slowDownWPM
        minSpeechS = try c.decodeIfPresent(Double.self, forKey: .minSpeechS) ?? d.minSpeechS
        trendResetS = try c.decodeIfPresent(Double.self, forKey: .trendResetS) ?? d.trendResetS
        conversationsLog = try c.decodeIfPresent(String.self, forKey: .conversationsLog) ?? d.conversationsLog
    }

    /// Estimated words per minute for a rate in syllables per second.
    public func wordsPerMinute(_ syllablesPerSecond: Double) -> Double {
        syllablesPerSecond * 60 / syllablesPerWord
    }

    public var sessionsURL: URL {
        URL(fileURLWithPath: (sessionsDir as NSString).expandingTildeInPath)
    }

    public var conversationsURL: URL {
        URL(fileURLWithPath: (conversationsLog as NSString).expandingTildeInPath)
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
