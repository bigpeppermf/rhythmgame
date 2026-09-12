extends Node
## Exercises scene flow, settings persistence and the calibration statistics.
##   godot --headless res://tests/flow_test.tscn

var failures := 0


func _ready() -> void:
	HandState.source = null
	await _test_scenes_instantiate()
	_test_signals_exist()
	await _test_flow_transitions()
	_test_settings_roundtrip()
	_test_calibration_stats()
	_test_results_stats()
	_finish()


func _test_scenes_instantiate() -> void:
	for path in ["res://scenes/menu.tscn", "res://scenes/calibrate.tscn",
			"res://scenes/results.tscn", "res://scenes/play_3d.tscn",
			"res://scenes/main.tscn"]:
		var packed: PackedScene = load(path)
		_check(packed != null, "%s loads" % path.get_file())
		if packed == null:
			continue
		var n: Node = packed.instantiate()
		add_child(n)
		await get_tree().process_frame
		_check(is_instance_valid(n), "%s survives _ready" % path.get_file())
		n.queue_free()
		remove_child(n)
	Conductor.stop()


## Main wires itself to these by name; a rename would otherwise only surface
## as a crash mid-demo.
func _test_signals_exist() -> void:
	var expect := {
		"res://scenes/menu.tscn": ["play_pressed", "calibrate_pressed"],
		"res://scenes/play_3d.tscn": ["song_finished", "quit_to_menu"],
		"res://scenes/calibrate.tscn": ["finished"],
		"res://scenes/results.tscn": ["finished"],
	}
	for path in expect:
		var n: Node = load(path).instantiate()
		for sig in expect[path]:
			_check(n.has_signal(sig), "%s has signal %s" % [path.get_file(), sig])
		n.free()
	Conductor.stop()


func _test_flow_transitions() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	_check(main._current != null, "flow starts on a scene")

	main._show_play()
	await get_tree().process_frame
	_check(main._current.has_signal("song_finished"), "menu -> play")

	var score := ScoreState.new()
	score.apply(_note(Note.Verdict.PERFECT, 0.01))
	main._show_results(score, main._current.chart)
	await get_tree().process_frame
	_check(main._current.has_method("setup"), "play -> results")

	main._show_menu()
	await get_tree().process_frame
	_check(main._current.has_signal("play_pressed"), "results -> menu")

	main._show_calibrate()
	await get_tree().process_frame
	_check(main._current.has_signal("finished"), "menu -> calibrate")

	main.queue_free()
	remove_child(main)
	Conductor.stop()


func _test_settings_roundtrip() -> void:
	var original := Settings.input_offset
	Settings.set_offset(0.0731)
	_check(is_equal_approx(Conductor.input_offset, 0.0731),
		"set_offset reaches the Conductor")
	Settings.input_offset = 0.0
	Settings.load_settings()
	_check(absf(Settings.input_offset - 0.0731) < 0.0001,
		"offset survives a save/load, got %.4f" % Settings.input_offset)
	_check(absf(Conductor.judge_time() - (Conductor.song_time - 0.0731)) < 0.0001,
		"judge_time applies the offset")
	Settings.set_offset(original)


## Median must ignore a single wild sample; a mean would not.
func _test_calibration_stats() -> void:
	var cal: Node = load("res://scenes/calibrate.tscn").instantiate()
	add_child(cal)
	cal.samples = PackedFloat32Array([0.04, 0.05, 0.045, 0.05, 0.30])
	var med: float = cal._median()
	_check(absf(med - 0.048) < 0.005,
		"median resists a 300ms outlier, got %.3f" % med)
	var mean := 0.0
	for s in cal.samples:
		mean += s
	mean /= cal.samples.size()
	_check(mean > 0.09, "a mean would have been dragged to %.3f" % mean)
	cal.queue_free()
	remove_child(cal)
	Conductor.stop()


## Misses carry no timing information, so they must not bias the mean.
func _test_results_stats() -> void:
	var r: Node = load("res://scenes/results.tscn").instantiate()
	add_child(r)
	var chart := Chart.new()
	chart.notes.append(_note(Note.Verdict.PERFECT, 0.02))
	chart.notes.append(_note(Note.Verdict.GREAT, 0.06))
	chart.notes.append(_note(Note.Verdict.MISS, 0.22))
	r.setup(ScoreState.new(), chart)
	var mean: float = r._mean_error()
	_check(absf(mean - 0.04) < 0.001,
		"mean error excludes misses, got %.3f (0.100 if misses counted)" % mean)
	var h: PackedInt32Array = r._histogram()
	var total := 0
	for v in h:
		total += v
	_check(total == 2, "histogram counts only judged hits, got %d" % total)
	r.queue_free()
	remove_child(r)


func _note(v: Note.Verdict, err: float) -> Note:
	var n := Note.new()
	n.verdict = v
	n.timing_error = err
	return n


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("\n%s (%d failures)" % ["ALL PASS" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)
