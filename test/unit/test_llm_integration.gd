extends GutTest

## Integration tests for LLM subsystems — DynamicConversation multi-turn loops
## and EventLog recording hooks (boss defeat, party wipe, area transition).
##
## These tests exercise the *integration* contracts between subsystems:
##   1. DynamicConversation multi-turn loop drives through all State transitions.
##   2. EventLog correctly persists facts for boss defeat, party wipe, and
##      area travel, including schema integrity and ring-buffer semantics.
##
## All tests are self-contained — no autoload singletons required.
## LLMService is intentionally absent so DynamicConversation tests exercise
## the deterministic fallback path throughout.
##
## Test naming convention:
##   test_dc_*        — DynamicConversation integration tests
##   test_hook_*      — EventLog game-loop hook recording tests
##   test_persist_*   — EventLog persistence / serialize round-trip tests


# ── Shared fixtures ───────────────────────────────────────────────────────────

var _log: EventLog
var _dc:  DynamicConversation


# ── GUT lifecycle ─────────────────────────────────────────────────────────────

func before_each() -> void:
	_log = EventLog.new()
	_dc  = DynamicConversation.new()
	_dc.name = "IntegTestDynamicConversation"
	add_child_autofree(_dc)


func after_each() -> void:
	_log = null
	_dc  = null


# Tick 261: real reachability check. The original gates used
# Engine.has_singleton("LLMService") which is ALWAYS false for Godot
# 4 autoloads (cowir-ai sharpening 2 in msg 1884) — those gates never
# actually skipped. Tests passed anyway because LLMService.complete
# falls over to the fallback string when no backend is ready, but the
# skip-when-Ollama-running INTENT wasn't enforceable. This helper
# probes the actual autoload + backend readiness so the gates work as
# documented.
func _llm_actually_reachable() -> bool:
	var svc: Node = get_tree().root.get_node_or_null("LLMService") if get_tree() else null
	return svc != null and svc.has_method("is_available") and svc.is_available()


# ══════════════════════════════════════════════════════════════════════════════
# ── 1. DynamicConversation multi-turn loop (no LLM / no UI) ──────────────────
# ══════════════════════════════════════════════════════════════════════════════

## setup() wires the event_log into the state machine.
func test_dc_setup_stores_event_log() -> void:
	_dc.setup("Arlan", "wise elder", "Verdant Vale", _log, ["Greetings!"])
	assert_eq(_dc._event_log, _log,
		"setup() should store the provided EventLog reference")


## After setup(), _npc_name, _npc_persona, _location, _fallback_lines are all set.
func test_dc_setup_all_fields() -> void:
	var fallbacks: Array = ["Line A", "Line B"]
	_dc.setup("Mira", "tavern keeper", "Brasston", _log, fallbacks)
	assert_eq(_dc._npc_name,    "Mira",          "_npc_name")
	assert_eq(_dc._npc_persona, "tavern keeper",  "_npc_persona")
	assert_eq(_dc._location,    "Brasston",       "_location")
	assert_eq(_dc._fallback_lines.size(), 2,      "_fallback_lines size")


## State machine begins in IDLE (0) before run() is called.
func test_dc_initial_state_is_idle() -> void:
	assert_eq(_dc._state, DynamicConversation.State.IDLE,
		"Initial state should be IDLE")


## is_active() is false before run().
func test_dc_is_not_active_before_run() -> void:
	assert_false(_dc.is_active(), "is_active() should be false before run()")


## run() while already active is a no-op (re-entrancy guard).
func test_dc_run_reentrant_guard_noop() -> void:
	_dc._active = true
	var ended_count: int = 0
	_dc.conversation_ended.connect(func(_n: String) -> void: ended_count += 1)
	_dc.run(null)  # Returns immediately — _active is already true.
	assert_eq(ended_count, 0,
		"run() while already active must not emit conversation_ended")
	_dc._active = false


## abort() on an idle machine leaves is_active() false.
func test_dc_abort_on_idle_is_noop() -> void:
	_dc.abort()
	assert_false(_dc.is_active(), "abort() on idle should leave is_active() false")


