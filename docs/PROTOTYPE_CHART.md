# The Entertainer prototype

A playable 52-second excerpt of Scott Joplin's **The Entertainer**, at a deliberate
80 quarter notes per minute. Choose **The Entertainer (2H)** or
**The Entertainer (1H)** on the menu.

Generate the matching audio once, from the repository root:

```bash
python3 tools/make_prototype_chart.py
```

Then open `game/project.godot` in Godot, let it import the WAV, and run the game.
No camera, model, MIDI library, or external song download is needed for the
prototype: mouse input works. Audio stays local, consistent with this repo's
policy; the checked-in generator reproduces it.

## What the chart follows

The source is the [Mutopia edition](https://www.mutopiaproject.org/cgibin/piece-info.cgi?id=263),
a reproduction of the 1902 score, typeset by Chris Sawer and overhauled by
Simon Albrecht. Mutopia marks this edition Public Domain.

- [Sheet music (PDF)](https://www.mutopiaproject.org/ftp/JoplinS/entertainer/entertainer-a4.pdf)
- [Editable notation (LilyPond)](https://www.mutopiaproject.org/ftp/JoplinS/entertainer/entertainer.ly)
- [Score MIDI](https://www.mutopiaproject.org/ftp/JoplinS/entertainer/entertainer.mid)

`tools/scores/entertainer_a.json` preserves the excerpt's 598 piano-note events
from that MIDI, in quarter-note units, with pitch, duration, velocity, and staff.
This lets the generator run offline with only Python's standard library.
The score is in **2/4**: a bar contains two chart beats, not four.

The excerpt starts with the two-note pickup at the end of measure 4, plays the
A strain twice (including its first ending), and stops on the second ending's
C-major arrival before the pickup into the next strain. Three clicks precede
the pickup. Source quarter beat 8 (measure 5) becomes chart beat 4; the pickup
lands on chart beats 3.5 and 3.75. The guide uses fixed tempo, without rubato.

## Turning piano notation into hand movement

The two-hand chart uses the **highest treble note at each onset**. Chords become
one target; ties remain one sustained event. Bass and inner voices are still
heard in the guide audio, but are not additional targets. This preserves the
melody's uneven sixteenth/eighth-note rhythm and offbeat arrivals.

Successive targets alternate hands, allowing a fast melodic figure without
asking one arm to make every move. Pitch controls height: higher pitches sit
higher on the panel, compressed into the central 40% of reach (y=0.3–0.7).
Each hand stays on its own panel. There are no gesture requirements, so this
chart can measure timing and motion before adding hand-shape difficulty.

Long melodic notes become holds, shortened slightly to leave time to move.
The solo version removes fast ornaments while prioritizing long, syncopated
arrivals. Its selected onsets are at least half a quarter note apart. Both
variants run through the game's 2.0 normalized units/second reachability limit.

The WAV is an **additive synthesized guide**, not a pianist's recording. It
plays the original piano voices, with quieter bass, exactly on the same clock
as the chart. This makes it useful for spotting timing or judgement errors.
It does not establish how a particular commercial or live recording is timed.

## Using an uploaded recording

Use the exact audio file you intend to play, ideally with matching sheet music,
MusicXML, or MIDI. A score gives beats; the recording gives where those beats
actually happen. We need to identify its opening, pickup, repeats, tempo, and
any rubato before replacing the guide.

For a constant-tempo performance, fit BPM and chart offset to several audible
landmarks, then check the end for drift. For changing tempo, establish a beat-to-
seconds map from multiple landmarks; bake those seconds into chart beat values
at one reference BPM. A single latency calibration value cannot fix musical
tempo drift. The Conductor's uniform beat indicator would also remain cosmetic
for such a recording.

## Editing and regenerating

The generated charts are `game/charts/entertainer.json` and
`game/charts/entertainer_solo.json`. The guide is
`game/audio/entertainer_guide.wav`. Regenerating overwrites those three files;
copy a chart before customizing it in the editor. Set `Settings.chart_path` to
one of these files to open it in the editor.

`--bpm 72` rebuilds chart timing and guide audio together at a slower tempo.
`--charts-only` is for chart mapping changes at the same BPM; changing BPM
requires regenerating the audio too.
