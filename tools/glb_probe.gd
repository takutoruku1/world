extends SceneTree
# Probe: verify runtime GLTF/GLB loading works without the editor import
# pipeline. Prints node/animation info for a building and a character.

func _init() -> void:
	_probe("res://assets/models/medieval/buildings/red/building_home_A_red.gltf")
	_probe("res://assets/models/characters/Knight.glb")
	quit(0)

func _probe(path: String) -> void:
	print("=== ", path)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	print("  load err: ", err)
	if err != OK:
		return
	var scene := doc.generate_scene(state)
	if scene == null:
		print("  generate_scene: null")
		return
	print("  root: ", scene.name, "  children: ", scene.get_child_count())
	var anims := scene.find_children("*", "AnimationPlayer", true, false)
	for ap in anims:
		print("  animations: ", ap.get_animation_list())
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	print("  mesh instances: ", meshes.size())
	scene.free()
