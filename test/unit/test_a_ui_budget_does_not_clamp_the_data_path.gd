extends GutTest

## `AutobattleGridEditor.MAX_RULES = 32` is a UI-ADD BUDGET, not a data invariant. Three lanes
## converged on clamping the data path in one evening, and both clamp shapes LOSE PLAYER DATA:
## truncate drops composed rules silently, reject discards the whole set — which is `.455`'s own
## bug verbatim, where one malformed part cost the player their entire composed script.
##
## Measured: MAX_RULES is enforced at exactly two sites, `_add_or_row` and `_insert_row_after`,
## both manual adds. The executor's loop, every editor render, the COWIR1 codec and save all bound
## on `rules.size()`, so a 33-rule script installs, renders, navigates and runs. Nothing downstream
## assumes 32 — the two other `32`s in those files are layout pixels.
##
## Notes at the const and at `set_character_script` record that decision. A COMMENT CANNOT GO RED,
## which is the whole reason this file exists: it fails if anyone clamps the choke point.
##
## ⛔ Rule 33 defers DELIBERATELY. `_get_default_action` returns `attack` while any enemy lives, so
## an `attack` at rule 33 would pass whether it fired or was never reached at all. Arm 2 asserts the
## 32-rule case yields that default FIRST, which is the same fixture one rule short — so the arm
## measures a change in output rather than a value that both branches happen to produce.

const BUDGET := 32
const OVER := 33

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


## `hp_percent < 0` is unsatisfiable, so every filler rule falls through to the one below it.
func _unreachable(i: int) -> Dictionary:
	return {
		"name": "filler %d" % i,
		"enabled": true,
		"conditions": [{"type": "hp_percent", "op": "<", "value": 0}],
		"actions": [{"type": "attack"}],
	}


## No conditions = always match, so this fires iff the executor reaches past the UI budget.
func _catch_all() -> Dictionary:
	return {
		"name": "past the budget",
		"enabled": true,
		"conditions": [],
		"actions": [{"type": "defer"}],
	}


func _rules(count: int, with_catch_all: bool) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(_unreachable(i))
	if with_catch_all:
		out.append(_catch_all())
	return out


## Installs a script and returns [combatant, character_id]. One live enemy, so the no-rule default
## is `attack` — with an empty enemy party it would be `defer` and collide with the catch-all.
func _install(rules: Array) -> Array:
	var c := Combatant.new()
	c.initialize({"name": "Over Budget", "max_hp": 400, "max_mp": 40,
		"attack": 50, "defense": 40, "magic": 40, "speed": 10})
	add_child_autofree(c)
	var foe := Combatant.new()
	foe.initialize({"name": "Wall", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1})
	add_child_autofree(foe)
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(c)
	_bm.enemy_party.append(foe)
	var cid: String = _abs._get_character_id(c)
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "name": "Over Budget", "rules": rules})
	return [c, cid]


func _first_action_type(c: Combatant) -> String:
	var actions: Array = _abs.execute_grid_autobattle(c)
	if actions.size() == 0:
		return "<none>"
	return str((actions[0] as Dictionary).get("type", ""))


func test_a_script_over_the_ui_budget_survives_the_choke_point() -> void:
	assert_not_null(_abs, "CONTROL: AutobattleSystem must resolve, or every arm here is vacuous")
	assert_not_null(_bm, "CONTROL: BattleManager must resolve, or every arm here is vacuous")
	var pair: Array = _install(_rules(BUDGET, true))
	var stored: Dictionary = _abs.get_character_script(str(pair[1]))
	assert_eq(int((stored.get("rules", []) as Array).size()), OVER,
		"set_character_script must not clamp to the grid's MAX_RULES. That 32 is a UI-ADD budget; "
		+ "truncating drops rules the player composed and rejecting discards the whole script, "
		+ "which is the bug .455 fixed at a different door")


func test_the_rule_past_the_budget_still_executes() -> void:
	assert_not_null(_abs, "CONTROL: AutobattleSystem must resolve, or every arm here is vacuous")
	assert_not_null(_bm, "CONTROL: BattleManager must resolve, or every arm here is vacuous")
	## The same fixture one rule short. Its answer must be the default, which proves both that the
	## fillers are genuinely unreachable and that `attack` != `defer` distinguishes the two branches.
	var short_pair: Array = _install(_rules(BUDGET, false))
	assert_eq(_first_action_type(short_pair[0] as Combatant), "attack",
		"CONTROL: with %d unreachable rules and no catch-all the executor must fall through to its "
		% BUDGET + "own default (attack). If this is `defer` the arm below cannot distinguish a "
		+ "reached rule 33 from the default and is vacuous")
	var over_pair: Array = _install(_rules(BUDGET, true))
	assert_eq(_first_action_type(over_pair[0] as Combatant), "defer",
		"execute_grid_autobattle iterates script[\"rules\"] unbounded, so rule %d must fire. " % OVER
		+ "A bound here would make a composed rule silently dead while still visible in the editor")
