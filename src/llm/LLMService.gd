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

## Emitted every time a request resolves to a guarded, non-fallback result.
signal inference_succeeded(mode: String)


# ── Constants ─────────────────────────────────────────────────────────────────
const QUEUE_CAP:          int    = 16    # Max queued (waiting) requests.
const CACHE_TTL_SECONDS:  float  = 300.0 # 5-minute TTL on cached responses.
const MAX_TEXT_CHARS:     int    = 2000  # Hard cap on free-text responses.
const MAX_CHOICE_TOKENS:  int    = 120   # Guard for choice-string length.

## Client-side guard. If the backend HTTPRequest hasn't resolved within
## CLIENT_TIMEOUT_SEC the awaiting caller takes the fallback so the player is
## never frozen for the full HTTPRequest timeout (default 30s). The backend
## request keeps running but is dropped on arrival via the stale-id guard.
## Matches design doc :155 ("set_can_move(false) freezes player for up to 30s
## during HTTPRequest timeout — no thinking indicator, no 6s guard").
const CLIENT_TIMEOUT_SEC: float  = 6.0

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

# Drain guard: true while cancel_all() is unwinding state so that any
# request_finished signal emitted synchronously by backend.cancel_all()
# does not re-enter _process_queue and submit a fresh request.
var _draining: bool = false

## True once 'no backend ready' has been logged this session.
## _select_backend() runs on every complete() call, so without this gate
## the warning fires for every NPC interaction / boss-strategy probe /
## party-chat fetch when LLM is enabled but no backend is reachable.
## One warning per session is plenty — it's status, not per-call info.
var _no_backend_warned: bool = false

# Active DynamicConversation registry — references to live DynamicConversation
# nodes so a scene-change can abort each one's UI/movement reset (LLM cancel
# alone leaves the choice menu visible).
var _active_conversations: Array = []


# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	# R4 (pause-safe): keep the await/poll loop alive when the SceneTree is
	# paused. _await_box yields on get_tree().process_frame; if the game pauses
	# mid-conversation a default-mode autoload would stop ticking and the
	# awaiting coroutine (and its CLIENT_TIMEOUT_SEC guard) would freeze until
	# unpause. PROCESS_MODE_ALWAYS makes the timeout fire regardless of pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
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
		if not _no_backend_warned:
			push_warning("[LLMService] No ready backend found — all calls will use fallbacks.")
			_no_backend_warned = true
	else:
		# Reset the gate when a backend comes back online (Ollama
		# returned, HTTP started accepting connections) — next outage
		# gets its own one-shot warning.
		_no_backend_warned = false


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
		inference_succeeded.emit(MODE_TEXT)
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
	else:
		inference_succeeded.emit(MODE_JSON)
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
		inference_succeeded.emit(MODE_CHOICE)
	return guarded


## Register a live DynamicConversation so abort_all_conversations() can tear it
## down on scene change. Idempotent; stale (freed) entries are pruned lazily.
func register_conversation(conv: Node) -> void:
	if conv == null:
		return
	if not (conv in _active_conversations):
		_active_conversations.append(conv)


## Unregister a conversation that has ended normally.
func unregister_conversation(conv: Node) -> void:
	_active_conversations.erase(conv)


## Abort every registered conversation (calls abort() on each). Used by GameLoop
## on scene change so the choice menu / frozen player are reset alongside the
## LLM request cancel.
func abort_all_conversations() -> void:
	var snapshot: Array = _active_conversations.duplicate()
	_active_conversations.clear()
	for conv in snapshot:
		if conv != null and is_instance_valid(conv) and conv.has_method("abort"):
			conv.abort()


## Cancel all in-flight and queued requests.  Each pending caller receives its
## fallback (the deferred resolution in _on_backend_finished handles this).
## Call on every scene change to prevent stale responses from previous scenes.
##
## Ordering invariant (bug #3): we MUST resolve the in-flight box and clear
## _inflight_id BEFORE calling backend.cancel_all().  HTTPBackend.cancel_all()
## emits request_finished synchronously; if _inflight_id were still set, the
## emit would pass the stale-id guard inside _on_backend_finished, then call
## _process_queue() and submit the next queued request — while cancel_all is
## still trying to drain it.  The _draining flag below additionally no-ops
## _process_queue so re-entrancy is double-safe.
func cancel_all(reason: String = "scene_change") -> void:
	_draining = true

	# Snapshot the in-flight id so we can mark + resolve it without leaving
	# state observably half-cleared while we resolve.
	var in_id: String = _inflight_id
	_inflight_id = ""
	if in_id != "":
		_cancelled_ids[in_id] = true
		_resolve_box(in_id, null)
		_pending_boxes.erase(in_id)

	# Drain the queue — resolve each box with null so awaiting callers unblock.
	for item in _queue:
		var id: String = item["id"]
		_cancelled_ids[id] = true
		_resolve_box(id, null)
		_pending_boxes.erase(id)
	_queue.clear()

	# Now tell the backend to abort its HTTPRequest.  Any synchronously emitted
	# request_finished will hit the stale-id guard cleanly (in_id != _inflight_id="")
	# and the _draining flag below means even if it did reach _process_queue,
	# it would no-op.
	if _active_backend != null:
		_active_backend.cancel_all()

	_draining = false
	print("[LLMService] cancel_all: %s" % reason)


