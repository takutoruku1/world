extends SceneTree
# Lists the animation takes inside each converted polyperfect GLB so the
# animal integration can pick Idle/Walk clip names.

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
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if aps.is_empty():
			print("%s: no AnimationPlayer" % f)
		else:
			var names := (aps[0] as AnimationPlayer).get_animation_list()
			print("%s: %d anims: %s" % [f, names.size(), ", ".join(names)])
	print("PP_PROBE DONE")
	quit(0)
