extends SceneTree
# Checks the Rig GLBs for meshes/skeletons and whether the Animations GLB's
# track paths resolve against the Rig scene after a library merge.

const U = preload("res://scripts/util.gd")

const PAIRS := {
	"SKM_Cat_Rig.glb": "SKM_Cat_Animations.glb",
	"SKM_Horse_Rig.glb": "SKM_Horse_Animations.glb",
}

func _init() -> void:
	for rig in PAIRS:
		var m := U.load_model("res://assets/models/polyperfect/" + rig)
		if m == null:
			print("%s: LOAD FAIL" % rig)
			continue
		var meshes := m.find_children("*", "MeshInstance3D", true, false)
		var skels := m.find_children("*", "Skeleton3D", true, false)
		var fit := U.fit_model_to_height_by_bones(m, 1.0)
		print("%s: meshes=%d skeletons=%d bones_fit=%s scale=%s" % [
			rig, meshes.size(), skels.size(), fit, m.scale])
		if not skels.is_empty():
			var sk: Skeleton3D = skels[0]
			print("  skeleton path from root: %s (bones=%d)" % [m.get_path_to(sk), sk.get_bone_count()])
		var donor := U.load_model("res://assets/models/polyperfect/" + str(PAIRS[rig]))
		if donor != null:
			var aps := donor.find_children("*", "AnimationPlayer", true, false)
			if not aps.is_empty():
				var src: AnimationPlayer = aps[0]
				var lib := AnimationLibrary.new()
				for anim_name in src.get_animation_list():
					lib.add_animation(anim_name, src.get_animation(anim_name).duplicate())
				var ap := AnimationPlayer.new()
				m.add_child(ap)
				ap.add_animation_library("", lib)
				var first := str(src.get_animation_list()[2])
				ap.play(first)
				# A track resolves if the animation advances without errors and
				# the root path exists; report first anim's first track path.
				var anim := ap.get_animation(first)
				var tpath := str(anim.track_get_path(0))
				var target := m.get_node_or_null(NodePath(tpath.split(":")[0]))
				print("  donor anims=%d sample_track=%s resolves=%s" % [
					src.get_animation_list().size(), tpath, target != null])
			donor.free()
		m.free()
	print("PP_PROBE5 DONE")
	quit(0)
