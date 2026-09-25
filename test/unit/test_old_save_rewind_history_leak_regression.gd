extends GutTest

## Saves written before the rewind ring was persisted have no save_history key.
## GameState._apply_save_data leaves the live ring alone when that key is absent,
## which rewind needs: a checkpoint written to disk has its nested save_history
## stripped, and clearing inside _apply_save_data would drop every remaining point
## the moment Rewind restored one.
##
## The file load is a different input. An old save never recorded checkpoints, so
## the ring still sitting on the autoload belongs to whatever slot was loaded
## earlier this session. Continue then shows those moments as this save's (the
## parish well counts them), and Rewind — or the next save of this slot — restores
## the other playthrough.

const GS := preload("res://src/meta/GameState.gd")

var _backup: Dictionary = {}


func before_each() -> void:
	if GameState:
		_backup = GameState.to_dict()


func after_each() -> void:
	if GameState and not _backup.is_empty():
		GameState._apply_save_data(_backup)
		_backup = {}


## Minimal pre-history save: game_state has been on disk since the 2026-04-30
## serializer; save_history was not. One party member so this is a playable file,
## not an empty envelope.
func _old_save() -> Dictionary:
	return {
		"game_state": {
			"version": "0.1.0",
			"party_gold": 120,
			"current_save_name": "Harmonia, before rewind history",
			"player_party": [{
				"name": "Fighter",
				"job_id": "fighter",
				"job_level": 4,
				"max_hp": 200,
				"current_hp": 180,
			}],
		},
	}


func test_an_old_save_does_not_inherit_another_slots_rewind_points() -> void:
	var ss = get_node_or_null("/root/SaveSystem")
	if ss == null or GameState == null:
		pending("SaveSystem and GameState autoloads required")
		return
	GameState.save_history.clear()
	GameState.save_history.append({"party_gold": 9999, "current_save_name": "later slot"})
	GameState.save_history.append({"party_gold": 1, "current_save_name": "later slot again"})
	assert_eq(GameState.save_history.size(), 2,
		"precondition: the other slot's checkpoints are live before the old file loads")
	ss._apply_save_data(_old_save())
	assert_eq(GameState.save_history.size(), 0,
		"a save with no save_history key kept nothing — it must not inherit the other slot's rewind points")
	assert_eq(GameState.party_gold, 120,
		"the old save's own gold must still load")
	assert_eq(GameState.player_party.size(), 1,
		"the old save's party must still load")
	assert_eq(str(GameState.player_party[0].get("name", "")), "Fighter")


func test_a_save_that_recorded_checkpoints_still_restores_them() -> void:
	var ss = get_node_or_null("/root/SaveSystem")
	if ss == null or GameState == null:
		pending("SaveSystem and GameState autoloads required")
		return
	GameState.save_history.clear()
	GameState.save_history.append({"party_gold": 9999, "current_save_name": "later slot"})
	var modern := _old_save()
	modern["game_state"]["save_history"] = [
		{"party_gold": 40, "current_save_name": "kept once"},
		{"party_gold": 80, "current_save_name": "kept twice"},
	]
	ss._apply_save_data(modern)
	assert_eq(GameState.save_history.size(), 2,
		"a save that actually recorded rewind points must still load them")
	assert_eq(int(GameState.save_history[0].get("party_gold", 0)), 40,
		"the loaded ring must be this save's checkpoints, not the slot that was live before")


func test_rewind_of_a_stripped_snapshot_keeps_the_remaining_ring() -> void:
	# Disk-shaped checkpoints omit nested save_history. Rewind feeds one of those
	# straight to GameState._apply_save_data. Clearing on an absent key THERE would
	# throw away every checkpoint still in the ring — the file-load fix must not.
	var gs = GS.new()
	autofree(gs)
	gs.meta_features["rewind_enabled"] = true
	gs.save_history.append({"party_gold": 10, "player_party": []})
	gs.save_history.append({"party_gold": 20, "player_party": []})
	assert_true(gs.rewind_to_previous_save(),
		"precondition: rewind is unlocked and two checkpoints are enough to fire")
	assert_eq(gs.party_gold, 10, "rewind restores the earlier snapshot")
	assert_eq(gs.save_history.size(), 1,
		"a stripped snapshot has no save_history key — rewind must keep the checkpoint still in the ring")
