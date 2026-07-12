extends SceneTree
# Renders all eight polyperfect animals in a row (walk clips playing) and
# saves animal_probe.png for visual inspection.
# Run: godot --path . --script tools/animal_probe.gd

const U = preload("res://scripts/util.gd")
const AnimalScript = preload("res://scripts/animal.gd")

const KINDS := ["chicken", "goat", "cow", "sheep", "horse", "dog", "cat", "deer"]

var frames := 0

func _init() -> void:
	var root3d := Node3D.new()
	get_root().add_child.call_deferred(root3d)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("87b06a")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	root3d.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.4
	root3d.add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 12)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color("6a9450")
	ground.material_override = gm
	root3d.add_child(ground)

	# 1m reference cube for size calibration.
	var ref := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 1.0, 0.3)
	ref.mesh = bm
	ref.position = Vector3(-10.4, 0.5, 0.0)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("d94c3d")
	ref.material_override = rm
	root3d.add_child(ref)

	var x := -8.4
	for kind in KINDS:
		var spec: Dictionary = AnimalScript.PP_MODELS.get(kind, {})
		var m := U.load_model(AnimalScript.PP_DIR + str(spec.get("file", "")))
		if m == null:
			print("%s: LOAD FAIL" % kind)
			x += 2.4
			continue
		if not U.fit_model_to_height_by_bones(m, float(spec.get("height", 1.0))) \
				and not U.fit_model_to_height(m, float(spec.get("height", 1.0))):
			print("%s: FIT FAIL" % kind)
			m.free()
			x += 2.4
			continue
		m.rotation.y = float(spec.get("yaw", 0.0))
		m.position.x += x
		root3d.add_child(m)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if spec.has("donor"):
			var g := U.graft_donor_anims(m, AnimalScript.PP_DIR + str(spec["donor"]))
			if g != null:
				aps = [g]
		if not aps.is_empty():
			var ap: AnimationPlayer = aps[0]
			var walk := str(spec.get("walk", ""))
			if walk != "" and ap.has_animation(walk):
				ap.play(walk)
				print("%s: playing %s" % [kind, walk])
		x += 2.4

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 2.6, 8.0)
	cam.rotation_degrees = Vector3(-13.0, 0.0, 0.0)
	cam.current = true
	root3d.add_child(cam)

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 30:
		var img := get_root().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://animal_probe.png"))
		print("ANIMAL_PROBE SAVED")
		quit(0)
	return false
