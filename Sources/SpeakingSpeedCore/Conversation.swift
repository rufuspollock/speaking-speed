import Foundation

public enum Rating: String, Codable, Sendable, CaseIterable {
    case calm, ok, rushed
}

public struct ConversationSummary: Codable, Equatable, Sendable, Identifiable {
    public var id = UUID()
    public var start: Date
    public var end: Date
    public var speakingS: Double
    public var medianRate: Double?      // syllables / s
    public var longestRunS: Double
    public var longRuns: Int            // runs of at least longRunS without a pause
    public var pauses: Int
    public var pausesPerMin: Double     // per minute of speech
    public var fractionSlow: Double     // share of speaking ticks under the "slow down" cue
    public var nudges: Int              // floating nudges shown
    public var rating: Rating?
}

/// Summarises a conversation. Feed it every tick; a call made from the menu
/// (`init(config:)`) only ends with `finish`, while `endAfterSilenceS` can
/// also close one after that long without speech.
public struct ConversationTracker: Sendable {
    public let endAfterSilenceS: Double
    public let minSpeakingS: Double
    public let longRunS: Double
    public let minSpeechS: Double

    private var start: Date?
    private var speakingS = 0.0
    private var silentS = 0.0
    private var rates: [Double] = []
    private var prevRun = 0.0
    private var runSpoken = false       // this run had real speech, not just a click
    private var longest = 0.0
    private var longRuns = 0
    private var pauses = 0
    private var speakingTicks = 0
    private var slowTicks = 0
    private var nudges = 0

    public init(endAfterSilenceS: Double = 120, minSpeakingS: Double = 30, longRunS: Double = 15,
                minSpeechS: Double = 1) {
        self.endAfterSilenceS = endAfterSilenceS
        self.minSpeakingS = minSpeakingS
        self.longRunS = longRunS
        self.minSpeechS = minSpeechS
    }

    /// An explicit call: never ends on silence.
    public init(config: Config) {
        self.init(endAfterSilenceS: .infinity, minSpeakingS: config.minConversationS,
                  longRunS: config.runNudgeS, minSpeechS: config.minSpeechS)
    }

    /// Returns a summary when a conversation has just ended.
    public mutating func update(_ m: Metrics, cue: Cue, nudgeShown: Bool = false,
                                now: Date, dt: Double) -> ConversationSummary? {
        let speaking = m.isSpeech(minSpeechS: minSpeechS)
        if m.currentRunS < prevRun {
            if runSpoken { endRun(prevRun) }
            runSpoken = false
        }
        prevRun = m.currentRunS
        if speaking { runSpoken = true }
        if nudgeShown { nudges += 1 }
        if speaking {
            if start == nil { start = now }
            speakingS += dt
            silentS = 0
            speakingTicks += 1
            if cue == .slow { slowTicks += 1 }
            if let r = m.speakingRate { rates.append(r) }
            return nil
        }
        guard start != nil else { return nil }
        silentS += dt
        return silentS >= endAfterSilenceS ? close(now: now) : nil
    }

    /// Close whatever is open (stop listening, quit).
    public mutating func finish(now: Date) -> ConversationSummary? {
        if prevRun > 0 && runSpoken { endRun(prevRun) }
        prevRun = 0
        return start == nil ? nil : close(now: now)
    }

    private mutating func endRun(_ length: Double) {
        pauses += 1
        longest = max(longest, length)
        if length >= longRunS { longRuns += 1 }
    }

    private mutating func close(now: Date) -> ConversationSummary? {
        defer { self = ConversationTracker(endAfterSilenceS: endAfterSilenceS, minSpeakingS: minSpeakingS,
                                           longRunS: longRunS, minSpeechS: minSpeechS) }
        guard let start, speakingS > 0, speakingS >= minSpeakingS else { return nil }
        return ConversationSummary(
            start: start, end: now, speakingS: speakingS, medianRate: median(rates),
            longestRunS: longest, longRuns: longRuns, pauses: pauses,
            pausesPerMin: Double(pauses) / (speakingS / 60),
            fractionSlow: speakingTicks > 0 ? Double(slowTicks) / Double(speakingTicks) : 0,
            nudges: nudges, rating: nil)
    }
}

/// One JSON object per line, oldest first.
public struct ConversationLog: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public func append(_ s: ConversationSummary) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = try Self.encoder.encode(s) + Data("\n".utf8)
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            h.seekToEndOfFile()
            h.write(line)
        } else {
            try line.write(to: url)
        }
    }

    public func all() throws -> [ConversationSummary] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            try Self.decoder.decode(ConversationSummary.self, from: Data($0.utf8))
        }
    }

    public func rate(_ id: UUID, _ rating: Rating) throws {
        let updated = try all().map { s -> ConversationSummary in
            var s = s
            if s.id == id { s.rating = rating }
            return s
        }
        let data = try updated.map { try Self.encoder.encode($0) + Data("\n".utf8) }.reduce(Data(), +)
        try data.write(to: url, options: .atomic)
    }
}

/// One line for the menu, notification and `report`.
public func formatConversation(_ s: ConversationSummary, syllablesPerWord: Double, longRunS: Double = 15) -> String {
    let wpm = s.medianRate.map { "\(Int(($0 * 60 / syllablesPerWord).rounded())) wpm" } ?? "-- wpm"
    let mins = Int((s.speakingS / 60).rounded())
    return "\(mins) min talking · \(wpm) · \(Int(s.pausesPerMin.rounded())) pauses/min · "
        + "longest \(Int(s.longestRunS))s without a pause · \(s.longRuns) over \(Int(longRunS))s"
}
