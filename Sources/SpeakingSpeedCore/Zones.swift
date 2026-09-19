// Map metrics to a colour zone, with hysteresis so the indicator is calm.

public enum Zone: Int, Comparable, Sendable {
    case unknown = -1
    case calm = 0
    case brisk = 1
    case fast = 2

    public static func < (a: Zone, b: Zone) -> Bool { a.rawValue < b.rawValue }
}

public struct Thresholds: Codable, Equatable, Sendable {
    public var calmMaxRate = 3.8
    public var fastMinRate = 4.5
    public var calmMaxRunS = 12.0
    public var fastMinRunS = 20.0

    public init(calmMaxRate: Double = 3.8, fastMinRate: Double = 4.5,
                calmMaxRunS: Double = 12.0, fastMinRunS: Double = 20.0) {
        self.calmMaxRate = calmMaxRate
        self.fastMinRate = fastMinRate
        self.calmMaxRunS = calmMaxRunS
        self.fastMinRunS = fastMinRunS
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Thresholds()
        calmMaxRate = try c.decodeIfPresent(Double.self, forKey: .calmMaxRate) ?? d.calmMaxRate
        fastMinRate = try c.decodeIfPresent(Double.self, forKey: .fastMinRate) ?? d.fastMinRate
        calmMaxRunS = try c.decodeIfPresent(Double.self, forKey: .calmMaxRunS) ?? d.calmMaxRunS
        fastMinRunS = try c.decodeIfPresent(Double.self, forKey: .fastMinRunS) ?? d.fastMinRunS
    }
}

public func classify(_ m: Metrics, _ t: Thresholds) -> Zone {
    guard let rate = m.articulationRate else { return .unknown }
    let byRate: Zone = rate >= t.fastMinRate ? .fast : rate >= t.calmMaxRate ? .brisk : .calm
    let run = m.currentRunS
    let byRun: Zone = run >= t.fastMinRunS ? .fast : run >= t.calmMaxRunS ? .brisk : .calm
    return max(byRate, byRun)
}

/// Only change zone after the new zone has held for N consecutive ticks.
public struct ZoneSmoother: Sendable {
    public let worsenTicks: Int
    public let improveTicks: Int
    public private(set) var current: Zone = .calm
    private var candidate: Zone = .calm
    private var count = 0

    public init(worsenTicks: Int = 3, improveTicks: Int = 4) {
        self.worsenTicks = worsenTicks
        self.improveTicks = improveTicks
    }

    public mutating func update(_ raw: Zone) -> Zone {
        if raw == .unknown { return current }
        if raw == current {
            candidate = raw
            count = 0
            return current
        }
        if raw == candidate {
            count += 1
        } else {
            candidate = raw
            count = 1
        }
        let needed = raw > current ? worsenTicks : improveTicks
        if count >= needed {
            current = raw
            count = 0
        }
        return current
    }
}
