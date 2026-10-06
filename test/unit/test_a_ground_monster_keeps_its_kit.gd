extends GutTest

## Regression (cowir-main's 2026-10-05 difficulty measurement): GameLoop._combatant_for_headless, the autogrind
## enemy builder, kept a monster's stats and dropped its abilities, weaknesses and resistances, all of which the
## spawner row carries and the live spawner applies. Every ground monster only basic-attacked and had no element.
## The headless enemy now carries the same kit and elements as the live one.

const GameLoopScript := preload("res://src/GameLoop.gd")
const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _row() -> Dictionary:
	return {"id": "slime", "name": "Slime", "stats": {"max_hp": 680, "attack": 40, "defense": 20, "magic": 10, "speed": 8},
		"weaknesses": ["fire"], "resistances": ["physical"], "abilities": ["tackle"]}


func _enemy(row: Dictionary) -> Combatant:
	var gl: Node = autofree(GameLoopScript.new())
	var e: Combatant = gl._combatant_for_headless(row)
	autofree(e)
	return e


func test_the_ground_monster_keeps_its_abilities() -> void:
	var e := _enemy(_row())
	assert_eq(e.learned_abilities, ["tackle"] as Array[String], "the resolver's enemy AI reads learned_abilities")
	assert_eq(HBR.new()._find_attack_ability(e), "tackle", "so the ground monster can actually use its attack ability")


func test_the_ground_monster_keeps_its_elements() -> void:
	var e := _enemy(_row())
	assert_eq(e.elemental_weaknesses, ["fire"] as Array[String], "a ground slime is weak to fire, as in a live battle")
	assert_eq(e.elemental_resistances, ["physical"] as Array[String], "and resists what it resists live")


func test_a_monster_with_no_kit_stays_a_basic_attacker() -> void:
	var row := _row()
	row.erase("abilities")
	var e := _enemy(row)
	assert_true(e.learned_abilities.is_empty(), "CONTROL: no authored abilities means none invented")
	assert_eq(HBR.new()._find_attack_ability(e), "", "CONTROL: and the AI falls back to its basic attack")
