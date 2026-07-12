extends Node2D
# A villager. Schedule-driven daily life: sleep, meals, assigned work, and
# evening chatter. While working, produces resources for the world (or build
# progress when assigned to a construction site).

const U = preload("res://scripts/util.gd")
const BubbleScript = preload("res://scripts/bubble.gd")

enum State { SLEEPING, MOVING, WORKING, EATING, FREE, PRAYING, TRAINING, LEADING }

const STATE_NAMES := ["SLEEPING", "MOVING", "WORKING", "EATING", "FREE", "PRAYING", "TRAINING", "LEADING"]
# Per-state marks, drawn by the 2D overhead overlay (emoji-capable there).
# The legacy Label3D badge stays hidden whenever the overlay exists — emoji
# bitmap glyphs would render at broken scale in Label3D.
const STATE_BADGES := {
	State.SLEEPING: "💤",
	State.WORKING: "🔨",
	State.EATING: "🍞",
	State.PRAYING: "🙏",
	State.TRAINING: "✨",
	State.LEADING: "🏗",
}
const MOVE_SPEED := 34.0  # px per game minute

const SCHEDULE := [
	{"key": "sleep", "start": 1320, "end": 360, "action": "sleep", "place": "home"},
	{"key": "breakfast", "start": 360, "end": 390, "action": "eat", "place": "home"},
	{"key": "work_am", "start": 390, "end": 720, "action": "work", "place": "job"},
	{"key": "lunch", "start": 720, "end": 750, "action": "eat", "place": "stay"},
	{"key": "work_pm", "start": 750, "end": 1020, "action": "work", "place": "job"},
	{"key": "free_eve", "start": 1020, "end": 1200, "action": "free", "place": "out"},
	{"key": "dinner", "start": 1200, "end": 1230, "action": "eat", "place": "home"},
	{"key": "free_night", "start": 1230, "end": 1320, "action": "free", "place": "home"},
]

var main
var id: String = ""
var display_name: String = ""
var color := Color.WHITE
var home_id: String = ""
var job_id: String = ""

var needs := {"hunger": 80.0, "energy": 90.0}
var mood := 65.0
var state: int = State.SLEEPING
var active_block := ""
var location_id := ""      # instance id when settled, "" while moving
var move_target := Vector2.ZERO
var move_time := 0.0       # time spent moving toward current target (stuck check)
var pending := {}          # {state, place}
var selected := false
var chatter_cd := 60.0
var free_choice := "plaza"
var rhythm_offset := 0.0  # personal shift of the daily schedule, in minutes

var visual: Node3D
var name_label: Label3D
var badge_label: Label3D
var selection_ring: MeshInstance3D
var model_root: Node3D
var body_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var arm_left: MeshInstance3D
var arm_right: MeshInstance3D
var fishing_root: Node3D
var fishing_pole: MeshInstance3D
var fishing_float: MeshInstance3D
var axe_root: Node3D
var character_model: Node3D
var character_anim: AnimationPlayer
var sleep_z_labels: Array = []
var bubble = null
var _gait_phase := 0.0
var _life_phase := 0.0
var _model_scale := 1.0
var _current_character_anim := ""
var _lie_needs_pose := false  # model's sleep anim lacks the lie-down rotation
var _overhead_selected := false
var _overhead_hero := false
var _overhead_close_names := false
var _overhead_stack := 0

func setup(d: Dictionary, m) -> void:
	main = m
	id = str(d.get("id", "v%d" % randi()))
	display_name = str(d.get("name", id))
	color = Color(str(d.get("color", "#cccccc")))
	home_id = str(d.get("home", "hut_1"))
	needs["hunger"] = 60.0 + randf() * 30.0
	needs["energy"] = 70.0 + randf() * 30.0
	chatter_cd = randf() * 60.0
	rhythm_offset = float((id.hash() % 61) - 30)  # early birds and night owls (±30 min)
	_life_phase = randf() * TAU
	_build_visual()
	var home = main.town.get_loc(home_id)
	if home:
		global_position = home.stand_global()
		location_id = home_id
	elif d.has("pos"):
		# No home exists yet: start in the open wilderness.
		global_position = Vector2(d["pos"][0], d["pos"][1])
		location_id = ""
	_update_label()
	_sync_visual()

# --- per-frame simulation -------------------------------------------------

func sim_tick(gmin: float, ctx: Dictionary) -> void:
	_update_needs(gmin)
	_expire_bubble(ctx)
	_life_phase += gmin * 0.08
	var block := _block_for(ctx["minute_of_day"])
	if block["key"] != active_block:
		active_block = block["key"]
		_apply_block(block, ctx)
	match state:
		State.MOVING:
			_move(gmin)
		State.WORKING:
			_produce(gmin, 1.0)
		State.FREE:
			_chatter(gmin, ctx)
	_sync_visual()

func _block_for(minute: float) -> Dictionary:
	var m := fposmod(minute - rhythm_offset, 1440.0)
	for b in SCHEDULE:
		var s: int = b["start"]
		var e: int = b["end"]
		if s <= e:
			if m >= s and m < e:
				return b
		elif m >= s or m < e:
			return b
	return SCHEDULE[0]

