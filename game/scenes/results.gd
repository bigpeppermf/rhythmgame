extends Control
## End-of-song summary.
##
## The timing histogram is the part worth having. A score tells the player how
## they did; the distribution of timing errors tells them *why* - and if the
## whole cluster sits off-centre, that is a calibration problem rather than a
## skill one, which the screen says out loud.

signal finished

const BUCKETS := 21          # odd, so there is a true centre bucket
const RANGE := 0.25          # +-250ms across the histogram
const DESIGN_SIZE := Vector2(1100, 720)
const BACKGROUND := preload("res://assets/menu/game_bg.png")
const BUBBLE := preload("res://assets/menu/bubble.png")
const FONT := preload("res://assets/fonts/cherry_bomb_one/CherryBombOne-Regular.ttf")

var score: ScoreState
var chart: Chart
var _font: Font
var _continue: Button


func _ready() -> void:
	_font = FONT
	_continue = Button.new()
	_continue.text = "Continue"
	_continue.add_theme_font_override("font", FONT)
	_continue.add_theme_font_size_override("font_size", 24)
	_continue.add_theme_color_override("font_color", Color("244c70"))
	_continue.add_theme_color_override("font_hover_color", Color("244c70"))
	_continue.add_theme_color_override("font_focus_color", Color("244c70"))
	_continue.add_theme_color_override("font_pressed_color", Color("244c70"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("b8f1ec") if state == "normal" else Color("fff0bc")
		style.set_corner_radius_all(18)
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("fff0bc")
			style.set_border_width_all(3)
		_continue.add_theme_stylebox_override(state, style)
	_continue.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_continue.pressed.connect(func(): finished.emit())
	add_child(_continue)
	resized.connect(_layout)
	_layout()
	_continue.grab_focus()


func setup(s: ScoreState, c: Chart) -> void:
	score = s
	chart = c
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE]:
			finished.emit()


func _layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	_continue.scale = Vector2.ONE * factor
	_continue.size = Vector2(280, 48)
	_continue.position = (size - DESIGN_SIZE * factor) * 0.5 + Vector2(410, 614) * factor
	queue_redraw()


## Mean timing error across everything that was actually hit. Misses carry no
## timing information, so including them would bias the result.
func _mean_error() -> float:
	if chart == null:
		return 0.0
	var total := 0.0
	var n := 0
	for note in chart.notes:
		if note.verdict == Note.Verdict.PENDING or note.verdict == Note.Verdict.MISS:
			continue
		total += note.timing_error
		n += 1
	return total / n if n > 0 else 0.0


func _histogram() -> PackedInt32Array:
	var h := PackedInt32Array()
	h.resize(BUCKETS)
	if chart == null:
		return h
	for note in chart.notes:
		if note.verdict == Note.Verdict.PENDING or note.verdict == Note.Verdict.MISS:
			continue
		var t: float = clampf(note.timing_error / RANGE, -1.0, 1.0)
		h[int(round((t + 1.0) * 0.5 * (BUCKETS - 1)))] += 1
	return h


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var sk := Ui.skin()
	# Cover the window with the same artwork as gameplay, preserving its ratio.
	var zoom := maxf(size.x / BACKGROUND.get_width(), size.y / BACKGROUND.get_height())
	var source_size := size / zoom
	draw_texture_rect_region(BACKGROUND, Rect2(Vector2.ZERO, size),
		Rect2((BACKGROUND.get_size() - source_size) * 0.5, source_size))
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	draw_set_transform((size - DESIGN_SIZE * factor) * 0.5, 0, Vector2.ONE * factor)
	for bubble in [Rect2(42, 135, 62, 62), Rect2(100, 240, 24, 24),
			Rect2(62, 510, 86, 86), Rect2(967, 112, 48, 48),
			Rect2(991, 374, 70, 70), Rect2(956, 580, 28, 28)]:
		draw_texture_rect(BUBBLE, bubble, false, Color(1, 1, 1, 0.65))
	_card(Rect2(150, 32, 800, 650), Color(0.08, 0.19, 0.38, 0.88), Color(sk.slot_color(0), 0.7))
	if score == null:
		return
	_center("Results", 84, 40, Color("fff0bc"))
	_center("Score: %d" % score.score, 184, 52, sk.ui_accent)
	_center("Combo: %d    Multiplier: x%d    Best combo: %d" %
		[score.combo, score.multiplier, score.best_combo],
		222, 20, sk.ui_text)
	var verdicts := [Note.Verdict.PERFECT, Note.Verdict.GREAT, Note.Verdict.GOOD, Note.Verdict.MISS]
	_card(Rect2(190, 250, 720, 90), Color(0.25, 0.47, 0.63, 0.48), Color("b8f1ec"))
	for i in verdicts.size():
		var v: Note.Verdict = verdicts[i]
		var x := 190.0 + i * 180.0
		_text(Note.verdict_name(v).capitalize() + ":", Vector2(x + 16, 282), 22, sk.ui_text)
		_text(str(score.counts[v]), Vector2(x + 16, 322), 30, sk.ui_text)
	_draw_histogram(398, Rect2(190, 0, 720, 0))
	draw_set_transform(Vector2.ZERO)


func _draw_histogram(top: float, col: Rect2) -> void:
	var sk := Ui.skin()
	var h := _histogram()
	var peak := 1
	for v in h:
		peak = maxi(peak, v)

	var w := col.size.x
	var x0 := col.position.x
	var bw := w / BUCKETS
	var height := 100.0

	_text("Timing", Vector2(x0, top - 20), 24, sk.ui_text)

	for i in BUCKETS:
		var frac := float(h[i]) / peak
		var bar := frac * height
		var x := x0 + i * bw
		# Centre bucket is on-time; edges are early (left) and late (right).
		var dist: float = absf(i - (BUCKETS - 1) * 0.5) / ((BUCKETS - 1) * 0.5)
		var c := sk.ui_accent.lerp(sk.ui_warn, dist)
		draw_rect(Rect2(x + 1, top + height - bar, bw - 2, bar), Color(c, 0.9))

	var mid := x0 + w * 0.5
	draw_line(Vector2(mid, top - 6), Vector2(mid, top + height + 6), Color("b8f1ec"), 1.0)
	draw_line(Vector2(x0, top + height), Vector2(x0 + w, top + height),
		Color(sk.ui_text, 0.4), 1.0)
	_text("Early", Vector2(x0, top + height + 22), 17, Color("b8f1ec"))
	_text("Late", Vector2(x0 + w - 42, top + height + 22), 17, Color("b8f1ec"))

	var mean := _mean_error()
	var hits := score.judged - int(score.counts[Note.Verdict.MISS])
	_center("Average timing: %+.0f ms" % (mean * 1000.0) if hits > 0 else "No hits to measure yet",
		top + height + 52, 20, sk.ui_text)

	# Close the loop back to calibration: a cluster that is consistently off
	# centre is an offset that was measured wrong, not a player who is bad.
	if absf(mean) > 0.045:
		_center("Consistently %s — try recalibrating your timing" %
			("late" if mean > 0 else "early"),
			top + height + 84, 17, sk.ui_warn)


func _card(rect: Rect2, fill: Color, border: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(22)
	draw_style_box(style, rect)


func _center(s: String, baseline: float, px: int, color: Color) -> void:
	var width := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	_text(s, Vector2((DESIGN_SIZE.x - width) * 0.5, baseline), px, color)


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _verdict_color(v: Note.Verdict) -> Color:
	return Ui.skin().verdict_color(v)
