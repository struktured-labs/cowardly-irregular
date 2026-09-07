extends GutTest

## tick 146 regression: BestiarySystem tracks "defeated" as a state
## distinct from "seen". Pre-fix the bestiary showed an entry the
## moment a monster spawned, even if the party fled or wiped. Now
## the UI can render "?" stats for seen-but-not-killed and full
## intel for actually-defeated monsters.
##
## Invariant: defeated is a strict subset of seen. mark_defeated
## auto-marks_seen so the invariant is maintained at the API level
## (you can't kill what you didn't see).
##
## Wired hooks:
##   - BattleManager.end_battle(victory=true) — full-fat battle
##   - HeadlessBattleResolver._build_results(victory=true) —
##     autogrind kill credit

const BESTIARY := "res://src/bestiary/BestiarySystem.gd"
const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"
const HEADLESS_RESOLVER := "res://src/autogrind/HeadlessBattleResolver.gd"
const MONSTER_TYPE := "tick_146_test_monster"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func before_each() -> void:
	# Defensive: clean test marker from prior runs.
	if GameState.game_constants.has("seen_monsters"):
		(GameState.game_constants["seen_monsters"] as Dictionary).erase(MONSTER_TYPE)
	if GameState.game_constants.has("defeated_monsters"):
		(GameState.game_constants["defeated_monsters"] as Dictionary).erase(MONSTER_TYPE)


func after_each() -> void:
	before_each()


# ── BestiarySystem API ───────────────────────────────────────────────────

func test_mark_defeated_implies_mark_seen() -> void:
	# Invariant: defeating an unseen monster is impossible. The API
	# enforces it by calling mark_seen internally.
	assert_false(BestiarySystem.is_seen(MONSTER_TYPE),
		"sanity: monster shouldn't be pre-seen")
	BestiarySystem.mark_defeated(MONSTER_TYPE)
	assert_true(BestiarySystem.is_seen(MONSTER_TYPE),
		"mark_defeated must imply mark_seen — encountered ≠ killed but killed ⊂ encountered")
	assert_true(BestiarySystem.is_defeated(MONSTER_TYPE),
		"mark_defeated must set defeated flag")


func test_mark_seen_does_NOT_imply_mark_defeated() -> void:
	# Reverse direction: seeing doesn't mean killing.
	BestiarySystem.mark_seen(MONSTER_TYPE)
	assert_true(BestiarySystem.is_seen(MONSTER_TYPE))
	assert_false(BestiarySystem.is_defeated(MONSTER_TYPE),
		"mark_seen must NOT auto-mark defeated — fled / wiped encounters stay un-killed")


func test_defeat_counts_returns_pair() -> void:
	# Pin the signature: (defeated, total) as Vector2i.
	var c: Vector2i = BestiarySystem.defeat_counts()
	assert_true(c is Vector2i, "defeat_counts must return Vector2i")
	assert_gte(c.x, 0, "defeated count non-negative")
	assert_gte(c.y, 0, "total count non-negative")
	assert_lte(c.x, c.y, "defeated must be ≤ total (can't kill more than exists)")


func test_get_defeated_ids_starts_empty_until_marked() -> void:
	# Pre-mark: not in defeated list.
	assert_false(BestiarySystem.get_defeated_ids().has(MONSTER_TYPE))
	BestiarySystem.mark_defeated(MONSTER_TYPE)
	assert_true(BestiarySystem.get_defeated_ids().has(MONSTER_TYPE))


# ── Bestiary entries include defeated flag ───────────────────────────────

func test_seen_entries_include_defeated_field() -> void:
	# UI relies on this for grayed-out display. Snapshot + restore
	# slime's seen state so the test doesn't permanently mark it
	# seen for other test files (was tick-148 pollution finding).
	var pre_seen: bool = BestiarySystem.is_seen("slime")
	BestiarySystem.mark_seen("slime")
	var entries: Array = BestiarySystem.get_seen_entries_sorted()
	var slime_entry: Dictionary = {}
	for e in entries:
		if e.get("id", "") == "slime":
			slime_entry = e
			break
	# Restore the pre-test state before assertions so a failure
	# doesn't leave the suite polluted.
	if not pre_seen:
		(GameState.game_constants["seen_monsters"] as Dictionary).erase("slime")
	assert_false(slime_entry.is_empty(),
		"slime must be in seen entries after mark_seen")
	assert_true(slime_entry.has("defeated"),
		"seen entry must include 'defeated' field — UI uses it for grayed-out display")
	# Don't pin the actual value — prior test runs may have killed
	# slime in this GameState; defeated could be true or false.


