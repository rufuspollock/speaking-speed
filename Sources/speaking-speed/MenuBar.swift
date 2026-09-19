// Menu-bar indicator: glyph + rate (+ run length when long), Start/Stop, Quit.
import AppKit
import ServiceManagement
import SpeakingSpeedCore

@MainActor
final class MenuBarController: NSObject {
    private var cfg: Config
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let toggleItem = NSMenuItem(title: "Start listening", action: #selector(toggle), keyEquivalent: "s")
    private let statusLine = NSMenuItem(title: "idle", action: nil, keyEquivalent: "")
    private let lastSummary = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let autoListenItem = NSMenuItem(title: "Listen when app starts", action: #selector(toggleAutoListen), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at login", action: #selector(toggleLogin), keyEquivalent: "")
    private var capture: Capture?
    private var pipeline: Pipeline?
    private var session: Session?
    private var smoother = ZoneSmoother()
    private var timer: Timer?

    init(cfg: Config) {
        self.cfg = cfg
        super.init()
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        setTitle("⚪ --")
        let menu = NSMenu()
        toggleItem.target = self
        statusLine.isEnabled = false
        lastSummary.isEnabled = false
        lastSummary.isHidden = true
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        autoListenItem.target = self
        autoListenItem.state = cfg.listenOnLaunch ? .on : .off
        loginItem.target = self
        // Login items need a real app bundle (scripts/install.sh), not `swift run`.
        loginItem.isHidden = Bundle.main.bundleURL.pathExtension != "app"
        refreshLoginItem()
        for i in [toggleItem, statusLine, lastSummary, .separator(), autoListenItem, loginItem, .separator(), quit] {
            menu.addItem(i)
        }
        item.menu = menu
    }

    @objc private func toggleAutoListen() {
        cfg.listenOnLaunch.toggle()
        autoListenItem.state = cfg.listenOnLaunch ? .on : .off
        do { try cfg.save() } catch { statusLine.title = "could not save config: \(error)" }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            statusLine.title = "login item: \(error.localizedDescription)"
        }
        refreshLoginItem()
    }

    private func refreshLoginItem() {
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func setTitle(_ s: String) {
        item.button?.title = s
    }

    @objc func toggle() {
        if session == nil { start() } else { stop() }
    }

    private func start() {
        do {
            try Capture.requestAccess()
            let cap = Capture()
            let p = Pipeline(config: cfg, sampleRate: cap.sampleRate)
            try cap.start(into: p)
            session = try Session(dir: cfg.sessionsURL, tickS: cfg.tickS)
            capture = cap
            pipeline = p
        } catch {
            statusLine.title = "\(error)"
            return
        }
        smoother = ZoneSmoother()
        toggleItem.title = "Stop listening"
        timer = Timer.scheduledTimer(
            timeInterval: cfg.tickS, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        capture?.stop()
        capture = nil
        pipeline = nil
        guard let s = session else { return }
        session = nil
        let summary = formatSummary(s.close())
        print(summary)
        setTitle("⚪ --")
        toggleItem.title = "Start listening"
        statusLine.title = "idle"
        lastSummary.title = "Last: " + summary
        lastSummary.isHidden = false
    }

    @objc private func tick() {
        guard let p = pipeline, let s = session else { return }
        let m = p.tick()
        let z = smoother.update(classify(m, cfg.thresholds))
        s.record(m, zone: z)
        let rate = m.speakingRate.map { String(format: "%.1f", $0) } ?? "--"
        let run = m.currentRunS >= cfg.thresholds.calmMaxRunS ? " \(Int(m.currentRunS))s" : ""
        setTitle("\(glyph[z]!) \(rate)\(run)")
        statusLine.title = "rate \(rate) syl/s · run \(Int(m.currentRunS))s · pauses \(m.pauses)"
    }

    @objc func quit() {
        stop()
        NSApp.terminate(nil)
    }
}

@MainActor
func runMenuBar(_ cfg: Config, startListening: Bool) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let controller = MenuBarController(cfg: cfg)
    if startListening { controller.toggle() }
    // Ctrl-C in the terminal closes the session cleanly.
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler { MainActor.assumeIsolated { controller.quit() } }
    sigint.resume()
    print("menu bar running; Ctrl-C or Quit to stop")
    withExtendedLifetime((controller, sigint)) { app.run() }
    exit(0)
}
