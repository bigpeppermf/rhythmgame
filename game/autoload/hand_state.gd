extends Node
## Where the game asks "where are the player's hands?"
##
## Holds two HandObservations and a swappable source. Gameplay reads from here
## and never learns whether the numbers came from a camera or a mouse.
##
## Autoloaded as `HandState` (see project.godot).

signal source_changed(name: String)

const SLOT_LEFT := 0
const SLOT_RIGHT := 1

## Cap on how far forward we will extrapolate between samples. Past this the
## producer has stalled, and guessing further would invent motion that never
## happened.
const MAX_EXTRAPOLATION := 0.05

var hands: Array[HandObservation] = []
var source: HandSource = null

var _sample_age: Array[float] = [0.0, 0.0]


func _ready() -> void:
	hands = [HandObservation.new(SLOT_LEFT), HandObservation.new(SLOT_RIGHT)]
	use_mock()
	process_priority = -100  # read input before anything consumes it


func use_mock() -> void:
	_swap(MockHandSource.new())


func use_udp() -> void:
	_swap(UdpHandSource.new())


func _swap(next: HandSource) -> void:
	if source != null:
		source.queue_free()
	source = next
	add_child(source)
	source_changed.emit(source.source_name())


func _process(delta: float) -> void:
	if source == null:
		return

	var before: Array[float] = [hands[0].t_capture, hands[1].t_capture]
	source.poll(hands)

	# Age each sample. A source running at 60Hz feeding a 144Hz renderer leaves
	# us holding the same observation for two or three frames; without this the
	# cursor moves in visible steps.
	for slot in 2:
		if hands[slot].t_capture != before[slot]:
			_sample_age[slot] = 0.0
		else:
			_sample_age[slot] += delta


## Where to draw the cursor: the last observed position, carried forward by its
## velocity for however long we have been holding that sample.
##
## This adds no information — it is purely perceptual. But a smoothly moving
## cursor reads as far more responsive than a stepping one, and responsiveness
## is a feeling rather than a measurement.
func cursor(slot: int) -> Vector2:
	var h: HandObservation = hands[slot]
	var age: float = minf(_sample_age[slot], MAX_EXTRAPOLATION)
	return h.pos + h.vel * age


func observation(slot: int) -> HandObservation:
	return hands[slot]


func any_usable() -> bool:
	return hands[0].is_usable() or hands[1].is_usable()


func source_name() -> String:
	return source.source_name() if source != null else "none"
