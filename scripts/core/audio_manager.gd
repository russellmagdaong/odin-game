extends Node
# Autoload: AudioManager

const _MUSIC: Dictionary = {
	"indoor":   "res://assets/audio/music/indoor.ogg",
	"outdoors": "res://assets/audio/music/outdoors.ogg",
	"mainmenu": "res://assets/audio/music/mainmenu.ogg",
	"battle":   "res://assets/audio/music/battle.ogg",
}

const _SFX: Dictionary = {
	"buttonclick": "res://assets/audio/sfx/buttonclick.mp3",
}

const _OUTDOOR_LEVELS: Array = ["Level11", "Level12"]

var _music_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _current_music: String = ""

func _ready() -> void:
	_ensure_buses()

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music_player)

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	_sfx_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sfx_player)

	get_tree().node_added.connect(_on_node_added)
	call_deferred("_scan_existing_buttons", get_tree().root)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)

func _connect_button(button: BaseButton) -> void:
	if button.has_meta("_sfx_connected"):
		return
	button.set_meta("_sfx_connected", true)
	button.pressed.connect(func(): play_sfx("buttonclick"))

func _scan_existing_buttons(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)
	for child in node.get_children():
		_scan_existing_buttons(child)

func play_music(track: String) -> void:
	if _current_music == track and _music_player.playing:
		return
	_current_music = track
	var stream: AudioStream = load(_MUSIC[track])
	stream.set("loop", true)
	_music_player.stream = stream
	_music_player.play()

func play_music_for_level(level_name: String) -> void:
	if level_name.is_empty():
		return
	if level_name in _OUTDOOR_LEVELS:
		play_music("outdoors")
	else:
		play_music("indoor")

func stop_music() -> void:
	_current_music = ""
	_music_player.stop()

func play_sfx(sfx: String) -> void:
	_sfx_player.stream = load(_SFX[sfx])
	_sfx_player.play()

func _ensure_buses() -> void:
	if AudioServer.get_bus_index("Music") < 0:
		var idx := AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_volume_db(idx, linear_to_db(0.5))
	if AudioServer.get_bus_index("SFX") < 0:
		var idx := AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_volume_db(idx, linear_to_db(0.5))
