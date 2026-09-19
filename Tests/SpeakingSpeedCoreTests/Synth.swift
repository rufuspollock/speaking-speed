// Synthetic audio for tests. 16 kHz mono Float.
import Foundation

let SR = 16000
let HOP = 320  // 20 ms at 16 kHz

func silence(_ seconds: Double) -> [Float] {
    [Float](repeating: 0, count: Int(Double(SR) * seconds))
}

func tone(_ seconds: Double, freq: Double = 220, amp: Double = 0.3) -> [Float] {
    let n = Int(Double(SR) * seconds)
    var y = (0..<n).map { Float(amp * sin(2 * .pi * freq * Double($0) / Double(SR))) }
    // short fade in/out so bursts have clean intensity dips between them
    let ramp = min(n / 4, Int(Double(SR) * 0.01))
    if ramp > 1 {
        for i in 0..<ramp {
            let w = Float(i) / Float(ramp - 1)
            y[i] *= w
            y[n - 1 - i] *= w
        }
    }
    return y
}

/// n tone bursts separated by short gaps: a crude "syllable" train.
func bursts(_ n: Int, on: Double = 0.12, off: Double = 0.08, amp: Double = 0.3) -> [Float] {
    var out: [Float] = []
    for i in 0..<n {
        out += tone(on, amp: amp)
        if i < n - 1 { out += silence(off) }
    }
    return out
}

/// Deterministic Gaussian noise (Box-Muller over a seeded LCG).
func noise(_ seconds: Double, amp: Double = 0.002, seed: UInt64 = 0) -> [Float] {
    var state = seed &+ 0x9E37_79B9_7F4A_7C15
    func uniform() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return (Double(state >> 11) + 0.5) / Double(1 << 53)
    }
    return (0..<Int(Double(SR) * seconds)).map { _ in
        Float(amp * sqrt(-2 * log(uniform())) * cos(2 * .pi * uniform()))
    }
}
