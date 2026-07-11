extends RefCounted
# Shared helpers: Japanese font, themed UI factory, palette, formatting.

const COL := {
	"bg": Color("14161f"),
	"panel": Color("1d2130"),
	"panel_light": Color("262b40"),
	"border": Color("3a4160"),
	"gold": Color("d9b96a"),
	"text": Color("e8e6df"),
	"sub": Color("9aa3b5"),
	"good": Color("7fc97f"),
	"warn": Color("e0a458"),
	"bad": Color("d96a6a"),
	"tech": Color("d97b4a"),
	"nature": Color("6fbf73"),
	"mystic": Color("8b7fd9"),
}

const RES_ICONS := {
	"food": "🌾", "wood": "🪵", "stone": "🪨",
	"metal": "⚙", "mana": "✨", "knowledge": "📖",
}
const RES_NAMES := {
	"food": "食料", "wood": "木材", "stone": "石材",
	"metal": "金属", "mana": "魔素", "knowledge": "知識",
}
const AXIS_NAMES := {"tech": "機械", "nature": "自然", "mystic": "神秘"}
const DANGER_NAMES := {"war": "戦禍", "blight": "荒廃"}

static var _jp_font: SystemFont = null
static var _theme: Theme = null

static func jp_font() -> SystemFont:
	if _jp_font == null:
		_jp_font = SystemFont.new()
		_jp_font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "MS Gothic"])
		var emoji := SystemFont.new()
		emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Segoe UI Symbol"])
		_jp_font.fallbacks = [emoji]
	return _jp_font

static func make_label(text: String, size: int = 14, color: Color = COL["text"]) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", jp_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func make_richtext(size: int = 13) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.add_theme_font_override("normal_font", jp_font())
	r.add_theme_font_override("bold_font", jp_font())
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", COL["text"])
	r.fit_content = true
	r.scroll_active = false
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r

static func _flat(bg: Color, border: Color = Color(0, 0, 0, 0), radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border.a > 0.0:
		sb.border_color = border
		sb.set_border_width_all(1)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	return sb

static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = jp_font()
	t.default_font_size = 14

	t.set_stylebox("panel", "PanelContainer", _flat(COL["panel"], COL["border"]))

	var bn := _flat(COL["panel_light"], COL["border"], 6)
	var bh := _flat(Color("323a58"), COL["gold"], 6)
	var bp := _flat(Color("11131c"), COL["gold"], 6)
	var bd := _flat(Color("191c28"), Color("2a2f45"), 6)
	t.set_stylebox("normal", "Button", bn)
	t.set_stylebox("hover", "Button", bh)
	t.set_stylebox("pressed", "Button", bp)
	t.set_stylebox("disabled", "Button", bd)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", COL["text"])
	t.set_color("font_hover_color", "Button", COL["gold"])
	t.set_color("font_pressed_color", "Button", COL["gold"])
	t.set_color("font_disabled_color", "Button", Color("5a6070"))

	var pb_bg := _flat(Color("11131c"), Color(0, 0, 0, 0), 4)
	pb_bg.content_margin_left = 2.0
	pb_bg.content_margin_right = 2.0
	pb_bg.content_margin_top = 2.0
	pb_bg.content_margin_bottom = 2.0
	var pb_fill := _flat(COL["gold"], Color(0, 0, 0, 0), 4)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)

	t.set_stylebox("separator", "HSeparator", _hsep())
	_theme = t
	return t

static func _hsep() -> StyleBoxLine:
	var s := StyleBoxLine.new()
	s.color = COL["border"]
	s.thickness = 1
	return s

static func make_bar(color: Color, width: float = 150.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.max_value = 100.0
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(width, 12)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := _flat(color, Color(0, 0, 0, 0), 4)
	pb.add_theme_stylebox_override("fill", fill)
	return pb

static func fmt_time(day: int, minute: float) -> String:
	return "%d日目 %02d:%02d" % [day, int(minute) / 60, int(minute) % 60]

static func fmt_clock(minute: float) -> String:
	return "%02d:%02d" % [int(minute) / 60, int(minute) % 60]

static func fmt_cost(cost: Dictionary) -> String:
	var parts: Array = []
	for k in cost:
		parts.append("%s%d" % [RES_ICONS.get(k, k), int(cost[k])])
	return " ".join(parts)
