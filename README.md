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
Each hand now has persistent TRACKED/COASTING/LOST state and velocity.
The demo now sends both slots as JSON over UDP to 127.0.0.1:5005 by default.
A Python diagnostic receiver is included; Godot integration is owned by gameplay.

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
4. Remove one hand: its cursor briefly holds and fades (**COASTING**), then
   disappears at 200 ms (**LOST**), while the other hand continues working.
5. Show the missing palm again: it returns to **TRACKED**, with velocity reset
   to zero for the first observation after the interruption.

The normal cursor view contains no camera image. `--debug` enables the debug
window at startup; `--camera 1` selects another webcam. `--video path/to/clip.mp4`
processes a recording as fast as possible, not as real-time replay.
Input is mirrored once before inference. The detector swaps the model's Left/Right
labels before slot assignment to correct the reversed controls observed in this
setup. Use an ordinary unmirrored camera/clip and restart the demo after changes.

### How this step works

`vision/vertical_demo.py` handles capture and display. `vision/hand_detector.py`
converts BGR to RGB and runs MediaPipe Tasks Hand Landmarker in VIDEO mode with
a maximum of two hands. Palm position averages landmarks 0, 5, 9, 13, and 17:
the wrist and four finger bases. Fingertips do not drive the cursor.

Handedness establishes identity at acquisition (minimum score 0.65). Subsequent
frames use one-to-one nearest-position association with a motion gate to resist
momentary label flips. History expires after 200 ms without a match; reacquisition
uses handedness again. Missing detections enter the state layer below. Full overlap,
occlusion, or incorrect initial classification can still confuse identity;
briefly remove both hands and present them separately to reacquire. Handedness
score measures left/right certainty, not hand-presence confidence.

### Step 1: persistent hand state

`vision/hand_state.py` consumes the two accepted positions (or `None`) and the
capture timestamp, independently of MediaPipe. It always returns two immutable
`HandState` snapshots, with slot, position, velocity, last_seen, state, and confidence.
Both slots start LOST, with zero confidence and a placeholder position of (0.5, 0.5).

| Observation | State | Position and velocity | Confidence |
|---|---|---|---|
| Valid palm this frame | TRACKED | Update position; estimate velocity | 1.0 |
| Missing for less than 200 ms | COASTING | Hold position; zero velocity | Linear fade to zero |
| Missing for 200 ms or more | LOST | Retain position only as a placeholder; zero velocity | 0.0 |

The timeout uses elapsed capture time since the last accepted detection, not
frame counts. Missing frames never refresh `last_seen`. Confidence is a defined
usability weight, not a probability or MediaPipe handedness score. A stationary
visible palm remains TRACKED. Velocity is position change divided by capture-time
change, in image units/second; upward motion has negative vy. It resets at first
acquisition, after any missing observation, or after a gap of at least 200 ms.

The cursor panel shows each state, confidence, and vx/vy. COASTING holds and fades
the cursor; LOST hides it. Debug landmarks are drawn only for fresh detections.
State updates occur as frames are processed; a blocked camera read will still
freeze the loop until capture threading is implemented. Receivers therefore need
their own packet timeout in addition to these hand tracking states.

Coordinates remain **uncalibrated image coordinates**: x increases right in the
mirrored image, y=0 is the top, y=1 is the bottom. Both axes are measured but only
y drives the cursors. These are not yet post-calibration wire-protocol values.

The panel measures loop FPS and detection time, not end-to-end latency. Camera
setting requests and readbacks print at startup; support varies by backend.
Exposure and buffering still need hardware tuning.

Camera-free tests use synthetic landmark results and controlled capture timestamps:

```powershell
.\.venv\Scripts\python.exe -m unittest discover -s vision -v
```

Reference: [MediaPipe Hand Landmarker Python guide](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/python).

### Step 2: send and receive UDP

In one terminal, from `rhythmgame`, run:

```powershell
.\.venv\Scripts\python.exe vision/udp_receiver.py
```

In another, run the demo normally. The receiver prints both hand states and
positions. Add `--json` to the receiver to inspect full JSON snapshots. Stop
the demo to check the receiver's 500 ms disconnect timeout. Stop the diagnostic
receiver before Godot uses the same port.

The demo sends one packet per processed frame, including when both hands are
LOST. Use `--host ADDRESS --port 5005` to change destination, or `--no-udp` to
disable sending. Sending never waits for a receiver and does not retry old frames.

Share [vision/UDP_PROTOCOL.md](vision/UDP_PROTOCOL.md) with the Godot teammate:
it documents the exact fields, coordinate conventions, receiver behavior,
sender restarts, and same-computer/LAN setup. No new dependencies are required.

Latest-frame capture, reach calibration, and smoothing remain future work.

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
