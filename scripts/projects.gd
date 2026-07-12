extends RefCounted
# Projects: buildings (placed as construction sites, built by the hero and
# assigned villagers) and one-shot hero actions. The village now develops on
# its own: the god only points at a policy (道), and auto_develop() keeps as
# many construction sites running in parallel as the population supports.

var main
var defs: Array = []
var sites: Array = []  # [{"def", "site", "hours", "needed"}], oldest first

# The paths the god can show. Each biases which projects the village starts on
# its own and which school of magic the hero trains in spare time.
const POLICIES := {
	"minori": {"name": "実りの道", "desc": "畑を広げ、食卓と住まいを満たす",
		"axis": "nature",
		"projects": ["farm", "hut", "drying_rack", "granary", "pen", "well",
			"communal_oven", "windmill", "watermill", "tavern", "bathhouse",
			"teahouse", "grand_market"]},
	"takumi": {"name": "匠の道", "desc": "道具と炉と石の力で村を固める",
		"axis": "tech",
		"projects": ["woodcamp", "quarry", "forge", "tower", "wall", "barracks",
			"stable", "market", "communal_oven", "printshop", "grand_market",
			"archeryrange", "castle", "great_engine"]},
	"hoshi": {"name": "星の道", "desc": "祈りと学びで魔法を極める",
		"axis": "mystic",
		"projects": ["prayer_rock", "shrine", "school", "herb_garden",
			"printshop", "theater", "mage_tower", "grand_circle", "observatory"]},
	"mori": {"name": "森の道", "desc": "木々と精霊のささやきと共に生きる",
		"axis": "nature",
		"projects": ["plaza", "drying_rack", "herb_garden", "grove", "well",
			"pen", "bathhouse", "teahouse", "theater", "world_tree", "hut"]},
}

func setup(m, d: Array) -> void:
	main = m
	defs = d

func policy_def(id: String) -> Dictionary:
	return POLICIES.get(id, POLICIES["minori"])

func get_def(id: String) -> Dictionary:
	for p in defs:
		if str(p.get("id", "")) == id:
			return p
	return {}

func active_site():
	# The hero leads the oldest running site.
	return sites[0]["site"] if not sites.is_empty() else null

func site_count() -> int:
	return sites.size()

# How many construction sites may run at once: grows with population so a
# bigger village visibly builds several things in parallel.
func slot_limit() -> int:
	return clampi(1 + main.world.pop() / 5, 1, 5)

func eligible(p: Dictionary) -> bool:
	if int(p.get("era", 0)) > main.world.era:
		return false
	var id := str(p.get("id", ""))
	if str(p.get("kind", "building")) == "building":
		var pending := 0
		for s in sites:
			if str(s["def"].get("id", "")) == id:
				pending += 1
		if main.town.built_count(id) + pending >= int(p.get("max", 1)):
			return false
	var rs := str(p.get("requires_spell", ""))
	if rs != "" and not main.magic.is_known(rs):
		return false
	var rf := str(p.get("requires_flag", ""))
	if rf != "" and not main.world.flags.get(rf, false):
		return false
	var rnf := str(p.get("requires_not_flag", ""))
	if rnf != "" and main.world.flags.get(rnf, false):
		return false
	var rb := str(p.get("requires_building", ""))
	if rb != "" and not main.town.has_built(rb):
		return false
	return true

func available() -> Array:
	var out: Array = []
	for p in defs:
		if eligible(p) and main.world.can_afford(p.get("cost", {})):
			out.append(p)
	return out

func start(id: String) -> bool:
	var def := get_def(id)
	if def.is_empty() or not eligible(def):
		return false
	if not main.world.spend(def.get("cost", {})):
		return false
	if str(def.get("kind", "building")) == "action":
		main.protagonist.start_action(def)
		main.log_event("アシタが「%s」に取りかかった" % def.get("name", "?"), "info")
		return true
	var site = main.town.place_construction(def)
	sites.append({"def": def, "site": site, "hours": 0.0, "needed": float(def.get("build_hours", 16))})
	main.log_event("「%s」の建設が始まった" % def.get("name", "?"), "build")
	main.assign_jobs()
	main.protagonist.on_project_started()
	return true

