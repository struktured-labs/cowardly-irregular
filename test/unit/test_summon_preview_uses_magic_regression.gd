extends GutTest

## The battle menu's "~N total" for an eidolon is estimate_ability_damage. Summon Ifrit,
## Shiva, Ramuh, and Bahamut are type "summon" with no summon_id, and _execute_ability
## sends that shape through _execute_magic_ability: magic versus magic defense, then the
## spell's element. The preview treated every type other than "magic" as a weapon swing,
## so it quoted attack versus defense and ignored fire immunity. A level-1 Summoner
## (attack 60, magic 190) aiming Ifrit at defense 50 / magic defense 20 was shown ~140
## and dealt ~550; a fire-immune target was still shown that ~140 and took 0.
## Ally summons (rat_swarm, royal_summon, pack_call) carry summon_id and are not this hit.

const MenuScript = preload("res://src/battle/BattleCommandMenu.gd")
const SceneScript = preload("res://src/battle/BattleScene.gd")

var _saved_weather: String = ""
var _saved_weather_timer: float = 0.0
var _saved_terrain: String = ""
var _saved_party: Array = []
var _saved_order: Array = []
var _saved_index: int = 0
var _saved_current: Variant = null


func before_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and "weather_condition" in gs:
		_saved_weather = str(gs.weather_condition)
		_saved_weather_timer = float(gs.weather_timer)
		gs.weather_condition = "clear"
		gs.weather_timer = 100000.0
	_saved_terrain = str(BattleManager._current_terrain)
	BattleManager.set_terrain("plains")
	_saved_party = BattleManager.player_party.duplicate()
	_saved_order = BattleManager.selection_order.duplicate()
	_saved_index = BattleManager.selection_index
	_saved_current = BattleManager.current_combatant


func after_each() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and _saved_weather != "" and "weather_condition" in gs:
		gs.weather_condition = _saved_weather
		gs.weather_timer = _saved_weather_timer
	BattleManager.set_terrain(_saved_terrain)
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.selection_order.assign(_alive(_saved_order))
	BattleManager.selection_index = _saved_index
	BattleManager.current_combatant = _saved_current if is_instance_valid(_saved_current) else null


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _summoner() -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Summoner"
	c.is_alive = true
	c.max_hp = 900
	c.current_hp = 900
	c.max_mp = 100
	c.current_mp = 100
	# jobs.json summoner, level 1, before gear. Magic is the stat the eidolon hits with.
	c.attack = 60
	c.magic = 190
	c.defense = 70
	c.magic_defense = 30
	return c


func _foe(defense: int, magic_defense: int) -> Combatant:
	var t := Combatant.new()
	autofree(t)
	t.combatant_name = "Foe"
	t.is_alive = true
	t.max_hp = 99999
	t.current_hp = 99999
	t.defense = defense
	t.magic_defense = magic_defense
	return t


## The deterministic core of _execute_magic_ability plus take_damage, with variance,
## terrain, and weather held at identity. Element is applied by the caller.
func _magic_core(magic_stat: int, mult: float, magic_defense: int) -> int:
	var raw := int(magic_stat * mult)
	var mitigated := int((raw * raw) / float(maxi(1, raw + magic_defense)))
	return maxi(1, mitigated)


func _physical_core(attack: int, mult: float, defense: int) -> int:
	var raw := int(attack * mult)
	var mitigated := int((raw * raw) / float(maxi(1, raw + defense)))
	return maxi(1, mitigated)


func test_ifrit_preview_uses_magic_defense_not_attack() -> void:
	var caster := _summoner()
	var foe := _foe(50, 20)
	var ifrit: Dictionary = JobSystem.get_ability("summon_ifrit")
	assert_eq(str(ifrit.get("type", "")), "summon", "CONTROL: Ifrit is still a summon")
	assert_eq(float(ifrit.get("damage_multiplier", 0.0)), 3.0, "CONTROL: Ifrit is still 3.0x")
	assert_false(ifrit.has("summon_id"), "CONTROL: an eidolon is not an ally spawn")
	var from_magic := _magic_core(caster.magic, 3.0, foe.magic_defense)
	var from_attack := _physical_core(caster.attack, 3.0, foe.defense)
	assert_gt(from_magic - from_attack, 100,
		"CONTROL: the fixture must separate the two formulas (%d magic vs %d attack)" % [from_magic, from_attack])
	var preview := BattleManager.estimate_ability_damage(caster, foe, ifrit)
	assert_eq(preview, from_magic,
		"Ifrit must preview the magic hit (%d), not the attack hit (%d) — got %d" % [from_magic, from_attack, preview])
	var working: String = str(BattleManager.estimate_ability_breakdown(caster, foe, ifrit)["formula"])
	assert_true(working.contains("MAG %d" % caster.magic) and working.contains("MDEF %d" % foe.magic_defense),
		"Formula Sight must name magic and magic defense (%s)" % working)


