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

Step 1 implemented: two bare hands tracked with MediaPipe. Your anatomical
left palm controls the left cursor; your right palm controls the right cursor.
Godot integration is still to come.

## Run the palm tracker

From the `rhythmgame` directory in PowerShell:

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r vision/requirements.txt
.\.venv\Scripts\python.exe vision/download_model.py
.\.venv\Scripts\python.exe vision/vertical_demo.py
```

Dependencies and the model are already installed in this checkout's `.venv`.
Use that Python executable rather than the system Python. Model download is
one-time setup; inference processes camera frames locally. The downloaded model
is ignored by Git. `--model path/to/hand_landmarker.task` selects another copy.

1. Face the webcam and show both open palms with your fingers visible.
2. Raise only your left palm: the left cursor should move up. Repeat with the
   right. No colored objects are needed; cyan/red are only cursor colors.
3. Press **D** for the separate camera debug window with palm landmarks, center
   points, and assigned labels. **Q** or **Esc** quits.
4. Remove one hand: its lane says **NOT DETECTED** while the other works.

The normal cursor view contains no camera image. `--debug` enables the debug
window at startup; `--camera 1` selects another webcam. `--video path/to/clip.mp4`
processes a recording as fast as possible, not as real-time replay.
Input is mirrored once before inference; use an ordinary unmirrored camera/clip
so handedness identifies the player's anatomical hands correctly.

### How this step works

`vision/vertical_demo.py` handles capture and display. `vision/hand_detector.py`
converts BGR to RGB and runs MediaPipe Tasks Hand Landmarker in VIDEO mode with
a maximum of two hands. Palm position averages landmarks 0, 5, 9, 13, and 17:
the wrist and four finger bases. Fingertips do not drive the cursor.

Handedness establishes identity at acquisition (minimum score 0.65). Subsequent
frames use one-to-one nearest-position association with a motion gate to resist
momentary label flips. History expires after 200 ms without a match; reacquisition
uses handedness again. Missing observations are immediately hidden. Full overlap,
occlusion, or incorrect initial classification can still confuse identity;
briefly remove both hands and present them separately to reacquire. Handedness
score measures left/right certainty, not hand-presence confidence.

Coordinates remain **uncalibrated image coordinates**: x increases right in the
mirrored image, y=0 is the top, y=1 is the bottom. Both axes are measured but only
y drives the cursors. These are not yet post-calibration wire-protocol values.

The panel measures loop FPS and detection time, not end-to-end latency. Camera
setting requests and readbacks print at startup; support varies by backend.
Exposure and buffering still need hardware tuning.

Camera-free tests use synthetic landmark results:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s vision -v
```

Reference: [MediaPipe Hand Landmarker Python guide](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/python).

Next steps: latest-frame capture; TRACKED/COASTING/LOST states; reach calibration
and smoothing; then UDP observations. There are no game judgments or UDP output yet.

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
