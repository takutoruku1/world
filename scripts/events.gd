extends RefCounted
# The god's conversation engine. Every prayer picks, in priority order:
# a triggered crisis/milestone event -> the era-up decision -> daily guidance
# (dynamically assembled choices: continue training / projects / spells / policies).

const U = preload("res://scripts/util.gd")

var main
var defs: Array = []
var dlg: Dictionary = {}          # dialogue.json
var seen: Dictionary = {}         # event id -> last day shown

func setup(m, events_data: Dictionary, dialogue_data: Dictionary) -> void:
	main = m
	defs = events_data.get("events", [])
	dlg = dialogue_data

func on_prayer() -> Dictionary:
	var ev := _match_event()
	if not ev.is_empty():
		return _event_convo(ev)
	if main.world.pending_era_up and main.day() >= int(main.world.flags.get("era_snooze_until", 0)):
		return _era_up_convo()
	return _guidance_convo()

# --- data-driven events -----------------------------------------------------

func _match_event() -> Dictionary:
	for ev in defs:
		var id := str(ev.get("id", ""))
		if seen.has(id):
			if ev.get("once", true):
				continue
			var gap := int(ev.get("cooldown_days", 5))
			if main.day() - int(seen[id]) < gap:
				continue
		if _cond_ok(ev.get("condition", {})):
			return ev
	return {}

func _cond_ok(c: Dictionary) -> bool:
	var w = main.world
	if w.era < int(c.get("min_era", 0)):
		return false
	if w.era > int(c.get("max_era", 99)):
		return false
	if main.day() < int(c.get("min_day", 0)):
		return false
	if w.pop() < int(c.get("pop_gte", 0)):
		return false
	if float(w.danger["war"]) < float(c.get("danger_war_gte", -1.0)):
		return false
	if float(w.danger["blight"]) < float(c.get("danger_blight_gte", -1.0)):
		return false
	for k in c.get("res_lt", {}):
		if float(w.res.get(k, 0.0)) >= float(c["res_lt"][k]):
			return false
	var f := str(c.get("flag", ""))
	if f != "" and not w.flags.get(f, false):
		return false
	var nf := str(c.get("not_flag", ""))
	if nf != "" and w.flags.get(nf, false):
		return false
	if c.has("chance") and randf() > float(c["chance"]):
		return false
	return true

func _event_convo(ev: Dictionary) -> Dictionary:
	seen[str(ev.get("id", ""))] = main.day()
	var choices: Array = []
	var payloads: Array = []
	for c in ev.get("choices", []):
		var rb := str(c.get("requires_building", ""))
		if rb != "" and not main.town.has_built(rb):
			continue
		var rs := str(c.get("requires_spell", ""))
		if rs != "" and not main.magic.is_known(rs):
			continue
		if c.has("requires_res") and not main.world.can_afford(c["requires_res"]):
			continue
		choices.append({"label": str(c.get("label", "…")), "sub": str(c.get("sub", ""))})
		payloads.append(c)
	return {
		"speaker": str(ev.get("speaker", "アシタ")),
		"text": str(ev.get("text", "")),
		"choices": choices,
		"payloads": payloads,
	}

# --- era up -------------------------------------------------------------------

func _era_up_convo() -> Dictionary:
	var choices: Array = [
		{"label": "工の道を示す", "sub": "道具と炎の文明へ　+機械"},
		{"label": "森の道を示す", "sub": "大地と共に生きる文明へ　+自然"},
		{"label": "星の道を示す", "sub": "魔法を極める文明へ　+神秘"},
		{"label": "時を待て", "sub": "まだ次の時代へは進まない"},
	]
	var payloads: Array = [
		{"era_up": true, "effects": {"axis_tech": 15}, "response": "はい。鎚と歯車の音が、村の明日を作るのですね。"},
		{"era_up": true, "effects": {"axis_nature": 15}, "response": "はい。木々と水のささやきに、耳を澄ませて生きていきます。"},
		{"era_up": true, "effects": {"axis_mystic": 15}, "response": "はい。星々の理を、この地に降ろしてみせます。"},
		{"snooze_era": true, "response": "わかりました。機が熟すのを待ちます。"},
	]
	return {
		"speaker": "アシタ",
		"text": "神さま……村は満ちてきました。わたしたちは、次の高みへ進めるはずです。どの道をお示しになりますか？",
		"choices": choices,
		"payloads": payloads,
	}

# --- daily guidance -------------------------------------------------------------

