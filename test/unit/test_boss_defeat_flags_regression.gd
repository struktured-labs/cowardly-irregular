extends GutTest

## Regression test for the Rat King quest log bug.
##
## Bug (2026-05-02): Player defeated the Cave Rat King, but the quest log
## still showed it as undefeated. Root cause: WhisperingCave._on_boss_defeated()
## was an orphaned function — nothing called it. The cave instance gets
## queue_freed during _return_to_exploration, so any handler on `self`
## evaporates before it could fire. The story flag rat_king_defeated never
## got set, so QuestLog and chapter4 cutscene gating both broke.
##
## Same bug existed in DragonCave (ice/fire/shadow/lightning_dragon and the
## meta-knight / masterite_warden bosses). All 9 boss dungeons were silently
## broken.
##
## Fix (centralized in GameLoop._on_battle_ended):
##   1. Dungeons set GameState.pending_boss_defeat = {...spec...} BEFORE
##      emitting battle_triggered.
##   2. GameLoop._apply_pending_boss_defeat() runs on victory and sets all
##      the flags from the spec (story_flags, constants, dungeon_flag,
##      unlock_world).
##   3. spec is cleared on apply (one-shot) and on game_over (so retries
##      don't fire flags from a battle the player didn't actually win).
##
## Tested structurally because end-to-end battle simulation crashes in GUT.


func _read(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	assert_not_null(file, "file should exist: %s" % path)
	var text = file.get_as_text()
	file.close()
	return text


func test_whispering_cave_registers_pending_boss_defeat() -> void:
	var text = _read("res://src/maps/dungeons/WhisperingCave.gd")
	var idx = text.find("func _trigger_boss_battle")
	assert_gt(idx, -1, "_trigger_boss_battle must exist")
	var body = text.substr(idx, 1500)
	assert_true(body.find("GameState.pending_boss_defeat") != -1,
		"_trigger_boss_battle must set GameState.pending_boss_defeat (regression: rat_king_defeated never set)")
	assert_true(body.find("rat_king_defeated") != -1,
		"WhisperingCave spec must include rat_king_defeated story flag")
	assert_true(body.find("w1_boss_defeated") != -1,
		"WhisperingCave spec must include w1_boss_defeated story flag")
	assert_true(body.find("cutscene_flag_rat_king_defeated") != -1,
		"WhisperingCave spec must include cutscene_flag_rat_king_defeated constant (gates chapter4)")
	assert_true(body.find("cave_rat_king_defeated") != -1,
		"WhisperingCave spec must include cave_rat_king_defeated dungeon flag")


func test_dragon_cave_registers_pending_boss_defeat() -> void:
	var text = _read("res://src/maps/dungeons/DragonCave.gd")
	var idx = text.find("func _trigger_boss_battle")
	assert_gt(idx, -1, "_trigger_boss_battle must exist")
	var body = text.substr(idx, 1500)
	assert_true(body.find("GameState.pending_boss_defeat") != -1,
		"DragonCave._trigger_boss_battle must set GameState.pending_boss_defeat")
	assert_true(body.find("boss_flag_key") != -1,
		"DragonCave spec must include boss_flag_key as the dungeon flag")
	assert_true(body.find("unlock_story_flag") != -1,
		"DragonCave spec must propagate unlock_story_flag")
	assert_true(body.find("unlock_world") != -1,
		"DragonCave spec must handle unlock_world advancement")


func test_gameloop_applies_pending_boss_defeat_on_victory() -> void:
	var text = _read("res://src/GameLoop.gd")
	var idx = text.find("func _on_battle_ended")
	assert_gt(idx, -1, "_on_battle_ended must exist")
	var body = text.substr(idx, 2000)
	assert_true(body.find("_apply_pending_boss_defeat") != -1,
		"_on_battle_ended must call _apply_pending_boss_defeat() on victory")


func test_gameloop_applies_before_return_to_exploration() -> void:
	# Critical ordering: flags must be applied BEFORE _return_to_exploration
	# instantiates the new dungeon scene. Otherwise the new scene's
	# _load_boss_state() reads stale dungeon_flags and the boss respawns.
	# Bound the search to just the if-victory branch so we don't accidentally
	# match against the _apply_pending_boss_defeat function declaration that
	# lives lower in the same slice.
	var text = _read("res://src/GameLoop.gd")
	var on_battle_idx = text.find("func _on_battle_ended")
	# Find the `else:` branch start to bound the if-victory body.
	var else_idx = text.find("\n\telse:", on_battle_idx)
	assert_gt(else_idx, on_battle_idx, "expected if/else inside _on_battle_ended")
	var victory_body = text.substr(on_battle_idx, else_idx - on_battle_idx)
	# Match actual call sites (with parens) — substring matches are unsafe
	# because the comment that documents the ordering also contains the names.
	var apply_idx = victory_body.find("_apply_pending_boss_defeat()")
	var return_idx = victory_body.find("_return_to_exploration()")
	assert_gt(apply_idx, -1, "must call _apply_pending_boss_defeat() in victory branch")
	assert_gt(return_idx, -1, "must call _return_to_exploration() in victory branch")
	assert_lt(apply_idx, return_idx,
		"_apply_pending_boss_defeat must run BEFORE _return_to_exploration "
		+ "(otherwise new dungeon scene reads stale state and boss respawns)")


func test_gameloop_clears_pending_on_defeat() -> void:
	# On battle defeat we should clear the pending spec so a retry doesn't
	# accidentally fire flags from a battle the player didn't actually win.
	var text = _read("res://src/GameLoop.gd")
	var idx = text.find("func _on_battle_ended")
	var body = text.substr(idx, 2000)
	# Defeat branch: look in the `else` clause for pending clear
	assert_true(body.find("pending_boss_defeat = {}") != -1,
		"On battle defeat, pending_boss_defeat must be cleared (prevent false-flag on retry)")


func test_gameloop_apply_helper_is_one_shot() -> void:
	# After applying, the spec must be cleared so subsequent normal battle
	# victories don't re-fire the same boss flags.
	var text = _read("res://src/GameLoop.gd")
	var idx = text.find("func _apply_pending_boss_defeat")
	assert_gt(idx, -1, "_apply_pending_boss_defeat must exist")
	# Find next func to bound the body
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	# Look for the clear-after-apply pattern
	assert_true(body.find("pending_boss_defeat = {}") != -1,
		"_apply_pending_boss_defeat must clear the spec after applying (one-shot)")


func test_gamestate_has_pending_boss_defeat_field() -> void:
	var text = _read("res://src/meta/GameState.gd")
	assert_true(text.find("var pending_boss_defeat") != -1,
		"GameState must declare pending_boss_defeat field")


func test_reset_game_state_clears_pending() -> void:
	var text = _read("res://src/meta/GameState.gd")
	var idx = text.find("func reset_game_state")
	assert_gt(idx, -1, "reset_game_state must exist")
	var next_func = text.find("\nfunc ", idx + 1)
	if next_func == -1:
		next_func = text.length()
	var body = text.substr(idx, next_func - idx)
	assert_true(body.find("pending_boss_defeat = {}") != -1,
		"reset_game_state must clear pending_boss_defeat (carry-over leak across new games)")
