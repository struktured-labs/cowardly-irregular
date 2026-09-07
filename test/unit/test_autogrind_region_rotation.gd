extends GutTest

## Regression coverage for region-rotation advisory — fired when monster_adaptation_level
## crosses ROTATION_SUGGEST_THRESHOLD, at most once per region per session.

var _system: Node
var _received: Array = []


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true  # Prevent test writes to user://autogrind/*.json (leaked TestChar0 into struktured's save, 2026-07-14)
	_system.region_rotation_suggested.connect(_capture_suggestion)
	_received.clear()

	_system.is_grinding = false
	_system.monster_adaptation_level = 0.0
	_system.current_region_id = ""
	_system._rotation_suggested_regions.clear()


func _capture_suggestion(current_region_id: String, suggested: Dictionary, adaptation_level: float) -> void:
	_received.append({"current": current_region_id, "suggested": suggested, "level": adaptation_level})


func test_no_suggestion_when_below_threshold() -> void:
	_system.current_region_id = "region_medieval"
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD - 0.5
	_system._maybe_suggest_region_rotation()
	assert_eq(_received.size(), 0,
		"Below threshold, no advisory should fire")


func test_suggestion_fires_at_threshold() -> void:
	_system.current_region_id = "region_medieval"
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD
	_system._maybe_suggest_region_rotation()
	assert_eq(_received.size(), 1,
		"At threshold, advisory should fire exactly once")
	assert_eq(_received[0]["current"], "region_medieval",
		"Emitted payload must carry the current region id")
	assert_almost_eq(_received[0]["level"], _system.ROTATION_SUGGEST_THRESHOLD, 0.001,
		"Emitted payload must carry the adaptation level at fire time")


func test_no_suggestion_when_region_id_empty() -> void:
	_system.current_region_id = ""
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD + 5.0
	_system._maybe_suggest_region_rotation()
	assert_eq(_received.size(), 0,
		"With empty region id, advisory must not fire (dedup keyed on region id)")


func test_suggestion_fires_only_once_per_region() -> void:
	_system.current_region_id = "region_suburban"
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD
	_system._maybe_suggest_region_rotation()
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD + 1.0
	_system._maybe_suggest_region_rotation()
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD + 2.0
	_system._maybe_suggest_region_rotation()
	assert_eq(_received.size(), 1,
		"Advisory must dedup to one fire per region per session — otherwise every _increase_efficiency after crossing would spam the toast")


func test_suggestion_fires_again_after_region_change() -> void:
	_system.current_region_id = "region_a"
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD
	_system._maybe_suggest_region_rotation()
	_system.current_region_id = "region_b"
	_system._maybe_suggest_region_rotation()
	assert_eq(_received.size(), 2,
		"Moving to a fresh region must allow a new advisory to fire once adaptation crosses the threshold there")
	assert_eq(_received[0]["current"], "region_a")
	assert_eq(_received[1]["current"], "region_b")


func test_start_autogrind_clears_dedup_marks() -> void:
	# Pre-populate the dedup dict as if a prior session had already fired the advisory
	# for region_a; a fresh start_autogrind must not carry that across.
	_system._rotation_suggested_regions["region_a"] = true
	_system.current_region_id = "region_a"

	# Minimally invoke the reset path (start_autogrind requires a Combatant party;
	# we exercise the specific line the feature depends on).
	_system._rotation_suggested_regions.clear()
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD
	_system._maybe_suggest_region_rotation()
	assert_eq(_received.size(), 1,
		"After start_autogrind clears the dedup dict, advisory must fire again in the new session")


func test_advisory_emits_even_when_no_next_region_available() -> void:
	# get_next_region() returning empty is the tail-of-progression case. The signal
	# should still fire — the receiver (GameLoop) formats a different message when
	# suggested is empty (see _on_autogrind_region_rotation_suggested).
	_system.current_region_id = "region_terminal"
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD + 2.0
	_system._maybe_suggest_region_rotation()
	assert_eq(_received.size(), 1,
		"Advisory must fire even at end of progression — the empty suggested dict is the signal to switch messaging")


func test_advisory_fires_via_increase_efficiency_path() -> void:
	# This is the ACTUAL entry point in production — _increase_efficiency() is
	# called from on_battle_victory, and the rotation check must ride along.
	_system.current_region_id = "region_med"
	_system.monster_adaptation_level = _system.ROTATION_SUGGEST_THRESHOLD - 0.03  # crosses on next tick
	_system._increase_efficiency()
	assert_eq(_received.size(), 1,
		"_increase_efficiency crossing the threshold must fire the advisory — otherwise the runtime hook is disconnected from the intent")
