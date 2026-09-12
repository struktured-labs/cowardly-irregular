extends GutTest

## The Speculator's whole kit moves one number and then spends it, and no rule could see it.
##
## leverage_position and overexpose raise the volatility band; press_the_edge scales
## 1.5x/2.5x/4.0x/6.0x with it and CONSUMES a level; circuit_breaker spends a level for AP. The
## band is the job's resource. But the grid grammar had no condition that reads it, so an autobattle
## script could only press at whatever band happened to be up — the job's central decision was
## unauthorable in a game whose stated pillar is that autobattle IS the game. That is why the
## Speculator has no preset catalog: authoring one without this would be guessing.
##
## ⚠️ It is 0..3, NOT a percentage, and that distinction is load-bearing in the editor — see the
## seeding arm below.

var _abs: Node = null
var _bm: Node = null
var _vol_backup = null
var _made_vol: bool = false
var _p_backup: Array = []
var _e_backup: Array = []
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_bm = get_node_or_null("/root/BattleManager")
	_made_vol = false
	if _bm:
		_p_backup = _bm.player_party.duplicate()
		_e_backup = _bm.enemy_party.duplicate()
		_vol_backup = _bm.volatility
		if _bm.volatility == null:
			_bm.volatility = VolatilitySystem.new()
			_made_vol = true
	_fixture_ids.clear()


func after_each() -> void:
	if _bm:
		_bm.player_party.clear()
		_bm.enemy_party.clear()
		for c in _p_backup:
			_bm.player_party.append(c)
		for c in _e_backup:
			_bm.enemy_party.append(c)
		_bm.volatility = _vol_backup
	if _abs:
		for cid in _fixture_ids:
			_abs.character_profiles.erase(cid)


func _speculator(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": 700, "max_mp": 65,
		"attack": 90, "defense": 70, "magic": 110, "speed": 14})
	c.job = JobSystem.get_job("speculator")
	c.job_level = 10
	add_child_autofree(c)
	return c


func test_the_condition_reads_the_live_band() -> void:
	if _bm == null or _bm.volatility == null:
		pass_test("no BattleManager/VolatilitySystem in this harness")
		return
	var c := _speculator("Band Reader")
	var cond := {"type": "volatility_band", "op": ">=", "value": 2}
	_bm.volatility.global_band = 0
	assert_false(_abs._evaluate_grid_condition(c, cond), "Stable is below the threshold")
	_bm.volatility.global_band = 2
	assert_true(_abs._evaluate_grid_condition(c, cond), "Unstable meets it")
	_bm.volatility.global_band = 3
	assert_true(_abs._evaluate_grid_condition(c, cond), "Fractured exceeds it")
	_bm.volatility.global_band = 1
	assert_false(_abs._evaluate_grid_condition(c, cond),
		"and it TRACKS — a rule that stayed true after the band was spent would press an edge that "
		+ "is no longer there, which is the failure this condition exists to let a player avoid")


func test_with_no_volatility_system_it_is_false_rather_than_stale() -> void:
	## The band lives on BattleManager, not an autoload, so outside a fight there may be none. The
	## honest answer is "do not fire", never a leftover from the last battle.
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var c := _speculator("No Band")
	var saved = _bm.volatility
	_bm.volatility = null
	var answer: bool = _abs._evaluate_grid_condition(c, {"type": "volatility_band", "op": ">=", "value": 0})
	_bm.volatility = saved
	assert_false(answer,
		"with no volatility system the rule must not fire — note the threshold is >= 0, which every "
		+ "real band satisfies, so a TRUE here would mean it answered from nothing")


func test_a_band_rule_gates_the_ladder() -> void:
	## The artifact: what the executor hands the character as the band moves.
	if _bm == null or _abs == null or _bm.volatility == null:
		pass_test("no battle autoloads in this harness")
		return
	var c := _speculator("Pressing Speculator")
	var foe := Combatant.new()
	foe.initialize({"name": "Band Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	_bm.enemy_party.append(foe)
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Press At Two", "rules": [
		{"conditions": [{"type": "volatility_band", "op": ">=", "value": 2},
			{"type": "mp_percent", "op": ">=", "value": 24}],
		 "actions": [{"type": "ability", "id": "press_the_edge", "target": "lowest_hp_enemy"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	]})
	var pick := func() -> String:
		var a: Dictionary = _abs.execute_grid_autobattle(c)[0]
		return str(a.get("ability_id", "")) if str(a.get("type", "")) == "ability" else str(a.get("type", ""))

	_bm.volatility.global_band = 0
	assert_eq(pick.call(), "attack", "band too low to be worth pressing — keep swinging")
	_bm.volatility.global_band = 3
	assert_eq(pick.call(), "press_the_edge", "Fractured: cash it out")
	_bm.volatility.global_band = 1
	assert_eq(pick.call(), "attack", "band spent, back to swinging — the rule re-arms downward too")


func test_the_editor_seeds_a_band_not_a_percentage() -> void:
	## The trap this branch exists for. Every other numeric condition in the grid is a PERCENTAGE,
	## so the generic seeding default is `< 50`. On a 0..3 band that is permanently TRUE, and an
	## always-true condition shadows every rule beneath it — picking the condition in the editor
	## would silently disable the rest of the script.
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(ge)
	ge.rules = [{"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true}]
	ge.cursor_row = 0
	ge.cursor_col = 0
	ge._apply_condition_type("volatility_band")
	var cell: Dictionary = ge.rules[0]["conditions"][0]
	assert_eq(str(cell.get("type", "")), "volatility_band", "CONTROL: the apply actually ran")
	assert_true(int(cell.get("value", 99)) >= 0 and int(cell.get("value", 99)) <= 3,
		"the seeded value must be a real band (0-3), not the percentage default: %s" % str(cell))
	assert_eq(str(cell.get("op", "")), ">=",
		"and the default comparison must be the one the job is about — press when the band is high")


func test_the_cell_says_which_band() -> void:
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(ge)
	var label: String = ge._format_condition({"type": "volatility_band", "op": ">=", "value": 2})
	assert_ne(label, "volatility_band", "it must render a readable cell label, not the raw type")
	assert_true(label.contains("Unstable"),
		"and name the band, because 'Band >= 2' does not tell a player what they are waiting for: '%s'" % label)


func test_simulate_refuses_it_rather_than_answering_from_the_last_fight() -> void:
	## VolatilitySystem is owned by BattleManager and SURVIVES the battle, so between fights it
	## holds the previous one's band. A readout answering from that is not a guess about an unknown,
	## it is a confident answer from another fight's leftovers — the same reason `turn` is refused.
	var ge = load("res://src/ui/autobattle/AutobattleGridEditor.gd").new()
	add_child_autofree(ge)
	var why: String = ge._undecidable_reason({"conditions": [{"type": "volatility_band", "op": ">=", "value": 2}]})
	assert_ne(why, "", "Simulate must report it as undecidable rather than reading a stale band")
