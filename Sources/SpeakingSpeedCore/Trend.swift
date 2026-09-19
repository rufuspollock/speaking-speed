import Foundation

/// Slow average of the speaking rate: follows sustained pace and ignores
/// sentence-to-sentence jitter. Exponential moving average with time constant
/// `tauS`, updated only while there is a rate (you are speaking), held otherwise.
/// Reports nil until `warmupS` seconds of speech have been seen, and starts
/// afresh after `resetAfterS` without speech, so an old average never carries
/// into the next thing you say.
public struct TrendTracker: Sendable {
    public let tauS: Double
    public let warmupS: Double
    public let resetAfterS: Double
    public private(set) var value: Double?
    private var average: Double?
    private var seenS = 0.0
    private var silentS = 0.0

    public init(tauS: Double = 25, warmupS: Double = 10, resetAfterS: Double = 10) {
        self.tauS = tauS
        self.warmupS = warmupS
        self.resetAfterS = resetAfterS
    }

    public mutating func update(_ rate: Double?, dt: Double) -> Double? {
        if let rate {
            silentS = 0
            seenS += dt
            if let a = average {
                average = a + (1 - exp(-dt / tauS)) * (rate - a)
            } else {
                average = rate
            }
        } else {
            silentS += dt
            if silentS >= resetAfterS - 1e-9 { reset() }
        }
        value = seenS >= warmupS - 1e-9 ? average : nil
        return value
    }

    public mutating func reset() {
        average = nil
        value = nil
        seenS = 0
        silentS = 0
    }
}