func _guidance_convo() -> Dictionary:
	var w = main.world
	var choices: Array = []
	var payloads: Array = []

	var tp: Dictionary = main.protagonist.training_progress()
	if not tp.is_empty():
		choices.append({"label": "修行を続けさせる",
			"sub": "「%s」 進み %d%%" % [tp["name"], int(tp["ratio"] * 100.0)]})
		payloads.append({"continue": true,
			"response": "はい。今日も「%s」の修行に励みます。" % tp["name"]})

	var projs: Array = main.projects.available()
	projs.shuffle()
	projs.sort_custom(func(a, b): return _proj_priority(a) > _proj_priority(b))
	for i in range(mini(2, projs.size())):
		if choices.size() >= 3:
			break
		var p: Dictionary = projs[i]
		var verb := "を作らせる" if str(p.get("kind", "building")) == "building" else "をさせる"
		choices.append({"label": "「%s」%s" % [p.get("name", "?"), verb],
			"sub": "%s　%s%s" % [str(p.get("desc", "")), U.fmt_cost(p.get("cost", {})), _axis_hint(p)]})
		payloads.append({"project": str(p.get("id", "")),
			"response": "わかりました。今日から「%s」に取りかかります。" % p.get("name", "?")})

	if tp.is_empty() and choices.size() < 3:
		var spells: Array = main.magic.trainable()
		if not spells.is_empty():
			spells.shuffle()
			spells.sort_custom(func(a, b): return int(a.get("era", 0)) > int(b.get("era", 0)))
			var s: Dictionary = spells[0]
			choices.append({"label": "魔法「%s」を授ける" % s.get("name", "?"),
				"sub": "%s　修行%d時間%s" % [str(s.get("desc", "")), int(s.get("train_hours", 16)), _axis_hint(s)]})
			payloads.append({"train": str(s.get("id", "")),
				"response": "ありがとうございます……！「%s」、必ず覚えてみせます。" % s.get("name", "?")})

	if choices.size() < 4 and float(w.res["mana"]) >= 15.0:
		choices.append({"label": "村に祝福を降らせる", "sub": "皆の心が晴れる　✨15を使う"})
		payloads.append({"effects": {"res_mana": -15, "mood_all": 12},
			"response": "あたたかい光……。みんな、今日はいい顔で働けそうです。"})

	if choices.size() < 4 and tp.is_empty():
		choices.append({"label": "皆と共に働け", "sub": "畑や森の仕事を手伝わせる"})
		payloads.append({"policy": "work",
			"response": "はい。今日は皆と一緒に汗を流します。"})

	return {
		"speaker": "アシタ",
		"text": _prayer_text(),
		"choices": choices,
		"payloads": payloads,
	}

func _proj_priority(p: Dictionary) -> float:
	var w = main.world
	var score := randf() * 10.0
	var prod: Dictionary = p.get("production", {})
	if prod.has("food") and float(w.res["food"]) < float(w.pop() * 8):
		score += 60.0
	if str(p.get("id", "")) == "hut" and main.town.housing_capacity() <= w.pop():
		score += 50.0
	if p.has("axis"):
		for a in p["axis"]:
			if a == w.dominant_axis():
				score += 12.0
	return score

func _axis_hint(def: Dictionary) -> String:
	var parts: Array = []
	for a in def.get("axis", {}):
		parts.append("+" + str(U.AXIS_NAMES.get(a, a)))
	return "" if parts.is_empty() else "　" + " ".join(parts)

func _prayer_text() -> String:
	var w = main.world
	var pool: Array
	if w.starvation_days > 0 or float(w.res["food"]) < float(w.pop() * 5):
		pool = dlg.get("prayer_hungry", ["神さま……食べものが心配です。どうかお導きを。"])
	elif float(w.danger["war"]) > 0.0 or float(w.danger["blight"]) >= 40.0:
		pool = dlg.get("prayer_danger", ["神さま、胸騒ぎがします。わたしは何をすべきでしょう。"])
	else:
		pool = dlg.get("prayer_normal", ["神さま、おはようございます。今日は何をすべきでしょうか。"])
	return str(pool[randi() % pool.size()])

# --- resolution --------------------------------------------------------------------

func resolve(convo: Dictionary, idx: int) -> String:
	var payloads: Array = convo.get("payloads", [])
	if idx < 0 or idx >= payloads.size():
		return "……"
	var p: Dictionary = payloads[idx]
	if p.has("effects"):
		main.world.apply_effects(p["effects"])
	if p.get("era_up", false):
		main.world.do_era_up()
	if p.get("snooze_era", false):
		main.world.flags["era_snooze_until"] = main.day() + 2
	if p.has("train"):
		var sdef: Dictionary = main.magic.get_def(str(p["train"]))
		if not sdef.is_empty():
			main.protagonist.start_training(sdef)
	if p.has("project"):
		if not main.projects.start(str(p["project"])):
			return "……申し訳ありません、いまは手が足りないようです。"
	if p.has("chronicle"):
		main.log_event(str(p["chronicle"]), str(p.get("chronicle_kind", "info")))
	main.world.check_endings()
	return str(p.get("response", "……はい、わかりました。"))
