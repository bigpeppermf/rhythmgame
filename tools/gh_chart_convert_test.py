#!/usr/bin/env python3
"""Test for gh_chart_convert.py. Run:

    python3 tools/gh_chart_convert_test.py

Drives the converter as a subprocess against a small synthetic .chart file
covering the cases that are easy to get subtly wrong: a tempo change partway
through, chords that map cleanly to one hand each, a yellow note that has to
pick a hand, a chord that has no hand left to give a third note, a real hold,
a sustain too short to count as one, and an open note.
"""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CONVERTER = REPO_ROOT / "tools" / "gh_chart_convert.py"

# Resolution 192: one beat = 192 ticks. Tempo changes from 120 to 150 BPM at
# tick 3840 (= beat 20), so every note past that exercises the tempo map
# rather than a single fixed BPM.
SAMPLE_CHART = """\
[Song]
{
  Resolution = 192
  Offset = 0
  Name = "Test Song"
}
[SyncTrack]
{
  0 = TS 4
  0 = B 120000
  3840 = B 150000
}
[ExpertSingle]
{
  0 = N 0 0
  192 = N 4 0
  384 = N 2 0
  576 = N 2 0
  768 = N 0 0
  768 = N 4 0
  960 = N 0 0
  960 = N 2 0
  1152 = N 0 0
  1152 = N 4 0
  1152 = N 2 0
  1344 = N 1 0
  1536 = N 3 384
  1728 = N 3 20
  3840 = N 7 0
  4032 = N 0 0
}
"""

failures = 0


def check(ok: bool, label: str) -> None:
    global failures
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")
    if not ok:
        failures += 1


def approx(a: float, b: float, eps: float = 1e-6) -> bool:
    return abs(a - b) < eps


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        chart_path = Path(tmp) / "sample.chart"
        out_path = Path(tmp) / "out.json"
        chart_path.write_text(SAMPLE_CHART)

        result = subprocess.run(
            [sys.executable, str(CONVERTER), str(chart_path),
             "--out", str(out_path), "--audio", "res://audio/song.ogg"],
            capture_output=True, text=True)
        check(result.returncode == 0, f"converter exits 0, stderr: {result.stderr.strip()}")
        check("dropped 1 note" in result.stderr,
              "warns about the one note that had no hand left")

        chart = json.loads(out_path.read_text())

    check(chart["title"] == "Test Song", "title read from the Name field")
    check(chart["bpm"] == 120.0, "output bpm is the *first* tempo, not a later one")
    check(chart["audio"] == "res://audio/song.ogg", "audio path passed through")

    notes = chart["notes"]
    # 16 real notes in the source; one yellow is dropped (chord already using
    # both hands), and the open note becomes two.
    check(len(notes) == 16, f"expected 16 output notes, got {len(notes)}")

    by_beat_slot = {(n["beat"], n["slot"]): n for n in notes}

    check((0.0, 0) in by_beat_slot, "green at beat 0 -> slot 0 (left)")
    check(approx(by_beat_slot[(0.0, 0)]["y"], 0.15), "green -> near the top of its lane")

    check((1.0, 1) in by_beat_slot, "orange at beat 1 -> slot 1 (right)")
    check(approx(by_beat_slot[(1.0, 1)]["y"], 0.85), "orange -> near the bottom of its lane")

    check((2.0, 1) in by_beat_slot, "lone yellow #1 -> right (toggle starts right)")
    check((3.0, 0) in by_beat_slot, "lone yellow #2 -> left (toggle alternates)")

    check((5.0, 0) in by_beat_slot and (5.0, 1) in by_beat_slot,
          "yellow+green chord -> yellow takes the hand green didn't")

    check((6.0, 0) in by_beat_slot and (6.0, 1) in by_beat_slot and
          len([n for n in notes if n["beat"] == 6.0]) == 2,
          "green+orange+yellow chord -> yellow dropped, only 2 notes survive")

    hold = by_beat_slot[(8.0, 1)]
    check(hold["type"] == "hold", "384-tick sustain becomes a hold")
    check(approx(hold["length"], 2.0), f"hold length is 2 beats, got {hold.get('length')}")

    tap = by_beat_slot[(9.0, 1)]
    check(tap["type"] == "tap", "a 20-tick sustain is charting noise, not a real hold")
    check("length" not in tap, "a tap note carries no length field")

    check((20.0, 0) in by_beat_slot and (20.0, 1) in by_beat_slot,
          "open note at beat 20 hits both hands")

    # This is the one that actually proves the tempo map: tick 4032 is 192
    # ticks (1 beat) past the 150 BPM change at tick 3840. At the *first*
    # tempo (120 BPM, what "beat" is expressed in) that's 0.4s = 0.8 beats
    # later, landing at beat 20.8 - not 21, which is what a single-tempo
    # converter would have produced.
    check((20.8, 0) in by_beat_slot,
          "note after the tempo change lands at 20.8 beats, proving the tempo "
          "map was used across the change rather than a single fixed BPM")

    print(f"\n{'ALL PASS' if failures == 0 else 'FAILURES'} "
          f"({failures} failure{'' if failures == 1 else 's'})")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
