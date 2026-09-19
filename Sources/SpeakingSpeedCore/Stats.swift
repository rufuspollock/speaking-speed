/// Percentile with linear interpolation between closest ranks (numpy's default).
public func percentile(_ values: [Double], _ p: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    let rank = p / 100 * Double(s.count - 1)
    let lo = Int(rank.rounded(.down))
    let hi = min(lo + 1, s.count - 1)
    return s[lo] + (s[hi] - s[lo]) * (rank - Double(lo))
}

public func median(_ values: [Double]) -> Double? {
    percentile(values, 50)
}
