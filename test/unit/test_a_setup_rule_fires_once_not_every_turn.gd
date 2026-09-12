extends GutTest

## You could not write "get into position, then fight."
##
## The grid grammar had `has_status` with no negation, and `not_has_buff` keys on a STAT. But
## shadow_step, vanish and invisible all land as a STATUS — so a setup rule had nothing to test
## against, matched again the turn after it fired, and the character re-cast forever while every
## rule beneath it stayed unreachable. That is the same pin that made a Guardian stand still all
## fight, except player-authored and MP-draining rather than turn-wasting, and it is why the Ninja
## kit has no preset that uses its own setup moves.
##
## `not_has_status` closes it. These arms measure the LADDER, not the boolean: what the autobattle
## executor hands back on consecutive turns as the status appears and lapses.

var _abs: Node = null
var _bm: Node = null
var _p_backup: Array = []
var _e_backup: Array = []
var _fixture_ids: Array[String] = []

const SETUP := "shadow_step"


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


func _ninja(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 850, "max_mp": 45,
		"attack": 140, "defense": 80, "magic": 80, "speed": 18
	})
	c.job = JobSystem.get_job("ninja")
	c.job_level = 10
	add_child_autofree(c)
	return c


func _foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({
		"name": "Setup Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1
	})
	add_child_autofree(e)
	return e


## rules: [setup, always-attack]. `guarded` picks whether the setup rule carries the new condition.
func _install(c: Combatant, guarded: bool) -> String:
	var conds: Array = [{"type": "mp_percent", "op": ">=", "value": 18}]
	if guarded:
		conds.push_front({"type": "not_has_status", "status": SETUP})
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {
		"character_id": cid,
		"name": "Setup Probe",
		"rules": [
			{"conditions": conds, "actions": [{"type": "ability", "id": SETUP, "target": "self"}], "enabled": true},
			{"conditions": [{"type": "always"}], "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
		]
	})
	return cid


func _chosen(c: Combatant) -> String:
	var actions: Array = _abs.execute_grid_autobattle(c)
	assert_gt(actions.size(), 0, "CONTROL: a turn resolved to at least one action")
	var a: Dictionary = actions[0]
	return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))


func _arm(c: Combatant) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	_bm.enemy_party.append(_foe())


func test_the_condition_answers_the_caster_not_the_field() -> void:
	var c := _ninja("Truth Ninja")
	var cond := {"type": "not_has_status", "status": SETUP}
	assert_true(_abs._evaluate_grid_condition(c, cond), "with no status it must be TRUE")
	c.add_status(SETUP, 1)
	assert_false(_abs._evaluate_grid_condition(c, cond), "once the status is on, FALSE")
	c.remove_status(SETUP)
	assert_true(_abs._evaluate_grid_condition(c, cond), "and TRUE again when it lapses")


func test_a_guarded_setup_rule_fires_once_then_yields_then_re_arms() -> void:
	## The whole point, measured on the executor over three turns of one combatant. Not "the
	## boolean is right" — what the character is handed to DO as the status appears and lapses.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _ninja("Guarded Ninja")
	_arm(c)
	_install(c, true)

	assert_eq(_chosen(c), SETUP, "turn 1: not in position yet, so set up")
	c.add_status(SETUP, 2)
	assert_eq(_chosen(c), "attack", "turn 2: already in position — the rule below must get the turn")
	c.remove_status(SETUP)
	assert_eq(_chosen(c), SETUP, "turn 3: it lapsed, so set up again — this is a re-arm, not a one-shot")


func test_without_the_guard_the_same_script_pins_forever() -> void:
	## The reason the condition had to exist, as a measurement rather than an argument. Identical
	## script minus the one condition: the character re-casts on every turn, including while the
	## status is already up, and never reaches the attack beneath it.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _ninja("Pinned Ninja")
	_arm(c)
	_install(c, false)
	c.add_status(SETUP, 99)
	var picks: Array = []
	for _i in range(4):
		picks.append(_chosen(c))
	var attacks: int = 0
	for p in picks:
		if p == "attack":
			attacks += 1
	assert_eq(attacks, 0,
		"CONTROL for the arm above: unguarded, the setup rule wins every turn even with the status "
		+ "already up, so the attack row is unreachable — got %s" % str(picks))


func test_a_missing_status_field_is_refused_rather_than_always_true() -> void:
	## An absent payload makes the negation permanently TRUE, and an always-true condition shadows
	## every rule below it under first-match-wins — the failure is silent and total. The shared
	## CONDITION_REQUIRED_FIELD map is what turns that into a validation error.
	if _abs == null or not _abs.has_method("validate_rule"):
		pending("AutobattleSystem.validate_rule required")
		return
	assert_eq(str(_abs.CONDITION_REQUIRED_FIELD.get("not_has_status", "")), "status",
		"not_has_status must declare its required payload field")
	var errors: Array = _abs.validate_rule({
		"conditions": [{"type": "not_has_status"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
	})
	assert_gt(errors.size(), 0, "a not_has_status with no 'status' must be refused: " + str(errors))
	var ok: Array = _abs.validate_rule({
		"conditions": [{"type": "not_has_status", "status": SETUP}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
	})
	assert_eq(ok.size(), 0, "CONTROL: the well-formed version passes, so the arm above is about the "
		+ "missing field and not about the condition being unknown: " + str(ok))


func test_the_player_can_reach_it_in_the_manual_editor() -> void:
	## Engine + grammar without the editor is the enemy_has_status bug of 2026-07-05 repeated: the
	## condition works from JSON and the LLM, and silently no-ops for anyone who picks it by hand.
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	autofree(ge)
	assert_ne(ge._format_condition({"type": "not_has_status", "status": "poison"}), "not_has_status",
		"it must render a readable cell label, not the raw type string")
	var cond: Dictionary = {"type": "always"}
	ge._apply_condition_type(cond, "not_has_status")
	assert_eq(str(cond.get("status", "")), "poison",
		"picking it in the editor must seed a default status, or the cell is born broken")
