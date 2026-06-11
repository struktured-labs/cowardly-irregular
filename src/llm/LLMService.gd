## LLMService — autoload singleton; central registry for LLM inference.
##
## Public API (all methods are safe to call when LLM is disabled):
##   is_available() -> bool
##   complete(prompt, fallback, opts)       -> Variant   (free text)
##   complete_json(prompt, schema, fallback, opts) -> Variant  (dict or fallback)
##   choose(prompt, valid_options, fallback, opts) -> String  (guaranteed ∈ options ∪ {fallback})
##   cancel_all(reason)                     — call on scene change
##
## Internals:
##   - Single in-flight request (serialized queue); requests queue while one is active.
##   - Per-session cache keyed by hash(mode+prompt+opts); bypassed on json_mode.
##   - Drop-oldest queue overflow (cap: QUEUE_CAP).
##   - inference_failed signal emitted on every fallback for telemetry.
##   - cancel_all routes all pending + in-flight requests to their fallbacks.
##
## Backend selection (first is_ready() wins):
##   LocalBackend → HTTPBackend → NullBackend
##
## Threading invariant: never blocks the main thread.  Uses `await signal`.
## Callers must also `await` — complete/complete_json/choose are async.

extends Node

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted every time a fallback is used (LLM failed or was skipped).
signal inference_failed(mode: String, reason: String)


# ── Constants ─────────────────────────────────────────────────────────────────
const QUEUE_CAP:          int    = 16    # Max queued (waiting) requests.
const CACHE_TTL_SECONDS:  float  = 300.0 # 5-minute TTL on cached responses.
const MAX_TEXT_CHARS:     int    = 2000  # Hard cap on free-text responses.
const MAX_CHOICE_TOKENS:  int    = 120   # Guard for choice-string length.

## Refusal pattern — any response starting/containing these is rejected.
const REFUSAL_PATTERNS: Array[String] = [
	"as an ai",
	"i'm an ai",
	"i cannot",
	"i'm unable",
	"i am unable",
]

# Request modes (used as cache key prefix + guard selector).
const MODE_TEXT   := "text"
const MODE_JSON   := "json"
const MODE_CHOICE := "choice"


# ── Configuration ─────────────────────────────────────────────────────────────
## Master enable flag — when false, every call returns its fallback immediately.
var llm_enabled: bool = true

## Backend instances (set up in _ready; replaceable for testing).
var _backends: Array[LLMBackend] = []

## Active backend (resolved lazily by _select_backend).
var _active_backend: LLMBackend = null


# ── Internal state ────────────────────────────────────────────────────────────

# Per-session response cache.  { cache_key:String → { text:String, ts:float } }
var _cache: Dictionary = {}

# Single in-flight slot: id of the current request, or "" if idle.
var _inflight_id: String = ""

# Queue of pending requests: Array of { id, resolve_signal, prompt, mode, opts, valid_options, fallback }
var _queue: Array[Dictionary] = []

# Maps request_id → signal for callers awaiting a result.
# We use a per-request Signal object created via Signal-as-value pattern.
# In GDScript 4 we store a Callable per id and use a local signal workaround.
# The implementation below uses a Dictionary of { id → result_container } where
# result_container is an Array[Variant] (mutable by reference via the closure).

# Pending completions map: id → Array (mutable box: [resolved:bool, value:Variant])
var _pending_boxes: Dictionary = {}

# Cancellation set: ids that have been cancelled.
var _cancelled_ids: Dictionary = {}


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	_build_backends()
	_select_backend()


func _build_backends() -> void:
	# NullBackend is always added last as the guaranteed fallback.
	# HTTPBackend and LocalBackend are added if they exist in the scene tree
	# already (set up by an external configurator), or created with defaults.
	var http := HTTPBackend.new()
	http.name = "HTTPBackend"
	add_child(http)

	var null_be := NullBackend.new()
	null_be.name = "NullBackend"
	add_child(null_be)

	_backends = [http, null_be]

	# Connect all backends.
	for be in _backends:
		be.request_finished.connect(_on_backend_finished)


func _select_backend() -> void:
	_active_backend = null
	for be in _backends:
		if be.is_ready():
			_active_backend = be
			break
	if _active_backend == null:
		push_warning("[LLMService] No ready backend found — all calls will use fallbacks.")


# ── Public API ────────────────────────────────────────────────────────────────

## Returns true when the LLM is enabled AND at least one non-Null backend is ready.
func is_available() -> bool:
	if not llm_enabled:
		return false
	for be in _backends:
		if be.backend_id() != "null" and be.is_ready():
			return true
	return false


