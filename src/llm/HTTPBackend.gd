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

# "base_url|model" -> {format: true} for every JSON format that server refused; a JSON request steps down past them.
var _json_refused: Dictionary = {}

# "base_url|model" -> {param: true} for each sampling param that server 400'd by name ("max_tokens", "temperature").
var _param_refused: Dictionary = {}

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

## The URL is player-set, so no reply is read unbounded. A 512-token completion is tens of KB.
const MAX_REPLY_BYTES := 1024 * 1024
## The probe and the model list read the listing endpoint; a hosted catalogue runs to a few MB.
const MAX_LISTING_BYTES := 8 * 1024 * 1024
## A server's error message is its own text on the player's screen and in the log, so it is cut to a line.
const MAX_REASON_CHARS := 100
## A run of this many characters shared with the key is a piece of it.
const KEY_PIECE_CHARS := 6
## Stands in for the kept model id while the shapes are struck; a control character no pattern matches.
const KEPT_MARK := "\u0001"
## What a credential looks like in server text, whoever's it is: a Bearer value, a masked token, a vendor prefix, a long opaque run.
const CREDENTIAL_SHAPES: Array[String] = [
	"(?i)bearer\\s+\\S+",
	"[A-Za-z0-9_\\-]*\\*{2,}[A-Za-z0-9_\\-*]*",
	"[A-Za-z0-9_\\-]{3,}(\\.{3,}|\u2026)[A-Za-z0-9_\\-]{3,}",
	"\\b(sk|pk|rk|gsk|xai|hf|key)[-_][A-Za-z0-9_\\-]{8,}",
	"[A-Za-z0-9_\\-]{20,}",
]
var max_reply_bytes: int = MAX_REPLY_BYTES
var max_listing_bytes: int = MAX_LISTING_BYTES


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
	_probe_request.body_size_limit = max_listing_bytes
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
	_list_request.body_size_limit = max_listing_bytes
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
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		models_listed.emit(false, PackedStringArray(), "%s sent a model list over the %d-byte cap" % [_probe_url(), max_listing_bytes])
		return
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
	# Through the SceneTree root, not "/root/…": an off-tree backend's absolute lookup logs an engine error and finds nothing.
	var tree := Engine.get_main_loop() as SceneTree
	var svc: Node = tree.root.get_node_or_null("LLMService") if tree != null and tree.root != null else null
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
	http.body_size_limit = max_reply_bytes
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
	var carried: String = _json_format(opts)
	http.request_completed.connect(
		func(result: int, response_code: int, _headers: PackedStringArray, body_bytes: PackedByteArray) -> void:
			if carried != "" and _retry_without(carried, _id, prompt, opts, result, response_code, body_bytes):
				return
			if _retry_param(_id, prompt, opts, result, response_code, body_bytes):
				return
			_on_request_completed(_id, result, response_code, body_bytes)
	)


## A server that refuses the JSON format a request carried 400s naming it; remember that and retry once a rung lower.
func _retry_without(format: String, id: String, prompt: String, opts: Dictionary, result: int, code: int, body: PackedByteArray) -> bool:
	if result != HTTPRequest.RESULT_SUCCESS or code != 400:
		return false
	if not body.get_string_from_utf8().contains("response_format" if api_format != "ollama" else "format"):
		return false
	var refused: Dictionary = _json_refused.get(_json_key(), {})
	refused[format] = true
	_json_refused[_json_key()] = refused
	_cleanup(id)
	submit(id, prompt, opts)
	return true


## Newer OpenAI models 400 on max_tokens (naming max_completion_tokens) or on a set temperature; remember it and retry once without.
func _retry_param(id: String, prompt: String, opts: Dictionary, result: int, code: int, body: PackedByteArray) -> bool:
	if api_format == "ollama" or result != HTTPRequest.RESULT_SUCCESS or code != 400:
		return false
	var text: String = body.get_string_from_utf8()
	var refused: Dictionary = _param_refused.get(_json_key(), {})
	var named: String = ""
	if text.contains("max_completion_tokens") and not refused.has("max_tokens"):
		named = "max_tokens"
	elif text.contains("temperature") and not refused.has("temperature"):
		named = "temperature"
	if named == "":
		return false
	refused[named] = true
	_param_refused[_json_key()] = refused
	_cleanup(id)
	submit(id, prompt, opts)
	return true


## The richest JSON format this server has not refused: the caller's schema, then plain JSON mode, then the prompt alone.
func _json_format(opts: Dictionary) -> String:
	if not bool(opts.get("json_mode", false)):
		return ""
	var refused: Dictionary = _json_refused.get(_json_key(), {})
	if opts.get("json_schema", {}) is Dictionary and not (opts.get("json_schema", {}) as Dictionary).is_empty() and not refused.has("json_schema"):
		return "json_schema"
	if not refused.has("json_object"):
		return "json_object"
	return ""


func _json_key() -> String:
	return "%s|%s" % [_base(), model]


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
			match _json_format(opts):
				"json_schema":
					payload["format"] = opts["json_schema"]
				"json_object":
					payload["format"] = "json"
		"openai", _:
			var refused: Dictionary = _param_refused.get(_json_key(), {})
			payload = {
				"model": model,
				"messages": [{"role": "user", "content": prompt}],
			}
			payload["max_completion_tokens" if refused.has("max_tokens") else "max_tokens"] = max_tokens
			if not refused.has("temperature"):
				payload["temperature"] = temperature
			match _json_format(opts):
				"json_schema":
					payload["response_format"] = {"type": "json_schema", "json_schema": {"name": "reply", "schema": opts["json_schema"]}}
				"json_object":
					payload["response_format"] = {"type": "json_object"}

	## Keys go out in the order they were authored. Sorted, a schema's verdict came after its reason and the model argued itself into one.
	return JSON.stringify(payload, "", false)


