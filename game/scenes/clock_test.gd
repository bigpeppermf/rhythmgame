extends Control
## Debug harness for the Conductor.
##
## The click track is 120 BPM, so beat N lands at exactly N * 0.5s. That makes
## this scene self-verifying: if the flash and the click ever drift apart, your
## clock is wrong, and the graph shows you how.
##
## SPACE = start / restart.

const CLICK_PATH := "res://audio/click_120.wav"
const BPM := 120.0
const HISTORY := 240

var _rate_song: PackedFloat32Array = PackedFloat32Array()
var _rate_audio: PackedFloat32Array = PackedFloat32Array()
var _prev_song := 0.0
var _prev_audio := 0.0
var _flash := 0.0
var _beat_index := -1

var _info: Label
var _hint: Label


func _ready() -> void:
	_info = Label.new()
	_info.position = Vector2(24, 20)
	_info.add_theme_font_size_override("font_size", 18)
	add_child(_info)

	_hint = Label.new()
	_hint.position = Vector2(24, 20)
	_hint.add_theme_font_size_override("font_size", 20)
	_hint.text = "SPACE to start"
	add_child(_hint)

	Conductor.beat.connect(_on_beat)
	set_process(true)


func _on_beat(index: int) -> void:
	_beat_index = index
	# Downbeats flash harder, matching the accented click.
	_flash = 1.0 if index % 4 == 0 else 0.6


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_accept") or (
			event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
		_start()


func _start() -> void:
	var stream: AudioStream = load(CLICK_PATH)
	if stream == null:
		_hint.text = "Missing %s\nRun: python3 tools/make_click_track.py" % CLICK_PATH
		return
	_rate_song.clear()
	_rate_audio.clear()
	_prev_song = 0.0
	_prev_audio = 0.0
	_beat_index = -1
	_hint.text = ""
	Conductor.play(stream, BPM)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta * 6.0)

	if Conductor.playing and delta > 0.0:
		# Rate error: how fast is each clock advancing, relative to real time?
		#   0.0  = advancing exactly in step with the frame
		#  -1.0  = did not advance at all this frame (a stalled, steppy clock)
		#  +N    = jumped forward by N extra frames' worth at once
		_rate_song.append((Conductor.song_time - _prev_song) / delta - 1.0)
		_rate_audio.append((Conductor.audio_time - _prev_audio) / delta - 1.0)
		while _rate_song.size() > HISTORY:
			_rate_song.remove_at(0)
			_rate_audio.remove_at(0)

	_prev_song = Conductor.song_time
	_prev_audio = Conductor.audio_time

	_info.text = _build_readout()
	queue_redraw()


func _build_readout() -> String:
	if not Conductor.playing:
		return ""
	var expected := _beat_index * 60.0 / BPM
	return "\n".join([
		"song_time   %8.3f s" % Conductor.song_time,
		"audio_time  %8.3f s" % Conductor.audio_time,
		"divergence  %+8.1f ms   (song - audio)" %
			((Conductor.song_time - Conductor.audio_time) * 1000.0),
		"",
		"beat %d   expected at %.3f s   error %+.1f ms" %
			[_beat_index, expected, (Conductor.song_time - expected) * 1000.0],
		"",
		"smoothness  song %s   audio %s" %
			[_rms(_rate_song), _rms(_rate_audio)],
	])


## Root-mean-square of the rate error. Near 0.00 means the clock advances
## evenly every frame. Large means it lurches.
func _rms(a: PackedFloat32Array) -> String:
	if a.is_empty():
		return "--"
	var acc := 0.0
	for v in a:
		acc += v * v
	return "%.2f" % sqrt(acc / a.size())


func _draw() -> void:
	var s := size

	# Beat flash: a bar across the top, brightest on the downbeat.
	if _flash > 0.0:
		draw_rect(Rect2(0, 0, s.x, 8), Color(0.4, 0.9, 1.0, _flash))

	if _rate_song.is_empty():
		return

	# Strip chart of rate error. A perfectly smooth clock is a flat line on
	# the centre; a steppy one sawtooths between -1 and positive spikes.
	var top := 260.0
	var h := 150.0
	var mid := top + h * 0.5
	var w := s.x - 48.0

	draw_rect(Rect2(24, top, w, h), Color(1, 1, 1, 0.04))
	draw_line(Vector2(24, mid), Vector2(24 + w, mid), Color(1, 1, 1, 0.25), 1.0)

	_plot(_rate_audio, 24.0, w, mid, h, Color(1.0, 0.45, 0.35, 0.9))
	_plot(_rate_song,  24.0, w, mid, h, Color(0.4, 0.95, 0.6, 0.95))

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(32, top + h + 22), "red = audio_time (raw)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.45, 0.35))
	draw_string(font, Vector2(220, top + h + 22), "green = song_time (yours)",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 0.95, 0.6))


func _plot(data: PackedFloat32Array, x0: float, w: float, mid: float,
		h: float, col: Color) -> void:
	if data.size() < 2:
		return
	var pts := PackedVector2Array()
	var step := w / float(HISTORY)
	for i in data.size():
		# +-2.0 rate error maps to the full height of the strip.
		var y := mid - clampf(data[i], -2.0, 2.0) * (h * 0.25)
		pts.append(Vector2(x0 + i * step, y))
	draw_polyline(pts, col, 1.5)
