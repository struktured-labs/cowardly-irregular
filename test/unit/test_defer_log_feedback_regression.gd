extends GutTest

## Feedback gap 2026-07-04: _execute_defer only print()'d "X defers" to
## the debug console — it emitted NO battle_log_message. So Defer, a
## deliberate defensive choice with a 50% incoming-damage reduction, was
## completely silent in the in-game log; the player queued it, it ran,
## and nothing confirmed they were now protected. Attacks/abilities/items
## all log; defer was the odd one out. Now it emits a shield line.

const BM := preload("res://src/battle/BattleManager.gd")


func test_defer_emits_a_battle_log_line() -> void:
	var bm = BM.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Guard"
	c.is_alive = true
	var logs: Array = []
	bm.battle_log_message.connect(func(m): logs.append(str(m)))
	bm._execute_defer(c)
	var found := false
	for l in logs:
		if "defends" in l:
			found = true
	assert_true(found, "deferring must emit a battle-log line confirming the defensive stance")


func test_defer_actually_sets_defending_state() -> void:
	# Cross-check the log claim matches the mechanic it describes.
	var bm = BM.new()
	add_child_autofree(bm)
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Guard"
	c.is_alive = true
	c.is_defending = false
	bm._execute_defer(c)
	assert_true(c.is_defending, "the log says 'defends' — is_defending must actually be set (−50% incoming)")


func test_source_uses_battle_log_not_only_print() -> void:
	var src: String = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")
	var fn: int = src.find("func _execute_defer")
	var body: String = src.substr(fn, 300)
	assert_true(body.contains("battle_log_message.emit"),
		"_execute_defer must emit to the battle log, not just print() to the debug console")
