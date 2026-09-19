# Speaking Speed v2: Behavioural Feedback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Read `docs/v1-lessons.md` first for the why. Beads epic: see `bd ready` (title "v2: behavioural feedback").

**Goal:** Turn the live words-per-minute meter into a behaviour-change tool: a quiet dot that only changes when there's something to act on, a "pause" nudge after long stretches without a pause (with a floating pill near the camera), a slow "sustained fast" signal, and a summary after each conversation with a calm / OK / rushed self-rating.

**Architecture:** All decisions are pure, tested logic in `SpeakingSpeedCore`: `TrendTracker` (slow average of the rate), `Nudger` (which cue to show, with hysteresis and a cooldown), `ConversationTracker` (splits always-on listening into conversations and summarises each), `ConversationLog` (JSON lines on disk). The executable only wires these to AppKit: the menu bar dot, an `NSPanel` pill, and a `UNUserNotificationCenter` notification with rating buttons. The existing `Pipeline` and per-tick session CSV stay as they are.

**Tech stack:** Swift 6.4, SwiftPM, Swift Testing, AppKit, UserNotifications. macOS 15+. Build and test: `swift build`, `swift test`. Install the app: `scripts/install.sh`.

**Behaviour, in one table** (defaults, all in config):

| Cue | Dot | Shown when | Clears when |
|---|---|---|---|
| idle | ⚪ hollow/grey | no speech in the last 5 s | you speak |
| ok | 🟢 | speaking, nothing to act on | |
| pause | 🟠 + pill "pause" | talking ≥ 15 s without a pause (`runNudgeS`) | you pause (run resets) |
| slow | 🔴 + pill "slow down" | 25 s average rate (`trendTauS`) ≥ your fast threshold, after ≥ 10 s of speech | average drops 5 % below the threshold |

A new cue's pill only appears if the last pill was ≥ 30 s ago (`nudgeCooldownS`); the dot still changes. A conversation ends after 120 s with no speech (`conversationEndS`); if you spoke for ≥ 30 s it is summarised and you get a notification asking how it felt.

**Conventions:** TDD for everything in `SpeakingSpeedCore`. UI tasks have a manual check instead. Commit after each task (conventional commits). Run the full suite (`swift test`) before each commit; it should stay green (45 tests at the start).

---

### Task 1: TrendTracker (slow average of the rate)

**Files:**
- Create: `Sources/SpeakingSpeedCore/Trend.swift`
- Test: `Tests/SpeakingSpeedCoreTests/TrendTests.swift`

**Step 1: Write the failing tests**

```swift
import Foundation
import Testing
@testable import SpeakingSpeedCore

@Test func trendIsNilUntilWarmedUp() {
    var t = TrendTracker(tauS: 25, warmupS: 10)
    for _ in 0..<19 { #expect(t.update(4.0, dt: 0.5) == nil) }  // 9.5 s of speech
    #expect(t.update(4.0, dt: 0.5) == 4.0)                      // 10 s
}

@Test func trendMovesAboutTwoThirdsInOneTimeConstant() throws {
    var t = TrendTracker(tauS: 25, warmupS: 0)
    _ = t.update(4.0, dt: 0.5)
    for _ in 0..<50 { _ = t.update(5.0, dt: 0.5) }  // 25 s at 5.0
    let v = try #require(t.value)
    #expect(abs(v - (5.0 - exp(-1.0))) < 0.02)       // 4 + (1 - 1/e)
}

@Test func trendHoldsWhileSilent() {
    var t = TrendTracker(tauS: 25, warmupS: 0)
    _ = t.update(4.0, dt: 0.5)
    #expect(t.update(nil, dt: 0.5) == 4.0)
}

@Test func resetForgetsEverything() {
    var t = TrendTracker(tauS: 25, warmupS: 1)
    for _ in 0..<4 { _ = t.update(4.0, dt: 0.5) }
    t.reset()
    #expect(t.update(4.0, dt: 0.5) == nil)
}
```