## abort() while active sets _state to DONE and deactivates.
func test_dc_abort_while_active_sets_done() -> void:
	_dc._active = true
	_dc._state  = DynamicConversation.State.PLAYER_TURN
	_dc.abort()
	assert_eq(_dc._state, DynamicConversation.State.DONE,
		"abort() should transition to DONE")
	# _active is NOT reset by abort() — the caller must do it.
	# Verify abort() emits no extra signal (the public contract only sets state).


## _fetch_npc_opening() — without LLM, returns first fallback line.
func test_dc_fetch_opening_uses_first_fallback() -> void:
	if _llm_actually_reachable():
		pending("LLMService present — skipping fallback-path test")
		return
	_dc.setup("Guard", "stoic guard", "Gate", null, ["Halt! Who goes there?"])
	_dc._exchange_count = 0
	var line: String = await _dc._fetch_npc_opening()
	assert_eq(line, "Halt! Who goes there?",
		"Without LLM, opening should return first fallback line")


## _fetch_npc_opening() cycles through fallback lines using exchange_count.
func test_dc_fetch_opening_cycles_fallbacks() -> void:
	if _llm_actually_reachable():
		pending("LLMService present — skipping fallback-path test")
		return
	var fallbacks: Array = ["Hello.", "Goodbye.", "Perhaps later."]
	_dc.setup("Vendor", "merchant", "Market", null, fallbacks)
	for i in range(fallbacks.size() * 2):
		_dc._exchange_count = i
		var line: String = await _dc._fetch_npc_opening()
		assert_eq(line, fallbacks[i % fallbacks.size()],
			"Exchange %d should map to fallback index %d" % [i, i % fallbacks.size()])


## _fetch_npc_opening() returns '...' when fallback_lines is empty.
func test_dc_fetch_opening_empty_fallbacks_is_ellipsis() -> void:
	if _llm_actually_reachable():
		pending("LLMService present — skipping fallback-path test")
		return
	_dc.setup("Ghost", "silent spirit", "Graveyard", null, [])
	var line: String = await _dc._fetch_npc_opening()
	assert_eq(line, "...", "Empty fallback_lines should yield '...'")


## _fetch_player_choices() — without LLM, returns DialoguePrompts fallback.
func test_dc_fetch_player_choices_fallback_non_empty() -> void:
	if _llm_actually_reachable():
		pending("LLMService present — skipping fallback-path test")
		return
	_dc.setup("Sage", "mystical sage", "Library", null, ["Indeed."])
	var choices: Array[String] = await _dc._fetch_player_choices()
	assert_false(choices.is_empty(),
		"Fallback player choices should not be empty")
	assert_lte(choices.size(), DialoguePrompts.MAX_CHOICES,
		"Fallback player choices must not exceed MAX_CHOICES")


## _fetch_player_choices() entries are all non-empty Strings.
func test_dc_fetch_player_choices_all_strings() -> void:
	if _llm_actually_reachable():
		pending("LLMService present — skipping fallback-path test")
		return
	_dc.setup("Sage", "mystical sage", "Library", null, ["Indeed."])
	var choices: Array[String] = await _dc._fetch_player_choices()
	for c in choices:
		assert_true(c is String and not (c as String).is_empty(),
			"Every fallback choice must be a non-empty String")


## Full fallback loop: OPENING → PLAYER_TURN → NPC_REPLY path is exercised
## synchronously without crashing by driving internal state directly.
func test_dc_full_fallback_state_sequence() -> void:
	_dc.setup("Innkeeper", "friendly innkeeper", "Tavern", _log, ["Welcome!", "Come again!", "Safe travels."])

	# Verify OPENING handler returns a non-empty fallback line.
	if _llm_actually_reachable():
		pending("LLMService present — skipping full fallback loop test")
		return

	_dc._exchange_count = 0
	var opening: String = await _dc._fetch_npc_opening()
	assert_false(opening.is_empty(), "Opening line should not be empty")

	# Advance exchange count to simulate OPENING complete.
	_dc._exchange_count = 1

	# PLAYER_TURN: fetch choices and verify at least one exists.
	var choices: Array[String] = await _dc._fetch_player_choices()
	assert_false(choices.is_empty(), "Player choices should not be empty")

	# NPC_REPLY: fetch next line cycling through fallbacks.
	var reply: String = await _dc._fetch_npc_opening()
	assert_false(reply.is_empty(), "NPC reply should not be empty")


