extends GutTest

## Comprehensive unit tests for LLM infrastructure.
##
## Coverage:
##   1. EventLog   — ring buffer bounds, serialization round-trips, fact retrieval.
##   2. NullBackend — response priming, deferred signal emission.
##   3. LLMContext  — serialization footprint and budget-guard truncation.
##   4. LLMService  — cache hits, in-flight serialization queue, Hallucination Guard
##                    (TEXT, CHOICE with fuzzy matches, JSON schema validation + fallback).
##
## All tests are self-contained: no autoload singletons are required.
##
## NOTE: Groups are separated by naming convention only; GUT does not have a
## native grouping mechanism.  All EventLog tests are prefixed test_event_log_*,
## NullBackend tests are prefixed test_null_be_*, LLMContext tests are prefixed
## test_llm_context_*, and LLMService tests are prefixed test_llm_service_*.


# ══════════════════════════════════════════════════════════════════════════════
# ── Shared instance variables ─────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

# Re-created before each test via before_each.
var _log: EventLog
var _null_be: NullBackend
var _svc: Node  # LLMService instance


# ── GUT lifecycle ─────────────────────────────────────────────────────────────

func before_each() -> void:
	# EventLog is a RefCounted — no scene tree needed.
	_log = EventLog.new()

	# NullBackend extends Node — must be in the tree for call_deferred to fire.
	_null_be = NullBackend.new()
	_null_be.name = "TestNullBackend"
	add_child_autofree(_null_be)

	# LLMService — instantiate with llm_enabled=false so no HTTP work happens.
	# Backends are constructed after _ready runs inside add_child_autofree,
	# but we replace them in individual tests that need a live backend.
	_svc = preload("res://src/llm/LLMService.gd").new()
	_svc.name = "TestLLMService"
	_svc.llm_enabled = false
	add_child_autofree(_svc)


func after_each() -> void:
	_log = null
	# _null_be and _svc are freed by add_child_autofree.


# ══════════════════════════════════════════════════════════════════════════════
# ── EventLog tests ────────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

## Fresh log is empty.
func test_event_log_starts_empty() -> void:
	assert_eq(_log.size(), 0, "Fresh EventLog should be empty")


## Basic record increments size.
func test_event_log_record_increments_size() -> void:
	_log.record(EventLog.TYPE_AREA_ENTERED, "Entered Verdant Vale")
	assert_eq(_log.size(), 1, "One record should yield size 1")


## clear() empties the log.
func test_event_log_clear_empties_log() -> void:
	_log.record(EventLog.TYPE_CUSTOM, "A")
	_log.record(EventLog.TYPE_CUSTOM, "B")
	_log.clear()
	assert_eq(_log.size(), 0, "clear() should empty the log")


## RING_CAP constant is 50.
func test_event_log_ring_cap_constant() -> void:
	assert_eq(EventLog.RING_CAP, 50, "RING_CAP should be 50")


## Adding exactly RING_CAP entries fills without dropping.
func test_event_log_fills_to_cap_without_dropping() -> void:
	for i in range(EventLog.RING_CAP):
		_log.record(EventLog.TYPE_CUSTOM, "event_%d" % i)
	assert_eq(_log.size(), EventLog.RING_CAP, "Should hold exactly RING_CAP entries")


## Adding RING_CAP + 1 entries drops the oldest.
func test_event_log_overflow_drops_oldest() -> void:
	for i in range(EventLog.RING_CAP):
		_log.record(EventLog.TYPE_CUSTOM, "old_%d" % i)
	_log.record(EventLog.TYPE_CUSTOM, "newest")
	assert_eq(_log.size(), EventLog.RING_CAP, "Size should remain at RING_CAP after overflow")
	# The oldest entry ('old_0') should have been dropped.
	var recent: Array[Dictionary] = _log.recent()
	var summaries: Array = []
	for e in recent:
		summaries.append(e.get("summary", ""))
	assert_false("old_0" in summaries, "Oldest entry should have been evicted")
	assert_true("newest" in summaries, "Newest entry should still be present")


## Double overflow keeps only the RING_CAP most recent.
func test_event_log_double_overflow_keeps_most_recent() -> void:
	var total: int = EventLog.RING_CAP + 10
	for i in range(total):
		_log.record(EventLog.TYPE_CUSTOM, "ev_%d" % i)
	assert_eq(_log.size(), EventLog.RING_CAP, "Size must not exceed RING_CAP")
	var recent: Array[Dictionary] = _log.recent()
	assert_eq(recent[recent.size() - 1].get("summary", ""),
		"ev_%d" % (total - 1), "Last entry should be the most recent")


## recent(n) returns exactly n entries when n < size.
func test_event_log_recent_n_returns_n_entries() -> void:
	for i in range(20):
		_log.record(EventLog.TYPE_CUSTOM, "ev_%d" % i)
	var r: Array[Dictionary] = _log.recent(5)
	assert_eq(r.size(), 5, "recent(5) should return exactly 5 entries")


## recent(n) returns all entries when n >= size.
func test_event_log_recent_n_ge_size_returns_all() -> void:
	for i in range(3):
		_log.record(EventLog.TYPE_CUSTOM, "ev_%d" % i)
	var r: Array[Dictionary] = _log.recent(100)
	assert_eq(r.size(), 3, "recent(100) with 3 entries should return all 3")


## recent(0) returns all entries.
func test_event_log_recent_zero_returns_all() -> void:
	for i in range(5):
		_log.record(EventLog.TYPE_CUSTOM, "ev_%d" % i)
	var r: Array[Dictionary] = _log.recent(0)
	assert_eq(r.size(), 5, "recent(0) should return all entries")


## recent_entries() is an alias for recent().
func test_event_log_recent_entries_alias() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Golem")
	var a: Array[Dictionary] = _log.recent()
	var b: Array[Dictionary] = _log.recent_entries()
	assert_eq(a.size(), b.size(), "recent() and recent_entries() should return same count")


