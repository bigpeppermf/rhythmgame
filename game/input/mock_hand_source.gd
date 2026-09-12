class_name MockHandSource
extends HandSource
## Mouse-driven stand-in for the camera.
##
## This is what lets the gameplay half of the project get built in parallel
## with the vision half. It emits the exact same observations a real tracker
## would, including velocity, so code written against it needs no changes when
## the camera arrives.
##
##   mouse   moves the active hand
##   TAB     switch which hand the mouse drives
##   M       toggle mirror mode (both hands from one mouse)
##   L       hold to simulate losing tracking

var mirror: bool = true
var active_slot: int = 0

var _prev_pos: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.5, 0.5)]
var _seeded: bool = false


func source_name() -> String:
	return "mock (mouse)%s" % (" mirrored" if mirror else "")


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_TAB: active_slot = 1 - active_slot
		KEY_M: mirror = not mirror


func poll(hands: Array) -> void:
	var vp: Viewport = get_viewport()
	if vp == null:
		return

	var rect: Vector2 = vp.get_visible_rect().size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return

	var m: Vector2 = vp.get_mouse_position() / rect
	var dt: float = get_process_delta_time()
	var lost: bool = Input.is_key_pressed(KEY_L)
	var now: float = Time.get_ticks_usec() / 1_000_000.0

	for slot in 2:
		var h: HandObservation = hands[slot]
		var target: Vector2 = h.pos

		if mirror:
			target = m if slot == 0 else Vector2(1.0 - m.x, m.y)
		elif slot == active_slot:
			target = m

		if not _seeded:
			_prev_pos[slot] = target

		h.pos = target
		h.vel = (target - _prev_pos[slot]) / maxf(dt, 0.0001)
		h.conf = 0.0 if lost else 1.0
		h.state = HandObservation.State.LOST if lost else HandObservation.State.TRACKED
		h.t_capture = now
		_prev_pos[slot] = target

	_seeded = true
