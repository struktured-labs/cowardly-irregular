extends GutTest

## temporal_strike (magic, hits: 2) landed ONCE live: only _execute_physical_ability read `hits`, while
## the grind looped both arms and so hit harder than live. struktured 2026-10-06: "do them all" -> wire it.
## Each hit is its own take, popup and death check, and the preview quotes both.

var _saved: Dictionary = {}
var _popups: Array = []


func before_each() -> void:
	_saved = {"pp": BattleManager.player_party.duplicate(), "ep": BattleManager.enemy_party.duplicate()}
	_popups = []
	BattleManager.damage_dealt.connect(_on_damage)


func after_each() -> void:
	BattleManager.damage_dealt.disconnect(_on_damage)
	BattleManager.player_party.assign(_saved["pp"].filter(func(x): return is_instance_valid(x)))
	BattleManager.enemy_party.assign(_saved["ep"].filter(func(x): return is_instance_valid(x)))


func _on_damage(t, amount, _c = false, _e = "", _m = 1.0) -> void:
	_popups.append(int(amount))


func _c(n: String, hp: int) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": n, "max_hp": hp, "max_mp": 999, "attack": 10, "defense": 0, "magic": 80, "speed": 10})
	c.magic_defense = 0
	add_child_autofree(c)
	return c


func test_temporal_strike_is_a_two_hit_spell() -> void:
	var ab: Dictionary = JobSystem.get_ability("temporal_strike")
	assert_eq(str(ab.get("type", "")), "magic", "CONTROL: a magic ability")
	assert_eq(int(ab.get("hits", 1)), 2, "CONTROL: authored to hit twice")


func test_it_lands_two_hits_and_two_popups() -> void:
	var caster := _c("Time Mage", 500)
	var foe := _c("Dummy", 10000000)
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.enemy_party.assign([foe] as Array[Combatant])
	var before := foe.current_hp
	BattleManager._execute_magic_ability(caster, JobSystem.get_ability("temporal_strike"), [foe])
	assert_eq(_popups.size(), 2, "two hits, two popups")
	assert_eq(before - foe.current_hp, _popups[0] + _popups[1], "both hits land, and the popups add up to the HP lost")


func test_a_kill_on_the_first_hit_stops_the_second() -> void:
	var caster := _c("Time Mage", 500)
	var foe := _c("Gnat", 1)
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.enemy_party.assign([foe] as Array[Combatant])
	BattleManager._execute_magic_ability(caster, JobSystem.get_ability("temporal_strike"), [foe])
	assert_eq(_popups.size(), 1, "the second hit does not land on a corpse")


func test_the_preview_quotes_both_hits() -> void:
	var caster := _c("Time Mage", 500)
	var foe := _c("Dummy", 10000000)
	var ab: Dictionary = JobSystem.get_ability("temporal_strike")
	var two: int = BattleManager.estimate_ability_damage(caster, foe, ab)
	var one_ab: Dictionary = ab.duplicate()
	one_ab["hits"] = 1
	var one: int = BattleManager.estimate_ability_damage(caster, foe, one_ab)
	assert_eq(two, one * 2, "the row quotes two hits: %d vs one hit %d" % [two, one])