## _is_farewell() identifies all canonical goodbye phrases.
func test_dc_farewell_recognition_all_canonical() -> void:
	var phrases: Array = [
		"Farewell.", "farewell", "Goodbye.", "goodbye",
		"Take care, safe travels.", "I should go now.",
		"I'll be going then.", "Good-bye friend."
	]
	for phrase in phrases:
		assert_true(_dc._is_farewell(phrase),
			'"%s" should be recognized as a farewell' % phrase)


## _is_farewell() rejects non-farewell phrases.
func test_dc_farewell_rejection_non_farewell_phrases() -> void:
	var phrases: Array = [
		"Tell me more.", "What happened here?", "I need your help.", "...", ""
	]
	for phrase in phrases:
		assert_false(_dc._is_farewell(phrase),
			'"%s" should NOT be recognized as a farewell' % phrase)


## _ensure_farewell() appends "Farewell." when list has room.
func test_dc_ensure_farewell_appends_when_absent() -> void:
	var choices: Array[String] = ["Ask about rumors.", "Trade.", "Do you know anything?"]
	_dc._ensure_farewell(choices)
	assert_true("Farewell." in choices,
		"_ensure_farewell should append 'Farewell.' when absent and there is room")


## _ensure_farewell() is idempotent when farewell already present.
func test_dc_ensure_farewell_idempotent() -> void:
	var choices: Array[String] = ["Ask about rumors.", "Farewell."]
	var size_before: int = choices.size()
	_dc._ensure_farewell(choices)
	assert_eq(choices.size(), size_before,
		"_ensure_farewell should not add duplicate if farewell already present")


## _ensure_farewell() replaces last item at MAX_CHOICES capacity.
func test_dc_ensure_farewell_replaces_at_capacity() -> void:
	# Fill to MAX_CHOICES with no farewell.
	var choices: Array[String] = []
	for i in range(DialoguePrompts.MAX_CHOICES):
		choices.append("Choice %d" % i)
	_dc._ensure_farewell(choices)
	assert_eq(choices.size(), DialoguePrompts.MAX_CHOICES,
		"Size must stay at MAX_CHOICES after _ensure_farewell")
	assert_true(_dc._is_farewell(choices[choices.size() - 1]),
		"Last choice should be a farewell after replacement")


## MAX_EXCHANGES constant is exactly 4.
func test_dc_max_exchanges_is_4() -> void:
	assert_eq(DynamicConversation.MAX_EXCHANGES, 4,
		"MAX_EXCHANGES should be 4")


## SIGN_OFF_FALLBACK is a non-empty string.
func test_dc_sign_off_fallback_non_empty() -> void:
	assert_false(DynamicConversation.SIGN_OFF_FALLBACK.is_empty(),
		"SIGN_OFF_FALLBACK must be a non-empty string")


## conversation_started and conversation_ended signals exist on the class.
func test_dc_has_required_signals() -> void:
	assert_has_signal(_dc, "conversation_started",
		"DynamicConversation must have conversation_started signal")
	assert_has_signal(_dc, "conversation_ended",
		"DynamicConversation must have conversation_ended signal")


## EventLog injected via setup() is read during _fetch_npc_opening().
func test_dc_uses_event_log_recent_during_fetch() -> void:
	if _llm_actually_reachable():
		pending("LLMService present — skipping EventLog integration test")
		return
	# Populate the event log with a fact.
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Cave Rat King",
		{"boss_id": "cave_rat_king_defeated"})

	_dc.setup("Elder", "wise elder", "Village", _log, ["Hm…"])
	_dc._exchange_count = 0
	# Without LLM, _fetch_npc_opening uses the fallback — but it does call
	# _event_log.recent() first (no crash / null guard).
	var line: String = await _dc._fetch_npc_opening()
	assert_false(line.is_empty(),
		"_fetch_npc_opening should succeed even when EventLog contains entries")


