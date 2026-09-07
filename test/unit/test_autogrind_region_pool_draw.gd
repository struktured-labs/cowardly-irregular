extends GutTest

## Autogrind draws from the REGION'S ENCOUNTER POOL, roster as fallback.
##
## struktured ruled (via cowir-main msg 2994): "worth doing for sure. autogrind
## is basically incomplete." Not a balance tweak — finishing a feature that
## shipped unwired. Autogrind had been fighting BattleEnemySpawner.MONSTER_TYPES,
## which cowir-battle established (msg 2971) is architecturally the engine's
## degraded-mode fallback, not a curated pool: spawn_enemies_from_ids calls it
## only when no valid ids resolve, and three load-failure warnings name it as
## the "monsters.json is broken" default. Autogrind never populated a pool, so
## it landed there by omission — 11 of 94 species, identical in every world.
##
## ACCEPTANCE CRITERION is permakill, not the diff (cowir-main msg 2994):
## Necromancer's authored promise is "EXTERMINATES species from all three spawn
## paths." With an 11-species draw that was quietly false for anything regional —
## permakill a W5 monster and the grind was unchanged because it was never going
## to spawn. The tests below verify it becomes true, INCLUDING the dangerous
## interaction cowir-battle flagged (msg 2999) and cowir-main escalated (msg 3001):
## a permakill that empties a region pool must NOT resurrect roster monsters via
## the fallback. That would be the promise breaking in the loudest possible way.
##
## YIELD PARITY (struktured 2026-07-01, no hidden yield tax): regional monsters
## legitimately pay different exp/gold because they ARE different monsters. What
## is forbidden is a compensating multiplier introduced to keep totals flat.
## Ratcheted below.

const ControllerScript := preload("res://src/autogrind/AutogrindController.gd")

var _ctrl: Node
var _saved_permakilled: Array = []
var _saved_region: String = ""


func before_each() -> void:
	_ctrl = ControllerScript.new()
	add_child_autofree(_ctrl)
	AutogrindSystem._test_disable_persistence = true
	_saved_region = AutogrindSystem.current_region_id
	if GameState and "permakilled_monster_types" in GameState:
		_saved_permakilled = GameState.permakilled_monster_types.duplicate()


func after_each() -> void:
	AutogrindSystem.current_region_id = _saved_region
	if GameState and "permakilled_monster_types" in GameState:
		GameState.permakilled_monster_types.clear()
		for m in _saved_permakilled:
			GameState.permakilled_monster_types.append(m)
	AutogrindSystem._test_disable_persistence = false


func _ids_of(candidates: Array) -> Array:
	var out: Array = []
	for c in candidates:
		out.append(str((c as Dictionary).get("id", "")))
	return out


func _roster_ids() -> Array:
	var out: Array = []
	for m in BattleEnemySpawner.MONSTER_TYPES:
		out.append(str(m.get("id", "")))
	return out


# ── Pool resolution ──────────────────────────────────────────────────────────

func test_exact_region_pool_is_used() -> void:
	# W2-W6 region ids match a pool id exactly (suburban_overworld etc).
	AutogrindSystem.current_region_id = "suburban_overworld"
	var ids: Array = _ctrl._region_pool_ids()
	assert_gt(ids.size(), 0,
		"suburban_overworld is a real pool in enemy_pools.json — it must resolve, or autogrind stays on the degraded-mode roster in W2")


func test_display_name_region_resolves_the_INTEGRATION_case() -> void:
	# The case that made the first cut of this feature INERT in real play, and
	# which the id-form tests above could never catch because they set the id
	# directly rather than the way the game does.
	#
	# GameLoop:4715 builds the grind config's region as a DISPLAY name —
	#   _current_map_id.replace("_", " ").capitalize()  →  "Suburban Overworld"
	# AutogrindUI:1607 passes that display string through as config["region"],
	# and AutogrindController:128 hands it to set_current_region(). So on the
	# normal start path current_region_id is "Suburban Overworld", which matches
	# no pool key. Only the auto-advance path (advance_to_next_region, which
	# passes WORLD_REGIONS' snake_case id) would have resolved — meaning the
	# feature worked only AFTER a world transition and never on a fresh grind.
	for pair in [["Suburban Overworld", "suburban_overworld"], ["Abstract Overworld", "abstract_overworld"]]:
		AutogrindSystem.current_region_id = str(pair[0])
		var via_display: Array = _ctrl._region_pool_ids()
		AutogrindSystem.current_region_id = str(pair[1])
		var via_id: Array = _ctrl._region_pool_ids()
		assert_gt(via_display.size(), 0,
			"display-name region '%s' must resolve a pool — this is the form the UI actually supplies, so failing here means the whole feature is inert on a fresh grind" % str(pair[0]))
		assert_eq(via_display, via_id,
			"'%s' and '%s' must resolve identically — the display and id forms are the same region reached by two code paths" % [str(pair[0]), str(pair[1])])


