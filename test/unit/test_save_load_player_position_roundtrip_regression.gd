extends GutTest

## tick 309: player position survives Continue / quick_load across a
## scene swap.
##
## Pre-fix SaveSystem._apply_save_data called player.teleport(pos) on
## whatever player happened to be in the tree at load time (typically
## the title screen's residual or a stale scene's). GameLoop then ran
## _start_exploration() which queue_free()'d that scene and instantiated
## the saved map's scene. The new scene's player spawned at the default
## spawn marker (via spawn_player_at) — saved position silently lost
## every Continue from anywhere except the in-overworld autosave path
## (where the current scene happened to match the saved map).
##
## Post-fix has three pieces:
##   1. SaveSystem exposes pending_player_position (Vector2.INF sentinel).
##   2. _apply_save_data writes it from data["player"]["position"] in
##      addition to the legacy in-place teleport.
##   3. GameLoop._restore_party_from_save_data pulls it into
##      _player_position and clears the SaveSystem field.
##   4. _start_exploration consumes _player_position AFTER spawn_player_at
##      so the saved coords override the default spawn marker.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: SaveSystem.pending_player_position field exists ─────

func test_pending_position_field_exists() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	assert_true(src.contains("var pending_player_position: Vector2"),
		"SaveSystem must declare pending_player_position field")
	assert_true(src.contains("Vector2.INF"),
		"sentinel must be Vector2.INF (distinguishes 'no pending' from a real (0,0) position)")


# ── Source pin: _apply_save_data populates the field ────────────────

func test_apply_save_data_writes_pending_position() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	var fn_idx: int = src.find("func _apply_save_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("pending_player_position = Vector2(pos["),
		"_apply_save_data must write pending_player_position from data[\"player\"][\"position\"]")


# ── Source pin: GameLoop consumes the field and clears it ───────────

func test_gameloop_consumes_and_clears_pending() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _restore_party_from_save_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("SaveSystem.pending_player_position"),
		"_restore_party_from_save_data must read SaveSystem.pending_player_position")
	assert_true(body.contains("_player_position = pending"),
		"must copy into _player_position so _start_exploration can apply it")
	assert_true(body.contains("SaveSystem.pending_player_position = Vector2.INF"),
		"must clear the SaveSystem field after consuming")


# ── Source pin: _start_exploration applies _player_position ─────────

func test_start_exploration_applies_player_position() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _start_exploration")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Find spawn_player_at and the position-override block.
	var spawn_idx: int = body.find("spawn_player_at(_spawn_point)")
	var pos_idx: int = body.find("_player_position != Vector2.ZERO")
	assert_gt(spawn_idx, -1, "_start_exploration must call spawn_player_at")
	assert_gt(pos_idx, -1, "_start_exploration must check _player_position pending value")
	assert_lt(spawn_idx, pos_idx,
		"position override must apply AFTER spawn_player_at so it overrides the default marker (else the marker overrides our value)")
	assert_true(body.contains("_player_position = Vector2.ZERO"),
		"_start_exploration must clear _player_position after consuming")


# ── Behavioral: _apply_save_data stashes position for dungeon save ──

func test_dungeon_save_stashes_position_into_pending() -> void:
	# This is the actual bug scenario — saved at dungeon coords, loaded
	# while not on the dungeon scene (typical Continue-from-title).
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# Pre-state.
	assert_eq(ss.pending_player_position, Vector2.INF,
		"pending_player_position must start at the INF sentinel")
	var fake_save := {
		"player": {"position": {"x": 1500.0, "y": 800.0}},
	}
	ss._apply_save_data(fake_save)
	assert_eq(ss.pending_player_position, Vector2(1500.0, 800.0),
		"_apply_save_data must stash the saved position into pending_player_position regardless of whether teleport succeeded against the (likely stale) current scene's player")


# ── Behavioral: missing position field leaves pending at sentinel ───

func test_no_position_leaves_sentinel() -> void:
	# Legacy save without player.position must not crash and must not
	# overwrite pending_player_position (still at INF sentinel).
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	ss._apply_save_data({})  # No "player" key at all.
	assert_eq(ss.pending_player_position, Vector2.INF,
		"empty save must leave pending_player_position at the INF sentinel — no pending consume")
