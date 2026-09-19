# Speaking Speed Phase 1 Implementation Plan (Swift)

> Supersedes `2026-09-18-speaking-speed-phase1-plan.md` (Python). That file
> stays the reference for the DSP algorithms, test cases and thresholds; this
> plan says how each piece maps to Swift. Why Swift: design doc section 6.

**Goal:** unchanged. A local macOS menu-bar monitor that listens to the mic,
estimates articulation rate (syllables/second) and run length since the last
pause, shows a colour zone with hysteresis, and logs a per-session summary.
No transcription, no app bundle.

**Stack (verified 2026-09-19):** Xcode 27.0, Swift 6.4, macOS SDK 27. SwiftPM
only, run from the terminal: `swift build`, `swift test`, `swift run
speaking-speed <cmd>`. No third-party dependencies.

**Layout:**

```
Package.swift
Sources/SpeakingSpeedCore/     pure logic, no hardware, fully tested
  Envelope.swift   frameDB (vDSP RMS), smooth, noiseFloor (percentile), speechMask
  Nuclei.swift     findNuclei: port of scipy find_peaks (plateaus, distance, prominence)
  Metrics.swift    Metrics struct + computeMetrics (runs, pauses, current run)
  Zones.swift      Zone, Thresholds, classify, ZoneSmoother
  Config.swift     Codable config, JSON at ~/.config/speaking-speed/config.json
  Pipeline.swift   push(samples) / tick() ring buffer, lock-protected
  Session.swift    CSV log, Summary, summarize, loadSummaries, formatSummary
  Calibrate.swift  thresholdsFromRates, PASSAGE
  Stats.swift      median / percentile (numpy linear interpolation)
Sources/speaking-speed/        executable: hardware + UI
  main.swift       subcommands: monitor, run, calibrate, report
  Capture.swift    AVAudioEngine input tap -> Pipeline
  MenuBar.swift    NSStatusItem app, Timer tick
Tests/SpeakingSpeedCoreTests/  Swift Testing; Synth.swift + one file per module
```

**Differences from the Python plan:**

- Sample rate: no resampling. The pipeline takes the input node's native rate
  and uses `hop = round(sampleRate * 0.02)`, so frames stay 20 ms. Tests use
  16 kHz synthetic audio as before.
- Config is JSON (`Codable`, missing keys fall back to defaults) instead of
  TOML. `inputDevice` is deferred: capture uses the system default input.
- `find_peaks` is ported by hand in the same order scipy applies filters:
  local maxima (flat plateaus resolve to their middle), then `distance`
  (highest peaks win), then `prominence`.
- Menu bar is AppKit `NSStatusItem` with `.accessory` activation policy. No
  `UNUserNotificationCenter` (needs a bundle); the summary goes in the menu and
  is printed to stdout.
- Swift 6 language mode. `Pipeline` is `@unchecked Sendable` guarded by an
  `NSLock`; the audio tap thread pushes, the main thread ticks.

**Tasks** (beads epic `spkspd-l1s`; each is TDD: port the Python tests to
Swift Testing, see them fail, implement, see them pass, commit):

0. Scaffold: Package.swift, smoke test, `.gitignore` for `.build/`.
1. Envelope. 2. Nuclei. 3. Metrics. 4. Zones. 5. Config (JSON round trip,
   defaults when missing). 6. Pipeline (bounded ring buffer, syllable train
   gives speech rate 3 to 5, empty tick is unknown).
7. Capture + `monitor` command. Manual check: mic prompt appears for the
   terminal app, silent reads `--`, reading aloud reads 3.5 to 5.5 syl/s.
8. Session CSV + `report` (same three tests as Python).
9. Calibration (`thresholdsFromRates` tests; `calibrate` command saves config).
10. Menu bar (`run`): title `glyph rate [run]`, Start/Stop, status line,
    Quit. Manual check on a real call with headphones.
12. README + changelog.

Acceptance: as in the Python plan, with `swift test` green in place of
pytest, plus: resident memory of `speaking-speed run` while listening is
under 50 MB (check in Activity Monitor).