## recent() returns a duplicate; mutations don't affect internal state.
func test_event_log_recent_returns_copy() -> void:
	_log.record(EventLog.TYPE_CUSTOM, "original")
	var r: Array[Dictionary] = _log.recent()
	r.clear()
	assert_eq(_log.size(), 1, "Clearing the returned copy must not affect internal state")


## by_type() returns only entries of the requested type.
func test_event_log_by_type_filters_correctly() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Boss1 down")
	_log.record(EventLog.TYPE_PARTY_WIPE,  "Everyone died")
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Boss2 down")
	_log.record(EventLog.TYPE_ITEM_OBTAINED, "Got potion")
	var defeats: Array[Dictionary] = _log.by_type(EventLog.TYPE_BOSS_DEFEAT)
	assert_eq(defeats.size(), 2, "Should find exactly 2 boss_defeat entries")
	for d in defeats:
		assert_eq(d.get("type", ""), EventLog.TYPE_BOSS_DEFEAT,
			"All returned entries should be boss_defeat")


## by_type() returns empty array for unknown type.
func test_event_log_by_type_unknown_type_returns_empty() -> void:
	_log.record(EventLog.TYPE_CUSTOM, "something")
	var result: Array[Dictionary] = _log.by_type("does_not_exist")
	assert_eq(result.size(), 0, "Unknown type should return empty array")


## Entry schema includes required fields: t, pt, type, summary, data.
func test_event_log_entry_schema() -> void:
	_log.record(EventLog.TYPE_LEVEL_UP, "Fighter levelled up", {"level": 5})
	var r: Array[Dictionary] = _log.recent()
	assert_eq(r.size(), 1, "Should have one entry")
	var entry: Dictionary = r[0]
	assert_true(entry.has("t"),       "Entry must have 't' (timestamp)")
	assert_true(entry.has("pt"),      "Entry must have 'pt' (playtime)")
	assert_true(entry.has("type"),    "Entry must have 'type'")
	assert_true(entry.has("summary"), "Entry must have 'summary'")
	assert_true(entry.has("data"),    "Entry must have 'data'")
	assert_eq(entry["type"],    EventLog.TYPE_LEVEL_UP,    "type should match")
	assert_eq(entry["summary"], "Fighter levelled up",     "summary should match")
	assert_eq(entry["data"],    {"level": 5},              "data should match")


## data dict is duplicated; external mutation doesn't affect stored entry.
func test_event_log_data_is_shallow_duplicated() -> void:
	var d: Dictionary = {"key": "original"}
	_log.record(EventLog.TYPE_CUSTOM, "test", d)
	d["key"] = "mutated"
	var stored: Dictionary = _log.recent()[0].get("data", {})
	assert_eq(stored.get("key", ""), "original",
		"Stored data should not reflect external mutation")


## Serialization round-trip: serialize() → restore() preserves all entries.
func test_event_log_serialize_restore_roundtrip() -> void:
	_log.record(EventLog.TYPE_AREA_ENTERED, "Forest", {"world": 1})
	_log.record(EventLog.TYPE_BOSS_DEFEAT,  "Dragon", {"boss_id": "dragon_1"})
	var raw: Array = _log.serialize()

	var log2 := EventLog.new()
	log2.restore(raw)
	assert_eq(log2.size(), 2, "Restored log should have 2 entries")
	assert_eq(log2.recent()[0].get("summary", ""), "Forest",
		"First entry summary should survive round-trip")
	assert_eq(log2.recent()[1].get("summary", ""), "Dragon",
		"Second entry summary should survive round-trip")


## serialize() returns a deep duplicate (not the internal array).
func test_event_log_serialize_returns_copy() -> void:
	_log.record(EventLog.TYPE_CUSTOM, "X")
	var raw: Array = _log.serialize()
	raw.clear()
	assert_eq(_log.size(), 1, "Clearing serialized output must not affect internal state")


## restore(null) clears the log gracefully.
func test_event_log_restore_null_clears() -> void:
	_log.record(EventLog.TYPE_CUSTOM, "existing")
	_log.restore(null)
	assert_eq(_log.size(), 0, "restore(null) should clear the log")


## restore() with a non-Array value is ignored gracefully.
func test_event_log_restore_non_array_ignored() -> void:
	_log.restore("not an array")
	assert_eq(_log.size(), 0, "restore with non-Array should yield empty log")


## restore() skips non-Dictionary entries without crashing.
func test_event_log_restore_skips_bad_entries() -> void:
	var mixed: Array = [{"type": "custom", "summary": "ok", "t": 0, "pt": 0, "data": {}},
						"not a dict", 42, null]
	_log.restore(mixed)
	assert_eq(_log.size(), 1, "Only valid Dictionary entries should be restored")


## restore() with exactly RING_CAP entries gives RING_CAP size.
func test_event_log_restore_at_ring_cap() -> void:
	var raw: Array = []
	for i in range(EventLog.RING_CAP):
		raw.append({"type": "custom", "summary": "ev_%d" % i, "t": i, "pt": 0, "data": {}})
	_log.restore(raw)
	assert_eq(_log.size(), EventLog.RING_CAP,
		"Restoring exactly RING_CAP entries should yield RING_CAP size")


## TYPE_* constants have correct string values.
func test_event_log_type_constants() -> void:
	assert_eq(EventLog.TYPE_BOSS_DEFEAT,   "boss_defeat",   "TYPE_BOSS_DEFEAT")
	assert_eq(EventLog.TYPE_PARTY_WIPE,    "party_wipe",    "TYPE_PARTY_WIPE")
	assert_eq(EventLog.TYPE_AREA_ENTERED,  "area_entered",  "TYPE_AREA_ENTERED")
	assert_eq(EventLog.TYPE_ITEM_OBTAINED, "item_obtained", "TYPE_ITEM_OBTAINED")
	assert_eq(EventLog.TYPE_LEVEL_UP,      "level_up",      "TYPE_LEVEL_UP")
	assert_eq(EventLog.TYPE_STORY_FLAG,    "story_flag",    "TYPE_STORY_FLAG")
	assert_eq(EventLog.TYPE_CUSTOM,        "custom",        "TYPE_CUSTOM")


