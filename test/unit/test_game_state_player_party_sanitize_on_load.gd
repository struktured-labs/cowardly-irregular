extends GutTest

## tick 163 regression: GameState._apply_save_data must sanitize
## per-entry data on player_party load:
##
##   1. Cap at MAX_PARTY_SIZE (5 — CLAUDE.md strict-5 party).
##      Pre-fix a corrupted save with 99 entries would propagate.
##      Strict-5 is canon — positions 0-4 are Fighter/Cleric/Mage/
##      Rogue/Bard. Anything beyond is corruption.
##
##   2. Sanitize per-entry nested `inventory` dict. The Combatant
##      tick 162 fix sanitizes when from_dict runs on a Combatant
##      instance — but ShopScene reads `game_state.player_party[0]
##      .get("inventory", {})` DIRECTLY, bypassing the Combatant.
##      So a negative-quantity entry leaks to the shop UI without
##      this fix.
##
##   3. Drop newest entries (pop_back) when oversized — preserves
##      the canonical starter roster at positions 0-4.

const GAME_STATE := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_load_caps_party_at_max_size() -> void:
	var src := _read(GAME_STATE)
	# Pin: MAX_PARTY_SIZE constant + while-loop trim.
	assert_true(src.contains("const MAX_PARTY_SIZE: int = 5"),
		"player_party load must declare MAX_PARTY_SIZE=5 (CLAUDE.md strict-5)")
	assert_true(src.contains("while typed_party.size() > MAX_PARTY_SIZE:"),
		"player_party load must enforce MAX_PARTY_SIZE via while-loop trim")


func test_trim_drops_back_not_front() -> void:
	# Strict-5 means positions 0-4 are canonical starters.
	# pop_front would drop the canonical roster.
	var src := _read(GAME_STATE)
	# Find the trim loop and verify pop_back.
	var loop_idx: int = src.find("while typed_party.size() > MAX_PARTY_SIZE:")
	assert_gt(loop_idx, -1, "trim loop must exist")
	var window: String = src.substr(loop_idx, 400)
	assert_true(window.contains("typed_party.pop_back()"),
		"trim must pop_back — preserves canonical 0-4 roster, drops corrupted extras")
	assert_false(window.contains("typed_party.pop_front()"),
		"pop_front would drop the canonical roster — must be pop_back")


func test_load_sanitizes_per_entry_inventory() -> void:
	var src := _read(GAME_STATE)
	var idx: int = src.find("if save_data.has(\"player_party\"):")
	var next_block: int = src.find("if save_data.has(\"party_leader_index\"):")
	assert_gt(idx, -1)
	assert_gt(next_block, -1)
	var body: String = src.substr(idx, next_block - idx)
	# Pin: per-entry inventory sanitize block.
	assert_true(body.contains("if copied.has(\"inventory\") and copied[\"inventory\"] is Dictionary:"),
		"per-entry load must check for inventory presence + type")
	assert_true(body.contains("var qty: int = int(raw_inv[item_id])"),
		"per-entry inventory must int() coerce quantity")
	assert_true(body.contains("if qty <= 0:"),
		"per-entry inventory must filter ≤ 0 quantities")
	assert_true(body.contains("if key == \"\":"),
		"per-entry inventory must filter empty keys")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_99_party_caps_at_5() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null
	var pre_leader: int = gs.party_leader_index

	var oversized: Array = []
	for i in 99:
		oversized.append({"name": "PC_%d" % i, "job_id": "fighter"})
	gs._apply_save_data({"player_party": oversized})
	var post_size: int = gs.player_party.size()
	# Drop from the back: positions 0-4 should survive (PC_0..PC_4).
	var post_first_name: String = str(gs.player_party[0].get("name", ""))
	var post_last_name: String = str(gs.player_party[4].get("name", ""))

	if pre_party != null:
		gs.player_party = pre_party
	gs.party_leader_index = pre_leader

	assert_eq(post_size, 5,
		"99 party members must cap at MAX_PARTY_SIZE=5")
	assert_eq(post_first_name, "PC_0",
		"position 0 must be PC_0 (front preserved — pop_back trims tail)")
	assert_eq(post_last_name, "PC_4",
		"position 4 must be PC_4 (last canonical slot survives)")


func test_runtime_negative_inventory_quantity_filtered_on_party_entry() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null

	gs._apply_save_data({
		"player_party": [
			{
				"name": "Hero",
				"job_id": "fighter",
				"inventory": {"potion": -5, "ether": 3},
			},
		],
	})
	var loaded_inv: Dictionary = gs.player_party[0]["inventory"]
	if pre_party != null:
		gs.player_party = pre_party

	assert_false(loaded_inv.has("potion"),
		"negative quantity must be filtered from per-entry inventory")
	assert_eq(int(loaded_inv.get("ether", 0)), 3,
		"valid sibling entry survives sanitization")


func test_runtime_empty_inventory_key_filtered_on_party_entry() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null

	gs._apply_save_data({
		"player_party": [
			{
				"name": "Hero",
				"job_id": "fighter",
				"inventory": {"": 7, "potion": 3},
			},
		],
	})
	var loaded_inv: Dictionary = gs.player_party[0]["inventory"]
	if pre_party != null:
		gs.player_party = pre_party

	assert_false(loaded_inv.has(""),
		"empty-string key must be filtered")
	assert_eq(int(loaded_inv.get("potion", 0)), 3,
		"valid sibling entry survives")


# ── Non-regression ──────────────────────────────────────────────────────

func test_runtime_normal_5_party_load_passes_through() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null

	gs._apply_save_data({
		"player_party": [
			{"name": "Fighter", "job_id": "fighter"},
			{"name": "Cleric", "job_id": "cleric"},
			{"name": "Mage", "job_id": "mage"},
			{"name": "Rogue", "job_id": "rogue"},
			{"name": "Bard", "job_id": "bard"},
		],
	})
	var post_size: int = gs.player_party.size()
	if pre_party != null:
		gs.player_party = pre_party

	assert_eq(post_size, 5,
		"normal 5-member party load passes through unchanged")


func test_runtime_non_dict_entries_filtered() -> void:
	# Pre-tick-163 filter (line 230 `if entry is Dictionary`)
	# must still drop non-Dictionary entries.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null

	gs._apply_save_data({
		"player_party": [
			"not_a_dict",
			{"name": "Hero", "job_id": "fighter"},
			42,
			null,
		],
	})
	var post_size: int = gs.player_party.size()
	if pre_party != null:
		gs.player_party = pre_party

	assert_eq(post_size, 1,
		"non-Dictionary entries filtered, only the valid 1 survives")
