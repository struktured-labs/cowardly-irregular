extends GutTest

## ⛔ NOTHING PINNED THIS, AND A MERGE DECIDED IT. `.357` folded two branches that both rewrote the
## grind resolver's magic arm — the hit loop (cowir-autogrind's `hits`) and the status roll
## (cowir-battle's `effect_chance`). cowir-main resolved it by hand, correctly: the loop runs, then the
## status is rolled ONCE. Had the roll landed INSIDE the loop, both branches' guards would still have
## passed — the rate arm uses single-hit abilities and the hit arm never looks at statuses.
##
## The difference is not cosmetic. A 3-hit ability authored at 0.3:
##     rolled once per target   0.300 — what the live engine does
##     rolled once per hit      0.657 — 1 - (1-0.3)^3, more than double
##
## Five shipped abilities author `hits` and all five are monster abilities (gold_scatter,
## recursive_strike, repetitive_strike, temporal_strike, thread_slash), so the difference lands on the
## PARTY. This arm pins the property in both engines, in behaviour, so the next merge cannot quietly
## choose the other one.

const ResolverScript = preload("res://src/autogrind/HeadlessBattleResolver.gd")
## 600 casts: the two candidate rates (0.30 and 0.657) are 20 binomial sigma apart, so the band can be
## wide enough never to flake and still never admit the wrong one.
const CASTS := 600
const BAND := 0.12
const AUTHORED := 0.3
const HITS := 3
## 1 - (1 - 0.3)^3 — what per-hit rolling would produce. Named so the arm can exclude it explicitly.
const PER_HIT_RATE := 0.657

var _saved_persist: bool
var _saved_party: Array
var _saved_enemies: Array


func before_each() -> void:
	_saved_persist = AutobattleSystem._test_disable_persistence
	_saved_party = BattleManager.player_party.duplicate()
	_saved_enemies = BattleManager.enemy_party.duplicate()
	AutobattleSystem._test_disable_persistence = true
	seed(20260916)


func after_each() -> void:
	JobSystem.abilities.erase(PROBE_ID)
	AutobattleSystem._test_disable_persistence = _saved_persist
	BattleManager.player_party.assign(_alive(_saved_party))
	BattleManager.enemy_party.assign(_alive(_saved_enemies))


func _alive(saved: Array) -> Array:
	var out: Array = []
	for c in saved:
		if is_instance_valid(c):
			out.append(c)
	return out


func _combatant(name: String) -> Combatant:
	var c := Combatant.new()
	autofree(c)
	c.combatant_name = name
	c.max_hp = 999999
	c.current_hp = 999999
	c.attack = 60
	c.magic = 60
	c.defense = 5
	c.is_alive = true
	return c


## A 3-hit ability that inflicts poison 30% of the time. Fabricated rather than shipped: no ability
## authors BOTH keys today, which is exactly why nothing caught the interaction.
func _multi_hit_ability(type: String) -> Dictionary:
	return {"type": type, "hits": HITS, "effect": "poison", "effect_chance": AUTHORED,
		"duration": 3, "damage_multiplier": 0.2, "power": 0.2}


func test_the_two_candidate_rates_are_far_apart_enough_to_tell_apart() -> void:
	## CONTROL for the arms below: if per-hit and per-target rolling produced similar rates, a passing
	## measurement would prove nothing. They differ by more than twice the band.
	var per_hit: float = 1.0 - pow(1.0 - AUTHORED, HITS)
	assert_almost_eq(per_hit, PER_HIT_RATE, 0.01, "per-hit rolling would land at %.3f" % per_hit)
	assert_gt(absf(per_hit - AUTHORED), BAND * 2.0,
		"the wrong behaviour must be outside the band, or these arms cannot see it")


## ⚠️ Drives the WHOLE resolver arm — loop and roll together — because that is the only thing that can
## tell the two placements apart. Calling `_maybe_inflict_status` directly would be tautological: one
## call is one roll whatever the loop does. No shipped ability authors both `hits` and `effect_chance`,
## which is exactly why nothing caught this, so the fixture is registered in JobSystem for the test and
## removed after.
const PROBE_ID := "zzz_multi_hit_probe"

