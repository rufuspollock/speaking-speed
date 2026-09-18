# Speaking Speed Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Read `docs/plans/2026-09-18-speaking-speed-research-and-design.md` first for the why.

**Goal:** A local macOS menu-bar monitor that listens to the mic, estimates articulation rate (syllables/second) and "run length since last pause", shows a colour zone in the menu bar with hysteresis, and logs a per-session summary. No transcription, no bundling.

**Architecture:** `sounddevice` streams 20 ms mono frames from the default mic into a queue. A worker thread turns frames into a dB envelope, picks syllable nuclei (de Jong & Wempe rules via `scipy.signal.find_peaks`), keeps a 10 s ring buffer and recomputes window metrics every 0.5 s. All DSP is pure numpy functions tested on synthetic audio. A `rumps` menu-bar app polls the latest metrics and sets its title; a CSV logger records each tick and prints a summary on stop.

**Tech Stack:** Python 3.12 via `uv`, `numpy`, `scipy`, `sounddevice` (needs `brew install portaudio`), `rumps`, `pytest`. Config in `~/.config/speaking-speed/config.toml` (stdlib `tomllib`). Sessions in `~/.local/share/speaking-speed/sessions/`.

**Environment notes (verified 2026-09-18):** Homebrew `python@3.14` on this machine is broken (pip dies with a `pyexpat`/`libexpat` dyld error). Do not use it. `uv` is not installed; Task 0 installs it. No Xcode, only Command Line Tools with the 14.4 SDK, so nothing here may depend on Swift or the macOS 26 SDK. Mic permission is granted to the terminal app (Ghostty) on first use; if the prompt never appears, check System Settings → Privacy & Security → Microphone.

**Conventions:** `src/` layout, package `speaking_speed`. Run everything with `uv run`. Commit after each task with a conventional-commit message. Tests: `uv run pytest -q`.

---

### Task 0: Project scaffold

**Files:**
- Create: `pyproject.toml`, `src/speaking_speed/__init__.py`, `tests/__init__.py`, `tests/test_smoke.py`
- Modify: `.gitignore`

**Step 1: Install tooling**

```bash
brew install uv portaudio
uv python install 3.12
```
Expected: `uv --version` prints a version; `brew list portaudio` lists `libportaudio.dylib`.

**Step 2: Write `pyproject.toml`**

```toml
[project]
name = "speaking-speed"
version = "0.1.0"
description = "Local macOS menu-bar monitor for speaking rate and pauses"
requires-python = ">=3.12,<3.13"
dependencies = [
  "numpy>=2.0",
  "scipy>=1.13",
  "sounddevice>=0.5",
  "rumps>=0.4",
]

[project.scripts]
speaking-speed = "speaking_speed.cli:main"

[dependency-groups]
dev = ["pytest>=8"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.hatch.build.targets.wheel]
packages = ["src/speaking_speed"]

[tool.pytest.ini_options]
testpaths = ["tests"]
```

**Step 3: Create package and smoke test**

`src/speaking_speed/__init__.py`:
```python
"""Speaking Speed: local speaking-rate monitor."""
__version__ = "0.1.0"
```

`tests/__init__.py`: empty file.

`tests/test_smoke.py`:
```python
import speaking_speed

def test_version():
    assert speaking_speed.__version__ == "0.1.0"
```

**Step 4: Append to `.gitignore`**

```
.venv/
__pycache__/
*.pyc
.pytest_cache/
dist/
```

**Step 5: Sync and run**

```bash
uv sync
uv run pytest -q
```
Expected: `1 passed`. (`uv sync` creates `.venv` and `uv.lock`; commit the lock file.)

**Step 6: Commit**

```bash
git add pyproject.toml uv.lock src tests .gitignore
git commit -m "chore: python project scaffold with uv"
```

---

### Task 1: Envelope (RMS → dB, smoothing, speech mask)

**Files:**
- Create: `src/speaking_speed/envelope.py`, `tests/test_envelope.py`, `tests/synth.py`

**Step 1: Write the synthetic-signal helper `tests/synth.py`**

```python
"""Synthetic audio for tests. 16 kHz mono float32."""
import numpy as np

SR = 16000

def silence(seconds: float) -> np.ndarray:
    return np.zeros(int(SR * seconds), dtype=np.float32)

def tone(seconds: float, freq: float = 220.0, amp: float = 0.3) -> np.ndarray:
    t = np.arange(int(SR * seconds)) / SR
    # short fade in/out so bursts have clean intensity dips between them
    y = amp * np.sin(2 * np.pi * freq * t)
    ramp = min(len(y) // 4, int(SR * 0.01))
    if ramp > 0:
        w = np.linspace(0, 1, ramp)
        y[:ramp] *= w
        y[-ramp:] *= w[::-1]
    return y.astype(np.float32)

def bursts(n: int, on: float = 0.12, off: float = 0.08, amp: float = 0.3) -> np.ndarray:
    """n tone bursts separated by short gaps: a crude 'syllable' train."""
    parts = []
    for i in range(n):
        parts.append(tone(on, amp=amp))
        if i < n - 1:
            parts.append(silence(off))
    return np.concatenate(parts)

def noise(seconds: float, amp: float = 0.002, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return (amp * rng.standard_normal(int(SR * seconds))).astype(np.float32)
```

**Step 2: Write the failing tests `tests/test_envelope.py`**

```python
import numpy as np
from speaking_speed import envelope as E
from tests.synth import SR, silence, tone, noise

HOP = 320  # 20 ms at 16 kHz

def test_frame_db_shape_and_range():
    x = np.concatenate([silence(0.2), tone(0.2), silence(0.2)])
    db = E.frame_db(x, HOP)
    assert db.shape == (len(x) // HOP,)
    assert db.min() >= E.DB_FLOOR
    assert db[15] > db[2] + 20  # tone frames far louder than silence frames

def test_smooth_preserves_length():
    db = np.zeros(50)
    assert E.smooth(db, 5).shape == (50,)

def test_speech_mask_marks_tone_not_noise():
    x = np.concatenate([noise(0.5), tone(0.5), noise(0.5)])
    db = E.smooth(E.frame_db(x, HOP), 3)
    floor = E.noise_floor(db)
    mask = E.speech_mask(db, floor, margin_db=8.0)
    n = len(mask)
    assert mask[n // 2]
    assert not mask[2]
    assert not mask[-3]
```

**Step 3: Run to verify failure**

