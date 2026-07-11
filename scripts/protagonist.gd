extends "res://scripts/agent.gd"
# The hero. The only creature the player can influence, and only indirectly:
# every morning they pray at the shrine and the god (the player) chooses their
# path. During the day they train magic, lead construction, or pitch in.

var prayed_today := false
var meals_today := 0
var directive := {}   # {"type": "train"|"action", ...} ("project" is tracked by projects.gd)
var training := {}    # {"spell": def, "hours": float}
var action_hours_left := 0.0
var help_target := ""

func setup(d: Dictionary, m) -> void:
	super.setup(d, m)
	name_label.add_theme_color_override("font_color", U.COL["gold"])
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
				main.projects.add_progress_hours(1.0 * (gmin / 60.0) * mood_factor(), loc)
			else:
				_choose_day_task()
		State.WORKING:
			_produce(gmin, 0.8)
		State.FREE:
			_chatter(gmin, ctx)

func _phase_for(m: float) -> String:
	if m >= 1320.0 or m < 330.0:
		return "sleep"
	if m < 420.0:
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
			_set_destination("plaza", State.FREE)

func _shrine_id() -> String:
	var s = main.town.shrine()
	return s.id if s else home_id

func on_day_started() -> void:
	prayed_today = false
	meals_today = 0

func _meal_bumps(ctx: Dictionary) -> void:
	var m: float = ctx["minute_of_day"]
	if meals_today == 0 and m >= 420.0 and m < 1200.0:
		meals_today = 1
		needs["hunger"] = clampf(needs["hunger"] + 35.0, 0.0, 100.0)
	elif meals_today == 1 and m >= 730.0 and m < 1200.0:
		meals_today = 2
		needs["hunger"] = clampf(needs["hunger"] + 35.0, 0.0, 100.0)
	elif meals_today == 2 and m >= 1205.0:
		meals_today = 3
		needs["hunger"] = clampf(needs["hunger"] + 35.0, 0.0, 100.0)

# --- directives from the god ------------------------------------------------

func start_training(spell_def: Dictionary) -> void:
	directive = {"type": "train"}
	training = {"spell": spell_def, "hours": 0.0}
	if active_block == "day":
		_choose_day_task()

func start_action(adef: Dictionary) -> void:
	directive = {"type": "action", "def": adef}
	action_hours_left = float(adef.get("build_hours", 4))
	if active_block == "day":
		_choose_day_task()

func on_project_started() -> void:
	if active_block == "day":
		_choose_day_task()

func _choose_day_task() -> void:
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
		_choose_day_task()

func _do_action(gmin: float, ctx: Dictionary) -> void:
	action_hours_left -= gmin / 60.0
	if action_hours_left <= 0.0:
		var adef: Dictionary = directive.get("def", {})
		directive = {}
		main.on_action_finished(adef)
		show_bubble(str(adef.get("done_line", "終わった！")), 8.0, ctx["abs_minutes"])
		_choose_day_task()

func training_progress() -> Dictionary:
	if training.is_empty():
		return {}
	var def: Dictionary = training["spell"]
	return {
		"name": str(def.get("name", "?")),
		"ratio": clampf(float(training["hours"]) / maxf(1.0, float(def.get("train_hours", 16))), 0.0, 1.0),
	}

func _update_label() -> void:
	name_label.text = "✦" + display_name + str(GLYPHS.get(state, ""))
	name_label.reset_size()
	name_label.position = Vector2(-name_label.size.x / 2.0, -36.0)

func _draw() -> void:
	draw_circle(Vector2.ZERO, 11.0, color)
	draw_arc(Vector2.ZERO, 12.5, 0.0, TAU, 28, U.COL["gold"], 2.0)
	if selected:
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 28, Color.WHITE, 2.0)

func action_text() -> String:
	if state == State.TRAINING and not training.is_empty():
		var t := training_progress()
		return "「%s」を修行中 (%d%%)" % [t["name"], int(t["ratio"] * 100.0)]
	if state == State.TRAINING and directive.get("type", "") == "action":
		return str(directive["def"].get("doing_line", "行動中"))
	return super.action_text()
