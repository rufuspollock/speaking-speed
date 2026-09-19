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

/// Splits continuous listening into conversations: one starts with speech and
/// ends after `endAfterSilenceS` without any. Feed it every tick.
public struct ConversationTracker: Sendable {
    public let endAfterSilenceS: Double
    public let minSpeakingS: Double
    public let longRunS: Double

    private var start: Date?
    private var speakingS = 0.0
    private var silentS = 0.0
    private var rates: [Double] = []
    private var prevRun = 0.0
    private var longest = 0.0
    private var longRuns = 0
    private var pauses = 0
    private var speakingTicks = 0
    private var slowTicks = 0
    private var nudges = 0

    public init(endAfterSilenceS: Double = 120, minSpeakingS: Double = 30, longRunS: Double = 15) {
        self.endAfterSilenceS = endAfterSilenceS
        self.minSpeakingS = minSpeakingS
        self.longRunS = longRunS
    }

    public init(config: Config) {
        self.init(endAfterSilenceS: config.conversationEndS, minSpeakingS: config.minConversationS,
                  longRunS: config.runNudgeS)
    }

    /// Returns a summary when a conversation has just ended.
    public mutating func update(_ m: Metrics, cue: Cue, nudgeShown: Bool = false,
                                now: Date, dt: Double) -> ConversationSummary? {
        let speaking = m.currentRunS > 0
        if m.currentRunS < prevRun { endRun(prevRun) }
        prevRun = m.currentRunS
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
        if prevRun > 0 { endRun(prevRun); prevRun = 0 }
        return start == nil ? nil : close(now: now)
    }

    private mutating func endRun(_ length: Double) {
        pauses += 1
        longest = max(longest, length)
        if length >= longRunS { longRuns += 1 }
    }

    private mutating func close(now: Date) -> ConversationSummary? {
        defer { self = ConversationTracker(endAfterSilenceS: endAfterSilenceS,
                                           minSpeakingS: minSpeakingS, longRunS: longRunS) }
        guard let start, speakingS >= minSpeakingS else { return nil }
        return ConversationSummary(
            start: start, end: now, speakingS: speakingS, medianRate: median(rates),
            longestRunS: longest, longRuns: longRuns, pauses: pauses,
            pausesPerMin: Double(pauses) / (speakingS / 60),
            fractionSlow: speakingTicks > 0 ? Double(slowTicks) / Double(speakingTicks) : 0,
            nudges: nudges, rating: nil)
    }
}
