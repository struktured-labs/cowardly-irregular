extends GutTest

## Layer-six coverage guard (cowir-story msg 2957, cowir-battle's criterion msg 2965).
##
## Autogrind joins TWO data sources that neither lane owns jointly:
##   • the DRAW pool  — BattleEnemySpawner.MONSTER_TYPES  (cowir-battle's file)
##   • the REWARD table — data/monsters.json               (shared content data)
## AutogrindController._generate_scaled_enemies picks ids from the first;
## HeadlessBattleResolver._build_results looks those ids up in the second for
## exp_reward / gold_reward.
##
## This is NOT the precedence hazard the other lanes found — the two sources
## don't compete for the same answer, so nothing "wins." They're complementary
## sources joined by a key, and the failure mode is referential: a roster id with
## no reward row doesn't error, it silently falls through to defaults
## (exp_reward 25, gold derived from enemy stats). The grind keeps running and
## quietly pays the wrong amount for that species.
##
## That lands on the no-hidden-yield-tax pillar (struktured, 2026-07-01): autogrind
## must pay authored rewards, and a species paying stat-derived defaults because
## its row is missing is exactly the silent divergence that ruling forbids.
##
## Why this guard is legitimate rather than a graveyard (cowir-battle's test,
## msg 2965 — "a check whose CORRECT case requires a suppression flag is not a
## check"): it passes 11/11 clean TODAY with no allowlist and no opt-out key. It
## can only go red by someone genuinely adding a roster entry without reward data
## — a cross-lane mistake neither lane's own tests would catch, since
## BattleEnemySpawner and monsters.json are edited by different lanes.

const MONSTERS_JSON := "res://data/monsters.json"


func _load_monster_db() -> Dictionary:
	# Disk-direct (cowir-ai msg 2942): no cache layer, no staleness question.
	var raw: String = FileAccess.get_file_as_string(MONSTERS_JSON)
	assert_false(raw.is_empty(), "setup: data/monsters.json must be readable")
	var parsed = JSON.parse_string(raw)
	assert_true(parsed is Dictionary, "setup: monsters.json root must be a Dictionary")
	var db: Dictionary = parsed
	# Tolerate both shapes — a bare id→row map or a {"monsters": {...}} wrapper.
	if db.has("monsters") and db["monsters"] is Dictionary:
		db = db["monsters"]
	return db


func _roster_ids() -> Array:
	var ids: Array = []
	for m in BattleEnemySpawner.MONSTER_TYPES:
		var id: String = str(m.get("id", ""))
		if not id.is_empty():
			ids.append(id)
	return ids


func test_every_grind_roster_id_resolves_in_monsters_json() -> void:
	var db := _load_monster_db()
	var missing: Array = []
	for id in _roster_ids():
		if not db.has(id):
			missing.append(id)
	assert_eq(missing.size(), 0,
		"grind roster ids with no row in monsters.json: %s — HeadlessBattleResolver._build_results would silently pay DEFAULT rewards (exp 25 + stat-derived gold) for these species instead of authored ones. Add the row, or remove the id from BattleEnemySpawner.MONSTER_TYPES." % str(missing))


func test_every_grind_roster_id_has_authored_exp_reward() -> void:
	var db := _load_monster_db()
	var no_exp: Array = []
	for id in _roster_ids():
		if db.has(id) and not (db[id] as Dictionary).has("exp_reward"):
			no_exp.append(id)
	assert_eq(no_exp.size(), 0,
		"grind roster species missing authored exp_reward: %s — falls back to the hardcoded 25 in _build_results, so these pay a flat rate regardless of difficulty" % str(no_exp))


func test_every_grind_roster_id_has_authored_gold_reward() -> void:
	var db := _load_monster_db()
	var no_gold: Array = []
	for id in _roster_ids():
		if db.has(id) and not (db[id] as Dictionary).has("gold_reward"):
			no_gold.append(id)
	assert_eq(no_gold.size(), 0,
		"grind roster species missing authored gold_reward: %s — falls back to the stat-derived int(max_hp * 0.3 + defense), which drifts from whatever the designer intended" % str(no_gold))


func test_roster_is_non_empty() -> void:
	# Degenerate-case guard: an empty roster would make _generate_scaled_enemies
	# return [] every draw, which AutogrindController reads as full extermination
	# and stops the grind. A roster refactor that emptied the const would present
	# as "autogrind refuses to start" with no obvious cause.
	assert_gt(_roster_ids().size(), 0,
		"BattleEnemySpawner.MONSTER_TYPES must be non-empty — an empty roster reads as total extermination and silently stops every grind")


func test_reward_lookup_matches_the_resolver_source() -> void:
	# Pins the JOIN itself, not just the two sides. If HBR ever stops reading
	# monsters.json for rewards, the three coverage tests above would keep passing
	# while guarding nothing — they'd be verifying a table nobody reads.
	var src: String = FileAccess.get_file_as_string("res://src/autogrind/HeadlessBattleResolver.gd")
	assert_true(src.contains("monster_database"),
		"HeadlessBattleResolver must still source rewards from EncounterSystem.monster_database (monsters.json) — if the reward lookup moves, this coverage suite is verifying a table nobody reads and must be repointed")
	assert_true(src.contains("exp_reward") and src.contains("gold_reward"),
		"HeadlessBattleResolver must still read exp_reward/gold_reward by name — the coverage tests above assert on those exact keys")
