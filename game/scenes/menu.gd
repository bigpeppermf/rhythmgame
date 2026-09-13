extends Control
## Ocean menu. The 1280x720 composition scales uniformly inside any window.

signal play_pressed
signal play_solo_pressed
signal prototype_pressed(solo: bool)
signal calibrate_pressed
signal edit_pressed

const DESIGN_SIZE := Vector2(1280, 720)

@onready var composition: Control = $Composition
@onready var play: TextureButton = $Composition/Play
@onready var solo: TextureButton = $Composition/Solo
@onready var calibrate: TextureButton = $Composition/Calibrate
@onready var options: TextureButton = $Composition/Options
@onready var overlay: Control = $OptionsOverlay
@onready var options_panel: PanelContainer = $OptionsOverlay/Panel
@onready var input_button: Button = $OptionsOverlay/Panel/Margin/Rows/Input
@onready var offset_label: Label = $OptionsOverlay/Panel/Margin/Rows/Offset
@onready var close_button: Button = $OptionsOverlay/Panel/Margin/Rows/Close

var _menu_buttons: Array[BaseButton] = []


func _ready() -> void:
	_menu_buttons = [play, solo, calibrate, options]
	play.pressed.connect(func(): play_pressed.emit())
	solo.pressed.connect(func(): play_solo_pressed.emit())
	calibrate.pressed.connect(func(): calibrate_pressed.emit())
	options.pressed.connect(_open_options)
	close_button.pressed.connect(_close_options)
	input_button.pressed.connect(_switch_input)
	$OptionsOverlay/Panel/Margin/Rows/TwoHands.pressed.connect(func(): prototype_pressed.emit(false))
	$OptionsOverlay/Panel/Margin/Rows/OneHand.pressed.connect(func(): prototype_pressed.emit(true))
	$OptionsOverlay/Panel/Margin/Rows/Editor.pressed.connect(func(): edit_pressed.emit())
	$OptionsOverlay/Panel/Margin/Rows/Quit.pressed.connect(func(): get_tree().quit())
	_style_options()
	for i in _menu_buttons.size():
		var button := _menu_buttons[i]
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_neighbor_top = button.get_path_to(_menu_buttons[posmod(i - 1, _menu_buttons.size())])
		button.focus_neighbor_bottom = button.get_path_to(_menu_buttons[(i + 1) % _menu_buttons.size()])
		button.focus_next = button.focus_neighbor_bottom
		button.focus_previous = button.focus_neighbor_top
		button.mouse_entered.connect(_highlight.bind(button, true))
		button.mouse_exited.connect(_highlight.bind(button, false))
		button.focus_entered.connect(_highlight.bind(button, true))
		button.focus_exited.connect(_highlight.bind(button, false))
	resized.connect(_layout)
	_layout()
	play.grab_focus()


func _layout() -> void:
	var factor := minf(size.x / DESIGN_SIZE.x, size.y / DESIGN_SIZE.y)
	composition.scale = Vector2.ONE * factor
	composition.position = (size - DESIGN_SIZE * factor) * 0.5
	var panel_factor := minf(1.0, minf(size.x / 520.0, size.y / 620.0))
	options_panel.scale = Vector2.ONE * panel_factor
	options_panel.position = (size - options_panel.size * panel_factor) * 0.5
	for button in _menu_buttons:
		button.pivot_offset = button.size * 0.5


func _highlight(button: BaseButton, active: bool) -> void:
	var highlighted := active or button.has_focus() or button.is_hovered()
	button.scale = Vector2.ONE * (1.035 if highlighted else 1.0)
	button.modulate = Color(1.08, 1.08, 1.08) if highlighted else Color.WHITE


func _open_options() -> void:
	overlay.show()
	for button in _menu_buttons:
		button.focus_mode = Control.FOCUS_NONE
	_layout()
	input_button.grab_focus()


func _close_options() -> void:
	overlay.hide()
	for button in _menu_buttons:
		button.focus_mode = Control.FOCUS_ALL
	options.grab_focus()


func _switch_input() -> void:
	if HandState.source is UdpHandSource:
		HandState.use_mock()
	else:
		HandState.use_udp()


func _process(_delta: float) -> void:
	if overlay.visible:
		input_button.text = "Input: %s   [U to switch]" % ("Camera" if HandState.source is UdpHandSource else "Mouse")
		input_button.tooltip_text = HandState.source_name()
		offset_label.text = "Calibration offset: %+.0f ms" % (Settings.input_offset * 1000.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_U:
			_switch_input()
		KEY_ESCAPE:
			if overlay.visible:
				_close_options()
			else:
				_open_options()
		KEY_W, KEY_S:
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null:
				var neighbor := focused.find_prev_valid_focus() if event.keycode == KEY_W else focused.find_next_valid_focus()
				if neighbor != null:
					neighbor.grab_focus()
		_:
			return
	get_viewport().set_input_as_handled()


func _style_options() -> void:
	var theme := Theme.new()
	theme.default_font = preload("res://assets/fonts/poppins/Poppins-Medium.ttf")
	theme.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("244c70")
	panel.border_color = Color("b8f1ec")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(24)
	options_panel.add_theme_stylebox_override("panel", panel)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("356787") if state == "normal" else Color("487f9b")
		style.set_corner_radius_all(10)
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		style.content_margin_left = 16
		style.content_margin_right = 16
		if state == "focus":
			style.bg_color = Color.TRANSPARENT
			style.border_color = Color("fff0bc")
			style.set_border_width_all(2)
		theme.set_stylebox(state, "Button", style)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, "Button", Color("f4fff5"))
	options_panel.theme = theme
	var rows := $OptionsOverlay/Panel/Margin/Rows.get_children()
	var buttons: Array[Button] = []
	for row in rows:
		if row is Button:
			buttons.append(row)
	for i in buttons.size():
		var button := buttons[i]
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_previous = button.get_path_to(buttons[posmod(i - 1, buttons.size())])
		button.focus_next = button.get_path_to(buttons[(i + 1) % buttons.size()])
		button.focus_neighbor_top = button.focus_previous
		button.focus_neighbor_bottom = button.focus_next
