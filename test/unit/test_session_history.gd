extends GutTest

## Tests for autogrind session history

var _system: Node = null


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system.session_history.clear()


func test_session_history_starts_empty() -> void:
	assert_eq(_system.session_history.size(), 0, "History should start empty")


func test_max_session_history_constant() -> void:
	assert_eq(_system.MAX_SESSION_HISTORY, 10, "Max history should be 10")


func test_get_session_history_returns_array() -> void:
	var history = _system.get_session_history()
	assert_true(history is Array, "Should return an array")


func test_record_session_adds_entry() -> void:
	_system.current_region_id = "overworld"
	var results = {
		"battles_completed": 15,
		"total_exp_gained": 500,
		"final_efficiency": 2.5,
		"corruption_level": 1.0,
		"stop_reason": "Manual stop",
	}
	var stats = {
		"elapsed_seconds": 300.0,
		"exp_per_min": 100.0,
		"total_gold": 200,
	}
	_system._record_session(results, stats)
	assert_eq(_system.session_history.size(), 1, "Should have 1 entry")

	var entry = _system.session_history[0]
	assert_eq(entry["battles"], 15, "Battles should be 15")
	assert_eq(entry["total_exp"], 500, "EXP should be 500")
	assert_eq(entry["region"], "overworld", "Region should be overworld")
	assert_eq(entry["reason"], "Manual stop", "Reason should match")
	assert_true(entry.has("timestamp"), "Should have timestamp")


func test_history_capped_at_max() -> void:
	for i in range(15):
		_system._record_session(
			{"battles_completed": i, "total_exp_gained": 0, "final_efficiency": 1.0,
			 "corruption_level": 0.0, "stop_reason": "test"},
			{"elapsed_seconds": 0.0, "exp_per_min": 0.0, "total_gold": 0}
		)
	assert_eq(_system.session_history.size(), 10, "Should be capped at MAX_SESSION_HISTORY")
	assert_eq(_system.session_history[0]["battles"], 5, "Oldest entry should be #5 (first 5 dropped)")
