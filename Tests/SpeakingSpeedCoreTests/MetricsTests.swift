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