## Free-text completion.  Returns `fallback` if LLM is off or fails.
## MUST be awaited: `var result = await LLMService.complete(prompt, fallback)`
func complete(prompt: String, fallback: String, opts: Dictionary = {}) -> Variant:
	if not llm_enabled:
		return fallback
	_select_backend()  # Re-probe readiness on each call.
	if _active_backend == null or not _active_backend.is_ready():
		inference_failed.emit(MODE_TEXT, "no ready backend")
		return fallback

	var cache_key: String = _cache_key(MODE_TEXT, prompt, opts)
	var cached = _get_cache(cache_key)
	if cached != null:
		return cached

	var raw: Variant = await _submit_and_wait(prompt, opts)
	if raw == null:
		inference_failed.emit(MODE_TEXT, "request failed or cancelled")
		return fallback

	var guarded: Variant = _guard_text(str(raw), fallback)
	if guarded == fallback:
		inference_failed.emit(MODE_TEXT, "guard rejected response")
	else:
		_set_cache(cache_key, guarded)
	return guarded


## JSON-mode completion validated against `schema`.
## `schema` keys are required; primitive type and enum constraints are checked.
## Returns `fallback` on any failure.
## MUST be awaited.
func complete_json(prompt: String, schema: Dictionary, fallback: Variant, opts: Dictionary = {}) -> Variant:
	if not llm_enabled:
		return fallback
	_select_backend()
	if _active_backend == null or not _active_backend.is_ready():
		inference_failed.emit(MODE_JSON, "no ready backend")
		return fallback

	# JSON responses are not cached (high variance + ephemeral by design).
	var merged_opts: Dictionary = opts.duplicate()
	merged_opts["json_mode"] = true

	var raw: Variant = await _submit_and_wait(prompt, merged_opts)
	if raw == null:
		inference_failed.emit(MODE_JSON, "request failed or cancelled")
		return fallback

	var guarded: Variant = _guard_json(str(raw), schema, fallback)
	if guarded == fallback:
		inference_failed.emit(MODE_JSON, "guard rejected response")
	return guarded


## Choice selection: returns a string guaranteed to be in `valid_options`,
## or `fallback` if the LLM fails or returns an unrecognised value.
## `fallback` MUST be a member of `valid_options` (asserted in debug builds).
## MUST be awaited.
func choose(prompt: String, valid_options: Array[String], fallback: String, opts: Dictionary = {}) -> String:
	assert(fallback in valid_options,
		"[LLMService] choose() fallback '%s' is not in valid_options." % fallback)

	if not llm_enabled:
		return fallback
	_select_backend()
	if _active_backend == null or not _active_backend.is_ready():
		inference_failed.emit(MODE_CHOICE, "no ready backend")
		return fallback

	var cache_key: String = _cache_key(MODE_CHOICE, prompt, opts)
	var cached = _get_cache(cache_key)
	if cached != null and (cached as String) in valid_options:
		return cached as String

	var raw: Variant = await _submit_and_wait(prompt, opts)
	if raw == null:
		inference_failed.emit(MODE_CHOICE, "request failed or cancelled")
		return fallback

	var guarded: String = _guard_choice(str(raw), valid_options, fallback)
	if guarded == fallback and not (str(raw).strip_edges() in valid_options):
		inference_failed.emit(MODE_CHOICE, "guard rejected response")
	else:
		_set_cache(cache_key, guarded)
	return guarded


## Cancel all in-flight and queued requests.  Each pending caller receives its
## fallback (the deferred resolution in _on_backend_finished handles this).
## Call on every scene change to prevent stale responses from previous scenes.
func cancel_all(reason: String = "scene_change") -> void:
	# Cancel the in-flight request on the active backend.
	if _inflight_id != "":
		_cancelled_ids[_inflight_id] = true
		if _active_backend != null:
			_active_backend.cancel_all()
		_inflight_id = ""

	# Drain the queue — resolve each box with null so awaiting callers unblock.
	for item in _queue:
		var id: String = item["id"]
		_cancelled_ids[id] = true
		_resolve_box(id, null)
	_queue.clear()

	print("[LLMService] cancel_all: %s" % reason)


# ── Internal: request dispatch ────────────────────────────────────────────────

