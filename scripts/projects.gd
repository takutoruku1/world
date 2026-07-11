extends RefCounted
# Projects the god can order: buildings (placed as construction sites, built
# by the hero + assigned villagers) and one-shot actions (festival, exploring).
# Only one building project runs at a time so the village grows deliberately.

var main
var defs: Array = []
var active: Dictionary = {}  # {"def", "site", "hours", "needed"}

func setup(m, d: Array) -> void:
	main = m
	defs = d

func get_def(id: String) -> Dictionary:
	for p in defs:
		if str(p.get("id", "")) == id:
			return p
	return {}

func active_site():
	return active.get("site", null)

func eligible(p: Dictionary) -> bool:
	if int(p.get("era", 0)) > main.world.era:
		return false
	var id := str(p.get("id", ""))
	if str(p.get("kind", "building")) == "building":
		if not active.is_empty():
			return false
		var built: int = main.town.built_count(id)
		var max_count := int(p.get("max", 1))
		if built >= max_count:
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
	active = {"def": def, "site": site, "hours": 0.0, "needed": float(def.get("build_hours", 16))}
	main.log_event("「%s」の建設が始まった" % def.get("name", "?"), "build")
	main.assign_jobs()
	main.protagonist.on_project_started()
	return true

func add_progress_hours(h: float, loc) -> void:
	if active.is_empty() or active.get("site") != loc:
		return
	active["hours"] = float(active["hours"]) + h
	loc.set_progress(float(active["hours"]) / float(active["needed"]))
	if float(active["hours"]) >= float(active["needed"]):
		_complete()

func _complete() -> void:
	var def: Dictionary = active["def"]
	var site = active["site"]
	active = {}
	site.activate()
	main.town.on_completed(site)
	for k in def.get("axis", {}):
		main.world.axes[k] = float(main.world.axes.get(k, 0.0)) + float(def["axis"][k])
	main.world.apply_effects(def.get("effects", {}))
	main.log_event("「%s」が完成した！" % def.get("name", "?"), "build")
	main.ui_toast("🏗 「%s」が完成！" % def.get("name", "?"), "build")
	main.assign_jobs()
	main.protagonist.on_project_started()
