# vision/

Python side. Tracks two hands and reports where they are. **That is all it does.**

It does not know what a note is, never sees the chart, and never decides "that
was a hit." See [`../PROTOCOL.md`](../PROTOCOL.md) for the contract.

## Run

```bash
pip install -r requirements.txt

python3 -m vision.main --probe     # camera diagnostics — DO THIS FIRST
python3 -m vision.main --debug     # tracking + debug window
python3 -m vision.main --no-emit   # run without sending packets
```

## Pipeline

```
capture ─→ tracker.detect ─→ slots.assign ─→ OneEuro ─→ HandReport ─→ emit
   │             │                │              │           │
capture.py   trackers/       slots.py       filters.py    hands.py
                                                          emitter.py
```

Each stage is replaceable without touching the others.

## What's written vs. what's yours

| Done | Yours |
|---|---|
| `capture.py` — threaded capture + the buffer fix | `trackers/color.py` → `detect()` |
| `filters.py` — One Euro | `slots.py` → `assign()` |
| `emitter.py` — the wire format | calibration |
| `hands.py` — the state machine | debug window |

The two `NotImplementedError`s are the real work. Both have the requirements
written out in their docstrings.

## Before you write any tracking code

Run `--probe` and look at the numbers. It reports what the camera actually
accepted (drivers silently refuse your settings) and measures real throughput
with a timed loop, because `CAP_PROP_FPS` reports what the driver claims rather
than what you get.

Watch the **p95 vs median** frame interval. That gap is jitter, and jitter is
the number that matters — constant latency calibrates away, variance does not.
