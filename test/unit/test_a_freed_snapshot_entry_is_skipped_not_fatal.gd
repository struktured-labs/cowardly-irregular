extends GutTest

## helpers/battle_state.gd's _valid_only exists to drop combatants a test freed from a snapshotted
## party, and checked them with `e is Object` FIRST. `is` on a freed instance is itself a SCRIPT ERROR
## (the hazard the helper's own comment names), so on the one input it exists for it ABORTED and handed
## restore() an empty array: the live members were dropped along with the freed one, in a teardown 75
## test files share, and nothing failed. Seen in fleet logs 2026-10-30/31 (battle_state.gd:102).

const BattleStateHelper := preload("res://test/unit/helpers/battle_state.gd")

var _saved_party: Array = []


func before_each() -> void:
	_saved_party = BattleManager.player_party.duplicate()


func after_each() -> void:
	var keep: Array = []
	for c in _saved_party:
		if typeof(c) == TYPE_OBJECT and is_instance_valid(c):
			keep.append(c)
	BattleManager.player_party.assign(keep)


func test_a_snapshot_holding_a_freed_combatant_restores_the_live_ones() -> void:
	var alive := Combatant.new()
	alive.combatant_name = "StillHere"
	autofree(alive)
	var doomed := Combatant.new()
	doomed.combatant_name = "Gone"
	BattleManager.player_party.assign([alive, doomed] as Array[Combatant])
	var helper = BattleStateHelper.new()
	helper.snapshot()
	doomed.free()
	BattleManager.player_party.assign([] as Array[Combatant])
	helper.restore()
	assert_eq(BattleManager.player_party.size(), 1,
		"the live member must come back and the freed one must not (got %d)" % BattleManager.player_party.size())
	assert_true(BattleManager.player_party.size() == 1 and BattleManager.player_party[0] == alive,
		"and it must be the live one")


func test_the_helper_never_tests_a_type_before_validity() -> void:
	## Source arm: `x is T` on a freed x errors, so validity must come first anywhere it filters.
	var src := FileAccess.get_file_as_string("res://test/unit/helpers/battle_state.gd")
	var body := src.substr(src.find("func _valid_only"), 600)
	assert_false(body.contains("e is Object and not is_instance_valid"),
		"_valid_only must not run `is` on an element before knowing it is still alive")
