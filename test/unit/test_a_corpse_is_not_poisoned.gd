extends GutTest

## ⛔ THE LIVE ENGINE AFFLICTS THE DEAD AND THE GRIND REFUSES TO. The status apply runs AFTER the
## damage, and `_apply_ability_status` never checks `is_alive` — so a blow that KILLS also poisons,
## blinds or stuns the corpse, and the battle log announces it.
##
## Found by running cowir-autogrind's twin-path shape (11799) in the REVERSE direction — everyone
## checked "live fixed it, the grind did not", and nobody checked the other way. The grind's
## `_maybe_inflict_status` opens with `if target == null or not target.is_alive: return` and has had
## an arm for it since 2026-09-16; live has no such guard and never did. I collapsed the two copies
## of that block this morning and carried the omission across faithfully.
##
## ⚠️ IT IS NOT COSMETIC, because revival exists. Anima Reddita (Cleric, starter) and Phoenix Down
## bring an ally back — and they come back still carrying whatever the killing blow inflicted, its
## duration untouched by the turns they spent dead.
##
## `doom` is the one that was already safe: `_inflict_doom` checks `is_alive`, added the same day it
## became reachable. That is the shape the rest of them need.

const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
const BM_PATH := "res://src/battle/BattleManager.gd"

var _saved_party: Array
var _saved_enemies: Array
var _saved_persist: bool


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	AutobattleSystem._test_disable_persistence = true
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	seed(20260916)


func after_each() -> void:
	AutobattleSystem._test_disable_persistence = _saved_persist
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _combatant(name: String, hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.max_hp = hp
	c.current_hp = hp
	c.attack = 200
	c.magic = 200
	c.defense = 0
	c.is_alive = true
	return c


## Certain poison on a blow big enough to kill the fixture outright.
func _lethal_poison(type: String) -> Dictionary:
	return {"type": type, "effect": "poison", "effect_chance": 1.0, "duration": 3,
		"damage_multiplier": 20.0, "power": 20.0}


func _kill_with(type: String) -> Combatant:
	var caster := _combatant("Mira", 9999)
	var victim := _combatant("Goblin", 10)
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.enemy_party.assign([victim] as Array[Combatant])
	if type == "magic":
		BattleManager._execute_magic_ability(caster, _lethal_poison(type), [victim])
	else:
		BattleManager._execute_physical_ability(caster, _lethal_poison(type), [victim])
	return victim


func test_a_killing_blow_does_not_also_poison_the_corpse() -> void:
	for type in ["physical", "magic"]:
		var victim := _kill_with(type)
		assert_false(victim.is_alive, "CONTROL: %s — the blow really did kill, or this arm is about nothing" % type)
		assert_false(victim.has_status("poison"),
			"%s: the dead are not afflicted — a revived ally must not come back carrying the blow that killed them" % type)


func test_a_survivor_is_still_afflicted() -> void:
	## Anti-vacuity: the guard must gate on DEATH, not disable the status apply.
	var caster := _combatant("Mira", 9999)
	var tank := _combatant("Goblin", 999999)
	BattleManager.player_party.assign([caster] as Array[Combatant])
	BattleManager.enemy_party.assign([tank] as Array[Combatant])
	BattleManager._execute_physical_ability(caster, _lethal_poison("physical"), [tank])
	assert_true(tank.is_alive, "CONTROL: this one survives the hit")
	assert_true(tank.has_status("poison"), "and is still poisoned by it")


func test_the_grind_already_refused_and_still_does() -> void:
	## The engine that was right. Pinned so the parity closes in the direction it actually needs to.
	var resolver = ResolverScript.new()
	var caster := _combatant("Mira", 9999)
	var corpse := _combatant("Goblin", 10)
	corpse.is_alive = false
	resolver._maybe_inflict_status(caster, corpse, _lethal_poison("physical"), "probe")
	assert_eq(corpse.status_effects.size(), 0, "the grind has always refused the dead")


func test_both_engines_state_the_rule_in_their_own_source() -> void:
	## The behavioural arms prove today; this says the rule is written where the next editor of either
	## engine will meet it, since the two have drifted on exactly this once already.
	var live: String = GdSourceHelper.code_of(BM_PATH)
	var at: int = live.find("func _apply_ability_status(")
	assert_gt(at, -1, "CONTROL: the live owner survives stripping")
	var nxt: int = live.find("\nfunc ", at + 1)
	assert_true(live.substr(at, nxt - at).contains("is_alive"),
		"live's status owner must refuse the dead, as the grind's does")
	var grind: String = GdSourceHelper.code_of("res://src/autogrind/HeadlessBattleResolver.gd")
	var g_at: int = grind.find("func _maybe_inflict_status(")
	assert_gt(g_at, -1, "CONTROL: the grind's owner survives stripping")
	var g_nxt: int = grind.find("\nfunc ", g_at + 1)
	assert_true(grind.substr(g_at, g_nxt - g_at).contains("not target.is_alive"),
		"and the grind's guard stays, or the parity closed the wrong way")
