extends CanvasLayer
# All HUD: top bar (era, clock, resources, speed), axis meter, right-side
# tabbed panel (village / person / chronicle / magic), toasts, era banner and
# the ending screen.

const U = preload("res://scripts/util.gd")

var main
var root: Control

var era_label: Label
var time_label: Label
var res_labels := {}   # resource key -> Label
var res_icon_chips := {}
var res_chip_nodes := {}  # resource key -> chip Control (for progressive disclosure)
var axis_panel: PanelContainer
var pop_label: Label
var speed_buttons: Array = []

var axis_bars := {}    # axis key -> ProgressBar
var axis_vals := {}    # axis key -> Label
var danger_rows := {}  # danger key -> HBoxContainer

var tab_buttons := {}
var tab_pages := {}
var current_tab := "village"

# village tab
var v_info: Label
var v_warn: Label
var v_buildings: RichTextLabel
var accept_btn: Button
var livestock_labels := {}
var livestock_plus := {}
var livestock_minus := {}
var wild_label: Label
# person tab
var p_name: Label
var p_action: Label
var p_bars := {}
# chronicle tab
var c_text: RichTextLabel
var chronicle_filter := "events"
var chronicle_filter_btns := {}
# magic tab
var m_training_label: Label
var m_training_bar: ProgressBar
var m_known: RichTextLabel

var toast_box: VBoxContainer
var banner_root: Control
var banner_title: Label
var banner_sub: Label
var help_overlay: Control
var ending_root: Control
var ending_art: TextureRect
var ending_title: Label
var ending_text: RichTextLabel
var ending_stats: RichTextLabel

var mission_panel: PanelContainer
var mission_title: Label
var mission_reward: Label

var _accum := 0.25

func build(m) -> void:
	main = m
	layer = 5
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = U.build_theme()
	add_child(root)
	_build_top_bar()
	_build_mission_panel()
	_build_axis_meter()
	_build_side_panel()
	_build_toasts()
	_build_banner()
	_build_ending()
	_build_help_overlay()

# --- construction helpers ----------------------------------------------------

func _chip(text: String, tip: String) -> Label:
	var l := U.make_label(text, 14)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l

func _resource_chip(key: String) -> Control:
	var tex := U.load_texture_file("res://assets/icons/icon_%s.png" % key)
	if tex == null:
		var fallback := _chip("", U.RES_NAMES[key])
		res_labels[key] = fallback
		res_icon_chips[key] = false
		return fallback
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	h.tooltip_text = U.RES_NAMES[key]
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(18, 18)
	icon.tooltip_text = U.RES_NAMES[key]
	h.add_child(icon)
	var label := U.make_label("0", 14)
	label.tooltip_text = U.RES_NAMES[key]
	h.add_child(label)
	res_labels[key] = label
	res_icon_chips[key] = true
	return h

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 8.0
	bar.offset_right = -8.0
	bar.offset_top = 6.0
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)

	era_label = U.make_label("", 15, U.COL["gold"])
	h.add_child(era_label)
	time_label = U.make_label("", 15)
	h.add_child(time_label)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp1)

	pop_label = _chip("👤 0", "人口")
	h.add_child(pop_label)
	for k in ["food", "wood", "stone", "metal", "mana", "knowledge"]:
		var chip := _resource_chip(k)
		res_chip_nodes[k] = chip
		h.add_child(chip)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp2)

	var help_btn := Button.new()
	help_btn.text = "?"
	help_btn.tooltip_text = "遊び方"
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.custom_minimum_size = Vector2(34, 0)
	help_btn.pressed.connect(_show_help)
	h.add_child(help_btn)

	var labels := ["⏸", "▶", "▶▶", "⏩"]
	var tips := ["一時停止 (Space)", "等速", "3倍速", "8倍速"]
	for i in range(labels.size()):
		var b := Button.new()
		b.text = labels[i]
		b.tooltip_text = tips[i]
		b.focus_mode = Control.FOCUS_NONE
		var idx := i
		b.pressed.connect(func(): main.clock.set_speed(idx))
		h.add_child(b)
		speed_buttons.append(b)

