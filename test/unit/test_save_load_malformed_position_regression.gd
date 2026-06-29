extends GutTest

## tick 362: SaveSystem._apply_save_data validates data["player"]["position"]
## shape before reading x/y instead of trusting the saved JSON.
##
## Pre-fix the load path read:
##   var pos = data["player"]["position"]
##   pending_player_position = Vector2(pos["x"], pos["y"])
##
## A hand-edited / partially-corrupted save where "position" is null,
## empty {}, an int, or a non-Dict (or where {"x": ..., "y": ...} is
## missing one key) crashed the title-screen Continue path with
## `Invalid get index 'x' on base: 'Nil'` (or similar). The crash left
## the player with no recovery path other than deleting the save.
##
## Post-fix verifies `pos is Dictionary and pos.has("x") and pos.has("y")`
## before constructing the Vector2 and otherwise pushes a warning and
## skips the position restore — the player keeps the default spawn
## marker (a survivable degraded state) instead of crashing.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: shape guard exists in _apply_save_data ──────────────

func test_apply_save_data_guards_position_shape() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _apply_save_data")
	assert_gt(fn_idx, -1, "_apply_save_data must exist")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The shape guard must check Dictionary + both keys.
	assert_true(body.contains("pos is Dictionary"),
		"_apply_save_data must verify pos is Dictionary before indexing")
	assert_true(body.contains("pos.has(\"x\")") and body.contains("pos.has(\"y\")"),
		"_apply_save_data must verify pos.has('x') and pos.has('y')")
	# The else branch must surface the corruption as a warning.
	assert_true(body.contains("player.position malformed"),
		"_apply_save_data must push_warning when position is malformed (silent skip would re-introduce the bug class)")


# ── Behavioral: null position does not crash ────────────────────────

func test_null_position_does_not_crash() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# Pre-fix this would crash on pos["x"] with Invalid get index on Nil.
	ss._apply_save_data({"player": {"position": null}})
	# Survival: pending stays at the INF sentinel.
	assert_eq(ss.pending_player_position, Vector2.INF,
		"null position must leave pending_player_position at the sentinel — no crash, no consume")


# ── Behavioral: empty Dict position does not crash ──────────────────

func test_empty_dict_position_does_not_crash() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# Pre-fix this would crash on pos["x"] with Invalid get index on {}.
	ss._apply_save_data({"player": {"position": {}}})
	assert_eq(ss.pending_player_position, Vector2.INF,
		"empty-Dict position must leave pending_player_position at the sentinel")


# ── Behavioral: half-missing key does not crash ─────────────────────

func test_missing_y_does_not_crash() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# A truncated save where only "x" got written. Pre-fix crashed on pos["y"].
	ss._apply_save_data({"player": {"position": {"x": 100.0}}})
	assert_eq(ss.pending_player_position, Vector2.INF,
		"position with only one of x/y must leave pending at sentinel — both keys required")


# ── Behavioral: int (non-Dict) position does not crash ──────────────

func test_int_position_does_not_crash() -> void:
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# A save where someone hand-edited position to a plain int. Pre-fix
	# would have crashed at `pos["x"]` with Invalid get index on a base int.
	ss._apply_save_data({"player": {"position": 42}})
	assert_eq(ss.pending_player_position, Vector2.INF,
		"non-Dict position must leave pending at sentinel")


# ── Behavioral: valid shape still works (regression check on the guard) ─

func test_valid_position_still_applies() -> void:
	# Confirm the guard didn't accidentally reject the well-formed case.
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	ss._apply_save_data({"player": {"position": {"x": 123.5, "y": -67.25}}})
	assert_eq(ss.pending_player_position, Vector2(123.5, -67.25),
		"well-formed position must still be applied — guard must not over-reject")
