import Testing
@testable import SpeakingSpeedCore

private func env(_ x: [Float]) -> ([Double], [Bool]) {
    let db = smooth(frameDB(x, hop: HOP), k: 3)
    return (db, speechMask(db, floor: noiseFloor(db), marginDB: 8))
}

@Test func countsBursts() {
    let (db, mask) = env(noise(0.3) + bursts(8) + noise(0.3))
    let idx = findNuclei(db, mask: mask)
    #expect((7...9).contains(idx.count))
}

@Test func noNucleiInNoise() {
    let (db, mask) = env(noise(2.0))
    #expect(findNuclei(db, mask: mask).isEmpty)
}

@Test func nucleiAreInsideSpeech() {
    let (db, mask) = env(silence(0.5) + bursts(3) + silence(0.5))
    let idx = findNuclei(db, mask: mask)
    #expect(idx.count == 3)
    #expect(idx.allSatisfy { mask[$0] })
}

// find_peaks port: plateau resolves to its middle, distance keeps the higher peak.
@Test func plateauPeakIsItsMiddle() {
    let db: [Double] = [0, 5, 5, 5, 0]
    #expect(findNuclei(db, mask: [Bool](repeating: true, count: 5), minGapFrames: 1) == [2])
}

@Test func distanceKeepsHigherPeak() {
    let db: [Double] = [0, 6, 0, 9, 0, 0, 0, 0, 7, 0]
    let idx = findNuclei(db, mask: [Bool](repeating: true, count: db.count), minGapFrames: 4)
    #expect(idx == [3, 8])
}

@Test func prominenceRejectsShallowDip() {
    // Second bump rises only 1 dB above the dip between them.
    let db: [Double] = [0, 10, 8, 9, 0]
    let idx = findNuclei(db, mask: [Bool](repeating: true, count: db.count), minGapFrames: 1)
    #expect(idx == [1])
}
