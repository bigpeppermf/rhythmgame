# Rhythm Game — Project Brief / Context Prompt

Paste this into a fresh session or share with teammates to bring anyone up to speed.

---

## The project

A hackathon rhythm game where a **webcam is the controller**. Two hands are
tracked by computer vision; the player moves their hands to intercept notes
flying toward them on a 3D perspective "highway." Built by a **3-person team**.

**Stack:** Python (OpenCV, optionally MediaPipe) for hand tracking → UDP →
Godot 4 for all game logic and rendering.

## Locked decisions

1. **The camera feed is never displayed.** The webcam is purely an input
   device. The game screen is a separate rendered 3D interface. There is no
   AR, no overlay, no camera/game space alignment problem.

2. **Two independently tracked hands**, covering a symmetric left/right
   highway. Notes arrive on both sides; each hand covers its own side.

3. **Perspective 3D view** — notes approach the player from depth, Guitar
   Hero / Beat Saber style, rather than a flat 2D scroll.

4. **Gestures are cut from v1.** Position-only. Gestures are a stretch goal.
   This means there is NO discrete trigger event — a "hit" is positional
   overlap during a time window, which is the most latency-tolerant design
   possible.

5. **Latency is solved by calibration, not by engineering.** (See below.)

## The central constraint: latency

A webcam pipeline runs ~150-200ms naive, ~50-70ms tuned. A traditional
rhythm game wants ±50ms. The resolution:

- **Constant latency is an offset problem, not a latency problem.** Judge
  against `song_time - measured_latency`, or nudge the audio. Every rhythm
  game already ships this calibration screen.
- **What survives calibration is jitter** (frame-to-frame variance), roughly
  ±8-15ms on a tuned pipeline. That is inside tolerance for overlap-based
  judgment.
- Therefore the real optimization target is **variance, not mean latency.**
  Chasing mean latency past the point calibration handles is wasted time.

### Latency budget

| Stage | Naive | Tuned | Fix |
|---|---|---|---|
| Exposure | 5-30ms | ~5ms | Lock exposure short |
| Frame period | 33ms | 8-16ms | MJPG fourcc + low res → 60/120fps |
| **Buffer backlog** | **0-130ms** | **0ms** | **Drain buffer / capture thread** |
| Detection | 10-30ms | 5-10ms | model_complexity=0, low res, ROI |
| IPC | <1ms | <1ms | UDP localhost |
| Render + display | ~20ms | ~12ms | Mostly fixed |

The buffer backlog row is most of the win and is not a CV problem —
`cv2.VideoCapture` queues frames internally, so a loop slightly slower than
the camera falls permanently behind.

### Optional: predictive compensation
An alpha-beta or constant-velocity Kalman filter gives smoothing and velocity
in one pass, enabling `pos_now ≈ pos_measured + velocity × latency`.
**Caveat:** a predictor is maximally wrong at direction reversals — which is
exactly where hits happen. Compensate 50-70% of measured latency, never 100%.

## Vision module contract

**Governing rule: the CV side reports observations. It never emits game
events.** It does not know what a note is, never sees the chart, never
decides "that was a hit."

Why this boundary matters:
- A teammate builds the whole game with a mouse-driven mock producer
- Sessions can be recorded to a file and replayed, making bugs reproducible
- Colored blobs → MediaPipe becomes a one-file swap
- Judgment needs the song clock, which only Godot has — Python
  *cannot* judge correctly

### Wire protocol (UDP, localhost, fire-and-forget, no retries)

```jsonc
{
  "seq": 4821,              // frame counter — lets Godot detect drops
  "t_capture": 18461.2044,  // perf_counter at cap.read(), NOT at send time
  "fps": 58.7,
  "hands": [
    { "slot": 0,            // 0 = left, 1 = right; STABLE across frames
      "x": 0.34, "y": 0.71, // normalized [0,1], post-calibration
      "vx": -1.2, "vy": 0.3,// normalized units/sec
      "conf": 0.93,
      "state": "TRACKED" }, // TRACKED | COASTING | LOST
    { "slot": 1, "x": 0.68, "y": 0.55, "vx": 0.0, "vy": 0.1,
      "conf": 0.41, "state": "COASTING" }
  ]
}
```

A dropped packet is a stale frame; stale beats late. Always take the newest.

### The six rules the vision side must answer explicitly

1. **What is a valid detection?** Four gates: confidence threshold; size
   sanity (area in range); shape sanity (a held ball is roughly round); and a
   **velocity gate** — if a candidate requires a physically impossible jump
   (>~2 normalized units/sec), it is a different object. Reject and coast.

2. **How are detections assigned to slots?** Nearest-neighbor to each slot's
   last position, with a max association distance. Never bind both slots to
   one detection. **Do not trust MediaPipe's Left/Right label** — it flips
   when hands cross or occlude. Continuity beats classification: the model
   reasons about one isolated frame, you know the hand didn't teleport since
   16ms ago.

3. **What happens on loss?** Three states — TRACKED → COASTING (hold/briefly
   extrapolate, decay confidence) → LOST after ~200ms (conf = 0, Godot dims
   the cursor and stops penalizing). **Never silently emit a stale position
   as if it were fresh.**

4. **What is the coordinate space?** Player-defined via a calibration screen
   (reach high, low, wide). Map ~**85%** of measured reach to the full play
   area, not 100% — if the extremes demand max extension they'll fatigue in
   one song. Allow slight overshoot past the bounds.

