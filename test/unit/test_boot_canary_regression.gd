extends GutTest

## Boot canary (2026-07-01 gray-void post-mortem). New class_name
## scripts merged without a --import leave the global class cache
## stale; dependent scene scripts fail to parse and the game boots
## into an empty default-clear (#4d4d4d) viewport with live input —
## 37 SCRIPT ERRORs buried in a log the player never sees. Real
## incident: FastTravelMenu + HiddenPassage merges → OverworldScene +
## SavePoint compile cascade → user's new game froze on a gray void.
##
## GameLoop._ready now try-loads a list of load-bearing scripts and
## puts an actionable fullscreen message up when any fail.

const GAME_LOOP_PATH := "res://src/GameLoop.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_canary_helper_exists_and_runs_first() -> void:
	var src := _read(GAME_LOOP_PATH)
	assert_true(src.contains("func _check_boot_canaries"),
		"GameLoop must declare _check_boot_canaries")
	var ready_idx: int = src.find("func _ready")
	var next_fn: int = src.find("\nfunc ", ready_idx + 1)
	var body: String = src.substr(ready_idx, next_fn - ready_idx)
	assert_true(body.contains("_check_boot_canaries()"),
		"_ready must invoke the boot canary")
	# It must run BEFORE the equipment-pool init (i.e. first real work).
	var canary_idx: int = body.find("_check_boot_canaries()")
	var equip_idx: int = body.find("_init_equipment_pool()")
	assert_gt(equip_idx, -1)
	assert_lt(canary_idx, equip_idx,
		"canary must run before any other boot work so the overlay wins the frame")


func test_canary_list_covers_incident_cascade_roots() -> void:
	var src := _read(GAME_LOOP_PATH)
	assert_true(src.contains("res://src/exploration/OverworldScene.gd"),
		"canary list must include OverworldScene (cascade root of the real incident)")
	assert_true(src.contains("res://src/exploration/SavePoint.gd"),
		"canary list must include SavePoint (the other cascade root)")
	assert_true(src.contains("res://src/battle/BattleScene.gd"),
		"canary list must include BattleScene (battle-side load-bearing)")


func test_failure_path_is_loud_and_actionable() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _check_boot_canaries")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("push_error"),
		"each failed canary must push_error (log trail)")
	assert_true(body.contains("CanvasLayer"),
		"failure must build an on-screen overlay — the log alone is what failed the player last time")
	assert_true(body.contains("launch.sh") and body.contains("--import"),
		"overlay text must name the actual fix (launch.sh / --import), not just complain")


func test_runtime_canaries_all_load_in_healthy_env() -> void:
	# In a healthy checkout (this test run), every canary must load.
	# If THIS test fails, the checkout itself has a compile break —
	# which is exactly the situation the canary exists to catch.
	for path in ["res://src/exploration/OverworldScene.gd",
			"res://src/exploration/SavePoint.gd",
			"res://src/battle/BattleScene.gd"]:
		var s: Variant = load(path)
		assert_not_null(s, "%s must load in a healthy environment" % path)
