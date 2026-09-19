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

@Test func trendResetsAfterSilence() {
    var t = TrendTracker(tauS: 25, warmupS: 1, resetAfterS: 10)
    for _ in 0..<4 { _ = t.update(6.0, dt: 0.5) }
    for _ in 0..<19 { #expect(t.update(nil, dt: 0.5) == 6.0) }  // 9.5 s quiet: held
    #expect(t.update(nil, dt: 0.5) == nil)                     // 10 s quiet: forgotten
    #expect(t.update(4.0, dt: 0.5) == nil)                     // warms up again
}
