extends GutTest

## Tick 472 follow-up: Bard's swayed-stack counter for the
## bard_hostile_courtier duel win_condition (status_threshold:
## swayed >= 3).
##
## tick 472 wired the win_condition dispatch to prefer a
## `_swayed_stacks` meta counter over the status_effects list count
## (per cowir-battle msg 2014 ask + status doesn't stack via multiple
## add_status calls). This follow-up wires the ability handler side
## so any song landed on a sway-listening target increments the
## counter. Voice-as-mechanic — any song (lullaby / discord /
## battle_hymn / inspiring_melody) counts.
##
## Trigger data (msg 1931 cowir-story): every song offered is a
## voice offered. The fight IS the duet. Landing 3 songs on the
## courtier = talked-down victory.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_song_dispatch_increments_meta() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("target.set_meta(\"_swayed_stacks\", current + 1)"),
		"_execute_support_ability must increment target's _swayed_stacks meta on any song landed on a sway-listening target")


func test_song_gate_covers_bard_songs() -> void:
	# Pin: the increment path fires for ability.type == "song"
	# (Bard's four songs — lullaby, discord, battle_hymn,
	# inspiring_melody — all carry type=song per abilities.json).
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# The check must be `str(ability.get("type", "")) == "song"`.
	assert_true(body.contains("str(ability.get(\"type\", \"\")) == \"song\""),
		"increment path must gate on ability.type == \"song\" so non-song supports don't count")


func test_target_specific_bard_hostile_courtier() -> void:
	# The counter only fires on `bard_hostile_courtier` OR any monster
	# authored with `tracks_sway_stacks: true`. A normal enemy hit with
	# a Bard song must NOT accumulate stacks (would trivialize normal
	# battles).
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_support_ability")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("m_type == \"bard_hostile_courtier\""),
		"target-specific check must hard-code bard_hostile_courtier (spec-lock, not a magic string smell)")
	assert_true(body.contains("tracks_sway_stacks"),
		"target-specific check must also honor tracks_sway_stacks:true for future-authored sway monsters")


func test_all_four_bard_songs_still_type_song() -> void:
	# Regression guard: if abilities.json ever rebrands a Bard song
	# away from type=song, the counter silently stops firing on that
	# ability. Pin all four canonical Bard songs.
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_true(parsed is Dictionary)
	var data: Dictionary = parsed
	for song_id in ["battle_hymn", "lullaby", "discord", "inspiring_melody"]:
		if not data.has(song_id):
			continue
		assert_eq(str((data[song_id] as Dictionary).get("type", "")), "song",
			"%s must remain type=song so it counts as a swayed step" % song_id)


func test_dispatch_reads_swayed_meta_counter() -> void:
	# Downstream contract: tick-472 win_condition dispatch reads the
	# meta counter. Verify the shape hasn't drifted (belt+suspenders
	# with test_win_condition_dispatch_regression).
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _evaluate_custom_win_condition")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("meta_key: String = \"_\" + status_name + \"_stacks\""),
		"win_condition dispatch must construct meta_key as '_<status>_stacks' — Bard's status='swayed' → '_swayed_stacks'")
	assert_true(body.contains("e.has_meta(meta_key)"),
		"win_condition dispatch must prefer the meta counter (Bard path)")
