# Speaking slower: what the evidence says, and what to do about it

Written 2026-09-18. Purpose: the research base for the Speaking Speed
project, written so it can become a blog post or landing-page copy later.
Sources at the end. Claims are hedged where the underlying evidence is
thin or comes from marketing copy rather than studies.

## TL;DR

1. "Speak slower" is the wrong instruction. Rate comes down as a
   by-product of **pausing more and speaking in shorter chunks**, and that
   is also what listeners actually notice. Stretching every syllable
   sounds odd and nobody keeps it up.
2. Normal conversational English runs around 150 words per minute and
   about 4 to 5 syllables per second. Fast talkers sit at 180 to 230 wpm.
   The interesting number is not the average but the **run**: how long
   you go without a real pause.
3. Live feedback helps in the moment. It does not make the change stick
   by itself. Motor-learning research is clear that **frequent, immediate
   feedback improves performance now and hurts retention later**; sparse
   feedback plus summary review is what transfers.
4. The clinical version of this problem (cluttering) is treated with
   exactly three things: deliberate pausing, self-monitoring, and clear
   articulation. Not with talking slowly.
5. So: a small local tool that (a) watches run length and pace with a
   quiet indicator that only speaks up when it matters, and (b) gives a
   short post-call summary and a weekly trend, is a sound experiment. A
   constant "SLOW DOWN" nag is not.

## 1. Why slow down at all

Three things happen to listeners of fast, run-on speech, and only one of
them is about speed.

**Comprehension.** Listeners need processing time at clause and sentence
boundaries. Studies inserting artificial pauses at syntactic boundaries
improve intelligibility, particularly for older listeners, while
compressing speech without pauses degrades it. The pause is where the
listener's working memory catches up. Fast speech with pauses is
easier to follow than moderate speech without them.

**Perceived competence and confidence.** This one is genuinely mixed and
worth being honest about. Classic work from the late 1970s (Miller and
colleagues) found speakers at around 195 wpm rated *more* credible and
knowledgeable than slow speakers; later work (Smith and Shaffer, 1991)
showed the effect depends on the message and the audience: slowing down
helps when listeners are receptive and lets them process, and fast speech
helps when they are hostile because it denies them time to
counter-argue. Meanwhile pausing before answering is read as competence,
but pauses over a few seconds read as uncertainty. The practical reading:
moderate pace with clear pauses is the robust choice; both extremes cost
you something.

**Sentence completeness.** Fast speakers tend to start a sentence, veer,
restart, and finish a different one. Listeners experience this as
"disorganised" rather than "fast". In the clinical literature on
cluttering this is described as speech in "spurts", with dropped
syllables, merged words and pauses in unexpected places. Most fast
talkers are nowhere near a clinical picture, but the pattern is the same
in miniature, and the treatment ideas transfer.

## 2. How fast is fast

Numbers to anchor on (English, adult, native speakers):

| Measure | Typical | Notes |
|---|---|---|
| Conversation | 150 wpm (US average), 190 to 230 wpm at the top end | Tauroza and Allison 1990 for British English |
| Rate bands (Tauroza and Allison) | < 100 slow; 125 to 160 average; 160 to 185 moderately fast; > 185 fast | wpm, with pauses included |
| Syllable rate in conversation | about 4.3 syl/s including pauses | Tauroza and Allison |
| Articulation rate (pauses excluded) | roughly 4 to 5.5 syl/s | the measure that does not need a transcript |
| Audiobooks and radio | 150 to 160 wpm | close to the ceiling for full comprehension of unfamiliar material |
| Presentations, teaching | 100 to 140 wpm | slower because content is dense |

Two points matter for a tool:

- **Articulation rate** (syllables per second of actual voicing) is more
  robust than wpm. It does not depend on word length or on transcription
  quality, and it is what phoneticians use. It can be estimated from the
  audio envelope alone using the de Jong and Wempe (2009) syllable-nucleus
  method, which correlates well with human syllable counts.
