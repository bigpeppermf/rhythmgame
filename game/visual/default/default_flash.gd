extends FlashView
## Placeholder hit flash: a ring that expands and fades.

var _mesh: MeshInstance3D
var _color: Color


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.rotation_degrees = Vector3(90, 0, 0)
	add_child(_mesh)


func configure(verdict: Note.Verdict, skin: GameSkin) -> void:
	_color = skin.verdict_color(verdict)
	visible = true


func update_view(age: float) -> void:
	var k: float = 1.0 - clampf(age, 0.0, 1.0)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42 + (1.0 - k) * 0.55
	ring.outer_radius = ring.inner_radius + 0.07
	_mesh.mesh = ring
	var c := _color
	# Eased so it reads as a pop rather than a linear wipe.
	c.a = k * k
	_mesh.material_override = Emissive.make(c.lerp(Color(1, 1, 1, c.a), 0.35 * k))
