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
var era_start_day := 1  # for the era min_days pacing gate
var era_defs: Array = []
var endings: Dictionary = {}
var starvation_days := 0
var pending_era_up := false
var ending_id := ""
var peak_pop := 1
var accept_villagers := true  # god's policy: whether travelers may join
var policy := "minori"  # the path the god currently points at (projects.POLICIES)
var weather := "sunny"  # rolled each morning: sunny / cloudy / rain / storm
var history: Array = []  # civilization turning points, shown in the History Book
# entry: {"day": int, "kind": "prologue"|"era"|"event"|"policy", "title": String,
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
	var m := float(multipliers.get(type_id, 1.0))
	if type_id == "farm":
		if weather == "rain":
			m *= 1.2  # 恵みの雨
		elif weather == "storm":
			m *= 0.8
	return m

# Daily weather: mostly fair, the occasional rainy day feeds the fields, and
# a rare storm rattles the village.
func _roll_weather() -> void:
	var prev := weather
	var r := randf()
	if r < 0.04:
		weather = "storm"
	elif r < 0.22:
		weather = "rain"
	elif r < 0.52:
		weather = "cloudy"
	else:
		weather = "sunny"
	if weather == prev:
		return
	match weather:
		"rain":
			main.log_event("雨の朝。畑が静かに潤っていく", "info")
		"storm":
			main.log_event("嵐が村を叩く。みんな早めに家へ", "crisis")
			main.mood_all(-3.0)
		"cloudy":
			main.log_event("空は薄曇り。過ごしやすい一日になりそうだ", "info")
		"sunny":
			main.log_event("雲ひとつない朝。洗濯日和だ、とアシタが言った", "info")

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
		elif key == "accept_travelers":
			# The whole waiting group joins (size decided in _growth_check).
			var n := maxi(1, int(flags.get("traveler_count", 1)))
			var joined := 0
			for i in range(n):
				if main.spawn_villager(false, true):
					joined += 1
			flags["traveler_count"] = 0
			if joined > 1:
				main.ui_toast("👤 旅人%d人が村に加わった！" % joined, "pop")
			elif joined == 1:
				main.ui_toast("👤 旅人が村に加わった！", "pop")
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
	_roll_weather()
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
	_birth_check()
	if flags.get("traveler_pending", false):
		return
	var space: int = main.town.housing_capacity() - pop()
	if space <= 0 or float(res["food"]) < float(pop() * 8) or main.avg_mood() < 50.0:
		return
	var chance := 0.7 if pop() < 4 else 0.5
	if randf() >= chance:
		return
	# Population must keep pace with the parallel auto-development: a bigger,
	# richer village draws whole groups of travelers, not one soul per day.
	# The group waits until the god decides at the next prayer (traveler_arrival).
	var group := clampi(1 + pop() / 4, 1, mini(space, 6))
	flags["traveler_pending"] = true
	flags["traveler_count"] = group
	if group > 1:
		main.log_event("旅人の一団(%d人)が村の灯りを見つけ、丘の上からこちらを窺っている" % group, "info")
	else:
		main.log_event("旅人が村の火を見つけ、丘の上からこちらを窺っている", "info")

# The second growth pillar, independent of prayers: a well-fed, happy village
# with room to live raises children on its own (idle-friendly).
func _birth_check() -> void:
	if pop() < 4 or pop() >= 40:
		return
	if main.town.housing_capacity() <= pop() \
			or float(res["food"]) < float(pop() * 10) \
			or main.avg_mood() < 58.0:
		return
	var chance := clampf(0.06 * float(pop() / 2), 0.0, 0.55)
	if randf() < chance:
		main.spawn_villager(true)

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
	# Pacing gate: each era must "ripen" for a minimum number of days so a
	# full 8x-speed run lands near the 30-minute target (data: min_days).
	if main.day() - era_start_day < int(era_def().get("min_days", 0)):
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

func set_policy(v: String) -> void:
	if not main.projects.POLICIES.has(v) or v == policy:
		return
	policy = v
	var pd: Dictionary = main.projects.policy_def(v)
	main.log_event("神は「%s」を示した" % pd["name"], "era")
	main.ui_toast("🧭 新しい方針 —「%s」" % pd["name"], "info")
	history.append({"day": main.day(), "kind": "policy",
		"title": "新しい道 —「%s」" % pd["name"], "choice": "",
		"text": str(pd["desc"])})
	if main.protagonist != null:
		main.protagonist.maybe_auto_train()

func do_era_up() -> void:
	era += 1
	era_start_day = main.day()
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

# --- save / load -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"res": res.duplicate(), "axes": axes.duplicate(), "danger": danger.duplicate(),
		"flags": flags.duplicate(), "multipliers": multipliers.duplicate(),
		"era": era, "era_start_day": era_start_day,
		"starvation_days": starvation_days,
		"plague_severity": plague_severity, "peak_pop": peak_pop,
		"accept_villagers": accept_villagers, "policy": policy, "weather": weather,
		"pending_era_up": pending_era_up, "history": history.duplicate(true),
	}

func from_dict(d: Dictionary) -> void:
	for k in res:
		res[k] = float(d.get("res", {}).get(k, res[k]))
	for k in axes:
		axes[k] = float(d.get("axes", {}).get(k, 0.0))
	for k in danger:
		danger[k] = float(d.get("danger", {}).get(k, 0.0))
	flags = {}
	for k in d.get("flags", {}):
		flags[str(k)] = d["flags"][k]
	multipliers = {}
	for k in d.get("multipliers", {}):
		multipliers[str(k)] = float(d["multipliers"][k])
	era = int(d.get("era", 0))
	era_start_day = int(d.get("era_start_day", 1))
	starvation_days = int(d.get("starvation_days", 0))
	plague_severity = float(d.get("plague_severity", 0.0))
	peak_pop = int(d.get("peak_pop", 1))
	accept_villagers = bool(d.get("accept_villagers", true))
	policy = str(d.get("policy", "minori"))
	weather = str(d.get("weather", "sunny"))
	pending_era_up = bool(d.get("pending_era_up", false))
	history = []
	for e in d.get("history", []):
		history.append({"day": int(e.get("day", 0)), "kind": str(e.get("kind", "event")),
			"title": str(e.get("title", "")), "choice": str(e.get("choice", "")),
			"text": str(e.get("text", ""))})

func _trigger(id: String) -> void:
	ending_id = id
	var def: Dictionary = endings.get(id, {"title": id, "text": ""}).duplicate()
	def["id"] = id
	main.log_event("結末 —「%s」" % def.get("title", id), "era")
	main.show_ending(def)
