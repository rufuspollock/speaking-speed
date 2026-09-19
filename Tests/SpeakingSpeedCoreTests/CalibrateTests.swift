import Testing
@testable import SpeakingSpeedCore

@Test func thresholdsFromRatesUsesMedianAnchor() throws {
    let t = try thresholdsFromRates([4.0, 4.2, 4.4, 4.1, 4.3])
    #expect(abs(t.calmMaxRate - 0.9 * 4.2) < 1e-9)
    #expect(abs(t.fastMinRate - 1.05 * 4.2) < 1e-9)
    #expect(t.calmMaxRunS == 12)
}

@Test func thresholdsRejectsTooFew() {
    #expect(throws: CalibrationError.self) { try thresholdsFromRates([4.0]) }
}
