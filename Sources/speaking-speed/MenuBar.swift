// Menu-bar indicator: a quiet dot that changes only when there is something to
// act on (see Nudger). Live numbers live in the menu, one click away.
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
    private let cueItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let nowItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let trendItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let showNumberItem = NSMenuItem(title: "Show words per minute in menu bar", action: #selector(toggleShowNumber), keyEquivalent: "")
    private let floatingItem = NSMenuItem(title: "Floating nudges", action: #selector(toggleFloating), keyEquivalent: "")
    private var capture: Capture?
    private var pipeline: Pipeline?
    private var session: Session?
    private var smoother = ZoneSmoother()
    private var trend = TrendTracker()
    private var nudger = Nudger(runNudgeS: 15, fastMinRate: 4.5, cooldownS: 30)
    private var call: ConversationTracker?       // set between Start call and End call
    private var callStart: Date?
    private var timer: Timer?
    private let nudgePanel = NudgePanel()
    private var lastConversationID: UUID?
    private let callItem = NSMenuItem(title: "Start call", action: #selector(toggleCall), keyEquivalent: "c")
    private let rateMenuItem = NSMenuItem(title: "Rate last call", action: nil, keyEquivalent: "")

    init(cfg: Config) {
        self.cfg = cfg
        super.init()
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        setTitle(dot[.idle]!)
        resetTrackers()
        let menu = NSMenu()
        toggleItem.target = self
        callItem.target = self
        statusLine.isEnabled = false
        cueItem.isEnabled = false
        cueItem.isHidden = true
        nowItem.isEnabled = false
        trendItem.isEnabled = false
        nowItem.isHidden = true
        trendItem.isHidden = true
        showNumberItem.target = self
        showNumberItem.state = cfg.showNumberInMenuBar ? .on : .off
        floatingItem.target = self
        floatingItem.state = cfg.floatingNudge ? .on : .off
        lastSummary.isEnabled = false
        lastSummary.isHidden = true
        let rateMenu = NSMenu()
        for r in Rating.allCases {
            let i = NSMenuItem(title: r.rawValue.capitalized, action: #selector(rateLast(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = r.rawValue
            rateMenu.addItem(i)
        }
        rateMenuItem.submenu = rateMenu
        rateMenuItem.isHidden = true
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        autoListenItem.target = self
        autoListenItem.state = cfg.listenOnLaunch ? .on : .off
        loginItem.target = self
        // Login items need a real app bundle (scripts/install.sh), not `swift run`.
        loginItem.isHidden = Bundle.main.bundleURL.pathExtension != "app"
        refreshLoginItem()
        for i in [toggleItem, callItem, .separator(), cueItem, nowItem, trendItem, statusLine, lastSummary, rateMenuItem, .separator(),
                  showNumberItem, floatingItem, autoListenItem, loginItem, .separator(), quit] {
            menu.addItem(i)
        }
        item.menu = menu
    }

    @objc private func toggleAutoListen() {
        cfg.listenOnLaunch.toggle()
        autoListenItem.state = cfg.listenOnLaunch ? .on : .off
        do { try cfg.save() } catch { statusLine.title = "could not save config: \(error)" }
    }

    @objc private func toggleShowNumber() {
        cfg.showNumberInMenuBar.toggle()
        showNumberItem.state = cfg.showNumberInMenuBar ? .on : .off
        do { try cfg.save() } catch { statusLine.title = "could not save config: \(error)" }
    }

    @objc private func toggleFloating() {
        cfg.floatingNudge.toggle()
        floatingItem.state = cfg.floatingNudge ? .on : .off
        do { try cfg.save() } catch { statusLine.title = "could not save config: \(error)" }
    }

    /// Fresh state for each listening stretch.
    private func resetTrackers() {
        trend = TrendTracker(tauS: cfg.trendTauS, warmupS: cfg.trendWarmupS, resetAfterS: cfg.trendResetS)
        nudger = Nudger(config: cfg)
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

    /// Calls are explicit: summary and rating only for what you mark as a call.
    @objc private func toggleCall() {
        if call != nil { endCall(); return }
        if session == nil { start() }
        guard session != nil else { return }
        call = ConversationTracker(config: cfg)
        callStart = Date()
        callItem.title = "End call"
    }

    private func endCall(ask: Bool = true) {
        guard var c = call else { return }
        call = nil
        callStart = nil
        callItem.title = "Start call"
        guard let done = c.finish(now: Date()) else {
            if ask { showDialog("Not enough of your speech in that call to summarise.", buttons: ["OK"]) }
            return
        }
        let text = formatConversation(done, syllablesPerWord: cfg.syllablesPerWord, longRunS: cfg.runNudgeS)
        do { try ConversationLog(url: cfg.conversationsURL).append(done) } catch { statusLine.title = "\(error)" }
        lastConversationID = done.id
        lastSummary.title = "Last call: " + text
        lastSummary.isHidden = false
        rateMenuItem.title = "Rate last call"
        rateMenuItem.isHidden = false
        print(text)
        guard ask else { return }
        let ratings = Rating.allCases
        let i = showDialog("How did that call feel?", info: text,
                           buttons: ratings.map { $0.rawValue.capitalized } + ["Skip"])
        if i < ratings.count { rate(done.id, ratings[i]) }
    }

    /// Returns the index of the button clicked.
    @discardableResult
    private func showDialog(_ message: String, info: String = "", buttons: [String]) -> Int {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        for b in buttons { alert.addButton(withTitle: b) }
        NSApp.activate()
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
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
        resetTrackers()
        cueItem.isHidden = false
        nowItem.isHidden = false
        trendItem.isHidden = false
        toggleItem.title = "Stop listening"
        timer = Timer.scheduledTimer(
            timeInterval: cfg.tickS, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
    }

    private func stop(ask: Bool = true) {
        timer?.invalidate()
        timer = nil
        endCall(ask: ask)
        capture?.stop()
        capture = nil
        pipeline = nil
        guard let s = session else { return }
        session = nil
        print(formatSummary(s.close(), syllablesPerWord: cfg.syllablesPerWord))
        nudgePanel.hideIfShowing()
        setTitle(dot[.idle]!)
        toggleItem.title = "Start listening"
        statusLine.title = "idle"
        cueItem.isHidden = true
        nowItem.isHidden = true
        trendItem.isHidden = true
        item.button?.toolTip = "Speaking Speed: not listening"
    }

    @objc private func rateLast(_ sender: NSMenuItem) {
        guard let id = lastConversationID, let raw = sender.representedObject as? String,
              let r = Rating(rawValue: raw) else { return }
        rate(id, r)
    }

    private func rate(_ id: UUID, _ r: Rating) {
        do { try ConversationLog(url: cfg.conversationsURL).rate(id, r) } catch { statusLine.title = "\(error)" }
        if id == lastConversationID { rateMenuItem.title = "Rated: \(r.rawValue)" }
    }

    @objc private func tick() {
        guard let p = pipeline, let s = session else { return }
        let m = p.tick()
        let z = smoother.update(classify(m, cfg.thresholds))
        s.record(m, zone: z)                      // per-tick CSV unchanged
        let speaking = m.isSpeech(minSpeechS: cfg.minSpeechS)
        let avg = trend.update(speaking ? m.speakingRate : nil, dt: cfg.tickS)
        let u = nudger.update(m, trend: avg, now: Date().timeIntervalSinceReferenceDate)
        if u.onset && cfg.floatingNudge { nudgePanel.show(u.cue) }
        if u.cue < .slow { nudgePanel.hideIfShowing() }
        if var c = call {
            _ = c.update(m, cue: u.cue, nudgeShown: u.onset && cfg.floatingNudge, now: Date(), dt: cfg.tickS)
            call = c
        }
        if let t = callStart { callItem.title = "End call (\(Int(Date().timeIntervalSince(t) / 60)) min)" }
        func wpm(_ r: Double?) -> String { r.map { String(Int(cfg.wordsPerMinute($0).rounded())) } ?? "--" }
        let number = cfg.showNumberInMenuBar ? " \(wpm(m.speakingRate))" : ""
        setTitle(dot[u.cue]! + number)
        cueItem.title = explain(u.cue, run: m.currentRunS, avg: avg)
        item.button?.toolTip = cueItem.title
        nowItem.title = "Now: ~\(wpm(m.speakingRate)) wpm (last \(Int(cfg.windowS)) s)"
        trendItem.title = "Last \(Int(cfg.trendTauS)) s: ~\(wpm(avg)) wpm"
        statusLine.title = "Talking \(Int(m.currentRunS)) s without a pause · \(m.pauses) pauses in \(Int(cfg.historyS)) s"
    }

    /// What the dot means right now, in words.
    private func explain(_ cue: Cue, run: Double, avg: Double?) -> String {
        let wpm = avg.map { "~\(Int(cfg.wordsPerMinute($0).rounded())) wpm" } ?? "--"
        switch cue {
        case .idle: return "⚪ Listening; no speech right now"
        case .ok: return "🟢 Fine: pausing and pace both OK"
        case .pause: return "🟠 Pause: \(Int(run)) s without a break (orange from \(Int(cfg.runNudgeS)) s)"
        case .slow: return "🔴 Slow down: \(wpm) over the last \(Int(cfg.trendTauS)) s (red from \(Int(cfg.slowDownWPM)) wpm)"
        }
    }

    @objc func quit() {
        stop(ask: false)
        NSApp.terminate(nil)
    }
}

let dot: [Cue: String] = [.idle: "⚪", .ok: "🟢", .slow: "🔴", .pause: "🟠"]

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
