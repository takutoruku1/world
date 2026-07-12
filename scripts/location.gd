extends Node2D
# One site on the map. Simulation remains 2D; this node owns only its 3D facade.

const U = preload("res://scripts/util.gd")

const PROP_MODEL_DIR := "res://assets/models/medieval/decoration/props/"
const PROP_MODELS := [
	"barrel.gltf", "bucket_empty.gltf", "bucket_water.gltf", "crate_A_big.gltf",
	"crate_A_small.gltf", "crate_B_big.gltf", "crate_B_small.gltf", "crate_long_A.gltf",
	"crate_long_B.gltf", "crate_long_C.gltf", "crate_open.gltf", "ladder.gltf",
	"pallet.gltf", "resource_lumber.gltf", "resource_stone.gltf", "sack.gltf",
	"target.gltf", "tent.gltf", "weaponrack.gltf", "wheelbarrow.gltf",
]
const SYNTY_KNIGHTS_MODEL_DIR := "res://assets/models/synty/PolygonKnights/Models/"
const SYNTY_KNIGHTS_ATLAS := "res://assets/models/synty/PolygonKnights/Textures/PolygonKnights_01.png"
const SYNTY_PROP_MODELS := [
	"SM_Prop_Banner_01.glb", "SM_Prop_Banner_02.glb", "SM_Prop_Banner_03.glb",
	"SM_Wep_Broadsword_01.glb", "SM_Wep_Halberd_01.glb", "SM_Wep_Shield_01.glb",
	"SM_Wep_Shield_02.glb", "SM_Prop_Brazier_01.glb", "SM_Prop_Crate_01.glb",
]

var main
var id: String = ""
var type_id: String = ""
var display_name: String = ""
var color := Color("777777")
var size_v := Vector2(96, 68)
var tags: Array = []
var slots: int = 0
var production: Dictionary = {}
var capacity: int = 0
var under_construction := false
var progress := 0.0
var def: Dictionary = {}
var stand_points: Array = []
var visual: Node3D
var name_label: Label3D
var progress_fill: MeshInstance3D
var progress_block: MeshInstance3D
var construction_stage_root: Node3D
var construction_stage_idx := -1
var model_palette := ""

func setup_site(d: Dictionary, m = null) -> void:
	main = m
	id = str(d.get("id", ""))
	type_id = str(d.get("type", id))
	display_name = str(d.get("name", id))
	color = Color(str(d.get("color", "#777777")))
	var pos: Array = d.get("pos", [400, 300])
	position = Vector2(pos[0], pos[1])
	var sz: Array = d.get("size", [96, 68])
	size_v = Vector2(sz[0], sz[1])
	tags = d.get("tags", [])
	slots = int(d.get("slots", 0))
	production = d.get("production", {})
	capacity = int(d.get("capacity", 0))
	model_palette = str(d.get("model_palette", ""))
	_finish_common()

func setup_construction(pdef: Dictionary, inst_id: String, pos: Vector2, m = null) -> void:
	main = m
	def = pdef
	id = inst_id
	type_id = str(pdef.get("id", ""))
	display_name = str(pdef.get("name", type_id))
	color = Color(str(pdef.get("color", "#8a815f")))
	position = pos
	var sz: Array = pdef.get("size", [96, 68])
	size_v = Vector2(sz[0], sz[1])
	under_construction = true
	progress = 0.0
	model_palette = _current_kaykit_palette()
	_finish_common()

func activate() -> void:
	under_construction = false
	progress = 1.0
	slots = int(def.get("slots", 0))
	production = def.get("production", {})
	capacity = int(def.get("capacity", 0))
	tags = def.get("tags", [])
	_rebuild_visual()

func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	_sync_construction_progress()
	if name_label:
		name_label.text = _label_text()

func _finish_common() -> void:
	stand_points.clear()
	if type_id == "forest":
		for i in range(6):
			stand_points.append(Vector2(
				lerpf(size_v.x * 0.18, size_v.x * 0.82, float(i % 3) / 2.0),
				lerpf(size_v.y * 0.64, size_v.y * 0.86, float(i / 3))))
	else:
		for i in range(6):
			stand_points.append(Vector2(
				randf_range(12.0, maxf(13.0, size_v.x - 12.0)),
				randf_range(20.0, maxf(21.0, size_v.y - 8.0))))
	_rebuild_visual()

func _exit_tree() -> void:
	if visual and is_instance_valid(visual):
		visual.queue_free()

func _label_text() -> String:
	return display_name + ("(建設中 %d%%)" % int(progress * 100.0) if under_construction else "")

func stand_global(i: int = -1) -> Vector2:
	if stand_points.is_empty():
		return position + size_v / 2.0
	var idx := i if i >= 0 else randi() % stand_points.size()
	return position + stand_points[idx % stand_points.size()]

func center() -> Vector2:
	return position + size_v / 2.0

func _rebuild_visual() -> void:
	if main == null:
		return
	if visual and is_instance_valid(visual):
		visual.queue_free()
	visual = Node3D.new()
	visual.name = "Visual_" + id
	visual.position = main.map_to_world(center(), 0.0)
	main.add_visual_node(visual)
	progress_fill = null
	progress_block = null
	construction_stage_root = null
	construction_stage_idx = -1

	var fp: Vector2 = main.map_size_to_world(size_v)
	if under_construction:
		_build_construction(fp)
	else:
		match type_id:
			"shrine":
				_build_shrine(fp)
			"prayer_rock":
				_build_prayer_rock(fp)
			"camp":
				_build_camp(fp)
			"plaza":
				_build_plaza(fp)
			"hut":
				_build_hut(fp)
			"forest":
				_build_forest_site(fp)
			"riverbank":
				_build_riverbank(fp)
			"farm":
				_build_farm(fp)
			"woodcamp":
				_build_woodcamp(fp)
			"well":
				_build_well(fp)
			"granary":
				_build_granary(fp)
			"school":
				_build_school(fp)
			"pen":
				_build_pen(fp)
			"quarry":
				_build_quarry(fp)
			"forge":
				_build_forge(fp)
			"grove":
				_build_grove(fp)
			"mage_tower":
				_build_mage_tower(fp)
			"market":
				_build_market(fp)
			"wall":
				_build_wall(fp)
			"tower":
				_build_tower(fp)
			"stable":
				_build_stable(fp)
			"clinic":
				_build_clinic(fp)
			"great_engine":
				_build_great_engine(fp)
			"world_tree":
				_build_world_tree(fp)
			"grand_circle":
				_build_grand_circle(fp)
			_:
				_build_simple_building(fp)
	if not under_construction:
		_build_village_props(fp)
	_build_label(_label_height())

func _build_label(height: float) -> void:
	name_label = Label3D.new()
	name_label.name = "NameLabel"
	name_label.text = _label_text()
	name_label.font = U.jp_font()
	name_label.font_size = 56
	name_label.pixel_size = 0.02
	name_label.fixed_size = false
	name_label.modulate = Color("fff1c7")
	name_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.92)
	name_label.outline_size = 10
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.position = Vector3(0.0, height, 0.0)
	visual.add_child(name_label)

func _label_height() -> float:
	if under_construction:
		return 2.2
	match type_id:
		"world_tree":
			return 6.4
		"mage_tower":
			return 5.1
		"tower":
			return 4.5
		"castle":
			return 4.6
		"great_engine":
			return 3.6
		"grand_circle":
			return 3.6
		"forest":
			return 5.4
		"camp":
			return 1.7
		"prayer_rock":
			return 1.9
	return 3.15

func _wooden_type() -> bool:
	return ["hut", "forest", "woodcamp", "granary", "school", "pen", "grove", "market", "world_tree"].has(type_id)

func _stone_type() -> bool:
	return ["shrine", "plaza", "well", "quarry", "forge", "mage_tower", "wall", "clinic", "great_engine", "grand_circle"].has(type_id)

func _roof_texture() -> String:
	if ["hut", "well", "granary", "pen", "market"].has(type_id):
		return "tex_thatch"
	return "tex_roof_tile"

