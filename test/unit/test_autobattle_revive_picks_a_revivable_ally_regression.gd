extends GutTest

## A Phoenix Down rule the editor writes, and a Raise rule, must bring back an ally who can
## still stand. The editor stores every item as target "self" (potions and antidotes). Phoenix
## Down is a revive: aimed at the living caster, battle drops the target and the turn fizzles,
## and the KO'd ally stays down. Raise already looks at corpses, but it took the first one in
## party order, including someone permakilled — revive() refuses them, so the ordinary KO
## behind them never got the spell. A permakilled ally stays dead for the campaign, so an
## ally_dead revive rule then matched every turn and the attack under it never ran.
##
## Undo Death is the spell that exists to touch a permakilled ally. It must keep doing that.

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


func _member(cname: String, job_id: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname, "max_hp": 400, "max_mp": 80,
		"attack": 20, "defense": 30, "magic": 30, "speed": 12
	})
	if job_id != "":
		c.job = JobSystem.get_job(job_id)
	c.job_level = 10
	add_child_autofree(c)
	return c


func _down(c: Combatant) -> void:
	c.current_hp = 0
	c.is_alive = false


func _permakill(c: Combatant) -> void:
	_down(c)
	c.add_status("permakilled", -1)


func _foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({
		"name": "Revive Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1
	})
	add_child_autofree(e)
	return e


func _register(party: Array) -> void:
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	for c in party:
		_bm.player_party.append(c)
	_bm.enemy_party.append(_foe())


func _script(cid: String, rules: Array) -> void:
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"character_id": cid, "rules": rules})


func _feather_rule() -> Dictionary:
	## The shape _apply_item_id writes for every consumable, Phoenix Down included.
	return {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "item", "id": "phoenix_down", "target": "self"}],
		"enabled": true,
	}


func _attack_rule() -> Dictionary:
	return {
		"conditions": [{"type": "always"}],
		"actions": [{"type": "attack", "target": "lowest_hp_enemy"}],
		"enabled": true,
	}


func test_phoenix_down_aimed_at_self_revives_the_ko_not_the_caster() -> void:
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var caster := _member("Feather Caster", "fighter")
	var fallen := _member("Feather Fallen", "mage")
	_register([caster, fallen])
	_down(fallen)
	var cid: String = _abs._get_character_id(caster)
	_script(cid, [_feather_rule(), _attack_rule()])
	caster.add_item("phoenix_down", 1)

	var actions: Array = _abs.execute_grid_autobattle(caster)
	assert_eq(str(actions[0].get("type", "")), "item",
		"someone is down and the bag has a feather, so the revive rule must be the one that fires")
	assert_eq(str(actions[0].get("item_id", "")), "phoenix_down")
	var targets: Array = actions[0].get("targets", [])
	assert_eq(targets.size(), 1, "the feather needs exactly one ally")
	assert_eq(targets[0], fallen,
		"a Phoenix Down rule stored as target self must land on the KO'd ally, not the living caster — battle drops a living target and the turn fizzles")
	assert_false(targets[0] == caster, "control: the caster is standing, so they are not a revive target")


func test_a_permakilled_corpse_does_not_pin_the_feather_rule() -> void:
	## ally_dead stays true for the rest of the campaign once someone is permakilled.
	## The feather cannot help them. The attack under the rule has to run.
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var caster := _member("Feather Pinned", "fighter")
	var gone := _member("Feather Gone", "rogue")
	_register([caster, gone])
	_permakill(gone)
	var cid: String = _abs._get_character_id(caster)
	_script(cid, [_feather_rule(), _attack_rule()])

	var actions: Array = _abs.execute_grid_autobattle(caster)
	assert_eq(str(actions[0].get("type", "")), "attack",
		"the only corpse is permakilled, so the feather rule must fall through to the attack under it instead of fizzling every turn")
	assert_eq(caster.get_item_count("phoenix_down"), 0,
		"control: this arm never put a feather in the bag, so a spent one would be a different bug")


