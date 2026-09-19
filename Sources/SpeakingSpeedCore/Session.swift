// Per-session CSV log and summary.
import Foundation

let csvFields = ["t", "zone", "speaking_rate", "articulation_rate", "current_run_s", "pauses",
                 "phonation_s", "syllables", "window_s", "run_phonation_s"]

public struct Summary: Equatable, Sendable {
    public var name: String
    public var ticks: Int
    public var talkS: Double  // approximate: windows overlap, good enough for trend
    public var medianRate: Double?
    public var p95Rate: Double?
    public var pctCalm: Double
    public var pctBrisk: Double
    public var pctFast: Double
    public var longestRunS: Double
    public var runsOver15s: Int
}

public func summarize(_ rows: [Metrics], zones: [Zone], tickS: Double, name: String = "") -> Summary {
    let rates = rows.compactMap(\.speakingRate)
    let n = Double(max(rows.count, 1))
    var runsOver = 0
    var above = false
    for r in rows {
        if r.currentRunS >= 15 && !above { runsOver += 1 }
        above = r.currentRunS >= 15
    }
    return Summary(
        name: name,
        ticks: rows.count,
        talkS: rows.reduce(0) { $0 + ($1.windowS > 0 ? $1.phonationS / $1.windowS : 0) } * tickS,
        medianRate: median(rates),
        p95Rate: percentile(rates, 95),
        pctCalm: Double(zones.count(where: { $0 == .calm })) / n,
        pctBrisk: Double(zones.count(where: { $0 == .brisk })) / n,
        pctFast: Double(zones.count(where: { $0 == .fast })) / n,
        longestRunS: rows.map(\.currentRunS).max() ?? 0,
        runsOver15s: runsOver
    )
}

/// Appends one CSV row per tick as it goes, so a crash loses nothing.
public final class Session {
    public let name: String
    public let url: URL
    public let tickS: Double
    private var rows: [Metrics] = []
    private var zones: [Zone] = []
    private let handle: FileHandle

    public init(dir: URL, tickS: Double) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        name = f.string(from: Date())
        url = dir.appendingPathComponent("\(name).csv")
        self.tickS = tickS
        try Data((csvFields.joined(separator: ",") + "\n").utf8).write(to: url)
        handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
    }

    public func record(_ m: Metrics, zone: Zone) {
        rows.append(m)
        zones.append(zone)
        let cells = [
            String(format: "%.1f", Double(rows.count) * tickS),
            String(zone.rawValue),
            m.speakingRate.map { String(format: "%.3f", $0) } ?? "",
            m.articulationRate.map { String(format: "%.3f", $0) } ?? "",
            String(format: "%.2f", m.currentRunS),
            String(m.pauses),
            String(format: "%.2f", m.phonationS),
            String(m.syllables),
            String(format: "%.1f", m.windowS),
            String(format: "%.2f", m.runPhonationS),
        ]
        handle.write(Data((cells.joined(separator: ",") + "\n").utf8))
    }

    public func close() -> Summary {
        try? handle.close()
        return summarize(rows, zones: zones, tickS: tickS, name: name)
    }
}

public func loadSummaries(dir: URL) throws -> [Summary] {
    guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
    let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        .filter { $0.hasSuffix(".csv") }.sorted()
    return try files.map { file in
        let lines = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
            .split(separator: "\n").map { $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init) }
        guard let header = lines.first else { return summarize([], zones: [], tickS: 0.5) }
        let col = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        func num(_ r: [String], _ k: String) -> Double? { col[k].flatMap { Double(r[$0]) } }
        var rows: [Metrics] = []
        var zones: [Zone] = []
        for r in lines.dropFirst() where r.count == header.count {
            rows.append(Metrics(
                windowS: num(r, "window_s") ?? 10, phonationS: num(r, "phonation_s") ?? 0,
                syllables: Int(num(r, "syllables") ?? 0), articulationRate: num(r, "articulation_rate"),
                speechRate: nil, pauses: Int(num(r, "pauses") ?? 0), meanPauseS: 0,
                currentRunS: num(r, "current_run_s") ?? 0,
                // Sessions before 2026-09-19 only logged articulation rate.
                speakingRate: col["speaking_rate"] != nil ? num(r, "speaking_rate") : num(r, "articulation_rate")))
            zones.append(Zone(rawValue: Int(num(r, "zone") ?? -1)) ?? .unknown)
        }
        // First row's t is one tick.
        let tickS = lines.dropFirst().first.flatMap { num($0, "t") } ?? 0.5
        return summarize(rows, zones: zones, tickS: tickS, name: String(file.dropLast(4)))
    }
}

public func formatSummary(_ s: Summary, syllablesPerWord: Double = Config().syllablesPerWord) -> String {
    func wpm(_ r: Double) -> Int { Int((r * 60 / syllablesPerWord).rounded()) }
    let rate = s.medianRate.map { "\(wpm($0)) wpm (p95 \(wpm(s.p95Rate ?? 0)))" } ?? "--"
    func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
    return "\(s.name): talk \(String(format: "%.1f", s.talkS / 60)) min · rate \(rate) · "
        + "calm \(pct(s.pctCalm)) brisk \(pct(s.pctBrisk)) fast \(pct(s.pctFast)) · "
        + "longest run \(Int(s.longestRunS.rounded()))s · runs>15s \(s.runsOver15s)"
}
