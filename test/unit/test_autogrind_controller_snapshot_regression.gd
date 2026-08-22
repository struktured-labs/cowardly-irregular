extends GutTest

## restore_from_snapshot is the pause/resume deserializer GameLoop:6311 calls on load, and
## nothing named it. Its pair serialize_snapshot is the only writer, so a key renamed on one
## side silently restores a DEFAULT instead of the player's state — the save-roundtrip defect
## class, in a path that only runs when a grind is resumed. Defaults are pinned by VALUE
## because `auto_advance` defaults to TRUE on an absent key, which is not the inert direction.

var _c


func before_each() -> void:
	_c = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(_c)


func _populate() -> void:
	_c._config = {"battles": 40, "nested": {"deep": 1}}
	_c._terrain = "volcano"
	_c._current_tier = 1
	_c.headless_mode = true
	_c._auto_advance_regions = false
	_c._saved_autobattle_states = {"fighter": true, "mage": false}


func test_a_snapshot_round_trips_every_field() -> void:
	_populate()
	var snap: Dictionary = _c.serialize_snapshot()
	var fresh = preload("res://src/autogrind/AutogrindController.gd").new()
	add_child_autofree(fresh)
	fresh.restore_from_snapshot(snap)
	assert_eq(int(fresh._config.get("battles", -1)), 40, "config must survive the round trip")
	assert_eq(str(fresh._terrain), "volcano", "terrain must survive the round trip")
	assert_eq(int(fresh._current_tier), 1, "the grind tier must survive the round trip")
	assert_true(bool(fresh.headless_mode), "headless_mode must survive the round trip")
	assert_false(bool(fresh._auto_advance_regions), "auto-advance OFF must survive as OFF")
	assert_true(bool(fresh._saved_autobattle_states.get("fighter", false)),
		"the saved autobattle states must survive — they are restored to the player on resume")


func test_an_empty_snapshot_restores_the_documented_defaults() -> void:
	_populate()
	_c.restore_from_snapshot({})
	assert_eq(str(_c._terrain), "plains", "absent terrain falls back to plains")
	assert_eq(int(_c._current_tier), 0, "absent tier falls back to the first tier")
	assert_false(bool(_c.headless_mode), "absent headless_mode falls back to false")
	assert_true(bool(_c._auto_advance_regions),
		"absent auto_advance falls back to TRUE — a missing key RESUMES region advance")
	assert_eq(_c._config.size(), 0, "absent config falls back to empty, not the previous config")


func test_restore_deep_copies_the_config() -> void:
	# ARM+ for duplicate(true): a shallow copy leaves the controller aliasing the caller's dict,
	# so a later edit to the save data would mutate live grind config.
	var snap: Dictionary = {"config": {"nested": {"deep": 1}}}
	_c.restore_from_snapshot(snap)
	(snap["config"]["nested"] as Dictionary)["deep"] = 999
	assert_eq(int((_c._config["nested"] as Dictionary).get("deep", -1)), 1,
		"the restored config must be a deep copy, not an alias of the snapshot")


func test_current_tier_reports_what_was_restored() -> void:
	_c.restore_from_snapshot({"tier": 1})
	assert_eq(int(_c.get_current_tier()), 1, "get_current_tier must report the restored tier")


func test_current_tier_reports_the_other_tier_too() -> void:
	# ARM+. Without this the accessor could return a constant and the test above still passes.
	_c.restore_from_snapshot({"tier": 0})
	assert_eq(int(_c.get_current_tier()), 0, "the accessor must track the value, not a constant")


func test_is_paused_is_false_when_idle() -> void:
	_c._state = _c.State.IDLE
	assert_false(_c.is_paused(), "an idle controller is not paused")


func test_is_paused_is_true_only_in_the_paused_state() -> void:
	# ARM+ for the sibling: proves the false above is scoped, not a stuck predicate.
	_c._state = _c.State.PAUSED
	assert_true(_c.is_paused(), "a PAUSED controller must report paused")
	_c._state = _c.State.PRE_BATTLE
	assert_false(_c.is_paused(), "a mid-grind controller is not paused")
