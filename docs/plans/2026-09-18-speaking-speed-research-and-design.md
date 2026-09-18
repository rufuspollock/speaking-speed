# Speaking Speed: research and design

Date: 2026-09-18. Status: design, not yet built.

## 1. The question

Rufus wants to speak more slowly, in whole sentences, with more pauses,
especially on calls. Is a small local macOS app that gives live feedback a
good way to help? If so, how should it work and how do we build it?

## 2. What the coaching literature says

Short version: yes, in-the-moment feedback on rate helps, but the thing that
actually sticks is *pausing and chunking*, not "talk slower", and
feedback must be sparse enough that you do not tune it out.

- **Rate is best reduced via pauses, not stretched words.** Speech-language
  pathologists steer clients to "thought units" (a clause or sentence,
  then a pause) and stressing one word per unit, rather than slowing every
  syllable. Stretched speech sounds odd and people abandon it.
  ([Banter Speech](https://www.banterspeech.com.au/how-to-slow-down-your-speech-do-we-need-a-new-approach/),
  [Talk Slower](https://www.talkslower.com/blog/how-to-talk-slower-stop-talking-too-fast))
- **Delayed auditory feedback (DAF)** at 125–250 ms reliably slows speech
  while it is on, but carryover is poor and users refuse to use it in real
  conversation. Not recommended as the main tool; worth a 10-minute try.
  ([PMC dataset](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11803211/),
  [Wikipedia stuttering therapy](https://en.wikipedia.org/wiki/Stuttering_therapy))
- **Ambulatory biofeedback** (voice therapy) works when it targets
  carryover into daily life and uses motor-learning principles: reduced
  feedback frequency and delayed summary feedback, not a constant nag.
  ([PMC ambulatory voice biofeedback](https://pmc.ncbi.nlm.nih.gov/articles/PMC5548081/),
  [PubMed](https://pubmed.ncbi.nlm.nih.gov/28124070/))
- **Commercial tools** (Yoodli, Poised, Orai) do exactly this: listen to the
  system mic during calls, show a private nudge for pace and fillers, and
  give a post-call summary. So the product shape is validated; what is
  missing is a local, private, tunable version.
  ([Yoodli review](https://www.finalroundai.com/blog/yoodli-review-pros-cons))
- **Typical numbers.** Conversational English ≈ 150 words per minute (wpm);
  140–160 counts as average, > 160 fast. Articulation rate is more robust
  than wpm and needs no transcription: roughly 4–5 syllables/second in
  conversational English; a "calm" target is ≈ 3.5–4.
  ([VirtualSpeech](https://virtualspeech.com/blog/average-speaking-rate-words-per-minute))

### Design implications

1. Measure **pauses and run length** (seconds of speech since the last real
   pause) as first-class metrics, not just rate.
2. Two feedback channels: a **quiet live indicator** (menu bar colour,
   optional small overlay) with hysteresis so it only changes after a few
   seconds of sustained fast speech, and a **post-session summary**.
3. Feedback during **real conversations**, not a practice mode. Practice
   mode is cheap to add but is not the point.
4. Make thresholds **calibrated to Rufus**, not population averages.
5. "Whole sentences" needs words, so it is phase 2 (transcription). Phase 1
   gets a proxy: long runs without a pause.

## 3. Verdict: is the experiment worth doing?

Yes. Phase 1 is one to two days of work, fully local, mic-only, no
transcription, no distribution. The risk is low and the tool is the kind
Yoodli charges for, minus the cloud. Main caveats:

- Wear headphones on calls, otherwise the mic picks up the other party
  and the rate numbers are garbage.
- Live nudges lose their effect over weeks; the session summary and
  weekly trend are what will keep working.
- Syllable rate is a proxy. It does not know about sentences. Phase 2 does.

## 4. macOS implementation research

### Toolchain on this machine (checked 2026-09-18)

| Thing | State |
|---|---|
| macOS | 26.0.1 (Tahoe) |
| Xcode | not installed; only Command Line Tools |
| CLT SDK / Swift | MacOSX 14.4 SDK, Swift 5.10 |
| Homebrew Python | python@3.14 present but broken (`pyexpat` dyld mismatch against `/usr/lib/libexpat`), pip cannot run |
| uv | not installed |
| ffmpeg | installed |
| Terminal | Ghostty |

Consequence: anything needing the macOS 26 SDK (Apple's new on-device
`SpeechAnalyzer`) is blocked until Xcode 26 (≈ 15 GB) or matching CLT is
installed. Python is the fastest path, via `uv` with a managed 3.12.

### Audio capture

- Python `sounddevice` (PortAudio, `brew install portaudio`) gives a
  callback stream of float32 frames from the default input. Simple, robust.
- Mic permission (TCC) is granted to the **terminal app** (Ghostty) when
  a CLI process first opens the mic. No Info.plist needed for a CLI. If the
  app were ever bundled it would need `NSMicrophoneUsageDescription` and a
  stable signature, otherwise TCC forgets the grant on every rebuild.
  ([Apple forum](https://developer.apple.com/forums/thread/109759),
  [t3code issue](https://github.com/pingdotgg/t3code/issues/728))
- Capturing the *call* audio (other party) is not needed and not wanted.

### Rate estimation without transcription

de Jong & Wempe (2009) detect syllable nuclei as intensity peaks that are
at least 2 dB above the neighbouring dips and are voiced. Correlation with
human syllable counts is high; it is the standard tool for articulation
rate in phonetics. It is ~50 lines of numpy on a smoothed dB envelope.
([paper](https://www.fon.hum.uva.nl/archive/2009/2009-brm-JongWempe.pdf),
[Praat script site](https://sites.google.com/site/speechrate))

Metrics per rolling window (default 10 s, updated every 0.5 s):

- `phonation_s`: seconds where energy is above the adaptive noise floor
- `syllables`: nuclei count
- `articulation_rate = syllables / phonation_s` (syl/s)
- `speech_rate = syllables / window_s`
- `pauses`: gaps ≥ 0.35 s inside speech; `mean_pause_s`
- `current_run_s`: seconds since the last pause ≥ 0.5 s (the "breathless
  run" signal that matters most for sentence chunking)

### Transcription options (phase 2)

| Option | Pros | Cons |
|---|---|---|
| Apple `SpeechAnalyzer` (macOS 26, Swift) | on-device, fast, word timings, free | needs Xcode 26; Swift only; note `SFSpeechRecognizer` is broken on macOS 26 ([PR](https://github.com/djacobs/transcribe-audio/pull/1)) |
| `whisper-cpp` via Homebrew (`whisper-stream` binary) | installed with one command, local, decent English, no Xcode | ~1–3 s latency; fillers ("um") often dropped unless prompted; extra CPU |
| Cloud STT | best accuracy | privacy, cost, not needed |

Decision: phase 2 uses `whisper-stream` as a subprocess fed by the same mic
device; revisit Apple `SpeechAnalyzer` if Xcode 26 gets installed.

### UI

- Menu bar: `rumps` (thin wrapper over PyObjC `NSStatusItem`). Title text
  like `🟢 3.6` is enough for phase 1.
- Optional floating overlay: a PyObjC `NSPanel` (`nonactivatingPanel`,
  level `.floating`, `canJoinAllSpaces`), a 120×40 px pill in a corner. Phase
  1.5, only if the menu bar glyph proves too easy to ignore.
- Sound cue: off by default. A soft tick every N seconds of red is worth an
  experiment, but only with headphones.

## 5. Design

### Architecture

```
mic (sounddevice, 16 kHz mono, 20 ms frames)
  -> envelope.py   : RMS per frame -> dB -> smoothed envelope, adaptive noise floor, voiced/unvoiced mask
  -> nuclei.py     : peak picking on the envelope (de Jong & Wempe rules) -> nucleus timestamps
  -> metrics.py    : ring buffer of (t, is_speech, is_nucleus) -> window metrics
  -> zones.py      : metrics -> {calm, brisk, fast} with hysteresis
  -> ui/menubar.py : rumps app, updates title every 0.5 s; Start/Stop/Calibrate menu
  -> session.py    : appends one CSV row per 0.5 s tick; prints/writes summary on stop
config.toml in ~/.config/speaking-speed/ : thresholds, window, device
```

All DSP is pure functions over numpy arrays so it is unit-testable with
synthetic signals; only `capture.py` and `ui/` touch hardware.

### Zone rules (defaults, all in config)

| Zone | Rule |
|---|---|
| calm  | articulation_rate < 3.8 syl/s and current_run_s < 12 |
| brisk | 3.8 ≤ rate < 4.5, or run 12–20 s |
| fast  | rate ≥ 4.5, or run ≥ 20 s |

Hysteresis: zone may only get worse after the condition holds for 3
consecutive ticks (1.5 s) and may only improve after 4 ticks. Calibration
replaces the numbers with Rufus's own: `calm` upper bound = 0.9 × his
measured normal rate, `fast` lower bound = 1.05 × normal.

### Session summary (on Stop and in `speaking-speed report`)

- talk time, mean/95th-percentile articulation rate, % of ticks in each zone
- number of runs > 15 s and the longest run
- pauses per minute of speech
- one line vs the previous 7 sessions ("rate down 6 %, long runs 9 → 4")

### Out of scope for phase 1

Transcription, wpm, filler words, sentence completeness, any UI beyond
menu bar + optional overlay, bundling, signing, auto-start.

### Phases

1. **Rate + pause monitor** (this plan, `2026-09-18-speaking-speed-phase1-plan.md`).
2. **Words**: `whisper-stream` subprocess → wpm, filler count, sentence
   chunk length in words, run-on detection (> 30 words without a
   sentence-final pause). Post-session transcript saved locally.
3. **Review**: send transcript + metrics to Claude for a short coaching note
   (incomplete sentences, restarts, where the long runs were). Optional.
4. **Native**: rewrite in Swift with `SpeechAnalyzer` only if the Python
   version proves useful and Xcode 26 is installed.
