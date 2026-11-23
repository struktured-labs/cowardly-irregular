extends GutTest

## `enemy_weak_to` let a rule say "hit the weakness"; nothing let it say "don't open with what it shrugs off".
## 93 monsters carry `resistances` and the runtime halves damage on them, but a script could only
## learn that by wasting the turn. `enemy_resists` reads `Combatant.elemental_resistances`, ANY living
## enemy, the same shape as its sibling.

var _abs: Node = null
var _bm: Node = null
var _p_backup: Array = []
var _e_backup: Array = []
var _fixture_ids: Array[String] = []


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


func _summoner(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": 620, "max_mp": 100,
		"attack": 70, "defense": 60, "magic": 130, "speed": 11})
	c.job = JobSystem.get_job("summoner")
	c.job_level = 10
	add_child_autofree(c)
	return c


func _foe(cname: String, resists: Array, weak: Array = []) -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": cname, "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	for r in resists:
		e.elemental_resistances.append(str(r))
	for w in weak:
		e.elemental_weaknesses.append(str(w))
	add_child_autofree(e)
	return e


func _field(c: Combatant, foes: Array) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	for f in foes:
		_bm.enemy_party.append(f)


func _reads(c: Combatant, element: String) -> bool:
	return _abs._evaluate_grid_condition(c, {"type": "enemy_resists", "element": element})


func test_it_reads_the_enemy_resistance() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _summoner("Reader")
	_field(c, [_foe("Fire Proof", ["fire"])])
	assert_true(_reads(c, "fire"), "the enemy resists fire")
	assert_false(_reads(c, "ice"), "CONTROL: and not ice, or it answers the same for every element")


func test_it_reads_resistance_not_weakness() -> void:
	## The sibling arm sits one line away; a copy that kept `elemental_weaknesses` would pass every arm above with the lists swapped.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _summoner("Two Lists")
	_field(c, [_foe("Fire Proof Ice Weak", ["fire"], ["ice"])])
	assert_true(_reads(c, "fire"), "resists fire")
	assert_false(_reads(c, "ice"), "being WEAK to ice is not resisting it")
	assert_false(_abs._evaluate_grid_condition(c, {"type": "enemy_weak_to", "element": "fire"}),
		"CONTROL: and the weakness condition does not read the resistance list either")


func test_ANY_enemy_is_enough_and_absence_is_false() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _summoner("Mixed")
	_field(c, [_foe("Plain", []), _foe("Ice Proof", ["ice"])])
	assert_true(_reads(c, "ice"), "one resisting enemy on a mixed field is enough, like enemy_weak_to")
	assert_false(_reads(c, "holy"), "CONTROL: a field where nobody resists it is FALSE")
	assert_false(_reads(c, "banana"), "an element the game does not have simply never fires")
	assert_false(_abs._evaluate_grid_condition(c, {"type": "enemy_resists"}),
		"a MISSING element is false: an always-true row would shadow every rule below it")


func test_a_resist_rule_steers_off_the_wasted_spell() -> void:
	## The artifact: the same two eidolons, and the rule above the default switches away from fire while fire would be halved.
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var c := _summoner("Careful Summoner")
	var foe := _foe("Switching Foe", ["fire"])
	_field(c, [foe])
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Avoid", "rules": [
		{"conditions": [{"type": "enemy_resists", "element": "fire"}, {"type": "mp_percent", "op": ">=", "value": 30}],
		 "actions": [{"type": "ability", "id": "summon_shiva", "target": "lowest_hp_enemy"}], "enabled": true},
		{"conditions": [{"type": "mp_percent", "op": ">=", "value": 30}],
		 "actions": [{"type": "ability", "id": "summon_ifrit", "target": "lowest_hp_enemy"}], "enabled": true},
	]})
	var pick := func() -> String:
		var a: Dictionary = _abs.execute_grid_autobattle(c)[0]
		return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))

	assert_eq(pick.call(), "summon_shiva", "it resists fire: not Ifrit")
	foe.elemental_resistances.clear()
	assert_eq(pick.call(), "summon_ifrit",
		"the SAME combatant, resisting nothing: back to Ifrit, so the rule chose on the resistance and not on its place in the list")


func test_the_player_can_reach_it_in_the_manual_editor() -> void:
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(ge)
	var label: String = ge._format_condition({"type": "enemy_resists", "element": "fire"})
	assert_eq(label, "Enemy resists Fire", "a readable cell, not the raw type string")
	assert_ne(label, ge._format_condition({"type": "enemy_weak_to", "element": "fire"}),
		"and not the weakness label: the two cells must read differently")
	ge.rules = [{"conditions": [{"type": "hp_percent", "op": "<", "value": 50}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	ge.cursor_row = 0
	ge.cursor_col = 0
	ge._apply_condition_type("enemy_resists")
	var cell: Dictionary = ge.rules[0]["conditions"][0]
	assert_eq(str(cell.get("type", "")), "enemy_resists", "CONTROL: the apply actually ran")
	assert_eq(str(cell.get("element", "")), str(AutobattleGridEditor.payload_vocabulary("element")[0]),
		"seeded with the dial's first element, or the cell is born permanently false: %s" % str(cell))
	assert_false(cell.has("op") or cell.has("value"), "a named payload carries no number to dial: %s" % str(cell))
	assert_true(AutobattleSystem.CONDITION_TYPES.has("enemy_resists"), "the validator knows the type")
	assert_eq(str(AutobattleSystem.CONDITION_REQUIRED_FIELD.get("enemy_resists", "")), "element",
		"and requires its element, so a shared script missing it is refused rather than run as false")


func test_a_real_bestiary_resistance_is_one_the_dial_can_name() -> void:
	## The dial offers weakness and ability elements; a resistance it cannot name is unauthorable.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	var monsters: Dictionary = parsed.get("monsters", parsed)
	var resisted: Dictionary = {}
	for id in monsters.keys():
		for r in ((monsters[id] as Dictionary).get("resistances", []) as Array):
			resisted[str(r)] = true
	assert_gt(resisted.size(), 3, "CONTROL: the bestiary declares resistances at all (%s)" % str(resisted.keys()))
	var dial: Array = AutobattleGridEditor.payload_vocabulary("element")
	var unnameable: Array = []
	for e in resisted.keys():
		if not dial.has(e):
			unnameable.append(e)
	assert_eq(unnameable, [], "every resisted element must be on the dial: dial=%s" % str(dial))
