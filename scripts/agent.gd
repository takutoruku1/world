extends Node2D
# A villager. Schedule-driven daily life: sleep, meals, assigned work, and
# evening chatter. While working, produces resources for the world (or build
# progress when assigned to a construction site).

const U = preload("res://scripts/util.gd")
const BubbleScript = preload("res://scripts/bubble.gd")

enum State { SLEEPING, MOVING, WORKING, EATING, FREE, PRAYING, TRAINING, LEADING }

const STATE_NAMES := ["SLEEPING", "MOVING", "WORKING", "EATING", "FREE", "PRAYING", "TRAINING", "LEADING"]
const GLYPHS := {State.SLEEPING: "💤", State.EATING: "🍚"}
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

var name_label: Label
var bubble = null

func setup(d: Dictionary, m) -> void:
	main = m
	id = str(d.get("id", "v%d" % randi()))
	display_name = str(d.get("name", id))
	color = Color(str(d.get("color", "#cccccc")))
	home_id = str(d.get("home", "hut_1"))
	needs["hunger"] = 60.0 + randf() * 30.0
	needs["energy"] = 70.0 + randf() * 30.0
	chatter_cd = randf() * 60.0
	name_label = U.make_label(display_name, 12)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_label.add_theme_constant_override("outline_size", 4)
	add_child(name_label)
	var home = main.town.get_loc(home_id)
	if home:
		global_position = home.stand_global()
		location_id = home_id
	_update_label()

# --- per-frame simulation -------------------------------------------------

func sim_tick(gmin: float, ctx: Dictionary) -> void:
	_update_needs(gmin)
	_expire_bubble(ctx)
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

func _block_for(minute: float) -> Dictionary:
	for b in SCHEDULE:
		var s: int = b["start"]
		var e: int = b["end"]
		if s <= e:
			if minute >= s and minute < e:
				return b
		elif minute >= s or minute < e:
			return b
	return SCHEDULE[0]

func _apply_block(block: Dictionary, _ctx: Dictionary) -> void:
	match block["action"]:
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
				free_choice = "plaza" if randf() < 0.65 else home_id
				_set_destination(free_choice if free_choice != "plaza" else "plaza", State.FREE)

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

func _move(gmin: float) -> void:
	global_position = global_position.move_toward(move_target, MOVE_SPEED * gmin)
	move_time += gmin
	if global_position.distance_to(move_target) < 1.0:
		location_id = pending.get("place", home_id)
		move_time = 0.0
		_enter(int(pending.get("state", State.FREE)))

func _enter(s: int) -> void:
	if s == State.EATING:
		needs["hunger"] = clampf(needs["hunger"] + 35.0, 0.0, 100.0)
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
	if randf() < 0.45:
		return
	var line: String = main.pick_chatter()
	if line != "":
		show_bubble(line, 6.0, ctx["abs_minutes"])
		mood = clampf(mood + 2.0, 0.0, 100.0)

func show_bubble(text: String, duration_gmin: float, abs_now: float) -> void:
	if bubble:
		bubble.queue_free()
	bubble = BubbleScript.new()
	add_child(bubble)
	bubble.setup(text, abs_now + duration_gmin)

func _expire_bubble(ctx: Dictionary) -> void:
	if bubble and bubble.expired(ctx["abs_minutes"]):
		bubble.queue_free()
		bubble = null

func die(reason: String) -> void:
	main.on_villager_died(self, reason)

# --- presentation ---------------------------------------------------------

func _update_label() -> void:
	name_label.text = display_name + str(GLYPHS.get(state, ""))
	name_label.reset_size()
	name_label.position = Vector2(-name_label.size.x / 2.0, -32.0)

func set_selected(v: bool) -> void:
	selected = v
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 9.0, color)
	draw_arc(Vector2.ZERO, 10.0, 0.0, TAU, 24, Color(0, 0, 0, 0.55), 1.5)
	if selected:
		draw_arc(Vector2.ZERO, 13.5, 0.0, TAU, 24, Color.WHITE, 2.0)

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
