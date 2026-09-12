extends NoteView
## Placeholder tap: a shape lying on the panel, chosen by the note's gesture.
##
## The playfield sets this node's basis to the panel's, so local -Z runs away
## down the panel and +Y is up. See note_shapes.gd for the silhouettes.

const NoteShapes := preload("res://visual/default/note_shapes.gd")

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	add_child(_mesh)


func configure(note: Note, skin: GameSkin) -> void:
	_color = skin.slot_color(note.slot)
	_mesh.mesh = NoteShapes.head_mesh(note.gesture)
	_mesh.rotation_degrees = NoteShapes.head_rotation(note.gesture)
	visible = true


func update_view(approach: float, _progress: float) -> void:
	var c := _color
	# Near notes read first; distant ones stay quiet so the panel is not clutter.
	c.a = clampf(1.15 - approach, 0.25, 1.0)
	_mesh.material_override = Emissive.make(c)
