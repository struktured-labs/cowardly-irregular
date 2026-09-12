extends GutTest

## You could not write "blind them, once."
##
## .307 gave the grid `not_has_status` for the CASTER, which closed setup moves like shadow_step.
## The same hole was still open facing outward: `enemy_has_status` had no negation, so a debuff rule
## re-applied every turn — burning the MP and the turn — and buried every rule below it under
## first-match-wins. That is why the Ninja's Defensive preset opens on `turn == 1` instead of "while
## they can still see", which I shipped and flagged rather than designed around.
##
## ⚠️ THE ASYMMETRY IS THE WHOLE TRAP. enemy_has_status is ANY, so the strict negation is NONE —
## not "some enemy is missing it". These arms pin that, because an author who assumes the other
## reading writes a rule that never fires on a mixed field.

var _abs: Node = null
var _bm: Node = null
var _p_backup: Array = []
var _e_backup: Array = []
var _fixture_ids: Array[String] = []

const DEBUFF := "blind"


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
	c.initialize({"name": cname, "max_hp": 850, "max_mp": 45,
		"attack": 140, "defense": 80, "magic": 80, "speed": 18})
	c.job = JobSystem.get_job("ninja")
	c.job_level = 10
	add_child_autofree(c)
	return c


func _foe(cname: String) -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": cname, "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(e)
	return e


func _field(c: Combatant, foes: Array) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	for f in foes:
		_bm.enemy_party.append(f)


func test_it_is_the_strict_negation_of_the_positive_it_mirrors() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _ninja("Mirror Ninja")
	var one := _foe("Foe One")
	_field(c, [one])
	var pos := {"type": "enemy_has_status", "status": DEBUFF}
	var neg := {"type": "not_enemy_has_status", "status": DEBUFF}

	assert_false(_abs._evaluate_grid_condition(c, pos), "nobody blinded: the positive is FALSE")
	assert_true(_abs._evaluate_grid_condition(c, neg), "so the negation is TRUE")
	one.add_status(DEBUFF, 2)
	assert_true(_abs._evaluate_grid_condition(c, pos), "blinded: the positive is TRUE")
	assert_false(_abs._evaluate_grid_condition(c, neg), "so the negation is FALSE")


func test_ANY_negates_to_NONE_not_to_some_enemy_lacks_it() -> void:
	## The arm that pins the semantic. On a MIXED field an author expecting "some enemy is missing
	## it" gets the opposite answer, and their debuff rule silently never fires.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _ninja("Mixed Ninja")
	var blinded := _foe("Blinded Foe")
	var seeing := _foe("Seeing Foe")
	_field(c, [blinded, seeing])
	blinded.add_status(DEBUFF, 2)
	assert_true(_abs._evaluate_grid_condition(c, {"type": "enemy_has_status", "status": DEBUFF}),
		"CONTROL: ANY is satisfied by the one blinded enemy")
	assert_false(_abs._evaluate_grid_condition(c, {"type": "not_enemy_has_status", "status": DEBUFF}),
		"NONE is not satisfied while one enemy still carries it — this is NOT 'some enemy lacks it'")
	blinded.remove_status(DEBUFF)
	assert_true(_abs._evaluate_grid_condition(c, {"type": "not_enemy_has_status", "status": DEBUFF}),
		"and once the field is clear again it is TRUE")


func test_a_debuff_rule_fires_once_then_yields_then_re_arms() -> void:
	## The artifact. Same three-turn shape as the .307 guard, aimed outward: what the executor hands
	## the character as the enemy's status appears and lapses.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _ninja("Debuffer Ninja")
	var foe := _foe("Debuffed Foe")
	_field(c, [foe])
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Blind Once", "rules": [
		{"conditions": [{"type": "not_enemy_has_status", "status": DEBUFF},
			{"type": "mp_percent", "op": ">=", "value": 14}],
		 "actions": [{"type": "ability", "id": "smoke_bomb", "target": "lowest_hp_enemy"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	]})
	var pick := func() -> String:
		var a: Dictionary = _abs.execute_grid_autobattle(c)[0]
		return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))

	assert_eq(pick.call(), "smoke_bomb", "turn 1: nobody is blinded yet")
	foe.add_status(DEBUFF, 2)
	assert_eq(pick.call(), "attack", "turn 2: the room is blind — the rule below must get the turn")
	foe.remove_status(DEBUFF)
	assert_eq(pick.call(), "smoke_bomb", "turn 3: it lapsed, so blind them again")


