extends GutTest

## Wave F — GameState.event_log save/restore roundtrip (bug #7).
##
## Verifies GameState.to_dict + GameState.from_dict actually serialize and
## restore the EventLog ring buffer. Without the Wave D fix, event_log was
## never written to / read from the save dict and silently reset on every
## load.
##
## Critical for: typed-array silent-fail class. EventLog.restore uses the
## explicit-coerce pattern; this test exercises that path end-to-end.


func _gs() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("GameState")


# ── Helpers ──────────────────────────────────────────────────────────────────

func _push_canned_events(gs: Node) -> void:
	# Push 5 distinct event types in a known order so we can compare ordering.
	gs.event_log.record(EventLog.TYPE_AREA_ENTERED, "Entered Harmonia",      {"world": 1})
	gs.event_log.record(EventLog.TYPE_BOSS_DEFEAT,  "Defeated Pyrroth",      {"boss": "pyrroth"})
	gs.event_log.record(EventLog.TYPE_ITEM_OBTAINED, "Got Ember Sword",      {"item": "ember_sword"})
	gs.event_log.record(EventLog.TYPE_LEVEL_UP,     "Fighter reached lv 14", {"job": "fighter"})
	gs.event_log.record(EventLog.TYPE_STORY_FLAG,   "Calibrant glimpsed",    {"flag": "calibrant_seen"})


# ── Tests ────────────────────────────────────────────────────────────────────

func test_event_log_present_on_gamestate() -> void:
	var gs := _gs()
	assert_not_null(gs, "GameState autoload missing")
	assert_not_null(gs.event_log, "GameState.event_log must be instantiated in _ready")


func test_event_log_persists_through_to_dict_from_dict() -> void:
	var gs := _gs()
	assert_not_null(gs)
	if gs == null:
		return

	# Clear any pre-existing log state from other tests.
	gs.event_log.clear()
	_push_canned_events(gs)
	assert_eq(gs.event_log.size(), 5, "preconditions: 5 events in log")

	# Snapshot via to_dict — should include event_log key.
	var snapshot: Dictionary = gs.to_dict()
	assert_true(snapshot.has("event_log"), "to_dict() MUST include 'event_log' key (bug #7)")
	var serialized: Variant = snapshot["event_log"]
	assert_true(serialized is Array, "serialized event_log must be Array")
	assert_eq((serialized as Array).size(), 5, "serialized event_log must contain all 5 entries")

	# Simulate JSON.parse() returning a generic Array — encode then decode the
	# snapshot so we exercise the typed-array silent-failure code path.
	var as_json: String = JSON.stringify(snapshot)
	var roundtripped: Variant = JSON.parse_string(as_json)
	assert_true(roundtripped is Dictionary, "roundtripped snapshot must be Dictionary")

	# Wipe the live event log and restore from the roundtripped snapshot.
	gs.event_log.clear()
	assert_eq(gs.event_log.size(), 0, "preconditions: cleared event_log")

	gs.from_dict(roundtripped as Dictionary)

	assert_eq(gs.event_log.size(), 5,
		"after from_dict: event_log MUST contain restored entries (bug #7 regression)")

	var recent: Array[Dictionary] = gs.event_log.recent(5)
	assert_eq(recent.size(), 5)

	# Order preserved — Entered Harmonia came first, Calibrant glimpsed came last.
	assert_eq(str(recent[0].get("summary", "")), "Entered Harmonia")
	assert_eq(str(recent[0].get("type", "")),    EventLog.TYPE_AREA_ENTERED)
	assert_eq(str(recent[4].get("summary", "")), "Calibrant glimpsed")
	assert_eq(str(recent[4].get("type", "")),    EventLog.TYPE_STORY_FLAG)

	# data field is preserved per-entry.
	assert_eq(str((recent[1].get("data", {}) as Dictionary).get("boss", "")), "pyrroth")


func test_from_dict_with_missing_event_log_clears_safely() -> void:
	var gs := _gs()
	assert_not_null(gs)
	if gs == null:
		return

	gs.event_log.clear()
	gs.event_log.record(EventLog.TYPE_CUSTOM, "lingering", {})
	assert_eq(gs.event_log.size(), 1)

	# Save snapshot without 'event_log' key — exercise the missing-key branch.
	gs.from_dict({})
	assert_eq(gs.event_log.size(), 0,
		"from_dict({}) should clear the event_log (apply_save_data missing-key branch)")
