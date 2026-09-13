extends Node
## Score-derived timing, physically continuous hand motion, and merged scene paths.
var failures := 0
const DT := 1.0 / 240.0

func _ready() -> void:
	HandState.source = null
	HandState.gestures_seen = false
	for solo in [false, true]:
		_test_chart(solo)
	await _test_scenes()
	Conductor.stop()
	await get_tree().create_timer(0.1).timeout
	print("Prototype: %d failures" % failures)
	get_tree().quit(1 if failures else 0)

func _test_chart(solo: bool) -> void:
	Field3D.solo = solo
	var path := "res://charts/entertainer_solo.json" if solo else "res://charts/entertainer.json"
	var c := Chart.load_from(path)
	_check(c != null and not c.notes.is_empty(), "prototype chart loads: " + path)
	if c == null or c.notes.is_empty():
		return
	_check(c.lint(2.0, Field3D.track).is_empty(), "all movements fit the reach budget")
	var stream: AudioStream = load(c.audio_path)
	_check(stream != null and stream.get_length() > c.duration() + 1.0,
		"guide audio covers the final hold and outro")
	_check(is_equal_approx(c.notes[0].time, 3.5 * 60.0 / 80.0), "pickup matches the score")
	var hook := false
	for n in c.notes:
		if is_equal_approx(c.beat_of(n), 5.75) and n.kind == Note.Kind.HOLD:
			hook = true
	_check(hook, "the tied syncopated arrival remains a hold")

	# Interpolate from each release to the next onset, rather than teleporting.
	var by_slot: Array = [[], []]
	for n in c.notes:
		by_slot[n.slot].append(n)
	var judge := Judge.new()
	add_child(judge)
	var score := ScoreState.new()
	judge.note_judged.connect(score.apply)
	judge.begin(c)
	var now := 0.0
	while now < c.duration() + 0.5:
		for slot in 2:
			var h: HandObservation = HandState.hands[slot]
			h.pos = _position(by_slot[slot], now)
			h.vel = Vector2.ZERO
			h.conf = 1.0
			h.state = HandObservation.State.TRACKED
		judge.tick(now, DT)
		now += DT
	_check(judge.finished() and score.judged == c.notes.size(), "every prototype note resolves")
	_check(score.counts[Note.Verdict.MISS] == 0, "continuous reachable motion misses no notes")
	_check(score.accuracy() > 95.0, "continuous motion scores above 95 percent")
	judge.free()

func _position(notes: Array, now: float) -> Vector2:
	if notes.is_empty():
		return Vector2(0.5, 0.5)
	var prev: Note = null
	for n: Note in notes:
		if now < n.time:
			if prev == null:
				return n.pos
			var start: float = prev.end_time()
			return prev.pos.lerp(n.pos, clampf((now - start) / (n.time - start), 0.0, 1.0))
		if now <= n.end_time():
			return n.pos
		prev = n
	return notes[-1].pos

func _test_scenes() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for solo in [true, false]:
		main._show_prototype(solo)
		await get_tree().process_frame
		var play: Node = main._current
		_check(Conductor.playing and play.chart.notes.size() > 0, "menu starts prototype audio")
		_check(play.field._cursors.size() == (1 if solo else 2), "prototype mode builds correct cursors")
		Conductor.stop()
		# Check a hold after its head passes the hit line: its body must remain.
		var n := Note.new()
		n.kind = Note.Kind.HOLD
		n.time = 1.0
		n.length = 2.0
		n.pos = Vector2(Field3D.lane_x(0), 0.5)
		var tail := Note.new()
		tail.time = 1.5
		var c := Chart.new()
		c.notes.assign([n, tail])
		_check(is_equal_approx(c.duration(), 3.0), "chart duration includes an earlier long hold")
		play.field.clear()
		play.field.sync(c, 1.7)
		_check(play.field._shown.has(n), "hold body stays visible after its onset window")
	main.free()
	Field3D.solo = false

func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])
