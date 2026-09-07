extends GutTest

## tick 244: regression test for stale-id count inflation.
##
## Pre-fix: discovery_counts() and defeat_counts() returned raw
## seen_monsters/defeated_monsters dict sizes from GameState. But
## get_seen_entries_sorted() silently skipped rows whose id wasn't
## in _monsters_cache. So if monsters.json got edited (data drift,
## story-agent reload, Scriptweaver typo) and an id vanished, the
## header could show "90/88 seen" while the list rendered 88 rows.
##
## Post-fix: numerator filters against _monsters_cache so an orphan
## id contributes 0 to the count. Numerator <= denominator always.
##
## The fix is non-destructive — orphan ids stay in the GameState
## dict (preserving historical data) but don't inflate the count.


func before_each() -> void:
	# Wipe seen/defeated state so previous tests don't bleed into ours.
	GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["defeated_monsters"] = {}
	BestiarySystem.reload()


# ── Numerator ≤ denominator invariant ───────────────────────────────

func test_discovery_count_caps_at_denominator() -> void:
	# Stuff a known-good id plus 3 orphans into seen.
	BestiarySystem.mark_seen("slime")
	GameState.game_constants["seen_monsters"]["__orphan_a"] = true
	GameState.game_constants["seen_monsters"]["__orphan_b"] = true
	GameState.game_constants["seen_monsters"]["__orphan_c"] = true
	var counts: Vector2i = BestiarySystem.discovery_counts()
	# Pre-fix: counts.x = 4 (3 orphans + slime), counts.y = ~88 — fine here.
	# Real bug surfaces when numerator > denominator. Force it:
	# add MORE orphan ids than the cache size to prove the invariant.
	var cache_size: int = counts.y
	for i in cache_size + 5:
		GameState.game_constants["seen_monsters"]["__bulk_orphan_%d" % i] = true
	var inflated: Vector2i = BestiarySystem.discovery_counts()
	assert_true(inflated.x <= inflated.y,
		"discovery_counts numerator must be <= denominator even with %d orphan ids in seen dict (raw seen size: %d, cache size: %d, count returned: %d/%d)" % [
			cache_size + 5,
			GameState.game_constants["seen_monsters"].size(),
			cache_size, inflated.x, inflated.y,
		])


func test_defeat_count_caps_at_denominator() -> void:
	BestiarySystem.mark_defeated("slime")
	var cache_size: int = BestiarySystem.defeat_counts().y
	for i in cache_size + 5:
		GameState.game_constants["defeated_monsters"]["__bulk_orphan_%d" % i] = true
	var inflated: Vector2i = BestiarySystem.defeat_counts()
	assert_true(inflated.x <= inflated.y,
		"defeat_counts numerator must be <= denominator even with orphan ids (got %d/%d)" % [inflated.x, inflated.y])


# ── Orphan ids in dict don't add to count ──────────────────────────

func test_orphan_seen_id_does_not_inflate_discovery_count() -> void:
	var baseline: Vector2i = BestiarySystem.discovery_counts()
	assert_eq(baseline.x, 0, "baseline must be 0 seen")
	GameState.game_constants["seen_monsters"]["__definitely_not_a_real_monster_id_xyz"] = true
	var after: Vector2i = BestiarySystem.discovery_counts()
	assert_eq(after.x, 0,
		"orphan id must contribute 0 to discovery_counts (got %d, expected 0)" % after.x)


func test_orphan_defeated_id_does_not_inflate_defeat_count() -> void:
	var baseline: Vector2i = BestiarySystem.defeat_counts()
	assert_eq(baseline.x, 0, "baseline must be 0 defeated")
	GameState.game_constants["defeated_monsters"]["__definitely_not_a_real_monster_id_xyz"] = true
	var after: Vector2i = BestiarySystem.defeat_counts()
	assert_eq(after.x, 0,
		"orphan id must contribute 0 to defeat_counts (got %d, expected 0)" % after.x)


# ── Valid ids still count ─────────────────────────────────────────

func test_valid_seen_id_increments_count() -> void:
	var baseline: Vector2i = BestiarySystem.discovery_counts()
	BestiarySystem.mark_seen("slime")
	var after: Vector2i = BestiarySystem.discovery_counts()
	# Confirm slime is in the cache (sanity); otherwise this test is meaningless.
	var has_slime: bool = not BestiarySystem.get_monster_data("slime").is_empty()
	if has_slime:
		assert_eq(after.x, baseline.x + 1,
			"a valid known id must add exactly 1 to the count")
	else:
		# slime missing from monsters.json — pick a different test fixture.
		push_warning("[test_valid_seen_id_increments_count] 'slime' not in monsters.json — skipping; pick a different fixture id")


# ── Orphan stays in GameState (non-destructive) ────────────────────

func test_orphan_id_preserved_in_game_state_dict() -> void:
	# Pin: the fix is filter-at-read, NOT clean-at-write. The raw
	# dict still holds the orphan id so historical data is preserved
	# (and if monsters.json adds the id back, it counts again).
	GameState.game_constants["seen_monsters"]["__legacy_id"] = true
	BestiarySystem.discovery_counts()
	# After calling discovery_counts, the dict must still contain the orphan.
	assert_true(GameState.game_constants["seen_monsters"].has("__legacy_id"),
		"orphan id must be preserved in seen_monsters dict — fix is filter-at-read, not destructive cleanup")


# ── Cross-pin: numerator matches get_seen_entries_sorted row count ─

func test_discovery_count_matches_rendered_entry_count() -> void:
	# The original bug: counts.x said 90 but the rendered list only
	# had 88 rows because get_seen_entries_sorted skips orphans.
	# After fix, counts.x must equal the rendered entry count.
	BestiarySystem.mark_seen("slime")
	GameState.game_constants["seen_monsters"]["__orphan_1"] = true
	GameState.game_constants["seen_monsters"]["__orphan_2"] = true
	var counts: Vector2i = BestiarySystem.discovery_counts()
	var rows: Array = BestiarySystem.get_seen_entries_sorted()
	assert_eq(counts.x, rows.size(),
		"discovery_counts numerator (%d) must match rendered entry count (%d) — header/list consistency" % [counts.x, rows.size()])
