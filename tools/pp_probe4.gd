extends SceneTree
# Dumps the node tree of the cat/horse GLBs whose skeleton went missing.

const U = preload("res://scripts/util.gd")

func _init() -> void:
	for f in ["SKM_Cat_Animations.glb", "SKM_Horse_Animations.glb"]:
		var m := U.load_model("res://assets/models/polyperfect/" + f)
		if m == null:
			print("%s: LOAD FAIL" % f)
			continue
		print("== %s ==" % f)
		_dump(m, 0)
		m.free()
	print("PP_PROBE4 DONE")
	quit(0)

func _dump(n: Node, depth: int) -> void:
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		extra = " mesh=%s aabb=%s skin=%s" % [
			mi.mesh != null, mi.get_aabb().size, mi.skin != null]
	print("%s%s (%s)%s" % ["  ".repeat(depth), n.name, n.get_class(), extra])
	if depth < 5:
		for c in n.get_children():
			_dump(c, depth + 1)
