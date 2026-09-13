extends NoteView
## Gesture artwork travels with the note, facing the player for readability.

const GestureArt := preload("res://visual/default/gesture_art.gd")

var _art: Sprite3D


func _ready() -> void:
	_art = GestureArt.new()
	add_child(_art)


func configure(note: Note, _skin: GameSkin) -> void:
	_art.configure(note.gesture)
	visible = true


func update_view(approach: float, _progress: float) -> void:
	_art.update_approach(approach)
