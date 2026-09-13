extends Node
## Scoring boundaries, two-hand judging, and real scene restart regression tests.
var failures := 0

func _ready() -> void:
	HandState.source = null
	HandState.gestures_seen = false
	_test_values_and_thresholds()
	_test_two_hands()
	_test_restart()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Scoring: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _hit(s: ScoreState, verdict: Note.Verdict) -> void:
	var n := Note.new()
	n.verdict = verdict
	s.apply(n)

func _test_values_and_thresholds() -> void:
	var s := ScoreState.new()
	for verdict in [Note.Verdict.PERFECT, Note.Verdict.GREAT, Note.Verdict.GOOD, Note.Verdict.MISS]:
		_hit(s, verdict)
	_check(s.score == 225 and s.combo == 0 and s.best_combo == 3 and s.multiplier == 1,
		"base points, successful combo, miss reset, best combo retained")
	for count in s.counts.values():
		_check(count == 1, "each verdict counted")
	s.reset()
	for i in range(1, 52):
		var before := s.score
		_hit(s, Note.Verdict.PERFECT)
		var expected := 1 if i < 10 else (2 if i < 20 else (3 if i < 30 else (4 if i < 40 else 5)))
		_check(s.multiplier == expected and s.score - before == 100 * expected,
			"hit %d uses x%d" % [i, expected])
	var before := s.score
	_hit(s, Note.Verdict.GREAT)
	_hit(s, Note.Verdict.GOOD)
	_check(s.score - before == 625, "GREAT and GOOD use x5")
	before = s.score
	_hit(s, Note.Verdict.MISS)
	_check(s.score == before and s.combo == 0 and s.multiplier == 1 and s.best_combo == 53,
		"miss awards zero and immediately resets x5 to x1")
	_hit(s, Note.Verdict.GREAT)
	_check(s.score == before + 75 and s.combo == 1, "next hit starts fresh combo at x1")
	s.reset()
	_check_reset(s)

func _test_two_hands() -> void:
	for spacing in [0.0, 0.005]:
		var s := ScoreState.new()
		for i in 9:
			_hit(s, Note.Verdict.PERFECT)
		var c := Chart.new()
		for slot in 2:
			var n := Note.new()
			n.slot = slot
			n.time = 1.0 + slot * spacing
			c.notes.append(n)
			HandState.hands[slot].pos = n.pos
			HandState.hands[slot].vel = Vector2.ZERO
			HandState.hands[slot].conf = 1.0
			HandState.hands[slot].state = HandObservation.State.TRACKED
		var j := Judge.new()
		add_child(j)
		j.note_judged.connect(s.apply)
		j.begin(c)
		j.tick(1.0, 0.005)
		j.tick(1.005, 0.005)
		j.tick(1.01, 0.005)
		_check(s.score == 1300 and s.combo == 11 and s.counts[Note.Verdict.PERFECT] == 11,
			"two hands %sms apart each score once across threshold" % (spacing * 1000))
		j.free()

func _test_restart() -> void:
	for scene in ["res://scenes/play_3d.tscn", "res://scenes/play_test.tscn"]:
		var play: Node = load(scene).instantiate()
		add_child(play)
		play._start()
		var original: ScoreState = play.score
		for i in 45:
			_hit(play.score, Note.Verdict.PERFECT)
		_hit(play.score, Note.Verdict.GREAT)
		_hit(play.score, Note.Verdict.GOOD)
		_hit(play.score, Note.Verdict.MISS)
		_hit(play.score, Note.Verdict.PERFECT)
		for n in play.chart.notes:
			n.verdict = Note.Verdict.GREAT
			n.timing_error = 0.07
			n.held = 0.5
			n._entered = true
			n._gesture_ok = true
		play._start()
		_check(play.score == original, "restart reuses ScoreState: " + scene)
		_check_reset(play.score)
		var clean := true
		for n in play.chart.notes:
			clean = clean and n.verdict == Note.Verdict.PENDING and n.timing_error == 0.0 \
				and n.held == 0.0 and not n._entered and not n._gesture_ok
		_check(clean, "restart clears note and timing history: " + scene)
		var results: Node = load("res://scenes/results.tscn").instantiate()
		results.setup(play.score, play.chart)
		var total := 0
		for count in results._histogram():
			total += count
		_check(total == 0 and results._mean_error() == 0.0, "restart clears timing graph and mean")
		results.free()
		play.free()
		Conductor.stop()

func _check_reset(s: ScoreState) -> void:
	_check(s.score == 0 and s.combo == 0 and s.best_combo == 0 and s.multiplier == 1 and s.judged == 0,
		"reset clears score, combo, best combo, multiplier, judged")
	_check(s.counts.values().all(func(n: int) -> bool: return n == 0), "reset clears all verdict counts")

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