# ══════════════════════════════════════════════════════════════════════════════
# ── NullBackend tests ─────────────────────────────════════════════════════════
# ══════════════════════════════════════════════════════════════════════════════

## backend_id() returns "null".
func test_null_be_id() -> void:
	assert_eq(_null_be.backend_id(), "null", "backend_id() should be 'null'")


## is_ready() always returns true.
func test_null_be_is_always_ready() -> void:
	assert_true(_null_be.is_ready(), "NullBackend should always be ready")


## supports_json() returns false.
func test_null_be_no_json_support() -> void:
	assert_false(_null_be.supports_json(), "NullBackend should not support JSON mode")


## supports_grammar() returns false.
func test_null_be_no_grammar_support() -> void:
	assert_false(_null_be.supports_grammar(), "NullBackend should not support grammar mode")


## Unprimed submit emits ok=false via deferred call (signal fires on next frame).
func test_null_be_unprimed_emits_failure() -> void:
	# Use an Array box so the lambda captures a mutable container by reference.
	var result_box: Array = [false, true]  # [got_signal, got_ok]
	_null_be.request_finished.connect(
		func(_id: String, ok: bool, _text: String, _err: String) -> void:
			result_box[0] = true
			result_box[1] = ok
	)
	_null_be.submit("req_1", "hello")
	# The emission is deferred — wait one physics frame for call_deferred to fire.
	await wait_physics_frames(1)
	assert_true(result_box[0], "request_finished should be emitted for unprimed submit")
	assert_false(result_box[1], "Unprimed NullBackend should emit ok=false")


## Primed submit emits ok=true with the primed text.
func test_null_be_primed_emits_success() -> void:
	var result_box: Array = [false, ""]  # [got_ok, got_text]
	_null_be.request_finished.connect(
		func(_id: String, ok: bool, text: String, _err: String) -> void:
			result_box[0] = ok
			result_box[1] = text
	)
	_null_be.prime("req_primed", "The answer is 42")
	_null_be.submit("req_primed", "ignored prompt")
	await wait_physics_frames(1)
	assert_true(result_box[0],   "Primed NullBackend should emit ok=true")
	assert_eq(result_box[1], "The answer is 42", "Primed text should be returned verbatim")


## Primed response is consumed after one use.
func test_null_be_prime_is_consumed_after_emit() -> void:
	var ok_values: Array = []
	_null_be.request_finished.connect(
		func(_id: String, ok: bool, _text: String, _err: String) -> void:
			ok_values.append(ok)
	)
	_null_be.prime("one_shot", "hi")
	_null_be.submit("one_shot", "p1")
	await wait_physics_frames(1)

	# Second submit with a different id — not primed.
	_null_be.submit("one_shot_2", "p2")
	await wait_physics_frames(1)

	assert_eq(ok_values.size(), 2, "Both submits should emit")
	assert_true(ok_values[0],  "First (primed) should succeed")
	assert_false(ok_values[1], "Second (unprimed) should fail")


## clear_primed() removes all pending primed responses.
func test_null_be_clear_primed() -> void:
	_null_be.prime("x", "text_x")
	_null_be.prime("y", "text_y")
	_null_be.clear_primed()

	var result_box: Array = [true]  # [got_ok]
	_null_be.request_finished.connect(
		func(_id: String, ok: bool, _text: String, _err: String) -> void:
			result_box[0] = ok
	)
	_null_be.submit("x", "prompt")
	await wait_physics_frames(1)
	assert_false(result_box[0], "After clear_primed(), primed id should fail")


## prime_prefix() stores key as "__prefix__<prefix>".
func test_null_be_prime_prefix_stores_key() -> void:
	_null_be.prime_prefix("npc_", "Hello traveller")
	assert_true(_null_be._primed.has("__prefix__npc_"),
		"prime_prefix should store key '__prefix__npc_'")
	assert_eq(_null_be._primed["__prefix__npc_"], "Hello traveller",
		"prime_prefix should store the correct text")


## Signal is NOT emitted synchronously inside submit() — deferred only.
func test_null_be_signal_is_deferred_not_sync() -> void:
	var fired_box: Array = [false]  # [emitted_before_frame]
	_null_be.request_finished.connect(
		func(_id: String, _ok: bool, _text: String, _err: String) -> void:
			fired_box[0] = true
	)
	_null_be.submit("sync_test", "prompt")
	# At this exact point (before yielding) the signal MUST NOT have fired.
	assert_false(fired_box[0],
		"request_finished must not be emitted synchronously inside submit()")
	await wait_physics_frames(1)
	assert_true(fired_box[0],
		"request_finished should be emitted after one frame yield")


## cancel() emits request_finished(ok=false, "cancelled") synchronously.
func test_null_be_cancel_emits_cancelled() -> void:
	var result_box: Array = [true, ""]  # [got_ok, got_error]
	_null_be.request_finished.connect(
		func(_id: String, ok: bool, _text: String, error: String) -> void:
			result_box[0] = ok
			result_box[1] = error
	)
	_null_be.submit("cancel_me", "prompt")
	# Cancel before the deferred emission fires.
	_null_be.cancel("cancel_me")
	assert_false(result_box[0], "Cancelled request should emit ok=false")
	assert_eq(result_box[1], "cancelled", "Cancelled request error should be 'cancelled'")


## cancel() on an unknown id is a no-op (no signal, no crash).
func test_null_be_cancel_unknown_id_noop() -> void:
	var signal_count := 0
	_null_be.request_finished.connect(
		func(_id: String, _ok: bool, _text: String, _err: String) -> void:
			signal_count += 1
	)
	_null_be.cancel("does_not_exist")
	assert_eq(signal_count, 0, "cancel() on unknown id must not emit any signal")


