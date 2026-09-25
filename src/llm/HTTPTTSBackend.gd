class_name HTTPTTSBackend
extends TTSBackend

## OpenAI-compatible speech client: POST /v1/audio/speech returns WAV bytes; GET /v1/audio/voices is the readiness probe.

signal availability_changed(available: bool)

@export var base_url: String = "http://127.0.0.1:8004"
@export var model: String = "chatterbox"

const PROBE_TIMEOUT_SEC: float = 1.5
const PROBE_INTERVAL_SEC: float = 30.0
const REQUEST_TIMEOUT_SEC: float = 8.0
## Per-frame reading budget: devnen streams its WAV as io.BytesIO lines, ~2000 chunks for a 5 s line.
const DRAIN_BUDGET_USEC := 2000

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
	var target := _target()
	if target.is_empty():
		synthesis_finished.emit(id, false, PackedByteArray(), "server URL '%s' is not http(s)://host[:port]" % base_url)
		return
	var job := {"client": HTTPClient.new(), "body": build_body(text, voice), "path": str(target["path"]) + "/v1/audio/speech",
		"started": Time.get_ticks_msec(), "requested": false, "code": 0, "bytes": PackedByteArray()}
	var err: int = (job["client"] as HTTPClient).connect_to_host(target["host"], target["port"], TLSOptions.client() if target["tls"] else null)
	if err != OK:
		synthesis_finished.emit(id, false, PackedByteArray(), "could not start connecting (error %d)" % err)
		return
	_inflight[id] = job
	set_process(true)


func cancel(id: String) -> void:
	if not _inflight.has(id):
		return
	_finish(id, false, "cancelled")


func cancel_all() -> void:
	for id in _inflight.keys().duplicate():
		cancel(id)


func _process(_delta: float) -> void:
	for id in _inflight.keys().duplicate():
		_step(id)
	if _inflight.is_empty():
		set_process(false)


## One job's frame: connect, send, then read EVERY chunk that has arrived (bounded), not one per frame.
func _step(id: String) -> void:
	var job: Dictionary = _inflight[id]
	var c: HTTPClient = job["client"]
	if Time.get_ticks_msec() - int(job["started"]) > int(REQUEST_TIMEOUT_SEC * 1000.0):
		_finish(id, false, "timed out after %.0fs" % REQUEST_TIMEOUT_SEC)
		return
	c.poll()
	match c.get_status():
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			return
		HTTPClient.STATUS_CONNECTED:
			if not job["requested"]:
				var err: int = c.request(HTTPClient.METHOD_POST, job["path"], PackedStringArray(["Content-Type: application/json"]), job["body"])
				if err != OK:
					_finish(id, false, "request could not be sent (error %d)" % err)
					return
				job["requested"] = true
			elif c.has_response():
				_complete(id, c.get_response_code())
		HTTPClient.STATUS_BODY:
			job["code"] = c.get_response_code()
			var t0 := Time.get_ticks_usec()
			var got: PackedByteArray = job["bytes"]
			var dry := 0
			while c.get_status() == HTTPClient.STATUS_BODY and Time.get_ticks_usec() - t0 < DRAIN_BUDGET_USEC:
				var chunk: PackedByteArray = c.read_response_body_chunk()
				if chunk.is_empty():
					dry += 1
					if dry > 1:
						break
					c.poll()
					continue
				dry = 0
				got.append_array(chunk)
			## A packed array read from a Dictionary is a copy: append to a local, then store it back.
			job["bytes"] = got
			if c.get_status() != HTTPClient.STATUS_BODY:
				_complete(id, int(job["code"]))
		HTTPClient.STATUS_DISCONNECTED:
			if job["requested"] and int(job["code"]) != 0:
				_complete(id, int(job["code"]))
			else:
				_finish(id, false, "disconnected before a response")
		_:
			_finish(id, false, _status_error(c.get_status()))


func _complete(id: String, code: int) -> void:
	var bytes: PackedByteArray = _inflight[id]["bytes"]
	if code < 200 or code >= 300:
		_finish(id, false, "HTTP %d: %s" % [code, bytes.get_string_from_utf8().left(200)])
	else:
		_finish(id, true, "")


func _finish(id: String, ok: bool, error: String) -> void:
	var job: Dictionary = _inflight[id]
	_inflight.erase(id)
	(job["client"] as HTTPClient).close()
	synthesis_finished.emit(id, ok, job["bytes"] if ok else PackedByteArray(), error)


## {host, port, tls, path} from base_url, or {} when it is not http(s)://host[:port][/path].
func _target() -> Dictionary:
	var url := contacts_url()
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var hostport := rest if slash == -1 else rest.substr(0, slash)
	var path := "" if slash == -1 else rest.substr(slash).rstrip("/")
	var host := hostport
	var port := 443 if tls else 80
	var colon := hostport.rfind(":")
	if colon != -1 and hostport.substr(colon + 1).is_valid_int():
		host = hostport.substr(0, colon)
		port = int(hostport.substr(colon + 1))
	if host.is_empty():
		return {}
	return {"host": host, "port": port, "tls": tls, "path": path}


func _status_error(st: int) -> String:
	match st:
		HTTPClient.STATUS_CANT_RESOLVE:
			return "cannot resolve the server's host name"
		HTTPClient.STATUS_CANT_CONNECT:
			return "cannot connect to the server"
		HTTPClient.STATUS_CONNECTION_ERROR:
			return "connection error"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
	return "HTTP client status %d" % st


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
