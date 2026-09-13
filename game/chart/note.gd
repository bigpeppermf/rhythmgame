class_name Note
extends RefCounted
## One note. Authored in beats, resolved to seconds at load.

enum Kind { TAP, HOLD }
enum Verdict { PENDING, PERFECT, GREAT, GOOD, MISS }

## When it should be hit, in seconds from the start of the song.
var time: float = 0.0
## Where, in normalized play space. Same coordinates the hands arrive in.
var pos: Vector2 = Vector2(0.5, 0.5)
## Which hand must hit it. 0 = left, 1 = right.
var slot: int = 0
var kind: Kind = Kind.TAP
## HOLD only: how long the hand must stay inside, in seconds.
var length: float = 0.0
## Hand shape the note asks for: one of GESTURES, or empty for any. Taps check
## the gesture at their closest approach; holds earn progress only while the
## required gesture is held.
var gesture: StringName = &""

const GESTURES: Array[StringName] = [&"OPEN_PALM", &"FIST", &"THUMBS_UP", &"PINCH"]

# ── Runtime judging state. Reset by Chart.rewind(). ──────────────────────────
var verdict: Verdict = Verdict.PENDING
## Seconds of a HOLD actually held. Ratio to `length` is the note's score.
var held: float = 0.0
## Signed timing error at the moment of the hit. Negative = early.
var timing_error: float = 0.0
## Distance from note centre when hit. Lower is better.
var hit_distance: float = 0.0
var _entered: bool = false
## Runtime: the required gesture matched at the judged tap observation, or the
## hold accumulated valid gesture progress.
var _gesture_ok: bool = false


func end_time() -> float:
	return time + length


func is_resolved() -> bool:
	return verdict != Verdict.PENDING


func reset() -> void:
	verdict = Verdict.PENDING
	held = 0.0
	timing_error = 0.0
	hit_distance = 0.0
	_entered = false
	_gesture_ok = false


func needs_gesture() -> bool:
	return gesture != &""


static func gesture_from_string(s: String) -> StringName:
	var g := StringName(s.to_upper())
	return g if g in GESTURES else &""


static func kind_from_string(s: String) -> Kind:
	return Kind.HOLD if s == "hold" else Kind.TAP


static func verdict_name(v: Verdict) -> String:
	match v:
		Verdict.PERFECT: return "PERFECT"
		Verdict.GREAT: return "GREAT"
		Verdict.GOOD: return "GOOD"
		Verdict.MISS: return "MISS"
		_: return "-"