func _texture_for_part(part: String) -> String:
	var p := part.to_lower()
	if p.contains("progress") or p.contains("light") or p.contains("glow") or p.contains("rune") or p.contains("cross") or p.contains("orb") or p.contains("core"):
		return ""
	if p.contains("water"):
		return "tex_water"
	if p.contains("cloth") or p.contains("awning"):
		return "tex_cloth"
	if p.contains("metal") or p.contains("engine") or p.contains("chimney"):
		return "tex_metal"
	if p.contains("plaster"):
		return "tex_plaster"
	if p.contains("cobble") or p.contains("plaza"):
		return "tex_cobble"
	if p.contains("gravel"):
		return "tex_gravel"
	if p.contains("sand"):
		return "tex_sand"
	if p.contains("crop"):
		return "tex_crops"
	if p.contains("flower"):
		return "tex_flowers"
	if p.contains("mossstone"):
		return "tex_moss_stone"
	if p.contains("darkplank"):
		return "tex_dark_planks"
	if p.contains("roof"):
		return _roof_texture()
	if p.contains("soil") or p.contains("dirt") or p.contains("camp") or p.contains("ground"):
		return "tex_soil" if ["farm", "woodcamp", "pen", "market"].has(type_id) else "tex_grass"
	if p.contains("moss") or p.contains("mound") or p.contains("edge"):
		return "tex_grass"
	if p.contains("trunk") or p.contains("log"):
		return "tex_bark"
	if p.contains("crown") or p.contains("seedling"):
		return "tex_leaves"
	if p.contains("rock") or p.contains("pit"):
		return "tex_rock"
	if p.contains("stone") or p.contains("wall") or p.contains("tower") or p.contains("circle") or (p.contains("base") and _stone_type()) or (p.contains("body") and _stone_type()):
		return "tex_stone"
	if p.contains("post") or p.contains("rail") or p.contains("dock") or p.contains("plank") or p.contains("door") or p.contains("stall") or p.contains("shed") or p.contains("sign") or p.contains("trim") or (p.contains("body") and _wooden_type()):
		return "tex_wood"
	return ""

func _mat(c: Color, emission := false, texture_id := "", uv_scale := Vector3.ZERO) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.82
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
				m.albedo_color = Color(c.r, c.g, c.b, minf(c.a, 0.82))
				m.roughness = 0.24
				m.metallic_specular = 0.68
				m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				m.emission_enabled = true
				m.emission = Color("66b8d4")
				m.emission_energy_multiplier = 0.12 if not emission else 0.28
			"tex_stone", "tex_rock":
				m.roughness = 0.9
				m.metallic_specular = 0.12
			"tex_wood", "tex_bark":
				m.roughness = 0.74
				m.metallic_specular = 0.2
			"tex_thatch":
				m.roughness = 0.94
				m.metallic_specular = 0.04
			"tex_roof_tile":
				m.roughness = 0.86
				m.metallic_specular = 0.1
			"tex_grass", "tex_leaves", "tex_soil":
				m.roughness = 0.9
				m.metallic_specular = 0.08
			"tex_crops", "tex_flowers":
				m.roughness = 0.92
				m.metallic_specular = 0.06
			"tex_plaster", "tex_cloth":
				m.roughness = 0.88
				m.metallic_specular = 0.08
			"tex_cobble", "tex_gravel", "tex_moss_stone", "tex_sand":
				m.roughness = 0.93
				m.metallic_specular = 0.08
			"tex_dark_planks":
				m.roughness = 0.78
				m.metallic_specular = 0.16
			"tex_metal":
				m.roughness = 0.46
				m.metallic = 0.62
				m.metallic_specular = 0.86
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.8
	return m

func _synty_palette_tint() -> Color:
	match _kaykit_palette():
		"red":
			return Color("ffd0c2")
		"green":
			return Color("d6f2cf")
		"blue":
			return Color("d5ddff")
	return Color("fff0c0")

func _synty_material(tint := Color.WHITE, texture_path := SYNTY_KNIGHTS_ATLAS) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = U.load_texture_file(texture_path)
	m.albedo_color = tint
	m.roughness = 1.0
	m.metallic_specular = 0.1
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _apply_synty_material(model: Node3D, tint := Color.WHITE, texture_path := SYNTY_KNIGHTS_ATLAS) -> void:
	var mat := _synty_material(tint, texture_path)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat

func _box(n: String, size: Vector3, pos: Vector3, c: Color, emission := false, texture_id := "", uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	var tex := texture_id if texture_id != "" else _texture_for_part(n)
	mi.material_override = _mat(c, emission, tex, uv_scale)
	visual.add_child(mi)
	return mi

func _cylinder(n: String, radius: float, height: float, pos: Vector3, c: Color, segments := 14, top_radius := -1.0, emission := false, texture_id := "", uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	var tex := texture_id if texture_id != "" else _texture_for_part(n)
	mi.material_override = _mat(c, emission, tex, uv_scale)
	visual.add_child(mi)
	return mi

func _sphere(n: String, radius: float, pos: Vector3, c: Color, scale := Vector3.ONE, emission := false, texture_id := "", uv_scale := Vector3.ZERO) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	var tex := texture_id if texture_id != "" else _texture_for_part(n)
	mi.material_override = _mat(c, emission, tex, uv_scale)
	visual.add_child(mi)
	return mi

func _gable_roof(n: String, sx: float, sz: float, y: float, h: float, c: Color, offset := Vector3.ZERO, texture_id := "", uv_scale := Vector3.ZERO) -> void:
	var o := 0.22
	var lx := -sx * 0.5 - o
	var rx := sx * 0.5 + o
	var fz := -sz * 0.5 - o
	var bz := sz * 0.5 + o
	var ridge_f := Vector3(0.0, y + h, fz)
	var ridge_b := Vector3(0.0, y + h, bz)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_tri(st, Vector3(lx, y, fz) + offset, ridge_f + offset, ridge_b + offset)
	_tri(st, Vector3(lx, y, fz) + offset, ridge_b + offset, Vector3(lx, y, bz) + offset)
	_tri(st, ridge_f + offset, Vector3(rx, y, fz) + offset, Vector3(rx, y, bz) + offset)
	_tri(st, ridge_f + offset, Vector3(rx, y, bz) + offset, ridge_b + offset)
	_tri(st, Vector3(lx, y, fz) + offset, Vector3(rx, y, fz) + offset, ridge_f + offset)
	_tri(st, Vector3(rx, y, bz) + offset, Vector3(lx, y, bz) + offset, ridge_b + offset)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = st.commit()
	var tex := texture_id if texture_id != "" else _texture_for_part(n)
	mi.material_override = _mat(c, false, tex, uv_scale)
	visual.add_child(mi)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_uv(Vector2(a.x, a.z))
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z))
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z))
	st.add_vertex(c)

func _build_construction(fp: Vector2) -> void:
	_box("ConstructionGround", Vector3(fp.x, 0.12, fp.y), Vector3(0.0, 0.06, 0.0), Color("3b3329"), false, "tex_gravel", Vector3(1.6, 1.2, 1.0))
	if not _build_construction_stage(fp):
		progress_block = _box("ConstructionMass", Vector3(fp.x * 0.58, 0.2, fp.y * 0.58), Vector3(0.0, 0.22, 0.0), color.darkened(0.28))
		_scaffold(fp)
	_box("ProgressBack", Vector3(fp.x, 0.08, 0.18), Vector3(0.0, 1.85, -fp.y * 0.5 - 0.28), Color("11131c"))
	progress_fill = _box("ProgressFill", Vector3(0.08, 0.09, 0.2), Vector3(0.0, 1.86, -fp.y * 0.5 - 0.28), U.COL["gold"], true)
	_sync_construction_progress()