```bash
uv run pytest tests/test_envelope.py -q
```
Expected: FAIL, `ModuleNotFoundError` or `AttributeError` on `speaking_speed.envelope`.

**Step 4: Implement `src/speaking_speed/envelope.py`**

```python
"""Intensity envelope of a mono float32 signal, in dB."""
from __future__ import annotations
import numpy as np

DB_FLOOR = -80.0

def frame_db(x: np.ndarray, hop: int) -> np.ndarray:
    """RMS per non-overlapping frame of `hop` samples, in dBFS. Drops the tail."""
    n = len(x) // hop
    if n == 0:
        return np.empty(0)
    frames = x[: n * hop].reshape(n, hop).astype(np.float64)
    rms = np.sqrt(np.mean(frames * frames, axis=1))
    return np.maximum(20.0 * np.log10(rms + 1e-9), DB_FLOOR)

def smooth(db: np.ndarray, k: int) -> np.ndarray:
    """Centred moving average over k frames (k odd recommended)."""
    if k <= 1 or len(db) == 0:
        return db.copy()
    kernel = np.ones(k) / k
    return np.convolve(db, kernel, mode="same")

def noise_floor(db: np.ndarray, percentile: float = 10.0) -> float:
    """Adaptive floor: a low percentile of the window."""
    if len(db) == 0:
        return DB_FLOOR
    return float(np.percentile(db, percentile))

def speech_mask(db: np.ndarray, floor: float, margin_db: float = 8.0) -> np.ndarray:
    """True where the frame is clearly above the noise floor."""
    return db > (floor + margin_db)
```

**Step 5: Run tests**

```bash
uv run pytest tests/test_envelope.py -q
```
Expected: `3 passed`.

**Step 6: Commit**

```bash
git add src/speaking_speed/envelope.py tests/test_envelope.py tests/synth.py
git commit -m "feat: dB envelope, smoothing and speech mask"
```

---

### Task 2: Syllable nucleus detection

**Files:**
- Create: `src/speaking_speed/nuclei.py`, `tests/test_nuclei.py`

Rule (de Jong & Wempe 2009): a nucleus is a local intensity peak that is at least `min_dip_db` (2 dB) above the surrounding dips, within speech, and at least `min_gap_frames` apart (80 ms → 4 frames: nobody exceeds ~12 syl/s). `scipy.signal.find_peaks` with `prominence` implements the dip rule.

**Step 1: Write the failing tests `tests/test_nuclei.py`**

```python
import numpy as np
from speaking_speed import envelope as E
from speaking_speed.nuclei import find_nuclei
from tests.synth import bursts, silence, noise

HOP = 320

def _env(x):
    db = E.smooth(E.frame_db(x, HOP), 3)
    mask = E.speech_mask(db, E.noise_floor(db), 8.0)
    return db, mask

def test_counts_bursts():
    x = np.concatenate([noise(0.3), bursts(8), noise(0.3)])
    db, mask = _env(x)
    idx = find_nuclei(db, mask)
    assert 7 <= len(idx) <= 9

def test_no_nuclei_in_noise():
    db, mask = _env(noise(2.0))
    assert len(find_nuclei(db, mask)) == 0

def test_nuclei_are_inside_speech():
    x = np.concatenate([silence(0.5), bursts(3), silence(0.5)])
    db, mask = _env(x)
    idx = find_nuclei(db, mask)
    assert len(idx) == 3
    assert all(mask[i] for i in idx)
```

**Step 2: Run to verify failure**

```bash
uv run pytest tests/test_nuclei.py -q
```
Expected: FAIL with `ModuleNotFoundError: speaking_speed.nuclei`.

**Step 3: Implement `src/speaking_speed/nuclei.py`**

```python
"""Syllable-nucleus detection on a dB envelope (de Jong & Wempe 2009, simplified)."""
from __future__ import annotations
import numpy as np
from scipy.signal import find_peaks

def find_nuclei(
    db: np.ndarray,
    mask: np.ndarray,
    min_dip_db: float = 2.0,
    min_gap_frames: int = 4,
) -> np.ndarray:
    """Frame indices of syllable nuclei.

    A nucleus is a peak with prominence >= min_dip_db (i.e. dips of at least
    that depth on both sides), inside the speech mask, and at least
    min_gap_frames from the previous nucleus.
    """
    if len(db) < 3:
        return np.empty(0, dtype=int)
    # Push non-speech frames down so peaks cannot form there.
    work = np.where(mask, db, db.min() - 20.0)
    peaks, _ = find_peaks(work, prominence=min_dip_db, distance=min_gap_frames)
    return peaks[mask[peaks]]
```

**Step 4: Run tests**

```bash
uv run pytest tests/test_nuclei.py -q
```
Expected: `3 passed`. If `test_counts_bursts` is off by more than one, check that `smooth(…, 3)` is not merging bursts (gap is 80 ms = 4 frames, smoothing spans 3 frames; that is fine). Do not widen the tolerance.

**Step 5: Commit**

```bash
git add src/speaking_speed/nuclei.py tests/test_nuclei.py
git commit -m "feat: syllable nucleus detection"
```

---

### Task 3: Window metrics

**Files:**
- Create: `src/speaking_speed/metrics.py`, `tests/test_metrics.py`

Inputs are per-frame booleans over the window; outputs are what the UI and log need.

**Step 1: Write the failing tests `tests/test_metrics.py`**

