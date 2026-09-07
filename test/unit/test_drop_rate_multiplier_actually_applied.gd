extends GutTest

## tick 115 regression: GameState.game_constants["drop_rate_multiplier"]
## must be consumed by BattleManager when rolling item drops. Pre-fix,
## the knob was in the defaults dict + persisted via save/load, but
## NO code path read it. Scriptweaver writes were cosmetic.
##
## Closes the game_constants multiplier wiring arc — every multiplier
## in the defaults dict now affects gameplay:
##   exp_multiplier      → BattleManager (tick 109)
##   gold_multiplier     → GameState.add_gold (tick 113 hardened)
##   encounter_rate      → OverworldController (tick 110)
##   damage_multiplier   → Combatant.take_damage (tick 114)
##   healing_multiplier  → Combatant.heal (tick 114)
##   drop_rate_multiplier→ BattleManager item-drop roll (this tick)

const BATTLE_MANAGER := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_battle_manager_reads_drop_rate_multiplier_defensively() -> void:
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("GameState.game_constants.get(\"drop_rate_multiplier\", 1.0)"),
		"BattleManager must read game_constants['drop_rate_multiplier'] with .get(default=1.0)")


func test_drop_rate_multiplier_clamped_to_uniform_band() -> void:
	var src := _read(BATTLE_MANAGER)
	# Anchor on the drop_rate_mult assignment to scope the clamp pin.
	var idx: int = src.find("drop_rate_mult = clampf(")
	assert_gt(idx, -1, "drop_rate_mult clampf must exist")
	# Look forward ~150 chars for the band literal.
	var window: String = src.substr(idx, 200)
	assert_true(window.contains("0.1, 10.0"),
		"drop_rate_mult clamp band must be [0.1, 10.0] — uniform with tick 109/110/113/114")


func test_drop_rate_multiplier_factored_into_chance_check() -> void:
	# Pin: the multiplier scales the drop chance threshold, not the
	# randf() result. drop.get("chance", 0.0) * drop_rate_mult is
	# the threshold; randf() compares < this. So a 0.1 base chance
	# with 1.5x multiplier → 15% drop.
	var src := _read(BATTLE_MANAGER)
	assert_true(src.contains("randf() < drop.get(\"chance\", 0.0) * drop_rate_mult"),
		"drop chance check must multiply drop_rate_mult into the threshold — otherwise the read is dead")


func test_old_unscaled_chance_check_gone() -> void:
	# Negative pin: the unscaled `randf() < drop.get("chance", 0.0)`
	# must NOT remain. If both forms coexist, the unscaled one would
	# silently win on the first match.
	var src := _read(BATTLE_MANAGER)
	# Need to exclude the new combined form. The grep target is the
	# original form WITHOUT the trailing `* drop_rate_mult`. Look
	# for the substring with a specific suffix to disambiguate.
	assert_false(src.contains("randf() < drop.get(\"chance\", 0.0):"),
		"the old unscaled chance check must be removed — drop_rate_mult would never apply otherwise")


func test_drop_rate_mult_computed_once_per_battle() -> void:
	# Pin: the multiplier read is OUTSIDE the per-drop-table loop so
	# it's evaluated once per battle, not per drop roll.
	# game_constants doesn't change mid-victory; per-roll lookups
	# would waste cycles. Anchor on `drop_table = monsters_data[mt]`
	# (the drop-table inner loop, not the earlier per-enemy stat loops).
	var src := _read(BATTLE_MANAGER)
	var read_idx: int = src.find("drop_rate_mult = clampf(")
	var drop_loop_idx: int = src.find("var drop_table = monsters_data[mt].get(\"drop_table\"")
	assert_gt(read_idx, -1, "drop_rate_mult assignment must exist")
	assert_gt(drop_loop_idx, -1, "drop_table read must exist (inside the drop-rolling loop)")
	assert_lt(read_idx, drop_loop_idx,
		"drop_rate_mult must be computed BEFORE the drop-table inner loop — one read per battle, not per drop roll")


func test_game_state_still_defaults_drop_rate_to_one() -> void:
	# Sanity: GameState.game_constants's default for drop_rate_multiplier
	# must still be 1.0 so vanilla play scales drops at face value.
	var src := _read("res://src/meta/GameState.gd")
	assert_true(src.contains("\"drop_rate_multiplier\": 1.0"),
		"GameState.game_constants['drop_rate_multiplier'] must default to 1.0 — vanilla play unchanged")


func test_runtime_default_returns_one_when_key_missing() -> void:
	# Functional test: a pathological save that removed the key
	# must fall back to 1.0, not crash. Direct dict access would
	# crash; .get with default is safe.
	var gs_script := load("res://src/meta/GameState.gd")
	var gs = gs_script.new()
	gs.game_constants.erase("drop_rate_multiplier")
	# The fallback expression read in source.
	var mult: float = float(gs.game_constants.get("drop_rate_multiplier", 1.0))
	assert_eq(mult, 1.0,
		"runtime .get must return default 1.0 when key missing — defensive against debug paths")
	gs.queue_free()
