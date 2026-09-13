#!/usr/bin/env python3
"""Convert a Clone Hero / Moonscraper .chart file into our chart JSON.

Stopgap until the real charting tool exists (see PROJECT_BRIEF.md): this lets
you point at any of the thousands of community-made 5-fret .chart files and
get something playable today, without hand-authoring beats.

    python3 tools/gh_chart_convert.py song.chart --audio res://audio/song.ogg
    python3 tools/gh_chart_convert.py song.chart --difficulty Hard --out game/charts/song.json

Prototyping one-handed against the "Play (1H)" menu option, straight from a
Clone Hero song folder, audio included:

    python3 tools/gh_chart_convert.py SongFolder/notes.chart --hands 1 \\
        --out game/charts/solo.json --audio res://audio/solo.ogg --copy-audio

## The lossy part: 5 frets, fewer hands

This game has one hand per lane; Guitar Hero has five frets on one guitar.
There's no faithful mapping, only a reasonable one.

With --hands 2 (the default, for the real two-hand game):

    green, red      (frets 0, 1)  -> left hand  (slot 0)
    blue, orange    (frets 3, 4)  -> right hand (slot 1)
    yellow          (fret 2)      -> alternates hands, one not already used
                                     by the rest of the chord this tick
    open note       (fret 7)      -> both hands at once
    forced/tap flags (frets 5, 6) -> not real notes, ignored

A chord that already uses both hands can't take a third note - that
information is simply lost, same as it would be for any 5-to-2 mapping.

With --hands 1 (for the "Play (1H)" solo prototyping mode), every note goes
to the single centred lane. A chord collapses to its highest fret - treated
as the lead line - since one hand can only be in one place.

Fret height (0=green .. 4=orange) becomes vertical position either way: green
is near the top of its lane, orange near the bottom, red/yellow/blue between.
That preserves the shape of the original chart even though the hand mapping
is approximate.

## The exact part: timing

Every note's time is resolved through the .chart file's *entire* tempo map
(every [SyncTrack] "B" event), not just its first BPM, so a mid-song tempo
change never desyncs a note from the audio. The output chart's "bpm" field is
only the *first* tempo, used as the beat unit "beat" values are expressed in
(this format has no other way to record a note's time) and to drive
Conductor's beat-flash - which is cosmetic and WILL drift from the music
after a tempo change. Note placement itself does not drift; it's computed in
seconds first and converted to "beat" only as a units question.
"""
import argparse
import json
import re
import shutil
import sys
from pathlib import Path

# Guitar Hero fret numbers, as they appear in "tick = N fret sustain" lines.
FRET_GREEN, FRET_RED, FRET_YELLOW, FRET_BLUE, FRET_ORANGE = 0, 1, 2, 3, 4
FRET_OPEN = 7
REAL_FRETS = {FRET_GREEN, FRET_RED, FRET_YELLOW, FRET_BLUE, FRET_ORANGE, FRET_OPEN}

LEFT, RIGHT = 0, 1
LANE_X = [0.29, 0.71]  # must match game/gameplay/field_3d.gd Field3D.TRACK_X
SOLO_X = 0.5           # must match Field3D.SOLO_TRACK_X

# Common filenames in a Clone Hero song folder, most specific first.
AUDIO_CANDIDATES = ["song.ogg", "song.opus", "song.mp3", "song.wav", "guitar.ogg"]

# A sustain shorter than this many beats is charting noise (or a strum artifact),
# not a real hold - treat it as a tap. A sixteenth note is a generous cutoff.
MIN_HOLD_BEATS = 0.2


def fret_y(fret: int) -> float:
    f = fret if fret != FRET_OPEN else 2  # open note: middle height
    return 0.15 + (f / 4.0) * 0.70


class TempoMap:
    """Converts .chart ticks to seconds via every recorded BPM change."""

    def __init__(self, resolution: int, offset_seconds: float):
        self.resolution = resolution
        self.offset = offset_seconds
        self._changes: list[tuple[int, float]] = []  # (tick, bpm), sorted

    def add(self, tick: int, bpm: float) -> None:
        self._changes.append((tick, bpm))

    def finalize(self) -> None:
        self._changes.sort(key=lambda c: c[0])
        if not self._changes or self._changes[0][0] != 0:
            self._changes.insert(0, (0, 120.0))

    def first_bpm(self) -> float:
        return self._changes[0][1]

    def seconds(self, tick: int) -> float:
        """Integrate seconds-per-tick across every tempo segment up to `tick`."""
        t = self.offset
        for i, (start_tick, bpm) in enumerate(self._changes):
            if start_tick > tick:
                break
            end_tick = self._changes[i + 1][0] if i + 1 < len(self._changes) else tick
            end_tick = min(end_tick, tick)
            spt = 60.0 / (bpm * self.resolution)
            t += (end_tick - start_tick) * spt
        return t


