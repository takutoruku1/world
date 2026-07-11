extends CanvasLayer
# The god-conversation window. Typewriter text, then choice buttons.
# The game clock is paused while a conversation is open.

const U = preload("res://scripts/util.gd")

var clock
var panel: PanelContainer
var speaker_label: Label
var text_rt: RichTextLabel
var choices_box: VBoxContainer
var _typing := false
var _cb := Callable()
var _choices: Array = []

func build(clk) -> void:
	clock = clk
	layer = 20
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = U.build_theme()
	add_child(root)

	panel = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 120.0
	panel.offset_right = -440.0
	panel.offset_top = -170.0
	panel.offset_bottom = -14.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.085, 0.095, 0.15, 0.97)
	sb.set_corner_radius_all(10)
	sb.border_color = U.COL["gold"]
	sb.set_border_width_all(1)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", sb)
	root.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	var header := HBoxContainer.new()
	header.add_child(U.make_label("🕯 ", 15, U.COL["gold"]))
	speaker_label = U.make_label("アシタ", 16, U.COL["gold"])
	header.add_child(speaker_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(spacer)
	header.add_child(U.make_label("クリックで進む", 11, U.COL["sub"]))
	v.add_child(header)

	text_rt = U.make_richtext(15)
	text_rt.custom_minimum_size = Vector2(0, 64)
	text_rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(text_rt)

	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 4)
	v.add_child(choices_box)

	panel.gui_input.connect(_on_panel_input)
	panel.visible = false
	set_process(false)

func is_open() -> bool:
	return panel.visible

func open(speaker: String, text: String, choices: Array, cb: Callable) -> void:
	clock.dialog_pause()
	panel.visible = true
	speaker_label.text = speaker
	text_rt.text = text
	text_rt.visible_characters = 0
	_typing = true
	_cb = cb
	_choices = choices
	_clear_choices()
	set_process(true)

func close() -> void:
	panel.visible = false
	_clear_choices()
	_cb = Callable()
	set_process(false)
	clock.dialog_resume()

func _process(delta: float) -> void:
	if not _typing:
		return
	text_rt.visible_characters += maxi(1, int(delta * 45.0))
	if text_rt.visible_characters >= text_rt.get_total_character_count():
		_finish_typing()

func _finish_typing() -> void:
	_typing = false
	text_rt.visible_characters = -1
	_show_choices()

func _show_choices() -> void:
	for i in range(_choices.size()):
		var c: Dictionary = _choices[i]
		var b := Button.new()
		b.text = "▶ " + str(c.get("label", "…"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func(): _choose(idx))
		choices_box.add_child(b)
		var sub := str(c.get("sub", ""))
		if sub != "":
			choices_box.add_child(U.make_label("　　" + sub, 11, U.COL["sub"]))

func _clear_choices() -> void:
	for child in choices_box.get_children():
		child.queue_free()

func _choose(idx: int) -> void:
	_clear_choices()
	var cb := _cb
	_cb = Callable()
	if cb.is_valid():
		cb.call(idx)

func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _typing:
			_finish_typing()
