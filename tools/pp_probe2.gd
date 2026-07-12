extends SceneTree
# Dumps the track paths of one walk clip per animal GLB to spot root-motion
# position tracks (they would make animals slide away from their anchor).

const U = preload("res://scripts/util.gd")

const CHECK := {
	"SKM_Deer_Animations.glb": "deer_walk",
	"SKM_Cow_Animations.glb": "Walk",
	"SKM_Hen_Animations.glb": "Hen_Walk",
	"SKM_Cat_Animations.glb": "Cat_Walk",
}

func _init() -> void:
	for f in CHECK:
		var m := U.load_model("res://assets/models/polyperfect/" + f)
		if m == null:
			print("%s: LOAD FAIL" % f)
			continue
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if aps.is_empty():
			continue
		var ap: AnimationPlayer = aps[0]
		var anim := ap.get_animation(str(CHECK[f]))
		if anim == null:
			print("%s: clip missing" % f)
			continue
		var pos_tracks: Array = []
		for i in range(anim.get_track_count()):
			if anim.track_get_type(i) == Animation.TYPE_POSITION_3D:
				pos_tracks.append(str(anim.track_get_path(i)))
		print("%s [%s]: %d tracks, position tracks: %s" % [
			f, CHECK[f], anim.get_track_count(),
			", ".join(pos_tracks) if not pos_tracks.is_empty() else "(none)"])
	print("PP_PROBE2 DONE")
	quit(0)
