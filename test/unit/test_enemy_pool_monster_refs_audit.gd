extends GutTest

## Data-integrity ratchet 2026-07-04: enemy_pools.json is hand-authored
## and high-churn (every new encounter area adds a pool). A typo'd
## monster id currently only surfaces at RUNTIME — EncounterSystem warns
## + falls back to slime when a player happens to hit that pool
## (test_encounter_system_unknown_enemy_warn covers that path). This
## adds the STATIC half CLAUDE.md's data-integrity section calls for:
## every monster referenced in every pool must resolve in monsters.json,
## caught at CI before it ships. Mirrors test_monster_data_integrity's
## drop/reward/ability resolution shape, for the pool→monster edge.


func test_every_pool_monster_resolves() -> void:
	var pools = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json"))
	var monsters = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	assert_true(pools is Dictionary and monsters is Dictionary, "both data files must parse")
	var dangling: Array = []
	for pool_id in pools:
		var entries = pools[pool_id]
		if not (entries is Array):
			continue
		for m in entries:
			# entries are bare ids today; tolerate a future {id, weight} shape
			var mid: String = str(m.get("id", "")) if m is Dictionary else str(m)
			if mid == "":
				continue
			# per-world variant convention: "<base>_<world>" falls back to "<base>"
			if monsters.has(mid):
				continue
			var base: String = mid.rsplit("_", true, 1)[0] if "_" in mid else mid
			if monsters.has(base):
				continue
			dangling.append("%s → %s" % [pool_id, mid])
	assert_eq(dangling.size(), 0,
		"enemy_pools.json monster ids that resolve NOWHERE in monsters.json (pool → id) — they spawn a slime fallback + runtime warn: %s" % str(dangling))


## Boss-only floors legitimately have empty pools (encounter_rate=0,
## encounter_enabled=false — see WhisperingCave floor 6). A genuinely
## empty NON-boss pool is still a bug (area can't spawn encounters).
const BOSS_ONLY_EMPTY_POOLS := {"cave_floor_6": true}


func test_no_unexpected_empty_pool() -> void:
	var pools = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json"))
	var empties: Array = []
	for pool_id in pools:
		var entries = pools[pool_id]
		if entries is Array and entries.is_empty() and not BOSS_ONLY_EMPTY_POOLS.has(pool_id):
			empties.append(pool_id)
	assert_eq(empties.size(), 0,
		"empty non-boss enemy pools (area can't spawn encounters): %s" % str(empties))
