// Syllable-nucleus detection on a dB envelope (de Jong & Wempe 2009, simplified).
// Peak picking ports scipy.signal.find_peaks with `distance` and `prominence`,
// applying the filters in scipy's order.

/// Frame indices of syllable nuclei.
///
/// A nucleus is a peak with prominence >= minDipDB (dips of at least that
/// depth on both sides), inside the speech mask, and at least minGapFrames
/// from its neighbours (the higher peak wins).
public func findNuclei(
    _ db: [Double],
    mask: [Bool],
    minDipDB: Double = 2,
    minGapFrames: Int = 4
) -> [Int] {
    guard db.count >= 3, let lowest = db.min() else { return [] }
    // Push non-speech frames down so peaks cannot form there.
    let work = zip(db, mask).map { $1 ? $0 : lowest - 20 }
    var peaks = localMaxima(work)
    peaks = selectByDistance(peaks, in: work, distance: minGapFrames)
    peaks = peaks.filter { prominence(of: $0, in: work) >= minDipDB }
    return peaks.filter { mask[$0] }
}

/// Strict local maxima; a flat plateau counts once, at its middle.
func localMaxima(_ x: [Double]) -> [Int] {
    var peaks: [Int] = []
    var i = 1
    let last = x.count - 1
    while i < last {
        if x[i - 1] < x[i] {
            var ahead = i + 1
            while ahead < last && x[ahead] == x[i] { ahead += 1 }
            if x[ahead] < x[i] {
                peaks.append((i + ahead - 1) / 2)
                i = ahead
            }
        }
        i += 1
    }
    return peaks
}

/// Drop peaks closer than `distance` to a higher peak.
func selectByDistance(_ peaks: [Int], in x: [Double], distance: Int) -> [Int] {
    guard distance > 1, peaks.count > 1 else { return peaks }
    var keep = [Bool](repeating: true, count: peaks.count)
    // Highest first; ties broken towards the later peak, as scipy's argsort walk does.
    let order = peaks.indices.sorted { (x[peaks[$0]], $0) > (x[peaks[$1]], $1) }
    for j in order where keep[j] {
        var k = j - 1
        while k >= 0 && peaks[j] - peaks[k] < distance { keep[k] = false; k -= 1 }
        k = j + 1
        while k < peaks.count && peaks[k] - peaks[j] < distance { keep[k] = false; k += 1 }
    }
    return peaks.indices.filter { keep[$0] }.map { peaks[$0] }
}

/// Height of a peak above the higher of the two lowest points reachable on
/// each side before meeting higher ground.
func prominence(of peak: Int, in x: [Double]) -> Double {
    var leftMin = x[peak]
    var i = peak
    while i >= 0 && x[i] <= x[peak] { leftMin = min(leftMin, x[i]); i -= 1 }
    var rightMin = x[peak]
    i = peak
    while i < x.count && x[i] <= x[peak] { rightMin = min(rightMin, x[i]); i += 1 }
    return x[peak] - max(leftMin, rightMin)
}