func _build_mission_panel() -> void:
	mission_panel = PanelContainer.new()
	mission_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mission_panel.offset_left = 8.0
	mission_panel.offset_top = 52.0
	mission_panel.offset_right = 328.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.09, 0.05, 0.92)
	sb.border_color = U.COL["gold"]
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	mission_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	mission_panel.add_child(v)
	v.add_child(U.make_label("📜 いまの目標", 12, U.COL["sub"]))
	mission_title = U.make_label("", 15, U.COL["gold"])
	mission_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(mission_title)
	mission_reward = U.make_label("", 12, U.COL["good"])
	mission_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(mission_reward)
	root.add_child(mission_panel)

func _build_axis_meter() -> void:
	var panel := PanelContainer.new()
	axis_panel = panel
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 8.0
	panel.offset_top = -170.0
	panel.offset_right = 250.0
	panel.offset_bottom = -8.0
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	v.add_child(U.make_label("文明のかたち", 12, U.COL["sub"]))
	for a in ["tech", "nature", "mystic"]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var nl := U.make_label(U.AXIS_NAMES[a], 12, U.COL[a])
		nl.custom_minimum_size = Vector2(34, 0)
		h.add_child(nl)
		var bar := U.make_bar(U.COL[a], 120.0)
		bar.max_value = 150.0
		axis_bars[a] = bar
		h.add_child(bar)
		var vl := U.make_label("0", 11, U.COL["sub"])
		vl.custom_minimum_size = Vector2(26, 0)
		axis_vals[a] = vl
		h.add_child(vl)
		v.add_child(h)
	for d in ["war", "blight"]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var nl := U.make_label(U.DANGER_NAMES[d], 12, U.COL["bad"])
		nl.custom_minimum_size = Vector2(34, 0)
		h.add_child(nl)
		var bar := U.make_bar(U.COL["bad"], 120.0)
		axis_bars[d] = bar
		h.add_child(bar)
		var vl := U.make_label("0", 11, U.COL["bad"])
		vl.custom_minimum_size = Vector2(26, 0)
		axis_vals[d] = vl
		h.add_child(vl)
		h.visible = false
		danger_rows[d] = h
		v.add_child(h)

