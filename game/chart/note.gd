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

# ── Runtime judging state. Reset by Chart.rewind(). ──────────────────────────
var verdict: Verdict = Verdict.PENDING
## Seconds of a HOLD actually held. Ratio to `length` is the note's score.
var held: float = 0.0
## Signed timing error at the moment of the hit. Negative = early.
var timing_error: float = 0.0
## Distance from note centre when hit. Lower is better.
var hit_distance: float = 0.0
var _entered: bool = false


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


static func kind_from_string(s: String) -> Kind:
	return Kind.HOLD if s == "hold" else Kind.TAP


static func verdict_name(v: Verdict) -> String:
	match v:
		Verdict.PERFECT: return "PERFECT"
		Verdict.GREAT: return "GREAT"
		Verdict.GOOD: return "GOOD"
		Verdict.MISS: return "MISS"
		_: return "-"