**Step 2: Run to verify failure**

Run: `swift test --filter Trend`
Expected: compile error, `cannot find 'TrendTracker' in scope`.

**Step 3: Implement `Sources/SpeakingSpeedCore/Trend.swift`**

```swift
import Foundation

/// Slow average of the speaking rate: follows sustained pace and ignores
/// sentence-to-sentence jitter. Exponential moving average with time constant
/// `tauS`, updated only while there is a rate (you are speaking), held otherwise.
/// Reports nil until `warmupS` seconds of speech have been seen.
public struct TrendTracker: Sendable {
    public let tauS: Double
    public let warmupS: Double
    public private(set) var value: Double?
    private var average: Double?
    private var seenS = 0.0

    public init(tauS: Double = 25, warmupS: Double = 10) {
        self.tauS = tauS
        self.warmupS = warmupS
    }

    public mutating func update(_ rate: Double?, dt: Double) -> Double? {
        if let rate {
            seenS += dt
            if let a = average {
                average = a + (1 - exp(-dt / tauS)) * (rate - a)
            } else {
                average = rate
            }
        }
        value = seenS >= warmupS ? average : nil
        return value
    }

    public mutating func reset() {
        average = nil
        value = nil
        seenS = 0
    }
}
```

Note on the warm-up test: 20 updates of 0.5 s reach exactly 10.0 s, so the 20th returns a value. If floating-point sums land at 9.999…, compare `seenS >= warmupS - 1e-9`.

**Step 4: Run tests**

Run: `swift test --filter Trend` then `swift test`
Expected: 4 new tests pass, whole suite green.

**Step 5: Commit**

```bash
git add Sources/SpeakingSpeedCore/Trend.swift Tests/SpeakingSpeedCoreTests/TrendTests.swift
git commit -m "feat: slow trend average of speaking rate"
```

---

### Task 2: Config for v2

**Files:**
- Modify: `Sources/SpeakingSpeedCore/Config.swift`
- Test: `Tests/SpeakingSpeedCoreTests/ConfigTests.swift`

**Step 1: Failing test** (append to `ConfigTests.swift`)

```swift
@Test func v2Defaults() throws {
    let c = try Config.load(from: tempDir().appendingPathComponent("none.json"))
    #expect(c.runNudgeS == 15)
    #expect(c.trendTauS == 25)
    #expect(c.trendWarmupS == 10)
    #expect(c.nudgeCooldownS == 30)
    #expect(c.conversationEndS == 120)
    #expect(c.minConversationS == 30)
    #expect(c.showNumberInMenuBar == false)
    #expect(c.floatingNudge == true)
    #expect(c.conversationsLog == "~/.local/share/speaking-speed/conversations.jsonl")
}
```

**Step 2:** `swift test --filter v2Defaults` → compile error (no member `runNudgeS`).

**Step 3: Implement.** In `Config`, after `listenOnLaunch`, add:

```swift
    /// Show the "pause" nudge after this long talking without a real pause.
    public var runNudgeS = 15.0
    /// Time constant of the slow rate average that drives the "slow down" cue.
    public var trendTauS = 25.0
    /// Seconds of speech before the slow average counts.
    public var trendWarmupS = 10.0
    /// Minimum gap between floating nudges; the dot still changes.
    public var nudgeCooldownS = 30.0
    /// A conversation ends after this long with no speech.
    public var conversationEndS = 120.0
    /// Conversations with less speech than this are not summarised.
    public var minConversationS = 30.0
    /// Show the live words-per-minute number next to the dot.
    public var showNumberInMenuBar = false
    /// Show a small floating pill near the top of the screen for nudges.
    public var floatingNudge = true
    public var conversationsLog = "~/.local/share/speaking-speed/conversations.jsonl"
```

