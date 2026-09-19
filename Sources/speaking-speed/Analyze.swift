// Offline analysis of an audio file: whole-file metrics, for tuning.
import AVFoundation
import SpeakingSpeedCore

func readMono(_ path: String) throws -> (samples: [Float], sampleRate: Double) {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = file.processingFormat
    let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buf)
    let samples = Array(UnsafeBufferPointer(start: buf.floatChannelData![0], count: Int(buf.frameLength)))
    return (samples, format.sampleRate)
}

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

func cmdAnalyze(_ args: [String]) {
    let paths = args.filter { !$0.contains("=") }
    let base = overriding(loadConfig(), with: args.filter { $0.contains("=") })
    for path in paths {
        do {
            let (x, sr) = try readMono(path)
            var cfg = base
            cfg.windowS = Double(x.count) / sr + 1
            let p = Pipeline(config: cfg, sampleRate: sr)
            p.push(x)
            let m = p.tick()
            func f(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "--" }
            print(String(format: "%@: %.1fs  talk %.1fs  speaking %.1fs  syllables %d  rate %@  articulation %@ syl/s  pauses %d  floor %.0f peak %.0f dB",
                         (path as NSString).lastPathComponent, Double(x.count) / sr, m.phonationS, m.speakingS,
                         m.syllables, f(m.speakingRate), f(m.articulationRate), m.pauses, p.lastFloorDB, p.lastPeakDB))
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