func _extract_text(response_code: int, body_bytes: PackedByteArray) -> Array:
	# Returns [ok: bool, text: String, error: String]
	if response_code < 200 or response_code >= 300:
		return [false, "", "HTTP %d%s" % [response_code, _server_reason(response_code, body_bytes)]]

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
				text = content_text(parsed["response"])
			else:
				return [false, "", "Ollama response missing 'response' key"]
		"openai", _:
			# { "choices": [{ "message": { "content": "..." } }] }
			var choices = parsed.get("choices", [])
			var first = {}
			var msg = {}
			if choices is Array and choices.size() > 0 and choices[0] is Dictionary:
				first = choices[0]
				if first.get("message", {}) is Dictionary:
					msg = first.get("message", {})
					text = content_text(msg.get("content", ""))
			if text.is_empty():
				return [false, "", "OpenAI response missing choices[0].message.content" + _why_empty(first, msg)]

	return [true, text, ""]


## The server's own words for a refusal, after the status: bounded, the key struck out, and nothing at all for a key rejection.
func _server_reason(code: int, body_bytes: PackedByteArray) -> String:
	if code == 401 or code == 403:
		return ""
	var said: String = server_error_text(body_bytes.get_string_from_utf8())
	said = strike_credentials(said, api_key, model)
	return "" if said.is_empty() else ": " + said.left(MAX_REASON_CHARS)


## Server text with anything key-shaped struck; the player's own model id is set aside first unless it is key-shaped itself.
static func strike_credentials(text: String, key: String, keep: String = "") -> String:
	## Judged without the 20+ run rule: a long id is fine, one holding a piece of the key or a vendor token is not kept.
	if keep == "" or _struck(keep, key, CREDENTIAL_SHAPES.slice(0, -1)) != keep:
		return _struck(text, key, CREDENTIAL_SHAPES)
	var exact: String = text.replace(key, "[key]") if key != "" else text
	## Only where the id stands alone: inside a longer run it would split a token into pieces too short to be struck.
	var escaped: String = ""
	for ch in keep:
		escaped += ch if RegEx.create_from_string("^[A-Za-z0-9]$").search(ch) != null else "\\" + ch
	var alone: RegEx = RegEx.create_from_string("(?<![A-Za-z0-9_\\-])%s(?![A-Za-z0-9_\\-])" % escaped)
	return _struck(alone.sub(exact, KEPT_MARK, true), key, CREDENTIAL_SHAPES).replace(KEPT_MARK, keep)


## The key, each given shape, then any run sharing KEY_PIECE_CHARS with the key, each replaced by [key].
static func _struck(text: String, key: String, shapes: Array) -> String:
	var out: String = text.replace(key, "[key]") if key != "" else text
	for pattern in shapes:
		out = RegEx.create_from_string(pattern).sub(out, "[key]", true)
	if key.length() < KEY_PIECE_CHARS:
		return out
	var runs: Array[RegExMatch] = RegEx.create_from_string("[A-Za-z0-9_\\-]{%d,}" % KEY_PIECE_CHARS).search_all(out)
	runs.reverse()
	for run in runs:
		var word: String = run.get_string()
		for i in range(word.length() - KEY_PIECE_CHARS + 1):
			if key.contains(word.substr(i, KEY_PIECE_CHARS)):
				out = out.substr(0, run.get_start()) + "[key]" + out.substr(run.get_end())
				break
	return out


## The message in a JSON error body: OpenAI's error.message, Ollama's error string, or a bare message/detail; "" for anything else.
static func server_error_text(raw: String) -> String:
	if not raw.strip_edges().begins_with("{"):
		return ""
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		return ""
	var said = json.data.get("error", json.data.get("message", json.data.get("detail")))
	if said is Dictionary:
		said = said.get("message")
	if not (said is String):
		return ""
	var line: String = said.replace("\r", " ").replace("\n", " ").replace("\t", " ").strip_edges()
	while line.contains("  "):
		line = line.replace("  ", " ")
	return line


## A reply's content as speech: null is nothing, an array of parts is their text joined; str() would print "<null>" or the array.
static func content_text(v) -> String:
	if v == null:
		return ""
	if v is String:
		return v
	if v is Array:
		var parts: PackedStringArray = []
		for part in v:
			if part is String:
				parts.append(part)
			elif part is Dictionary and part.get("text") is String:
				parts.append(part["text"])
		return "".join(parts)
	return ""


## Why a reply carried no speech, for the error a player or Test Connection sees.
static func _why_empty(first: Dictionary, msg: Dictionary) -> String:
	if msg.get("refusal") is String and not str(msg["refusal"]).is_empty():
		return " (the model refused: %s)" % str(msg["refusal"]).left(120)
	var thought: bool = content_text(msg.get("reasoning_content")) != "" or content_text(msg.get("reasoning")) != ""
	if str(first.get("finish_reason", "")) == "length":
		return " (it ran out of tokens%s)" % (" while still reasoning" if thought else "")
	if thought:
		return " (it only reasoned)"
	return ""


func _on_request_completed(id: String, result: int, response_code: int, body_bytes: PackedByteArray) -> void:
	_cleanup(id)

	if result != HTTPRequest.RESULT_SUCCESS:
		var err_msg: String = _result_to_error(result)
		if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			err_msg = "reply passed the %d-byte cap" % max_reply_bytes
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
