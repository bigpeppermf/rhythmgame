extends NoteView
## Example of a custom note: a slowly tumbling cube instead of a sphere.
##
## This file exists to demonstrate the seam. It implements NoteView and nothing
## else - no knowledge of charts, timing, judgement or the Conductor. Drop your
## own scene in the same way.

var _mesh: MeshInstance3D
var _color: Color
var _spin := 0.0


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.8, 0.8, 0.8)
	_mesh.mesh = b
	add_child(_mesh)


func configure(note: Note, skin: GameSkin) -> void:
	_color = skin.slot_color(note.slot)
	_spin = randf() * TAU
	visible = true


func update_view(approach: float, _progress: float) -> void:
	_spin += get_process_delta_time() * 2.0
	_mesh.rotation = Vector3(_spin * 0.6, _spin, 0.0)
	var c := _color
	c.a = clampf(1.15 - approach, 0.25, 1.0)
	_mesh.material_override = Emissive.make(c)
