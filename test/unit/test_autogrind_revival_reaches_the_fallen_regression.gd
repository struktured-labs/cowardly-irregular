extends GutTest

## A grind kills party members, and the Cleric's `raise` could not bring any of them back —
## for TWO independent reasons, one per half of the pipeline.
##
## SELECTION: `raise` authors target_type "dead_ally". Every ally helper in AutobattleSystem
## routes through _get_allies_for, which filters is_alive, so lowest_hp_ally can never return a
## corpse. The editor maps dead_ally -> lowest_hp_ally under the comment "Autobattle will handle
## dead ally targeting" — a claim the consumer contradicts. Live SKIPS living targets
## (BattleManager:5473), so the same rule was inert in live autobattle too.
##
## EXECUTION: HeadlessBattleResolver had arms for healing/magic/physical/mp_restore/support-song-
## status and nothing else. "revival" fell to the `_:` default, which no-ops on a same-side
## target — so even a correctly-targeted raise spent 20 MP and left the ally dead.
##
## Fixing either half alone changes nothing, which is why both are driven here through the real
## selector rather than by calling _resolve_ability.

var _abs: Node = null
var _fixture_ids: Array[String] = []


func before_each() -> void:
	_abs = get_node_or_null("/root/AutobattleSystem")
	if _abs:
		_abs._test_disable_persistence = true
	_fixture_ids.clear()


func after_each() -> void:
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
		"name": "Revive Foe", "max_hp": 99999, "max_mp": 0,
		"attack": 1, "defense": 999, "magic": 1, "speed": 1
	})
	add_child_autofree(e)
	return e


func _install(caster: Combatant, rules: Array) -> void:
	var cid: String = caster.combatant_name.to_lower().replace(" ", "_")
	_fixture_ids.append(cid)
	_abs.set_character_script(cid, {"rules": rules})


func test_a_cleric_raises_a_fallen_ally_during_a_grind() -> void:
	var cleric := _member("Revive Cleric", "cleric")
	var fallen := _member("Revive Fallen", "fighter")
	add_child_autofree(fallen)
	assert_true(cleric.knows_ability("raise"),
		"precondition: raise is a level-10 Cleric ability and the fixture must know it")

	## ally_count drops when a member dies, because _get_allies_for filters the dead out. It is
	## the only condition in the shipped grammar that can notice a death at all.
	_install(cleric, [
		{"conditions": [{"type": "ally_count", "op": "<=", "value": 1}],
		 "actions": [{"type": "ability", "id": "raise", "target": "lowest_hp_ally"}], "enabled": true},
		{"conditions": [{"type": "always"}],
		 "actions": [{"type": "attack", "target": "lowest_hp_enemy"}], "enabled": true},
	])

	fallen.current_hp = 0
	fallen.is_alive = false
	assert_false(fallen.is_alive, "precondition: the ally starts the battle dead")

	var resolver := HeadlessBattleResolver.new()
	var result: Dictionary = resolver.resolve_battle([cleric, fallen], [_punching_bag()])
	assert_gt(result.get("log", []).size(), 0, "precondition: the battle produced a log")
	assert_true(is_instance_valid(fallen), "precondition: the fixture survived to be read")

	assert_true(fallen.is_alive,
		"a Cleric with a raise rule must bring a fallen member back during a grind — still dead means either the selector never handed raise a corpse or the resolver has no revival arm")
	## Read the revive amount WHERE IT IS PRODUCED. current_hp at the end of the battle is the
	## revive value minus fifty more rounds of chip damage — a real number that answers a
	## different question (it measured 175 against an expected 200).
	var revive_line: String = ""
	for line in result.get("log", []):
		if str(line).contains("revives") and str(line).contains(fallen.combatant_name):
			revive_line = str(line)
			break
	assert_ne(revive_line, "",
		"the resolver must log the revival it performed, or there is nothing to check the amount against")
	assert_true(revive_line.contains(str(int(fallen.max_hp * 0.5))),
		"raise authors revive_percentage 50, and headless must mirror live's revive_hp (max_hp/2 = %d) exactly — got: %s" % [int(fallen.max_hp * 0.5), revive_line])
	assert_lte(fallen.current_hp, int(fallen.max_hp * 0.5),
		"a revived ally must never come back above the authored percentage")


func test_the_selector_can_hand_a_revival_ability_a_corpse() -> void:
	## The selection half on its own. Control first: with everyone alive the same call must return
	## NOTHING, so a helper that simply returns the whole party cannot pass the test above.
	var cleric := _member("Target Cleric", "cleric")
	var mate := _member("Target Mate", "fighter")
	var foe := _punching_bag()
	var bm = get_node_or_null("/root/BattleManager")
	if bm == null:
		pass_test("no BattleManager autoload in this harness")
		return
	var p_backup: Array = bm.player_party.duplicate()
	var e_backup: Array = bm.enemy_party.duplicate()
	bm.player_party.clear()
	bm.enemy_party.clear()
	for c in [cleric, mate]:
		bm.player_party.append(c)
	bm.enemy_party.append(foe)

	var alive_targets: Array = _abs._resolve_ability_targets(cleric, "raise", "lowest_hp_ally")
	mate.current_hp = 0
	mate.is_alive = false
	var dead_targets: Array = _abs._resolve_ability_targets(cleric, "raise", "lowest_hp_ally")

	bm.player_party.clear()
	bm.enemy_party.clear()
	for c in p_backup:
		bm.player_party.append(c)
	for c in e_backup:
		bm.enemy_party.append(c)

	assert_eq(alive_targets.size(), 0,
		"control: with the whole party alive a dead_ally ability must resolve to NO target — a helper returning the party would revive the living")
	assert_eq(dead_targets.size(), 1,
		"raise is single-target: exactly one corpse, never the whole graveyard")
	assert_eq(str(dead_targets[0].combatant_name), "Target Mate",
		"the corpse handed to raise must be the ally who actually fell")
