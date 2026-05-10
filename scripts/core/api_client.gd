extends Node
# Autoload: ApiClient
#
# All communication with the ODIN backend goes through here.
# Set base_url before the game starts, or inject it from the web page (see _get_base_url).
#
# Request flow:  caller → _enqueue() → _flush() → HTTPRequest → _on_request_completed()
# Requests are processed one at a time; extras wait in _queue.

signal submission_completed(data: Dictionary)
signal session_created(data: Dictionary)
signal request_failed(tag: String, http_code: int)
signal puzzle_fetched(data: Dictionary)

var base_url: String = ""

var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _busy: bool = false
var _current_tag: String = ""
var _jwt_token: String = ""

func _ready() -> void:
	base_url = _get_base_url()
	PlayerDataManager.user_id = _get_user_id()
	_jwt_token = _get_jwt_token()

	_http = HTTPRequest.new()
	_http.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	GameLogger.info("ApiClient ready — base_url: %s  user_id: %s  auth: %s" % [
		base_url,
		PlayerDataManager.user_id,
		"token present" if not _jwt_token.is_empty() else "no token (local dev)",
	])

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func post_submission(payload: Dictionary) -> void:
	_enqueue(HTTPClient.METHOD_POST, "/api/submission", payload, "submission")

func post_session_start(payload: Dictionary) -> void:
	_enqueue(HTTPClient.METHOD_POST, "/api/session", payload, "session_start")

func patch_session_end(session_id: String) -> void:
	_enqueue(HTTPClient.METHOD_PATCH, "/api/session/" + session_id + "/end", {}, "session_end")

func get_puzzle(puzzle_id: String) -> void:
	_enqueue(HTTPClient.METHOD_GET, "/api/puzzle/" + puzzle_id, {}, "puzzle_fetch")

# ---------------------------------------------------------------------------
# Internal queue
# ---------------------------------------------------------------------------

func _enqueue(method: int, endpoint: String, payload: Dictionary, tag: String) -> void:
	_queue.append({"method": method, "endpoint": endpoint, "payload": payload, "tag": tag})
	if not _busy:
		_flush()

func _flush() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var req: Dictionary = _queue.pop_front()
	_current_tag = req.tag

	var body := "" if req.method == HTTPClient.METHOD_GET else JSON.stringify(req.payload)
	var headers: PackedStringArray = ["Content-Type: application/json", "Accept: application/json"]
	if not _jwt_token.is_empty():
		headers.append("Authorization: Bearer " + _jwt_token)
	var err := _http.request(base_url + req.endpoint, headers, req.method, body)
	if err != OK:
		GameLogger.error("ApiClient: request error %d for [%s] %s" % [err, req.tag, req.endpoint])
		request_failed.emit(_current_tag, err)
		_busy = false
		_flush()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var tag := _current_tag
	_current_tag = ""
	_busy = false

	if result != HTTPRequest.RESULT_SUCCESS:
		GameLogger.error("ApiClient: HTTP result=%d code=%d tag=%s" % [result, response_code, tag])
		request_failed.emit(tag, response_code)
		_flush()
		return

	var text := body.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(text) != OK:
		GameLogger.error("ApiClient: JSON parse failed for tag=%s — body: %s" % [tag, text])
		request_failed.emit(tag, response_code)
		_flush()
		return

	var data: Dictionary = json.data if json.data is Dictionary else {}
	GameLogger.info("ApiClient: response tag=%s code=%d" % [tag, response_code])

	match tag:
		"submission":
			submission_completed.emit(data)
		"session_start":
			session_created.emit(data)
		"puzzle_fetch":
			puzzle_fetched.emit(data)

	_flush()

# ---------------------------------------------------------------------------
# URL / credential resolution
# ---------------------------------------------------------------------------

# In web builds, the HTML page injects the server URL:
#   <script>window.ODIN_API_URL = "https://api.yourserver.com";</script>
func _get_base_url() -> String:
	if OS.has_feature("web"):
		var js_url = JavaScriptBridge.eval("(window.parent.__ODIN_GAME_CONFIG?.apiUrl) || window.ODIN_API_URL || ''")
		if typeof(js_url) == TYPE_STRING and not (js_url as String).is_empty():
			return js_url
	return "http://localhost:5000"

func _get_user_id() -> String:
	if OS.has_feature("web"):
		var js_id = JavaScriptBridge.eval("(window.parent.__ODIN_GAME_CONFIG?.userId) || window.ODIN_USER_ID || ''")
		if typeof(js_id) == TYPE_STRING and not (js_id as String).is_empty():
			return js_id
	return "local_dev"

func _get_jwt_token() -> String:
	if OS.has_feature("web"):
		var js_token = JavaScriptBridge.eval("(window.parent.__ODIN_GAME_CONFIG?.token) || window.ODIN_JWT_TOKEN || ''")
		if typeof(js_token) == TYPE_STRING and not (js_token as String).is_empty():
			return js_token
	return ""