In `init(from:)` add one `decodeIfPresent(...) ?? d.<name>` line per field (same pattern as the others; `Bool` for the two flags, `String` for the path). Add:

```swift
    public var conversationsURL: URL {
        URL(fileURLWithPath: (conversationsLog as NSString).expandingTildeInPath)
    }
```

**Step 4:** `swift test` → green.

**Step 5: Commit** `git commit -am "feat: config for nudges and conversations"`

---

### Task 3: Nudger (which cue to show)

**Files:**
- Create: `Sources/SpeakingSpeedCore/Nudge.swift`
- Test: `Tests/SpeakingSpeedCoreTests/NudgeTests.swift`

**Step 1: Failing tests**

```swift
import Testing
@testable import SpeakingSpeedCore

private func m(run: Double, speaking: Bool = true) -> Metrics {
    Metrics(windowS: 5, phonationS: speaking ? 3 : 0, syllables: 0, articulationRate: nil,
            speechRate: nil, pauses: 0, meanPauseS: 0, currentRunS: run,
            speakingRate: speaking ? 4.0 : nil)
}

private func nudger() -> Nudger {
    Nudger(runNudgeS: 15, fastMinRate: 4.5, cooldownS: 30)
}

@Test func idleWhenNoSpeech() {
    var n = nudger()
    #expect(n.update(m(run: 0, speaking: false), trend: nil, now: 0).cue == .idle)
}

@Test func okWhileSpeakingNormally() {
    var n = nudger()
    #expect(n.update(m(run: 5), trend: 4.0, now: 0).cue == .ok)
}

@Test func pauseCueAfterLongRunAndClearsOnPause() {
    var n = nudger()
    let u = n.update(m(run: 15), trend: 4.0, now: 100)
    #expect(u.cue == .pause)
    #expect(u.onset)
    #expect(!n.update(m(run: 15.5), trend: 4.0, now: 100.5).onset)  // onset only once
    #expect(n.update(m(run: 0.4), trend: 4.0, now: 101).cue == .ok)  // paused: run reset
}

@Test func slowCueFromTrendWithHysteresis() {
    var n = nudger()
    #expect(n.update(m(run: 3), trend: 4.6, now: 0).cue == .slow)
    #expect(n.update(m(run: 3), trend: 4.4, now: 1).cue == .slow)   // above 4.5 * 0.95
    #expect(n.update(m(run: 3), trend: 4.2, now: 2).cue == .ok)
}

@Test func pauseBeatsSlow() {
    var n = nudger()
    #expect(n.update(m(run: 20), trend: 5.0, now: 0).cue == .pause)
}

@Test func cooldownSuppressesPillButNotCue() {
    var n = nudger()
    #expect(n.update(m(run: 16), trend: 4.0, now: 0).onset)
    _ = n.update(m(run: 0.2), trend: 4.0, now: 1)
    let again = n.update(m(run: 16), trend: 4.0, now: 20)  // 20 s later: inside 30 s cooldown
    #expect(again.cue == .pause)
    #expect(!again.onset)
    _ = n.update(m(run: 0.2), trend: 4.0, now: 21)
    #expect(n.update(m(run: 16), trend: 4.0, now: 40).onset)  // 40 s after the last pill
}

@Test func countsPillsShown() {
    var n = nudger()
    _ = n.update(m(run: 16), trend: 4.0, now: 0)
    _ = n.update(m(run: 0.2), trend: 4.0, now: 1)
    _ = n.update(m(run: 3), trend: 5.0, now: 40)
    #expect(n.pillsShown == 2)
}
```

**Step 2:** `swift test --filter Nudge` → compile error.

**Step 3: Implement `Sources/SpeakingSpeedCore/Nudge.swift`**

