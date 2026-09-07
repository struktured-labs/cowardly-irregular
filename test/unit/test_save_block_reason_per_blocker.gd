extends GutTest

## tick 75 regression: save_game / quick_save must emit the SPECIFIC
## blocker reason, not a generic "Cannot save during battle" when
## the actual blocker is something else (player is inside an interior).
##
## Original silent bug (caught in tick 75 audit): tick 74 added the
## interior gate to can_quick_save, but save_game's failure-emit was
## still hardcoded to "Cannot save during battle". Player in the
## chapel pressing Save would see a phantom-battle error.

const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_save_block_reason_helper_exists() -> void:
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("func _save_block_reason() -> String"),
		"_save_block_reason helper must exist — returns specific message for each blocker")


func test_block_reason_mirrors_can_quick_save_order() -> void:
	var src := _read(SAVE_SYSTEM)
	var idx: int = src.find("func _save_block_reason")
	assert_gt(idx, -1, "_save_block_reason must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Order: battle ready check, battle active check, interior check.
	var bm_check: int = body.find("if not BattleManager")
	var battle_check: int = body.find("is_battle_active()")
	var interior_check: int = body.find("_is_player_inside_interior()")
	assert_gt(bm_check, -1, "_save_block_reason must guard BattleManager null")
	assert_gt(battle_check, -1, "_save_block_reason must check is_battle_active")
	assert_gt(interior_check, -1, "_save_block_reason must check is_inside_interior")
	assert_lt(battle_check, interior_check,
		"battle check must come before interior check — mirrors can_quick_save order so the same blocker wins")


func test_interior_message_is_specific() -> void:
	# Pin the wording. Generic "cannot save" hides the actual reason.
	# Specific wording tells the player what to do.
	var src := _read(SAVE_SYSTEM)
	assert_true(src.contains("Cannot save inside this room"),
		"interior block message must say 'Cannot save inside this room' — gives the player a specific action (leave to village)")


func test_save_game_uses_specific_block_reason() -> void:
	var src := _read(SAVE_SYSTEM)
	var idx: int = src.find("func save_game(slot: int = -1)")
	assert_gt(idx, -1, "save_game must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("_save_block_reason()"),
		"save_game must derive the failure message from _save_block_reason, not hardcoded 'during battle'")
	assert_true(body.contains("save_failed.emit(reason)"),
		"save_game must emit the derived reason, not a hardcoded string")
	# Negative: the old hardcoded message must NOT be the emit target.
	assert_false(body.contains("save_failed.emit(\"Cannot save during battle\")"),
		"save_game must NOT emit hardcoded 'Cannot save during battle' — that's a phantom-battle UX bug when the real blocker is the interior")


func test_quick_save_uses_specific_block_reason() -> void:
	var src := _read(SAVE_SYSTEM)
	var idx: int = src.find("func quick_save()")
	assert_gt(idx, -1, "quick_save must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("_save_block_reason()"),
		"quick_save must derive the failure message from _save_block_reason, not hardcoded 'Cannot quick save here'")
	assert_false(body.contains("save_failed.emit(\"Cannot quick save here\")"),
		"quick_save must NOT emit hardcoded 'Cannot quick save here' — generic message hides the real blocker")


func test_block_reason_empty_string_when_save_allowed() -> void:
	# Pin the contract: empty string means save is allowed. Callers
	# can use this to detect 'no blocker' without re-running the full
	# can_quick_save logic.
	var src := _read(SAVE_SYSTEM)
	var idx: int = src.find("func _save_block_reason")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("return \"\""),
		"_save_block_reason must return \"\" (empty string) when no blocker — signals 'save allowed' to callers")
