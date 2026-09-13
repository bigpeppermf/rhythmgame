extends Node
## Scene flow. Owns nothing but the transitions.
##
##   menu -> play -> results -> menu
##        -> play (solo) -> results -> menu
##        -> calibrate -> menu

const MENU := "res://scenes/menu.tscn"
const PLAY := "res://scenes/play_3d.tscn"
## One hand, one centred lane - where GH-converted charts get prototyped
## before the real charting tool exists. See tools/gh_chart_convert.py.
const SOLO_CHART := "res://charts/solo.json"
const CALIBRATE := "res://scenes/calibrate.tscn"
const RESULTS := "res://scenes/results.tscn"

var _current: Node


func _ready() -> void:
	_show_menu()


func _swap(path: String) -> Node:
	if _current != null:
		_current.queue_free()
		# Free immediately rather than at end of frame, so the outgoing scene
		# cannot handle input meant for the incoming one.
		remove_child(_current)
	Conductor.stop()
	_current = load(path).instantiate()
	add_child(_current)
	return _current


func _show_menu() -> void:
	var m := _swap(MENU)
	m.play_pressed.connect(_show_play)
	m.play_solo_pressed.connect(_show_play_solo)
	m.calibrate_pressed.connect(_show_calibrate)


func _show_play() -> void:
	var p := _swap(PLAY)
	p.skin_path = Settings.skin_path
	p.song_finished.connect(_show_results)
	p.quit_to_menu.connect(_show_menu)


func _show_play_solo() -> void:
	var p := _swap(PLAY)
	p.skin_path = Settings.skin_path
	p.solo_mode = true
	p.chart_path = SOLO_CHART
	p.song_finished.connect(_show_results)
	p.quit_to_menu.connect(_show_menu)


func _show_calibrate() -> void:
	_swap(CALIBRATE).finished.connect(_show_menu)


func _show_results(score: ScoreState, chart: Chart) -> void:
	var r := _swap(RESULTS)
	r.setup(score, chart)
	r.finished.connect(_show_menu)
