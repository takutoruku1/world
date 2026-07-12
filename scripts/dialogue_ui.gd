extends CanvasLayer
# The god-conversation window, visual-novel style: Ashita's portrait (with
# expressions) in a gold frame, typewriter text, then choice buttons.
# The game clock is paused while a conversation is open.

const U = preload("res://scripts/util.gd")

const PORTRAIT_MOODS := ["normal", "smile", "worried", "surprised", "determined"]

var clock
var dim: ColorRect
var panel: PanelContainer
var portrait_frame: PanelContainer
var portrait_rect: TextureRect
var cutin_rect: TextureRect
var speaker_label: Label
var text_rt: RichTextLabel
var choices_panel: PanelContainer
var choices_box: VBoxContainer
var advance_hint: Label
var _typing := false
var _cb := Callable()
var _choices: Array = []
var _current_mood := ""

func build(clk) -> void:
	clock = clk
	layer = 20
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = U.build_theme()
	add_child(root)

	dim = ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.03, 0.30)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	root.add_child(dim)

	panel = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 208.0
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

	cutin_rect = TextureRect.new()
	cutin_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cutin_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cutin_rect.custom_minimum_size = Vector2(0, 120)
	cutin_rect.clip_contents = true
	cutin_rect.visible = false
	v.add_child(cutin_rect)

	var header := HBoxContainer.new()
	speaker_label = U.make_label("アシタ", 16, U.COL["gold"])
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(0.14, 0.12, 0.05, 0.92)
	chip.border_color = U.COL["gold"]
	chip.set_border_width_all(1)
	chip.set_corner_radius_all(6)
	chip.content_margin_left = 10.0
	chip.content_margin_right = 10.0
	chip.content_margin_top = 2.0
	chip.content_margin_bottom = 2.0
	speaker_label.add_theme_stylebox_override("normal", chip)
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
	advance_hint = U.make_label("▼", 13, U.COL["gold"])
	advance_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	advance_hint.visible = false
	v.add_child(advance_hint)

	# The god's choices live in their own panel above the dialog window, so the
	# hero's words and the player's guidance never crowd each other.
	choices_panel = PanelContainer.new()
	choices_panel.anchor_left = 0.0
	choices_panel.anchor_right = 1.0
	choices_panel.anchor_top = 1.0
	choices_panel.anchor_bottom = 1.0
	choices_panel.offset_left = 320.0
	choices_panel.offset_right = -440.0
	choices_panel.offset_bottom = -184.0
	choices_panel.offset_top = -184.0
	choices_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var cp := StyleBoxFlat.new()
	cp.bg_color = Color(0.1, 0.09, 0.05, 0.97)
	cp.set_corner_radius_all(10)
	cp.border_color = U.COL["gold"]
	cp.set_border_width_all(2)
	cp.content_margin_left = 14.0
	cp.content_margin_right = 14.0
	cp.content_margin_top = 8.0
	cp.content_margin_bottom = 8.0
	choices_panel.add_theme_stylebox_override("panel", cp)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	choices_panel.add_child(cv)
	var ch := U.make_label("⟡ 神の導き — どうする？", 14, U.COL["gold"])
	cv.add_child(ch)
	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 4)
	cv.add_child(choices_box)
	choices_panel.visible = false
	root.add_child(choices_panel)

	portrait_frame = PanelContainer.new()
	portrait_frame.anchor_left = 0.0
	portrait_frame.anchor_right = 0.0
	portrait_frame.anchor_top = 1.0
	portrait_frame.anchor_bottom = 1.0
	portrait_frame.offset_left = 14.0
	portrait_frame.offset_right = 196.0
	portrait_frame.offset_top = -262.0
	portrait_frame.offset_bottom = -14.0
	var pf := StyleBoxFlat.new()
	pf.bg_color = Color(0.06, 0.06, 0.1, 1.0)
	pf.border_color = U.COL["gold"]
	pf.set_border_width_all(2)
	pf.set_corner_radius_all(12)
	pf.content_margin_left = 4.0
	pf.content_margin_right = 4.0
	pf.content_margin_top = 4.0
	pf.content_margin_bottom = 4.0
	portrait_frame.add_theme_stylebox_override("panel", pf)
	portrait_rect = TextureRect.new()
	portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_rect.clip_contents = true
	portrait_frame.add_child(portrait_rect)
	portrait_frame.visible = false
	root.add_child(portrait_frame)

	panel.gui_input.connect(_on_panel_input)
	panel.visible = false
	set_process(false)