def parse_sections(text: str) -> dict[str, list[str]]:
    """Split a .chart file into {SectionName: [raw lines inside braces]}."""
    sections: dict[str, list[str]] = {}
    name = None
    lines: list[str] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line in ("{", "}"):
            continue
        m = re.match(r"^\[(\w+)\]$", line)
        if m:
            if name is not None:
                sections[name] = lines
            name, lines = m.group(1), []
            continue
        lines.append(line)
    if name is not None:
        sections[name] = lines
    return sections


def parse_tempo_map(sync_lines: list[str], resolution: int, offset: float) -> TempoMap:
    tempo = TempoMap(resolution, offset)
    for line in sync_lines:
        m = re.match(r"^(\d+)\s*=\s*B\s+(\d+)", line)
        if m:
            tick, raw_bpm = int(m.group(1)), int(m.group(2))
            tempo.add(tick, raw_bpm / 1000.0)
    tempo.finalize()
    return tempo


def parse_song_header(song_lines: list[str]) -> tuple[int, float]:
    resolution, offset = 192, 0.0
    for line in song_lines:
        m = re.match(r"^Resolution\s*=\s*(\d+)", line)
        if m:
            resolution = int(m.group(1))
        m = re.match(r"^Offset\s*=\s*(-?[\d.]+)", line)
        if m:
            offset = float(m.group(1))
    return resolution, offset


def parse_notes(track_lines: list[str]) -> list[tuple[int, int, int]]:
    """Return [(tick, fret, sustain_ticks), ...] for real frets only."""
    notes = []
    for line in track_lines:
        m = re.match(r"^(\d+)\s*=\s*N\s+(\d+)\s+(\d+)", line)
        if not m:
            continue
        tick, fret, sustain = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if fret in REAL_FRETS:
            notes.append((tick, fret, sustain))
    notes.sort(key=lambda n: n[0])
    return notes


def assign_hand(frets_this_tick: set[int], fret: int, toggle: list[int]) -> int | None:
    """Which hand plays `fret`, given the other frets struck on the same tick.

    `toggle` is a 1-element list used as a mutable int, so consecutive lone
    yellow notes alternate hands instead of piling onto one.
    """
    if fret in (FRET_GREEN, FRET_RED):
        return LEFT
    if fret in (FRET_BLUE, FRET_ORANGE):
        return RIGHT
    if fret == FRET_OPEN:
        return None  # handled specially: emits both hands
    # FRET_YELLOW: take whichever hand this chord doesn't already use.
    uses_left = bool(frets_this_tick & {FRET_GREEN, FRET_RED})
    uses_right = bool(frets_this_tick & {FRET_BLUE, FRET_ORANGE})
    if uses_left and not uses_right:
        return RIGHT
    if uses_right and not uses_left:
        return LEFT
    if uses_left and uses_right:
        return None  # both hands already spoken for this tick - dropped
    toggle[0] ^= 1
    return toggle[0]


def _make_note(tick: int, fret: int, sustain_ticks: int, slot: int, x: float,
               tempo: TempoMap, spb: float) -> dict:
    t0 = tempo.seconds(tick)
    t1 = tempo.seconds(tick + sustain_ticks) if sustain_ticks > 0 else t0
    length_beats = (t1 - t0) / spb
    note = {
        "beat": round(t0 / spb, 4),
        "slot": slot,
        "x": x,
        "y": round(fret_y(fret), 3),
        "type": "hold" if length_beats >= MIN_HOLD_BEATS else "tap",
    }
    if length_beats >= MIN_HOLD_BEATS:
        note["length"] = round(length_beats, 4)
    return note


def convert(notes: list[tuple[int, int, int]], tempo: TempoMap,
            output_bpm: float, hands: int) -> list[dict]:
    spb = 60.0 / output_bpm
    by_tick: dict[int, list[tuple[int, int]]] = {}
    for tick, fret, sustain in notes:
        by_tick.setdefault(tick, []).append((fret, sustain))

    if hands == 1:
        return _convert_solo(by_tick, tempo, spb)

    out = []
    toggle = [0]
    dropped = 0
    for tick in sorted(by_tick):
        frets_here = {f for f, _ in by_tick[tick]}
        for fret, sustain_ticks in by_tick[tick]:
            hand_slots = (LEFT, RIGHT) if fret == FRET_OPEN \
                else [assign_hand(frets_here, fret, toggle)]
            for slot in hand_slots:
                if slot is None:
                    dropped += 1
                    continue
                out.append(_make_note(tick, fret, sustain_ticks, slot, LANE_X[slot],
                                       tempo, spb))
    if dropped:
        print(f"warning: dropped {dropped} note(s) that needed a third hand "
              f"(a chord already using both slots)", file=sys.stderr)
    out.sort(key=lambda n: (n["beat"], n["slot"]))
    return out


