# Speech fixtures

Real read-aloud clips with known syllable counts, used to tune and regression-test the detector (`swift test`, and `speaking-speed analyze fixtures/*.wav`).

- Speaker: Rufus. Recorded 2026-09-19 on the MacBook's built-in mic in a noisy room (no headphones), 30 s each, with `speaking-speed record`. Converted to 16 kHz 16-bit mono.
- Each clip reads `script.md` from the start at the given pace and stops mid-script. `clips.json` gives the last words reached and the true word and syllable counts up to that point (syllables counted by dictionary plus a vowel-group rule, about ±3 %).
- True speaking rate is roughly `syllables / 30 s` (slow 3.6, normal 4.5, fast 5.0 syl/s); it understates slightly because the clips include a little lead-in silence.
- These are a hard case: noisy room, laptop mic. A call on a headset should be easier.

To add clips: record with `speaking-speed record fixtures/NAME.wav --seconds 30`, convert with `afconvert -f WAVE -d LEI16@16000 -c 1`, note where you stopped, and add a row to `clips.json`.