func _apply_block(block: Dictionary, _ctx: Dictionary) -> void:
	var action: String = block["action"]
	if action != "sleep" and main.festival_active():
		# The whole village gathers for the festival.
		_set_destination(main.festival_site, State.FREE)
		return
	if action == "work" and main.is_rest_day():
		action = "free"  # rest day: no work, gather with the others instead
	match action:
		"sleep":
			_set_destination(home_id, State.SLEEPING)
		"eat":
			var place: String = block["place"]
			if place == "stay":
				_enter(State.EATING)
			else:
				_set_destination(home_id, State.EATING)
		"work":
			_set_destination(_job_or_fallback(), State.WORKING)
		"free":
			if block["place"] == "home":
				_set_destination(home_id, State.FREE)
			else:
				var socials: Array = main.town.by_tag("social")
				if not socials.is_empty() and randf() < 0.65:
					_set_destination(socials[randi() % socials.size()].id, State.FREE)
				else:
					_set_destination(home_id, State.FREE)

func _job_or_fallback() -> String:
	if job_id != "" and main.town.get_loc(job_id) != null:
		return job_id
	return "forest"

func on_job_changed() -> void:
	if active_block.begins_with("work"):
		_set_destination(_job_or_fallback(), State.WORKING)

func _set_destination(place_id: String, next_state: int) -> void:
	var loc = main.town.get_loc(place_id)
	if loc == null:
		loc = main.town.get_loc(home_id)
		place_id = home_id
	if loc == null:
		# Nowhere to go (nothing built yet): do it right here in the open.
		_enter(next_state)
		return
	if location_id == place_id and state != State.MOVING:
		_enter(next_state)
		return
	pending = {"state": next_state, "place": place_id}
	move_target = loc.stand_global()
	move_time = 0.0
	location_id = ""
	state = State.MOVING
	_update_label()

func _move_speed() -> float:
	return MOVE_SPEED

func _move(gmin: float) -> void:
	var before := global_position
	global_position = global_position.move_toward(move_target, _move_speed() * gmin)
	_gait_phase += before.distance_to(global_position) * 0.32
	move_time += gmin
	if global_position.distance_to(move_target) < 1.0:
		location_id = pending.get("place", home_id)
		move_time = 0.0
		_enter(int(pending.get("state", State.FREE)))

func _enter(s: int) -> void:
	if s == State.EATING:
		if main.world.consume_meal():
			needs["hunger"] = clampf(needs["hunger"] + 35.0, 0.0, 100.0)
		else:
			mood = clampf(mood - 4.0, 0.0, 100.0)  # went hungry
	state = s
	_update_label()

func _update_needs(gmin: float) -> void:
	var h := gmin / 60.0
	if state == State.SLEEPING:
		needs["hunger"] = clampf(needs["hunger"] - 1.5 * h, 0.0, 100.0)
		needs["energy"] = clampf(needs["energy"] + 14.0 * h, 0.0, 100.0)
	else:
		needs["hunger"] = clampf(needs["hunger"] - 5.0 * h, 0.0, 100.0)
		needs["energy"] = clampf(needs["energy"] - 4.5 * h, 0.0, 100.0)
	mood = move_toward(mood, 60.0, 1.0 * h)
	if needs["hunger"] < 25.0:
		mood = clampf(mood - 3.0 * h, 0.0, 100.0)

func mood_factor() -> float:
	return 0.6 + 0.8 * mood / 100.0

func _produce(gmin: float, rate: float) -> void:
	var loc = main.town.get_loc(location_id)
	if loc == null:
		return
	var hours := gmin / 60.0
	if loc.under_construction:
		main.projects.add_progress_hours(0.6 * hours * rate * mood_factor(), loc)
		return
	for k in loc.production:
		main.world.add_production(loc, k, float(loc.production[k]) * hours * rate * mood_factor())

# --- flavor ---------------------------------------------------------------

func _chatter(gmin: float, ctx: Dictionary) -> void:
	chatter_cd -= gmin
	if chatter_cd > 0.0:
		return
	chatter_cd = 30.0 + randf() * 40.0
	# While the plague runs through the village, coughing drowns out small talk.
	if main.world.flags.get("plague_outbreak", false) and randf() < 0.4:
		show_bubble("ゴホッ、ゴホッ……", 5.0, ctx["abs_minutes"])
		mood = clampf(mood - 2.0, 0.0, 100.0)
		return
	if randf() < 0.45:
		return
	var line: String = main.pick_chatter()
	if line != "":
		show_bubble(line, 6.0, ctx["abs_minutes"])
		mood = clampf(mood + 2.0, 0.0, 100.0)
		main.log_event("%s「%s」" % [display_name, line], "talk")

func show_bubble(text: String, duration_gmin: float, abs_now: float) -> void:
	if bubble:
		bubble.queue_free()
	bubble = BubbleScript.new()
	add_child(bubble)
	bubble.setup(text, abs_now + duration_gmin)
	_refresh_overhead_display()

