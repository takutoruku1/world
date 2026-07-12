extends Node2D
# Animals are flavor: deer graze in the forest, livestock wander near their
# pen, and the dog follows the hero around. Visuals come from the purchased
# polyperfect Low Poly Animated Animals pack (procedural shapes as fallback).

const U = preload("res://scripts/util.gd")

const PP_DIR := "res://assets/models/polyperfect/"
# Clip names probed from the converted GLBs (tools/pp_probe.gd). Heights are
# bone-fit calibration targets (tools/animal_probe.gd), not exact meters.
const PP_MODELS := {
	"chicken": {"file": "SKM_Hen_Animations.glb", "height": 0.42, "yaw": 0.0,
		"idle": "Hen_Idle Breathing", "walk": "Hen_Walk", "eat": "Hen_Eat"},
	"goat": {"file": "SKM_Goat_Animation.glb", "height": 0.72, "yaw": 0.0,
		"idle": "Idle", "walk": "Walk", "eat": "Eating"},
	"cow": {"file": "SKM_Cow_Animations.glb", "height": 0.68, "yaw": 0.0,
		"idle": "Idle1", "walk": "Walk", "eat": "Eat"},
	"sheep": {"file": "SKM_Sheep_Wool_Animations.glb", "height": 0.85, "yaw": 0.0,
		"idle": "Sheep_Sheep_Idle", "walk": "Sheep_Sheep_Walk", "eat": "Sheep_Sheep_Eat"},
	"horse": {"file": "SKM_Horse_Rig.glb", "donor": "SKM_Horse_Animations.glb",
		"height": 2.3, "yaw": 0.0, "idle": "Idle", "walk": "Walk", "eat": "Eating"},
	"dog": {"file": "SKM_Dog_GoldenRetriever_Rig.glb", "height": 0.6, "yaw": 0.0},
	"cat": {"file": "SKM_Cat_Rig.glb", "donor": "SKM_Cat_Animations.glb",
		"height": 0.38, "yaw": 0.0, "idle": "Cat_Idle", "walk": "Cat_Walk"},
	"deer": {"file": "SKM_Deer_Animations.glb", "height": 1.1, "yaw": 0.0,
		"idle": "deer_idle breath", "walk": "deer_walk", "eat": "deer_idle 2"},
}

var main
var kind := "deer"
var fed := true  # livestock: whether it got its feed this morning
var home_center := Vector2.ZERO
var radius := 80.0
var target := Vector2.ZERO
var idle_t := 0.0
var speed := 8.0
var visual: Node3D
var model: Node3D
var model_anim: AnimationPlayer
var model_spec: Dictionary = {}
var _cur_anim := ""
var _last_pos := Vector2.ZERO
var _bob_phase := 0.0

func setup(k: String, center: Vector2, m) -> void:
	main = m
	kind = k
	home_center = center
	global_position = center + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	target = global_position
	match kind:
		"dog":
			speed = 26.0
		"horse":
			speed = 14.0
		"cat":
			speed = 13.0
		_:
			speed = 8.0
	_build_visual()
	_sync_visual()

func sim_tick(gmin: float, _ctx: Dictionary) -> void:
	if kind == "dog" and main.protagonist:
		var goal: Vector2 = main.protagonist.global_position + Vector2(18, 10)
		target = goal
		if global_position.distance_to(goal) > 46.0:
			global_position = global_position.move_toward(goal, speed * gmin)
		_sync_visual(gmin)
		return
	idle_t -= gmin
	if idle_t <= 0.0:
		idle_t = 60.0 + randf() * 150.0
		target = home_center + Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
	global_position = global_position.move_toward(target, speed * gmin)
	_sync_visual(gmin)

func _exit_tree() -> void:
	if visual and is_instance_valid(visual):
		visual.queue_free()

func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Animal_" + kind
	main.add_visual_node(visual)
	if _build_pp_model():
		return
	match kind:
		"dog":
			_build_dog()
		"chicken":
			_build_chicken()
		"goat":
			_build_goat()
		"cow":
			_build_cow()
		"sheep":
			_build_sheep()
		"horse":
			_build_horse()
		"cat":
			_build_cat()
		_:
			_build_deer()

