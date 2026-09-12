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

var score: ScoreState
var chart: Chart
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process(true)


func setup(s: ScoreState, c: Chart) -> void:
	score = s
	chart = c


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE, KEY_SPACE]:
			finished.emit()


func _process(_delta: float) -> void:
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


## Everything sits in one centred column so the layout holds at any window
## aspect rather than drifting to one side of a wide screen.
func _column() -> Rect2:
	var w := minf(size.x - 96.0, 620.0)
	return Rect2(Vector2((size.x - w) * 0.5, maxf(60.0, size.y * 0.10)), Vector2(w, 0))


func _draw() -> void:
	var sk := Ui.skin()
	Ui.background(self, size)
	if score == null:
		return
	var col := _column()
	var x := col.position.x
	var y := col.position.y

	_text("RESULTS", Vector2(x, y), 17, sk.ui_faint)
	y += 58.0
	_text("%d" % score.score, Vector2(x, y), 46, sk.ui_text)
	y += 34.0
	_text("%.1f%%    best combo x%d" % [score.accuracy(), score.best_combo],
		Vector2(x, y), 17, sk.ui_dim)

	y += 52.0
	for v in [Note.Verdict.PERFECT, Note.Verdict.GREAT, Note.Verdict.GOOD, Note.Verdict.MISS]:
		_text("%-8s %3d" % [Note.verdict_name(v), score.counts[v]], Vector2(x, y), 16,
			_verdict_color(v))
		y += 24.0

	_draw_histogram(y + 46.0, col)
	_text("ENTER to continue", Vector2(x, size.y - 52.0), 15, sk.ui_faint)


func _draw_histogram(top: float, col: Rect2) -> void:
	var sk := Ui.skin()
	var h := _histogram()
	var peak := 1
	for v in h:
		peak = maxi(peak, v)

	var w := col.size.x
	var x0 := col.position.x
	var bw := w / BUCKETS
	var height := 110.0

	_text("timing", Vector2(x0, top - 12), 14, sk.ui_faint)

	for i in BUCKETS:
		var frac := float(h[i]) / peak
		var bar := frac * height
		var x := x0 + i * bw
		# Centre bucket is on-time; edges are early (left) and late (right).
		var dist: float = absf(i - (BUCKETS - 1) * 0.5) / ((BUCKETS - 1) * 0.5)
		var c := sk.ui_accent.lerp(sk.ui_warn, dist)
		draw_rect(Rect2(x + 1, top + height - bar, bw - 2, bar), Color(c, 0.9))

	var mid := x0 + w * 0.5
	draw_line(Vector2(mid, top - 6), Vector2(mid, top + height + 6), sk.ui_faint, 1.0)
	draw_line(Vector2(x0, top + height), Vector2(x0 + w, top + height),
		Color(sk.ui_faint, 0.4), 1.0)
	_text("early", Vector2(x0, top + height + 20), 13, sk.ui_faint)
	_text("late", Vector2(x0 + w - 26, top + height + 20), 13, sk.ui_faint)

	var mean := _mean_error()
	_text("mean %+.0f ms" % (mean * 1000.0), Vector2(x0, top + height + 48), 15, sk.ui_dim)

	# Close the loop back to calibration: a cluster that is consistently off
	# centre is an offset that was measured wrong, not a player who is bad.
	if absf(mean) > 0.045:
		_text("consistently %s - recalibrating would recover this" %
			("late" if mean > 0 else "early"),
			Vector2(x0, top + height + 72), 14, sk.ui_warn)


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _verdict_color(v: Note.Verdict) -> Color:
	return Ui.skin().verdict_color(v)
