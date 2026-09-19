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
    public var speakingS: Double          // speech plus in-turn pauses (< turnGapS)
    public var speakingRate: Double?      // syl / s of speakingS: slows when you pause
    public var runPhonationS: Double      // voice within the current run (clicks have little)

    public init(
        windowS: Double, phonationS: Double, syllables: Int, articulationRate: Double?,
        speechRate: Double?, pauses: Int, meanPauseS: Double, currentRunS: Double,
        speakingS: Double = 0, speakingRate: Double? = nil, runPhonationS: Double? = nil
    ) {
        self.windowS = windowS
        self.phonationS = phonationS
        self.syllables = syllables
        self.articulationRate = articulationRate
        self.speechRate = speechRate
        self.pauses = pauses
        self.meanPauseS = meanPauseS
        self.currentRunS = currentRunS
        self.speakingS = speakingS
        self.speakingRate = speakingRate
        // Tests often leave it out: treat the whole run as voiced.
        self.runPhonationS = runPhonationS ?? currentRunS
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

/// Rates come from the last `rateWindowFrames` frames (all frames if nil), so
/// they respond quickly; pauses and the current run use the whole history.
/// `currentRunS` includes short gaps (< runPauseS) inside the run, by design:
/// a 0.2 s breath does not end a "thought unit".
public func computeMetrics(
    speech: [Bool],
    nuclei: [Bool],
    frameS: Double,
    minPhonationS: Double = 1.0,
    pauseMinS: Double = 0.35,
    runPauseS: Double = 0.5,
    turnGapS: Double = 2.0,
    rateWindowFrames: Int? = nil
) -> Metrics {
    let start = rateWindowFrames.map { max(0, speech.count - $0) } ?? 0
    let recent = Array(speech[start...])
    let windowS = Double(recent.count) * frameS
    let phonationS = Double(recent.count(where: { $0 })) * frameS
    let syllables = nuclei[start...].count(where: { $0 })
    let art = phonationS >= minPhonationS ? Double(syllables) / phonationS : nil
    let spr = (windowS > 0 && art != nil) ? Double(syllables) / windowS : nil

    let rs = runs(speech)
    // Pauses: silent runs bounded by speech on both sides, long enough.
    let pauseLens = rs.indices
        .filter { k in !rs[k].value && k > 0 && k < rs.count - 1 }
        .map { Double(rs[$0].length) * frameS }
        .filter { $0 >= pauseMinS }
    // Speaking time: speech plus the pauses inside a turn. Silences of
    // turnGapS or more (listening, thinking) and the window edges are excluded.
    let rr = runs(recent)
    let speakingS = rr.indices.reduce(0.0) { acc, k in
        let length = Double(rr[k].length) * frameS
        if rr[k].value { return acc + length }
        let interior = k > 0 && k < rr.count - 1
        return interior && length < turnGapS ? acc + length : acc
    }
    // Current run: walk back from the end until a silent run >= runPauseS.
    var current = 0.0, voiced = 0.0
    for r in rs.reversed() {
        let length = Double(r.length) * frameS
        if !r.value && length >= runPauseS { break }
        current += length
        if r.value { voiced += length }
    }
    return Metrics(
        windowS: windowS,
        phonationS: phonationS,
        syllables: syllables,
        articulationRate: art,
        speechRate: spr,
        pauses: pauseLens.count,
        meanPauseS: pauseLens.isEmpty ? 0 : pauseLens.reduce(0, +) / Double(pauseLens.count),
        currentRunS: current,
        speakingS: speakingS,
        speakingRate: art != nil && speakingS > 0 ? Double(syllables) / speakingS : nil,
        runPhonationS: voiced
    )
}
