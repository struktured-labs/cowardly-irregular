extends GutTest

## provoke is in a shipped autobattle template. It writes taunted_<caster> and live's
## _choose_target locks the victim onto that caster. The grind wrote the key and still
## struck whoever had the least HP. Player scripts are not retargeted: live's autobattle
## resolver does not consult taunt either.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()


func _fighter(cname: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": cname,
		"max_hp": 5000,
		"max_mp": 500,
		"attack": 40,
		"defense": 10,
		"magic": 40,
		"speed": 10,
	})
	add_child_autofree(c)
	c.current_hp = c.max_hp
	c.current_mp = c.max_mp
	return c


func _party(tank: Combatant, squish: Combatant, enemy: Combatant) -> void:
	_res._player_party = [tank, squish]
	_res._enemy_party = [enemy]


func test_provoke_makes_the_enemy_hit_the_provoker() -> void:
	var tank := _fighter("Tank")
	var squish := _fighter("Squish")
	squish.current_hp = 10
	var enemy := _fighter("Goblin")
	enemy.current_mp = 0
	_res._player_party = [tank]
	_res._enemy_party = [enemy]
	_res._resolve_ability(tank, "provoke", [enemy])
	assert_true(enemy.has_status("taunted_Tank"),
		"provoke must write taunted_<caster> — _find_taunter reads that key and nothing else")
	_party(tank, squish, enemy)
	var action: Dictionary = _res._select_enemy_action(enemy)
	assert_eq(action.get("type"), "attack")
	assert_eq(action.get("target"), tank,
		"a taunted enemy struck the lowest-HP ally — live locks onto the provoker")


func test_without_a_taunt_the_enemy_still_picks_lowest_hp() -> void:
	var tank := _fighter("Tank")
	var squish := _fighter("Squish")
	squish.current_hp = 10
	var enemy := _fighter("Goblin")
	enemy.current_mp = 0
	_party(tank, squish, enemy)
	var action: Dictionary = _res._select_enemy_action(enemy)
	assert_eq(action.get("target"), squish,
		"CONTROL: with no taunt the grind's enemy AI still focuses the lowest HP")


func test_a_dead_taunter_falls_through_to_lowest_hp() -> void:
	var tank := _fighter("Tank")
	tank.is_alive = false
	var squish := _fighter("Squish")
	squish.current_hp = 10
	var enemy := _fighter("Goblin")
	enemy.current_mp = 0
	enemy.add_status("taunted_Tank", 2)
	_party(tank, squish, enemy)
	var action: Dictionary = _res._select_enemy_action(enemy)
	assert_eq(action.get("target"), squish,
		"a taunt naming a dead ally must not lock the attack — live only matches a living name")


func test_an_offensive_ability_aims_at_the_taunter() -> void:
	var tank := _fighter("Tank")
	var squish := _fighter("Squish")
	squish.current_hp = 10
	var enemy := _fighter("Goblin")
	enemy.learned_abilities.append("fire")
	_party(tank, squish, enemy)
	enemy.add_status("taunted_Tank", 2)
	var action: Dictionary = _res._select_enemy_action(enemy)
	assert_eq(action.get("type"), "ability")
	assert_eq(action.get("ability_id"), "fire")
	var targets: Array = action.get("targets", [])
	assert_eq(targets.size(), 1)
	assert_eq(targets[0], tank,
		"a taunted caster's spell must aim at the provoker, not the lowest-HP ally")
