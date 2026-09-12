extends NoteView
## Placeholder hold: the same dash, stretched along the panel by its duration.
##
## Length comes from the note, so the mesh is rebuilt per note rather than
## merely retinted - exactly the kind of thing a custom skin may want to do
## differently (a stretched texture, a shader, a trail).

const THICK := 0.34
const DEPTH := 0.12

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	add_child(_mesh)


func configure(note: Note, skin: GameSkin) -> void:
	_color = skin.slot_color(note.slot)
	var b := BoxMesh.new()
	var length: float = maxf(note.length * Field3D.SCROLL, 0.6)
	b.size = Vector3(DEPTH, THICK, length)
	_mesh.mesh = b
	# Anchor the near end at the note's own moment; the body trails behind it
	# up the panel, so the head is what the player aims at.
	_mesh.position.z = -length * 0.5
	visible = true


func update_view(approach: float, progress: float) -> void:
	var c := _color
	c.a = clampf(1.15 - approach, 0.25, 1.0)
	c = c.lerp(Color(1, 1, 1, c.a), progress * 0.7)
	_mesh.material_override = Emissive.make(c)
