# Speaking Speed

A lightweight macOS menu-bar app that nudges you to pause when you talk too long without one, with the goal of slower, calmer speech. Everything runs locally; no audio is stored and nothing is transcribed.

## What it shows

The menu bar shows a single dot. It only changes when there is something to do about it:

| Dot | Means | Goes back when |
|---|---|---|
| ⚪ | nobody speaking (key clicks and bumps don't count) | you speak |
| 🟢 | speaking, all fine | |
| 🟠 + "pause" pill | you have talked for 15 s without a real pause | you pause |
| 🔴 + "slow down" pill | your average pace over the last 25 s or so is 220 wpm or more | the average drops 5 % below it, or you stop talking for 10 s |

The top line of the menu (and the dot's hover text) says in words what the colour means right now. The red average starts afresh after 10 s without speech and needs 10 s of new speech first, so an earlier fast patch never makes the dot red the moment you start talking.

The pill is a small floating label at the top centre of the screen, near the camera, so you notice it on a call without looking away. It doesn't take focus, shows over full-screen apps, and fades after a few seconds or as soon as the cue clears. A new pill appears at most once every 30 s; the dot still changes in between.

After each conversation (it ends after 2 minutes of silence, and needs at least 30 s of your speech), you get a notification: **How did that feel?** with Calm / OK / Rushed buttons and a one-line summary (minutes talking, words per minute, pauses per minute, longest stretch without a pause). Comparing your own sense with the numbers is how the feel for it builds. You can also rate from the menu.

### Why no number?

Version 1 showed live words per minute. It was fun for a day, then it became wallpaper, and while you watch it you learn less (the "guidance effect"). The behaviour that actually slows fast talkers down is pausing, so v2 nudges that and saves the numbers for a summary afterwards. The full story is in [`docs/v1-lessons.md`](docs/v1-lessons.md).

The numbers are still there, one click away in the menu:

- **Now**: words per minute over the last 5 s, estimated from the syllables the app hears (from the mic's loudness, no speech recognition), converted at 1.5 syllables per word (`syllablesPerWord`). Speaking time includes short pauses (under 2 s), so pausing more slows it down; longer silences, such as listening on a call, are left out. It is an estimate: formal or technical speech has longer words, so it reads high.
- **Last 25 s**: the slow average that drives the 🔴 cue.
- **Talking N s without a pause** (a real pause is ≥ 0.5 s), and pauses in the last 30 s.
- **Last conversation**: the summary line, and a submenu to rate it.

Tick **Show words per minute in menu bar** to put the live number back next to the dot.

## Install and run

Needs Xcode 26 or later (for Swift 6 and the macOS SDK).

```bash
scripts/install.sh    # builds a release, installs ~/Applications/Speaking Speed.app, opens it
```

It lives in the menu bar only (no Dock icon) and starts listening straight away. From its menu:

- **Start / Stop listening**: toggle at any time; each listening stretch is one session.
- **Show words per minute in menu bar**: the live number next to the dot (off by default).
- **Floating nudges**: turn the pill off; the dot still changes.
- **Listen when app starts**: turn off if you would rather start it by hand.
- **Open at login**: keep it running all the time.

Re-run `scripts/install.sh` after pulling changes. Then calibrate once to your own pace:

```bash
~/Applications/Speaking\ Speed.app/Contents/MacOS/speaking-speed calibrate   # read a passage at normal pace, ~45 s
```

The same binary has terminal commands (or use `swift run speaking-speed <command>` during development):

Commands:

| Command | What it does |
|---|---|
| `run` | Menu bar app from the terminal (notifications need the installed app). |
| `monitor` | Same metrics on one updating terminal line, plus noise floor and peak dB for tuning. |
| `record FILE [--seconds S]` | Save the mic to a WAV file. |
| `analyze FILE... [key=value...]` | Whole-file metrics for recorded audio; `key=value` overrides detector settings, e.g. `minDipDB=2`. |
| `calibrate [--seconds S]` | Sets your thresholds from a read-aloud at normal pace: calm is below 90 % of your normal rate, fast above 105 %. |
| `report [-n N]` | One-line summaries of recent sessions and conversations, with your ratings. |

The app asks for microphone access on first launch; terminal commands ask on behalf of your terminal app. If it never asks, check System Settings → Privacy & Security → Microphone.

Use headphones on calls, otherwise the other side's voice counts as yours.

## Files

- Config: `~/.config/speaking-speed/config.json` (written by `calibrate`; any key left out uses its default).
- Sessions: `~/.local/share/speaking-speed/sessions/*.csv`, one row per half-second tick.
- Conversations: `~/.local/share/speaking-speed/conversations.jsonl`, one summary per line, with your rating.

Nudge and conversation settings (seconds unless noted):

| Key | Default | |
|---|---|---|
| `runNudgeS` | 15 | talking this long without a pause shows "pause" |
| `slowDownWPM` | 220 | red when the slow average reaches this (words per minute; not changed by `calibrate`) |
| `minSpeechS` | 1 | seconds of voice in the last 5 s before it counts as speaking |
| `trendResetS` | 10 | silence after which the slow average starts afresh |
| `trendTauS` | 25 | time constant of the slow average behind "slow down" |
| `trendWarmupS` | 10 | seconds of speech before the slow average counts |
| `nudgeCooldownS` | 30 | minimum gap between pills |
| `conversationEndS` | 120 | silence that ends a conversation |
| `minConversationS` | 30 | less speech than this isn't summarised |
| `showNumberInMenuBar` | false | live words per minute next to the dot |
| `floatingNudge` | true | show the pill |
| `conversationsLog` | see above | where conversations are saved |

`calibrate` sets the calm / brisk / fast zones recorded in the session files from your read-aloud pace; conversation runs faster, so the red cue has its own threshold.

The rate is averaged over the last 5 s, so it takes a few seconds to follow a change of pace (`windowS`; shorter is quicker but jumpier). Nothing counts as speech unless the window gets louder than `minLoudDB` (default −35 dBFS); if your mic is quiet and the rate never appears, lower it. The detector defaults were tuned on the clips in `fixtures/`.

## More

Research write-up: `docs/research.md`. Design and plans: `docs/plans/`. Task tracking: beads (`bd ready`).