# ── BattleManager end_battle wires mark_defeated ─────────────────────────

func test_battle_manager_end_battle_marks_defeated() -> void:
	var src := _read(BATTLE_MANAGER)
	# Pin: end_battle victory branch iterates enemy_party and calls
	# mark_defeated on each enemy's monster_type meta.
	var idx: int = src.find("func end_battle(victory: bool)")
	assert_gt(idx, -1, "end_battle must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	# Tick 260: mark_defeated gained an optional location arg.
	var has_legacy: bool = body.contains("BestiarySystem.mark_defeated(mtype)")
	var has_with_loc: bool = body.contains("BestiarySystem.mark_defeated(mtype, defeat_loc)")
	assert_true(has_legacy or has_with_loc,
		"end_battle (victory branch) must call BestiarySystem.mark_defeated")
	# Negative pin: must be guarded behind victory.
	var victory_idx: int = body.find("if victory:")
	var mark_idx: int = body.find("BestiarySystem.mark_defeated")
	assert_gt(victory_idx, -1)
	assert_gt(mark_idx, -1)
	assert_lt(victory_idx, mark_idx,
		"mark_defeated must be inside the `if victory:` block — don't credit kills on defeat")


# ── HeadlessBattleResolver wires mark_defeated ───────────────────────────

func test_headless_resolver_marks_defeated_on_victory() -> void:
	var src := _read(HEADLESS_RESOLVER)
	var idx: int = src.find("func _build_results")
	assert_gt(idx, -1, "_build_results must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx)
	# Tick 260: mark_defeated gained an optional location arg.
	var has_legacy: bool = body.contains("BestiarySystem.mark_defeated(mtype)")
	var has_with_loc: bool = body.contains("BestiarySystem.mark_defeated(mtype, defeat_loc)")
	assert_true(has_legacy or has_with_loc,
		"_build_results must call mark_defeated in the victory branch")
	# Same victory-only guard as BattleManager.
	var victory_idx: int = body.find("if victory:")
	var mark_idx: int = body.find("BestiarySystem.mark_defeated")
	assert_lt(victory_idx, mark_idx,
		"autogrind mark_defeated must be inside victory branch")


# ── Runtime check via HeadlessBattleResolver ─────────────────────────────

func test_runtime_resolve_battle_victory_marks_enemy_defeated() -> void:
	# End-to-end: spawn a low-HP mock enemy that dies easily, run
	# resolve_battle with a strong party, verify defeated flag set.
	var Combatant = load("res://src/battle/Combatant.gd")
	var enemy = Combatant.new()
	enemy.combatant_name = "Test Mob"
	enemy.max_hp = 1
	enemy.current_hp = 0
	enemy.is_alive = false
	enemy.set_meta("monster_type", MONSTER_TYPE)
	add_child_autofree(enemy)
	# Already-dead enemy → resolver enters victory path immediately
	# via _all_dead check. _build_results(true) runs.
	# Mock a player so all_dead check on player_party is false.
	var player = Combatant.new()
	player.is_alive = true
	player.max_hp = 100
	player.current_hp = 100
	add_child_autofree(player)
	var rss = load(HEADLESS_RESOLVER)
	var resolver = rss.new()
	var pre_def: bool = BestiarySystem.is_defeated(MONSTER_TYPE)
	resolver.resolve_battle([player], [enemy])
	var post_def: bool = BestiarySystem.is_defeated(MONSTER_TYPE)
	assert_false(pre_def, "sanity: pre-defeat state")
	assert_true(post_def,
		"HeadlessBattleResolver victory must propagate to BestiarySystem.is_defeated")
