# Charting system — design

How songs get turned into charts. Nothing here changes the game's runtime
format: the editor reads and writes the same JSON `Chart.load_from()` already
parses.

## What this game actually asks of a chart

The editor's shape falls out of four facts about the game:

1. **Notes are authored in beats**, resolved to seconds once at load. So the
   editor's horizontal axis is beats, not seconds, and BPM is a property of the
   chart rather than something to fight per note.
2. **Each hand has one vertical lane.** `x` is pinned to the lane centre and
   carries no information — so the editor never asks for it. You pick a hand
   and a **height**.
3. **Two kinds:** tap, and hold with a duration in beats.
4. **Difficulty is travel distance, not density.** Two notes 80 ms apart at the
   same height are trivial; two notes 400 ms apart at opposite heights may be
   impossible.

That last point is the whole argument for building a tool rather than editing
JSON by hand. **Density is visible in a text file. Reachability is not.**

## Shape: a piano roll, fed by a record mode

```
        beat 8       12       16       20       24
        |        |        |        |        |
 L  1.0 ─────────────────────────────────────────────
        ▁▁▁        ▔▔▔▔▔▔                 ▁▁▁
 L  0.0 ─────────────────────────────────────────────
 R  1.0 ─────────────────────────────────────────────
              ▔▔▔        ▁▁▁▁▁▁▁▁▁▁ (hold)
 R  0.0 ─────────────────────────────────────────────
        ^ playhead                    ^ lint warning
```

Two rows, one per hand. Horizontal is beats, vertical is the height being
charted. A tap is a point; a hold is a bar.

This is the same view the game renders, unrolled flat — which matters, because
what you draw is literally the path the player's hand must trace. A chart that
looks like a comfortable line to follow *is* one.

**Record mode** is an input method, not a separate tool. Play the song, hold
your hand (or the mouse) where you want the note, tap a key on the beat. It
captures beat + height, quantized to the current snap. Then you clean it up on
the timeline. That is how osu! and StepMania both work, and it is far faster
than placing several hundred notes by hand.

## Pieces

| Piece | Job |
|---|---|
| `EditorChart` | Mutable chart + undo stack. Add, move, delete, resize. |
| Timeline view | Draw the roll, hit-test clicks, drag to move or resize |
| Snap | Quantize to 1/1, 1/2, 1/4, 1/3, 1/6 of a beat, or off |
| Transport | Play, pause, scrub, loop a bar range |
| Live lint | Run `Chart.lint()` on every edit, draw flagged pairs in place |
| Writer | `Chart` → the same JSON the game loads |
| Playtest | Hand the in-memory chart straight to the play scene |

## Two things the runtime is missing

The editor needs these and neither exists yet. Both are added on this branch
as the foundation:

- **`Conductor` cannot seek.** `play()` always starts at zero. Scrubbing needs
  `play_from(seconds)`, and the free-running clock must be *reseeded* on a seek
  rather than eased toward the new position — easing across a two-second jump
  would take a visible second to settle, and the editor would feel broken.
- **`Chart` cannot save.** It parses JSON and never writes it. Round-tripping
  matters more than it sounds: load → save with no edits must produce an
  identical file, or the editor quietly rewrites every chart it opens.

## Why not generate charts from the audio

Onset detection gets you note *times* almost for free and tells you nothing
about *heights* — which in this game is the entire chart. You would still place
every note by hand, only now while arguing with a machine about where the beats
are. It is a good idea for a game with fixed lanes and a bad one here.

Worth revisiting only to **seed the timeline with beat markers**, which is a
much smaller and more reliable job.

## Order to build it

1. ✅ `Conductor.play_from()` / `seek()` and `Chart.save_to()`
2. ✅ Timeline that draws an existing chart, with a moving playhead
3. ✅ Click to place and delete taps, with snap (1/1 1/2 1/4 1/3 1/6 off)
4. ✅ Drag to move; drag a note's end to make it a hold; `H` toggles
5. ✅ Live lint overlay — flagged pairs drawn in place as red connectors
6. ⬜ Record mode
7. ✅ Playtest hand-off — `P` saves and plays the in-memory chart; results
   return you to the editor

All of it lives in `game/scenes/editor.gd`. Every edit goes through a method
that takes beats and heights rather than pixels, which is what lets
`tests/editor_test.tscn` drive the whole model headless — 29 checks, no mouse.

Open it from the menu (**Edit chart**) or run `res://scenes/editor.tscn`
directly. It edits `res://charts/test.json`; change `chart_path` for another.

**Stop after 5 if time runs out.** A timeline with lint that you click notes
onto is already far better than editing JSON; 6 and 7 are conveniences rather
than capabilities.
