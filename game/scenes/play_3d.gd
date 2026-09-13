extends Node3D
## Wires the song, the rules and the view together. Nothing else.
##
## Conductor keeps time, Judge decides what happened, Playfield draws it. This
## file owns none of those jobs - it just hands them to each other, which is
## why swapping the look (Playfield.skin) or the input (HandState.source)
## changes nothing here.
##
##   SPACE restart   U udp/mock   TAB switch hand   M mirror   L lose   ESC menu
##   F3 input diagnostics

signal song_finished(score: ScoreState, chart: Chart)
signal quit_to_menu

var chart_path: String = Settings.chart_path
## Grace after the last note resolves, so its hit flash is seen before the
## results screen replaces it.
const OUTRO := 1.2
const SCORE_FONT := preload("res://assets/fonts/poppins/Poppins-Medium.ttf")
const PLAY_FOV := 44.0
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
var _preview_enabled := true
var _show_debug := false
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
	get_viewport().size_changed.connect(_layout_gameplay)
	_layout_gameplay()
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
	# A tighter lens enlarges the panels without changing chart or hit geometry.
	_cam.position = Vector3(0.0, 0.4, 12.0)
	_cam.rotation_degrees = Vector3(-2.0, 0.0, 0.0)
	_cam.fov = PLAY_FOV
	add_child(_cam)

	# Render the full-window artwork behind the 3D field, with the HUD above it.
	var background_layer := CanvasLayer.new()
	background_layer.layer = -10
	add_child(background_layer)
	var background := TextureRect.new()
	background.texture = preload("res://assets/menu/game_bg.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_layer.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var env := Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.background_canvas_max_layer = -10
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
	_score_hud.add_theme_font_override("font", SCORE_FONT)
	_score_hud.add_theme_font_size_override("font_size", 36)
	_score_hud.add_theme_color_override("font_color", field.skin.ui_accent)
	layer.add_child(_score_hud)
	# Stack the readout in the narrow gap; anchors follow viewport resizing.
	_score_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_score_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_hud.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Solo's panel occupies the middle, so put the score in the open right side.
	if solo_mode:
		_score_hud.anchor_left = 0.78
		_score_hud.anchor_right = 0.78
	_hud = Label.new()
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_theme_font_size_override("font_size", 15)
	layer.add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_top = 12


func _layout_gameplay() -> void:
	var screen := get_viewport().get_visible_rect().size
	var aspect := screen.x / maxf(screen.y, 1.0)
	# Keep the same horizontal room in narrow windows so the hit edges and
	# enlarged icons remain visible. Widescreen uses the closer framing.
	var aspect_scale := maxf(1.0, (16.0 / 9.0) / maxf(aspect, 0.1))
	_cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(PLAY_FOV * 0.5)) * aspect_scale))
	var ui_scale := clampf(minf(screen.x / 1280.0, screen.y / 720.0), 0.6, 1.5)
	_score_hud.add_theme_font_size_override("font_size", roundi(36.0 * ui_scale))


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
	var vis: bool = _preview_enabled and _preview.texture != null
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
		KEY_F3:
			_show_debug = not _show_debug
			_update_hud()
		KEY_C:
			_preview_enabled = not _preview_enabled
			_layout_preview()
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
		if _show_debug:
			lines.append("t %6.2f    %d/%d" % [
				Conductor.judge_time(), score.judged, chart.notes.size()])
		if _show_debug and fader.miss_streak > 0:
			lines.append("music %.0f dB (miss streak %d)" %
				[Conductor.volume_db, fader.miss_streak])
	lines.append("F3 input details   ·   SPACE restart   ·   ESC menu")
	if not _show_debug:
		_hud.text = "\n".join(lines)
		return
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
