extends GutTest

## tick 174 regression: defer log emit centralized in
## BattleManager.player_defer so every caller path gets it
## exactly once. Pre-fix three callers (BattleScene R-key,
## BattleCommandMenu win98 defer, BattleCommandMenu address-
## action) emitted their own log lines, but two other callers
## (legacy button at BattleScene._on_default_pressed and the
## Bossbinder Mind Swap path) silently entered player_defer
## without logging — player saw nothing and wondered if their
## defer went through.
##
## Centralizing in BattleManager solves two problems at once:
##   1. The two silent paths now log automatically.
##   2. The "X defers!" line surfaces consistently regardless
##      of which input path the player used.
##
## Caller-side pre-emits are removed to prevent double-logging.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"
const BATTLE_SCENE := "res://src/battle/BattleScene.gd"
const BATTLE_COMMAND := "res://src/battle/BattleCommandMenu.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Centralized emit in BattleManager.player_defer ──────────────────────

func test_player_defer_emits_log_in_battle_manager() -> void:
	# Pin: the defer log fragment lives inside player_defer body.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func player_defer")
	assert_gt(idx, -1, "player_defer must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("battle_log_message.emit(\"[color=cyan]%s defers![/color]\" % current_combatant.combatant_name)"),
		"player_defer must emit the canonical defer log line — drives consistent feedback across all caller paths")


func test_defer_log_inside_success_branch() -> void:
	# Critical: the emit must be AFTER the cannot_defer guard and
	# AFTER _queue_action. Otherwise we'd log "X defers!" even for
	# blocked defers (cannot_defer status) where the function
	# returns early.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func player_defer")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	var cannot_defer_idx: int = body.find("if current_combatant.has_status(\"cannot_defer\"):")
	var defer_log_idx: int = body.find("battle_log_message.emit(\"[color=cyan]%s defers![/color]\"")
	var queue_action_idx: int = body.find("_queue_action(action)")
	assert_gt(cannot_defer_idx, -1)
	assert_gt(defer_log_idx, -1)
	assert_gt(queue_action_idx, -1)
	assert_lt(cannot_defer_idx, defer_log_idx,
		"defer log must be AFTER cannot_defer guard — else blocked defers also log")
	assert_lt(queue_action_idx, defer_log_idx,
		"defer log must be AFTER _queue_action — confirms action queued before announcing")


# ── Caller-side pre-emits removed (prevent double-log) ──────────────────

func test_battle_scene_r_key_no_longer_pre_emits_defer_log() -> void:
	var src := _read(BATTLE_SCENE)
	# The R-key handler should still call player_defer but not pre-emit.
	# Find the R-key block.
	var idx: int = src.find("if event.keycode == KEY_R and is_player_selecting")
	assert_gt(idx, -1, "R-key block must exist")
	# Walk forward ~300 chars to find the player_defer call.
	var window: String = src.substr(idx, 400)
	# Negative pin: no pre-emit log_message defer in this window.
	assert_false(window.contains("log_message(\"[color=cyan]%s defers![/color]\""),
		"BattleScene R-key path must NOT pre-emit defer log — centralized in BattleManager.player_defer")
	# Positive pin: still calls player_defer.
	assert_true(window.contains("BattleManager.player_defer()"),
		"BattleScene R-key path must still call player_defer")


func test_command_menu_defer_no_longer_pre_emits() -> void:
	var src := _read(BATTLE_COMMAND)
	# The win98 defer (item_id == "defer") path.
	var idx: int = src.find("if item_id == \"defer\":")
	assert_gt(idx, -1, "win98 defer dispatch must exist")
	var window: String = src.substr(idx, 250)
	assert_false(window.contains("log_message(\"[color=cyan]%s defers![/color]\""),
		"BattleCommandMenu win98 defer must NOT pre-emit defer log")
	assert_true(window.contains("BattleManager.player_defer()"),
		"BattleCommandMenu win98 defer must still call player_defer")


func test_win98_defer_requested_handler_no_longer_pre_emits() -> void:
	var src := _read(BATTLE_COMMAND)
	# _on_win98_defer_requested signal handler.
	var idx: int = src.find("func _on_win98_defer_requested")
	assert_gt(idx, -1, "_on_win98_defer_requested must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_false(body.contains("log_message(\"[color=cyan]%s defers![/color]\""),
		"_on_win98_defer_requested must NOT pre-emit defer log — centralized")
	assert_true(body.contains("BattleManager.player_defer()"),
		"_on_win98_defer_requested must still call player_defer")


# ── Pre-existing emit branches preserved ────────────────────────────────

func test_cannot_defer_log_preserved() -> void:
	# The "cannot defer while exposed!" branch must NOT lose its emit
	# while we're refactoring. Tick 237 swapped the literal [color=red]
	# for AccessibilityPalette.penalty_bbcode() — the invariant (red
	# in default mode, distinguishable color name in CB mode) holds
	# either way. Pin both shapes so this stays robust.
	var src := _read(BATTLE_MANAGER)
	var has_legacy: bool = src.contains("[color=red]%s cannot defer while exposed![/color]")
	var has_palette: bool = src.contains("[color=%s]%s cannot defer while exposed![/color]\" % [AccessibilityPalette.penalty_bbcode(), current_combatant.combatant_name]")
	assert_true(has_legacy or has_palette,
		"cannot_defer guard's log emit must remain (legacy [color=red] OR tick 237 penalty_bbcode shape)")


func test_print_statement_for_debug_preserved() -> void:
	# Non-regression: debug overlay print stays.
	var src := _read(BATTLE_MANAGER)
	var idx: int = src.find("func player_defer")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	assert_true(body.contains("print(\"%s chooses to defer\""),
		"player_defer print() preserved for debug overlay")
