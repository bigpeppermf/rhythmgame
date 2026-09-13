extends Node
## Scene flow. Owns nothing but the transitions.
##
##   menu -> play -> results -> menu
##        -> play (solo) -> results -> menu
##        -> calibrate -> menu

const MENU := "res://scenes/menu.tscn"
const PLAY := "res://scenes/play_3d.tscn"
## One hand, one centred lane - see charts/README.md for how to chart it.
const SOLO_CHART := "res://charts/solo.json"
const CALIBRATE := "res://scenes/calibrate.tscn"
const RESULTS := "res://scenes/results.tscn"

var _current: Node


func _ready() -> void:
	_show_menu()


## `configure` runs on the instance before it enters the tree - `_ready` fires
## synchronously inside `add_child`, so any export that affects _ready (chart
## path, solo mode, skin) MUST be set here, not on the node `_swap` returns.
func _swap(path: String, configure: Callable = Callable()) -> Node:
	if _current != null:
		_current.queue_free()
		# Free immediately rather than at end of frame, so the outgoing scene
		# cannot handle input meant for the incoming one.
		remove_child(_current)
	Conductor.stop()
	_current = load(path).instantiate()
	if configure.is_valid():
		configure.call(_current)
	add_child(_current)
	return _current


func _show_menu() -> void:
	var m := _swap(MENU)
	m.play_pressed.connect(_show_play)
	m.play_solo_pressed.connect(_show_play_solo)
	m.calibrate_pressed.connect(_show_calibrate)


func _show_play() -> void:
	var p := _swap(PLAY, func(n): n.skin_path = Settings.skin_path)
	p.song_finished.connect(_show_results)
	p.quit_to_menu.connect(_show_menu)


func _show_play_solo() -> void:
	var p := _swap(PLAY, func(n):
		n.skin_path = Settings.skin_path
		n.solo_mode = true
		n.chart_path = SOLO_CHART)
	p.song_finished.connect(_show_results)
	p.quit_to_menu.connect(_show_menu)


func _show_calibrate() -> void:
	_swap(CALIBRATE).finished.connect(_show_menu)


func _show_results(score: ScoreState, chart: Chart) -> void:
	var r := _swap(RESULTS)
	r.setup(score, chart)
	r.finished.connect(_show_menu)