func _sync_construction_progress() -> void:
	if progress_fill == null:
		return
	var fp: Vector2 = main.map_size_to_world(size_v)
	if construction_stage_root:
		_sync_construction_stage(fp)
	if progress_block:
		var h := 0.18 + progress * 1.15
		var block_mesh := progress_block.mesh as BoxMesh
		block_mesh.size = Vector3(fp.x * 0.58, h, fp.y * 0.58)
		progress_block.position.y = 0.12 + h * 0.5
	var total_w := maxf(0.1, fp.x - 0.22)
	var fill_w := maxf(0.04, total_w * progress)
	var fill_mesh := progress_fill.mesh as BoxMesh
	fill_mesh.size = Vector3(fill_w, 0.09, 0.2)
	progress_fill.position.x = -total_w * 0.5 + fill_w * 0.5

func _build_construction_stage(fp: Vector2) -> bool:
	construction_stage_root = Node3D.new()
	construction_stage_root.name = "KayKitConstructionStage"
	visual.add_child(construction_stage_root)
	_sync_construction_stage(fp)
	if construction_stage_root.get_child_count() == 0:
		construction_stage_root.queue_free()
		construction_stage_root = null
		return false
	var scaffolding := _place_kaykit_model("res://assets/models/medieval/buildings/neutral/building_scaffolding.gltf", fp, "KayKitScaffolding", 0.9, 1.75)
	if scaffolding == null:
		_scaffold(fp)
	return true

func _sync_construction_stage(fp: Vector2) -> void:
	if construction_stage_root == null:
		return
	var idx := 0
	if progress >= 0.66:
		idx = 2
	elif progress >= 0.33:
		idx = 1
	if idx == construction_stage_idx:
		return
	for child in construction_stage_root.get_children():
		construction_stage_root.remove_child(child)
		child.queue_free()
	var suffix: String = ["A", "B", "C"][idx]
	var model := U.load_model("res://assets/models/medieval/buildings/neutral/building_stage_%s.gltf" % suffix)
	if model == null:
		return
	model.name = "KayKitStage" + suffix
	if not U.fit_model_to_footprint(model, fp, 0.82, 1.42):
		model.free()
		return
	construction_stage_root.add_child(model)
	construction_stage_idx = idx

func _scaffold(fp: Vector2) -> void:
	var wood := Color("7a6042")
	for x in [-fp.x * 0.5, fp.x * 0.5]:
		for z in [-fp.y * 0.5, fp.y * 0.5]:
			_cylinder("ScaffoldPost", 0.045, 1.65, Vector3(x, 0.83, z), wood, 6)
	for z in [-fp.y * 0.5, fp.y * 0.5]:
		var rail := _cylinder("ScaffoldRail", 0.035, fp.x, Vector3(0.0, 1.32, z), wood, 6)
		rail.rotation.z = PI * 0.5
	for x in [-fp.x * 0.5, fp.x * 0.5]:
		var rail := _cylinder("ScaffoldRail", 0.035, fp.y, Vector3(x, 1.08, 0.0), wood, 6)
		rail.rotation.x = PI * 0.5

func _build_shrine(fp: Vector2) -> void:
	if _build_synty_church(fp):
		_sphere("ShrineLight", 0.23, Vector3(0.0, 2.65, -0.05), Color("b9a7ff"), Vector3.ONE, true)
		return
	if _build_kaykit_building(fp, 0.9, 2.8):
		_sphere("ShrineLight", 0.23, Vector3(0.0, 2.45, -0.05), Color("b9a7ff"), Vector3.ONE, true)
		return
	_box("ShrineBase", Vector3(fp.x, 0.18, fp.y), Vector3(0.0, 0.09, 0.0), Color("4b465d"), false, "tex_moss_stone", Vector3(1.4, 1.4, 1.0))
	_box("ShrineBody", Vector3(fp.x * 0.42, 0.72, fp.y * 0.42), Vector3(0.0, 0.54, 0.05), Color("675aa6"))
	_gable_roof("ShrineRoof", fp.x * 0.6, fp.y * 0.52, 0.93, 0.38, Color("2b213c"))
	_cylinder("ToriiLeft", 0.06, 1.2, Vector3(-fp.x * 0.34, 0.6, -fp.y * 0.58), U.COL["mystic"], 8, -1.0, true)
	_cylinder("ToriiRight", 0.06, 1.2, Vector3(fp.x * 0.34, 0.6, -fp.y * 0.58), U.COL["mystic"], 8, -1.0, true)
	_box("ToriiBeam", Vector3(fp.x * 0.86, 0.12, 0.12), Vector3(0.0, 1.18, -fp.y * 0.58), U.COL["mystic"], true)
	_sphere("ShrineLight", 0.23, Vector3(0.0, 1.55, -0.05), Color("b9a7ff"), Vector3.ONE, true)

func _build_prayer_rock(fp: Vector2) -> void:
	# A lone mossy standing stone — the primitive place of prayer.
	_sphere("RockBase", 0.5, Vector3(0.0, 0.16, 0.0), Color("545b64"), Vector3(1.3, 0.4, 1.0), false, "tex_moss_stone")
	_box("PrayerStone", Vector3(0.5, 1.1, 0.34), Vector3(0.0, 0.62, 0.0), Color("6a7280"), false, "tex_moss_stone")
	_sphere("MossPatch", 0.2, Vector3(0.1, 0.95, 0.12), Color("4a6a3d"), Vector3(1.0, 0.5, 0.8))
	_sphere("PrayerGlow", 0.14, Vector3(0.0, 1.28, 0.0), Color("b9a7ff"), Vector3.ONE, true)
	for i in range(5):
		var a := TAU * float(i) / 5.0
		_cylinder("RingPebble", 0.09, 0.07, Vector3(cos(a) * fp.x * 0.4, 0.04, sin(a) * fp.y * 0.4), Color("6f765d"), 7, -1.0, false, "tex_gravel")

func _build_camp(fp: Vector2) -> void:
	# Ashita's camp: a small fire, a bedroll and a log to sit on.
	_box("CampGround", Vector3(fp.x, 0.05, fp.y), Vector3(0.0, 0.025, 0.0), Color("5d5138"))
	for i in range(4):
		var a := TAU * float(i) / 4.0 + 0.4
		_cylinder("FireStone", 0.1, 0.1, Vector3(cos(a) * 0.42, 0.06, sin(a) * 0.42), Color("5a5f68"), 7)
	var log_a := _cylinder("FireLog", 0.07, 0.65, Vector3(0.0, 0.12, 0.0), Color("6b4c30"), 7)
	log_a.rotation = Vector3(0.0, 0.5, PI * 0.5)
	var log_b := _cylinder("FireLog", 0.07, 0.65, Vector3(0.05, 0.14, 0.0), Color("7a5838"), 7)
	log_b.rotation = Vector3(PI * 0.5, 0.0, 0.4)
	_sphere("FireGlow", 0.19, Vector3(0.0, 0.26, 0.0), Color(1.0, 0.55, 0.2, 0.95), Vector3(1.0, 0.85, 1.0), true)
	var fire_light := OmniLight3D.new()
	fire_light.name = "CampFireLight"
	fire_light.position = Vector3(0.0, 0.42, 0.0)
	fire_light.light_color = Color("ff9a45")
	fire_light.light_energy = 0.72
	fire_light.omni_range = 4.2
	visual.add_child(fire_light)
	_build_sparks(Vector3(0.0, 0.34, 0.0), Color("ffb35c"), 18, 0.24)
	_box("Bedroll", Vector3(0.5, 0.1, 1.15), Vector3(fp.x * 0.28, 0.1, fp.y * 0.12), Color("8c7a5a"))
	_box("BedrollPillow", Vector3(0.42, 0.12, 0.3), Vector3(fp.x * 0.28, 0.12, fp.y * 0.12 - 0.48), Color("a89273"))
	var seat := _cylinder("SeatLog", 0.14, 0.8, Vector3(-fp.x * 0.28, 0.14, -fp.y * 0.1), Color("6b4c30"), 8)
	seat.rotation = Vector3(0.0, 0.0, PI * 0.5)