func test_w1_display_name_resolves_too() -> void:
	# W1 via the UI path: map id "overworld" → display "Overworld".
	AutogrindSystem.current_region_id = "Overworld"
	var ids: Array = _ctrl._region_pool_ids()
	assert_gt(ids.size(), 0,
		"W1's display form 'Overworld' must union the zone pools — W1 is the most-played world and the UI start path is how a grind normally begins")


func test_subdivided_region_unions_its_zone_pools() -> void:
	# W1's region id is "overworld" and NO pool has that id — W1 was authored
	# with 8 zone pools (overworld_central/forest/ice/…) while W2-W6 got one
	# pool each. Grinding "the medieval overworld" should span its bestiary,
	# so prefix-matched zone pools are unioned. This is the case that matters
	# most in practice: W1 is where struktured plays.
	AutogrindSystem.current_region_id = "overworld"
	var ids: Array = _ctrl._region_pool_ids()
	assert_gt(ids.size(), 0,
		"W1 'overworld' has no exact pool — the zone-pool union must resolve, else W1 (the most-played world) silently keeps the 11-species roster")
	assert_true(ids.size() > 3,
		"the union of 8 W1 zone pools should exceed any single zone's size — got %d, which suggests only one zone matched" % ids.size())


func test_union_has_no_duplicates() -> void:
	# Zone pools overlap (slime appears in several). Duplicates would bias the
	# random draw toward common species rather than sampling the region evenly.
	AutogrindSystem.current_region_id = "overworld"
	var ids: Array = _ctrl._region_pool_ids()
	var seen := {}
	var dupes: Array = []
	for id in ids:
		if seen.has(id):
			dupes.append(id)
		seen[id] = true
	assert_eq(dupes.size(), 0,
		"unioned zone pools must de-duplicate — dupes bias the draw toward species that appear in multiple zones: %s" % str(dupes))


func test_unknown_region_falls_back_to_roster() -> void:
	# The fallback is the const's actual job and must stay reachable.
	AutogrindSystem.current_region_id = "__not_a_real_region_xyz"
	assert_eq(_ctrl._region_pool_ids().size(), 0, "unknown region resolves no pool")
	var candidates: Array = _ctrl._grind_draw_candidates()
	assert_gt(candidates.size(), 0,
		"unknown region must still grind via the roster fallback — a region with no pool, an unknown id, or a data-load failure must never leave the player unable to grind")


func test_empty_region_falls_back_to_roster() -> void:
	AutogrindSystem.current_region_id = ""
	assert_gt(_ctrl._grind_draw_candidates().size(), 0,
		"empty region id (grind started without a region) must fall back rather than empty-emit")


func test_pool_draw_prefers_pool_over_roster() -> void:
	# The whole point: in a region WITH a pool, the draw must not be the roster.
	AutogrindSystem.current_region_id = "abstract_overworld"
	var pool_ids: Array = _ctrl._region_pool_ids()
	if pool_ids.is_empty():
		pending("abstract_overworld pool missing from enemy_pools.json")
		return
	var drawn: Array = _ids_of(_ctrl._grind_draw_candidates())
	var roster: Array = _roster_ids()
	var from_pool := 0
	for id in drawn:
		if id in pool_ids:
			from_pool += 1
	assert_eq(from_pool, drawn.size(),
		"every candidate in a pooled region must come from that pool — leakage means the roster is still winning (drawn=%s pool=%s roster=%s)" % [str(drawn), str(pool_ids), str(roster)])


# ── Permakill: the acceptance criterion ──────────────────────────────────────

func test_permakill_removes_a_regional_species_from_the_draw() -> void:
	# The authored promise, in the case that was previously false: a species
	# that only exists in a regional pool must actually vanish from the grind.
	AutogrindSystem.current_region_id = "abstract_overworld"
	var pool_ids: Array = _ctrl._region_pool_ids()
	if pool_ids.size() < 2:
		pending("need a multi-species pool for this case")
		return
	var victim: String = str(pool_ids[0])
	if GameState == null or not ("permakilled_monster_types" in GameState):
		pending("GameState.permakilled_monster_types unavailable")
		return
	GameState.permakilled_monster_types.append(victim)

	var drawn: Array = _ids_of(_ctrl._generate_scaled_enemies())
	assert_false(victim in drawn,
		"permakilled species '%s' must not spawn in its own region's grind — this is Necromancer's authored 'EXTERMINATES from all three spawn paths' promise, which was quietly false for every regional species while autogrind drew from the 11-monster roster" % victim)


