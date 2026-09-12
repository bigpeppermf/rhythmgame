extends Node
## Renders the 3D playfield at a few points in the chart and writes PNGs.
## Not a test - a way to see the scene without watching it.
##
## Hands are driven from _process at a priority between HandState (-100) and
## the field (0), so the positions the Judge sees are the ones intended for
## that frame. Driving them from the capture coroutine instead put them a
## frame behind and the synthetic player missed almost everything.
const OUT := "user://shots"
const AT := [27.0, 35.5, 43.0]   # fists on the bar, thumbs-up holds, pinches

## Override the skin, to prove a swap needs no gameplay changes.
static var skin_override := ""

var field: Node


func _ready() -> void:
	process_priority = -50
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	field = load("res://scenes/play_3d.tscn").instantiate()
	field.chart_path = "res://charts/simple.json"
	if not skin_override.is_empty():
		field.skin_path = skin_override
	add_child(field)
	HandState.source = null
	await get_tree().process_frame
	field._start()

	for i in AT.size():
		while Conductor.song_time < AT[i]:
			await get_tree().process_frame
		for _w in 3:
			await RenderingServer.frame_post_draw
		var path := "%s/%s%d.png" % [OUT, "alt_" if not skin_override.is_empty() else "play_", i]
		get_viewport().get_texture().get_image().save_png(path)
		print("wrote %s   score=%d miss=%d" % [
			ProjectSettings.globalize_path(path), field.score.score,
			field.score.counts[Note.Verdict.MISS]])
	get_tree().quit()


func _process(_delta: float) -> void:
	if field == null or field.chart == null or not Conductor.playing:
		return
	var now: float = Conductor.judge_time()
	for slot in 2:
		var best: Note = null
		var best_d := 1e9
		for n in field.chart.notes:
			if n.slot != slot or n.is_resolved():
				continue
			if n.time - 0.25 > now or now > n.end_time() + 0.10:
				continue
			var d: float = absf(n.time - now)
			if d < best_d:
				best_d = d
				best = n
		if best != null:
			HandState.hands[slot].pos = best.pos
		HandState.hands[slot].conf = 1.0
		HandState.hands[slot].state = HandObservation.State.TRACKED
