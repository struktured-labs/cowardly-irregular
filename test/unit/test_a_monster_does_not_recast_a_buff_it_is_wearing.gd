extends GutTest

## Glacius rolled Frost Armor on 41% of turns whether or not it was already up: 15 MP and a turn to refresh a 3-turn buff.
## A self stat buff the caster already wears, as strong and with turns left, is not offered to the ladder.

const DRAWS := 200


func _row(id: String) -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	return (raw.get("monsters", raw) as Dictionary).get(id, {})


func _boss(id: String) -> Combatant:
	var row := _row(id)
	var s: Dictionary = row.get("stats", {})
	var c: Combatant = Combatant.new()
	add_child_autofree(c)
	c.initialize({"name": str(row.get("name", id)), "max_hp": int(s.get("max_hp", 1)), "max_mp": int(s.get("max_mp", 0)),
		"attack": int(s.get("attack", 1)), "defense": int(s.get("defense", 1)), "magic": int(s.get("magic", 1)),
		"magic_defense": int(s.get("magic_defense", 1)), "speed": int(s.get("speed", 1))})
	c.set_meta("monster_type", id)
	var kit: Array = row.get("abilities", [])
	c.job = {"abilities": kit.duplicate(), "name": c.combatant_name}
	return c


func _foes() -> Array:
	var out: Array = []
	for i in 3:
		var p: Combatant = Combatant.new()
		add_child_autofree(p)
		p.initialize({"name": "PC%d" % i, "max_hp": 900, "max_mp": 100, "attack": 60, "defense": 60, "magic": 60, "magic_defense": 60, "speed": 20})
		out.append(p)
	return out


## How many of DRAWS live picks are `ability_id`, at full MP each draw.
func _picks(boss: Combatant, foes: Array, ability_id: String) -> int:
	var n := 0
	for i in DRAWS:
		boss.current_mp = boss.max_mp
		var a: Dictionary = BattleManager._make_ai_decision(boss, [boss], foes)
		if str(a.get("ability_id", "")) == ability_id:
			n += 1
	return n


func test_glacius_does_not_recast_frost_armor_while_it_is_up() -> void:
	var ab: Dictionary = JobSystem.get_ability("frost_armor")
	assert_eq(str(ab.get("effect", "")), "defense_up", "FLOOR: frost_armor is still the defense buff this is written against")
	assert_eq(str(ab.get("target_type", "")), "self", "FLOOR: and still cast on the caster")
	var boss := _boss("ice_dragon")
	var foes := _foes()
	assert_gt(_picks(boss, foes, "frost_armor"), DRAWS / 10, "CONTROL: with no buff up, Glacius reaches for Frost Armor")
	boss.add_buff("Praesidium", "defense", float(ab.get("stat_modifier", 1.0)), int(ab.get("duration", 3)))
	assert_eq(_picks(boss, foes, "frost_armor"), 0, "worn at full strength with turns left: never offered")


func test_a_buff_about_to_lapse_may_be_renewed() -> void:
	var ab: Dictionary = JobSystem.get_ability("frost_armor")
	var boss := _boss("ice_dragon")
	boss.add_buff("Praesidium", "defense", float(ab.get("stat_modifier", 1.0)), int(ab.get("duration", 3)))
	boss.active_buffs[0]["remaining_turns"] = BattleManager.SELF_BUFF_RENEW_TURNS
	assert_gt(_picks(boss, _foes(), "frost_armor"), 0, "on its last turn the buff is renewable")


func test_a_weaker_buff_does_not_block_a_stronger_one() -> void:
	var ab: Dictionary = JobSystem.get_ability("frost_armor")
	var boss := _boss("ice_dragon")
	boss.add_buff("Praesidium", "defense", float(ab.get("stat_modifier", 1.0)) - 0.3, 3)
	assert_false(BattleManager._self_buff_is_already_worn(boss, ab), "a weaker defense buff leaves the stronger cast worth making")
	boss.active_buffs.clear()
	boss.add_buff("Berserk", "attack", 9.0, 3)
	assert_false(BattleManager._self_buff_is_already_worn(boss, ab), "and a buff on another stat is not this buff")


func test_only_self_stat_buffs_are_judged() -> void:
	var boss := _boss("ice_dragon")
	boss.add_buff("Praesidium", "defense", 9.0, 9)
	var judged := 0
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/abilities.json"))
	var all: Dictionary = raw.get("abilities", raw)
	for id in all:
		var a: Dictionary = all[id]
		var mine: bool = str(a.get("target_type", "")) == "self" and str(a.get("effect", "")) == "defense_up"
		assert_eq(BattleManager._self_buff_is_already_worn(boss, a), mine, "%s: withheld only if it is a self defense buff" % id)
		judged += int(mine)
	assert_gt(judged, 3, "FLOOR: the data holds self defense buffs for this to judge")