func is_open() -> bool:
	return panel.visible

func open(speaker: String, text: String, choices: Array, cb: Callable, event_id := "", mood := "normal") -> void:
	clock.dialog_pause()
	var fresh := not panel.visible
	panel.visible = true
	dim.visible = true
	_apply_cutin(event_id)
	_apply_mood(mood, fresh)
	if speaker != "アシタ":
		portrait_frame.visible = false
	speaker_label.text = speaker
	var scol: Color = U.COL["gold"]
	if speaker == "語り":
		scol = U.COL["sub"]
	elif speaker.begins_with("？"):
		scol = U.COL["mystic"]
	speaker_label.add_theme_color_override("font_color", scol)
	text_rt.text = text
	text_rt.visible_characters = 0
	_typing = true
	_cb = cb
	_choices = choices
	_clear_choices()
	set_process(true)
	if fresh:
		panel.modulate.a = 0.0
		dim.modulate.a = 0.0
		var tw := panel.create_tween().set_parallel(true)
		tw.tween_property(panel, "modulate:a", 1.0, 0.22)
		tw.tween_property(dim, "modulate:a", 1.0, 0.3)

func _apply_mood(mood: String, fresh: bool) -> void:
	if not PORTRAIT_MOODS.has(mood):
		mood = "normal"
	var tex := U.load_texture_file("res://assets/portraits/ashita_%s.png" % mood)
	if tex == null:
		tex = U.load_texture_file("res://assets/portraits/ashita_normal.png")
	portrait_frame.visible = tex != null
	if tex == null:
		return
	var changed := mood != _current_mood
	_current_mood = mood
	portrait_rect.texture = tex
	if fresh or changed:
		portrait_frame.modulate.a = 0.25
		var start_y := portrait_frame.offset_top + 10.0
		var tw := portrait_frame.create_tween().set_parallel(true)
		tw.tween_property(portrait_frame, "modulate:a", 1.0, 0.25)
		tw.tween_property(portrait_frame, "offset_top", portrait_frame.offset_top, 0.25).from(start_y)

func _apply_cutin(event_id: String) -> void:
	var tex = null
	if event_id != "":
		tex = U.load_texture_file("res://assets/illustrations/cutin_%s.png" % event_id)
	cutin_rect.texture = tex
	cutin_rect.visible = tex != null
	panel.offset_top = -300.0 if tex != null else -170.0

func close() -> void:
	panel.visible = false
	dim.visible = false
	portrait_frame.visible = false
	choices_panel.visible = false
	_current_mood = ""
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
	if _choices.is_empty():
		advance_hint.visible = true
		return
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
	choices_panel.visible = true
	choices_panel.modulate.a = 0.0
	# Size the panel explicitly from its content and pin it fully above the
	# dialog box. Container auto-grow (GROW_DIRECTION_BEGIN) proved unreliable
	# after window resizes: layout re-evaluation grew the list downward over
	# the dialog and off-screen.
	await get_tree().process_frame
	if not choices_panel.visible:
		return  # closed while waiting for layout
	var need: float = choices_panel.get_combined_minimum_size().y
	choices_panel.offset_bottom = panel.offset_top - 6.0
	choices_panel.offset_top = choices_panel.offset_bottom - need
	var tw := choices_panel.create_tween()
	tw.tween_property(choices_panel, "modulate:a", 1.0, 0.2)

func _clear_choices() -> void:
	choices_panel.visible = false
	if advance_hint:
		advance_hint.visible = false
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
		elif _choices.is_empty():
			_choose(-1)  # response page: any click advances
