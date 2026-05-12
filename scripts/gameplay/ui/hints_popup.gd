extends Panel

signal close_requested
signal request_hint_requested

@onready var _hints_list: VBoxContainer = $PanelContainer/VBoxContainer/ScrollContainer/HintsList
@onready var _request_button: Button = $PanelContainer/VBoxContainer/ButtonRow/RequestButton
@onready var _close_button: Button = $PanelContainer/VBoxContainer/ButtonRow/CloseButton

func _ready() -> void:
	_request_button.pressed.connect(_on_request_pressed)

func _on_request_pressed() -> void:
	request_hint_requested.emit()

func _on_close_pressed() -> void:
	close_requested.emit()
	hide()

func add_hint(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = 2 # AUTOWRAP_WORD
	_hints_list.add_child(label)
	
func clear_hints() -> void:
	for child in _hints_list.get_children():
		child.queue_free()
