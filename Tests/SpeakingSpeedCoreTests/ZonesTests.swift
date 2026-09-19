import Testing
@testable import SpeakingSpeedCore

private let T = Thresholds(calmMaxRate: 3.8, fastMinRate: 4.5, calmMaxRunS: 12, fastMinRunS: 20)

private func m(_ rate: Double?, run: Double = 0) -> Metrics {
    Metrics(windowS: 10, phonationS: 5, syllables: 0, articulationRate: rate,
            speechRate: nil, pauses: 0, meanPauseS: 0, currentRunS: run, speakingRate: rate)
}

@Test func classifyByRate() {
    #expect(classify(m(3.0), T) == .calm)
    #expect(classify(m(4.0), T) == .brisk)
    #expect(classify(m(5.0), T) == .fast)
}

@Test func classifyByRunOverridesCalmRate() {
    #expect(classify(m(3.0, run: 15), T) == .brisk)
    #expect(classify(m(3.0, run: 25), T) == .fast)
}

@Test func classifyUnknownWhenNoRate() {
    #expect(classify(m(nil), T) == .unknown)
}

@Test func smootherNeedsSustainedTicksToWorsen() {
    var s = ZoneSmoother(worsenTicks: 3, improveTicks: 4)
    #expect(s.update(.calm) == .calm)
    #expect(s.update(.fast) == .calm)
    #expect(s.update(.fast) == .calm)
    #expect(s.update(.fast) == .fast)
}

@Test func smootherNeedsMoreTicksToImprove() {
    var s = ZoneSmoother(worsenTicks: 3, improveTicks: 4)
    for _ in 0..<3 { _ = s.update(.fast) }
    #expect(s.current == .fast)
    for _ in 0..<3 { #expect(s.update(.calm) == .fast) }
    #expect(s.update(.calm) == .calm)
}

@Test func smootherIgnoresUnknown() {
    var s = ZoneSmoother(worsenTicks: 3, improveTicks: 4)
    for _ in 0..<3 { _ = s.update(.fast) }
    #expect(s.update(.unknown) == .fast)
}
