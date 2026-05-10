extends Control

var _code_editor: CodeEdit
var _output_text: Label
var _submit_btn: Button

const PLAYER_SPRITE_HEIGHT = 150.0
const ENEMY_SPRITE_HEIGHT = 200.0

# Session state
var _session_id: String = ""
var _puzzle_id: String = ""
var _skill_type: String = ""
var _attempt_count: int = 0
var _hint_count: int = 0
var _previous_code: String = ""

# Keystroke tracker
var _metrics: BattleMetrics

func _ready() -> void:
	if Globals.instance != null and Globals.instance.ui_theme != null:
		theme = Globals.instance.ui_theme

	_code_editor = get_node("%CodeEditor")
	_output_text  = get_node("%OutputText")
	_submit_btn   = get_node("%SubmitButton")

	# Disabled until the server confirms the session was created.
	_submit_btn.disabled = true
	_submit_btn.pressed.connect(_on_submit_pressed)
	get_node("%DefeatButton").pressed.connect(_on_defeat_pressed)

	_setup_sprites()
	call_deferred("_apply_zoom")

	# --- Server setup ---
	var enemy = SceneManager.battle_enemy
	_puzzle_id  = str(enemy.get("puzzle_id"))   if enemy != null else ""
	_skill_type = _skill_name(enemy.get("skill_type") if enemy != null else 0)

	_metrics = BattleMetrics.new()
	_metrics.start()

	_code_editor.gui_input.connect(_on_code_editor_input)
	ApiClient.submission_completed.connect(_on_submission_completed)
	ApiClient.session_created.connect(_on_session_created)
	ApiClient.request_failed.connect(_on_request_failed)
	ApiClient.puzzle_fetched.connect(_on_puzzle_fetched)

	if not _puzzle_id.is_empty():
		ApiClient.get_puzzle(_puzzle_id)
	_post_session_start()

func _exit_tree() -> void:
	if ApiClient.submission_completed.is_connected(_on_submission_completed):
		ApiClient.submission_completed.disconnect(_on_submission_completed)
	if ApiClient.session_created.is_connected(_on_session_created):
		ApiClient.session_created.disconnect(_on_session_created)
	if ApiClient.request_failed.is_connected(_on_request_failed):
		ApiClient.request_failed.disconnect(_on_request_failed)
	if ApiClient.puzzle_fetched.is_connected(_on_puzzle_fetched):
		ApiClient.puzzle_fetched.disconnect(_on_puzzle_fetched)

# ---------------------------------------------------------------------------
# Keystroke capture
# ---------------------------------------------------------------------------

func _on_code_editor_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.echo:
		return
	if key.pressed:
		_metrics.record_key_down(key.physical_keycode)
	else:
		_metrics.record_key_up(key.physical_keycode)

# ---------------------------------------------------------------------------
# Submit
# ---------------------------------------------------------------------------

func _on_submit_pressed() -> void:
	_attempt_count += 1
	var code := _code_editor.text
	var raw_metrics := _metrics.collect()

	var payload := {
		"playerId":       PlayerDataManager.user_id,
		"sessionId":      _session_id,
		"puzzleId":       _puzzle_id,
		"skillType":      _skill_type,
		"sourceCode":     code,
		"hintUsageCount": _hint_count,
		"keystrokeData":  {
			"averageFlightTimeMs": raw_metrics.get("avg_flight_time_ms", -1.0),
			"averageDwellTimeMs":  raw_metrics.get("avg_dwell_time_ms",  -1.0),
			"initialLatencyMs":    raw_metrics.get("initial_latency_ms", -1.0),
			"totalTimeSeconds":    raw_metrics.get("total_time_seconds",  0.0),
			"rawEvents":           raw_metrics.get("raw_events", []),
		},
	}
	_previous_code = code

	_output_text.text = "Submitting..."
	_submit_btn.disabled = true
	ApiClient.post_submission(payload)

# ---------------------------------------------------------------------------
# Response handling
# ---------------------------------------------------------------------------

