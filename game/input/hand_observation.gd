class_name HandObservation
extends RefCounted
## One hand, as most recently observed. Mirrors the per-hand object in
## PROTOCOL.md — see that file for authoritative field meanings.

enum State { TRACKED, COASTING, LOST }

var slot: int = 0
## Normalized, calibrated. [0,1] is the play area; x=0 screen-left, y=0 screen-top.
var pos: Vector2 = Vector2(0.5, 0.5)
## Normalized units per second.
var vel: Vector2 = Vector2.ZERO
var conf: float = 0.0
var state: State = State.LOST
## Producer-side timestamp of the frame this came from. Only ever compared to
## other t_capture values — never converted into song time.
var t_capture: float = 0.0


func _init(p_slot: int = 0) -> void:
	slot = p_slot


func is_usable() -> bool:
	return state != State.LOST and conf > 0.0


static func state_from_string(s: String) -> State:
	match s:
		"TRACKED": return State.TRACKED
		"COASTING": return State.COASTING
		_: return State.LOST
