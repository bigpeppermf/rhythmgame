extends Control
## Chart editor: a piano roll, one row per hand.
##
## Horizontal is beats, vertical is the height being charted. A tap is a dot,
## a hold is a bar. With one lane per hand there is no x to author - you pick
## a hand and a height - so the roll is the game's own view unrolled flat, and
## what you draw is literally the path the player's hand must trace.
##
##   click empty     place a tap          drag note        move it
##   drag note end   make / resize hold   Delete / RMB     remove
##   Space           play / pause         click ruler      seek
##   wheel           scroll               Ctrl+wheel       zoom
##   S               cycle snap           Ctrl+Z           undo
##   Ctrl+S          save                 P                playtest
##   J / K (hold)    record a note for L / R at the playhead, at the height
##                   your hand (or the mouse mock) is at. Hold for a hold.
##   Esc             back
##
## Every edit goes through a method that takes beats and heights rather than
## pixels, so the model can be exercised without a mouse.

signal finished
signal playtest_requested(chart: Chart)

enum Drag { NONE, MOVE, RESIZE, SCRUB }

const SNAPS := [1.0, 0.5, 0.25, 1.0 / 3.0, 1.0 / 6.0, 0.0]
const SNAP_NAMES := ["1/1", "1/2", "1/4", "1/3", "1/6", "off"]
const RULER := 30.0
const MARGIN_LEFT := 58.0
const STATUS := 56.0
const NOTE_R := 7.0
const HANDLE := 9.0
const MAX_UNDO := 200

var chart: Chart
var chart_path := "res://charts/test.json"

var px_per_beat := 72.0
var scroll_beat := 0.0
var snap_index := 2
var cursor_beat := 0.0
var selected: Note = null
var dirty := false

var _undo: Array[Dictionary] = []
var _drag := Drag.NONE
var _drag_note: Note = null
var _drag_grab_offset := 0.0
var _status := ""
var _status_until := 0.0
## Notes currently being recorded, per slot, while the record key is held.
var _recording: Array = [null, null]
var _esc_armed_until := 0.0
var _font: Font
var _stream: AudioStream


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process(true)
	if chart == null:
		load_chart(chart_path)


func load_chart(path: String) -> void:
	chart_path = path
	chart = Chart.load_from(path)
	if chart == null:
		chart = Chart.new()
		chart.title = path.get_file()
	_stream = load(chart.audio_path) if not chart.audio_path.is_empty() else null
	_undo.clear()
	selected = null
	dirty = false
	_relint()


# ── model ────────────────────────────────────────────────────────────────────
# These take beats and heights, never pixels. Input handlers translate.

func snap_beat(beat: float) -> float:
	var step: float = SNAPS[snap_index]
	return beat if step <= 0.0 else roundf(beat / step) * step


func place(slot: int, beat: float, height: float) -> Note:
	_snapshot()
	var n := Note.new()
	n.slot = clampi(slot, 0, 1)
	n.pos = Vector2(Field3D.lane_x(n.slot), clampf(height, 0.0, 1.0))
	n.kind = Note.Kind.TAP
	chart.set_beat(n, maxf(snap_beat(beat), 0.0))
	chart.notes.append(n)
	chart.sort_notes()
	selected = n
	_edited()
	return n


func remove(n: Note) -> void:
	if n == null:
		return
	_snapshot()
	chart.remove_note(n)
	if selected == n:
		selected = null
	_edited()


func move(n: Note, beat: float, height: float) -> void:
	chart.set_beat(n, maxf(snap_beat(beat), 0.0))
	n.pos.y = clampf(height, 0.0, 1.0)
	chart.sort_notes()
	_edited()


func set_length(n: Note, beats: float) -> void:
	# Anything shorter than half a snap step collapses back to a tap, so a
	# small wobble while dragging never leaves a near-zero hold behind.
	var step: float = SNAPS[snap_index] if SNAPS[snap_index] > 0.0 else 0.25
	var snapped: float = snap_beat(beats)
	chart.set_length_beats(n, snapped if snapped >= step * 0.5 else 0.0)
	_edited()