5. **Where does filtering live?** **Filter in Python, extrapolate in Godot.**
   Python has the highest sample rate (right place for One Euro / alpha-beta);
   Godot has the highest frame rate (right place to smooth between samples).
   One Euro is specifically correct here — it smooths hard when slow, barely
   at all when fast, so it kills resting jitter without adding lag to strikes.

6. **What must be visible?** A toggleable debug window: mask, candidate blobs,
   slot assignments, calibration box, live FPS. This is how you re-tune in
   sixty seconds when the venue lighting is wrong.

### What to actually look for

**Colored objects (recommended for v1):**
- **HSV, never RGB** — HSV separates color from brightness, so thresholds
  survive someone opening a door
- Two hues **≥60° apart**, far from skin tone and from clothes/walls.
  Saturated cyan + magenta are good. **Avoid red** — skin is full of red
- Morphological **open then close** (open kills speckle, close fills holes)
- Centroid from **image moments**, not bounding-box center — sub-pixel, steadier
- Two distinct colors makes Rule 2's association problem vanish entirely

**MediaPipe (the upgrade path):**
- Never use a fingertip — jitteriest landmarks on the hand
- Use the **centroid of the five palm landmarks** (wrist 0, MCPs 5/9/13/17).
  Averaging five noisy estimates of a rigid structure is free noise reduction
- `model_complexity=0`, `max_num_hands=2`
- Keep tracking alive — losing the hand re-runs the expensive palm detector
  and spikes latency exactly when you can least afford it
- Note: **OpenCV alone cannot track a bare hand or classify gestures.** That's
  MediaPipe. OpenCV covers capture, colored blobs, ArUco markers

### Camera setup non-negotiables
```python
cap = cv2.VideoCapture(0, cv2.CAP_V4L2)                        # force backend
cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*'MJPG'))  # often 30→60fps
cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)                            # + capture thread
cap.set(cv2.CAP_PROP_AUTO_EXPOSURE, 0.25)                      # manual (V4L2)
cap.set(cv2.CAP_PROP_EXPOSURE, <low>)                          # sharp + fast
# Resolution: 320x240 or 640x480. You are extracting ONE NUMBER, not a photo.
```
Autoexposure is a latency *and* blur amplifier — in dim light it lengthens
exposure, slowing frame delivery and smearing the moving hand.
Verify settings stick by reading the properties back; cameras silently refuse.

## Godot architecture

```
Conductor (autoload)      → authoritative song_time, the one clock
HandState (autoload)      → 2 slots: smoothed pos, velocity, confidence, state
  ├─ UdpHandSource        → real input (PacketPeerUDP, drain queue, take newest)
  └─ MockHandSource       → mouse/keyboard, for parallel development
Chart (Resource)          → sorted note array, beat→seconds at load
NoteSpawner               → windowed spawn from sorted array + object pool
Judge                     → samples HandState against active notes (2D overlap)
ScoreState                → combo, accuracy, health
```

### Two rules that are not negotiable

**1. Never use `delta` for the song clock.** Accumulated delta drifts from the
audio hardware within seconds. Use:
```gdscript
song_time = audio_player.get_playback_position() \
          + AudioServer.get_time_since_last_mix() \
          - AudioServer.get_output_latency()
```
(Smooth it — `get_playback_position()` updates in chunks.)

**2. Never derive note position from velocity.** Every note's position is a
pure function of song time:
```gdscript
z = -(note.time - song_time) * scroll_speed
```
If you instead do `position.z -= speed * delta`, one dropped frame desyncs the
entire chart permanently. Pure functions of the clock self-heal. The 3D
perspective view changes rendering only — same function, different axis.

## Chart design consequence

With no discrete trigger, **difficulty comes from hand travel distance, not
note density.** Two notes 80ms apart at the same position are trivial. Two
notes 400ms apart at opposite extremes may be physically impossible.

The chart format needs a notion of **reachability** — a max safe
`Δposition / Δtime` — and the chart tooling should flag violations. This is a
real thing to build, not a nice-to-have.

## Team split (3 people, parallel from day one)

| Person | Owns | Unblocked because |
|---|---|---|
| **A — Vision** | Python capture, tracking, slot assignment, filtering, UDP emit | Tests against a recorded video file + terminal visualizer |
| **B — Gameplay** | Godot: Conductor, chart loading, spawning, Judge, scoring | Builds the entire game against MockHandSource (mouse) |
| **C — Feel & content** | Godot: 3D visuals, audio, feedback, chart authoring + reachability linter, calibration screen | Needs only B's note scene contract |

**The single most important day-one artifact is the wire protocol above.**
Writing it down first converts a serial dependency into three parallel tracks.

## First-two-hours checklist (measurement, not features)

- [ ] Actual sustained FPS, timed in your own loop (`CAP_PROP_FPS` lies)
- [ ] Does `BUFFERSIZE=1` hold, or is a capture thread required?
- [ ] Does MJPG stick? What FPS does it unlock?
- [ ] Can exposure be locked? Lowest usable value in the demo room?
- [ ] Rough glass-to-number latency (wave sharply, eyeball the delay)
- [ ] Per-frame processing time for the chosen tracker
- [ ] **Does tracking survive the actual lighting of the actual demo venue?**

That last one is not a joke. HSV thresholds tuned at 2am under a desk lamp
fail under judging-room fluorescents. Build the calibration screen partly so
you can re-tune on-site in sixty seconds.

## Still open

- Does the hand control 1 axis or 2? (decides whether Judge is 1D or 2D overlap)
- Note vocabulary: taps only, or holds and traces too?
- Chart format specifics — beat-based authoring, seconds at runtime
- Scoring model: binary hit/miss, or graded by % of window satisfied?