func _expire_bubble(ctx: Dictionary) -> void:
	if bubble and bubble.expired(ctx["abs_minutes"]):
		bubble.queue_free()
		bubble = null
		_refresh_overhead_display()

func die(reason: String) -> void:
	main.on_villager_died(self, reason)

# --- presentation ---------------------------------------------------------

func _exit_tree() -> void:
	if visual and is_instance_valid(visual):
		visual.queue_free()

func _build_visual() -> void:
	visual = Node3D.new()
	visual.name = "Visual_" + id
	main.add_visual_node(visual)
	selection_ring = _cylinder("Selection", 0.58, 0.03, Vector3(0.0, 0.025, 0.0), Color(1.0, 0.82, 0.32, 0.62), 32, -1.0, true, false)
	selection_ring.visible = false
	model_root = Node3D.new()
	model_root.name = "Model"
	visual.add_child(model_root)
	_build_person_model()
	_build_activity_props()
	_build_sleep_zs()
	name_label = Label3D.new()
	name_label.name = "Name"
	name_label.font = U.jp_font()
	name_label.font_size = 72
	name_label.pixel_size = 0.0062
	name_label.fixed_size = false
	name_label.modulate = Color("fff4c9")
	name_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.96)
	name_label.outline_size = 9
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.no_depth_test = true
	name_label.double_sided = true
	name_label.shaded = false
	name_label.render_priority = 8
	visual.add_child(name_label)
	badge_label = Label3D.new()
	badge_label.name = "StateBadge"
	badge_label.font = U.jp_font()
	badge_label.font_size = 62
	badge_label.pixel_size = 0.0068
	badge_label.fixed_size = false
	badge_label.modulate = Color("fff2cf")
	badge_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.94)
	badge_label.outline_size = 7
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge_label.no_depth_test = true
	badge_label.double_sided = true
	badge_label.shaded = false
	badge_label.render_priority = 7
	visual.add_child(badge_label)

func _is_hero_visual() -> bool:
	return id == "hero" or display_name == "アシタ"

func _hash_index(modulus: int) -> int:
	return int(abs(id.hash()) % modulus)

const DM_HERO_BASE := "res://assets/models/dmason/hero/mesh/CharacterBaseMesh.glb"
const DM_HERO_TEX := "res://assets/models/dmason/hero/texture/PolyArt.png"
const DM_HERO_ANIM_DIR := "res://assets/models/dmason/hero/anim/"
# Which sub-meshes of the modular base stay visible for Ashita's villager look.
const DM_HERO_PARTS := ["Face1", "Hair3", "Cloth1", "Shoe1", "Belt1"]
const DM_HERO_HAIR_TINT := Color("8a5a3a")
# Game animation name -> animation GLB basename from the Modular RPG Hero pack.
const DM_HERO_ANIMS := {
	"Idle": "Idle_noWeapon",
	"Walking_A": "NormalWalk_noWeapon",
	"Lie_Idle": "Sleep_noWeapon",
	"Use_Item": "PickUp_noWeapon",
	"Interact": "PickUp_noWeapon",
	"Sit_Floor_Idle": "StandingIdle_noWeapon",
	"Spellcasting": "Attack02Maintain_MagicWand",
	"Cheer": "Victory_noWeapon",
}

