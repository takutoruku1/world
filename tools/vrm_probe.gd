extends SceneTree
# Close-up render probe for VRM loading: verifies the model loads through
# U.load_model, prints mesh stats, and saves a close-up screenshot.
# Run: godot --path . --script tools/vrm_probe.gd

const U = preload("res://scripts/util.gd")

func _init() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.1, 2.2)
	root3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.85, 0.0))
	cam.current = true

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	root3d.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 1.2
	env.environment = e
	root3d.add_child(env)

	var model := U.load_model("res://assets/models/vroid/sample_godette.vrm")
	if model == null:
		print("VRM_PROBE: LOAD FAILED")
		quit(1)
		return
	var fitted := U.fit_model_to_height(model, 1.42)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	print("VRM_PROBE: loaded fitted=%s meshes=%d anim_players=%d aabb=%s" % [
		str(fitted), meshes.size(), anims.size(), str(U.model_aabb(model))])
	root3d.add_child(model)
	if not anims.is_empty():
		var ap := anims[0] as AnimationPlayer
		print("VRM_PROBE: autoplay='%s' anims=%s" % [ap.autoplay, str(ap.get_animation_list())])
	_model = model
	call_deferred("_capture")

var _model: Node3D = null

func _relax(model: Node3D) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0]
	for side in [["LeftUpperArm", "J_Bip_L_UpperArm", 1.0], ["RightUpperArm", "J_Bip_R_UpperArm", 1.0]]:
		var bi: int = skel.find_bone(str(side[0]))
		if bi < 0:
			bi = skel.find_bone(str(side[1]))
		if bi >= 0:
			var pose := skel.get_bone_pose_rotation(bi)
			skel.set_bone_pose_rotation(bi,
				pose * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(62.0 * float(side[2]))))
	print("VRM_PROBE: A-pose applied localX L+ R-")

func _capture() -> void:
	await process_frame
	_relax(_model)
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://vrm_probe.png"))
	print("VRM_PROBE: saved vrm_probe.png")
	U.clear_model_cache()
	quit(0)