func _build_plaza(fp: Vector2) -> void:
	_cylinder("PlazaStone", minf(fp.x, fp.y) * 0.48, 0.08, Vector3(0.0, 0.04, 0.0), Color("6c695d"), 28, -1.0, false, "tex_cobble", Vector3(1.6, 1.6, 1.0))
	for i in range(10):
		var a := TAU * float(i) / 10.0
		_cylinder("PlazaPebble", 0.12, 0.06, Vector3(cos(a) * fp.x * 0.36, 0.08, sin(a) * fp.y * 0.34), Color("6f765d"), 8, -1.0, false, "tex_gravel")

func _variation() -> float:
	# Deterministic per-instance tint so identical buildings don't look cloned.
	return float((id.hash() % 13) - 6) / 100.0

func _tinted(c: Color) -> Color:
	var v := _variation()
	return c.lightened(v) if v >= 0.0 else c.darkened(-v)

func _current_kaykit_palette() -> String:
	if main == null or main.world == null:
		return "yellow"
	var best := ""
	var best_v := 0.0
	for axis in ["tech", "nature", "mystic"]:
		var v := float(main.world.axes.get(axis, 0.0))
		if v > best_v:
			best_v = v
			best = axis
	match best:
		"tech":
			return "red"
		"nature":
			return "green"
		"mystic":
			return "blue"
	return "yellow"

func _kaykit_palette() -> String:
	return model_palette if model_palette != "" else _current_kaykit_palette()

func _colored_building_path(key: String) -> String:
	var palette := _kaykit_palette()
	return "res://assets/models/medieval/buildings/%s/building_%s_%s.gltf" % [palette, key, palette]

func _colored_tower_base_path() -> String:
	var palette := _kaykit_palette()
	return "res://assets/models/medieval/buildings/%s/building_tower_base_%s.gltf" % [palette, palette]

func _kaykit_building_path() -> String:
	match type_id:
		"shrine":
			return _colored_building_path("church")
		"hut":
			return _colored_building_path("home_A" if abs(id.hash()) % 2 == 0 else "home_B")
		"woodcamp":
			return _colored_building_path("lumbermill")
		"well":
			return _colored_building_path("well")
		"granary":
			return "res://assets/models/medieval/buildings/neutral/building_grain.gltf"
		"school":
			return _colored_building_path("tavern")
		"quarry":
			return _colored_building_path("mine")
		"forge":
			return _colored_building_path("blacksmith")
		"market":
			return _colored_building_path("market")
		"tavern":
			return _colored_building_path("tavern")
		"windmill":
			return _colored_building_path("windmill")
		"watermill":
			return _colored_building_path("watermill")
		"tower":
			return _colored_building_path("tower_A")
		"barracks":
			return _colored_building_path("barracks")
		"archeryrange":
			return _colored_building_path("archeryrange")
		"castle":
			return _colored_building_path("castle")
		"wall":
			return "res://assets/models/medieval/buildings/neutral/wall_straight.gltf"
		"stable":
			return _colored_building_path("home_B")
	return ""

func _kaykit_model_height() -> float:
	match type_id:
		"castle":
			return 4.1
		"tower":
			return 3.8
		"windmill":
			return 3.5
		"watermill":
			return 2.5
		"barracks", "archeryrange", "tavern":
			return 2.45
	return 0.0

func _place_kaykit_model(path: String, fp: Vector2, node_name: String, margin := 0.86, max_height := 0.0, offset := Vector3.ZERO, rot_y := 0.0, parent: Node3D = null) -> Node3D:
	var model := U.load_model(path)
	if model == null:
		return null
	model.name = node_name
	if not U.fit_model_to_footprint(model, fp, margin, max_height):
		model.free()
		return null
	model.position += offset
	model.rotation.y += rot_y
	var target := visual if parent == null else parent
	target.add_child(model)
	return model

func _place_synty_model(model_name: String, fp: Vector2, node_name: String, margin := 0.86, max_height := 0.0, offset := Vector3.ZERO, rot_y := 0.0, parent: Node3D = null, tint := Color.WHITE) -> Node3D:
	var model := U.load_model(SYNTY_KNIGHTS_MODEL_DIR + model_name)
	if model == null:
		return null
	model.name = node_name
	if not U.fit_model_to_footprint(model, fp, margin, max_height):
		model.free()
		return null
	_apply_synty_material(model, tint)
	model.position += offset
	model.rotation.y += rot_y
	var target := visual if parent == null else parent
	target.add_child(model)
	return model

