extends GutTest

## A staked autogrind defeat killed the ally and wrote their name into the grind's
## skip list, and never set permakilled. Phoenix Down and Raise only refuse that
## status, so the "permanently lost" ally stood back up. The marker has to be
## permanent (-1) at the moment of the stake: the default 3-turn ailment duration
## wears off if anything ticks it. Time Mage undo_death still lifts the marker
## and the grind record. A defeat with staking off stays an ordinary KO.

var _system
var _saved_persist: bool = false
var _saved_names: Array = []
var _saved_staking: bool = false


func before_each() -> void:
	_system = preload("res://src/autogrind/AutogrindSystem.gd").new()
	add_child_autofree(_system)
	_system._test_disable_persistence = true
	_system.is_grinding = true
	_system.permadeath_staking_enabled = false
	_system.permadead_characters.clear()
	if AutogrindSystem:
		_saved_persist = AutogrindSystem._test_disable_persistence
		_saved_names = AutogrindSystem.permadead_characters.duplicate()
		_saved_staking = AutogrindSystem.permadeath_staking_enabled
		AutogrindSystem._test_disable_persistence = true


func after_each() -> void:
	if AutogrindSystem:
		AutogrindSystem.permadead_characters.clear()
		for n in _saved_names:
			AutogrindSystem.permadead_characters.append(str(n))
		AutogrindSystem.permadeath_staking_enabled = _saved_staking
		AutogrindSystem._test_disable_persistence = _saved_persist


func _member(who: String, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": who, "max_hp": 100, "max_mp": 20,
		"attack": 10, "defense": 10, "magic": 5, "speed": 10,
	})
	add_child_autofree(c)
	c.current_hp = hp
	return c


func _party() -> Array[Combatant]:
	var party: Array[Combatant] = []
	party.append(_member("StakeProbe", 10))
	party.append(_member("StillUp", 80))
	return party


func test_a_staked_defeat_marks_the_victim_so_phoenix_down_refuses() -> void:
	var party := _party()
	_system.grind_party = party
	_system.permadeath_staking_enabled = true
	_system.on_battle_defeat()
	var victim: Combatant = party[0]
	var bystander: Combatant = party[1]
	assert_false(victim.is_alive, "CONTROL: staking killed the lowest-HP ally")
	assert_eq(victim.current_hp, 0)
	assert_true(victim.has_status("permakilled"),
		"the stake must set the marker Raise and Phoenix Down actually check")
	assert_eq(int(victim.status_durations.get("permakilled", 0)), -1,
		"the marker is permanent at the moment of the stake, not a 3-turn ailment")
	for _i in 4:
		victim.update_buff_durations()
	assert_true(victim.has_status("permakilled"),
		"four duration ticks must not wear a permanent marker off")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [victim]), "StakeProbe can't be revived",
		"the field menu must keep the feather")
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [victim], true), "StakeProbe can't be revived",
		"the battle item row uses the same gate")
	victim.revive(victim.max_hp)
	assert_false(victim.is_alive, "revive() refuses a staked ally")
	assert_eq(victim.current_hp, 0, "a refused revive must not restore HP")
	assert_true(bystander.is_alive, "only the claimed ally is killed")
	assert_false(bystander.has_status("permakilled"), "a survivor must not grow the marker")
	bystander.die()
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [bystander]), "",
		"an ordinary KO in the same party is still a Phoenix Down target")
	bystander.revive(25)
	assert_true(bystander.is_alive)


func test_staking_off_leaves_a_ko_revivable() -> void:
	var party := _party()
	party[0].die()
	_system.grind_party = party
	_system.permadeath_staking_enabled = false
	_system.on_battle_defeat()
	assert_false(party[0].has_status("permakilled"), "a defeat without the stake is an ordinary KO")
	assert_eq(_system.permadead_characters.size(), 0)
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", [party[0]]), "")
	party[0].revive(25)
	assert_true(party[0].is_alive)


func test_a_wiped_staked_party_is_marked_permanently() -> void:
	var party := _party()
	for m in party:
		m.die()
	_system.grind_party = party
	_system.permadeath_staking_enabled = true
	_system.on_battle_defeat()
	for m in party:
		assert_true(m.has_status("permakilled"), "%s was wiped under the stake" % m.combatant_name)
		assert_eq(int(m.status_durations.get("permakilled", 0)), -1)
		m.revive(m.max_hp)
		assert_false(m.is_alive, "%s must stay down" % m.combatant_name)
	assert_eq(ItemSystem.ineffective_use_reason("phoenix_down", party), "No one can be revived")


func test_undo_death_lifts_the_marker_and_the_grind_record() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null or AutogrindSystem == null:
		pending("BattleManager and AutogrindSystem autoloads required")
		return
	var party := _party()
	_system.grind_party = party
	_system.permadeath_staking_enabled = true
	_system.on_battle_defeat()
	var victim: Combatant = party[0]
	assert_true(victim.has_status("permakilled"), "CONTROL: the stake landed")
	assert_true("StakeProbe" in _system.permadead_characters, "CONTROL: the grind recorded the name")
	AutogrindSystem.permadead_characters.append("StakeProbe")
	var caster := _member("TimeMage", 100)
	bm._execute_meta_ability(caster, {"id": "undo_death", "meta_effect": "reverse_permadeath"}, [victim])
	assert_false(victim.has_status("permakilled"), "undo_death removes the marker")
	assert_true(victim.is_alive, "and stands them up")
	assert_gt(victim.current_hp, 0)
	assert_false("StakeProbe" in AutogrindSystem.permadead_characters,
		"undo_death also drops the grind skip, or the next session still leaves them behind")
