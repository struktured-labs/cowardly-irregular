extends GutTest

## struktured on .788 (main 23431): "Lv 2 Cleric healing with Sanatio was like 3-ish per cure, that's kinda terrible".
## Measured on his save (battle 23433): Sanatio's raw heal is ~683 HP against party max HP of 32-148, and the log
## printed what it RESTORED, capped at missing HP, so a full heal on a near-full ally read "+3". Now a heal that tops
## its target off says so: "(full)" in the log, a FULL banner on the popup.

const BattleState := preload("res://test/unit/helpers/battle_state.gd")

var _guard: RefCounted = null
var _lines: Array = []


func before_each() -> void:
	_guard = BattleState.new()
	_guard.snapshot()
	_lines.clear()
	BattleManager.battle_log_message.connect(_on_log)


func after_each() -> void:
	if BattleManager.battle_log_message.is_connected(_on_log):
		BattleManager.battle_log_message.disconnect(_on_log)
	if _guard != null:
		_guard.restore()


func _on_log(line: String) -> void:
	_lines.append(line)


func _unit(nm: String, max_hp: int, magic: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": max_hp, "max_mp": 50, "attack": 5, "defense": 5, "magic": magic, "speed": 5})
	add_child_autofree(c)
	return c


func _heal_line(nm: String) -> String:
	for l in _lines:
		if nm in str(l) and "recovers" in str(l):
			return str(l)
	return ""


func test_full_means_the_target_ended_at_max_hp() -> void:
	var u := _unit("Rogue", 80, 5)
	assert_true(BattleResultsDisplay.healed_to_full(u), "at max HP it is full")
	u.current_hp = 79
	assert_false(BattleResultsDisplay.healed_to_full(u), "one short is not full")
	u.current_hp = 0
	u.is_alive = false
	assert_false(BattleResultsDisplay.healed_to_full(u), "a fallen target is not 'full'")


func test_a_capped_sanatio_says_full_and_a_partial_one_does_not() -> void:
	var cleric := _unit("Cleric", 60, 20)
	var cure: Dictionary = JobSystem.get_ability("cure")
	assert_gt(BattleManager.heal_cast_amount(cleric, cure), 100, "CONTROL: Sanatio's raw heal dwarfs a 3 HP gap")
	var near := _unit("Rogue", 80, 5)
	near.current_hp = 77
	BattleManager._execute_healing_ability(cleric, cure, [near])
	var line := _heal_line("Rogue")
	assert_string_contains(line, "recovers", "CONTROL: the heal logged")
	assert_string_contains(line, "(full)", "a heal capped by missing HP says it topped the target off, not just '+3'")
	var deep := _unit("Fighter", 100000, 5)
	deep.current_hp = 10
	BattleManager._execute_healing_ability(cleric, cure, [deep])
	var line2 := _heal_line("Fighter")
	assert_string_contains(line2, "recovers", "CONTROL: the second heal logged")
	assert_false("(full)" in line2, "a heal that leaves the target short shows its full power and no '(full)'")
