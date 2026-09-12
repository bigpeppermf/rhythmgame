extends Node
## Renders the editor with the test chart loaded, scrolled to the busy bars.
const OUT := "user://shots"

func _ready() -> void:
	HandState.source = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var ed: Control = load("res://scenes/editor.tscn").instantiate()
	add_child(ed)
	await get_tree().process_frame
	ed.scroll_beat = 22.0
	ed.px_per_beat = 60.0
	ed.seek_beat(30.0)
	ed.selected = ed.chart.notes[20]
	for _w in 4:
		await RenderingServer.frame_post_draw
	var p := "%s/editor.png" % OUT
	get_viewport().get_texture().get_image().save_png(p)
	print("wrote ", ProjectSettings.globalize_path(p))
	get_tree().quit()
