class_name Judge
extends Node
## Decides whether notes were hit.
##
## There is no tap event to listen for. A hand is simply somewhere, continuously,
## and a note is hittable for a window of time. So judging is an *overlap*
## question — "was the hand inside this note while the note was live?" — rather
## than "at exactly what instant did the player press?".
##
## That is what makes the whole design survive ~100ms of camera latency: there
## is no instant to get wrong, only a window to be inside.

signal note_judged(note: Note)
signal hold_progress(note: Note, fraction: float)

## How far either side of a note's time it can still be hit. Generous on
## purpose — see the class comment.
const WINDOW := 0.22

const PERFECT_TIME := 0.05
const GREAT_TIME := 0.10
const GOOD_TIME := 0.18

## Spatial tolerance in normalized units. A note is a circle this big.
const HIT_RADIUS := 0.09
const PERFECT_RADIUS := 0.035
const GREAT_RADIUS := 0.060

## A HOLD must be entered within this of its start or it is a miss outright.
const HOLD_GRAB := 0.15
## Fraction of a hold that must be held to count as hit at all.
const HOLD_PASS := 0.5

var chart: Chart = null
var active: Array[Note] = []

var _next: int = 0


func begin(c: Chart) -> void:
	chart = c
	chart.rewind()
	active.clear()
	_next = 0


## Call once per frame with the calibrated song time.
func tick(now: float, delta: float) -> void:
	if chart == null:
		return
	_admit(now)

	var still: Array[Note] = []
	for n in active:
		if _evaluate(n, now, delta):
			still.append(n)
	active = still


## Move notes into the active set as their window opens. The chart is sorted,
## so this is a pointer walk rather than a search.
func _admit(now: float) -> void:
	while _next < chart.notes.size() and chart.notes[_next].time - WINDOW <= now:
		active.append(chart.notes[_next])
		_next += 1


## Returns true if the note is still live.
func _evaluate(n: Note, now: float, delta: float) -> bool:
	var hand: HandObservation = HandState.hands[n.slot]
	var inside: bool = hand.is_usable() and HandState.cursor(n.slot).distance_to(n.pos) <= HIT_RADIUS

	if n.kind == Note.Kind.HOLD:
		return _evaluate_hold(n, now, delta, hand, inside)

	# TAP. Resolve the moment the hand arrives, rather than waiting for the
	# window to close: late feedback feels like the game is lagging, even when
	# the verdict is right.
	if inside:
		n.timing_error = now - n.time
		n.hit_distance = HandState.cursor(n.slot).distance_to(n.pos)
		n.verdict = _grade(absf(n.timing_error), n.hit_distance)
		note_judged.emit(n)
		return false

	if now > n.time + WINDOW:
		n.verdict = Note.Verdict.MISS
		n.timing_error = WINDOW
		note_judged.emit(n)
		return false

	return true


func _evaluate_hold(n: Note, now: float, delta: float, hand: HandObservation,
		inside: bool) -> bool:
	if not n._entered:
		if inside:
			n._entered = true
			n.timing_error = now - n.time
		elif now > n.time + HOLD_GRAB:
			n.verdict = Note.Verdict.MISS
			note_judged.emit(n)
			return false
		else:
			return true

	# Accumulate only while actually inside. Letting go mid-hold does not fail
	# the note outright — it just costs you the fraction you dropped.
	if inside:
		n.held = minf(n.held + delta, n.length)
	if n.length > 0.0:
		hold_progress.emit(n, n.held / n.length)

	if now >= n.end_time():
		var frac: float = n.held / maxf(n.length, 0.0001)
		if frac < HOLD_PASS:
			n.verdict = Note.Verdict.MISS
		elif frac > 0.95:
			n.verdict = Note.Verdict.PERFECT
		elif frac > 0.8:
			n.verdict = Note.Verdict.GREAT
		else:
			n.verdict = Note.Verdict.GOOD
		note_judged.emit(n)
		return false

	return true


## Grade on both axes and take the worse. You need to be on time *and* on
## target; being excellent at one does not excuse the other.
func _grade(dt: float, dist: float) -> Note.Verdict:
	var by_time: Note.Verdict
	if dt <= PERFECT_TIME:
		by_time = Note.Verdict.PERFECT
	elif dt <= GREAT_TIME:
		by_time = Note.Verdict.GREAT
	elif dt <= GOOD_TIME:
		by_time = Note.Verdict.GOOD
	else:
		by_time = Note.Verdict.MISS

	var by_space: Note.Verdict
	if dist <= PERFECT_RADIUS:
		by_space = Note.Verdict.PERFECT
	elif dist <= GREAT_RADIUS:
		by_space = Note.Verdict.GREAT
	else:
		by_space = Note.Verdict.GOOD

	# Verdict enum ascends PENDING, PERFECT, GREAT, GOOD, MISS - so "worse" is
	# the larger value.
	return maxi(by_time, by_space) as Note.Verdict


func finished() -> bool:
	return chart != null and _next >= chart.notes.size() and active.is_empty()
