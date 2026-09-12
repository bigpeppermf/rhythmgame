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

## Setup (once per machine)

We are a cross-platform team: macOS, Linux, and Windows all work. Run everything
from the `rhythmgame` directory. Pick **one** of the two routes below — they
produce the same `.venv`.

Neither `.venv/` nor `vision/models/` is committed (both are in `.gitignore`), so
a fresh clone never arrives with them. Everyone runs this once.

### Route A — uv (recommended: one set of commands on all three platforms)

```bash
uv venv
uv pip install -r vision/requirements.txt
uv run vision/download_model.py
```

If you don't have uv yet:

| Platform | Install uv |
|---|---|
| macOS / Linux | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Windows (PowerShell) | `powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 \| iex"` |
| Homebrew | `brew install uv` |

`uv venv` downloads a suitable CPython for you if the system one is too old or
missing, which is why the commands don't change per OS. `uv run` discovers
`.venv` by itself — there is nothing to activate.

### Route B — stock Python and pip

**macOS / Linux** (needs Python 3.10+; on Debian/Ubuntu also `sudo apt install python3-venv`):

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r vision/requirements.txt
.venv/bin/python vision/download_model.py
```

**Windows (PowerShell)**:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r vision/requirements.txt
.\.venv\Scripts\python.exe vision/download_model.py
```

Use that venv Python, never the system Python — recent macOS and Ubuntu refuse
system-wide `pip install` outright (PEP 668, "externally-managed-environment").

### How to read the commands in the rest of this README

Later sections write plain `python vision/...`. Make that work in either of two
ways, whichever you prefer:

- prefix every command with `uv run` (`uv run vision/vertical_demo.py`), or
- activate the venv once per terminal, then use `python` directly:

| Shell | Activate |
|---|---|
| bash / zsh (macOS, Linux) | `source .venv/bin/activate` |
| fish | `source .venv/bin/activate.fish` |
| PowerShell (Windows) | `.\.venv\Scripts\Activate.ps1` |
| cmd.exe (Windows) | `.\.venv\Scripts\activate.bat` |

If PowerShell blocks the activation script, run
`Set-ExecutionPolicy -Scope Process RemoteSigned` in that window first, or just
use `uv run` and skip activation entirely.

The model download is one-time. Inference runs locally on your machine; nothing
is uploaded. `--model path/to/hand_landmarker.task` points at another copy.

## Run the palm tracker

```bash
python vision/vertical_demo.py
# or, without activating: uv run vision/vertical_demo.py
```

### Choosing the camera

`--camera 0` is the default, and it is **not** always the camera you want.
Virtual cameras (Iriun, OBS, Camo, EpocCam, Snap) tend to claim a low index and
fail to open when their app or phone is not streaming. That shows up as:

```
Input demo failed: Cannot open input. Close other camera apps or try --camera 1.
```

Work up through `--camera 1`, `--camera 2` until you see yourself in the debug
window (**D**). Per platform:

- **Linux** — `v4l2-ctl --list-devices` maps indices to devices. On this
  checkout's machine index 0 is an Iriun `v4l2loopback` device and the built-in
  webcam is **index 1**, so the demo needs `--camera 1`.
- **macOS** — the first run must be allowed under System Settings → Privacy &
  Security → Camera for *the terminal app you launched from* (Terminal, iTerm,
  VS Code), not for Python itself. Without that approval the device opens but
  every frame is black.
- **Windows** — quit Zoom/Teams/OBS first; most webcams allow only one
  DirectShow consumer at a time.

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
State updates occur only for fresh processed frames. During a camera stall the
panel hides cursors after 200 ms and the sender stops publishing. Receivers use
their own packet timeout in addition to the hand tracking states.

Coordinates remain **uncalibrated image coordinates**: x increases right in the
mirrored image, y=0 is the top, y=1 is the bottom. Both axes are measured but only
y drives the cursors. These are not yet post-calibration wire-protocol values.

The panel measures loop FPS and detection time, not end-to-end latency. Camera
setting requests and readbacks print at startup; support varies by backend.
Exposure and backend buffering still need hardware measurements.

### Latest-frame webcam capture

Use the [live camera checklist](vision/LIVE_CAMERA_CHECKLIST.md) to check controls,
hand loss, capture performance, UDP, and shutdown. It includes a results table
and explicitly marks bystander rejection as a known failing area: player ownership
is not yet implemented.

`vision/capture.py` reads the live webcam on a dedicated thread. Each captured
image replaces a single latest-frame slot. If inference is slower than capture,
intermediate frames are skipped rather than queued. A frame already handed to
the detector remains stable while the capture thread publishes newer ones.
There is no new command to enable this: live webcam input uses it by default.
Recorded files (`--video`) remain sequential so their frames are not discarded.

The capture worker records `perf_counter()` immediately after each `read()`;
that timestamp travels with the frame into detection, hand states, and UDP.
Each frame is processed at most once. UDP `seq` still counts send attempts, not
camera frames: skipped camera images do not introduce UDP sequence gaps.

The panel adds three measurements:

- **Capture FPS:** actual worker read rate; **Loop FPS** remains the processing
  rate and is still the `fps` value in UDP. Both start at zero while measuring.
- **Skipped:** total captured frames superseded before the detector consumed them.
  This is expected when capture is faster than detection.
- **Wait:** milliseconds from read completion to selecting the frame for detection.
  It excludes exposure, camera/driver buffering, and detection time; it is not
  an end-to-end latency measurement.

The UI polls for frames with short waits, so Q/Esc still works during camera
stalls. No repeated stale snapshots are transmitted. After 2 seconds without
a frame, the demo exits with an error. A read failure also exits with an error.
The capture worker owns camera release. Shutdown waits up to 1 second for it;
if a native driver hangs inside `read()`, the demo reports that condition and
the daemon worker releases the camera if the call returns. The main thread
does not try to release a camera while another thread is reading it.

The demo still requests `CAP_PROP_BUFFERSIZE=1`, but backend acceptance varies.
The thread removes the application's growing backlog; actual hardware latency
still needs a webcam check. Try fast hand motion and compare Capture FPS, Loop
FPS, Skipped, and Wait. Tests use controlled fake cameras, not live hardware.

Camera-free tests use synthetic landmark results and controlled capture timestamps:

```bash
python -m unittest discover -s vision -v
# or: uv run python -m unittest discover -s vision -v
```

These need no webcam and no model file, so they are the fastest way to confirm a
fresh setup on any platform. All 21 should pass.

Reference: [MediaPipe Hand Landmarker Python guide](https://ai.google.dev/edge/mediapipe/solutions/vision/hand_landmarker/python).

### Step 2: send and receive UDP

In one terminal, from `rhythmgame`, run:

```bash
python vision/udp_receiver.py
# or: uv run vision/udp_receiver.py
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

Reach calibration and smoothing remain future work.

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
