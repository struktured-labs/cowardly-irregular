extends GutTest

## v3.33.197 shipped the GameState day/night clock (day_phase 0..1 +
## get_time_of_day_name() → "dawn"|"day"|"dusk"|"night" +
## time_of_day_changed signal + 24-min cycle + save-persisted). Music
## night bus + interior tint were wired to it in the same batch.
##
## BattleBackground had the READY infrastructure to react — enum TimeOfDay
## {DAWN, DAY, DUSK, NIGHT}, TIME_TINTS table with per-band r/g/b/
## brightness offsets, set_time_of_day() setter that triggers _draw_
## background — but ZERO callers outside the file. Battle backgrounds
## always rendered at DAY regardless of the clock.
##
## Cycle 10 wires the two directions:
##   1. Initial read on _ready:      GameState.get_time_of_day_name() → set_time_of_day
##   2. Live update via signal:      time_of_day_changed → _on_time_of_day_changed
##
## Symmetric disconnect on _exit_tree (cycle 6 discipline) so scene
## teardown never leaves a stale handler on the GameState autoload.
##
## All GameState calls are defensive-guarded — helper no-ops if the
## clock API isn't loaded (headless GUT env, older save loaded during
## an API migration, etc). Same discipline the night_monster_multiplier
## seam uses in BattleEnemySpawner.

const BB_PATH: String = "res://src/battle/BattleBackground.gd"
const BBScript = preload("res://src/battle/BattleBackground.gd")


## ── Wire surface pinned ────────────────────────────────────────────────

func test_sync_helper_declared() -> void:
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	assert_string_contains(src, "func _sync_to_game_state_clock() -> void:",
		"the sync helper must exist so initial state and signal wire live in one place")


func test_ready_calls_sync_helper() -> void:
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	var idx: int = src.find("func _ready() -> void:")
	assert_gt(idx, -1)
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 500)
	assert_string_contains(body, "_sync_to_game_state_clock()",
		"_ready must call the sync helper — otherwise every fresh BattleBackground starts locked at DAY")


func test_exit_tree_disconnects() -> void:
	# Cycle 6 discipline (BattleScene→BattleManager symmetric disconnects
	# msg 2621) applies here too: BattleBackground subscribes to a signal
	# on a persistent autoload (GameState), so scene teardown MUST
	# disconnect explicitly. Auto-cleanup on Node free covers the leak in
	# practice — the explicit disconnect matches the pattern the rest of
	# the codebase uses.
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	assert_string_contains(src, "func _exit_tree() -> void:",
		"_exit_tree must exist to symmetrize the connect discipline")
	assert_string_contains(src, "func _disconnect_game_state_clock() -> void:",
		"the disconnect helper must exist as the other side of _sync_to_game_state_clock")


func test_signal_connect_is_guarded_and_dedupe() -> void:
	# Two guards required at the connect site:
	#   1. has_signal("time_of_day_changed") — GameState API drift safe.
	#   2. not already connected — a double-_ready (unlikely but possible
	#      via scene reset) shouldn't stack the handler.
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	var idx: int = src.find("func _sync_to_game_state_clock() -> void:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1200)
	assert_string_contains(body, "has_signal(\"time_of_day_changed\")",
		"connect must guard on has_signal so API drift doesn't push_error")
	assert_string_contains(body, "not gs.time_of_day_changed.is_connected(_on_time_of_day_changed)",
		"connect must guard against double-connection")


func test_signal_disconnect_matches_connect_guards() -> void:
	# Disconnect must use the SAME guards or a rare shutdown case where
	# GameState was re-instantiated between connect and disconnect can
	# push_error on an unmatched disconnect.
	var src: String = FileAccess.get_file_as_string(BB_PATH)
	var idx: int = src.find("func _disconnect_game_state_clock() -> void:")
	var next: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, (next - idx) if next > -1 else 1000)
	assert_string_contains(body, "has_signal(\"time_of_day_changed\")",
		"disconnect must mirror the has_signal guard from connect")
	assert_string_contains(body, "gs.time_of_day_changed.is_connected(_on_time_of_day_changed)",
		"disconnect must guard on already-connected so re-instantiated GameState doesn't crash")


## ── Name → enum mapping is total + safe ────────────────────────────────

func test_name_to_enum_maps_all_four_bands() -> void:
	# Contract with GameState.get_time_of_day_name(): returns exactly
	# "dawn" | "day" | "dusk" | "night". Any drift (extra bands, casing
	# shifts) must degrade gracefully to DAY rather than blank the
	# background.
	assert_eq(BBScript._time_of_day_from_name("dawn"), BBScript.TimeOfDay.DAWN)
	assert_eq(BBScript._time_of_day_from_name("day"), BBScript.TimeOfDay.DAY)
	assert_eq(BBScript._time_of_day_from_name("dusk"), BBScript.TimeOfDay.DUSK)
	assert_eq(BBScript._time_of_day_from_name("night"), BBScript.TimeOfDay.NIGHT)


func test_name_to_enum_case_insensitive() -> void:
	# GameState currently returns lowercase strings but that could shift.
	# Handle mixed case explicitly so a Title-Case migration doesn't blank
	# the wire.
	assert_eq(BBScript._time_of_day_from_name("NIGHT"), BBScript.TimeOfDay.NIGHT,
		"upper case maps to same enum — case-insensitive contract")
	assert_eq(BBScript._time_of_day_from_name("Dawn"), BBScript.TimeOfDay.DAWN,
		"title case maps to same enum")


func test_unknown_name_falls_back_to_day() -> void:
	# Data drift safety: unknown band names return DAY, not the last enum
	# value or a random pick. Matches the "at 1.0 identity" defensive
	# pattern from the night-scaling seam.
	assert_eq(BBScript._time_of_day_from_name(""), BBScript.TimeOfDay.DAY,
		"empty band → DAY fallback")
	assert_eq(BBScript._time_of_day_from_name("midnight"), BBScript.TimeOfDay.DAY,
		"unknown band → DAY fallback (data drift safety)")


## ── Behavioral: helper is a no-op when GameState is missing ───────────

## Extends BattleBackground so we can call the helpers directly without
## needing a full BattleScene. Extended class works because BattleBackground
## extends Control which is instantiable.
func test_sync_is_noop_without_game_state() -> void:
	# Standard headless GUT env has no GameState autoload. The helper
	# must not crash — same discipline as apply_night_scaling_to_stats.
	var bg = BBScript.new()
	add_child_autofree(bg)
	# Calling the sync helper here must silently no-op without a
	# GameState node in the tree.
	bg._sync_to_game_state_clock()
	# If we reached this point without a crash, the guard worked.
	assert_eq(bg.current_time_of_day, bg.TimeOfDay.DAY,
		"without a GameState in the tree, the background stays at its default DAY state")


func test_disconnect_is_noop_without_game_state() -> void:
	# Same defense on the teardown side — scene teardown running before
	# GameState is available (e.g. during test env spin-down) must not
	# crash.
	var bg = BBScript.new()
	add_child_autofree(bg)
	bg._disconnect_game_state_clock()
	# Reaching this point without a crash confirms the guard.
	assert_true(true, "disconnect helper survived a missing-GameState environment")
