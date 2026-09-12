#!/usr/bin/env python3
"""Generate a metronome click track for Conductor testing.

At 120 BPM, beat N lands at exactly N * 0.5 seconds. That makes this file a
ground truth: if the Conductor's clock is correct, a beat indicator driven by
song_time flashes exactly when you hear the click. If it drifts, you will both
see and hear it separate over the length of the track.

Downbeats (every 4th) are pitched higher so bars are audible.
"""
import wave, struct, math, sys

SR      = 44100
BPM     = 120.0
BEATS   = 240          # 120 s at 120 BPM
CLICK_MS= 25
OUT     = sys.argv[1] if len(sys.argv) > 1 else "game/audio/click_120.wav"

total = int(SR * BEATS * 60.0 / BPM)
buf = [0.0] * total
n_click = int(SR * CLICK_MS / 1000)

for b in range(BEATS):
    start = int(round(b * 60.0 / BPM * SR))     # exact beat sample
    freq  = 1760.0 if b % 4 == 0 else 880.0     # accent the downbeat
    for i in range(n_click):
        if start + i >= total:
            break
        env = math.exp(-6.0 * i / n_click)      # fast percussive decay
        buf[start + i] += 0.6 * env * math.sin(2 * math.pi * freq * i / SR)

with wave.open(OUT, "w") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(b"".join(
        struct.pack("<h", max(-32767, min(32767, int(s * 32767)))) for s in buf))

print(f"{OUT}  {BEATS} beats @ {BPM} BPM  =  {total/SR:.1f}s")
print(f"beat N is at exactly N * {60.0/BPM:.3f}s")
