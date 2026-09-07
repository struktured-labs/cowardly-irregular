## LLMBackend — abstract contract for all LLM inference backends.
##
## Every concrete backend (HTTPBackend, NullBackend, LocalBackend) extends this
## class and overrides the virtual methods below.  LLMService only talks to this
## interface, making backends fully interchangeable with zero call-site changes.
##
## Lifecycle
## ─────────
##   submit(id, prompt, opts)  →  (async)  →  request_finished.emit(id, ok, text, error)
##
## The `id` is an opaque string chosen by the caller (typically a UUID from
## LLMService).  The backend MUST emit `request_finished` exactly once per
## submitted id — even on error or cancellation — so that callers never deadlock.
##
## Threading invariant: all methods run on the main thread.  Implementations must
## never block (no sleep / busy-wait / synchronous HTTP).

class_name LLMBackend
extends Node

# ── Signals ───────────────────────────────────────────────────────────────────

## Emitted when a previously submitted request has completed (success or fail).
##   id    — the opaque id passed to submit()
##   ok    — true if `text` contains a usable response; false on any error
##   text  — raw response text from the model (empty string on failure)
##   error — human-readable error description (empty string on success)
signal request_finished(id: String, ok: bool, text: String, error: String)


# ── Virtual API ───────────────────────────────────────────────────────────────

## Return a stable identifier for this backend (e.g. "http", "null", "local").
## Must be a non-empty lowercase string with no spaces.
func backend_id() -> String:
	return "base"


## Return true when the backend is ready to accept new requests.
## LLMService will skip this backend and fall through to the next if false.
func is_ready() -> bool:
	return false


## Return true if this backend supports requesting JSON-structured output
## (e.g. Ollama `"format":"json"` or OpenAI response_format).
func supports_json() -> bool:
	return false


## Return true if this backend supports grammar-constrained output
## (currently reserved for llama.cpp backends; not used in Phase 1).
func supports_grammar() -> bool:
	return false


## Submit an inference request.
##   id     — opaque caller-assigned identifier; echoed in request_finished
##   prompt — full prompt string (system + user already concatenated by caller)
##   opts   — Dictionary with optional keys:
##              "max_tokens"  : int    (default backend-specific)
##              "temperature" : float  (default backend-specific)
##              "json_mode"   : bool   (request structured JSON output)
##              "timeout_sec" : float  (0 = backend default)
##
## Implementations MUST emit request_finished exactly once for every call.
func submit(id: String, prompt: String, opts: Dictionary = {}) -> void:
	push_error("[LLMBackend] submit() not implemented in backend '%s'" % backend_id())
	request_finished.emit(id, false, "", "submit() not implemented")


## Cancel an in-flight request identified by `id`.
## If the id is not found (already finished), this is a no-op.
## Implementations should emit request_finished(id, false, "", "cancelled")
## if the request was actually in-flight at the time of the call.
func cancel(id: String) -> void:
	pass  # Default: no-op (NullBackend never has in-flight requests)


## Cancel ALL in-flight requests (called by LLMService.cancel_all on scene change).
## Default implementation is a no-op; backends with queues should override.
func cancel_all() -> void:
	pass
