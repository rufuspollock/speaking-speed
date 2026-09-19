// Intensity envelope of a mono Float signal, in dB.
import Accelerate

public let dbFloor = -80.0

/// RMS per non-overlapping frame of `hop` samples, in dBFS. Drops the tail.
public func frameDB(_ x: [Float], hop: Int) -> [Double] {
    let n = x.count / hop
    guard n > 0 else { return [] }
    return x.withUnsafeBufferPointer { buf in
        (0..<n).map { i in
            let frame = UnsafeBufferPointer(rebasing: buf[(i * hop)..<((i + 1) * hop)])
            let rms = Double(vDSP.rootMeanSquare(frame))
            return max(20 * log10(rms + 1e-9), dbFloor)
        }
    }
}

/// Centred moving average over k frames (k odd recommended). At the edges it
/// averages only the frames that exist, so the newest frame is not biased.
public func smooth(_ db: [Double], k: Int) -> [Double] {
    guard k > 1, !db.isEmpty else { return db }
    let half = k / 2
    return db.indices.map { i in
        let lo = max(0, i - half)
        let hi = min(db.count - 1, i + (k - 1 - half))
        return db[lo...hi].reduce(0, +) / Double(hi - lo + 1)
    }
}

/// Adaptive floor: a low percentile of the window.
public func noiseFloor(_ db: [Double], percentile p: Double = 10) -> Double {
    percentile(db, p) ?? dbFloor
}

/// True where the frame is clearly above the noise floor.
public func speechMask(_ db: [Double], floor: Double, marginDB: Double = 8) -> [Bool] {
    db.map { $0 > floor + marginDB }
}
