# Speaking Speed

A lightweight macOS menu-bar app that gives live feedback on speaking speed, with the goal of encouraging slower, calmer speech. Everything runs locally; no audio is stored and nothing is transcribed.

## What it measures

- **Speaking rate**: syllables per second of speaking time, estimated from the mic's loudness envelope (no speech recognition). Speaking time includes your short pauses (under 2 s), so pausing more slows the number down; longer silences, such as listening on a call, are left out.
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
| `record FILE [--seconds S]` | Save the mic to a WAV file. |
| `analyze FILE... [key=value...]` | Whole-file metrics for recorded audio; `key=value` overrides detector settings, e.g. `minDipDB=2`. |
| `calibrate [--seconds S]` | Sets your thresholds from a read-aloud at normal pace: calm is below 90 % of your normal rate, fast above 105 %. |
| `report [-n N]` | One-line summaries of recent sessions. |

The first run asks for microphone access for your terminal app. If it never asks, check System Settings → Privacy & Security → Microphone.

Use headphones on calls, otherwise the other side's voice counts as yours.

## Files

- Config: `~/.config/speaking-speed/config.json` (written by `calibrate`; any key left out uses its default).
- Sessions: `~/.local/share/speaking-speed/sessions/*.csv`, one row per half-second tick.

The rate is averaged over the last 10 s, so it takes a few seconds to follow a change of pace. Nothing counts as speech unless the window gets louder than `minLoudDB` (default −35 dBFS); if your mic is quiet and the rate never appears, lower it. The detector defaults were tuned on the clips in `fixtures/`.

## More

Research write-up: `docs/research.md`. Design and plans: `docs/plans/`. Task tracking: beads (`bd ready`).
