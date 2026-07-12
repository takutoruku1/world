extends SceneTree
# Probe for the Modular RPG Hero (Dungeon Mason) pipeline: loads the base
# mesh, lists its parts/materials, merges an animation GLB, applies the
# PolyArt texture, and renders a close-up.
# Run: godot --path . --script tools/hero_probe.gd

const U = preload("res://scripts/util.gd")
const BASE := "res://assets/models/dmason/hero/mesh/CharacterBaseMesh.glb"
const ANIM := "res://assets/models/dmason/hero/anim/Sleep_noWeapon.glb"

func _init() -> void:
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.1, 2.4)
	root3d.add_child(cam)
	cam.look_at(Vector3(0.0, 0.9, 0.0))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	root3d.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.75, 0.55)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	e.ambient_light_energy = 1.1
	env.environment = e
	root3d.add_child(env)

	var model := U.load_model(BASE)
	if model == null:
		print("HERO_PROBE: BASE LOAD FAILED")
		quit(1)
		return
	# Villager-look try-on: everything hidden except this set.
	var visible_parts := ["Face1", "Hair3", "Cloth1", "Shoe1", "Belt1"]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = U.load_texture_file("res://assets/models/dmason/hero/texture/PolyArt.png")
	mat.roughness = 1.0
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	print("HERO_PROBE: meshes=%d" % meshes.size())
	for m in meshes:
		var mi := m as MeshInstance3D
		mi.visible = mi.name in visible_parts
		if mi.visible:
			mi.material_override = mat
			print("HERO_PROBE: shown [%s]" % mi.name)

	# Animation merge test: pull the animation out of the Idle GLB, attach it
	# to the base model, and advance it — if bones resolve, the render will
	# show a relaxed idle pose instead of a T-pose.
	var anim_scene := U.load_model(ANIM)
	if anim_scene != null:
		var aps := anim_scene.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var src: AnimationPlayer = aps[0]
			var names := src.get_animation_list()
			if names.size() > 0:
				var anim := src.get_animation(names[0]).duplicate()
				print("HERO_PROBE: track0 path=%s" % str(anim.track_get_path(0)))
				var lib := AnimationLibrary.new()
				lib.add_animation("Idle", anim)
				var ap := AnimationPlayer.new()
				model.add_child(ap)
				ap.add_animation_library("", lib)
				ap.play("Idle")
				ap.advance(3.0)
				print("HERO_PROBE: Idle playing=%s" % str(ap.current_animation))
		anim_scene.free()

	U.fit_model_to_height(model, 1.6)
	root3d.add_child(model)
	call_deferred("_capture")

func _capture() -> void:
	await process_frame
	await process_frame
	await process_frame
	RenderingServer.force_draw()
	var img := get_root().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://vrm_probe.png"))
	print("HERO_PROBE: saved vrm_probe.png")
	U.clear_model_cache()
	quit(0)
