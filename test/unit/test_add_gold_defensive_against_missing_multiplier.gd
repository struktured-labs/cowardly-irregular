extends GutTest

## tick 113 regression: GameState.add_gold must read gold_multiplier
## defensively (.get with a default), not via direct dict access.
## Pre-fix, a debug path or pathological save that removed the key
## from game_constants would crash the entire victory flow with a
## KeyError the first time _on_battle_ended fired add_gold.
##
## Tick 112 made the from_dict load merge-instead-of-replace so this
## was much less likely — but a malformed runtime mutation (e.g. a
## Scriptweaver script that `.erase()`s the key) would still hit it.
## Belt + suspenders.

const GAME_STATE := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


func test_add_gold_uses_defensive_get_with_default() -> void:
	var src := _read(GAME_STATE)
	# Negative pin: the old direct-dict access must be gone.
	assert_false(src.contains("game_constants[\"gold_multiplier\"]"),
		"add_gold must NOT use direct dict access `game_constants[\"gold_multiplier\"]` — crashes if key missing")
	# Positive pin: the defensive .get(key, default) pattern.
	assert_true(src.contains("game_constants.get(\"gold_multiplier\", 1.0)"),
		"add_gold must use game_constants.get('gold_multiplier', 1.0) — safe against missing key")


func test_add_gold_clamps_multiplier_to_sane_band() -> void:
	# Pin: same [0.1, 10.0] band as the tick 109 / 110 multipliers.
	# Wider would risk runaway economies; narrower would clip daemon
	# nudges. Catch a regression to either side.
	var src := _read(GAME_STATE)
	# The clamp call must be inside add_gold body. Anchor on the
	# function and search forward.
	var idx: int = src.find("func add_gold")
	assert_gt(idx, -1, "add_gold must exist")
	var next_fn: int = src.find("\nfunc ", idx + 1)
	var body: String = src.substr(idx, next_fn - idx) if next_fn > -1 else src.substr(idx)
	assert_true(body.contains("clampf("),
		"add_gold body must clamp the multiplier — protects against debug overrides + post-load corruption")
	assert_true(body.contains("0.1, 10.0"),
		"add_gold clamp must use [0.1, 10.0] band — matches tick 109 exp_multiplier + tick 110 encounter_rate")


func test_add_gold_with_missing_key_returns_unmodified_amount() -> void:
	# Functional test: remove the key entirely, then call add_gold.
	# Pre-fix this crashed; post-fix the default 1.0 means gold
	# is added at face value.
	var gs_script := load(GAME_STATE)
	var gs = gs_script.new()
	gs.game_constants.erase("gold_multiplier")
	gs.party_gold = 0
	gs.add_gold(100)
	assert_eq(gs.party_gold, 100,
		"add_gold must add the face-value amount when gold_multiplier key is missing — defensive default 1.0")
	gs.queue_free()


func test_add_gold_with_present_multiplier_scales_correctly() -> void:
	# Verify the multiplier path still works when key is present.
	var gs_script := load(GAME_STATE)
	var gs = gs_script.new()
	gs.game_constants["gold_multiplier"] = 1.5
	gs.party_gold = 0
	gs.add_gold(100)
	assert_eq(gs.party_gold, 150,
		"add_gold must scale by gold_multiplier when present")
	gs.queue_free()


func test_add_gold_clamps_runaway_multiplier_to_band_ceiling() -> void:
	# Pathological case: a debug path sets the multiplier to 1000.
	# The clamp must cap at 10.0.
	var gs_script := load(GAME_STATE)
	var gs = gs_script.new()
	gs.game_constants["gold_multiplier"] = 1000.0
	gs.party_gold = 0
	gs.add_gold(100)
	assert_eq(gs.party_gold, 1000,
		"add_gold must clamp 1000x multiplier to 10x — 100 * 10 = 1000")
	gs.queue_free()


func test_add_gold_clamps_zero_multiplier_to_band_floor() -> void:
	# Pathological case: multiplier set to 0. Clamp floor is 0.1.
	var gs_script := load(GAME_STATE)
	var gs = gs_script.new()
	gs.game_constants["gold_multiplier"] = 0.0
	gs.party_gold = 0
	gs.add_gold(100)
	assert_eq(gs.party_gold, 10,
		"add_gold must clamp 0x multiplier to 0.1x floor — 100 * 0.1 = 10")
	gs.queue_free()