func _on_puzzle_fetched(data: Dictionary) -> void:
	var desc: String = data.get("description", "")
	var code: String = data.get("starterCode", "")
	if not desc.is_empty():
		set_problem_text(desc)
	if not code.is_empty():
		_code_editor.text = code
		_code_editor.set_caret_line(_code_editor.get_line_count() - 1)

func _on_session_created(data: Dictionary) -> void:
	_session_id = str(data.get("id", ""))
	_submit_btn.disabled = false
	GameLogger.info("BattleScene: session created id=%s" % _session_id)

func _on_submission_completed(data: Dictionary) -> void:
	var correct: bool              = data.get("isCorrect", false)
	if not correct:
		_submit_btn.disabled = false

	var diag_msg: String           = data.get("diagnosticMessage", "")
	var _diag_category: String     = data.get("diagnosticCategory", "")
	var intervention_type: String  = data.get("interventionType", "None")
	var npc_dialogue: Dictionary   = data.get("npcDialogue", {})
	var is_mastered: bool          = data.get("isMastered", false)
	var mastery_pct: float         = data.get("masteryProbability", 0.0) * 100.0
	var xp: int                    = data.get("xpAwarded", 0)

	# Line number from first compiler diagnostic (if any)
	var compiler_diags: Array = data.get("compilerDiagnostics", [])
	var line_no: int = compiler_diags[0].get("line", -1) if not compiler_diags.is_empty() else -1
	var loc := "  (line %d)" % line_no if line_no > 0 else ""

	if correct:
		_output_text.text = "Correct!    Mastery: %d%%" % int(mastery_pct)
		if xp > 0:
			_output_text.text += "\n+%d XP" % xp
		if is_mastered:
			await _show_server_dialogue("Odin", "You've mastered this skill. Well done.", "")
		await get_tree().create_timer(3.0).timeout
		_finish_session(true)
		return

	var msg := diag_msg if not diag_msg.is_empty() else "Incorrect."
	_output_text.text = "%s%s" % [msg, loc]

	if xp > 0:
		_output_text.text += "\n+%d XP" % xp

	match intervention_type:
		"ScaffoldingHint":
			var support: String = npc_dialogue.get("dialogueText", "")
			var hint: String    = npc_dialogue.get("technicalHint", "")
			if not hint.is_empty():
				support = (support + "\n" if not support.is_empty() else "") + hint
			if not support.is_empty():
				_output_text.text += "\n\n" + support
		"Rejection":
			_output_text.text += "\nTry a different approach."

func _on_request_failed(tag: String, code: int) -> void:
	match tag:
		"submission":
			_submit_btn.disabled = false
			_output_text.text = "Could not reach the server. (HTTP %d)\nYour code was not evaluated." % code
		"session_start":
			_output_text.text = "Could not create session. (HTTP %d)\nSubmitting is disabled." % code
		"puzzle_fetch":
			set_problem_text("(Puzzle failed to load — puzzle_id: %s)" % _puzzle_id)

# ---------------------------------------------------------------------------
# Session management
# ---------------------------------------------------------------------------

func _post_session_start() -> void:
	var dungeon_level := 0
	if SceneManager.current_level != null:
		var level_name := str(SceneManager.current_level.name)
		if level_name.length() > 5:
			dungeon_level = int(level_name[5])

	ApiClient.post_session_start({
		"userId":       PlayerDataManager.user_id,
		"puzzleId":     _puzzle_id,
		"dungeonLevel": dungeon_level,
	})

func _on_defeat_pressed() -> void:
	_finish_session(false)

func _finish_session(_completed: bool) -> void:
	if ApiClient.submission_completed.is_connected(_on_submission_completed):
		ApiClient.submission_completed.disconnect(_on_submission_completed)
	if ApiClient.session_created.is_connected(_on_session_created):
		ApiClient.session_created.disconnect(_on_session_created)
	if ApiClient.request_failed.is_connected(_on_request_failed):
		ApiClient.request_failed.disconnect(_on_request_failed)
	if ApiClient.puzzle_fetched.is_connected(_on_puzzle_fetched):
		ApiClient.puzzle_fetched.disconnect(_on_puzzle_fetched)

	if not _session_id.is_empty():
		ApiClient.patch_session_end(_session_id)
	SceneManager.end_battle()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _show_server_dialogue(speaker: String, text: String, hint: String) -> void:
	var entries: Array[DialogueEntry] = []
	if not text.is_empty():
		var e1 := DialogueEntry.new()
		e1.speaker_name = speaker
		e1.text = text
		entries.append(e1)
	if not hint.is_empty():
		var e2 := DialogueEntry.new()
		e2.speaker_name = speaker
		e2.text = hint
		entries.append(e2)
	if not entries.is_empty():
		await DialogueManager.show(entries)

