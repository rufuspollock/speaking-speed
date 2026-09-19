// Window metrics from per-frame speech / nucleus flags.

public struct Metrics: Equatable, Sendable {
    public var windowS: Double
    public var phonationS: Double
    public var syllables: Int
    public var articulationRate: Double?  // syl / s of phonation
    public var speechRate: Double?        // syl / s of window
    public var pauses: Int
    public var meanPauseS: Double
    public var currentRunS: Double        // seconds of speech since last pause >= runPauseS

    public init(
        windowS: Double, phonationS: Double, syllables: Int, articulationRate: Double?,
        speechRate: Double?, pauses: Int, meanPauseS: Double, currentRunS: Double
    ) {
        self.windowS = windowS
        self.phonationS = phonationS
        self.syllables = syllables
        self.articulationRate = articulationRate
        self.speechRate = speechRate
        self.pauses = pauses
        self.meanPauseS = meanPauseS
        self.currentRunS = currentRunS
    }
}

/// Run-length encode -> [(value, length)].
func runs(_ flags: [Bool]) -> [(value: Bool, length: Int)] {
    var out: [(value: Bool, length: Int)] = []
    for f in flags {
        if let last = out.last, last.value == f {
            out[out.count - 1].length += 1
        } else {
            out.append((f, 1))
        }
    }
    return out
}

/// `currentRunS` includes short gaps (< runPauseS) inside the run, by design:
/// a 0.2 s breath does not end a "thought unit".
public func computeMetrics(
    speech: [Bool],
    nuclei: [Bool],
    frameS: Double,
    minPhonationS: Double = 1.0,
    pauseMinS: Double = 0.35,
    runPauseS: Double = 0.5
) -> Metrics {
    let windowS = Double(speech.count) * frameS
    let phonationS = Double(speech.count(where: { $0 })) * frameS
    let syllables = nuclei.count(where: { $0 })
    let art = phonationS >= minPhonationS ? Double(syllables) / phonationS : nil
    let spr = (windowS > 0 && art != nil) ? Double(syllables) / windowS : nil

    let rs = runs(speech)
    // Pauses: silent runs bounded by speech on both sides, long enough.
    let pauseLens = rs.indices
        .filter { k in !rs[k].value && k > 0 && k < rs.count - 1 }
        .map { Double(rs[$0].length) * frameS }
        .filter { $0 >= pauseMinS }
    // Current run: walk back from the end until a silent run >= runPauseS.
    var current = 0.0
    for r in rs.reversed() {
        let length = Double(r.length) * frameS
        if !r.value && length >= runPauseS { break }
        current += length
    }
    return Metrics(
        windowS: windowS,
        phonationS: phonationS,
        syllables: syllables,
        articulationRate: art,
        speechRate: spr,
        pauses: pauseLens.count,
        meanPauseS: pauseLens.isEmpty ? 0 : pauseLens.reduce(0, +) / Double(pauseLens.count),
        currentRunS: current
    )
}
