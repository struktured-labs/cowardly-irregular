extends GutTest

## 16 of 24 masterites cannot be fought, and the guard that used to live here said otherwise. 2026-07-29.
##
## I added the four W3 masterites, noticed they had no encounter pool, added `masterite_steampunk` to
## enemy_pools.json, and wrote a test asserting every masterite belongs to a pool. All of that passed.
## None of it made a monster appear, because NOTHING READS THE MASTERITE POOLS:
##
##   set_enemy_pool_for_area()      0 production callers
##   "masterite_*" as a pool key    0 references in src/
##   EncounterSystem dynamic key    "miniboss_" + prefix, never "masterite_"
##
## The real spawn verbs are `monster_id` (a placed MasteriteEncounter), `boss_id` (a dungeon boss),
## and GameLoop.common_enemies. Measured against those:
##
##   medieval     4/4    four MasteriteEncounter placements, one per village — the intended pattern
##   suburban     1/4    warden only, as SuburbanUnderground's boss
##   steampunk    0/4    nothing
##   industrial   1/4    warden only
##   futuristic   1/4    arbiter only
##   abstract     1/4    curator only
##
## Each of the 16 has stats, a sprite sheet, and authored intro/defeat/fragment cutscenes that can
## never fire. Three separate guards certified them: data-integrity (drops/abilities resolve — true of
## an unreachable monster), sheet-coverage (idle loads — also true), and the pool check that used to
## be in this file. All three were honest and all three measured a layer that does not decide whether
## a player meets the monster.
##
## The floors below are a ratchet on a KNOWN GAP, not a claim that the gap is acceptable. Filling it
## means placing encounters across five worlds, which is an encounter-design call, not a data edit.

const SPAWN_VERBS := ["monster_id", "boss_id", "common_enemies"]

## Reachable count per world at the time of measurement. Floors, never targets.
const REACHABLE_FLOOR := {
	"medieval": 4, "suburban": 1, "steampunk": 0,
	"industrial": 1, "futuristic": 1, "abstract": 1,
}


func _gd_sources() -> Array[String]:
	var out: Array[String] = []
	var stack: Array[String] = ["res://src"]
	while not stack.is_empty():
		var dir_path: String = stack.pop_back()
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while name != "":
			var full := dir_path + "/" + name
			if d.current_is_dir():
				stack.append(full)
			elif name.ends_with(".gd"):
				out.append(full)
			name = d.get_next()
		d.list_dir_end()
	return out


## A monster is reachable when a spawn verb NAMES it on the same line. A mention is not a spawn.
func _reachable_masterites() -> Dictionary:
	var found: Dictionary = {}
	for path in _gd_sources():
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("masterite_"):
			continue
		for line in text.split("\n"):
			var verb_present := false
			for verb in SPAWN_VERBS:
				if line.contains(verb):
					verb_present = true
					break
			if not verb_present:
				continue
			for id in _masterite_ids():
				if line.contains(id):
					found[id] = path.get_file()
	return found


func _masterite_ids() -> Array:
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var ids: Array = []
	for id in mons:
		var e: Dictionary = mons[id]
		if bool(e.get("masterite", false)) or str(id).begins_with("masterite_"):
			ids.append(str(id))
	ids.sort()
	return ids


func _world_of(id: String) -> String:
	return id.rsplit("_", true, 1)[-1]


# ── the ratchet ─────────────────────────────────────────────────────

func test_no_world_loses_masterite_reachability() -> void:
	# Per-world floors rather than a single total: a total of 8 stays green if someone wires two
	# steampunk masterites and breaks two medieval ones, which is the swap the aggregate cannot see.
	var reachable: Dictionary = _reachable_masterites()
	var counts: Dictionary = {}
	for id in _masterite_ids():
		var w := _world_of(id)
		counts[w] = int(counts.get(w, 0)) + (1 if reachable.has(id) else 0)
	var regressions: Array = []
	for w in REACHABLE_FLOOR:
		var now: int = int(counts.get(w, 0))
		if now < int(REACHABLE_FLOOR[w]):
			regressions.append("%s: %d reachable, floor is %d" % [w, now, REACHABLE_FLOOR[w]])
	assert_eq(regressions, [], "a masterite that could be fought no longer can:\n  %s"
		% "\n  ".join(regressions))


