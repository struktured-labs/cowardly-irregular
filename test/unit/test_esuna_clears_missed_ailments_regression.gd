extends GutTest

## Purgatio (esuna, effect "cleanse") says it removes every negative status.
## The arm only named ten. Shipped enemies land five more, and the cast left
## all five on the ally while the log said there was nothing to cleanse:
##   silence      void_pulse — Cartographer, Umbraxis, the Null Entity
##   pacify       peace_sign — New Age Retro Hippie
##   static       static_field — Corrupted Sprite (4% max HP each turn)
##   memory_leak  memory_leak — SCRIPT ERROR (3% max HP each turn)
##   festered     fester — Diseased Rat (doubles the next poison tick)
## Regen, haste, Praesidium, and Velamen must survive. Cleanse is not dispel.

const MISSED: Array[String] = ["silence", "pacify", "static", "memory_leak", "festered"]
const ResolverScript := preload("res://src/autogrind/HeadlessBattleResolver.gd")


func _person(who: String, mp: int) -> Combatant:
	var c := Combatant.new()
	c.combatant_name = who
	c.max_hp = 200
	c.current_hp = 200
	c.max_mp = mp
	c.current_mp = mp
	c.is_alive = true
	add_child_autofree(c)
	return c


func _afflict(target: Combatant) -> void:
	for status in MISSED:
		target.add_status(status, 3)
	target.add_status("regen", 4)
	target.add_status("haste", 3)
	target.add_buff("Praesidium", "defense", 1.5, 3)
	target.add_buff("Velamen", "magic_defense", 1.5, 3)


func _assert_cleared(target: Combatant, where: String) -> void:
	var left: Array[String] = []
	for status in MISSED:
		if target.has_status(status):
			left.append(status)
	assert_eq(left.size(), 0, "%s left ailments it is supposed to clear: %s" % [where, str(left)])
	assert_true(target.has_status("regen"), "%s stripped regen — cleanse must leave a beneficial status" % where)
	assert_true(target.has_status("haste"), "%s stripped haste" % where)
	assert_eq(target.active_buffs.size(), 2, "%s stripped Praesidium or Velamen" % where)


func test_live_esuna_clears_the_ailments_the_list_forgot() -> void:
	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return
	var caster := _person("Cleric", 40)
	var ally := _person("Ally", 20)
	_afflict(ally)
	assert_eq(ally.status_effects.size(), MISSED.size() + 2,
		"CONTROL: the five ailments plus regen and haste are on the ally before the cast")
	BattleManager._execute_support_ability(caster, {
		"id": "esuna",
		"name": "Purgatio",
		"type": "support",
		"effect": "cleanse",
	}, [ally])
	_assert_cleared(ally, "live Esuna")


func test_limit_break_keeps_its_named_list() -> void:
	## The Group menu tooltip is "Ultimate combined assault — requires 4 AP from all
	## members". It names no cleanse. Silence and pacify were already on the list;
	## static, memory leak, and festered were not, and they stay.
	assert_not_null(BattleManager, "BattleManager autoload required")
	if BattleManager == null:
		return
	var ally := _person("Ally", 20)
	ally.add_status("silence", 2)
	ally.add_status("pacify", 2)
	ally.add_status("static", 3)
	ally.add_status("memory_leak", 4)
	ally.add_status("festered", 3)
	ally.add_status("regen", 4)
	ally.add_status("haste", 3)
	BattleManager._limit_break_cleanse([ally])
	assert_false(ally.has_status("silence"), "limit break stopped clearing silence")
	assert_false(ally.has_status("pacify"), "limit break stopped clearing pacify")
	assert_true(ally.has_status("static"), "limit break cleared static, which its list does not name")
	assert_true(ally.has_status("memory_leak"), "limit break cleared memory leak, which its list does not name")
	assert_true(ally.has_status("festered"), "limit break cleared festered, which its list does not name")
	assert_true(ally.has_status("regen"), "limit break stripped regen")
	assert_true(ally.has_status("haste"), "limit break stripped haste")


func test_grind_esuna_clears_the_same_ailments() -> void:
	var resolver: HeadlessBattleResolver = ResolverScript.new()
	var caster := _person("Cleric", 40)
	var ally := _person("Ally", 20)
	_afflict(ally)
	resolver.call("_resolve_ability", caster, "esuna", [ally])
	_assert_cleared(ally, "grind Esuna")
	assert_false(ally.has_status("cleanse"), "Esuna must not invent a status named cleanse")
