extends Node
## Persisted player settings. Autoloaded as `Settings`.
##
## Small on purpose: the only thing here that matters is input_offset, and it
## matters a lot - it is the single number that absorbs the entire camera
## pipeline's delay, which is what makes a ~100ms input path playable.

const PATH := "user://settings.cfg"

## Seconds. Positive means the player's input arrives late, so judge against an
## earlier point in the song. Measured by the calibration screen.
var input_offset: float = 0.0
var skin_path: String = "res://visual/default_skin.tres"
## The chart the game plays and the editor opens.
var chart_path: String = "res://charts/simple.json"


func _ready() -> void:
	load_settings()
	_apply()          # even with no settings file, the skin must reach Ui


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	input_offset = cfg.get_value("input", "offset", 0.0)
	skin_path = cfg.get_value("visual", "skin", skin_path)
	chart_path = cfg.get_value("chart", "path", chart_path)
	_apply()


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "offset", input_offset)
	cfg.set_value("visual", "skin", skin_path)
	cfg.set_value("chart", "path", chart_path)
	cfg.save(PATH)
	_apply()


func set_offset(seconds: float) -> void:
	input_offset = seconds
	save()


func _apply() -> void:
	Conductor.input_offset = input_offset
	# Push rather than let Ui pull: a static function on a plain class cannot
	# see autoload singletons.
	var sk: GameSkin = load(skin_path) as GameSkin
	Ui.set_skin(sk if sk != null else GameSkin.new())
