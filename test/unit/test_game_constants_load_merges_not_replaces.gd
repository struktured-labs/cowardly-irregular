extends GutTest

## tick 112 regression: GameState.from_dict must MERGE the saved
## game_constants onto the default dict, not replace wholesale.
## Pre-fix, loading a save that predated any later-added key
## (exp_multiplier, encounter_rate, etc.) wiped the defaults — so
## consumers using direct dict access like
## `game_constants["gold_multiplier"]` crashed with KeyError on a
## save load that didn't include that key.
##
## The merge approach preserves both: saved daemon nudges win on
## conflict, defaults fill in any keys the save didn't have.

const GAME_STATE := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_load_merges_instead_of_replaces() -> void:
	# Pin: the source uses a merge loop, not a duplicate-and-replace.
	var src := _read(GAME_STATE)
	# Negative pin first: the old `game_constants = save_data[...].duplicate()`
	# replace pattern must be gone.
	assert_false(src.contains("game_constants = save_data[\"game_constants\"].duplicate()"),
		"GameState.from_dict must NOT replace game_constants wholesale — that wipes defaults for keys the save didn't include")
	# Positive pin: the merge loop.
	assert_true(src.contains("for key in saved.keys():"),
		"GameState.from_dict must merge saved keys into game_constants — preserves defaults for newer keys")
	assert_true(src.contains("game_constants[key] = saved[key]"),
		"merge loop must overwrite per-key — saved daemon nudges win on conflict, missing keys keep defaults")


func test_runtime_merge_preserves_default_for_missing_key() -> void:
	# Functional test: instantiate a GameState, simulate a load
	# with a save_data that's MISSING gold_multiplier. Verify the
	# default 1.0 survives.
	var gs_script := load(GAME_STATE)
	var gs = gs_script.new()
	# Defaults populated at construction time.
	assert_eq(float(gs.game_constants.get("gold_multiplier", -1.0)), 1.0,
		"gold_multiplier default must be 1.0")

	var save_data: Dictionary = {
		"game_constants": {
			# Saved daemon nudge for exp_multiplier only.
			"exp_multiplier": 1.10,
			# gold_multiplier deliberately omitted — simulates an old save.
		},
	}
	gs._apply_save_data(save_data)
	# After load: exp_multiplier reflects the nudge, gold_multiplier
	# keeps the default.
	assert_eq(float(gs.game_constants.get("exp_multiplier", -1.0)), 1.10,
		"saved exp_multiplier nudge must apply on load")
	assert_eq(float(gs.game_constants.get("gold_multiplier", -1.0)), 1.0,
		"gold_multiplier must keep default when save_data omits the key — merge instead of replace")
	gs.queue_free()


func test_runtime_merge_overwrites_when_saved_key_present() -> void:
	# When the save DOES carry a key, it must override the default.
	var gs_script := load(GAME_STATE)
	var gs = gs_script.new()
	var save_data: Dictionary = {
		"game_constants": {
			"gold_multiplier": 0.85,
			"exp_multiplier": 1.10,
			"encounter_rate": 1.05,
		},
	}
	gs._apply_save_data(save_data)
	assert_eq(float(gs.game_constants.get("gold_multiplier", -1.0)), 0.85)
	assert_eq(float(gs.game_constants.get("exp_multiplier", -1.0)), 1.10)
	assert_eq(float(gs.game_constants.get("encounter_rate", -1.0)), 1.05)
	gs.queue_free()


func test_unknown_saved_key_still_merged_into_dict() -> void:
	# Defensive: if a save contains a key NOT in the defaults (e.g.
	# Scriptweaver added a custom constant), the merge must still
	# preserve it. Replace semantics did this too; merge semantics
	# must keep doing it.
	var gs_script := load(GAME_STATE)
	var gs = gs_script.new()
	var save_data: Dictionary = {
		"game_constants": {
			"some_custom_scriptweaver_var": 42.0,
		},
	}
	gs._apply_save_data(save_data)
	assert_eq(float(gs.game_constants.get("some_custom_scriptweaver_var", -1.0)), 42.0,
		"merge must preserve saved keys not in the defaults — Scriptweaver may add custom constants")
	gs.queue_free()
