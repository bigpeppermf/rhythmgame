extends Control
## Flat 2D playfield. Everything the Judge cares about, nothing it doesn't.
##
## The 3D perspective view replaces only _draw(). The Judge compares normalized
## positions and has no idea what the renderer is doing — which is exactly why
## the logic gets proven here first, where a miss is visibly a miss.
##
##   SPACE  start / restart      TAB  switch hand (mock)
##   U      toggle UDP input     M    mirror mode (mock)
##   L      hold to lose tracking

const CHART_PATH := "res://charts/test.json"
## How far ahead a note becomes visible. Purely cosmetic - the Judge's window
## is much tighter.
const LOOKAHEAD := 1.6

var chart: Chart
var judge: Judge
var score := ScoreState.new()

var _flashes: Array = []      # {pos, verdict, age}
var _beat_pulse := 0.0
var _font: Font


func _ready() -> void:
	Field3D.solo = false
	_font = ThemeDB.fallback_font
	judge = Judge.new()
	add_child(judge)
	judge.note_judged.connect(_on_judged)
	Conductor.beat.connect(func(_i: int) -> void: _beat_pulse = 1.0)

	chart = Chart.load_from(CHART_PATH)
	if chart == null:
		return
	for w in chart.lint(2.0, Field3D.track):
		push_warning("chart lint: %s" % w)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE: _start()
		KEY_U:
			if HandState.source is UdpHandSource:
				HandState.use_mock()
			else:
				HandState.use_udp()


func _start() -> void:
	if chart == null:
		return
	score.reset()
	_flashes.clear()
	judge.begin(chart)
	Conductor.play(load(chart.audio_path), chart.bpm)


func _process(delta: float) -> void:
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 5.0)
	for f in _flashes:
		f.age += delta
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return f.age < 0.6)

	if Conductor.playing:
		judge.tick(Conductor.judge_time(), delta)
	queue_redraw()


func _on_judged(n: Note) -> void:
	score.apply(n)
	_flashes.append({"pos": n.pos, "verdict": n.verdict, "age": 0.0})


# ── drawing ──────────────────────────────────────────────────────────────────

## The play area: normalized [0,1] mapped to a centred box on screen.
func _field() -> Rect2:
	var m := 90.0
	var avail := size - Vector2(m * 2, m * 2)
	var side := minf(avail.x, avail.y)
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _to_screen(p: Vector2) -> Vector2:
	var f := _field()
	return f.position + p * f.size


func _slot_color(slot: int) -> Color:
	return Color(0.35, 0.85, 1.0) if slot == 0 else Color(1.0, 0.45, 0.75)


func _draw() -> void:
	var f := _field()
	# One track per hand, with the centre band left empty.
	for slot in 2:
		var t: Vector2 = Field3D.track(slot)
		var r := Rect2(f.position + Vector2(t.x * f.size.x, 0.0),
			Vector2((t.y - t.x) * f.size.x, f.size.y))
		draw_rect(r, Color(1, 1, 1, 0.04))
		draw_rect(r, Color(1, 1, 1, 0.12), false, 1.0)

	if Conductor.playing:
		_draw_notes(f)
	_draw_flashes(f)
	_draw_cursors(f)
	_draw_hud()


func _draw_notes(f: Rect2) -> void:
	var now := Conductor.judge_time()
	var r := Judge.HIT_RADIUS * f.size.x

	for n in chart.notes:
		if n.is_resolved():
			continue
		var dt := n.time - now
		if dt > LOOKAHEAD or dt < -Judge.WINDOW:
			continue

		var c := _slot_color(n.slot)
		var at := _to_screen(n.pos)
		# Fade in from far away so the field does not read as clutter.
		var fade: float = clampf(1.0 - dt / LOOKAHEAD, 0.0, 1.0)

		if n.kind == Note.Kind.HOLD:
			var held: float = n.held / maxf(n.length, 0.0001)
			draw_arc(at, r + 8.0, -PI / 2, -PI / 2 + TAU * held, 48,
				Color(c, 0.9 * fade), 5.0)

		draw_circle(at, r, Color(c, 0.16 * fade))
		draw_arc(at, r, 0, TAU, 40, Color(c, 0.85 * fade), 2.0)

		# Approach ring: shrinks onto the note as its moment arrives. In a
		# positional game there are no lanes to read timing from, so the ring
		# is where timing lives.
		if dt > 0.0:
			var t: float = dt / LOOKAHEAD
			draw_arc(at, r + t * f.size.x * 0.18, 0, TAU, 40,
				Color(c, 0.55 * fade), 1.5)


