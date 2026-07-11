extends Node2D
# Speech bubble above a creature. Lifetime is denominated in game minutes,
# so bubbles freeze on pause and speed up with the clock.

const U = preload("res://scripts/util.gd")

var expire_at := 0.0

func setup(text: String, expire_abs_min: float) -> void:
	expire_at = expire_abs_min
	z_index = 50
	var label := U.make_label(text, 12, Color(0.12, 0.12, 0.14))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.96, 0.92, 0.95)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.35, 0.33, 0.3)
	sb.set_border_width_all(1)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	label.add_theme_stylebox_override("normal", sb)
	add_child(label)
	label.reset_size()
	label.position = Vector2(-label.size.x / 2.0, -60.0)

func expired(abs_min: float) -> bool:
	return abs_min >= expire_at
