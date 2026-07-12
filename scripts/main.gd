extends Node2D
# Composition root. Builds the whole world in code from a near-empty scene,
# drives the explicit tick order, and owns cross-system glue (prayers, jobs,
# population, endings). Debug modes: `-- --selftest`, `-- --shot`.

const U = preload("res://scripts/util.gd")
const ClockScript = preload("res://scripts/clock.gd")
const TerrainScript = preload("res://scripts/terrain.gd")
const TownScript = preload("res://scripts/town.gd")
const AgentScript = preload("res://scripts/agent.gd")
const ProtagonistScript = preload("res://scripts/protagonist.gd")
const AnimalScript = preload("res://scripts/animal.gd")
const WorldScript = preload("res://scripts/world.gd")
const MagicScript = preload("res://scripts/magic.gd")
const ProjectsScript = preload("res://scripts/projects.gd")
const EventsScript = preload("res://scripts/events.gd")
const DialogueUIScript = preload("res://scripts/dialogue_ui.gd")
const MenuUIScript = preload("res://scripts/menu_ui.gd")
const UIScript = preload("res://scripts/ui.gd")
const ChronicleScript = preload("res://scripts/chronicle.gd")
const BgmScript = preload("res://scripts/bgm.gd")

const MAP_CENTER := Vector2(490.0, 380.0)
const MAP_SCALE := 0.08
const CAMERA_CLICK_THRESHOLD := 5.0
const CAMERA_MIN_PITCH := PI * 16.0 / 180.0  # low enough to view the world from the side
const CAMERA_MAX_PITCH := PI * 70.0 / 180.0
const CAMERA_MIN_DISTANCE := 22.0
const CAMERA_MAX_DISTANCE := 84.0
const CAMERA_NAME_DISTANCE := 48.0
const VILLAGER_COLORS := [
	"#e07a5f", "#81b29a", "#f2cc8f", "#6fa8dc", "#c98bb9",
	"#94b0da", "#e5989b", "#8fbf9f", "#d9b96a", "#a48fd9",
	"#7fc9c9", "#d98f6a",
]
const DM_MONSTER_MODEL_DIR := "res://assets/models/dmason/monster/Meshes/Character/"
const DM_MONSTER_ANIM_DIR := "res://assets/models/dmason/monster/Animations/"
const DM_MONSTER_TEX := "res://assets/models/dmason/monster/Textures/Albedo.png"
const DM_MONSTER_WALK_ANIMS := {
	"Slime": "Walk_Slime_Anim",
	"Spider": "Walk_Spider_Anim",
	"Orc": "WalkFWD_Orc_Anim",
	"Skeleton": "WalkFront_Skeleton_Anim",
	"Golem": "Walk_Golem_Anim",
	"EvilMage": "WalkFWD_EvilMage_Anim",
}
const DM_MONSTER_HEIGHTS := {
	"Slime": 0.9,
	"Spider": 0.82,
	"Orc": 1.65,
	"Skeleton": 1.5,
	"Golem": 2.05,
	"EvilMage": 1.65,
}
const SYNTY_KNIGHTS_MODEL_DIR := "res://assets/models/synty/PolygonKnights/Models/"
const SYNTY_KNIGHTS_ATLAS := "res://assets/models/synty/PolygonKnights/Textures/PolygonKnights_01.png"
const SYNTY_CHARACTER_MODEL := "res://assets/models/synty/PolygonKnights/Models/Characters/Characters.glb"
const SYNTY_ENEMY_TEX := "res://assets/models/synty/PolygonKnights/Textures/Characters_01_Black.png"

var clock
var terrain
var town
var world
var magic
var projects
var events
var dialogue_ui
var menu_ui
var ui
var bgm
var chronicle
var protagonist
var villagers: Array = []
var animals: Array = []
var agents_node: Node2D
var animals_node: Node2D
var visual_root: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var night_glow: OmniLight3D
var world_env: WorldEnvironment
var sky_material: PanoramaSkyMaterial
var sky_textures := {}
var shrine_motes: GPUParticles3D
var fireflies: GPUParticles3D
var festival_visual_root: Node3D
var monster_raid_root: Node3D
var monster_raid_skeletons: Array = []
var monster_raid_started := -1.0
var overhead_layer: CanvasLayer
var overhead_root: Control
var overhead_controls := {}
var _active_sky := ""
var _camera_target := Vector3(-1.2, 0.0, -2.4)
var _camera_yaw := -0.65
var _camera_pitch := 1.08
var _camera_distance := 78.0
var _camera_current_target := Vector3(-1.2, 0.0, -2.4)
var _camera_current_yaw := -0.65
var _camera_current_pitch := 1.08
var _camera_current_distance := 78.0
var _panning := false
var _rotating := false
var _left_down := false
var _left_press_pos := Vector2.ZERO
var _left_dragging := false
var _pan_grab_world = null

var dlg_data: Dictionary = {}
var story_data: Dictionary = {}
var chapters_data: Dictionary = {}
var missions: Array = []
var mission_idx := 0
var name_pool: Array = []
var name_idx := 0
var color_idx := 0

var selected_agent = null
var hovered_location = null  # building under the cursor; only it shows its name
var dialog_open := false
var pending_ending := {}
var auto_resolve := false
var auto_oracle := false  # 🎲 idle mode: dice answer every non-special oracle
var game_over := false
var game_started := false  # true once the title screen is dismissed
var follow_agent = null  # camera tracks this agent until the player pans
var data_ok := true

var headless_mode := false

const SAVE_PATH := "user://save.json"
const AUTOSAVE_PATH := "user://autosave.json"
# Survives get_tree().reload_current_scene(): the freshly built world applies
# this snapshot in _ready instead of showing the title screen.
static var pending_load: Dictionary = {}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest") or args.has("--shot"):
		seed(20260711)
		headless_mode = true
	else:
		randomize()
	_configure_viewport_quality()
	RenderingServer.set_default_clear_color(Color("0e1016"))
	_build_world()
	if args.has("--selftest"):
		_run_selftest()
	elif args.has("--shot"):
		_run_shot(args)
	elif not pending_load.is_empty():
		var snapshot := pending_load
		pending_load = {}
		_apply_save(snapshot)
	elif ui:
		ui.show_title()

func _build_world() -> void:
	chronicle = ChronicleScript.new()
	clock = ClockScript.new()
	clock.name = "Clock"
	add_child(clock)

	_build_3d_view()

	terrain = TerrainScript.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(self)

	town = TownScript.new()
	town.name = "Town"
	add_child(town)

	agents_node = Node2D.new()
	agents_node.name = "Agents"
	add_child(agents_node)
	animals_node = Node2D.new()
	animals_node.name = "Animals"
	add_child(animals_node)

	world = WorldScript.new()
	world.name = "World"
	add_child(world)

	var locations_data: Array = _load_json("res://data/locations.json", [])
	var agents_data: Dictionary = _load_json("res://data/agents.json", {})
	var eras_data: Dictionary = _load_json("res://data/eras.json", {})
	var spells_data: Array = _load_json("res://data/spells.json", [])
	var projects_data: Array = _load_json("res://data/projects.json", [])
	var events_data: Dictionary = _load_json("res://data/events.json", {})
	dlg_data = _load_json("res://data/dialogue.json", {})
	name_pool = _load_json("res://data/names.json", [])
	story_data = _load_json("res://data/story.json", {})
	chapters_data = _load_json("res://data/chapters.json", {})
	missions = _load_json("res://data/missions.json", {}).get("missions", [])

	town.setup(self, locations_data)
	world.setup(self, eras_data)

	magic = MagicScript.new()
	magic.setup(self, spells_data)
	projects = ProjectsScript.new()
	projects.setup(self, projects_data)
	events = EventsScript.new()
	events.setup(self, events_data, dlg_data)

	protagonist = ProtagonistScript.new()
	protagonist.name = "Hero"
	agents_node.add_child(protagonist)
	protagonist.setup(agents_data.get("protagonist", {}), self)
	for d in agents_data.get("villagers", []):
		_add_villager(d)
	for spec in agents_data.get("animals", []):
		spawn_animal(str(spec.get("kind", "deer")), Vector2(spec.get("pos", [150, 180])[0], spec.get("pos", [150, 180])[1]), float(spec.get("radius", 80)))

	dialogue_ui = DialogueUIScript.new()
	dialogue_ui.name = "DialogueUI"
	add_child(dialogue_ui)
	dialogue_ui.build(clock)

	ui = UIScript.new()
	ui.name = "UILayer"
	add_child(ui)
	ui.build(self)
	if not headless_mode:
		bgm = BgmScript.new()
		bgm.name = "BGM"
		add_child(bgm)
		bgm.setup(self, _load_json("res://data/bgm.json", {}))
	menu_ui = MenuUIScript.new()
	menu_ui.name = "MenuUI"
	add_child(menu_ui)
	menu_ui.setup(self)
	_build_overhead_layer()

	clock.day_started.connect(_on_day_started)
	assign_jobs()
	terrain.build_wilderness()
	if villagers.is_empty():
		log_event("深い森の奥で、アシタひとりの旅が始まった", "era")
	else:
		log_event("小さな祠のまわりに、%d人の暮らしが始まった" % world.pop(), "era")

func _exit_tree() -> void:
	U.clear_model_cache()

