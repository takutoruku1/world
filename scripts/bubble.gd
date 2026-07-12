extends Node2D
# Speech bubble above a creature. Lifetime is denominated in game minutes.

const U = preload("res://scripts/util.gd")

var expire_at := 0.0
var visual: Node3D
var label: Label3D

func setup(text: String, expire_abs_min: float) -> void:
	expire_at = expire_abs_min
	var carrier = get_parent()
	if carrier == null or carrier.main == null:
		return
	visual = Node3D.new()
	visual.name = "Bubble"
	carrier.main.add_visual_node(visual)

	# No background quad: the old white box was oriented with look_at while
	# the text billboarded separately, so it drifted over the glyphs and read
	# as a white sticky note / diamond artifact (user-reported). Outlined text
	# alone stays readable on any ground color.
	label = Label3D.new()
	label.name = "BubbleText"
	label.text = "「" + text + "」"
	label.font = U.jp_font()
	label.font_size = 42
	label.pixel_size = 0.008
	label.modulate = Color(1.0, 0.98, 0.92)
	label.outline_modulate = Color(0.09, 0.09, 0.14, 0.92)
	label.outline_size = 9
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 5
	label.position = Vector3(0.0, -0.15, 0.02)
	visual.add_child(label)
	sync_visual()

func _exit_tree() -> void:
	if visual and is_instance_valid(visual):
		visual.queue_free()

func sync_visual() -> void:
	if visual == null:
		return
	var carrier = get_parent()
	if carrier == null or not carrier.has_method("bubble_anchor_world"):
		return
	visual.global_position = carrier.bubble_anchor_world()

func expired(abs_min: float) -> bool:
	return abs_min >= expire_at
