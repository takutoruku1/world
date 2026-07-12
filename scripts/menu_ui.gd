extends CanvasLayer
# ESC menu with the History Book: every civilization turning point (prologue
# answer, era transitions, major event decisions) recorded by events.gd /
# main.gd into world.history is rendered here. Opening the menu pauses the
# clock on its own channel so it never fights the dialog pause.

const U = preload("res://scripts/util.gd")

var main
var root: Control
var book: RichTextLabel
var scroll: ScrollContainer
var save_btn: Button
var load_btn: Button

func setup(m) -> void:
	main = m
	layer = 60
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			close())
	root.add_child(dim)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = U.COL["panel"]
	sb.border_color = U.COL["gold"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 26.0
	sb.content_margin_right = 26.0
	sb.content_margin_top = 18.0
	sb.content_margin_bottom = 16.0
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(680.0, 520.0)
	panel.offset_left = -340.0
	panel.offset_top = -260.0
	panel.offset_right = 340.0
	panel.offset_bottom = 260.0
	root.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var title := U.make_label("― 歴史書 ―", 24, U.COL["gold"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var sub := U.make_label("文明の分岐点は、ここに刻まれる", 12, U.COL["sub"])
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	var rule := ColorRect.new()
	rule.color = U.COL["border"]
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	vb.add_child(rule)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)

	book = U.make_richtext(14)
	book.size_flags_vertical = Control.SIZE_FILL
	scroll.add_child(book)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	vb.add_child(foot)
	var hint := U.make_label("ESC または 外側クリックで閉じる", 11, U.COL["sub"])
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	save_btn = Button.new()
	save_btn.text = "  💾 セーブ  "
	save_btn.tooltip_text = "いまの世界を記録する(毎朝のオートセーブとは別)"
	save_btn.pressed.connect(_on_save)
	foot.add_child(save_btn)
	load_btn = Button.new()
	load_btn.text = "  📂 ロード  "
	load_btn.tooltip_text = "セーブした世界に戻る(なければ今朝のオートセーブ)"
	load_btn.pressed.connect(_on_load)
	foot.add_child(load_btn)
	var btn := Button.new()
	btn.text = "  閉じる  "
	btn.pressed.connect(close)
	foot.add_child(btn)

func _on_save() -> void:
	if main.save_game():
		main.ui_toast("💾 世界を記録した", "build")
	else:
		main.ui_toast("💾 いまはセーブできない", "bad")
	close()

func _on_load() -> void:
	close()
	if not main.load_game():
		main.ui_toast("📂 セーブが見つからない", "bad")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		# Never open over the title screen or an ending; closing always works.
		if not is_open() and (main == null or not main.game_started or main.game_over):
			return
		toggle()
		get_viewport().set_input_as_handled()

func is_open() -> bool:
	return root.visible

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func open() -> void:
	_refresh()
	if save_btn:
		save_btn.disabled = main.game_over or not main.game_started
	if load_btn:
		load_btn.disabled = not main.has_any_save()
	root.visible = true
	main.clock.menu_pause()

func close() -> void:
	if not is_open():
		return
	root.visible = false
	main.clock.menu_resume()

const KIND_COLORS := {
	"prologue": "8b7fd9",
	"era": "d9b96a",
	"event": "e0a458",
	"policy": "7fc9c9",
	"cheat": "6fd98f",
}

func _refresh() -> void:
	var hist: Array = main.world.history
	var bb := ""
	if hist.is_empty():
		bb = "[color=9aa3b5]まだ何も記されていない。\n\n時代の岐路や大きな事件で神が示した導きが、\nここに刻まれていく。[/color]"
	else:
		for e in hist:
			var kind := str(e.get("kind", "event"))
			var col: String = KIND_COLORS.get(kind, "e0a458")
			bb += "[color=%s]◆ %d日目 — %s[/color]\n" % [
				col, int(e.get("day", 0)), str(e.get("title", ""))]
			var choice := str(e.get("choice", ""))
			if choice != "":
				bb += "[color=9aa3b5]　神の導き:[/color] %s\n" % choice
			var txt := str(e.get("text", ""))
			if txt != "":
				bb += "[color=b9c0d0]　%s[/color]\n" % txt
			bb += "\n"
	book.parse_bbcode(bb)
	# A chronicle reads oldest-first; keep the view at the latest entry.
	await get_tree().process_frame
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
