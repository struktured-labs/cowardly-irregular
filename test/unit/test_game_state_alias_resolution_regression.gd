extends GutTest

## Regression: legacy job aliases (white_mage / black_mage / thief) must
## be resolved to canonical IDs (cleric / mage / rogue) when restoring
## GameState.player_party via from_dict / _apply_save_data — not just at
## the SaveSystem._deserialize_party layer.
##
## Bug shape: SaveSystem._apply_save_data called _deserialize_party FIRST
## (which resolved aliases) and then immediately called
## GameState.from_dict(data["game_state"]) (which overwrote player_party
## with raw aliased IDs from game_state.player_party — the alias
## resolution at the SaveSystem layer was silently undone). Old saves
## therefore continued to render with stale `white_mage` sprites/labels
## despite the SaveSystem fix.
##
## Fix: push the alias resolution into GameState._apply_save_data so it
## happens regardless of who calls from_dict (SaveSystem, time-rewind
## restore, save-migration tooling, etc.).
##
## Tests:
##   • from_dict on a legacy-aliased player_party emits canonical IDs.
##   • Modern saves with already-canonical IDs round-trip unchanged.
##   • Mixed party (legacy + canonical) resolves correctly per-entry.
##   • secondary_job_id and the legacy "job" field are both resolved.
##   • SaveSystem-load order shape: from_dict still writes player_party
##     last, so even if _deserialize_party didn't run, resolution holds.

const GAME_STATE_PATH := "res://src/meta/GameState.gd"


func _read(path: String) -> String:
	var text: String = FileAccess.get_file_as_string(path)
	assert_ne(text, "", "Expected %s to be readable" % path)
	return text


# ── Behavioural via the live autoload ─────────────────────────────────────────

func _gs() -> Node:
	var gs := get_node_or_null("/root/GameState")
	assert_not_null(gs, "GameState autoload must be reachable")
	return gs


func _snapshot() -> Dictionary:
	# Snapshot player_party so we can restore after each behavioural test.
	# (The autoload is shared with the rest of the suite.)
	var gs := _gs()
	return {"player_party": gs.player_party.duplicate(true)}


func _restore(snap: Dictionary) -> void:
	var gs := _gs()
	var typed: Array[Dictionary] = []
	for e in snap.get("player_party", []):
		if e is Dictionary:
			typed.append(e.duplicate(true))
	gs.player_party = typed


func test_legacy_job_aliases_resolved_to_canonical_on_from_dict() -> void:
	var gs := _gs()
	var snap := _snapshot()
	gs.from_dict({
		"player_party": [
			{"job_id": "white_mage", "name": "Cleric"},
			{"job_id": "black_mage", "name": "Mage"},
			{"job_id": "thief",      "name": "Rogue"},
			{"job_id": "fighter",    "name": "Fighter"},
		],
	})
	assert_eq(gs.player_party.size(), 4, "all 4 party entries must restore")
	assert_eq(gs.player_party[0].get("job_id", ""), "cleric",
		"white_mage must resolve to cleric")
	assert_eq(gs.player_party[1].get("job_id", ""), "mage",
		"black_mage must resolve to mage")
	assert_eq(gs.player_party[2].get("job_id", ""), "rogue",
		"thief must resolve to rogue")
	assert_eq(gs.player_party[3].get("job_id", ""), "fighter",
		"fighter must pass through unchanged")
	_restore(snap)


func test_modern_canonical_ids_round_trip_unchanged() -> void:
	var gs := _gs()
	var snap := _snapshot()
	gs.from_dict({
		"player_party": [
			{"job_id": "cleric", "name": "C"},
			{"job_id": "mage",   "name": "M"},
			{"job_id": "rogue",  "name": "R"},
			{"job_id": "bard",   "name": "B"},
		],
	})
	for i in range(4):
		var expected: String = ["cleric", "mage", "rogue", "bard"][i]
		assert_eq(gs.player_party[i].get("job_id", ""), expected,
			"canonical %s must round-trip unchanged" % expected)
	_restore(snap)