```python
import numpy as np
from speaking_speed.metrics import compute_metrics

FRAME_S = 0.02

def _frames(pattern: str) -> np.ndarray:
    """'s' = speech frame, '.' = silence frame."""
    return np.array([c == "s" for c in pattern])

def test_articulation_rate():
    # 100 speech frames = 2.0 s phonation, 8 nuclei -> 4.0 syl/s
    speech = _frames("s" * 100)
    nuclei = np.zeros(100, dtype=bool)
    nuclei[::13][:8] = True
    m = compute_metrics(speech, nuclei, FRAME_S)
    assert m.phonation_s == 2.0
    assert m.syllables == 8
    assert abs(m.articulation_rate - 4.0) < 1e-9

def test_rate_is_none_when_too_little_speech():
    speech = _frames("s" * 10 + "." * 90)
    m = compute_metrics(speech, np.zeros(100, dtype=bool), FRAME_S, min_phonation_s=1.0)
    assert m.articulation_rate is None

def test_pauses_counted_only_between_speech():
    # speech 1 s, pause 0.5 s, speech 1 s, trailing silence 1 s (not a pause)
    speech = _frames("s" * 50 + "." * 25 + "s" * 50 + "." * 50)
    m = compute_metrics(speech, np.zeros(175, dtype=bool), FRAME_S, pause_min_s=0.35)
    assert m.pauses == 1
    assert abs(m.mean_pause_s - 0.5) < 1e-9

def test_current_run_resets_after_pause():
    speech = _frames("s" * 100 + "." * 30 + "s" * 40)  # 2 s, 0.6 s gap, 0.8 s
    m = compute_metrics(speech, np.zeros(170, dtype=bool), FRAME_S, run_pause_s=0.5)
    assert abs(m.current_run_s - 0.8) < 1e-9

def test_current_run_zero_when_currently_silent():
    speech = _frames("s" * 100 + "." * 30)
    m = compute_metrics(speech, np.zeros(130, dtype=bool), FRAME_S, run_pause_s=0.5)
    assert m.current_run_s == 0.0

def test_current_run_spans_short_gaps():
    speech = _frames("s" * 50 + "." * 10 + "s" * 50)  # 0.2 s gap < run_pause_s
    m = compute_metrics(speech, np.zeros(110, dtype=bool), FRAME_S, run_pause_s=0.5)
    assert abs(m.current_run_s - 2.2) < 1e-9
```

**Step 2: Run to verify failure**

```bash
uv run pytest tests/test_metrics.py -q
```
Expected: FAIL, `ModuleNotFoundError`.

**Step 3: Implement `src/speaking_speed/metrics.py`**

```python
"""Window metrics from per-frame speech / nucleus flags."""
from __future__ import annotations
from dataclasses import dataclass
import numpy as np

@dataclass(frozen=True)
class Metrics:
    window_s: float
    phonation_s: float
    syllables: int
    articulation_rate: float | None   # syl / s of phonation
    speech_rate: float | None         # syl / s of window
    pauses: int
    mean_pause_s: float
    current_run_s: float              # seconds of speech since last pause >= run_pause_s

def _runs(flags: np.ndarray) -> list[tuple[bool, int, int]]:
    """Run-length encode -> [(value, start, end_exclusive), ...]."""
    if len(flags) == 0:
        return []
    out = []
    start = 0
    for i in range(1, len(flags) + 1):
        if i == len(flags) or flags[i] != flags[start]:
            out.append((bool(flags[start]), start, i))
            start = i
    return out

def compute_metrics(
    speech: np.ndarray,
    nuclei: np.ndarray,
    frame_s: float,
    min_phonation_s: float = 1.0,
    pause_min_s: float = 0.35,
    run_pause_s: float = 0.5,
) -> Metrics:
    n = len(speech)
    window_s = n * frame_s
    phonation_s = float(speech.sum()) * frame_s
    syllables = int(nuclei.sum())
    art = syllables / phonation_s if phonation_s >= min_phonation_s else None
    spr = syllables / window_s if (window_s > 0 and art is not None) else None

    runs = _runs(speech)
    # Pauses: silent runs bounded by speech on both sides, long enough.
    pause_lens = [
        (e - s) * frame_s
        for k, (v, s, e) in enumerate(runs)
        if not v and 0 < k < len(runs) - 1 and (e - s) * frame_s >= pause_min_s
    ]
    # Current run: walk back from the end until a silent run >= run_pause_s.
    current = 0.0
    if runs and runs[-1][0] is False and (runs[-1][2] - runs[-1][1]) * frame_s >= run_pause_s:
        current = 0.0
    else:
        for v, s, e in reversed(runs):
            length = (e - s) * frame_s
            if not v and length >= run_pause_s:
                break
            current += length
    return Metrics(
        window_s=window_s,
        phonation_s=phonation_s,
        syllables=syllables,
        articulation_rate=art,
        speech_rate=spr,
        pauses=len(pause_lens),
        mean_pause_s=float(np.mean(pause_lens)) if pause_lens else 0.0,
        current_run_s=current,
    )
```

Note: `current_run_s` includes short gaps (< `run_pause_s`) inside the run, by design: a 0.2 s breath does not end a "thought unit".

**Step 4: Run tests**

```bash
uv run pytest tests/test_metrics.py -q
```
Expected: `6 passed`.

**Step 5: Commit**

```bash
git add src/speaking_speed/metrics.py tests/test_metrics.py
git commit -m "feat: window metrics (rate, pauses, current run)"
```

---

### Task 4: Zones with hysteresis

**Files:**
- Create: `src/speaking_speed/zones.py`, `tests/test_zones.py`

**Step 1: Write the failing tests `tests/test_zones.py`**

```python
from speaking_speed.metrics import Metrics
from speaking_speed.zones import Zone, Thresholds, classify, ZoneSmoother

T = Thresholds(calm_max_rate=3.8, fast_min_rate=4.5, calm_max_run_s=12.0, fast_min_run_s=20.0)

def _m(rate, run=0.0):
    return Metrics(10.0, 5.0, 0, rate, None, 0, 0.0, run)

def test_classify_by_rate():
    assert classify(_m(3.0), T) == Zone.CALM
    assert classify(_m(4.0), T) == Zone.BRISK
    assert classify(_m(5.0), T) == Zone.FAST

def test_classify_by_run_overrides_calm_rate():
    assert classify(_m(3.0, run=15.0), T) == Zone.BRISK
    assert classify(_m(3.0, run=25.0), T) == Zone.FAST

def test_classify_unknown_when_no_rate():
    assert classify(_m(None), T) == Zone.UNKNOWN

def test_smoother_needs_sustained_ticks_to_worsen():
    s = ZoneSmoother(worsen_ticks=3, improve_ticks=4)
    assert s.update(Zone.CALM) == Zone.CALM
    assert s.update(Zone.FAST) == Zone.CALM
    assert s.update(Zone.FAST) == Zone.CALM
    assert s.update(Zone.FAST) == Zone.FAST

def test_smoother_needs_more_ticks_to_improve():
    s = ZoneSmoother(worsen_ticks=3, improve_ticks=4)
    for _ in range(3):
        s.update(Zone.FAST)
    assert s.current == Zone.FAST
    for _ in range(3):
        assert s.update(Zone.CALM) == Zone.FAST
    assert s.update(Zone.CALM) == Zone.CALM

def test_smoother_ignores_unknown():
    s = ZoneSmoother(3, 4)
    for _ in range(3):
        s.update(Zone.FAST)
    assert s.update(Zone.UNKNOWN) == Zone.FAST
```

