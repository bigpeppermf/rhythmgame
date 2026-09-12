extends Node3D
## The perspective highway. Notes approach the player down a lane and are
## struck at the hit plane.
##
## Every gameplay decision still lives in Judge/Chart/HandState. This file only
## decides where to draw things - swapping it for scenes/play_test.gd changes
## nothing about how the game plays.
##
##   SPACE start/restart   U udp/mock   TAB switch hand   M mirror   L lose

const CHART_PATH := "res://charts/test.json"
const POOL := 48

var chart: Chart
var judge: Judge
var score := ScoreState.new()

var _pool: Array[MeshInstance3D] = []
var _cursors: Array[MeshInstance3D] = []
var _hud: Label
var _beat_pulse := 0.0
var _cam: Camera3D
var _flashes: Array = []


func _ready() -> void:
	_build_camera()
	_build_highway()
	_build_pool()
	_build_cursors()
	_build_hud()

	judge = Judge.new()
	add_child(judge)
	judge.note_judged.connect(_on_judged)
	Conductor.beat.connect(func(_i: int) -> void: _beat_pulse = 1.0)

	chart = Chart.load_from(CHART_PATH)
	if chart != null:
		for w in chart.lint():
			push_warning("chart lint: %s" % w)


# ── scene construction ───────────────────────────────────────────────────────

func _build_camera() -> void:
	_cam = Camera3D.new()
	# Above and behind the hit plane, tilted down. This is the "angled, coming
	# out of the screen" read - the foreshortening does the timing communication
	# that the 2D view needed approach rings for.
	_cam.position = Vector3(0.0, 5.0, 10.5)
	_cam.rotation_degrees = Vector3(-21.0, 0.0, 0.0)
	_cam.fov = 55.0
	add_child(_cam)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.035, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _line_mesh(pts: PackedVector3Array, col: Color) -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	for p in pts:
		im.surface_set_color(col)
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	add_child(mi)
	return mi


func _build_highway() -> void:
	var d := Field3D.depth()
	var hw := Field3D.WIDTH * 0.5
	var hh := Field3D.HEIGHT * 0.5
	var rails := PackedVector3Array()

	# Side rails and the centre divider running into the distance.
	for x in [-hw, 0.0, hw]:
		rails.append(Vector3(x, -hh, 0.0))
		rails.append(Vector3(x, -hh, -d))
	# Depth ticks, one per second of lookahead, to make speed legible.
	for i in range(1, int(Field3D.LOOKAHEAD) + 1):
		var z := -float(i) * Field3D.SCROLL
		rails.append(Vector3(-hw, -hh, z))
		rails.append(Vector3(hw, -hh, z))
	_line_mesh(rails, Color(0.45, 0.55, 0.75, 0.30))

	# Longitudinal floor lines. Three rails alone leave the tunnel reading
	# flat; these give the eye something to measure approach speed against.
	var floor_lines := PackedVector3Array()
	for i in range(1, 8):
		var x: float = -hw + (Field3D.WIDTH / 8.0) * i
		floor_lines.append(Vector3(x, -hh, 0.0))
		floor_lines.append(Vector3(x, -hh, -d))
	_line_mesh(floor_lines, Color(0.35, 0.45, 0.7, 0.10))

	# The hit plane - where judgement happens, so it gets its own weight.
	var frame := PackedVector3Array([
		Vector3(-hw, -hh, 0), Vector3(hw, -hh, 0),
		Vector3(hw, -hh, 0), Vector3(hw, hh, 0),
		Vector3(hw, hh, 0), Vector3(-hw, hh, 0),
		Vector3(-hw, hh, 0), Vector3(-hw, -hh, 0),
	])
	_line_mesh(frame, Color(0.8, 0.9, 1.0, 0.55))


func _emissive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 1.4
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _build_pool() -> void:
	# Pre-allocate. Instancing mid-song causes frame spikes, and a frame spike
	# in a rhythm game is a missed note.
	for i in POOL:
		var mi := MeshInstance3D.new()
		mi.visible = false
		add_child(mi)
		_pool.append(mi)


func _build_cursors() -> void:
	for slot in 2:
		var mi := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.42
		torus.outer_radius = 0.55
		mi.mesh = torus
		mi.rotation_degrees = Vector3(90, 0, 0)  # face the camera
		mi.material_override = _emissive(_slot_color(slot))
		add_child(mi)
		_cursors.append(mi)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(24, 20)
	_hud.add_theme_font_size_override("font_size", 15)
	layer.add_child(_hud)