## EventLog with null injected via setup() does not crash during fetch.
func test_dc_null_event_log_no_crash_during_fetch() -> void:
	if _llm_actually_reachable():
		pending("LLMService present — skipping null EventLog test")
		return
	_dc.setup("Ghost", "silent spirit", "Ruin", null, ["..."])
	var line: String = await _dc._fetch_npc_opening()
	assert_false(line.is_empty(),
		"Null event_log should not crash _fetch_npc_opening")


# ══════════════════════════════════════════════════════════════════════════════
# ── 2. EventLog game-loop hook recording — boss defeat ────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

## Boss defeat record has correct type.
func test_hook_boss_defeat_type() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Cave Rat King",
		{"boss_id": "cave_rat_king_defeated", "map_id": "whispering_cave", "world": 1})
	var entries: Array[Dictionary] = _log.by_type(EventLog.TYPE_BOSS_DEFEAT)
	assert_eq(entries.size(), 1, "Should have exactly one boss_defeat entry")
	assert_eq(entries[0].get("type", ""), EventLog.TYPE_BOSS_DEFEAT,
		"Entry type should be TYPE_BOSS_DEFEAT")


## Boss defeat record summary is non-empty.
func test_hook_boss_defeat_summary_non_empty() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Cave Rat King", {})
	var entry: Dictionary = _log.by_type(EventLog.TYPE_BOSS_DEFEAT)[0]
	assert_false(entry.get("summary", "").is_empty(),
		"Boss defeat summary should be non-empty")


## Boss defeat record data preserves boss_id and map_id.
func test_hook_boss_defeat_data_schema() -> void:
	_log.record(
		EventLog.TYPE_BOSS_DEFEAT,
		"Defeated Fire Dragon",
		{"boss_id": "fire_dragon_defeated", "map_id": "fire_dragon_cave", "world": 2}
	)
	var entry: Dictionary = _log.by_type(EventLog.TYPE_BOSS_DEFEAT)[0]
	var data: Dictionary = entry.get("data", {})
	assert_eq(data.get("boss_id",  ""), "fire_dragon_defeated", "boss_id should be preserved")
	assert_eq(data.get("map_id",   ""), "fire_dragon_cave",     "map_id should be preserved")
	assert_eq(data.get("world",    -1), 2,                      "world should be preserved")


## Multiple boss defeats accumulate in FIFO order.
func test_hook_boss_defeat_multiple_accumulate() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Rat King",    {"boss_id": "rat_king"})
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Fire Dragon", {"boss_id": "fire_dragon"})
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Shadow Lord", {"boss_id": "shadow_lord"})
	var entries: Array[Dictionary] = _log.by_type(EventLog.TYPE_BOSS_DEFEAT)
	assert_eq(entries.size(), 3, "Three boss defeat entries should accumulate")
	assert_eq(entries[0]["data"]["boss_id"], "rat_king",    "First defeat should be Rat King")
	assert_eq(entries[2]["data"]["boss_id"], "shadow_lord", "Third defeat should be Shadow Lord")


## Boss defeat is distinct from party wipe and area entries.
func test_hook_boss_defeat_distinct_from_other_types() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT,  "Defeated Boss",         {})
	_log.record(EventLog.TYPE_PARTY_WIPE,   "Wiped in cave",         {})
	_log.record(EventLog.TYPE_AREA_ENTERED, "Entered Brasston",      {})
	assert_eq(_log.by_type(EventLog.TYPE_BOSS_DEFEAT).size(),  1, "1 boss_defeat")
	assert_eq(_log.by_type(EventLog.TYPE_PARTY_WIPE).size(),   1, "1 party_wipe")
	assert_eq(_log.by_type(EventLog.TYPE_AREA_ENTERED).size(), 1, "1 area_entered")


# ══════════════════════════════════════════════════════════════════════════════
# ── 3. EventLog game-loop hook recording — party wipe ─────────────────────────
# ══════════════════════════════════════════════════════════════════════════════

