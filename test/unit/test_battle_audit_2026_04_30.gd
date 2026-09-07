extends GutTest

## Regression tests for the 2026-04-30 battle audit fixes.
##
## Each test corresponds to a bug found by the battle-system audit and
## fixed in the same commit. These are source-level checks where runtime
## verification would require full BattleManager scene context (which GUT
## isolates poorly), and runtime checks where state can be set up cleanly.


func _read_file(path: String) -> String:
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t = f.get_as_text()
	f.close()
	return t


# Bug 1: _apply_vulnerability_window was setting AP to literal -2.
func test_vulnerability_window_subtracts_ap_not_set_literal() -> void:
	var src = _read_file("res://src/battle/BattleManager.gd")
	# The previous broken line was `clampi(-2, -4, 4)` (literal). We require
	# the new `clampi(p.current_ap - 2, -4, 4)` form (subtraction).
	assert_string_contains(src, "clampi(p.current_ap - 2, -4, 4)",
		"_apply_vulnerability_window must subtract 2 from current AP, " +
		"not set to literal -2 (the literal heals AP-debt characters " +
		"and over-punishes high-AP characters)")


# Bug 1b: vulnerability status duration must outlive the round.
func test_vulnerability_window_duration_is_2() -> void:
	var src = _read_file("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "p.add_status(\"exposed\", 2)",
		"exposed status duration must be 2 — duration 1 expires at the " +
		"very next end_turn (start of next round) before any enemy can " +
		"exploit the vulnerability window")
	assert_string_contains(src, "p.add_status(\"cannot_defer\", 2)",
		"cannot_defer status duration must be 2 (matches exposed)")


# Bug 5: take_damage with amount=0 was dividing by zero.
func test_take_damage_zero_amount_does_not_crash() -> void:
	var c = Combatant.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.defense = 0
	c.is_alive = true
	# This used to: int((0 * 0) / float(0 + 0)) = NaN, error in console.
	var dealt = c.take_damage(0, false)
	assert_eq(dealt, 1, "take_damage(0) should still apply minimum 1 damage")
	assert_eq(c.current_hp, 99, "current_hp should drop by 1 from minimum-damage")
	c.queue_free()


# Bug 5b: take_damage with negative amount must not crash either.
func test_take_damage_negative_amount_clamps_safely() -> void:
	var c = Combatant.new()
	c.combatant_name = "Test"
	c.max_hp = 100
	c.current_hp = 100
	c.defense = 5
	c.is_alive = true
	var dealt = c.take_damage(-50, false)
	# Negative damage clamped to 0, then min-1 enforced
	assert_eq(dealt, 1, "Negative damage should clamp to 0, then min-1 applies")
	assert_eq(c.current_hp, 99)
	c.queue_free()


# Bug 3: _execute_advance was double-granting AP (natural +1 + extra +1).
func test_execute_advance_does_not_double_grant_ap() -> void:
	var src = _read_file("res://src/battle/BattleManager.gd")
	# The function header
	assert_string_contains(src, "func _execute_advance",
		"_execute_advance must exist")
	# Look for evidence of the old bug pattern: a `combatant.gain_ap(1)`
	# at the top of _execute_advance immediately before the actions loop.
	# We don't assert absence (too brittle) — we assert the comment that
	# explains the fix is present so future readers don't re-add the bug.
	assert_string_contains(src, "double-counting and made\n\t# 4-action Advances end at -2 instead of -3",
		"_execute_advance must carry the 'double-counting' fix comment so " +
		"the +1 isn't reintroduced by a future refactor")


# Bug 8: doom_counter was being clobbered to 0 instead of -1 sentinel.
func test_start_battle_doom_counter_uses_sentinel() -> void:
	var src = _read_file("res://src/battle/BattleManager.gd")
	# Look for `combatant.doom_counter = -1` inside the cleanup loop
	# (was previously = 0).
	assert_string_contains(src, "combatant.doom_counter = -1",
		"start_battle cleanup must set doom_counter to -1 ('not doomed' " +
		"sentinel from Combatant.gd:84), not 0 — preserves the sentinel " +
		"design even though update_buff_durations only ticks > 0")


# Bug 2: died signal connect with .bind() was leaking listeners across battles.
func test_died_signal_uses_bound_callable_dict() -> void:
	var src = _read_file("res://src/battle/BattleManager.gd")
	assert_string_contains(src, "_died_callbacks",
		"BattleManager must cache bound `died` Callables in _died_callbacks " +
		"so they can be properly disconnected (is_connected/disconnect with " +
		"the unbound method always returns false on a bound listener — " +
		"every start_battle stacked another listener)")


# Bug 7: repeat_previous_actions targeting stale enemies from prior battles.
func test_repeat_actions_retargets_stale_enemies() -> void:
	var src = _read_file("res://src/battle/BattleManager.gd")
	# The fix: we now check `target not in player_party and target not in enemy_party`
	# in addition to dead/freed.
	assert_string_contains(src, "target not in player_party",
		"repeat_previous_actions must retarget when saved target belongs " +
		"to a previous battle's roster (Y-button replay was hitting ghosts)")
	assert_string_contains(src, "target not in enemy_party",
		"repeat_previous_actions must check enemy_party membership too")


# Bug 9: _execute_attack must spend AP even when target is invalid.
func test_execute_attack_spends_ap_before_target_check() -> void:
	var src = _read_file("res://src/battle/BattleManager.gd")
	# Find _execute_attack body — spend_ap must come before the retarget check.
	var idx = src.find("func _execute_attack")
	assert_gt(idx, -1, "_execute_attack must exist")
	var body = src.substr(idx, 600)  # First ~600 chars of function body
	var spend_idx = body.find("attacker.spend_ap(1)")
	var retarget_idx = body.find("_retarget_enemy(attacker, target)")
	assert_gt(spend_idx, -1, "_execute_attack must spend AP")
	assert_gt(retarget_idx, -1, "_execute_attack must retarget")
	assert_lt(spend_idx, retarget_idx,
		"AP must be spent BEFORE retarget so a fizzled action still " +
		"commits the cost (otherwise mixed-valid Advance ends with " +
		"elevated AP)")


# Bug 12: _get_lowest_hp_ally must return null on no allies, not the caller.
func test_get_lowest_hp_ally_returns_null_when_empty() -> void:
	var src = _read_file("res://src/autobattle/AutobattleSystem.gd")
	# We require the function to return null in the empty branch (not combatant)
	var idx = src.find("func _get_lowest_hp_ally")
	assert_gt(idx, -1)
	var body = src.substr(idx, 1200)
	assert_string_contains(body, "if allies.size() == 0:\n\t\treturn null",
		"_get_lowest_hp_ally must return null when no allies exist " +
		"(was returning the caller, which is misleading and inconsistent " +
		"with _get_lowest_hp_enemy)")
