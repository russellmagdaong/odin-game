extends Control

var _code_editor: CodeEdit
var _output_text: Label
var _submit_btn: Button

const PLAYER_SPRITE_HEIGHT = 150.0
const ENEMY_SPRITE_HEIGHT = 200.0
const CODE_FONT_SIZE_DEFAULT: int = 20
const CODE_FONT_SIZE_MIN: int = 6
const CODE_FONT_SIZE_MAX: int = 32

var _code_font_size: int = CODE_FONT_SIZE_DEFAULT

# Session state
var _session_id: String = ""
var _puzzle_id: String = ""
var _skill_type: String = ""
var _attempt_count: int = 0
var _hint_count: int = 0
var _previous_code: String = ""

# Keystroke tracker
var _metrics: BattleMetrics

# ── 4-Phase Telemetry ──
var _inactivity_timer: float = 0.0      # Phase 2: counts up when idle, resets on keystroke
var _last_submit_ms: float = -1.0       # Phase 2: wall-clock ms of last submission
var _error_log: Array[Dictionary] = []  # Phase 2: accumulated errors (reset after intervention)
var _is_baseline: bool = true           # Phase 1: true until first submission fires

# Comment lines in starter code are wrapped to this width (chars) so they
# fit in the CodeEdit at default zoom (font size 20) without horizontal scroll.
const COMMENT_WRAP_WIDTH: int = 52

func _ready() -> void:
	if Globals.instance != null and Globals.instance.ui_theme != null:
		theme = Globals.instance.ui_theme

	_code_editor = get_node("%CodeEditor")
	_output_text  = get_node("%OutputText")
	_submit_btn   = get_node("%SubmitButton")
	_code_editor.add_theme_font_size_override("font_size", _code_font_size)

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
# Phase 2: Telemetry Accumulation — inactivity timer
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_inactivity_timer += delta

# ---------------------------------------------------------------------------
# Keystroke capture
# ---------------------------------------------------------------------------

func _on_code_editor_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.ctrl_pressed and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_set_code_font_size(_code_font_size + 2)
				get_viewport().set_input_as_handled()
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_code_font_size(_code_font_size - 2)
				get_viewport().set_input_as_handled()
				return

	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.echo:
		return
	if key.pressed and key.ctrl_pressed:
		match key.keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_set_code_font_size(_code_font_size + 2)
				get_viewport().set_input_as_handled()
				return
			KEY_MINUS, KEY_KP_SUBTRACT:
				_set_code_font_size(_code_font_size - 2)
				get_viewport().set_input_as_handled()
				return
			KEY_0, KEY_KP_0:
				_set_code_font_size(CODE_FONT_SIZE_DEFAULT)
				get_viewport().set_input_as_handled()
				return
			KEY_V:
				_metrics.record_paste()
				return
	if key.pressed:
		_inactivity_timer = 0.0  # Phase 2: any keystroke resets idle clock
		_metrics.record_key_down(key.physical_keycode)
	else:
		_metrics.record_key_up(key.physical_keycode)

func _set_code_font_size(new_size: int) -> void:
	_code_font_size = clampi(new_size, CODE_FONT_SIZE_MIN, CODE_FONT_SIZE_MAX)
	_code_editor.add_theme_font_size_override("font_size", _code_font_size)

# ---------------------------------------------------------------------------
# Phase 3: Threshold Evaluation — build and send accumulated payload
# ---------------------------------------------------------------------------

func _on_submit_pressed() -> void:
	_attempt_count += 1
	var code := _code_editor.text
	var raw_metrics := _metrics.collect()

	# Compute client-side time since last submit
	var now_ms := float(Time.get_ticks_msec())
	var time_since_last_submit: float
	if _last_submit_ms >= 0.0:
		time_since_last_submit = (now_ms - _last_submit_ms) / 1000.0
	else:
		time_since_last_submit = raw_metrics.get("total_time_seconds", 0.0)
	_last_submit_ms = now_ms

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
			"pasteDetected":       raw_metrics.get("paste_detected",     false),
			"rawEvents":           raw_metrics.get("raw_events", []),
			# ── 4-Phase telemetry fields ──
			"inactivityDuration":  _inactivity_timer,
			"timeSinceLastSubmit": time_since_last_submit,
			"errorLog":            _error_log.duplicate(),
			"isFirstSubmission":   _is_baseline,
		},
	}

	# Phase 1 baseline consumed — all subsequent submissions are Phase 2+
	_is_baseline = false
	# Reset inactivity clock: idle tracking starts fresh after each submit
	_inactivity_timer = 0.0
	_previous_code = code

	_set_output_text("Submitting...")
	_submit_btn.disabled = true
	ApiClient.post_submission(payload)

# ---------------------------------------------------------------------------
# Phase 4: Targeted Intervention — parse response and route dialogue
# ---------------------------------------------------------------------------

