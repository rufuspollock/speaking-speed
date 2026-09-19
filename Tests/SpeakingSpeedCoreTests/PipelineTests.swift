import Testing
@testable import SpeakingSpeedCore

private func config(windowS: Double) -> Config {
    var c = Config()
    c.windowS = windowS
    return c
}

@Test func tickReportsRateForSyllableTrain() throws {
    let p = Pipeline(config: config(windowS: 4), sampleRate: Double(SR))
    // 20 bursts at 0.2 s period; the 4 s window keeps ~16 of them plus 0.8 s trailing noise.
    // Synthetic bursts drop to the noise bed between syllables (real speech does not), so
    // articulationRate is inflated here; assert on speechRate (syllables / window).
    // The bed matters: pure digital silence in the gaps would set the noise floor
    // at -80 dB and make the trailing noise look like speech.
    p.push(onNoiseBed(silence(0.5) + bursts(20, on: 0.12, off: 0.08) + silence(0.8)))
    let m = p.tick()
    #expect(m.articulationRate != nil)
    let rate = try #require(m.speechRate)
    #expect((3.0...5.0).contains(rate))
    #expect(m.currentRunS == 0.0)  // 0.8 s trailing noise >= runPauseS
}

@Test func ringBufferBounded() {
    var c = config(windowS: 2)
    c.historyS = 2
    let p = Pipeline(config: c, sampleRate: Double(SR))
    p.push(silence(10))
    #expect(p.framesBuffered == 100)
}

@Test func pushInOddSizedChunks() {
    let p = Pipeline(config: config(windowS: 2), sampleRate: Double(SR))
    let x = silence(1.0)
    p.push(Array(x[0..<1000]))
    p.push(Array(x[1000...]))
    #expect(p.framesBuffered == 50)
}

@Test func tickBeforeAudioIsUnknown() {
    #expect(Pipeline(config: Config(), sampleRate: Double(SR)).tick().articulationRate == nil)
}

@Test func hopFollowsSampleRate() {
    #expect(Pipeline(config: Config(), sampleRate: 48000).hop == 960)
}

@Test func quietWindowIsNotSpeech() {
    // A syllable train 30 dB down (a voice across the room) never counts as talking.
    let p = Pipeline(config: Config(), sampleRate: Double(SR))
    p.push(onNoiseBed(bursts(20, amp: 0.01), amp: 0.0002))
    let m = p.tick()
    #expect(m.phonationS == 0)
    #expect(m.speakingRate == nil)
}

@Test func historyOutlastsRateWindow() {
    var c = Config()
    c.windowS = 2
    c.historyS = 6
    let p = Pipeline(config: c, sampleRate: Double(SR))
    p.push(silence(10))
    #expect(p.framesBuffered == 300)
}
