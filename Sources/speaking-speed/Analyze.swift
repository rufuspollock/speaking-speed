// Offline analysis of an audio file: whole-file metrics, for tuning.
import AVFoundation
import SpeakingSpeedCore

/// Apply `key=value` overrides (numbers) to a config, via its JSON form.
func overriding(_ cfg: Config, with pairs: [String]) -> Config {
    guard !pairs.isEmpty else { return cfg }
    var dict = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(cfg)) as! [String: Any]
    for pair in pairs {
        let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
        guard kv.count == 2, let v = Double(kv[1]) else { fail("bad override \(pair), want key=number") }
        dict[kv[0]] = v
    }
    do {
        return try JSONDecoder().decode(Config.self, from: JSONSerialization.data(withJSONObject: dict))
    } catch {
        fail("bad override: \(error)")
    }
}

/// Replay a file tick by tick, as the live app sees it, once the window is full.
func slidingRates(_ path: String, _ cfg: Config) throws -> [Double] {
    let (x, sr) = try readMono(path)
    let p = Pipeline(config: cfg, sampleRate: sr)
    let chunk = Int(sr * cfg.tickS)
    var rates: [Double] = []
    var i = 0
    while i + chunk <= x.count {
        p.push(Array(x[i..<(i + chunk)]))
        i += chunk
        let m = p.tick()
        if Double(i) / sr >= cfg.windowS, let r = m.speakingRate { rates.append(r) }
    }
    return rates
}

func cmdAnalyze(_ args: [String]) {
    let paths = args.filter { !$0.contains("=") && !$0.hasPrefix("--") }
    let base = overriding(loadConfig(), with: args.filter { $0.contains("=") })
    if args.contains("--sliding") {
        for path in paths {
            do {
                let r = try slidingRates(path, base)
                let mean = r.reduce(0, +) / Double(max(r.count, 1))
                let sd = (r.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(max(r.count, 1))).squareRoot()
                print(String(format: "%@: window %.0fs  ticks %d  mean %.2f  sd %.2f  min %.2f  max %.2f",
                             (path as NSString).lastPathComponent, base.windowS, r.count, mean, sd,
                             r.min() ?? 0, r.max() ?? 0))
            } catch {
                print("\(path): \(error)")
            }
        }
        return
    }
    for path in paths {
        do {
            let (x, sr) = try readMono(path)
            var cfg = base
            cfg.windowS = Double(x.count) / sr + 1
            let p = Pipeline(config: cfg, sampleRate: sr)
            p.push(x)
            let m = p.tick()
            func f(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "--" }
            print(String(format: "%@: %.1fs  talk %.1fs  speaking %.1fs  syllables %d  rate %@ syl/s (~%.0f wpm)  articulation %@ syl/s  pauses %d  floor %.0f peak %.0f dB",
                         (path as NSString).lastPathComponent, Double(x.count) / sr, m.phonationS, m.speakingS,
                         m.syllables, f(m.speakingRate), base.wordsPerMinute(m.speakingRate ?? 0), f(m.articulationRate), m.pauses, p.lastFloorDB, p.lastPeakDB))
        } catch {
            print("\(path): \(error)")
        }
    }
}

/// Record the default mic to a WAV file until Ctrl-C or `seconds` elapse.
func cmdRecord(path: String, seconds: Double?) -> Never {
    do { try Capture.requestAccess() } catch { fail("\(error)") }
    let cap = Capture()
    let url = URL(fileURLWithPath: path)
    let file: AVAudioFile
    do {
        file = try AVAudioFile(forWriting: url, settings: cap.format.settings)
        try cap.start { buffer in try? file.write(from: buffer) }
    } catch {
        fail("\(error)")
    }
    let start = Date()
    print("recording to \(path)… Ctrl-C to stop")
    runUntilInterrupted(every: 0.5) {
        let t = Date().timeIntervalSince(start)
        print(String(format: "\r%5.1fs", t), terminator: "")
        fflush(stdout)
        if let seconds, t >= seconds { raise(SIGINT) }
    } onStop: {
        cap.stop()
        file.close()
        print("\nsaved \(path)")
    }
}