**Step 2: Run to verify failure**

```bash
uv run pytest tests/test_zones.py -q
```
Expected: FAIL, `ModuleNotFoundError`.

**Step 3: Implement `src/speaking_speed/zones.py`**

```python
"""Map metrics to a colour zone, with hysteresis so the indicator is calm."""
from __future__ import annotations
from dataclasses import dataclass
from enum import IntEnum
from .metrics import Metrics

class Zone(IntEnum):
    UNKNOWN = -1
    CALM = 0
    BRISK = 1
    FAST = 2

@dataclass(frozen=True)
class Thresholds:
    calm_max_rate: float = 3.8
    fast_min_rate: float = 4.5
    calm_max_run_s: float = 12.0
    fast_min_run_s: float = 20.0

def classify(m: Metrics, t: Thresholds) -> Zone:
    if m.articulation_rate is None:
        return Zone.UNKNOWN
    if m.articulation_rate >= t.fast_min_rate:
        by_rate = Zone.FAST
    elif m.articulation_rate >= t.calm_max_rate:
        by_rate = Zone.BRISK
    else:
        by_rate = Zone.CALM
    if m.current_run_s >= t.fast_min_run_s:
        by_run = Zone.FAST
    elif m.current_run_s >= t.calm_max_run_s:
        by_run = Zone.BRISK
    else:
        by_run = Zone.CALM
    return max(by_rate, by_run)

class ZoneSmoother:
    """Only change zone after the new zone has held for N consecutive ticks."""

    def __init__(self, worsen_ticks: int = 3, improve_ticks: int = 4):
        self.worsen_ticks = worsen_ticks
        self.improve_ticks = improve_ticks
        self.current = Zone.CALM
        self._candidate = Zone.CALM
        self._count = 0

    def update(self, raw: Zone) -> Zone:
        if raw == Zone.UNKNOWN:
            return self.current
        if raw == self.current:
            self._candidate, self._count = raw, 0
            return self.current
        if raw == self._candidate:
            self._count += 1
        else:
            self._candidate, self._count = raw, 1
        needed = self.worsen_ticks if raw > self.current else self.improve_ticks
        if self._count >= needed:
            self.current, self._count = raw, 0
        return self.current
```

**Step 4: Run tests**

```bash
uv run pytest tests/test_zones.py -q
```
Expected: `6 passed`.

**Step 5: Commit**

```bash
git add src/speaking_speed/zones.py tests/test_zones.py
git commit -m "feat: zone classification with hysteresis"
```

---

### Task 5: Config

**Files:**
- Create: `src/speaking_speed/config.py`, `tests/test_config.py`

**Step 1: Write the failing tests `tests/test_config.py`**

```python
from pathlib import Path
from speaking_speed.config import Config, load, save

def test_defaults_when_missing(tmp_path: Path):
    c = load(tmp_path / "config.toml")
    assert c.thresholds.calm_max_rate == 3.8
    assert c.window_s == 10.0

def test_roundtrip(tmp_path: Path):
    p = tmp_path / "config.toml"
    c = Config()
    c = c.with_thresholds(calm_max_rate=3.2, fast_min_rate=4.1)
    save(c, p)
    c2 = load(p)
    assert c2.thresholds.calm_max_rate == 3.2
    assert c2.thresholds.fast_min_rate == 4.1
    assert c2.sessions_dir == c.sessions_dir
```

**Step 2: Run to verify failure**

```bash
uv run pytest tests/test_config.py -q
```
Expected: FAIL, `ModuleNotFoundError`.

**Step 3: Implement `src/speaking_speed/config.py`**

```python
"""User config: ~/.config/speaking-speed/config.toml."""
from __future__ import annotations
import dataclasses
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from .zones import Thresholds

DEFAULT_PATH = Path.home() / ".config" / "speaking-speed" / "config.toml"
DEFAULT_SESSIONS = Path.home() / ".local" / "share" / "speaking-speed" / "sessions"

@dataclass(frozen=True)
class Config:
    sample_rate: int = 16000
    hop: int = 320                 # 20 ms
    window_s: float = 10.0
    tick_s: float = 0.5
    smooth_frames: int = 3
    speech_margin_db: float = 8.0
    input_device: str | None = None
    thresholds: Thresholds = field(default_factory=Thresholds)
    sessions_dir: Path = DEFAULT_SESSIONS

    def with_thresholds(self, **kw) -> "Config":
        return dataclasses.replace(self, thresholds=dataclasses.replace(self.thresholds, **kw))

def load(path: Path = DEFAULT_PATH) -> Config:
    if not path.exists():
        return Config()
    data = tomllib.loads(path.read_text())
    th = Thresholds(**data.get("thresholds", {}))
    top = {k: v for k, v in data.items() if k != "thresholds"}
    if "sessions_dir" in top:
        top["sessions_dir"] = Path(top["sessions_dir"]).expanduser()
    return Config(thresholds=th, **top)

def save(c: Config, path: Path = DEFAULT_PATH) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        f"sample_rate = {c.sample_rate}",
        f"hop = {c.hop}",
        f"window_s = {c.window_s}",
        f"tick_s = {c.tick_s}",
        f"smooth_frames = {c.smooth_frames}",
        f"speech_margin_db = {c.speech_margin_db}",
        f'sessions_dir = "{c.sessions_dir}"',
    ]
    if c.input_device is not None:
        lines.append(f'input_device = "{c.input_device}"')
    lines += ["", "[thresholds]"]
    for f in dataclasses.fields(Thresholds):
        lines.append(f"{f.name} = {getattr(c.thresholds, f.name)}")
    path.write_text("\n".join(lines) + "\n")
```

**Step 4: Run tests**

```bash
uv run pytest tests/test_config.py -q
```
Expected: `2 passed`.

**Step 5: Commit**

```bash
git add src/speaking_speed/config.py tests/test_config.py
git commit -m "feat: toml config with thresholds"
```

---

### Task 6: Pipeline (ring buffer + tick)

**Files:**
- Create: `src/speaking_speed/pipeline.py`, `tests/test_pipeline.py`

The pipeline is hardware-free: you `push(samples)` and call `tick()`; that makes it testable with synthetic audio and reusable by both the terminal monitor and the menu bar.

**Step 1: Write the failing tests `tests/test_pipeline.py`**

