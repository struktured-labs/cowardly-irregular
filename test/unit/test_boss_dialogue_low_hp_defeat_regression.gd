extends GutTest

## tick 428: BattleScene wires the boss `low_hp` and `defeat`
## dialogue keys from monsters.json.
##
## Pre-fix BattleEnemySpawner copied the full `dialogue` dict into
## _boss_dialogue_data but only the `intro` key was consumed (the
## intro line at battle start). cave_rat_king, the 4 W1 dragons,
## optimization_itself, etc. all author intro+low_hp+defeat triples
## — players never saw the low_hp ("I'm wounded") or defeat
## ("you've bested me") lines regardless of fight state.

const BATTLE_SCENE_PATH := "res://src/battle/BattleScene.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_low_hp_latch_declared() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	assert_true(src.contains("var _boss_low_hp_spoken: bool = false"),
		"BattleScene must declare _boss_low_hp_spoken latch")
	assert_true(src.contains("var _boss_defeat_spoken: bool = false"),
		"BattleScene must declare _boss_defeat_spoken latch")


func test_latches_reset_on_battle_start() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	# Find the battle-start music block where _masterite_phase2_swapped resets.
	var reset_idx: int = src.find("_masterite_phase2_swapped = false")
	assert_gt(reset_idx, -1)
	# The boss-dialogue latch resets should appear NEAR the
	# masterite_phase2_swapped reset (same battle-start block).
	var window: String = src.substr(reset_idx, 500)
	assert_true(window.contains("_boss_low_hp_spoken = false"),
		"_boss_low_hp_spoken must reset at battle start")
	assert_true(window.contains("_boss_defeat_spoken = false"),
		"_boss_defeat_spoken must reset at battle start")


func test_low_hp_handler_in_damage_dealt() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = src.find("func _on_damage_dealt(")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	# Pin the latch-and-fire pattern.
	assert_true(body.contains("_boss_dialogue_data.has(\"low_hp\")"),
		"_on_damage_dealt must check for low_hp dialogue")
	assert_true(body.contains("not _boss_low_hp_spoken"),
		"_on_damage_dealt must gate on the not-spoken latch")
	assert_true(body.contains("_boss_low_hp_spoken = true"),
		"_on_damage_dealt must set the latch after firing (one-shot per battle)")


func test_defeat_handler_in_battle_ended() -> void:
	var src := _read(BATTLE_SCENE_PATH)
	var fn_idx: int = src.find("func _on_battle_ended(")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_boss_dialogue_data.has(\"defeat\")"),
		"_on_battle_ended must check for defeat dialogue")
	assert_true(body.contains("victory and not _boss_defeat_spoken"),
		"_on_battle_ended must gate on victory + not-spoken latch")


func test_data_still_authors_low_hp_and_defeat() -> void:
	# Sanity: cave_rat_king (W1 first boss) authors both keys.
	var raw: String = FileAccess.get_file_as_string("res://data/monsters.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("cave_rat_king"))
	var d: Dictionary = data["cave_rat_king"].get("dialogue", {})
	assert_true(d.has("low_hp"),
		"cave_rat_king must still author dialogue.low_hp")
	assert_true(d.has("defeat"),
		"cave_rat_king must still author dialogue.defeat")
