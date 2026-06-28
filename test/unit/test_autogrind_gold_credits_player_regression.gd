extends GutTest

## tick 342: autogrind battles now credit the player's actual gold
## pool. Pre-fix the entire autogrind pipeline DROPPED gold:
##
##   - HeadlessBattleResolver computed gold (line ~748) and returned
##     it in result["gold_gained"].
##   - GameLoop._resolve_headless_battle IGNORED result["gold_gained"]
##     and called controller.on_battle_ended(..., {}) — empty
##     items_gained dict.
##   - GameLoop._on_autogrind_battle_ended (live path) used items_gained
##     = {} and never computed gold from the live BattleManager.enemy_party.
##   - AutogrindSystem.on_battle_victory tracked total_gold via
##     items_gained.get("gold", 0) — got 0 from the empty dict.
##   - GameState.party_gold NEVER moved.
##
## Symptom: "I autogrind for 30 minutes and the gold counter says I
## earned 5000 G, but my actual party gold didn't change at all."
## The grind_stats display showed 0 because items_gained was empty.
## Both numbers were wrong but the player only saw the second one
## change (it didn't).
##
## Fix has 3 parts:
##   1. Live autogrind path computes gold from enemies + applies
##      gold_multiplier + forwards via items_gained["gold"].
##   2. Headless autogrind path forwards result["gold_gained"] via
##      items_gained["gold"].
##   3. AutogrindSystem.on_battle_victory updates GameState.party_gold
##      directly (bypassing add_gold so the gold_multiplier doesn't
##      apply twice — already applied upstream).

const GAME_LOOP_PATH := "res://src/GameLoop.gd"
const AUTOGRIND_SYSTEM_PATH := "res://src/autogrind/AutogrindSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: live autogrind path computes + forwards gold ────────

func test_live_path_computes_gold() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _on_autogrind_battle_ended")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("gold_gained_live"),
		"live autogrind path must compute gold_gained_live from enemy_party")
	assert_true(body.contains("items_gained[\"gold\"]"),
		"live autogrind path must forward gold via items_gained['gold']")
	assert_true(body.contains("gold_multiplier"),
		"live autogrind gold formula must apply gold_multiplier")


# ── Source pin: headless path forwards gold_gained ──────────────────

func test_headless_path_forwards_gold() -> void:
	var src := _read(GAME_LOOP_PATH)
	var fn_idx: int = src.find("func _resolve_headless_battle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("result.get(\"gold_gained\""),
		"headless path must pick up result.gold_gained")
	assert_true(body.contains("{\"gold\": gold_gained_headless}"),
		"headless path must forward gold via items_gained dict to on_battle_ended")


# ── Source pin: AutogrindSystem credits party_gold ──────────────────

func test_autogrind_system_credits_party_gold() -> void:
	var src := _read(AUTOGRIND_SYSTEM_PATH)
	var fn_idx: int = src.find("func on_battle_victory")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("party_gold"),
		"on_battle_victory must credit GameState.party_gold (was display-only pre-fix)")
	assert_true(body.contains("gs.party_gold += scaled_gold"),
		"must add scaled_gold to party_gold directly (skip add_gold to avoid double-multiply)")


# ── Behavioral: end-to-end gold flow updates party_gold ─────────────

func test_on_battle_victory_updates_party_gold() -> void:
	assert_not_null(GameState, "GameState autoload required")
	assert_not_null(AutogrindSystem, "AutogrindSystem autoload required")
	if GameState == null or AutogrindSystem == null:
		return

	# Snapshot and reset.
	var prior_gold: int = GameState.party_gold
	GameState.party_gold = 100
	AutogrindSystem._grind_stats["total_gold"] = 0
	# Provide a non-zero reward_scale by setting current_region_id empty
	# (yield_mult defaults to 1.0) and clearing crack penalty cache.
	AutogrindSystem.current_region_id = ""
	# Need a non-empty grind_party so the function doesn't early-return.
	# It iterates members for gain_job_exp — empty party is fine for the
	# gold-credit assertion path.
	AutogrindSystem.grind_party = []

	# Drive: pass items_gained with a known gold amount.
	AutogrindSystem.on_battle_victory(0, {"gold": 50})

	# party_gold should have increased by ~50 * reward_scale * 1.0.
	# (reward_scale = 1.0 since yield_mult=1.0 and crack_penalty=0)
	assert_eq(GameState.party_gold, 150,
		"party_gold must have increased by the gold amount (50) — pre-fix it stayed at 100 because the gold-credit path didn't exist")

	# Cleanup.
	GameState.party_gold = prior_gold
	AutogrindSystem._grind_stats["total_gold"] = 0
