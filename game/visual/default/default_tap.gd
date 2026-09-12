extends NoteView
## Placeholder tap: an emissive sphere that brightens as it approaches.

const RADIUS := 0.52

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = RADIUS
	s.height = RADIUS * 2.0
	_mesh.mesh = s
	add_child(_mesh)


func configure(note: Note, skin: GameSkin) -> void:
	_color = skin.slot_color(note.slot)
	visible = true


func update_view(approach: float, _progress: float) -> void:
	var c := _color
	# Near notes read first; distant ones stay quiet so the lane is not clutter.
	c.a = clampf(1.15 - approach, 0.25, 1.0)
	_mesh.material_override = Emissive.make(c)