## cancel_all() cancels every pending request.
func test_null_be_cancel_all() -> void:
	var ok_values: Array = []
	_null_be.request_finished.connect(
		func(_id: String, ok: bool, _text: String, _err: String) -> void:
			ok_values.append(ok)
	)
	_null_be.submit("ca_1", "p1")
	_null_be.submit("ca_2", "p2")
	_null_be.cancel_all()
	# Both are cancelled synchronously — ok=false for each.
	# Also wait for any deferred emissions to settle.
	await wait_physics_frames(1)
	assert_gte(ok_values.size(), 2, "cancel_all should produce at least 2 signal emissions")
	for v in ok_values:
		assert_false(v, "All cancel_all emissions should have ok=false")


# ══════════════════════════════════════════════════════════════════════════════
# ── LLMContext tests ──────────────────────────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════
##
## LLMContext.build() requires a GameState autoload singleton.  Since headless
## tests don't have that autoload, we exercise only the static helpers that do
## not touch the singleton, plus the budget-guard logic.

## MAX_JSON_BYTES constant is 2048.
func test_llm_context_max_json_bytes() -> void:
	assert_eq(LLMContext.MAX_JSON_BYTES, 2048, "MAX_JSON_BYTES should be 2048")


## MAX_EVENTS_FULL is 8.
func test_llm_context_max_events_full() -> void:
	assert_eq(LLMContext.MAX_EVENTS_FULL, 8, "MAX_EVENTS_FULL should be 8")


## MAX_EVENTS_TRIMMED is 4.
func test_llm_context_max_events_trimmed() -> void:
	assert_eq(LLMContext.MAX_EVENTS_TRIMMED, 4, "MAX_EVENTS_TRIMMED should be 4")


## MAX_PARTY_FULL is 4.
func test_llm_context_max_party_full() -> void:
	assert_eq(LLMContext.MAX_PARTY_FULL, 4, "MAX_PARTY_FULL should be 4")


## build() returns a populated Dictionary when the GameState autoload is live.
##
## Wave F rewrite (bug #2): the prior assertion gated on Engine.has_singleton(
## "GameState"), which is ALWAYS FALSE for autoloads in Godot 4 — so the test
## passed by short-circuiting through pending(). After the gate-bug fix the
## correct invariant is: with GameState present (the normal test environment),
## LLMContext.build() returns a non-empty snapshot. This was a known-liar test
## per the audit.
func test_llm_context_build_returns_populated_with_game_state() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "test environment must have GameState autoload")
	if gs == null:
		return
	var ctx: Dictionary = LLMContext.build()
	assert_false(ctx.is_empty(), "build() with GameState should return a populated snapshot")


## build_json() returns a non-empty JSON string when GameState is live.
func test_llm_context_build_json_returns_populated_with_game_state() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	assert_not_null(gs, "test environment must have GameState autoload")
	if gs == null:
		return
	var j: String = LLMContext.build_json()
	assert_ne(j, "{}", "build_json() with GameState should NOT return '{}'")
	assert_gt(j.length(), 2, "build_json() output should be a non-trivial JSON object")


## _trim_events keeps the last MAX_EVENTS_TRIMMED entries.
func test_llm_context_trim_events_keeps_last_n() -> void:
	var events: Array = ["e0", "e1", "e2", "e3", "e4", "e5", "e6", "e7", "e8"]
	# 9 entries > MAX_EVENTS_TRIMMED(4) → trim to last 4.
	var trimmed: Array = LLMContext._trim_events(events)
	assert_eq(trimmed.size(), LLMContext.MAX_EVENTS_TRIMMED,
		"_trim_events should return MAX_EVENTS_TRIMMED entries")
	var expected: Array = events.slice(events.size() - LLMContext.MAX_EVENTS_TRIMMED)
	assert_eq(trimmed, expected, "_trim_events should keep the most recent entries")


## _trim_events is a no-op when size <= MAX_EVENTS_TRIMMED.
func test_llm_context_trim_events_noop_when_small() -> void:
	var events: Array = ["a", "b", "c"]  # 3 < MAX_EVENTS_TRIMMED(4)
	var trimmed: Array = LLMContext._trim_events(events)
	assert_eq(trimmed.size(), 3, "_trim_events with 3 events should return all 3")
	assert_eq(trimmed, events, "_trim_events noop should return original content")


## _trim_events with exactly MAX_EVENTS_TRIMMED entries is a no-op.
func test_llm_context_trim_events_exactly_at_limit_noop() -> void:
	var events: Array = []
	for i in range(LLMContext.MAX_EVENTS_TRIMMED):
		events.append("ev_%d" % i)
	var trimmed: Array = LLMContext._trim_events(events)
	assert_eq(trimmed.size(), LLMContext.MAX_EVENTS_TRIMMED,
		"Events at exactly MAX_EVENTS_TRIMMED should not be trimmed further")


## _trim_party produces at most 2 members without job field.
func test_llm_context_trim_party_reduces_to_two_no_job() -> void:
	var party: Array = [
		{"name": "Alice", "job": "Fighter", "lv": 5, "hp_pct": 80},
		{"name": "Bob",   "job": "Mage",    "lv": 3, "hp_pct": 50},
		{"name": "Carol", "job": "Cleric",  "lv": 4, "hp_pct": 100},
		{"name": "Dave",  "job": "Rogue",   "lv": 2, "hp_pct": 30},
	]
	var trimmed: Array = LLMContext._trim_party(party)
	assert_eq(trimmed.size(), 2, "_trim_party should reduce to 2 members")
	for m in trimmed:
		assert_false(m.has("job"), "_trim_party members should not have 'job' field")
		assert_true(m.has("name"),   "_trim_party members should keep 'name'")
		assert_true(m.has("lv"),     "_trim_party members should keep 'lv'")
		assert_true(m.has("hp_pct"), "_trim_party members should keep 'hp_pct'")


