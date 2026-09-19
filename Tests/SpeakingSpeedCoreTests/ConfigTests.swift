import Foundation
import Testing
@testable import SpeakingSpeedCore

private func tempDir() -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@Test func defaultsWhenMissing() throws {
    let c = try Config.load(from: tempDir().appendingPathComponent("config.json"))
    #expect(c.thresholds.calmMaxRate == 3.8)
    #expect(c.windowS == 10.0)
}

@Test func roundTrip() throws {
    let p = tempDir().appendingPathComponent("config.json")
    var c = Config()
    c.thresholds.calmMaxRate = 3.2
    c.thresholds.fastMinRate = 4.1
    try c.save(to: p)
    let c2 = try Config.load(from: p)
    #expect(c2 == c)
}

@Test func partialFileKeepsOtherDefaults() throws {
    let p = tempDir().appendingPathComponent("config.json")
    try #"{"speechMarginDB": 11, "thresholds": {"fastMinRate": 4.0}}"#.write(to: p, atomically: true, encoding: .utf8)
    let c = try Config.load(from: p)
    #expect(c.speechMarginDB == 11)
    #expect(c.thresholds.fastMinRate == 4.0)
    #expect(c.thresholds.calmMaxRate == 3.8)
    #expect(c.tickS == 0.5)
}
