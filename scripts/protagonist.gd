extends "res://scripts/agent.gd"
# The hero. The only creature the player can influence, and only indirectly:
# every morning they pray at the shrine and the god (the player) chooses their
# path. During the day they train magic, lead construction, or pitch in.

var prayed_today := false
var prayers_today := 0
var meals_today := 0
var talk_cd := 90.0
var directive := {}   # {"type": "train"|"action", ...} ("project" is tracked by projects.gd)
var training := {}    # {"spell": def, "hours": float}
var action_hours_left := 0.0
var help_target := ""
var thought := ""      # Japan-cheat inner monologue, always shown in the HUD
var _thought_key := ""
var _thought_cd := 0.0

func setup(d: Dictionary, m) -> void:
	super.setup(d, m)
	promote_hero_visual()
	_update_label()

func sim_tick(gmin: float, ctx: Dictionary) -> void:
	_update_needs(gmin)
	_expire_bubble(ctx)
	_meal_bumps(ctx)
	var phase := _phase_for(ctx["minute_of_day"])
	if phase != active_block:
		active_block = phase
		_apply_phase(phase)
	match state:
		State.MOVING:
			_move(gmin)
		State.PRAYING:
			if not prayed_today:
				main.request_prayer()
		State.TRAINING:
			_train(gmin, ctx)
		State.LEADING:
			var loc = main.town.get_loc(location_id)
			if loc and loc.under_construction:
				var horse_boost := 1.15 if main.animal_counts().get("horse", 0) > 0 else 1.0
				main.projects.add_progress_hours(1.0 * (gmin / 60.0) * mood_factor() * horse_boost, loc)
			else:
				_choose_day_task()
		State.WORKING:
			_produce(gmin, 0.8)
		State.FREE:
			_chatter(gmin, ctx)
	_update_thought(gmin)
	_sync_visual()

func _move_speed() -> float:
	# Riding the horse makes the hero noticeably quicker.
	return MOVE_SPEED * (1.35 if main.animal_counts().get("horse", 0) > 0 else 1.0)

func _phase_for(m: float) -> String:
	if m >= 1320.0 or m < 330.0:
		return "sleep"
	# Day 1 begins with quiet work: the first prayer waits until mid-morning so
	# the player can simply watch the world for a while after the prologue.
	var pray_start := 540.0 if main.clock.day == 1 else 330.0
	if m >= pray_start and m < pray_start + 150.0 and prayers_today == 0:
		return "pray"
	if m < 1200.0:
		return "day"
	return "free"

func _apply_phase(phase: String) -> void:
	match phase:
		"sleep":
			_set_destination(home_id, State.SLEEPING)
		"pray":
			_set_destination(_shrine_id(), State.PRAYING)
		"day":
			_choose_day_task()
		"free":
			var socials: Array = main.town.by_tag("social")
			_set_destination(socials[0].id if not socials.is_empty() else home_id, State.FREE)

func _shrine_id() -> String:
	var s = main.town.shrine()
	return s.id if s else home_id

func on_day_started() -> void:
	prayed_today = false
	prayers_today = 0
	meals_today = 0

func _eat_meal() -> void:
	if main.world.consume_meal():
		needs["hunger"] = clampf(needs["hunger"] + 35.0, 0.0, 100.0)
	else:
		mood = clampf(mood - 4.0, 0.0, 100.0)

func _meal_bumps(ctx: Dictionary) -> void:
	var m: float = ctx["minute_of_day"]
	if meals_today == 0 and m >= 420.0 and m < 1200.0:
		meals_today = 1
		_eat_meal()
	elif meals_today == 1 and m >= 730.0 and m < 1200.0:
		meals_today = 2
		_eat_meal()
	elif meals_today == 2 and m >= 1205.0:
		meals_today = 3
		_eat_meal()

# --- directives from the god ------------------------------------------------

func start_training(spell_def: Dictionary) -> void:
	directive = {"type": "train"}
	training = {"spell": spell_def, "hours": 0.0}
	if active_block == "day":
		_choose_day_task()

