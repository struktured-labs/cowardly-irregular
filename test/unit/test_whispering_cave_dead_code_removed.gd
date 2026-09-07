extends GutTest

## tick 106 cleanup: WhisperingCave._on_boss_defeated was dead code
## (no caller anywhere) — the same class as DragonCave._on_boss_defeated
## removed in tick 105. The "defeat_cutscene" key in the
## pending_boss_defeat spec was also unread — no consumer reads the
## key off the spec, so the field was misleading.
##
## The actual mechanism for the rat king flow:
## - Side-effect flags applied via GameLoop._apply_pending_boss_defeat
##   reading the spec.
## - world1_rat_king_defeat cutscene played via
##   GameLoop._get_pending_story_cutscene gate at line ~1026
##   (cutscene_flag_rat_king_defeated + in whispering_cave).

const WHISPERING_CAVE := "res://src/maps/dungeons/WhisperingCave.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_whispering_cave_no_longer_has_on_boss_defeated() -> void:
	var src := _read(WHISPERING_CAVE)
	assert_false(src.contains("func _on_boss_defeated()"),
		"WhisperingCave must NOT define _on_boss_defeated — removed as dead code (no caller anywhere)")


func test_whispering_cave_pending_spec_no_longer_has_defeat_cutscene_key() -> void:
	# The "defeat_cutscene" key on the pending_boss_defeat spec was
	# never read by any consumer. Removing it makes the spec match
	# what _apply_pending_boss_defeat actually consumes.
	var src := _read(WHISPERING_CAVE)
	assert_false(src.contains("\"defeat_cutscene\": \"world1_rat_king_defeat\""),
		"WhisperingCave's pending_boss_defeat spec must NOT carry a 'defeat_cutscene' key — that key was never read")


func test_whispering_cave_pending_spec_still_has_live_keys() -> void:
	# Sanity: don't accidentally remove the LIVE keys that
	# _apply_pending_boss_defeat actually consumes.
	var src := _read(WHISPERING_CAVE)
	# story_flags: applied to GameState.set_story_flag.
	assert_true(src.contains("\"story_flags\": [\"rat_king_defeated\"]"),
		"WhisperingCave spec must still carry story_flags = ['rat_king_defeated']")
	# constants: each pushed into game_constants.
	assert_true(src.contains("\"cutscene_flag_rat_king_defeated\""),
		"WhisperingCave spec constants must still carry cutscene_flag_rat_king_defeated")
	# dungeon_flag: written to leader's dungeon_flags dict.
	assert_true(src.contains("\"dungeon_flag\": \"cave_rat_king_defeated\""),
		"WhisperingCave spec must still carry dungeon_flag = 'cave_rat_king_defeated'")


func test_world1_rat_king_defeat_still_gated_in_game_loop() -> void:
	# The live play mechanism — pin it so a regression that
	# accidentally removes the gate is caught.
	var src := _read("res://src/GameLoop.gd")
	assert_true(src.contains("return \"world1_rat_king_defeat\""),
		"GameLoop._get_pending_story_cutscene must still return world1_rat_king_defeat — the live play mechanism")


func test_apply_pending_boss_defeat_still_consumes_known_keys() -> void:
	# Sanity: pin the consumer side reads the keys we're still
	# providing. If a future refactor renames spec keys, the
	# rat king flow silently breaks.
	var gl_src := _read("res://src/GameLoop.gd")
	var idx: int = gl_src.find("func _apply_pending_boss_defeat")
	assert_gt(idx, -1, "_apply_pending_boss_defeat must exist")
	var next_fn: int = gl_src.find("\nfunc ", idx + 1)
	var body: String = gl_src.substr(idx, next_fn - idx) if next_fn > -1 else gl_src.substr(idx)
	assert_true(body.contains("spec.get(\"story_flags\""),
		"_apply_pending_boss_defeat must read 'story_flags' from spec")
	assert_true(body.contains("spec.get(\"constants\""),
		"_apply_pending_boss_defeat must read 'constants' from spec")
	assert_true(body.contains("spec.get(\"dungeon_flag\""),
		"_apply_pending_boss_defeat must read 'dungeon_flag' from spec")
	# Negative: the consumer must NOT pretend to read 'defeat_cutscene'
	# off the spec (the key we just removed).
	assert_false(body.contains("spec.get(\"defeat_cutscene\""),
		"_apply_pending_boss_defeat must NOT read 'defeat_cutscene' from spec — that key was always unread; would resurrect dead semantics")
