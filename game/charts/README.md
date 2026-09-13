# Writing a chart

A chart is a JSON file: song metadata plus a list of notes. `Chart.load_from()`
(`../chart/chart.gd`) reads it; `Note` (`../chart/note.gd`) is what each note
becomes at runtime.

```json
{
 "title": "My Song",
 "bpm": 128,
 "audio": "res://audio/solo.ogg",
 "offset": 0.0,
 "notes": [
  { "beat": 4,   "slot": 0, "x": 0.5, "y": 0.3, "type": "tap" },
  { "beat": 4.5, "slot": 0, "x": 0.5, "y": 0.7, "type": "tap" },
  { "beat": 5,   "slot": 0, "x": 0.5, "y": 0.5, "type": "hold", "length": 2 }
 ]
}
```

## Top-level fields

| Field | Meaning |
|---|---|
| `title` | Shown on the HUD before you press SPACE. |
| `bpm` | One constant tempo for the whole song - see "No tempo changes" below. |
| `audio` | `res://audio/...` - see `../audio/README.md` for dropping the file in. |
| `offset` | Seconds added to every note's time. Use it if the song's first beat isn't at t=0 (a lead-in count, a fade-in intro, etc). |
| `notes` | The list below. Order doesn't matter - `Chart.load_from` sorts by time. |

## Per-note fields

| Field | Meaning |
|---|---|
| `beat` | When it's hit, in **beats** from the start of the song (not seconds - see below). Can be fractional: `4.5` is the off-beat between beats 4 and 5. |
| `slot` | Which hand: `0` = left, always `0` in solo mode (Play (1H) - only one hand exists). `1` = right, two-hand mode only. |
| `x` | Normalized horizontal position. **Leave this at the lane's centre** - see "x doesn't vary" below. |
| `y` | Normalized vertical position, `0` = top of the lane, `1` = bottom. **This is the axis you actually chart on** - see below. |
| `type` | `"tap"` or `"hold"`. |
| `length` | HOLD only, in beats. How long the hand must stay in place. Omit for taps. |

### beats, not seconds

`beat * (60 / bpm) + offset` is the note's real time in seconds
(`Chart.load_from` does this once at load, so nothing does BPM math at
runtime). Authoring in beats means you write down "this note lands on beat
16" while listening and counting bars, instead of computing seconds by hand.

**Find your song's BPM first** - most audio editors show it, or use any
online BPM tap-tempo tool while listening. Get it as exact as you can: a BPM
that's off by even 0.5 will drift out of sync with the audio over a few
minutes, because there's no way to correct it mid-song (see below).

### No tempo changes

There's one `bpm` for the entire chart - no way to speed up or slow down
partway through. If your song does that, you have two options: pick the
song's dominant tempo and accept some drift during the different section, or
convert that section's beats to the chart's tempo by hand (figure out the
section's real start time in seconds, then `beat = seconds / (60 / bpm)`).
Most songs don't change tempo; this only matters if yours does.

### x doesn't vary

Despite being a 2D `pos`, x is **not** a second charted axis - it's fixed per
hand, and only `y` (height) is what the player actually reacts to. Set `x` to
whichever of these applies and leave it there for every note:

- **Solo mode** (`slot: 0` only): `x: 0.5` - the lane is dead centre.
- **Two-hand mode**: `x: 0.29` for `slot: 0` (left), `x: 0.71` for `slot: 1`
  (right) - these must match `Field3D.TRACK_X` (`../gameplay/field_3d.gd`).

`Chart.lint()` (see below) flags a note whose `x` doesn't match its slot's
lane, so getting this wrong is caught immediately rather than silently
missing.

### Reachability

There's no discrete "press" trigger in this game (see `PROJECT_BRIEF.md`) -
a note is a circle the hand has to be inside of, on time. That makes
difficulty entirely about how far the hand has to travel between notes, not
density: two notes 400ms apart on top of each other are trivial, two notes
400ms apart at opposite corners of the lane may be physically impossible.

`Chart.lint(max_speed, Field3D.track)` checks every consecutive pair on the
same hand and flags any jump that would need more than `max_speed` (normalized
units/second, default 2.0 in `play_3d.gd`) to make. `play_3d.gd` runs this
automatically and prints `lint: ...` lines to the HUD before you press SPACE -
watch for those while iterating on a chart. A HOLD occupies the hand until it
ends, so travel time to the next note is measured from the hold's release,
not its start.

## Workflow

1. Get the song's BPM (see above) and, if needed, its lead-in offset.
2. Write a `{title, bpm, audio, offset, "notes": []}` skeleton (`solo.json`
   and `test.json` in this folder are examples - `test.json` is denser and
   uses both hands, for a sense of the format at scale).
3. Add notes a section at a time. Play the song, count beats, jot down which
   beat number lines up with each hit you want.
4. Point `"audio"` at your track (`../audio/README.md`) and run the game -
   `play_3d.gd`'s HUD shows `lint:` warnings and lets you SPACE-restart
   instantly, so this is meant to be an iterate-and-replay loop, not a
   write-then-check-once pass.
5. For solo mode, pick which menu option loads your chart in
   `game/scenes/main.gd`'s `SOLO_CHART` (or `PLAY`'s default `chart_path` for
   two-hand mode) if you're not just editing `solo.json`/`test.json` in place.

## Generating a chart instead of hand-writing JSON

For a click-track-style chart (evenly spaced, programmatic), see
`../../tools/make_test_chart.py` for a working example script you can copy
and adapt - it builds `test.json` from a handful of Python loops rather than
typing out every note by hand. Useful if your chart has a lot of regular,
repeating structure.