func _add_villager(d: Dictionary):
	var a = AgentScript.new()
	var vd := d.duplicate()
	if not vd.has("color"):
		vd["color"] = VILLAGER_COLORS[color_idx % VILLAGER_COLORS.size()]
		color_idx += 1
	a.name = "Agent_" + str(vd.get("id", villagers.size()))
	agents_node.add_child(a)
	a.setup(vd, self)
	villagers.append(a)
	return a

# --- frame loop ---------------------------------------------------------------

func _process(delta: float) -> void:
	# Selected characters are followed by the camera until the player grabs
	# the ground to pan away.
	if follow_agent != null and is_instance_valid(follow_agent):
		_camera_target = _clamp_camera_target(
			map_to_world(follow_agent.global_position, 0.0))
	_update_camera_smoothing(delta)
	_update_overheads()
	_update_location_hover()
	_update_festival_visuals(delta)
	_update_monster_raid_visual(delta)
	if game_over:
		ui.refresh(delta)
		return
	var gmin: float = clock.advance(delta)
	_tick(gmin)
	_check_ui_unlocks()
	_check_missions()
	_update_tint()
	ui.refresh(delta)

func _tick(gmin: float) -> void:
	if gmin <= 0.0:
		return
	var ctx := build_ctx()
	protagonist.sim_tick(gmin, ctx)
	for a in villagers.duplicate():
		a.sim_tick(gmin, ctx)
	for an in animals:
		an.sim_tick(gmin, ctx)

func build_ctx() -> Dictionary:
	return {
		"day": clock.day,
		"minute_of_day": clock.minute_of_day,
		"abs_minutes": clock.abs_minutes(),
	}

func day() -> int:
	return clock.day

func is_rest_day() -> bool:
	return clock.day % 7 == 0 and world.pop() >= 4

# --- progressive status disclosure -----------------------------------------------
# Resources / meters appear in the HUD only once the village first touches
# them, each with a one-time explanation.

const UI_UNLOCK_INFO := {
	"stone": "🪨 石材が使えるようになった — 硬い建物と時代を進める材料",
	"metal": "⚙ 金属が使えるようになった — 機械文明への鍵",
	"mana": "✨ 魔素が見えるようになった — 魔法の源。祈りの場に集まる",
	"knowledge": "📖 知識が積み上がりはじめた — 学びが新しい時代を開く",
	"axes": "🧭 文明のかたちが見えるようになった — 機械・自然・神秘。あなたの導きが未来の姿を決める",
	"magic_tab": "「魔」タブが開いた — 覚えた魔法と修行の進みを確認できる",
}

func is_ui_unlocked(key: String) -> bool:
	return world.flags.get("ui_" + key, false)

func _check_ui_unlocks() -> void:
	_unlock_ui("mana", float(world.res["mana"]) > 0.0)
	_unlock_ui("stone", float(world.res["stone"]) > 0.0 or town.has_built("quarry"))
	_unlock_ui("metal", float(world.res["metal"]) > 0.0 or town.has_built("forge"))
	_unlock_ui("knowledge", float(world.res["knowledge"]) > 0.0 or town.has_built("school"))
	_unlock_ui("axes",
		float(world.axes["tech"]) + float(world.axes["nature"]) + float(world.axes["mystic"]) > 0.0)
	_unlock_ui("magic_tab", not magic.known.is_empty() or not protagonist.training.is_empty())

# --- festival ---------------------------------------------------------------------

var festival_site := ""
var festival_end := 0.0

func festival_active() -> bool:
	return festival_site != "" and clock.abs_minutes() < festival_end

func begin_festival(site_id: String, hours: float) -> void:
	festival_site = site_id
	festival_end = clock.abs_minutes() + hours * 60.0
	_clear_festival_visuals()
	ui_toast("🎉 収穫祭が始まった！みんなが集まってくる", "build")
	log_event("収穫祭が始まり、村じゅうが集まった", "era")
	for v in villagers:
		if v.state != v.State.SLEEPING:
			v._set_destination(site_id, v.State.FREE)

func _update_festival_visuals(delta: float) -> void:
	if not festival_active():
		if festival_site != "":
			festival_site = ""
			_clear_festival_visuals()
		return
	var loc = town.get_loc(festival_site)
	if loc == null:
		_clear_festival_visuals()
		return
	if festival_visual_root == null or not is_instance_valid(festival_visual_root):
		_build_festival_visuals(loc.center())
	else:
		festival_visual_root.position = map_to_world(loc.center(), 0.08)
	var phase: float = clock.abs_minutes() * 0.08 + delta
	for child in festival_visual_root.get_children():
		if child is OmniLight3D:
			var light := child as OmniLight3D
			light.light_energy = 0.55 + (sin(phase + light.position.x * 0.9 + light.position.z * 0.7) * 0.5 + 0.5) * 0.45

func _build_festival_visuals(center_map: Vector2) -> void:
	festival_visual_root = Node3D.new()
	festival_visual_root.name = "FestivalVisual"
	festival_visual_root.position = map_to_world(center_map, 0.08)
	add_visual_node(festival_visual_root)
	_particle_cloud("FestivalGoldMotes", Vector3(0.0, 1.15, 0.0), Color("ffe08a"), 54, 2.8, 2.0, Vector3(0.0, 0.08, 0.0), festival_visual_root)
	_particle_cloud("FestivalGreenMotes", Vector3(0.0, 0.9, 0.0), Color("8fffba"), 34, 3.4, 1.7, Vector3(0.0, 0.05, 0.0), festival_visual_root)
	_particle_cloud("FestivalBlueMotes", Vector3(0.0, 1.35, 0.0), Color("9fd7ff"), 28, 3.0, 1.45, Vector3(0.0, 0.06, 0.0), festival_visual_root)
	var colors := [Color("ffd166"), Color("ff8fab"), Color("80ed99"), Color("90dbf4"), Color("c77dff"), Color("fff1a8")]
	for i in range(6):
		var a := TAU * float(i) / 6.0
		var pos := Vector3(cos(a) * 2.5, 1.15 + float(i % 2) * 0.18, sin(a) * 1.65)
		_festival_lantern(pos, colors[i % colors.size()])

