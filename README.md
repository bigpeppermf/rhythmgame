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
cd game && godot .          # F5 — playfield, mouse-driven
python3 tools/mock_sender.py --pattern circle --lose 3   # fake camera over real UDP
godot --headless res://tests/judge_test.tscn             # Judge test suite
```