func _grind_rate(type: String) -> float:
	JobSystem.abilities[PROBE_ID] = _multi_hit_ability(type)
	var resolver = ResolverScript.new()
	var caster := _combatant("Mira")
	var landed: int = 0
	for i in CASTS:
		var victim := _combatant("Goblin")
		caster.current_mp = caster.max_mp
		resolver._resolve_ability(caster, PROBE_ID, [victim])
		if victim.has_status("poison"):
			landed += 1
		victim.free()
	JobSystem.abilities.erase(PROBE_ID)
	return float(landed) / float(CASTS)


func test_the_grind_rolls_the_authored_chance_not_one_per_hit() -> void:
	for type in ["magic", "physical"]:
		var rate: float = _grind_rate(type)
		assert_almost_eq(rate, AUTHORED, BAND, "%s: the grind rolled %.3f, authored %.2f" % [type, rate, AUTHORED])
		assert_gt(absf(rate - PER_HIT_RATE), BAND, "%s: and it is not the per-hit rate %.3f" % [type, PER_HIT_RATE])


func test_the_live_engine_rolls_it_once_too() -> void:
	## Behavioural on the live executor, because this is the behaviour the grind is mirroring — if the
	## anchor ever moves, the grind's "parity" would be parity with something else.
	var caster := _combatant("Mira")
	var ability: Dictionary = _multi_hit_ability("physical")
	var hits: int = 0
	for i in CASTS:
		var victim := _combatant("Goblin")
		BattleManager.player_party.assign([caster] as Array[Combatant])
		BattleManager.enemy_party.assign([victim] as Array[Combatant])
		BattleManager._execute_physical_ability(caster, ability, [victim])
		if victim.has_status("poison"):
			hits += 1
		victim.free()
	var rate: float = float(hits) / float(CASTS)
	assert_almost_eq(rate, AUTHORED, BAND, "live rolled %.3f, authored %.2f" % [rate, AUTHORED])
	assert_gt(absf(rate - PER_HIT_RATE), BAND, "and it is not the per-hit rate %.3f" % PER_HIT_RATE)


func test_neither_engine_rolls_inside_its_hit_loop() -> void:
	## The placement itself, in both files: the roll must not sit inside the loop that repeats the
	## damage. A behavioural arm can only see the rate; this says where the line is, which is what a
	## merge actually chooses between.
	var live: String = GdSourceHelper.code_of("res://src/battle/BattleManager.gd")
	var live_at: int = live.find("for hit_idx in range(hits):")
	assert_gt(live_at, -1, "CONTROL: the live hit loop survives stripping")
	var live_loop: String = live.substr(live_at, 400)
	## ⚠️ RE-POINTED 2026-09-16 AND IT WAS GREEN-AND-VACUOUS FOR ONE COMMIT. This read
	## `contains("effect_chance")`, and the day the two copies of the status block collapsed into
	## `_apply_ability_status` the literal left the executor entirely — so the arm passed by absence
	## rather than by placement. The roll is now named by its CALL, which is what sits in or out of
	## the loop. Anti-vacuity: the call must exist in the executor at all.
	var live_exec_at: int = live.find("func _execute_physical_ability(")
	var live_exec_end: int = live.find("\nfunc ", live_exec_at + 1)
	var live_exec: String = live.substr(live_exec_at, live_exec_end - live_exec_at)
	assert_true(live_exec.contains("_apply_ability_status(caster, target, ability)"),
		"CONTROL: the physical executor rolls the status through the one owner, or this arm is about nothing")
	assert_false(live_loop.contains("_apply_ability_status"),
		"the live engine must not roll the status inside its hit loop")
	var grind: String = GdSourceHelper.code_of("res://src/autogrind/HeadlessBattleResolver.gd")
	var offenders: Array = []
	for at in [grind.find('"magic":'), grind.find('"physical":')]:
		if at < 0:
			continue
		var loop_at: int = grind.find("for _h in hits:", at)
		if loop_at < 0:
			continue
		var log_at: int = grind.find("_log(", loop_at)
		var loop_body: String = grind.substr(loop_at, maxi(log_at - loop_at, 0)) if log_at > loop_at else grind.substr(loop_at, 300)
		if loop_body.contains("_maybe_inflict_status"):
			offenders.append(grind.substr(at, 12))
	assert_eq(offenders.size(), 0, "the grind must roll the status after its hit loop, not inside it: " + str(offenders))


const GdSourceHelper = preload("res://test/unit/helpers/gd_source.gd")
