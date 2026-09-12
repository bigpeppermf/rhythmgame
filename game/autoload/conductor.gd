extends Node
## The single source of musical time.
##
## Everything in the game reads `song_time` from here. Notes derive their
## position from it, the Judge compares against it, visuals pulse on it.
## Nothing else is allowed to keep its own idea of what time it is.
##
## Autoloaded as `Conductor` (see project.godot).

signal beat(index: int)
signal song_started
signal song_finished

## Authoritative position in the song, in seconds.
var song_time: float = 0.0

## Raw reading from the audio hardware, before any smoothing. Exposed only so
## the debug view can show you the difference. Do not use this for gameplay.
var audio_time: float = 0.0

var bpm: float = 120.0
var playing: bool = false

## Calibration. Positive values mean "the player's input arrives late, so judge
## against an earlier point in the song." Tuned per-machine in a calibration
## screen later; this is the knob that absorbs the whole camera pipeline delay.
var input_offset: float = 0.0

var _player: AudioStreamPlayer
var _last_beat: int = -1
var _started: bool = false


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = &"Master"
	add_child(_player)
	set_process(false)


## Autoloads outlive the scene tree, so their children and any resource they
## hold have to be released explicitly or they are still live at shutdown.
func _exit_tree() -> void:
	if _player != null:
		_player.stop()
		_player.stream = null


func play(stream: AudioStream, song_bpm: float) -> void:
	play_from(stream, song_bpm, 0.0)


## Start (or restart) at an arbitrary point. The editor scrubs with this.
func play_from(stream: AudioStream, song_bpm: float, from_seconds: float) -> void:
	bpm = song_bpm
	_player.stream = stream
	song_time = from_seconds
	audio_time = from_seconds
	# Beats before the seek point must not fire. floor(t/spb) is the last beat
	# already past, so starting there means the next one emitted is the first
	# that genuinely follows.
	var spb: float = 60.0 / maxf(bpm, 0.0001)
	_last_beat = int(floor(from_seconds / spb)) if from_seconds > 0.0 else -1
	_started = false
	playing = true
	set_process(true)
	_player.play(from_seconds)
	song_started.emit()


## Jump within the song that is already playing.
##
## `_started = false` is the point of this: it makes the next _process reseed
## song_time straight from the audio clock instead of easing toward it. The
## continuous correction is built for drift of a few milliseconds; asked to
## absorb a two second jump it would take a visible second to settle, and the
## editor would feel broken.
func seek(to_seconds: float) -> void:
	if _player.stream == null:
		return
	var spb: float = 60.0 / maxf(bpm, 0.0001)
	song_time = to_seconds
	audio_time = to_seconds
	_last_beat = int(floor(to_seconds / spb)) if to_seconds > 0.0 else -1
	_started = false
	playing = true
	set_process(true)
	_player.play(to_seconds)


func stop() -> void:
	_player.stop()
	playing = false
	set_process(false)


func sec_per_beat() -> float:
	return 60.0 / bpm


## Song time as gameplay should see it: the musical clock, shifted by the
## calibrated input latency.
func judge_time() -> float:
	return song_time - input_offset


func _process(delta: float) -> void:
	if not playing:
		return

	if not _player.playing:
		playing = false
		set_process(false)
		song_finished.emit()
		return

	audio_time = _read_audio_clock()
	song_time = _compute_song_time(delta, audio_time)
	_emit_beats()


## The raw hardware clock.
##
## get_playback_position() alone is not enough: it is only updated once per
## audio mix buffer, so between updates it reports a stale value. The two
## AudioServer terms correct for that and for the output buffer's own delay.
func _read_audio_clock() -> float:
	return _player.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()


## How fast the audio clock pulls our free-running clock back toward it,
## expressed as the fraction of remaining error removed per second.
const RESYNC_RATE := 8.0

## Divergence beyond this is not drift — it is a seek, a stall, or a buffer
## underrun. Easing through it would take a visible second, so we snap.
const RESYNC_SNAP := 0.10


## Combine the two clocks: run smoothly on `delta`, but let the audio hardware
## continuously pull us back so we can never drift away from it.
##
## `audio_clock` is authoritative but steppy — it only updates once per mix
## buffer, so at high frame rates we read the same value several frames running
## and then see a jump. `delta` is smooth but knows nothing about the audio
## hardware, so on its own it accumulates error.
##
## Neither snapping (jitter gets through) nor free-running (drift) is
## acceptable, so we do neither: advance by `delta`, then remove a fixed
## fraction of the error every second.
func _compute_song_time(delta: float, audio_clock: float) -> float:
	if not _started:
		_started = true
		return audio_clock

	var t: float = song_time + delta
	var error: float = audio_clock - t

	if absf(error) > RESYNC_SNAP:
		return audio_clock

	# Frame-rate independent exponential approach. The naive `error * k` form
	# removes k of the error per *frame*, so the same constant behaves
	# differently at 60fps and 144fps — and a frame spike overshoots. This form
	# removes the same fraction per *second* of real time no matter how many
	# frames that took.
	return t + error * (1.0 - exp(-RESYNC_RATE * delta))


func _emit_beats() -> void:
	var spb: float = sec_per_beat()
	if spb <= 0.0:
		return
	var current: int = int(floor(song_time / spb))
	while _last_beat < current:
		_last_beat += 1
		beat.emit(_last_beat)
