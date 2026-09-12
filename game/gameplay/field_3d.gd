class_name Field3D
extends RefCounted
## Maps normalized play space to the 3D highway.
##
## This is the *only* place that knows the game is rendered in perspective.
## The Judge, the Chart and HandState all work in normalized [0,1] and never
## learn what the renderer does with it - which is why the flat 2D playfield
## and this one can judge identically.

## World size of the play area at the hit plane.
const WIDTH := 8.0
const HEIGHT := 4.8
## World units the highway travels per second. Raising this makes notes arrive
## faster at the same chart - it is a readability knob, not a difficulty one.
const SCROLL := 8.5
## Seconds of chart visible ahead. Sets how long the highway looks.
const LOOKAHEAD := 2.0


## Normalized position -> world position at the hit plane.
## y=0 is the TOP of the play area (see PROTOCOL.md), so it inverts here.
static func plane(p: Vector2) -> Vector3:
	return Vector3((p.x - 0.5) * WIDTH, (0.5 - p.y) * HEIGHT, 0.0)


## Where a note sits right now. Purely a function of song time - never
## integrated from velocity, so a dropped frame cannot desync the chart.
static func note_position(note_time: float, now: float, p: Vector2) -> Vector3:
	var v := plane(p)
	v.z = -(note_time - now) * SCROLL
	return v


static func depth() -> float:
	return LOOKAHEAD * SCROLL
