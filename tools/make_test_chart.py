#!/usr/bin/env python3
"""Generate a test chart aligned to the 120 BPM click track.

Escalates through the cases the Judge has to get right, and deliberately ends
with one unreachable pair so the reachability linter has something to catch.
"""
import json

BPM = 120
OUT = "game/charts/test.json"
notes = []


def n(beat, slot, x, y, kind="tap", length=0):
    e = {"beat": beat, "slot": slot, "x": round(x, 3), "y": round(y, 3), "type": kind}
    if length:
        e["length"] = length
    notes.append(e)


# Bars 1-2: lead in, nothing to hit.

# Bars 3-4 - alternating taps, small travel. Should feel trivial.
for i in range(8):
    beat = 8 + i
    slot = i % 2
    x = 0.30 if slot == 0 else 0.70
    n(beat, slot, x, 0.45 + 0.1 * (i % 2))

# Bars 5-6 - wide vertical travel, one hand at a time.
for i in range(8):
    beat = 16 + i
    slot = i % 2
    x = 0.25 if slot == 0 else 0.75
    n(beat, slot, x, 0.20 if i % 4 < 2 else 0.80)

# Bars 7-8 - holds. Two beats each, both hands.
for i in range(2):
    base = 24 + i * 4
    n(base, 0, 0.28, 0.35, "hold", 2)
    n(base + 2, 1, 0.72, 0.65, "hold", 2)

# Bars 9-10 - simultaneous, both hands on the same beat.
# Starts at 34, not 32: slot 1's last hold runs until beat 32, and a tap on
# the same beat somewhere else would require that hand to be in two places at
# once. The linter catches it, but charts should not need catching.
for i in range(8):
    beat = 34 + i
    y = 0.30 + 0.4 * (i % 2)
    n(beat, 0, 0.22 + 0.12 * (i % 3), y)
    n(beat, 1, 0.78 - 0.12 * (i % 3), y)

# Bar 11 - DELIBERATELY UNREACHABLE. Quarter of a beat (0.125s) apart at
# opposite corners: needs ~5 u/s against a 2 u/s budget. The linter should
# flag exactly this and nothing before it.
n(43, 0, 0.10, 0.10)
n(43.25, 0, 0.48, 0.90)

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
print(f"{OUT}: {len(notes)} notes, {max(e['beat'] for e in notes)} beats "
      f"({max(e['beat'] for e in notes) * 60 / BPM:.1f}s)")