def _convert_solo(by_tick: dict[int, list[tuple[int, int]]], tempo: TempoMap,
                   spb: float) -> list[dict]:
    """One hand, one lane: a chord collapses to its highest fret (the lead
    line), since a single cursor can only be in one place at a time."""
    out = []
    collapsed = 0
    for tick in sorted(by_tick):
        entries = by_tick[tick]
        if len(entries) > 1:
            collapsed += 1
        fret, sustain_ticks = max(entries, key=lambda e: e[0])
        out.append(_make_note(tick, fret, sustain_ticks, LEFT, SOLO_X, tempo, spb))
    if collapsed:
        print(f"note: collapsed {collapsed} chord(s) to a single note (one-hand mode)",
              file=sys.stderr)
    out.sort(key=lambda n: n["beat"])
    return out


def find_audio(chart_file: str) -> str | None:
    folder = Path(chart_file).resolve().parent
    for name in AUDIO_CANDIDATES:
        candidate = folder / name
        if candidate.is_file():
            return str(candidate)
    return None


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("chart_file", help="path to the .chart file")
    ap.add_argument("--out", default="game/charts/song.json")
    ap.add_argument("--audio", default="res://audio/song.ogg",
                    help="value for the output chart's \"audio\" field")
    ap.add_argument("--difficulty", default="Expert",
                    choices=["Easy", "Medium", "Hard", "Expert"])
    ap.add_argument("--track", default=None,
                    help="exact .chart section name to read, overriding "
                         "--difficulty (e.g. ExpertDoubleBass)")
    ap.add_argument("--title", default=None)
    ap.add_argument("--hands", type=int, default=2, choices=[1, 2],
                    help="2 (default) for the real two-hand game, "
                         "1 for the Play (1H) solo prototyping mode")
    ap.add_argument("--copy-audio", action="store_true",
                    help="look for a song audio file next to the .chart "
                         "(song.ogg, song.mp3, ...) and copy it to where "
                         "--audio says, so the chart is playable immediately")
    args = ap.parse_args()

    with open(args.chart_file, encoding="utf-8-sig") as f:
        sections = parse_sections(f.read())

    if "Song" not in sections:
        sys.exit("error: no [Song] section - is this a .chart file?")
    if "SyncTrack" not in sections:
        sys.exit("error: no [SyncTrack] section - can't resolve any timing")

    track_name = args.track or f"{args.difficulty}Single"
    if track_name not in sections:
        available = [s for s in sections if s.endswith("Single")]
        sys.exit(f"error: no [{track_name}] section. Found: {', '.join(available) or '(none)'}")

    resolution, offset = parse_song_header(sections["Song"])
    tempo = parse_tempo_map(sections["SyncTrack"], resolution, offset)
    notes = parse_notes(sections[track_name])
    if not notes:
        sys.exit(f"error: [{track_name}] has no notes")

    output_bpm = round(tempo.first_bpm(), 3)
    chart_notes = convert(notes, tempo, output_bpm, args.hands)

    title = args.title
    if title is None:
        for line in sections["Song"]:
            m = re.match(r'^Name\s*=\s*"(.*)"', line)
            if m:
                title = m.group(1)
                break
    title = title or args.chart_file

    chart = {
        "title": title,
        "bpm": output_bpm,
        "audio": args.audio,
        "offset": 0.0,  # baked into each note's "beat" already, via TempoMap.offset
        "notes": chart_notes,
    }
    with open(args.out, "w") as f:
        json.dump(chart, f, indent=1)

    if args.copy_audio:
        src = find_audio(args.chart_file)
        if src is None:
            print(f"warning: --copy-audio found no audio file next to "
                  f"{args.chart_file} (looked for {', '.join(AUDIO_CANDIDATES)})",
                  file=sys.stderr)
        else:
            # "game/charts/x.json" and "res://audio/name" both assume the same
            # game/ layout, so the copy destination falls out of --out's own
            # parent directory rather than needing a third path to keep in sync.
            game_dir = Path(args.out).resolve().parent.parent
            dest = game_dir / "audio" / args.audio.rsplit("/", 1)[-1]
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy(src, dest)
            print(f"copied {src} -> {dest}")

    tempo_changes = len(tempo._changes)
    holds = sum(1 for n in chart_notes if n["type"] == "hold")
    print(f"{args.out}: {len(chart_notes)} notes ({holds} holds) from [{track_name}], "
          f"{chart_notes[-1]['beat']:.1f} beats")
    if tempo_changes > 1:
        print(f"note: {tempo_changes} tempo changes in the source - note timing is exact, "
              f"but Conductor's beat-flash (fixed at {output_bpm} BPM) will drift after "
              f"the first change")


if __name__ == "__main__":
    main()
