extends Node
# Background music: two AudioStreamPlayers crossfading between mood pools
# (title / era-band day / night / crisis / ending) defined in data/bgm.json.
# Tracks load at runtime via U.load_audio_file, so no import pipeline needed.

const U = preload("res://scripts/util.gd")
const BGM_DIR := "res://assets/audio/bgm/"
const FADE_SEC := 1.8

var main
var data: Dictionary = {}
var players: Array = []
var cur := 0
var current_key := ""
var current_track := ""
var enabled := true
var _accum := 0.0
var _volume_db := -8.0

func setup(m, d: Dictionary) -> void:
	main = m
	data = d
	_volume_db = float(d.get("volume_db", -8.0))
	for i in range(2):
		var p := AudioStreamPlayer.new()
		p.name = "BGM%d" % i
		p.volume_db = -80.0
		add_child(p)
		players.append(p)

func set_enabled(v: bool) -> void:
	enabled = v
	if not v:
		for p in players:
			p.stop()
		current_key = ""
		current_track = ""

func _process(delta: float) -> void:
	if main == null or players.is_empty() or not enabled:
		return
	_accum += delta
	if _accum < 1.0:
		return
	_accum = 0.0
	var key := _desired_key()
	var active: AudioStreamPlayer = players[cur]
	if key != current_key or not active.playing:
		_play_from_pool(key)

func _desired_key() -> String:
	if main.game_over:
		return "ending"
	if not main.game_started:
		return "title"
	if _crisis_active():
		return "crisis"
	if main.clock.is_night():
		return "night"
	if main.world.era >= 4:
		return "era_high"
	if main.world.era >= 2:
		return "era_mid"
	return "era_low"

func _crisis_active() -> bool:
	var w = main.world
	if float(w.danger["war"]) > 0.0 and not w.flags.get("war_resolved", false):
		return true
	if w.flags.get("plague_outbreak", false) and w.plague_severity >= 40.0:
		return true
	if w.starvation_days >= 2:
		return true
	return main.monster_raid_root != null and is_instance_valid(main.monster_raid_root)

func _play_from_pool(key: String) -> void:
	var pool: Array = data.get(key, [])
	if pool.is_empty():
		pool = data.get("era_low", [])
	if pool.is_empty():
		return
	var candidates := pool.duplicate()
	if candidates.size() > 1:
		candidates.erase(current_track)
	var track := str(candidates[randi() % candidates.size()])
	var stream := U.load_audio_file(BGM_DIR + track)
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	current_key = key
	current_track = track
	var from: AudioStreamPlayer = players[cur]
	cur = (cur + 1) % 2
	var to: AudioStreamPlayer = players[cur]
	to.stream = stream
	to.volume_db = -40.0
	to.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(to, "volume_db", _volume_db, FADE_SEC)
	if from.playing:
		tw.tween_property(from, "volume_db", -40.0, FADE_SEC)
		tw.chain().tween_callback(from.stop)
