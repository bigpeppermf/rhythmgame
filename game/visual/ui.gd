class_name Ui
extends RefCounted
## Shared access to the current skin for the 2D screens.
##
## Menus, calibration and results are as much a part of the look as the notes
## are, so they read the same resource rather than hardcoding colours.
##
## Note the direction of the dependency: Settings *pushes* the skin in here.
## A static function on a plain class cannot see autoload singletons, so this
## cannot pull from Settings itself - and pushing is the better shape anyway,
## since it means the skin is set exactly once when it changes.

static var _skin: GameSkin


static func set_skin(s: GameSkin) -> void:
	_skin = s


static func skin() -> GameSkin:
	if _skin == null:
		_skin = GameSkin.new()      # defaults, so screens never render unstyled
	return _skin


## Paint the whole screen. Without this the engine's default clear colour shows
## through and every screen reads as unfinished.
static func background(ctrl: CanvasItem, rect_size: Vector2) -> void:
	ctrl.draw_rect(Rect2(Vector2.ZERO, rect_size), skin().ui_background)


static func text(ctrl: CanvasItem, s: String, at: Vector2, px: int, col: Color) -> void:
	ctrl.draw_string(ThemeDB.fallback_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
