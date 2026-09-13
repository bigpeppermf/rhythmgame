extends Node
## Drives the editor's model without a mouse: place, move, resize, delete,
## undo, snap, save, live lint.
##   godot --headless res://tests/editor_test.tscn

var failures := 0
var ed: Control


func _ready() -> void:
	HandState.source = null
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child(ed)
	await get_tree().process_frame
	ed.load_chart("res://charts/test.json")
	_check(ed.chart != null and ed.chart.notes.size() == 38, "editor loads the test chart")
	var base: int = ed.chart.notes.size()

	# ── snap ────────────────────────────────────────────────────────────────
	ed.snap_index = 2                                   # 1/4
	_check(is_equal_approx(ed.snap_beat(8.13), 8.25), "1/4 snap: 8.13 -> 8.25")
	ed.snap_index = 3                                   # 1/3
	_check(absf(ed.snap_beat(8.4) - 8.3333) < 0.001, "1/3 snap: 8.4 -> 8.333")
	ed.snap_index = 5                                   # off
	_check(is_equal_approx(ed.snap_beat(8.13), 8.13), "snap off leaves the beat alone")
	ed.snap_index = 2

	# ── place ───────────────────────────────────────────────────────────────
	var n: Note = ed.place(0, 8.13, 0.62)
	_check(ed.chart.notes.size() == base + 1, "place adds a note")
	_check(is_equal_approx(ed.chart.beat_of(n), 8.25), "placed note is snapped")
	_check(is_equal_approx(n.pos.x, Field3D.lane_x(0)), "placed note sits on its lane x")
	_check(is_equal_approx(n.pos.y, 0.62), "placed note keeps its height")
	_check(ed.selected == n and ed.dirty, "placing selects and dirties")
	_check(_sorted(), "notes stay sorted after place")

	# ── move ────────────────────────────────────────────────────────────────
	ed.move(n, 12.6, 0.2)
	_check(is_equal_approx(ed.chart.beat_of(n), 12.5) and is_equal_approx(n.pos.y, 0.2),
		"move snaps beat and clamps height")
	ed.move(n, -3.0, 1.7)
	_check(ed.chart.beat_of(n) >= 0.0 and n.pos.y <= 1.0, "move clamps to valid range")
	_check(_sorted(), "notes stay sorted after move")

	# ── hold ────────────────────────────────────────────────────────────────
	ed.set_length(n, 2.1)
	_check(n.kind == Note.Kind.HOLD and is_equal_approx(ed.chart.length_beats(n), 2.0),
		"resize makes a snapped 2-beat hold")
	ed.set_length(n, 0.05)
	_check(n.kind == Note.Kind.TAP and n.length == 0.0,
		"a hold shorter than half a snap collapses to a tap")
	ed.toggle_hold(n)
	_check(n.kind == Note.Kind.HOLD and is_equal_approx(ed.chart.length_beats(n), 1.0),
		"H toggles a 1-beat hold on")
	ed.toggle_hold(n)
	_check(n.kind == Note.Kind.TAP, "H toggles it back off")

	# ── delete + undo ───────────────────────────────────────────────────────
	var before: int = ed.chart.notes.size()
	ed.remove(n)
	_check(ed.chart.notes.size() == before - 1 and ed.selected == null, "remove deletes and deselects")
	_check(ed.undo(), "undo restores the removed note")
	_check(ed.chart.notes.size() == before, "count is back after undo")
	while ed.undo():
		pass
	_check(ed.chart.notes.size() == base, "undoing everything returns to the loaded chart (%d)" % ed.chart.notes.size())
	_check(not ed.undo(), "undo on an empty stack is a no-op")

	# ── live lint ───────────────────────────────────────────────────────────
	var flagged_before: int = ed.chart.flagged.size()
	ed.snap_index = 5
	ed.place(1, 50.0, 0.05)
	ed.place(1, 50.1, 0.95)     # 0.9 of height in 50 ms - impossible; beat 50 is past the chart so nothing else is nearby
	_check(ed.chart.flagged.size() == flagged_before + 1,
		"an unreachable pair is flagged as soon as it is placed (%d -> %d)" %
		[flagged_before, ed.chart.flagged.size()])
	ed.undo(); ed.undo()
	_check(ed.chart.flagged.size() == flagged_before, "undoing it clears the flag")

	# ── transport ───────────────────────────────────────────────────────────
	ed.seek_beat(16.0)
	_check(is_equal_approx(ed.playhead_beat(), 16.0), "seek moves the paused playhead")
	ed.play_from_cursor()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(ed.playing() and ed.playhead_beat() >= 15.9, "play starts from the cursor (%.2f)" % ed.playhead_beat())
	ed.pause()
	_check(not ed.playing() and ed.playhead_beat() >= 15.9, "pause keeps the position")

	# ── record mode ─────────────────────────────────────────────────────────
	ed.snap_index = 2
	var count_before: int = ed.chart.notes.size()
	var r: Note = ed.record_press(1, 44.13, 0.33)
	_check(ed.chart.notes.size() == count_before + 1 and is_equal_approx(ed.chart.beat_of(r), 44.25)
		and is_equal_approx(r.pos.y, 0.33), "record press places a snapped note at the hand's height")
	_check(ed.record_press(1, 44.5, 0.9) == r, "a second press while held does not place again")
	ed.record_release(1, 44.30)
	_check(r.kind == Note.Kind.TAP, "a quick press records a tap")
	var h: Note = ed.record_press(0, 46.0, 0.5)
	ed.record_release(0, 48.05)
	_check(h.kind == Note.Kind.HOLD and is_equal_approx(ed.chart.length_beats(h), 2.0),
		"holding the key records a 2-beat hold")
	ed.record_release(0, 99.0)
	_check(h.kind == Note.Kind.HOLD and is_equal_approx(ed.chart.length_beats(h), 2.0),
		"a release with nothing recording is ignored")

	# ── gestures ────────────────────────────────────────────────────────────
	var gnote: Note = ed.place(0, 60.0, 0.5)
	_check(not gnote.needs_gesture(), "a placed note requires no gesture by default")
	ed.set_gesture(gnote, &"FIST")
	_check(gnote.gesture == &"FIST", "set_gesture requires a fist")
	ed.set_gesture(gnote, &"NOT_A_GESTURE")
	_check(gnote.gesture == &"", "an unknown gesture name clears the requirement")
	ed.set_gesture(gnote, &"PINCH")
	ed.undo()
	# Undo restores a snapshot, so every Note is a fresh object afterwards and
	# the old reference is stale. Look the note up again by where it is.
	gnote = _note_at(60.0, 0)
	_check(gnote != null and gnote.gesture == &"", "gesture changes are undoable")
	HandState.hands[1].gesture = &"THUMBS_UP"
	var rec: Note = ed.record_press(1, 62.0, 0.4)
	ed.record_release(1, 62.1)
	_check(rec.gesture == &"THUMBS_UP", "record captures the hand's current gesture")
	HandState.hands[1].gesture = &"UNKNOWN"
	var rec2: Note = ed.record_press(1, 64.0, 0.4)
	ed.record_release(1, 64.1)
	_check(not rec2.needs_gesture(), "record with no gesture reported stays plain")
	ed.set_gesture(gnote, &"FIST")

	# ── save round trip ─────────────────────────────────────────────────────
	ed.snap_index = 2
	ed.place(0, 40.0, 0.5)
	ed.chart_path = "user://editor_test.json"
	_check(ed.save() and not ed.dirty, "save succeeds and clears dirty")
	var back := Chart.load_from("user://editor_test.json")
	_check(back != null and back.notes.size() == ed.chart.notes.size(),
		"saved chart reloads with %d notes" % (back.notes.size() if back else -1))
	var fists := 0
	for bn in back.notes:
		if bn.gesture == &"FIST":
			fists += 1
	_check(fists == 1, "the gesture requirement survives save and reload (%d fist)" % fists)

	_finish()


func _note_at(beat: float, slot: int) -> Note:
	for n in ed.chart.notes:
		if n.slot == slot and absf(ed.chart.beat_of(n) - beat) < 0.01:
			return n
	return null


func _sorted() -> bool:
	for i in range(1, ed.chart.notes.size()):
		if ed.chart.notes[i].time < ed.chart.notes[i - 1].time - 0.0001:
			return false
	return true


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	Conductor.stop()
	# Allow the audio server to release its last playback before shutdown.
	await get_tree().create_timer(0.1).timeout
	print("\n%s (%d failures)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)
