class_name FlashView
extends Node3D
## A thing that shows the verdict on a note that just resolved.

func configure(_verdict: Note.Verdict, _skin: GameSkin) -> void:
	pass

## age: 0.0 at the moment of judgement, 1.0 when the flash should be gone.
func update_view(_age: float) -> void:
	pass

func release() -> void:
	visible = false
