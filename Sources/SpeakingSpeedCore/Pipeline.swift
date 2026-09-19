// Samples in, Metrics out. push() from the audio thread, tick() from any thread.
import Foundation

public final class Pipeline: @unchecked Sendable {
    public let config: Config
    public let hop: Int
    public let maxFrames: Int
    private var db: [Double] = []
    private var pending: [Float] = []
    private let lock = NSLock()
    /// Envelope levels seen by the last tick, for tuning speechMarginDB.
    public private(set) var lastFloorDB = dbFloor
    public private(set) var lastPeakDB = dbFloor

    public init(config: Config, sampleRate: Double) {
        self.config = config
        self.hop = Int((sampleRate * config.frameS).rounded())
        self.maxFrames = Int((max(config.historyS, config.windowS) / config.frameS).rounded())
    }

    public func push(_ samples: [Float]) {
        lock.withLock {
            pending += samples
            let n = pending.count / hop
            guard n > 0 else { return }
            db += frameDB(Array(pending[0..<(n * hop)]), hop: hop)
            pending.removeFirst(n * hop)
            if db.count > maxFrames { db.removeFirst(db.count - maxFrames) }
        }
    }

    public var framesBuffered: Int {
        lock.withLock { db.count }
    }

    public func tick() -> Metrics {
        let raw = lock.withLock { db }
        let frameS = config.frameS
        guard raw.count >= 3 else {
            return computeMetrics(speech: [], nuclei: [], frameS: frameS)
        }
        let env = smooth(raw, k: config.smoothFrames)
        let floor = noiseFloor(env)
        lastFloorDB = floor
        lastPeakDB = env.max() ?? dbFloor
        let loud = percentile(env, 99) ?? dbFloor
        var cutoff = floor + config.speechMarginDB
        if let below = config.speechBelowPeakDB { cutoff = max(cutoff, loud - below) }
        if loud < config.minLoudDB { cutoff = .infinity }
        let mask = env.map { $0 > cutoff }
        var nuclei = [Bool](repeating: false, count: env.count)
        for i in findNuclei(env, mask: mask, minDipDB: config.minDipDB, minGapFrames: config.minGapFrames) {
            nuclei[i] = true
        }
        return computeMetrics(speech: mask, nuclei: nuclei, frameS: frameS,
                              rateWindowFrames: Int((config.windowS / frameS).rounded()))
    }
}