func _build_pp_model() -> bool:
	model_spec = PP_MODELS.get(kind, {})
	if model_spec.is_empty():
		return false
	var m := U.load_model(PP_DIR + str(model_spec["file"]))
	if m == null:
		return false
	if not U.fit_model_to_height_by_bones(m, float(model_spec["height"])) \
			and not U.fit_model_to_height(m, float(model_spec["height"])):
		m.free()
		return false
	# No atlas override: ufbx preserves the pack's per-material flat colors,
	# and the COL/Gradient atlases don't match these SKM rigs' UVs (probed).
	m.rotation.y = float(model_spec.get("yaw", 0.0))
	visual.add_child(m)
	model = m
	_bob_phase = randf() * TAU
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if model_spec.has("donor"):
		# The rig file may carry a lone bind-pose take — the donor GLB owns
		# the real clips, so it always wins.
		var grafted := U.graft_donor_anims(m, PP_DIR + str(model_spec["donor"]))
		if grafted != null:
			aps = [grafted]
	if not aps.is_empty():
		model_anim = aps[0]
		for anim_name in model_anim.get_animation_list():
			model_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		_play_model_anim("idle")
	return true

func _play_model_anim(key: String) -> void:
	if model_anim == null:
		return
	var anim_name := str(model_spec.get(key, ""))
	if anim_name == "" or anim_name == _cur_anim or not model_anim.has_animation(anim_name):
		return
	_cur_anim = anim_name
	model_anim.play(anim_name, 0.3)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m