func _build_person_model() -> void:
	if _is_hero_visual() and _build_dmason_hero_model():
		return
	if _build_kaykit_person_model():
		return
	var hero := _is_hero_visual()
	var h := int(abs(id.hash()))
	var skin_options := [Color("f0bd8f"), Color("d9a177"), Color("c98b63"), Color("f2c79b")]
	var hair_options := [Color("3b2a22"), Color("2c211b"), Color("5a3926"), Color("6b4b2c"), Color("1f1b18")]
	var cloth_options := [Color("b95f4a"), Color("5f8c6b"), Color("d0aa5b"), Color("5e82a8"), Color("9a6c93"), Color("7b8c52")]
	var skin: Color = Color("f2bd8c") if hero else skin_options[h % skin_options.size()]
	var hair: Color = Color("332017") if hero else hair_options[int(h / 3) % hair_options.size()]
	var tunic: Color = Color("f4e5b8") if hero else cloth_options[int(h / 5) % cloth_options.size()].lerp(color, 0.28)
	var belt: Color = Color("5f4a96") if hero else tunic.darkened(0.42)
	_model_scale = 1.06 if hero else 1.0
	body_mesh = _capsule("TunicBody", 0.24, 0.92, Vector3(0.0, 0.62, 0.0), tunic)
	_cylinder("WaistBelt", 0.255, 0.13, Vector3(0.0, 0.62, 0.0), belt, 18)
	_sphere("SashKnot", 0.09, Vector3(0.0, 0.62, -0.24), belt.lightened(0.08), Vector3(1.15, 0.9, 0.65))
	var sash_tail := _capsule("SashTail", 0.04, 0.38, Vector3(0.04, 0.39, -0.25), belt.lightened(0.04), Vector3(0.18, 0.0, -0.12))
	sash_tail.scale.x = 0.72
	head_mesh = _sphere("Head", 0.22, Vector3(0.0, 1.18, 0.0), skin, Vector3(1.0, 0.94, 1.0))
	_sphere("Nose", 0.035, Vector3(0.0, 1.16, -0.205), skin.darkened(0.08), Vector3(0.7, 1.0, 0.55))
	for x in [-0.075, 0.075]:
		_sphere("Eye", 0.025, Vector3(x, 1.22, -0.205), Color("241913"), Vector3(1.0, 0.9, 0.45))
	arm_left = _capsule("LeftSleeve", 0.055, 0.58, Vector3(-0.29, 0.66, -0.02), tunic.darkened(0.04), Vector3(0.0, 0.0, -0.18))
	arm_right = _capsule("RightSleeve", 0.055, 0.58, Vector3(0.29, 0.66, -0.02), tunic.darkened(0.04), Vector3(0.0, 0.0, 0.18))
	for x in [-0.31, 0.31]:
		_sphere("Hand", 0.055, Vector3(x, 0.37, -0.02), skin, Vector3(0.9, 0.75, 0.9))
	for x in [-0.08, 0.08]:
		_cylinder("Leg", 0.045, 0.34, Vector3(x, 0.19, 0.02), Color("5b4433"), 8)
	_sphere("FootLeft", 0.06, Vector3(-0.1, 0.05, -0.05), Color("372920"), Vector3(1.25, 0.45, 0.8))
	_sphere("FootRight", 0.06, Vector3(0.1, 0.05, -0.05), Color("372920"), Vector3(1.25, 0.45, 0.8))
	_build_hair(hair, 4 if hero else h % 4)
	if hero:
		_cylinder("NecklaceLeft", 0.012, 0.44, Vector3(-0.07, 1.0, -0.225), Color("1b1511"), 6)
		_cylinder("NecklaceRight", 0.012, 0.44, Vector3(0.07, 1.0, -0.225), Color("1b1511"), 6)
		_box("WoodPendant", Vector3(0.13, 0.18, 0.045), Vector3(0.0, 0.86, -0.25), Color("7a4f24"))
	else:
		_sphere("ClothPin", 0.05, Vector3(0.0, 0.86, -0.245), belt.lightened(0.18), Vector3(1.0, 0.8, 0.55))

# The hero is assembled from the Modular RPG Hero pack (Dungeon Mason): pick
# a villager-looking part set from the master mesh, apply the PolyArt atlas
# (hair tinted brown), and merge the daily-life animations, whose GLBs each
# carry a single take on the same rig.
func _build_dmason_hero_model() -> bool:
	var model := U.load_model(DM_HERO_BASE)
	if model == null:
		return false
	if not U.fit_model_to_height(model, 1.5):
		model.free()
		return false
	var tex := U.load_texture_file(DM_HERO_TEX)
	if tex == null:
		model.free()
		return false
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_texture = tex
	body_mat.roughness = 1.0
	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_texture = tex
	hair_mat.albedo_color = DM_HERO_HAIR_TINT
	hair_mat.roughness = 1.0
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.visible = mi.name in DM_HERO_PARTS
		if mi.visible:
			mi.material_override = hair_mat if str(mi.name).begins_with("Hair") else body_mat
	var lib := AnimationLibrary.new()
	for target in DM_HERO_ANIMS:
		var src_scene := U.load_model(DM_HERO_ANIM_DIR + str(DM_HERO_ANIMS[target]) + ".glb")
		if src_scene == null:
			continue
		var aps := src_scene.find_children("*", "AnimationPlayer", true, false)
		if not aps.is_empty():
			var src: AnimationPlayer = aps[0]
			var names := src.get_animation_list()
			if names.size() > 0:
				lib.add_animation(str(target), src.get_animation(names[0]).duplicate())
		src_scene.free()
	character_model = model
	character_model.name = "DmasonHero"
	# The pack's Sleep take keeps the body vertical (root motion was authored
	# on the controller, not the rig) — lay the model down ourselves.
	_lie_needs_pose = true
	model_root.add_child(character_model)
	if lib.get_animation_list().size() > 0:
		var ap := AnimationPlayer.new()
		character_model.add_child(ap)
		ap.add_animation_library("", lib)
		character_anim = ap
	_model_scale = 1.08
	return true

func _build_kaykit_person_model() -> bool:
	var model := U.load_model(_character_model_path())
	if model == null:
		return false
	model.name = "KayKitCharacter"
	if not U.fit_model_to_height(model, 1.42 if _is_hero_visual() else 1.35):
		model.free()
		return false
	character_model = model
	# The pack characters come armed; nobody in this village carries weapons.
	for slot in model.find_children("handslot_*", "", true, false):
		for held in slot.get_children():
			held.queue_free()
	model_root.add_child(character_model)
	var anims := character_model.find_children("*", "AnimationPlayer", true, false)
	if not anims.is_empty():
		var ap := anims[0] as AnimationPlayer
		# VRM models expose an AnimationPlayer for facial expressions only;
		# without a locomotion set, leave character_anim null so _sync_visual
		# falls back to procedural sway and the lie-down sleeping pose.
		if ap.has_animation("Idle") or ap.has_animation("Walking_A") or ap.has_animation("Walk"):
			character_anim = ap
	if _character_model_path().get_extension().to_lower() == "vrm":
		_relax_vrm_pose(character_model)
	_model_scale = 1.08 if _is_hero_visual() else 1.0
	return true

