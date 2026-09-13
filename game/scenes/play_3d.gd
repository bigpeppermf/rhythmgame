extends Node3D
## Wires the song, the rules and the view together. Nothing else.
##
## Conductor keeps time, Judge decides what happened, Playfield draws it. This
## file owns none of those jobs - it just hands them to each other, which is
## why swapping the look (Playfield.skin) or the input (HandState.source)
## changes nothing here.
##
##   SPACE restart   U udp/mock   TAB switch hand   M mirror   L lose   ESC menu

signal song_finished(score: ScoreState, chart: Chart)
signal quit_to_menu

## Overridable so the same scene serves both the two-hand game and the
## one-hand solo mode (see main.gd) - only the chart and the field's hand
## count differ between them.
@export var chart_path := "res://charts/test.json"
## Grace after the last note resolves, so its hit flash is seen before the
## results screen replaces it.
const OUTRO := 1.2
## Swap this (or set it before _ready) to restyle the entire game.
@export var skin_path := "res://visual/default_skin.tres"
## One hand, one centred lane - see Field3D.solo. Set before _ready.
@export var solo_mode := false

var chart: Chart
var judge: Judge
var field: Playfield
var score := ScoreState.new()

var _hud: Label
var _cam: Camera3D
var _outro := -1.0
## True when the chart's audio file isn't there yet. Not an error: expected
## while authoring a chart, before the real track has been dropped into
## game/audio/.
var _missing_audio := false


func _ready() -> void:
	Field3D.solo = solo_mode
	var skin: GameSkin = load(skin_path)
	if skin == null:
		push_warning("no skin at %s; falling back to defaults" % skin_path)
		skin = GameSkin.new()

	_build_camera(skin)
	field = Playfield.new()
	field.skin = skin
	add_child(field)
	_build_hud()

	judge = Judge.new()
	add_child(judge)
	judge.note_judged.connect(_on_judged)

	chart = Chart.load_from(chart_path)
	if chart != null:
		for w in chart.lint(2.0, Field3D.track):
			push_warning("chart lint: %s" % w)
	_start()


func _build_camera(skin: GameSkin) -> void:
	_cam = Camera3D.new()
	# Centred and nearly head-on. Height is the only charted axis, so a steep
	# downward tilt would foreshorten exactly what the player is judged on.
	_cam.position = Vector3(0.0, 0.4, 12.0)
	_cam.rotation_degrees = Vector3(-2.0, 0.0, 0.0)
	# Two side-by-side panels need a wide FOV to both fit with margins either
	# side. A single centred lane has no second panel to fill that width with
	# - at the same FOV it reads as a thin line lost in a mostly empty frame -
	# so solo mode zooms in instead, until the lane's own height (the only
	# axis that actually varies) fills a comparable share of the screen.
	_cam.fov = 34.0 if solo_mode else 56.0
	add_child(_cam)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = skin.background_color
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = skin.ambient_color
	env.ambient_light_energy = skin.ambient_energy
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24, 20)
	_hud.add_theme_font_size_override("font_size", 15)
	layer.add_child(_hud)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE: _start()
		KEY_ESCAPE: quit_to_menu.emit()
		KEY_U:
			if HandState.source is UdpHandSource:
				HandState.use_mock()
			else:
				HandState.use_udp()


func _start() -> void:
	if chart == null:
		return
	_outro = -1.0
	_missing_audio = not ResourceLoader.exists(chart.audio_path)
	if _missing_audio:
		Conductor.stop()
		field.clear()
		return
	score.reset()
	field.clear()
	judge.begin(chart)
	Conductor.play(load(chart.audio_path), chart.bpm)


func _process(_delta: float) -> void:
	var now := Conductor.judge_time()
	if Conductor.playing:
		judge.tick(now, _delta)
		field.sync(chart, now)
	else:
		field.sync(null, now)
	_update_hud()
	_check_finished(_delta)


## The chart ends when every note has resolved, which is usually well before
## the audio does - the click track is two minutes and the chart is twenty
## seconds. Waiting for the song to end would leave the player staring at an
## empty lane.
func _check_finished(delta: float) -> void:
	if _outro >= 0.0:
		_outro += delta
		if _outro >= OUTRO:
			_outro = -1.0
			Conductor.stop()
			song_finished.emit(score, chart)
		return
	if Conductor.playing and judge.finished():
		_outro = 0.0


func _on_judged(n: Note) -> void:
	score.apply(n)
	field.flash(n)


func _update_hud() -> void:
	var lines := PackedStringArray()
	if chart == null:
		lines.append("no chart at %s" % chart_path)
	elif _missing_audio:
		lines.append("%s  -  no audio yet at %s" % [chart.title, chart.audio_path])
		lines.append("drop the track in, then SPACE to retry")
	elif not Conductor.playing:
		lines.append("%s  -  %d notes  -  SPACE to start" % [chart.title, chart.notes.size()])
		for w in chart.warnings:
			lines.append("lint: " + w)
	else:
		lines.append("%7d    x%d combo    %.1f%%" % [score.score, score.combo, score.accuracy()])
		lines.append("P %d  G %d  g %d  MISS %d" % [
			score.counts[Note.Verdict.PERFECT], score.counts[Note.Verdict.GREAT],
			score.counts[Note.Verdict.GOOD], score.counts[Note.Verdict.MISS]])
		lines.append("t %6.2f    %d/%d" % [
			Conductor.judge_time(), score.judged, chart.notes.size()])
	lines.append("")
	lines.append("input: %s   (U udp/mock, TAB switch, M mirror, L lose)" % HandState.source_name())
	_hud.text = "\n".join(lines)
