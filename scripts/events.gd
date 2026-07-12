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
		"event_id": str(ev.get("id", "")),
		"mood": str(ev.get("mood", "normal")),
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
		"mood": "determined",
	}

# --- daily guidance -------------------------------------------------------------
# The god no longer micromanages projects: every morning he only points at a
# path (POLICY). The village then develops itself (projects.auto_develop).

const POLICY_RESPONSES := {
	"minori": "実りの道ですね！　輪作に堆肥に……日本の農業の知識、フル活用でいきます！",
	"takumi": "匠の道！　ものづくりは日本のお家芸です。向こうの世界の道具、どんどん再現しますよ！",
	"hoshi": "星の道……魔法は日本になかった分野です。ぼくの知識と組み合わせたら、すごいことになりますよ！",
	"mori": "森の道——里山ってやつですね。森と一緒に暮らす知恵なら、任せてください！",
}

func _guidance_convo() -> Dictionary:
	var w = main.world
	var choices: Array = []
	var payloads: Array = []

	var cur: Dictionary = main.projects.policy_def(w.policy)
	choices.append({"label": "「%s」を歩み続けよ" % cur["name"],
		"sub": str(cur["desc"]) + "　— いまの道"})
	payloads.append({"policy": w.policy,
		"response": "はい。今日も%sを歩みます。" % cur["name"]})

	for pid in _suggest_policies(2):
		var pd: Dictionary = main.projects.policy_def(pid)
		choices.append({"label": "「%s」を示す" % pd["name"],
			"sub": "%s　+%s" % [str(pd["desc"]), U.AXIS_NAMES.get(str(pd["axis"]), "")]})
		payloads.append({"policy": pid,
			"response": str(POLICY_RESPONSES.get(pid, "はい、その道を歩みます。"))})

	if float(w.res["mana"]) >= 15.0:
		choices.append({"label": "村に祝福を降らせる", "sub": "皆の心が晴れる　✨15を使う"})
		payloads.append({"effects": {"res_mana": -15, "mood_all": 12},
			"response": "あたたかい光……。みんな、今日はいい顔で働けそうです。"})

	var mood := "normal"
	if w.starvation_days > 0 or float(w.res["food"]) < float(w.pop() * 5) \
			or float(w.danger["war"]) > 0.0 or float(w.danger["blight"]) >= 40.0:
		mood = "worried"
	return {
		"speaker": "アシタ",
		"text": _prayer_text(),
		"choices": choices,
		"payloads": payloads,
		"mood": mood,
	}

# Which alternative paths feel most urgent today; keeps the dice-god's whims
# grounded in what the village actually needs.
func _suggest_policies(n: int) -> Array:
	var w = main.world
	var scores: Dictionary = {}
	for pid in main.projects.POLICIES:
		if pid == w.policy:
			continue
		scores[pid] = randf() * 10.0
	if scores.has("minori") and (w.starvation_days > 0 or float(w.res["food"]) < float(w.pop() * 6)):
		scores["minori"] += 60.0
	if scores.has("takumi") and float(w.danger["war"]) > 0.0:
		scores["takumi"] += 40.0
	if scores.has("mori") and float(w.danger["blight"]) >= 40.0:
		scores["mori"] += 40.0
	if scores.has("hoshi") and not main.magic.trainable().is_empty():
		scores["hoshi"] += 12.0
	var ids: Array = scores.keys()
	ids.sort_custom(func(a, b): return scores[a] > scores[b])
	return ids.slice(0, mini(n, ids.size()))

func _prayer_text() -> String:
	var w = main.world
	var pool: Array
	if main.day() == 1:
		pool = dlg.get("prayer_first", dlg.get("prayer_solo", ["神さま、今日は何をいたしましょう。"]))
	elif main.villagers.is_empty():
		pool = dlg.get("prayer_solo", dlg.get("prayer_normal", ["神さま、今日は何をいたしましょう。"]))
	elif w.starvation_days > 0 or float(w.res["food"]) < float(w.pop() * 5):
		pool = dlg.get("prayer_hungry", ["神さま……食べものが心配です。どうかお導きを。"])
	elif float(w.danger["war"]) > 0.0 or float(w.danger["blight"]) >= 40.0:
		pool = dlg.get("prayer_danger", ["神さま、胸騒ぎがします。わたしは何をすべきでしょう。"])
	else:
		pool = dlg.get("prayer_normal", ["神さま、おはようございます。今日は何をすべきでしょうか。"])
	return str(pool[randi() % pool.size()])

# --- resolution --------------------------------------------------------------------

# Japanese headings for the History Book (ESC menu); events not listed here are
# daily guidance, not civilization turning points.
const HIST_TITLES := {
	"war_attack": "軍勢の襲来",
	"plague": "はやり病",
	"plague_spread": "病のさなかで",
	"blight_warning": "枯れの兆し",
	"neighbor_visit": "隣人たちの訪れ",
	"forbidden_tome": "禁忌の書",
	"drought": "日照りの季節",
	"beast_howl": "獣の遠吠え",
	"meteor": "星降りの夜",
	"monster_raid": "魔物の襲撃",
	"flood": "大洪水",
}

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
	if p.has("policy"):
		main.world.set_policy(str(p["policy"]))
	if p.has("project"):
		if not main.projects.start(str(p["project"])):
			return "……申し訳ありません、いまは手が足りないようです。"
	if p.has("chronicle"):
		main.log_event(str(p["chronicle"]), str(p.get("chronicle_kind", "info")))
	_record_history(convo, idx, p)
	main.world.check_endings()
	main.projects.auto_develop()
	return str(p.get("response", "……はい、わかりました。"))

# Turning points (era transitions and major event decisions) go into
# world.history, which the ESC-menu History Book renders.
func _record_history(convo: Dictionary, idx: int, p: Dictionary) -> void:
	var label := ""
	var choices: Array = convo.get("choices", [])
	if idx >= 0 and idx < choices.size():
		label = str(choices[idx].get("label", ""))
	var eid := str(convo.get("event_id", ""))
	if p.get("era_up", false):
		# do_era_up already ran above, so era_name() is the new era.
		main.world.history.append({
			"day": main.day(), "kind": "era",
			"title": "時代の岐路 —「%s」へ" % main.world.era_name(),
			"choice": label,
			"text": str(p.get("response", "")),
		})
	elif HIST_TITLES.has(eid):
		main.world.history.append({
			"day": main.day(), "kind": "event",
			"title": str(HIST_TITLES[eid]),
			"choice": label,
			"text": str(p.get("response", "")),
		})
