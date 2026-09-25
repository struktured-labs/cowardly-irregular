class_name HTTPTTSBackend
extends TTSBackend

## OpenAI-compatible speech client: POST /v1/audio/speech returns WAV bytes; GET /v1/audio/voices is the readiness probe.

signal availability_changed(available: bool)

@export var base_url: String = "http://127.0.0.1:8004"
@export var model: String = "chatterbox"

const PROBE_TIMEOUT_SEC: float = 1.5
const PROBE_INTERVAL_SEC: float = 30.0
const REQUEST_TIMEOUT_SEC: float = 8.0

var _inflight: Dictionary = {}
var _ready_flag: bool = false
var _probe_request: HTTPRequest = null
var _last_probe_msec: int = 0
var _first_probe_done: bool = false
var _voices: Array[String] = []


func _ready() -> void:
	_start_probe()


func backend_id() -> String:
	return "http"


func is_ready() -> bool:
	_maybe_refresh_probe()
	return _ready_flag


func contacts_url() -> String:
	var b: String = base_url.strip_edges().rstrip("/")
	if b.ends_with("/v1"):
		b = b.substr(0, b.length() - 3)
	return b.rstrip("/")


func server_voices() -> Array[String]:
	return _voices.duplicate()


func status() -> Dictionary:
	return {"backend": backend_id(), "ready": _ready_flag, "url": contacts_url(), "probed": _first_probe_done}


func build_body(text: String, voice: String) -> String:
	return JSON.stringify({"model": model, "input": text, "voice": voice, "response_format": "wav"})


func synthesize(id: String, text: String, voice: String) -> void:
	if _inflight.has(id):
		push_warning("[HTTPTTSBackend] duplicate request id '%s' ignored" % id)
		return
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SEC
	add_child(http)
	_inflight[id] = http
	var err: int = http.request(contacts_url() + "/v1/audio/speech", PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, build_body(text, voice))
	if err != OK:
		_cleanup(id)
		synthesis_finished.emit(id, false, PackedByteArray(), "request could not start (error %d)" % err)
		return
	var _id := id
	http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void: _on_completed(_id, result, code, body))


func cancel(id: String) -> void:
	if not _inflight.has(id):
		return
	(_inflight[id] as HTTPRequest).cancel_request()
	_cleanup(id)
	synthesis_finished.emit(id, false, PackedByteArray(), "cancelled")


func cancel_all() -> void:
	for id in _inflight.keys().duplicate():
		cancel(id)


## Voice names from {"status":"ok","voices":[...]} (devnen 915ae28) or a list of {"filename":...}.
static func parse_voices(body: String) -> Array[String]:
	var out: Array[String] = []
	var parsed: Variant = JSON.parse_string(body)
	var list: Variant = (parsed as Dictionary).get("voices", []) if parsed is Dictionary else parsed
	if not (list is Array):
		return out
	for v in list:
		if v is String:
			out.append(v)
		elif v is Dictionary and (v as Dictionary).has("filename"):
			out.append(str(v["filename"]))
	return out


func _on_completed(id: String, result: int, code: int, body: PackedByteArray) -> void:
	if not _inflight.has(id):
		return
	_cleanup(id)
	if result != HTTPRequest.RESULT_SUCCESS:
		synthesis_finished.emit(id, false, PackedByteArray(), "request failed (HTTPRequest result %d)" % result)
		return
	if code < 200 or code >= 300:
		synthesis_finished.emit(id, false, PackedByteArray(), "HTTP %d: %s" % [code, body.get_string_from_utf8().left(200)])
		return
	synthesis_finished.emit(id, true, body, "")


func _cleanup(id: String) -> void:
	var http: Variant = _inflight.get(id)
	_inflight.erase(id)
	if http != null and is_instance_valid(http):
		(http as HTTPRequest).queue_free()


func _start_probe() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		return
	_probe_request = HTTPRequest.new()
	_probe_request.timeout = PROBE_TIMEOUT_SEC
	add_child(_probe_request)
	_probe_request.request_completed.connect(_on_probe_completed)
	if _probe_request.request(contacts_url() + "/v1/audio/voices") != OK:
		_first_probe_done = true
		_last_probe_msec = Time.get_ticks_msec()
		_cleanup_probe()


func _maybe_refresh_probe() -> void:
	if not _first_probe_done or (_probe_request != null and is_instance_valid(_probe_request)):
		return
	if Time.get_ticks_msec() - _last_probe_msec >= int(PROBE_INTERVAL_SEC * 1000.0):
		_start_probe()


func _on_probe_completed(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	var now_ready: bool = result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if now_ready:
		_voices = parse_voices(body.get_string_from_utf8())
	var changed: bool = now_ready != _ready_flag or not _first_probe_done
	_ready_flag = now_ready
	_first_probe_done = true
	_last_probe_msec = Time.get_ticks_msec()
	_cleanup_probe()
	if changed:
		availability_changed.emit(now_ready)


func _cleanup_probe() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		if _probe_request.request_completed.is_connected(_on_probe_completed):
			_probe_request.request_completed.disconnect(_on_probe_completed)
		_probe_request.queue_free()
	_probe_request = null
