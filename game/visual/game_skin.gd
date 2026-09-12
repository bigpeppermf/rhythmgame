class_name GameSkin
extends Resource
## Everything about how the game looks, in one replaceable resource.
##
## Gameplay never reads this. The playfield does, and it only ever asks the
## skin for a scene to instantiate and a colour to tint it - so replacing the
## look means pointing these at your own scenes, not editing game code.
##
## To make your own: duplicate default_skin.tres, swap the scene slots for your
## own, and set Playfield.skin to it. Your scenes need only extend NoteView /
## CursorView / FlashView and implement their handful of methods.

@export_group("Palette")
## Per hand. Index is the slot: 0 = left, 1 = right.
@export var slot_colors: Array[Color] = [
	Color(0.35, 0.85, 1.00),
	Color(1.00, 0.45, 0.75),
]
@export var perfect_color := Color(0.50, 1.00, 0.70)
@export var great_color := Color(0.60, 0.85, 1.00)
@export var good_color := Color(1.00, 0.90, 0.50)
@export var miss_color := Color(1.00, 0.40, 0.40)

@export_group("Environment")
@export var background_color := Color(0.03, 0.035, 0.06)
@export var ambient_color := Color(0.50, 0.55, 0.70)
@export var ambient_energy := 0.6

@export_group("Lane")
@export var draw_lane := true
@export var rail_color := Color(0.45, 0.55, 0.75, 0.30)
@export var grid_color := Color(0.35, 0.45, 0.70, 0.10)
@export var hit_plane_color := Color(0.80, 0.90, 1.00, 0.55)
@export var grid_columns := 8

@export_group("Interface")
## Menus, calibration and results read these, so restyling the game restyles
## its screens too rather than leaving them on engine defaults.
@export var ui_background := Color(0.05, 0.055, 0.08)
@export var ui_text := Color(0.95, 0.96, 1.00)
@export var ui_dim := Color(0.62, 0.66, 0.76)
@export var ui_faint := Color(0.35, 0.38, 0.46)
@export var ui_accent := Color(0.50, 1.00, 0.70)
@export var ui_warn := Color(1.00, 0.82, 0.45)

@export_group("Scenes")
## Each must extend NoteView.
@export var tap_scene: PackedScene
@export var hold_scene: PackedScene
## Must extend CursorView.
@export var cursor_scene: PackedScene
## Must extend FlashView.
@export var flash_scene: PackedScene

@export_group("Timing")
## How long a hit flash lives, in seconds.
@export var flash_duration := 0.45


func slot_color(slot: int) -> Color:
	return slot_colors[slot] if slot < slot_colors.size() else Color.WHITE


func verdict_color(v: Note.Verdict) -> Color:
	match v:
		Note.Verdict.PERFECT: return perfect_color
		Note.Verdict.GREAT: return great_color
		Note.Verdict.GOOD: return good_color
		_: return miss_color
