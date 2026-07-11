extends Node2D
# Decorative background: grass, a river along the east side, forest to the
# north-west, rocks to the south-west. Pure _draw, no interaction.

const MAP := Rect2(0, 40, 980, 680)

var forest_spots: Array = []
var rock_spots: Array = []
var grass_spots: Array = []
var river_pts := PackedVector2Array()

func setup() -> void:
	river_pts = PackedVector2Array([
		Vector2(950, 40), Vector2(905, 190), Vector2(880, 340),
		Vector2(900, 490), Vector2(870, 720),
	])
	for i in range(26):
		forest_spots.append(Vector2(50 + randf() * 210, 80 + randf() * 230))
	for i in range(9):
		rock_spots.append(Vector2(60 + randf() * 160, 570 + randf() * 110))
	for i in range(50):
		grass_spots.append(Vector2(randf() * 960, 50 + randf() * 660))
	queue_redraw()

func _draw() -> void:
	draw_rect(MAP, Color("223122"))
	for p in grass_spots:
		draw_circle(p, 5.0 + fmod(p.x, 4.0), Color("263826"))
	# mountains behind the north-west forest
	var peaks := [Vector2(60, 46), Vector2(150, 46), Vector2(240, 46)]
	for i in range(peaks.size()):
		var base: Vector2 = peaks[i]
		var h := 52.0 + 14.0 * float(i % 2)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-56, h), base + Vector2(0, -18), base + Vector2(56, h),
		]), Color("3a4148"))
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-14, 4), base + Vector2(0, -18), base + Vector2(14, 4),
		]), Color("aeb6c2"))
	for i in range(river_pts.size() - 1):
		draw_line(river_pts[i], river_pts[i + 1], Color("2e4a63"), 28.0)
		draw_line(river_pts[i], river_pts[i + 1], Color("39617f"), 14.0)
	for p in forest_spots:
		draw_circle(p + Vector2(0, 4), 15.0, Color("15230f"))
		draw_circle(p, 13.0, Color("2b4a26"))
		draw_circle(p + Vector2(-3, -4), 6.0, Color("35592e"))
	for p in rock_spots:
		draw_circle(p, 10.0, Color("4a4f58"))
		draw_circle(p + Vector2(-3, -3), 6.0, Color("5d636e"))
