extends GutTest

## Regression (2026-10-04, the autogrind sibling of .575/.576): HeadlessBattleResolver's group and formation sites discarded
## take_damage's return and logged the pre-mitigation number, and that log reaches the player through the autogrind console
## (AutogrindUI.append_resolver_log). Against a defended enemy the console overstated every group hit. Lines now log what landed.

const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _member(n: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = n
	c.max_hp = 500
	c.current_hp = 500
	c.attack = 400
	c.magic = 400
	c.defense = 0
	c.current_ap = 4
	c.is_alive = true
	return c


func _wall(defense: int) -> Combatant:
	var e := Combatant.new()
	autofree(e)
	e.combatant_name = "Wall"
	e.max_hp = 100000000
	e.current_hp = 100000000
	e.defense = defense
	e.attack = 10
	e.is_alive = true
	return e


func _logged_hit(resolver, prefix: String) -> int:
	for line in resolver._battle_log:
		var s := str(line)
		if s.begins_with(prefix) and s.contains(" for "):
			return int(s.get_slice(" for ", 1).trim_suffix("!"))
	return -1


func test_a_group_hit_logs_the_hp_the_wall_lost() -> void:
	var wall := _wall(300)
	var hero := _member("Fighter")
	var r = HBR.new()
	r._player_party = [hero]
	r._enemy_party = [wall]
	var before := wall.current_hp
	r._execute_group_physical([hero], "all_out_attack")
	var lost := before - wall.current_hp
	assert_gt(lost, 0, "SCOPE: the strike landed")
	assert_eq(_logged_hit(r, "all_out_attack hits"), lost, "the grind console must log the HP actually lost, not the pre-defense number")


func test_the_control_defense_really_mitigates() -> void:
	var soft := _wall(0)
	var hard := _wall(300)
	var a = HBR.new()
	a._player_party = [_member("A")]
	a._enemy_party = [soft]
	a._execute_group_physical(a._player_party, "all_out_attack")
	var b = HBR.new()
	b._player_party = [_member("B")]
	b._enemy_party = [hard]
	b._execute_group_physical(b._player_party, "all_out_attack")
	assert_gt(100000000 - soft.current_hp, 100000000 - hard.current_hp, "CONTROL: defense reduces what lands, so a pre-mitigation log would overstate")