func start_action(adef: Dictionary) -> void:
	directive = {"type": "action", "def": adef}
	action_hours_left = float(adef.get("build_hours", 4))
	if str(adef.get("id", "")) == "festival":
		var site := str(adef.get("site", "plaza_1"))
		if main.town.get_loc(site) != null:
			main.begin_festival(site, action_hours_left)
	if active_block == "day":
		_choose_day_task()

func on_project_started() -> void:
	if active_block == "day":
		_choose_day_task()

# The hero trains magic on his own now, guided by the god's current path:
# on the Star path he always studies; on other paths he uses days when no
# construction needs his lead to polish that path's school of magic.
func maybe_auto_train() -> void:
	if not training.is_empty() or not directive.is_empty():
		return
	var pol: Dictionary = main.projects.policy_def(main.world.policy)
	var axis := str(pol.get("axis", ""))
	# Training runs even while sites are under construction — the villagers
	# can build without the hero, but only he can learn the gate spells that
	# unlock each era's key building. Exception: a tiny founding village still
	# needs his hands on the site more than his nose in a grimoire.
	if main.world.pop() < 4 and main.projects.active_site() != null:
		return
	var opts: Array = []
	for s in main.magic.trainable():
		if not s.get("forbidden", false):
			opts.append(s)
	if opts.is_empty():
		return
	opts.sort_custom(func(a, b):
		return float(a.get("axis", {}).get(axis, 0.0)) > float(b.get("axis", {}).get(axis, 0.0)))
	var best: Dictionary = opts[0]
	if float(best.get("axis", {}).get(axis, 0.0)) <= 0.0 and main.world.policy != "hoshi":
		return
	start_training(best)
	main.log_event("アシタは魔法「%s」の修行を始めた" % best.get("name", "?"), "magic")
	main.ui_toast("✨ アシタが「%s」の修行を始めた" % best.get("name", "?"), "magic")

func _chatter(gmin: float, ctx: Dictionary) -> void:
	# The hero shares stories from his old world (Japan) with nearby villagers;
	# these exchanges are recorded in the chronicle.
	talk_cd -= gmin
	if talk_cd > 0.0:
		return
	talk_cd = 150.0 + randf() * 120.0
	var partner = null
	for v in main.villagers:
		if v.state == State.FREE and v.bubble == null \
				and v.global_position.distance_to(global_position) < 90.0:
			partner = v
			break
	if partner == null:
		var line: String = main.pick_chatter()
		if line != "":
			show_bubble(line, 6.0, ctx["abs_minutes"])
			main.log_event("アシタ「%s」" % line, "talk")
		return
	var talk: String = main.pick_talk("talk_hero")
	var reply: String = main.pick_talk("talk_reply")
	if talk == "":
		return
	show_bubble(talk, 8.0, ctx["abs_minutes"])
	partner.show_bubble(reply, 8.0, ctx["abs_minutes"] + 3.0)
	mood = clampf(mood + 4.0, 0.0, 100.0)
	partner.mood = clampf(partner.mood + 4.0, 0.0, 100.0)
	main.log_event("アシタ「%s」／%s「%s」" % [talk, partner.display_name, reply], "talk")

func _choose_day_task() -> void:
	if main.is_rest_day() and training.is_empty() and directive.is_empty() \
			and main.projects.active_site() == null:
		var socials: Array = main.town.by_tag("social")
		_set_destination(socials[0].id if not socials.is_empty() else home_id, State.FREE)
		return
	if not training.is_empty():
		var place := "mage_tower_1" if main.town.has_built("mage_tower") else _shrine_id()
		_set_destination(place, State.TRAINING)
		return
	if directive.get("type", "") == "action":
		var adef: Dictionary = directive["def"]
		_set_destination(str(adef.get("site", "plaza")), State.TRAINING)
		return
	var site = main.projects.active_site()
	if site:
		_set_destination(site.id, State.LEADING)
		return
	help_target = _pick_help_target()
	_set_destination(help_target, State.WORKING)

