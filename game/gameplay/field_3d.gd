class_name Field3D
extends RefCounted
## Maps normalized play space onto the two angled panels.
##
## This is the *only* place that knows the game is rendered in perspective.
## The Judge, the Chart and HandState all work in normalized [0,1] and never
## learn what the renderer does with it - which is why the flat 2D playfield
## and this one judge identically.
##
## Each hand plays a flat vertical panel. The panels splay outward: the hit
## edge is the OUTER vertical edge, nearest the player, and each panel runs
## back and inward toward the centre. Notes slide down their panel from the
## far inner edge to the near outer edge, where the hand meets them.
##
##        far edge                      far edge
##            \                          /
##             \                        /
##              \____                __/
##   hit edge -> |    (player is here)   | <- hit edge

## World height of a panel. Tall, because height is the only charted axis.
const HEIGHT := 7.2
## World x of the near (hit) edge - the outer edge of each panel.
const OUTER_X := 4.0
## World x of the far edge. Smaller than OUTER_X, so the panels angle inward
## as they recede.
const INNER_X := 1.5

## World units travelled per second along the panel. A readability knob, not a
## difficulty one - it changes how far apart notes look, not how hard they are.
const SCROLL := 6.5
## Seconds of chart visible ahead. Sets how long each panel looks.
const LOOKAHEAD := 2.0

## Normalized width of one lane. One lane, undivided: height is the axis the
## player plays on, and the note nearly fills the lane because with a single
## lane the note IS the position.
const TRACK_W := 0.21
## Normalized x each panel is centred on. Index is the slot: 0 = left, 1 = right.
const TRACK_X := [0.29, 0.71]
## World scale applied to horizontal drift off the lane, so a hand that strays
## visibly slides off its panel instead of silently failing to score.
const DRIFT := 9.0


static func side(slot: int) -> float:
	return -1.0 if slot == 0 else 1.0


static func depth() -> float:
	return LOOKAHEAD * SCROLL


## Centre of the hit edge: where notes arrive and the hand waits.
static func hit_edge(slot: int) -> Vector3:
	return Vector3(side(slot) * OUTER_X, 0.0, 0.0)


## Centre of the far edge, where notes appear.
static func far_edge(slot: int) -> Vector3:
	return Vector3(side(slot) * INNER_X, 0.0, -depth())


## Movement per second along the panel, pointing away from the player.
static func travel(slot: int) -> Vector3:
	return (far_edge(slot) - hit_edge(slot)) / LOOKAHEAD


## A point on the panel: `dt` seconds from its hit moment, at normalized
## height `y`, drifted by `dx` normalized units off the lane centre.
##
## Purely a function of time - never integrated from velocity, so a dropped
## frame cannot desync the chart.
static func at(slot: int, dt: float, y: float, dx: float = 0.0) -> Vector3:
	var v := hit_edge(slot) + travel(slot) * dt
	v.y += (0.5 - y) * HEIGHT          # y=0 is the TOP (see PROTOCOL.md)
	v.x += dx * DRIFT
	return v


static func note_position(note_time: float, now: float, slot: int, p: Vector2) -> Vector3:
	return at(slot, note_time - now, p.y, p.x - TRACK_X[slot])


## Where a hand's cursor sits: on the hit edge, at the hand's height. The
## hand's x is ignored - it is not judged, so drawing it would show a drift
## that costs the player nothing and looks like it should.
static func cursor_position(slot: int, p: Vector2) -> Vector3:
	return at(slot, 0.0, p.y, 0.0)


## Orientation for anything drawn on a panel. In this basis -Z runs away down
## the panel and +Y is up, so a view can draw a dash simply by being long in Z.
static func panel_basis(slot: int) -> Basis:
	return Basis.looking_at(travel(slot), Vector3.UP)


## The panel's four corners, near pair first.
static func corners(slot: int) -> PackedVector3Array:
	var hh := HEIGHT * 0.5
	var n := hit_edge(slot)
	var f := far_edge(slot)
	return PackedVector3Array([
		n + Vector3(0, hh, 0), n - Vector3(0, hh, 0),
		f + Vector3(0, hh, 0), f - Vector3(0, hh, 0),
	])


## Normalized x bounds of one hand's lane.
static func track(slot: int) -> Vector2:
	var c: float = TRACK_X[slot]
	return Vector2(c - TRACK_W * 0.5, c + TRACK_W * 0.5)


## Normalized x every note for this hand should sit on. With one lane, the
## charted axis is height; x is just which panel you are on.
static func lane_x(slot: int) -> float:
	return TRACK_X[slot]


static func on_track(slot: int, x: float) -> bool:
	var t := track(slot)
	return x >= t.x - 0.001 and x <= t.y + 0.001
