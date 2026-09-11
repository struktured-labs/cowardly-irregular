extends GutTest

## My blind-parity guard asserts the SOURCE reads `has_status("blind")`. That is the REGISTER.
## Nothing asserted the ARTIFACT — that a blinded attacker actually misses more in a grind.
##
## The distinction cost another lane a day: they measured `export_presets.cfg`, reported it as a
## player experience, and built two guards, a scene count, a budget argument and a ruling on top of
## a filter the shipping build does not use. "I measured the register and reported it as the
## artifact." My source assert is the same class — true, necessary, and not the thing a player meets.
##
## So this one runs the resolver's own attack path and counts misses.

const RESOLVER := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const N := 400

func _combatant(cname: String, spd: int = 10) -> Combatant:
	var c = Combatant.new()
	c.initialize({"name": cname, "max_hp": 100, "max_mp": 20, "attack": 15, "defense": 10, "magic": 5, "speed": spd})
	add_child_autofree(c)
	return c

## Swing N times and count the zeros. The target is healed each swing so it cannot die mid-sample
## and turn later swings into early returns — which would read as misses and inflate BOTH arms.
func _miss_rate(blinded: bool) -> float:
	var r = RESOLVER.new()
	add_child_autofree(r)
	var atk := _combatant("Swinger")
	var tgt := _combatant("Bag")
	if blinded:
		atk.add_status("blind", 99)
	seed(0x5EED)
	var misses: int = 0
	for i in N:
		tgt.current_hp = tgt.max_hp
		tgt.is_alive = true
		if r._resolve_attack(atk, tgt) == 0:
			misses += 1
	return float(misses) / float(N)

func test_a_blinded_attacker_actually_misses_more() -> void:
	## Equal speed, so the base rate is 0.10 and blind adds 0.40 — roughly 10% vs 50%.
	## Asserted as a RELATIONSHIP plus loose bounds, never an exact count: an exact number would
	## pin the RNG stream and red on any unrelated change to it.
	var clear := _miss_rate(false)
	var blind := _miss_rate(true)
	gut.p("  miss rate: clear %.3f · blinded %.3f (n=%d each)" % [clear, blind, N])
	assert_lt(clear, 0.25, "an unblinded attacker at equal speed should miss ~10%%, got %.3f" % clear)
	assert_gt(blind, 0.35, "a blinded attacker should miss far more; got %.3f" % blind)
	assert_gt(blind, clear * 2.0,
		"blind must move the miss rate substantially, not marginally: clear %.3f vs blinded %.3f" % [clear, blind])

func test_the_sample_can_distinguish_at_all() -> void:
	## CONTROL. If _resolve_attack always returned 0, or never did, both arms above would agree with
	## some story. Prove the measurement has both outcomes in it before trusting the comparison.
	var clear := _miss_rate(false)
	assert_gt(clear, 0.0, "CONTROL: some swings must MISS, or a miss cannot be detected")
	assert_lt(clear, 1.0, "CONTROL: some swings must LAND, or every result reads as a miss")

func test_the_status_is_what_moves_it_not_the_combatant() -> void:
	## Same combatant, measured twice — blind added between. Rules out the two arms differing
	## because the fixtures differ rather than because the status does anything.
	var r = RESOLVER.new()
	add_child_autofree(r)
	var atk := _combatant("Twice")
	var tgt := _combatant("Bag2")
	var before: int = 0
	var after: int = 0
	seed(0x5EED)
	for i in N:
		tgt.current_hp = tgt.max_hp
		tgt.is_alive = true
		if r._resolve_attack(atk, tgt) == 0:
			before += 1
	atk.add_status("blind", 99)
	seed(0x5EED)
	for i in N:
		tgt.current_hp = tgt.max_hp
		tgt.is_alive = true
		if r._resolve_attack(atk, tgt) == 0:
			after += 1
	gut.p("  same combatant: %d misses before blind, %d after (n=%d)" % [before, after, N])
	assert_gt(after, before * 2,
		"adding blind to the SAME combatant must raise its miss count: %d -> %d" % [before, after])
