extends Node
## Where the game asks "where are the player's hands?"
##
## Holds two HandObservations and a swappable source. Gameplay reads from here
## and never learns whether the numbers came from a camera or a mouse.
##
## The UDP source is always bound, even while the mouse mock is driving. The
## moment real packets arrive it takes over, so starting the tracker is the
## whole setup - nobody has to remember a key. Pressing U still switches by
## hand, and doing so turns the automatic switch off for the session.
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
## Switch to the camera automatically when its packets appear.
var auto_switch: bool = true

var _udp: UdpHandSource
var _mock: MockHandSource
var _probe: Array[HandObservation] = []
var _sample_age: Array[float] = [0.0, 0.0]


func _ready() -> void:
	hands = [HandObservation.new(SLOT_LEFT), HandObservation.new(SLOT_RIGHT)]
	_probe = [HandObservation.new(SLOT_LEFT), HandObservation.new(SLOT_RIGHT)]
	_udp = UdpHandSource.new()
	add_child(_udp)
	_mock = MockHandSource.new()
	add_child(_mock)
	_activate(_mock)
	process_priority = -100  # read input before anything consumes it


func use_mock() -> void:
	auto_switch = false
	_activate(_mock)


func use_udp() -> void:
	auto_switch = false
	_activate(_udp)


func _activate(next: HandSource) -> void:
	if source == next:
		return
	source = next
	source_changed.emit(source.source_name())


func _process(delta: float) -> void:
	if source == null:
		return

	# Keep draining the socket even when the mock is driving, so packets never
	# back up and so we notice the moment a tracker starts talking.
	if source != _udp and auto_switch:
		_udp.poll(_probe)
		if _udp.connected:
			_activate(_udp)

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
## This adds no information - it is purely perceptual. But a smoothly moving
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
	if source == null:
		return "none"
	var n := source.source_name()
	if source == _mock and auto_switch:
		n += "  (camera auto-detect on :%d)" % UdpHandSource.PORT
	return n
