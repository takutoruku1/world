extends Node2D
# Decorative 3D background: grass, river, forest, mountains and rocks.

const U = preload("res://scripts/util.gd")

const MAP := Rect2(0, 40, 980, 680)
const NATURE_MODEL_DIR := "res://assets/models/medieval/decoration/nature/"

var main
var visual: Node3D
var forest_spots: Array = []
var rock_spots: Array = []
var grass_spots: Array = []
var flower_patches: Array = []
var river_pts := PackedVector2Array()
var water_materials: Array = []
var monster_eye_pairs: Array = []
var cloud_nodes: Array = []

func setup(m) -> void:
	main = m
	river_pts = PackedVector2Array([
		Vector2(950, 40), Vector2(905, 190), Vector2(880, 340),
		Vector2(900, 490), Vector2(870, 720),
	])
	for i in range(26):
		forest_spots.append(Vector2(50 + randf() * 210, 80 + randf() * 230))
	for i in range(9):
		rock_spots.append(Vector2(60 + randf() * 160, 570 + randf() * 110))
	for i in range(50):
		grass_spots.append(Vector2(randf() * 960, 50 + randf() * 660))
	flower_patches = [
		Vector2(330, 170), Vector2(595, 135), Vector2(700, 315),
		Vector2(365, 545), Vector2(665, 585), Vector2(205, 420),
	]
	_build_visual()

func _exit_tree() -> void:
	if visual and is_instance_valid(visual):
		visual.queue_free()

# --- clearable wilderness ---------------------------------------------------
# The playfield starts covered in forest; placing a building fells the trees
# on its footprint (and grants wood), so the village is literally carved out.

var clearable_trees: Array = []  # [{pos: Vector2, node: Node3D}]

func build_wilderness() -> void:
	var start: Vector2 = main.protagonist.global_position
	for i in range(240):
		var p := Vector2(randf_range(60.0, 790.0), randf_range(70.0, 680.0))
		if p.distance_to(start) < 95.0:
			continue  # keep a small clearing where the hero begins
		if Rect2(40, 60, 250, 260).has_point(p):
			continue  # the mountain site
		if Rect2(730, 290, 150, 120).has_point(p):
			continue  # the riverbank site
		var tn := Node3D.new()
		tn.position = main.map_to_world(p, 0.0)
		visual.add_child(tn)
		_clearable_tree_visual(tn, 0.55 + randf() * 0.4)
		clearable_trees.append({"pos": p, "node": tn})

func _clearable_tree_visual(parent: Node3D, s: float) -> void:
	parent.rotation.y = randf() * TAU
	if _tree_model(parent, s):
		return
	var kind := randi() % 4
	var bark := Color("5f432b").lerp(Color("8a6340"), randf() * 0.45)
	var leaf := Color(0.18 + randf() * 0.08, 0.34 + randf() * 0.15, 0.15 + randf() * 0.08)
	match kind:
		0:
			_tree_cylinder(parent, "ClearTrunk", 0.09 * s, 0.065 * s, 0.72 * s, Vector3(0.0, 0.36 * s, 0.0), bark)
			_tree_sphere(parent, "ClearBroadCrown", 0.38 * s, Vector3(0.0, 0.98 * s, 0.0), leaf, Vector3(1.08, 0.86, 1.02))
			_tree_sphere(parent, "ClearBroadCrown", 0.23 * s, Vector3(-0.18 * s, 1.05 * s, 0.08 * s), leaf.lightened(0.08), Vector3(1.0, 0.82, 1.0))
			_tree_sphere(parent, "ClearBroadCrown", 0.22 * s, Vector3(0.2 * s, 0.92 * s, -0.05 * s), leaf.darkened(0.04), Vector3(0.95, 0.78, 0.95))
		1:
			_tree_cylinder(parent, "ClearTrunk", 0.075 * s, 0.055 * s, 0.9 * s, Vector3(0.0, 0.45 * s, 0.0), bark.darkened(0.06))
			for i in range(3):
				var layer_s := 1.0 - float(i) * 0.18
				_tree_cylinder(parent, "ClearPineLayer", 0.46 * s * layer_s, 0.05 * s, 0.72 * s, Vector3(0.0, (0.82 + float(i) * 0.34) * s, 0.0), leaf.darkened(float(i) * 0.035), 10, 0.05 * s)
		2:
			_tree_cylinder(parent, "ClearTallTrunk", 0.07 * s, 0.05 * s, 1.18 * s, Vector3(0.0, 0.59 * s, 0.0), bark)
			_tree_cylinder(parent, "ClearTallCrown", 0.34 * s, 0.04 * s, 0.9 * s, Vector3(0.0, 1.34 * s, 0.0), leaf.darkened(0.05), 11)
			_tree_cylinder(parent, "ClearTallTip", 0.2 * s, 0.02 * s, 0.48 * s, Vector3(0.0, 1.92 * s, 0.0), leaf.lightened(0.03), 9)
		_:
			_tree_cylinder(parent, "ClearTrunk", 0.085 * s, 0.065 * s, 0.78 * s, Vector3(0.0, 0.39 * s, 0.0), bark)
			_tree_sphere(parent, "ClearLowCrown", 0.34 * s, Vector3(-0.08 * s, 0.95 * s, 0.02 * s), leaf.lightened(0.06), Vector3(1.15, 0.72, 1.0))
			_tree_cylinder(parent, "ClearYoungPine", 0.27 * s, 0.03 * s, 0.68 * s, Vector3(0.18 * s, 1.04 * s, -0.08 * s), leaf.darkened(0.08), 9)