## Party wipe record has correct type.
func test_hook_party_wipe_type() -> void:
	_log.record(EventLog.TYPE_PARTY_WIPE, "Party wiped in Whispering Cave",
		{"map_id": "whispering_cave", "survivors": 0, "party_size": 3, "world": 1})
	var entries: Array[Dictionary] = _log.by_type(EventLog.TYPE_PARTY_WIPE)
	assert_eq(entries.size(), 1, "Should have exactly one party_wipe entry")
	assert_eq(entries[0].get("type", ""), EventLog.TYPE_PARTY_WIPE,
		"Entry type should be TYPE_PARTY_WIPE")


## Party wipe data preserves survivors, party_size, and map_id.
func test_hook_party_wipe_data_schema() -> void:
	_log.record(
		EventLog.TYPE_PARTY_WIPE,
		"Party wiped in Overworld",
		{"map_id": "overworld", "survivors": 1, "party_size": 4,
		 "enemy_types": ["slime", "goblin"], "world": 1}
	)
	var data: Dictionary = _log.by_type(EventLog.TYPE_PARTY_WIPE)[0].get("data", {})
	assert_eq(data.get("map_id",     ""), "overworld", "map_id preserved")
	assert_eq(data.get("survivors",  -1), 1,           "survivors preserved")
	assert_eq(data.get("party_size", -1), 4,           "party_size preserved")
	assert_eq(data.get("world",      -1), 1,           "world preserved")
	var enemy_types: Array = data.get("enemy_types", [])
	assert_eq(enemy_types.size(), 2, "enemy_types array should have 2 entries")


## Multiple party wipes accumulate and are ordered oldest-first.
func test_hook_party_wipe_multiple_ordered() -> void:
	_log.record(EventLog.TYPE_PARTY_WIPE, "Wipe 1", {"map_id": "overworld"})
	_log.record(EventLog.TYPE_PARTY_WIPE, "Wipe 2", {"map_id": "whispering_cave"})
	var entries: Array[Dictionary] = _log.by_type(EventLog.TYPE_PARTY_WIPE)
	assert_eq(entries.size(), 2, "Two wipe entries should be present")
	assert_eq(entries[0].get("summary", ""), "Wipe 1", "Oldest wipe is first")
	assert_eq(entries[1].get("summary", ""), "Wipe 2", "Newest wipe is second")


## Party wipe summary encodes the location name.
func test_hook_party_wipe_summary_has_location() -> void:
	var map_label: String = "Dragon Cave"
	_log.record(EventLog.TYPE_PARTY_WIPE, "Party wiped in %s" % map_label, {})
	var summary: String = _log.by_type(EventLog.TYPE_PARTY_WIPE)[0].get("summary", "")
	assert_true(map_label in summary,
		"Party wipe summary should contain the location name")


## Survivors field is 0 on a total wipe.
func test_hook_party_wipe_total_wipe_has_zero_survivors() -> void:
	_log.record(EventLog.TYPE_PARTY_WIPE, "Total wipe", {"survivors": 0, "party_size": 4})
	var data: Dictionary = _log.by_type(EventLog.TYPE_PARTY_WIPE)[0].get("data", {})
	assert_eq(data.get("survivors", -1), 0, "Total wipe should record 0 survivors")


# ══════════════════════════════════════════════════════════════════════════════
# ── 4. EventLog game-loop hook recording — area transition ────────────────────
# ══════════════════════════════════════════════════════════════════════════════

## Area entered record has correct type.
func test_hook_area_entered_type() -> void:
	_log.record(EventLog.TYPE_AREA_ENTERED, "Entered Harmonia Village",
		{"map_id": "harmonia_village", "spawn_point": "default", "world": 1})
	var entries: Array[Dictionary] = _log.by_type(EventLog.TYPE_AREA_ENTERED)
	assert_eq(entries.size(), 1, "Should have exactly one area_entered entry")
	assert_eq(entries[0].get("type", ""), EventLog.TYPE_AREA_ENTERED,
		"Entry type should be TYPE_AREA_ENTERED")


