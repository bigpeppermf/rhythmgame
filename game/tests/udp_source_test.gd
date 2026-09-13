extends Node
## Cross-process integration test for the wire protocol boundary. Run:
##   godot --headless res://tests/udp_source_test.tscn
##
## Everything else in tests/ drives the game side with synthetic data. This is
## the one place that exercises the real thing: it launches the actual
## tools/mock_sender.py as a subprocess and receives its packets over a real
## loopback UDP socket through the real UdpHandSource, so a change on either
## side of PROTOCOL.md that breaks the other shows up here.

var _sender_pid: int = -1
var failures: int = 0


func _ready() -> void:
	var script := ProjectSettings.globalize_path("res://../tools/mock_sender.py")
	_sender_pid = OS.create_process("python3",
		[script, "--pattern", "static", "--fps", "60"])
	_check(_sender_pid > 0, "mock_sender.py launched (pid %d)" % _sender_pid)

	HandState.use_udp()
	await get_tree().create_timer(2.0).timeout
	_run_checks()

	if _sender_pid > 0:
		OS.kill(_sender_pid)
	_finish()


func _run_checks() -> void:
	var src := HandState.source as UdpHandSource
	_check(src != null, "HandState.source is a UdpHandSource")
	if src == null:
		return

	_check(src.connected, "UdpHandSource reports connected after real packets arrive")
	_check(src.last_seq > 0, "sequence numbers are advancing, got %d" % src.last_seq)

	var h0 := HandState.hands[0]
	var h1 := HandState.hands[1]
	_check(h0.state == HandObservation.State.TRACKED, "slot 0 parsed as TRACKED")
	_check(h1.state == HandObservation.State.TRACKED, "slot 1 parsed as TRACKED")

	# mock_sender.py --pattern static holds (0.3, 0.5) and (0.7, 0.5).
	_check(h0.pos.distance_to(Vector2(0.3, 0.5)) < 0.01,
		"slot 0 position matches the static pattern, got %s" % h0.pos)
	_check(h1.pos.distance_to(Vector2(0.7, 0.5)) < 0.01,
		"slot 1 position matches the static pattern, got %s" % h1.pos)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("\n%s (%d failure%s)" % [
		"ALL PASS" if failures == 0 else "FAILURES", failures,
		"" if failures == 1 else "s"])
	get_tree().quit(1 if failures > 0 else 0)