func _festival_lantern(pos: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 12
	mesh.rings = 6
	var bulb := MeshInstance3D.new()
	bulb.name = "FestivalLantern"
	bulb.mesh = mesh
	bulb.position = pos
	bulb.material_override = _emissive_mat(Color(color.r, color.g, color.b, 0.82), 1.7)
	festival_visual_root.add_child(bulb)
	var light := OmniLight3D.new()
	light.name = "FestivalLanternLight"
	light.position = pos
	light.light_color = color
	light.light_energy = 0.75
	light.omni_range = 4.4
	festival_visual_root.add_child(light)

func _clear_festival_visuals() -> void:
	if festival_visual_root and is_instance_valid(festival_visual_root):
		festival_visual_root.queue_free()
	festival_visual_root = null

# --- missions ---------------------------------------------------------------------

func current_mission() -> Dictionary:
	if mission_idx >= missions.size():
		return {}
	return missions[mission_idx]

func _check_missions() -> void:
	if mission_idx >= missions.size() or game_over:
		return
	var m: Dictionary = missions[mission_idx]
	if not _mission_done(m.get("cond", {})):
		return
	world.apply_effects(m.get("reward", {}))
	log_event("ミッション達成:「%s」— %s" % [m.get("title", ""), m.get("reward_text", "")], "era")
	ui_toast("📜 達成!「%s」 %s" % [m.get("title", ""), m.get("reward_text", "")], "build")
	mission_idx += 1

func _mission_done(cond: Dictionary) -> bool:
	if cond.has("building") and not town.has_built(str(cond["building"])):
		return false
	if cond.has("pop") and world.pop() < int(cond["pop"]):
		return false
	if cond.has("era") and world.era < int(cond["era"]):
		return false
	if cond.has("spells") and magic.known.size() < int(cond["spells"]):
		return false
	return true

func _unlock_ui(key: String, cond: bool) -> void:
	if not cond or world.flags.get("ui_" + key, false):
		return
	world.flags["ui_" + key] = true
	var info: String = UI_UNLOCK_INFO.get(key, "")
	if info != "":
		ui_toast(info, "info")
		log_event(info, "info")

func _on_day_started(d: int) -> void:
	world.on_day_started(d)
	protagonist.on_day_started()
	projects.auto_develop()
	protagonist.maybe_auto_train()
	assign_jobs()
	if is_rest_day():
		log_event("今日は安息日。みんな仕事を休み、体をやすめる", "info")
		ui_toast("🌿 今日は安息日", "info")
	_livestock_cycle()
	if game_started and not game_over and not headless_mode:
		save_game(AUTOSAVE_PATH)

const LIVESTOCK := {
	"chicken": {"jp": "にわとり", "feed": 0.2, "produce": 1.5, "cost": 10.0},
	"goat": {"jp": "やぎ", "feed": 0.4, "produce": 2.5, "cost": 12.0},
	"cow": {"jp": "うし", "feed": 1.0, "produce": 4.0, "cost": 25.0},
	"sheep": {"jp": "ひつじ", "feed": 0.5, "produce": 2.2, "cost": 15.0},
}

func _livestock_cycle() -> void:
	# Each morning livestock eat a little and give back more (eggs / milk).
	for an in animals:
		if an.kind == "cat":
			mood_all(1.0)  # the granary cat keeps spirits (and mice) in check
			continue
		var spec: Dictionary = LIVESTOCK.get(an.kind, {})
		if spec.is_empty():
			continue
		if float(world.res["food"]) >= float(spec["feed"]):
			world.add_res("food", -float(spec["feed"]))
			world.add_res("food", float(spec["produce"]))
			an.fed = true
		else:
			an.fed = false

func livestock_daily_yield(kind: String) -> float:
	var spec: Dictionary = LIVESTOCK.get(kind, {})
	if spec.is_empty():
		return 0.0
	return float(spec["produce"]) - float(spec["feed"])

func kill_starving_livestock() -> void:
	for an in animals:
		if LIVESTOCK.has(an.kind):
			var jp: String = LIVESTOCK[an.kind]["jp"]
			animals.erase(an)
			an.queue_free()
			world.add_res("food", 12.0)
			log_event("飢えのなか、「%s」が村の糧になった" % jp, "crisis")
			return

func _update_tint() -> void:
	var m: float = clock.minute_of_day
	var t: float
	if m < 240.0:
		t = 0.0
	elif m < 420.0:
		t = (m - 240.0) / 180.0
	elif m < 1080.0:
		t = 1.0
	elif m < 1380.0:
		t = 1.0 - (m - 1080.0) / 300.0
	else:
		t = 0.0
	var dawn_w := _phase_weight(m, 240.0, 365.0, 520.0)
	var dusk_w := _phase_weight(m, 990.0, 1140.0, 1380.0)
	var night_w := 1.0 - t
	var sky := Color("0b1328").lerp(Color("86abc5"), t)
	sky = sky.lerp(Color("f1a75d"), dusk_w * 0.18).lerp(Color("6f91c4"), dawn_w * 0.14)
	# Night floor lifted (~"1f2c50" base, higher energy): buildings must stay
	# readable as shapes at 23:00, not collapse into silhouettes.
	var ambient := Color("1f2c50").lerp(Color("72816a"), t)
	ambient = ambient.lerp(Color("d28b55"), dusk_w * 0.18).lerp(Color("5d77a8"), night_w * 0.2)
	if world_env and world_env.environment:
		world_env.environment.background_color = sky
		world_env.environment.ambient_light_color = ambient
		world_env.environment.ambient_light_energy = lerpf(0.74, 0.56, t) + dawn_w * 0.03 + dusk_w * 0.04
		world_env.environment.fog_light_color = Color("1d2e55").lerp(Color("8d957d"), t).lerp(Color("f0aa61"), dusk_w * 0.2).lerp(Color("314a82"), dawn_w * 0.12)
		world_env.environment.fog_density = lerpf(0.009, 0.0042, t) + dusk_w * 0.0015
		world_env.environment.fog_sky_affect = lerpf(0.22, 0.04, t) + dusk_w * 0.03
		world_env.environment.adjustment_brightness = lerpf(0.97, 1.02, t) + dawn_w * 0.02 - dusk_w * 0.01
		world_env.environment.adjustment_contrast = 1.04 + night_w * 0.06 + dusk_w * 0.09
		world_env.environment.adjustment_saturation = 1.0 + dusk_w * 0.14 + dawn_w * 0.06 - night_w * 0.04
		world_env.environment.glow_intensity = lerpf(0.36, 0.14, t) + dusk_w * 0.04
		world_env.environment.glow_strength = lerpf(1.05, 0.68, t) + dusk_w * 0.12
		_update_sky(m, t)
	if sun:
		var sun_angle := TAU * (m / 1440.0)
		sun.light_color = Color("8fa6d8").lerp(Color("ffe2b0"), t).lerp(Color("ffb35c"), dusk_w * 0.65).lerp(Color("ffc985"), dawn_w * 0.35)
		sun.light_energy = lerpf(0.45, 1.55, t) + dusk_w * 0.32
		sun.rotation_degrees = Vector3(-28.0 - 30.0 * t, -35.0 + sin(sun_angle) * 34.0, 0.0)
	if night_glow:
		night_glow.light_energy = lerpf(2.4, 0.15, t)
	_update_particle_visibility(t)
	RenderingServer.set_default_clear_color(sky)

func _phase_weight(m: float, start: float, peak: float, end: float) -> float:
	if m < start or m > end:
		return 0.0
	if m <= peak:
		return clampf((m - start) / maxf(1.0, peak - start), 0.0, 1.0)
	return clampf(1.0 - (m - peak) / maxf(1.0, end - peak), 0.0, 1.0)

# --- 3D view -------------------------------------------------------------------

func _configure_viewport_quality() -> void:
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_4X

func _build_3d_view() -> void:
	visual_root = Node3D.new()
	visual_root.name = "View3D"
	add_child(visual_root)

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("10172b")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("263052")
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.18
	env.glow_strength = 0.8
	env.glow_bloom = 0.08
	env.ssao_enabled = true
	env.ssao_radius = 2.2
	env.ssao_intensity = 1.12
	env.ssao_power = 1.35
	env.ssao_detail = 0.5
	env.ssao_horizon = 0.05
	env.ssao_sharpness = 0.72
	env.adjustment_enabled = true
	env.adjustment_brightness = 0.96
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.98
	env.fog_enabled = true
	env.fog_density = 0.028
	env.fog_light_color = Color("17213a")
	env.fog_sky_affect = 0.12
	_setup_sky(env)
	world_env.environment = env
	visual_root.add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("fff0c2")
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 190.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 1.1
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	visual_root.add_child(sun)

	night_glow = OmniLight3D.new()
	night_glow.name = "ShrineNightGlow"
	night_glow.position = map_to_world(Vector2(475.0, 280.0), 4.0)
	night_glow.light_color = Color("8b7fd9")
	night_glow.light_energy = 1.0
	night_glow.omni_range = 28.0
	visual_root.add_child(night_glow)
	_build_ambient_particles()

	camera = Camera3D.new()
	camera.name = "GodCamera"
	camera.current = true
	camera.fov = 46.0
	camera.near = 0.05
	camera.far = 650.0
	visual_root.add_child(camera)
	_update_camera(true)
	_update_tint()

func _setup_sky(env: Environment) -> void:
	sky_textures.clear()
	for key in ["dawn", "day", "dusk", "night"]:
		var tex := U.load_texture_file("res://assets/sky/sky_%s.png" % key)
		if tex:
			sky_textures[key] = tex
	if sky_textures.is_empty():
		sky_material = null
		return
	var sky := Sky.new()
	sky_material = PanoramaSkyMaterial.new()
	sky.sky_material = sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY

func _sky_phase(minute: float) -> String:
	if minute < 240.0:
		return "night"
	if minute < 420.0:
		return "dawn"
	if minute < 1080.0:
		return "day"
	if minute < 1380.0:
		return "dusk"
	return "night"

func _available_sky_key(key: String) -> String:
	if sky_textures.has(key):
		return key
	for fallback in ["day", "dawn", "dusk", "night"]:
		if sky_textures.has(fallback):
			return fallback
	return ""

func _update_sky(minute: float, light_t: float) -> void:
	if sky_material == null or world_env == null or world_env.environment == null:
		return
	var key := _available_sky_key(_sky_phase(minute))
	if key != "" and key != _active_sky:
		sky_material.panorama = sky_textures[key]
		_active_sky = key
	world_env.environment.background_energy_multiplier = lerpf(0.38, 1.0, light_t)

func _build_ambient_particles() -> void:
	shrine_motes = _particle_cloud("ShrineMotes", map_to_world(Vector2(475.0, 275.0), 1.5), Color("d8ccff"), 58, 3.2, 0.95, Vector3(0.0, 0.24, 0.0))
	fireflies = _particle_cloud("NightFireflies", map_to_world(Vector2(490.0, 390.0), 1.0), Color("dfff9a"), 36, 4.8, 23.0, Vector3(0.0, 0.01, 0.0))
	fireflies.visible = false

func _particle_cloud(n: String, pos: Vector3, color: Color, amount: int, lifetime: float, radius: float, gravity: Vector3, parent: Node3D = null) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.randomness = 0.82
	p.position = pos
	p.emitting = true
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = radius
	pm.direction = Vector3(0.0, 1.0, 0.0)
	pm.spread = 42.0
	pm.gravity = gravity
	pm.initial_velocity_min = 0.03
	pm.initial_velocity_max = 0.22
	pm.scale_min = 0.035
	pm.scale_max = 0.095
	pm.color = color
	p.process_material = pm
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.09
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color.r, color.g, color.b, 0.72)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mesh.material = mat
	p.draw_pass_1 = mesh
	var target := visual_root if parent == null else parent
	target.add_child(p)
	return p

