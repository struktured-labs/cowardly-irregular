extends GutTest

## `_get_cache` carries a severity argument that rests on a false premise:
##
##     "this cache is in-memory and cleared on scene change, so it only costs
##      freshness"
##
## It is never cleared. `clear_cache()` has ZERO production callers — only
## test_llm_infra.gd calls it — and `cancel_all("scene_change")`, which GameLoop
## :5080 fires on every scene change, does not touch `_cache`.
##
## ⛔ THE COMMENT IS THE DEFECT, NOT JUST THE GROWTH. It is the sentence a reader
## reaches for when judging how bad a cache problem is, and it answers wrong in
## the reassuring direction. That is the half no test would otherwise catch.
##
## Growth: an entry is evicted only when its OWN key is read again (`_get_cache`
## erases on TTL). A key never queried again is never visited, so the 5-minute
## TTL bounds STALENESS, not MEMORY. Every distinct prompt+opts leaves a
## permanent entry holding a response of up to MAX_TEXT_CHARS.
##
## ⚠️ SEVERITY, STATED HONESTLY: nobody has measured a memory problem, and a
## realistic session leaves this in the low megabytes at worst. The reasons to
## fix it are that the documented behaviour is false and the bound is absent,
## not that anyone observed harm.

var _svc = null


func before_each() -> void:
	_svc = get_tree().root.get_node_or_null("LLMService")
	if _svc:
		_svc._cache.clear()


func after_each() -> void:
	if _svc:
		_svc._cache.clear()


# ── floor ─────────────────────────────────────────────────────────────────────

func test_the_pieces_this_file_drives_are_reachable() -> void:
	assert_not_null(_svc, "LLMService autoload missing — nothing below runs")
	assert_true("_cache" in _svc, "LLMService._cache is gone")
	assert_true(_svc.has_method("cancel_all"), "LLMService.cancel_all is gone")
	assert_true(_svc.has_method("_set_cache"), "LLMService._set_cache is gone")
	assert_true(_svc.has_method("clear_cache"), "LLMService.clear_cache is gone")


func test_eviction_is_read_driven_which_is_why_the_ttl_bounds_no_memory() -> void:
	## PINS THE MECHANISM the header's growth claim rests on: eviction lives in
	## _get_cache, so it can only ever reach a key somebody asks for again. The
	## later _set_cache is the part that matters — without it this arm cannot
	## see a set-driven sweep and passes while claiming otherwise.
	_svc._set_cache("never_read_again", "x")
	_svc._cache["never_read_again"]["ts"] = 0.0
	_svc._set_cache("some_other_key", "y")
	assert_true(_svc._cache.has("never_read_again"),
		"an expired entry was evicted without its key being read. That is a "
		+ "BETTER cache, not a regression — but this file's header argues the TTL "
		+ "bounds staleness and not memory, and that argument is now stale. "
		+ "Update the header, then this arm.")


# ── the defect ────────────────────────────────────────────────────────────────

func test_a_scene_change_clears_the_cache_as_the_comment_promises() -> void:
	## THE DEFECT. GameLoop:5080 calls cancel_all("scene_change") on every scene
	## change; the comment in _get_cache tells the reader that is what bounds this
	## cache. Either the code does it or the comment must stop saying so.
	_svc._set_cache("a", "one")
	_svc._set_cache("b", "two")
	_svc.cancel_all("scene_change")
	assert_eq(_svc._cache.size(), 0,
		("cancel_all left %d cache entr(ies) behind. _get_cache states this cache "
		+ "is 'cleared on scene change, so it only costs freshness' — it is never "
		+ "cleared in production: clear_cache() has no src/ caller and cancel_all "
		+ "does not touch _cache. An entry is evicted only when its own key is "
		+ "read again, so the TTL bounds staleness, not memory.")
			% [_svc._cache.size()])
