extends Node
## Verifies the game receives what the real vision encoder produces.
## Start tools/vision_bridge_check.py first, then run this.

var _t := 0.0
var _seen := 0
var _moved := false
var _first := Vector2.ZERO
var _preview: CameraPreview


func _ready() -> void:
	HandState.use_udp()
	_preview = CameraPreview.new()
	add_child(_preview)
	print("hands on :%d   preview on :%d" % [UdpHandSource.PORT, CameraPreview.PORT])


func _process(delta: float) -> void:
	_t += delta
	var src: UdpHandSource = HandState.source
	if src.connected:
		if _seen == 0:
			_first = HandState.hands[0].pos
		_seen += 1
		if HandState.hands[0].pos.distance_to(_first) > 0.05:
			_moved = true
	if _t > 4.0:
		# The preview is optional by design, so it is reported but never
		# allowed to fail the bridge.
		var ok := src.connected and _seen > 60 and _moved
		print("connected=%s  frames=%d  seq=%d  dropped=%d  pps=%.0f" %
			[src.connected, _seen, src.last_seq, src.dropped, src.packets_per_sec])
		print("hand0 pos=%s conf=%.2f state=%d" %
			[HandState.hands[0].pos, HandState.hands[0].conf, HandState.hands[0].state])
		print("hand1 pos=%s conf=%.2f" % [HandState.hands[1].pos, HandState.hands[1].conf])
		print("moving=%s" % _moved)
		print("preview: connected=%s frames=%d fps=%.0f size=%s" % [
			_preview.connected, _preview.frames, _preview.fps,
			_preview.texture.get_size() if _preview.texture != null else "none"])
		print("\n%s" % ("BRIDGE OK" if ok else "BRIDGE FAILED"))
		get_tree().quit(0 if ok else 1)
