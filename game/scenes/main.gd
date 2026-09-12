extends Node
## Scene flow. Owns nothing but the transitions.
##
##   menu -> play -> results -> menu
##        -> calibrate -> menu
##        -> editor -> play (playtest) -> results -> editor

const MENU := "res://scenes/menu.tscn"
const PLAY := "res://scenes/play_3d.tscn"
const CALIBRATE := "res://scenes/calibrate.tscn"
const RESULTS := "res://scenes/results.tscn"
const EDITOR := "res://scenes/editor.tscn"

var _current: Node
## The chart a playtest was launched with. Non-null means results should hand
## control back to the editor rather than the menu.
var _playtest_chart: Chart = null


func _ready() -> void:
	_show_menu()


## Instantiate but do not mount, so the caller can configure exports that
## _ready reads. Call _mount when done.
func _swap(path: String) -> Node:
	if _current != null:
		_current.queue_free()
		# Free immediately rather than at end of frame, so the outgoing scene
		# cannot handle input meant for the incoming one.
		remove_child(_current)
	Conductor.stop()
	_current = load(path).instantiate()
	return _current


func _mount(n: Node) -> void:
	add_child(n)


func _show_menu() -> void:
	_playtest_chart = null
	var m := _swap(MENU)
	m.play_pressed.connect(_show_play)
	m.calibrate_pressed.connect(_show_calibrate)
	m.edit_pressed.connect(_show_editor)
	_mount(m)


func _show_play(chart: Chart = null) -> void:
	var p := _swap(PLAY)
	p.skin_path = Settings.skin_path
	p.chart_override = chart
	p.song_finished.connect(_show_results)
	p.quit_to_menu.connect(_after_play)
	_mount(p)


func _show_calibrate() -> void:
	var c := _swap(CALIBRATE)
	c.finished.connect(_show_menu)
	_mount(c)


func _show_editor(chart: Chart = null) -> void:
	var e := _swap(EDITOR)
	if chart != null:
		e.chart = chart
	e.finished.connect(_show_menu)
	e.playtest_requested.connect(_playtest)
	_mount(e)


func _playtest(chart: Chart) -> void:
	_playtest_chart = chart
	_show_play(chart)


## Where play goes when it ends early or finishes: back to whoever started it.
func _after_play() -> void:
	if _playtest_chart != null:
		_playtest_chart.rewind()
		_show_editor(_playtest_chart)
	else:
		_show_menu()


func _show_results(score: ScoreState, chart: Chart) -> void:
	var r := _swap(RESULTS)
	r.setup(score, chart)
	r.finished.connect(_after_play)
	_mount(r)