func test_without_the_guard_the_same_script_pins() -> void:
	## The reason the condition had to exist, measured. Identical script minus the one condition.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _ninja("Pinned Debuffer")
	var foe := _foe("Already Blind Foe")
	_field(c, [foe])
	foe.add_status(DEBUFF, 99)
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Blind Forever", "rules": [
		{"conditions": [{"type": "mp_percent", "op": ">=", "value": 14}],
		 "actions": [{"type": "ability", "id": "smoke_bomb", "target": "lowest_hp_enemy"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	]})
	var picks: Array = []
	for _i in range(4):
		var a: Dictionary = _abs.execute_grid_autobattle(c)[0]
		picks.append(str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", "")))
	assert_false(picks.has("attack"),
		"CONTROL for the arm above: unguarded, it re-blinds an already-blind room every turn and the "
		+ "attack row is unreachable — got %s" % str(picks))


func test_a_missing_status_field_is_refused_rather_than_always_true() -> void:
	## Absent payload makes the negation permanently TRUE, and an always-true condition shadows every
	## rule below it. CONDITION_REQUIRED_FIELD is what turns that into a validation error.
	if _abs == null or not _abs.has_method("validate_rule"):
		pending("AutobattleSystem.validate_rule required")
		return
	assert_eq(str(_abs.CONDITION_REQUIRED_FIELD.get("not_enemy_has_status", "")), "status",
		"it must declare its required payload field")
	assert_gt(_abs.validate_rule({"conditions": [{"type": "not_enemy_has_status"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}).size(), 0,
		"a not_enemy_has_status with no 'status' must be refused")
	assert_eq(_abs.validate_rule({"conditions": [{"type": "not_enemy_has_status", "status": DEBUFF}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}]}).size(), 0,
		"CONTROL: the well-formed version passes, so the arm above is about the missing field")


func test_the_simulate_readout_refuses_it_rather_than_guessing() -> void:
	## It reads the ENEMY party, so the grid editor's scratch probe cannot decide it — unlike
	## not_has_status, which reads the caster and belongs on the other list. Getting this wrong
	## would make Simulate answer confidently against an empty field.
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(ge)
	var why: String = ge._undecidable_reason({"conditions": [{"type": "not_enemy_has_status", "status": DEBUFF}]})
	assert_ne(why, "", "Simulate must report it as undecidable, not answer it against no enemies")


func test_the_player_can_reach_it_in_the_manual_editor() -> void:
	## Engine plus grammar without the editor is the enemy_has_status bug of 2026-07-05 repeated.
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(ge)
	assert_ne(ge._format_condition({"type": "not_enemy_has_status", "status": DEBUFF}), "not_enemy_has_status",
		"it must render a readable cell label, not the raw type string")
	## ⚠️ `_apply_condition_type` takes ONE argument and operates on the editor's OWN cursor state.
	## The first version of this arm called it as `(cond, "not_enemy_has_status")` — a two-arg call that
	## errors, ABORTS the rest of the function, and leaves GUT reporting a pass. Caught by
	## reconciling authored asserts against executed ones: 17 vs 16. Seed the editor like
	## test_autobattle_editor_picker_regression does, then read the cell back out of it.
	ge.rules = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	ge.cursor_row = 0
	ge.cursor_col = 0
	ge._apply_condition_type("not_enemy_has_status")
	var cell: Dictionary = ge.rules[0]["conditions"][0]
	assert_eq(str(cell.get("type", "")), "not_enemy_has_status",
		"CONTROL: the apply actually ran and rewrote the cell")
	assert_eq(str(cell.get("status", "")), "poison",
		"picking it in the editor must seed a default status, or the cell is born broken")
