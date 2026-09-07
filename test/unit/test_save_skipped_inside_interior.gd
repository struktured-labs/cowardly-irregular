extends GutTest

## tick 74 regression: auto-save and quick-save must be blocked while
## the player is inside an interior. Interiors bypass MapSystem
## entirely (GameLoop loads them via scene-routing, not
## MapSystem.load_map), so MapSystem.current_map_id is stale —
## saving would record the wrong map and resume would fail.

const GAME_LOOP := "res://src/GameLoop.gd"
const SAVE_SYSTEM := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_game_loop_exposes_is_inside_interior() -> void:
	# Pin the public API SaveSystem queries. If this method is renamed
	# or removed, the SaveSystem gate becomes a no-op silently (its
	# has_method check just returns false).
	var src := _read(GAME_LOOP)
	assert_true(src.contains("func is_inside_interior() -> bool"),
		"GameLoop.is_inside_interior() must exist — SaveSystem._is_player_inside_interior calls it via has_method")
	assert_true(src.contains("return _current_map_id in INTERIOR_MAP_IDS"),
		"is_inside_interior must check _current_map_id against INTERIOR_MAP_IDS")


func test_can_quick_save_blocks_when_inside_interior() -> void:
	var src := _read(SAVE_SYSTEM)
	var idx: int = src.find("func can_quick_save")
	assert_gt(idx, -1, "can_quick_save must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("_is_player_inside_interior()"),
		"can_quick_save must invoke _is_player_inside_interior — auto-save and quick-save both depend on this gate")
	# And the result of that check must short-circuit to false (return early).
	# Pin the specific pattern.
	assert_true(body.contains("if _is_player_inside_interior():\n\t\treturn false"),
		"can_quick_save must return false when player is inside an interior — letting it through would corrupt the save")


func test_save_system_finds_game_loop_via_scene_root() -> void:
	# SaveSystem can't import GameLoop (it'd be a circular dep). It
	# must look it up via get_tree().current_scene. Pin that pattern.
	var src := _read(SAVE_SYSTEM)
	var idx: int = src.find("func _is_player_inside_interior")
	assert_gt(idx, -1, "_is_player_inside_interior helper must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("get_tree().current_scene"),
		"SaveSystem._is_player_inside_interior must look up GameLoop via get_tree().current_scene")
	assert_true(body.contains("has_method(\"is_inside_interior\")"),
		"SaveSystem must guard with has_method check — keeps unit tests / non-game contexts permissive")


func test_post_transition_auto_save_skipped_for_interior() -> void:
	# Defense in depth: even if can_quick_save gate were bypassed,
	# the post-transition auto-save call site explicitly skips
	# "interior" transition type.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("if transition_type != \"interior\" and SaveSystem and SaveSystem.has_method(\"auto_save\")"),
		"post-transition auto-save must explicitly skip transition_type == 'interior' — belt + suspenders with the can_quick_save gate")


func test_get_current_map_id_exposed_for_introspection() -> void:
	# Public accessor used by the gate. Pin it so a rename doesn't
	# silently break the SaveSystem call chain.
	var src := _read(GAME_LOOP)
	assert_true(src.contains("func get_current_map_id() -> String"),
		"GameLoop must expose get_current_map_id() — used by external systems that need to query location")
