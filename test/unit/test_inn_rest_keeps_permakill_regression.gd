extends GutTest

## InnInterior is the rest the player actually buys. revive() refuses a permakilled
## ally, then the loop still wrote current_hp = max_hp, so the party menu showed a
## full green bar under the KO stamp and the death stayed. Poison, blind, and
## temporary buffs were left on the same combatants the innkeeper called fully
## rested. The marker and a formation row are not ailments.

const INN_PATH := "res://src/maps/interiors/InnInterior.gd"
const CombatantRes = preload("res://src/battle/Combatant.gd")

const _STUB_GAMELOOP := """
extends Node
var party: Array = []
"""

var _prior_gold: int = 0


func before_each() -> void:
	_prior_gold = GameState.party_gold


func after_each() -> void:
	GameState.party_gold = _prior_gold


func _make_stub_gameloop(party: Array) -> Node:
	var script := GDScript.new()
	script.source_code = _STUB_GAMELOOP
	script.reload()
	var stub := Node.new()
	stub.set_script(script)
	stub.name = "GameLoop"
	stub.party = party
	get_tree().root.add_child(stub)
	return stub


func _member(name_str: String, alive: bool, hp: int) -> Combatant:
	var c: Combatant = CombatantRes.new()
	add_child_autofree(c)
	c.combatant_name = name_str
	c.max_hp = 100
	c.current_hp = hp
	c.max_mp = 40
	c.current_mp = 0
	c.is_alive = alive
	return c


func _has_effect(entries: Array, effect: String) -> bool:
	for entry in entries:
		if entry is Dictionary and str(entry.get("effect", "")) == effect:
			return true
	return false


func test_rest_revives_a_ko_clears_ailments_and_leaves_permakill() -> void:
	var perma := _member("Bard", false, 0)
	perma.add_status("permakilled", -1)
	perma.add_status("poison", 3)
	perma.add_buff("Protect", "defense", 1.5, 3)
	perma.add_buff("formation_atk", "attack", 1.1, 999)
	perma.add_debuff("Armor Break", "defense", 0.7, 2)
	perma.add_debuff("formation_def", "defense", 0.9, 999)
	perma.permanent_injuries.append({"stat": "max_hp", "penalty": 8, "id": "rib"})

	var ko := _member("Fighter", false, 0)
	ko.add_status("blind", 2)

	var wounded := _member("Mage", true, 1)
	wounded.add_status("poison", 3)
	wounded.add_buff("Haste", "speed", 1.5, 3)

	var stub := _make_stub_gameloop([perma, ko, wounded])
	var inn: Node2D = load(INN_PATH).new()
	add_child_autofree(inn)
	GameState.party_gold = 500
	inn._do_rest()
	stub.free()

	assert_eq(int(GameState.get_gold()), 500 - int(load(INN_PATH).REST_COST),
		"the night is still paid for")
	assert_false(perma.is_alive, "a permakilled ally stays down")
	assert_eq(perma.current_hp, 0, "their HP bar stays empty — revive() refused, so the top-up must not run")
	assert_true(perma.has_status("permakilled"), "the permadeath marker stays")
	assert_false(perma.has_status("poison"), "poison on that corpse is still an ailment")
	assert_false(_has_effect(perma.active_buffs, "Protect"), "a temporary buff does not survive the night")
	assert_true(_has_effect(perma.active_buffs, "formation_atk"), "the formation row is not a temporary buff")
	assert_false(_has_effect(perma.active_debuffs, "Armor Break"), "a temporary debuff does not survive the night")
	assert_true(_has_effect(perma.active_debuffs, "formation_def"), "the formation penalty stays with the row")
	assert_eq(perma.permanent_injuries.size(), 1, "a permanent injury is not an ailment")
	assert_true(ko.is_alive, "an ordinary KO is raised")
	assert_eq(ko.current_hp, ko.max_hp, "and brought to full HP")
	assert_false(ko.has_status("blind"), "blind does not survive the night")
	assert_eq(wounded.current_hp, wounded.max_hp, "a living ally is healed")
	assert_eq(wounded.current_mp, wounded.max_mp, "and their MP is restored")
	assert_false(wounded.has_status("poison"), "poison does not survive the night")
	assert_false(_has_effect(wounded.active_buffs, "Haste"), "a temporary buff on a living ally does not survive the night")

	await get_tree().create_timer(1.8).timeout
