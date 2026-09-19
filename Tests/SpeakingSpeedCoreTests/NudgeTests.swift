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

@Test func keyboardBlipIsNotSpeech() {
    var n = nudger()
    _ = n.update(m(run: 5), trend: 5.0, now: 0)  // slow
    let blip = Metrics(windowS: 5, phonationS: 0.1, syllables: 1, articulationRate: nil, speechRate: nil,
                       pauses: 0, meanPauseS: 0, currentRunS: 0.2, speakingRate: nil)
    #expect(n.update(blip, trend: 5.0, now: 60).cue == .idle)
}

@Test func slowNeedsAFreshAverage() {
    var n = nudger()
    #expect(n.update(m(run: 5), trend: 5.0, now: 0).cue == .slow)
    #expect(n.update(m(run: 1), trend: nil, now: 60).cue == .ok)  // average reset after silence
}

@Test func slowThresholdFromWordsPerMinute() {
    var c = Config()
    c.slowDownWPM = 200
    c.syllablesPerWord = 1.5
    #expect(abs(Nudger(config: c).fastMinRate - 5.0) < 1e-9)
}

private func clicks(run: Double) -> Metrics {
    // Typing: a stretch of short gaps with little voice in it; the window still holds earlier speech.
    Metrics(windowS: 5, phonationS: 2, syllables: 3, articulationRate: nil, speechRate: nil, pauses: 0,
            meanPauseS: 0, currentRunS: run, speakingRate: 4.0, runPhonationS: run * 0.1)
}

@Test func typingAfterSpeakingGoesIdle() {
    var n = nudger()
    _ = n.update(m(run: 5), trend: 4.0, now: 0)
    #expect(n.update(clicks(run: 0.4), trend: 4.0, now: 2).cue == .ok)    // still just after speech
    #expect(n.update(clicks(run: 0.4), trend: 4.0, now: 5).cue == .idle)  // 5 s since real speech
}

@Test func staysOnThroughAPauseBetweenPhrases() {
    var n = nudger()
    _ = n.update(m(run: 5), trend: 4.0, now: 0)
    #expect(n.update(m(run: 0, speaking: false), trend: 4.0, now: 1.5).cue == .ok)
}

@Test func longTypingStretchIsNotAPauseNudge() {
    var n = nudger()
    #expect(n.update(clicks(run: 16), trend: 4.0, now: 0).cue == .idle)
}
