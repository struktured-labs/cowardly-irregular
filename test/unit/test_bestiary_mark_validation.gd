extends GutTest

## tick 245: mark_seen/mark_defeated input validation.
##
## Pre-tick-245 these accepted any string with no warning. Concrete
## silent-fail vectors:
##
##   - empty monster_id (Combatant with missing monster_type — typical
##     for Summoner internals, mid-test fixtures, save-side drift):
##     "" got written to seen_monsters dict. Forever.
##
##   - typo'd id (Scriptweaver spawn, content edit): silently polluted
##     the dict — tick 244 count filter now hides it from the UI but
##     the dict still grew unboundedly.
##
## Post-fix:
##   - empty id: reject outright + push_warning
##   - unknown id (not in cache): push_warning but still write so that
##     a story-agent reload that introduces the id later still grants
##     credit (the tick 244 count filter swallows the noise until then)
##
## The unknown-id WRITE-anyway behavior is intentional. If we rejected,
## a story-agent reload+rename sequence (cache version N has 'slime',
## reload to N+1 renames it 'slime_mk2', player's saved 'slime' would
## be lost if mark_seen rejected unknown ids).


func before_each() -> void:
	GameState.game_constants["seen_monsters"] = {}
	GameState.game_constants["defeated_monsters"] = {}
	BestiarySystem.reload()


# ── Empty id is rejected outright ───────────────────────────────────

func test_mark_seen_rejects_empty_string() -> void:
	BestiarySystem.mark_seen("")
	assert_false(GameState.game_constants["seen_monsters"].has(""),
		"empty monster_id must NOT be written to seen_monsters dict (was — silent pollution from missing monster_type)")


func test_mark_defeated_rejects_empty_string() -> void:
	BestiarySystem.mark_defeated("")
	assert_false(GameState.game_constants["defeated_monsters"].has(""),
		"empty monster_id must NOT be written to defeated_monsters dict")
	# mark_defeated calls mark_seen — must ALSO not pollute seen.
	assert_false(GameState.game_constants["seen_monsters"].has(""),
		"empty monster_id rejected by mark_defeated must NOT bleed into seen via the implicit mark_seen call")


# ── Unknown id still writes (non-destructive) ──────────────────────

func test_mark_seen_writes_unknown_id_anyway() -> void:
	# Pin: the WRITE-anyway behavior is intentional. We can't reject
	# unknown ids because reload might add them later.
	BestiarySystem.mark_seen("__test_future_monster_xyz")
	assert_true(GameState.game_constants["seen_monsters"].has("__test_future_monster_xyz"),
		"unknown id must still be written so future reload can grant credit")


func test_mark_defeated_writes_unknown_id_anyway() -> void:
	BestiarySystem.mark_defeated("__test_future_monster_xyz")
	assert_true(GameState.game_constants["defeated_monsters"].has("__test_future_monster_xyz"),
		"unknown id must still be written to defeated_monsters")
	assert_true(GameState.game_constants["seen_monsters"].has("__test_future_monster_xyz"),
		"unknown id written to defeated_monsters must also seed seen_monsters via the implicit mark_seen call")


# ── Known id writes cleanly (no regression) ────────────────────────

func test_mark_seen_known_id_still_works() -> void:
	# Sanity: validation doesn't break the happy path.
	# Skip if 'slime' isn't in the cache for some reason.
	if BestiarySystem.get_monster_data("slime").is_empty():
		push_warning("[test] slime missing from monsters.json — pick a different fixture id")
		return
	BestiarySystem.mark_seen("slime")
	assert_true(GameState.game_constants["seen_monsters"].has("slime"),
		"known id must still be written normally")


func test_mark_defeated_known_id_still_works() -> void:
	if BestiarySystem.get_monster_data("slime").is_empty():
		push_warning("[test] slime missing from monsters.json — pick a different fixture id")
		return
	BestiarySystem.mark_defeated("slime")
	assert_true(GameState.game_constants["defeated_monsters"].has("slime"))
	assert_true(GameState.game_constants["seen_monsters"].has("slime"),
		"defeat must seed seen (a monster can only be killed if encountered)")


# ── Cross-pin with tick 244 count filter ────────────────────────────

func test_tick_244_filter_swallows_warned_unknown_ids() -> void:
	# The push_warning is informative but the count filter must hide
	# the unknown id from the user-facing header. Otherwise warning +
	# 90/88 display would be a confusing double-failure.
	BestiarySystem.mark_seen("__unknown_late_arrival")
	var counts: Vector2i = BestiarySystem.discovery_counts()
	assert_eq(counts.x, 0,
		"unknown id written by mark_seen must be filtered out of discovery_counts (tick 244 invariant)")


# ── No side effects on guard rejection ──────────────────────────────

func test_empty_seen_does_not_create_dict_keys() -> void:
	# If mark_seen("") falsely created a "" key with value true, the
	# guard rejection is incomplete. Confirm zero keys after.
	GameState.game_constants.erase("seen_monsters")
	BestiarySystem.mark_seen("")
	# Either the dict wasn't created (preferred) or it has 0 keys.
	var dict: Dictionary = GameState.game_constants.get("seen_monsters", {})
	assert_eq(dict.size(), 0,
		"mark_seen('') must not leak any keys into seen_monsters dict")
