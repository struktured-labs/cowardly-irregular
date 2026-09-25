extends GutTest

## A full-bank Advance spends 1 AP per swing and refunds the fifth, so five actions from +4
## end at 0. The refund was gated on still being alive. Dying ON that fifth swing — Reflect,
## a counter, recoil — had already charged the AP, and the refund never ran. A raise brings
## the character back at -1, and the next round is spent "paying down Advance" for an action
## the full-bank rule said was free. Dying earlier in the chain must NOT refund: those later
## swings never happened, and only the ones that did are paid for.

const BattleManagerScript = preload("res://src/battle/BattleManager.gd")

var _bm = null
var _banks: int = 0
var _landed: Array = []


func before_each() -> void:
	_bm = BattleManagerScript.new()
	_bm.turbo_mode = true
	add_child_autofree(_bm)
	_bm.damage_dealt.connect(func(target, _amount, _crit, _element, _mod): _landed.append(target))
	if GameState and "full_banks_unleashed" in GameState:
		_banks = int(GameState.full_banks_unleashed)


func after_each() -> void:
	randomize() # seed() is process-wide and GUT runs every file in one process
	if GameState and "full_banks_unleashed" in GameState:
		GameState.full_banks_unleashed = _banks


func _fighter(hp: int) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = "Mira"
	c.max_hp = 100
	c.current_hp = hp
	c.max_mp = 20
	c.current_mp = 20
	c.attack = 80
	c.defense = 40
	c.magic = 10
	c.speed = 10
	c.current_ap = 4
	c.is_alive = true
	return c


func _foe(cname: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = cname
	c.max_hp = 5000
	c.current_hp = 5000
	c.attack = 10
	c.defense = 10
	c.magic = 10
	c.speed = 8
	c.is_alive = true
	return c


func _swings(dummy: Combatant, mirror: Combatant, mirror_at: int) -> Array:
	var actions: Array = []
	for i in 5:
		actions.append({"type": "attack", "target": mirror if i == mirror_at else dummy})
	return actions


func _stage(hero: Combatant, dummy: Combatant, mirror: Combatant) -> void:
	var ally := _fighter(100)
	ally.combatant_name = "Bram"
	_bm.player_party.clear()
	_bm.enemy_party.clear()
	_bm.player_party.append(hero)
	_bm.player_party.append(ally)
	_bm.enemy_party.append(dummy)
	_bm.enemy_party.append(mirror)


## A basic attack misses at least 2% of the time, so one roll fails the hit-count precondition while the AP result is already right. Retry until the killing swing is the one that connected.
func _pattern(mirror_at: int, dummy_hits: int, hero_hits: int) -> Dictionary:
	for s in range(1, 48):
		seed(s)
		var hero := _fighter(1)
		var dummy := _foe("Dummy")
		var mirror := _foe("Mirror")
		mirror.add_status("reflect", 3)
		_stage(hero, dummy, mirror)
		_landed.clear()
		await _bm._execute_advance(hero, {
			"type": "advance",
			"combatant": hero,
			"actions": _swings(dummy, mirror, mirror_at),
			"full_bank": true,
		})
		if hero.is_alive:
			continue
		if _hits_on(dummy, _landed) != dummy_hits:
			continue
		if _hits_on(hero, _landed) != hero_hits:
			continue
		return {"hero": hero, "dummy": dummy, "landed": _landed.duplicate()}
	return {}


func _hits_on(who: Combatant, seen: Array) -> int:
	var n := 0
	for hit in seen:
		if hit == who:
			n += 1
	return n


func test_dying_on_the_free_fifth_does_not_keep_its_cost() -> void:
	var found: Dictionary = await _pattern(4, 4, 1)
	assert_false(found.is_empty(), "precondition: a seed must exist where Reflect on the fifth swing is the hit that KOs")
	var hero: Combatant = found["hero"]
	var landed: Array = found["landed"]
	assert_false(hero.is_alive, "precondition: Reflect on the fifth swing must KO the attacker")
	assert_eq(_hits_on(found["dummy"], landed), 4, "the first four swings land; the chain does not continue past the KO")
	assert_eq(_hits_on(hero, landed), 1, "the fifth swing bounces and is the one that kills")
	hero.revive(20)
	assert_true(hero.is_alive, "a raise brings them back")
	assert_eq(hero.current_ap, 0,
		"five swings from a full bank cost 4 AP even if the fifth kills you — revived at %d, which is a debt turn" % hero.current_ap)


func test_dying_before_the_fifth_does_not_refund_swings_that_never_happened() -> void:
	## CONTROL. The refund is for the fifth swing, not a consolation prize for dying mid-chain.
	## Two swings from +4 cost 2 AP and stop. A refund here would leave them at 3.
	var found: Dictionary = await _pattern(1, 1, 1)
	assert_false(found.is_empty(), "precondition: a seed must exist where Reflect on the second swing is the hit that KOs")
	var hero: Combatant = found["hero"]
	assert_false(hero.is_alive, "precondition: Reflect on the second swing must KO the attacker")
	assert_eq(_hits_on(found["dummy"], found["landed"]), 1, "only the swing before the KO lands — later actions must not play")
	assert_eq(hero.current_ap, 2, "two swings that happened cost 2 AP; the unplayed fifth is not refunded (got %d)" % hero.current_ap)
