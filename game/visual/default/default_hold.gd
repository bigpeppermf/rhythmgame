extends NoteView
## Placeholder hold: a capsule lying along the lane, whitening as it is held.
##
## Length comes from the note, so the view has to be rebuilt per note rather
## than merely retinted - which is exactly the kind of thing a custom skin may
## want to do differently (a stretched mesh, a shader, a particle trail).

const RADIUS := 0.34

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.rotation_degrees = Vector3(90, 0, 0)   # lie along Z
	add_child(_mesh)


func configure(note: Note, skin: GameSkin) -> void:
	_color = skin.slot_color(note.slot)
	var cyl := CylinderMesh.new()
	cyl.top_radius = RADIUS
	cyl.bottom_radius = RADIUS
	cyl.height = maxf(note.length * Field3D.SCROLL, 0.4)
	_mesh.mesh = cyl
	# Anchor the near end at the note's own moment; the body trails behind it.
	_mesh.position.z = -cyl.height * 0.5
	visible = true


func update_view(approach: float, progress: float) -> void:
	var c := _color
	c.a = clampf(1.15 - approach, 0.25, 1.0)
	c = c.lerp(Color(1, 1, 1, c.a), progress * 0.7)
	_mesh.material_override = Emissive.make(c)