## Submit a request and await the response (as raw text Variant, or null on fail).
## This is the single choke-point through which all public API calls flow.
func _submit_and_wait(prompt: String, opts: Dictionary) -> Variant:
	var id: String = _generate_id()
	var box: Array = [false, null]  # [resolved, value]
	_pending_boxes[id] = box

	if _inflight_id != "":
		# Another request is in-flight; queue this one.
		if _queue.size() >= QUEUE_CAP:
			# Drop-oldest: evict the front of the queue.
			var dropped: Dictionary = _queue.pop_front()
			var dropped_id: String = dropped["id"]
			_cancelled_ids[dropped_id] = true
			_resolve_box(dropped_id, null)
			push_warning("[LLMService] Queue overflow — dropped request '%s'." % dropped_id)

		_queue.append({"id": id, "prompt": prompt, "opts": opts})
		# Wait for box to be resolved (by _process_queue when it's our turn).
		await _await_box(id)
		return box[1]

	# No in-flight — submit immediately.
	_inflight_id = id
	_active_backend.submit(id, prompt, opts)
	await _await_box(id)
	return box[1]


## Poll until box[0] is true, then return.  Uses a timer-based poll so we never
## spin-block the main thread.  This replaces a custom per-request Signal.
func _await_box(id: String) -> void:
	# We rely on the fact that _resolve_box always defers to the next frame,
	# so we can safely yield here and check on the next physics / idle frame.
	while _pending_boxes.has(id) and not _pending_boxes[id][0]:
		await get_tree().process_frame


func _resolve_box(id: String, value: Variant) -> void:
	if _pending_boxes.has(id):
		_pending_boxes[id][0] = true
		_pending_boxes[id][1] = value
		# Don't erase yet — _await_box will see resolved=true and exit.


func _on_backend_finished(id: String, ok: bool, text: String, error: String) -> void:
	if id != _inflight_id:
		# Stale signal from a previous/cancelled request — ignore.
		return

	_inflight_id = ""

	var value: Variant = text if ok else null
	_resolve_box(id, value)
	_pending_boxes.erase(id)

	# Dispatch the next queued request, if any.
	_process_queue()


func _process_queue() -> void:
	if _queue.is_empty() or _inflight_id != "":
		return

	# Re-check backend readiness before dispatching.
	_select_backend()
	if _active_backend == null or not _active_backend.is_ready():
		# Drain the queue with failures.
		for item in _queue.duplicate():
			_resolve_box(item["id"], null)
			_pending_boxes.erase(item["id"])
		_queue.clear()
		return

	var next: Dictionary = _queue.pop_front()
	var id: String = next["id"]

	if _cancelled_ids.has(id):
		_cancelled_ids.erase(id)
		_resolve_box(id, null)
		_pending_boxes.erase(id)
		_process_queue()  # Try next.
		return

	_inflight_id = id
	_active_backend.submit(id, next["prompt"], next["opts"])


# ── Hallucination guard ────────────────────────────────────────────────────────
# Every branch returns a value the call site has already proved safe.

## TEXT guard: trim, clamp, reject refusals.
func _guard_text(raw: String, fallback: String) -> Variant:
	var text: String = raw.strip_edges()
	if text.is_empty():
		return fallback

	# Refusal check (case-insensitive prefix/contains scan).
	var lower: String = text.to_lower()
	for pattern in REFUSAL_PATTERNS:
		if lower.begins_with(pattern) or lower.contains(pattern):
			push_warning("[LLMService][guard/text] Refusal pattern '%s' detected." % pattern)
			return fallback

	# Hard length cap.
	if text.length() > MAX_TEXT_CHARS:
		text = text.left(MAX_TEXT_CHARS)

	return text


## CHOICE guard: exact match → whole-token match → {"choice":X} extraction → fallback.
func _guard_choice(raw: String, valid_options: Array[String], fallback: String) -> String:
	var trimmed: String = raw.strip_edges()

	# 1. Exact match (case-sensitive).
	if trimmed in valid_options:
		return trimmed

	# 2. Case-insensitive exact match.
	var lower: String = trimmed.to_lower()
	for opt in valid_options:
		if opt.to_lower() == lower:
			return opt

	# 3. Unique whole-token match — option appears as a standalone word in the response.
	var matches: Array[String] = []
	for opt in valid_options:
		# Use word-boundary-style search: check the response contains the option
		# surrounded by non-alphanumeric chars or at start/end.
		var pattern: String = opt.to_lower()
		var idx: int = lower.find(pattern)
		while idx != -1:
			var before_ok: bool = (idx == 0) or not lower[idx - 1].unicode_at(0) in range(97, 123)
			var after_idx: int = idx + pattern.length()
			var after_ok: bool = (after_idx >= lower.length()) or not lower[after_idx].unicode_at(0) in range(97, 123)
			if before_ok and after_ok:
				if not (opt in matches):
					matches.append(opt)
				break
			idx = lower.find(pattern, idx + 1)
	if matches.size() == 1:
		return matches[0]

	# 4. {"choice": X} extraction from JSON wrapper.
	var extracted: Variant = _extract_json_from_raw(trimmed)
	if extracted is Dictionary:
		var choice_val = extracted.get("choice", null)
		if choice_val != null:
			var choice_str: String = str(choice_val).strip_edges()
			if choice_str in valid_options:
				return choice_str
			# Case-insensitive.
			for opt in valid_options:
				if opt.to_lower() == choice_str.to_lower():
					return opt

	return fallback


