extends GutTest

## Enemy-facing support was aimed at the caster's own side.
## A tank treats every utility row as a buff for itself, or for a wounded ally.
## A healer's support branch always picks an ally. The shared opener slot aims
## "all_enemies" at the caster, because that string does not contain "enemy".
## Lure, Infinite Loop, Rattle, Bad Vibes, and Peace Sign therefore never land
## on the party. A self row such as Frost Armor must stay on the caster even
## when a packmate is under half HP.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null

func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)

func _fighter(who: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.max_hp = max_hp
	c.current_hp = hp
	c.speed = 10
	c.is_alive = true
	return c

func _first_ability(rolls: int, pull: Callable) -> Dictionary:
	for _i in rolls:
		var action: Dictionary = pull.call()
		if str(action.get("type", "")) == "ability":
			return action
	return {}

func test_a_tank_taunt_lands_on_the_party() -> void:
	var mimic := _fighter("Mimic", 200, 200)
	var hero := _fighter("Hero", 200, 200)
	var lure := {"id": "lure", "type": "support", "target_type": "single_enemy", "effect": "taunt"}
	var action := _first_ability(80, func(): return _bm._ai_tank(mimic, [lure], [mimic], [hero]))
	assert_eq(str(action.get("ability_id", "")), "lure", "CONTROL: the 40% utility roll fired")
	assert_eq(action["targets"], [hero], "Lure is single_enemy — the mimic taunted itself")

func test_a_tank_party_debuff_hits_every_hero_not_the_wounded_packmate() -> void:
	var boss := _fighter("Supervisor", 500, 500)
	var pack := _fighter("Intern", 40, 100)
	var hero_a := _fighter("Hero", 200, 200)
	var hero_b := _fighter("Ally", 80, 200)
	var review := {"id": "performance_review", "type": "support", "target_type": "all_enemies", "effect": "all_stats_down"}
	var action := _first_ability(80, func(): return _bm._ai_tank(boss, [review], [boss, pack], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "performance_review", "CONTROL: the 40% utility roll fired")
	assert_eq(action["targets"].size(), 2, "all_enemies is the whole party, not one body")
	assert_true(hero_a in action["targets"] and hero_b in action["targets"],
		"Performance Review must land on both heroes")
	assert_false(boss in action["targets"] or pack in action["targets"],
		"the review hit the supervisor's own side")

func test_a_tank_party_buff_reaches_every_ally() -> void:
	var boss := _fighter("Supervisor", 500, 500)
	var pack := _fighter("Intern", 500, 500)
	var hero := _fighter("Hero", 200, 200)
	var overtime := {"id": "mandatory_overtime", "type": "support", "target_type": "all_allies", "effect": "attack_up"}
	var action := _first_ability(80, func(): return _bm._ai_tank(boss, [overtime], [boss, pack], [hero]))
	assert_eq(str(action.get("ability_id", "")), "mandatory_overtime", "CONTROL: the 40% utility roll fired")
	assert_true(boss in action["targets"] and pack in action["targets"],
		"Mandatory Overtime boosts every ally")
	assert_false(hero in action["targets"], "the overtime buff hit the party")

func test_a_self_buff_stays_on_the_caster_when_an_ally_is_hurt() -> void:
	var dragon := _fighter("Glacius", 800, 800)
	var pack := _fighter("Whelp", 30, 100)
	var hero := _fighter("Hero", 200, 200)
	var armor := {"id": "frost_armor", "type": "support", "target_type": "self", "effect": "defense_up"}
	var action := _first_ability(80, func(): return _bm._ai_tank(dragon, [armor], [dragon, pack], [hero]))
	assert_eq(str(action.get("ability_id", "")), "frost_armor", "CONTROL: the 40% utility roll fired")
	assert_eq(action["targets"], [dragon], "Frost Armor encases the caster, not the wounded whelp")

func test_a_healer_debuff_lands_on_the_party() -> void:
	var hippie := _fighter("Hippie", 120, 120)
	var hero := _fighter("Hero", 200, 200)
	var vibes := {"id": "bad_vibes", "type": "support", "target_type": "single_enemy", "effect": "all_stats_down"}
	var action := _first_ability(80, func(): return _bm._ai_healer(hippie, [vibes], [hippie], [hero]))
	assert_eq(str(action.get("ability_id", "")), "bad_vibes", "CONTROL: the 40% support roll fired")
	assert_eq(action["targets"], [hero], "Bad Vibes is single_enemy — it hit an ally")

func test_a_healer_party_pacify_hits_every_hero() -> void:
	var hippie := _fighter("Hippie", 120, 120)
	var hero_a := _fighter("Hero", 200, 200)
	var hero_b := _fighter("Ally", 200, 200)
	var peace := {"id": "peace_sign", "type": "support", "target_type": "all_enemies", "effect": "pacify"}
	var action := _first_ability(80, func(): return _bm._ai_healer(hippie, [peace], [hippie], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "peace_sign", "CONTROL: the 40% support roll fired")
	assert_true(hero_a in action["targets"] and hero_b in action["targets"],
		"Peace Sign is all_enemies and pacified nobody on the party")
	assert_false(hippie in action["targets"], "Peace Sign pacified the caster")

func test_a_party_wide_opener_is_not_a_self_cast() -> void:
	## Brutes and assassins share _ai_utility_action. Skeleton Rattle is all_enemies.
	var skeleton := _fighter("Skeleton", 80, 80)
	var hero_a := _fighter("Hero", 200, 200)
	var hero_b := _fighter("Ally", 200, 200)
	var rattle := {"id": "rattle", "type": "support", "target_type": "all_enemies", "effect": "attack_down"}
	var action: Dictionary = _bm._ai_utility_action(skeleton, [rattle], [hero_a, hero_b], 1.0)
	assert_false(action.is_empty(), "CONTROL: chance 1.0 returns the opener")
	assert_eq(action["targets"].size(), 2, "all_enemies passes every living hero")
	assert_true(hero_a in action["targets"] and hero_b in action["targets"],
		"Rattle must lower the party's attack")
	assert_false(skeleton in action["targets"], "Rattle lowered the skeleton's own attack")