# ── Internal: request dispatch ────────────────────────────────────────────────

## Submit a request and await the response (as raw text Variant, or null on fail).
## This is the single choke-point through which all public API calls flow.
##
## Bug fix (Wave C): we race the in-flight HTTPRequest against a 6-second
## client-side timer. If the timer wins, _await_box marks the request as
## cancelled, resolves the box with null (so the caller picks its fallback),
## and emits inference_failed("…", "client_timeout") for telemetry. The
## backend HTTPRequest is left running — when it eventually completes,
## _on_backend_finished sees the stale-id guard (_inflight_id has moved on)
## and drops the response cleanly.
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
		await _await_box(id, opts)
		# B1 (robust return): snapshot the resolved value the instant resolution
		# is observed. `box` is the same Array stored in _pending_boxes[id], and
		# cancel_all()/timeout paths may erase that dict entry (and other code may
		# reuse the id's slot); reading box[1] into a local NOW guarantees the
		# returned value can't be mutated out from under us afterwards.
		var queued_result: Variant = box[1]
		return queued_result

	# No in-flight — submit immediately.
	_inflight_id = id
	_active_backend.submit(id, prompt, opts)
	await _await_box(id, opts)
	# B1 (robust return): capture before returning — see note above.
	var result: Variant = box[1]
	return result


## Poll until box[0] is true, then return.  Uses a timer-based poll so we never
## spin-block the main thread.  This replaces a custom per-request Signal.
##
## Wave C: race the per-frame poll against a CLIENT_TIMEOUT_SEC timer. On
## timeout the box is force-resolved with null so the awaiting caller's
## fallback fires; the backend request is left in-flight and ignored on
## arrival via the stale-id guard in _on_backend_finished.
func _await_box(id: String, opts: Dictionary = {}) -> void:
	# Resolve the timeout for this call (allow override via opts for tests).
	var timeout: float = float(opts.get("client_timeout_sec", CLIENT_TIMEOUT_SEC))
	if timeout <= 0.0:
		# No client guard — fall back to legacy unbounded poll.
		while _pending_boxes.has(id) and not _pending_boxes[id][0]:
			await get_tree().process_frame
		return

	# Wave F B4 fix — use wall-clock ticks instead of get_process_delta_time().
	# delta is the LAST process tick on this node — meaningless when the
	# LLMService autoload's process_mode is anything other than the default,
	# and outright zero for nodes that don't tick. Time.get_ticks_msec() is
	# always monotonic.
	var t0_msec: int = Time.get_ticks_msec()
	while _pending_boxes.has(id) and not _pending_boxes[id][0]:
		await get_tree().process_frame
		var elapsed: float = float(Time.get_ticks_msec() - t0_msec) / 1000.0
		if elapsed >= timeout and _pending_boxes.has(id) and not _pending_boxes[id][0]:
			# Client timeout. Resolve the box with null so the awaiting
			# caller's fallback path fires immediately. Mark the id
			# cancelled and clear _inflight_id so:
			#   (a) the queue can dispatch the next pending request now,
			#       rather than waiting up to 30s for the HTTPRequest;
			#   (b) when the orphaned backend HTTPRequest eventually
			#       fires request_finished, the stale-id guard in
			#       _on_backend_finished (id != _inflight_id) drops it
			#       cleanly without re-resolving the box.
			# The _pending_boxes entry is erased here so the orphan can't
			# accidentally resolve into a re-used dict key later.
			_cancelled_ids[id] = true
			_resolve_box(id, null)
			_pending_boxes.erase(id)
			if _inflight_id == id:
				_inflight_id = ""
			# R6 (no orphan requests): now that _inflight_id no longer points at
			# this id, ask the backend to abort the still-running HTTPRequest so
			# the node doesn't linger until the server (or the 30s HTTPRequest
			# timeout) replies. HTTPBackend.cancel(id) frees the HTTPRequest and
			# emits request_finished(id, ...) — possibly SYNCHRONOUSLY. That is
			# safe here precisely because _inflight_id was cleared above:
			#   - _on_backend_finished's stale-id guard (id != _inflight_id) now
			#     holds, so the sync emit is a clean no-op (it does not re-resolve
			#     the already-erased box, nor re-enter _process_queue);
			#   - _pending_boxes[id] was already erased, so even if it slipped
			#     through, _resolve_box would no-op (it has()-checks first).
			# This is independent of the cancel_all() path: _draining stays false
			# here, but the stale-id guard alone makes the sync emit harmless.
			if _active_backend != null and _active_backend.has_method("cancel"):
				_active_backend.cancel(id)
			var mode_label: String = MODE_JSON if opts.get("json_mode", false) else MODE_TEXT
			inference_failed.emit(mode_label, "client_timeout")
			# Kick the queue so any pending request runs immediately.
			_process_queue()
			return


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
	# Re-entrant guard: cancel_all() may indirectly trigger _on_backend_finished
	# synchronously (HTTPBackend.cancel_all emits request_finished in the same
	# call frame).  Skip dispatch while draining; cancel_all is mid-cleanup.
	if _draining:
		return
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