- **Run length** (seconds of speech since the last pause of half a second
  or more) captures the "no full stops" problem that rate alone misses.
  Someone can speak at a moderate 4 syl/s for 40 seconds without a pause
  and still be exhausting to listen to.

## 3. What actually slows speech

Speech-language pathologists distinguish several levers for reducing
rate: lengthening syllables, adding or lengthening pauses, changing
breath patterns, and changing phrasing. The consistent advice, and the
consistent finding in cluttering treatment, is that **pausing and phrasing
work; syllable stretching does not stick**.

The core technique goes by several names: "thought units", "phrasing",
"chunking", "breath groups". Speak one clause or short sentence, stress
one or two words in it, then pause. The pause is where the breath
happens, where the listener processes, and where you decide what the
next sentence is before you start it. That last effect is why chunking
improves sentence completeness: you are no longer planning the sentence
while speaking it.

Concrete forms of the same idea:

- Full stop = pause. Treat the end of every sentence as a mandatory
  half-second silence. Most fast talkers use commas where full stops
  belong.
- Groups of three to six words with a small gap between groups.
- One breath per thought unit, in through the nose, before speaking.
- "Land the sentence": finish the sentence you started before starting
  the next one, even if it is a bad one.

Deliberate pausing initially feels far too long to the speaker and sounds
normal to the listener. Recording and listening back is the standard way
to recalibrate that feeling, and self-monitoring is described across the
therapy literature as the single most important factor in carryover.

## 4. Why the change does not stick, and what to do about it

This is the part most "talk slower" advice skips, and where the design
of any tool is decided.

**Performance is not learning.** Maas and colleagues' 2008 tutorial on
principles of motor learning in speech, and the studies since, show that
the conditions that make you perform well *during* practice (immediate,
frequent feedback) are not the conditions that make the skill *stay*
(sparse, delayed, summary feedback). The "guidance hypothesis" explains
it: constant feedback lets you lean on the signal instead of building
your own internal sense of "that was too fast". Take the signal away and
the behaviour goes with it. Reduced-frequency feedback is the principle
with the best preliminary evidence in speech motor learning specifically.

**Carryover needs the real context.** Voice-therapy work with ambulatory
biofeedback (a device worn through the day) found the same thing: the
gains came from targeting carryover into daily life, using reduced
feedback frequency and delayed summary feedback, rather than from the
in-clinic sessions. Practice in a practice app transfers poorly to a
tense meeting. Feedback during the actual meeting transfers.

**Nagging habituates.** Any indicator that is on all the time becomes
wallpaper within days. Feedback has to be rare enough to still register,
and it should arrive when the behaviour is actually happening (a 20-second
run, a sustained burst above your own normal rate), not on every
fluctuation.