```swift
// Which cue the menu bar dot shows, and when a floating nudge should appear.
// Only a few, actionable cues; rare enough not to become wallpaper.

public enum Cue: Int, Sendable, Comparable {
    case idle = 0   // nobody speaking
    case ok = 1     // speaking, nothing to act on
    case slow = 2   // sustained fast pace (slow average)
    case pause = 3  // long stretch without a pause

    public static func < (a: Cue, b: Cue) -> Bool { a.rawValue < b.rawValue }
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
    /// The slow cue clears only when the average drops this far below the threshold.
    public let clearFraction = 0.95
    public private(set) var pillsShown = 0
    private var slowOn = false
    private var last: Cue = .idle
    private var lastPillAt: Double?

    public init(runNudgeS: Double, fastMinRate: Double, cooldownS: Double) {
        self.runNudgeS = runNudgeS
        self.fastMinRate = fastMinRate
        self.cooldownS = cooldownS
    }

    public init(config: Config) {
        self.init(runNudgeS: config.runNudgeS, fastMinRate: config.thresholds.fastMinRate,
                  cooldownS: config.nudgeCooldownS)
    }

    /// `trend` is the slow average from TrendTracker; `now` is seconds on any clock.
    public mutating func update(_ m: Metrics, trend: Double?, now: Double) -> NudgeUpdate {
        if let t = trend {
            if t >= fastMinRate { slowOn = true } else if t < fastMinRate * clearFraction { slowOn = false }
        }
        let cue: Cue
        if m.currentRunS >= runNudgeS {
            cue = .pause
        } else if m.phonationS == 0 && m.currentRunS == 0 {
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
```

Check against `pauseCueAfterLongRunAndClearsOnPause`: after the pause, run is 0.4 and phonation 3, so `.ok`, correct.

**Step 4:** `swift test` → green.

**Step 5: Commit** `git commit -m "feat: nudger picks the cue with hysteresis and cooldown"` (add both files).

---

### Task 4: ConversationTracker (split listening into conversations, summarise each)

**Files:**
- Create: `Sources/SpeakingSpeedCore/Conversation.swift`
- Test: `Tests/SpeakingSpeedCoreTests/ConversationTests.swift`

A run ends (and counts as one pause) when `currentRunS` drops. The run's length is the value just before the drop.

**Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import SpeakingSpeedCore

