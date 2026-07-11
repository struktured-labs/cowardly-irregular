extends GutTest

## tick 308: SaveSystem._apply_save_data writes MapSystem.current_map_id
## UNCONDITIONALLY before calling load_map, so dungeon/interior saves
## survive the round-trip.
##
## Pre-fix the load flow was:
##   1. SaveSystem.load_data reads data["map"]["current_map_id"]
##   2. Calls MapSystem.load_map(saved_map_id)
##   3. MapSystem._get_map_path only handles 3 ids (overworld /
##      harmonia_village / whispering_cave). For everything else it
##      returns a path that doesn't exist; load_map push_errors +
##      early-returns at line 50 WITHOUT touching current_map_id.
##   4. GameLoop._restore_party_from_save_data then reads
##      MapSystem.current_map_id to sync its own _current_map_id (tick
##      307). But MapSystem.current_map_id was never updated — sat at
##      "" or the previous value. So the player ended up on whatever
##      GameLoop was already showing (typically "overworld") regardless
##      of where they actually saved.
##
## Post-fix: SaveSystem sets MapSystem.current_map_id from the saved
## value BEFORE the load_map call. load_map's success path overwrites
## with the same value (harmless); its failure path leaves our pre-set
## value intact. GameLoop._restore_party_from_save_data then reads the
## correct value and routes to the right scene.

const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"
const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: SaveSystem writes current_map_id before load_map ────

func test_savesystem_writes_map_id_unconditionally() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	# 2026-07-11: the legacy load_map call is GONE — it double-built the
	# overworld on Continue (stacked Mode 7 overlays). The hand-off is now
	# assignment-only; GameLoop owns every scene build.
	var assign_idx: int = src.find("MapSystem.current_map_id = saved_map_id")
	assert_gt(assign_idx, -1,
		"SaveSystem must write MapSystem.current_map_id directly from saved value")
	assert_eq(src.find("MapSystem.load_map(saved_map_id)"), -1,
		"state restore must never build scenes — the legacy call double-built the overworld")


# ── Source pin: GameLoop reads MapSystem.current_map_id after restore ─

func test_gameloop_syncs_from_mapsystem_after_restore() -> void:
	var src := _read(GAME_LOOP_PATH)
	# _restore_party_from_save_data should call _set_current_map_id with
	# the value read from MapSystem.current_map_id.
	var fn_idx: int = src.find("func _restore_party_from_save_data")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("MapSystem.current_map_id"),
		"_restore_party_from_save_data must read MapSystem.current_map_id (the canonical post-load location)")
	assert_true(body.contains("_set_current_map_id"),
		"_restore_party_from_save_data must call _set_current_map_id to route _start_exploration correctly")


# ── Behavioral: dungeon round-trip preserves the map_id ─────────────

func test_dungeon_save_writes_correct_map_id_to_mapsystem() -> void:
	# Real autoload — available in GUT.
	assert_not_null(MapSystem, "MapSystem autoload required")
	if MapSystem == null:
		return

	# Simulate save data with a dungeon map_id that ISN'T in
	# MapSystem._get_map_path's lookup table — the exact failure case.
	var fake_save := {
		"map": {"current_map_id": "fire_dragon_cave"},
		# Minimal extra fields to avoid downstream null derefs (the
		# function still tries to apply player position / party / etc
		# after the map block; empty defaults are fine).
	}

	var prior: String = MapSystem.current_map_id
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)

	# _apply_save_data is the inner workhorse SaveSystem.load_game calls.
	# Calling it directly skips the file-IO and lets us control the data.
	ss._apply_save_data(fake_save)

	assert_eq(MapSystem.current_map_id, "fire_dragon_cave",
		"Even though MapSystem.load_map('fire_dragon_cave') push_errors and early-returns, MapSystem.current_map_id must reflect the saved value because SaveSystem set it directly first")

	# Restore.
	MapSystem.current_map_id = prior


# ── Behavioral: known mapped id still works post-fix ────────────────

func test_overworld_save_still_works_after_fix() -> void:
	# Regression: don't break the 3 mapped ids by routing around load_map.
	assert_not_null(MapSystem, "MapSystem autoload required")
	if MapSystem == null:
		return

	var fake_save := {"map": {"current_map_id": "overworld"}}
	var prior: String = MapSystem.current_map_id
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	ss._apply_save_data(fake_save)

	# After load_map succeeds, current_map_id should be "overworld" (same
	# value — assignment is idempotent).
	assert_eq(MapSystem.current_map_id, "overworld",
		"overworld save (one of the 3 paths MapSystem._get_map_path handles) must still round-trip correctly")

	MapSystem.current_map_id = prior


# ── Empty / missing map block must not crash ────────────────────────

func test_missing_map_block_is_tolerated() -> void:
	# Legacy saves may not have a "map" key at all. The fix shouldn't
	# regress that path — the block is guarded by `if data.has("map")`.
	var script: GDScript = load(SAVE_SYSTEM_PATH)
	var ss: Object = script.new()
	add_child_autofree(ss)
	# Passing an empty dict should be a no-op for the map branch.
	ss._apply_save_data({})
	# If we got here, no crash. Source-pin the guard for posterity.
	var src := _read(SAVE_SYSTEM_PATH)
	assert_true(src.contains("if data.has(\"map\"):"),
		"empty-map guard must be preserved")
