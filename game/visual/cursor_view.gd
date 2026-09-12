class_name CursorView
extends Node3D
## A thing that shows where one hand is. Position is set by the playfield.

func configure(_slot: int, _skin: GameSkin) -> void:
	pass

## confidence 0..1, and the tracking state, so degraded input is visible
## rather than silently wrong.
func update_view(_confidence: float, _state: HandObservation.State) -> void:
	pass
