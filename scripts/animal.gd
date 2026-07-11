extends Node2D
# Animals are flavor: deer graze in the forest, livestock wander near their
# pen, and the dog follows the hero around.

const U = preload("res://scripts/util.gd")

var main
var kind := "deer"
var home_center := Vector2.ZERO
var radius := 80.0
var target := Vector2.ZERO
var idle_t := 0.0
var speed := 8.0

const EMOJI := {"deer": "🦌", "dog": "🐕", "chicken": "🐔", "goat": "🐐"}

func setup(k: String, center: Vector2, m) -> void:
	main = m
	kind = k
	home_center = center
	global_position = center + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	target = global_position
	speed = 26.0 if kind == "dog" else 8.0
	var label := U.make_label(EMOJI.get(kind, "🐾"), 18)
	label.position = Vector2(-11, -14)
	add_child(label)

func sim_tick(gmin: float, _ctx: Dictionary) -> void:
	if kind == "dog" and main.protagonist:
		var goal: Vector2 = main.protagonist.global_position + Vector2(18, 10)
		if global_position.distance_to(goal) > 46.0:
			global_position = global_position.move_toward(goal, speed * gmin)
		return
	idle_t -= gmin
	if idle_t <= 0.0:
		idle_t = 60.0 + randf() * 150.0
		target = home_center + Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
	global_position = global_position.move_toward(target, speed * gmin)