static func _skill_name(index: int) -> String:
	var keys := Enums.SkillType.keys()
	return keys[index] if index >= 0 and index < keys.size() else "Unknown"

# ---------------------------------------------------------------------------
# Visual setup (unchanged)
# ---------------------------------------------------------------------------

func _apply_zoom() -> void:
	var hgap = get_node("MarginContainer/ContentSplit/LeftVBox/VisualPanel/VisualHBox/HGap")
	if hgap:
		hgap.custom_minimum_size.x = 16.0
	var bg           = get_node("%BattleBG")
	var visual_hbox  = get_node("MarginContainer/ContentSplit/LeftVBox/VisualPanel/VisualHBox")
	var _visual_panel = get_node("MarginContainer/ContentSplit/LeftVBox/VisualPanel")
	var zoom_scale   = Vector2(2.0, 2.0)
	if bg:
		bg.pivot_offset = bg.size / 2.0
		bg.scale = zoom_scale
	if visual_hbox:
		visual_hbox.pivot_offset = visual_hbox.size / 2.0
		visual_hbox.scale = zoom_scale
		visual_hbox.position.y += 10.0

func _setup_sprites() -> void:
	var enemy_display  = get_node("%EnemyDisplay")
	var player_display = get_node("%PlayerDisplay")
	var character: String = Globals.instance.selected_character if Globals.instance != null else "playerm"
	var enemy = SceneManager.battle_enemy
	var is_final_boss: bool = enemy.is_final_boss if enemy != null else false
	if is_final_boss:
		enemy_display.custom_minimum_size = Vector2(0, ENEMY_SPRITE_HEIGHT)
	enemy_display.texture = _load_battle_texture("player", character)
	var bg = get_node("%BattleBG")
	if enemy != null and is_final_boss:
		bg.texture = _load_battle_texture("bg", "boss")
	else:
		var enemy_id: String = enemy.enemy_id if enemy != null else ""
		var bg_tex := _load_battle_texture("bg", enemy_id)
		bg.texture = bg_tex if bg_tex != null else _load_battle_texture("bg", "default")
	if enemy != null:
		if is_final_boss:
			var boss_char = "playerf" if character == "playerm" else "playerm"
			player_display.texture = _flip_horizontal(_load_battle_texture("player", boss_char))
		else:
			var et := _load_battle_texture("enemy", enemy.enemy_id)
			player_display.texture = et if et != null else _load_battle_texture("enemy", "default")

func _flip_horizontal(source: Texture2D) -> Texture2D:
	if source == null:
		return null
	var img = source.get_image()
	img.flip_x()
	return ImageTexture.create_from_image(img)

func _load_battle_texture(folder: String, texture_name: String) -> Texture2D:
	if texture_name.is_empty():
		return null
	var path := "res://assets/battle/%s/%s.png" % [folder, texture_name]
	return load(path) if ResourceLoader.exists(path) else null

func set_problem_text(text: String) -> void:
	var label = get_node("%ProblemText")
	label.text = text
	call_deferred("_adjust_problem_font_size", label)

func _adjust_problem_font_size(label: Label) -> void:
	var panel = get_node("MarginContainer/ContentSplit/RightVBox/ProblemPanel")
	var available = panel.size.y - 24.0
	var width = label.size.x
	if width <= 0:
		return
	var font = label.get_theme_font("font")
	for f_size in range(64, 7, -1):
		label.add_theme_font_size_override("font_size", f_size)
		var text_size = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, f_size)
		if text_size.y <= available:
			return
