extends Node
## Renders the menu and a populated results screen.
const OUT := "user://shots"

func _ready() -> void:
	HandState.source = null
	await _shot(load("res://scenes/menu.tscn").instantiate(), "menu")
	var r: Node = load("res://scenes/results.tscn").instantiate()
	r.setup(_fake_score(), _fake_chart())
	await _shot(r, "results")
	get_tree().quit()

func _shot(n: Node, name: String) -> void:
	add_child(n)
	for _w in 4:
		await RenderingServer.frame_post_draw
	var p := "%s/%s.png" % [OUT, name]
	get_viewport().get_texture().get_image().save_png(p)
	print("wrote ", ProjectSettings.globalize_path(p))
	n.queue_free()
	remove_child(n)

## A plausible run: mostly on time, a slight late bias, a few drops.
func _fake_chart() -> Chart:
	var c := Chart.new()
	var errs := [0.01, -0.02, 0.03, 0.05, 0.02, -0.01, 0.04, 0.08, 0.02, 0.03,
		-0.03, 0.01, 0.06, 0.02, 0.11, 0.04, -0.01, 0.03, 0.07, 0.02, 0.05, 0.0]
	for e in errs:
		var n := Note.new()
		n.timing_error = e
		n.verdict = Note.Verdict.PERFECT if absf(e) <= 0.05 \
			else (Note.Verdict.GREAT if absf(e) <= 0.10 else Note.Verdict.GOOD)
		c.notes.append(n)
	for i in 3:
		var m := Note.new()
		m.verdict = Note.Verdict.MISS
		c.notes.append(m)
	return c

func _fake_score() -> ScoreState:
	var s := ScoreState.new()
	for n in _fake_chart().notes:
		s.apply(n)
	return s
