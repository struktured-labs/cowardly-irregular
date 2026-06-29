extends GutTest

## tick 431: abilities.json `hits` field now actually multi-hits.
##
## Pre-fix 5 abilities (gold_scatter, recursive_strike,
## repetitive_strike, temporal_strike, thread_slash) authored
## hits=2 or hits=3 with low damage_multiplier each — but the field
## was never read, so each "barrage of smaller hits" ability dealt
## one hit instead of N. A 3-hit 0.8x = 2.4x total ability landed
## as a single 0.8x hit, dealing 1/3 the intended damage.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_hits_field_read() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the read.
	assert_true(src.contains("max(1, int(ability.get(\"hits\", 1)))"),
		"physical-ability path must read the `hits` field with default 1")


func test_hits_loop_breaks_on_kill() -> void:
	# Defensive: a multi-hit ability that lands the killing blow on
	# hit 1 of 3 must NOT keep hitting a dead target.
	var src := _read(BATTLE_MANAGER_PATH)
	# The for-loop body must check is_alive before each hit.
	assert_true(src.contains("if not target.is_alive:") and src.contains("break  # don't keep hitting after a kill"),
		"multi-hit loop must early-break when target dies mid-volley")


func test_log_shows_hit_count() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the "×N" log surface so the player can see the multi-hit.
	assert_true(src.contains("\" ×%d\" % hits"),
		"battle log must surface the hit count via ×N suffix")


func test_data_still_authors_multi_hit_abilities() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	for ability_id in ["gold_scatter", "recursive_strike", "repetitive_strike", "temporal_strike", "thread_slash"]:
		assert_true(data.has(ability_id), "%s ability must exist" % ability_id)
		var hits: int = int(data[ability_id].get("hits", 0))
		assert_gt(hits, 1,
			"%s must still author hits > 1 (fix relies on this)" % ability_id)


func test_per_hit_helpers_called_inside_loop() -> void:
	# Each hit independently triggers permadeath_on_kill +
	# heal_from_damage. This is important for the_absence interactions
	# — three small hits absorb three small heals, not one big heal.
	var src := _read(BATTLE_MANAGER_PATH)
	# Pin the per-hit damage variable so we know the call site is
	# inside the loop.
	assert_true(src.contains("var hit_damage: int = target.take_damage(damage, false)"),
		"each hit must have its own take_damage call")
	# heal_from_damage takes hit_damage (per-hit) not actual_damage (total).
	assert_true(src.contains("_maybe_heal_from_damage(target, hit_damage, \"\")"),
		"_maybe_heal_from_damage must be called PER HIT with hit_damage (not total) so the_absence absorbs each hit independently")