func test_the_unreachable_set_is_named_not_counted() -> void:
	# Raising a floor is the only way to make this file greener, and raising it requires wiring a
	# real encounter. The list prints on every failure so the gap stays legible instead of becoming
	# a number nobody can decode.
	var reachable: Dictionary = _reachable_masterites()
	var dead: Array = []
	for id in _masterite_ids():
		if not reachable.has(id):
			dead.append(id)
	var expected_dead: int = 24 - _floor_total()
	assert_lt(dead.size(), expected_dead + 1,
		"more masterites are unreachable than the recorded gap allows — %d dead, gap permits %d:\n  %s"
			% [dead.size(), expected_dead, "\n  ".join(dead)])


func _floor_total() -> int:
	var t: int = 0
	for w in REACHABLE_FLOOR:
		t += int(REACHABLE_FLOOR[w])
	return t


# ── the mistake this file used to make ──────────────────────────────

func test_enemy_pools_are_not_a_spawn_path_for_masterites() -> void:
	# The trap that produced the wrong fix. `masterite_*` pools look exactly like the pools that DO
	# feed encounters, so the obvious repair is to add a missing one — which is what I did, and it
	# changed nothing. If a consumer is ever built this test goes red, and that is the correct signal
	# to delete it rather than a reason to suppress it.
	# Derived from enemy_pools.json, not hand-listed: a seventh world's pool is covered on arrival.
	# The first cut of this asserted `contains("\"masterite_") and contains("enemy_pool")` per file
	# and went red on BattleManager's `masterite_type` metadata — wide in the wrong dimension.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json"))
	var pools: Dictionary = raw.get("pools", raw)
	var keys: Array = []
	for k in pools:
		if str(k).begins_with("masterite_"):
			keys.append(str(k))
	assert_gt(keys.size(), 0, "no masterite pools in the data — this test would be vacuous")
	var referenced: Array = []
	for path in _gd_sources():
		var text := FileAccess.get_file_as_string(path)
		for k in keys:
			if text.contains("\"%s\"" % k):
				referenced.append("%s in %s" % [k, path.get_file()])
	assert_eq(referenced, [],
		"src/ now reads a masterite_* enemy pool — if that is deliberate, the reachability floors "
		+ "above must be re-derived, because pool membership finally means something:\n  %s"
			% "\n  ".join(referenced))


func test_pool_entries_still_resolve_to_real_monsters() -> void:
	# Unchanged and still worth keeping: a pool naming a missing id reads as a spawn bug rather than
	# a data typo. Inert data can still be wrong data, and this is cheap.
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemy_pools.json"))
	var pools: Dictionary = raw.get("pools", raw)
	var mons: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var ghosts: Array = []
	for key in pools:
		for m in (pools[key] as Array):
			if not mons.has(str(m)):
				ghosts.append("%s -> %s" % [key, m])
	assert_eq(ghosts, [], "pool entries with no monster behind them:\n  %s" % "\n  ".join(ghosts))


# ── positive controls ───────────────────────────────────────────────

func test_the_scan_actually_finds_spawns() -> void:
	# Every assertion above passes against a scanner that returns {}. Medieval is the proof the
	# derivation works: four placements the corpus can confirm independently.
	var reachable: Dictionary = _reachable_masterites()
	assert_gt(_gd_sources().size(), 100, "the source walk must actually enumerate src/")
	assert_eq(_masterite_ids().size(), 24, "24 masterites = 4 axes x 6 worlds")
	assert_true(reachable.has("masterite_curator_medieval"),
		"the scanner must find the Ironhaven placement — if it cannot, every zero above is vacuous")
	assert_gt(reachable.size(), 0, "a scanner finding nothing would report the whole roster dead")


func test_a_dialogue_mention_is_not_counted_as_a_spawn() -> void:
	# The error in my first sweep: I counted any occurrence, and every masterite appears in authored
	# intro/defeat cutscenes, so all 24 looked wired. This pins the discrimination itself.
	var line := '{"type": "dialogue", "speaker": "masterite_tempo_steampunk"}'
	var verb_present := false
	for verb in SPAWN_VERBS:
		if line.contains(verb):
			verb_present = true
	assert_false(verb_present,
		"a cutscene dialogue line must not satisfy the spawn predicate — that miscount turned 16 "
		+ "unreachable monsters into 4")
