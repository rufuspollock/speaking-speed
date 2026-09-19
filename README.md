# Speaking Speed

A lightweight macOS menu-bar app that gives live feedback on speaking speed, with the goal of encouraging slower, calmer speech. Everything runs locally; no audio is stored and nothing is transcribed.

## What it measures

- **Articulation rate**: syllables per second while you are actually talking (pauses excluded), estimated from the mic's loudness envelope. No speech recognition.
- **Run length**: seconds of talk since your last real pause (≥ 0.5 s). Long unbroken runs push the zone up even at a calm rate.
- **Pauses**: count and mean length over the last 10 s.

These combine into a zone: 🟢 calm, 🟡 brisk, 🔴 fast. The zone only changes after it has held for a couple of ticks, so the indicator stays calm too.

## Install and run

Needs Xcode 26 or later (for Swift 6 and the macOS SDK).

```bash
swift build -c release
.build/release/speaking-speed calibrate   # read a passage at your normal pace, ~45 s
.build/release/speaking-speed run --start # menu bar indicator, listening at once
```

Commands:

| Command | What it does |
|---|---|
| `run [--start]` | Menu bar indicator. Title is `zone rate [run]`; menu has Start/Stop, live status, last session summary, Quit. |
| `monitor` | Same metrics on one updating terminal line, plus noise floor and peak dB for tuning. |
| `calibrate [--seconds S]` | Sets your thresholds from a read-aloud at normal pace: calm is below 90 % of your normal rate, fast above 105 %. |
| `report [-n N]` | One-line summaries of recent sessions. |

The first run asks for microphone access for your terminal app. If it never asks, check System Settings → Privacy & Security → Microphone.

Use headphones on calls, otherwise the other side's voice counts as yours.

## Files

- Config: `~/.config/speaking-speed/config.json` (written by `calibrate`; any key left out uses its default).
- Sessions: `~/.local/share/speaking-speed/sessions/*.csv`, one row per half-second tick.

If the rate reads high while you are silent, raise `speechMarginDB` (default 8) in the config.

## More

Research write-up: `docs/research.md`. Design and plans: `docs/plans/`. Task tracking: beads (`bd ready`).
