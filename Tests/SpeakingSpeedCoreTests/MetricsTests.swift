import Testing
@testable import SpeakingSpeedCore

private let frameS = 0.02

/// "s" = speech frame, "." = silence frame.
private func frames(_ pattern: String) -> [Bool] {
    pattern.map { $0 == "s" }
}

private func none(_ n: Int) -> [Bool] {
    [Bool](repeating: false, count: n)
}

private func approx(_ a: Double?, _ b: Double) -> Bool {
    guard let a else { return false }
    return abs(a - b) < 1e-9
}

@Test func articulationRate() {
    // 100 speech frames = 2.0 s phonation, 8 nuclei -> 4.0 syl/s
    let speech = frames(String(repeating: "s", count: 100))
    var nuclei = none(100)
    for i in stride(from: 0, to: 100, by: 13).prefix(8) { nuclei[i] = true }
    let m = computeMetrics(speech: speech, nuclei: nuclei, frameS: frameS)
    #expect(m.phonationS == 2.0)
    #expect(m.syllables == 8)
    #expect(approx(m.articulationRate, 4.0))
}

@Test func rateIsNilWhenTooLittleSpeech() {
    let speech = frames(String(repeating: "s", count: 10) + String(repeating: ".", count: 90))
    let m = computeMetrics(speech: speech, nuclei: none(100), frameS: frameS, minPhonationS: 1.0)
    #expect(m.articulationRate == nil)
}

@Test func pausesCountedOnlyBetweenSpeech() {
    // speech 1 s, pause 0.5 s, speech 1 s, trailing silence 1 s (not a pause)
    let speech = frames(String(repeating: "s", count: 50) + String(repeating: ".", count: 25)
        + String(repeating: "s", count: 50) + String(repeating: ".", count: 50))
    let m = computeMetrics(speech: speech, nuclei: none(175), frameS: frameS, pauseMinS: 0.35)
    #expect(m.pauses == 1)
    #expect(approx(m.meanPauseS, 0.5))
}

@Test func currentRunResetsAfterPause() {
    // 2 s, 0.6 s gap, 0.8 s
    let speech = frames(String(repeating: "s", count: 100) + String(repeating: ".", count: 30)
        + String(repeating: "s", count: 40))
    let m = computeMetrics(speech: speech, nuclei: none(170), frameS: frameS, runPauseS: 0.5)
    #expect(approx(m.currentRunS, 0.8))
}

@Test func currentRunZeroWhenCurrentlySilent() {
    let speech = frames(String(repeating: "s", count: 100) + String(repeating: ".", count: 30))
    let m = computeMetrics(speech: speech, nuclei: none(130), frameS: frameS, runPauseS: 0.5)
    #expect(m.currentRunS == 0.0)
}

@Test func currentRunSpansShortGaps() {
    // 0.2 s gap < runPauseS
    let speech = frames(String(repeating: "s", count: 50) + String(repeating: ".", count: 10)
        + String(repeating: "s", count: 50))
    let m = computeMetrics(speech: speech, nuclei: none(110), frameS: frameS, runPauseS: 0.5)
    #expect(approx(m.currentRunS, 2.2))
}

@Test func speakingRateCountsShortPausesButNotLongSilences() {
    // 1 s speech, 1 s pause, 1 s speech, then 3 s silence (listening): 12 syllables.
    let speech = frames(String(repeating: "s", count: 50) + String(repeating: ".", count: 50)
        + String(repeating: "s", count: 50) + String(repeating: ".", count: 150))
    var nuclei = none(300)
    for i in stride(from: 0, to: 50, by: 9) { nuclei[i] = true; nuclei[100 + i] = true }
    let m = computeMetrics(speech: speech, nuclei: nuclei, frameS: frameS, turnGapS: 2.0)
    #expect(approx(m.speakingS, 3.0))
    #expect(approx(m.speakingRate, 4.0))
    #expect(approx(m.articulationRate, 6.0))
}

@Test func speakingTimeExcludesLongGapBetweenTurns() {
    // 1 s speech, 2.5 s gap (other person talking), 1 s speech.
    let speech = frames(String(repeating: "s", count: 50) + String(repeating: ".", count: 125)
        + String(repeating: "s", count: 50))
    let m = computeMetrics(speech: speech, nuclei: none(225), frameS: frameS, turnGapS: 2.0)
    #expect(approx(m.speakingS, 2.0))
}

@Test func rateUsesOnlyTheRecentWindowButRunUsesHistory() {
    // 10 s of fast speech (5 syl/s), no pauses: 6 s earlier + 4 s recent.
    // Recent window is 2 s with 6 syllables -> 3 syl/s; the run spans all 10 s.
    let speech = frames(String(repeating: "s", count: 500))
    var nuclei = none(500)
    for i in stride(from: 0, to: 400, by: 10) { nuclei[i] = true }   // 40 early: 5 syl/s over 8 s
    for i in stride(from: 400, to: 500, by: 17) { nuclei[i] = true } // 6 recent
    let m = computeMetrics(speech: speech, nuclei: nuclei, frameS: frameS, rateWindowFrames: 100)
    #expect(m.syllables == 6)
    #expect(approx(m.phonationS, 2.0))
    #expect(approx(m.speakingRate, 3.0))
    #expect(approx(m.currentRunS, 10.0))
}

@Test func runPhonationCountsVoiceInTheCurrentRunOnly() {
    let t = { (n: Int) in [Bool](repeating: true, count: n) }
    let f = { (n: Int) in [Bool](repeating: false, count: n) }
    // old run, 0.6 s pause, then 0.6 s voice, 0.2 s gap, 0.4 s voice
    let speech = t(50) + f(30) + t(30) + f(10) + t(20)
    let m = computeMetrics(speech: speech, nuclei: f(speech.count), frameS: 0.02)
    #expect(abs(m.currentRunS - 1.2) < 1e-9)
    #expect(abs(m.runPhonationS - 1.0) < 1e-9)
    let quiet = computeMetrics(speech: speech + f(30), nuclei: f(speech.count + 30), frameS: 0.02)
    #expect(quiet.runPhonationS == 0)
}
