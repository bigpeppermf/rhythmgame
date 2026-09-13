extends Control
## Title screen. Also where the input source and the current offset are
## visible, because both are things you want to check before a demo rather
## than discover during one.

signal play_pressed
signal play_solo_pressed
signal calibrate_pressed

var _font: Font
var _sel := 0
const ITEMS := ["Play", "Play (1H)", "Calibrate", "Quit"]


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_UP, KEY_W: _sel = posmod(_sel - 1, ITEMS.size())
		KEY_DOWN, KEY_S: _sel = posmod(_sel + 1, ITEMS.size())
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _activate()
		KEY_U:
			if HandState.source is UdpHandSource:
				HandState.use_mock()
			else:
				HandState.use_udp()


func _activate() -> void:
	match _sel:
		0: play_pressed.emit()
		1: play_solo_pressed.emit()
		2: calibrate_pressed.emit()
		3: get_tree().quit()


func _draw() -> void:
	var sk := Ui.skin()
	Ui.background(self, size)
	var x := maxf(80.0, size.x * 0.5 - 310.0)
	var y := maxf(110.0, size.y * 0.18)

	_text("RHYTHM", Vector2(x, y), 52, sk.ui_text)
	_text("camera-tracked, two hands", Vector2(x + 4, y + 34), 16, sk.ui_faint)

	y += 132.0
	for i in ITEMS.size():
		var on: bool = i == _sel
		_text(("> " if on else "  ") + ITEMS[i], Vector2(x, y), 22,
			sk.ui_text if on else sk.ui_faint)
		y += 38.0

	var lines := [
		"input    %s" % HandState.source_name(),
		"offset   %+.0f ms" % (Settings.input_offset * 1000.0),
		"",
		"U switches input source    arrows + ENTER",
	]
	y = size.y - 130.0
	for l in lines:
		_text(l, Vector2(x, y), 14, sk.ui_faint)
		y += 22.0


func _text(s: String, at: Vector2, px: int, col: Color) -> void:
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
