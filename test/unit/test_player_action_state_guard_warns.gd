extends GutTest

## tick 231: surfaces state-machine bugs at the 7 player action
## entry points + 1 autobattle entry that previously silently
## `return`d on state mismatch.
##
## Pre-fix flow at each site:
##   func player_X(...) -> void:
##       if current_state != BattleState.PLAYER_SELECTING:
##           return
##       ...
##
## Player input arriving outside PLAYER_SELECTING is always a
## bug: the UI shouldn't even be showing a clickable Attack
## button during enemy execution, autobattle phase, etc. But the
## silent return swallowed the diagnostic — the dev only saw
## "button click did nothing" with no editor log to trace.
##
## Fix: a shared _check_player_selecting_state helper that
## push_warns naming the calling action AND the current state
## (so devs see WHICH UI button arrived in WHICH bad state).
## Returns false; caller still returns. Identical behavior at
## runtime, loud diagnostic in editor + CI logs.
##
## go_back_to_previous_player at line ~884 is intentionally left
## with its existing print + battle_log_message — that one's
## designed for player-facing feedback, not dev surfacing.

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Helper exists and warns ──────────────────────────────────────────

func test_helper_function_present() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("func _check_player_selecting_state(action_name: String) -> bool:"),
		"_check_player_selecting_state helper must exist")


func test_helper_returns_true_when_in_state() -> void:
	var src := _read(BATTLE_MANAGER)
	var fn_idx: int = src.find("func _check_player_selecting_state")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("if current_state == BattleState.PLAYER_SELECTING:"),
		"helper must check positive state")
	assert_true(body.contains("return true"),
		"helper must return true when in selecting state")


func test_helper_warns_with_action_name_and_state() -> void:
	var src := _read(BATTLE_MANAGER)
	var fn_idx: int = src.find("func _check_player_selecting_state")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("push_warning"),
		"helper must push_warning on state mismatch")
	assert_true(body.contains("called outside PLAYER_SELECTING"),
		"warning must explicitly name the violated state")
	assert_true(body.contains("UI state-machine bug"),
		"warning must hint at the likely root cause")
	# Action name + current_state name both in the format string.
	assert_true(body.contains("BattleState.keys()[current_state]"),
		"warning must include the current state name (not just the enum int)")


# ── All 8 sites use the helper ───────────────────────────────────────

func test_all_8_call_sites_use_helper() -> void:
	# Pin count: exactly 8 occurrences of the helper call.
	var src := _read(BATTLE_MANAGER)
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find("_check_player_selecting_state(", idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	# 1 declaration + 7 call sites... actually 8 because each call site
	# also counts the literal _check_player_selecting_state token.
	# Let me count distinct call sites by looking for the full pattern.
	var call_count: int = 0
	idx = 0
	while true:
		var next: int = src.find("if not _check_player_selecting_state(\"", idx)
		if next < 0:
			break
		call_count += 1
		idx = next + 1
	assert_eq(call_count, 7,
		"7 entry points (attack/use_ability/defer/advance/group_attack/item/execute_autobattle) must use the helper. Got %d." % call_count)


func test_specific_action_names_pinned() -> void:
	var src := _read(BATTLE_MANAGER)
	# Each entry point passes its function name as the action_name
	# argument so warnings are immediately traceable.
	for action_name in ["player_attack", "player_use_ability", "player_defer",
			"player_advance", "player_group_attack", "player_item",
			"execute_autobattle_for_current"]:
		var pattern: String = "_check_player_selecting_state(\"%s\")" % action_name
		assert_true(src.contains(pattern),
			"site must pass action_name '%s' to the helper" % action_name)


# ── Negative pins: old bare state-guard sites gone ───────────────────

func test_no_more_bare_state_guard_returns_in_player_functions() -> void:
	var src := _read(BATTLE_MANAGER)
	# Pre-fix shape `if current_state != BattleState.PLAYER_SELECTING:`
	# directly followed by `return` (with nothing else). Count.
	# The go_back function legitimately uses this pattern but has a
	# battle_log emit BEFORE the return — different from the silent
	# fall-through we're refactoring.
	# Search for the exact silent-fall-through pattern.
	var silent_pattern: String = "if current_state != BattleState.PLAYER_SELECTING:\n\t\treturn"
	var count: int = 0
	var idx: int = 0
	while true:
		var next: int = src.find(silent_pattern, idx)
		if next < 0:
			break
		count += 1
		idx = next + 1
	# After tick 231 refactor, no silent-return pattern should remain in
	# the player_* / execute_autobattle entry points. go_back uses a
	# DIFFERENT shape (print before return) so it's excluded.
	assert_eq(count, 0,
		"all bare silent-return state guards in player_* entry points must be replaced by the helper. Got %d." % count)


# ── go_back's existing player-facing feedback preserved ──────────────

func test_go_back_player_facing_feedback_preserved() -> void:
	# Cross-pin: go_back_to_previous_player keeps its existing
	# print + battle_log_message approach. That's intentional —
	# player-facing buttons need IN-GAME feedback (not just editor
	# warnings).
	var src := _read(BATTLE_MANAGER)
	var fn_idx: int = src.find("func go_back_to_previous_player")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx)
	assert_true(body.contains("print(\"Cannot go back"),
		"go_back's existing print preserved (intentional player-feedback design)")


# ── Cross-pin: tick 221 silent-fail audit work preserved ─────────────

func test_tick_221_execute_ability_warnings_preserved() -> void:
	var src := _read(BATTLE_MANAGER)
	# Spot-check the tick 221 push_warning at _execute_ability.
	assert_true(src.contains("[BattleManager] _execute_ability: '%s' insufficient MP after can_use_ability check passed"),
		"tick 221 MP shortfall warning preserved")
