extends RefCounted
# The village chronicle: a timestamped log of everything that mattered.

const U = preload("res://scripts/util.gd")

const KIND_COLORS := {
	"era": "d9b96a",     # gold
	"magic": "8b7fd9",   # violet
	"build": "6fbf73",   # green
	"crisis": "d96a6a",  # red
	"pop": "6fa8dc",     # blue
	"info": "9aa3b5",    # grey
}

var entries: Array = []  # {day, minute, text, kind}

func add(day: int, minute: float, text: String, kind: String = "info") -> void:
	entries.append({"day": day, "minute": minute, "text": text, "kind": kind})
	print("[年代記] %s %s" % [U.fmt_time(day, minute), text])

func to_bbcode(limit: int = 80) -> String:
	if entries.is_empty():
		return "[color=#9aa3b5]まだ何も起きていない。[/color]"
	var out := ""
	var start := maxi(0, entries.size() - limit)
	for i in range(entries.size() - 1, start - 1, -1):
		var e: Dictionary = entries[i]
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
