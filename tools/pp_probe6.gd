extends SceneTree
# Computes each model's facing from its skeleton: direction Root_M -> Head_M
# on the XZ plane, and prints the yaw that aligns the head to +Z.

const U = preload("res://scripts/util.gd")
const AnimalScript = preload("res://scripts/animal.gd")

func _init() -> void:
	for kind in AnimalScript.PP_MODELS:
		var spec: Dictionary = AnimalScript.PP_MODELS[kind]
		var m := U.load_model(AnimalScript.PP_DIR + str(spec["file"]))
		if m == null:
			print("%s: LOAD FAIL" % kind)
			continue
		var head := Vector3.ZERO
		var root := Vector3.ZERO
		var got_head := false
		var got_root := false
		for sk in m.find_children("*", "Skeleton3D", true, false):
			var s: Skeleton3D = sk
			var xf := U._transform_to_ancestor(s, m)
			for i in range(s.get_bone_count()):
				var bname := s.get_bone_name(i)
				var pos := (xf * s.get_bone_global_rest(i)).origin
				if bname == "Head_M" or (not got_head and bname.contains("Head")):
					head = pos
					got_head = true
				if bname == "Root_M" or (not got_root and bname.contains("Root")):
					root = pos
					got_root = true
		if not (got_head and got_root):
			print("%s: bones missing (head=%s root=%s)" % [kind, got_head, got_root])
			m.free()
			continue
		var d := head - root
		var yaw := -atan2(d.x, d.z)
		print("%s: head_dir=(%.2f, %.2f) needed_yaw=%.2f (deg %.0f)" % [
			kind, d.x, d.z, yaw, rad_to_deg(yaw)])
		m.free()
	print("PP_PROBE6 DONE")
	quit(0)