func toggle_hold(n: Note) -> void:
	if n == null:
		return
	_snapshot()
	set_length(n, 0.0 if n.kind == Note.Kind.HOLD else 1.0)


# ── record mode ──────────────────────────────────────────────────────────────
# Height comes from HandState - the same input the game judges - so recording
# with the camera charts what your hand actually did, and the mouse mock works
# the same way. Beat comes from the playhead. Hold the key and you get a hold.

func record_press(slot: int, beat: float, height: float) -> Note:
	if _recording[slot] != null:
		return _recording[slot]
	var n := place(slot, beat, height)
	_recording[slot] = n
	return n


func record_release(slot: int, beat: float) -> void:
	var n: Note = _recording[slot]
	if n == null:
		return
	_recording[slot] = null
	# set_length collapses anything under half a snap step back to a tap, so a
	# quick press is a tap and only a real hold becomes one.
	set_length(n, beat - chart.beat_of(n))


func undo() -> bool:
	if _undo.is_empty():
		_say("nothing to undo")
		return false
	chart.replace_notes_from(_undo.pop_back())
	selected = null
	_edited()
	_say("undo")
	return true


func save() -> bool:
	var target := chart_path
	if target.begins_with("res://") and not OS.has_feature("editor"):
		# An exported game cannot write into its own pack. Fall back to user://
		# so a save from a build still lands somewhere the author can find.
		target = "user://" + chart_path.get_file()
	if chart.save_to(target) != OK:
		_say("SAVE FAILED: %s" % target)
		return false
	dirty = false
	_say("saved %s (%d notes)" % [target, chart.notes.size()])
	return true


func _snapshot() -> void:
	_undo.append(chart.to_dict())
	while _undo.size() > MAX_UNDO:
		_undo.pop_front()


func _edited() -> void:
	dirty = true
	_relint()
	queue_redraw()


func _relint() -> void:
	chart.lint(2.0, Field3D.track)


# ── transport ────────────────────────────────────────────────────────────────

func playing() -> bool:
	return Conductor.playing


func play_from_cursor() -> void:
	if _stream == null:
		_say("no audio: %s" % chart.audio_path)
		return
	Conductor.play_from(_stream, chart.bpm, cursor_beat * chart.sec_per_beat() + chart.offset)


func pause() -> void:
	cursor_beat = chart.beat_of_time(Conductor.song_time) if playing() else cursor_beat
	Conductor.stop()


func seek_beat(beat: float) -> void:
	cursor_beat = maxf(beat, 0.0)
	if playing():
		Conductor.seek(cursor_beat * chart.sec_per_beat() + chart.offset)


func playhead_beat() -> float:
	return chart.beat_of_time(Conductor.song_time) if playing() else cursor_beat


# ── layout ───────────────────────────────────────────────────────────────────

func _roll_rect() -> Rect2:
	return Rect2(MARGIN_LEFT, RULER, size.x - MARGIN_LEFT, size.y - RULER - STATUS)


func _row_rect(slot: int) -> Rect2:
	var r := _roll_rect()
	var gap := 14.0
	var h := (r.size.y - gap) * 0.5
	return Rect2(r.position.x, r.position.y + slot * (h + gap), r.size.x, h)


func _beat_to_x(beat: float) -> float:
	return MARGIN_LEFT + (beat - scroll_beat) * px_per_beat


func _x_to_beat(x: float) -> float:
	return scroll_beat + (x - MARGIN_LEFT) / px_per_beat


func _height_to_y(h: float, slot: int) -> float:
	var r := _row_rect(slot)
	return r.position.y + h * r.size.y


func _y_to_height(y: float, slot: int) -> float:
	var r := _row_rect(slot)
	return clampf((y - r.position.y) / r.size.y, 0.0, 1.0)


func _slot_at(y: float) -> int:
	for slot in 2:
		if _row_rect(slot).has_point(Vector2(MARGIN_LEFT + 1.0, y)):
			return slot
	return -1


func _note_span(n: Note) -> Vector2:
	var x0 := _beat_to_x(chart.beat_of(n))
	var x1 := x0 + (chart.length_beats(n) * px_per_beat if n.kind == Note.Kind.HOLD else 0.0)
	return Vector2(x0, x1)


