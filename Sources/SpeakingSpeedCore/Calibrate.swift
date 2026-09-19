// Derive personal thresholds from a short read-aloud at normal pace.

public let calibrationPassage = """
    When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. \
    The rainbow is a division of white light into many beautiful colors. These take the shape \
    of a long round arch, with its path high above, and its two ends apparently beyond the horizon. \
    There is, according to legend, a boiling pot of gold at one end. People look, but no one ever \
    finds it. When a man looks for something beyond his reach, his friends say he is looking for \
    the pot of gold at the end of the rainbow.
    """

public enum CalibrationError: Error, CustomStringConvertible {
    case tooFewSamples(Int)

    public var description: String {
        switch self {
        case .tooFewSamples(let n): "need at least 5 rate samples, got \(n); speak closer to the mic?"
        }
    }
}

/// The median rate at normal pace is the anchor. "Calm" sits below it on
/// purpose: the aim is to speak slower than habit.
public func thresholdsFromRates(_ rates: [Double]) throws -> Thresholds {
    guard rates.count >= 5, let anchor = median(rates) else {
        throw CalibrationError.tooFewSamples(rates.count)
    }
    return Thresholds(calmMaxRate: 0.9 * anchor, fastMinRate: 1.05 * anchor)
}
