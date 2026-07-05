extends Control

signal arena_level_requested(level_name: int)
signal back_requested

const ARENA_LEVELS: Array[Dictionary] = [
	{
		"label": "Level 0",
		"level": Enums.LevelName.Level0,
		"achievement": "level0_complete",
	},
	{
		"label": "Level 1",
		"level": Enums.LevelName.Level1,
		"achievement": "level1_complete",
	},
	{
		"label": "Level 2",
		"level": Enums.LevelName.Level2,
		"achievement": "level2_complete",
	},
	{
		"label": "Level 3",
		"level": Enums.LevelName.Level3,
		"achievement": "level3_complete",
	},
	{
		"label": "Final Boss",
		"level": Enums.LevelName.Level31,
		"achievement": "final_boss_complete",
	},
]

var _level_buttons: Array[Button] = []

func _ready() -> void:
	if Globals.instance and Globals.instance.ui_theme:
		theme = Globals.instance.ui_theme

	_build_level_buttons()
	get_node("%BackButton").pressed.connect(func(): back_requested.emit())

func _build_level_buttons() -> void:
	var container: VBoxContainer = get_node("%LevelButtons")
	for child in container.get_children():
		child.queue_free()
	_level_buttons.clear()

	for entry in ARENA_LEVELS:
		var button := Button.new()
		button.text = str(entry["label"])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var unlocked := str(entry["achievement"]) in PlayerDataManager.achievements
		button.disabled = not unlocked
		if not unlocked:
			button.text += "  (Locked)"
		var level_name := int(entry["level"])
		button.pressed.connect(func(): arena_level_requested.emit(level_name))
		container.add_child(button)
		_level_buttons.append(button)
