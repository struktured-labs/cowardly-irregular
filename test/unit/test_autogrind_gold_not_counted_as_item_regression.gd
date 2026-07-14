extends GutTest

## tick 343: AutogrindSystem.on_battle_victory's item-tracking loop
## skips the "gold" key.
##
## Pre-fix tick 342 added items_gained["gold"] as the channel for
## passing autogrind gold from GameLoop to AutogrindSystem. But the
## item-tracking loop at line ~499 treated "gold" like any other item
## ID and pushed the gold amount into total_items_gained:
##
##   for item_id in items_gained:
##       total_items_gained[item_id] += quantity
##
## AutogrindController.get_grind_stats counts total_items_gained
## values as item drops (line ~568). So after a single autogrind
## battle that produced 50 gold, the "items obtained" counter would
## report 50 items. After a 30-min session: thousands of "gold" items.
##
## Fix: filter out the "gold" key from the item-tracking loop. The
## party_gold credit path below handles gold separately.

const AUTOGRIND_SYSTEM_PATH := "res://src/autogrind/AutogrindSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


# ── Source pin: gold filter in the loop ─────────────────────────────

func test_gold_filter_in_loop() -> void:
	var src := _read(AUTOGRIND_SYSTEM_PATH)
	var fn_idx: int = src.find("func on_battle_victory")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Find the for-loop block.
	var loop_idx: int = body.find("for item_id in items_gained:")
	assert_gt(loop_idx, -1)
	var loop_body: String = body.substr(loop_idx, 400)
	assert_true(loop_body.contains("if item_id == \"gold\":"),
		"item-tracking loop must explicitly skip 'gold' — tick 342's gold channel uses items_gained but it's not a real item")
	assert_true(loop_body.contains("continue"),
		"the gold guard must be a continue (skip), not a noop")


# ── Behavioral: gold doesn't inflate total_items_gained ─────────────

func test_gold_does_not_inflate_items_gained() -> void:
	assert_not_null(AutogrindSystem, "AutogrindSystem autoload required")
	if AutogrindSystem == null:
		return

	# Snapshot.
	var prior_items: Dictionary = AutogrindSystem.total_items_gained.duplicate()
	var prior_gold: int = GameState.party_gold if GameState else 0
	AutogrindSystem.total_items_gained = {}
	AutogrindSystem.grind_party = []
	AutogrindSystem.current_region_id = ""
	AutogrindSystem._grind_stats["total_gold"] = 0
	if GameState:
		GameState.party_gold = 0

	# Drive: pass items_gained with gold AND a real item.
	AutogrindSystem.on_battle_victory(0, {"gold": 500, "potion": 2})

	# total_items_gained must contain "potion" but NOT "gold".
	assert_eq(int(AutogrindSystem.total_items_gained.get("potion", 0)), 2,
		"real items (potion) must still be tracked")
	assert_false(AutogrindSystem.total_items_gained.has("gold"),
		"'gold' key must NOT be in total_items_gained — would inflate the items counter")

	# Cleanup.
	AutogrindSystem.total_items_gained = prior_items
	AutogrindSystem._grind_stats["total_gold"] = 0
	if GameState:
		GameState.party_gold = prior_gold


# ── Behavioral: gold still credits party_gold (tick 342 still works) ─

func test_gold_still_credits_party_gold_after_filter() -> void:
	# Regression guard: the filter must skip the items loop but NOT
	# skip the party_gold update below.
	assert_not_null(GameState, "GameState autoload required")
	assert_not_null(AutogrindSystem, "AutogrindSystem autoload required")
	if GameState == null or AutogrindSystem == null:
		return

	var prior_gold: int = GameState.party_gold
	GameState.party_gold = 0
	AutogrindSystem.grind_party = []
	AutogrindSystem.current_region_id = ""
	AutogrindSystem._grind_stats["total_gold"] = 0

	AutogrindSystem.on_battle_victory(0, {"gold": 100})

	assert_eq(GameState.party_gold, 100,
		"party_gold must still receive the gold (tick 342 fix must not regress)")

	GameState.party_gold = prior_gold
	AutogrindSystem._grind_stats["total_gold"] = 0
