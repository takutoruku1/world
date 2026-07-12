extends Node
# Auto-play controller for the review run: advances every dialog the way a
# player would (finish typing, then pick the first choice / click through),
# keeps the clock at max speed, captures screenshots at fixed times each day,
# and quits after the final day.

const SHOT_TIMES := [390.0, 780.0, 1120.0, 1380.0]  # 6:30 13:00 18:40 23:00
const LAST_DAY := 13

var main
var dlg_cd := 0.0
var boot_t := 0.0
var started := false
var stuck_cd := 3.0
var taken := {}

func _process(delta: float) -> void:
	if main == null:
		return
	boot_t += delta
	if not started and boot_t > 2.0:
		# Press the title screen's start button the way a player would, so the
		# overlay fades itself out.
		for b in get_tree().root.find_children("*", "Button", true, false):
			if "はじまり" in str(b.text):
				b.pressed.emit()
				started = true
				break
	if not started:
		return
	_auto_dialog(delta)
	_keep_speed(delta)
	_maybe_shot()
	if main.clock.day > LAST_DAY:
		print("REVIEW_RUN DONE day=%d era=%d pop=%d" % [
			main.clock.day, main.world.era, main.world.pop()])
		get_tree().quit(0)

func _auto_dialog(delta: float) -> void:
	dlg_cd -= delta
	var dui = main.dialogue_ui
	if dui == null or dui.panel == null or not dui.panel.visible:
		return
	if dlg_cd > 0.0:
		return
	dlg_cd = 0.55
	if dui._typing:
		dui._finish_typing()
		return
	if dui.choices_panel != null and dui.choices_panel.visible:
		dui._choose(0)
	else:
		dui._choose(-1)

# Chapter cards and other overlays pause the clock and wait for a click;
# synthesize one at the screen center when the sim stalls with no dialog.
func _keep_speed(delta: float) -> void:
	var dui = main.dialogue_ui
	if dui != null and dui.panel != null and dui.panel.visible:
		stuck_cd = 3.0
		return
	if main.clock.speed_index > 0:
		if main.clock.speed_index != 3:
			main.clock.set_speed(3)
		stuck_cd = 3.0
		return
	stuck_cd -= delta
	if stuck_cd <= 0.0:
		stuck_cd = 2.0
		var center := get_viewport().get_visible_rect().size * 0.5
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = center
			ev.global_position = center
			Input.parse_input_event(ev)

func _maybe_shot() -> void:
	var d: int = main.clock.day
	var m: float = main.clock.minute_of_day
	for st in SHOT_TIMES:
		if absf(m - float(st)) <= 8.0:
			var key := "%d_%d" % [d, int(st)]
			if not taken.has(key):
				taken[key] = true
				var img := get_viewport().get_texture().get_image()
				var out := "res://review/day%02d_%04d.png" % [d, int(st)]
				img.save_png(ProjectSettings.globalize_path(out))
				print("REVIEW_SHOT " + out)