```python
import numpy as np
from speaking_speed.config import Config
from speaking_speed.pipeline import Pipeline
from tests.synth import bursts, noise, silence

def test_tick_reports_rate_for_syllable_train():
    cfg = Config(window_s=4.0)
    p = Pipeline(cfg)
    # 20 bursts at 0.2 s period; the 4 s window keeps ~16 of them plus 0.8 s trailing noise.
    # Synthetic bursts go fully silent between syllables (real speech does not), so
    # articulation_rate is inflated here; assert on speech_rate (syllables / window).
    p.push(np.concatenate([noise(0.5), bursts(20, on=0.12, off=0.08), noise(0.8)]))
    m = p.tick()
    assert m.articulation_rate is not None
    assert 3.0 <= m.speech_rate <= 5.0
    assert m.current_run_s == 0.0   # 0.8 s trailing noise >= run_pause_s

def test_ring_buffer_bounded():
    cfg = Config(window_s=2.0)
    p = Pipeline(cfg)
    p.push(silence(10.0))
    assert p.frames_buffered() == int(2.0 / 0.02)

def test_tick_before_audio_is_unknown():
    m = Pipeline(Config()).tick()
    assert m.articulation_rate is None
```

**Step 2: Run to verify failure**

```bash
uv run pytest tests/test_pipeline.py -q
```
Expected: FAIL, `ModuleNotFoundError`.

**Step 3: Implement `src/speaking_speed/pipeline.py`**

```python
"""Samples in, Metrics out. Thread-safe push; tick from any thread."""
from __future__ import annotations
import threading
from collections import deque
import numpy as np
from . import envelope as E
from .config import Config
from .metrics import Metrics, compute_metrics
from .nuclei import find_nuclei

class Pipeline:
    def __init__(self, cfg: Config):
        self.cfg = cfg
        self.frame_s = cfg.hop / cfg.sample_rate
        self.max_frames = int(round(cfg.window_s / self.frame_s))
        self._db: deque[float] = deque(maxlen=self.max_frames)
        self._pending = np.empty(0, dtype=np.float32)
        self._lock = threading.Lock()

    def push(self, samples: np.ndarray) -> None:
        with self._lock:
            x = np.concatenate([self._pending, samples.astype(np.float32).ravel()])
            n = len(x) // self.cfg.hop
            if n:
                self._db.extend(E.frame_db(x[: n * self.cfg.hop], self.cfg.hop).tolist())
            self._pending = x[n * self.cfg.hop :]

    def frames_buffered(self) -> int:
        with self._lock:
            return len(self._db)

    def tick(self) -> Metrics:
        with self._lock:
            db = np.array(self._db)
        if len(db) < 3:
            return compute_metrics(np.zeros(0, bool), np.zeros(0, bool), self.frame_s)
        db = E.smooth(db, self.cfg.smooth_frames)
        mask = E.speech_mask(db, E.noise_floor(db), self.cfg.speech_margin_db)
        idx = find_nuclei(db, mask)
        nuc = np.zeros(len(db), dtype=bool)
        nuc[idx] = True
        return compute_metrics(mask, nuc, self.frame_s)
```

**Step 4: Run tests**

```bash
uv run pytest tests/test_pipeline.py -q
```
Expected: `3 passed`.

**Step 5: Commit**

```bash
git add src/speaking_speed/pipeline.py tests/test_pipeline.py
git commit -m "feat: audio pipeline with ring buffer"
```

---

### Task 7: Mic capture + terminal monitor (first real-audio check)

**Files:**
- Create: `src/speaking_speed/capture.py`, `src/speaking_speed/cli.py`

No unit tests for hardware. Manual check is the test.

**Step 1: Implement `src/speaking_speed/capture.py`**

```python
"""Default-mic capture via sounddevice into a Pipeline."""
from __future__ import annotations
import sounddevice as sd
from .config import Config
from .pipeline import Pipeline

class Capture:
    def __init__(self, cfg: Config, pipeline: Pipeline):
        self.cfg = cfg
        self.pipeline = pipeline
        self._stream: sd.InputStream | None = None

    def _callback(self, indata, frames, time_info, status):
        if status:
            print(f"[capture] {status}", flush=True)
        self.pipeline.push(indata[:, 0])

    def start(self) -> None:
        self._stream = sd.InputStream(
            samplerate=self.cfg.sample_rate,
            channels=1,
            dtype="float32",
            blocksize=self.cfg.hop,
            device=self.cfg.input_device,
            callback=self._callback,
        )
        self._stream.start()

    def stop(self) -> None:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None

def list_devices() -> str:
    return str(sd.query_devices())
```

**Step 2: Implement `src/speaking_speed/cli.py` (monitor + devices only for now)**

```python
"""CLI entry: speaking-speed <command>."""
from __future__ import annotations
import argparse
import sys
import time
from . import config as C
from .capture import Capture, list_devices
from .pipeline import Pipeline
from .zones import ZoneSmoother, classify

GLYPH = {-1: "⚪", 0: "🟢", 1: "🟡", 2: "🔴"}

def cmd_monitor(args) -> int:
    cfg = C.load()
    p = Pipeline(cfg)
    cap = Capture(cfg, p)
    sm = ZoneSmoother()
    cap.start()
    print("listening… Ctrl-C to stop", flush=True)
    try:
        while True:
            time.sleep(cfg.tick_s)
            m = p.tick()
            z = sm.update(classify(m, cfg.thresholds))
            rate = "  -- " if m.articulation_rate is None else f"{m.articulation_rate:5.2f}"
            print(
                f"\r{GLYPH[int(z)]} rate {rate} syl/s  run {m.current_run_s:5.1f}s  "
                f"pauses {m.pauses:2d}  talk {m.phonation_s:4.1f}/{m.window_s:.0f}s   ",
                end="", flush=True,
            )
    except KeyboardInterrupt:
        print()
    finally:
        cap.stop()
    return 0

def cmd_devices(args) -> int:
    print(list_devices())
    return 0

def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="speaking-speed")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("monitor", help="print live metrics in the terminal").set_defaults(fn=cmd_monitor)
    sub.add_parser("devices", help="list audio input devices").set_defaults(fn=cmd_devices)
    args = ap.parse_args(argv)
    return args.fn(args)

if __name__ == "__main__":
    sys.exit(main())
```

**Step 3: Manual test**

