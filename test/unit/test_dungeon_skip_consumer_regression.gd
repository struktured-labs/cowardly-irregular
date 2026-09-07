extends GutTest

## tick 410: DragonCave._ready consumes the
## meta_dungeon_skip_pending flag (set by tick 403's BattleManager
## arm) so the Skiptrotter warp_to_boss meta-ability actually
## warps the player to the boss floor on next dungeon entry.
##
## Pre-fix the flag was set but no consumer read it; entering a
## dungeon after the cast just spawned the player at floor 1.

const DRAGON_CAVE_PATH := "res://src/maps/dungeons/DragonCave.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_consumer_block_exists() -> void:
	var src := _read(DRAGON_CAVE_PATH)
	var fn_idx: int = src.find("func _ready()")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("meta_dungeon_skip_pending"),
		"DragonCave._ready must read meta_dungeon_skip_pending flag")
	assert_true(body.contains("current_floor = total_floors"),
		"consumer must jump current_floor to total_floors (boss floor)")
	# Single-shot clear so the next normal entry doesn't auto-warp.
	assert_true(body.contains("\"meta_dungeon_skip_pending\"] = false"),
		"consumer must clear the flag after consuming (single-shot)")


func test_consumer_refuses_when_boss_defeated() -> void:
	# Don't strand the player in an empty boss room. Pin that the
	# consumer gates on `not boss_defeated`.
	var src := _read(DRAGON_CAVE_PATH)
	var fn_idx: int = src.find("func _ready()")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("skip_pending and not boss_defeated"),
		"consumer must refuse skip when boss is already defeated")


func test_consumer_persists_floor_in_game_constants() -> void:
	# Pin that the warped floor is also written to the saved floor key
	# so a subsequent save/load doesn't bounce the player back to 1.
	var src := _read(DRAGON_CAVE_PATH)
	var fn_idx: int = src.find("func _ready()")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("game_constants[floor_key] = total_floors"),
		"consumer must persist the warped floor so save/load preserves the warp")
