# We built a live speaking-speed meter. Here's why we're hiding the number.

Written 2026-09-19, after one day with version 1. A draft for a blog post; the
research behind it is in `research.md`.

## What we built

The problem: I talk fast, especially when I'm excited about an idea, and I want
to speak in a calmer, clearer way. The obvious tool is a speedometer: something
that listens and tells you how fast you're going.

So that's what version 1 was. A small native Mac app that sits in the menu bar,
listens to the microphone, and shows your speaking rate: first in syllables per
second, then in words per minute, with a green, amber or red dot. No
transcription, nothing leaves the machine, about 16 MB of memory. It estimates
syllables from the loudness of your voice: each syllable has a vowel at its
core, and vowels are the loud bits.

It worked. After some tuning against recordings of me reading a script at
slow, normal and fast pace, the numbers matched the real counts to within about
5%. It was genuinely fun to watch.

And that's the problem.

## Lesson 1: "slow down" is the wrong target

When I recorded myself reading "slow", "normal" and "fast", the surprise was
*how* I changed pace. Going from normal to fast, I didn't say syllables much
faster. I stopped pausing. My talk time in a 30 s clip went up while the rate
of the syllables themselves barely moved.

That matches what speech therapists say: people who talk too fast don't need to
stretch their words, they need to **pause**. Speak a phrase, land the sentence,
pause, then the next one. Pauses are where the listener catches up and where you
decide what your next sentence is before you start it. The overall rate comes
down by itself.

So the thing to measure isn't really speed. It's **how long you go without a
pause**.

## Lesson 2: a live number becomes wallpaper

A number in the menu bar that updates twice a second is fascinating for about a
day. You watch it, you play with it, you try to push it up and down. Then you
stop seeing it, the same way you stop seeing the clock.

Worse, while you *are* watching it, it teaches you the wrong thing. Research on
motor learning (how we learn physical skills, including speech) has a name for
this: the **guidance effect**. Constant, immediate feedback makes you perform
better *while it's on* and learn *less*, because you lean on the signal instead
of building your own sense of "that was too fast". Take the signal away and the
improvement goes with it. What makes a skill stick is sparse feedback in the
moment plus a summary afterwards.

## Lesson 3: accurate and calm pull in opposite directions

We shortened the averaging window from 10 s to 5 s so the number would react
faster. It did, and it also jumped around, because real speech varies a lot
from one sentence to the next. A 10 s window is calmer but lags behind what
you're doing. There's no window length that is both instant and steady.

That was the clue that the number was the wrong thing to show. Feedback you act
on needs to be steady and rare. Feedback that reacts instantly is only useful for
curiosity.

## What version 2 does instead

- **A quiet dot, no number.** The menu bar shows a dot that changes only when
  there's something worth doing about it.
- **One live nudge that tells you what to do: "pause".** It appears when you've
  been talking for about 15 seconds without a real pause, and a small floating
  pill appears near the camera so you notice it on a call without looking away.
  It goes away as soon as you pause.
- **A slow "you've been fast for a while" signal**, based on a 20 to 30 second
  average, not on the jittery live number.
- **The live number is still there**, one click away in the menu, for when
  you're curious.
- **A summary after each conversation**, with one question: how did that feel?
  Calm, OK or rushed. Comparing your own sense with the numbers is how you build
  the internal feel that lasts. (Therapists call it self-monitoring. It's the
  single best predictor of the change carrying over into everyday life.)
- **Trends over days and weeks**, so the live nudges can fade out as you
  improve, and the summaries do the work.

The general lesson, beyond speaking: when you build a feedback tool, the
obvious display (the raw number, live) is often the one that works least. Start
from the behaviour you want, work out what cue would prompt it, and show as
little as you can get away with.
