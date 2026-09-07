extends GutTest

## Mini battle fuzz (2026-07-09): 20 seeded randomized battles through
## HeadlessBattleResolver every suite run — the in-suite sibling of
## tools/battle_fuzz.gd (which ran 2000 clean). Pins the engine invariants
## the big fuzzer checks: battles terminate in sane round counts, nobody
## ends alive at 0 HP or below 0 HP, and every battle produces a verdict.
## Fixed seed => deterministic; a failure here replays exactly.

const HBR := preload("res://src/autogrind/HeadlessBattleResolver.gd")
const SEED := 20260709
const BATTLES := 20
const JOBS := ["fighter", "cleric", "mage", "rogue", "bard"]


func test_mini_fuzz_invariants() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var pools: Array = EncounterSystem.enemy_pools.keys()
	assert_gt(pools.size(), 5, "sanity: encounter pools loaded")
	var verdicts := 0
	for i in range(BATTLES):
		var party := _random_party(rng)
		var enemies := _random_enemies(rng, pools)
		if enemies.is_empty():
			continue
		var resolver = HBR.new()
		var result: Dictionary = resolver.resolve_battle(party, enemies)
		verdicts += 1
		var rounds := int(result.get("rounds", -1))
		assert_true(rounds > 0 and rounds <= 500,
			"battle %d (seed %d): rounds=%d out of sane range" % [i, SEED, rounds])
		for c in party + enemies:
			assert_true(c.current_hp >= 0,
				"battle %d: %s ended at negative HP %d" % [i, c.combatant_name, c.current_hp])
			assert_false(c.is_alive and c.current_hp == 0,
				"battle %d: %s alive at 0 HP" % [i, c.combatant_name])
	assert_gt(verdicts, 15, "sanity: most battles actually ran")


func _random_party(rng: RandomNumberGenerator) -> Array:
	var party := []
	for i in range(rng.randi_range(1, 5)):
		var c := Combatant.new()
		add_child_autofree(c)
		var lvl := rng.randi_range(1, 25)
		c.initialize({
			"name": "Fuzz%d" % i,
			"max_hp": 80 + lvl * 12, "max_mp": 30 + lvl * 4,
			"attack": 10 + lvl * 2, "defense": 6 + lvl,
			"magic": 8 + lvl * 2, "speed": 8 + rng.randi_range(0, lvl),
		})
		c.job_level = lvl
		JobSystem.assign_job(c, JOBS[rng.randi_range(0, JOBS.size() - 1)])
		c.current_ap = rng.randi_range(0, 4)
		party.append(c)
	return party


func _random_enemies(rng: RandomNumberGenerator, pools: Array) -> Array:
	var pool: Array = EncounterSystem.enemy_pools.get(pools[rng.randi_range(0, pools.size() - 1)], [])
	if pool.is_empty():
		return []
	var enemies := []
	for i in range(rng.randi_range(1, 4)):
		var eid: String = str(pool[rng.randi_range(0, pool.size() - 1)])
		var c := Combatant.new()
		add_child_autofree(c)
		c.initialize(EncounterSystem._create_enemy_data(eid))
		c.set_meta("monster_type", eid)
		enemies.append(c)
	return enemies
