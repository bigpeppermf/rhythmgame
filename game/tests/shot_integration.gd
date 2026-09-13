extends Node
## Render menu and both prototype modes without a camera or real-time playback.
const OUT := "/tmp/rhythm-integration-shots"

func _ready() -> void:
	HandState.source = null
	DirAccess.make_dir_recursive_absolute(OUT)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _shot("menu")
	for solo in [false, true]:
		main._show_prototype(solo)
		var play: Node = main._current
		play.set_process(false)
		Conductor.stop()
		play.chart.rewind()
		for slot in 2:
			HandState.hands[slot].pos = Vector2(Field3D.lane_x(slot), 0.4 + slot * 0.2)
			HandState.hands[slot].vel = Vector2.ZERO
			HandState.hands[slot].conf = 1.0
			HandState.hands[slot].state = HandObservation.State.TRACKED
		play.field.sync(play.chart, 10.0)
		play.score.score = 4200
		play.score.combo = 12
		play.score.multiplier = 2
		Conductor.song_time = 10.0
		Conductor.playing = true
		play._update_hud()
		Conductor.playing = false
		await _shot("solo" if solo else "two_hand")
	main.free()
	get_tree().quit()

func _shot(name: String) -> void:
	for i in 4:
		await RenderingServer.frame_post_draw
	var path := OUT.path_join(name + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("Saved ", path)
