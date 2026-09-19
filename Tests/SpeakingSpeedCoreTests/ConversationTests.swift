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
    let done = c.finish(now: t0 + 100)
    let s = try #require(done)
    #expect(s.longRuns == 2)
}

@Test func timeInSlowCueIsAFraction() throws {
    var c = tracker()
    _ = feed(&c, runs: [20], cue: .ok)
    _ = feed(&c, runs: [20], from: 21, cue: .slow)
    let done = c.finish(now: t0 + 100)
    let s = try #require(done)
    #expect(abs(s.fractionSlow - 0.5) < 0.05)
}

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

@Test func blipsDoNotKeepAConversationOpen() throws {
    var c = tracker()
    let (_, t) = feed(&c, runs: [20, 20])
    let blip = Metrics(windowS: 5, phonationS: 0.1, syllables: 1, articulationRate: nil, speechRate: nil,
                       pauses: 0, meanPauseS: 0, currentRunS: 0.2, speakingRate: nil)
    var s: ConversationSummary?
    var tt = t
    while s == nil && tt < t + 200 {
        let isBlip = Int(tt * 2) % 20 == 0  // a key click every 10 s
        s = c.update(isBlip ? blip : m(run: 0), cue: .idle, now: t0 + tt, dt: 0.5)
        tt += 0.5
    }
    #expect(s != nil)
}

@Test func aCallOnlyEndsWhenYouEndIt() throws {
    var cfg = Config()
    cfg.minConversationS = 10
    var c = ConversationTracker(config: cfg)
    let (_, t) = feed(&c, runs: [20])
    var tt = t
    while tt < t + 1000 { #expect(c.update(m(run: 0), cue: .idle, now: t0 + tt, dt: 0.5) == nil); tt += 0.5 }
    let done = c.finish(now: t0 + tt)
    #expect(try #require(done).longRuns == 1)
}

@Test func silentCallHasNoSummary() {
    var c = ConversationTracker(endAfterSilenceS: .infinity, minSpeakingS: 0, longRunS: 15)
    _ = c.update(m(run: 0), cue: .idle, now: t0, dt: 0.5)
    #expect(c.finish(now: t0 + 60) == nil)
}
