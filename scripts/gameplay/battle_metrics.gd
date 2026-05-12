class_name BattleMetrics
extends RefCounted

var _load_time_ms: float = 0.0
var _first_key_time_ms: float = -1.0
var _last_key_up_ms: float = -1.0
var _dwell_times: Array[float] = []
var _flight_times: Array[float] = []
var _key_down_times: Dictionary = {}
var _raw_events: Array = []
var _paste_detected: bool = false
var _last_paste_ms: float = -1.0
var _last_paste_char_count: int = 0
var _key_down_count: int = 0
var _key_down_count_at_last_paste: int = 0

func start() -> void:
	_load_time_ms = float(Time.get_ticks_msec())

func record_paste(pasted_text: String = "") -> void:
	var now := float(Time.get_ticks_msec())
	_paste_detected = true
	_last_paste_ms = now
	_last_paste_char_count = pasted_text.length()
	_key_down_count_at_last_paste = _key_down_count
	_raw_events.append([int(now), 0, 2, _last_paste_char_count])

func record_key_down(keycode: int) -> void:
	var now := float(Time.get_ticks_msec())
	_key_down_count += 1
	if _first_key_time_ms < 0.0:
		_first_key_time_ms = now
	if _last_key_up_ms >= 0.0:
		_flight_times.append(now - _last_key_up_ms)
	_key_down_times[keycode] = now
	_raw_events.append([int(now), keycode, 0])

func record_key_up(keycode: int) -> void:
	var now := float(Time.get_ticks_msec())
	_last_key_up_ms = now
	if keycode in _key_down_times:
		_dwell_times.append(now - float(_key_down_times[keycode]))
		_key_down_times.erase(keycode)
	_raw_events.append([int(now), keycode, 1])

func collect() -> Dictionary:
	var now := float(Time.get_ticks_msec())
	var seconds_since_paste := -1.0
	if _last_paste_ms >= 0.0:
		seconds_since_paste = (now - _last_paste_ms) / 1000.0
	var result := {
		"avg_flight_time_ms":    _avg(_flight_times),
		"avg_dwell_time_ms":     _avg(_dwell_times),
		"initial_latency_ms":    (_first_key_time_ms - _load_time_ms) if _first_key_time_ms >= 0.0 else -1.0,
		"total_time_seconds":    (now - _load_time_ms) / 1000.0,
		"paste_detected":        _paste_detected,
		"seconds_since_paste":   seconds_since_paste,
		"pasted_char_count":     _last_paste_char_count,
		"key_downs_since_paste": max(0, _key_down_count - _key_down_count_at_last_paste),
	}
	result["raw_events"] = _raw_events.duplicate()
	# Reset per-attempt buffers so next submission reflects only that attempt's keystrokes.
	_dwell_times.clear()
	_flight_times.clear()
	_raw_events.clear()
	_first_key_time_ms = -1.0
	_last_key_up_ms    = -1.0
	_paste_detected    = false
	_last_paste_ms     = -1.0
	_last_paste_char_count = 0
	_key_down_count    = 0
	_key_down_count_at_last_paste = 0
	_load_time_ms      = now
	return result

# Levenshtein distance between two strings (used for edit_distance metric).
static func levenshtein(a: String, b: String) -> int:
	var m := a.length()
	var n := b.length()
	if m == 0: return n
	if n == 0: return m
	var prev: Array = []
	prev.resize(n + 1)
	for j in range(n + 1):
		prev[j] = j
	for i in range(1, m + 1):
		var curr: Array = []
		curr.resize(n + 1)
		curr[0] = i
		for j in range(1, n + 1):
			curr[j] = prev[j - 1] if a[i - 1] == b[j - 1] else 1 + mini(prev[j], mini(curr[j - 1], prev[j - 1]))
		prev = curr
	return prev[n]

static func _avg(arr: Array[float]) -> float:
	if arr.is_empty():
		return 0.0
	var total := 0.0
	for v in arr:
		total += v
	return total / float(arr.size())
