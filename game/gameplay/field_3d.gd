class_name Field3D
extends RefCounted
## Maps normalized play space to the 3D highway.
##
## This is the *only* place that knows the game is rendered in perspective.
## The Judge, the Chart and HandState all work in normalized [0,1] and never
## learn what the renderer does with it - which is why the flat 2D playfield
## and this one judge identically.

## World span of the full normalized x range.
const WIDTH := 9.0
## Tall, because each track is a vertical ribbon rather than a floor.
const HEIGHT := 7.2

## World units the track travels per second. Raising this makes notes arrive
## faster at the same chart - a readability knob, not a difficulty one.
const SCROLL := 8.5
## Seconds of chart visible ahead. Sets how long the track looks.
const LOOKAHEAD := 2.0

## Normalized width of one track. One lane, undivided: height is the axis the
## player plays on, so subdividing horizontally would only add noise.
##
## Sized so a note nearly fills the lane with a little margin - which is the
## point of a single lane. The note IS the lane position.
const TRACK_W := 0.21
## Normalized centre of each track. Index is the slot: 0 = left, 1 = right.
const TRACK_X := [0.29, 0.71]


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


## Normalized x bounds of one hand's track.
static func track(slot: int) -> Vector2:
	var c: float = TRACK_X[slot]
	return Vector2(c - TRACK_W * 0.5, c + TRACK_W * 0.5)


## Normalized x every note for this hand should sit on. With one lane, the
## charted axis is height; x is just which track you are on.
static func lane_x(slot: int) -> float:
	return TRACK_X[slot]


static func on_track(slot: int, x: float) -> bool:
	var t := track(slot)
	return x >= t.x - 0.001 and x <= t.y + 0.001
