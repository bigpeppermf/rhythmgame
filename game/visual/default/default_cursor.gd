extends CursorView
## Placeholder cursor: a solid marker riding the panel's hit edge.
##
## Opacity follows tracking confidence, so degraded input is visible rather
## than silently wrong.

const RADIUS := 0.42

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = RADIUS
	s.height = RADIUS * 2.0
	_mesh.mesh = s
	add_child(_mesh)


func configure(slot: int, skin: GameSkin) -> void:
	_color = skin.slot_color(slot)


func update_view(confidence: float, state: HandObservation.State) -> void:
	var c := _color
	c.a = 0.12 if state == HandObservation.State.LOST else clampf(confidence, 0.2, 1.0)
	_mesh.material_override = Emissive.make(c)