func _emissive_mat(color: Color, energy: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat

func _update_particle_visibility(light_t: float) -> void:
	if shrine_motes:
		shrine_motes.visible = true
	if fireflies:
		fireflies.visible = light_t < 0.35

func add_visual_node(node: Node3D) -> void:
	visual_root.add_child(node)

func map_to_world(p: Vector2, height: float = 0.0) -> Vector3:
	return Vector3((p.x - MAP_CENTER.x) * MAP_SCALE, height, (p.y - MAP_CENTER.y) * MAP_SCALE)

func world_to_map(p: Vector3) -> Vector2:
	return Vector2(p.x / MAP_SCALE + MAP_CENTER.x, p.z / MAP_SCALE + MAP_CENTER.y)

func map_size_to_world(v: Vector2) -> Vector2:
	return v * MAP_SCALE

func _update_camera(immediate := false) -> void:
	if camera == null:
		return
	_camera_pitch = clampf(_camera_pitch, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
	_camera_distance = clampf(_camera_distance, CAMERA_MIN_DISTANCE, CAMERA_MAX_DISTANCE)
	_camera_target = _clamp_camera_target(_camera_target)
	if immediate:
		_camera_current_target = _camera_target
		_camera_current_yaw = _camera_yaw
		_camera_current_pitch = _camera_pitch
		_camera_current_distance = _camera_distance
	_apply_camera_transform()

func _update_camera_smoothing(delta: float) -> void:
	if camera == null:
		return
	var t := clampf(1.0 - exp(-delta * 16.0), 0.0, 1.0)
	_camera_current_target = _camera_current_target.lerp(_camera_target, t)
	_camera_current_yaw = lerp_angle(_camera_current_yaw, _camera_yaw, t)
	_camera_current_pitch = lerpf(_camera_current_pitch, _camera_pitch, t)
	_camera_current_distance = lerpf(_camera_current_distance, _camera_distance, t)
	_apply_camera_transform()

func _apply_camera_transform() -> void:
	var horizontal := cos(_camera_current_pitch) * _camera_current_distance
	var height := sin(_camera_current_pitch) * _camera_current_distance
	var offset := Vector3(sin(_camera_current_yaw) * horizontal, height, cos(_camera_current_yaw) * horizontal)
	camera.global_position = _camera_current_target + offset
	camera.look_at(_camera_current_target, Vector3.UP)

func _clamp_camera_target(v: Vector3) -> Vector3:
	return Vector3(clampf(v.x, -44.0, 44.0), 0.0, clampf(v.z, -33.0, 33.0))

func _begin_pan(screen_pos: Vector2) -> void:
	follow_agent = null
	_pan_grab_world = _screen_to_ground(screen_pos)
	_panning = _pan_grab_world != null

func _pan_camera_to(screen_pos: Vector2) -> void:
	if _pan_grab_world == null:
		return
	var current = _screen_to_ground(screen_pos)
	if current == null:
		return
	_camera_target += _pan_grab_world - current
	_update_camera(true)

func _rotate_camera(delta: Vector2) -> void:
	_camera_yaw -= delta.x * 0.0065
	_camera_pitch = clampf(_camera_pitch - delta.y * 0.0034, CAMERA_MIN_PITCH, CAMERA_MAX_PITCH)
	_update_camera()

func _zoom_camera(delta_distance: float, screen_pos: Vector2) -> void:
	var before = _screen_to_ground(screen_pos)
	_camera_distance = clampf(_camera_distance + delta_distance, CAMERA_MIN_DISTANCE, CAMERA_MAX_DISTANCE)
	_update_camera(true)
	if before == null:
		return
	var after = _screen_to_ground(screen_pos)
	if after == null:
		return
	_camera_target += before - after
	_update_camera(true)

func _screen_to_ground(screen_pos: Vector2):
	if camera == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var dist := -origin.y / dir.y
	if dist < 0.0:
		return null
	return origin + dir * dist

func _mouse_to_map(screen_pos: Vector2):
	var hit = _screen_to_ground(screen_pos)
	if hit == null:
		return null
	return world_to_map(hit)

# --- input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		clock.toggle_pause()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_Q:
		_camera_yaw += 0.12
		_update_camera()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_camera_yaw -= 0.12
		_update_camera()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				_begin_pan(event.position)
			else:
				_panning = false
				_pan_grab_world = null
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_begin_pan(event.position)
			else:
				_panning = false
				_pan_grab_world = null
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			# Wheel over a UI panel (e.g. the chronicle log) must never leak
			# into camera zoom, even when the panel's scroll hits its end.
			if get_viewport().gui_get_hovered_control() == null:
				_zoom_camera(-4.5, event.position)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if get_viewport().gui_get_hovered_control() == null:
				_zoom_camera(4.5, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_down = true
				_left_dragging = false
				_rotating = false
				_left_press_pos = event.position
			else:
				var was_click: bool = _left_down and not _left_dragging and event.position.distance_to(_left_press_pos) < CAMERA_CLICK_THRESHOLD
				_left_down = false
				_left_dragging = false
				_rotating = false
				if was_click:
					var mp = _mouse_to_map(event.position)
					if mp == null:
						_select(null)
						return
					_pick_agent(mp)
	if event is InputEventMouseMotion:
		if _left_down:
			if _left_dragging or event.position.distance_to(_left_press_pos) >= CAMERA_CLICK_THRESHOLD:
				_left_dragging = true
				_rotating = true
				_rotate_camera(event.relative)
		elif _rotating:
			_rotate_camera(event.relative)
		elif _panning:
			_pan_camera_to(event.position)

func _pick_agent(mp: Vector2) -> void:
	var best = null
	var best_d := 26.0
	for a in villagers + [protagonist] + animals:
		var dist: float = a.global_position.distance_to(mp)
		if dist < best_d:
			best_d = dist
			best = a
	_select(best)

func _spawn_monster_raid() -> void:
	if headless_mode:
		return
	_clear_monster_raid_visual()
	monster_raid_root = Node3D.new()
	monster_raid_root.name = "MonsterRaidVisual"
	add_visual_node(monster_raid_root)
	monster_raid_started = clock.abs_minutes()
	var kinds := _raid_monster_kinds()
	var count := 2 + randi() % 3
	for i in range(count):
		var monster := Node3D.new()
		var kind: String = kinds[i % kinds.size()]
		monster.name = "Raid" + kind
		var p := Vector2(80.0 + float(i) * 52.0 + randf_range(-10.0, 10.0), 82.0 + randf_range(-8.0, 18.0))
		monster.position = map_to_world(p, 0.0)
		monster_raid_root.add_child(monster)
		var model := _build_dmason_monster(kind)
		if model != null:
			monster.add_child(model)
		else:
			_fallback_skeleton(monster)
		monster_raid_skeletons.append({"node": monster, "base": monster.position, "phase": randf() * TAU, "spread": 0.34 + randf() * 0.18})
	_particle_cloud("RaidMist", map_to_world(Vector2(170.0, 88.0), 0.18), Color(0.72, 0.78, 0.86, 0.36), 34, 3.0, 4.2, Vector3(0.0, 0.02, 0.0), monster_raid_root)

func _raid_monster_kinds() -> Array:
	if world.era <= 1:
		return ["Slime", "Spider"]
	if world.era <= 3:
		return ["Orc", "Skeleton"]
	return ["Golem", "EvilMage"]

func _build_dmason_monster(kind: String) -> Node3D:
	var model := U.load_model(DM_MONSTER_MODEL_DIR + "%sMesh.glb" % kind)
	if model == null:
		return null
	var h := float(DM_MONSTER_HEIGHTS.get(kind, 1.5))
	if not U.fit_model_to_height(model, h):
		model.free()
		return null
	model.name = kind + "Model"
	_apply_atlas_material(model, DM_MONSTER_TEX)
	var anim_name := str(DM_MONSTER_WALK_ANIMS.get(kind, ""))
	if anim_name != "":
		_merge_take_anim(model, DM_MONSTER_ANIM_DIR + kind + "/" + anim_name + ".glb", "Walk")
	return model

func _apply_atlas_material(model: Node3D, texture_path: String, tint := Color.WHITE) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = U.load_texture_file(texture_path)
	mat.albedo_color = tint
	mat.roughness = 1.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).material_override = mat

func _fallback_skeleton(parent: Node3D) -> void:
	var bone := Color("c8c2aa")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = bone
	var body := CapsuleMesh.new()
	body.radius = 0.16
	body.height = 0.9
	var body_i := MeshInstance3D.new()
	body_i.mesh = body
	body_i.position = Vector3(0.0, 0.62, 0.0)
	body_i.material_override = mat
	parent.add_child(body_i)
	var head := SphereMesh.new()
	head.radius = 0.18
	head.height = 0.36
	var head_i := MeshInstance3D.new()
	head_i.mesh = head
	head_i.position = Vector3(0.0, 1.2, 0.0)
	head_i.material_override = mat
	parent.add_child(head_i)

func _update_monster_raid_visual(delta: float) -> void:
	if monster_raid_root == null or not is_instance_valid(monster_raid_root):
		return
	var age: float = clock.abs_minutes() - monster_raid_started
	var alpha := 1.0 if age < 96.0 else clampf((120.0 - age) / 24.0, 0.0, 1.0)
	if alpha <= 0.0:
		_clear_monster_raid_visual()
		return
	for item in monster_raid_skeletons:
		var node: Node3D = item["node"]
		if not is_instance_valid(node):
			continue
		var base: Vector3 = item["base"]
		var phase := float(item["phase"])
		var spread := float(item["spread"])
		var wander := Vector3(sin(age * 0.035 + phase) * spread, 0.0, cos(age * 0.028 + phase * 1.3) * spread)
		node.position = base + wander + Vector3(age * 0.006, 0.0, age * 0.01)
		var to_village := map_to_world(Vector2(430.0, 330.0), 0.0) - node.position
		node.rotation.y = lerp_angle(node.rotation.y, atan2(to_village.x, to_village.z), clampf(delta * 2.5, 0.0, 1.0))
		_set_geometry_alpha(node, alpha)

func _set_geometry_alpha(node: Node, alpha: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).transparency = 1.0 - alpha
	for child in node.get_children():
		_set_geometry_alpha(child, alpha)

func _clear_monster_raid_visual() -> void:
	if monster_raid_root and is_instance_valid(monster_raid_root):
		monster_raid_root.queue_free()
	monster_raid_root = null
	monster_raid_skeletons.clear()
	monster_raid_started = -1.0

func _spawn_war_band() -> void:
	if headless_mode:
		return
	_clear_monster_raid_visual()
	monster_raid_root = Node3D.new()
	monster_raid_root.name = "WarBandVisual"
	add_visual_node(monster_raid_root)
	monster_raid_started = clock.abs_minutes()
	var variants := ["Character_Knight_02", "Character_Soldier_02", "Character_Knight_03", "Character_Soldier_01", "Character_Knight_01"]
	for i in range(variants.size()):
		var sol := Node3D.new()
		sol.name = "WarSoldier"
		var p := Vector2(880.0 + randf_range(-8.0, 8.0),
			170.0 + float(i) * 44.0 + randf_range(-10.0, 10.0))
		sol.position = map_to_world(p, 0.0)
		monster_raid_root.add_child(sol)
		var model := _build_synty_war_soldier(variants[i])
		if model != null:
			sol.add_child(model)
		else:
			_fallback_skeleton(sol)
		monster_raid_skeletons.append({"node": sol, "base": sol.position,
			"phase": randf() * TAU, "spread": 0.3 + randf() * 0.15})
	var flag := U.load_model(SYNTY_KNIGHTS_MODEL_DIR + "SM_Prop_Banner_03.glb")
	if flag != null and U.fit_model_to_height(flag, 1.7):
		flag.name = "WarBanner"
		_apply_atlas_material(flag, SYNTY_KNIGHTS_ATLAS, Color("ffb2aa"))
		flag.position = map_to_world(Vector2(884.0, 148.0), 0.0)
		monster_raid_root.add_child(flag)
	elif flag != null:
		flag.free()
	_particle_cloud("WarDust", map_to_world(Vector2(880.0, 250.0), 0.14),
		Color(0.6, 0.52, 0.4, 0.32), 30, 3.2, 4.0, Vector3(-0.02, 0.015, 0.0), monster_raid_root)

func _build_synty_war_soldier(variant: String) -> Node3D:
	var model := U.load_model(SYNTY_CHARACTER_MODEL)
	if model == null:
		return null
	if not U.fit_model_to_height(model, 1.65):
		model.free()
		return null
	model.name = "SyntyEnemySoldier"
	var keep := _synty_soldier_parts(variant)
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.visible = str(mi.name) in keep
	_apply_atlas_material(model, SYNTY_ENEMY_TEX, Color("ffd7d0"))
	return model

func _synty_soldier_parts(variant: String) -> Array:
	var parts: Array = [variant, "Item_Sword2", "Item_SwordHolder2", "Item_SwordSheath2"]
	if variant.begins_with("Character_Knight"):
		parts.append("Item_WarriorShoulderArmor_L2")
		parts.append("Item_WarriorShoulderArmor_R2")
	else:
		parts.append("Item_Dagger2")
		parts.append("Item_Pouch2")
	return parts

# Presentation-only prowlers for the beast events: orcish beasts pace the
# western treeline and fade out (same wander/fade machinery as the raid).
func _spawn_beast_prowl() -> void:
	if headless_mode:
		return
	_clear_monster_raid_visual()
	monster_raid_root = Node3D.new()
	monster_raid_root.name = "BeastProwlVisual"
	add_visual_node(monster_raid_root)
	monster_raid_started = clock.abs_minutes()
	for i in range(2):
		var beast := Node3D.new()
		beast.name = "ProwlBeast"
		var p := Vector2(60.0 + randf_range(-6.0, 6.0), 420.0 + float(i) * 60.0)
		beast.position = map_to_world(p, 0.0)
		monster_raid_root.add_child(beast)
		var model := U.load_model("res://assets/models/dmason/monster/Meshes/Character/OrcMesh.glb")
		if model != null and U.fit_model_to_height(model, 1.7):
			_apply_atlas_material(model, DM_MONSTER_TEX)
			_merge_take_anim(model, "res://assets/models/dmason/monster/Animations/Orc/WalkFWD_Orc_Anim.glb", "Walk")
			beast.add_child(model)
		elif model != null:
			model.free()
		else:
			_fallback_skeleton(beast)
		monster_raid_skeletons.append({"node": beast, "base": beast.position,
			"phase": randf() * TAU, "spread": 0.5 + randf() * 0.2})

# Merge the single take from a Dungeon Mason animation GLB into `model` and
# loop it (their packs ship mesh and animations as separate files on one rig).
func _merge_take_anim(model: Node3D, anim_path: String, target: String) -> void:
	var src_scene := U.load_model(anim_path)
	if src_scene == null:
		return
	var aps := src_scene.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		var src: AnimationPlayer = aps[0]
		var names := src.get_animation_list()
		if names.size() > 0:
			var anim := src.get_animation(names[0]).duplicate()
			anim.loop_mode = Animation.LOOP_LINEAR
			var lib := AnimationLibrary.new()
			lib.add_animation(target, anim)
			var ap := AnimationPlayer.new()
			model.add_child(ap)
			ap.add_animation_library("", lib)
			ap.play(target)
	src_scene.free()

func _select(a) -> void:
	if selected_agent and is_instance_valid(selected_agent) and selected_agent.has_method("set_selected"):
		selected_agent.set_selected(false)
	selected_agent = a
	follow_agent = a
	if a:
		if a.has_method("set_selected"):
			a.set_selected(true)
		ui.set_tab("person")
	_update_overheads()

# Building names show only for the location under the cursor, so the diorama
# isn't papered over in floating kanji (user feedback).
func _update_location_hover() -> void:
	var hovered = null
	if not headless_mode and game_started and not game_over \
			and get_viewport().gui_get_hovered_control() == null:
		var mp = _mouse_to_map(get_viewport().get_mouse_position())
		if mp != null:
			for l in town.locations.values():
				if Rect2(l.position, l.size_v).has_point(mp):
					hovered = l
					break
	if hovered == hovered_location:
		return
	if hovered_location != null and is_instance_valid(hovered_location):
		hovered_location.set_hovered(false)
	hovered_location = hovered
	if hovered != null:
		hovered.set_hovered(true)

func _build_overhead_layer() -> void:
	overhead_layer = CanvasLayer.new()
	overhead_layer.name = "OverheadLabels"
	overhead_layer.layer = 4
	add_child(overhead_layer)
	overhead_root = Control.new()
	overhead_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overhead_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overhead_root.theme = U.build_theme()
	overhead_layer.add_child(overhead_root)

func _update_overheads() -> void:
	if camera == null or protagonist == null:
		return
	for c in overhead_controls.values():
		if is_instance_valid(c):
			c.visible = false
	var all_agents: Array = [protagonist]
	all_agents.append_array(villagers)
	var buckets: Dictionary = {}
	for a in all_agents:
		if a == null or not is_instance_valid(a) or not a.has_method("set_overhead_display"):
			continue
		var key := str(a.location_id)
		if key == "":
			key = "%d:%d" % [roundi(a.global_position.x / 18.0), roundi(a.global_position.y / 18.0)]
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(a)
	var close_names := _camera_distance <= CAMERA_NAME_DISTANCE
	for key in buckets:
		var group: Array = buckets[key]
		group.sort_custom(func(a, b): return a.display_name < b.display_name)
		for i in range(group.size()):
			var a = group[i]
			var is_selected: bool = a == selected_agent
			var is_hero: bool = a == protagonist
			a.set_overhead_display(is_selected, is_hero, close_names, i)
			_update_overhead_control(a, is_selected, is_hero, close_names, i)

func _overhead_control_for(a) -> Label:
	if overhead_controls.has(a) and is_instance_valid(overhead_controls[a]):
		return overhead_controls[a]
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", U.jp_font())
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.94))
	overhead_root.add_child(l)
	overhead_controls[a] = l
	return l

