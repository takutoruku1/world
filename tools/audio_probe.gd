extends SceneTree
# Verifies runtime OGG loading works (U.load_audio_file) without the editor
# import pipeline: prints stream class and length for one track per pool.

const U = preload("res://scripts/util.gd")

func _init() -> void:
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/bgm.json"))
	var fails := 0
	for key in ["title", "era_low", "era_mid", "era_high", "night", "crisis", "ending"]:
		var pool: Array = data.get(key, [])
		if pool.is_empty():
			print("POOL %s: EMPTY" % key)
			fails += 1
			continue
		var s := U.load_audio_file("res://assets/audio/bgm/" + str(pool[0]))
		if s == null:
			print("POOL %s: LOAD FAIL %s" % [key, pool[0]])
			fails += 1
		else:
			print("POOL %s: %s len=%.1fs (%s)" % [key, s.get_class(), s.get_length(), pool[0]])
	print("AUDIO_PROBE %s" % ("OK" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
