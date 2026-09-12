class_name UdpHandSource
extends HandSource
## Receives hand observations from the Python vision module.
##
## See PROTOCOL.md for the packet format. The one rule that matters here:
## drain the whole queue every frame and keep only the newest packet. A
## backlog means we are rendering the past, and a stale frame is always
## better than a late one.

## Must match vision/udp_protocol.py DEFAULT_PORT.
const PORT := 5005
const PROTOCOL_VERSION := 1
## No packet for this long and we consider the producer gone.
const TIMEOUT := 0.5

var connected: bool = false
var last_seq: int = -1
var dropped: int = 0
var packets_per_sec: float = 0.0

var _udp := PacketPeerUDP.new()
var _last_rx: float = 0.0
var _rx_count: int = 0
var _rx_window: float = 0.0
var _bad_version_warned: bool = false


func source_name() -> String:
	return "udp:%d %s" % [PORT, "live" if connected else "waiting"]


func _ready() -> void:
	var err: int = _udp.bind(PORT, "127.0.0.1")
	if err != OK:
		push_error("UdpHandSource: could not bind port %d (err %d)" % [PORT, err])


func _exit_tree() -> void:
	_udp.close()


func poll(hands: Array) -> void:
	var now: float = Time.get_ticks_usec() / 1_000_000.0
	var newest: Dictionary = {}

	# Drain. We deliberately overwrite rather than process each packet: only
	# the last one describes where the hands are *now*.
	while _udp.get_available_packet_count() > 0:
		var raw: PackedByteArray = _udp.get_packet()
		var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
		if parsed is Dictionary:
			newest = parsed
			_rx_count += 1

	_track_rate(now)

	if newest.is_empty():
		if connected and now - _last_rx > TIMEOUT:
			connected = false
			_mark_all_lost(hands)
		return

	# A packet with no "v" is v1 by definition - that is the version that
	# predates the field. Rejecting it would mean the game silently ignores a
	# sender that is, in every other respect, speaking the protocol correctly.
	if int(newest.get("v", PROTOCOL_VERSION)) != PROTOCOL_VERSION:
		if not _bad_version_warned:
			push_error("UdpHandSource: protocol v%s, expected v%d" %
				[newest.get("v", "?"), PROTOCOL_VERSION])
			_bad_version_warned = true
		return

	var seq: int = int(newest.get("seq", 0))
	if last_seq >= 0 and seq > last_seq + 1:
		dropped += seq - last_seq - 1
	last_seq = seq

	connected = true
	_last_rx = now
	_apply(newest.get("hands", []), hands)


func _apply(incoming: Array, hands: Array) -> void:
	for entry in incoming:
		if not (entry is Dictionary):
			continue
		var slot: int = int(entry.get("slot", -1))
		if slot < 0 or slot >= hands.size():
			continue
		var h: HandObservation = hands[slot]
		h.pos = Vector2(float(entry.get("x", 0.5)), float(entry.get("y", 0.5)))
		h.vel = Vector2(float(entry.get("vx", 0.0)), float(entry.get("vy", 0.0)))
		h.conf = float(entry.get("conf", 0.0))
		h.state = HandObservation.state_from_string(str(entry.get("state", "LOST")))
		h.t_capture = float(entry.get("t_capture", 0.0))


func _mark_all_lost(hands: Array) -> void:
	for h in hands:
		h.conf = 0.0
		h.state = HandObservation.State.LOST
		h.vel = Vector2.ZERO


func _track_rate(now: float) -> void:
	_rx_window += get_process_delta_time()
	if _rx_window >= 0.5:
		packets_per_sec = _rx_count / _rx_window
		_rx_count = 0
		_rx_window = 0.0
