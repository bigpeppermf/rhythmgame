# Wire Protocol v1

The contract between the vision module (Python) and the game (Godot).

**This file is the boundary.** Both sides code against it. Neither side needs
the other to exist in order to make progress — the game runs against
`MockHandSource` or `tools/mock_sender.py`, the vision module runs against a
recorded video and a terminal readout.

Change this file only by agreement, and bump `v` when you do.

---

## Transport

- **UDP**, `127.0.0.1:9000`, vision → game, one datagram per camera frame
- **Fire and forget.** No handshake, no acknowledgement, no retries
- The game **drains its socket every frame and keeps only the newest packet**

A dropped packet is a stale frame. A *resent* packet is a late frame. Stale is
always better than late, so we never resend anything.

## Packet

UTF-8 JSON, one object per datagram. Target < 512 bytes.

```jsonc
{
  "v": 1,
  "seq": 4821,
  "t_capture": 18461.2044,
  "fps": 58.7,
  "hands": [
    {
      "slot": 0,
      "x": 0.34, "y": 0.71,
      "vx": -1.2, "vy": 0.30,
      "conf": 0.93,
      "state": "TRACKED"
    },
    {
      "slot": 1,
      "x": 0.68, "y": 0.55,
      "vx": 0.0, "vy": 0.10,
      "conf": 0.41,
      "state": "COASTING"
    }
  ]
}
```

### Fields

| Field | Type | Meaning |
|---|---|---|
| `v` | int | Protocol version. Game ignores packets whose `v` it does not know. |
| `seq` | int | Monotonic frame counter. Lets the game detect drops and reordering. |
| `t_capture` | float | `time.perf_counter()` sampled **immediately after `cap.read()` returns**, never at send time. |
| `fps` | float | Observed capture rate, for the debug overlay. |
| `hands` | array | Always exactly 2 entries, always slot 0 then slot 1. |

### Per hand

| Field | Type | Meaning |
|---|---|---|
| `slot` | int | `0` = left, `1` = right, **as they appear on the game screen**. Stable across frames — see Slot Identity. |
| `x`, `y` | float | Normalized position after calibration. `[0,1]` is the play area; up to `[-0.1, 1.1]` is allowed overshoot. `x=0` is screen-left, `y=0` is screen-**top**. |
| `vx`, `vy` | float | Velocity in normalized units per second. Used for extrapolation between packets. |
| `conf` | float | `[0,1]`. The game fades the cursor below ~0.4 and stops judging at 0. |
| `state` | string | `TRACKED` \| `COASTING` \| `LOST` |

### Rules both sides rely on

**Always send both slots.** A hand that isn't visible is sent as `LOST` with
`conf: 0`, not omitted. A missing entry is a protocol error, not "no hand."

**`y=0` is the top of the screen.** Camera coordinates also put row 0 at the
top, so there is no flip — but the camera **mirrors x**. The vision side owns
un-mirroring; the game never thinks about it.

**Never emit a stale position as if it were fresh.** A coasting hand keeps
reporting a position, but its `conf` decays and its `state` says `COASTING`.
The confidence field is what makes that honest.

### State machine

```
TRACKED  ──no detection──→  COASTING  ──after ~200ms──→  LOST
   ↑                            │                          │
   └──────── detection ─────────┴──────────────────────────┘
```

| State | `conf` | Game behaviour |
|---|---|---|
| `TRACKED` | high | Normal play |
| `COASTING` | decaying | Cursor fades; still judged |
| `LOST` | `0.0` | Cursor hidden, judging suspended, "hand not found" shown |

### Slot identity

Slots are assigned by **positional continuity**, not by any classifier's
left/right label. Whichever detection is nearest a slot's last known position
keeps that slot. Two slots never bind to the same detection.

MediaPipe's handedness label flips when hands cross or occlude. Continuity
doesn't: the model reasons about one isolated frame, we know the hand did not
teleport since 16ms ago. Use the label only to break ties when re-acquiring
both hands from nothing.

## Timebase

The two processes do **not** share a clock, and they don't need to.

`t_capture` is only ever compared to *other* `t_capture` values, to measure
jitter and to extrapolate forward. The game never tries to convert it into
song time. All fixed pipeline delay is absorbed by a single calibrated
`Conductor.input_offset`, tuned once per machine.

## Testing without the other half

```bash
# Game side: fake vision, no camera needed
python3 tools/mock_sender.py --pattern circle

# Vision side: no game needed
python3 -m vision.main --debug --no-emit
```