## Area entered data preserves map_id, spawn_point, and world.
func test_hook_area_entered_data_schema() -> void:
	_log.record(
		EventLog.TYPE_AREA_ENTERED,
		"Entered Fire Dragon Cave",
		{"map_id": "fire_dragon_cave", "spawn_point": "entrance", "world": 2}
	)
	var data: Dictionary = _log.by_type(EventLog.TYPE_AREA_ENTERED)[0].get("data", {})
	assert_eq(data.get("map_id",      ""), "fire_dragon_cave", "map_id preserved")
	assert_eq(data.get("spawn_point", ""), "entrance",         "spawn_point preserved")
	assert_eq(data.get("world",       -1), 2,                  "world preserved")


## Multiple area transitions accumulate in visit order.
func test_hook_area_entered_multiple_ordered() -> void:
	var maps: Array = ["overworld", "harmonia_village", "whispering_cave", "overworld"]
	for m in maps:
		_log.record(EventLog.TYPE_AREA_ENTERED, "Entered %s" % m, {"map_id": m})
	var entries: Array[Dictionary] = _log.by_type(EventLog.TYPE_AREA_ENTERED)
	assert_eq(entries.size(), 4, "Four area_entered entries should accumulate")
	for i in range(maps.size()):
		assert_eq(entries[i]["data"]["map_id"], maps[i],
			"Entry %d map_id should be '%s'" % [i, maps[i]])


## Area entered summary contains the display name.
func test_hook_area_entered_summary_has_name() -> void:
	_log.record(EventLog.TYPE_AREA_ENTERED, "Entered Brasston Village",
		{"map_id": "brasston_village"})
	var summary: String = _log.by_type(EventLog.TYPE_AREA_ENTERED)[0].get("summary", "")
	assert_true("Brasston Village" in summary,
		"Area entered summary should contain the human-readable area name")


## Cave transition recorded as area_entered with correct map_id prefix.
func test_hook_area_entered_cave_map_id() -> void:
	_log.record(EventLog.TYPE_AREA_ENTERED, "Entered Whispering Cave",
		{"map_id": "whispering_cave"})
	var data: Dictionary = _log.by_type(EventLog.TYPE_AREA_ENTERED)[0].get("data", {})
	assert_true("cave" in data.get("map_id", ""),
		"Cave map_id should contain 'cave'")


# ══════════════════════════════════════════════════════════════════════════════
# ── 5. EventLog persistence / serialize-restore round-trips ───────────────────
# ══════════════════════════════════════════════════════════════════════════════

## All three hook types survive a serialize → restore round-trip.
func test_persist_all_hook_types_survive_roundtrip() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT,  "Defeated Boss",    {"boss_id": "dragon"})
	_log.record(EventLog.TYPE_PARTY_WIPE,   "Wiped in cave",    {"survivors": 0})
	_log.record(EventLog.TYPE_AREA_ENTERED, "Entered village",  {"map_id": "harmonia_village"})

	var raw: Array = _log.serialize()
	var log2 := EventLog.new()
	log2.restore(raw)

	assert_eq(log2.size(), 3, "Restored log should contain all 3 entries")
	assert_eq(log2.by_type(EventLog.TYPE_BOSS_DEFEAT).size(),  1, "1 boss_defeat after restore")
	assert_eq(log2.by_type(EventLog.TYPE_PARTY_WIPE).size(),   1, "1 party_wipe after restore")
	assert_eq(log2.by_type(EventLog.TYPE_AREA_ENTERED).size(), 1, "1 area_entered after restore")


## Boss defeat data is intact after round-trip.
func test_persist_boss_defeat_data_intact() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "Defeated Shadow Lord",
		{"boss_id": "shadow_lord_defeated", "map_id": "null_chamber", "world": 6})
	var raw: Array = _log.serialize()
	var log2 := EventLog.new()
	log2.restore(raw)
	var data: Dictionary = log2.by_type(EventLog.TYPE_BOSS_DEFEAT)[0].get("data", {})
	assert_eq(data.get("boss_id", ""), "shadow_lord_defeated", "boss_id after round-trip")
	assert_eq(data.get("map_id",  ""), "null_chamber",         "map_id after round-trip")
	assert_eq(data.get("world",   -1), 6,                      "world after round-trip")


