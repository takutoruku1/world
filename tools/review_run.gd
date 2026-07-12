extends SceneTree
# Boots the real game scene and attaches the auto-play review controller.
# Run (windowed, rendering needed for screenshots):
#   godot --path . --script tools/review_run.gd

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://review"))
	var scene = load("res://scenes/main.tscn").instantiate()
	get_root().add_child.call_deferred(scene)
	var ctl := Node.new()
	ctl.set_script(load("res://tools/review_ctl.gd"))
	ctl.set_deferred("main", scene)
	get_root().add_child.call_deferred(ctl)
