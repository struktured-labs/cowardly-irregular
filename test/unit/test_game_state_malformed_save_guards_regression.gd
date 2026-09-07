extends GutTest

## tick 363: GameState._apply_save_data type-guards Dictionary/Array
## fields before reading them so a corrupted save with null/int/string
## in game_constants / meta_features / story_flags / corruption_effects
## warns + skips instead of crashing the load path.
##
## Pre-fix:
##   var saved: Dictionary = save_data["game_constants"]
##       # ↑ raises "Trying to assign a value of type 'X' to a variable
##       #   of type 'Dictionary'" if game_constants is null/int/etc.
##   story_flags = save_data["story_flags"].duplicate()
##       # ↑ raises "Invalid call .duplicate() on base: 'Nil'"
##   for ce in save_data["corruption_effects"]:
##       # ↑ raises "Cannot iterate" if corruption_effects isn't iterable
##
## Same defensive shape as tick 362's player.position guard in SaveSystem.

const GAME_STATE_PATH := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: type guards exist for each fragile field ────────────

func test_apply_save_data_guards_game_constants() -> void:
	var src := _read(GAME_STATE_PATH)
	# Window: from _apply_save_data start to next func.
	var fn_idx: int = src.find("func _apply_save_data")
	assert_gt(fn_idx, -1, "_apply_save_data must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("raw_gc is Dictionary"),
		"game_constants must be type-guarded before merge — pre-fix typed-var assignment crashed on non-Dict")
	assert_true(body.contains("raw_meta is Dictionary"),
		"meta_features must be type-guarded before merge")
	assert_true(body.contains("raw_sf is Dictionary"),
		"story_flags must be type-guarded before .duplicate()")
	assert_true(body.contains("raw_ce is Array"),
		"corruption_effects must be type-guarded before iteration")
	# Warnings must surface the corruption, not silently swallow.
	assert_true(body.contains("game_constants malformed"),
		"malformed game_constants must surface as push_warning")


# ── Behavioral: null game_constants doesn't crash ───────────────────

func test_null_game_constants_does_not_crash() -> void:
	# We don't want to mutate the actual GameState autoload across tests,
	# so spin up a fresh instance just for this assertion. The autoload
	# stays untouched.
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	# Pre-fix would crash on `var saved: Dictionary = save_data["game_constants"]`
	# because typed assignment from Nil errors out.
	gs._apply_save_data({"game_constants": null})
	# Survival: game_constants stays as default (not corrupted to {}).
	assert_eq(typeof(gs.game_constants), TYPE_DICTIONARY,
		"game_constants must stay Dict after malformed-save load — no crash, no overwrite to non-Dict")


# ── Behavioral: int meta_features doesn't crash ─────────────────────

func test_int_meta_features_does_not_crash() -> void:
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	gs._apply_save_data({"meta_features": 42})
	assert_eq(typeof(gs.meta_features), TYPE_DICTIONARY,
		"meta_features must stay Dict after malformed-save load")


# ── Behavioral: null story_flags doesn't crash ──────────────────────

func test_null_story_flags_does_not_crash() -> void:
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	# Pre-fix crashed on .duplicate() of null.
	gs._apply_save_data({"story_flags": null})
	assert_eq(typeof(gs.story_flags), TYPE_DICTIONARY,
		"story_flags must stay Dict after malformed-save load")


# ── Behavioral: int corruption_effects doesn't crash ────────────────

func test_int_corruption_effects_does_not_crash() -> void:
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	# Pre-fix crashed on `for ce in 42:` with cannot-iterate error.
	gs._apply_save_data({"corruption_effects": 42})
	# Survival: corruption_effects stays as a typed array (default []).
	assert_eq(typeof(gs.corruption_effects), TYPE_ARRAY,
		"corruption_effects must stay Array after malformed-save load")


# ── Behavioral: valid shapes still load ─────────────────────────────

func test_valid_shapes_still_apply() -> void:
	# Ensure the guards didn't accidentally reject well-formed saves.
	var script: GDScript = load(GAME_STATE_PATH)
	var gs: Object = script.new()
	add_child_autofree(gs)
	gs._apply_save_data({
		"game_constants": {"exp_multiplier": 1.5},
		"meta_features": {"some_flag": true},
		"story_flags": {"hero_intro_complete": true},
		"corruption_effects": ["stuttering_text"],
	})
	assert_eq(gs.game_constants.get("exp_multiplier", null), 1.5,
		"well-formed game_constants must be merged in")
	assert_eq(gs.meta_features.get("some_flag", null), true,
		"well-formed meta_features must be merged in")
	assert_eq(gs.story_flags.get("hero_intro_complete", null), true,
		"well-formed story_flags must be loaded")
	assert_true("stuttering_text" in gs.corruption_effects,
		"well-formed corruption_effects must be loaded")