func _update_overhead_control(a, is_selected: bool, is_hero: bool, close_names: bool, stack_index: int) -> void:
	if overhead_root == null or not is_instance_valid(a) or a.visual == null:
		return
	var show_name := is_selected or is_hero or close_names
	var badge: String = a._state_badge()
	if not show_name and badge == "":
		return
	var label := _overhead_control_for(a)
	label.visible = true
	# Badges shrink with distance so a far-off 🍞 never dwarfs the hut it
	# floats over; names keep a fixed readable size.
	var badge_size := int(clampf(remap(_camera_current_distance, 30.0, 84.0, 22.0, 12.0), 12.0, 22.0))
	label.add_theme_font_size_override("font_size", 17 if show_name else badge_size)
	label.add_theme_color_override("font_color", Color("ffe08a") if is_hero else Color("fff4c9"))
	label.size = Vector2(260.0 if show_name else 48.0, 58.0 if is_selected else 42.0)
	label.text = _overhead_name_text(a, is_selected, is_hero) if show_name else badge
	var world_pos: Vector3 = a.visual.global_position + Vector3(0.0, 3.05 + (0.45 if is_selected else 0.0), 0.0)
	if camera.is_position_behind(world_pos):
		label.visible = false
		return
	var screen := camera.unproject_position(world_pos)
	# People sharing a spot stack upward in screen space (world offsets vanish
	# when zoomed out), and everyone dodges the building's own 3D label.
	var step := 26.0 if show_name else 24.0
	var lift := 0.0 if show_name else 10.0  # badges clear co-located name rows
	screen.y -= lift + float(stack_index % 6) * step
	var loc = town.get_loc(str(a.location_id)) if str(a.location_id) != "" else null
	if loc != null and loc.name_label != null and is_instance_valid(loc.name_label) \
			and loc.name_label.visible:
		var ls := camera.unproject_position(loc.name_label.global_position)
		if absf(ls.x - screen.x) < 130.0 and screen.y > ls.y - 44.0 and screen.y < ls.y + 30.0:
			screen.y = ls.y - 44.0 - lift - float(stack_index % 6) * step
	label.position = screen - label.size * 0.5