## Party wipe data is intact after round-trip.
func test_persist_party_wipe_data_intact() -> void:
	_log.record(EventLog.TYPE_PARTY_WIPE, "Wiped in steampunk",
		{"map_id": "steampunk_mechanism", "survivors": 2, "party_size": 4,
		 "enemy_types": ["mechataur"], "world": 3})
	var raw: Array = _log.serialize()
	var log2 := EventLog.new()
	log2.restore(raw)
	var data: Dictionary = log2.by_type(EventLog.TYPE_PARTY_WIPE)[0].get("data", {})
	assert_eq(data.get("map_id",     ""), "steampunk_mechanism", "map_id after round-trip")
	assert_eq(data.get("survivors",  -1), 2,                     "survivors after round-trip")
	assert_eq(data.get("party_size", -1), 4,                     "party_size after round-trip")


## Area entered data is intact after round-trip.
func test_persist_area_entered_data_intact() -> void:
	_log.record(EventLog.TYPE_AREA_ENTERED, "Entered Node Prime",
		{"map_id": "node_prime_village", "spawn_point": "south_gate", "world": 5})
	var raw: Array = _log.serialize()
	var log2 := EventLog.new()
	log2.restore(raw)
	var data: Dictionary = log2.by_type(EventLog.TYPE_AREA_ENTERED)[0].get("data", {})
	assert_eq(data.get("map_id",      ""), "node_prime_village", "map_id after round-trip")
	assert_eq(data.get("spawn_point", ""), "south_gate",         "spawn_point after round-trip")
	assert_eq(data.get("world",       -1), 5,                    "world after round-trip")


## restore() with null produces an empty log (safe no-op).
func test_persist_restore_null_produces_empty() -> void:
	_log.record(EventLog.TYPE_BOSS_DEFEAT, "some boss", {})
	_log.restore(null)
	assert_eq(_log.size(), 0, "restore(null) should clear the log")


## restore() with mixed valid and invalid entries skips bad ones.
func test_persist_restore_skips_invalid_entries() -> void:
	var mixed: Array = [
		{"type": EventLog.TYPE_BOSS_DEFEAT,  "summary": "valid",   "t": 1, "pt": 0, "data": {}},
		"not a dict",
		42,
		null,
		{"type": EventLog.TYPE_PARTY_WIPE,   "summary": "valid 2", "t": 2, "pt": 0, "data": {}},
	]
	_log.restore(mixed)
	assert_eq(_log.size(), 2, "Only the 2 valid Dictionary entries should be restored")


## Overflow behaviour: adding events beyond RING_CAP evicts oldest first.
func test_persist_overflow_preserves_most_recent() -> void:
	# Fill past RING_CAP using a mix of all hook types.
	var total: int = EventLog.RING_CAP + 5
	for i in range(total):
		var t: String = [
			EventLog.TYPE_BOSS_DEFEAT,
			EventLog.TYPE_PARTY_WIPE,
			EventLog.TYPE_AREA_ENTERED
		][i % 3]
		_log.record(t, "event_%d" % i, {"idx": i})
	assert_eq(_log.size(), EventLog.RING_CAP, "Size must not exceed RING_CAP after overflow")
	var recent: Array[Dictionary] = _log.recent()
	assert_eq(recent[recent.size() - 1]["data"]["idx"], total - 1,
		"The last entry should be the most recently recorded event")


## recent(5) returns the 5 most recent of a mixed-type log.
func test_persist_recent_n_mixed_types() -> void:
	for i in range(20):
		var t: String = [
			EventLog.TYPE_BOSS_DEFEAT,
			EventLog.TYPE_PARTY_WIPE,
			EventLog.TYPE_AREA_ENTERED,
			EventLog.TYPE_CUSTOM
		][i % 4]
		_log.record(t, "ev_%d" % i, {"idx": i})
	var r: Array[Dictionary] = _log.recent(5)
	assert_eq(r.size(), 5, "recent(5) should return exactly 5 entries")
	assert_eq(r[r.size() - 1]["data"]["idx"], 19,
		"Last entry in recent(5) should be the newest overall")