func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -308.0
	panel.offset_right = -8.0
	panel.offset_top = 52.0
	panel.offset_bottom = -8.0
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	var tab_defs := [["village", "村"], ["person", "人"], ["chronicle", "記"], ["magic", "魔"]]
	for td in tab_defs:
		var b := Button.new()
		b.text = td[1]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key: String = td[0]
		b.pressed.connect(func(): set_tab(key))
		tabs.add_child(b)
		tab_buttons[key] = b

	var content := MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(content)

	# village tab
	var vt := VBoxContainer.new()
	vt.add_theme_constant_override("separation", 6)
	v_info = U.make_label("", 13)
	v_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vt.add_child(v_info)
	v_warn = U.make_label("", 13, U.COL["bad"])
	v_warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vt.add_child(v_warn)
	vt.add_child(HSeparator.new())
	vt.add_child(U.make_label("たてもの", 12, U.COL["sub"]))
	v_buildings = U.make_richtext(13)
	vt.add_child(v_buildings)
	vt.add_child(HSeparator.new())
	vt.add_child(U.make_label("くらしの管理", 12, U.COL["sub"]))
	accept_btn = Button.new()
	accept_btn.focus_mode = Control.FOCUS_NONE
	accept_btn.pressed.connect(func():
		main.world.accept_villagers = not main.world.accept_villagers
		_refresh_tab())
	vt.add_child(accept_btn)
	for kd in [["chicken", "にわとり"], ["goat", "やぎ"], ["cow", "うし"], ["sheep", "ひつじ"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var kind: String = kd[0]
		var nl := U.make_label("", 13)
		nl.custom_minimum_size = Vector2(110, 0)
		livestock_labels[kind] = nl
		row.add_child(nl)
		var plus := Button.new()
		plus.text = "＋"
		plus.tooltip_text = "家畜に迎える（食料10・家畜小屋が必要）"
		plus.focus_mode = Control.FOCUS_NONE
		plus.pressed.connect(func():
			main.add_livestock(kind)
			_refresh_tab())
		row.add_child(plus)
		livestock_plus[kind] = plus
		var minus := Button.new()
		minus.text = "－"
		minus.tooltip_text = "食料にする（食料+12）"
		minus.focus_mode = Control.FOCUS_NONE
		minus.pressed.connect(func():
			main.remove_livestock(kind)
			_refresh_tab())
		row.add_child(minus)
		livestock_minus[kind] = minus
		vt.add_child(row)
	wild_label = U.make_label("", 12, U.COL["sub"])
	vt.add_child(wild_label)
	content.add_child(vt)
	tab_pages["village"] = vt

	# person tab
	var pt := VBoxContainer.new()
	pt.add_theme_constant_override("separation", 6)
	p_name = U.make_label("", 17, U.COL["gold"])
	pt.add_child(p_name)
	p_action = U.make_label("", 13, U.COL["sub"])
	p_action.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pt.add_child(p_action)
	pt.add_child(HSeparator.new())
	var bar_defs := [["hunger", "おなか", U.COL["warn"]], ["energy", "元気", U.COL["good"]], ["mood", "機嫌", U.COL["gold"]]]
	for bd in bar_defs:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 6)
		var nl := U.make_label(bd[1], 12)
		nl.custom_minimum_size = Vector2(44, 0)
		h.add_child(nl)
		var bar := U.make_bar(bd[2], 130.0)
		p_bars[bd[0]] = bar
		h.add_child(bar)
		pt.add_child(h)
	pt.add_child(U.make_label("※ 村人をクリックすると様子が見られます", 11, U.COL["sub"]))
	content.add_child(pt)
	tab_pages["person"] = pt

	# chronicle tab
	var ct := VBoxContainer.new()
	var ct_head := HBoxContainer.new()
	ct_head.add_theme_constant_override("separation", 6)
	ct_head.add_child(U.make_label("村の年代記", 13, U.COL["gold"]))
	var ct_sp := Control.new()
	ct_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ct_sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ct_head.add_child(ct_sp)
	for fd in [["events", "出来事"], ["talk", "会話"], ["all", "全部"]]:
		var fb := Button.new()
		fb.text = fd[1]
		fb.focus_mode = Control.FOCUS_NONE
		var fkey: String = fd[0]
		fb.pressed.connect(func():
			chronicle_filter = fkey
			_refresh_tab())
		ct_head.add_child(fb)
		chronicle_filter_btns[fkey] = fb
	ct.add_child(ct_head)
	c_text = U.make_richtext(12)
	c_text.fit_content = false
	c_text.scroll_active = true
	c_text.scroll_following = false
	c_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ct.add_child(c_text)
	content.add_child(ct)
	tab_pages["chronicle"] = ct

	# magic tab
	var mt := VBoxContainer.new()
	mt.add_theme_constant_override("separation", 6)
	m_training_label = U.make_label("", 13)
	m_training_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mt.add_child(m_training_label)
	m_training_bar = U.make_bar(U.COL["mystic"], 200.0)
	mt.add_child(m_training_bar)
	mt.add_child(HSeparator.new())
	mt.add_child(U.make_label("覚えた魔法", 12, U.COL["sub"]))
	m_known = U.make_richtext(13)
	mt.add_child(m_known)
	content.add_child(mt)
	tab_pages["magic"] = mt

	set_tab("village")

func set_tab(key: String) -> void:
	current_tab = key
	for k in tab_pages:
		tab_pages[k].visible = (k == key)
		tab_buttons[k].modulate = Color(1.0, 0.95, 0.7) if k == key else Color(0.75, 0.78, 0.85)
	_refresh_tab()

func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toast_box.offset_left = -640.0
	toast_box.offset_right = -320.0
	toast_box.offset_top = 54.0
	toast_box.add_theme_constant_override("separation", 6)
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)

func toast(text: String, kind: String = "info") -> void:
	var colors := {"magic": U.COL["mystic"], "build": U.COL["good"], "bad": U.COL["bad"],
			"pop": Color("6fa8dc"), "info": U.COL["border"]}
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.16, 0.94)
	sb.set_corner_radius_all(8)
	sb.border_color = colors.get(kind, U.COL["border"])
	sb.set_border_width_all(1)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := U.make_label(text, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	toast_box.add_child(p)
	p.modulate.a = 0.0
	var tw := p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.6)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()

