#!/usr/bin/env python3
"""Build a score-timed Entertainer prototype and its matching guide audio.

Run from any directory: python3 tools/make_prototype_chart.py
Only the Python standard library is required. The source note events are a
public-domain Mutopia MIDI transcription; see docs/PROTOTYPE_CHART.md.
"""
import argparse
from array import array
import json
import math
from pathlib import Path
import sys
import wave

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'tools/scores/entertainer_a.json'
BPM = 80.0
COUNT_IN = 4.0  # quarter notes; the two-note pickup begins half a beat earlier
LANES = (0.29, 0.71)
SAMPLE_RATE = 22050


def melody(source):
    """Top voice of each treble chord, preserving onset times and tied lengths."""
    by_beat = {}
    for beat, duration, pitch, velocity, staff in source['events']:
        if staff != 1:
            continue
        if beat not in by_beat or pitch > by_beat[beat][1]:
            by_beat[beat] = (duration, pitch)
    return [(beat, *by_beat[beat]) for beat in sorted(by_beat)]


def build_chart(source, bpm, solo=False):
    line = melody(source)
    if solo:
        # Weighted selection keeps long syncopated arrivals over short ornaments.
        # Every pair of selected onsets remains at least half a quarter apart.
        best = [(0.0, [])]
        for i, event in enumerate(line):
            previous = i - 1
            while previous >= 0 and event[0] - line[previous][0] < 0.5:
                previous -= 1
            weight = 1.0 + 2.0 * event[1]
            if i == 0:
                weight += 0.25  # keep the first pickup as the entry cue
            if event[0] % 1 in (0.25, 0.75):
                weight += 0.1
            score, chosen = best[previous + 1]
            take = (score + weight, chosen + [event])
            best.append(take if take[0] > best[-1][0] else best[-1])
        line = best[-1][1]
    low = min(pitch for _, _, pitch in line)
    high = max(pitch for _, _, pitch in line)
    notes = []
    for i, (beat, duration, pitch) in enumerate(line):
        slot = 0 if solo else i % 2
        # Pitch maps to a comfortable central reach, not maximum extension.
        y = 0.70 - 0.40 * (pitch - low) / max(high - low, 1)
        notes.append({
            'beat': beat - source['source_downbeat'] + COUNT_IN,
            'slot': slot,
            'x': 0.5 if solo else LANES[slot],
            'y': round(y, 4),
            'type': 'tap',
        })
        if duration >= 1.0:
            # Release before the next motion. Do not turn tied notes into taps.
            length = duration - 0.25
            next_index = i + (1 if solo else 2)
            if next_index < len(line):
                length = min(length, line[next_index][0] - beat - 0.5)
            if length >= 0.5:
                notes[-1].update(type='hold', length=length)
    chart = {
        'title': 'The Entertainer — ' + ('solo practice' if solo else 'melody relay'),
        'bpm': bpm,
        'audio': 'res://audio/entertainer_guide.wav',
        'offset': 0.0,
        'notes': notes,
    }
    validate_reach(chart)
    return chart


def validate_reach(chart):
    last = {}
    for note in chart['notes']:
        prev = last.get(note['slot'])
        if prev:
            gap = (note['beat'] - prev['beat'] - prev.get('length', 0)) * 60 / chart['bpm']
            travel = abs(note['y'] - prev['y'])
            if gap <= 0 or travel / gap > 2.0:
                raise ValueError(f"Unreachable slot {note['slot']} at beat {note['beat']}")
        last[note['slot']] = note


def synthesize(source, bpm, path):
    """Deterministic additive piano-like guide, using all score voices.

    This is a timing reference, not a recording of a pianist. Envelopes avoid
    clicks; the bass remains audible but quieter than the melody.
    """
    spb = 60 / bpm
    length = (source['source_end'] - source['source_downbeat'] + COUNT_IN) * spb + 1.5
    samples = array('f', [0.0]) * math.ceil(length * SAMPLE_RATE)
    for beat, duration, pitch, velocity, staff in source['events']:
        start = round((beat - source['source_downbeat'] + COUNT_IN) * spb * SAMPLE_RATE)
        held = duration * spb
        frequency = 440 * 2 ** ((pitch - 69) / 12)
        count = min(math.ceil((held + 0.12) * SAMPLE_RATE), len(samples) - start)
        gain = 0.15 * velocity / 127 * (1.0 if staff == 1 else 0.55)
        for i in range(count):
            t = i / SAMPLE_RATE
            envelope = min(1.0, t / 0.006) * math.exp(-2.5 * t)
            if t > held:
                envelope *= max(0.0, 1 - (t - held) / 0.12) ** 2
            phase = math.tau * frequency * t
            tone = math.sin(phase) + 0.28 * math.sin(2 * phase) + 0.12 * math.sin(3 * phase)
            samples[start + i] += gain * envelope * tone
    # Three count-in clicks. Beat 3 is silent so the pickup at 3.5 is clear.
    for beat in range(3):
        start = round(beat * spb * SAMPLE_RATE)
        for i in range(round(0.04 * SAMPLE_RATE)):
            t = i / SAMPLE_RATE
            samples[start + i] += 0.24 * math.exp(-100 * t) * math.sin(math.tau * 1400 * t)
    peak = max(abs(x) for x in samples) or 1.0
    pcm = array('h', (round(x / peak * 0.85 * 32767) for x in samples))
    if sys.byteorder != 'little':
        pcm.byteswap()
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(pcm.tobytes())
    return length


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bpm', type=float, default=BPM)
    parser.add_argument('--charts-only', action='store_true', help='Skip regenerating guide audio')
    args = parser.parse_args()
    if not math.isfinite(args.bpm) or args.bpm <= 0:
        parser.error('--bpm must be positive and finite')
    source = json.loads(SOURCE.read_text())
    for solo, filename in [(False, 'entertainer.json'), (True, 'entertainer_solo.json')]:
        chart = build_chart(source, args.bpm, solo)
        path = ROOT / 'game/charts' / filename
        path.write_text(json.dumps(chart, indent=1) + '\n')
        holds = sum(n['type'] == 'hold' for n in chart['notes'])
        print(f"{path.relative_to(ROOT)}: {len(chart['notes'])} notes, {holds} holds, no reach violations")
    if not args.charts_only:
        path = ROOT / 'game/audio/entertainer_guide.wav'
        length = synthesize(source, args.bpm, path)
        print(f'{path.relative_to(ROOT)}: {length:.2f}s at {args.bpm:g} BPM')


if __name__ == '__main__':
    main()