# VRoid models load in T-pose (arms straight out); drop the upper arms so the
# character stands in a natural A-pose.
func _relax_vrm_pose(model: Node3D) -> void:
	var skels := model.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	var skel: Skeleton3D = skels[0]
	# Local +X rotation on both upper arms drops them to the sides (verified
	# empirically with tools/vrm_probe.gd against VRoid humanoid rigs).
	for side in [["LeftUpperArm", "J_Bip_L_UpperArm"], ["RightUpperArm", "J_Bip_R_UpperArm"]]:
		var bi: int = skel.find_bone(str(side[0]))
		if bi < 0:
			bi = skel.find_bone(str(side[1]))
		if bi >= 0:
			var pose := skel.get_bone_pose_rotation(bi)
			skel.set_bone_pose_rotation(bi,
				pose * Quaternion(Vector3(1.0, 0.0, 0.0), deg_to_rad(62.0)))

func _character_model_path() -> String:
	if _is_hero_visual():
		# Anime-style hero: the player's own VRoid model wins; the CC-BY
		# sample stands in until assets/models/vroid/ashita.vrm exists.
		if FileAccess.file_exists("res://assets/models/vroid/ashita.vrm"):
			return "res://assets/models/vroid/ashita.vrm"
		if FileAccess.file_exists("res://assets/models/vroid/sample_godette.vrm"):
			return "res://assets/models/vroid/sample_godette.vrm"
		return "res://assets/models/characters/Rogue.glb"
	var h := _hash_index(19)
	if h == 0:
		return "res://assets/models/characters/Mage.glb"
	if h % 5 == 0:
		return "res://assets/models/characters/Rogue_Hooded.glb"
	if h % 3 == 0:
		return "res://assets/models/characters/Barbarian.glb"
	return "res://assets/models/characters/Rogue.glb"

func _build_hair(hair: Color, style: int) -> void:
	_sphere("HairCap", 0.18, Vector3(0.0, 1.32, -0.01), hair, Vector3(1.12, 0.55, 1.0))
	_sphere("HairBack", 0.14, Vector3(0.0, 1.22, 0.12), hair.darkened(0.05), Vector3(0.95, 0.95, 0.65))
	if style == 4:
		for i in range(5):
			var x := -0.18 + float(i) * 0.09
			var y := 1.27 + sin(float(i) * 1.7) * 0.035
			_sphere("FrontCurl", 0.075, Vector3(x, y, -0.16), hair.lightened(0.04 if i % 2 == 0 else 0.0), Vector3(0.95, 1.2, 0.55))
		for x in [-0.22, 0.22]:
			var side := _capsule("SideTuft", 0.045, 0.26, Vector3(x, 1.21, -0.03), hair, Vector3(0.0, 0.0, -0.55 if x < 0.0 else 0.55))
			side.scale.z = 0.72
		_capsule("BackTuft", 0.05, 0.3, Vector3(0.12, 1.13, 0.12), hair.darkened(0.08), Vector3(0.58, 0.0, -0.35))
		return
	match style:
		0:
			for x in [-0.13, 0.0, 0.13]:
				_sphere("ShortBang", 0.07, Vector3(x, 1.27, -0.16), hair, Vector3(0.9, 1.05, 0.55))
		1:
			_sphere("TopKnot", 0.095, Vector3(0.0, 1.47, 0.02), hair.lightened(0.05), Vector3(1.0, 0.8, 1.0))
			for x in [-0.16, 0.16]:
				_sphere("PartedBang", 0.07, Vector3(x, 1.27, -0.15), hair, Vector3(0.75, 1.15, 0.55))
		2:
			for i in range(4):
				var x := -0.18 + float(i) * 0.12
				_sphere("CurlyLock", 0.068, Vector3(x, 1.28 + float(i % 2) * 0.025, -0.15), hair.lightened(0.03), Vector3(1.0, 1.0, 0.6))
			for x in [-0.23, 0.23]:
				_sphere("SidePuff", 0.075, Vector3(x, 1.19, -0.01), hair.darkened(0.04), Vector3(0.78, 1.05, 0.78))
		_:
			_capsule("LeftSweep", 0.055, 0.28, Vector3(-0.12, 1.28, -0.15), hair, Vector3(0.0, 0.0, 0.52))
			_capsule("RightSweep", 0.055, 0.24, Vector3(0.12, 1.27, -0.15), hair, Vector3(0.0, 0.0, -0.48))
			_sphere("SideLock", 0.075, Vector3(0.22, 1.19, 0.0), hair.darkened(0.03), Vector3(0.72, 1.1, 0.75))

