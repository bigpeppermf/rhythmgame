#!/usr/bin/env python3
"""Generate a test chart aligned to the 120 BPM click track.

Each hand has one vertical lane, so x is fixed at the lane centre and every
note is placed by HEIGHT. Escalates through the cases the Judge has to get
right, and ends with one unreachable pair so the reachability linter has
something to catch.

Lane centres must match Field3D.TRACK_X.
"""
import json

BPM = 120
OUT = "game/charts/test.json"
LANE = [0.29, 0.71]

# A hand can cross about 2.0 normalized units per second. At 120 BPM one beat
# is 0.5s, so a same-hand jump one beat apart must stay under ~1.0 of height.
notes = []


def n(beat, slot, y, kind="tap", length=0):
    e = {"beat": beat, "slot": slot, "x": LANE[slot], "y": round(y, 3), "type": kind}
    if length:
        e["length"] = length
    notes.append(e)


# Bars 1-2: lead in, nothing to hit.

# Bars 3-4 - alternating hands, small height changes. Should feel trivial.
for i in range(8):
    n(8 + i, i % 2, 0.40 + 0.20 * (i % 2))

# Bars 5-6 - full-height swings, one hand at a time.
for i in range(8):
    n(16 + i, i % 2, 0.18 if i % 4 < 2 else 0.82)

# Bars 7-8 - holds, two beats each, both hands.
for i in range(2):
    base = 24 + i * 4
    n(base, 0, 0.30, "hold", 2)
    n(base + 2, 1, 0.70, "hold", 2)

# Bars 9-10 - simultaneous, both hands on the same beat, moving in contrary
# motion so the two lanes cannot be read as one pattern.
for i in range(8):
    n(34 + i, 0, 0.25 + 0.12 * (i % 4))
    n(34 + i, 1, 0.75 - 0.12 * (i % 4))

# Bar 12 - DELIBERATELY UNREACHABLE. A quarter beat (0.125s) apart across
# nearly the full height: needs ~6 u/s against a 2 u/s budget. The linter
# should flag exactly this and nothing before it.
n(43, 0, 0.10)
n(43.25, 0, 0.90)

notes.sort(key=lambda e: (e["beat"], e["slot"]))
chart = {
    "title": "Judge Test",
    "bpm": BPM,
    "audio": "res://audio/click_120.wav",
    "offset": 0.0,
    "notes": notes,
}
with open(OUT, "w") as f:
    json.dump(chart, f, indent=1)
last = max(e["beat"] for e in notes)
print(f"{OUT}: {len(notes)} notes, {last} beats ({last * 60 / BPM:.1f}s)")
