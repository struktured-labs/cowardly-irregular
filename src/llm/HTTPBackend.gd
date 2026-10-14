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
##   default_timeout_sec — applied to every HTTPRequest. 0 does NOT mean unbounded:
##                        HTTPBackend's own `submit` floors it at 30s (Wave F B15), so a
##                        hung server cannot leak HTTPRequest nodes for a whole session.
##                        (`submit` is declared in three backends — the qualifier is
##                        load-bearing, not habit.)
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

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted whenever reachability changes (and once when the boot probe resolves).
signal availability_changed(available: bool)

## Emitted once per list_models() call; models is empty when ok is false.
signal models_listed(ok: bool, models: PackedStringArray, err: String)


# ── Internal state ────────────────────────────────────────────────────────────
# Maps request_id → HTTPRequest node.
var _inflight: Dictionary = {}

# Last known reachability. Refreshed on an interval — never cached for the session.
var _ready_flag: bool = false

# Probe HTTPRequest reference (kept alive until probe completes).
var _probe_request: HTTPRequest = null

# Separate from _probe_request: a model listing must never cancel a reachability probe.
var _list_request: HTTPRequest = null

# Engine-msec stamp of the last RESOLVED probe; drives the re-probe interval.
var _last_probe_msec: int = 0

# The models the last probe's own response listed. The probe GETs the listing endpoint and used
# to discard the body, so this costs no extra request. Empty means "not known", never "none".
var _server_models: PackedStringArray = []

# HTTP status of the last resolved probe, 0 if it never reached a server. A 401/403
# means the endpoint ANSWERED and refused the credential, which is a different repair
# from "unreachable" - and telling the player to wait for a retry that cannot succeed
# is the worse of the two wrong answers.
var _last_probe_code: int = 0

# False until the boot probe resolves, so boot isn't reported as a transition.
var _first_probe_done: bool = false


# ── Configuration: probe ──────────────────────────────────────────────────────
## Per-API endpoints used to detect a live server.
##   ollama → GET /api/tags        (lists installed models)
##   openai → GET /v1/models       (lists available models)
##   any    → HEAD on base_url     (generic fallback)
const PROBE_TIMEOUT_SEC: float = 1.5

## How stale a probe result may get before is_ready() kicks off a fresh one.
const PROBE_INTERVAL_SEC: float = 30.0


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Wave C: start as NOT ready. Spawn an async probe; on a 2xx response we
	# flip _ready_flag to true. Until the probe finishes, is_ready() returns
	# false so LLMService routes calls through fallbacks. This eliminates
	# the stale-true race where every dynamic NPC freezes for 30s during
	# the first request to a missing server.
	_ready_flag = false
	_start_probe()


func _start_probe() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		return
	_probe_request = HTTPRequest.new()
	_probe_request.name = "Probe"
	_probe_request.timeout = PROBE_TIMEOUT_SEC
	add_child(_probe_request)
	_probe_request.request_completed.connect(_on_probe_completed)

	var url: String = _probe_url()
	var method: int = _probe_method()
	# Bound to a local rather than called inline: test_the_byok_log_never_carries_the_key
	# treats a local assigned from a key-carrying function as an alias of that container, so
	# `var err = request(url, probe_headers(), ...)` made the INT err an alias and the warning
	# below, which interpolates err, read as a credential leak. Naming the container is also
	# clearer about what crosses the wire.
	var auth: PackedStringArray = probe_headers()
	var err: int = _probe_request.request(url, auth, method, "")
	if err != OK:
		# The request never started (malformed or empty base_url, bad host), so
		# _on_probe_completed will NEVER fire. Leaving _first_probe_done false
		# made _maybe_refresh_probe's `not _first_probe_done` guard return early
		# FOREVER: the backend stayed unavailable for the whole session, silently,
		# recoverable only by re-applying the config — which is exactly the
		# "I had to enable/re-enable LLM for it to trigger" struktured reported
		# on 2026-09-07. Mark the attempt CONCLUDED so the retry path is armed and
		# the 30s re-probe the warning below promises actually happens.
		if not _first_probe_done:
			push_warning("[HTTPBackend] probe could not start for %s (error %d) — check base_url. Retrying every %ds; no restart needed once it is valid." % [url, err, int(PROBE_INTERVAL_SEC)])
		_first_probe_done = true
		_last_probe_msec = Time.get_ticks_msec()
		# Never reached a server, so no status survives from the previous endpoint.
		_last_probe_code = 0
		_cleanup_probe()