**Self-monitoring beats external monitoring.** The therapy literature is
consistent that the client judging their own production ("was that
fast?") is what generalises. A tool that shows you a summary and lets you
compare it with how you *felt* the call went is doing that job. A tool
that just says "fast" is not.

### What has been tried

- **Delayed auditory feedback (DAF).** Your own voice fed back to
  headphones with a 125 to 250 ms delay. It reliably slows speech while
  it is on, which is why it is used for stuttering. The evidence base is
  patchy, the effect wears off, and people refuse to use it in real
  conversation because it makes them sound drugged. Worth ten minutes as
  an experiment to feel what "slow" feels like; not a daily tool.
- **Metronomes and pacing boards.** Used in cluttering and dysarthria
  therapy to impose rhythm. Effective in the clinic; obviously not usable
  on a call.
- **Recording and playback.** Cheap, unglamorous, and the technique with
  the most consistent support for building self-awareness.
- **Live coaching apps** (Yoodli, Poised, Orai). They listen to the mic
  during video calls, show a private pace and filler-word nudge, and give
  a post-call summary. That product shape works and people pay for it.
  Their weaknesses for our purpose are cloud transcription of every
  meeting, population-average thresholds rather than personal ones, and
  nudges that are easy to tune out.

## 5. What this implies for a tool

Putting the evidence together, a tool that is likely to help has these
properties:

1. **Measures the right things.** Articulation rate plus run length plus
   pauses per minute. Later, with transcription: words per sentence,
   restarts, fillers.
2. **Thresholds are personal.** Calibrate against your own normal reading
   rate and set "calm" a little below it. Population averages are the
   wrong reference; the goal is slower than *you* usually are.
3. **Live indicator is quiet.** A colour in the menu bar (optionally a
   small overlay) that changes only after a few seconds of sustained fast
   speech or a long run. No sound by default. It is a cue, not a coach.
4. **The summary is the product.** After each call: talk time, median and
   95th-percentile rate, share of time in each zone, longest run, pauses
   per minute, and a one-line comparison with the last week. This is the
   self-monitoring step the research says matters.
5. **Runs in real conversations**, locally, mic only, headphones on so the
   other party's voice does not pollute the numbers. Not a practice mode.
6. **Expect the live cue to fade** in usefulness over weeks. That is
   fine; by then the summary and trend are doing the work. If the cue
   becomes wallpaper, make it rarer, not louder.

## 6. Verdict

Yes, the small local app is a good experiment. It is cheap (a day or
two for the rate-and-pause version, no transcription needed), private,
and it matches what the evidence says helps: feedback in context,
sparse cues, summaries for self-monitoring, personal thresholds. The main
risks are (a) the syllable-rate proxy misreading noisy audio, fixed by
calibration and headphones, and (b) feedback fatigue, addressed by
hysteresis and by making the summary, not the live cue, the centre of the
design.

What the tool cannot do on its own: teach the pausing technique. That
still has to be practised deliberately (full stop = pause, one breath per
thought unit) and the tool's job is to tell you honestly whether you did.

## 7. Next steps

1. **Phase 1, build the monitor.** Menu-bar app, articulation rate and
   run length from the mic, calibration, session log and report. Plan and
   task breakdown in `docs/plans/2026-09-18-speaking-speed-phase1-plan.md`
   (beads epic `spkspd-l1s`). Prerequisite on this machine: fix or bypass
   the broken Homebrew Python and install `uv`; the plan does the latter.
2. **Use it for a week on real calls**, headphones on, and judge two
   things: does the glyph agree with how the call felt, and is the summary
   interesting enough to look at. Record the answer as a beads note.
3. **Phase 2, add words** if phase 1 earns it: local `whisper-stream`
   for words per minute, fillers, sentence length and restarts. Optional
   Claude review of the transcript for a short coaching note.
4. **Native rewrite** in Swift with Apple's on-device SpeechAnalyzer only
   if the Python version proves its worth and Xcode 26 gets installed.

## Sources

Rate and pause norms

- Tauroza, S. and Allison, D. (1990). Speech rates in British English.
  *Applied Linguistics* 11(1), 90–105. Summarised in
  [Plug et al., Speech Communication](https://eprints.whiterose.ac.uk/172033/1/Plugea_SpeechCom_finalsub.pdf)
  and [Trouvain, Measuring Tempo](https://www.coli.uni-saarland.de/trouvain/Phonus8/04_chapter4.pdf).
- [VirtualSpeech: average speaking rate](https://virtualspeech.com/blog/average-speaking-rate-words-per-minute)
  (US 150 wpm; audiobook 150–160; presentation 100–140).
- de Jong, N. H. and Wempe, T. (2009). Praat script to detect syllable
  nuclei and measure speech rate automatically. *Behavior Research
  Methods* 41(2), 385–390. [PDF](https://www.fon.hum.uva.nl/archive/2009/2009-brm-JongWempe.pdf),
  [script site](https://sites.google.com/site/speechrate).

Pauses and listeners

- [Effects of pause duration and speech rate on sentence intelligibility in younger and older adult listeners](https://www.researchgate.net/publication/234040331_Effects_of_pause_duration_and_speech_rate_on_sentence_intelligibility_in_younger_and_older_adult_listeners).
- [The effect of pause location on perceived fluency](https://www.cambridge.org/core/journals/applied-psycholinguistics/article/abs/effect-of-pause-location-on-perceived-fluency/D8EF194FCD2C5FBF0D6BA49EF6F0624E), *Applied Psycholinguistics*.
- [Kohtz et al. 2017, How long is too long? pause features](https://www.isca-archive.org/interspeech_2017/kohtz17_interspeech.pdf), Interspeech.
- [Pause length and cognitive-state attribution](https://www.mdpi.com/2226-471X/8/1/26), *Languages* 2023.
- [The power of pausing in collaborative conversations](https://www.sciencedirect.com/science/article/pii/S0749597825000676), OBHDP 2025.
- [Psychology Today: the silent signal](https://www.psychologytoday.com/ie/blog/communication-uncovered/202509/the-silent-signal).

Rate and persuasion (mixed evidence)

- Miller et al. (1976), Speed of speech and persuasion, *JPSP*.
  [ResearchGate](https://www.researchgate.net/publication/232560700_Speed_of_Speech_and_Persuasion).
- Smith and Shaffer (1991) via [Quick and Dirty Tips summary](https://www.quickanddirtytips.com/qdtarchive/are-fast-talkers-more-persuasive/)
  and [PsyBlog](https://www.spring.org.uk/2024/11/talking-fast.php).

Technique: pausing, chunking, thought units

- [Banter Speech: how to slow down your speech, do we need a new approach?](https://www.banterspeech.com.au/how-to-slow-down-your-speech-do-we-need-a-new-approach/)
- [Talk Slower: how to talk slower](https://www.talkslower.com/blog/how-to-talk-slower-stop-talking-too-fast)
- [Steady State: mastering slow speech](https://steadystatehq.com/blog/speakslower)

Cluttering (the clinical analogue)

- [Stuttering Foundation: cluttering](https://www.stutteringhelp.org/cluttering)
- [Cleveland Clinic: cluttering](https://my.clevelandclinic.org/health/diseases/cluttering)
- [Wikipedia: cluttering](https://en.wikipedia.org/wiki/Cluttering)
- [Too Fast for Words: cluttering therapy guidelines](https://toofastforwords.com/cluttering-speech-therapy/)

Motor learning, feedback and carryover

- Maas, E. et al. (2008). Principles of motor learning in treatment of
  motor speech disorders. *AJSLP* 17, 277–298.
  [PDF](https://gwulf.faculty.unlv.edu/wp-content/uploads/2014/05/Maas-et-al_AJSLP-2008_PML-tutorial.pdf),
  [ASHA](https://pubs.asha.org/doi/10.1044/1058-0360%282008/025%29).
- [Do principles of motor learning enhance retention and transfer of speech skills? A systematic review](https://www.researchgate.net/publication/233190318_Do_principles_of_motor_learning_enhance_retention_and_transfer_of_speech_skills_A_systematic_review).
- [Impact of feedback frequency on a novel speech motor learning task](https://ncbi.nlm.nih.gov/pmc/articles/PMC5544402), PMC.
- Van Stan et al., [Ambulatory voice biofeedback: relative frequency and summary feedback](https://pmc.ncbi.nlm.nih.gov/articles/PMC5548081/), PMC;
  [motor learning principles in ambulatory voice biofeedback](https://pubmed.ncbi.nlm.nih.gov/28124070/), PubMed.
- [Marshalla: carryover techniques](https://pammarshalla.com/article-on-carryover-techniques/);
  [Speech and Language Kids: self-awareness and carryover](https://www.speechandlanguagekids.com/increase-self-awareness-and-carry-over/).

Delayed auditory feedback

- [Dataset of speech produced with delayed auditory feedback](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11803211/), PMC.
- [Wikipedia: stuttering therapy](https://en.wikipedia.org/wiki/Stuttering_therapy) (DAF evidence "patchy").

Commercial live-coaching tools

- [Yoodli review](https://www.finalroundai.com/blog/yoodli-review-pros-cons);
  [Yoodli overview](https://aitools.aiting.com/ai/yoodli);
  [AI communication coaches 2026](https://usefulai.com/tools/ai-communication-coaches).
