extends Node
# Autoload: PlayerDataManager
# Persists player data to user://player_data.json (IndexedDB on web).
# When your server is ready, replace load_data/write_to_file with HTTP calls.

const SAVE_PATH: String = "user://player_data.json"

const ACHIEVEMENTS: Array = [
	{
		"id": "level0_complete",
		"title": "First Blood Draw",
		"description": "Completed the diagnostic test. Your knowledge has been measured, catalogued, and filed appropriately.",
	},
	{
		"id": "level1_complete",
		"title": "In a Row",
		"description": "Tamed the single-dimensional array. One dimension down — the others are watching.",
	},
	{
		"id": "level2_complete",
		"title": "Around and Around",
		"description": "Conquered loops and iteration. The code runs endlessly — you just decide when it stops.",
	},
	{
		"id": "level3_complete",
		"title": "The Grid Whisperer",
		"description": "Survived multidimensional arrays and nested loops. You can traverse a grid in your sleep now.",
	},
	{
		"id": "final_boss_complete",
		"title": "Return 0",
		"description": "The final boss is defeated. The program exits cleanly — no errors, no exceptions, just you, victorious.",
	},
]

var user_id: String = ""
var has_played: bool = false
var player_name: String = ""
var selected_character: String = "playerm"
var achievements: Array[String] = []
var last_level_name: String = ""
var last_position: Vector2 = Vector2.ZERO
var triggered_dialogues: Array[String] = []

# Intentionally NOT called on startup (debug mode).
# Reads local JSON; swap for an HTTP call when server is ready.
func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		has_played = false
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.ModeFlags.READ)
	if file == null:
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return

	var data: Dictionary = json.data
	has_played = true
	selected_character = data.get("selected_character", "playerm")
	player_name        = data.get("player_name", "")
	last_level_name    = data.get("last_level", "")
	var pos_x          = data.get("last_position_x", 0.0)
	var pos_y          = data.get("last_position_y", 0.0)
	last_position      = Vector2(pos_x, pos_y)

	achievements = []
	for b in data.get("achievements", data.get("badges", [])):
		achievements.append(str(b))

	triggered_dialogues = []
	for t in data.get("triggered_dialogues", []):
		triggered_dialogues.append(str(t))

func save_character(character: String) -> void:
	selected_character = character
	has_played = true
	_write_to_file()

func save_progress(level_name: String, position: Vector2 = Vector2.ZERO) -> void:
	last_level_name = level_name
	last_position = position
	_write_to_file()

func mark_dialogue_triggered(trigger_id: String) -> void:
	if not trigger_id in triggered_dialogues:
		triggered_dialogues.append(trigger_id)
	_write_to_file()

func unlock_achievement(id: String) -> void:
	if id not in achievements:
		achievements.append(id)
		_write_to_file()

func set_from_server(
		p_has_played: bool,
		p_player_name: String,
		p_character: String,
		p_achievements: Array[String],
		p_last_level: String = "",
		p_last_position: Vector2 = Vector2.ZERO,
		p_triggered_dialogues: Array[String] = []) -> void:
	has_played          = p_has_played
	player_name         = p_player_name
	selected_character  = p_character if p_character != "" else "playerm"
	achievements        = p_achievements
	last_level_name     = p_last_level
	last_position       = p_last_position
	triggered_dialogues = p_triggered_dialogues

func _write_to_file() -> void:
	var data := {
		"selected_character":  selected_character,
		"player_name":         player_name,
		"achievements":        achievements.duplicate(),
		"last_level":          last_level_name,
		"last_position_x":     last_position.x,
		"last_position_y":     last_position.y,
		"triggered_dialogues": triggered_dialogues.duplicate(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.ModeFlags.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data))