func _build_synty_house(fp: Vector2) -> bool:
	var root := Node3D.new()
	root.name = "SyntyHouse"
	visual.add_child(root)
	var tint := _synty_palette_tint()
	var h := int(abs(id.hash()))
	var room := "SM_Bld_House_Room_%02d.glb" % (1 + h % 7)
	var top := "SM_Bld_House_RoomTop_%02d.glb" % (1 + int(h / 7) % 7)
	var ok := false
	ok = _place_synty_model("SM_Bld_House_Foundation_01.glb", fp * 0.78, "SyntyHouseFoundation", 0.9, 0.28, Vector3(0.0, 0.0, 0.0), 0.0, root, tint) != null or ok
	ok = _place_synty_model(room, fp * 0.72, "SyntyHouseRoom", 0.9, 1.15, Vector3(0.0, 0.2, 0.0), 0.0, root, tint) != null or ok
	ok = _place_synty_model(top, fp * 0.78, "SyntyHouseTop", 0.9, 0.95, Vector3(0.0, 1.22, 0.0), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_House_Chimney_01.glb", fp * 0.18, "SyntyHouseChimney", 0.9, 0.7, Vector3(fp.x * 0.22, 1.95, fp.y * 0.05), 0.0, root, tint) != null or ok
	if not ok:
		root.queue_free()
	return ok

func _build_synty_church(fp: Vector2) -> bool:
	var root := Node3D.new()
	root.name = "SyntyChurch"
	visual.add_child(root)
	var tint := _synty_palette_tint()
	var ok := false
	ok = _place_synty_model("SM_Bld_Church_Room_01.glb", fp * 0.75, "SyntyChurchRoom", 0.9, 1.6, Vector3(-fp.x * 0.06, 0.0, 0.0), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Church_TowerBase_01.glb", fp * 0.34, "SyntyChurchTowerBase", 0.9, 1.35, Vector3(fp.x * 0.24, 0.0, fp.y * 0.04), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Church_Tower_01.glb", fp * 0.32, "SyntyChurchTower", 0.9, 1.75, Vector3(fp.x * 0.24, 1.18, fp.y * 0.04), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Church_Door_01.glb", fp * 0.18, "SyntyChurchDoor", 0.9, 0.75, Vector3(-fp.x * 0.18, 0.06, -fp.y * 0.36), 0.0, root, tint) != null or ok
	if not ok:
		root.queue_free()
	return ok

func _build_synty_barracks(fp: Vector2) -> bool:
	var root := Node3D.new()
	root.name = "SyntyBarracks"
	visual.add_child(root)
	var tint := _synty_palette_tint()
	var ok := false
	ok = _place_synty_model("SM_Bld_Tent_01.glb", fp * 0.54, "SyntyBarracksTent", 0.92, 1.35, Vector3(-fp.x * 0.18, 0.0, 0.0), -0.18, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Tent_02.glb", fp * 0.48, "SyntyBarracksTent", 0.92, 1.25, Vector3(fp.x * 0.2, 0.0, fp.y * 0.06), 0.22, root, tint) != null or ok
	ok = _place_synty_model("SM_Prop_Banner_01.glb", fp * 0.18, "SyntyBarracksBanner", 0.9, 1.4, Vector3(0.0, 0.0, -fp.y * 0.34), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Wep_Halberd_01.glb", fp * 0.1, "SyntyBarracksWeapon", 0.9, 1.0, Vector3(fp.x * 0.34, 0.0, -fp.y * 0.2), -0.25, root, tint) != null or ok
	if not ok:
		root.queue_free()
	return ok

func _build_synty_archeryrange(fp: Vector2) -> bool:
	var root := Node3D.new()
	root.name = "SyntyArcheryRange"
	visual.add_child(root)
	var tint := _synty_palette_tint()
	var ok := false
	ok = _place_synty_model("SM_Bld_Leanto_01.glb", fp * 0.42, "SyntyArcheryLeanto", 0.9, 1.15, Vector3(-fp.x * 0.24, 0.0, fp.y * 0.05), PI * 0.5, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Tent_03.glb", fp * 0.42, "SyntyArcheryTent", 0.92, 1.05, Vector3(fp.x * 0.2, 0.0, fp.y * 0.05), -0.2, root, tint) != null or ok
	ok = _place_synty_model("SM_Prop_Banner_02.glb", fp * 0.16, "SyntyArcheryBanner", 0.9, 1.25, Vector3(0.0, 0.0, -fp.y * 0.38), 0.0, root, tint) != null or ok
	ok = _place_kaykit_model(PROP_MODEL_DIR + "target.gltf", fp * 0.16, "KayKitArcheryTarget", 0.95, 0.9, Vector3(fp.x * 0.34, 0.0, -fp.y * 0.2), -0.18, root) != null or ok
	if not ok:
		root.queue_free()
	return ok

func _build_synty_castle(fp: Vector2) -> bool:
	var root := Node3D.new()
	root.name = "SyntyCastle"
	visual.add_child(root)
	var tint := _synty_palette_tint()
	var ok := false
	ok = _place_synty_model("SM_Bld_Castle_Wall_Gate_01.glb", Vector2(fp.x * 0.78, fp.y * 0.26), "SyntyCastleGate", 0.9, 1.9, Vector3(0.0, 0.0, -fp.y * 0.34), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Castle_Wall_01.glb", Vector2(fp.x * 0.82, fp.y * 0.22), "SyntyCastleWall", 0.92, 1.55, Vector3(0.0, 0.0, fp.y * 0.28), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Castle_Tower_01.glb", fp * 0.32, "SyntyCastleTower", 0.9, 3.5, Vector3(-fp.x * 0.34, 0.0, -fp.y * 0.12), 0.0, root, tint) != null or ok
	ok = _place_synty_model("SM_Bld_Castle_Tower_02.glb", fp * 0.32, "SyntyCastleTower", 0.9, 3.5, Vector3(fp.x * 0.34, 0.0, -fp.y * 0.12), 0.0, root, tint) != null or ok
	if not ok:
		root.queue_free()
	return ok

func _build_synty_simple_building(fp: Vector2) -> bool:
	match type_id:
		"barracks":
			return _build_synty_barracks(fp)
		"archeryrange":
			return _build_synty_archeryrange(fp)
		"castle":
			return _build_synty_castle(fp)
	return false

func _build_kaykit_building(fp: Vector2, margin := 0.88, max_height := 0.0) -> bool:
	var path := _kaykit_building_path()
	return path != "" and _place_kaykit_model(path, fp, "KayKitBuilding", margin, max_height) != null

func _build_tower(fp: Vector2) -> void:
	var ok := false
	ok = _place_kaykit_model(_colored_tower_base_path(), fp * 0.92, "KayKitTowerBase", 0.9, 0.68) != null or ok
	ok = _place_kaykit_model(_colored_building_path("tower_A"), fp * 0.82, "KayKitTower", 0.9, 3.55, Vector3(0.0, 0.18, 0.0)) != null or ok
	if ok:
		return
	_cylinder("WatchTowerBody", minf(fp.x, fp.y) * 0.24, 2.7, Vector3(0.0, 1.35, 0.0), color, 14, -1.0, false, "tex_stone")
	_box("WatchTowerTop", Vector3(fp.x * 0.58, 0.42, fp.y * 0.58), Vector3(0.0, 2.86, 0.0), color.lightened(0.08), false, "tex_wood")
	_gable_roof("WatchTowerRoof", fp.x * 0.7, fp.y * 0.7, 3.12, 0.42, color.darkened(0.35))

func _build_kaykit_fence_rect(fp: Vector2) -> bool:
	var path := "res://assets/models/medieval/buildings/neutral/fence_wood_straight.gltf"
	var ok := false
	for z in [-fp.y * 0.5, fp.y * 0.5]:
		ok = _place_kaykit_model(path, Vector2(fp.x, 0.5), "KayKitFence", 0.98, 0.62, Vector3(0.0, 0.0, z)) != null or ok
	for x in [-fp.x * 0.5, fp.x * 0.5]:
		ok = _place_kaykit_model(path, Vector2(fp.y, 0.5), "KayKitFence", 0.98, 0.62, Vector3(x, 0.0, 0.0), PI * 0.5) != null or ok
	return ok

func _build_hut(fp: Vector2) -> void:
	if _build_synty_house(fp):
		return
	if _build_kaykit_building(fp, 0.88, 2.5):
		return
	# Taller-than-wide silhouette so the hut reads as a house, not a pancake.
	var w := minf(fp.x * 0.62, 3.0)
	var d := minf(fp.y * 0.68, 2.5)
	var h := 1.45
	var body_col := _tinted(Color("8a6a50"))
	_box("HutYard", Vector3(fp.x, 0.06, fp.y), Vector3(0.0, 0.03, 0.0), Color("6f8551"))
	_box("HutBody", Vector3(w, h, d), Vector3(0.0, 0.06 + h * 0.5, 0.0), body_col)
	_box("HutTrim", Vector3(w + 0.1, 0.12, d + 0.1), Vector3(0.0, 0.06 + h - 0.02, 0.0), Color("4d352a"))
	_gable_roof("HutRoof", w + 0.34, d + 0.3, 0.06 + h, 0.95, _tinted(Color("c9a95e")))
	_box("Door", Vector3(0.42, 0.74, 0.07), Vector3(-w * 0.16, 0.06 + 0.37, -d * 0.5 - 0.02), Color("3c2b21"))
	_box("Window", Vector3(0.36, 0.32, 0.06), Vector3(w * 0.24, 0.06 + 0.85, -d * 0.5 - 0.02), Color("241c14"))
	_box("WindowGlow", Vector3(0.26, 0.22, 0.07), Vector3(w * 0.24, 0.06 + 0.85, -d * 0.5 - 0.03), Color(1.0, 0.82, 0.45, 0.9), true)

func _build_simple_building(fp: Vector2) -> void:
	if _build_synty_simple_building(fp):
		return
	if _build_kaykit_building(fp, 0.9, _kaykit_model_height()):
		return
	var w := minf(fp.x * 0.68, 4.6)
	var d := minf(fp.y * 0.7, 3.4)
	var h := 1.75
	var body_col := _tinted(color.darkened(0.05))
	_box("BuildingYard", Vector3(fp.x, 0.06, fp.y), Vector3(0.0, 0.03, 0.0), color.darkened(0.45))
	_box("BuildingBody", Vector3(w, h, d), Vector3(0.0, 0.06 + h * 0.5, 0.0), body_col)
	_box("BuildingBand", Vector3(w + 0.1, 0.12, d + 0.1), Vector3(0.0, 0.06 + h - 0.02, 0.0), color.darkened(0.35))
	_gable_roof("BuildingRoof", w + 0.34, d + 0.32, 0.06 + h, 1.0, _tinted(color.darkened(0.42)))
	_box("Door", Vector3(0.46, 0.8, 0.07), Vector3(0.0, 0.06 + 0.4, -d * 0.5 - 0.02), Color("3c2b21"))

func _build_forest_site(fp: Vector2) -> void:
	_box("FoothillGround", Vector3(fp.x * 0.92, 0.12, fp.y * 0.36), Vector3(0.0, 0.06, fp.y * 0.28), color.darkened(0.18), false, "tex_grass", Vector3(1.8, 1.0, 1.0))
	_box("GatheringFlat", Vector3(fp.x * 0.72, 0.08, fp.y * 0.24), Vector3(0.0, 0.14, fp.y * 0.34), Color("5f704b"), false, "tex_grass", Vector3(1.2, 0.7, 1.0))
	if _place_kaykit_model("res://assets/models/medieval/decoration/nature/mountain_B_grass_trees.gltf", Vector2(fp.x * 0.86, fp.y * 0.78), "KayKitMountainSite", 0.94, 5.15, Vector3(-fp.x * 0.04, 0.0, -fp.y * 0.18), -0.16) == null:
		var main_mountain := _cylinder("MountainBody", fp.x * 0.28, 4.8, Vector3(-fp.x * 0.06, 2.4, -fp.y * 0.2), Color("707069"), 22, 0.0, false, "tex_rock", Vector3(1.7, 1.7, 1.0))
		main_mountain.rotation.y = -0.18
		var left_mountain := _cylinder("MountainShoulder", fp.x * 0.2, 3.4, Vector3(-fp.x * 0.28, 1.7, -fp.y * 0.08), Color("626a5e"), 18, 0.0, false, "tex_rock", Vector3(1.4, 1.4, 1.0))
		left_mountain.rotation.y = 0.22
		var right_mountain := _cylinder("MountainShoulder", fp.x * 0.22, 3.8, Vector3(fp.x * 0.24, 1.9, -fp.y * 0.22), Color("69695f"), 18, 0.0, false, "tex_rock", Vector3(1.45, 1.45, 1.0))
		right_mountain.rotation.y = -0.34
		_cylinder("SnowCap", fp.x * 0.075, 0.72, Vector3(-fp.x * 0.06, 4.56, -fp.y * 0.2), Color("edf2f5"), 18, 0.0)
		_cylinder("SnowCap", fp.x * 0.052, 0.52, Vector3(fp.x * 0.24, 3.58, -fp.y * 0.22), Color("dfe8e8"), 14, 0.0)
	for i in range(10):
		var x := -fp.x * 0.42 + float(i % 5) * fp.x * 0.21
		var z := -fp.y * 0.43 + float(i / 5) * fp.y * 0.18
		var s := 0.72 + float(i % 3) * 0.13
		_cylinder("ForestTrunk", 0.055 * s, 0.55 * s, Vector3(x, 0.34 * s, z), Color("5d4632"), 7, -1.0, false, "tex_bark")
		_cylinder("ForestCrown", 0.3 * s, 0.78 * s, Vector3(x, 0.9 * s, z), Color("254b2a").lightened(float(i % 4) * 0.035), 10, 0.05 * s, false, "tex_leaves")
	for i in range(4):
		var log := _cylinder("GatheringLog", 0.08, fp.x * 0.22, Vector3(-fp.x * 0.27 + i * fp.x * 0.18, 0.24, fp.y * 0.34), Color("6b4c30"), 8, -1.0, false, "tex_bark")
		log.rotation.z = PI * 0.5

func _build_riverbank(fp: Vector2) -> void:
	_box("RiverSandBank", Vector3(fp.x, 0.06, fp.y), Vector3(0.0, 0.03, 0.0), Color("b8a06d"), false, "tex_sand", Vector3(1.8, 1.2, 1.0))
	_box("Dock", Vector3(fp.x * 0.8, 0.12, fp.y * 0.34), Vector3(0.0, 0.12, 0.0), Color("6e5438"))
	for i in range(4):
		_box("DockPlank", Vector3(fp.x * 0.82, 0.04, 0.04), Vector3(0.0, 0.22, -fp.y * 0.16 + i * fp.y * 0.1), Color("92734f"))
	_cylinder("FishingPole", 0.025, 1.1, Vector3(fp.x * 0.28, 0.62, -fp.y * 0.26), Color("8a6b43"), 6)

func _build_farm(fp: Vector2) -> void:
	_box("FarmSoil", Vector3(fp.x, 0.1, fp.y), Vector3(0.0, 0.05, 0.0), Color("5d4624"), false, "tex_crops", Vector3(1.8, 1.35, 1.0))
	_box("FarmEdge", Vector3(fp.x, 0.08, 0.12), Vector3(0.0, 0.12, -fp.y * 0.5), Color("1f351f"))
	_box("FarmEdge", Vector3(fp.x, 0.08, 0.12), Vector3(0.0, 0.12, fp.y * 0.5), Color("1f351f"))
	for i in range(5):
		var x := -fp.x * 0.36 + float(i) * fp.x * 0.18
		_box("Furrow", Vector3(0.16, 0.12, fp.y * 0.86), Vector3(x, 0.16, 0.0), Color("7a4f29"))
		for j in range(3):
			_cylinder("Seedling", 0.075, 0.32, Vector3(x, 0.34, -fp.y * 0.28 + j * fp.y * 0.28), Color("76d86f"), 6, 0.0)

func _build_woodcamp(fp: Vector2) -> void:
	if _build_kaykit_building(fp, 0.9, 2.3):
		return
	_box("CampDirt", Vector3(fp.x, 0.08, fp.y), Vector3(0.0, 0.04, 0.0), Color("564631"))
	_box("WoodcampDarkPlanks", Vector3(fp.x * 0.72, 0.06, fp.y * 0.34), Vector3(0.0, 0.1, -fp.y * 0.16), Color("3a2c24"), false, "tex_dark_planks", Vector3(1.5, 0.9, 1.0))
	for i in range(4):
		var log := _cylinder("Log", 0.14, fp.x * 0.62, Vector3(0.0, 0.23 + i * 0.18, -fp.y * 0.18 + i * 0.12), Color("7a5638"), 10)
		log.rotation.z = PI * 0.5
	_box("AxeBlock", Vector3(0.34, 0.45, 0.34), Vector3(fp.x * 0.28, 0.24, fp.y * 0.2), Color("6b4d34"))

func _build_well(fp: Vector2) -> void:
	if _build_kaykit_building(fp, 0.92, 1.7):
		return
	_cylinder("WellStone", minf(fp.x, fp.y) * 0.28, 0.55, Vector3(0.0, 0.28, 0.0), Color("7d8790"), 16)
	_cylinder("WellWater", minf(fp.x, fp.y) * 0.22, 0.03, Vector3(0.0, 0.58, 0.0), Color(0.32, 0.58, 0.78, 0.82), 16, -1.0, true)
	for x in [-0.42, 0.42]:
		_cylinder("WellPost", 0.04, 0.9, Vector3(x, 0.94, 0.0), Color("6b4d34"), 6)
	_gable_roof("WellRoof", 1.2, 0.7, 1.34, 0.3, Color("5d4632"))

func _build_granary(fp: Vector2) -> void:
	# KayKit's building_grain.gltf is a flat crop-field hex tile, not a granary
	# building — always use the raised-floor storehouse below instead.
	for x in [-fp.x * 0.3, fp.x * 0.3]:
		for z in [-fp.y * 0.25, fp.y * 0.25]:
			_cylinder("GranaryLeg", 0.045, 0.42, Vector3(x, 0.21, z), Color("5b422e"), 6)
	_box("GranaryBody", Vector3(fp.x * 0.72, 0.9, fp.y * 0.68), Vector3(0.0, 0.9, 0.0), color)
	_gable_roof("GranaryRoof", fp.x * 0.84, fp.y * 0.78, 1.36, 0.4, Color("6a4a2e"))
	_cylinder("Silo", 0.32, 1.05, Vector3(fp.x * 0.34, 0.68, 0.0), Color("b8a06f"), 14)

func _build_school(fp: Vector2) -> void:
	if _build_kaykit_building(fp, 0.88, 2.5):
		return
	_box("SchoolBody", Vector3(fp.x * 0.82, 1.05, fp.y * 0.74), Vector3(0.0, 0.54, 0.0), Color("d7d3bf"), false, "tex_plaster")
	_gable_roof("SchoolRoof", fp.x * 0.94, fp.y * 0.84, 1.08, 0.42, Color("243c57"))
	_box("SchoolSign", Vector3(0.62, 0.34, 0.06), Vector3(0.0, 0.62, -fp.y * 0.39), U.COL["gold"])

func _build_pen(fp: Vector2) -> void:
	_box("PenGround", Vector3(fp.x, 0.06, fp.y), Vector3(0.0, 0.03, 0.0), Color("5b4a31"))
	if not _build_kaykit_fence_rect(fp):
		_fence(fp)
	if _place_kaykit_model(_colored_building_path("home_A"), fp * 0.46, "KayKitPenShed", 0.86, 1.18, Vector3(-fp.x * 0.24, 0.0, fp.y * 0.18), -0.18) != null:
		return
	_box("PenShed", Vector3(fp.x * 0.38, 0.55, fp.y * 0.34), Vector3(-fp.x * 0.24, 0.33, fp.y * 0.18), Color("8a6544"))
	_gable_roof("PenRoof", fp.x * 0.44, fp.y * 0.4, 0.62, 0.24, Color("5c3d2f"), Vector3(-fp.x * 0.24, 0.0, fp.y * 0.18))

func _fence(fp: Vector2) -> void:
	var wood := Color("765c3c")
	for x in [-fp.x * 0.5, -fp.x * 0.18, fp.x * 0.18, fp.x * 0.5]:
		for z in [-fp.y * 0.5, fp.y * 0.5]:
			_cylinder("FencePost", 0.035, 0.5, Vector3(x, 0.28, z), wood, 6)
	for z in [-fp.y * 0.5, fp.y * 0.5]:
		_box("FenceRail", Vector3(fp.x, 0.06, 0.05), Vector3(0.0, 0.35, z), wood)
	for x in [-fp.x * 0.5, fp.x * 0.5]:
		_box("FenceRail", Vector3(0.05, 0.06, fp.y), Vector3(x, 0.35, 0.0), wood)

func _build_village_props(fp: Vector2) -> void:
	if ["forest", "riverbank", "prayer_rock", "plaza", "wall", "grand_circle", "world_tree"].has(type_id):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(abs((id + ":" + type_id).hash())) + 19
	var count := 1 + int(rng.randi_range(0, 1))
	for i in range(count):
		var path: String = PROP_MODEL_DIR + PROP_MODELS[int(rng.randi_range(0, PROP_MODELS.size() - 1))]
		var side := int(rng.randi_range(0, 3))
		var offset := Vector3.ZERO
		var rot := rng.randf_range(-0.28, 0.28)
		match side:
			0:
				offset = Vector3(rng.randf_range(-fp.x * 0.42, fp.x * 0.42), 0.0, -fp.y * 0.5 - rng.randf_range(0.28, 0.72))
				rot += 0.0
			1:
				offset = Vector3(fp.x * 0.5 + rng.randf_range(0.28, 0.72), 0.0, rng.randf_range(-fp.y * 0.36, fp.y * 0.36))
				rot += PI * 0.5
			2:
				offset = Vector3(rng.randf_range(-fp.x * 0.42, fp.x * 0.42), 0.0, fp.y * 0.5 + rng.randf_range(0.28, 0.72))
				rot += PI
			_:
				offset = Vector3(-fp.x * 0.5 - rng.randf_range(0.28, 0.72), 0.0, rng.randf_range(-fp.y * 0.36, fp.y * 0.36))
				rot -= PI * 0.5
		var model := U.load_model(path)
		if model == null:
			continue
		model.name = "VillageProp"
		var prop_size := rng.randf_range(0.46, 0.68)
		if not U.fit_model_to_footprint(model, Vector2(prop_size, prop_size), 0.95, prop_size * 0.9):
			model.free()
			continue
		model.position += offset
		model.rotation.y += rot
		visual.add_child(model)
	if rng.randf() < 0.72:
		var synty_path: String = SYNTY_PROP_MODELS[int(rng.randi_range(0, SYNTY_PROP_MODELS.size() - 1))]
		var synty_offset := Vector3(rng.randf_range(-fp.x * 0.46, fp.x * 0.46), 0.0, -fp.y * 0.5 - rng.randf_range(0.35, 0.85))
		var synty_rot := rng.randf_range(-0.35, 0.35)
		_place_synty_model(synty_path, Vector2(0.62, 0.62), "SyntyVillageProp", 0.95, 1.05, synty_offset, synty_rot, null, _synty_palette_tint())

func _build_quarry(fp: Vector2) -> void:
	if _build_kaykit_building(fp, 0.9, 2.35):
		return
	_box("QuarryPit", Vector3(fp.x, 0.12, fp.y), Vector3(0.0, 0.02, 0.0), Color("3a3d42"))
	for i in range(7):
		_sphere("QuarryRock", 0.28 + randf() * 0.16, Vector3(randf_range(-fp.x * 0.38, fp.x * 0.38), 0.22, randf_range(-fp.y * 0.35, fp.y * 0.35)), color.lightened(randf() * 0.2), Vector3(1.25, 0.5, 0.9))
	_box("CutStone", Vector3(fp.x * 0.28, 0.35, fp.y * 0.22), Vector3(fp.x * 0.28, 0.2, -fp.y * 0.28), Color("777d86"))

func _build_forge(fp: Vector2) -> void:
	if _build_kaykit_building(fp, 0.9, 2.55):
		_build_smoke(Vector3(fp.x * 0.24, 2.12, fp.y * 0.12))
		_build_sparks(Vector3(-fp.x * 0.16, 0.62, -fp.y * 0.35), Color("ff9a3d"), 14, 0.18)
		return
	_box("ForgeBody", Vector3(fp.x * 0.78, 0.95, fp.y * 0.72), Vector3(0.0, 0.5, 0.0), color)
	_gable_roof("ForgeRoof", fp.x * 0.9, fp.y * 0.82, 1.0, 0.32, Color("3a3030"))
	_cylinder("Chimney", 0.16, 1.15, Vector3(fp.x * 0.24, 1.32, fp.y * 0.12), Color("6b6048"), 10, -1.0, false, "tex_metal")
	_build_smoke(Vector3(fp.x * 0.24, 2.0, fp.y * 0.12))
	_box("ForgeGlow", Vector3(0.48, 0.35, 0.08), Vector3(-fp.x * 0.16, 0.42, -fp.y * 0.38), Color("ff8a3d"), true)
	_box("ForgeAnvil", Vector3(0.52, 0.22, 0.36), Vector3(fp.x * 0.18, 0.26, -fp.y * 0.22), Color("8f856a"), false, "tex_metal")
	var forge_light := OmniLight3D.new()
	forge_light.name = "ForgeLight"
	forge_light.position = Vector3(-fp.x * 0.16, 0.55, -fp.y * 0.35)
	forge_light.light_color = Color("ff8a3d")
	forge_light.light_energy = 0.62
	forge_light.omni_range = 3.6
	visual.add_child(forge_light)
	_build_sparks(Vector3(-fp.x * 0.16, 0.6, -fp.y * 0.35), Color("ff9a3d"), 14, 0.18)

func _build_sparks(pos: Vector3, spark_color: Color, amount: int, radius: float) -> void:
	var p := GPUParticles3D.new()
	p.name = "FireSparks"
	p.amount = amount
	p.lifetime = 1.25
	p.preprocess = 1.25
	p.randomness = 0.84
	p.position = pos
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 28.0
	pm.gravity = Vector3(0.0, -0.16, 0.0)
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.38
	pm.scale_min = 0.025
	pm.scale_max = 0.07
	pm.color = spark_color
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.07
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(spark_color.r, spark_color.g, spark_color.b, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = spark_color
	mat.emission_energy_multiplier = 1.9
	mesh.material = mat
	p.draw_pass_1 = mesh
	visual.add_child(p)

func _build_smoke(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.name = "ForgeSmoke"
	p.amount = 20
	p.lifetime = 3.2
	p.preprocess = 3.2
	p.randomness = 0.72
	p.position = pos
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 22.0
	pm.gravity = Vector3(0.0, 0.08, 0.0)
	pm.initial_velocity_min = 0.08
	pm.initial_velocity_max = 0.22
	pm.scale_min = 0.22
	pm.scale_max = 0.52
	pm.color = Color(0.48, 0.48, 0.46, 0.34)
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.48, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	p.draw_pass_1 = mesh
	visual.add_child(p)

func _build_grove(fp: Vector2) -> void:
	_box("GroveMoss", Vector3(fp.x, 0.06, fp.y), Vector3(0.0, 0.03, 0.0), color.darkened(0.18))
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var p := Vector3(cos(a) * fp.x * 0.32, 0.0, sin(a) * fp.y * 0.32)
		_cylinder("GroveTrunk", 0.08, 0.8, p + Vector3(0.0, 0.4, 0.0), Color("5d4632"), 8)
		_sphere("GroveCrown", 0.42, p + Vector3(0.0, 1.08, 0.0), color.lightened(0.12), Vector3(1.0, 0.9, 1.0))
	_sphere("GroveSpirit", 0.26, Vector3(0.0, 0.9, 0.0), Color("b7ffd0"), Vector3.ONE, true)

func _build_mage_tower(fp: Vector2) -> void:
	_cylinder("TowerBody", minf(fp.x, fp.y) * 0.28, 3.0, Vector3(0.0, 1.5, 0.0), color, 18)
	_cylinder("TowerRoof", minf(fp.x, fp.y) * 0.36, 1.0, Vector3(0.0, 3.45, 0.0), Color("33265f"), 18, 0.0)
	_sphere("TowerOrb", 0.32, Vector3(0.0, 4.12, 0.0), Color("bbaaff"), Vector3.ONE, true)
	for i in range(3):
		var a := TAU * float(i) / 3.0
		_sphere("OrbitLight", 0.11, Vector3(cos(a) * 0.75, 2.65, sin(a) * 0.75), U.COL["mystic"], Vector3.ONE, true)

func _build_market(fp: Vector2) -> void:
	if _build_kaykit_building(fp, 0.9, 2.5):
		return
	_box("MarketGround", Vector3(fp.x, 0.08, fp.y), Vector3(0.0, 0.04, 0.0), Color("6b5638"), false, "tex_gravel", Vector3(1.6, 1.2, 1.0))
	for i in range(3):
		var x := -fp.x * 0.28 + i * fp.x * 0.28
		_box("Stall", Vector3(fp.x * 0.22, 0.42, fp.y * 0.32), Vector3(x, 0.26, 0.0), Color("6b4b32"), false, "tex_dark_planks")
		_gable_roof("Awning", fp.x * 0.26, fp.y * 0.36, 0.52, 0.22, Color("d7b578"), Vector3(x, 0.0, 0.0), "tex_cloth", Vector3(0.8, 0.7, 1.0))

func _build_wall(fp: Vector2) -> void:
	if _build_kaykit_building(fp, 0.98, 1.75):
		return
	_box("WallBody", Vector3(fp.x, 1.0, fp.y * 0.36), Vector3(0.0, 0.52, 0.0), color, false, "tex_moss_stone", Vector3(2.2, 1.0, 1.0))
	for i in range(6):
		var x := -fp.x * 0.44 + i * fp.x * 0.176
		_box("Battlement", Vector3(fp.x * 0.1, 0.28, fp.y * 0.38), Vector3(x, 1.16, 0.0), color.lightened(0.08), false, "tex_moss_stone")

func _build_stable(fp: Vector2) -> void:
	_box("StableGround", Vector3(fp.x, 0.06, fp.y), Vector3(0.0, 0.03, 0.0), Color("5b4a31"))
	if not _build_kaykit_fence_rect(fp):
		_fence(fp)
	if _build_kaykit_building(fp * 0.72, 0.88, 1.85):
		return
	_box("StableBody", Vector3(fp.x * 0.52, 0.78, fp.y * 0.44), Vector3(-fp.x * 0.16, 0.42, 0.0), Color("8a6544"))
	_gable_roof("StableRoof", fp.x * 0.62, fp.y * 0.5, 0.82, 0.3, Color("5c3d2f"), Vector3(-fp.x * 0.16, 0.0, 0.0))

func _build_clinic(fp: Vector2) -> void:
	_box("ClinicBody", Vector3(fp.x * 0.78, 1.0, fp.y * 0.7), Vector3(0.0, 0.52, 0.0), Color("ddd7c8"), false, "tex_plaster")
	_gable_roof("ClinicRoof", fp.x * 0.9, fp.y * 0.8, 1.05, 0.38, Color("6c3a45"))
	_box("CrossV", Vector3(0.12, 0.55, 0.06), Vector3(0.0, 0.68, -fp.y * 0.36), Color("d96a6a"))
	_box("CrossH", Vector3(0.46, 0.12, 0.07), Vector3(0.0, 0.68, -fp.y * 0.37), Color("d96a6a"))

func _build_great_engine(fp: Vector2) -> void:
	_box("EngineBase", Vector3(fp.x, 0.25, fp.y), Vector3(0.0, 0.12, 0.0), Color("5c5748"), false, "tex_metal", Vector3(1.5, 1.2, 1.0))
	var drum := _cylinder("EngineDrum", 0.62, fp.x * 0.62, Vector3(0.0, 0.85, 0.0), color, 20, -1.0, false, "tex_metal")
	drum.rotation.z = PI * 0.5
	for x in [-fp.x * 0.24, fp.x * 0.24]:
		_cylinder("EngineWheel", 0.62, 0.18, Vector3(x, 0.85, 0.0), Color("8a8065"), 18, -1.0, false, "tex_metal")
	_box("EngineCore", Vector3(0.48, 0.48, 0.48), Vector3(0.0, 0.88, -fp.y * 0.28), Color("ffc36a"), true)
	_cylinder("EngineStack", 0.18, 1.6, Vector3(fp.x * 0.32, 1.02, fp.y * 0.22), Color("6b6048"), 12, -1.0, false, "tex_metal")

func _build_world_tree(fp: Vector2) -> void:
	_box("WorldTreeMoss", Vector3(fp.x, 0.08, fp.y), Vector3(0.0, 0.04, 0.0), color.darkened(0.22))
	_cylinder("WorldTreeTrunk", 0.55, 4.2, Vector3(0.0, 2.1, 0.0), Color("6d4c34"), 16)
	_sphere("WorldTreeCrown", 1.65, Vector3(0.0, 4.55, 0.0), color.lightened(0.1), Vector3(1.1, 0.82, 1.05))
	_sphere("WorldTreeCrownA", 1.0, Vector3(-0.95, 4.0, 0.35), Color("5fb66a"), Vector3(1.0, 0.8, 1.0))
	_sphere("WorldTreeCrownB", 1.0, Vector3(0.9, 4.12, -0.22), Color("69c46e"), Vector3(1.0, 0.8, 1.0))
	_sphere("WorldTreeGlow", 0.24, Vector3(0.0, 2.9, -0.55), Color("d8ffd1"), Vector3.ONE, true)

func _build_grand_circle(fp: Vector2) -> void:
	_cylinder("CircleOuter", minf(fp.x, fp.y) * 0.46, 0.055, Vector3(0.0, 0.045, 0.0), Color("514990"), 42, -1.0, true)
	_cylinder("CircleInner", minf(fp.x, fp.y) * 0.3, 0.065, Vector3(0.0, 0.075, 0.0), Color("171321"), 42)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		_cylinder("CirclePillar", 0.1, 0.7, Vector3(cos(a) * fp.x * 0.42, 0.38, sin(a) * fp.y * 0.34), U.COL["mystic"], 10, -1.0, true)
	_box("CircleRuneX", Vector3(fp.x * 0.8, 0.035, 0.06), Vector3(0.0, 0.12, 0.0), Color("bbaaff"), true)
	var rune := _box("CircleRuneZ", Vector3(fp.x * 0.8, 0.035, 0.06), Vector3(0.0, 0.13, 0.0), Color("bbaaff"), true)
	rune.rotation.y = PI * 0.5
