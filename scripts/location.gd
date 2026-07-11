extends Node2D
# One site on the map: an initial feature (shrine, hut, forest) or a building
# placed by a project. Buildings start as construction sites and are activated
# when the project completes.

const U = preload("res://scripts/util.gd")

var id: String = ""            # unique instance id
var type_id: String = ""       # building type ("farm", "hut", ...)
var display_name: String = ""
var color := Color("777777")
var size_v := Vector2(96, 68)
var tags: Array = []
var slots: int = 0             # worker slots when active
var production: Dictionary = {}  # resource -> amount per worker-hour
var capacity: int = 0          # housing capacity
var under_construction := false
var progress := 0.0
var def: Dictionary = {}       # project definition when placed by a project
var stand_points: Array = []
var name_label: Label

func setup_site(d: Dictionary) -> void:
	id = str(d.get("id", ""))
	type_id = str(d.get("type", id))
	display_name = str(d.get("name", id))
	color = Color(str(d.get("color", "#777777")))
	var pos: Array = d.get("pos", [400, 300])
	position = Vector2(pos[0], pos[1])
	var sz: Array = d.get("size", [96, 68])
	size_v = Vector2(sz[0], sz[1])
	tags = d.get("tags", [])
	slots = int(d.get("slots", 0))
	production = d.get("production", {})
	capacity = int(d.get("capacity", 0))
	_finish_common()

func setup_construction(pdef: Dictionary, inst_id: String, pos: Vector2) -> void:
	def = pdef
	id = inst_id
	type_id = str(pdef.get("id", ""))
	display_name = str(pdef.get("name", type_id))
	color = Color(str(pdef.get("color", "#8a815f")))
	position = pos
	var sz: Array = pdef.get("size", [96, 68])
	size_v = Vector2(sz[0], sz[1])
	under_construction = true
	progress = 0.0
	_finish_common()

func activate() -> void:
	under_construction = false
	progress = 1.0
	slots = int(def.get("slots", 0))
	production = def.get("production", {})
	capacity = int(def.get("capacity", 0))
	tags = def.get("tags", [])
	name_label.text = _label_text()
	queue_redraw()

func set_progress(p: float) -> void:
	progress = clampf(p, 0.0, 1.0)
	queue_redraw()

func _finish_common() -> void:
	for i in range(6):
		stand_points.append(Vector2(
			randf_range(12.0, maxf(13.0, size_v.x - 12.0)),
			randf_range(20.0, maxf(21.0, size_v.y - 8.0))))
	name_label = U.make_label(_label_text(), 13)
	name_label.position = Vector2(2, -20)
	add_child(name_label)
	queue_redraw()

func _label_text() -> String:
	return display_name + ("(建設中)" if under_construction else "")

func stand_global(i: int = -1) -> Vector2:
	if stand_points.is_empty():
		return position + size_v / 2.0
	var idx := i if i >= 0 else randi() % stand_points.size()
	return position + stand_points[idx % stand_points.size()]

func center() -> Vector2:
	return position + size_v / 2.0

func _draw() -> void:
	if under_construction:
		draw_rect(Rect2(Vector2.ZERO, size_v), Color(0.25, 0.24, 0.22, 0.9))
		draw_rect(Rect2(Vector2.ZERO, size_v), Color("8a815f"), false, 2.0)
		draw_rect(Rect2(Vector2(4, size_v.y - 10), Vector2(size_v.x - 8.0, 6)), Color("11131c"))
		var w := (size_v.x - 8.0) * progress
		draw_rect(Rect2(Vector2(4, size_v.y - 10), Vector2(w, 6)), U.COL["gold"])
	else:
		draw_rect(Rect2(Vector2.ZERO, size_v), Color(color, 0.85))
		draw_rect(Rect2(Vector2.ZERO, size_v), color.darkened(0.45), false, 2.0)
		draw_line(Vector2(2, 2), Vector2(size_v.x - 2.0, 2), color.lightened(0.25), 2.0)