func _build_banner() -> void:
	banner_root = Control.new()
	banner_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_root.add_child(dim)
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_sub = U.make_label("", 16, U.COL["sub"])
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(banner_sub)
	banner_title = U.make_label("", 40, U.COL["gold"])
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(banner_title)
	banner_root.add_child(center)
	banner_root.visible = false
	root.add_child(banner_root)

func _build_help_overlay() -> void:
	help_overlay = Control.new()
	help_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	help_overlay.visible = false
	help_overlay.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_close_help())
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.84)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_overlay.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(650, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_overlay.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)
	var title := U.make_label("遊び方", 26, U.COL["gold"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(title)
	var lines := [
		"カメラ: 左ドラッグ=回転 / 右ドラッグ=移動 / ホイール=ズーム / Space=一時停止",
		"村人や動物をクリック=様子を見る",
		"毎朝アシタが祈る→選択肢で導く",
		"左上=いまの目標(ミッション)",
		"右パネル: 村=暮らし / 人=選択中の様子 / 記=年代記 / 魔=魔法と修行",
		"クリックで閉じる",
	]
	for i in range(lines.size()):
		var line := U.make_label(lines[i], 15 if i < lines.size() - 1 else 12, U.COL["text"] if i < lines.size() - 1 else U.COL["sub"])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(line)
	root.add_child(help_overlay)

func _show_help() -> void:
	help_overlay.visible = true
	help_overlay.modulate.a = 0.0
	var tw := help_overlay.create_tween()
	tw.tween_property(help_overlay, "modulate:a", 1.0, 0.16)

func _close_help() -> void:
	if help_overlay == null or not help_overlay.visible:
		return
	help_overlay.visible = false

func chapter_card(c: Dictionary, on_done := Callable()) -> void:
	# Full-screen chapter title card with its illustration, shown on era-up.
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.04, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var art := U.load_texture_file("res://assets/illustrations/%s.png" % c.get("art", ""))
	if art:
		var tr := TextureRect.new()
		tr.texture = art
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.modulate = Color(0.85, 0.85, 0.9)
		overlay.add_child(tr)
		var grad := ColorRect.new()
		grad.color = Color(0.02, 0.02, 0.06, 0.4)
		grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(grad)
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 10)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var no_l := U.make_label(str(c.get("no", "")), 18, U.COL["gold"])
	no_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(no_l)
	var title_l := U.make_label("『%s』" % c.get("title", ""), 46, U.COL["text"])
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title_l.add_theme_constant_override("outline_size", 8)
	center.add_child(title_l)
	var catch_l := U.make_label(str(c.get("catch", "")), 16, Color(0.95, 0.93, 0.85))
	catch_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	catch_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	catch_l.add_theme_constant_override("outline_size", 6)
	center.add_child(catch_l)
	overlay.add_child(center)
	root.add_child(overlay)
	overlay.modulate.a = 0.0
	var tw := overlay.create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.9)
	tw.tween_interval(3.4)
	tw.tween_property(overlay, "modulate:a", 0.0, 1.0)
	tw.tween_callback(overlay.queue_free)
	if on_done.is_valid():
		tw.tween_callback(on_done)

func era_banner(era: int, name: String) -> void:
	banner_sub.text = "第%dの時代" % (era + 1)
	banner_title.text = "「%s」" % name
	banner_root.visible = true
	banner_root.modulate.a = 0.0
	var tw := banner_root.create_tween()
	tw.tween_property(banner_root, "modulate:a", 1.0, 0.7)
	tw.tween_interval(2.4)
	tw.tween_property(banner_root, "modulate:a", 0.0, 0.9)
	tw.tween_callback(func(): banner_root.visible = false)

# --- title screen ---------------------------------------------------------

