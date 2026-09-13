# Audio

Nothing here is committed. Drop your own audio files in locally.

## Solo mode (Play (1H) on the menu)

One hand, one centred lane - see `../charts/README.md` for how to author
`charts/solo.json`.

1. Drop the track here, e.g. `solo.ogg` (`.wav`/`.mp3` also load).
2. Make sure `charts/solo.json`'s `"audio"` field points at it.

Until it's there, `charts/solo.json` ships with an empty `notes` array and
an `audio` path that doesn't exist yet. Play still runs - the HUD just
reports there's no audio until the file shows up, instead of erroring.

## Two-hand mode (Play on the menu)

Currently points at `charts/test.json`, the engine's own Judge/Conductor
test fixture - see `tools/make_click_track.py`. A hand-authored song and
chart for the real two-hand game will replace this later.

`click_120.wav` is that fixture's audio, regenerated with
`../../tools/make_click_track.py game/audio/click_120.wav`. It has nothing
to do with either chart above - don't point either "audio" field at it.