## Which note is under the point, and whether it is the resize handle.
func _hit(p: Vector2) -> Dictionary:
	# Iterate in reverse so the topmost drawn note wins on overlap.
	for i in range(chart.notes.size() - 1, -1, -1):
		var n: Note = chart.notes[i]
		var y := _height_to_y(n.pos.y, n.slot)
		if absf(p.y - y) > NOTE_R + 4.0:
			continue
		var span := _note_span(n)
		if n.kind == Note.Kind.HOLD and absf(p.x - span.y) <= HANDLE:
			return {"note": n, "resize": true}
		if p.x >= span.x - NOTE_R - 2.0 and p.x <= span.y + NOTE_R + 2.0:
			return {"note": n, "resize": false}
	return {}


func _ensure_visible(beat: float) -> void:
	var w := _roll_rect().size.x
	var x := _beat_to_x(beat)
	if x > MARGIN_LEFT + w * 0.8:
		scroll_beat = beat - (w * 0.25) / px_per_beat
	elif x < MARGIN_LEFT:
		scroll_beat = maxf(beat - (w * 0.25) / px_per_beat, 0.0)


# ── input ────────────────────────────────────────────────────────────────────

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion and _drag != Drag.NONE:
		_mouse_drag(event.position)


func _mouse_button(e: InputEventMouseButton) -> void:
	var p := e.position
	if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not e.pressed:
			return
		var dir := -1.0 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		if e.ctrl_pressed:
			var under := _x_to_beat(p.x)
			px_per_beat = clampf(px_per_beat * (0.85 if dir > 0 else 1.18), 16.0, 400.0)
			scroll_beat = maxf(under - (p.x - MARGIN_LEFT) / px_per_beat, 0.0)
		else:
			scroll_beat = maxf(scroll_beat + dir * 2.0, 0.0)
		queue_redraw()
		return

	if e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if p.y < RULER:
				_drag = Drag.SCRUB
				seek_beat(snap_beat(_x_to_beat(p.x)))
				return
			var hit := _hit(p)
			if not hit.is_empty():
				selected = hit.note
				_snapshot()
				_drag = Drag.RESIZE if hit.resize else Drag.MOVE
				_drag_note = hit.note
				_drag_grab_offset = _x_to_beat(p.x) - chart.beat_of(hit.note)
			else:
				var slot := _slot_at(p.y)
				if slot >= 0:
					var n := place(slot, _x_to_beat(p.x), _y_to_height(p.y, slot))
					_drag = Drag.MOVE
					_drag_note = n
					_drag_grab_offset = 0.0
				else:
					selected = null
		else:
			_drag = Drag.NONE
			_drag_note = null
		queue_redraw()

	elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
		var hit := _hit(p)
		if not hit.is_empty():
			remove(hit.note)


func _mouse_drag(p: Vector2) -> void:
	match _drag:
		Drag.SCRUB:
			seek_beat(snap_beat(_x_to_beat(p.x)))
		Drag.MOVE:
			move(_drag_note, _x_to_beat(p.x) - _drag_grab_offset,
				_y_to_height(p.y, _drag_note.slot))
		Drag.RESIZE:
			set_length(_drag_note, _x_to_beat(p.x) - chart.beat_of(_drag_note))
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k: int = event.keycode
	var rec_slot: int = 0 if k == KEY_J else (1 if k == KEY_K else -1)
	if rec_slot >= 0:
		if event.echo:
			return
		if event.pressed:
			record_press(rec_slot, playhead_beat(), HandState.cursor(rec_slot).y)
		else:
			record_release(rec_slot, playhead_beat())
		queue_redraw()
		return
	if not event.pressed:
		return
	var ctrl: bool = event.ctrl_pressed or event.meta_pressed
	if event.echo and k != KEY_LEFT and k != KEY_RIGHT:
		return
	match k:
		KEY_SPACE:
			if playing():
				pause()
			else:
				play_from_cursor()
		KEY_HOME:
			seek_beat(0.0)
			scroll_beat = 0.0
		KEY_LEFT:
			seek_beat(snap_beat(playhead_beat() - maxf(SNAPS[snap_index], 0.25)))
		KEY_RIGHT:
			seek_beat(snap_beat(playhead_beat() + maxf(SNAPS[snap_index], 0.25)))
		KEY_S:
			if ctrl:
				save()
			else:
				snap_index = (snap_index + 1) % SNAPS.size()
				_say("snap %s" % SNAP_NAMES[snap_index])
		KEY_Z:
			if ctrl:
				undo()
		KEY_H:
			toggle_hold(selected)
		KEY_DELETE, KEY_BACKSPACE:
			remove(selected)
		KEY_P:
			if dirty:
				save()
			Conductor.stop()
			chart.rewind()
			playtest_requested.emit(chart)
		KEY_ESCAPE:
			var now := Time.get_ticks_msec() / 1000.0
			if dirty and now > _esc_armed_until:
				_esc_armed_until = now + 2.0
				_say("unsaved changes - Ctrl+S to save, Esc again to discard")
			else:
				Conductor.stop()
				finished.emit()
	queue_redraw()


