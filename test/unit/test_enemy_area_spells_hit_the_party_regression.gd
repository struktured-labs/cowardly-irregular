extends GutTest

## Offensive enemy AI wrapped every spell in a one-element target list.
## Support rows already expand all_enemies through _utility_targets. Magic and
## physical rows did not, and both executors only hurt the list they are given.
## Stack Overflow's data says all_enemies and "damage to all enemies". A
## Recursive Loop (tank) and the headless grind both aimed it at one hero.
## A single_enemy row stays one body, so Provoke can still lock that swing.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _bm = null
var _abilities: Dictionary = {}


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	_abilities = (parsed as Dictionary).get("abilities", parsed)


func _hero(who: String, hp: int = 5000) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = who
	c.max_hp = hp
	c.current_hp = hp
	c.defense = 10
	c.magic_defense = 10
	c.speed = 10
	c.is_alive = true
	return c


func _caster(who: String, magic: int) -> Combatant:
	var c := _hero(who, 8000)
	c.magic = magic
	c.max_mp = 200
	c.current_mp = 200
	c.attack = 40
	return c


func _first_ability(rolls: int, pull: Callable) -> Dictionary:
	for _i in rolls:
		var action: Dictionary = pull.call()
		if str(action.get("type", "")) == "ability":
			return action
	return {}


func _spell(ability_id: String) -> Dictionary:
	assert_true(_abilities.has(ability_id), "CONTROL: %s is in abilities.json" % ability_id)
	return _abilities[ability_id]


