extends Node2D
# Owns all Location nodes. New buildings are placed on a spiral lattice of
# free spots around the village center so the town visibly grows outward.

const LocationScript = preload("res://scripts/location.gd")

const CENTER := Vector2(480, 380)

var main
var locations: Dictionary = {}      # instance id -> Location
var _built_counts: Dictionary = {}  # type id -> completed count
var _placed_counts: Dictionary = {} # type id -> placed count (for instance ids)
var _lattice: Array = []
var _lattice_used := 0

func setup(m, initial: Array) -> void:
	main = m
	_build_lattice()
	for d in initial:
		var loc = LocationScript.new()
		loc.name = "Loc_" + str(d.get("id", ""))
		add_child(loc)
		loc.setup_site(d, main)
		locations[loc.id] = loc
		_built_counts[loc.type_id] = int(_built_counts.get(loc.type_id, 0)) + 1
		_placed_counts[loc.type_id] = int(_placed_counts.get(loc.type_id, 0)) + 1

func _build_lattice() -> void:
	for ring in range(1, 6):
		var r := 130.0 + 90.0 * float(ring - 1)
		var count := 6 + ring * 3
		for i in range(count):
			var ang := TAU * float(i) / float(count) + (0.35 if ring % 2 == 1 else 0.0)
			var p := CENTER + Vector2(cos(ang), sin(ang)) * r - Vector2(48, 34)
			if _valid_spot(p):
				_lattice.append(p)

func _valid_spot(p: Vector2) -> bool:
	if p.x < 20.0 or p.x > 750.0 or p.y < 80.0 or p.y > 610.0:
		return false
	if p.x < 290.0 and p.y < 330.0:
		return false  # forest
	if p.x < 250.0 and p.y > 530.0:
		return false  # rocks
	return true

func next_spot() -> Vector2:
	while _lattice_used < _lattice.size():
		var p: Vector2 = _lattice[_lattice_used]
		_lattice_used += 1
		var free := true
		for l in locations.values():
			if Rect2(p, Vector2(100, 72)).grow(8.0).intersects(Rect2(l.position, l.size_v)):
				free = false
				break
		if free:
			return p
	return Vector2(300.0 + randf() * 350.0, 420.0 + randf() * 150.0)

func place_construction(pdef: Dictionary):
	var type_id := str(pdef.get("id", ""))
	_placed_counts[type_id] = int(_placed_counts.get(type_id, 0)) + 1
	var inst_id := "%s_%d" % [type_id, _placed_counts[type_id]]
	var loc = LocationScript.new()
	loc.name = "Loc_" + inst_id
	add_child(loc)
	loc.setup_construction(pdef, inst_id, next_spot(), main)
	locations[inst_id] = loc
	var felled: int = main.terrain.clear_trees_rect(Rect2(loc.position, loc.size_v))
	if felled > 0:
		main.world.add_res("wood", float(felled * 2))
		main.log_event("木を伐り、土地を拓いた（木材+%d）" % (felled * 2), "info")
	return loc

func on_completed(loc) -> void:
	_built_counts[loc.type_id] = int(_built_counts.get(loc.type_id, 0)) + 1

func get_loc(inst_id: String):
	return locations.get(inst_id)

func has_built(type_id: String) -> bool:
	return int(_built_counts.get(type_id, 0)) > 0

func built_count(type_id: String) -> int:
	return int(_built_counts.get(type_id, 0))

func workplaces() -> Array:
	var out: Array = []
	for l in locations.values():
		if not l.under_construction and l.slots > 0:
			out.append(l)
	return out

func by_tag(tag: String) -> Array:
	var out: Array = []
	for l in locations.values():
		if not l.under_construction and l.tags.has(tag):
			out.append(l)
	return out

func housing_capacity() -> int:
	var cap := 0
	for l in locations.values():
		if not l.under_construction:
			cap += l.capacity
	return cap

func shrine():
	# A proper shrine (once built) supersedes the primitive prayer rock.
	var rock = null
	for l in locations.values():
		if l.under_construction:
			continue
		if l.type_id == "shrine":
			return l
		if l.type_id == "prayer_rock":
			rock = l
	return rock

# Rebuild every constructed location from a save snapshot. The wilderness
# sites (forest / riverbank) from locations.json stay as-is.
func load_saved(saved: Array, projects) -> void:
	for key in locations.keys():
		var l = locations[key]
		if l.type_id == "forest" or l.type_id == "riverbank":
			continue
		locations.erase(key)
		l.free()
	_built_counts.clear()
	_placed_counts.clear()
	for l in locations.values():
		_built_counts[l.type_id] = int(_built_counts.get(l.type_id, 0)) + 1
		_placed_counts[l.type_id] = int(_placed_counts.get(l.type_id, 0)) + 1
	for sd in saved:
		var pdef: Dictionary = projects.get_def(str(sd.get("type", "")))
		if pdef.is_empty():
			continue
		var inst_id := str(sd.get("id", ""))
		var loc = LocationScript.new()
		loc.name = "Loc_" + inst_id
		add_child(loc)
		var pos_arr: Array = sd.get("pos", [400.0, 400.0])
		loc.setup_construction(pdef, inst_id, Vector2(float(pos_arr[0]), float(pos_arr[1])), main)
		locations[inst_id] = loc
		var suffix := inst_id.get_slice("_", inst_id.get_slice_count("_") - 1)
		_placed_counts[loc.type_id] = maxi(int(_placed_counts.get(loc.type_id, 0)),
			maxi(1, int(suffix)))
		if bool(sd.get("built", true)):
			loc.activate()
			_built_counts[loc.type_id] = int(_built_counts.get(loc.type_id, 0)) + 1
		else:
			loc.set_progress(float(sd.get("progress", 0.0)))

func building_summary() -> Array:
	var counts: Dictionary = {}
	var names: Dictionary = {}
	for l in locations.values():
		if l.under_construction:
			continue
		counts[l.type_id] = int(counts.get(l.type_id, 0)) + 1
		names[l.type_id] = l.display_name
	var out: Array = []
	for t in counts:
		out.append("%s ×%d" % [names[t], counts[t]])
	return out
