extends GutTest

## tick 80 regression: F2 quick-save and F3 quick-load must refuse
## while an area-transition is in flight. Pre-fix, both checked only
## TITLE / character-creation / battle / autogrind — none of those
## cover the fade-in/fade-out window where the scene swap is mid-air.
##
## F2 silent risk: _current_map_id was updated to the destination
## (line ~2917) but the scene itself isn't loaded yet. SaveSystem
## reads MapSystem.current_map_id which is stale-or-mid-update,
## producing inconsistent state on disk.
##
## F3 silent risk: load_game → MapSystem.load_map races against
## GameLoop's in-flight scene-routing. Both try to instantiate
## destination maps and the second one wins, sometimes with leftover
## nodes from the first.

const GAME_LOOP := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func _body(fn_name: String) -> String:
	var src := _read(GAME_LOOP)
	var idx: int = src.find("func " + fn_name)
	assert_gt(idx, -1, "%s must exist" % fn_name)
	var next_fn: int = src.find("\nfunc ", idx + 1)
	return src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)


func test_quick_save_blocks_when_in_transition() -> void:
	var body := _body("_quick_save_with_toast")
	assert_true(body.contains("_in_exploration_transition()"),
		"_quick_save_with_toast must check _in_exploration_transition() — F2 mid-fade captures stale/half-updated map state")
	assert_true(body.contains("Cannot quick-save mid-transition"),
		"F2 transition block must surface a specific toast message — generic 'right now' hides the actual blocker")


func test_quick_load_blocks_when_in_transition() -> void:
	var body := _body("_quick_load_with_toast")
	assert_true(body.contains("_in_exploration_transition()"),
		"_quick_load_with_toast must check _in_exploration_transition() — F3 mid-fade races MapSystem.load_map against the in-flight scene swap")
	assert_true(body.contains("Cannot quick-load mid-transition"),
		"F3 transition block must surface a specific toast")


func test_quick_save_transition_check_precedes_can_quick_save() -> void:
	# Ordering: the transition check must run BEFORE SaveSystem's
	# generic can_quick_save call. Otherwise a transition INTO an
	# interior catches the wrong toast ('Cannot save inside this
	# room') instead of the actual blocker ('mid-transition').
	var body := _body("_quick_save_with_toast")
	var trans_idx: int = body.find("_in_exploration_transition()")
	var can_save_idx: int = body.find("SaveSystem.can_quick_save()")
	assert_gt(trans_idx, -1, "transition check must exist")
	assert_gt(can_save_idx, -1, "can_quick_save check must still exist")
	assert_lt(trans_idx, can_save_idx,
		"transition check must come BEFORE can_quick_save — otherwise the wrong reason wins during interior transitions")


func test_quick_load_transition_check_precedes_load_attempt() -> void:
	# Make sure the transition check sits BEFORE load_game is called.
	# A late check after load_game already ran would be cosmetic only.
	var body := _body("_quick_load_with_toast")
	var trans_idx: int = body.find("_in_exploration_transition()")
	var load_idx: int = body.find("SaveSystem.load_game(slot)")
	assert_gt(trans_idx, -1, "transition check must exist")
	assert_gt(load_idx, -1, "load_game call must still exist")
	assert_lt(trans_idx, load_idx,
		"transition check must come BEFORE the load_game call — otherwise the race already happened")


func test_existing_battle_and_autogrind_guards_preserved() -> void:
	# Don't regress the prior protections.
	var save_body := _body("_quick_save_with_toast")
	var load_body := _body("_quick_load_with_toast")
	assert_true(save_body.contains("LoopState.AUTOGRIND"),
		"F2 must still block during autogrind")
	assert_true(load_body.contains("is_battle_active()"),
		"F3 must still block mid-battle")
	assert_true(load_body.contains("LoopState.AUTOGRIND"),
		"F3 must still block during autogrind")