func _capsule(n: String, radius: float, height: float, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 5
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(c)
	visual.add_child(mi)
	return mi

func _sphere(n: String, radius: float, pos: Vector3, c: Color, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	mi.material_override = _mat(c)
	visual.add_child(mi)
	return mi

func _cylinder(n: String, radius: float, height: float, pos: Vector3, c: Color, rot := Vector3.ZERO, top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 7
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(c)
	visual.add_child(mi)
	return mi

func _box(n: String, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(c)
	visual.add_child(mi)
	return mi

func _build_deer() -> void:
	var fur := Color("a06b3f")
	_capsule("DeerBody", 0.18, 0.8, Vector3(0.0, 0.48, 0.0), fur, Vector3(0.0, 0.0, PI * 0.5))
	_sphere("DeerHead", 0.16, Vector3(0.42, 0.63, -0.02), fur.lightened(0.08), Vector3(1.0, 0.85, 0.9))
	for x in [-0.22, 0.22]:
		for z in [-0.13, 0.13]:
			_cylinder("DeerLeg", 0.035, 0.42, Vector3(x, 0.22, z), Color("6d452a"))
	for z in [-0.08, 0.08]:
		var horn := _cylinder("Antler", 0.018, 0.32, Vector3(0.52, 0.86, z), Color("d8c7a0"), Vector3(0.5, 0.0, 0.25))
		horn.rotation.z += z * 2.0

func _build_dog() -> void:
	var fur := Color("8a5a35")
	_capsule("DogBody", 0.16, 0.65, Vector3(0.0, 0.36, 0.0), fur, Vector3(0.0, 0.0, PI * 0.5))
	_sphere("DogHead", 0.16, Vector3(0.36, 0.45, 0.0), fur.lightened(0.12), Vector3(1.0, 0.9, 0.9))
	_cylinder("DogTail", 0.025, 0.35, Vector3(-0.38, 0.48, 0.0), fur.lightened(0.1), Vector3(0.0, 0.0, -0.9))
	for x in [-0.2, 0.2]:
		for z in [-0.11, 0.11]:
			_cylinder("DogLeg", 0.03, 0.28, Vector3(x, 0.16, z), Color("5b3924"))

func _build_chicken() -> void:
	_sphere("ChickenBody", 0.18, Vector3(0.0, 0.27, 0.0), Color("f0ead8"), Vector3(1.05, 1.0, 0.9))
	_sphere("ChickenHead", 0.12, Vector3(0.18, 0.43, 0.0), Color("f7f1df"))
	_cylinder("Beak", 0.05, 0.15, Vector3(0.3, 0.43, 0.0), Color("e6a23c"), Vector3(0.0, 0.0, PI * 0.5), 0.0)
	_sphere("Comb", 0.055, Vector3(0.18, 0.55, 0.0), Color("d94c3d"), Vector3(0.8, 1.0, 0.55))
	for z in [-0.05, 0.05]:
		_cylinder("ChickenLeg", 0.018, 0.18, Vector3(0.0, 0.12, z), Color("d8a24a"))

func _build_goat() -> void:
	var fur := Color("d8d0bd")
	_capsule("GoatBody", 0.18, 0.72, Vector3(0.0, 0.43, 0.0), fur, Vector3(0.0, 0.0, PI * 0.5))
	_sphere("GoatHead", 0.15, Vector3(0.4, 0.54, 0.0), fur.lightened(0.05), Vector3(1.0, 0.85, 0.9))
	for z in [-0.07, 0.07]:
		_cylinder("GoatHorn", 0.023, 0.28, Vector3(0.48, 0.75, z), Color("6d604d"), Vector3(0.62, 0.0, 0.35))
	for x in [-0.2, 0.2]:
		for z in [-0.11, 0.11]:
			_cylinder("GoatLeg", 0.03, 0.33, Vector3(x, 0.18, z), Color("7b7262"))
	_cylinder("GoatBeard", 0.02, 0.22, Vector3(0.52, 0.38, 0.0), Color("eee8d8"))

func _build_cow() -> void:
	var hide := Color("efe9df")
	var dark := Color("2f2a27")
	_capsule("CowBody", 0.26, 1.0, Vector3(0.0, 0.56, 0.0), hide, Vector3(0.0, 0.0, PI * 0.5))
	_sphere("CowPatch", 0.18, Vector3(-0.18, 0.67, 0.13), dark, Vector3(1.25, 0.62, 0.72))
	_sphere("CowPatch", 0.14, Vector3(0.22, 0.59, -0.15), dark, Vector3(1.05, 0.62, 0.7))
	_sphere("CowPatch", 0.1, Vector3(0.02, 0.78, -0.2), dark.lightened(0.08), Vector3(0.9, 0.55, 0.55))
	_sphere("CowHead", 0.19, Vector3(0.55, 0.66, 0.0), hide, Vector3(1.05, 0.9, 0.9))
	_sphere("CowNose", 0.1, Vector3(0.68, 0.58, 0.0), Color("d8a8a0"), Vector3(1.0, 0.7, 1.0))
	_sphere("CowFacePatch", 0.08, Vector3(0.54, 0.71, -0.08), dark, Vector3(0.75, 0.65, 0.55))
	for z in [-0.14, 0.14]:
		_sphere("CowEar", 0.06, Vector3(0.5, 0.73, z), hide.darkened(0.08), Vector3(0.55, 0.85, 1.0))
	for z in [-0.09, 0.09]:
		_cylinder("CowHorn", 0.02, 0.16, Vector3(0.58, 0.85, z), Color("d8c7a0"), Vector3(0.4, 0.0, z * 3.0))
	for x in [-0.28, 0.28]:
		for z in [-0.14, 0.14]:
			_cylinder("CowLeg", 0.045, 0.42, Vector3(x, 0.22, z), Color("cfc7ba"))
			_box("CowHoof", Vector3(0.09, 0.045, 0.08), Vector3(x, 0.03, z), dark)
	_cylinder("CowTail", 0.02, 0.42, Vector3(-0.52, 0.58, 0.02), dark, Vector3(0.0, 0.0, -0.85))
	_sphere("CowTailTip", 0.045, Vector3(-0.68, 0.38, 0.02), dark, Vector3(0.7, 1.0, 0.7))
	_sphere("Udder", 0.08, Vector3(-0.08, 0.31, 0.0), Color("d8a8a0"), Vector3(1.2, 0.65, 0.9))

func _build_sheep() -> void:
	var wool := Color("f2eee2")
	var face := Color("4a4038")
	_sphere("SheepWool", 0.26, Vector3(0.0, 0.46, 0.0), wool, Vector3(1.28, 1.0, 1.05))
	for i in range(7):
		var x := -0.24 + float(i % 4) * 0.16
		var z := -0.12 + float(i / 4) * 0.24
		_sphere("SheepWoolBlob", 0.105, Vector3(x, 0.62 + sin(float(i)) * 0.035, z), wool.lightened(0.04 if i % 2 == 0 else 0.0), Vector3(1.0, 0.85, 1.0))
	_sphere("SheepWoolTop", 0.15, Vector3(0.12, 0.69, 0.0), Color("f7f4ea"), Vector3(1.05, 0.85, 1.0))
	_sphere("SheepHead", 0.12, Vector3(0.39, 0.5, 0.0), face, Vector3(1.05, 0.9, 0.85))
	for z in [-0.08, 0.08]:
		_sphere("SheepEar", 0.045, Vector3(0.36, 0.54, z), face.darkened(0.05), Vector3(0.52, 0.8, 1.0))
	for x in [-0.16, 0.16]:
		for z in [-0.1, 0.1]:
			_cylinder("SheepLeg", 0.03, 0.28, Vector3(x, 0.14, z), face)
			_box("SheepHoof", Vector3(0.065, 0.035, 0.06), Vector3(x, 0.025, z), face.darkened(0.18))
	_sphere("SheepTail", 0.065, Vector3(-0.32, 0.47, 0.0), wool, Vector3(0.75, 0.85, 0.75))

func _build_horse() -> void:
	var coat := Color("7a4f2c")
	var dark := Color("322417")
	_capsule("HorseBody", 0.22, 1.05, Vector3(0.0, 0.72, 0.0), coat, Vector3(0.0, 0.0, PI * 0.5))
	var neck := _capsule("HorseNeck", 0.11, 0.5, Vector3(0.45, 0.98, 0.0), coat, Vector3(0.0, 0.0, 0.7))
	neck.rotation.z = 0.8
	_sphere("HorseHead", 0.13, Vector3(0.66, 1.18, 0.0), coat.lightened(0.06), Vector3(1.35, 0.8, 0.8))
	_sphere("HorseMuzzle", 0.07, Vector3(0.79, 1.14, 0.0), coat.lightened(0.18), Vector3(1.25, 0.62, 0.72))
	for z in [-0.07, 0.07]:
		_cylinder("HorseEar", 0.026, 0.16, Vector3(0.61, 1.32, z), coat.darkened(0.08), Vector3(0.45, 0.0, z * 4.0), 0.0)
	for i in range(4):
		_sphere("HorseMane", 0.055, Vector3(0.37 + float(i) * 0.07, 1.16 - float(i) * 0.08, 0.0), dark, Vector3(0.85, 1.1, 0.55))
	_cylinder("HorseTailBase", 0.038, 0.38, Vector3(-0.55, 0.66, 0.0), dark, Vector3(0.0, 0.0, -0.5))
	_sphere("HorseTailFan", 0.09, Vector3(-0.68, 0.47, 0.0), dark, Vector3(0.7, 1.45, 0.65))
	for x in [-0.32, 0.32]:
		for z in [-0.12, 0.12]:
			_cylinder("HorseLeg", 0.04, 0.6, Vector3(x, 0.3, z), coat.darkened(0.2))
			_box("HorseHoof", Vector3(0.085, 0.045, 0.075), Vector3(x, 0.03, z), dark)

func _build_cat() -> void:
	var fur := Color("c99a54")
	var stripe := fur.darkened(0.28)
	_capsule("CatBody", 0.09, 0.36, Vector3(0.0, 0.16, 0.0), fur, Vector3(0.0, 0.0, PI * 0.5))
	_sphere("CatHead", 0.09, Vector3(0.2, 0.24, 0.0), fur.lightened(0.08))
	for z in [-0.045, 0.045]:
		_cylinder("CatEar", 0.025, 0.09, Vector3(0.22, 0.34, z), fur.darkened(0.15), Vector3(0.0, 0.0, 0.0), 0.0)
		_sphere("CatEye", 0.014, Vector3(0.27, 0.255, z * 0.55), Color("223322"), Vector3(1.0, 0.7, 0.45))
	for x in [-0.06, 0.04, 0.14]:
		_box("CatStripe", Vector3(0.025, 0.025, 0.2), Vector3(x, 0.26, 0.0), stripe, Vector3(0.0, 0.0, 0.35))
	for z in [-0.055, 0.055]:
		_cylinder("CatWhisker", 0.006, 0.16, Vector3(0.29, 0.235, z), Color("f0e4cf"), Vector3(PI * 0.5, 0.0, PI * 0.5))
	var tail_a := _cylinder("CatTail", 0.018, 0.24, Vector3(-0.18, 0.24, 0.0), fur.darkened(0.08), Vector3(0.0, 0.0, -1.0))
	tail_a.rotation.z = -1.05
	var tail_b := _cylinder("CatTailTip", 0.016, 0.2, Vector3(-0.31, 0.34, 0.0), fur.darkened(0.12), Vector3(0.0, 0.0, -0.35))
	tail_b.rotation.z = -0.32
	for x in [-0.1, 0.1]:
		for z in [-0.045, 0.045]:
			_cylinder("CatLeg", 0.014, 0.14, Vector3(x, 0.08, z), fur.darkened(0.04))

func _sync_visual(gmin := 0.0) -> void:
	if visual == null:
		return
	visual.position = main.map_to_world(global_position, 0.0)
	var moving := global_position.distance_to(_last_pos) > 0.05
	_last_pos = global_position
	var dir := target - global_position
	if dir.length() > 0.1 and moving:
		visual.rotation.y = atan2(dir.x, dir.y)
	if model_anim != null:
		if moving:
			_play_model_anim("walk")
		elif model_spec.has("eat"):
			_play_model_anim("eat")  # grazing while stopped reads naturally
		else:
			_play_model_anim("idle")
	elif model != null:
		# Animation-less models (the dog rig): a light procedural trot-bob.
		_bob_phase += gmin * 0.9
		if moving:
			model.position.y = absf(sin(_bob_phase * 4.0)) * 0.05
			model.rotation.z = sin(_bob_phase * 8.0) * 0.05
		else:
			model.position.y = 0.0
			model.rotation.z = 0.0