func _draw_flashes(f: Rect2) -> void:
	var r := Judge.HIT_RADIUS * f.size.x
	for fl in _flashes:
		var k: float = 1.0 - fl.age / 0.6
		var col: Color = _verdict_color(fl.verdict)
		draw_arc(_to_screen(fl.pos), r + (1.0 - k) * 44.0, 0, TAU, 40,
			Color(col, k * 0.9), 3.0)
		draw_string(_font, _to_screen(fl.pos) + Vector2(-30, -r - 14),
			Note.verdict_name(fl.verdict), HORIZONTAL_ALIGNMENT_CENTER, 60, 15,
			Color(col, k))


func _draw_cursors(f: Rect2) -> void:
	for slot in 2:
		var h: HandObservation = HandState.hands[slot]
		var at := _to_screen(HandState.cursor(slot))
		var c := _slot_color(slot)
		if h.state == HandObservation.State.LOST:
			draw_arc(at, 16.0, 0, TAU, 24, Color(c, 0.18), 1.0)
			continue
		# Confidence drives opacity, so degraded tracking is visible rather
		# than silently wrong.
		var a: float = clampf(h.conf, 0.15, 1.0)
		draw_circle(at, 9.0, Color(c, a * 0.35))
		draw_arc(at, 15.0, 0, TAU, 28, Color(c, a), 2.0)
		draw_line(at - Vector2(22, 0), at + Vector2(22, 0), Color(c, a * 0.5), 1.0)
		draw_line(at - Vector2(0, 22), at + Vector2(0, 22), Color(c, a * 0.5), 1.0)


func _draw_hud() -> void:
	if _beat_pulse > 0.0:
		draw_rect(Rect2(0, 0, size.x, 5), Color(1, 1, 1, _beat_pulse * 0.5))

	var lines := PackedStringArray()
	if chart == null:
		lines.append("no chart at %s" % CHART_PATH)
	elif not Conductor.playing:
		lines.append("%s  -  %d notes  -  SPACE to start" % [chart.title, chart.notes.size()])
		if not chart.warnings.is_empty():
			lines.append("lint: %d unreachable pair(s)" % chart.warnings.size())
			for w in chart.warnings:
				lines.append("   " + w)
	else:
		lines.append("Score %d   Multiplier x%d   Combo %d   Best Combo %d" %
			[score.score, score.multiplier, score.combo, score.best_combo])
		lines.append("PERFECT %d  GREAT %d  GOOD %d  MISS %d" % [
			score.counts[Note.Verdict.PERFECT], score.counts[Note.Verdict.GREAT],
			score.counts[Note.Verdict.GOOD], score.counts[Note.Verdict.MISS]])
		lines.append("t %6.2f   %d/%d" % [Conductor.judge_time(), score.judged, chart.notes.size()])

	lines.append("")
	lines.append("input: %s   (U toggles, TAB switches, M mirrors, L loses)" % HandState.source_name())

	var y := 26.0
	for l in lines:
		draw_string(_font, Vector2(24, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(1, 1, 1, 0.85))
		y += 20.0


func _verdict_color(v: Note.Verdict) -> Color:
	match v:
		Note.Verdict.PERFECT: return Color(0.5, 1.0, 0.7)
		Note.Verdict.GREAT: return Color(0.6, 0.85, 1.0)
		Note.Verdict.GOOD: return Color(1.0, 0.9, 0.5)
		_: return Color(1.0, 0.4, 0.4)
