extends NoteView
## Placeholder tap: a flat dash lying on the panel.
##
## The playfield sets this node's basis to the panel's, so local -Z runs away
## down the panel and +Y is up. A dash is therefore just a box that is long in
## Z, thin in Y, and barely there in X.

const LENGTH := 1.5
const THICK := 0.30
const DEPTH := 0.10

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(DEPTH, THICK, LENGTH)
	_mesh.mesh = b
	add_child(_mesh)


func configure(note: Note, skin: GameSkin) -> void:
	_color = skin.slot_color(note.slot)
	visible = true


func update_view(approach: float, _progress: float) -> void:
	var c := _color
	# Near notes read first; distant ones stay quiet so the panel is not clutter.
	c.a = clampf(1.15 - approach, 0.25, 1.0)
	_mesh.material_override = Emissive.make(c)
