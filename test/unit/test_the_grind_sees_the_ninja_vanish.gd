extends GutTest

## The Ninja's two hiding moves did nothing in a grind, and the presets that cast them are mine.
##
## `vanish` (12 MP) and `shadow_step` (8 MP) were APPLIED by the headless resolver and then read by
## nobody — the same shape blind had before .301. ninja_defensive spends 12 MP on vanish every time
## it drops below 35% HP; ninja_balanced and ninja_aggressive spend 8 on shadow_step whenever it
## lapses. In autogrind all of that bought a turn of nothing, which is worse than attacking.
##
## Live semantics, mirrored rather than invented:
##   invisible / shadow_step on the TARGET   the swing MISSES and the status falls off — "the swing
##                                           reveals them" (BattleManager._target_dodges_physical)
##   shadow_step on the ATTACKER             a guaranteed crit (_calculate_crit_chance returns 1.0)
##
## Measured, not asserted: rates over samples, with a control that the sample can tell hit from miss.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const SWINGS := 200


func _fighter(cname: String, speed: int = 12) -> Combatant:
	var c := Combatant.new()
	c.initialize({"name": cname, "max_hp": 99999, "max_mp": 50,
		"attack": 100, "defense": 40, "magic": 40, "speed": speed})
	add_child_autofree(c)
	return c


## ⚠️ HeadlessBattleResolver is RefCounted, NOT a Node. The first version called
## add_child_autofree() on it, which errors — so this helper aborted and returned the TYPE DEFAULT,
## null. _misses() then aborted too and returned 0, and "0 misses in 200 swings" read as a clean
## measurement: assert_lt(0, 70) passed. Only the control below it — "and some must miss" — fired.
## That control is why the bug took one run instead of an afternoon.
func _resolver() -> HeadlessBattleResolver:
	var r: HeadlessBattleResolver = RESOLVER.new()
	autofree(r)
	return r


## Swings where the target survives to be swung at again; returns the miss count.
func _misses(r: HeadlessBattleResolver, attacker: Combatant, target: Combatant, n: int) -> int:
	var missed: int = 0
	for i in range(n):
		target.current_hp = target.max_hp
		if r._resolve_attack(attacker, target) <= 0:
			missed += 1
	return missed


func test_a_clear_swing_mostly_lands_so_the_sample_can_tell() -> void:
	## CONTROL for everything below. If swings missed anyway, "the hidden target was missed" would
	## be agreeing with a story rather than measuring one.
	var r: HeadlessBattleResolver = _resolver()
	var misses := _misses(r, _fighter("Clear Attacker"), _fighter("Clear Target"), SWINGS)
	assert_lt(misses, int(SWINGS * 0.35),
		"CONTROL: with nobody hiding, most swings must LAND (%d misses of %d)" % [misses, SWINGS])
	assert_gt(misses, 0,
		"CONTROL: and some must miss, or the resolver is not rolling at all and every arm below is "
		+ "reading a constant")


func test_a_vanished_target_is_missed_and_is_then_revealed() -> void:
	## One swing, not a rate: live does not ROLL against invisible, it misses outright. And the
	## status falls off on the attempt, so the SECOND swing must land — a rule that stayed invisible
	## forever would make a grind unwinnable rather than merely wrong.
	var r: HeadlessBattleResolver = _resolver()
	var attacker := _fighter("Seeker")
	var target := _fighter("Vanished")
	target.add_status("invisible", 2)
	assert_eq(r._resolve_attack(attacker, target), 0, "the swing must find nothing")
	assert_false(target.has_status("invisible"),
		"and the swing must REVEAL them — the status falls off on the attempt, exactly as live does")
	target.current_hp = target.max_hp
	var second: int = 0
	for i in range(40):
		target.current_hp = target.max_hp
		if r._resolve_attack(attacker, target) > 0:
			second += 1
	assert_gt(second, 0, "once revealed, swings must be able to land again")


func test_a_shadow_stepped_target_is_missed_the_same_way() -> void:
	var r: HeadlessBattleResolver = _resolver()
	var attacker := _fighter("Seeker Two")
	var target := _fighter("Stepped")
	target.add_status("shadow_step", 1)
	assert_eq(r._resolve_attack(attacker, target), 0, "the swing must miss a shadow-stepped target")
	assert_false(target.has_status("shadow_step"), "and consume the step")


func test_shadow_step_on_the_ATTACKER_buys_the_crit_it_promises() -> void:
	## The half the Ninja actually pays for: "step into the shadows so the next swing crits". Same
	## combatant measured twice with the status added between, so the arms cannot differ because the
	## fixtures differ.
	var r: HeadlessBattleResolver = _resolver()
	var attacker := _fighter("Crit Ninja", 20)
	var target := _fighter("Crit Dummy")
	var plain: int = 0
	for i in range(SWINGS):
		target.current_hp = target.max_hp
		plain += r._resolve_attack(attacker, target)
	attacker.add_status("shadow_step", 99)
	var stepped: int = 0
	for i in range(SWINGS):
		target.current_hp = target.max_hp
		stepped += r._resolve_attack(attacker, target)
	assert_gt(plain, 0, "CONTROL: the plain sample dealt damage at all (%d)" % plain)
	gut.p("mean damage  plain %.1f   shadow_step %.1f" % [float(plain) / SWINGS, float(stepped) / SWINGS])
	assert_gt(float(stepped), float(plain) * 1.15,
		"a guaranteed crit must show up as materially more damage over %d swings — plain %d, "
		% [SWINGS, plain] + "stepped %d. Loose bound on purpose: pinning the ratio would freeze the "
		% stepped + "RNG stream and red on any unrelated change to it")
