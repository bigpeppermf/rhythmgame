# Audio

Audio files stay local and are ignored by Git. Drop an Ogg Vorbis, WAV, or MP3
file here and set the chart's `audio` field to `res://audio/<filename>`.

The normal Play option uses `Settings.chart_path`; Play (1H) uses
`charts/solo.json`. The editor can open and playtest other charts. See
[chart authoring](../charts/README.md) and [the editor guide](../../docs/CHARTING.md).

`charts/song.json` is an empty template for a new song. Set its BPM, offset,
and notes before selecting it. A missing audio file displays a message in
the game instead of starting a broken playback session.

Generate the 120 BPM click track used by calibration and test charts from
the repository root:

```bash
python3 tools/make_click_track.py
```

During gameplay, successive misses gradually lower music volume (down to
-24 dB). A hit restores the target volume; a restart resets it. The timing
clock continues running throughout the fade.