func add_progress_hours(h: float, loc) -> void:
	for s in sites:
		if s.get("site") == loc:
			s["hours"] = float(s["hours"]) + h
			loc.set_progress(float(s["hours"]) / float(s["needed"]))
			if float(s["hours"]) >= float(s["needed"]):
				_complete(s)
			return

func _complete(entry: Dictionary) -> void:
	var def: Dictionary = entry["def"]
	var site = entry["site"]
	sites.erase(entry)
	site.activate()
	main.town.on_completed(site)
	for k in def.get("axis", {}):
		main.world.axes[k] = float(main.world.axes.get(k, 0.0)) + float(def["axis"][k])
	main.world.apply_effects(def.get("effects", {}))
	main.log_event("「%s」が完成した！" % def.get("name", "?"), "build")
	main.ui_toast("🏗 「%s」が完成！" % def.get("name", "?"), "build")
	main.apply_japan_cheat(def)
	main.assign_jobs()
	main.protagonist.on_project_started()
	auto_develop()

# --- autonomous development -------------------------------------------------

func score(p: Dictionary) -> float:
	var w = main.world
	var s := randf() * 10.0
	var pid := str(p.get("id", ""))
	var prod: Dictionary = p.get("production", {})
	if pid == "camp" and main.town.by_tag("home").is_empty():
		s += 220.0
	if pid == "prayer_rock" and main.town.shrine() == null:
		s += 160.0
	if prod.has("food") and float(w.res["food"]) < float(w.pop() * 8):
		s += 90.0
	if pid == "hut" and main.town.housing_capacity() <= w.pop():
		s += 80.0
	if p.has("axis"):
		for a in p["axis"]:
			if a == w.dominant_axis():
				s += 8.0
	if policy_def(w.policy)["projects"].has(pid):
		s += 60.0
	return s

# Fill every free construction slot with the best available project, then let
# the hero pick up a worthwhile one-shot action if his hands are free.
func auto_develop() -> void:
	if main.game_over or main.world.ending_id != "":
		return
	var guard := 8
	while site_count() < slot_limit() and guard > 0:
		guard -= 1
		var best_id := ""
		var best_s := -1.0
		for p in available():
			if str(p.get("kind", "building")) != "building":
				continue
			var s := score(p)
			if s > best_s:
				best_s = s
				best_id = str(p.get("id", ""))
		if best_id == "" or not start(best_id):
			break
	_maybe_start_action()

func _maybe_start_action() -> void:
	if not main.protagonist.directive.is_empty() or not main.protagonist.training.is_empty():
		return
	var best: Dictionary = {}
	var best_s := 0.0
	for p in available():
		if str(p.get("kind", "")) != "action":
			continue
		var s := 0.0
		match str(p.get("id", "")):
			"hunt_beast":
				s = 120.0
			"craft_weapons":
				s = 90.0 if float(main.world.danger["war"]) > 0.0 else 25.0
			"festival":
				s = 70.0 if main.avg_mood() < 58.0 else 8.0
			"explore":
				s = 18.0
			_:
				s = 15.0
		if s > best_s:
			best_s = s
			best = p
	if best.is_empty():
		return
	if best_s >= 60.0 or (best_s >= 20.0 and randf() < 0.3):
		start(str(best.get("id", "")))

# --- save / load ------------------------------------------------------------

func to_list() -> Array:
	var out: Array = []
	for s in sites:
		out.append({"def": str(s["def"].get("id", "")), "site": str(s["site"].id),
			"hours": float(s["hours"]), "needed": float(s["needed"])})
	return out

func load_saved(saved: Array) -> void:
	sites.clear()
	for sd in saved:
		var def := get_def(str(sd.get("def", "")))
		var loc = main.town.get_loc(str(sd.get("site", "")))
		if def.is_empty() or loc == null:
			continue
		var needed := maxf(1.0, float(sd.get("needed", 16.0)))
		var hours := float(sd.get("hours", 0.0))
		sites.append({"def": def, "site": loc, "hours": hours, "needed": needed})
		loc.set_progress(hours / needed)