func test_bahamut_preview_uses_magic_even_with_no_element() -> void:
	var caster := _summoner()
	var foe := _foe(50, 20)
	var bahamut: Dictionary = JobSystem.get_ability("summon_bahamut")
	assert_eq(float(bahamut.get("damage_multiplier", 0.0)), 5.0, "CONTROL: Bahamut is still 5.0x")
	assert_eq(str(bahamut.get("element", "")), "", "CONTROL: Bahamut authors no element")
	var preview := BattleManager.estimate_ability_damage(caster, foe, bahamut)
	assert_eq(preview, _magic_core(caster.magic, 5.0, foe.magic_defense),
		"Bahamut has no element and still hits with magic — preview %d" % preview)
	assert_ne(preview, _physical_core(caster.attack, 5.0, foe.defense),
		"Bahamut must not fall through to the attack formula")


func test_an_elemental_eidolon_honors_immunity() -> void:
	var caster := _summoner()
	for id in ["summon_ifrit", "summon_shiva", "summon_ramuh"]:
		var ability: Dictionary = JobSystem.get_ability(id)
		var element := str(ability.get("element", ""))
		assert_ne(element, "", "CONTROL: %s must still name an element" % id)
		var immune := _foe(50, 20)
		var typed: Array[String] = []
		typed.append(element)
		immune.elemental_immunities = typed
		var preview := BattleManager.estimate_ability_damage(caster, immune, ability)
		assert_eq(preview, 0, "%s against %s immunity must preview 0, not a physical swing — got %d" % [id, element, preview])
		var working: String = str(BattleManager.estimate_ability_breakdown(caster, immune, ability)["formula"])
		assert_true(working.contains("immune"), "%s's working must say why the preview is 0 (%s)" % [id, working])


func test_ifrit_preview_rises_against_a_fire_weakness() -> void:
	var caster := _summoner()
	var plain := _foe(50, 20)
	var weak := _foe(50, 20)
	var typed: Array[String] = []
	typed.append("fire")
	weak.elemental_weaknesses = typed
	var ifrit: Dictionary = JobSystem.get_ability("summon_ifrit")
	var neutral := BattleManager.estimate_ability_damage(caster, plain, ifrit)
	var boosted := BattleManager.estimate_ability_damage(caster, weak, ifrit)
	var as_magic := BattleManager.estimate_ability_damage(caster, weak, {
		"type": "magic",
		"damage_multiplier": float(ifrit.get("damage_multiplier", 0.0)),
		"element": "fire",
	})
	assert_gt(boosted, neutral, "a fire weakness must raise Ifrit's preview (%d vs %d)" % [boosted, neutral])
	assert_eq(boosted, as_magic,
		"Ifrit's weak-target preview must match the same numbers a magic spell uses (%d vs %d)" % [boosted, as_magic])


func test_an_ally_spawn_is_not_quoted_as_an_eidolon_hit() -> void:
	var caster := _summoner()
	var foe := _foe(50, 20)
	for id in ["rat_swarm", "royal_summon", "pack_call"]:
		var ability: Dictionary = JobSystem.get_ability(id)
		assert_eq(str(ability.get("type", "")), "summon", "CONTROL: %s is a summon" % id)
		assert_ne(str(ability.get("summon_id", "")), "", "CONTROL: %s still spawns an ally" % id)
		assert_false(ability.has("damage_multiplier"), "CONTROL: %s is not a damage eidolon" % id)
		var preview := BattleManager.estimate_ability_damage(caster, foe, ability)
		var physical := BattleManager.estimate_ability_damage(caster, foe, {"type": "physical", "damage_multiplier": 1.0})
		assert_eq(preview, physical,
			"%s must stay off the magic formula — preview %d, physical %d" % [id, preview, physical])


func test_the_menu_prints_the_magic_total() -> void:
	var caster := _summoner()
	caster.learn_ability("summon_ifrit")
	var foe := _foe(50, 20)
	var expected := _magic_core(caster.magic, 3.0, foe.magic_defense)
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.selection_order.assign([caster] as Array[Combatant])
	BattleManager.selection_index = 0
	BattleManager.current_combatant = caster
	var scene = autofree(SceneScript.new())
	scene.party_members.assign([caster] as Array[Combatant])
	scene.test_enemies.assign([foe] as Array[Combatant])
	var sprite := AnimatedSprite2D.new()
	add_child_autofree(sprite)
	scene.party_sprite_nodes.append(sprite)
	var enemy_sprite := AnimatedSprite2D.new()
	add_child_autofree(enemy_sprite)
	scene.enemy_sprite_nodes.append(enemy_sprite)
	add_child_autofree(scene)
	var label := ""
	for item in MenuScript.new(scene).build_command_menu_items_with_targets(caster):
		if str(item.get("id", "")) == "ability_menu":
			for row in item.get("submenu", []):
				if str(row.get("id", "")) == "ability_summon_ifrit":
					label = str(row.get("label", ""))
	assert_ne(label, "", "CONTROL: the Ability menu must list Summon Ifrit")
	assert_true(label.contains("~%d total" % expected),
		"the row the player reads must be the magic total %d, not an attack estimate — got '%s'" % [expected, label])