private func m(run: Double, rate: Double? = 4.0) -> Metrics {
    Metrics(windowS: 5, phonationS: run > 0 ? 3 : 0, syllables: 0, articulationRate: nil,
            speechRate: nil, pauses: 0, meanPauseS: 0, currentRunS: run, speakingRate: run > 0 ? rate : nil)
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

/// Feed `runs` (seconds of talk each, then `gap` seconds silent) at 0.5 s ticks.
private func feed(_ c: inout ConversationTracker, runs: [Double], gap: Double = 1,
                  from start: Double = 0, cue: Cue = .ok) -> (ConversationSummary?, Double) {
    var t = start
    var out: ConversationSummary?
    for r in runs {
        var s = 0.5
        while s <= r { out = c.update(m(run: s), cue: cue, now: t0 + t, dt: 0.5) ?? out; s += 0.5; t += 0.5 }
        var g = 0.0
        while g < gap { out = c.update(m(run: 0), cue: .idle, now: t0 + t, dt: 0.5) ?? out; g += 0.5; t += 0.5 }
    }
    return (out, t)
}

private func tracker() -> ConversationTracker {
    ConversationTracker(endAfterSilenceS: 120, minSpeakingS: 30, longRunS: 15)
}

@Test func conversationEndsAfterLongSilenceWithSummary() throws {
    var c = tracker()
    let (none, t) = feed(&c, runs: [10, 20, 10])
    #expect(none == nil)
    var s: ConversationSummary?
    var tt = t
    while s == nil && tt < t + 200 { s = c.update(m(run: 0), cue: .idle, now: t0 + tt, dt: 0.5); tt += 0.5 }
    let sum = try #require(s)
    #expect(abs(sum.speakingS - 40) < 1)
    #expect(sum.longestRunS == 20)
    #expect(sum.longRuns == 1)
    #expect(sum.pauses == 3)
    #expect(abs(sum.pausesPerMin - 4.5) < 0.2)   // 3 pauses in 40 s of speech
    #expect(sum.medianRate == 4.0)
}

@Test func tooLittleSpeechIsNotAConversation() {
    var c = tracker()
    let (_, t) = feed(&c, runs: [5, 5])
    var s: ConversationSummary?
    var tt = t
    while tt < t + 200 { s = c.update(m(run: 0), cue: .idle, now: t0 + tt, dt: 0.5) ?? s; tt += 0.5 }
    #expect(s == nil)
}

@Test func finishClosesAnOpenConversation() throws {
    var c = tracker()
    _ = feed(&c, runs: [20, 20])
    let s = try #require(c.finish(now: t0 + 100))
    #expect(s.longRuns == 2)
}

@Test func timeInSlowCueIsAFraction() throws {
    var c = tracker()
    _ = feed(&c, runs: [20], cue: .ok)
    _ = feed(&c, runs: [20], from: 21, cue: .slow)
    let s = try #require(c.finish(now: t0 + 100))
    #expect(abs(s.fractionSlow - 0.5) < 0.05)
}
```

**Step 2:** `swift test --filter Conversation` → compile error.

**Step 3: Implement `Sources/SpeakingSpeedCore/Conversation.swift`**

```swift
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
```

`longestRunS == 20` in the test relies on runs being fed as exact multiples of 0.5; if it comes out 19.5 or 20.5, fix the helper loop bounds, not the tolerance.

**Step 4:** `swift test` → green.

**Step 5: Commit** `git commit -m "feat: conversation tracker and summary"` (add both files).

---

### Task 5: ConversationLog (JSON lines on disk, ratings)

**Files:**
- Modify: `Sources/SpeakingSpeedCore/Conversation.swift`
- Test: `Tests/SpeakingSpeedCoreTests/ConversationTests.swift`

**Step 1: Failing tests** (append)

```swift
private func sample() -> ConversationSummary {
    ConversationSummary(start: t0, end: t0 + 600, speakingS: 300, medianRate: 4.2, longestRunS: 22,
                        longRuns: 2, pauses: 40, pausesPerMin: 8, fractionSlow: 0.1, nudges: 3, rating: nil)
}

@Test func logAppendsAndReadsBack() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    let log = ConversationLog(url: url)
    try log.append(sample())
    try log.append(sample())
    #expect(try log.all().count == 2)
}