func show_title() -> void:
	var art := U.load_texture_file("res://assets/illustrations/title.png")
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 1.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	if art:
		var tr := TextureRect.new()
		tr.texture = art
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(tr)
		var grad := ColorRect.new()
		grad.color = Color(0.02, 0.02, 0.05, 0.35)
		grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(grad)
	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 18)
	var sub := U.make_label("― 神となり、祈りに応え、世界を育てよ ―", 16, U.COL["text"])
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := U.make_label("箱庭の神", 64, U.COL["gold"])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 10)
	center.add_child(title)
	center.add_child(sub)
	var start := Button.new()
	start.text = "　はじまりの朝へ　"
	start.focus_mode = Control.FOCUS_NONE
	start.pressed.connect(func():
		var tw := overlay.create_tween()
		tw.tween_property(overlay, "modulate:a", 0.0, 0.8)
		tw.tween_callback(overlay.queue_free)
		main.begin_after_title())
	center.add_child(start)
	overlay.add_child(center)
	root.add_child(overlay)
	main.clock.dialog_pause()

func _build_ending() -> void:
	ending_root = Control.new()
	ending_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.03, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ending_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	ending_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	ending_art = TextureRect.new()
	ending_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ending_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ending_art.custom_minimum_size = Vector2(588, 240)
	ending_art.clip_contents = true
	ending_art.visible = false
	v.add_child(ending_art)
	ending_title = U.make_label("", 32, U.COL["gold"])
	ending_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ending_title)
	ending_text = U.make_richtext(14)
	v.add_child(ending_text)
	v.add_child(HSeparator.new())
	ending_stats = U.make_richtext(13)
	v.add_child(ending_stats)
	var b := Button.new()
	b.text = "もう一度、最初の朝から"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): main.get_tree().reload_current_scene())
	v.add_child(b)
	ending_root.visible = false
	root.add_child(ending_root)

func show_ending(def: Dictionary, stats_bb: String) -> void:
	var art := U.load_texture_file("res://assets/illustrations/ending_%s.png" % def.get("id", ""))
	ending_art.visible = art != null
	if art:
		ending_art.texture = art
	ending_title.text = str(def.get("title", "終わり"))
	ending_text.text = str(def.get("text", ""))
	ending_stats.text = stats_bb
	ending_root.visible = true
	ending_root.modulate.a = 0.0
	var tw := ending_root.create_tween()
	tw.tween_property(ending_root, "modulate:a", 1.0, 1.2)

# --- refresh -------------------------------------------------------------------

func refresh(delta: float) -> void:
	_accum += delta
	if _accum < 0.25:
		return
	_accum = 0.0
	var w = main.world
	var c = main.clock
	era_label.text = "❖ %s" % w.era_name()
	time_label.text = U.fmt_time(c.day, c.minute_of_day)
	pop_label.text = "👤 %d" % w.pop()
	for k in res_labels:
		res_labels[k].text = str(int(w.res[k])) if res_icon_chips.get(k, false) else "%s %d" % [U.RES_ICONS[k], int(w.res[k])]
	for k in res_chip_nodes:
		if k == "food" or k == "wood":
			continue
		res_chip_nodes[k].visible = main.is_ui_unlocked(k)
	if mission_panel:
		var m: Dictionary = main.current_mission()
		mission_panel.visible = not m.is_empty()
		if not m.is_empty():
			mission_title.text = str(m.get("title", ""))
			mission_reward.text = "報酬: " + str(m.get("reward_text", ""))
	if axis_panel:
		axis_panel.visible = main.is_ui_unlocked("axes")
	if tab_buttons.has("magic"):
		var magic_open: bool = main.is_ui_unlocked("magic_tab")
		tab_buttons["magic"].visible = magic_open
		if not magic_open and current_tab == "magic":
			set_tab("village")
	for i in range(speed_buttons.size()):
		speed_buttons[i].modulate = Color(1.0, 0.9, 0.4) if c.speed_index == i else Color.WHITE
	for a in ["tech", "nature", "mystic"]:
		axis_bars[a].value = float(w.axes[a])
		axis_vals[a].text = str(int(w.axes[a]))
	for d in ["war", "blight"]:
		var v := float(w.danger[d])
		danger_rows[d].visible = v > 0.0
		axis_bars[d].value = v
		axis_vals[d].text = str(int(v))
	_refresh_tab()

