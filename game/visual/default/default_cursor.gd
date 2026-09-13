extends CursorView
## Placeholder cursor: a solid marker riding the panel's hit edge.
##
## Opacity follows tracking confidence, so degraded input is visible rather
## than silently wrong.

var _art: Sprite3D
var _color: Color
const HEIGHT := 0.95
const TEXTURES := [
	preload("res://assets/menu/left_jelly.png"),
	preload("res://assets/menu/right_jelly.png"),
]


func _ready() -> void:
	_art = Sprite3D.new()
	_art.name = "JellyCursor"
	_art.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_art.shaded = false
	_art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_art.render_priority = 2
	add_child(_art)


func configure(slot: int, skin: GameSkin) -> void:
	_color = skin.cursor_color
	var texture: Texture2D = TEXTURES[clampi(slot, 0, TEXTURES.size() - 1)]
	_art.texture = texture
	_art.pixel_size = HEIGHT / texture.get_height()
	_art.modulate = Color.WHITE


func update_view(confidence: float, state: HandObservation.State) -> void:
	var c := _color
	c.a = 0.12 if state == HandObservation.State.LOST else clampf(confidence, 0.2, 1.0)
	_art.modulate = Color(1, 1, 1, c.a)
