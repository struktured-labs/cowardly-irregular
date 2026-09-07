extends GutTest

## tick 155 regression: party_leader_index restore from save must
## (a) coerce from JSON's float to int and (b) clamp to a valid
## range against the loaded player_party.size().
##
## Pre-fix:
##   - JSON.parse returns numerics as float. Assigning float to
##     the typed int field works (auto-truncates) but only by
##     accident; explicit int() makes the contract clear.
##   - No range clamp on load. A corrupted save with an
##     out-of-range index (e.g. saved party had 5 members, loaded
##     state has 3) would propagate the bad value. The first
##     consumer of player_party[party_leader_index] would crash.
##
## GameLoop._sync_party_to_game_state clamps the index but only
## fires on overworld menu open / battle exit. Between load and
## the first sync, a crash is reachable.

const GAME_STATE := "res://src/meta/GameState.gd"


func _read(p: String) -> String:
	var t: String = FileAccess.get_file_as_string(p)
	assert_ne(t, "", "Expected %s to be readable" % p)
	return t


# ── Source pins ──────────────────────────────────────────────────────────

func test_load_int_coerces_value() -> void:
	var src := _read(GAME_STATE)
	# Pin: int() wraps the save_data lookup.
	assert_true(src.contains("var raw_idx: int = int(save_data[\"party_leader_index\"])"),
		"_apply_save_data must int() coerce party_leader_index — JSON returns float")
	# Negative pin: the old direct assignment must be gone.
	assert_false(src.contains("party_leader_index = save_data[\"party_leader_index\"]\n"),
		"old direct `party_leader_index = save_data[...]` assignment must be gone")


func test_load_clamps_to_party_size() -> void:
	var src := _read(GAME_STATE)
	assert_true(src.contains("var max_idx: int = max(0, player_party.size() - 1)"),
		"_apply_save_data must compute max_idx based on loaded player_party.size()")
	assert_true(src.contains("party_leader_index = clampi(raw_idx, 0, max_idx)"),
		"_apply_save_data must clamp via clampi")


func test_clamp_uses_loaded_party_size_not_pre_load() -> void:
	# Critical ordering: the clamp must use the JUST-loaded player_party
	# (line ~218) NOT whatever was set before. Otherwise the size could
	# be stale (= pre-load default empty []).
	var src := _read(GAME_STATE)
	var party_load_idx: int = src.find("if save_data.has(\"player_party\"):")
	var leader_load_idx: int = src.find("if save_data.has(\"party_leader_index\"):")
	assert_gt(party_load_idx, -1, "player_party load must exist")
	assert_gt(leader_load_idx, -1, "party_leader_index load must exist")
	assert_lt(party_load_idx, leader_load_idx,
		"player_party MUST be loaded BEFORE party_leader_index — else clamp uses empty array size")


# ── Runtime behavior ────────────────────────────────────────────────────

func test_runtime_out_of_range_index_clamps_to_valid() -> void:
	# Corrupted save scenario: saved party had 5, loaded has 3,
	# saved index is 4. Must clamp to 2 (max valid for size 3).
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	# Snapshot for isolation.
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null
	var pre_leader: int = gs.party_leader_index

	var fake_save: Dictionary = {
		"player_party": [
			{"name": "A", "job_id": "fighter"},
			{"name": "B", "job_id": "cleric"},
			{"name": "C", "job_id": "mage"},
		],
		"party_leader_index": 4,  # out of range for 3-member party
	}
	gs._apply_save_data(fake_save)
	var post_index: int = gs.party_leader_index
	# Restore.
	if pre_party != null:
		gs.player_party = pre_party
	gs.party_leader_index = pre_leader
	assert_eq(post_index, 2,
		"out-of-range index 4 must clamp to 2 (size-1) for a 3-member party — pre-fix it stayed at 4 and would crash on next player_party[party_leader_index] read")


func test_runtime_float_value_coerces_to_int() -> void:
	# JSON.parse returns numeric as float — verify the load handles
	# a literal float gracefully (not just a Python-style int from
	# direct dict construction).
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null
	var pre_leader: int = gs.party_leader_index

	# Pass via JSON to actually exercise the float-from-stringify path.
	var json := JSON.new()
	json.parse(JSON.stringify({
		"player_party": [
			{"name": "A", "job_id": "fighter"},
			{"name": "B", "job_id": "cleric"},
		],
		"party_leader_index": 1,
	}))
	gs._apply_save_data(json.data as Dictionary)
	var post_index: int = gs.party_leader_index
	if pre_party != null:
		gs.player_party = pre_party
	gs.party_leader_index = pre_leader
	assert_eq(post_index, 1,
		"JSON-loaded leader index 1 must round-trip cleanly via int() coercion")


func test_runtime_empty_party_clamps_safely() -> void:
	# Edge case: empty party (size 0). max_idx = max(0, -1) = 0.
	# Index must clamp to 0 without crashing.
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null
	var pre_leader: int = gs.party_leader_index

	var fake_save: Dictionary = {
		"player_party": [],
		"party_leader_index": 3,
	}
	gs._apply_save_data(fake_save)
	var post_index: int = gs.party_leader_index
	if pre_party != null:
		gs.player_party = pre_party
	gs.party_leader_index = pre_leader
	assert_eq(post_index, 0,
		"empty party + any saved index must clamp to 0 — defensive: don't crash via negative max_idx")


# ── Non-regression: in-range values unchanged ───────────────────────────

func test_runtime_in_range_index_passes_through_unchanged() -> void:
	var gs = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs == null:
		pending("GameState autoload missing")
		return
	var pre_party = gs.player_party.duplicate(true) if gs.player_party else null
	var pre_leader: int = gs.party_leader_index

	var fake_save: Dictionary = {
		"player_party": [
			{"name": "A", "job_id": "fighter"},
			{"name": "B", "job_id": "cleric"},
			{"name": "C", "job_id": "mage"},
		],
		"party_leader_index": 1,
	}
	gs._apply_save_data(fake_save)
	var post_index: int = gs.party_leader_index
	if pre_party != null:
		gs.player_party = pre_party
	gs.party_leader_index = pre_leader
	assert_eq(post_index, 1,
		"valid in-range index must pass through unchanged (don't accidentally over-clamp)")