func _slot_color(slot: int) -> Color:
	return Color(0.35, 0.85, 1.0) if slot == 0 else Color(1.0, 0.45, 0.75)


# ── loop ─────────────────────────────────────────────────────────────────────

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE: _start()
		KEY_U:
			if HandState.source is UdpHandSource:
				HandState.use_mock()
			else:
				HandState.use_udp()


func _start() -> void:
	if chart == null:
		return
	score.reset()
	_flashes.clear()
	judge.begin(chart)
	Conductor.play(load(chart.audio_path), chart.bpm)


func _process(delta: float) -> void:
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 5.0)
	for f in _flashes:
		f.age += delta
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return f.age < 0.45)

	if Conductor.playing:
		judge.tick(Conductor.judge_time(), delta)

	_update_notes()
	_update_cursors()
	_update_hud()


func _update_notes() -> void:
	for mi in _pool:
		mi.visible = false
	if chart == null or not Conductor.playing:
		return

	var now := Conductor.judge_time()
	var slot_i := 0
	for n in chart.notes:
		if slot_i >= POOL:
			break
		if n.is_resolved():
			continue
		var dt := n.time - now
		if dt > Field3D.LOOKAHEAD or dt < -Judge.WINDOW:
			continue

		var mi := _pool[slot_i]
		slot_i += 1
		mi.visible = true
		mi.position = Field3D.note_position(n.time, now, n.pos)

		var col := _slot_color(n.slot)
		# Notes brighten as they approach, so the near ones read first.
		col.a = clampf(1.15 - dt / Field3D.LOOKAHEAD, 0.25, 1.0)

		if n.kind == Note.Kind.HOLD:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.34
			cyl.bottom_radius = 0.34
			cyl.height = maxf(n.length * Field3D.SCROLL, 0.4)
			mi.mesh = cyl
			mi.rotation_degrees = Vector3(90, 0, 0)   # lie along Z
			mi.position.z -= cyl.height * 0.5
			# Held portion dims, so progress is visible on the note itself.
			if n._entered and n.length > 0.0:
				col = col.lerp(Color(1, 1, 1, col.a), n.held / n.length * 0.7)
		else:
			var sph := SphereMesh.new()
			sph.radius = 0.52
			sph.height = 1.04
			mi.mesh = sph
			mi.rotation_degrees = Vector3.ZERO

		mi.material_override = _emissive(col)

	# Hit flashes reuse leftover pool slots.
	for f in _flashes:
		if slot_i >= POOL:
			break
		var mi := _pool[slot_i]
		slot_i += 1
		var k: float = 1.0 - f.age / 0.45
		var ring := TorusMesh.new()
		ring.inner_radius = 0.42 + (1.0 - k) * 0.55
		ring.outer_radius = ring.inner_radius + 0.07
		mi.mesh = ring
		mi.rotation_degrees = Vector3(90, 0, 0)
		mi.position = Field3D.plane(f.pos)
		var c: Color = f.color
		# Ease the fade so the flash reads as a pop rather than a linear wipe.
		c.a = k * k
		c = c.lerp(Color(1, 1, 1, c.a), 0.35 * k)
		mi.material_override = _emissive(c)
		mi.visible = true


func _update_cursors() -> void:
	for slot in 2:
		var h: HandObservation = HandState.hands[slot]
		_cursors[slot].position = Field3D.plane(HandState.cursor(slot))
		var c := _slot_color(slot)
		c.a = 0.12 if h.state == HandObservation.State.LOST else clampf(h.conf, 0.2, 1.0)
		_cursors[slot].material_override = _emissive(c)


func _on_judged(n: Note) -> void:
	score.apply(n)
	_flashes.append({"pos": n.pos, "color": _verdict_color(n.verdict), "age": 0.0})


func _update_hud() -> void:
	var lines := PackedStringArray()
	if chart == null:
		lines.append("no chart at %s" % CHART_PATH)
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


func _verdict_color(v: Note.Verdict) -> Color:
	match v:
		Note.Verdict.PERFECT: return Color(0.5, 1.0, 0.7)
		Note.Verdict.GREAT: return Color(0.6, 0.85, 1.0)
		Note.Verdict.GOOD: return Color(1.0, 0.9, 0.5)
		_: return Color(1.0, 0.4, 0.4)
