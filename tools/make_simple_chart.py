#!/usr/bin/env python3
"""A simple chart for actually playing: something arrives every beat from the
start, hands alternate, heights drift gently. No tricks, no holds until the
end, nothing near the reachability limit.

Same 120 BPM click track. Lane centres must match Field3D.TRACK_X.
"""
import json, math

BPM = 120
OUT = "game/charts/simple.json"
LANE = [0.29, 0.71]
notes = []


def n(beat, slot, y, kind="tap", length=0, gesture=None):
    e = {"beat": beat, "slot": slot, "x": LANE[slot], "y": round(y, 3), "type": kind}
    if length:
        e["length"] = length
    if gesture:
        e["gesture"] = gesture   # required hand shape; absent means any
    notes.append(e)


# The first note is charted at beat 4 (2.0 s) - exactly the lookahead - so it
# is already visible at the far end of the panel the instant the song starts.
beat = 4

# Section A - alternate hands every beat, heights on a slow sine. Same-hand
# notes are two beats apart and never move more than ~0.15 of height.
for i in range(48):
    slot = i % 2
    y = 0.5 + 0.22 * math.sin(i / 48 * math.tau * 1.5)
    n(beat + i, slot, y)
beat += 48

# Section B - both hands on every beat, mirrored heights. Every fourth beat
# asks for a fist, so the shape changes on the bar and nowhere else.
for i in range(16):
    y = 0.5 + 0.25 * math.sin(i / 16 * math.tau)
    g = "FIST" if i % 4 == 0 else None
    n(beat + i, 0, y, gesture=g)
    n(beat + i, 1, 1.0 - y, gesture=g)
beat += 16

# Section C - easy 2-beat holds with a thumbs-up, alternating hands.
for i in range(4):
    n(beat + i * 4, i % 2, 0.5, "hold", 2, gesture="THUMBS_UP")
beat += 16

# Section D - pinches, one per bar, alternating, at mid height.
for i in range(4):
    n(beat + i * 4, i % 2, 0.5, gesture="PINCH")
beat += 16

notes.sort(key=lambda e: (e["beat"], e["slot"]))
with open(OUT, "w") as f:
    json.dump({"title": "Simple", "bpm": BPM, "audio": "res://audio/click_120.wav",
               "offset": 0.0, "default_gesture": "OPEN_PALM", "notes": notes}, f, indent=1)
last = max(e["beat"] + e.get("length", 0) for e in notes)
print(f"{OUT}: {len(notes)} notes, ends at beat {last} ({last * 60 / BPM:.0f}s)")
