class_name CameraPreview
extends Node
## Receives the optional camera self-view from the vision module.
##
## Deliberately its own socket and its own node, with no connection to
## HandState. The preview is a mirror for the player, not an input: if it is
## slow, lossy or entirely absent, nothing about gameplay changes. Keeping the
## two apart is what guarantees that.
##
## Wire format: one datagram, raw JPEG bytes, no header. Newest wins - there is
## nothing to reassemble and nothing to acknowledge. See vision/preview.py.

signal frame_received

## Must match vision/preview.py DEFAULT_PORT.
const PORT := 5006
## No frame for this long and we treat the preview as gone.
const TIMEOUT := 1.0

var texture: ImageTexture = null
var connected: bool = false
var frames: int = 0
var fps: float = 0.0

var _udp := PacketPeerUDP.new()
var _image := Image.new()
var _last_rx := 0.0
var _count := 0
var _window := 0.0
var _decode_failures := 0


func _ready() -> void:
	var err: int = _udp.bind(PORT, "127.0.0.1")
	if err != OK:
		# Not fatal. A missing preview is a missing convenience.
		push_warning("CameraPreview: could not bind port %d (err %d); preview disabled"
			% [PORT, err])
		set_process(false)


func _exit_tree() -> void:
	_udp.close()


func _process(delta: float) -> void:
	var now: float = Time.get_ticks_usec() / 1_000_000.0
	var newest := PackedByteArray()

	# Drain and keep only the last. Decoding every queued frame would spend
	# time drawing images the player will never see.
	while _udp.get_available_packet_count() > 0:
		newest = _udp.get_packet()

	_window += delta
	if _window >= 0.5:
		fps = _count / _window
		_count = 0
		_window = 0.0

	if newest.is_empty():
		if connected and now - _last_rx > TIMEOUT:
			connected = false
		return

	if _image.load_jpg_from_buffer(newest) != OK:
		_decode_failures += 1
		return

	if texture == null:
		texture = ImageTexture.create_from_image(_image)
	else:
		# update() reuses the GPU texture; set_image() would reallocate it
		# every frame.
		# ImageTexture reports Vector2, Image reports Vector2i, so compare the
		# dimensions rather than the vectors.
		if texture.get_width() != _image.get_width() \
				or texture.get_height() != _image.get_height():
			texture.set_image(_image)
		else:
			texture.update(_image)

	connected = true
	_last_rx = now
	frames += 1
	_count += 1
	frame_received.emit()


func status() -> String:
	if not connected:
		return "camera: waiting on :%d" % PORT
	return "camera: %.0f fps" % fps
