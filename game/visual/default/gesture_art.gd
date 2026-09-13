extends Sprite3D
## Shared gesture artwork for taps and hold heads. The parent remains placed
## and oriented by the playfield; only this visual child faces the camera.

const HEIGHT := 1.65
const TEXTURES := {
	&"OPEN_PALM": preload("res://assets/menu/fat_open_palm.png"),
	&"FIST": preload("res://assets/menu/fat_fist.png"),
	&"PINCH": preload("res://assets/menu/fat_pinch.png"),
	&"THUMBS_UP": preload("res://assets/menu/fat_thumbs_up.png"),
}


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shaded = false
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# Draw the head over its hold trail, while retaining normal depth testing.
	render_priority = 1


func configure(gesture: StringName) -> void:
	# Unrestricted notes share the open-palm visual, not its judging requirement.
	texture = TEXTURES.get(gesture, TEXTURES[&"OPEN_PALM"])
	pixel_size = HEIGHT / texture.get_height()
	modulate = Color.WHITE
	visible = true


func update_approach(approach: float) -> void:
	# Preserve the artist's palette; distance changes opacity, never hand tint.
	modulate = Color(1, 1, 1, clampf(1.15 - approach, 0.25, 1.0))
