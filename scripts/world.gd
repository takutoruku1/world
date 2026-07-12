extends Node
# Global world state: resources, the three development axes (tech / nature /
# mystic), danger meters (war / blight), flags, era progression and endings.

const U = preload("res://scripts/util.gd")

var main
var res := {"food": 50.0, "wood": 30.0, "stone": 0.0, "metal": 0.0, "mana": 0.0, "knowledge": 0.0}
var axes := {"tech": 0.0, "nature": 0.0, "mystic": 0.0}
var danger := {"war": 0.0, "blight": 0.0}
var plague_severity := 0.0  # 0..100; grows daily while flags.plague_outbreak
var flags: Dictionary = {}
var multipliers: Dictionary = {}  # building type -> production multiplier
var era := 0
var era_defs: Array = []
var endings: Dictionary = {}
var starvation_days := 0
var pending_era_up := false
var ending_id := ""
var peak_pop := 1
var accept_villagers := true  # god's policy: whether travelers may join
var history: Array = []  # civilization turning points, shown in the History Book
# entry: {"day": int, "kind": "prologue"|"era"|"event", "title": String,
#          "choice": String, "text": String}

func setup(m, eras_data: Dictionary) -> void:
	main = m
	era_defs = eras_data.get("eras", [])
	endings = eras_data.get("endings", {})

func pop() -> int:
	return main.villagers.size() + 1  # villagers + the hero

# --- resources --------------------------------------------------------------

func add_res(k: String, v: float) -> void:
	res[k] = maxf(0.0, float(res.get(k, 0.0)) + v)

func add_production(loc, k: String, amount: float) -> void:
	add_res(k, amount * production_mult(loc.type_id))

func production_mult(type_id: String) -> float:
	return float(multipliers.get(type_id, 1.0))

func can_afford(cost: Dictionary) -> bool:
	for k in cost:
		if float(res.get(k, 0.0)) < float(cost[k]):
			return false
	return true

func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for k in cost:
		res[k] = float(res[k]) - float(cost[k])
	return true

# --- generic effect vocabulary ----------------------------------------------
# Keys: res_food +20 / axis_tech +10 / danger_war +30 / mood_all +15 /
# flag_x true / mult_farm 1.3 / kill_villagers 2 / spawn_villagers 1 /
# spawn_animals {"chicken": 2}

func apply_effects(eff: Dictionary) -> void:
	for key in eff:
		var v = eff[key]
		if key.begins_with("res_"):
			add_res(key.substr(4), float(v))
		elif key.begins_with("axis_"):
			var a: String = key.substr(5)
			axes[a] = maxf(0.0, float(axes.get(a, 0.0)) + float(v))
		elif key.begins_with("danger_"):
			var d: String = key.substr(7)
			danger[d] = clampf(float(danger.get(d, 0.0)) + float(v), 0.0, 100.0)
		elif key.begins_with("flag_"):
			flags[key.substr(5)] = v
		elif key.begins_with("mult_"):
			var t: String = key.substr(5)
			multipliers[t] = float(multipliers.get(t, 1.0)) * float(v)
		elif key == "mood_all":
			main.mood_all(float(v))
		elif key == "kill_villagers":
			main.kill_random_villagers(int(v), "災いに呑まれた")
		elif key == "spawn_villagers":
			for i in range(int(v)):
				main.spawn_villager()
		elif key == "spawn_animals":
			main.spawn_animals(v)
		elif key == "cure_plague":
			plague_severity = 0.0
			flags["plague_outbreak"] = false
			flags["plague_contained"] = false
		elif key == "plague_severity":
			plague_severity = clampf(plague_severity + float(v), 0.0, 100.0)
		else:
			push_error("Unknown effect key: " + key)

# --- daily cycle --------------------------------------------------------------

func on_day_started(_day: int) -> void:
	if ending_id != "":
		return
	peak_pop = maxi(peak_pop, pop())
	_food_upkeep()
	_growth_check()
	_danger_progress()
	_plague_progress()
	pending_era_up = era_ready()
	check_endings()

# Meals now draw from the food stock directly (1.5 food per meal); the day
# counter below only tracks empty-larder crises.
func consume_meal() -> bool:
	if float(res["food"]) >= 1.5:
		res["food"] = float(res["food"]) - 1.5
		return true
	return false

func _food_upkeep() -> void:
	if float(res["food"]) <= 1.0:
		starvation_days += 1
		main.mood_all(-12.0)
		main.log_event("食料が尽きた…（%d日目の飢え）" % starvation_days, "crisis")
		main.ui_toast("🌾 食料が尽きた！", "bad")
		if starvation_days >= 2 and main.livestock_count() > 0:
			main.kill_starving_livestock()
		elif starvation_days >= 3:
			main.kill_random_villagers(1, "飢えて倒れた")
	else:
		starvation_days = 0

