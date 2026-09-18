extends GutTest

## The grind ignored silence entirely. HeadlessBattleResolver never called
## JobSystem.can_use_ability and its only mention of "silence" was the random-debuff pool, so a
## silenced character kept casting for a whole grind while live refuses at BattleManager:4669.
##
## Declared as a gap when the ability_silence key was fixed (null_field landed an unread key, so
## nothing was silenced and the divergence could not be observed). Closing it now that it can.
##
## Mirrors live exactly, including the two things that are easy to get wrong in the player's favour:
##   the TURN IS CONSUMED — live logs and returns, it does not fall back to an attack
##   NO MP IS SPENT     — live's gate sits above its own spend
## and it is ability-scoped: a basic attack takes _resolve_attack and is not gated, as in live.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")

var _res


func before_each() -> void:
	_res = ResolverScript.new()
	for n in ["AutogrindSystem", "AutobattleSystem"]:
		var sys: Node = get_node_or_null("/root/" + n)
		if sys != null and "_test_disable_persistence" in sys:
			sys._test_disable_persistence = true


func _combatant(nm: String) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": nm, "max_hp": 200, "max_mp": 99,
		"attack": 20, "defense": 5, "magic": 20, "speed": 10})
	add_child_autofree(c)
	c.current_mp = c.max_mp
	return c


func _damaging_ability() -> String:
	## Derived, not named: an id this file hardcodes can be renamed out from under it.
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("get_ability"):
		return ""
	for candidate in ["fire", "blizzard", "thunder"]:
		var ab: Dictionary = js.get_ability(candidate)
		if not ab.is_empty() and int(ab.get("mp_cost", 0)) > 0:
			return candidate
	return ""


func test_a_silenced_caster_does_nothing() -> void:
	var aid: String = _damaging_ability()
	if aid == "":
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _combatant("Mage")
	var target := _combatant("Victim")
	caster.add_status("silence", 2)
	var hp_before: int = target.current_hp
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._resolve_ability(caster, aid, [target])
	assert_eq(target.current_hp, hp_before, "a silenced caster's spell must not land in a grind")


func test_the_unsilenced_control_actually_casts() -> void:
	## Without this the arm above passes on any resolver that does nothing at all.
	var aid: String = _damaging_ability()
	if aid == "":
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _combatant("Mage")
	var target := _combatant("Victim")
	var hp_before: int = target.current_hp
	_res._player_party = [caster]
	_res._enemy_party = [target]
	_res._resolve_ability(caster, aid, [target])
	gut.p("    unsilenced cast dealt %d" % (hp_before - target.current_hp))
	assert_lt(target.current_hp, hp_before, "CONTROL: the same cast must land when NOT silenced")


func test_no_mp_is_spent_on_a_silenced_cast() -> void:
	## Live's gate sits ABOVE its own spend, so a silenced cast costs nothing. Charging for it would
	## be a quiet second penalty the player never sees.
	var aid: String = _damaging_ability()
	if aid == "":
		pass_test("JobSystem autoload unavailable")
		return
	var caster := _combatant("Mage")
	caster.add_status("silence", 2)
	var mp_before: int = caster.current_mp
	_res._player_party = [caster]
	_res._enemy_party = [_combatant("Victim")]
	_res._resolve_ability(caster, aid, [_combatant("Victim")])
	assert_eq(caster.current_mp, mp_before, "a refused cast must not charge MP, as in live")


func test_silence_does_not_block_a_basic_attack() -> void:
	## Ability-scoped, like live's: JobSystem.can_use_ability gates ABILITIES. A silenced fighter
	## still swings, and gating the attack would be a far bigger nerf than the status describes.
	var attacker := _combatant("Fighter")
	var target := _combatant("Victim")
	attacker.add_status("silence", 2)
	var hp_before: int = target.current_hp
	_res._player_party = [attacker]
	_res._enemy_party = [target]
	_res._resolve_attack(attacker, target)
	assert_lt(target.current_hp, hp_before, "silence must not stop a basic attack")


func test_live_still_gates_the_same_way() -> void:
	## This file's premise is that live REFUSES. If live stops gating, the grind is now the stricter
	## engine and this guard defends a divergence rather than closing one.
	var js: Node = get_node_or_null("/root/JobSystem")
	if js == null or not js.has_method("can_use_ability"):
		pass_test("JobSystem autoload unavailable")
		return
	var aid: String = _damaging_ability()
	var c := _combatant("Mage")
	c.learned_abilities.append(aid)
	assert_true(js.can_use_ability(c, aid), "CONTROL: an unsilenced caster is allowed")
	c.add_status("silence", 2)
	assert_false(js.can_use_ability(c, aid), "live must still refuse a silenced caster")
