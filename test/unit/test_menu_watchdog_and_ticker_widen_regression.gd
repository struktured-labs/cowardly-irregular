extends GutTest

## Live-playtest bugs from cowir-main msg 2372 (rogue-battle screenshot).
##
## Watchdog: when BattleScene sits in PLAYER_SELECTING for the current
## human PC and no command menu is up, the state must self-heal instead
## of soft-locking. The threshold is MENU_WATCHDOG_MS wall-clock so a
## thoughtful player still gets their menu on the first frame; only a
## legit failure-to-spawn trips it.
##
## Ticker: the bottom-center battle_log widget was ~400×66 clipping
## "Fighter selecting..." mid-line. It's now ~520×90, matching the hint-
## bar width (msg 2372 recommendation) and rendering one more line.

const BS_PATH: String = "res://src/battle/BattleScene.gd"
const BS_SCENE_PATH: String = "res://src/battle/BattleScene.tscn"


## ── Watchdog surface ───────────────────────────────────────────────────

func test_watchdog_constant_declared() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "const MENU_WATCHDOG_MS",
		"threshold must be a named const so it's greppable / tunable")
	assert_string_contains(src, "MENU_WATCHDOG_MS: int = 2500",
		"initial 2.5s threshold — clears the AI selection window with room and stops soft-locks fast")


func test_watchdog_helper_defined_and_wired_into_process() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "func _tick_menu_watchdog() -> void:",
		"the watchdog check lives in its own function so _process stays readable")
	var proc_idx: int = src.find("func _process(delta: float) -> void:")
	assert_gt(proc_idx, -1)
	var proc_body: String = src.substr(proc_idx, 900)
	assert_string_contains(proc_body, "_tick_menu_watchdog()",
		"_process must call the helper each frame — dropping this reintroduces the class of bug")


func test_watchdog_resets_on_wrong_state() -> void:
	# The elapsed timer must reset whenever the situation stops being "player
	# turn without a menu" — otherwise a stale ms carries into the next real
	# PLAYER_SELECTING and force-spawns instantly with 0 grace period.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var wd_idx: int = src.find("func _tick_menu_watchdog() -> void:")
	assert_gt(wd_idx, -1)
	var body: String = src.substr(wd_idx, 2000)
	# Count reset sites (each early return must clear _menu_wd_started_ms).
	assert_gt(body.count("_menu_wd_started_ms = 0"), 5,
		"every early-out branch in the watchdog must reset the timer — 6+ reset sites expected")


func test_watchdog_skips_trust_interrupt_window() -> void:
	# During a trust-interrupt window (queue #4 option a), state is still
	# PLAYER_SELECTING and no menu is open — but that's the DESIGN, not a
	# stall. Watchdog must consult BM.is_trust_interrupt_window_open first.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "is_trust_interrupt_window_open()",
		"trust window is a legitimate menu-closed state — do not spawn over it")


func test_watchdog_skips_spotlight_locked_pc() -> void:
	# Spotlight-locked PCs route to AI via _process_ai_selection which
	# advances the turn synchronously — they should never sit in
	# PLAYER_SELECTING long enough to trip. The pc-in-player_party check
	# implicitly covers "current is an enemy" but we also require alive.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var wd_idx: int = src.find("func _tick_menu_watchdog() -> void:")
	var body: String = src.substr(wd_idx, 2000)
	assert_string_contains(body, "pc in bm.player_party",
		"guard against enemy-turn false trips")
	assert_string_contains(body, "pc.is_alive",
		"a KO'd combatant shouldn't be spawning menus")


func test_watchdog_force_spawn_logs_loudly() -> void:
	# When the watchdog fires, both a push_warning (CI / logs) and a
	# battle_log_message (in-battle visible line) must go out so a live
	# hit is diagnosable even if the immediate recovery worked.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var wd_idx: int = src.find("func _tick_menu_watchdog() -> void:")
	var body: String = src.substr(wd_idx, 2000)
	assert_string_contains(body, "push_warning(\"[MENU-WATCHDOG]",
		"loud CI signal")
	assert_string_contains(body, "log_message(\"[color=orange]",
		"visible in-battle line — the player sees recovery, not a silent auto-fix")
	assert_string_contains(body, "_show_win98_command_menu(pc)",
		"the actual recovery: re-invoke the same menu-spawn call the normal path uses")


## ── Ticker widen ───────────────────────────────────────────────────────

func test_ticker_widened_to_hint_bar_width() -> void:
	# Hint bar is offset_left=-260 / offset_right=260 (520px). The ticker
	# must match so "Fighter selecting..." can't clip like it did in the
	# 2026-07-11 cap.
	var scene_src: String = FileAccess.get_file_as_string(BS_SCENE_PATH)
	var panel_idx: int = scene_src.find("[node name=\"BattleLogPanel\"")
	assert_gt(panel_idx, -1)
	var panel_block: String = scene_src.substr(panel_idx, 600)
	assert_string_contains(panel_block, "offset_left = -260.0",
		"widen to hint-bar left offset")
	assert_string_contains(panel_block, "offset_right = 260.0",
		"widen to hint-bar right offset")


func test_ticker_taller_by_one_line() -> void:
	var scene_src: String = FileAccess.get_file_as_string(BS_SCENE_PATH)
	var panel_idx: int = scene_src.find("[node name=\"BattleLogPanel\"")
	assert_gt(panel_idx, -1)
	var panel_block: String = scene_src.substr(panel_idx, 600)
	# 90px tall (-128 top, -38 bottom) — +24px vs the old 66, one more line.
	assert_string_contains(panel_block, "offset_top = -128.0")
	assert_string_contains(panel_block, "offset_bottom = -38.0")
	# BattleLog inner min-height matches.
	assert_string_contains(scene_src, "custom_minimum_size = Vector2(0, 80)",
		"inner RichTextLabel min-height must grow with the panel or content clips again")


func test_ticker_sits_above_hint_bar_with_a_small_gap() -> void:
	# Hint bar top is -34, ticker bottom is -38 → 4px gap. Regressing this
	# to overlap looks messy on small resolutions (the two panels stack).
	var scene_src: String = FileAccess.get_file_as_string(BS_SCENE_PATH)
	var panel_idx: int = scene_src.find("[node name=\"BattleLogPanel\"")
	var panel_block: String = scene_src.substr(panel_idx, 600)
	assert_string_contains(panel_block, "offset_bottom = -38.0",
		"ticker bottom must sit above hint-bar top (-34)")