func _overhead_name_text(a, is_selected: bool, is_hero: bool) -> String:
	var text: String = ("✦" if is_hero else "") + a.display_name
	if is_selected:
		var action: String = a.action_text()
		if action != "":
			text += "\n" + action
	return text

# --- prayers & dialog -----------------------------------------------------------

func request_prayer() -> void:
	if dialog_open or game_over:
		return
	protagonist.prayed_today = true
	protagonist.prayers_today += 1
	var convo: Dictionary = events.on_prayer()
	if convo["choices"].is_empty():
		return
	if auto_resolve:
		var idx := _auto_choice(convo)
		var resp: String = events.resolve(convo, idx)
		print("[祈り %d日目] %s → %s" % [clock.day, convo["choices"][idx]["label"], resp])
		return
	# 🎲 idle mode: the dice answer everything except the big set pieces
	# (cutin events, era crossroads) — those still stop the world for the god.
	if auto_oracle and not _is_special_convo(convo):
		_dice_resolve(convo)
		return
	dialog_open = true
	var event_id := str(convo.get("event_id", ""))
	var mood := str(convo.get("mood", "normal"))
	if event_id == "monster_raid":
		_spawn_monster_raid()
	elif event_id == "war_attack":
		_spawn_war_band()
	elif event_id == "beast_howl" or event_id == "hunt_beast":
		_spawn_beast_prowl()
	var on_choice := func(idx):
		var payloads: Array = convo.get("payloads", [])
		var p: Dictionary = payloads[idx] if idx >= 0 and idx < payloads.size() else {}
		var resp: String = events.resolve(convo, idx)
		var rmood := mood
		if p.has("train") or p.has("project") or p.get("era_up", false):
			rmood = "smile"
		var eff: Dictionary = p.get("effects", {})
		if eff.has("kill_villagers") or eff.has("flag_war_lost"):
			rmood = "worried"
		var on_done := func(_i):
			dialogue_ui.close()
			dialog_open = false
			_flush_pending_ending()
		dialogue_ui.open(convo["speaker"], resp, [], on_done, event_id, rmood)
	dialogue_ui.open(convo["speaker"], convo["text"], convo["choices"], on_choice, event_id, mood)

func _auto_choice(convo: Dictionary) -> int:
	var payloads: Array = convo["payloads"]
	var good: Array = []
	for i in range(payloads.size()):
		var p: Dictionary = payloads[i]
		if p.has("project") or p.has("train") or p.get("era_up", false):
			good.append(i)
	if good.is_empty():
		return 0
	return good[randi() % good.size()]

func _is_special_convo(convo: Dictionary) -> bool:
	var eid := str(convo.get("event_id", ""))
	if eid != "" and U.load_texture_file("res://assets/illustrations/cutin_%s.png" % eid) != null:
		return true
	for p in convo.get("payloads", []):
		if p.get("era_up", false):
			return true
	return false

func _dice_resolve(convo: Dictionary) -> void:
	var n: int = convo["choices"].size()
	var die := randi() % 6 + 1
	var idx := (die - 1) % n
	# The traveler gate is the god's standing policy (the 歓迎中 toggle), not a
	# gamble — dice refusing half of all arrivals starved population growth.
	if str(convo.get("event_id", "")) == "traveler_arrival":
		idx = 0 if world.accept_villagers else 1
	var label := str(convo["choices"][idx]["label"])
	var resp: String = events.resolve(convo, idx)
	ui_toast("🎲 %d の目 —「%s」" % [die, label], "magic")
	log_event("🎲 サイコロは%dの目 — %s" % [die, label], "info")
	if resp != "":
		protagonist.show_bubble(resp, 6.0, clock.abs_minutes())

func set_auto_oracle(v: bool) -> void:
	if auto_oracle == v:
		return
	auto_oracle = v
	if v:
		ui_toast("🎲 オートモード — 神託はサイコロに委ねられた", "magic")
		log_event("神は世界の行く末をサイコロに委ねた", "era")
	else:
		ui_toast("🎲 オートモードを終えた", "info")

func show_ending(def: Dictionary) -> void:
	game_over = true
	if dialog_open:
		pending_ending = def
		return
	ui.show_ending(def, _ending_stats_bb())

func _flush_pending_ending() -> void:
	if not pending_ending.is_empty():
		var def := pending_ending
		pending_ending = {}
		ui.show_ending(def, _ending_stats_bb())

func _ending_stats_bb() -> String:
	var bb := "[color=#9aa3b5]%d日間の歩み ／ 人口 %d人 ／ 覚えた魔法 %d\n機械 %d ・ 自然 %d ・ 神秘 %d[/color]\n\n" % [
		clock.day, world.pop(), magic.known.size(),
		int(world.axes["tech"]), int(world.axes["nature"]), int(world.axes["mystic"])]
	for h in chronicle.highlights(8):
		bb += "[color=#d9b96a]・%s[/color]\n" % h
	return bb

# --- village management -----------------------------------------------------------

func assign_jobs() -> void:
	var sites: Array = []
	# Every running construction site draws workers; earlier sites first.
	for i in range(projects.sites.size()):
		sites.append({"loc": projects.sites[i]["site"], "slots": 2,
			"prio": 100.0 - float(i) * 4.0})
	for loc in town.workplaces():
		var prio := 40.0
		if loc.production.has("food"):
			prio = 80.0 if float(world.res["food"]) < float(world.pop() * 10) else 60.0
		elif loc.type_id == "forest":
			prio = 50.0
		if loc.production.has("knowledge"):
			prio = 55.0
		if loc.production.has("mana"):
			prio = 45.0
		sites.append({"loc": loc, "slots": loc.slots, "prio": prio})
	sites.sort_custom(func(a, b): return a["prio"] > b["prio"])
	var pool := villagers.duplicate()
	for s in sites:
		for i in range(int(s["slots"])):
			if pool.is_empty():
				break
			var best = pool[0]
			var best_d := 1e9
			for v in pool:
				var dist: float = v.global_position.distance_to(s["loc"].center())
				if dist < best_d:
					best_d = dist
					best = v
			pool.erase(best)
			if best.job_id != s["loc"].id:
				best.job_id = s["loc"].id
				best.on_job_changed()
	for v in pool:
		if v.job_id != "forest":
			v.job_id = "forest"
			v.on_job_changed()
	_assign_homes()

func _assign_homes() -> void:
	# Anyone whose home doesn't exist yet (e.g. the hero before the camp is
	# built) moves into the first home-tagged building with space; camp
	# dwellers upgrade into a real house as soon as one has room.
	if town.by_tag("home").is_empty():
		return
	for a in [protagonist] + villagers:
		var cur = town.get_loc(a.home_id)
		if cur == null:
			var h := _home_with_space()
			if h != "":
				a.home_id = h
		elif str(cur.type_id) == "camp":
			var better := _home_with_space("camp")
			if better != "":
				a.home_id = better
				log_event("%sは小屋に移り住んだ" % a.display_name, "info")

func spawn_villager(newborn := false, quiet := false) -> bool:
	if name_pool.is_empty():
		return false
	var home_id := _home_with_space()
	if home_id == "":
		return false
	var vname: String = name_pool[name_idx % name_pool.size()]
	name_idx += 1
	var a = _add_villager({"id": "v_%d" % name_idx, "name": vname, "home": home_id})
	if newborn:
		var home = town.get_loc(home_id)
		a.global_position = home.stand_global() if home else Vector2(430.0, 340.0)
		log_event("「%s」が生まれた！村に新しい産声が響く" % vname, "pop")
		if not quiet:
			ui_toast("👶 「%s」が生まれた！" % vname, "pop")
	else:
		a.global_position = Vector2(30.0, 620.0)
		log_event("新しい村人「%s」がやってきた" % vname, "pop")
		if not quiet:
			ui_toast("👤 「%s」が村に加わった！" % vname, "pop")
	a.location_id = ""
	a.active_block = ""
	assign_jobs()
	return true

func _home_with_space(exclude_type := "") -> String:
	var residents: Dictionary = {}
	residents[protagonist.home_id] = int(residents.get(protagonist.home_id, 0)) + 1
	for v in villagers:
		residents[v.home_id] = int(residents.get(v.home_id, 0)) + 1
	for loc in town.by_tag("home"):
		if exclude_type != "" and str(loc.type_id) == exclude_type:
			continue
		if int(residents.get(loc.id, 0)) < loc.capacity:
			return loc.id
	return ""

func kill_random_villagers(n: int, reason: String) -> void:
	for i in range(n):
		if villagers.is_empty():
			return
		var v = villagers[randi() % villagers.size()]
		log_event("「%s」が%s" % [v.display_name, reason], "crisis")
		ui_toast("🕯 「%s」が%s…" % [v.display_name, reason], "bad")
		villagers.erase(v)
		if selected_agent == v:
			selected_agent = null
		v.queue_free()
	assign_jobs()

func mood_all(v: float) -> void:
	protagonist.mood = clampf(protagonist.mood + v, 0.0, 100.0)
	for a in villagers:
		a.mood = clampf(a.mood + v, 0.0, 100.0)

func avg_mood() -> float:
	var total: float = protagonist.mood
	for a in villagers:
		total += a.mood
	return total / float(villagers.size() + 1)

