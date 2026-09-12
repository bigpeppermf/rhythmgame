class_name Playfield
extends Node3D
## Draws the lane, the notes, the cursors and the hit flashes.
##
## Owns no rules. It is handed a chart and a time and asks the GameSkin for scenes
## to instantiate - so the entire look of the game can be replaced by pointing
## `skin` at a different resource, without touching Judge, Chart or Conductor.

@export var skin: GameSkin

## Views are instantiated on demand and reused. Instancing mid-song causes
## frame spikes, and a frame spike in a rhythm game is a missed note.
var _pool: Dictionary = {}          # Note.Kind -> Array[NoteView]
var _shown: Dictionary = {}         # Note -> NoteView
var _cursors: Array[CursorView] = []
var _flash_pool: Array[FlashView] = []
var _flashes: Array = []            # {view, age}
var _lane: Node3D


func _ready() -> void:
	if skin == null:
		skin = GameSkin.new()
	_pool[Note.Kind.TAP] = []
	_pool[Note.Kind.HOLD] = []
	_build_lane()
	_build_cursors()
	# Warm the pools so the first bar does not instantiate under load.
	for kind in [Note.Kind.TAP, Note.Kind.HOLD]:
		for i in 24:
			_release(kind, _make_note_view(kind))
	for i in 8:
		_flash_pool.append(_make_flash())


## Redraw everything for this instant. Call once per frame.
func sync(chart: Chart, now: float) -> void:
	_sync_notes(chart, now)
	_sync_cursors()
	_sync_flashes()


func flash(note: Note) -> void:
	var v: FlashView = _flash_pool.pop_back() if not _flash_pool.is_empty() else _make_flash()
	v.configure(note.verdict, skin)
	v.position = Field3D.plane(note.pos)
	_flashes.append({"view": v, "age": 0.0})


func clear() -> void:
	for note in _shown:
		_release(note.kind, _shown[note])
	_shown.clear()
	for f in _flashes:
		f.view.release()
		_flash_pool.append(f.view)
	_flashes.clear()


# ── notes ────────────────────────────────────────────────────────────────────

func _sync_notes(chart: Chart, now: float) -> void:
	var wanted: Dictionary = {}
	if chart != null:
		for n in chart.notes:
			if n.is_resolved():
				continue
			var dt: float = n.time - now
			if dt > Field3D.LOOKAHEAD:
				break          # sorted, so nothing later is visible either
			if dt < -Judge.WINDOW:
				continue
			wanted[n] = true

	for note in _shown.keys():
		if not wanted.has(note):
			_release(note.kind, _shown[note])
			_shown.erase(note)

	for note in wanted:
		var v: NoteView = _shown.get(note)
		if v == null:
			v = _acquire(note.kind)
			v.configure(note, skin)
			_shown[note] = v
		v.position = Field3D.note_position(note.time, now, note.pos)
		var approach: float = clampf((note.time - now) / Field3D.LOOKAHEAD, 0.0, 1.0)
		var progress: float = note.held / note.length if note.length > 0.0 else 0.0
		v.update_view(approach, progress)


func _acquire(kind: Note.Kind) -> NoteView:
	var pool: Array = _pool[kind]
	var v: NoteView = pool.pop_back() if not pool.is_empty() else _make_note_view(kind)
	v.visible = true
	return v


func _release(kind: Note.Kind, v: NoteView) -> void:
	v.release()
	_pool[kind].append(v)


func _make_note_view(kind: Note.Kind) -> NoteView:
	var scene: PackedScene = skin.hold_scene if kind == Note.Kind.HOLD else skin.tap_scene
	var v: NoteView
	if scene != null:
		v = scene.instantiate()
	else:
		# A skin with an empty slot should degrade to something visible rather
		# than crash mid-demo.
		push_warning("GameSkin has no scene for note kind %d; using a blank view" % kind)
		v = NoteView.new()
	add_child(v)
	v.visible = false
	return v


# ── cursors ──────────────────────────────────────────────────────────────────

func _build_cursors() -> void:
	for slot in 2:
		var v: CursorView
		if skin.cursor_scene != null:
			v = skin.cursor_scene.instantiate()
		else:
			v = CursorView.new()
		add_child(v)
		v.configure(slot, skin)
		_cursors.append(v)


func _sync_cursors() -> void:
	for slot in 2:
		var h: HandObservation = HandState.hands[slot]
		_cursors[slot].position = Field3D.plane(HandState.cursor(slot))
		_cursors[slot].update_view(h.conf, h.state)


# ── flashes ──────────────────────────────────────────────────────────────────

func _make_flash() -> FlashView:
	var v: FlashView
	if skin.flash_scene != null:
		v = skin.flash_scene.instantiate()
	else:
		v = FlashView.new()
	add_child(v)
	v.visible = false
	return v


func _sync_flashes() -> void:
	var dt: float = get_process_delta_time()
	var live: Array = []
	for f in _flashes:
		f.age += dt
		var a: float = f.age / maxf(skin.flash_duration, 0.01)
		if a >= 1.0:
			f.view.release()
			_flash_pool.append(f.view)
			continue
		f.view.update_view(a)
		live.append(f)
	_flashes = live


# ── lane ─────────────────────────────────────────────────────────────────────

func _build_lane() -> void:
	if not skin.draw_lane:
		return
	_lane = Node3D.new()
	add_child(_lane)

	var d := Field3D.depth()
	var hh := Field3D.HEIGHT * 0.5

	var rails := PackedVector3Array()
	var grid := PackedVector3Array()
	var frame := PackedVector3Array()

	# One track per hand, with the centre left empty.
	for slot in 2:
		var t: Vector2 = Field3D.track(slot)
		var x0: float = Field3D.plane(Vector2(t.x, 0.5)).x
		var x1: float = Field3D.plane(Vector2(t.y, 0.5)).x

		for x in [x0, x1]:
			rails.append(Vector3(x, -hh, 0.0))
			rails.append(Vector3(x, -hh, -d))
		for i in range(1, int(Field3D.LOOKAHEAD) + 1):
			var z := -float(i) * Field3D.SCROLL
			rails.append(Vector3(x0, -hh, z))
			rails.append(Vector3(x1, -hh, z))

		# Longitudinal floor lines give the eye something to measure approach
		# speed against; rails alone leave the track reading flat.
		var cols: int = maxi(skin.grid_columns / 2, 1)
		for i in range(1, cols):
			var x: float = lerpf(x0, x1, float(i) / cols)
			grid.append(Vector3(x, -hh, 0.0))
			grid.append(Vector3(x, -hh, -d))

		frame.append_array(PackedVector3Array([
			Vector3(x0, -hh, 0), Vector3(x1, -hh, 0),
			Vector3(x1, -hh, 0), Vector3(x1, hh, 0),
			Vector3(x1, hh, 0), Vector3(x0, hh, 0),
			Vector3(x0, hh, 0), Vector3(x0, -hh, 0),
		]))

	_line(rails, skin.rail_color)
	_line(grid, skin.grid_color)
	_line(frame, skin.hit_plane_color)


func _line(pts: PackedVector3Array, col: Color) -> void:
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
	_lane.add_child(mi)
