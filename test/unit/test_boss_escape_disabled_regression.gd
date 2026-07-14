extends GutTest

## tick 419: escape_allowed is gated on boss presence in the enemy
## party. Pre-fix it defaulted to true and no code path ever set it
## false — players could flee from boss battles (Cave Rat King,
## Mordaine, dragons, etc.).
##
## start_battle now reads monsters.json `boss: true` flag on each
## enemy and disables flee when ANY boss is in the party.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_start_battle_gates_escape_on_boss_flag() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Pin the boss-detection logic.
	assert_true(body.contains("data.get(\"boss\", false)"),
		"start_battle must read the boss flag from monsters.json")
	assert_true(body.contains("escape_allowed = false"),
		"start_battle must set escape_allowed=false when a boss is detected")
	assert_true(body.contains("escape_allowed = true"),
		"start_battle must reset escape_allowed=true at the top of the boss-detection block (default)")


func test_pin_data_carries_boss_flag() -> void:
	# Sanity: the W1 bosses still author the boss flag — if a future
	# rebalance drops the flag from cave_rat_king, the new code path
	# would silently re-enable flee for that battle.
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	for boss_id in ["cave_rat_king", "chancellor_mordaine"]:
		assert_true(data.has(boss_id), "monsters.json must include %s" % boss_id)
		assert_true(bool(data[boss_id].get("boss", false)),
			"%s must author boss=true (fix relies on this)" % boss_id)


func test_default_remains_escapable() -> void:
	# Regression guard: random encounters (no boss in pool) must still
	# allow escape. The fix sets escape_allowed=true BEFORE the loop,
	# so a no-boss enemy party leaves it true.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The reset-true must appear BEFORE the boss-detection loop.
	var reset_idx: int = body.find("escape_allowed = true")
	var loop_idx: int = body.find("for enemy in enemies:")
	assert_gt(reset_idx, -1)
	assert_gt(loop_idx, -1)
	assert_lt(reset_idx, loop_idx,
		"escape_allowed=true reset must be BEFORE the for-loop so non-boss battles stay escapable")
