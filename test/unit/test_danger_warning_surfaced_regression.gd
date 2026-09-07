extends GutTest

## tick 420: monsters.json `very_dangerous` (script_error) and
## `extremely_dangerous` (permadeath_reaper) flags are authored as
## player warnings but were never read in code. EncounterSystem
## copied them into enemy data; nothing consumed them.
##
## start_battle now scans the enemy party for the flags and emits a
## distinct battle_log line. Highest tier (extremely > very) wins
## when multiple dangerous enemies share a party.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_start_battle_scans_danger_flags() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Pin both flag reads.
	assert_true(body.contains("data.get(\"extremely_dangerous\", false)"),
		"start_battle must read the extremely_dangerous flag from monsters.json")
	assert_true(body.contains("data.get(\"very_dangerous\", false)"),
		"start_battle must read the very_dangerous flag")
	# Pin the warning emit.
	assert_true(body.contains("EXTREME DANGER"),
		"start_battle must emit an EXTREME DANGER battle log line")
	assert_true(body.contains("⚠ Danger:") or body.contains("Danger:"),
		"start_battle must emit a Danger warning for very_dangerous enemies")


func test_data_still_authors_danger_monsters() -> void:
	# Sanity: the canonical flagged monsters still author the flags.
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var data: Dictionary = parsed
	# script_error → very_dangerous
	if data.has("script_error"):
		assert_true(bool(data["script_error"].get("very_dangerous", false)),
			"script_error must still author very_dangerous=true (fix relies on this)")
	# permadeath_reaper → extremely_dangerous
	if data.has("permadeath_reaper"):
		assert_true(bool(data["permadeath_reaper"].get("extremely_dangerous", false)),
			"permadeath_reaper must still author extremely_dangerous=true")


func test_highest_tier_wins() -> void:
	# Pin source ordering: max_danger compares against the existing
	# value so a second very_dangerous in the same party doesn't
	# overwrite an extremely_dangerous already detected.
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle(")
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# extremely tier uses < 2, very tier uses < 1
	assert_true(body.contains("max_danger < 2"),
		"extremely_dangerous detection must gate on max_danger < 2")
	assert_true(body.contains("max_danger < 1"),
		"very_dangerous detection must gate on max_danger < 1 (doesn't downgrade an extreme)")