func test_phoenix_down_skips_the_permakilled_ally_and_raises_the_one_behind_them() -> void:
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var caster := _member("Feather Order", "fighter")
	var gone := _member("Feather First", "rogue")
	var fallen := _member("Feather Second", "bard")
	_register([caster, gone, fallen])
	_permakill(gone)
	_down(fallen)
	var cid: String = _abs._get_character_id(caster)
	_script(cid, [_feather_rule()])

	var actions: Array = _abs.execute_grid_autobattle(caster)
	var targets: Array = actions[0].get("targets", [])
	assert_eq(targets.size(), 1)
	assert_eq(targets[0], fallen,
		"party order puts the permakilled ally first; the feather has to skip them and land on the ally revive() will accept")
	assert_ne(targets[0], gone, "control: the permakilled ally is not a Phoenix Down target")


func test_raise_skips_a_permakilled_ally_for_the_ordinary_ko() -> void:
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var cleric := _member("Raise Order", "cleric")
	assert_true(cleric.knows_ability("raise"),
		"precondition: a level-10 cleric knows raise, or this arm is not the spell players script")
	var gone := _member("Raise Gone", "fighter")
	var fallen := _member("Raise Fallen", "mage")
	_register([cleric, gone, fallen])
	_permakill(gone)
	_down(fallen)
	var cid: String = _abs._get_character_id(cleric)
	_script(cid, [{
		"conditions": [{"type": "ally_dead"}],
		"actions": [{"type": "ability", "id": "raise", "target": "lowest_hp_ally"}],
		"enabled": true,
	}])

	var actions: Array = _abs.execute_grid_autobattle(cleric)
	assert_eq(str(actions[0].get("type", "")), "ability")
	assert_eq(str(actions[0].get("ability_id", "")), "raise")
	var targets: Array = actions[0].get("targets", [])
	assert_eq(targets.size(), 1)
	assert_eq(targets[0], fallen,
		"Raise must land on the ordinary KO, not the permakilled ally listed ahead of them")


func test_undo_death_still_targets_the_permakilled_ally() -> void:
	## The filter is revival-only. Undo Death is the meta spell whose subject IS the permakilled ally.
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var caster := _member("Undo Caster", "time_mage")
	var gone := _member("Undo Gone", "fighter")
	var fallen := _member("Undo Fallen", "mage")
	_register([caster, gone, fallen])
	_permakill(gone)
	_down(fallen)
	var targets: Array = _abs._resolve_ability_targets(caster, "undo_death", "lowest_hp_ally")
	assert_eq(targets.size(), 1)
	assert_eq(targets[0], gone,
		"Undo Death must still see the permakilled ally — skipping every permakilled corpse would make the spell unable to do the one thing it is for")


func test_a_potion_still_targets_the_living_caster_when_someone_is_down() -> void:
	if _bm == null or _abs == null:
		pass_test("no battle autoloads in this harness")
		return
	var caster := _member("Potion Caster", "fighter")
	var fallen := _member("Potion Fallen", "mage")
	_register([caster, fallen])
	_down(fallen)
	var action: Dictionary = _abs._action_def_to_action(caster, {"type": "item", "id": "potion", "target": "self"})
	var targets: Array = action.get("targets", [])
	assert_eq(targets.size(), 1)
	assert_eq(targets[0], caster,
		"the revive retarget is Phoenix Down's, not every item's — a potion on self must stay on the caster")
	assert_true(fallen.is_alive == false, "control: the KO'd ally was not the potion target and is still down")


func test_the_grind_spends_a_feather_on_the_ko_and_keeps_it_off_the_permakilled() -> void:
	if _bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var resolver := HeadlessBattleResolver.new()
	var user := _member("Grind Feather", "fighter")
	var fallen := _member("Grind Fallen", "mage")
	_down(fallen)
	user.add_item("phoenix_down", 1)
	resolver._resolve_item(user, "phoenix_down", fallen)
	assert_true(fallen.is_alive,
		"autogrind must revive the KO'd ally — it used to take the feather and return because the target was dead")
	assert_gt(fallen.current_hp, 0, "the revived ally has HP, not an alive flag over a corpse")
	assert_eq(user.get_item_count("phoenix_down"), 0, "the feather is spent when the revive lands")

	var gone := _member("Grind Gone", "rogue")
	_permakill(gone)
	user.add_item("phoenix_down", 1)
	var hp_before: int = gone.current_hp
	resolver._resolve_item(user, "phoenix_down", gone)
	assert_false(gone.is_alive, "a permakilled ally stays down")
	assert_eq(gone.current_hp, hp_before, "revive() must not move their HP")
	assert_eq(user.get_item_count("phoenix_down"), 1,
		"the feather stays in the bag when the only target is permakilled")