func _pick_help_target() -> String:
	var best_id := "forest"
	var best := -1.0
	for loc in main.town.workplaces():
		var score := 10.0 + randf() * 5.0
		if loc.production.has("food") and main.world.res["food"] < main.world.pop() * 10:
			score += 40.0
		if loc.production.has("knowledge"):
			score += 15.0
		if score > best:
			best = score
			best_id = loc.id
	return best_id

func _train(gmin: float, ctx: Dictionary) -> void:
	if training.is_empty():
		if directive.get("type", "") == "action":
			_do_action(gmin, ctx)
			return
		_choose_day_task()
		return
	training["hours"] = float(training["hours"]) + gmin / 60.0
	var def: Dictionary = training["spell"]
	if float(training["hours"]) >= float(def.get("train_hours", 16)):
		var learned: Dictionary = def
		training = {}
		if directive.get("type", "") == "train":
			directive = {}
		main.magic.learn(learned)
		show_bubble("「%s」を覚えた！" % learned.get("name", "?"), 8.0, ctx["abs_minutes"])
		# New spells can unlock buildings (forge / grove / mage tower).
		main.projects.auto_develop()
		maybe_auto_train()
		_choose_day_task()

func _do_action(gmin: float, ctx: Dictionary) -> void:
	action_hours_left -= gmin / 60.0
	if action_hours_left <= 0.0:
		var adef: Dictionary = directive.get("def", {})
		directive = {}
		main.on_action_finished(adef)
		show_bubble(str(adef.get("done_line", "終わった！")), 8.0, ctx["abs_minutes"])
		_choose_day_task()

# --- the always-visible inner monologue --------------------------------------
# Picks a Japan-knowledge thought matching what Ashita is doing right now
# (crises win over daily work); rotates within the pool every few hours.

func _thought_context_key() -> String:
	var w = main.world
	if w.flags.get("plague_outbreak", false):
		return "crisis_plague"
	if float(w.danger["war"]) > 0.0 and not w.flags.get("war_resolved", false):
		return "crisis_war"
	if w.starvation_days > 0 or float(w.res["food"]) < float(w.pop() * 4):
		return "crisis_food"
	match state:
		State.LEADING:
			var site = main.projects.active_site()
			if site != null:
				return "lead_" + str(site.type_id)
			return "lead"
		State.TRAINING:
			return "train"
		State.PRAYING:
			return "pray"
		State.SLEEPING:
			return "sleep"
		State.EATING:
			return "eat"
		State.FREE:
			return "free"
		State.WORKING:
			var loc = main.town.get_loc(location_id)
			if loc != null:
				return "work_" + str(loc.type_id)
			return "work"
	return ""  # MOVING keeps the previous thought

func _update_thought(gmin: float) -> void:
	_thought_cd -= gmin
	var key := _thought_context_key()
	if key == "":
		return
	if key == _thought_key and _thought_cd > 0.0:
		return
	var pools: Dictionary = main.thoughts_data
	var pool: Array = pools.get(key, [])
	if pool.is_empty() and key.contains("_"):
		pool = pools.get(key.get_slice("_", 0), [])
	if pool.is_empty():
		pool = pools.get("generic", [])
	if pool.is_empty():
		return
	_thought_key = key
	_thought_cd = 150.0 + randf() * 90.0
	var pick := str(pool[randi() % pool.size()])
	if pick != thought:
		thought = pick

func training_progress() -> Dictionary:
	if training.is_empty():
		return {}
	var def: Dictionary = training["spell"]
	return {
		"name": str(def.get("name", "?")),
		"ratio": clampf(float(training["hours"]) / maxf(1.0, float(def.get("train_hours", 16))), 0.0, 1.0),
	}

func _display_label_name() -> String:
	return "✦" + display_name

func _name_label_base_height() -> float:
	return 2.48

func _badge_label_base_height() -> float:
	return 2.36

func _update_label() -> void:
	_refresh_overhead_display()

func action_text() -> String:
	if state == State.TRAINING and not training.is_empty():
		var t := training_progress()
		return "「%s」を修行中 (%d%%)" % [t["name"], int(t["ratio"] * 100.0)]
	if state == State.TRAINING and directive.get("type", "") == "action":
		return str(directive["def"].get("doing_line", "行動中"))
	return super.action_text()
