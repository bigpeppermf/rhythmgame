extends Control
## Measures how late the player's input lands, and stores it.
##
## This screen is what makes the rest of the design honest. The camera pipeline
## runs 50-150ms behind reality; almost all of that is *constant*, and constant
## delay is not a latency problem but an offset problem. Measure it once, judge
## against `song_time - offset`, and it stops mattering. What survives is
## jitter, which is small enough to live with.
##
## Method: two targets alternate on every beat, so the pattern is completely
## predictable and the player can anticipate rather than react. We record when
## they actually arrive relative to each beat and take the median. Anticipation
## means this measures pipeline delay plus the player's own systematic bias -
## which is exactly what we want to cancel, since both are present in play too.

signal finished

const CLICK := "res://audio/click_120.wav"
const BPM := 120.0
const RADIUS := 0.13
const WARMUP := 4        # beats to ignore while the player finds the rhythm
const WANTED := 20       # samples to collect after warmup
## A sample further than this from its beat is a missed swing, not a reading.
const SANE := 0.35

var samples: PackedFloat32Array = PackedFloat32Array()
var running := false

var _armed_beat := -1
var _armed_target := Vector2.ZERO
var _got_this_beat := false
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	Conductor.beat.connect(_on_beat)
	set_process(true)


func _exit_tree() -> void:
	if Conductor.beat.is_connected(_on_beat):
		Conductor.beat.disconnect(_on_beat)


func _target_for(beat: int) -> Vector2:
	return Vector2(0.28 if beat % 2 == 0 else 0.72, 0.5)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE: _start()
		KEY_ENTER, KEY_KP_ENTER: _accept()
		KEY_ESCAPE:
			Conductor.stop()
			finished.emit()
		KEY_R:
			samples.clear()


func _start() -> void:
	samples.clear()
	_armed_beat = -1
	running = true
	Conductor.play(load(CLICK), BPM)


func _accept() -> void:
	if samples.size() >= 4:
		Settings.set_offset(_median())
	Conductor.stop()
	running = false
	finished.emit()


func _on_beat(index: int) -> void:
	_armed_beat = index
	_armed_target = _target_for(index)
	_got_this_beat = false


func _process(_delta: float) -> void:
	queue_redraw()
	if not running or not Conductor.playing or _got_this_beat:
		return
	if samples.size() >= WANTED + WARMUP:
		return

	# Measure against the raw song clock, not judge_time() - we are trying to
	# discover the offset, so applying the current one would fold it in twice.
	var now := Conductor.song_time
	for slot in 2:
		var h: HandObservation = HandState.hands[slot]
		if not h.is_usable():
			continue
		if HandState.cursor(slot).distance_to(_armed_target) > RADIUS:
			continue
		_got_this_beat = true
		var beat_time: float = _armed_beat * 60.0 / BPM
		var err: float = now - beat_time
		if absf(err) <= SANE and _armed_beat >= WARMUP:
			samples.append(err)
		break


## Median, not mean: one fumbled swing should not drag the result, and with
## only ~20 samples a single 300ms outlier would move a mean by 15ms.
func _median() -> float:
	if samples.is_empty():
		return 0.0
	var a := Array(samples)
	a.sort()
	var n := a.size()
	return a[n / 2] if n % 2 == 1 else (a[n / 2 - 1] + a[n / 2]) * 0.5


func _spread() -> float:
	if samples.size() < 2:
		return 0.0
	var m := _median()
	var d: Array = []
	for s in samples:
		d.append(absf(s - m))
	d.sort()
	return d[d.size() / 2]      # median absolute deviation


# ── drawing ──────────────────────────────────────────────────────────────────

func _field() -> Rect2:
	var side := minf(size.x - 160.0, size.y - 320.0)
	return Rect2(Vector2((size.x - side) * 0.5, 150.0), Vector2(side, side * 0.45))


func _to_screen(p: Vector2) -> Vector2:
	var f := _field()
	return f.position + p * f.size


func _draw() -> void:
	Ui.background(self, size)
	var f := _field()
	var collected: int = samples.size()

	for beat_parity in 2:
		var at := _to_screen(_target_for(beat_parity))
		var live: bool = running and _armed_beat >= 0 and _armed_beat % 2 == beat_parity
		var c := Color(1, 1, 1, 0.85 if live else 0.18)
		draw_arc(at, RADIUS * f.size.x, 0, TAU, 48, c, 3.0 if live else 1.5)
		if live and _got_this_beat:
			draw_circle(at, RADIUS * f.size.x * 0.55, Color(Ui.skin().ui_accent, 0.35))

	for slot in 2:
		var h: HandObservation = HandState.hands[slot]
		if h.state == HandObservation.State.LOST:
			continue
		var at := _to_screen(HandState.cursor(slot))
		var c := Ui.skin().slot_color(slot)
		draw_circle(at, 10.0, Color(c, clampf(h.conf, 0.2, 1.0)))

	_draw_scatter(collected)
	_draw_text(collected)


## Every sample as a dot on a ±300ms axis, with the median marked. Seeing the
## spread matters as much as the number: a tight cluster means the reading is
## trustworthy, a smear means the tracking is too noisy to calibrate against.
func _draw_scatter(collected: int) -> void:
	var top := size.y - 150.0
	var w := size.x - 160.0
	var x0 := 80.0
	var mid := x0 + w * 0.5

	draw_line(Vector2(x0, top), Vector2(x0 + w, top), Color(1, 1, 1, 0.12), 1.0)
	draw_line(Vector2(mid, top - 34), Vector2(mid, top + 34), Color(1, 1, 1, 0.35), 1.0)
	for ms in [-200, -100, 100, 200]:
		var x: float = mid + (ms / 300.0) * (w * 0.5)
		draw_line(Vector2(x, top - 10), Vector2(x, top + 10), Color(1, 1, 1, 0.12), 1.0)
		draw_string(_font, Vector2(x - 14, top + 28), "%+d" % ms,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.3))

	for s in samples:
		var x: float = mid + clampf(s / 0.3, -1.0, 1.0) * (w * 0.5)
		draw_circle(Vector2(x, top), 4.0, Color(Ui.skin().great_color, 0.75))

	if collected >= 4:
		var x: float = mid + clampf(_median() / 0.3, -1.0, 1.0) * (w * 0.5)
		draw_line(Vector2(x, top - 26), Vector2(x, top + 26), Ui.skin().ui_accent, 2.5)


func _draw_text(collected: int) -> void:
	var lines := PackedStringArray()
	if not running:
		lines.append("CALIBRATION")
		lines.append("")
		lines.append("Swing between the two circles, one per click.")
		lines.append("Do not react to the beat - anticipate it.")
		lines.append("")
		lines.append("SPACE start     ENTER accept     R reset     ESC back")
		lines.append("")
		lines.append("current offset: %+.0f ms" % (Settings.input_offset * 1000.0))
	else:
		var need: int = WANTED + WARMUP
		lines.append("beat %d     samples %d / %d" % [_armed_beat, collected, WANTED])
		if collected >= 4:
			lines.append("")
			lines.append("offset  %+.0f ms      spread  +-%.0f ms" %
				[_median() * 1000.0, _spread() * 1000.0])
			if _spread() > 0.040:
				lines.append("spread is high - tracking may be too noisy to trust")
		if collected >= WANTED:
			lines.append("")
			lines.append("ENTER to accept")

	var y := 34.0
	for l in lines:
		draw_string(_font, Vector2(80, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Ui.skin().ui_text)
		y += 24.0
