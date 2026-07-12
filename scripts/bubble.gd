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

	var bg_mesh := BoxMesh.new()
	var width := clampf(0.65 + float(text.length()) * 0.12, 1.4, 5.2)
	bg_mesh.size = Vector3(width, 0.5, 0.035)
	var bg := MeshInstance3D.new()
	bg.name = "BubbleBack"
	bg.mesh = bg_mesh
	bg.position = Vector3(0.0, 0.0, -0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.96, 0.9, 0.94)
	mat.roughness = 0.75
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg.material_override = mat
	visual.add_child(bg)

	label = Label3D.new()
	label.name = "BubbleText"
	label.text = text
	label.font = U.jp_font()
	label.font_size = 42
	label.pixel_size = 0.008
	label.modulate = Color("22222a")
	label.outline_modulate = Color(1.0, 1.0, 1.0, 0.9)
	label.outline_size = 3
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
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
	if carrier.main and carrier.main.camera:
		visual.look_at(carrier.main.camera.global_position, Vector3.UP)

func expired(abs_min: float) -> bool:
	return abs_min >= expire_at
