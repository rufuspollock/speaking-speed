import Testing
@testable import SpeakingSpeedCore

@Test func frameDBShapeAndRange() {
    let x = silence(0.2) + tone(0.2) + silence(0.2)
    let db = frameDB(x, hop: HOP)
    #expect(db.count == x.count / HOP)
    #expect(db.min()! >= dbFloor)
    #expect(db[15] > db[2] + 20)  // tone frames far louder than silence frames
}

@Test func smoothPreservesLength() {
    #expect(smooth([Double](repeating: 0, count: 50), k: 5).count == 50)
}

@Test func speechMaskMarksToneNotNoise() {
    let x = noise(0.5) + tone(0.5) + noise(0.5)
    let db = smooth(frameDB(x, hop: HOP), k: 3)
    let mask = speechMask(db, floor: noiseFloor(db), marginDB: 8)
    let n = mask.count
    #expect(mask[n / 2])
    #expect(!mask[2])
    #expect(!mask[n - 3])
}
