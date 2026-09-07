extends GutTest

## Scriptweaver flagship fix (2026-07-09): constant_modification and
## code_inspection were ATMOSPHERIC NO-OPS — 25/15 MP casts that emitted a
## magenta line, added corruption, and changed nothing (the death_sentence
## class at flagship scale). Now: Modify Constant turns ONE tunable dial
## ±10% (clamped 0.5..2.0) through GameState.modify_constant; Analyze Code
## reveals the real speed-sorted execution order. edit_formula stays
## atmospheric but its description now admits it.

const DIALS := ["exp_multiplier", "gold_multiplier", "damage_multiplier",
	"healing_multiplier", "drop_rate_multiplier", "encounter_rate"]

var _log_lines: Array = []


func _capture(line: String) -> void:
	_log_lines.append(line)


func _make_caster() -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": "Weaver", "max_hp": 50, "max_mp": 99, "attack": 5,
		"defense": 5, "magic": 20, "speed": 10})
	return c


func before_each() -> void:
	_log_lines.clear()
	BattleManager.battle_log_message.connect(_capture)


func after_each() -> void:
	BattleManager.battle_log_message.disconnect(_capture)


func test_constant_modification_actually_turns_a_dial() -> void:
	var before := {}
	for d in DIALS:
		before[d] = float(GameState.game_constants.get(d, 1.0))
	var prev_corruption: float = GameState.corruption_level
	var caster := _make_caster()

	BattleManager._execute_meta_ability(caster,
		{"id": "modify_constant", "meta_effect": "constant_modification", "corruption_risk": 0.1}, [])

	var changed: Array = []
	for d in DIALS:
		var now := float(GameState.game_constants.get(d, 1.0))
		if not is_equal_approx(now, before[d]):
			changed.append(d)
			assert_true(now >= 0.5 and now <= 2.0, "%s stayed clamped (got %f)" % [d, now])
			GameState.game_constants[d] = before[d]
	assert_eq(changed.size(), 1, "exactly ONE dial turns per cast (got %s)" % str(changed))
	assert_gt(GameState.corruption_level, prev_corruption, "the modification corrupts")
	GameState.corruption_level = prev_corruption
	assert_true(_log_lines.any(func(l): return "reaches into the constants" in str(l)),
		"the log names the dial and the change")


func test_code_inspection_reveals_execution_order() -> void:
	var caster := _make_caster()
	var prev_party: Array = BattleManager.player_party
	var prev_enemies = BattleManager.enemy_party
	BattleManager.player_party = [caster]
	BattleManager.enemy_party = []

	BattleManager._execute_meta_ability(caster,
		{"id": "analyze_code", "meta_effect": "code_inspection"}, [])

	BattleManager.player_party = prev_party
	BattleManager.enemy_party = prev_enemies
	assert_true(_log_lines.any(func(l): return "Execution order" in str(l) and "Weaver" in str(l)),
		"the reveal lists real combatants with speeds — not just flavor")


func test_edit_formula_description_admits_the_resistance() -> void:
	var ab: Dictionary = JobSystem.get_ability("edit_formula")
	assert_true("resist" in str(ab.get("description", "")).to_lower(),
		"edit_formula's tooltip must not promise a rewrite it doesn't perform")
