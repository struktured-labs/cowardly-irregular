extends GutTest

## Provoke's row says "Force an enemy to target you for 2 turns" and abilities.json
## authors duration 2. The taunt arm called add_status without that duration, and
## add_status's default is 3, so the lock lasted an extra round. Menu and autobattle
## both reach BattleManager._execute_ability; the grind reaches HeadlessBattleResolver.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm


func before_each() -> void:
	_bm = BattleManagerScript.new()
	add_child_autofree(_bm)


func _provoke() -> Dictionary:
	var ability: Dictionary = JobSystem.get_ability("provoke")
	assert_false(ability.is_empty(), "CONTROL: provoke must resolve from abilities.json")
	assert_eq(str(ability.get("effect", "")), "taunt")
	assert_true(str(ability.get("description", "")).contains("2 turns"),
		"CONTROL: the player-facing text still promises 2 turns — %s" % str(ability.get("description", "")))
	assert_eq(int(ability.get("duration", -1)), 2,
		"CONTROL: the authored duration is 2, matching the text")
	return ability


func _fighter(cname: String) -> Combatant:
	var c := Combatant.new()
	add_child_autofree(c)
	c.combatant_name = cname
	c.max_hp = 400
	c.current_hp = 400
	c.max_mp = 40
	c.current_mp = 40
	c.is_alive = true
	c.job = {"id": "fighter", "abilities": ["provoke", "power_strike", "cleave"]}
	return c


func _key(caster: Combatant) -> String:
	return "taunted_%s" % caster.combatant_name


func test_omitting_duration_stores_three_turns() -> void:
	## Names the default the bug was hitting, so a green here is not "duration happened to be 2".
	var enemy := _fighter("Goblin")
	enemy.add_status("marker")
	assert_eq(int(enemy.status_durations.get("marker", -1)), 3,
		"add_status with no duration argument stores 3 — that is the extra turn Provoke was giving")


func test_a_menu_or_autobattle_provoke_lasts_two_turns() -> void:
	var promised := int(_provoke().get("duration"))
	var fighter := _fighter("Bram")
	var enemy := _fighter("Goblin")
	_bm.player_party.append(fighter)
	_bm.enemy_party.append(enemy)
	_bm._execute_ability(fighter, "provoke", [enemy])
	var key := _key(fighter)
	assert_true(enemy.has_status(key), "provoke must lock the enemy onto the fighter")
	assert_eq(int(enemy.status_durations.get(key, -1)), promised,
		"the lock must be the authored 2 turns, not add_status's default of 3")
	for _i in promised - 1:
		enemy.end_turn()
	assert_true(enemy.has_status(key), "one round in, the 2-turn lock must still hold")
	enemy.end_turn()
	assert_false(enemy.has_status(key), "after 2 rounds the lock the description promised must be gone")


func test_a_grind_provoke_stores_the_same_two_turns() -> void:
	var promised := int(_provoke().get("duration"))
	var res = ResolverScript.new()
	var fighter := _fighter("Bram")
	var enemy := _fighter("Goblin")
	res._resolve_ability(fighter, "provoke", [enemy])
	var key := _key(fighter)
	assert_true(enemy.has_status(key), "the grind must write taunted_<caster>, the key live's lock reads")
	assert_eq(int(enemy.status_durations.get(key, -1)), promised,
		"a grind Provoke lasted the default 3 turns while the battle and the text say 2")