@Test func ratingIsStoredOnTheRightConversation() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    let log = ConversationLog(url: url)
    let a = sample(), b = sample()
    try log.append(a)
    try log.append(b)
    try log.rate(b.id, .rushed)
    let all = try log.all()
    #expect(all.first { $0.id == a.id }?.rating == nil)
    #expect(all.first { $0.id == b.id }?.rating == .rushed)
}
```

**Step 2:** fails to compile.

**Step 3: Implement** (append to `Conversation.swift`)

```swift
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
```

**Step 4:** `swift test` → green.

**Step 5: Commit** `git commit -m "feat: conversation log with ratings"`

---

### Task 6: Menu bar: dot only, readouts in the menu

**Files:**
- Modify: `Sources/speaking-speed/MenuBar.swift`

No unit tests (AppKit). The logic lives in Tasks 1–5.

**Step 1: Wire the core pieces into `MenuBarController`.** Add properties:

```swift
    private var trend = TrendTracker()
    private var nudger = Nudger(runNudgeS: 15, fastMinRate: 4.5, cooldownS: 30)
    private var conversation = ConversationTracker()
    private let nowItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let trendItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let showNumberItem = NSMenuItem(title: "Show words per minute in menu bar", action: #selector(toggleShowNumber), keyEquivalent: "")
    private let floatingItem = NSMenuItem(title: "Floating nudges", action: #selector(toggleFloating), keyEquivalent: "")
```

In `init`, set `trend = TrendTracker(tauS: cfg.trendTauS, warmupS: cfg.trendWarmupS)`, `nudger = Nudger(config: cfg)`, `conversation = ConversationTracker(config: cfg)`; disable `nowItem`/`trendItem` (info lines); set checkbox states from `cfg.showNumberInMenuBar` / `cfg.floatingNudge`; menu order:

```
Start/Stop listening
────
Now: ~168 wpm (last 5 s)
Last 30 s: ~155 wpm
Talking 8 s without a pause · 3 pauses in 30 s     (statusLine)
Last conversation: …                               (lastSummary, hidden until one exists)
────
Show words per minute in menu bar  ✓/✗
Floating nudges  ✓/✗
Listen when app starts  ✓/✗
Open at login  ✓/✗
────
Quit
```

The two toggles follow `toggleAutoListen`: flip the config field, set `.state`, `try cfg.save()`.

**Step 2: Replace `tick()`**

```swift
    @objc private func tick() {
        guard let p = pipeline, let s = session else { return }
        let m = p.tick()
        let z = smoother.update(classify(m, cfg.thresholds))
        s.record(m, zone: z)                      // per-tick CSV unchanged
        let avg = trend.update(m.speakingRate, dt: cfg.tickS)
        let u = nudger.update(m, trend: avg, now: Date().timeIntervalSinceReferenceDate)
        if u.onset && cfg.floatingNudge { nudgePanel.show(u.cue) }
        if u.cue < .slow { nudgePanel.hideIfShowing() }
        if let done = conversation.update(m, cue: u.cue, nudgeShown: u.onset && cfg.floatingNudge,
                                          now: Date(), dt: cfg.tickS) {
            conversationEnded(done)
        }
        func wpm(_ r: Double?) -> String { r.map { String(Int(cfg.wordsPerMinute($0).rounded())) } ?? "--" }
        let number = cfg.showNumberInMenuBar ? " \(wpm(m.speakingRate))" : ""
        setTitle(dot[u.cue]! + number)
        nowItem.title = "Now: ~\(wpm(m.speakingRate)) wpm (last \(Int(cfg.windowS)) s)"
        trendItem.title = "Last \(Int(cfg.trendTauS)) s: ~\(wpm(avg)) wpm"
        statusLine.title = "Talking \(Int(m.currentRunS)) s without a pause · \(m.pauses) pauses in \(Int(cfg.historyS)) s"
    }
```

with, at file scope:

```swift
let dot: [Cue: String] = [.idle: "⚪", .ok: "🟢", .slow: "🔴", .pause: "🟠"]
```

`nudgePanel` comes in Task 7 and `conversationEnded` in Task 8; for this task stub them (`private func conversationEnded(_ s: ConversationSummary) {}` and leave the two `nudgePanel` lines commented) so it builds.

In `start()`: reset `trend`, `nudger`, `conversation` with the config (fresh state per listening stretch). In `stop()`: `if let done = conversation.finish(now: Date()) { conversationEnded(done) }` before tearing down, and title back to `⚪`.

**Step 3: Build and manual check**

```bash
swift build && scripts/install.sh
```

Expected: menu bar shows only a dot. Silent → ⚪. Talking → 🟢. Talk 15 s without pausing → 🟠, back to 🟢 when you pause. The menu shows Now / Last 30 s / Talking lines updating. Toggle "Show words per minute in menu bar" → number appears next to the dot and the setting survives a restart.

**Step 4: Commit** `git commit -am "feat: menu bar shows a quiet dot; numbers move into the menu"`

---

### Task 7: Floating nudge pill

**Files:**
- Create: `Sources/speaking-speed/NudgePanel.swift`
- Modify: `Sources/speaking-speed/MenuBar.swift` (uncomment the two `nudgePanel` lines; add `private let nudgePanel = NudgePanel()`)

**Step 1: Implement**

```swift
// A small floating pill near the top centre of the screen (close to the camera),
// shown only when a nudge starts. Never takes focus, visible over full-screen apps.
import AppKit
import SpeakingSpeedCore

@MainActor
final class NudgePanel {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 150, height: 34),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let bg = NSView(frame: panel.contentRect(forFrameRect: panel.frame))
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 17
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = bg.bounds.insetBy(dx: 8, dy: 7)
        label.autoresizingMask = [.width, .height]
        bg.addSubview(label)
        panel.contentView = bg
    }

    func show(_ cue: Cue) {
        let text: String, color: NSColor
        switch cue {
        case .pause: (text, color) = ("pause", .systemOrange)
        case .slow: (text, color) = ("slow down", .systemRed)
        default: return
        }
        label.stringValue = text
        panel.contentView?.layer?.backgroundColor = color.withAlphaComponent(0.85).cgColor
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.maxY - panel.frame.height - 8))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideIfShowing() }
        }
    }

    func hideIfShowing() {
        guard panel.isVisible else { return }
        hideTimer?.invalidate()
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; panel.animator().alphaValue = 0 },
                                             completionHandler: { MainActor.assumeIsolated { self.panel.orderOut(nil) } })
    }
}
```

The pill hides when the cue clears (you paused) or after 6 s, whichever is first.

**Step 2: Manual check.** `scripts/install.sh`, then talk for 15 s without a pause, in a full-screen app too (e.g. a full-screen browser or Zoom). Expected: orange "pause" pill fades in at top centre, doesn't take keyboard focus, fades when you pause. Talk again for 15 s within 30 s: dot turns orange, no pill (cooldown). Untick "Floating nudges": no pill, dot still changes.

**Step 3: Commit** `git commit -m "feat: floating nudge pill near the camera"` (add the new file).

---

### Task 8: End-of-conversation summary with a self-rating

**Files:**
- Create: `Sources/speaking-speed/ConversationNotifier.swift`
- Modify: `Sources/speaking-speed/MenuBar.swift`

**Step 1: Implement the notifier**

```swift
// Posts "How did that feel?" after each conversation, with Calm / OK / Rushed
// buttons. Needs the app bundle (scripts/install.sh); from `swift run` it no-ops
// and the rating is only available in the menu.
import Foundation
import SpeakingSpeedCore
import UserNotifications

