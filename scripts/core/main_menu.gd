extends Control

signal game_start_requested(character: String)

func _ready() -> void:
	if Globals.instance and Globals.instance.ui_theme:
		theme = Globals.instance.ui_theme
	
	var welcome_label = get_node("%WelcomeLabel")
	var continue_button = get_node("%ContinueButton")
	var new_game_button = get_node("%NewGameButton")
	
	var player_name: String = PlayerDataManager.player_name
	welcome_label.text = "Welcome!" if player_name.is_empty() else "Welcome back, %s!" % player_name
	
	continue_button.visible = PlayerDataManager.has_played
	new_game_button.visible = not PlayerDataManager.has_played
	
	continue_button.pressed.connect(_on_continue_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	get_node("%SettingsButton").pressed.connect(_on_settings_pressed)

func _on_continue_pressed() -> void:
	game_start_requested.emit(PlayerDataManager.selected_character)

func _on_new_game_pressed() -> void:
	var select_scene = load("res://scenes/core/character_select.tscn")
	var select = select_scene.instantiate()
	add_child(select)
	select.character_selected.connect(_on_character_selected)
	select.cancelled.connect(select.queue_free)

func _on_settings_pressed() -> void:
	var pause_scene = load("res://scenes/ui/pause_menu.tscn")
	var menu = pause_scene.instantiate()
	menu.is_from_main_menu = true
	add_child(menu)
	menu.resumed.connect(func(): menu.queue_free())

func _on_character_selected(character: String) -> void:
	PlayerDataManager.save_character(character)
	game_start_requested.emit(character)