func _build_activity_props() -> void:
	fishing_root = Node3D.new()
	fishing_root.name = "FishingRig"
	fishing_root.position = Vector3(0.38, 0.74, -0.14) if character_model else Vector3(0.3, 0.82, -0.18)
	model_root.add_child(fishing_root)
	fishing_pole = _prop_cylinder(fishing_root, "FishingPole", 0.012, 1.42, Vector3(0.28, 0.42, -0.02), Color("7a5b35"), Vector3(0.0, 0.0, -0.62))
	_prop_cylinder(fishing_root, "FishingLine", 0.004, 0.78, Vector3(0.78, 0.02, -0.14), Color(0.86, 0.92, 0.96, 0.76))
	fishing_float = _prop_sphere(fishing_root, "FishingFloat", 0.045, Vector3(0.78, -0.39, -0.14), Color("d94c3d"), Vector3(1.0, 0.7, 1.0), true)
	fishing_root.visible = false
	axe_root = Node3D.new()
	axe_root.name = "AxeRig"
	axe_root.position = Vector3(0.36, 0.72, -0.14) if character_model else Vector3(0.32, 0.78, -0.18)
	model_root.add_child(axe_root)
	_prop_cylinder(axe_root, "AxeHandle", 0.022, 0.72, Vector3(0.0, 0.0, 0.0), Color("6c4b30"), Vector3(0.0, 0.0, -0.82))
	_prop_box(axe_root, "AxeHead", Vector3(0.2, 0.08, 0.06), Vector3(0.21, 0.25, 0.0), Color("a4a6a2"))
	axe_root.visible = false

func _build_sleep_zs() -> void:
	sleep_z_labels.clear()
	for i in range(3):
		var z := Label3D.new()
		z.name = "SleepZ"
		z.text = "z"
		z.font = U.jp_font()
		z.font_size = 48 - i * 6
		z.pixel_size = 0.0065
		z.fixed_size = false
		z.modulate = Color(0.74, 0.88, 1.0, 0.0)
		z.outline_modulate = Color(0.0, 0.0, 0.0, 0.65)
		z.outline_size = 4
		z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		z.no_depth_test = true
		z.double_sided = true
		z.shaded = false
		z.visible = false
		z.render_priority = 6
		visual.add_child(z)
		sleep_z_labels.append(z)

