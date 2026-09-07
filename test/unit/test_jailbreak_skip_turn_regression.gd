extends GutTest

## Wave F R1 regression test — landed boss jailbreak with consequence
## `skip_turn` (the documented outcome of "appeal_old_loyalty" et al.) must
## actually CAUSE the boss to skip its next action, not just apply a status
## the engine ignores.
##
## Bug summary: `BattleManager._on_boss_jailbreak_succeeded` applied a
## `cannot_act` status but no code in `_execute_next_action` consumed it,
## so the boss would still take its queued action normally — silently
## reducing every landed jailbreak to a flavor line.
##
## Fix: added a `cannot_act` consumer alongside the existing `stun` check
## in `_execute_next_action` (BattleManager.gd ~:1655). This test pins it.


# Build a minimal Combatant standin (no JobSystem dependency) so the
# regression check stays surgical.
func _make_boss() -> Combatant:
	var c := Combatant.new()
	c.combatant_name = "TestBoss"
	c.max_hp = 100
	c.current_hp = 100
	c.max_mp = 50
	c.current_mp = 50
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 10
	c.is_alive = true
	return c


func test_cannot_act_status_is_added_and_persists_after_skip_turn_jailbreak() -> void:
	# The status the jailbreak path adds must match what _execute_next_action
	# consumes. The bug was a literal name mismatch ("cannot_act" added,
	# only "stun" / "sleep" consumed).
	var boss := _make_boss()
	add_child_autofree(boss)
	boss.add_status("cannot_act", 2)
	assert_true(boss.has_status("cannot_act"),
		"cannot_act must be addable as a status — Combatant.add_status path")
	assert_eq(int(boss.status_durations.get("cannot_act", 0)), 2,
		"duration must round-trip into status_durations")


func test_cannot_act_status_decrements_on_consumption() -> void:
	# Verify the duration-tick semantics the BattleManager skip consumer uses.
	# When remaining > 1, decrement; when remaining <= 1, remove.
	var boss := _make_boss()
	add_child_autofree(boss)
	boss.add_status("cannot_act", 2)
	# Simulate one tick (mirror the consumer's logic without spinning up
	# a full BattleManager — keeps the regression test fast & deterministic).
	var remaining: int = int(boss.status_durations.get("cannot_act", 1))
	assert_eq(remaining, 2)
	# After one consumption, duration should drop to 1 and status persist.
	if remaining > 1:
		boss.status_durations["cannot_act"] = remaining - 1
	else:
		boss.remove_status("cannot_act")
	assert_true(boss.has_status("cannot_act"), "1-remaining: status still present")
	assert_eq(int(boss.status_durations.get("cannot_act", 0)), 1)
	# Second consumption should clear it.
	remaining = int(boss.status_durations.get("cannot_act", 1))
	if remaining > 1:
		boss.status_durations["cannot_act"] = remaining - 1
	else:
		boss.remove_status("cannot_act")
	assert_false(boss.has_status("cannot_act"), "0-remaining: status removed")


func test_battle_manager_has_cannot_act_consumer() -> void:
	# Source-level guard: make sure the cannot_act check survives in the
	# behavioral status block. Without this someone could "clean up" the
	# regression fix and silently re-break landed jailbreaks.
	var bm_src := FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	assert_true(bm_src != "",
		"BattleManager.gd must be readable from disk")
	assert_true(bm_src.find("has_status(\"cannot_act\")") != -1,
		"BattleManager._execute_next_action must consume 'cannot_act' " +
		"so landed boss jailbreaks actually skip the boss's turn")
