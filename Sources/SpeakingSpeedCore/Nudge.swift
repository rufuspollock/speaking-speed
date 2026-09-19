// Which cue the menu bar dot shows, and when a floating nudge should appear.
// Only a few, actionable cues; rare enough not to become wallpaper.

public enum Cue: Int, Sendable, Comparable {
    case idle = 0   // nobody speaking
    case ok = 1     // speaking, nothing to act on
    case slow = 2   // sustained fast pace (slow average)
    case pause = 3  // long stretch without a pause

    public static func < (a: Cue, b: Cue) -> Bool { a.rawValue < b.rawValue }
}

extension Metrics {
    /// Real speech, not key clicks or bumps: the current stretch of sound has at
    /// least `minSpeechS` of voice and is mostly voice. Typing makes stretches of
    /// short clicks with long gaps, which fail the second test even when long.
    public func isSpeech(minSpeechS: Double, minVoicedShare: Double = 0.4) -> Bool {
        currentRunS > 0 && runPhonationS >= minSpeechS && runPhonationS >= minVoicedShare * currentRunS
    }
}

public struct NudgeUpdate: Equatable, Sendable {
    public var cue: Cue
    /// True when a floating nudge should appear now (new cue, outside cooldown).
    public var onset: Bool
}

public struct Nudger: Sendable {
    public let runNudgeS: Double
    public let fastMinRate: Double
    public let cooldownS: Double
    public let minSpeechS: Double
    /// The dot stays on this long after the last real speech, through pauses between phrases.
    public let holdS = 5.0
    /// The slow cue clears only when the average drops this far below the threshold.
    public let clearFraction = 0.95
    public private(set) var pillsShown = 0
    private var slowOn = false
    private var last: Cue = .idle
    private var lastPillAt: Double?
    private var lastSpeechAt: Double?

    public init(runNudgeS: Double, fastMinRate: Double, cooldownS: Double, minSpeechS: Double = 1) {
        self.runNudgeS = runNudgeS
        self.fastMinRate = fastMinRate
        self.cooldownS = cooldownS
        self.minSpeechS = minSpeechS
    }

    public init(config: Config) {
        self.init(runNudgeS: config.runNudgeS,
                  fastMinRate: config.slowDownWPM * config.syllablesPerWord / 60,
                  cooldownS: config.nudgeCooldownS, minSpeechS: config.minSpeechS)
    }

    /// `trend` is the slow average from TrendTracker (nil until it has a fresh
    /// average, which also clears "slow"); `now` is seconds on any clock.
    public mutating func update(_ m: Metrics, trend: Double?, now: Double) -> NudgeUpdate {
        if let t = trend {
            if t >= fastMinRate { slowOn = true } else if t < fastMinRate * clearFraction { slowOn = false }
        } else {
            slowOn = false
        }
        let speech = m.isSpeech(minSpeechS: minSpeechS)
        if speech { lastSpeechAt = now }
        let cue: Cue
        if speech && m.currentRunS >= runNudgeS {
            cue = .pause
        } else if lastSpeechAt.map({ now - $0 >= holdS }) ?? true {
            cue = .idle
        } else if slowOn {
            cue = .slow
        } else {
            cue = .ok
        }
        var onset = false
        if cue >= .slow && cue != last {
            if lastPillAt.map({ now - $0 >= cooldownS }) ?? true {
                onset = true
                lastPillAt = now
                pillsShown += 1
            }
        }
        last = cue
        return NudgeUpdate(cue: cue, onset: onset)
    }
}