func spawn_animal(kind: String, center: Vector2, radius: float = 80.0) -> void:
	var an = AnimalScript.new()
	animals_node.add_child(an)
	an.setup(kind, center, self)
	an.radius = radius
	animals.append(an)

func animal_counts() -> Dictionary:
	var counts: Dictionary = {}
	for an in animals:
		counts[an.kind] = int(counts.get(an.kind, 0)) + 1
	return counts

func livestock_count() -> int:
	var c := animal_counts()
	var total := 0
	for kind in LIVESTOCK:
		total += int(c.get(kind, 0))
	return total

func can_add_livestock(kind := "chicken") -> bool:
	var cost := float(LIVESTOCK.get(kind, {}).get("cost", 10.0))
	return town.has_built("pen") and float(world.res["food"]) >= cost and livestock_count() < 10

func add_livestock(kind: String) -> void:
	if not can_add_livestock(kind):
		return
	world.add_res("food", -float(LIVESTOCK[kind]["cost"]))
	var pen_center := Vector2(600.0, 500.0)
	for loc in town.workplaces():
		if loc.type_id == "pen":
			pen_center = loc.center()
	spawn_animal(kind, pen_center, 55.0)
	log_event("「%s」を家畜に迎えた" % LIVESTOCK[kind]["jp"], "info")

func remove_livestock(kind: String) -> void:
	for an in animals:
		if an.kind == kind:
			animals.erase(an)
			an.queue_free()
			world.add_res("food", 12.0)
			log_event("「%s」が村の糧になった（食料+12）" % LIVESTOCK[kind]["jp"], "info")
			return

func pick_talk(key: String) -> String:
	var pool: Array = dlg_data.get(key, [])
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])

func spawn_animals(spec: Dictionary) -> void:
	var pen_center := Vector2(600.0, 500.0)
	for loc in town.workplaces():
		if loc.type_id == "pen":
			pen_center = loc.center()
	for kind in spec:
		for i in range(int(spec[kind])):
			match str(kind):
				"dog":
					spawn_animal("dog", protagonist.global_position + Vector2(24, 12), 40.0)
					log_event("焚き火の灯りに誘われて、一匹の犬が住みついた", "pop")
					ui_toast("🐕 犬が村に住みついた！", "pop")
				"cat":
					var gc: Vector2 = protagonist.global_position
					for loc in town.locations.values():
						if loc.type_id == "granary" and not loc.under_construction:
							gc = loc.center()
					spawn_animal("cat", gc, 45.0)
					log_event("穀倉に、ねこが住みついた", "pop")
					ui_toast("🐈 ねこが穀倉に住みついた！", "pop")
				"horse":
					spawn_animal("horse", pen_center, 70.0)
					log_event("厩に馬がやってきた。アシタの相棒だ", "pop")
					ui_toast("🐴 馬がやってきた！", "pop")
				_:
					spawn_animal(str(kind), pen_center, 55.0)

func on_villager_died(v, reason: String) -> void:
	log_event("「%s」が%s" % [v.display_name, reason], "crisis")
	villagers.erase(v)
	if selected_agent == v:
		selected_agent = null
	v.queue_free()
	assign_jobs()

func on_action_finished(adef: Dictionary) -> void:
	for k in adef.get("axis", {}):
		world.axes[k] = float(world.axes.get(k, 0.0)) + float(adef["axis"][k])
	world.apply_effects(adef.get("effects", {}))
	log_event("アシタが「%s」をやり遂げた" % adef.get("name", "?"), "info")
	ui_toast("✅ 「%s」を終えた" % adef.get("name", "?"), "info")

func pick_chatter() -> String:
	var pool: Array = []
	if world.starvation_days > 0 or float(world.danger["war"]) > 0.0 or float(world.danger["blight"]) >= 40.0:
		pool = dlg_data.get("chatter_worried", [])
	if pool.is_empty():
		pool = dlg_data.get("chatter_common", []).duplicate()
		pool.append_array(dlg_data.get("chatter_era%d" % world.era, []))
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])

# --- save / load ------------------------------------------------------------------

func save_game(path := SAVE_PATH) -> bool:
	if game_over or not game_started:
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_save_dict()))
	f.close()
	return true

func has_any_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(AUTOSAVE_PATH)

# Loads the manual save; falls back to this morning's autosave.
func load_game() -> bool:
	var path := SAVE_PATH
	if not FileAccess.file_exists(path):
		path = AUTOSAVE_PATH
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return false
	pending_load = parsed
	get_tree().reload_current_scene()
	return true

func _save_dict() -> Dictionary:
	var locs: Array = []
	for l in town.locations.values():
		if l.type_id == "forest" or l.type_id == "riverbank":
			continue
		locs.append({"id": l.id, "type": l.type_id,
			"pos": [l.position.x, l.position.y],
			"built": not l.under_construction, "progress": float(l.progress)})
	var vs: Array = []
	for v in villagers:
		vs.append({"id": v.id, "name": v.display_name, "color": v.color.to_html(false),
			"home": v.home_id, "job": v.job_id,
			"pos": [v.global_position.x, v.global_position.y], "mood": v.mood,
			"hunger": float(v.needs["hunger"]), "energy": float(v.needs["energy"])})
	var ans: Array = []
	for an in animals:
		ans.append({"kind": an.kind,
			"pos": [an.global_position.x, an.global_position.y],
			"radius": float(an.radius)})
	var tspell := ""
	var thours := 0.0
	if not protagonist.training.is_empty():
		tspell = str(protagonist.training["spell"].get("id", ""))
		thours = float(protagonist.training["hours"])
	var seen_out: Dictionary = {}
	for k in events.seen:
		seen_out[str(k)] = int(events.seen[k])
	var chron: Array = []
	var start := maxi(0, chronicle.entries.size() - 250)
	for i in range(start, chronicle.entries.size()):
		var e: Dictionary = chronicle.entries[i]
		chron.append({"day": int(e["day"]), "minute": float(e["minute"]),
			"text": str(e["text"]), "kind": str(e["kind"])})
	return {
		"version": 1,
		"clock": {"day": clock.day, "minute": clock.minute_of_day},
		"world": world.to_dict(),
		"magic": magic.known.duplicate(),
		"events_seen": seen_out,
		"mission_idx": mission_idx,
		"name_idx": name_idx, "color_idx": color_idx,
		"auto_oracle": auto_oracle,
		"locations": locs,
		"sites": projects.to_list(),
		"villagers": vs,
		"animals": ans,
		"hero": {
			"pos": [protagonist.global_position.x, protagonist.global_position.y],
			"home": protagonist.home_id, "mood": protagonist.mood,
			"hunger": float(protagonist.needs["hunger"]),
			"energy": float(protagonist.needs["energy"]),
			"prayed_today": protagonist.prayed_today,
			"prayers_today": protagonist.prayers_today,
			"meals_today": protagonist.meals_today,
			"train_spell": tspell, "train_hours": thours,
		},
		"chronicle": chron,
	}

func _apply_save(d: Dictionary) -> void:
	game_started = true
	var ck: Dictionary = d.get("clock", {})
	clock.day = int(ck.get("day", 1))
	clock.minute_of_day = float(ck.get("minute", 320.0))
	world.from_dict(d.get("world", {}))
	magic.known.clear()
	for id in d.get("magic", []):
		magic.known.append(str(id))
	events.seen.clear()
	for k in d.get("events_seen", {}):
		events.seen[str(k)] = int(d["events_seen"][k])
	mission_idx = int(d.get("mission_idx", 0))
	name_idx = int(d.get("name_idx", 0))
	color_idx = int(d.get("color_idx", 0))
	auto_oracle = bool(d.get("auto_oracle", false))
	town.load_saved(d.get("locations", []), projects)
	projects.load_saved(d.get("sites", []))
	# Replace the fresh-start villagers/animals with the saved ones.
	for v in villagers.duplicate():
		villagers.erase(v)
		v.free()
	for vd in d.get("villagers", []):
		var a = _add_villager({"id": str(vd.get("id", "")), "name": str(vd.get("name", "?")),
			"color": "#" + str(vd.get("color", "cccccc")), "home": str(vd.get("home", ""))})
		var pos: Array = vd.get("pos", [400, 400])
		a.global_position = Vector2(float(pos[0]), float(pos[1]))
		a.job_id = str(vd.get("job", ""))
		a.mood = float(vd.get("mood", 65.0))
		a.needs["hunger"] = float(vd.get("hunger", 70.0))
		a.needs["energy"] = float(vd.get("energy", 80.0))
		a.location_id = ""
		a.active_block = ""
	for an in animals.duplicate():
		animals.erase(an)
		an.free()
	for ad in d.get("animals", []):
		var apos: Array = ad.get("pos", [400, 400])
		spawn_animal(str(ad.get("kind", "deer")),
			Vector2(float(apos[0]), float(apos[1])), float(ad.get("radius", 60.0)))
	var hd: Dictionary = d.get("hero", {})
	var hpos: Array = hd.get("pos", [430, 330])
	protagonist.global_position = Vector2(float(hpos[0]), float(hpos[1]))
	protagonist.home_id = str(hd.get("home", protagonist.home_id))
	protagonist.mood = float(hd.get("mood", 65.0))
	protagonist.needs["hunger"] = float(hd.get("hunger", 70.0))
	protagonist.needs["energy"] = float(hd.get("energy", 80.0))
	protagonist.prayed_today = bool(hd.get("prayed_today", false))
	protagonist.prayers_today = int(hd.get("prayers_today", 0))
	protagonist.meals_today = int(hd.get("meals_today", 0))
	protagonist.location_id = ""
	protagonist.active_block = ""
	protagonist.directive = {}
	protagonist.training = {}
	var tspell := str(hd.get("train_spell", ""))
	if tspell != "":
		var sdef: Dictionary = magic.get_def(tspell)
		if not sdef.is_empty():
			protagonist.training = {"spell": sdef, "hours": float(hd.get("train_hours", 0.0))}
			protagonist.directive = {"type": "train"}
	chronicle.entries.clear()
	for e in d.get("chronicle", []):
		chronicle.entries.append({"day": int(e.get("day", 0)), "minute": float(e.get("minute", 0.0)),
			"text": str(e.get("text", "")), "kind": str(e.get("kind", "info"))})
	assign_jobs()
	_update_tint()
	_update_camera(true)
	clock.set_speed(1)
	log_event("神は世界の記憶を呼び覚ました", "era")
	ui_toast("📂 セーブを読み込んだ — %d日目から再開" % clock.day, "info")