func _refresh_tab() -> void:
	var w = main.world
	match current_tab:
		"village":
			v_info.text = "人口 %d人 / 住める数 %d人\n村のみんなの機嫌 %d\n食料のたくわえ %d日分" % [
				w.pop(), main.town.housing_capacity(), int(main.avg_mood()),
				int(float(w.res["food"]) / maxf(1.0, float(w.pop() * 3)))]
			var warn := ""
			if w.starvation_days > 0:
				warn += "⚠ 飢えが %d日 続いている\n" % w.starvation_days
			if float(w.danger["war"]) > 0.0:
				warn += "⚠ 戦の気配がする\n"
			if float(w.danger["blight"]) >= 40.0:
				warn += "⚠ 大地の魔力が淀んでいる\n"
			v_warn.text = warn
			v_warn.visible = warn != ""
			var bb := ""
			for line in main.town.building_summary():
				bb += "・%s\n" % line
			v_buildings.text = bb if bb != "" else "[color=#9aa3b5]まだ何もない[/color]"
			accept_btn.text = "旅人: 歓迎中（押すと停止）" if w.accept_villagers else "旅人: 受け入れ停止中（押すと再開）"
			var ac: Dictionary = main.animal_counts()
			var jp_names := {"chicken": "にわとり", "goat": "やぎ", "cow": "うし", "sheep": "ひつじ"}
			for kind in livestock_labels:
				livestock_labels[kind].text = "%s ×%d (+%.1f/日)" % [
					jp_names.get(kind, kind), int(ac.get(kind, 0)), main.livestock_daily_yield(kind)]
				livestock_plus[kind].disabled = not main.can_add_livestock()
				livestock_minus[kind].disabled = int(ac.get(kind, 0)) <= 0
			wild_label.text = "鹿×%d　犬×%d　うま×%d　ねこ×%d" % [
				int(ac.get("deer", 0)), int(ac.get("dog", 0)), int(ac.get("horse", 0)), int(ac.get("cat", 0))]
		"person":
			var a = main.selected_agent if main.selected_agent else main.protagonist
			if a == null or not is_instance_valid(a):
				a = main.protagonist
			if "kind" in a:
				var names := {"chicken": "にわとり", "goat": "やぎ", "cow": "うし",
						"sheep": "ひつじ", "horse": "うま", "cat": "ねこ", "deer": "鹿", "dog": "犬"}
				p_name.text = "🐾 " + str(names.get(a.kind, a.kind))
				var status := "元気にしている"
				if main.LIVESTOCK.has(a.kind):
					status = "エサをもらって元気" if a.fed else "おなかをすかせている"
					status += "　産出 +%.1f/日" % main.livestock_daily_yield(a.kind)
				elif a.kind == "dog":
					status = "アシタのそばが好き。村の癒やし"
				elif a.kind == "horse":
					status = "アシタを乗せて駆ける。移動と建設がはかどる"
				elif a.kind == "cat":
					status = "穀倉の番人。ねずみを寄せつけない"
				elif a.kind == "deer":
					status = "山でのんびり暮らしている"
				p_action.text = status
				for k in p_bars:
					p_bars[k].get_parent().visible = false
			else:
				for k in p_bars:
					p_bars[k].get_parent().visible = true
				p_name.text = ("✦ " if a == main.protagonist else "") + a.display_name
				p_action.text = a.action_text()
				p_bars["hunger"].value = a.needs["hunger"]
				p_bars["energy"].value = a.needs["energy"]
				p_bars["mood"].value = a.mood
		"chronicle":
			c_text.text = main.chronicle.to_bbcode(80, chronicle_filter)
			for fkey in chronicle_filter_btns:
				chronicle_filter_btns[fkey].modulate = \
					Color(1.0, 0.95, 0.7) if fkey == chronicle_filter else Color(0.75, 0.78, 0.85)
		"magic":
			var tp: Dictionary = main.protagonist.training_progress()
			if tp.is_empty():
				m_training_label.text = "いまは修行していない"
				m_training_bar.value = 0.0
			else:
				m_training_label.text = "修行中:「%s」" % tp["name"]
				m_training_bar.value = tp["ratio"] * 100.0
			var bb := ""
			for d in main.magic.known_defs():
				bb += "[color=#8b7fd9]✨ %s[/color]  [color=#9aa3b5]%s[/color]\n" % [d.get("name", "?"), d.get("desc", "")]
			m_known.text = bb if bb != "" else "[color=#9aa3b5]まだ何も覚えていない[/color]"
