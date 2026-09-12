extends Node
## Headless test for Chart + Judge. Run:
##   godot --headless res://tests/judge_test.tscn
##
## Drives the Judge with a synthetic clock rather than real audio, so it is
## fast and deterministic: no sound card, no wall-clock waiting, identical
## results every run.

const CHART := "res://charts/test.json"
const DT := 1.0 / 120.0

var failures: int = 0


func _ready() -> void:
	# Detach the live input so nothing overwrites the hands we script.
	HandState.source = null

	var chart := Chart.load_from(CHART)
	_check(chart != null, "chart loads")
	if chart == null:
		return _finish()

	_check(chart.notes.size() == 38, "38 notes, got %d" % chart.notes.size())
	_check(chart.bpm == 120.0, "bpm 120")
	_check(_is_sorted(chart), "notes sorted by time")

	# The generator plants exactly one physically impossible pair.
	var warns := chart.lint()
	_check(warns.size() == 1, "lint finds 1 unreachable pair, got %d" % warns.size())
	if warns.size() == 1:
		print("      ", warns[0])

	_run_perfect(chart)
	_run_idle(chart)
	_run_holds_released(chart)
	_finish()


## A player who is always exactly on the note should score straight PERFECTs.
func _run_perfect(chart: Chart) -> void:
	var res := _simulate(chart, true, 1.0)
	_check(res.judged == chart.notes.size(),
		"perfect play judges every note (%d/%d)" % [res.judged, chart.notes.size()])
	_check(res.counts[Note.Verdict.MISS] == 0,
		"perfect play misses nothing, got %d" % res.counts[Note.Verdict.MISS])
	_check(res.counts[Note.Verdict.PERFECT] == chart.notes.size(),
		"all PERFECT, got %d" % res.counts[Note.Verdict.PERFECT])
	_check(res.combo == chart.notes.size(), "combo unbroken (%d)" % res.combo)
	_check(res.accuracy > 99.9, "accuracy %.1f%%" % res.accuracy)


## A player who never moves should miss everything - and crucially, every note
## must still resolve. A note that never resolves would hang the chart.
func _run_idle(chart: Chart) -> void:
	var res := _simulate(chart, false, 1.0)
	_check(res.judged == chart.notes.size(),
		"idle play still resolves every note (%d/%d)" % [res.judged, chart.notes.size()])
	_check(res.counts[Note.Verdict.MISS] == chart.notes.size(),
		"idle play misses everything, got %d" % res.counts[Note.Verdict.MISS])
	_check(res.score == 0, "idle score 0, got %d" % res.score)


## Grabbing holds but releasing them a third of the way through should drop
## those notes below HOLD_PASS while taps still land.
func _run_holds_released(chart: Chart) -> void:
	var holds: int = 0
	for n in chart.notes:
		if n.kind == Note.Kind.HOLD:
			holds += 1
	var res := _simulate(chart, true, 0.33)
	_check(res.counts[Note.Verdict.MISS] == holds,
		"releasing holds early misses exactly the %d holds, got %d" %
		[holds, res.counts[Note.Verdict.MISS]])


## hold_ratio: fraction of each HOLD the synthetic hand stays inside for.
func _simulate(chart: Chart, follow: bool, hold_ratio: float) -> Dictionary:
	var judge := Judge.new()
	add_child(judge)
	var score := ScoreState.new()
	judge.note_judged.connect(func(n: Note) -> void: score.apply(n))
	judge.begin(chart)

	var next: Array[int] = [0, 0]
	var by_slot: Array = [[], []]
	for n in chart.notes:
		by_slot[n.slot].append(n)

	var t: float = -1.0
	var limit: float = chart.duration() + Judge.WINDOW + 1.0
	while t < limit:
		if follow:
			for slot in 2:
				HandState.hands[slot].pos = _target(by_slot[slot], next, slot, t, hold_ratio)
				HandState.hands[slot].conf = 1.0
				HandState.hands[slot].state = HandObservation.State.TRACKED
		else:
			for slot in 2:
				HandState.hands[slot].pos = Vector2(0.5, 0.02)  # parked, far from every note
				HandState.hands[slot].conf = 1.0
				HandState.hands[slot].state = HandObservation.State.TRACKED
		judge.tick(t, DT)
		t += DT

	judge.queue_free()
	return {
		"judged": score.judged, "counts": score.counts,
		"score": score.score, "combo": score.best_combo,
		"accuracy": score.accuracy(),
	}


## Where a perfect hand would be at time t: on the next note once its moment
## has arrived, parked out of the way otherwise.
func _target(notes: Array, next: Array[int], slot: int, t: float,
		hold_ratio: float) -> Vector2:
	while next[slot] < notes.size():
		var n: Note = notes[next[slot]]
		var leave: float = n.time + (n.length * hold_ratio if n.kind == Note.Kind.HOLD else 0.0)
		if t > leave + 0.01:
			next[slot] += 1
			continue
		if t >= n.time - 0.005:
			return n.pos
		return Vector2(0.5, 0.02)
	return Vector2(0.5, 0.02)


func _is_sorted(chart: Chart) -> bool:
	for i in range(1, chart.notes.size()):
		if chart.notes[i].time < chart.notes[i - 1].time:
			return false
	return true


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("\n%s (%d failure%s)" % [
		"ALL PASS" if failures == 0 else "FAILURES", failures,
		"" if failures == 1 else "s"])
	get_tree().quit(1 if failures > 0 else 0)
