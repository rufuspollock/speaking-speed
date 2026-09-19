import Foundation
import Testing
@testable import SpeakingSpeedCore

private func m(_ rate: Double?, run: Double = 0, pauses: Int = 0) -> Metrics {
    Metrics(windowS: 10, phonationS: 5, syllables: 20, articulationRate: rate,
            speechRate: nil, pauses: pauses, meanPauseS: 0.4, currentRunS: run, speakingRate: rate)
}

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

@Test func sessionWritesCSVAndSummary() throws {
    let dir = tempDir()
    let s = try Session(dir: dir, tickS: 0.5)
    s.record(m(3.5, run: 3), zone: .calm)
    s.record(m(4.8, run: 16), zone: .fast)
    s.record(m(4.0, run: 22), zone: .brisk)
    let summary = s.close()
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".csv") }
    #expect(files.count == 1)
    let text = try String(contentsOf: dir.appendingPathComponent(files[0]), encoding: .utf8)
    #expect(text.filter { $0 == "\n" }.count == 4)  // header + 3 rows
    #expect(summary.ticks == 3)
    #expect(summary.pctFast == 1.0 / 3)
    #expect(summary.longestRunS == 22)
    #expect(summary.runsOver15s == 1)  // 16 -> 22 is the same run
}

@Test func summarizeMedianRate() throws {
    let rows = [m(3.0), m(4.0), m(5.0), m(nil)]
    let s = summarize(rows, zones: Array(repeating: .calm, count: 4), tickS: 0.5)
    #expect(s.medianRate == 4.0)
    #expect(try #require(s.p95Rate) >= 4.9)
}

@Test func loadSummariesReadsBack() throws {
    let dir = tempDir()
    let s = try Session(dir: dir, tickS: 0.5)
    s.record(m(3.5), zone: .calm)
    s.record(m(nil), zone: .unknown)
    _ = s.close()
    let summaries = try loadSummaries(dir: dir)
    #expect(summaries.count == 1)
    #expect(summaries[0].medianRate == 3.5)
    #expect(summaries[0].ticks == 2)
}