func _probe_url() -> String:
	match api_format:
		"ollama":
			return _base() + "/api/tags"
		"openai", _:
			return _base() + "/v1/models"


func _probe_method() -> int:
	# Both formats probe with GET; an unknown one follows OpenAI like every other site.
	return HTTPClient.METHOD_GET


## The probe GETs the provider's MODEL-LISTING endpoint, which every paid provider
## authenticates: measured unauthenticated 2026-10-12, api.openai.com / api.groq.com /
## api.deepseek.com / api.together.xyz all answer 401 (OpenRouter's list is public).
## It sent no headers until now, so a VALID key read as "server unreachable" for the
## whole session while the BYOK panel's Test Connection - which does send the key - said OK.
## No Content-Type: a GET carries no body, and an empty array keeps local Ollama, which
## authenticates nothing, byte-for-byte as it was.
func probe_headers() -> PackedStringArray:
	var headers: PackedStringArray = []
	if api_key != "":
		headers.append("Authorization: Bearer " + api_key)
	return headers


## The models the SERVER reports. The reachability probe already GETs this exact endpoint and
## discards the body; parsing it is the difference between a player guessing a model name and
## picking one they actually have. Shapes follow _probe_url's own branching, so the two agree.
static func parse_model_list(api_format: String, raw: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var is_ollama: bool = api_format == "ollama"
	var rows: Variant = (parsed as Dictionary).get("models" if is_ollama else "data", [])
	if typeof(rows) != TYPE_ARRAY:
		return out
	var field: String = "name" if is_ollama else "id"
	for r in (rows as Array):
		if typeof(r) != TYPE_DICTIONARY:
			continue
		var id: String = str((r as Dictionary).get(field, "")).strip_edges()
		if id != "" and not out.has(id):
			out.append(id)
	return out


## Whether the configured model is one the server listed. UNKNOWN (true) when the listing was
## empty or unparsed: absence of evidence must not read as evidence of absence, because a provider
## may serve a model its /v1/models does not enumerate for this key.
func model_is_on_server() -> bool:
	if _server_models.is_empty() or model == "":
		return true
	return model in _server_models


## Ask the server what it has. Answers exactly once through models_listed.
func list_models() -> void:
	if _list_request != null and is_instance_valid(_list_request):
		models_listed.emit(false, PackedStringArray(), "a model listing is already in flight")
		return
	_list_request = HTTPRequest.new()
	_list_request.name = "ModelList"
	_list_request.timeout = PROBE_TIMEOUT_SEC
	add_child(_list_request)
	_list_request.request_completed.connect(_on_list_completed)
	# Bound to a local like _start_probe's: a local assigned from a key-carrying call registers as
	# an alias of that container, and every warning interpolating it then reads as a key leak.
	var auth: PackedStringArray = probe_headers()
	var err: int = _list_request.request(_probe_url(), auth, HTTPClient.METHOD_GET, "")
	if err != OK:
		# The request never started, so _on_list_completed will never fire; answer anyway.
		_cleanup_list()
		models_listed.emit(false, PackedStringArray(), "could not reach %s (error %d)" % [_probe_url(), err])


func _on_list_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_cleanup_list()
	if result != HTTPRequest.RESULT_SUCCESS:
		models_listed.emit(false, PackedStringArray(), "%s did not answer" % _probe_url())
		return
	if response_code < 200 or response_code >= 300:
		# Reuses the probe's own vocabulary so one HTTP status reads the same on both surfaces.
		_last_probe_code = response_code
		models_listed.emit(false, PackedStringArray(), unavailable_reason())
		return
	var models: PackedStringArray = parse_model_list(api_format, body.get_string_from_utf8())
	if models.is_empty():
		models_listed.emit(false, models, "%s listed no models" % _probe_url())
		return
	models_listed.emit(true, models, "")


func _cleanup_list() -> void:
	if _list_request != null and is_instance_valid(_list_request):
		if _list_request.request_completed.is_connected(_on_list_completed):
			_list_request.request_completed.disconnect(_on_list_completed)
		_list_request.queue_free()
	_list_request = null


func _on_probe_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var now_ready: bool = result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	var was_ready: bool = _ready_flag
	_ready_flag = now_ready
	_last_probe_msec = Time.get_ticks_msec()
	_last_probe_code = response_code if result == HTTPRequest.RESULT_SUCCESS else 0
	_server_models = parse_model_list(api_format, body.get_string_from_utf8()) if now_ready else PackedStringArray()
	_cleanup_probe()
	# Boot resolution isn't a "transition" — announce state, but only warn if unreachable.
	if not _first_probe_done:
		_first_probe_done = true
		if not now_ready:
			push_warning("[HTTPBackend] %s" % unavailable_reason())
		availability_changed.emit(now_ready)
		return
	if was_ready == now_ready:
		return
	# Silent-failure guard (struktured 2026-07-25): the state must never change unannounced.
	var consequence: String = dialogue_consequence(now_ready, dialogue_enabled())
	if now_ready:
		print("[HTTPBackend] LLM server reachable again at %s. %s" % [_probe_url(), consequence])
	else:
		push_warning("[HTTPBackend] %s %s" % [unavailable_reason(), consequence])
	availability_changed.emit(now_ready)


## The kind each probe status means, as DATA so a guard can read the set through this class
## instead of parsing the source for it. 0 is "no server answered", not a status.
const KIND_FOR_CODE := {
	0: "unreachable",
	401: "key_rejected",
	403: "key_rejected",
	404: "not_found",
	429: "rate_limited",
}

## Any status the table does not name. A reachable backend reports "" instead.
const KIND_FALLBACK := "http_error"


## WHAT KIND of unavailable, as one token. The log wants a paragraph and a Settings subtitle has
## about eighty columns, so the two surfaces must not share a STRING — they share this FACT and
## each phrases it. Pinning the code->kind table pins both without pinning either one's prose.
func unavailable_kind() -> String:
	# Guarded HERE rather than at the readout: no caller can be handed a kind for a healthy 200.
	if _ready_flag:
		return ""
	return str(KIND_FOR_CODE.get(_last_probe_code, KIND_FALLBACK))


## Why the backend is unavailable, for the log. The credential case is split out because
## "retrying every 30s" is a promise a 401 can never keep: no amount of waiting fixes a
## rejected key, and the player has to go edit it.
func unavailable_reason() -> String:
	var every: int = int(PROBE_INTERVAL_SEC)
	match unavailable_kind():
		"key_rejected":
			return "%s rejected the API key (HTTP %d) - the server IS reachable, so re-check the key in Configure BYOK. Retrying cannot fix this one." % [_probe_url(), _last_probe_code]
		"not_found":
			return "%s answered HTTP 404 - the host is reachable but lists no models at that path, so check the Base URL against your provider's docs." % _probe_url()
		"rate_limited":
			return "%s answered HTTP 429 (rate limited) - re-probing every %ds; this one does clear on its own." % [_probe_url(), every]
		"http_error":
			return "LLM server at %s answered HTTP %d - dynamic dialogue will use fallbacks. Re-probing every %ds." % [_probe_url(), _last_probe_code, every]
		_:
			return "LLM server unreachable at %s - dynamic dialogue will use fallbacks. Re-probing every %ds; no restart needed once it's up." % [_probe_url(), every]


## The player-facing consequence of a reachability change; the toggle is LLMService's, not ours.
static func dialogue_consequence(now_ready: bool, dialogue_on: bool) -> String:
	if not dialogue_on:
		return "Dynamic dialogue stays off — the Settings toggle is off."
	if now_ready:
		return "Dynamic dialogue restored."
	return "Falling back to scripted dialogue."


## Read the Dynamic Dialogue toggle off the service, the way RuleComposer does.
func dialogue_enabled() -> bool:
	var svc: Node = get_node_or_null("/root/LLMService")
	return svc != null and "llm_enabled" in svc and bool(svc.llm_enabled)


func _cleanup_probe() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		# queue_free is deferred; disconnect so a late reply cannot report on a new endpoint.
		if _probe_request.request_completed.is_connected(_on_probe_completed):
			_probe_request.request_completed.disconnect(_on_probe_completed)
		_probe_request.queue_free()
	_probe_request = null


# ── LLMBackend overrides ──────────────────────────────────────────────────────

func backend_id() -> String:
	return "http"


## Last known reachability. Also kicks off an async re-probe when the result is stale,
## so a server that comes up AFTER boot heals the backend instead of staying dead
## for the whole session (struktured 2026-07-25: "dynamic quips disabled" with a
## perfectly healthy Ollama — the boot-time miss had been cached permanently).
func is_ready() -> bool:
	_maybe_refresh_probe()
	return _ready_flag


## Kick off a re-probe if the last result has gone stale. Async — heals the NEXT call.
func _maybe_refresh_probe() -> void:
	if not _first_probe_done:
		return
	if _probe_request != null and is_instance_valid(_probe_request):
		return
	if Time.get_ticks_msec() - _last_probe_msec < int(PROBE_INTERVAL_SEC * 1000.0):
		return
	_start_probe()


## The endpoint CHANGED: drop the cached verdict and any in-flight probe aimed at
## the old one, and probe the new one now. Zeroing _ready_flag alone left
## _last_probe_msec stale, so _maybe_refresh_probe blocked the revival probe for
## up to PROBE_INTERVAL_SEC and every LLM call fell back meanwhile.
func invalidate_and_reprobe() -> void:
	_ready_flag = false
	_first_probe_done = false
	_cleanup_probe()
	_start_probe()


## Force an immediate re-probe regardless of interval (Settings "test connection").
func refresh_availability() -> void:
	if _probe_request != null and is_instance_valid(_probe_request):
		return
	_start_probe()


## Observability surface for the Settings LLM panel — no internals reach required.
func get_availability_info() -> Dictionary:
	return {
		"available": _ready_flag,
		"probe_url": _probe_url(),
		"model": model,
		"probed": _first_probe_done,
		"probe_code": _last_probe_code,
		"model_present": model_is_on_server(),
		"server_model_count": _server_models.size(),
		"kind": unavailable_kind(),
		"seconds_since_probe": (Time.get_ticks_msec() - _last_probe_msec) / 1000.0 if _first_probe_done else -1.0,
		"probe_interval_sec": PROBE_INTERVAL_SEC,
	}


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
	# Wave F B15 fix — never let a request run unbounded. Even when
	# default_timeout_sec is 0 (legacy "no timeout") we set a hard 30s cap
	# so a hung server can't leak HTTPRequest nodes forever during a long
	# play session. Tests that need a short timeout pass opts.timeout_sec.
	var effective_timeout: float = float(opts.get("timeout_sec", default_timeout_sec))
	if effective_timeout <= 0.0:
		effective_timeout = 30.0
	http.timeout = effective_timeout
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

## Every provider's docs call "https://host/v1" the base URL, and we append the
## version ourselves — so accept both spellings rather than 404 on the common one.
func _base() -> String:
	var b: String = base_url.rstrip("/")
	if b.ends_with("/v1"):
		b = b.substr(0, b.length() - 3)
	return b.rstrip("/")


func _endpoint_url(json_mode: bool) -> String:
	match api_format:
		"ollama":
			return _base() + "/api/generate"
		"openai":
			return _base() + "/v1/chat/completions"
		_:
			push_warning("[HTTPBackend] Unknown api_format '%s'; using OpenAI-compatible requests." % api_format)
			return _base() + "/v1/chat/completions"


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