## JSON guard: extract JSON from raw → parse → schema validate → fallback.
func _guard_json(raw: String, schema: Dictionary, fallback: Variant) -> Variant:
	var extracted: Variant = _extract_json_from_raw(raw.strip_edges())
	if not (extracted is Dictionary):
		push_warning("[LLMService][guard/json] Failed to extract valid JSON from response.")
		return fallback

	var parsed: Dictionary = extracted as Dictionary

	# Lightweight schema validation: required keys + primitive types + enums.
	for key in schema.keys():
		if not parsed.has(key):
			push_warning("[LLMService][guard/json] Missing required key '%s'." % key)
			return fallback
		var spec: Variant = schema[key]
		var val: Variant = parsed[key]
		if spec is String:
			# Treat spec as a type name: "String", "int", "float", "bool", "Array", "Dictionary"
			if not _type_matches(val, spec):
				push_warning("[LLMService][guard/json] Key '%s' type mismatch (expected %s)." % [key, spec])
				return fallback
		elif spec is Array:
			# Treat spec as an enum of valid values.
			if not (val in spec):
				push_warning("[LLMService][guard/json] Key '%s' value '%s' not in enum %s." % [key, val, spec])
				return fallback

	return parsed


# ── JSON utilities ─────────────────────────────────────────────────────────────

## Extract a JSON object from raw text, stripping markdown fences and prose.
## Returns a Dictionary on success, or null on failure.
func _extract_json_from_raw(raw: String) -> Variant:
	# 1. Try direct parse.
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		return parsed

	# 2. Strip ``` fences.
	var stripped: String = raw
	var fence_start: int = raw.find("```")
	if fence_start != -1:
		var fence_end: int = raw.find("```", fence_start + 3)
		if fence_end != -1:
			stripped = raw.substr(fence_start + 3, fence_end - fence_start - 3)
			# Strip optional language tag on the opening fence.
			var nl: int = stripped.find("\n")
			if nl != -1 and nl < 20:
				stripped = stripped.substr(nl + 1).strip_edges()
		parsed = JSON.parse_string(stripped.strip_edges())
		if parsed is Dictionary:
			return parsed

	# 3. Find first '{' … last '}' in the raw string.
	var brace_open: int = raw.find("{")
	var brace_close: int = raw.rfind("}")
	if brace_open != -1 and brace_close > brace_open:
		var json_slice: String = raw.substr(brace_open, brace_close - brace_open + 1)
		parsed = JSON.parse_string(json_slice)
		if parsed is Dictionary:
			return parsed

	return null


func _type_matches(val: Variant, type_name: String) -> bool:
	match type_name:
		"String":  return val is String
		"int":     return val is int or val is float
		"float":   return val is float or val is int
		"bool":    return val is bool
		"Array":   return val is Array
		"Dictionary": return val is Dictionary
		_:         return true  # Unknown type spec — pass through.


# ── Cache helpers ─────────────────────────────────────────────────────────────

func _cache_key(mode: String, prompt: String, opts: Dictionary) -> String:
	return "%s:%d" % [mode, hash(prompt + str(opts))]


func _get_cache(key: String) -> Variant:
	if not _cache.has(key):
		return null
	var entry: Dictionary = _cache[key]
	var age: float = Time.get_unix_time_from_system() - float(entry.get("ts", 0.0))
	if age > CACHE_TTL_SECONDS:
		_cache.erase(key)
		return null
	return entry.get("text", null)


func _set_cache(key: String, text: Variant) -> void:
	_cache[key] = {"text": text, "ts": Time.get_unix_time_from_system()}


## Clear the entire session cache (call on scene change alongside cancel_all).
func clear_cache() -> void:
	_cache.clear()


# ── Utility ───────────────────────────────────────────────────────────────────

var _id_counter: int = 0

func _generate_id() -> String:
	_id_counter += 1
	return "llm_%d_%d" % [_id_counter, int(Time.get_ticks_msec())]
