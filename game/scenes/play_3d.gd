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

var chart_path: String = Settings.chart_path
## Grace after the last note resolves, so its hit flash is seen before the
## results screen replaces it.
const OUTRO := 1.2
## Swap this (or set it before _ready) to restyle the entire game.
@export var skin_path := "res://visual/default_skin.tres"
## One hand, one centred lane - see Field3D.solo. Set before _ready.
@export var solo_mode := false

var chart: Chart
## Set before adding to the tree to play a chart that is not on disk - the
## editor hands its working copy over this way for playtesting.
var chart_override: Chart = null
var judge: Judge
var field: Playfield
var score := ScoreState.new()
var fader := MusicFader.new()

var _score_hud: Label
var _hud: Label
var _cam: Camera3D
var _outro := -1.0
var _preview: CameraPreview
var _preview_rect: TextureRect
var _preview_frame: Panel
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
	_build_preview(skin)

	judge = Judge.new()
	add_child(judge)
	judge.note_judged.connect(_on_judged)

	chart = chart_override if chart_override != null else Chart.load_from(chart_path)
	if chart != null:
		for w in chart.lint(2.0, Field3D.track):
			push_warning("chart lint: %s" % w)
	_start()


func _build_camera(skin: GameSkin) -> void:
	_cam = Camera3D.new()
	# Centred and nearly head-on. Height is the only charted axis, so a steep
	# downward tilt would foreshorten exactly what the player is judged on.
	# Far enough back that both panels fit with margins either side. The solo
	# panel is a normal panel slid to the centre, so the same framing serves it.
	_cam.position = Vector3(0.0, 0.4, 12.0)
	_cam.rotation_degrees = Vector3(-2.0, 0.0, 0.0)
	_cam.fov = 56.0
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
	_score_hud = Label.new()
	_score_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_score_hud.add_theme_font_size_override("font_size", 22)
	_score_hud.add_theme_color_override("font_color", field.skin.ui_accent)
	layer.add_child(_score_hud)
	# Stack the readout in the narrow gap; anchors follow viewport resizing.
	_score_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_score_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_hud.grow_vertical = Control.GROW_DIRECTION_BOTH
	_hud = Label.new()
	_hud.position = Vector2(24, 54)
	_hud.add_theme_font_size_override("font_size", 15)
	layer.add_child(_hud)


## The self-view sits in the lower-right corner, clear of both panels.
func _build_preview(skin: GameSkin) -> void:
	_preview = CameraPreview.new()
	add_child(_preview)
	if not skin.show_preview:
		return

	var layer := CanvasLayer.new()
	layer.layer = -1        # behind the HUD text
	add_child(layer)

	_preview_frame = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_border_width_all(1)
	sb.border_color = skin.preview_border
	sb.set_corner_radius_all(3)
	_preview_frame.add_theme_stylebox_override("panel", sb)
	_preview_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_preview_frame)

	_preview_rect = TextureRect.new()
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.modulate = Color(1, 1, 1, skin.preview_opacity)
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_preview_rect)


func _layout_preview() -> void:
	if _preview_rect == null:
		return
	var vis: bool = _preview.texture != null
	_preview_rect.visible = vis
	_preview_frame.visible = vis
	if not vis:
		return
	var skin: GameSkin = field.skin
	var screen: Vector2 = get_viewport().get_visible_rect().size
	var h: float = screen.y * skin.preview_height
	var aspect: float = float(_preview.texture.get_width()) / maxf(_preview.texture.get_height(), 1)
	var size := Vector2(h * aspect, h)
	var at := screen - size - Vector2(skin.preview_margin, skin.preview_margin)
	_preview_rect.position = at
	_preview_rect.size = size
	_preview_rect.texture = _preview.texture
	_preview_frame.position = at
	_preview_frame.size = size


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE: _start()
		KEY_C:
			if _preview_rect != null:
				_preview_rect.visible = not _preview_rect.visible
				_preview_frame.visible = _preview_rect.visible
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
	fader.reset()
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
	_layout_preview()
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
	fader.on_judged(n)
	field.flash(n)


func _update_hud() -> void:
	_score_hud.text = "SCORE\n%d\nx%d" % [score.score, score.multiplier]
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
		lines.append("Combo %d    Best Combo %d" % [score.combo, score.best_combo])
		lines.append("PERFECT %d  GREAT %d  GOOD %d  MISS %d" % [
			score.counts[Note.Verdict.PERFECT], score.counts[Note.Verdict.GREAT],
			score.counts[Note.Verdict.GOOD], score.counts[Note.Verdict.MISS]])
		lines.append("t %6.2f    %d/%d" % [
			Conductor.judge_time(), score.judged, chart.notes.size()])
		if fader.miss_streak > 0:
			lines.append("music %.0f dB (miss streak %d)" %
				[Conductor.volume_db, fader.miss_streak])
	lines.append("")
	lines.append("input: %s   (U udp/mock, TAB switch, M mirror, L lose, C camera)"
		% HandState.source_name())
	if _preview != null:
		lines.append(_preview.status())
	var g0: HandObservation = HandState.hands[0]
	var g1: HandObservation = HandState.hands[1]
	if HandState.gestures_seen:
		lines.append("gestures: L %s %.2f   R %s %.2f   (wrong shape caps at %s)" %
			[g0.gesture, g0.gesture_conf, g1.gesture, g1.gesture_conf,
			Note.verdict_name(Judge.WRONG_GESTURE_CAP)])
	else:
		lines.append("gestures: not reported - shape requirements ignored (mock: keys 1-4)")
	_hud.text = "\n".join(lines)