func test_secondary_job_id_also_resolved() -> void:
	var gs := _gs()
	var snap := _snapshot()
	gs.from_dict({
		"player_party": [
			{"job_id": "fighter", "secondary_job_id": "white_mage"},
			{"job_id": "fighter", "secondary_job_id": "thief"},
			{"job_id": "fighter", "secondary_job_id": ""},
		],
	})
	assert_eq(gs.player_party[0].get("secondary_job_id", ""), "cleric",
		"secondary white_mage must resolve to cleric")
	assert_eq(gs.player_party[1].get("secondary_job_id", ""), "rogue",
		"secondary thief must resolve to rogue")
	assert_eq(gs.player_party[2].get("secondary_job_id", ""), "",
		"empty secondary_job_id must round-trip empty")
	_restore(snap)


func test_legacy_job_string_field_resolved() -> void:
	# The old metadata had a top-level "job" string (not "job_id") that
	# get_party_summary still reads for save-slot UI.
	var gs := _gs()
	var snap := _snapshot()
	gs.from_dict({
		"player_party": [{"job_id": "fighter", "job": "white_mage"}],
	})
	assert_eq(gs.player_party[0].get("job", ""), "cleric",
		"legacy top-level 'job' string field must resolve too")
	_restore(snap)


func test_mixed_party_resolves_per_entry() -> void:
	var gs := _gs()
	var snap := _snapshot()
	gs.from_dict({
		"player_party": [
			{"job_id": "white_mage"},
			{"job_id": "cleric"},
			{"job_id": "thief"},
			{"job_id": "bard"},
		],
	})
	assert_eq(gs.player_party[0].get("job_id", ""), "cleric")
	assert_eq(gs.player_party[1].get("job_id", ""), "cleric")
	assert_eq(gs.player_party[2].get("job_id", ""), "rogue")
	assert_eq(gs.player_party[3].get("job_id", ""), "bard")
	_restore(snap)


func test_non_dictionary_party_entries_are_skipped() -> void:
	# Defense: corrupted save with mixed Variant types in player_party must
	# not crash; non-dict entries are filtered, dict entries still resolve.
	var gs := _gs()
	var snap := _snapshot()
	gs.from_dict({
		"player_party": [
			{"job_id": "white_mage"},
			"not a dict",
			null,
			{"job_id": "thief"},
		],
	})
	assert_eq(gs.player_party.size(), 2,
		"non-dict entries must be dropped, leaving 2 valid party members")
	assert_eq(gs.player_party[0].get("job_id", ""), "cleric")
	assert_eq(gs.player_party[1].get("job_id", ""), "rogue")
	_restore(snap)


# ── Source pin ────────────────────────────────────────────────────────────────

func test_apply_save_data_calls_resolve_job_id_for_player_party() -> void:
	# Pin the wiring so the fix can't silently regress (e.g. if someone
	# refactors _apply_save_data and drops the resolver loop).
	var text := _read(GAME_STATE_PATH)
	var idx := text.find("if save_data.has(\"player_party\")")
	assert_gt(idx, -1, "_apply_save_data must handle the 'player_party' key")
	# Slice through the next `if save_data.has(...)` so we stay inside the
	# player_party block.
	var rest := text.substr(idx)
	var next_block := rest.find("\n\tif save_data.has(", 1)
	var block := rest.substr(0, next_block) if next_block > -1 else rest
	assert_true(block.contains("resolve_job_id"),
		"player_party deserialization must call resolve_job_id (the fix)")
	# Either path form is acceptable: literal "/root/JobSystem" via get_node_or_null
	# OR the autoload-singleton tree.root.get_node_or_null("JobSystem") shape.
	var resolves_autoload := block.contains("\"JobSystem\"") \
		or block.contains("\"/root/JobSystem\"")
	assert_true(resolves_autoload,
		"player_party deserialization must look up the JobSystem autoload")
