extends GutTest

## tick 150 regression: GameState._apply_save_data must MERGE
## meta_features onto the default dict, not REPLACE the dict
## wholesale. Same silent-failure class as the tick-112 fix for
## game_constants.
##
## Pre-fix: a save written by an older game version (missing a
## key that newer versions added to the meta_features defaults)
## would lose that default on load. Consumers reading the missing
## key would crash on KeyError or silently fall through to a
## non-default fallback that wasn't expected.
##
## meta_features defaults: {autosave_enabled, rewind_enabled,
## restore_points_enabled, max_restore_points}. If any future
## version adds a default-true flag and an old save loads, the
## replace pattern would silently set it to false.

const GAME_STATE := "res://src/meta/GameState.gd"
const MARKER_KEY := "tick_150_future_default_flag"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_apply_save_data_uses_merge_loop_for_meta_features() -> void:
	# Pin: the load path iterates saved_meta.keys() and assigns
	# into the existing meta_features dict.
	var src := _read(GAME_STATE)
	assert_true(src.contains("var saved_meta: Dictionary = save_data[\"meta_features\"]"),
		"_apply_save_data must capture saved meta into a local var")
	assert_true(src.contains("for key in saved_meta.keys():"),
		"_apply_save_data must iterate saved keys, NOT replace the dict")
	assert_true(src.contains("meta_features[key] = saved_meta[key]"),
		"_apply_save_data must assign per-key into the existing dict")


func test_apply_save_data_no_longer_replaces_meta_features() -> void:
	# Negative pin: the old replace pattern must be gone.
	var src := _read(GAME_STATE)
	assert_false(src.contains("meta_features = save_data[\"meta_features\"].duplicate()"),
		"old `meta_features = save_data['meta_features'].duplicate()` replace pattern must be gone — was the silent-overwrite bug")


func test_runtime_old_save_keeps_future_defaults() -> void:
	# Simulates loading a save that was written by an older version
	# (missing a key that the newer version adds as a default).
	# After merge, the new default key survives.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing in test env")
		return
	# Snapshot original state for restoration.
	var original: Dictionary = gs.meta_features.duplicate()
	# Inject a "future default" key as if the current GameState
	# version added it to defaults.
	gs.meta_features[MARKER_KEY] = true
	# Build a "save_data" that came from an OLDER version that
	# doesn't have the marker key.
	var old_save_meta: Dictionary = {
		"autosave_enabled": true,  # explicitly set in old save
		"rewind_enabled": false,
	}
	var fake_save: Dictionary = {"meta_features": old_save_meta}
	gs._apply_save_data(fake_save)
	# The merge must preserve the new default while still applying
	# the explicitly-saved overrides.
	var merged_has_marker: bool = gs.meta_features.has(MARKER_KEY)
	var merged_marker_value: bool = bool(gs.meta_features.get(MARKER_KEY, false))
	var merged_autosave: bool = bool(gs.meta_features.get("autosave_enabled", false))
	# Restore.
	gs.meta_features = original
	assert_true(merged_has_marker,
		"future default key must survive a load from an old save — was the silent-overwrite bug pre-tick-150")
	assert_true(merged_marker_value,
		"future default value must be preserved verbatim")
	assert_true(merged_autosave,
		"explicitly-saved override must still apply (autosave_enabled was true in the fake save)")


func test_save_data_overrides_take_priority_over_defaults() -> void:
	# Pin: when the save HAS a key, the saved value wins. This is
	# the symmetric case to the future-default test above.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing in test env")
		return
	var original: Dictionary = gs.meta_features.duplicate()
	# Force a default that doesn't match what the save will set.
	gs.meta_features["rewind_enabled"] = false
	var fake_save: Dictionary = {
		"meta_features": {"rewind_enabled": true}
	}
	gs._apply_save_data(fake_save)
	var post: bool = bool(gs.meta_features.get("rewind_enabled", false))
	gs.meta_features = original
	assert_true(post,
		"explicitly-saved rewind_enabled=true must override the false default")


func test_game_constants_merge_pattern_still_present() -> void:
	# Negative regression: don't accidentally regress tick 112's
	# merge fix while updating meta_features.
	var src := _read(GAME_STATE)
	assert_true(src.contains("var saved: Dictionary = save_data[\"game_constants\"]"),
		"game_constants merge loop (tick 112) must still be present")
	assert_true(src.contains("game_constants[key] = saved[key]"),
		"game_constants per-key assign must still be present")
