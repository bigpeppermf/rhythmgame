# (untitled rhythm game)

A rhythm game where **the webcam is the controller**. Two hands are tracked by
computer vision; you move them to intercept notes flying toward you down a 3D
perspective highway.

The camera feed is never shown. It is purely an input device — the game screen
is a completely separate rendered interface.

```
┌──────────────┐   UDP    ┌──────────────────┐
│  Python      │  ~60Hz   │  Godot 4         │
│  OpenCV /    │ ───────► │  all game logic  │
│  MediaPipe   │  JSON    │  + rendering     │
└──────────────┘          └──────────────────┘
  reports WHERE              decides WHAT IT MEANS
  the hands are
```

## The one rule

**The vision side emits observations. It never emits game events.**

It doesn't know what a note is, never sees the chart, and never decides "that
was a hit." It reports two hand positions with confidence and a capture
timestamp, and stops.

This is what lets three people work in parallel from day one: the gameplay
programmer builds the entire game against a mouse-driven mock producer, and the
real tracker drops in later without changing a line of game code.

## Status

Design phase. No implementation yet.

**Read [`PROJECT_BRIEF.md`](PROJECT_BRIEF.md) first** — it has the wire
protocol, the latency analysis, the vision rules, and the Godot architecture.

## Who owns what

| | Owns | Works against |
|---|---|---|
| **Vision** | Python capture, tracking, slot assignment, filtering, UDP emit | a recorded video file |
| **Gameplay** | Conductor, chart loading, spawning, Judge, scoring | `MockHandSource` (mouse) |
| **Feel & content** | 3D visuals, audio, feedback, chart tooling, calibration screen | the note scene contract |

## Open questions

- 1 axis of hand control, or 2? (decides whether the Judge is a 1D or 2D overlap test)
- Note vocabulary — taps only, or holds and traces?
- Chart format specifics
- Scoring — binary hit/miss, or graded by how much of the window was satisfied?

## Running

```bash
cd game && godot .        # F5 — menu → play → results
```

| Scene | |
|---|---|
| `scenes/main.tscn` | entry point; owns the flow |
| `scenes/play_3d.tscn` | the game |
| `scenes/calibrate.tscn` | measures input offset — **run this first on new hardware** |
| `scenes/play_test.tscn` | same logic, flat 2D, for debugging judgement |
| `scenes/clock_test.tscn` | Conductor jitter/drift graph |

```bash
godot --headless res://tests/judge_test.tscn   # 16 tests — chart, judging, scoring
godot --headless res://tests/flow_test.tscn    # 28 tests — scenes, settings, stats
godot res://tests/shot.tscn                    # render screenshots
python3 ../tools/mock_sender.py --lose 3       # fake camera over real UDP
```

## Replacing the look

All presentation lives behind a `GameSkin` resource. Duplicate
`game/visual/default_skin.tres`, point its scene slots at your own scenes, and
set `Settings.skin_path`. Your scenes implement `NoteView`, `CursorView` or
`FlashView` — three tiny interfaces, none of which know what a chart, a beat or
a score is.

`game/visual/example_alt/` is a worked example that renders the same score at
the same timestamp as the default. See [`game/visual/README.md`](game/visual/README.md).

## Calibration

The camera pipeline runs 50–150ms behind reality. Nearly all of that is
*constant*, and constant delay is an offset problem rather than a latency one:
measure it once, judge against `song_time - offset`, and it stops mattering.
What survives is jitter, which is small enough to live with.

`scenes/calibrate.tscn` measures it — two targets alternate on every beat, so
the pattern is predictable and the player anticipates rather than reacts. The
median of ~20 swings becomes `Settings.input_offset`.
