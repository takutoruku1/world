extends RefCounted
# The village chronicle: a timestamped log of everything that mattered.

const U = preload("res://scripts/util.gd")

const KIND_COLORS := {
	"era": "d9b96a",     # gold
	"magic": "8b7fd9",   # violet
	"build": "6fbf73",   # green
	"crisis": "d96a6a",  # red
	"pop": "6fa8dc",     # blue
	"talk": "8fb3d9",    # pale blue (hero conversations)
	"info": "9aa3b5",    # grey
}

var entries: Array = []  # {day, minute, text, kind}

func add(day: int, minute: float, text: String, kind: String = "info") -> void:
	entries.append({"day": day, "minute": minute, "text": text, "kind": kind})
	print("[年代記] %s %s" % [U.fmt_time(day, minute), text])

func to_bbcode(limit: int = 80, filter := "all") -> String:
	var picked: Array = []
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		var is_talk: bool = e["kind"] == "talk"
		if filter == "talk" and not is_talk:
			continue
		if filter == "events" and is_talk:
			continue
		picked.append(e)
		if picked.size() >= limit:
			break
	if picked.is_empty():
		return "[color=#9aa3b5]まだ何もない。[/color]"
	var out := ""
	for e in picked:
		var col: String = KIND_COLORS.get(e["kind"], "9aa3b5")
		out += "[color=#6a7186]%d日目[/color] [color=#%s]%s[/color]\n" % [e["day"], col, e["text"]]
	return out

func highlights(max_count: int = 8) -> Array:
	var picked: Array = []
	for e in entries:
		if e["kind"] in ["era", "magic", "crisis"]:
			picked.append("%d日目 %s" % [e["day"], e["text"]])
	if picked.size() > max_count:
		picked = picked.slice(picked.size() - max_count, picked.size())
	return picked
