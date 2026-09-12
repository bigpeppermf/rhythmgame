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

## Spatial tolerance in normalized units of HEIGHT. Each hand has one lane,
## so a note's x carries no information and is not judged: the tracker's x is
## wherever the hand happens to be in the camera frame, and asking it to also
## land on the lane centre would fail players for standing slightly off-axis.
const HIT_RADIUS := 0.09
const PERFECT_RADIUS := 0.035
const GREAT_RADIUS := 0.060

## A HOLD must be entered within this of its start or it is a miss outright.
const HOLD_GRAB := 0.15

## Minimum classifier confidence for a hand shape to count.
const GESTURE_CONF := 0.5
## Right place, right time, wrong hand shape: the verdict can be no better
## than this. GOOD rather than MISS because the classifier is wrong on the
## order of one frame in ten, and a miss for a reason the player cannot see
## reads as the game being broken. Set to Note.Verdict.MISS to make the
## gesture the whole note.
const WRONG_GESTURE_CAP := Note.Verdict.GOOD
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
	var inside: bool = hand.is_usable() and _distance(n) <= HIT_RADIUS
	if inside and not n._gesture_ok and n.needs_gesture():
		n._gesture_ok = hand.gesture == n.gesture and hand.gesture_conf >= GESTURE_CONF

	if n.kind == Note.Kind.HOLD:
		return _evaluate_hold(n, now, delta, hand, inside)

	# TAP.
	#
	# Resolving on first contact is wrong here, and the reason is specific to
	# a game with no trigger: the hand is *always* somewhere. If it happens to
	# be resting where the next note will arrive - which is constantly true,
	# since consecutive notes are often near each other - then first contact
	# happens the instant the note becomes active, a full WINDOW early, and
	# grades as a MISS. The player is sitting exactly on the note and the game
	# says they missed it.
	#
	# So track the closest approach in time instead, and resolve at the moment
	# the grade can no longer improve: once `now` passes the note's time, every
	# further frame is worse. That still gives immediate feedback in the common
	# case, because for a hand already on target that moment IS the note's beat.
	if inside:
		var dt: float = now - n.time
		if not n._entered or absf(dt) < absf(n.timing_error):
			n._entered = true
			n.timing_error = dt
			n.hit_distance = _distance(n)
		if now >= n.time:
			n.verdict = _cap(n, _grade(absf(n.timing_error), n.hit_distance))
			note_judged.emit(n)
			return false

	if now > n.time + GOOD_TIME:
		# Touched at some point but never while on the beat: grade the best
		# approach we saw. Never touched at all: miss.
		n.verdict = _cap(n, _grade(absf(n.timing_error), n.hit_distance)) if n._entered \
			else Note.Verdict.MISS
		if not n._entered:
			n.timing_error = GOOD_TIME
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

	# Accumulate only while actually inside, and only once the hold has
	# started - a hand parked on the note early must not bank credit for time
	# before the note existed.
	if inside and now >= n.time:
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
		n.verdict = _cap(n, n.verdict)
		note_judged.emit(n)
		return false

	return true


## Apply the wrong-shape cap. Requirements are only enforced once the input
## has reported a gesture at all - see HandState.gestures_seen.
func _cap(n: Note, v: Note.Verdict) -> Note.Verdict:
	if v == Note.Verdict.MISS or not n.needs_gesture() or not HandState.gestures_seen:
		return v
	if n._gesture_ok:
		return v
	# Verdict enum ascends PENDING, PERFECT, GREAT, GOOD, MISS: worse is larger.
	return maxi(v, WRONG_GESTURE_CAP) as Note.Verdict


## How far the hand is from the note, along the one axis that is charted.
func _distance(n: Note) -> float:
	return absf(HandState.cursor(n.slot).y - n.pos.y)


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