func _growth_check() -> void:
	if starvation_days > 0 or pop() >= 40 or not accept_villagers:
		return
	# Lonely fires draw travelers: arrivals are more eager while the settlement is tiny.
	var chance := 0.65 if pop() < 4 else 0.45
	if float(res["food"]) >= float(pop() * 12) \
			and main.town.housing_capacity() > pop() \
			and main.avg_mood() >= 50.0 \
			and randf() < chance:
		main.spawn_villager()

func _danger_progress() -> void:
	if danger["war"] > 0.0:
		if flags.get("war_resolved", false):
			danger["war"] = maxf(0.0, float(danger["war"]) - 10.0)
		else:
			danger["war"] = clampf(float(danger["war"]) + 2.0, 0.0, 100.0)
	if danger["blight"] >= 60.0:
		main.mood_all(-4.0)
	if danger["blight"] >= 90.0 and danger["blight"] < 100.0:
		main.log_event("大地の魔力が淀み、作物が枯れ始めた", "crisis")

# Untreated plague spreads day by day; containment (isolation) and clean water
# slow it, a cure event resets it, 100 collapses the town (pestilence ending).
func _plague_progress() -> void:
	if not flags.get("plague_outbreak", false):
		return
	var rate := 3.0 if flags.get("plague_contained", false) else 6.0
	if main.town.has_built("well"):
		rate -= 1.0
	if main.town.has_built("clinic"):
		rate -= 2.0
	plague_severity = clampf(plague_severity + maxf(rate, 0.5), 0.0, 100.0)
	main.mood_all(-3.0)
	if plague_severity >= 40.0 and randf() < 0.5:
		main.kill_random_villagers(1, "はやり病に倒れた")
	if plague_severity >= 70.0:
		main.log_event("病が家から家へ広がっていく……村に咳の音が響く", "crisis")
		main.ui_toast("🤒 はやり病が村中に！", "bad")

# --- era ----------------------------------------------------------------------

func era_def() -> Dictionary:
	return era_defs[era] if era < era_defs.size() else {}

func era_name() -> String:
	var d := era_def()
	if d.has("variants"):
		return str(d["variants"].get(dominant_axis(), d.get("name", "?")))
	return str(d.get("name", "?"))

func dominant_axis() -> String:
	var best := "nature"
	var best_v := -1.0
	for a in ["tech", "nature", "mystic"]:
		if float(axes[a]) > best_v:
			best_v = float(axes[a])
			best = a
	return best

func era_ready() -> bool:
	if era >= era_defs.size() - 1:
		return false
	var req: Dictionary = era_def().get("req", {})
	if pop() < int(req.get("pop", 0)):
		return false
	for k in req.get("res", {}):
		if float(res.get(k, 0.0)) < float(req["res"][k]):
			return false
	for b in req.get("buildings", []):
		if not main.town.has_built(str(b)):
			return false
	if req.has("buildings_any"):
		var any := false
		for b in req["buildings_any"]:
			if main.town.has_built(str(b)):
				any = true
		if not any:
			return false
	if req.has("axis") and float(axes[dominant_axis()]) < float(req["axis"]):
		return false
	for f in req.get("flags", []):
		if not flags.get(str(f), false):
			return false
	return true

func do_era_up() -> void:
	era += 1
	pending_era_up = false
	if era >= era_defs.size() - 1:
		flags["final_done"] = true
	main.log_event("時代が進んだ —「%s」" % era_name(), "era")
	main.ui_era_banner(era, era_name())

# --- endings --------------------------------------------------------------------

func check_endings() -> void:
	if ending_id != "":
		return
	if main.villagers.is_empty() and peak_pop >= 3:
		_trigger("ruin")
	elif plague_severity >= 100.0:
		_trigger("pestilence")
	elif danger["blight"] >= 100.0:
		_trigger("silence")
	elif flags.get("war_lost", false):
		_trigger("scorched")
	elif flags.get("final_done", false):
		var vals := [float(axes["tech"]), float(axes["nature"]), float(axes["mystic"])]
		vals.sort()
		if vals[2] - vals[0] <= 25.0:
			_trigger("harmony")
		else:
			_trigger("modern_" + dominant_axis())

func _trigger(id: String) -> void:
	ending_id = id
	var def: Dictionary = endings.get(id, {"title": id, "text": ""}).duplicate()
	def["id"] = id
	main.log_event("結末 —「%s」" % def.get("title", id), "era")
	main.show_ending(def)