func _tree_cylinder(parent: Node3D, n: String, bottom_radius: float, top_radius: float, height: float, pos: Vector3, c: Color, segments := 8, cap_top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius if cap_top_radius < 0.0 else cap_top_radius
	mesh.height = height
	mesh.radial_segments = segments
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(c, false, "tex_bark" if n.to_lower().contains("trunk") else "tex_leaves")
	parent.add_child(mi)
	return mi

func _tree_sphere(parent: Node3D, n: String, radius: float, pos: Vector3, c: Color, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	mi.material_override = _mat(c, false, "tex_leaves")
	parent.add_child(mi)
	return mi

func clear_trees_rect(r: Rect2) -> int:
	var cleared := 0
	for t in clearable_trees.duplicate():
		if r.grow(6.0).has_point(t["pos"]):
			if is_instance_valid(t["node"]):
				t["node"].queue_free()
			clearable_trees.erase(t)
			cleared += 1
	return cleared

func _process(delta: float) -> void:
	for mat in water_materials:
		if is_instance_valid(mat):
			mat.uv1_offset += Vector3(delta * 0.028, delta * 0.011, 0.0)
	_update_clouds(delta)
	_update_monster_eyes(delta)

func _build_visual() -> void:
	water_materials.clear()
	visual = Node3D.new()
	visual.name = "TerrainVisual"
	main.add_visual_node(visual)
	_build_outer_world()
	_build_clouds()

	var ground := PlaneMesh.new()
	ground.size = main.map_size_to_world(MAP.size)
	var ground_i := MeshInstance3D.new()
	ground_i.name = "Grassland"
	ground_i.mesh = ground
	ground_i.position = main.map_to_world(MAP.position + MAP.size / 2.0, -0.03)
	ground_i.material_override = _mat(Color("7a925d"), false, "tex_grass", Vector3(15.0, 15.0, 1.0))
	visual.add_child(ground_i)

	for i in range(flower_patches.size()):
		var p: Vector2 = flower_patches[i]
		var patch_size := Vector2(70.0 + float(i % 3) * 18.0, 42.0 + float(i % 2) * 14.0)
		var patch := _ground_patch("FlowerPatch", p, patch_size, 0.006 + float(i) * 0.0007, Color("8ea767"), "tex_flowers", Vector3(1.45, 1.05, 1.0))
		patch.rotation.y = -0.35 + float(i % 5) * 0.18

	for p in grass_spots:
		var s := 0.08 + fmod(p.x, 4.0) * 0.012
		_box("GrassTuft", Vector3(s, 0.08, s * 0.32), main.map_to_world(p, 0.04), Color("4f7b3c"), false, "tex_leaves")

	for i in range(river_pts.size() - 1):
		_river_sand_segment(river_pts[i], river_pts[i + 1])
		_river_segment(river_pts[i], river_pts[i + 1], 2.35, Color("244861"), 0.0)
		_river_segment(river_pts[i], river_pts[i + 1], 1.15, Color(0.30, 0.54, 0.69, 0.86), 0.035, true)
		_river_segment(river_pts[i], river_pts[i + 1], 0.28, Color(0.72, 0.9, 0.98, 0.38), 0.075, true)
	_build_river_decor()

	var peaks := [Vector2(60, 104), Vector2(150, 94), Vector2(240, 106)]
	for i in range(peaks.size()):
		_mountain(peaks[i], 4.2 + float(i % 2) * 0.55, 6.4 + float(i % 2) * 0.9)

	for p in forest_spots:
		_tree(p, 0.65 + randf() * 0.2)
	for p in rock_spots:
		_rock(p)

func _build_outer_world() -> void:
	var map_world: Vector2 = main.map_size_to_world(MAP.size)
	var outer_size: float = maxf(map_world.x, map_world.y) * 12.0
	var outer := PlaneMesh.new()
	outer.size = Vector2(outer_size, outer_size)
	var outer_i := MeshInstance3D.new()
	outer_i.name = "OuterGrassland"
	outer_i.mesh = outer
	outer_i.position = main.map_to_world(MAP.position + MAP.size / 2.0, -0.08)
	outer_i.material_override = _mat(Color("70895a"), false, "tex_grass", Vector3(108.0, 108.0, 1.0))
	visual.add_child(outer_i)
	_build_horizon_mountains(outer_i.position)
	_build_monster_eyes()

func _build_horizon_mountains(center: Vector3) -> void:
	for i in range(14):
		var a := TAU * float(i) / 14.0 + (0.1 if i % 2 == 0 else -0.06)
		var ring_radius := 150.0 + float(i % 4) * 13.0
		var radius := 10.0 + float(i % 5) * 1.7
		var height := 18.0 + float((i * 7) % 9) * 1.8
		var base := center + Vector3(cos(a) * ring_radius, height * 0.5 - 0.08, sin(a) * ring_radius)
		if i % 2 == 0:
			var hill_paths := ["hills_A.gltf", "hills_B_trees.gltf", "hills_C_trees.gltf"]
			var hill_path: String = NATURE_MODEL_DIR + hill_paths[int(i / 2) % hill_paths.size()]
			var hill_pos := center + Vector3(cos(a) * ring_radius, -0.08, sin(a) * ring_radius)
			if _place_world_model(hill_path, hill_pos, Vector2(radius * 3.0, radius * 1.8), 0.92, height * 0.48, -a * 0.2):
				continue
		var mountain := _cone_shell("HorizonMountain", radius, height, base, Color("5d6658"), 8, "tex_rock", Vector3(3.2, 3.2, 1.0))
		mountain.rotation.y = -a * 0.2
		if i % 3 == 0:
			_cone_shell("HorizonPeak", radius * 0.26, height * 0.18, base + Vector3(0.0, height * 0.4, 0.0), Color("cfd7d4"), 8)

func _build_monster_eyes() -> void:
	monster_eye_pairs.clear()
	var spots := [Vector2(18, 118), Vector2(300, 42), Vector2(930, 118), Vector2(965, 610), Vector2(74, 700)]
	for i in range(spots.size()):
		var root := Node3D.new()
		root.name = "MonsterEyes"
		root.position = main.map_to_world(spots[i], 0.72 + float(i % 2) * 0.12)
		root.rotation.y = randf_range(-0.45, 0.45)
		root.visible = false
		visual.add_child(root)
		for x in [-0.07, 0.07]:
			var mesh := SphereMesh.new()
			mesh.radius = 0.04
			mesh.height = 0.08
			mesh.radial_segments = 8
			mesh.rings = 4
			var eye := MeshInstance3D.new()
			eye.name = "Eye"
			eye.mesh = mesh
			eye.position = Vector3(x, 0.0, 0.0)
			eye.material_override = _mat(Color(1.0, 0.08, 0.04, 0.85), true)
			root.add_child(eye)
		monster_eye_pairs.append({"node": root, "base_y": root.position.y, "phase": randf() * TAU})

func _build_clouds() -> void:
	cloud_nodes.clear()
	for i in range(4):
		var root := Node3D.new()
		root.name = "KayKitCloud"
		root.position = Vector3(-54.0 + float(i) * 34.0, 18.0 + float(i % 2) * 2.4, -42.0 + float((i * 17) % 5) * 9.0)
		root.rotation.y = -0.25 + float(i) * 0.18
		visual.add_child(root)
		var path := NATURE_MODEL_DIR + ("cloud_big.gltf" if i % 2 == 0 else "cloud_small.gltf")
		var model := U.load_model(path)
		if model != null and U.fit_model_to_footprint(model, Vector2(7.5 + float(i % 2) * 1.6, 3.4), 0.95, 2.4):
			model.name = "CloudModel"
			root.add_child(model)
		else:
			if model != null:
				model.free()
			_cloud_fallback(root, 1.0 + float(i % 2) * 0.18)
		cloud_nodes.append({"node": root, "speed": 0.14 + float(i) * 0.035, "min_x": -64.0, "max_x": 64.0})

func _update_clouds(delta: float) -> void:
	for c in cloud_nodes:
		var root: Node3D = c["node"]
		if not is_instance_valid(root):
			continue
		root.position.x += float(c["speed"]) * delta
		if root.position.x > float(c["max_x"]):
			root.position.x = float(c["min_x"])

func _cloud_fallback(parent: Node3D, s: float) -> void:
	for i in range(4):
		var mesh := SphereMesh.new()
		mesh.radius = (0.45 + float(i % 2) * 0.18) * s
		mesh.height = mesh.radius * 1.1
		mesh.radial_segments = 12
		mesh.rings = 6
		var mi := MeshInstance3D.new()
		mi.name = "CloudBlob"
		mi.mesh = mesh
		mi.position = Vector3(-1.0 + float(i) * 0.62, sin(float(i)) * 0.12, 0.0)
		mi.scale = Vector3(1.45, 0.48, 0.75)
		mi.material_override = _mat(Color(0.92, 0.94, 0.92, 0.78), false)
		parent.add_child(mi)

func _update_monster_eyes(delta: float) -> void:
	if main == null or main.clock == null:
		return
	var m: float = main.clock.minute_of_day
	var night := m >= 1320.0 or m < 240.0
	for pair in monster_eye_pairs:
		var root: Node3D = pair["node"]
		if not is_instance_valid(root):
			continue
		root.visible = night
		if not night:
			continue
		pair["phase"] = float(pair["phase"]) + delta * 1.4
		root.position.y = float(pair["base_y"]) + sin(float(pair["phase"])) * 0.06
		var pulse := 0.85 + (sin(float(pair["phase"]) * 2.1) * 0.5 + 0.5) * 0.35
		root.scale = Vector3.ONE * pulse

func _mat(color: Color, emission := false, texture_id := "", uv_scale := Vector3.ZERO) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.86
	m.metallic = 0.0
	m.metallic_specular = 0.16
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if texture_id != "":
		var tex := U.load_texture_file("res://assets/textures/%s.png" % texture_id)
		if tex:
			m.albedo_texture = tex
			m.uv1_scale = uv_scale if uv_scale != Vector3.ZERO else Vector3(2.0, 2.0, 1.0)
		match texture_id:
			"tex_water":
				m.albedo_color = Color(color.r, color.g, color.b, minf(color.a, 0.82))
				m.roughness = 0.28
				m.metallic_specular = 0.62
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.emission_enabled = true
				m.emission = Color("66b8d4")
				m.emission_energy_multiplier = 0.08 if not emission else 0.2
			"tex_rock", "tex_stone":
				m.roughness = 0.92
				m.metallic_specular = 0.11
			"tex_bark", "tex_wood":
				m.roughness = 0.76
				m.metallic_specular = 0.2
			"tex_leaves", "tex_grass":
				m.roughness = 0.88
				m.metallic_specular = 0.08
			"tex_flowers":
				m.roughness = 0.9
				m.metallic_specular = 0.06
			"tex_sand":
				m.roughness = 0.95
				m.metallic_specular = 0.04
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.35
	return m

func _box(n: String, size: Vector3, pos: Vector3, color: Color, emission := false, texture_id := "", uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, emission, texture_id, uv_scale)
	visual.add_child(mi)
	return mi

func _ground_patch(n: String, center_map: Vector2, size_map: Vector2, y: float, color: Color, texture_id: String, uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var patch_world_size: Vector2 = main.map_size_to_world(size_map)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 18
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var r0 := 0.82 + sin(float(i) * 1.7) * 0.11
		var r1 := 0.82 + sin(float(i + 1) * 1.7) * 0.11
		var v0 := Vector3(cos(a0) * patch_world_size.x * 0.5 * r0, 0.0, sin(a0) * patch_world_size.y * 0.5 * r0)
		var v1 := Vector3(cos(a1) * patch_world_size.x * 0.5 * r1, 0.0, sin(a1) * patch_world_size.y * 0.5 * r1)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(0.5 + v1.x / patch_world_size.x, 0.5 + v1.z / patch_world_size.y))
		st.add_vertex(v1)
		st.set_uv(Vector2(0.5 + v0.x / patch_world_size.x, 0.5 + v0.z / patch_world_size.y))
		st.add_vertex(v0)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = st.commit()
	mi.position = main.map_to_world(center_map, y)
	mi.material_override = _mat(color, false, texture_id, uv_scale)
	visual.add_child(mi)
	return mi

func _cylinder(n: String, radius: float, height: float, pos: Vector3, color: Color, segments := 12, top_radius := -1.0, texture_id := "", uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, false, texture_id, uv_scale)
	visual.add_child(mi)
	return mi

func _sphere(n: String, radius: float, pos: Vector3, color: Color, scale := Vector3.ONE, texture_id := "", uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	mi.material_override = _mat(color, false, texture_id, uv_scale)
	visual.add_child(mi)
	return mi

func _cone_shell(n: String, radius: float, height: float, pos: Vector3, color: Color, segments := 10, texture_id := "", uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.0, height * 0.5, 0.0)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		st.set_uv(Vector2(float(i) / float(segments), 1.0))
		st.add_vertex(Vector3(cos(a0) * radius, -height * 0.5, sin(a0) * radius))
		st.set_uv(Vector2((float(i) + 0.5) / float(segments), 0.0))
		st.add_vertex(tip)
		st.set_uv(Vector2(float(i + 1) / float(segments), 1.0))
		st.add_vertex(Vector3(cos(a1) * radius, -height * 0.5, sin(a1) * radius))
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = st.commit()
	mi.position = pos
	mi.material_override = _mat(color, false, texture_id, uv_scale)
	visual.add_child(mi)
	return mi

func _river_segment(a: Vector2, b: Vector2, width: float, color: Color, y: float, emission := false) -> void:
	var aw: Vector3 = main.map_to_world(a, y)
	var bw: Vector3 = main.map_to_world(b, y)
	var d: Vector3 = bw - aw
	var len := Vector2(d.x, d.z).length()
	var mi := _box("River", Vector3(width, 0.045, len + width * 0.5), (aw + bw) * 0.5, color)
	mi.rotation.y = atan2(d.x, d.z)
	var mat := _mat(color, emission, "tex_water", Vector3(0.9, maxf(1.0, len * 0.55), 1.0))
	mi.material_override = mat
	water_materials.append(mat)

func _river_sand_segment(a: Vector2, b: Vector2) -> void:
	var aw: Vector3 = main.map_to_world(a, -0.012)
	var bw: Vector3 = main.map_to_world(b, -0.012)
	var d: Vector3 = bw - aw
	var len := Vector2(d.x, d.z).length()
	var mi := _box("RiverSand", Vector3(3.15, 0.035, len + 1.05), (aw + bw) * 0.5, Color("b7a06d"), false, "tex_sand", Vector3(1.0, maxf(1.0, len * 0.42), 1.0))
	mi.rotation.y = atan2(d.x, d.z)

func _build_river_decor() -> void:
	var bridge_mid := river_pts[2].lerp(river_pts[3], 0.48)
	var bridge_dir := river_pts[3] - river_pts[2]
	_place_world_model(
		"res://assets/models/medieval/buildings/neutral/building_bridge_A.gltf",
		main.map_to_world(bridge_mid, 0.11),
		Vector2(5.6, 2.1),
		0.96,
		1.1,
		atan2(bridge_dir.x, bridge_dir.y) + PI * 0.5)
	var decor := [
		["waterlily_A.gltf", Vector2(928, 94), 0.54, 0.16],
		["waterplant_A.gltf", Vector2(914, 152), 0.5, 0.38],
		["waterlily_B.gltf", Vector2(894, 226), 0.54, 0.16],
		["waterplant_B.gltf", Vector2(874, 296), 0.48, 0.42],
		["waterplant_C.gltf", Vector2(898, 365), 0.5, 0.44],
		["waterlily_A.gltf", Vector2(872, 428), 0.5, 0.16],
		["waterplant_A.gltf", Vector2(920, 490), 0.48, 0.38],
		["waterlily_B.gltf", Vector2(886, 548), 0.52, 0.16],
		["waterplant_B.gltf", Vector2(856, 620), 0.48, 0.42],
		["waterplant_C.gltf", Vector2(878, 686), 0.5, 0.44],
	]
	for i in range(decor.size()):
		var d: Array = decor[i]
		var path: String = NATURE_MODEL_DIR + str(d[0])
		var pos: Vector2 = d[1]
		_place_world_model(path, main.map_to_world(pos, 0.08), Vector2(float(d[2]), float(d[2])), 0.96, float(d[3]), float(i) * 0.73)

func _mountain(p: Vector2, radius: float, height: float) -> void:
	var path := NATURE_MODEL_DIR + "mountain_A_grass_trees.gltf"
	if _place_world_model(path, main.map_to_world(p, -0.02), Vector2(radius * 2.15, radius * 2.15), 0.95, height, -0.18 + randf() * 0.36):
		return
	var base: Vector3 = main.map_to_world(p, height * 0.5)
	_cone_shell("Mountain", radius, height, base, Color("7a7770"), 9, "tex_rock", Vector3(1.8, 1.8, 1.0))
	_cone_shell("SnowCap", radius * 0.32, height * 0.2, base + Vector3(0.0, height * 0.4, 0.0), Color("edf2f5"), 9)

func _tree(p: Vector2, s: float) -> void:
	var wp: Vector3 = main.map_to_world(p)
	var root := Node3D.new()
	root.name = "KayKitTree"
	root.position = wp
	root.rotation.y = randf() * TAU
	visual.add_child(root)
	if _tree_model(root, s):
		return
	root.queue_free()
	_cylinder("TreeTrunk", 0.09 * s, 0.72 * s, wp + Vector3(0.0, 0.36 * s, 0.0), Color("7a563a"), 8, -1.0, "tex_bark")
	_cylinder("TreeTop", 0.48 * s, 1.0 * s, wp + Vector3(0.0, 1.05 * s, 0.0), Color("4f7b3c"), 10, 0.08 * s, "tex_leaves")
	_sphere("TreeLight", 0.25 * s, wp + Vector3(-0.12 * s, 1.18 * s, -0.05 * s), Color("6b9449"), Vector3(1.0, 0.78, 1.0), "tex_leaves")

func _tree_model(parent: Node3D, s: float) -> bool:
	var paths := [
		"tree_single_A.gltf",
		"tree_single_B.gltf",
		"trees_A_small.gltf",
		"trees_B_small.gltf",
		"trees_A_medium.gltf",
		"trees_B_medium.gltf",
	]
	var model := U.load_model(NATURE_MODEL_DIR + paths[randi() % paths.size()])
	if model == null:
		return false
	model.name = "TreeModel"
	if not U.fit_model_to_footprint(model, Vector2(0.74 * s, 0.74 * s), 0.95, 2.2 * s):
		model.free()
		return false
	parent.add_child(model)
	return true

func _place_world_model(path: String, pos: Vector3, footprint: Vector2, margin := 0.86, max_height := 0.0, rot_y := 0.0) -> bool:
	var model := U.load_model(path)
	if model == null:
		return false
	if not U.fit_model_to_footprint(model, footprint, margin, max_height):
		model.free()
		return false
	model.name = "KayKitModel"
	model.position += pos
	model.rotation.y += rot_y
	visual.add_child(model)
	return true

func _rock(p: Vector2) -> void:
	var wp: Vector3 = main.map_to_world(p, 0.16)
	_sphere("Rock", 0.35, wp, Color("77766e"), Vector3(1.2, 0.55, 0.82), "tex_rock")
	_sphere("RockFacet", 0.21, wp + Vector3(-0.13, 0.12, -0.09), Color("8a8880"), Vector3(1.0, 0.55, 0.8), "tex_rock")
