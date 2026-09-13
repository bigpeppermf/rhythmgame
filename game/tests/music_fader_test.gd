extends Node
## Headless test for MusicFader + Conductor's volume ease. Run:
##   godot --headless res://tests/music_fader_test.tscn

var failures: int = 0


func _ready() -> void:
	_run_step_and_floor()
	_run_hit_recovers()
	_run_ease_is_gradual()
	_finish()


func _miss() -> Note:
	var n := Note.new()
	n.verdict = Note.Verdict.MISS
	return n


func _hit() -> Note:
	var n := Note.new()
	n.verdict = Note.Verdict.PERFECT
	return n


## Each miss ducks another STEP_DB, down to FLOOR_DB and no further.
func _run_step_and_floor() -> void:
	var fader := MusicFader.new()
	fader.reset()
	_check(Conductor.volume_db == 0.0, "starts at 0 dB")

	fader.on_judged(_miss())
	_check(is_equal_approx(Conductor.volume_db, MusicFader.STEP_DB),
		"one miss ducks to %.0f dB, got %.1f" % [MusicFader.STEP_DB, Conductor.volume_db])

	for i in 10:
		fader.on_judged(_miss())
	_check(is_equal_approx(Conductor.volume_db, MusicFader.FLOOR_DB),
		"a long miss streak never passes the floor, got %.1f" % Conductor.volume_db)


## A single hit clears the streak and restores full volume immediately.
func _run_hit_recovers() -> void:
	var fader := MusicFader.new()
	fader.reset()
	fader.on_judged(_miss())
	fader.on_judged(_miss())
	fader.on_judged(_hit())
	_check(fader.miss_streak == 0, "a hit clears the miss streak")
	_check(Conductor.volume_db == 0.0, "a hit restores the target to 0 dB")


## The target changes in a step, but Conductor eases the audible volume toward
## it over time rather than snapping - a real fade, not a click.
func _run_ease_is_gradual() -> void:
	var fader := MusicFader.new()
	fader.reset()
	fader.on_judged(_miss())
	_check(Conductor.volume_db == MusicFader.STEP_DB, "target ducks immediately")

	Conductor._ease_volume(1.0 / 60.0)
	var after_one_frame: float = Conductor._current_volume_db
	_check(after_one_frame < 0.0 and after_one_frame > MusicFader.STEP_DB,
		"one frame in, volume has moved but not arrived (%.2f dB)" % after_one_frame)

	for i in 300:
		Conductor._ease_volume(1.0 / 60.0)
	_check(is_equal_approx(Conductor._current_volume_db, MusicFader.STEP_DB),
		"given enough time, volume converges on the target (%.2f dB)" %
		Conductor._current_volume_db)


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("\n%s (%d failure%s)" % [
		"ALL PASS" if failures == 0 else "FAILURES", failures,
		"" if failures == 1 else "s"])
	get_tree().quit(1 if failures > 0 else 0)