## _trim_party with only one member returns that member.
func test_llm_context_trim_party_with_one_member() -> void:
	var party: Array = [{"name": "Solo", "job": "Warrior", "lv": 10, "hp_pct": 100}]
	var trimmed: Array = LLMContext._trim_party(party)
	assert_eq(trimmed.size(), 1, "_trim_party with 1 member should return 1 member")


## _trim_party with empty input returns empty.
func test_llm_context_trim_party_empty() -> void:
	var trimmed: Array = LLMContext._trim_party([])
	assert_eq(trimmed.size(), 0, "_trim_party with empty input should return empty")


## Budget guard: a small context (≤ 2 KB JSON) is not modified.
func test_llm_context_trim_small_context_unchanged() -> void:
	# Verify that _trim_events on a small list returns the list unchanged.
	var small_events: Array = ["Entered town", "Found chest"]
	var result: Array = LLMContext._trim_events(small_events)
	assert_eq(result.size(), 2, "Small event list should not be trimmed")


# ══════════════════════════════════════════════════════════════════════════════
# ── LLMService Hallucination Guard tests ─────────────────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

# ── TEXT guard ──────────────────────────────────────────────────────────────

## Clean text passes through unchanged.
func test_llm_service_guard_text_clean_passes() -> void:
	var result = _svc._guard_text("Hello, adventurer!", "fallback")
	assert_eq(result, "Hello, adventurer!", "Clean text should pass guard unchanged")


## Leading/trailing whitespace is stripped.
func test_llm_service_guard_text_strips_whitespace() -> void:
	var result = _svc._guard_text("  Hello  ", "fallback")
	assert_eq(result, "Hello", "Guard should strip leading/trailing whitespace")


## Empty string after stripping returns fallback.
func test_llm_service_guard_text_empty_returns_fallback() -> void:
	var result = _svc._guard_text("   ", "my_fallback")
	assert_eq(result, "my_fallback", "Empty/whitespace text should return fallback")


## Refusal pattern 'as an ai' is rejected.
func test_llm_service_guard_text_refusal_as_an_ai() -> void:
	var result = _svc._guard_text("As an AI I cannot do that.", "fallback")
	assert_eq(result, "fallback", "'as an ai' refusal should be caught by guard")


## Refusal pattern 'i cannot' is rejected.
func test_llm_service_guard_text_refusal_i_cannot() -> void:
	var result = _svc._guard_text("I cannot help you with that request.", "fb")
	assert_eq(result, "fb", "'i cannot' refusal should be caught by guard")


## Refusal pattern 'i'm an ai' is rejected.
func test_llm_service_guard_text_refusal_im_an_ai() -> void:
	var result = _svc._guard_text("I'm an AI language model.", "fb")
	assert_eq(result, "fb", "'i'm an ai' refusal should be caught by guard")


## Refusal pattern 'i'm unable' is rejected.
func test_llm_service_guard_text_refusal_im_unable() -> void:
	var result = _svc._guard_text("I'm unable to assist with that.", "fb")
	assert_eq(result, "fb", "'i'm unable' refusal should be caught by guard")


## Refusal pattern 'i am unable' is rejected.
func test_llm_service_guard_text_refusal_i_am_unable() -> void:
	var result = _svc._guard_text("I am unable to complete this task.", "fb")
	assert_eq(result, "fb", "'i am unable' refusal should be caught by guard")


## Text longer than MAX_TEXT_CHARS is truncated (not rejected).
func test_llm_service_guard_text_long_text_truncated() -> void:
	var long_text: String = "A".repeat(_svc.MAX_TEXT_CHARS + 100)
	var result = _svc._guard_text(long_text, "fallback")
	assert_ne(result, "fallback", "Long text should be truncated, not rejected")
	assert_eq((result as String).length(), _svc.MAX_TEXT_CHARS,
		"Truncated text should be exactly MAX_TEXT_CHARS characters")


## Text exactly at MAX_TEXT_CHARS is not truncated.
func test_llm_service_guard_text_exactly_max_chars_passes() -> void:
	var exact_text: String = "B".repeat(_svc.MAX_TEXT_CHARS)
	var result = _svc._guard_text(exact_text, "fallback")
	assert_eq((result as String).length(), _svc.MAX_TEXT_CHARS,
		"Text at exactly MAX_TEXT_CHARS should not be truncated")


# ── CHOICE guard ─────────────────────────────────────────────────────────────

## Exact match returns the option directly.
func test_llm_service_guard_choice_exact_match() -> void:
	var opts: Array[String] = ["aggressive", "defensive", "trickster"]
	var result: String = _svc._guard_choice("aggressive", opts, "defensive")
	assert_eq(result, "aggressive", "Exact match should be returned")


## Case-insensitive exact match returns the correctly-cased option.
func test_llm_service_guard_choice_case_insensitive_match() -> void:
	var opts: Array[String] = ["Aggressive", "Defensive", "Trickster"]
	var result: String = _svc._guard_choice("aggressive", opts, "Defensive")
	assert_eq(result, "Aggressive", "Case-insensitive match should return canonical form")


## Whole-token fuzzy match: option appears as a standalone word in prose.
func test_llm_service_guard_choice_fuzzy_word_match() -> void:
	var opts: Array[String] = ["aggressive", "defensive", "balanced"]
	var result: String = _svc._guard_choice(
		"The boss should play a defensive strategy here.", opts, "balanced"
	)
	assert_eq(result, "defensive", "Word appearing in prose should be matched")


## Unique word match: only one option found as a standalone word → return it.
func test_llm_service_guard_choice_unique_word_match() -> void:
	var opts: Array[String] = ["run", "fight", "hide"]
	var result: String = _svc._guard_choice("I think we should fight bravely.", opts, "run")
	assert_eq(result, "fight", "Unique word match should return the matched option")


