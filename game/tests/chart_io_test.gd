extends Node
## Round-tripping and seeking - the two primitives the editor is built on.
##   godot --headless res://tests/chart_io_test.tscn

const SRC := "res://charts/test.json"
const OUT := "user://roundtrip.json"

var failures := 0


func _ready() -> void:
	HandState.source = null
	_test_roundtrip()
	await _test_seek()
	_finish()


## Load -> save -> load must reproduce every note exactly. If it does not, the
## editor silently rewrites every chart it opens.
func _test_roundtrip() -> void:
	var a := Chart.load_from(SRC)
	_check(a != null, "source chart loads")
	if a == null:
		return

	_check(a.save_to(OUT) == OK, "saves without error")
	var b := Chart.load_from(OUT)
	_check(b != null, "saved chart loads back")
	if b == null:
		return

	_check(b.title == a.title, "title survives")
	_check(is_equal_approx(b.bpm, a.bpm), "bpm survives")
	_check(b.audio_path == a.audio_path, "audio path survives")
	_check(b.notes.size() == a.notes.size(),
		"note count survives (%d -> %d)" % [a.notes.size(), b.notes.size()])
	if b.notes.size() != a.notes.size():
		return

	var worst_time := 0.0
	var worst_pos := 0.0
	var mismatched := 0
	for i in a.notes.size():
		var x: Note = a.notes[i]
		var y: Note = b.notes[i]
		worst_time = maxf(worst_time, absf(x.time - y.time))
		worst_pos = maxf(worst_pos, x.pos.distance_to(y.pos))
		if x.slot != y.slot or x.kind != y.kind:
			mismatched += 1
		worst_time = maxf(worst_time, absf(x.length - y.length))
	# 0.1 ms: well inside the tightest judging window, so a round trip can
	# never move a note into a different grade.
	_check(worst_time < 0.0001, "times survive (worst %.6fs)" % worst_time)
	_check(worst_pos < 0.0005, "positions survive (worst %.6f)" % worst_pos)
	_check(mismatched == 0, "slot and kind survive (%d mismatched)" % mismatched)

	# Saving twice must be stable, or the file churns on every open.
	b.save_to(OUT)
	var c := Chart.load_from(OUT)
	_check(c != null and c.notes.size() == b.notes.size(), "second save is stable")

	var warns := b.lint(2.0, Field3D.track)
	_check(warns.size() == 1, "lint result survives the trip, got %d" % warns.size())

	# The gesture field, when present, must come back exactly.
	a.notes[0].gesture = &"PINCH"
	a.notes[1].gesture = &"FIST"
	a.save_to(OUT)
	var g := Chart.load_from(OUT)
	_check(g != null and g.notes[0].gesture == &"PINCH" and g.notes[1].gesture == &"FIST"
		and not g.notes[2].needs_gesture(),
		"gesture requirements round-trip (and absence stays absent)")


## A seek must land where asked and must not replay beats it jumped over.
func _test_seek() -> void:
	var beats: Array[int] = []
	Conductor.beat.connect(func(i: int) -> void: beats.append(i))
	Conductor.play(load("res://audio/click_120.wav"), 120.0)
	await get_tree().process_frame

	Conductor.seek(10.0)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(absf(Conductor.song_time - 10.0) < 0.15,
		"seek lands at 10s, got %.3f" % Conductor.song_time)
	# At 120 BPM, 10s is beat 20. Nothing below that should have fired.
	var stale := 0
	for i in beats:
		if i < 19:
			stale += 1
	_check(stale == 0, "no beats replayed from before the seek (%d stale)" % stale)

	# And it must keep running from there rather than stalling.
	var before := Conductor.song_time
	for _i in 30:
		await get_tree().process_frame
	_check(Conductor.song_time > before,
		"clock still advances after seek (%.3f -> %.3f)" % [before, Conductor.song_time])
	Conductor.stop()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	# Let the audio server release stopped playback before the tree exits.
	await get_tree().create_timer(0.1).timeout
	print("\n%s (%d failures)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)
