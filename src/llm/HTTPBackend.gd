## HTTPBackend — async LLM backend over HTTP.
##
## Supports two wire formats:
##   - Ollama  : POST /api/generate   (detected by api_format = "ollama")
##   - OpenAI  : POST /v1/chat/completions  (api_format = "openai")
##
## Each in-flight request spawns its own child HTTPRequest node (the canonical
## Godot async idiom — never blocks the main thread).  Nodes are freed once the
## response is received or the request is cancelled.
##
## Configuration (set before _ready or updated at runtime):
##   base_url     — e.g. "http://localhost:11434"  (Ollama default)
##   api_format   — "ollama" | "openai"
##   model        — model name string passed to the API
##   api_key      — Authorization bearer token (empty = omit header)
##   default_timeout_sec — applied to every HTTPRequest; 0 = HTTPRequest default
##
## Threading invariant: all methods run on the main thread.  HTTPRequest nodes
## use Godot's built-in async HTTP — no Thread or WorkerThreadPool required.

class_name HTTPBackend
extends LLMBackend

# ── Configuration ─────────────────────────────────────────────────────────────
@export var base_url: String = "http://localhost:11434"
@export var api_format: String = "ollama"   # "ollama" | "openai"
@export var model: String = "llama3"
@export var api_key: String = ""
@export var default_timeout_sec: float = 30.0

# ── Internal state ────────────────────────────────────────────────────────────
# Maps request_id → HTTPRequest node.
var _inflight: Dictionary = {}

# Whether a connection has been confirmed at _ready (set by _probe).
var _ready_flag: bool = false


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# We don't block on a probe; readiness is assumed once the node is in-tree.
	# Callers observe is_ready() after construction; a real probe would require
	# an async ping, which is out of scope for Phase 1.
	_ready_flag = true


# ── LLMBackend overrides ──────────────────────────────────────────────────────

func backend_id() -> String:
	return "http"


func is_ready() -> bool:
	return _ready_flag


func supports_json() -> bool:
	# Both Ollama and OpenAI-compat APIs support JSON-mode requests.
	return true


func supports_grammar() -> bool:
	return false


## Submit an inference request.
## Spawns a child HTTPRequest node; emits request_finished on completion.
func submit(id: String, prompt: String, opts: Dictionary = {}) -> void:
	if _inflight.has(id):
		push_warning("[HTTPBackend] Duplicate request id '%s' — ignoring." % id)
		return

	var http := HTTPRequest.new()
	http.name = "Req_" + id
	if default_timeout_sec > 0.0:
		http.timeout = opts.get("timeout_sec", default_timeout_sec)
	add_child(http)
	_inflight[id] = http

	var body: String = _build_body(prompt, opts)
	var headers: PackedStringArray = _build_headers()
	var url: String = _endpoint_url(opts.get("json_mode", false))

	var err: int = http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_cleanup(id)
		request_finished.emit(id, false, "", "HTTPRequest.request() error %d" % err)
		return

	# Capture id in the lambda via a local variable — GDScript closures capture
	# by reference, so we bind `_id` separately to avoid id being stale.
	var _id := id
	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			_on_request_completed(_id, result, response_code, body_bytes)
	)


func cancel(id: String) -> void:
	if not _inflight.has(id):
		return
	var http: HTTPRequest = _inflight[id]
	http.cancel_request()
	_cleanup(id)
	request_finished.emit(id, false, "", "cancelled")


func cancel_all() -> void:
	for id in _inflight.keys().duplicate():
		cancel(id)


# ── Internal helpers ──────────────────────────────────────────────────────────

func _endpoint_url(json_mode: bool) -> String:
	match api_format:
		"ollama":
			return base_url.rstrip("/") + "/api/generate"
		"openai":
			return base_url.rstrip("/") + "/v1/chat/completions"
		_:
			push_warning("[HTTPBackend] Unknown api_format '%s'; defaulting to Ollama." % api_format)
			return base_url.rstrip("/") + "/api/generate"


func _build_headers() -> PackedStringArray:
	var headers: PackedStringArray = ["Content-Type: application/json"]
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	return headers


func _build_body(prompt: String, opts: Dictionary) -> String:
	var max_tokens: int = opts.get("max_tokens", 512)
	var temperature: float = opts.get("temperature", 0.7)
	var json_mode: bool = opts.get("json_mode", false)

	var payload: Dictionary
	match api_format:
		"ollama":
			payload = {
				"model":  model,
				"prompt": prompt,
				"stream": false,
				"options": {
					"num_predict": max_tokens,
					"temperature": temperature,
				},
			}
			if json_mode:
				payload["format"] = "json"
		"openai", _:
			payload = {
				"model": model,
				"messages": [{"role": "user", "content": prompt}],
				"max_tokens": max_tokens,
				"temperature": temperature,
			}
			if json_mode:
				payload["response_format"] = {"type": "json_object"}

	return JSON.stringify(payload)


func _extract_text(response_code: int, body_bytes: PackedByteArray) -> Array:
	# Returns [ok: bool, text: String, error: String]
	if response_code < 200 or response_code >= 300:
		return [false, "", "HTTP %d" % response_code]

	var raw: String = body_bytes.get_string_from_utf8()
	if raw.is_empty():
		return [false, "", "empty response body"]

	var parsed = JSON.parse_string(raw)
	if parsed == null:
		return [false, "", "JSON parse failure"]

	if not (parsed is Dictionary):
		return [false, "", "unexpected JSON root type"]

	var text: String = ""
	match api_format:
		"ollama":
			# { "response": "..." }
			if parsed.has("response"):
				text = str(parsed["response"])
			else:
				return [false, "", "Ollama response missing 'response' key"]
		"openai", _:
			# { "choices": [{ "message": { "content": "..." } }] }
			var choices = parsed.get("choices", [])
			if choices is Array and choices.size() > 0:
				var first = choices[0]
				if first is Dictionary:
					var msg = first.get("message", {})
					if msg is Dictionary:
						text = str(msg.get("content", ""))
			if text.is_empty():
				return [false, "", "OpenAI response missing choices[0].message.content"]

	return [true, text, ""]


func _on_request_completed(id: String, result: int, response_code: int, body_bytes: PackedByteArray) -> void:
	_cleanup(id)

	if result != HTTPRequest.RESULT_SUCCESS:
		var err_msg: String = _result_to_error(result)
		request_finished.emit(id, false, "", err_msg)
		return

	var extracted: Array = _extract_text(response_code, body_bytes)
	var ok: bool = extracted[0]
	var text: String = extracted[1]
	var error: String = extracted[2]
	request_finished.emit(id, ok, text, error)


func _cleanup(id: String) -> void:
	if _inflight.has(id):
		var http: HTTPRequest = _inflight[id]
		_inflight.erase(id)
		if is_instance_valid(http):
			http.queue_free()


func _result_to_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "chunked body size mismatch"
		HTTPRequest.RESULT_CANT_CONNECT:
			return "cannot connect to server"
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "cannot resolve hostname"
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "connection error"
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS handshake error"
		HTTPRequest.RESULT_NO_RESPONSE:
			return "no response"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "body size limit exceeded"
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "request failed"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "download file cannot be opened"
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "download file write error"
		HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			return "redirect limit reached"
		HTTPRequest.RESULT_TIMEOUT:
			return "request timed out"
		_:
			return "unknown HTTPRequest error %d" % result
