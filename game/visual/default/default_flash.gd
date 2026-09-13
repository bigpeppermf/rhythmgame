extends FlashView
## Placeholder hit flash: a ring that expands and fades in the panel's plane.

var _mesh: MeshInstance3D
var _badge: Sprite3D
var _color: Color

const BADGES := {
	Note.Verdict.PERFECT: preload("res://assets/menu/perfect!.png"),
	Note.Verdict.GREAT: preload("res://assets/menu/great.png"),
	Note.Verdict.GOOD: preload("res://assets/menu/good.png"),
	Note.Verdict.MISS: preload("res://assets/menu/miss.png"),
}
const BADGE_HEIGHT := 0.72


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	# The playfield orients this node with the panel, whose normal is local X.
	# A torus spins about its own Y, so tip it to lie flat in the panel.
	_mesh.rotation_degrees = Vector3(0, 0, 90)
	add_child(_mesh)
	_badge = Sprite3D.new()
	_badge.name = "VerdictBadge"
	_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_badge.shaded = false
	_badge.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_badge.render_priority = 2
	_badge.position = Vector3(0.0, 0.95, 0.0)
	add_child(_badge)


func configure(verdict: Note.Verdict, skin: GameSkin) -> void:
	_color = skin.verdict_color(verdict)
	_badge.texture = BADGES.get(verdict, BADGES[Note.Verdict.MISS])
	_badge.pixel_size = BADGE_HEIGHT / _badge.texture.get_height()
	_badge.modulate = Color.WHITE
	_badge.scale = Vector3.ONE * 0.82
	_badge.visible = true
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
	_badge.position.y = 0.95 + (1.0 - k) * 0.28
	_badge.scale = Vector3.ONE * lerpf(0.82, 1.0, k)
	_badge.modulate = Color(1, 1, 1, k * k)


func release() -> void:
	visible = false
	_badge.visible = false
