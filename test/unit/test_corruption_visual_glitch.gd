extends GutTest

## Feature 2026-07-05: save-corruption "visual_glitch" was authored (added to
## GameState.corruption_effects when a save corrupts) but had NO runtime handler
## — it silently no-op'd, flagged in BattleManager's push_warning list. It now
## drives a cosmetic chromatic screen-stutter at the top of each battle round
## (BattleScene._on_round_started_corruption_glitch, gated on the static
## _corruption_glitch_active predicate). Cosmetic only — zero balance impact.
## Turns "save corruption: actual mechanic, not just flavor" one notch more real.

const BS := preload("res://src/battle/BattleScene.gd")

var _saved: Array[String] = []


func before_each() -> void:
	_saved = GameState.corruption_effects.duplicate()


func after_each() -> void:
	GameState.corruption_effects = _saved


func _set_effects(effects: Array) -> void:
	var typed: Array[String] = []
	for e in effects:
		typed.append(str(e))
	GameState.corruption_effects = typed


func test_inactive_when_no_corruption() -> void:
	_set_effects([])
	assert_false(BS._corruption_glitch_active(), "no corruption → no glitch")


func test_active_when_visual_glitch_present() -> void:
	_set_effects(["visual_glitch"])
	assert_true(BS._corruption_glitch_active(), "visual_glitch corruption → glitch active")


func test_inactive_for_other_corruption() -> void:
	_set_effects(["encounter_surge", "stat_drain"])
	assert_false(BS._corruption_glitch_active(), "unrelated corruption effects don't trigger the glitch")


func test_handler_wired_to_round_started() -> void:
	# Source-pin: the handler must be connected to (and disconnected from)
	# round_started, or the effect never fires in a real battle.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")
	assert_string_contains(src, "round_started.connect(_on_round_started_corruption_glitch)",
		"the glitch handler must be connected to round_started")
	assert_string_contains(src, "round_started.disconnect(_on_round_started_corruption_glitch)",
		"the glitch handler must be disconnected in teardown")


func test_removed_from_unimplemented_warning_list() -> void:
	# visual_glitch now has a handler, so it must NOT still sit in BattleManager's
	# unimplemented-corruption push_warning loop.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var idx: int = src.find("for unimplemented in [")
	assert_gt(idx, -1, "the unimplemented-corruption loop must still exist")
	var line: String = src.substr(idx, 120)
	assert_false(line.contains("visual_glitch"),
		"visual_glitch is implemented now — it must leave the unimplemented warning list")