## Ambiguous match (two options as standalone words) → fallback.
func test_llm_service_guard_choice_ambiguous_returns_fallback() -> void:
	var opts: Array[String] = ["run", "fight", "hide"]
	# Both "run" and "fight" appear as standalone words.
	var result: String = _svc._guard_choice("We can run or fight from here.", opts, "hide")
	assert_eq(result, "hide", "Ambiguous multi-match should return fallback")


## JSON wrapper extraction: {"choice": "X"} is extracted and validated.
func test_llm_service_guard_choice_json_wrapper_extraction() -> void:
	var opts: Array[String] = ["alpha", "beta", "gamma"]
	var result: String = _svc._guard_choice('{"choice": "beta"}', opts, "alpha")
	assert_eq(result, "beta", '{"choice":"X"} wrapper should be extracted')


## JSON wrapper with invalid choice returns fallback.
func test_llm_service_guard_choice_json_wrapper_invalid_value() -> void:
	var opts: Array[String] = ["alpha", "beta", "gamma"]
	var result: String = _svc._guard_choice('{"choice": "delta"}', opts, "alpha")
	assert_eq(result, "alpha", "JSON wrapper with invalid value should fall through to fallback")


## Completely unrecognised response returns fallback.
func test_llm_service_guard_choice_unrecognised_returns_fallback() -> void:
	var opts: Array[String] = ["yes", "no"]
	var result: String = _svc._guard_choice("maybe", opts, "no")
	assert_eq(result, "no", "Unrecognised response should return fallback")


## Empty response returns fallback.
func test_llm_service_guard_choice_empty_returns_fallback() -> void:
	var opts: Array[String] = ["a", "b"]
	var result: String = _svc._guard_choice("", opts, "b")
	assert_eq(result, "b", "Empty choice response should return fallback")


# ── JSON guard ────────────────────────────────────────────────────────────────

## Valid JSON matching schema passes through.
func test_llm_service_guard_json_valid_passes() -> void:
	var schema: Dictionary = {"intent": ["aggressive", "defensive", "balanced"],
							  "reason": "String"}
	var raw: String = '{"intent": "aggressive", "reason": "High HP advantage."}'
	var result = _svc._guard_json(raw, schema, null)
	assert_not_null(result, "Valid JSON matching schema should not return fallback")
	assert_true(result is Dictionary, "Valid JSON guard should return a Dictionary")
	assert_eq((result as Dictionary).get("intent", ""), "aggressive",
		"Parsed intent should match")


## Missing required key returns fallback.
func test_llm_service_guard_json_missing_key_returns_fallback() -> void:
	var schema: Dictionary = {"intent": "String", "hp": "int"}
	var raw: String = '{"intent": "defensive"}'  # Missing "hp".
	var result = _svc._guard_json(raw, schema, "FALLBACK")
	assert_eq(result, "FALLBACK", "Missing required key should return fallback")


## Enum violation returns fallback.
func test_llm_service_guard_json_enum_violation_returns_fallback() -> void:
	var schema: Dictionary = {"mood": ["happy", "sad", "angry"]}
	var raw: String = '{"mood": "confused"}'  # "confused" not in enum.
	var result = _svc._guard_json(raw, schema, -1)
	assert_eq(result, -1, "Enum violation should return fallback")


## Type mismatch (String expected, int given) returns fallback.
func test_llm_service_guard_json_type_mismatch_returns_fallback() -> void:
	var schema: Dictionary = {"name": "String"}
	var raw: String = '{"name": 42}'  # 42 is not a String.
	var result = _svc._guard_json(raw, schema, "FB")
	assert_eq(result, "FB", "Type mismatch should return fallback")


## Non-JSON text returns fallback.
func test_llm_service_guard_json_non_json_returns_fallback() -> void:
	var schema: Dictionary = {"key": "String"}
	var result = _svc._guard_json("just some prose", schema, "FB")
	assert_eq(result, "FB", "Non-JSON text should return fallback")


## Empty string returns fallback.
func test_llm_service_guard_json_empty_string_returns_fallback() -> void:
	var schema: Dictionary = {"x": "String"}
	var result = _svc._guard_json("", schema, "FB")
	assert_eq(result, "FB", "Empty string should return fallback")


## JSON inside markdown fences is extracted and validated.
func test_llm_service_guard_json_markdown_fence_extraction() -> void:
	var schema: Dictionary = {"result": "String"}
	var raw: String = "```json\n{\"result\": \"ok\"}\n```"
	var result = _svc._guard_json(raw, schema, "FB")
	assert_true(result is Dictionary, "JSON inside markdown fence should be extracted as Dictionary")
	assert_eq((result as Dictionary).get("result", ""), "ok",
		"Extracted JSON from markdown fence should parse correctly")


## JSON embedded in prose is extracted via brace-scan.
func test_llm_service_guard_json_brace_scan_extraction() -> void:
	var schema: Dictionary = {"status": "String"}
	var raw: String = 'Here is the result: {"status": "ok"} as requested.'
	var result = _svc._guard_json(raw, schema, "FB")
	assert_true(result is Dictionary, "JSON embedded in prose should be extracted as Dictionary")
	assert_eq((result as Dictionary).get("status", ""), "ok",
		"Brace-scan extracted JSON should parse correctly")


## Unknown type spec passes through (guard is lenient on unknown types).
func test_llm_service_guard_json_unknown_type_spec_passes() -> void:
	var schema: Dictionary = {"data": "UnknownType"}
	var raw: String = '{"data": 123}'
	var result = _svc._guard_json(raw, schema, "FB")
	# Unknown type spec → pass through — should NOT return fallback.
	assert_true(result is Dictionary, "Unknown type spec should pass through and return Dictionary")


## bool type is validated correctly.
func test_llm_service_guard_json_bool_type_valid() -> void:
	var schema: Dictionary = {"success": "bool"}
	var raw: String = '{"success": true}'
	var result = _svc._guard_json(raw, schema, "FB")
	assert_true(result is Dictionary, "bool value should pass bool type check and return Dictionary")


