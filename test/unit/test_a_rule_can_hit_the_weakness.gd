extends GutTest

## "Hit the weakness" is the oldest decision in the genre, and no autobattle rule could say it.
##
## Every one of the 106 monsters carries a `weaknesses` array, and the runtime already reads it —
## `Combatant.elemental_weaknesses`, and `_get_weakness_target` for the "Exploit Weakness" TARGET.
## But a script could only choose a spell by MP cost, so the Summoner's three 30 MP eidolons are
## identical to it: Ifrit, Shiva and Ramuh differ in nothing but element. That is why the Summoner
## has no preset catalog — three stances authored without this would pick an element by coin flip.
##
## ANY living enemy is weak to it, matching `enemy_has_status`, so the two read alike.

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


func _foe(cname: String, weak: Array) -> Combatant:
	var e := Combatant.new()
	e.initialize({"name": cname, "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
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


func test_it_reads_the_enemy_weakness() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _summoner("Reader")
	_field(c, [_foe("Fire Weak", ["fire"])])
	assert_true(_abs._evaluate_grid_condition(c, {"type": "enemy_weak_to", "element": "fire"}),
		"the enemy is weak to fire")
	assert_false(_abs._evaluate_grid_condition(c, {"type": "enemy_weak_to", "element": "ice"}),
		"and not to ice — otherwise it answers the same for every element and checks nothing")


func test_ANY_enemy_is_enough_matching_enemy_has_status() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _summoner("Mixed")
	_field(c, [_foe("Immune One", []), _foe("Ice Weak", ["ice"])])
	assert_true(_abs._evaluate_grid_condition(c, {"type": "enemy_weak_to", "element": "ice"}),
		"one weak enemy on a mixed field is enough, the same way enemy_has_status works")
	assert_false(_abs._evaluate_grid_condition(c, {"type": "enemy_weak_to", "element": "holy"}),
		"CONTROL: and a field with nobody weak to it is still FALSE")


func test_an_element_nobody_is_weak_to_never_fires_rather_than_erroring() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _summoner("Nonsense")
	_field(c, [_foe("Plain", ["fire"])])
	assert_false(_abs._evaluate_grid_condition(c, {"type": "enemy_weak_to", "element": "banana"}),
		"an element the game does not have must simply not fire")
	assert_false(_abs._evaluate_grid_condition(c, {"type": "enemy_weak_to"}),
		"and a MISSING element must be false, never true — an always-true condition would shadow "
		+ "every rule below it under first-match-wins")


func test_a_weakness_rule_picks_the_matching_eidolon() -> void:
	## The artifact. Two summons, identical in cost and power, chosen by what the enemy cannot
	## survive — which is the entire reason the Summoner's kit has three of them.
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var c := _summoner("Choosing Summoner")
	var foe := _foe("Switching Foe", ["fire"])
	_field(c, [foe])
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Exploit", "rules": [
		{"conditions": [{"type": "enemy_weak_to", "element": "fire"}, {"type": "mp_percent", "op": ">=", "value": 30}],
		 "actions": [{"type": "ability", "id": "summon_ifrit", "target": "lowest_hp_enemy"}], "enabled": true},
		{"conditions": [{"type": "enemy_weak_to", "element": "ice"}, {"type": "mp_percent", "op": ">=", "value": 30}],
		 "actions": [{"type": "ability", "id": "summon_shiva", "target": "lowest_hp_enemy"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	]})
	var pick := func() -> String:
		var a: Dictionary = _abs.execute_grid_autobattle(c)[0]
		return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))

	assert_eq(pick.call(), "summon_ifrit", "weak to fire: Ifrit")
	foe.elemental_weaknesses.clear()
	foe.elemental_weaknesses.append("ice")
	assert_eq(pick.call(), "summon_shiva", "the SAME combatant, now weak to ice: Shiva")
	foe.elemental_weaknesses.clear()
	assert_eq(pick.call(), "attack",
		"and weak to nothing: neither eidolon, just steel — the rules are choosing on the weakness "
		+ "rather than on their order in the list")


func test_the_player_can_reach_it_in_the_manual_editor() -> void:
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(ge)
	assert_ne(ge._format_condition({"type": "enemy_weak_to", "element": "fire"}), "enemy_weak_to",
		"it must render a readable cell label, not the raw type string")
	ge.rules = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	ge.cursor_row = 0
	ge.cursor_col = 0
	ge._apply_condition_type("enemy_weak_to")
	var cell: Dictionary = ge.rules[0]["conditions"][0]
	assert_eq(str(cell.get("type", "")), "enemy_weak_to", "CONTROL: the apply actually ran")
	assert_ne(str(cell.get("element", "")), "",
		"picking it must seed an element, or the cell is born permanently false: %s" % str(cell))


func test_the_grammar_only_advertises_elements_something_is_actually_weak_to() -> void:
	## The LLM composer is handed a list of elements "that appear as a weakness in the bestiary".
	## If that list drifts from the data it teaches rules that can never fire — the same shape as
	## an ability id the job cannot know. Derived from monsters.json, so it cannot agree with itself.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_not_null(parsed, "CONTROL: monsters.json parses")
	var monsters: Dictionary = parsed.get("monsters", parsed)
	var real: Dictionary = {}
	for id in monsters.keys():
		for e in ((monsters[id] as Dictionary).get("weaknesses", []) as Array):
			real[str(e)] = true
	assert_gt(real.size(), 3, "CONTROL: the bestiary declares weaknesses at all (%s)" % str(real.keys()))

	var prompt: String = FileAccess.get_file_as_string("res://src/llm/DialoguePrompts.gd")
	var start: int = prompt.find("enemy_weak_to takes an 'element' field")
	assert_gt(start, -1, "the grammar must document the condition")
	var para: String = prompt.substr(start, 420)
	var claimed: Array = []
	for e in ["fire", "holy", "lightning", "ice", "water", "physical", "dark", "poison", "earth", "wind", "arcane"]:
		if para.contains(e):
			claimed.append(e)
	assert_gt(claimed.size(), 3, "CONTROL: the paragraph names elements at all (%s)" % str(claimed))
	var phantom: Array = []
	for e in claimed:
		if not real.has(e):
			phantom.append(e)
	assert_eq(phantom.size(), 0,
		"the grammar offers an element NOTHING in the bestiary is weak to, so a rule composed with "
		+ "it can never fire: " + str(phantom))
