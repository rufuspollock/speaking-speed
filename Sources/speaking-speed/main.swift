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
    print("listening at \(Int(cap.sampleRate)) Hz… Ctrl-C to stop")
    runUntilInterrupted(every: cfg.tickS) {
        let m = p.tick()
        let z = smoother.update(classify(m, cfg.thresholds))
        let rate = m.articulationRate.map { String(format: "%5.2f", $0) } ?? "  -- "
        let line = String(
            format: "%@ rate %@ syl/s  run %5.1fs  pauses %2d  talk %4.1f/%.0fs  floor %4.0f peak %4.0f dB   ",
            glyph[z]!, rate, m.currentRunS, m.pauses, m.phonationS, m.windowS, p.lastFloorDB, p.lastPeakDB)
        print("\r" + line, terminator: "")
        fflush(stdout)
    } onStop: {
        cap.stop()
        print()
    }
}

let usage = """
    usage: speaking-speed <command>
      monitor     print live metrics in the terminal
    """

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "monitor": cmdMonitor()
case "--version": print(version)
default: fail(usage)
}
