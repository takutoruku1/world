extends SceneTree
# Prints the collected AABB of each polyperfect GLB before and after
# fit_model_to_height, to diagnose the giant-animal scaling failure.

const U = preload("res://scripts/util.gd")

func _init() -> void:
	var dir := DirAccess.open("res://assets/models/polyperfect")
	for f in dir.get_files():
		if not f.ends_with(".glb"):
			continue
		var m := U.load_model("res://assets/models/polyperfect/" + f)
		if m == null:
			print("%s: LOAD FAIL" % f)
			continue
		var ok := U.fit_model_to_height_by_bones(m, 1.0)
		print("%s: bones_fit=%s scale=%s y_off=%.3f" % [f, ok, m.scale, m.position.y])
		m.free()
	print("PP_PROBE3 DONE")
	quit(0)
