extends GutTest

## The permadeath marker lives in status_effects, and both battle engines wipe that
## array at the start of the next fight so poison cannot leak across encounters.
## The wipe did not spare permakilled. A character erased in fight one walked into
## fight two as an ordinary KO: Raise and Phoenix Down stood them back up, because
## revive() only refuses while the marker is still on them.
## Poison must still be stripped. A normal KO must still be revivable.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _state = null


func before_each() -> void:
	_state = load("res://test/unit/helpers/battle_state.gd").new()
	_state.snapshot()


func after_each() -> void:
	if _state:
		_state.restore()


func _pc(who: String, alive: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({
		"name": who, "max_hp": 200, "max_mp": 40,
		"attack": 40, "defense": 20, "magic": 10, "speed": 10,
	})
	add_child_autofree(c)
	if not alive:
		c.die()
	return c


func _foe() -> Combatant:
	var e := Combatant.new()
	e.initialize({
		"name": "Rat", "max_hp": 1, "max_mp": 0,
		"attack": 1, "defense": 0, "magic": 1, "speed": 1,
	})
	add_child_autofree(e)
	return e


func test_the_next_battle_keeps_permadeath_and_still_clears_poison() -> void:
	var erased := _pc("Bram", false)
	erased.add_status("permakilled")
	erased.add_status("poison", 5)
	var knocked_out := _pc("Milo", false)
	knocked_out.add_status("poison", 5)
	var standing := _pc("Theron", true)
	standing.add_status("poison", 5)
	assert_true(erased.has_status("permakilled"), "precondition: the marker is on before the next fight")
	assert_false(erased.is_alive, "precondition: they are down")

	BattleManager.start_battle([standing, erased, knocked_out], [_foe()])

	assert_true(erased.has_status("permakilled"),
		"the next battle must not forget a permadeath — without the marker, Raise treats them as a normal KO")
	assert_eq(int(erased.status_durations.get("permakilled", 0)), -1,
		"the marker is permanent; a 3-turn ailment duration would let it wear off once anything ticks them")
	assert_false(erased.has_status("poison"),
		"ordinary ailments still clear — the wipe exists so poison does not leak into the next fight")
	assert_false(erased.is_alive, "they are still dead")
	assert_eq(erased.current_hp, 0, "and still at 0 HP")
	erased.revive(erased.max_hp)
	assert_false(erased.is_alive, "revive() still refuses once the marker has survived the boundary")
	assert_eq(erased.current_hp, 0, "a refused revive must not restore HP")

	assert_false(knocked_out.has_status("permakilled"), "a normal KO must not grow a permadeath marker")
	assert_false(knocked_out.has_status("poison"), "and their poison still clears")
	knocked_out.revive(50)
	assert_true(knocked_out.is_alive, "a normal KO is still revivable after the boundary")
	assert_gt(knocked_out.current_hp, 0)

	assert_false(standing.has_status("poison"), "a living member's poison still clears too")
	assert_true(standing.is_alive)


func test_a_grind_battle_keeps_permadeath_and_still_clears_poison() -> void:
	var erased := _pc("Bram", false)
	erased.add_status("permakilled")
	erased.add_status("poison", 5)
	var standing := _pc("Theron", true)
	standing.attack = 500
	standing.max_hp = 99999
	standing.current_hp = standing.max_hp
	var resolver = ResolverScript.new()
	resolver.resolve_battle([standing, erased], [_foe()])
	assert_true(erased.has_status("permakilled"),
		"autogrind reuses the same party objects, so its battle start must keep the marker too")
	assert_eq(int(erased.status_durations.get("permakilled", 0)), -1,
		"the grind's copy of the marker is permanent, same as live")
	assert_false(erased.has_status("poison"), "poison still does not follow the party into the next grind fight")
	assert_false(erased.is_alive)
	erased.revive(erased.max_hp)
	assert_false(erased.is_alive, "a grind that kept the marker must still refuse the revive")
