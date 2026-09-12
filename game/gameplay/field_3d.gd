class_name Field3D
extends RefCounted
## Maps normalized play space to the 3D highway.
##
## This is the *only* place that knows the game is rendered in perspective.
## The Judge, the Chart and HandState all work in normalized [0,1] and never
## learn what the renderer does with it - which is why the flat 2D playfield
## and this one can judge identically.

## World size of the play area at the hit plane.
const WIDTH := 8.6

## Half-width of the empty band down the centre, in normalized x. Each hand
## gets its own track and the middle is left clear, so the two read as separate
## even when the hands cross.
##
## Note that this changes *nothing* about the coordinate mapping: plane() stays
## a plain linear map and the gap is purely a region where no lane is drawn.
## Warping x to open the gap would have made judged distance and on-screen
## distance disagree near the centre, which is a bug waiting to happen.
const GAP := 0.11
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


## Normalized x bounds of one hand's track. slot 0 is left, 1 is right.
static func track(slot: int) -> Vector2:
	return Vector2(0.0, 0.5 - GAP) if slot == 0 else Vector2(0.5 + GAP, 1.0)


## True if x falls in the empty centre band, where nothing should be charted.
static func in_gap(x: float) -> bool:
	return absf(x - 0.5) < GAP
