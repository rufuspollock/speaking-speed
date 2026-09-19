// CLI entry: speaking-speed <command>.
import Foundation
import SpeakingSpeedCore

let glyph: [Zone: String] = [.unknown: "⚪", .calm: "🟢", .brisk: "🟡", .fast: "🔴"]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func loadConfig() -> Config {
    do { return try Config.load() } catch { fail("bad config at \(Config.defaultPath.path): \(error)") }
}

/// Run `body` on the main queue until Ctrl-C, then `onStop`, then exit.
func runUntilInterrupted(every seconds: Double, _ body: @escaping () -> Void, onStop: @escaping () -> Void) -> Never {
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
        onStop()
        exit(0)
    }
    sigint.resume()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + seconds, repeating: seconds)
    timer.setEventHandler(handler: body)
    timer.resume()
    withExtendedLifetime((sigint, timer)) { dispatchMain() }
}

func startListening(_ cfg: Config) -> (Capture, Pipeline) {
    do {
        try Capture.requestAccess()
        let cap = Capture()
        let p = Pipeline(config: cfg, sampleRate: cap.sampleRate)
        try cap.start(into: p)
        return (cap, p)
    } catch {
        fail("\(error)")
    }
}

func cmdMonitor() -> Never {
    let cfg = loadConfig()
    let (cap, p) = startListening(cfg)
    var smoother = ZoneSmoother()
    let session: Session
    do { session = try Session(dir: cfg.sessionsURL, tickS: cfg.tickS) } catch { fail("\(error)") }
    print("listening at \(Int(cap.sampleRate)) Hz… Ctrl-C to stop")
    runUntilInterrupted(every: cfg.tickS) {
        let m = p.tick()
        let z = smoother.update(classify(m, cfg.thresholds))
        session.record(m, zone: z)
        let rate = m.speakingRate.map { String(format: "%3.0f wpm (%.2f syl/s)", cfg.wordsPerMinute($0), $0) } ?? " -- wpm"
        let line = String(
            format: "%@ %@  run %5.1fs  pauses %2d  talk %4.1f/%.0fs  floor %4.0f peak %4.0f dB   ",
            glyph[z]!, rate, m.currentRunS, m.pauses, m.phonationS, m.windowS, p.lastFloorDB, p.lastPeakDB)
        print("\r" + line, terminator: "")
        fflush(stdout)
    } onStop: {
        cap.stop()
        print()
        print(formatSummary(session.close(), syllablesPerWord: cfg.syllablesPerWord))
    }
}

func cmdCalibrate(seconds: Double) -> Never {
    var cfg = loadConfig()
    print("Read this aloud at your NORMAL pace. Recording starts in 3 s.\n")
    print(calibrationPassage + "\n")
    Thread.sleep(forTimeInterval: 3)
    let (cap, p) = startListening(cfg)
    var rates: [Double] = []
    let start = Date()
    func finish() -> Never {
        cap.stop()
        print()
        do {
            let t = try thresholdsFromRates(rates)
            cfg.thresholds.calmMaxRate = t.calmMaxRate
            cfg.thresholds.fastMinRate = t.fastMinRate
            try cfg.save()
            let w = cfg.wordsPerMinute
            let normal = median(rates)!
            print(String(format: "normal pace ~%.0f wpm (%.2f syl/s) → calm below %.0f wpm, fast from %.0f wpm. Saved to %@",
                         w(normal), normal, w(t.calmMaxRate), w(t.fastMinRate), Config.defaultPath.path))
            exit(0)
        } catch {
            fail("\(error)")
        }
    }
    runUntilInterrupted(every: cfg.tickS) {
        let m = p.tick()
        if let r = m.speakingRate, m.phonationS >= 3 { rates.append(r) }
        let left = seconds - Date().timeIntervalSince(start)
        print(String(format: "\r%4.0fs left  samples %3d", max(left, 0), rates.count), terminator: "")
        fflush(stdout)
        if left <= 0 { finish() }
    } onStop: {
        finish()
    }
}

func cmdReport(n: Int) {
    let cfg = loadConfig()
    do {
        for s in try loadSummaries(dir: cfg.sessionsURL).suffix(n) {
            print(formatSummary(s, syllablesPerWord: cfg.syllablesPerWord))
        }
    } catch {
        fail("\(error)")
    }
}

let usage = """
    usage: speaking-speed <command>
      run [--start]   menu bar app (--start: begin listening at once)
      monitor     print live metrics in the terminal
      calibrate [--seconds S]   read a passage to set personal thresholds (default 45 s)
      record FILE [--seconds S]   save the mic to a WAV file
      analyze FILE...   whole-file metrics for recorded audio
      report [-n N]   summaries of the last N sessions (default 10)
    """

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "run":
    let cfg = loadConfig()
    runMenuBar(cfg, startListening: args.contains("--start") || cfg.listenOnLaunch)
case nil where Bundle.main.bundleURL.pathExtension == "app":
    // Launched as Speaking Speed.app (Finder, login item).
    let cfg = loadConfig()
    runMenuBar(cfg, startListening: cfg.listenOnLaunch)
case "monitor": cmdMonitor()
case "calibrate":
    cmdCalibrate(seconds: args.count == 3 && args.dropFirst().first == "--seconds" ? Double(args.last!) ?? 45 : 45)
case "record":
    guard args.count >= 2 else { fail(usage) }
    let a = Array(args)
    cmdRecord(path: a[1], seconds: a.count == 4 && a[2] == "--seconds" ? Double(a[3]) : nil)
case "analyze":
    cmdAnalyze(Array(args.dropFirst()))
case "report":
    cmdReport(n: args.count == 3 && args.dropFirst().first == "-n" ? Int(args.last!) ?? 10 : 10)
case "--version": print(version)
default: fail(usage)
}
