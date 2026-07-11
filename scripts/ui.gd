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
# person tab
var p_name: Label
var p_action: Label
var p_bars := {}
# chronicle tab
var c_text: RichTextLabel
# magic tab
var m_training_label: Label
var m_training_bar: ProgressBar
var m_known: RichTextLabel

var toast_box: VBoxContainer
var banner_root: Control
var banner_title: Label
var banner_sub: Label
var ending_root: Control
var ending_title: Label
var ending_text: RichTextLabel
var ending_stats: RichTextLabel

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
	_build_axis_meter()
	_build_side_panel()
	_build_toasts()
	_build_banner()
	_build_ending()

# --- construction helpers ----------------------------------------------------

func _chip(text: String, tip: String) -> Label:
	var l := U.make_label(text, 14)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l

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
		var l := _chip("", U.RES_NAMES[k])
		res_labels[k] = l
		h.add_child(l)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(sp2)

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

func _build_axis_meter() -> void:
	var panel := PanelContainer.new()
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
	ct.add_child(U.make_label("村の年代記", 13, U.COL["gold"]))
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
		res_labels[k].text = "%s %d" % [U.RES_ICONS[k], int(w.res[k])]
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
		"person":
			var a = main.selected_agent if main.selected_agent else main.protagonist
			p_name.text = ("✦ " if a == main.protagonist else "") + a.display_name
			p_action.text = a.action_text()
			p_bars["hunger"].value = a.needs["hunger"]
			p_bars["energy"].value = a.needs["energy"]
			p_bars["mood"].value = a.mood
		"chronicle":
			c_text.text = main.chronicle.to_bbcode()
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
