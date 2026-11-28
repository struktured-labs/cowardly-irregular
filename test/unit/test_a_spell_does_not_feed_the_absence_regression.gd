extends GutTest

## The Absence (W6) "heals 30% of physical damage received"; struktured 2026-11-28: physical only, every spell bypasses.
## Both engines' magic executors called _maybe_heal_from_damage with the spell's element, so only holy bypassed and a
## Fire fed it. Each arm strikes the_absence and an identical twin on one seed: a heal shows as the_absence ending higher.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res
var _saved_party: Array
var _saved_enemies: Array
var _saved_persist: bool
var _inherit_was: bool = true


func before_each() -> void:
	_res = ResolverScript.new()
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	_inherit_was = DamageRules.abilities_inherit_swing_crit
	DamageRules.abilities_inherit_swing_crit = false


func after_each() -> void:
	randomize()
	DamageRules.abilities_inherit_swing_crit = _inherit_was
	AutobattleSystem._test_disable_persistence = _saved_persist
	BattleManager.player_party.assign(_saved_party.filter(func(c): return is_instance_valid(c)))
	BattleManager.enemy_party.assign(_saved_enemies.filter(func(c): return is_instance_valid(c)))


func _unit(name: String, absence: bool) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": name, "max_hp": 5000, "max_mp": 500,
		"attack": 80, "defense": 0, "magic": 80, "speed": 10, "magic_defense": 0})
	add_child_autofree(c)
	if absence:
		c.set_meta("monster_type", "the_absence")
	return c


## [the_absence's HP, its twin's HP] after the same ability on the same seed. live: BattleManager's executor, else the grind's.
func _pair(ability_id: String, live: bool) -> Array:
	var caster := _unit("Caster", false)
	var fed := _unit("The Absence", true)
	var twin := _unit("Twin", false)
	for t in [fed, twin]:
		caster.current_mp = caster.max_mp
		seed(20261128)
		if live:
			BattleManager.player_party.assign([caster] as Array[Combatant])
			BattleManager.enemy_party.assign([t] as Array[Combatant])
			var ability: Dictionary = JobSystem.get_ability(ability_id)
			if str(ability.get("type", "")) == "magic":
				BattleManager._execute_magic_ability(caster, ability, [t])
			else:
				BattleManager._execute_physical_ability(caster, ability, [t])
		else:
			_res._player_party = [caster]
			_res._enemy_party = [t]
			_res._resolve_ability(caster, ability_id, [t])
	return [fed.current_hp, twin.current_hp]


func test_a_physical_ability_still_feeds_it_in_both_engines() -> void:
	for live in [true, false]:
		var hp: Array = _pair("power_strike", live)
		assert_lt(int(hp[1]), 5000, "CONTROL (live=%s): the twin took the hit" % live)
		assert_gt(int(hp[0]), int(hp[1]), "CONTROL (live=%s): a physical hit still feeds the_absence" % live)


func test_a_spell_does_not_feed_it_in_either_engine() -> void:
	for live in [true, false]:
		var hp: Array = _pair("fire", live)
		assert_lt(int(hp[1]), 5000, "CONTROL (live=%s): the twin took the spell" % live)
		assert_eq(int(hp[0]), int(hp[1]), "live=%s: a Fire must not feed the_absence: it heals from physical damage only" % live)