func _on_submission_completed(data: Dictionary) -> void:
	var correct: bool            = data.get("isCorrect", false)
	if not correct:
		_submit_btn.disabled = false

	var diag_msg: String         = data.get("diagnosticMessage", "")
	var diag_category: String    = data.get("diagnosticCategory", "")
	var npc_dialogue: Dictionary = data.get("npcDialogue", {})
	var intervention_type: String = data.get("interventionType", "None")
	var is_mastered: bool        = data.get("isMastered", false)
	var mastery_pct: float       = data.get("masteryProbability", 0.0) * 100.0
	var xp: int                  = data.get("xpAwarded", 0)

	# Line number from first compiler diagnostic (if any)
	var compiler_diags: Array = data.get("compilerDiagnostics", [])
	var line_no: int = compiler_diags[0].get("line", -1) if not compiler_diags.is_empty() else -1
	var loc := "  (line %d)" % line_no if line_no > 0 else ""

	# ── Correct answer ──
	if correct:
		var out := "Correct!    Mastery: %d%%" % int(mastery_pct)
		if xp > 0:
			out += "\n+%d XP" % xp
		_set_output_text(out)
		if is_mastered:
			await _show_server_dialogue("Odin", "You've mastered this skill. Well done.", "")
		await get_tree().create_timer(3.0).timeout
		_finish_session(true)
		return

	# ── Incorrect answer ──

	# Phase 2: accumulate this error into the log for future intervention evaluation.
	# Skip "None" or empty categories (e.g. starter-code guard hits).
	if not diag_category.is_empty() and diag_category != "None":
		_error_log.append({ "category": diag_category, "message": diag_msg })

	# Always show the diagnostic message in the output panel.
	var msg := diag_msg if not diag_msg.is_empty() else "Incorrect."
	var out := "%s%s" % [msg, loc]
	if xp > 0:
		out += "\n+%d XP" % xp
	_set_output_text(out)

	# Phase 4: route intervention based on server's classification.
	var dialogue_text: String = npc_dialogue.get("dialogueText", "") if not npc_dialogue.is_empty() else ""

	match intervention_type:
		"ScaffoldingHint":
			# Show ODIN dialogue popup, then reset the error accumulation cycle.
			if not dialogue_text.is_empty():
				await _show_server_dialogue("Odin", dialogue_text, "")
			_error_log.clear()  # Intervention delivered — start fresh accumulation

		"Rejection":
			# GamingTheSystem — popup warning, then clear log (not a genuine attempt).
			if not dialogue_text.is_empty():
				await _show_server_dialogue("Odin", dialogue_text, "")
			_error_log.clear()

		"None", "Reward", _:
			# HintWithheld, ActiveThinking, or first-submission baseline.
			# ODIN remains completely silent — productive struggle is preserved.
			# Output panel already updated above; no popup.
			pass

func _on_puzzle_fetched(data: Dictionary) -> void:
	var desc: String = data.get("description", "")
	var code: String = data.get("starterCode", "")
	if not desc.is_empty():
		set_problem_text(desc)
	if not code.is_empty():
		_code_editor.text = _wrap_starter_comments(code)
		_code_editor.set_caret_line(_code_editor.get_line_count() - 1)

# Wraps only comment lines (// ...) in starter code that exceed COMMENT_WRAP_WIDTH.
# Code lines are left exactly as-is to preserve correct indentation and syntax.
func _wrap_starter_comments(code: String) -> String:
	var lines := code.split("\n")
	var result: PackedStringArray = PackedStringArray()
	for raw_line in lines:
		# Detect indent + comment prefix
		var stripped := raw_line.strip_edges(true, false)  # strip leading only
		if stripped.begins_with("//") and raw_line.length() > COMMENT_WRAP_WIDTH:
			var indent := raw_line.substr(0, raw_line.length() - stripped.length())
			var content := stripped.substr(2).strip_edges()  # text after //
			var wrapped_lines := _split_comment(content, indent, COMMENT_WRAP_WIDTH)
			for wl in wrapped_lines:
				result.append(wl)
		else:
			result.append(raw_line)
	return "\n".join(result)

# Word-wraps a comment body into multiple "// " prefixed lines.
func _split_comment(text: String, indent: String, max_width: int) -> Array[String]:
	var prefix := indent + "// "
	var words := text.split(" ")
	var lines: Array[String] = []
	var current := prefix
	for word in words:
		if word.is_empty():
			continue
		if current != prefix and (current + word).length() > max_width:
			lines.append(current.rstrip(" "))
			current = prefix + word + " "
		else:
			current += word + " "
	if current != prefix:
		lines.append(current.rstrip(" "))
	return lines

func _on_session_created(data: Dictionary) -> void:
	_session_id = str(data.get("id", ""))
	_submit_btn.disabled = false
	GameLogger.info("BattleScene: session created id=%s" % _session_id)

func _on_request_failed(tag: String, code: int) -> void:
	match tag:
		"submission":
			_submit_btn.disabled = false
			_set_output_text("Could not reach the server. (HTTP %d)\nYour code was not evaluated." % code)
		"session_start":
			_set_output_text("Could not create session. (HTTP %d)\nSubmitting is disabled." % code)
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

func _set_output_text(text: String) -> void:
	_output_text.text = text
	call_deferred("_adjust_output_font_size")

func _adjust_output_font_size() -> void:
	var scroll := get_node("MarginContainer/ContentSplit/LeftVBox/OutputPanel/OutputMargin/OutputVBox/OutputScroll") as Control
	var available := scroll.size.y
	var width := _output_text.size.x
	if width <= 0 or available <= 0:
		return
	var font = _output_text.get_theme_font("font")
	for f_size in range(24, 7, -1):
		_output_text.add_theme_font_size_override("font_size", f_size)
		var text_size = font.get_multiline_string_size(_output_text.text, HORIZONTAL_ALIGNMENT_LEFT, width, f_size)
		if text_size.y <= available:
			return

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
