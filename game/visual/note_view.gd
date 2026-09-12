class_name NoteView
extends Node3D
## A thing that shows one note.
##
## The playfield owns position - that is gameplay geometry, derived from song
## time - and calls into here for everything else. Implement these four and any
## scene can be a note.

## Once, when this view is taken from the pool for a note.
func configure(_note: Note, _skin: GameSkin) -> void:
	pass

## Every frame the note is visible.
##   approach: 1.0 when the note first appears, 0.0 at the hit plane.
##   progress: HOLD only - fraction of the hold completed, 0..1.
func update_view(_approach: float, _progress: float) -> void:
	pass

## Returned to the pool. Reset anything stateful.
func release() -> void:
	visible = false