# ── drawing ──────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if playing():
		_ensure_visible(playhead_beat())
		for slot in 2:
			var n: Note = _recording[slot]
			if n != null:
				chart.set_length_beats(n, maxf(playhead_beat() - chart.beat_of(n), 0.0))
		queue_redraw()


func _draw() -> void:
	var sk := Ui.skin()
	Ui.background(self, size)
	if chart == null:
		return
	_draw_rows(sk)
	_draw_ruler(sk)
	_draw_notes(sk)
	_draw_lint(sk)
	_draw_playhead(sk)
	_draw_status(sk)


func _draw_rows(sk: GameSkin) -> void:
	var roll := _roll_rect()
	var first := int(floor(scroll_beat))
	var last := int(ceil(_x_to_beat(size.x)))
	for slot in 2:
		var r := _row_rect(slot)
		draw_rect(r, Color(sk.slot_color(slot), 0.05))
		draw_rect(r, Color(sk.slot_color(slot), 0.25), false, 1.0)
		# Height guides at quarters. y=0 is the TOP, matching the protocol.
		for q: float in [0.25, 0.5, 0.75]:
			var y: float = r.position.y + r.size.y * q
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.05), 1.0)
		_text("L" if slot == 0 else "R", Vector2(18, r.position.y + r.size.y * 0.5 + 6),
			18, sk.slot_color(slot))
		_text("top", Vector2(22, r.position.y + 12), 10, sk.ui_faint)
		_text("btm", Vector2(22, r.end.y - 4), 10, sk.ui_faint)
	# Beat grid across both rows; bars every 4 beats read heavier.
	for b in range(maxi(first, 0), last + 1):
		var x := _beat_to_x(float(b))
		if x < MARGIN_LEFT:
			continue
		var bar := b % 4 == 0
		draw_line(Vector2(x, roll.position.y), Vector2(x, roll.end.y),
			Color(1, 1, 1, 0.16 if bar else 0.06), 1.0)
	# Snap subdivisions, faint, only when zoomed in enough to be usable.
	var step: float = SNAPS[snap_index]
	if step > 0.0 and step < 1.0 and px_per_beat * step >= 10.0:
		var b := floorf(scroll_beat)
		while b < last + 1:
			var x := _beat_to_x(b)
			if x >= MARGIN_LEFT and absf(b - roundf(b)) > 0.001:
				draw_line(Vector2(x, roll.position.y), Vector2(x, roll.end.y),
					Color(1, 1, 1, 0.03), 1.0)
			b += step


func _draw_ruler(sk: GameSkin) -> void:
	draw_rect(Rect2(0, 0, size.x, RULER), Color(sk.ui_background.lightened(0.04)))
	var first := maxi(int(floor(scroll_beat)), 0)
	var last := int(ceil(_x_to_beat(size.x)))
	for b in range(first, last + 1):
		var x := _beat_to_x(float(b))
		if x < MARGIN_LEFT:
			continue
		var bar := b % 4 == 0
		draw_line(Vector2(x, RULER - (12 if bar else 6)), Vector2(x, RULER),
			Color(1, 1, 1, 0.5 if bar else 0.2), 1.0)
		if bar:
			_text("%d" % (b / 4 + 1), Vector2(x + 4, 13), 11, sk.ui_dim)
	_text("%s" % chart.title, Vector2(6, 13), 11, sk.ui_faint)


