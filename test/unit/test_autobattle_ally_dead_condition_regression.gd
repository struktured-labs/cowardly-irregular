extends GutTest

## `ally_dead` — the condition a revival rule needs, which the grammar did not have.
##
## Revival was armed on 2026-09-09 (a0de2c2c) in both halves of the pipeline, and then could not
## be TRIGGERED by anything a player can author. Of the nineteen shipped grid conditions, not one
## can observe a death: every ally helper filters is_alive, so ally_hp_percent and ally_mp_percent
## see only the living, and the sole proxy was `ally_count <= N` — which requires the author to
## know their own party size and silently means something different in a 3-party than a 5-party.
##
## NULLARY, following the is_night ruling (cowir-ai msg 2916/2959): no operator, no value, nothing
## the Rule Composer LLM can malform. "Someone fell" has no parameter.

var _abs: Node = null
var _fixture_ids: Array[String] = []
var _p_backup: Array = []
var _e_backup: Array = []
var _bm: Node = null


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_bm = get_node_or_null("/root/BattleManager")
	if _bm:
		_p_backup = _bm.player_party.duplicate()
		_e_backup = _bm.enemy_party.duplicate()
	_fixture_ids.clear()


func after_each() -> void:
	if _bm:
		_bm.player_party.clear()
		_bm.enemy_party.clear()
		for c in _p_backup:
			_bm.player_party.append(c)
		for c in _e_backup:
			_bm.enemy_party.append(c)
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _member(cname: String, job_id: String, lvl: int = 10) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 400, "max_mp": 80,
		"attack": 20, "defense": 30, "magic": 30, "speed": 12
	})
	if job_id != "":
		c.job = JobSystem.get_job(job_id)
	c.job_level = lvl
	add_child_autofree(c)
	return c


func _punching_bag() -> Combatant:
	var e := Combatant.new()
	e.initialize({
		"name": "AllyDead Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1
	})
	add_child_autofree(e)
	return e


func _register(party: Array, foes: Array) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	for c in party:
		_bm.player_party.append(c)
	for c in foes:
		_bm.enemy_party.append(c)


func test_ally_dead_is_false_while_the_party_stands_and_true_once_it_does_not() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var cleric := _member("AllyDead Cleric", "cleric")
	var mate := _member("AllyDead Mate", "fighter")
	_register([cleric, mate], [_punching_bag()])
	var cond := {"type": "ally_dead"}

	assert_false(_abs._evaluate_grid_condition(cleric, cond),
		"control: with the whole party alive ally_dead must be FALSE — a condition that is always true would pass the second half of this test for the wrong reason")

	mate.current_hp = 0
	mate.is_alive = false
	assert_true(_abs._evaluate_grid_condition(cleric, cond),
		"ally_dead must be true once a party member is down")


func test_ally_dead_ignores_a_fallen_ENEMY() -> void:
	## The helper reads the caster's OWN party. A dead enemy is not an ally down, and a rule that
	## fired on enemy corpses would cast raise every round of a winning fight.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var cleric := _member("Side Cleric", "cleric")
	var mate := _member("Side Mate", "fighter")
	var foe := _punching_bag()
	_register([cleric, mate], [foe])
	foe.current_hp = 0
	foe.is_alive = false
	assert_false(_abs._evaluate_grid_condition(cleric, {"type": "ally_dead"}),
		"a fallen ENEMY is not an ally down")


func test_the_validator_accepts_a_nullary_ally_dead_rule() -> void:
	## Registered in CONDITION_TYPES is what makes the rule saveable and the picker offer it.
	## An evaluator arm alone ships a condition the editor rejects.
	var errors: Array = _abs.validate_rule({
		"conditions": [{"type": "ally_dead"}],
		"actions": [{"type": "ability", "id": "raise", "target": "lowest_hp_ally"}],
		"enabled": true,
	})
	assert_eq(errors.size(), 0,
		"a nullary ally_dead rule must validate with no op and no value — got %s" % str(errors))
	var bogus: Array = _abs.validate_rule({
		"conditions": [{"type": "ally_definitely_not_a_real_type"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
		"enabled": true,
	})
	assert_gt(bogus.size(), 0,
		"control: the validator must still reject an unregistered condition type, or the check above proves nothing")


func test_an_ally_dead_rule_actually_raises_the_fallen_in_a_grind() -> void:
	## End-to-end through the real selector: the condition, the dead_ally targeting and the
	## revival arm are three separate pieces and this is the first thing that needs all three.
	var cleric := _member("Grind Cleric", "cleric")
	var fallen := _member("Grind Fallen", "fighter")
	assert_true(cleric.knows_ability("raise"), "precondition: the Cleric fixture knows raise")
	var cid: String = cleric.combatant_name.to_lower().replace(" ", "_")
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"rules": [
		{"conditions": [{"type": "ally_dead"}],
		 "actions": [{"type": "ability", "id": "raise", "target": "lowest_hp_ally"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	]})

	fallen.current_hp = 0
	fallen.is_alive = false
	assert_false(fallen.is_alive, "precondition: the ally starts the battle down")

	var resolver := HeadlessBattleResolver.new()
	var result: Dictionary = resolver.resolve_battle([cleric, fallen], [_punching_bag()])
	assert_true(is_instance_valid(fallen), "precondition: the fixture survived to be read")
	assert_gt(result.get("log", []).size(), 0, "precondition: the battle produced a log")

	assert_true(fallen.is_alive,
		"an `ally_dead -> raise` rule must bring the fallen member back — this is the rule the grammar could not express before, and it needs the condition, the dead_ally targeting and the revival arm all three")