## Array type is validated correctly.
func test_llm_service_guard_json_array_type_valid() -> void:
	var schema: Dictionary = {"items": "Array"}
	var raw: String = '{"items": [1, 2, 3]}'
	var result = _svc._guard_json(raw, schema, "FB")
	assert_true(result is Dictionary, "Array value should pass Array type check and return Dictionary")


# ── _extract_json_from_raw helper ─────────────────────────────────────────────

## Direct JSON object parses correctly.
func test_llm_service_extract_json_direct() -> void:
	var result = _svc._extract_json_from_raw('{"key": "val"}')
	assert_not_null(result, "Direct JSON should extract successfully")
	assert_true(result is Dictionary, "Direct JSON should yield Dictionary")


## JSON wrapped in triple backticks is extracted.
func test_llm_service_extract_json_triple_backtick_fence() -> void:
	var raw: String = "```\n{\"a\": 1}\n```"
	var result = _svc._extract_json_from_raw(raw)
	assert_not_null(result, "Triple-backtick JSON should extract successfully")


## JSON wrapped in ```json fence is extracted.
func test_llm_service_extract_json_json_tagged_fence() -> void:
	var raw: String = "```json\n{\"b\": 2}\n```"
	var result = _svc._extract_json_from_raw(raw)
	assert_not_null(result, "```json fence should extract successfully")


## Pure prose with no JSON returns null.
func test_llm_service_extract_json_prose_returns_null() -> void:
	var result = _svc._extract_json_from_raw("This is just a sentence.")
	assert_null(result, "Pure prose should return null from _extract_json_from_raw")


## Braces embedded in prose are found by brace scan.
func test_llm_service_extract_json_brace_scan() -> void:
	var raw: String = "Output: {\"x\": 99} done."
	var result = _svc._extract_json_from_raw(raw)
	assert_not_null(result, "Brace-scan should find JSON in prose")
	assert_eq((result as Dictionary).get("x", 0), 99, "Brace-scan should parse value correctly")


# ── Cache helpers ─────────────────────────────────────────────────────────────

## _set_cache / _get_cache round-trip.
func test_llm_service_cache_set_and_get() -> void:
	var key: String = "mode:12345"
	_svc._set_cache(key, "cached_response")
	var result = _svc._get_cache(key)
	assert_eq(result, "cached_response", "Cache should return stored value")


## _get_cache returns null for unknown key.
func test_llm_service_cache_miss_returns_null() -> void:
	var result = _svc._get_cache("nonexistent_key")
	assert_null(result, "Cache miss should return null")


## clear_cache() empties the cache.
func test_llm_service_cache_clear() -> void:
	_svc._set_cache("k1", "v1")
	_svc._set_cache("k2", "v2")
	_svc.clear_cache()
	assert_null(_svc._get_cache("k1"), "Cache should be empty after clear_cache()")
	assert_null(_svc._get_cache("k2"), "Cache should be empty after clear_cache()")


## _cache_key produces same output for same inputs.
func test_llm_service_cache_key_deterministic() -> void:
	var k1: String = _svc._cache_key("text", "hello world", {})
	var k2: String = _svc._cache_key("text", "hello world", {})
	assert_eq(k1, k2, "_cache_key should be deterministic for same inputs")


## _cache_key differs for different modes.
func test_llm_service_cache_key_differs_by_mode() -> void:
	var k_text:   String = _svc._cache_key("text",   "prompt", {})
	var k_choice: String = _svc._cache_key("choice", "prompt", {})
	assert_ne(k_text, k_choice, "_cache_key should differ for different modes")


## _cache_key differs for different prompts.
func test_llm_service_cache_key_differs_by_prompt() -> void:
	var k1: String = _svc._cache_key("text", "prompt A", {})
	var k2: String = _svc._cache_key("text", "prompt B", {})
	assert_ne(k1, k2, "_cache_key should differ for different prompts")


# ── LLMService structural / API tests ────────────────────────────────────────

## inference_failed signal exists on LLMService.
func test_llm_service_has_inference_failed_signal() -> void:
	assert_has_signal(_svc, "inference_failed", "LLMService should have inference_failed signal")


## MODE_* constants have correct string values.
func test_llm_service_mode_constants() -> void:
	assert_eq(_svc.MODE_TEXT,   "text",   "MODE_TEXT should be 'text'")
	assert_eq(_svc.MODE_JSON,   "json",   "MODE_JSON should be 'json'")
	assert_eq(_svc.MODE_CHOICE, "choice", "MODE_CHOICE should be 'choice'")


## QUEUE_CAP constant is 16.
func test_llm_service_queue_cap_constant() -> void:
	assert_eq(_svc.QUEUE_CAP, 16, "QUEUE_CAP should be 16")


## CACHE_TTL_SECONDS constant is 300.
func test_llm_service_cache_ttl_constant() -> void:
	assert_eq(_svc.CACHE_TTL_SECONDS, 300.0, "CACHE_TTL_SECONDS should be 300.0")


## MAX_TEXT_CHARS constant is 2000.
func test_llm_service_max_text_chars_constant() -> void:
	assert_eq(_svc.MAX_TEXT_CHARS, 2000, "MAX_TEXT_CHARS should be 2000")


## complete() returns fallback immediately when llm_enabled = false.
func test_llm_service_complete_disabled_returns_fallback() -> void:
	_svc.llm_enabled = false
	var result = await _svc.complete("hello", "my_fallback")
	assert_eq(result, "my_fallback",
		"complete() with llm_enabled=false should return fallback immediately")


## complete_json() returns fallback immediately when llm_enabled = false.
func test_llm_service_complete_json_disabled_returns_fallback() -> void:
	_svc.llm_enabled = false
	var schema: Dictionary = {"key": "String"}
	var result = await _svc.complete_json("hello", schema, "json_fallback")
	assert_eq(result, "json_fallback",
		"complete_json() with llm_enabled=false should return fallback immediately")