func test_fully_exterminated_pool_stops_the_grind_and_does_NOT_resurrect_roster() -> void:
	# THE dangerous interaction (cowir-battle msg 2999, escalated cowir-main msg 3001).
	# BattleEnemySpawner's own fallback is all-or-nothing: a pool resolving zero
	# ids drops the WHOLE encounter to the roster. If autogrind copied that shape
	# and applied permakill BEFORE the fallback decision, exterminating a region
	# would resurrect W1 trash into the region the player just cleared — the
	# promise breaking in the loudest possible way.
	#
	# Autogrind deliberately orders it the other way: the pool-vs-roster decision
	# is made on RESOLVABILITY (does the data exist), permakill filters AFTER.
	# So an exterminated pool yields [], which the controller reads as "nothing
	# left to grind" and stops cleanly.
	AutogrindSystem.current_region_id = "abstract_overworld"
	var pool_ids: Array = _ctrl._region_pool_ids()
	if pool_ids.is_empty():
		pending("abstract_overworld pool missing")
		return
	if GameState == null or not ("permakilled_monster_types" in GameState):
		pending("GameState.permakilled_monster_types unavailable")
		return
	for id in pool_ids:
		GameState.permakilled_monster_types.append(str(id))

	var drawn: Array = _ids_of(_ctrl._generate_scaled_enemies())
	assert_eq(drawn.size(), 0,
		"a fully exterminated region pool must yield an EMPTY draw so the grind stops — got %s" % str(drawn))

	var roster: Array = _roster_ids()
	var resurrected: Array = []
	for id in drawn:
		if id in roster and not (id in pool_ids):
			resurrected.append(id)
	assert_eq(resurrected.size(), 0,
		"exterminating a region must NEVER resurrect roster species via the fallback: %s — permakill is filtered AFTER the pool/roster decision precisely so an emptied pool reads as extermination, not as 'no data, use the roster'" % str(resurrected))


func test_permakill_still_works_on_the_roster_fallback_path() -> void:
	# The fallback is a second entry point and needs its own case.
	AutogrindSystem.current_region_id = "__not_a_real_region_xyz"
	if GameState == null or not ("permakilled_monster_types" in GameState):
		pending("GameState.permakilled_monster_types unavailable")
		return
	var roster: Array = _roster_ids()
	assert_gt(roster.size(), 0, "setup: roster must be non-empty")
	GameState.permakilled_monster_types.append(str(roster[0]))
	var drawn: Array = _ids_of(_ctrl._generate_scaled_enemies())
	assert_false(str(roster[0]) in drawn,
		"permakill must hold on the roster fallback path too — it's a separate entry point from the pool path")


# ── Data integrity + yield parity ────────────────────────────────────────────

func test_every_pool_id_resolves_in_monsters_json() -> void:
	# Extends the cadence-#25 roster↔reward guard: moving the draw from 11 ids
	# to 76 moves the dangling-key risk with it. An unresolvable pool id is
	# silently skipped by _base_data_for_id, so a typo shrinks the region's
	# bestiary with no error — exactly the silent class this lane keeps finding.
	var raw: String = FileAccess.get_file_as_string("res://data/enemy_pools.json")
	var pools: Dictionary = JSON.parse_string(raw)
	var mraw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var mdb: Dictionary = JSON.parse_string(mraw)
	if mdb.has("monsters"):
		mdb = mdb["monsters"]
	var missing: Array = []
	for pool_id in pools:
		for enemy_id in pools[pool_id]:
			if not mdb.has(str(enemy_id)) and not (str(enemy_id) in missing):
				missing.append("%s (in pool %s)" % [str(enemy_id), str(pool_id)])
	assert_eq(missing.size(), 0,
		"enemy_pools.json ids with no monsters.json row: %s — _base_data_for_id skips them silently, so the region quietly loses that species from its grind" % str(missing))


func test_no_compensating_yield_multiplier_was_introduced() -> void:
	# struktured's 2026-07-01 no-hidden-yield-tax ruling. Regional monsters
	# paying different exp/gold is CORRECT — they are different monsters. What
	# is forbidden is normalising totals back to the roster's. If the draw
	# change ever tempts someone to "keep yields stable," this fails.
	var src: String = FileAccess.get_file_as_string("res://src/autogrind/AutogrindController.gd")
	var fn_start: int = src.find("func _grind_draw_candidates")
	assert_true(fn_start >= 0, "setup: _grind_draw_candidates must exist")
	var fn_end: int = src.find("\nfunc _generate_scaled_enemies", fn_start)
	var body: String = src.substr(fn_start, fn_end - fn_start)
	for banned in ["exp_multiplier", "gold_multiplier", "yield", "normali"]:
		assert_false(body.to_lower().contains(banned),
			"the draw path must not touch yields — regional rewards differ because the MONSTERS differ, never because a compensating '%s' was added to flatten totals (struktured 2026-07-01, no hidden yield tax)" % banned)


func test_pool_drawn_data_has_the_shape_scaling_expects() -> void:
	# create_scaled_enemy_data reads a nested "stats" dict. A pool-drawn entry
	# missing it would scale nothing and spawn an unscaled monster.
	AutogrindSystem.current_region_id = "suburban_overworld"
	var candidates: Array = _ctrl._grind_draw_candidates()
	assert_gt(candidates.size(), 0, "setup: expected candidates")
	for c in candidates:
		var d: Dictionary = c
		assert_true(d.has("stats") and d["stats"] is Dictionary and not (d["stats"] as Dictionary).is_empty(),
			"pool-drawn candidate '%s' must carry a non-empty nested stats dict — AutogrindSystem.create_scaled_enemy_data scales through it, so a flat or missing shape spawns an unscaled enemy" % str(d.get("id", "?")))
		assert_true(d.has("id") and not str(d["id"]).is_empty(),
			"every candidate needs an id — permakill filtering and bestiary credit both key on it")
