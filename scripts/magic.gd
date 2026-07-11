extends RefCounted
# Spell definitions, availability and learning. Learned spells push the world
# along an axis and apply lasting effects (production multipliers, unlocks).

var main
var defs: Array = []
var known: Array = []  # spell ids in learn order

func setup(m, d: Array) -> void:
	main = m
	defs = d

func get_def(id: String) -> Dictionary:
	for s in defs:
		if str(s.get("id", "")) == id:
			return s
	return {}

func is_known(id: String) -> bool:
	return known.has(id)

func trainable() -> Array:
	var out: Array = []
	for s in defs:
		var id := str(s.get("id", ""))
		if known.has(id):
			continue
		if int(s.get("era", 0)) > main.world.era:
			continue
		if s.get("forbidden", false) and not main.world.flags.get("dark_unlocked", false):
			continue
		var rf := str(s.get("requires_flag", ""))
		if rf != "" and not main.world.flags.get(rf, false):
			continue
		out.append(s)
	return out

func learn(def: Dictionary) -> void:
	var id := str(def.get("id", ""))
	if known.has(id):
		return
	known.append(id)
	for k in def.get("axis", {}):
		main.world.axes[k] = float(main.world.axes.get(k, 0.0)) + float(def["axis"][k])
	main.world.apply_effects(def.get("effects", {}))
	main.log_event("アシタが魔法「%s」を覚えた" % def.get("name", "?"), "magic")
	main.ui_toast("✨ 魔法「%s」を習得！" % def.get("name", "?"), "magic")

func known_defs() -> Array:
	var out: Array = []
	for id in known:
		var d := get_def(id)
		if not d.is_empty():
			out.append(d)
	return out
