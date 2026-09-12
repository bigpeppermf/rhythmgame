extends Node
## Starts on the mouse mock; real packets should flip it to UDP by themselves.
var _t := 0.0
func _ready() -> void:
	print("start: ", HandState.source_name())
func _process(delta: float) -> void:
	_t += delta
	if _t > 3.0:
		var ok := HandState.source is UdpHandSource and HandState.hands[0].conf > 0.5
		print("after 3s: %s   hand0 conf %.2f" % [HandState.source_name(), HandState.hands[0].conf])
		print("AUTOSWITCH " + ("OK" if ok else "FAILED"))
		get_tree().quit(0 if ok else 1)
