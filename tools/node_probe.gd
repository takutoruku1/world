extends SceneTree
# List all node names inside character GLBs (to find weapon nodes to prune).

func _init() -> void:
	for f in ["Knight", "Rogue", "Barbarian", "Mage", "Rogue_Hooded"]:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file("res://assets/models/characters/%s.glb" % f, state) != OK:
			continue
		var scene := doc.generate_scene(state)
		print("=== ", f)
		_dump(scene, 0)
		scene.free()
	quit(0)

func _dump(n: Node, depth: int) -> void:
	if depth > 0:
		print("  ".repeat(depth), n.name, "  [", n.get_class(), "]")
	for c in n.get_children():
		_dump(c, depth + 1)