```bash
uv run speaking-speed devices
uv run speaking-speed monitor
```
Expected: macOS asks to let Ghostty use the microphone (first time only). Then a single updating line. Sit silent: rate shows `--`, run `0.0`. Read a paragraph aloud at normal pace: rate lands roughly 3.5–5.5 syl/s, run climbs while you talk and resets to 0 after a half-second pause, glyph turns 🟡/🔴 only after ~1.5 s of sustained fast speech. Deliberately talk in a rush: 🔴. Pause and talk slowly with clear sentences: back to 🟢 after ~2 s.

If rate is wildly high in silence, the noise floor margin is too small: raise `speech_margin_db` to 10–12 in `~/.config/speaking-speed/config.toml` (create it with `speaking-speed` defaults; Task 5's `save` can be called from a Python one-liner) and record the value that works as the new default in `config.py`.

**Step 4: Commit**

```bash
git add src/speaking_speed/capture.py src/speaking_speed/cli.py
git commit -m "feat: mic capture and terminal monitor"
```

---

### Task 8: Session log + summary

**Files:**
- Create: `src/speaking_speed/session.py`, `tests/test_session.py`
- Modify: `src/speaking_speed/cli.py` (monitor writes a session; add `report`)

**Step 1: Write the failing tests `tests/test_session.py`**

```python
from pathlib import Path
from speaking_speed.metrics import Metrics
from speaking_speed.session import Session, summarize, load_summaries
from speaking_speed.zones import Zone

def _m(rate, run=0.0, pauses=0):
    return Metrics(10.0, 5.0, 20, rate, None, pauses, 0.4, run)

def test_session_writes_csv_and_summary(tmp_path: Path):
    s = Session(tmp_path, tick_s=0.5)
    s.record(_m(3.5, run=3.0), Zone.CALM)
    s.record(_m(4.8, run=16.0), Zone.FAST)
    s.record(_m(4.0, run=22.0), Zone.BRISK)
    summary = s.close()
    files = list(tmp_path.glob("*.csv"))
    assert len(files) == 1
    assert files[0].read_text().count("\n") == 4  # header + 3 rows
    assert summary.ticks == 3
    assert summary.pct_fast == 1 / 3
    assert summary.longest_run_s == 22.0
    assert summary.runs_over_15s == 1  # one run that went past 15 s (16 -> 22 is the same run)

def test_summarize_median_rate():
    rows = [_m(3.0), _m(4.0), _m(5.0), _m(None)]
    z = [Zone.CALM] * 4
    s = summarize(rows, z, tick_s=0.5)
    assert s.median_rate == 4.0
    assert s.p95_rate >= 4.9

def test_load_summaries_reads_back(tmp_path: Path):
    s = Session(tmp_path, tick_s=0.5)
    s.record(_m(3.5), Zone.CALM)
    s.close()
    summaries = load_summaries(tmp_path)
    assert len(summaries) == 1
    assert summaries[0].median_rate == 3.5
```

**Step 2: Run to verify failure**

```bash
uv run pytest tests/test_session.py -q
```
Expected: FAIL, `ModuleNotFoundError`.

**Step 3: Implement `src/speaking_speed/session.py`**

```python
"""Per-session CSV log and summary."""
from __future__ import annotations
import csv
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
import numpy as np
from .metrics import Metrics
from .zones import Zone

FIELDS = ["t", "zone", "articulation_rate", "current_run_s", "pauses", "phonation_s", "syllables"]

@dataclass(frozen=True)
class Summary:
    name: str
    ticks: int
    talk_s: float
    median_rate: float | None
    p95_rate: float | None
    pct_calm: float
    pct_brisk: float
    pct_fast: float
    longest_run_s: float
    runs_over_15s: int

def summarize(rows: list[Metrics], zones: list[Zone], tick_s: float, name: str = "") -> Summary:
    rates = [m.articulation_rate for m in rows if m.articulation_rate is not None]
    n = max(len(rows), 1)
    runs_over = 0
    above = False
    longest = 0.0
    for m in rows:
        longest = max(longest, m.current_run_s)
        if m.current_run_s >= 15.0 and not above:
            runs_over += 1
        above = m.current_run_s >= 15.0
    return Summary(
        name=name,
        ticks=len(rows),
        talk_s=sum(m.phonation_s for m in rows) * tick_s / max(rows[0].window_s, 1e-9) if rows else 0.0,
        median_rate=float(np.median(rates)) if rates else None,
        p95_rate=float(np.percentile(rates, 95)) if rates else None,
        pct_calm=sum(z == Zone.CALM for z in zones) / n,
        pct_brisk=sum(z == Zone.BRISK for z in zones) / n,
        pct_fast=sum(z == Zone.FAST for z in zones) / n,
        longest_run_s=longest,
        runs_over_15s=runs_over,
    )

class Session:
    def __init__(self, sessions_dir: Path, tick_s: float):
        sessions_dir.mkdir(parents=True, exist_ok=True)
        self.name = datetime.now().strftime("%Y-%m-%d-%H%M%S")
        self.path = sessions_dir / f"{self.name}.csv"
        self.tick_s = tick_s
        self._rows: list[Metrics] = []
        self._zones: list[Zone] = []
        self._fh = self.path.open("w", newline="")
        self._w = csv.writer(self._fh)
        self._w.writerow(FIELDS)

    def record(self, m: Metrics, z: Zone) -> None:
        self._rows.append(m)
        self._zones.append(z)
        self._w.writerow([
            round(len(self._rows) * self.tick_s, 1), int(z),
            "" if m.articulation_rate is None else round(m.articulation_rate, 3),
            round(m.current_run_s, 2), m.pauses, round(m.phonation_s, 2), m.syllables,
        ])

    def close(self) -> Summary:
        self._fh.close()
        return summarize(self._rows, self._zones, self.tick_s, self.name)

def load_summaries(sessions_dir: Path) -> list[Summary]:
    out = []
    for p in sorted(sessions_dir.glob("*.csv")):
        rows, zones = [], []
        with p.open() as fh:
            for r in csv.DictReader(fh):
                rate = float(r["articulation_rate"]) if r["articulation_rate"] else None
                rows.append(Metrics(10.0, float(r["phonation_s"]), int(r["syllables"]), rate, None,
                                    int(r["pauses"]), 0.0, float(r["current_run_s"])))
                zones.append(Zone(int(r["zone"])))
        out.append(summarize(rows, zones, 0.5, p.stem))
    return out

def format_summary(s: Summary) -> str:
    rate = "--" if s.median_rate is None else f"{s.median_rate:.2f} (p95 {s.p95_rate:.2f})"
    return (
        f"{s.name}: talk {s.talk_s/60:.1f} min · rate {rate} syl/s · "
        f"calm {s.pct_calm:.0%} brisk {s.pct_brisk:.0%} fast {s.pct_fast:.0%} · "
        f"longest run {s.longest_run_s:.0f}s · runs>15s {s.runs_over_15s}"
    )
```

Known simplification: `talk_s` is approximate (window overlap). Good enough for trend; note it in the report header.

**Step 4: Run tests**

```bash
uv run pytest tests/test_session.py -q
```
Expected: `3 passed`. If `talk_s` maths makes a test fail, the tests do not assert on it; the failing assertion is a real bug.

**Step 5: Wire into `cli.py`**

In `cmd_monitor`, after `sm = ZoneSmoother()` add `sess = Session(cfg.sessions_dir, cfg.tick_s)`; after computing `z`, call `sess.record(m, z)`; in `finally`, after `cap.stop()`, `print(format_summary(sess.close()))`. Add:

```python
def cmd_report(args) -> int:
    cfg = C.load()
    for s in load_summaries(cfg.sessions_dir)[-args.n:]:
        print(format_summary(s))
    return 0
```
and in `main`:
```python
rp = sub.add_parser("report", help="summaries of recent sessions")
rp.add_argument("-n", type=int, default=10)
rp.set_defaults(fn=cmd_report)
```
Imports: `from .session import Session, format_summary, load_summaries`.

**Step 6: Manual test**

```bash
uv run speaking-speed monitor   # talk 30 s, Ctrl-C
uv run speaking-speed report
```
Expected: one summary line on stop; `report` prints the same line; a CSV appears in `~/.local/share/speaking-speed/sessions/`.

**Step 7: Commit**

```bash
git add src/speaking_speed/session.py tests/test_session.py src/speaking_speed/cli.py
git commit -m "feat: session log and summary report"
```

---

### Task 9: Calibration

**Files:**
- Create: `src/speaking_speed/calibrate.py`, `tests/test_calibrate.py`
- Modify: `src/speaking_speed/cli.py`

Rufus reads a fixed passage at his *normal* pace for ~45 s. The median articulation rate becomes the anchor; calm upper bound = 0.9 × anchor, fast lower bound = 1.05 × anchor. (The point is to speak slower than his habit, so "calm" is below his normal.)

**Step 1: Write the failing test `tests/test_calibrate.py`**

```python
from speaking_speed.calibrate import thresholds_from_rates
from speaking_speed.zones import Thresholds

def test_thresholds_from_rates():
    t = thresholds_from_rates([4.0, 4.2, 4.4, 4.1, 4.3])
    assert isinstance(t, Thresholds)
    assert abs(t.calm_max_rate - 0.9 * 4.2) < 1e-9
    assert abs(t.fast_min_rate - 1.05 * 4.2) < 1e-9
    assert t.calm_max_run_s == 12.0

def test_thresholds_rejects_too_few():
    import pytest
    with pytest.raises(ValueError):
        thresholds_from_rates([4.0])
```

**Step 2: Run to verify failure**

```bash
uv run pytest tests/test_calibrate.py -q
```
Expected: FAIL, `ModuleNotFoundError`.

**Step 3: Implement `src/speaking_speed/calibrate.py`**

```python
"""Derive personal thresholds from a short read-aloud at normal pace."""
from __future__ import annotations
import time
import numpy as np
from .capture import Capture
from .config import Config
from .pipeline import Pipeline
from .zones import Thresholds

PASSAGE = (
    "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow. "
    "The rainbow is a division of white light into many beautiful colors. These take the shape "
    "of a long round arch, with its path high above, and its two ends apparently beyond the horizon. "
    "There is, according to legend, a boiling pot of gold at one end. People look, but no one ever "
    "finds it. When a man looks for something beyond his reach, his friends say he is looking for "
    "the pot of gold at the end of the rainbow."
)

def thresholds_from_rates(rates: list[float]) -> Thresholds:
    if len(rates) < 5:
        raise ValueError("need at least 5 rate samples")
    anchor = float(np.median(rates))
    return Thresholds(calm_max_rate=0.9 * anchor, fast_min_rate=1.05 * anchor)

def run_calibration(cfg: Config, seconds: float = 45.0) -> tuple[Thresholds, float]:
    p = Pipeline(cfg)
    cap = Capture(cfg, p)
    rates: list[float] = []
    print("Read this aloud at your NORMAL pace. Recording starts in 3 s.\n")
    print(PASSAGE + "\n")
    time.sleep(3)
    cap.start()
    t0 = time.time()
    try:
        while time.time() - t0 < seconds:
            time.sleep(cfg.tick_s)
            m = p.tick()
            if m.articulation_rate is not None and m.phonation_s >= 3.0:
                rates.append(m.articulation_rate)
            print(f"\r{seconds - (time.time() - t0):4.0f}s left  samples {len(rates):3d}", end="", flush=True)
    finally:
        cap.stop()
        print()
    return thresholds_from_rates(rates), float(np.median(rates))
```

**Step 4: Run tests**

```bash
uv run pytest tests/test_calibrate.py -q
```
Expected: `2 passed`.

**Step 5: Wire `calibrate` into `cli.py`**

```python
def cmd_calibrate(args) -> int:
    cfg = C.load()
    th, anchor = run_calibration(cfg, seconds=args.seconds)
    C.save(cfg.with_thresholds(calm_max_rate=th.calm_max_rate, fast_min_rate=th.fast_min_rate))
    print(f"normal rate {anchor:.2f} syl/s → calm < {th.calm_max_rate:.2f}, fast ≥ {th.fast_min_rate:.2f}. Saved to {C.DEFAULT_PATH}")
    return 0
```
and in `main`:
```python
cp = sub.add_parser("calibrate", help="read a passage to set personal thresholds")
cp.add_argument("--seconds", type=float, default=45.0)
cp.set_defaults(fn=cmd_calibrate)
```
Import: `from .calibrate import run_calibration`.

**Step 6: Manual test**

```bash
uv run speaking-speed calibrate
cat ~/.config/speaking-speed/config.toml
uv run speaking-speed monitor
```
Expected: thresholds saved; `monitor` now uses them (normal pace reads 🟡, slower reads 🟢).

**Step 7: Commit**

```bash
git add src/speaking_speed/calibrate.py tests/test_calibrate.py src/speaking_speed/cli.py
git commit -m "feat: calibration from a read-aloud passage"
```

---

### Task 10: Menu bar app

**Files:**
- Create: `src/speaking_speed/ui/__init__.py` (empty), `src/speaking_speed/ui/menubar.py`
- Modify: `src/speaking_speed/cli.py`

`rumps` must own the main thread; audio runs in the PortAudio callback thread; a `rumps.Timer` polls the pipeline every `tick_s`.

**Step 1: Implement `src/speaking_speed/ui/menubar.py`**

```python
"""Menu-bar indicator: glyph + rate, Start/Stop, Quit."""
from __future__ import annotations
import rumps
from ..capture import Capture
from ..config import Config
from ..pipeline import Pipeline
from ..session import Session, format_summary
from ..zones import Zone, ZoneSmoother, classify

GLYPH = {Zone.UNKNOWN: "⚪", Zone.CALM: "🟢", Zone.BRISK: "🟡", Zone.FAST: "🔴"}

class SpeakingSpeedApp(rumps.App):
    def __init__(self, cfg: Config):
        super().__init__("⚪ --", quit_button=None)
        self.cfg = cfg
        self.pipeline = Pipeline(cfg)
        self.capture = Capture(cfg, self.pipeline)
        self.smoother = ZoneSmoother()
        self.session: Session | None = None
        self.toggle_item = rumps.MenuItem("Start listening", callback=self.toggle)
        self.status_item = rumps.MenuItem("idle")
        self.status_item.set_callback(None)
        self.menu = [self.toggle_item, self.status_item, None, rumps.MenuItem("Quit", callback=self.quit)]
        self.timer = rumps.Timer(self.on_tick, cfg.tick_s)

    def toggle(self, _):
        if self.session is None:
            self.session = Session(self.cfg.sessions_dir, self.cfg.tick_s)
            self.smoother = ZoneSmoother()
            self.capture.start()
            self.timer.start()
            self.toggle_item.title = "Stop listening"
        else:
            self._stop()

    def _stop(self):
        self.timer.stop()
        self.capture.stop()
        summary = self.session.close()
        self.session = None
        self.title = "⚪ --"
        self.toggle_item.title = "Start listening"
        self.status_item.title = format_summary(summary)
        rumps.notification("Speaking Speed", "Session summary", format_summary(summary))

    def on_tick(self, _):
        m = self.pipeline.tick()
        z = self.smoother.update(classify(m, self.cfg.thresholds))
        self.session.record(m, z)
        rate = "--" if m.articulation_rate is None else f"{m.articulation_rate:.1f}"
        run = f" {m.current_run_s:.0f}s" if m.current_run_s >= self.cfg.thresholds.calm_max_run_s else ""
        self.title = f"{GLYPH[z]} {rate}{run}"
        self.status_item.title = f"rate {rate} syl/s · run {m.current_run_s:.0f}s · pauses {m.pauses}"

    def quit(self, _):
        if self.session is not None:
            self._stop()
        rumps.quit_application()

def run(cfg: Config) -> None:
    SpeakingSpeedApp(cfg).run()
```

**Step 2: Wire into `cli.py`**

```python
def cmd_run(args) -> int:
    from .ui.menubar import run
    run(C.load())
    return 0
```
and `sub.add_parser("run", help="menu bar app").set_defaults(fn=cmd_run)`.

**Step 3: Manual test**

```bash
uv run speaking-speed run
```
Expected: `⚪ --` appears in the menu bar. Click → Start listening. Title becomes `🟢 3.6` and updates twice a second; a run counter like `🟡 4.1 14s` appears once a run exceeds the calm run limit. Stop listening → macOS notification with the summary, and it stays in the menu. Quit works. Test on a real call with headphones for 10 minutes and note whether the glyph is noticeable enough; that decides whether Task 11 happens.

Known rumps gotcha: if the icon does not appear, the process is not a "UI element"; rumps sets this itself but only when run as the main thread of the process, which `uv run speaking-speed run` satisfies. If `rumps.notification` complains about a bundle identifier, delete that line; the summary is still in the menu and in `report`.

**Step 4: Commit**

```bash
git add src/speaking_speed/ui src/speaking_speed/cli.py
git commit -m "feat: menu bar app"
```

---

### Task 11 (optional): floating overlay pill

Only if, after a week, the menu-bar glyph is too easy to ignore. Design: a PyObjC `NSPanel` with `NSWindowStyleMaskNonactivatingPanel | Borderless`, level `NSFloatingWindowLevel`, `collectionBehavior = canJoinAllSpaces | fullScreenAuxiliary`, 140×36 px, bottom-right of the main screen, background colour = zone colour at 70 % alpha, text = rate and run. Toggle from the menu. Build it in `src/speaking_speed/ui/overlay.py` and drive it from `on_tick`. Write the plan for it when it is needed; do not build speculatively.

---

### Task 12: README + changelog

**Files:**
- Modify: `README.md`
- Create: `changelog/2026-09-XX-phase1-rate-monitor.md` (date = ship date)

README gets: what it measures (articulation rate, run length, pauses), install (`brew install uv portaudio; uv sync`), commands (`calibrate`, `monitor`, `run`, `report`), where config and sessions live, the headphones caveat, and a pointer to the design doc. Changelog entry per the convention in `AGENTS.md`, with a screenshot of the menu bar glyph.

```bash
git add README.md changelog
git commit -m "docs: README and changelog for phase 1"
```

---

## Acceptance for phase 1

- `uv run pytest -q` green (≈ 25 tests).
- `speaking-speed calibrate` writes personal thresholds.
- `speaking-speed run` shows a glyph that goes 🟢/🟡/🔴 in a way Rufus agrees matches how he was speaking, on a real call, with headphones.
- `speaking-speed report` shows per-session summaries with % fast and longest run.
- Decision recorded (in a beads note) after one week of use: keep, add overlay, or go to phase 2 (words).

## Phase 2 sketch (not planned in detail yet)

`brew install whisper-cpp`, download `ggml-base.en.bin`, spawn `whisper-stream -m … --step 500 --length 5000 -t 4` reading the same device, parse its stdout lines, compute wpm over the window, count fillers (`um`, `uh`, `you know`, `like` as a discourse marker), and flag runs > 30 words without sentence-final punctuation. Keep the transcript in the session folder. Then a `review` command that sends transcript + CSV to Claude for a 5-line coaching note. Swift + Apple `SpeechAnalyzer` remains the better engine if Xcode 26 ever gets installed; the pipeline boundaries above make swapping the words source cheap.