func test_stack_overflow_hits_every_hero_and_the_executor_hurts_them() -> void:
	var spell := _spell("stack_overflow")
	assert_eq(str(spell.get("target_type", "")), "all_enemies",
		"CONTROL: Stack Overflow is authored as all_enemies")
	assert_eq(str(spell.get("type", "")), "magic",
		"CONTROL: it is magic, so the tank's offensive arm is the one that aims it")
	assert_true(str(spell.get("description", "")).contains("all enemies"),
		"CONTROL: the description promises the whole party")
	var loop := _caster("Recursive Loop", 420)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	var action := _first_ability(80, func(): return _bm._ai_tank(loop, [spell], [loop], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "stack_overflow", "CONTROL: the 50% offensive roll fired")
	var targets: Array = action.get("targets", [])
	assert_eq(targets.size(), 2, "Stack Overflow was aimed at one hero")
	assert_true(hero_a in targets and hero_b in targets, "both living heroes must be on the list")
	var before_a := hero_a.current_hp
	var before_b := hero_b.current_hp
	_bm._execute_magic_ability(loop, spell, targets)
	assert_lt(hero_a.current_hp, before_a, "the executor skipped the first hero")
	assert_lt(hero_b.current_hp, before_b, "the executor skipped the second hero — resolution only walks the list")


func test_a_single_enemy_strike_stays_on_one_hero() -> void:
	var spell := _spell("recursive_strike")
	assert_eq(str(spell.get("target_type", "")), "single_enemy",
		"CONTROL: Recursive Strike is the single-target row in the same kit")
	var loop := _caster("Recursive Loop", 420)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	var action := _first_ability(80, func(): return _bm._ai_tank(loop, [spell], [loop], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "recursive_strike", "CONTROL: the offensive roll fired")
	assert_eq(action.get("targets", []).size(), 1, "a single_enemy strike was widened to the party")


func test_provoke_does_not_collapse_a_party_wide_spell() -> void:
	var spell := _spell("stack_overflow")
	var loop := _caster("Recursive Loop", 420)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	hero_b.current_hp = 10
	loop.add_status("taunted_Hero", 3)
	var action := _first_ability(80, func(): return _bm._ai_tank(loop, [spell], [loop], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "stack_overflow", "CONTROL: the offensive roll fired")
	var targets: Array = action.get("targets", [])
	assert_eq(targets.size(), 2, "taunt collapsed Stack Overflow onto the provoker")
	assert_true(hero_b in targets, "the wounded ally was left out of an all_enemies cast")


func test_a_caster_breath_is_the_whole_party() -> void:
	var spell := _spell("void_breath")
	assert_eq(str(spell.get("target_type", "")), "all_enemies",
		"CONTROL: Void Breath is all_enemies")
	var dragon := _caster("Umbraxis", 500)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	var action := _first_ability(40, func(): return _bm._ai_caster(dragon, [spell], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "void_breath", "CONTROL: the cast roll fired")
	assert_eq(action.get("targets", []).size(), 2, "Void Breath was aimed at one hero")
	assert_true(hero_a in action["targets"] and hero_b in action["targets"],
		"both heroes must be in the breath")


func test_a_brute_cleave_is_the_whole_party() -> void:
	var spell := _spell("cleave")
	assert_eq(str(spell.get("target_type", "")), "all_enemies", "CONTROL: Cleave is all_enemies")
	var brute := _caster("Brute", 20)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	var action := _first_ability(80, func(): return _bm._ai_brute(brute, [spell], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "cleave", "CONTROL: the 30% ability roll fired")
	assert_eq(action.get("targets", []).size(), 2, "Cleave was aimed at one hero")


func test_an_assassin_area_spell_is_not_only_the_wounded() -> void:
	var spell := _spell("cleave")
	var assassin := _caster("Bat", 20)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	hero_b.current_hp = 10
	var action := _first_ability(40, func(): return _bm._ai_assassin(assassin, [spell], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "cleave", "CONTROL: the 60% ability roll fired")
	var targets: Array = action.get("targets", [])
	assert_eq(targets.size(), 2, "the assassin's area spell finished only the wounded hero")
	assert_true(hero_a in targets, "the healthy hero was left out")


func test_a_healer_area_spell_is_the_whole_party() -> void:
	var spell := _spell("stack_overflow")
	var healer := _caster("Elder", 80)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	var action := _first_ability(80, func(): return _bm._ai_healer(healer, [spell], [healer], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "stack_overflow", "CONTROL: the 30% offensive roll fired")
	assert_eq(action.get("targets", []).size(), 2, "the healer's area spell hit one hero")


func test_a_debuffer_area_spell_is_the_whole_party() -> void:
	var spell := _spell("stack_overflow")
	var hexer := _caster("Hexer", 80)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	var action := _first_ability(80, func(): return _bm._ai_debuffer(hexer, [spell], [hexer], [hero_a, hero_b]))
	assert_eq(str(action.get("ability_id", "")), "stack_overflow", "CONTROL: the offensive roll fired")
	assert_eq(action.get("targets", []).size(), 2, "the debuffer's area spell hit one hero")


func test_the_grind_aims_stack_overflow_at_the_party() -> void:
	var spell := _spell("stack_overflow")
	assert_eq(str(spell.get("target_type", "")), "all_enemies", "CONTROL: the grind reads this same row")
	var res = ResolverScript.new()
	var loop := _caster("Recursive Loop", 420)
	loop.learned_abilities.append("stack_overflow")
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	hero_b.current_hp = 10
	res._player_party = [hero_a, hero_b]
	res._enemy_party = [loop]
	var action: Dictionary = res._select_enemy_action(loop)
	assert_eq(str(action.get("ability_id", "")), "stack_overflow",
		"CONTROL: the grind picks the strongest offensive ability")
	var targets: Array = action.get("targets", [])
	assert_eq(targets.size(), 2, "the grind aimed Stack Overflow at one hero")
	assert_true(hero_a in targets and hero_b in targets, "both heroes must be in the grind's target list")
	var before_a := hero_a.current_hp
	var before_b := hero_b.current_hp
	res._resolve_ability(loop, "stack_overflow", targets)
	assert_lt(hero_a.current_hp, before_a, "headless resolution skipped the first hero")
	assert_lt(hero_b.current_hp, before_b, "headless resolution skipped the wounded hero")


func test_the_grind_does_not_let_provoke_shrink_an_area_spell() -> void:
	var res = ResolverScript.new()
	var loop := _caster("Recursive Loop", 420)
	loop.learned_abilities.append("stack_overflow")
	loop.add_status("taunted_Hero", 3)
	var hero_a := _hero("Hero")
	var hero_b := _hero("Ally")
	hero_b.current_hp = 10
	res._player_party = [hero_a, hero_b]
	res._enemy_party = [loop]
	var action: Dictionary = res._select_enemy_action(loop)
	assert_eq(str(action.get("ability_id", "")), "stack_overflow", "CONTROL: the area spell was selected")
	var targets: Array = action.get("targets", [])
	assert_eq(targets.size(), 2, "provoke collapsed the grind's area spell onto the tank")
	assert_true(hero_b in targets, "the wounded ally was left out")