@MainActor
final class ConversationNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let category = "conversation"
    private let onRating: (UUID, Rating) -> Void
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    init(onRating: @escaping (UUID, Rating) -> Void) {
        self.onRating = onRating
        super.init()
        guard let center else { return }
        center.delegate = self
        let actions = Rating.allCases.map {
            UNNotificationAction(identifier: $0.rawValue, title: $0.rawValue.capitalized, options: [])
        }
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: actions, intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    func post(_ s: ConversationSummary, text: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "How did that feel?"
        content.body = text
        content.categoryIdentifier = Self.category
        content.userInfo = ["id": s.id.uuidString]
        center.add(UNNotificationRequest(identifier: s.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let rating = Rating(rawValue: response.actionIdentifier),
              let idString = response.notification.request.content.userInfo["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        await MainActor.run { onRating(id, rating) }
    }
}
```

If Swift 6 complains about `onRating` crossing actors, mark the closure `@MainActor @Sendable`.

**Step 2: Wire into `MenuBarController`**

- Properties: `private lazy var notifier = ConversationNotifier { [weak self] id, r in self?.rate(id, r) }`, `private var lastConversationID: UUID?`, and a "Rate last conversation" submenu item with three children (Calm / OK / Rushed) calling `rateLast(_:)`; hidden until a conversation exists.
- `conversationEnded(_ s:)`:

```swift
    private func conversationEnded(_ s: ConversationSummary) {
        let text = formatConversation(s, syllablesPerWord: cfg.syllablesPerWord, longRunS: cfg.runNudgeS)
        do { try ConversationLog(url: cfg.conversationsURL).append(s) } catch { statusLine.title = "\(error)" }
        lastConversationID = s.id
        lastSummary.title = "Last conversation: " + text
        lastSummary.isHidden = false
        rateMenuItem.isHidden = false
        notifier.post(s, text: text)
        print(text)
    }

    private func rate(_ id: UUID, _ r: Rating) {
        try? ConversationLog(url: cfg.conversationsURL).rate(id, r)
        rateMenuItem.title = "Rated: \(r.rawValue)"
    }
```

**Step 3: Manual check.** Use a short end time to test: `~/.config/speaking-speed/config.json` → `{"conversationEndS": 20, "minConversationS": 10}`, restart the app, talk for 15 s, go quiet for 20 s. Expected: first time, macOS asks to allow notifications; then "How did that feel?" with the summary line and Calm / OK / Rushed buttons (hover or expand the notification to see them). Click one; `tail -1 ~/.local/share/speaking-speed/conversations.jsonl` shows the rating. The menu shows "Last conversation: …". Remove the test config values afterwards.

If an ad-hoc signed app can't get notification permission on this macOS, keep the menu submenu as the rating path and file a beads issue; don't block the rest.

**Step 4: Commit** `git commit -m "feat: conversation summary notification with self-rating"`

---

### Task 9: `report` shows conversations and ratings

**Files:**
- Modify: `Sources/speaking-speed/main.swift` (`cmdReport`)

**Step 1:** After the session lines, print the last N conversations:

```swift
    let convs = (try? ConversationLog(url: cfg.conversationsURL).all()) ?? []
    if !convs.isEmpty { print("\nConversations:") }
    let df = DateFormatter()
    df.dateFormat = "EEE d MMM HH:mm"
    for c in convs.suffix(n) {
        let rating = c.rating.map { " · felt \($0.rawValue)" } ?? ""
        print("\(df.string(from: c.start)): "
              + formatConversation(c, syllablesPerWord: cfg.syllablesPerWord, longRunS: cfg.runNudgeS) + rating)
    }
```

**Step 2: Manual check.** `swift run speaking-speed report` after Task 8's test conversation shows it with its rating.

**Step 3: Commit** `git commit -am "feat: report lists conversations with ratings"`

---

### Task 10: Docs, changelog, install

**Files:**
- Modify: `README.md`
- Create: `changelog/2026-MM-DD-behavioural-feedback.md` (date = ship date), screenshot of the dot and of the pill in `changelog/images/`

**Step 1: README.** Rewrite "What it measures" and the menu description around the new behaviour: the dot and its four states, the pause nudge and pill, the slow-down cue, the conversation summary and rating, where conversations are logged, the config keys added in Task 2, and a short "why no number?" paragraph linking `docs/v1-lessons.md`. This also closes the "explain the number" issue.

**Step 2: Changelog entry**, feature tier: title, two or three sentences, screenshot of the pill.

**Step 3:** `swift test` green, `scripts/install.sh`, then commit and push (pushing is fine for this repo).

---

## Acceptance

- `swift test` green (≈ 65 tests).
- Silent → ⚪, talking → 🟢, 15 s without a pause → 🟠 and a pill that goes when you pause, sustained fast → 🔴.
- After a call: a notification asking how it felt; the rating lands in `conversations.jsonl`; `report` lists it.
- Memory still under 50 MB (Activity Monitor or `vmmap --summary`).

## Then: one-week trial (beads task)

Use it on real calls for a week with headphones. Record in the beads task notes: how many nudges a day, whether the pill felt helpful or annoying, whether your ratings match the numbers, and whether you notice yourself pausing without the nudge. That decides the next step: fading the nudges out automatically, the stats-over-time view, or retuning `runNudgeS`.
