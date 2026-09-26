extends GutTest

## Provoke writes taunted_<caster> and _choose_target locks onto that caster.
## A Bat (speed 18) is an assassin: its bite and its basic attack pick the
## lowest HP% and never call _choose_target, so the fighter's Provoke is a
## log line and the bat still bites the wounded ally. A tank's basic-attack
## fallback (Cave Rat King when it does not spend the turn on a kit ability)
## picks the highest attack+magic the same way. Headless grind already locks.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _body(who: String, hp: int, max_hp: int, atk: int, defense: int, magic: int, spd: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = who
	c.max_hp = max_hp
	c.current_hp = hp
	c.attack = atk
	c.defense = defense
	c.magic = magic
	c.speed = spd
	c.is_alive = true
	return c


func _struck(action: Dictionary):
	if str(action.get("type", "")) == "attack":
		return action.get("target")
	var targets: Array = action.get("targets", [])
	if targets.size() == 1:
		return targets[0]
	return null


func test_a_taunted_assassin_hits_the_provoker_not_the_wounded_ally() -> void:
	var fighter := _body("Fighter", 400, 400, 20, 20, 10, 8)
	var squish := _body("Bard", 10, 200, 10, 10, 10, 10)
	# Bat: speed 18, defense does not clear the tank bar, bite is physical.
	var bat := _body("Bat", 500, 500, 230, 50, 150, 18)
	var bite := {"id": "bite", "type": "physical", "target_type": "single_enemy"}
	assert_eq(_bm._get_ai_archetype(bat, [bite]), "assassin",
		"a bat is an assassin — this is the live path Provoke has to lock")
	bat.add_status("taunted_Fighter", 2)
	for _i in 24:
		var action: Dictionary = _bm._execute_archetype_ai(bat, "assassin", [bite], [bat], [fighter, squish])
		assert_eq(_struck(action), fighter,
			"Provoke said the bat would hit the fighter; it hit the wounded bard")


func test_without_provoke_the_assassin_still_finishes_the_wounded_ally() -> void:
	var fighter := _body("Fighter", 400, 400, 20, 20, 10, 8)
	var squish := _body("Bard", 10, 200, 10, 10, 10, 10)
	var bat := _body("Bat", 500, 500, 230, 50, 150, 18)
	var action: Dictionary = _bm._execute_archetype_ai(bat, "assassin", [], [bat], [fighter, squish])
	assert_eq(str(action.get("type", "")), "attack")
	assert_eq(action.get("target"), squish,
		"CONTROL: with no taunt the assassin still focuses the lowest HP%")


func test_a_taunted_tank_basic_attack_hits_the_provoker_not_the_biggest_threat() -> void:
	var fighter := _body("Fighter", 400, 400, 10, 20, 10, 8)
	var cannon := _body("Mage", 400, 400, 90, 10, 90, 8)
	# defense > attack * 0.5 and max_hp >= 1500, same bar the Rat King clears.
	var king := _body("Cave Rat King", 6500, 6500, 40, 280, 10, 8)
	assert_eq(_bm._get_ai_archetype(king, []), "tank",
		"this body is a tank — the basic-attack fallback is the path that ignores Provoke")
	king.add_status("taunted_Fighter", 2)
	var action: Dictionary = _bm._execute_archetype_ai(king, "tank", [], [king], [fighter, cannon])
	assert_eq(str(action.get("type", "")), "attack")
	assert_eq(action.get("target"), fighter,
		"Provoke said the tank would swing at the fighter; it swung at the higher attack+magic")


func test_without_provoke_the_tank_still_swings_at_the_highest_threat() -> void:
	var fighter := _body("Fighter", 400, 400, 10, 20, 10, 8)
	var cannon := _body("Mage", 400, 400, 90, 10, 90, 8)
	var king := _body("Cave Rat King", 6500, 6500, 40, 280, 10, 8)
	var action: Dictionary = _bm._execute_archetype_ai(king, "tank", [], [king], [fighter, cannon])
	assert_eq(action.get("target"), cannon,
		"CONTROL: with no taunt the tank fallback still picks the highest attack+magic")


func test_a_taunted_tank_still_buffs_itself() -> void:
	var fighter := _body("Fighter", 400, 400, 10, 20, 10, 8)
	var king := _body("Glacius", 800, 2000, 40, 280, 10, 8)
	king.add_status("taunted_Fighter", 2)
	var armor := {"id": "frost_armor", "type": "support", "target_type": "self", "effect": "defense_up"}
	var action := {}
	for _i in 80:
		var rolled: Dictionary = _bm._execute_archetype_ai(king, "tank", [armor], [king], [fighter])
		if str(rolled.get("ability_id", "")) == "frost_armor":
			action = rolled
			break
	assert_eq(str(action.get("ability_id", "")), "frost_armor", "CONTROL: the utility roll fired")
	assert_eq(action.get("targets"), [king],
		"a self buff must stay on the caster when Provoke is up")
