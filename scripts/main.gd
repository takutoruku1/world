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
const UIScript = preload("res://scripts/ui.gd")
const ChronicleScript = preload("res://scripts/chronicle.gd")

const VILLAGER_COLORS := [
	"#e07a5f", "#81b29a", "#f2cc8f", "#6fa8dc", "#c98bb9",
	"#94b0da", "#e5989b", "#8fbf9f", "#d9b96a", "#a48fd9",
	"#7fc9c9", "#d98f6a",
]

var clock
var terrain
var town
var world
var magic
var projects
var events
var dialogue_ui
var ui
var chronicle
var protagonist
var villagers: Array = []
var animals: Array = []
var agents_node: Node2D
var animals_node: Node2D
var tint: CanvasModulate

var dlg_data: Dictionary = {}
var name_pool: Array = []
var name_idx := 0
var color_idx := 0

var selected_agent = null
var dialog_open := false
var pending_ending := {}
var auto_resolve := false
var game_over := false
var data_ok := true

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest") or args.has("--shot"):
		seed(20260711)
	else:
		randomize()
	RenderingServer.set_default_clear_color(Color("0e1016"))
	_build_world()
	if args.has("--selftest"):
		_run_selftest()
	elif args.has("--shot"):
		_run_shot()

func _build_world() -> void:
	chronicle = ChronicleScript.new()
	clock = ClockScript.new()
	clock.name = "Clock"
	add_child(clock)

	terrain = TerrainScript.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup()

	town = TownScript.new()
	town.name = "Town"
	add_child(town)

	agents_node = Node2D.new()
	agents_node.name = "Agents"
	add_child(agents_node)
	animals_node = Node2D.new()
	animals_node.name = "Animals"
	add_child(animals_node)

	tint = CanvasModulate.new()
	tint.name = "Tint"
	add_child(tint)

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

	clock.day_started.connect(_on_day_started)
	assign_jobs()
	log_event("小さな祠のまわりに、%d人の暮らしが始まった" % world.pop(), "era")

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
	if game_over:
		ui.refresh(delta)
		return
	var gmin: float = clock.advance(delta)
	_tick(gmin)
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

func _on_day_started(d: int) -> void:
	world.on_day_started(d)
	protagonist.on_day_started()
	assign_jobs()

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
	tint.color = Color(0.5, 0.55, 0.8).lerp(Color.WHITE, t)

# --- input ---------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		clock.toggle_pause()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := get_global_mouse_position()
		var best = null
		var best_d := 20.0
		for a in villagers + [protagonist]:
			var dist: float = a.global_position.distance_to(mp)
			if dist < best_d:
				best_d = dist
				best = a
		_select(best)

func _select(a) -> void:
	if selected_agent and is_instance_valid(selected_agent):
		selected_agent.set_selected(false)
	selected_agent = a
	if a:
		a.set_selected(true)
		ui.set_tab("person")

# --- prayers & dialog -----------------------------------------------------------

func request_prayer() -> void:
	if dialog_open or game_over:
		return
	protagonist.prayed_today = true
	var convo: Dictionary = events.on_prayer()
	if convo["choices"].is_empty():
		return
	if auto_resolve:
		var idx := _auto_choice(convo)
		var resp: String = events.resolve(convo, idx)
		print("[祈り %d日目] %s → %s" % [clock.day, convo["choices"][idx]["label"], resp])
		return
	dialog_open = true
	dialogue_ui.open(convo["speaker"], convo["text"], convo["choices"], func(idx):
		var resp: String = events.resolve(convo, idx)
		dialogue_ui.open(convo["speaker"], resp, [{"label": "（見守る）"}], func(_i):
			dialogue_ui.close()
			dialog_open = false
			_flush_pending_ending()))

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
	var active_site = projects.active_site()
	if active_site:
		sites.append({"loc": active_site, "slots": 3, "prio": 100.0})
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

func spawn_villager() -> void:
	if name_pool.is_empty():
		return
	var vname: String = name_pool[name_idx % name_pool.size()]
	name_idx += 1
	var home_id := _home_with_space()
	if home_id == "":
		return
	var a = _add_villager({"id": "v_%d" % name_idx, "name": vname, "home": home_id})
	a.global_position = Vector2(30.0, 620.0)
	a.location_id = ""
	a.active_block = ""
	log_event("新しい村人「%s」がやってきた" % vname, "pop")
	ui_toast("👤 「%s」が村に加わった！" % vname, "pop")
	assign_jobs()

func _home_with_space() -> String:
	var residents: Dictionary = {}
	residents[protagonist.home_id] = int(residents.get(protagonist.home_id, 0)) + 1
	for v in villagers:
		residents[v.home_id] = int(residents.get(v.home_id, 0)) + 1
	for loc in town.by_tag("home"):
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

func spawn_animals(spec: Dictionary) -> void:
	var pen_center := Vector2(600.0, 500.0)
	for loc in town.workplaces():
		if loc.type_id == "pen":
			pen_center = loc.center()
	for kind in spec:
		for i in range(int(spec[kind])):
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

# --- logging shims ------------------------------------------------------------------

func log_event(text: String, kind: String = "info") -> void:
	chronicle.add(clock.day, clock.minute_of_day, text, kind)

func ui_toast(text: String, kind: String = "info") -> void:
	if ui:
		ui.toast(text, kind)

func ui_era_banner(era: int, ename: String) -> void:
	if ui:
		ui.era_banner(era, ename)

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
	var total := 12 * 1440
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
		failures.append("era did not advance in 12 days")
	if world.pop() < 5 and world.ending_id == "":
		failures.append("population collapsed: %d" % world.pop())
	if chronicle.entries.size() < 5:
		failures.append("chronicle suspiciously empty")
	if failures.is_empty():
		print("SELFTEST OK")
		get_tree().quit(0)
	else:
		for f in failures:
			print("SELFTEST FAIL: " + f)
		get_tree().quit(1)

func _run_shot() -> void:
	auto_resolve = true
	set_process(false)
	var step := 1.0
	while not (clock.day == 2 and clock.minute_of_day >= 1110.0):
		clock.force_advance(step)
		_tick(step)
	auto_resolve = false
	_update_tint()
	_select(protagonist)
	var convo: Dictionary = events._guidance_convo()
	dialog_open = true
	dialogue_ui.open(convo["speaker"], convo["text"], convo["choices"], func(_idx): pass)
	dialogue_ui._finish_typing()
	ui.refresh(1.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://shot.png")
	img.save_png(out)
	print("shot saved: " + out)
	get_tree().quit(0)
