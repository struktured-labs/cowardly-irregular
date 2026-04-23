extends GutTest

## Regression tests for the MapSystem dead-location gutting
## (commit 360ce86). Ensures the removed APIs stay removed and the
## surviving save-gate behavior is preserved.


func test_mapsystem_has_no_dead_location_api():
	# The "enter_location" subsystem was never hooked up and its removal
	# is intentional. Adding it back without wiring callers would silently
	# re-create the current_location_id-always-empty trap.
	var removed_members = [
		"enter_location",
		"exit_location",
		"_on_enter_village",
		"_on_enter_dungeon",
		"register_location",
		"get_location",
		"get_current_map_type",
		"is_in_safe_zone",
		"get_current_location_name",
	]
	for member in removed_members:
		assert_false(
			MapSystem.has_method(member),
			"MapSystem.%s was removed as dead code — don't re-add without wiring callers" % member,
		)


func test_mapsystem_has_no_dead_location_signals():
	var removed_signals = ["location_entered", "location_exited"]
	for sig in removed_signals:
		assert_false(
			MapSystem.has_signal(sig),
			"MapSystem.%s was removed along with enter_location()" % sig,
		)


func test_mapsystem_maptype_enum_still_present():
	# The enum is kept for save-format compatibility and future use even
	# though the dispatch that read it was removed. If any of these
	# expressions throw, the test will naturally fail.
	assert_eq(MapSystem.MapType.OVERWORLD, 0, "OVERWORLD should be first")
	assert_eq(MapSystem.MapType.VILLAGE, 1, "VILLAGE should be second")
	assert_eq(MapSystem.MapType.DUNGEON, 2, "DUNGEON should be third")


func test_mapsystem_still_exposes_core_api():
	var required = [
		"load_map",
		"unload_current_map",
		"transition_to_map",
		"set_player",
		"get_player",
	]
	for member in required:
		assert_true(
			MapSystem.has_method(member),
			"MapSystem.%s is core API — don't remove without a migration plan" % member,
		)


func test_can_quick_save_true_outside_battle():
	# Previously this gated on get_current_map_type() which always
	# returned OVERWORLD (dead data). Out of battle, saving must be
	# allowed so the save menu's "quick save" button is never a no-op.
	if BattleManager and BattleManager.is_battle_active():
		pending("Cannot validate quick save outside battle while battle is active")
		return
	assert_true(
		SaveSystem.can_quick_save(),
		"can_quick_save() must return true when no battle is active",
	)


