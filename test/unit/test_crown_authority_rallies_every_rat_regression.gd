extends GutTest

## Crown Authority authors target_type all_rat_allies and says the Rat King rallies all rat allies.
## Nothing read that tag, so the tank fallback buffed one body: the most wounded ally under half HP,
## otherwise the caster. A rat is a monster id with "rat" as its own token — "curator" contains the
## letters and is not one. The king is the one rallying; the sentence does not put him in the pack.
## The headless grind never selects a support row, so this aim lives in the live utility picker.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _body(who: String, monster_id: String, hp: int, max_hp: int) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = who
	c.max_hp = max_hp
	c.current_hp = hp
	c.attack = 40
	c.defense = 20
	c.magic = 10
	c.speed = 8
	c.is_alive = hp > 0
	if monster_id != "":
		c.set_meta("monster_type", monster_id)
	return c


func _crown() -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed = JSON.parse_string(raw)
	assert_not_null(parsed, "CONTROL: abilities.json parses")
	var table: Dictionary = parsed.get("abilities", parsed)
	var ability: Dictionary = table.get("crown_authority", {})
	assert_false(ability.is_empty(), "CONTROL: crown_authority is authored")
	return ability


func _buff_on(who: Combatant) -> Dictionary:
	for buff in who.active_buffs:
		if str(buff.get("stat", "")) == "attack":
			return buff
	return {}


func test_crown_authority_rallies_every_living_rat_and_not_the_king() -> void:
	var ability := _crown()
	assert_eq(str(ability.get("target_type", "")), "all_rat_allies",
		"CONTROL: the authored tag is the one this test exists for")
	assert_eq(float(ability.get("stat_modifier", 0.0)), 1.5, "the rally's attack multiplier stays 1.5")
	assert_eq(int(ability.get("duration", 0)), 3, "the rally still lasts 3 turns")
	var king := _body("Cave Rat King", "cave_rat_king", 6500, 6500)
	var swarm := _body("Cave Rat", "cave_rat", 900, 900)
	var guard := _body("Rat Guard", "rat_guard", 400, 1600)
	var steam := _body("Steam Rat", "steam_rat", 700, 700)
	var corpse := _body("Diseased Rat", "diseased_rat", 0, 1400)
	var bat := _body("Giant Bat", "giant_bat", 100, 850)
	var curator := _body("Curator", "masterite_curator_medieval", 50, 2000)
	var hero := _body("Fighter", "", 200, 400)
	var allies: Array = [king, swarm, guard, steam, corpse, bat, curator]
	var targets: Array = _bm._utility_targets(king, ability, allies, [hero])
	assert_eq(targets.size(), 3, "three living rats, not the wounded non-rat and not the king")
	assert_true(swarm in targets and guard in targets and steam in targets,
		"Crown Authority must boost every living rat ally, healthy or hurt")
	assert_false(king in targets, "the king rallies his allies; the text does not buff him")
	assert_false(corpse in targets, "a dead rat is not rallied")
	assert_false(bat in targets or curator in targets, "a bat and a curator are not rats")
	assert_false(hero in targets, "the rally does not land on the party")
	_bm._execute_support_ability(king, ability, targets)
	for rat in [swarm, guard, steam]:
		var buff := _buff_on(rat)
		assert_eq(float(buff.get("modifier", 0.0)), 1.5, "%s keeps the authored 1.5 attack buff" % rat.combatant_name)
		assert_eq(int(buff.get("duration", 0)), 3, "%s keeps the authored 3-turn duration" % rat.combatant_name)
	for other in [king, corpse, bat, curator, hero]:
		assert_eq(_buff_on(other), {}, "%s must not gain the rally" % other.combatant_name)


func test_a_provoked_king_still_rallies_rats_not_the_provoker() -> void:
	var ability := _crown()
	var fighter := _body("Fighter", "", 400, 400)
	var king := _body("Cave Rat King", "cave_rat_king", 6500, 6500)
	king.defense = 280
	king.max_hp = 6500
	var only := _body("Cave Rat", "cave_rat", 900, 900)
	var wounded_bat := _body("Giant Bat", "giant_bat", 80, 850)
	king.add_status("taunted_Fighter", 2)
	var action := {}
	for _i in 80:
		var rolled: Dictionary = _bm._execute_archetype_ai(king, "tank", [ability], [king, only, wounded_bat], [fighter])
		if str(rolled.get("ability_id", "")) == "crown_authority":
			action = rolled
			break
	assert_eq(str(action.get("ability_id", "")), "crown_authority", "CONTROL: the utility roll fired")
	assert_eq(action.get("targets"), [only],
		"the one living rat is the rally, not the wounded bat and not the king")
	assert_false(fighter in action.get("targets", []),
		"Provoke must not steal an ally rally onto the provoker")


func test_with_no_rat_allies_the_rally_does_not_become_a_self_buff() -> void:
	var ability := _crown()
	var king := _body("Cave Rat King", "cave_rat_king", 6500, 6500)
	var bat := _body("Giant Bat", "giant_bat", 100, 850)
	var targets: Array = _bm._utility_targets(king, ability, [king, bat], [])
	assert_eq(targets, [], "no living rat ally means nobody to rally, including the king")
