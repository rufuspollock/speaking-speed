// Regression test on real read-aloud clips in fixtures/ (see fixtures/README.md).
import Foundation
import Testing
@testable import SpeakingSpeedCore

private struct Clip: Decodable {
    let file: String
    let pace: String
    let syllables: Int
}

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures")

private func clips() throws -> [Clip] {
    try JSONDecoder().decode([Clip].self, from: Data(contentsOf: fixtures.appendingPathComponent("clips.json")))
}

private func analyze(_ clip: Clip) throws -> Metrics {
    let (x, sr) = try readMono(fixtures.appendingPathComponent(clip.file).path)
    var cfg = Config()
    cfg.windowS = Double(x.count) / sr + 1
    let p = Pipeline(config: cfg, sampleRate: sr)
    p.push(x)
    return p.tick()
}

private let haveFixtures = FileManager.default.fileExists(atPath: fixtures.appendingPathComponent("clips.json").path)

@Test(.enabled(if: haveFixtures)) func syllableCountsWithinTenPercent() throws {
    for clip in try clips() {
        let m = try analyze(clip)
        let err = abs(Double(m.syllables - clip.syllables)) / Double(clip.syllables)
        #expect(err <= 0.10, "\(clip.file): detected \(m.syllables), true \(clip.syllables)")
    }
}

@Test(.enabled(if: haveFixtures)) func speakingRateOrdersPaces() throws {
    let rates = try Dictionary(uniqueKeysWithValues: clips().map { ($0.pace, try #require(analyze($0).speakingRate)) })
    let slow = try #require(rates["slow"]), normal = try #require(rates["normal"]), fast = try #require(rates["fast"])
    #expect(slow * 1.1 < normal, "slow should read clearly below normal")
    #expect(normal < fast)
}