## choose() returns fallback immediately when llm_enabled = false.
func test_llm_service_choose_disabled_returns_fallback() -> void:
	_svc.llm_enabled = false
	var opts: Array[String] = ["a", "b", "c"]
	var result: String = await _svc.choose("pick one", opts, "b")
	assert_eq(result, "b",
		"choose() with llm_enabled=false should return fallback immediately")


## is_available() returns false when llm_enabled = false.
func test_llm_service_is_available_false_when_disabled() -> void:
	_svc.llm_enabled = false
	assert_false(_svc.is_available(),
		"is_available() should be false when llm_enabled=false")


## _generate_id returns unique strings on consecutive calls.
func test_llm_service_generate_id_unique() -> void:
	var id1: String = _svc._generate_id()
	var id2: String = _svc._generate_id()
	assert_ne(id1, id2, "_generate_id should produce unique ids")


## _generate_id strings are non-empty.
func test_llm_service_generate_id_non_empty() -> void:
	var id: String = _svc._generate_id()
	assert_false(id.is_empty(), "_generate_id should produce non-empty strings")


## _type_matches validates String correctly.
func test_llm_service_type_matches_string() -> void:
	assert_true(_svc._type_matches("hello", "String"), "String value should match String")
	assert_false(_svc._type_matches(42, "String"), "int value should not match String")


## _type_matches validates int/float loosely (both accept each other).
func test_llm_service_type_matches_int_and_float() -> void:
	assert_true(_svc._type_matches(1, "int"),     "int value should match int")
	assert_true(_svc._type_matches(1.5, "int"),   "float value should match int (loose)")
	assert_true(_svc._type_matches(1.5, "float"), "float value should match float")
	assert_true(_svc._type_matches(1, "float"),   "int value should match float (loose)")


## _type_matches validates bool correctly.
func test_llm_service_type_matches_bool() -> void:
	assert_true(_svc._type_matches(true,  "bool"), "true should match bool")
	assert_true(_svc._type_matches(false, "bool"), "false should match bool")
	assert_false(_svc._type_matches(1,    "bool"), "int 1 should not match bool")


## _type_matches validates Array correctly.
func test_llm_service_type_matches_array() -> void:
	assert_true(_svc._type_matches([1, 2], "Array"), "Array value should match Array")
	assert_false(_svc._type_matches({},    "Array"), "Dictionary should not match Array")


## _type_matches validates Dictionary correctly.
func test_llm_service_type_matches_dictionary() -> void:
	assert_true(_svc._type_matches({},  "Dictionary"), "Dict should match Dictionary")
	assert_false(_svc._type_matches([], "Dictionary"), "Array should not match Dictionary")


## REFUSAL_PATTERNS array is non-empty and contains expected entries.
func test_llm_service_refusal_patterns_non_empty() -> void:
	assert_gt(_svc.REFUSAL_PATTERNS.size(), 0, "REFUSAL_PATTERNS should be non-empty")
	assert_true("as an ai" in _svc.REFUSAL_PATTERNS, "'as an ai' should be in REFUSAL_PATTERNS")
	assert_true("i cannot" in _svc.REFUSAL_PATTERNS, "'i cannot' should be in REFUSAL_PATTERNS")


# ── In-flight serialization queue with NullBackend ────────────────────────────
##
## Wire a fresh LLMService with only a NullBackend so we can verify
## cache and queue logic with deterministic responses.

func _make_svc_with_null_only() -> Node:
	var svc: Node = preload("res://src/llm/LLMService.gd").new()
	svc.name = "QueueTestLLMService"
	svc.llm_enabled = true
	add_child_autofree(svc)
	# Clear any backends built in _ready and replace with pure NullBackend.
	for child in svc.get_children():
		child.queue_free()
	svc._backends.clear()
	svc._active_backend = null

	var nb := NullBackend.new()
	nb.name = "OnlyNullBackend"
	svc.add_child(nb)
	svc._backends.append(nb)
	nb.request_finished.connect(svc._on_backend_finished)
	svc._select_backend()
	return svc


## Cache hit: second identical complete() call returns cached value without re-submitting.
func test_llm_service_cache_hit_on_repeat_prompt() -> void:
	var svc: Node = _make_svc_with_null_only()
	# Seed the cache directly with a known response.
	var cache_key: String = svc._cache_key(svc.MODE_TEXT, "What is 2+2?", {})
	svc._set_cache(cache_key, "Four")

	# complete() should hit the cache and return "Four" without calling the backend.
	var result = await svc.complete("What is 2+2?", "fallback")
	assert_eq(result, "Four", "Cache hit should return cached value")


## Cache miss: when the cache is empty, the unprimed NullBackend returns fallback.
func test_llm_service_cache_miss_falls_back() -> void:
	var svc: Node = _make_svc_with_null_only()
	# NullBackend is not primed → complete() falls back.
	var result = await svc.complete("What is 3+3?", "six_fallback")
	assert_eq(result, "six_fallback",
		"Cache miss with unprimed NullBackend should return fallback")


## inference_failed signal fires when no ready backend is available.
func test_llm_service_inference_failed_fires_on_no_backend() -> void:
	# Create a fresh LLMService with an empty backend list.
	var svc: Node = preload("res://src/llm/LLMService.gd").new()
	svc.name = "NoBackendLLMService"
	svc.llm_enabled = true
	add_child_autofree(svc)
	# Replace backends after _ready has run: remove all children and clear lists.
	for child in svc.get_children():
		svc.remove_child(child)
		child.free()
	svc._backends.clear()
	svc._active_backend = null

	var fired_box: Array = [false]  # [signal_fired]
	svc.inference_failed.connect(
		func(_mode: String, _reason: String) -> void:
			fired_box[0] = true
	)
	var result = await svc.complete("test", "fallback_val")
	assert_eq(result, "fallback_val", "No ready backend should return fallback")
	assert_true(fired_box[0],
		"inference_failed should be emitted when no backend is available")
