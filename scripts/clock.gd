extends Node
# Game time. 1 real second = 12 game minutes at 1x (one day = 120s).
# advance() is the single source of simulation time; everything downstream
# consumes game minutes, never real delta.

signal day_started(day: int)
signal hour_started(hour: int)

const MIN_PER_SEC := 12.0
const SPEEDS := [0, 1, 3, 8]

var day: int = 1
var minute_of_day: float = 320.0  # 05:20, just before the morning prayer
var speed_index: int = 1
var _prev_speed: int = 1
var _paused_by_dialog := false

func advance(delta: float) -> float:
	var gmin := delta * MIN_PER_SEC * float(SPEEDS[speed_index])
	if gmin > 0.0:
		force_advance(gmin)
	return gmin

func force_advance(gmin: float) -> void:
	var prev_hour := int(minute_of_day) / 60
	minute_of_day += gmin
	while minute_of_day >= 1440.0:
		minute_of_day -= 1440.0
		day += 1
		prev_hour = -1
		day_started.emit(day)
	var hour := int(minute_of_day) / 60
	if hour != prev_hour:
		hour_started.emit(hour)

func abs_minutes() -> float:
	return float(day - 1) * 1440.0 + minute_of_day

func is_night() -> bool:
	return minute_of_day >= 1290.0 or minute_of_day < 300.0

func set_speed(index: int) -> void:
	if _paused_by_dialog:
		_prev_speed = clampi(index, 0, SPEEDS.size() - 1)
		return
	speed_index = clampi(index, 0, SPEEDS.size() - 1)

func toggle_pause() -> void:
	if _paused_by_dialog:
		return
	if speed_index == 0:
		speed_index = maxi(_prev_speed, 1)
	else:
		_prev_speed = speed_index
		speed_index = 0

func dialog_pause() -> void:
	if not _paused_by_dialog:
		_prev_speed = speed_index
		_paused_by_dialog = true
	speed_index = 0

func dialog_resume() -> void:
	if _paused_by_dialog:
		_paused_by_dialog = false
		speed_index = maxi(_prev_speed, 1)
