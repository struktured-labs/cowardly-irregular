extends GutTest

## Bugfix 2026-07-05: Flee (type="escape") calls BattleManager.end_battle(false)
## on a SUCCESSFUL escape — the same path a party wipe takes — so GameLoop
## ._on_battle_ended sent the player to the GAME OVER screen instead of back to
## the overworld. A flee leaves living party members; a true wipe leaves none.
## The defeat/game-over flow is now gated on the party actually being down: any
## survivor means we escaped, so return to exploration and skip game over.


func test_on_battle_ended_gates_game_over_on_actual_wipe() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	var idx: int = src.find("func _on_battle_ended")
	assert_gt(idx, -1, "_on_battle_ended must exist")
	var body: String = src.substr(idx, src.find("\nfunc ", idx + 1) - idx)
	assert_true(body.contains("_escape_survivors"),
		"the defeat branch must count living party members to tell escape from wipe")
	var surv_idx: int = body.find("if _escape_survivors > 0:")
	assert_gt(surv_idx, -1, "there must be a survivors>0 escape branch")
	var surv_block: String = body.substr(surv_idx, 320)
	assert_true(surv_block.contains("_return_to_exploration"),
		"an escape (survivors>0) must return to exploration, not fall through to game over")
	assert_true(surv_block.contains("return"),
		"the escape branch must return BEFORE the game-over path")


func test_escape_ability_routes_through_end_battle() -> void:
	# Documents the interaction the GameLoop fix relies on: the ability success
	# path calls end_battle(false); distinguishing escape from wipe happens in
	# _on_battle_ended, not here.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("func _execute_escape_ability")
	assert_gt(idx, -1, "_execute_escape_ability must exist")
	var body: String = src.substr(idx, src.find("\nfunc ", idx + 1) - idx)
	assert_true(body.contains("end_battle(false)"),
		"escape success routes through end_battle(false) — the path the GameLoop fix now splits")
