extends GutTest

## Regression tests for the MapSystem dead-location gutting
## (commit 360ce86). Ensures the removed APIs stay removed and the
## surviving save-gate behavior is preserved.
##
## Autoload identifiers are resolved at runtime via tree.root.get_node()
## rather than the global-identifier form; test scripts parse before
## autoloads register as globals (same constraint that applies to
## preload()-chain files like Combatant.gd).


var _map_system: Node
var _save_system: Node
var _battle_manager: Node


func before_all() -> void:
	var tree = get_tree()
	if tree and tree.root:
		_map_system = tree.root.get_node_or_null("MapSystem")
		_save_system = tree.root.get_node_or_null("SaveSystem")
		_battle_manager = tree.root.get_node_or_null("BattleManager")


func test_mapsystem_has_no_dead_location_api():
	if _map_system == null:
		pending("MapSystem autoload not available")
		return
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
			_map_system.has_method(member),
			"MapSystem.%s was removed as dead code — don't re-add without wiring callers" % member,
		)


func test_mapsystem_has_no_dead_location_signals():
	if _map_system == null:
		pending("MapSystem autoload not available")
		return
	var removed_signals = ["location_entered", "location_exited"]
	for sig in removed_signals:
		assert_false(
			_map_system.has_signal(sig),
			"MapSystem.%s was removed along with enter_location()" % sig,
		)


func test_mapsystem_maptype_enum_still_present():
	if _map_system == null:
		pending("MapSystem autoload not available")
		return
	# The enum is kept for save-format compatibility and future use even
	# though the dispatch that read it was removed. Access via the
	# autoload node's script constants instead of MapSystem.MapType to
	# avoid parse-time identifier lookup.
	var script = _map_system.get_script()
	assert_not_null(script, "MapSystem autoload should have a script")
	var constants = script.get_script_constant_map() if script else {}
	assert_true("MapType" in constants, "MapSystem.MapType enum should still exist")
	var mt = constants.get("MapType", {})
	assert_eq(mt.get("OVERWORLD", -1), 0, "OVERWORLD should be first")
	assert_eq(mt.get("VILLAGE", -1), 1, "VILLAGE should be second")
	assert_eq(mt.get("DUNGEON", -1), 2, "DUNGEON should be third")


func test_mapsystem_still_exposes_core_api():
	if _map_system == null:
		pending("MapSystem autoload not available")
		return
	var required = [
		"load_map",
		"unload_current_map",
		"transition_to_map",
		"set_player",
		"get_player",
	]
	for member in required:
		assert_true(
			_map_system.has_method(member),
			"MapSystem.%s is core API — don't remove without a migration plan" % member,
		)


## Restored in after_each, never inline: an assert that fails mid-test must not leak a mutated
## autoload into every later file.
var _saved_party: Array[Dictionary] = []
var _had_party: bool = false


func _stash_party() -> void:
	_had_party = GameState != null and "player_party" in GameState
	if not _had_party:
		return
	_saved_party = []
	for e in GameState.player_party:
		_saved_party.append((e as Dictionary).duplicate(true))


func after_each() -> void:
	if not _had_party:
		return
	var restored: Array[Dictionary] = []
	for e in _saved_party:
		restored.append(e as Dictionary)
	GameState.player_party = restored
	_had_party = false


## Array[Dictionary] is TYPED — assigning a bare Array fails AND aborts the caller
func _set_party(entries: Array) -> void:
	var typed: Array[Dictionary] = []
	for e in entries:
		typed.append(e as Dictionary)
	GameState.player_party = typed


func test_can_quick_save_true_outside_battle():
	if _save_system == null:
		pending("SaveSystem autoload not available")
		return
	# Previously this gated on get_current_map_type() which always
	# returned OVERWORLD (dead data). Out of battle, saving must be
	# allowed so the save menu's "quick save" button is never a no-op.
	if _battle_manager and _battle_manager.is_battle_active():
		pending("Cannot validate quick save outside battle while battle is active")
		return
	# A LOADED PARTY is now part of this contract, not an ambient assumption. The gate added
	# 2026-08-23 blocks saving when none was ever loaded — that is what wrote struktured's
	# partyless slot 98. This test asserted an UNCONDITIONAL true and so went red on a correct
	# change; stating the precondition is what makes it specific rather than weaker.
	_stash_party()
	if not _had_party:
		pending("GameState.player_party unavailable")
		return
	_set_party([{"name": "Fighter", "is_alive": true, "current_hp": 100}])
	assert_true(
		_save_system.can_quick_save(),
		"can_quick_save() must return true when no battle is active and a party is loaded",
	)


func test_can_quick_save_false_when_no_party_was_ever_loaded():
	# The other half, so the pair cannot drift back to an unconditional assertion: without this
	# the test above passes just as happily if the gate were deleted.
	if _save_system == null:
		pending("SaveSystem autoload not available")
		return
	if _battle_manager and _battle_manager.is_battle_active():
		pending("battle active")
		return
	_stash_party()
	if not _had_party:
		pending("GameState.player_party unavailable")
		return
	_set_party([])
	assert_false(
		_save_system.can_quick_save(),
		"a quick save with no party loaded is what wrote the partyless shell slot 98",
	)
