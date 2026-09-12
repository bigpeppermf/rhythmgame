extends CursorView
## Placeholder cursor: a ring facing the camera, opacity driven by tracking
## confidence so degraded input is visible rather than silently wrong.

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.42
	t.outer_radius = 0.55
	_mesh.mesh = t
	_mesh.rotation_degrees = Vector3(90, 0, 0)
	add_child(_mesh)


func configure(slot: int, skin: GameSkin) -> void:
	_color = skin.slot_color(slot)


func update_view(confidence: float, state: HandObservation.State) -> void:
	var c := _color
	c.a = 0.12 if state == HandObservation.State.LOST else clampf(confidence, 0.2, 1.0)
	_mesh.material_override = Emissive.make(c)
