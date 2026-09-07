extends GutTest

## tick 277: AbstractOverworld's _get_objective_position now reads
## the real Calibrant-defeat completion flag instead of a story_flag
## that nothing in the game ever set.
##
## Pre-fix:
##   if GameState.get_story_flag("w6_boss_defeated"):
##       return spawn_points.get("the_question", Vector2.ZERO)
##   return spawn_points.get("vertex_entrance", Vector2.ZERO)
##
## "w6_boss_defeated" had ZERO writers — grep across src/ confirmed.
## Result: AFTER the W6 Calibrant cutscene finished, the objective
## arrow STILL pointed the player back at vertex_entrance instead
## of the post-game "the_question" sequence. The W6 endgame UX was
## silently broken.
##
## Fix: read the actual completion flag
## `cutscene_flag_world6_calibrant_defeat_complete`, set by the
## post-cutscene hook in GameLoop._play_story_cutscene via
## _CUTSCENE_COMPLETION_FLAGS.


const ABSTRACT_OVERWORLD := "res://src/exploration/AbstractOverworld.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: correct flag now read ─────────────────────────────

func test_uses_calibrant_defeat_completion_flag() -> void:
	var src := _read(ABSTRACT_OVERWORLD)
	assert_true(src.contains("game_constants.get(\"cutscene_flag_world6_calibrant_defeat_complete\""),
		"AbstractOverworld must read cutscene_flag_world6_calibrant_defeat_complete from game_constants")


func test_no_longer_reads_dead_w6_boss_defeated_flag() -> void:
	var src := _read(ABSTRACT_OVERWORLD)
	assert_false(src.contains("get_story_flag(\"w6_boss_defeated\")"),
		"dead story_flag 'w6_boss_defeated' must no longer be referenced (no writer existed)")


# ── Behavioral: objective flips when the real flag is set ─────────

func test_objective_flips_to_the_question_when_calibrant_defeated() -> void:
	# Build the AbstractOverworld script + a minimal spawn_points dict.
	# We can't easily instantiate the full scene in headless GUT, but
	# the function under test reads only:
	#   1. GameState.game_constants[flag]
	#   2. spawn_points[key]
	# Both can be set from outside. Test by directly invoking the
	# method on a stub instance with the script attached.
	var script: GDScript = load(ABSTRACT_OVERWORLD)
	var inst: Object = script.new()
	add_child_autofree(inst)
	inst.spawn_points = {
		"the_question": Vector2(100, 200),
		"vertex_entrance": Vector2(300, 400),
	}

	# Save existing flag state to restore after.
	var prior = GameState.game_constants.get("cutscene_flag_world6_calibrant_defeat_complete", null)
	GameState.game_constants["cutscene_flag_world6_calibrant_defeat_complete"] = false

	var pos1: Vector2 = inst._get_objective_position()
	assert_eq(pos1, Vector2(300, 400),
		"pre-defeat: objective must point to vertex_entrance")

	GameState.game_constants["cutscene_flag_world6_calibrant_defeat_complete"] = true
	var pos2: Vector2 = inst._get_objective_position()
	assert_eq(pos2, Vector2(100, 200),
		"post-defeat: objective must flip to the_question (was broken pre-tick-277)")

	# Restore state.
	if prior == null:
		GameState.game_constants.erase("cutscene_flag_world6_calibrant_defeat_complete")
	else:
		GameState.game_constants["cutscene_flag_world6_calibrant_defeat_complete"] = prior


# ── Cross-pin: GameLoop sets the flag via the canonical map ───────

func test_calibrant_flag_in_cutscene_completion_map() -> void:
	var gl: String = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	# The cutscene id → flag map (tick 220's _CUTSCENE_COMPLETION_FLAGS)
	# must include the calibrant defeat mapping. If this drifts, the
	# fix above also breaks (flag would never be set).
	assert_true(gl.contains("\"world6_calibrant_defeat\":") and gl.contains("\"cutscene_flag_world6_calibrant_defeat_complete\""),
		"GameLoop's _CUTSCENE_COMPLETION_FLAGS must map world6_calibrant_defeat → cutscene_flag_world6_calibrant_defeat_complete")
