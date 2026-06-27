extends GutTest

## tick 145 regression: two related bestiary fixes.
##
## 1. HeadlessBattleResolver (autogrind) never called
##    BestiarySystem.mark_seen. So a player running autogrind for
##    hours could face hundreds of monster types and have NONE of
##    them registered in their bestiary. Fixed by mirroring the
##    BattleScene._show_battle_quip mark_seen loop at the top of
##    resolve_battle.
##
## 2. BestiarySystem.get_seen_entries_sorted's `data.get("name", id)`
##    fallback leaked raw snake_case for monsters_cache entries
##    missing the "name" field (data drift, save built against
##    older monsters list). Same tick-141 prettifier-fallback
##    pattern.

const HEADLESS_RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const BESTIARY_SYSTEM := "res://src/bestiary/BestiarySystem.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── HeadlessBattleResolver mark_seen wiring ──────────────────────────────

func test_resolve_battle_marks_each_enemy_seen() -> void:
	# Pin: resolve_battle iterates _enemy_party and calls
	# BestiarySystem.mark_seen with each enemy's monster_type meta.
	var src := _read(HEADLESS_RESOLVER)
	var idx: int = src.find("func resolve_battle")
	assert_gt(idx, -1, "resolve_battle must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Tick 260: mark_seen gained an optional location arg.
	# Accept either legacy 1-arg or new 2-arg form.
	var has_legacy: bool = body.contains("BestiarySystem.mark_seen(mtype)")
	var has_with_loc: bool = body.contains("BestiarySystem.mark_seen(mtype, loc)")
	assert_true(has_legacy or has_with_loc,
		"resolve_battle must call BestiarySystem.mark_seen on each encountered enemy")
	assert_true(body.contains("enemy.get_meta(\"monster_type\", \"\")"),
		"resolve_battle must read monster_type meta (same key used by BattleScene + BattleEnemySpawner)")


func test_resolve_battle_marks_seen_runs_BEFORE_immediate_defeat() -> void:
	# Pin ordering: the mark_seen loop runs BEFORE the all-dead-
	# party defeat check. Otherwise an immediate-defeat case skips
	# the bestiary update. Edge case but real — a poisoned party
	# might enter autogrind already at 0 HP from the last battle.
	var src := _read(HEADLESS_RESOLVER)
	var idx: int = src.find("func resolve_battle")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	var mark_idx: int = body.find("BestiarySystem.mark_seen")
	var defeat_idx: int = body.find("immediate defeat")
	assert_gt(mark_idx, -1)
	assert_gt(defeat_idx, -1)
	assert_lt(mark_idx, defeat_idx,
		"mark_seen loop must run BEFORE the immediate-defeat short-circuit so bestiary updates even on instant-loss cases")


func test_resolve_battle_marks_seen_guards_invalid_combatant() -> void:
	# Defensive: an enemy can be queue_free'd between the autogrind
	# trigger and resolve_battle. Pin the is_instance_valid guard.
	var src := _read(HEADLESS_RESOLVER)
	var idx: int = src.find("func resolve_battle")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# The guard appears in the mark_seen loop.
	assert_true(body.contains("if not is_instance_valid(enemy):"),
		"mark_seen loop must guard is_instance_valid(enemy)")


# ── BestiarySystem.get_seen_entries_sorted name fallback ─────────────────

func test_seen_entries_name_fallback_prettifies_id() -> void:
	var src := _read(BESTIARY_SYSTEM)
	# Pin the new prettifier fallback line.
	assert_true(src.contains("\"name\": data.get(\"name\", id.replace(\"_\", \" \").capitalize()),"),
		"get_seen_entries_sorted must prettify id fallback — pre-fix leaked raw snake_case for monsters.json entries missing a 'name' field")
	# Negative pin: the old raw-id fallback must be gone.
	assert_false(src.contains("\"name\": data.get(\"name\", id),"),
		"old raw `data.get('name', id)` fallback must be gone — would surface 'cave_rat_king' instead of 'Cave Rat King' in the bestiary")


# ── Runtime check via mocked enemy + mark_seen ───────────────────────────

func test_runtime_mark_seen_propagates_to_bestiary() -> void:
	# End-to-end: spawn a mock enemy with monster_type meta, call
	# resolve_battle, verify the bestiary has the id marked.
	# This exercises the actual code path (not just string pins).
	var rss = load(HEADLESS_RESOLVER)
	var resolver = rss.new()

	# Mock enemy: a Combatant with monster_type meta and is_alive.
	var Combatant = load("res://src/battle/Combatant.gd")
	var enemy = Combatant.new()
	enemy.combatant_name = "Test Slime"
	enemy.max_hp = 1
	enemy.current_hp = 1
	enemy.is_alive = true
	enemy.set_meta("monster_type", "tick_145_test_slime")
	add_child_autofree(enemy)

	# Empty party — triggers immediate defeat path, but mark_seen
	# should have already run (pin: ordering check above).
	var was_seen_before: bool = BestiarySystem.is_seen("tick_145_test_slime")
	resolver.resolve_battle([], [enemy])
	var was_seen_after: bool = BestiarySystem.is_seen("tick_145_test_slime")

	# Cleanup the test marker so subsequent runs aren't polluted.
	if GameState.game_constants.has("seen_monsters"):
		(GameState.game_constants["seen_monsters"] as Dictionary).erase("tick_145_test_slime")

	assert_false(was_seen_before,
		"sanity: marker shouldn't be pre-set (test pollution check)")
	assert_true(was_seen_after,
		"BestiarySystem must mark the enemy as seen after resolve_battle — was the bug pre-tick-145")