# --- logging shims ------------------------------------------------------------------

func log_event(text: String, kind: String = "info") -> void:
	chronicle.add(clock.day, clock.minute_of_day, text, kind)

func ui_toast(text: String, kind: String = "info") -> void:
	if ui:
		ui.toast(text, kind)

func ui_era_banner(era_i: int, ename: String) -> void:
	if ui == null:
		return
	var c := _chapter_for_era(era_i)
	if c.is_empty():
		ui.era_banner(era_i, ename)
	else:
		# Freeze the sim while the card plays so it never lingers half-faded
		# over normal gameplay (and the era's first morning isn't skipped).
		clock.scene_pause()
		ui.chapter_card(c, func(): clock.scene_resume())

func _chapter_for_era(era_i: int) -> Dictionary:
	var variant := ""
	if era_i >= 2:
		variant = world.dominant_axis()
	for c in chapters_data.get("chapters", []):
		if int(c.get("era", -1)) == era_i and str(c.get("variant", "")) == variant:
			return c
	return {}

# --- opening story ---------------------------------------------------------------------

func begin_after_title() -> void:
	game_started = true
	var pages: Array = story_data.get("prologue", [])
	if pages.is_empty():
		clock.dialog_resume()
		return
	_play_story_page(pages, 0)

func _play_story_page(pages: Array, i: int) -> void:
	if i >= pages.size():
		dialogue_ui.close()
		log_event("アシタは、空の上の神の声を聞いた", "era")
		var c := _chapter_for_era(world.era)
		if c.is_empty():
			return
		# Keep time frozen while the chapter card plays, so the first prayer
		# doesn't open on top of it.
		clock.scene_pause()
		ui.chapter_card(c, func(): clock.scene_resume())
		return
	var pg: Dictionary = pages[i]
	var speaker := str(pg.get("speaker", "アシタ"))
	var mood := str(pg.get("mood", "normal"))
	var raw_choices: Array = pg.get("choices", [])
	var advance := func(_j): _play_story_page(pages, i + 1)
	if raw_choices.is_empty():
		dialogue_ui.open(speaker, str(pg.get("text", "")), [], advance, "", mood)
		return
	var disp: Array = []
	for c in raw_choices:
		disp.append({"label": str(c.get("label", "")), "sub": str(c.get("sub", ""))})
	var on_pick := func(idx):
		var resp: Array = pg.get("responses", [])
		if idx >= 0 and idx < disp.size():
			var first_words := ""
			if idx < resp.size():
				first_words = str(resp[idx].get("text", ""))
			world.history.append({"day": clock.day, "kind": "prologue",
				"title": "神の最初の言葉", "choice": str(disp[idx]["label"]),
				"text": first_words})
		if idx >= 0 and idx < resp.size():
			var r: Dictionary = resp[idx]
			dialogue_ui.open(str(r.get("speaker", "アシタ")), str(r.get("text", "")), [],
				advance, "", str(r.get("mood", "normal")))
		else:
			_play_story_page(pages, i + 1)
	dialogue_ui.open(speaker, str(pg.get("text", "")), disp, on_pick, "", mood)

# --- data -----------------------------------------------------------------------------

func _load_json(path: String, fallback):
	if not FileAccess.file_exists(path):
		push_error("Missing data file: " + path)
		data_ok = false
		return fallback
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if parsed == null:
		push_error("Invalid JSON: " + path)
		data_ok = false
		return fallback
	return parsed

# --- debug modes ------------------------------------------------------------------------

func _run_selftest() -> void:
	auto_resolve = true
	set_process(false)
	var failures: Array = []
	if not data_ok:
		failures.append("data files failed to load")
	var step := 1.0
	# 24 game days: traveler arrivals now consume prayer slots, so progression
	# is a little slower than the original 18-day budget.
	var total := 24 * 1440
	for i in range(total):
		clock.force_advance(step)
		_tick(step)
		if world.ending_id != "":
			break
		for a in villagers + [protagonist]:
			if a.state == AgentScript.State.MOVING and a.move_time > 240.0:
				failures.append("%s stuck moving at day %d" % [a.display_name, clock.day])
				a.move_time = 0.0
	print("=== SELFTEST RESULT ===")
	print("day=%d era=%d (%s) pop=%d ending=%s" % [clock.day, world.era, world.era_name(), world.pop(), world.ending_id])
	print("res: %s" % [world.res])
	print("axes: %s danger: %s" % [world.axes, world.danger])
	print("buildings: %s" % [", ".join(town.building_summary())])
	print("spells: %s" % [", ".join(magic.known)])
	print("chronicle entries: %d" % chronicle.entries.size())
	if world.era < 1 and world.ending_id == "":
		failures.append("era did not advance in 18 days")
	if world.pop() < 4 and world.ending_id == "":
		failures.append("population collapsed: %d" % world.pop())
	# Population must keep pace with auto-development (group arrivals + births
	# land ~30 by day 25 on the fixed seed; 12 leaves RNG headroom).
	if world.pop() < 12 and world.ending_id == "":
		failures.append("population growth too slow: %d" % world.pop())
	if chronicle.entries.size() < 5:
		failures.append("chronicle suspiciously empty")
	if world.ending_id == "":
		failures.append_array(_selftest_saveload())
	if failures.is_empty():
		print("SELFTEST OK")
		get_tree().quit(0)
	else:
		for f in failures:
			print("SELFTEST FAIL: " + f)
		get_tree().quit(1)

# Serialize the live world, apply it back onto this same instance, and check
# nothing was lost — catches save/load schema drift without a GUI run.
func _selftest_saveload() -> Array:
	var fails: Array = []
	game_started = true
	var pop_before: int = world.pop()
	var era_before: int = world.era
	var locs_before: int = town.locations.size()
	var sites_before: int = projects.site_count()
	var known_before: int = magic.known.size()
	var parsed = JSON.parse_string(JSON.stringify(_save_dict()))
	if not (parsed is Dictionary):
		return ["save dict did not survive JSON roundtrip"]
	_apply_save(parsed)
	if world.pop() != pop_before:
		fails.append("saveload pop %d -> %d" % [pop_before, world.pop()])
	if world.era != era_before:
		fails.append("saveload era %d -> %d" % [era_before, world.era])
	if town.locations.size() != locs_before:
		fails.append("saveload locations %d -> %d" % [locs_before, town.locations.size()])
	if projects.site_count() != sites_before:
		fails.append("saveload sites %d -> %d" % [sites_before, projects.site_count()])
	if magic.known.size() != known_before:
		fails.append("saveload spells %d -> %d" % [known_before, magic.known.size()])
	if fails.is_empty():
		print("SAVELOAD OK pop=%d era=%d locs=%d sites=%d" % [
			world.pop(), world.era, town.locations.size(), projects.site_count()])
	return fails

func _run_shot(args: Array = []) -> void:
	auto_resolve = true
	set_process(false)
	var step := 1.0
	var shot_minute := 1110.0
	var shot_name := "shot.png"
	if args.has("--shot-day"):
		shot_minute = 780.0
		shot_name = "shot_day.png"
	elif args.has("--shot-night"):
		shot_minute = 1410.0
		shot_name = "shot_night.png"
	while not (clock.day == 2 and clock.minute_of_day >= shot_minute):
		clock.force_advance(step)
		_tick(step)
	auto_resolve = false
	_check_ui_unlocks()
	_update_tint()
	var shot_agent = protagonist
	_select(shot_agent)
	_camera_target = _clamp_camera_target(map_to_world(shot_agent.global_position))
	_camera_distance = 68.0
	_update_camera(true)
	_update_overheads()
	if ui.toast_box:
		for child in ui.toast_box.get_children():
			child.queue_free()
	var convo: Dictionary = events.on_prayer()
	if not convo["choices"].is_empty():
		dialog_open = true
		dialogue_ui.open(convo["speaker"], convo["text"], convo["choices"], func(_idx): pass,
			str(convo.get("event_id", "")), str(convo.get("mood", "normal")))
		dialogue_ui._finish_typing()
		dialogue_ui.panel.modulate.a = 1.0
		dialogue_ui.dim.modulate.a = 1.0
		dialogue_ui.portrait_frame.modulate.a = 1.0
		dialogue_ui.choices_panel.modulate.a = 1.0
	ui.refresh(1.0)
	await get_tree().process_frame
	await get_tree().process_frame
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://" + shot_name)
	img.save_png(out)
	print("shot saved: " + out)
	get_tree().quit(0)
