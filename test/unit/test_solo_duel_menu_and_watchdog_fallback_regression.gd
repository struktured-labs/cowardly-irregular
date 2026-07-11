extends GutTest

## Cowir-main msg 2379 (urgent): the watchdog LOOPED in the rogue spotlight
## duel because _show_win98_command_menu had its own autobattle_locked early
## return — my earlier BM routing fix only overrode the BM-level gate.
##
## Fix: the menu-spawn code needs the same solo-duel override, and the
## watchdog needs a retry cap + terminal fallback so a real spawn failure
## can never wedge the battle.

const BS_PATH: String = "res://src/battle/BattleScene.gd"
const BCM_PATH: String = "res://src/battle/BattleCommandMenu.gd"


## ── Menu-spawn solo-duel override ──────────────────────────────────────

func test_command_menu_has_own_solo_duel_on_spotlight_gate() -> void:
	# Struktured's msg 2379 root cause: the spotlight autobattle_locked
	# gate in BattleCommandMenu.show_win98_command_menu returns before the
	# menu opens, so the watchdog force-spawns → gate returns again → loop.
	# A player_party of size 1 whose sole member IS the locked PC is inside
	# their own spotlight duel — that's the intended manual-control case.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	var idx: int = src.find("autobattle_locked")
	assert_gt(idx, -1, "spotlight gate must exist")
	var window: String = src.substr(idx, 800)
	assert_string_contains(window, "own_solo_duel",
		"the spotlight gate must recognize the solo-duel case explicitly")
	assert_string_contains(window, "BattleManager.player_party.size() == 1",
		"solo duel = player_party of size 1")
	assert_string_contains(window, "combatant in BattleManager.player_party",
		"and the combatant asking for a menu IS the sole duelist")


func test_debug_and_solo_duel_are_both_honored_before_early_return() -> void:
	# Both escape hatches must gate the return statement — either debug
	# unlock or solo duel keeps the menu opening.
	var src: String = FileAccess.get_file_as_string(BCM_PATH)
	var idx: int = src.find("autobattle_locked")
	var window: String = src.substr(idx, 800)
	assert_string_contains(window, "not debug_override and not own_solo_duel",
		"BOTH escape hatches must gate the early return")


## ── Watchdog retry cap ─────────────────────────────────────────────────

func test_watchdog_max_retries_declared() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "const MENU_WATCHDOG_MAX_RETRIES",
		"retry cap must be a named const for greppability")
	assert_string_contains(src, "MENU_WATCHDOG_MAX_RETRIES: int = 3",
		"3 attempts is enough to clear one-off races without pounding a truly broken spawn")


func test_watchdog_has_retry_counter_and_increments_on_force_spawn() -> void:
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	assert_string_contains(src, "var _menu_wd_retries: int = 0",
		"retry counter must be a persistent field, not a local")
	var wd_idx: int = src.find("func _tick_menu_watchdog() -> void:")
	assert_gt(wd_idx, -1)
	var body: String = src.substr(wd_idx, 3000)
	assert_string_contains(body, "_menu_wd_retries += 1",
		"each force-spawn attempt must count toward the cap")


func test_watchdog_terminal_fallback_routes_via_autobattle() -> void:
	# When the retry cap trips, the battle CANNOT wedge — msg 2379.
	# BattleManager.execute_autobattle_for_current queues a basic attack
	# for the current combatant via the autobattle path, guaranteeing the
	# turn advances even if the menu genuinely can't spawn.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var wd_idx: int = src.find("func _tick_menu_watchdog() -> void:")
	var body: String = src.substr(wd_idx, 3000)
	assert_string_contains(body, "_menu_wd_retries >= MENU_WATCHDOG_MAX_RETRIES",
		"terminal branch must consult the cap")
	assert_string_contains(body, "execute_autobattle_for_current",
		"terminal fallback routes via autobattle so the battle CANNOT wedge")
	assert_string_contains(body, "push_error(\"[MENU-WATCHDOG]",
		"terminal fallback must log LOUDLY — push_error, not just push_warning")


func test_watchdog_reset_helper_clears_retries_too() -> void:
	# The helper must clear BOTH the timestamp and retry counter — otherwise
	# a stale count carries into the next PLAYER_SELECTING and the very
	# first spawn attempt hits the cap and terminal-fallbacks immediately.
	var src: String = FileAccess.get_file_as_string(BS_PATH)
	var reset_idx: int = src.find("func _reset_menu_watchdog() -> void:")
	assert_gt(reset_idx, -1)
	var reset_body: String = src.substr(reset_idx, 200)
	assert_string_contains(reset_body, "_menu_wd_retries = 0",
		"stale retry count would poison the next PLAYER_SELECTING")


func test_execute_autobattle_for_current_exists_on_battle_manager() -> void:
	# The terminal fallback names this method — if BattleManager ever
	# renames or removes it, the fallback becomes a silent no-op and the
	# battle wedges again. Pin the API.
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "func execute_autobattle_for_current",
		"terminal-fallback contract with BattleManager must be maintained")