func _draw_notes(sk: GameSkin) -> void:
	for n in chart.notes:
		var span := _note_span(n)
		if span.y < MARGIN_LEFT - NOTE_R or span.x > size.x + NOTE_R:
			continue
		var y := _height_to_y(n.pos.y, n.slot)
		var c := sk.slot_color(n.slot)
		var sel: bool = n == selected
		if n.kind == Note.Kind.HOLD:
			draw_rect(Rect2(span.x, y - NOTE_R * 0.7, span.y - span.x, NOTE_R * 1.4),
				Color(c, 0.55))
			draw_rect(Rect2(span.y - 2.0, y - NOTE_R, 4.0, NOTE_R * 2.0), Color(c, 0.9))
		draw_circle(Vector2(span.x, y), NOTE_R, c)
		if sel:
			draw_arc(Vector2(span.x, y), NOTE_R + 4.0, 0, TAU, 32, Color(1, 1, 1, 0.9), 1.5)
			if n.kind == Note.Kind.HOLD:
				draw_arc(Vector2(span.y, y), HANDLE, 0, TAU, 24, Color(1, 1, 1, 0.6), 1.0)


## Flagged pairs drawn where they are, not listed: the whole point of the tool
## is making the invisible constraint visible.
func _draw_lint(sk: GameSkin) -> void:
	for pair in chart.flagged:
		var a: Note = pair[0]
		var b: Note = pair[1]
		var ax := _note_span(a).y
		var bx := _note_span(b).x
		var ay := _height_to_y(a.pos.y, a.slot)
		var by := _height_to_y(b.pos.y, b.slot)
		if maxf(ax, bx) < MARGIN_LEFT or minf(ax, bx) > size.x:
			continue
		draw_line(Vector2(ax, ay), Vector2(bx, by), Color(sk.miss_color, 0.85), 2.0)
		draw_circle(Vector2(bx, by), NOTE_R + 3.0, Color(sk.miss_color, 0.35))


func _draw_playhead(sk: GameSkin) -> void:
	var x := _beat_to_x(playhead_beat())
	if x < MARGIN_LEFT or x > size.x:
		return
	draw_line(Vector2(x, 0), Vector2(x, size.y - STATUS), sk.ui_accent, 2.0)
	draw_polygon(PackedVector2Array([
		Vector2(x - 6, 0), Vector2(x + 6, 0), Vector2(x, 9)]), [sk.ui_accent])


func _draw_status(sk: GameSkin) -> void:
	var y0 := size.y - STATUS
	draw_rect(Rect2(0, y0, size.x, STATUS), Color(sk.ui_background.lightened(0.03)))
	var beat := playhead_beat()
	var left := "%s   beat %.2f   %d notes   snap %s   zoom %.0f px/beat   %s%s" % [
		"PLAYING" if playing() else "paused", beat, chart.notes.size(),
		SNAP_NAMES[snap_index], px_per_beat,
		"" if chart.warnings.is_empty() else "%d unreachable   " % chart.warnings.size(),
		"*unsaved*" if dirty else "saved"]
	_text(left, Vector2(12, y0 + 20), 13, sk.ui_text)
	var now := Time.get_ticks_msec() / 1000.0
	if now < _status_until:
		_text(_status, Vector2(12, y0 + 42), 13, sk.ui_warn)
	else:
		_text("click place   drag move   drag end hold   RMB/Del remove   Space play   " +
			"S snap   H hold   J/K record L/R   Ctrl+Z undo   Ctrl+S save   P playtest   Esc back",
			Vector2(12, y0 + 42), 12, sk.ui_faint)


func _say(msg: String) -> void:
	_status = msg
	_status_until = Time.get_ticks_msec() / 1000.0 + 2.5
	queue_redraw()


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
