# Hand observations: Python to Godot

The demo now sends UTF-8 JSON in one UDP datagram per processed camera frame.
Default destination: **127.0.0.1:5005** (same computer). No acknowledgment,
retransmission, camera image, or game event is sent. Godot owns judgment/scoring.

## Packet

```json
{
  "seq": 42,
  "t_capture": 18461.2044,
  "fps": 30.2,
  "hands": [
    {"slot": 0, "x": 0.3, "y": 0.4, "vx": 0.0, "vy": -0.5, "conf": 1.0, "state": "TRACKED"},
    {"slot": 1, "x": 0.7, "y": 0.6, "vx": 0.0, "vy": 0.0, "conf": 0.0, "state": "LOST"}
  ]
}
```

- `seq`: starts at 0 per sender process, increments per send attempt (even a
  local send failure). Gaps are allowed; never wait for a missing packet.
- `t_capture`: Python `perf_counter()` seconds immediately after `cap.read()`.
  This is read-completion time, not sensor exposure time or send time. Each
  snapshot retains its capture timestamp through inference and serialization.
  Live webcam capture now runs on a thread holding only the latest frame. The
  timestamp belongs to that selected frame; unprocessed camera frames are skipped.
- `fps`: measured processing-loop rate, updated about once a second. Initially 0.
  The separate Capture FPS shown in the demo is not transmitted. `seq` counts
  packet attempts, not captured frames; capture skips do not cause sequence gaps.
- `hands`: always two slots, 0 = anatomical left, 1 = anatomical right. Use the
  slot field for assignment. Both can be LOST, including at startup.
- `x/y`: currently **uncalibrated**, normalized mirrored image coordinates in
  [0,1]. x increases right; y increases down. Reach calibration is future work;
  this is the current deviation from the brief's post-calibration contract.
- `vx/vy`: image units per second. Upward movement gives negative vy. Zero while
  missing, at first detection, and on reacquisition after an interruption.
- `conf`: usability weight, not model probability. TRACKED = 1, COASTING fades
  linearly to 0 across 200 ms since last detection, LOST = 0.
- `state`: TRACKED, COASTING, or LOST. COASTING holds position; LOST position is
  only a placeholder and must not be treated as a usable hand.

## Receiver behavior for the Godot teammate

### Optional gesture extension

`vertical_demo.py --gestures` adds two fields per hand:

```json
{"gesture": "FIST", "gesture_conf": 0.91}
```

Allowed labels: OPEN_PALM (normal input), FIST, THUMBS_UP, PINCH, and UNKNOWN
(uncertain/unrecognized/missing, not an action). Plain mode has neither field.
This is an opt-in CV extension; game-side gesture handling still needs integration.
Default ports remain unchanged (vision 5005; game currently 9000); use the CLI
override until the team agrees which default should move.

`gesture_conf` is separate from `conf`: it describes model or geometric evidence
for the label and decays while briefly bridging uncertain classifications. It is
not a calibrated probability and scores are not directly comparable across classes.
UNKNOWN has gesture_conf=0. COASTING and LOST always carry UNKNOWN, even though
COASTING retains position. New gestures confirm over 40 ms; uncertain classifications
can retain the previous gesture for at most 100 ms since its last support only
while the hand is still detected. Pinch has separate entry/release thresholds.

FIST does not certify a specific camera-facing orientation. PINCH estimates
thumb/index-tip proximity with the middle, ring, and little fingers loosely curled and
the index reaching toward the thumb (a closed-hand pinch). An open-hand OK sign
is not PINCH. Both need real-camera validation. These fields report
poses only; they do not report hits, presses, or rising-edge events. Godot owns
action transitions and judgment, and must also clear gestures on packet timeout.

### Position and state reception

1. Bind a `PacketPeerUDP` to port 5005 on 127.0.0.1 for same-computer testing.
2. Each game frame, read queued datagrams, decode UTF-8, parse JSON, and validate
   the expected fields. Read raw packet bytes, not Godot's Variant wire format.
3. Keep the newest valid snapshot and discard older ones. For this single-producer
   stream the Python diagnostic receiver orders by `(t_capture, seq)`, so seq can
   restart at 0 while the sender OS monotonic clock keeps increasing. Restart
   the receiver after changing producer computers or rebooting the sender.
4. Assign each hand by slot, update its position/velocity/state/confidence, and
   use these observations for your cursors. Godot decides how COASTING affects hits.
5. Record the **local receipt time** of each newer valid snapshot. After 500 ms
   without one, treat both hands as LOST. Do this even if the last packet said
   TRACKED: a stopped Python process or blocked camera cannot send its own LOST.

Do not subtract `t_capture` directly from a Godot clock or song clock: their
origins are not established as equivalent. Use local time for disconnects;
song/input latency calibration is separate. Only one producer should send to a
receiver at a time. Receipt freshness alone does not measure camera latency.

## Test without Godot

From `rhythmgame`, start the receiver in one terminal:

```powershell
.\.venv\Scripts\python.exe vision/udp_receiver.py
```

In another terminal:

```powershell
.\.venv\Scripts\python.exe vision/vertical_demo.py
```

The receiver prints newest state summaries at 5 Hz while receiving the full-rate
stream. Add `--json` to print complete snapshots at that display rate. Move and
hide each palm, then stop the demo: the receiver should report no fresh data
after 500 ms (plus up to 200 ms for the next printed status).

Stop this diagnostic receiver before Godot binds the same port. Both sender
and receiver accept `--port`; the demo also supports `--no-udp`.

For LAN testing, run the receiver on your teammate's machine with `--bind 0.0.0.0`
(Godot can bind the LAN interface instead). Send from your machine with
`--host TEAMMATE_IPV4 --port 5005`. The receiver machine must permit incoming UDP
on that port, and the network must allow communication between the computers.
127.0.0.1 only reaches the computer running the sender.

Successful send means queued locally, not confirmed delivery. The sender is
nonblocking, drops on socket errors, reports failures at most once per second,
and never retries old observations. The next frame carries another full snapshot.

Recorded clips (`--video`) currently run at processing speed and use read-completion
timestamps too; they are detector experiments, not timed session replay.