func _mat(c: Color, emission := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.82
	m.metallic = 0.0
	m.metallic_specular = 0.18
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emission:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.05
	return m

func _part_parent(attach_to_model := true) -> Node3D:
	if attach_to_model and model_root != null:
		return model_root
	return visual

func _cylinder(n: String, radius: float, height: float, pos: Vector3, c: Color, segments := 14, top_radius := -1.0, emission := false, attach_to_model := true) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = segments
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(c, emission)
	_part_parent(attach_to_model).add_child(mi)
	return mi

func _capsule(n: String, radius: float, height: float, pos: Vector3, c: Color, rot := Vector3.ZERO, attach_to_model := true) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(c)
	_part_parent(attach_to_model).add_child(mi)
	return mi

func _sphere(n: String, radius: float, pos: Vector3, c: Color, scale := Vector3.ONE, emission := false, attach_to_model := true) -> MeshInstance3D:
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
	mi.material_override = _mat(c, emission)
	_part_parent(attach_to_model).add_child(mi)
	return mi

func _box(n: String, size: Vector3, pos: Vector3, c: Color, emission := false, attach_to_model := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(c, emission)
	_part_parent(attach_to_model).add_child(mi)
	return mi

func _prop_cylinder(parent: Node3D, n: String, radius: float, height: float, pos: Vector3, c: Color, rot := Vector3.ZERO, emission := false, top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 8
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat(c, emission)
	parent.add_child(mi)
	return mi

func _prop_sphere(parent: Node3D, n: String, radius: float, pos: Vector3, c: Color, scale := Vector3.ONE, emission := false) -> MeshInstance3D:
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
	mi.material_override = _mat(c, emission)
	parent.add_child(mi)
	return mi

func _prop_box(parent: Node3D, n: String, size: Vector3, pos: Vector3, c: Color, emission := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(c, emission)
	parent.add_child(mi)
	return mi

func promote_hero_visual() -> void:
	if visual == null:
		return
	_model_scale = 1.08
	if model_root:
		model_root.scale = Vector3.ONE * _model_scale
	if body_mesh:
		body_mesh.scale = Vector3(1.12, 1.08, 1.12)
	# No halo ring — it read as clutter (and a noose while sleeping…); the
	# gold ✦ name label is enough to mark the hero.
	name_label.modulate = Color("ffe08a")

func _sync_visual() -> void:
	if visual == null:
		return
	var moving := state == State.MOVING
	var talking := bubble != null
	var sleeping := state == State.SLEEPING
	var loc_type := _current_location_type()
	var fishing := state == State.WORKING and loc_type == "riverbank"
	var chopping := state == State.WORKING and loc_type == "forest"
	_sync_character_animation(moving, talking, sleeping, fishing, chopping)
	var bob := sin(_gait_phase * 1.15) * 0.06 + sin(_gait_phase * 2.1) * 0.018 if moving else 0.0
	if talking and not moving:
		bob = sin(_life_phase * 2.2) * 0.018
	visual.position = main.map_to_world(global_position, 0.0 if sleeping else bob)
	if model_root:
		# VRM models ship without baked animations (character_anim == null);
		# give them the primitive-model poses plus a light procedural sway so
		# they lie down when sleeping and don't glide like statues.
		var animless := character_model != null and character_anim == null
		var use_pose := character_model == null or animless
		var lie_pose := sleeping and (use_pose or _lie_needs_pose)
		var pose_pos := Vector3(0.44, 0.24, 0.0) if lie_pose else Vector3.ZERO
		var pose_rot := Vector3(0.0, 0.0, PI * 0.5) if lie_pose else Vector3.ZERO
		var pose_scale := _model_scale if character_model else _model_scale * (0.92 if sleeping else 1.0)
		if animless and not sleeping:
			if moving:
				pose_rot.z = sin(_gait_phase * 0.72) * 0.06
				pose_rot.x = 0.05
			elif chopping:
				pose_rot.x = 0.12 + sin(_life_phase * 5.0) * 0.1
			elif fishing:
				pose_rot.x = 0.08
			elif talking:
				pose_rot.x = sin(_life_phase * 2.3) * 0.03
		model_root.position = model_root.position.lerp(pose_pos, 0.24)
		model_root.rotation.x = lerp_angle(model_root.rotation.x, pose_rot.x, 0.24)
		model_root.rotation.y = lerp_angle(model_root.rotation.y, pose_rot.y, 0.24)
		model_root.rotation.z = lerp_angle(model_root.rotation.z, pose_rot.z, 0.24)
		model_root.scale = Vector3.ONE * pose_scale
	if body_mesh:
		if sleeping:
			body_mesh.rotation = Vector3.ZERO
		else:
			body_mesh.rotation.z = sin(_gait_phase * 0.72) * 0.045 if moving else 0.0
			body_mesh.rotation.x = sin(_life_phase * 2.3) * 0.025 if talking and not moving else 0.0
			if chopping:
				body_mesh.rotation.x += sin(_life_phase * 5.0) * 0.06
			elif fishing:
				body_mesh.rotation.z -= 0.035
	if head_mesh:
		head_mesh.position.y = 1.18 + (0.0 if sleeping else (sin(_gait_phase * 1.7 + 0.6) * 0.025 if moving else 0.0) + (sin(_life_phase * 3.2) * 0.018 if talking else 0.0))
	if arm_left and arm_right:
		_sync_arm_pose(fishing, chopping, sleeping)
	_sync_activity_props(fishing, chopping, sleeping)
	_sync_sleep_zs(sleeping)
	if selection_ring:
		var pulse := 1.0 + sin(_life_phase * 1.6) * 0.08 if selected else 1.0
		selection_ring.scale = Vector3(pulse, 1.0, pulse)
	if moving:
		var dir := move_target - global_position
		if dir.length() > 0.1:
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(dir.x, dir.y), 0.22)
	if bubble and bubble.has_method("sync_visual"):
		bubble.sync_visual()
	_face_overhead_to_camera()

func _current_location_type() -> String:
	if location_id == "":
		return ""
	var loc = main.town.get_loc(location_id)
	return loc.type_id if loc else ""

func _sync_arm_pose(fishing: bool, chopping: bool, sleeping: bool) -> void:
	if sleeping:
		arm_left.rotation = Vector3(0.0, 0.0, -0.18)
		arm_right.rotation = Vector3(0.0, 0.0, 0.18)
		return
	if fishing:
		arm_left.rotation = Vector3(0.0, 0.0, -0.35)
		arm_right.rotation = Vector3(0.0, 0.0, -0.72 + sin(_life_phase * 3.7) * 0.035)
		return
	if chopping:
		var swing := sin(_life_phase * 5.0)
		arm_left.rotation = Vector3(0.0, 0.0, -0.38 - swing * 0.16)
		arm_right.rotation = Vector3(0.0, 0.0, -0.72 - swing * 0.34)
		return
	arm_left.rotation = Vector3(0.0, 0.0, -0.18)
	arm_right.rotation = Vector3(0.0, 0.0, 0.18)

func _sync_activity_props(fishing: bool, chopping: bool, sleeping: bool) -> void:
	if fishing_root:
		fishing_root.visible = fishing and not sleeping
		if fishing_root.visible:
			fishing_root.rotation.z = -0.06 + sin(_life_phase * 3.8 + float(_hash_index(11))) * 0.055
	if fishing_pole and fishing_root and fishing_root.visible:
		fishing_pole.rotation.z = -0.62 + sin(_life_phase * 5.1) * 0.025
	if fishing_float and fishing_root and fishing_root.visible:
		fishing_float.position.y = -0.39 + sin(_life_phase * 4.3 + 0.8) * 0.035
	if axe_root:
		axe_root.visible = chopping and not sleeping
		if axe_root.visible:
			axe_root.rotation.z = -0.25 + sin(_life_phase * 5.0) * 0.58

func _sync_sleep_zs(sleeping: bool) -> void:
	for i in range(sleep_z_labels.size()):
		var z: Label3D = sleep_z_labels[i]
		z.visible = sleeping
		if not sleeping:
			continue
		var phase := _life_phase * 0.62 + float(i) * 1.15
		z.position = Vector3(-0.42 + float(i) * 0.2, 1.12 + float(i) * 0.18 + sin(phase) * 0.08, -0.2)
		var c := z.modulate
		c.a = 0.34 + (sin(phase + 0.7) * 0.5 + 0.5) * 0.42
		z.modulate = c

func bubble_anchor_world() -> Vector3:
	return main.map_to_world(global_position, 2.15)

func _display_label_name() -> String:
	return display_name

func _name_label_base_height() -> float:
	return 2.34

func _badge_label_base_height() -> float:
	return 2.24

func _state_badge() -> String:
	return str(STATE_BADGES.get(state, ""))

func _update_label() -> void:
	_refresh_overhead_display()

func set_overhead_display(is_selected: bool, is_hero: bool, close_names: bool, stack_index: int) -> void:
	_overhead_selected = is_selected
	_overhead_hero = is_hero
	_overhead_close_names = close_names
	_overhead_stack = stack_index
	_refresh_overhead_display()

func _refresh_overhead_display() -> void:
	if name_label == null or badge_label == null:
		return
	var stack_y := float(_overhead_stack % 6) * 0.18
	var show_name := _overhead_selected or _overhead_hero or _overhead_close_names
	# The screen-space overhead layer (main.overhead_root) is the single source
	# of truth for names/badges; the 3D labels stay hidden while it exists so
	# names never render twice.
	var use_2d: bool = main != null and main.overhead_root != null
	var action := action_text()
	name_label.text = _display_label_name() + ("\n" + action if _overhead_selected and action != "" else "")
	name_label.position = Vector3(0.0, _name_label_base_height() + stack_y + (0.85 if _overhead_selected else 0.0), 0.0)
	name_label.visible = show_name and not use_2d
	badge_label.text = _state_badge()
	badge_label.position = Vector3(0.0, _badge_label_base_height() + stack_y, 0.0)
	badge_label.visible = not use_2d and not show_name and badge_label.text != "" and bubble == null
	_face_overhead_to_camera()

func _face_overhead_to_camera() -> void:
	if main == null or main.camera == null or name_label == null or badge_label == null:
		return
	if name_label.visible:
		name_label.look_at(main.camera.global_position, Vector3.UP)
	if badge_label.visible:
		badge_label.look_at(main.camera.global_position, Vector3.UP)

func _sync_character_animation(moving: bool, talking: bool, sleeping: bool, fishing: bool, chopping: bool) -> void:
	if character_anim == null:
		return
	var desired := "Idle"
	match state:
		State.MOVING:
			desired = ["Walking_A", "Walking_B", "Walking_C"][_hash_index(3)]
		State.WORKING, State.LEADING:
			desired = "Use_Item" if (fishing or chopping) else "Interact"
		State.SLEEPING:
			desired = "Lie_Idle"
		State.PRAYING, State.EATING:
			desired = "Sit_Floor_Idle"
		State.TRAINING:
			desired = "Spellcasting"
		State.FREE:
			var festival_cheer: bool = main != null and main.festival_active() and location_id == main.festival_site and sin(_life_phase * 0.75 + float(_hash_index(7))) > 0.42
			desired = "Cheer" if (talking or festival_cheer) and sin(_life_phase * 0.8) > 0.2 else "Idle"
	if not character_anim.has_animation(desired):
		desired = "Interact" if character_anim.has_animation("Interact") and not moving and not sleeping else "Idle"
	if not character_anim.has_animation(desired):
		return
	var anim := character_anim.get_animation(desired)
	if anim:
		anim.loop_mode = Animation.LOOP_LINEAR
	if _current_character_anim != desired:
		character_anim.play(desired, 0.18)
		_current_character_anim = desired

func set_selected(v: bool) -> void:
	selected = v
	if selection_ring:
		selection_ring.visible = selected
	_refresh_overhead_display()

func action_text() -> String:
	var place_name := ""
	var loc = main.town.get_loc(location_id) if location_id != "" else null
	if loc:
		place_name = loc.display_name
	match state:
		State.SLEEPING:
			return "眠っている"
		State.MOVING:
			return "移動中"
		State.WORKING:
			return "%sで働いている" % place_name
		State.EATING:
			return "食事中"
		State.FREE:
			return "くつろいでいる"
		State.PRAYING:
			return "祠で祈っている"
		State.TRAINING:
			return "魔法を修行している"
		State.LEADING:
			return "建設を指揮している"
	return ""
