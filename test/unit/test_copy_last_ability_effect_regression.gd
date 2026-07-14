extends GutTest

## tick 406: copy_last_ability (mimic_ability) replays the last
## ability cast by any combatant this battle.
##
## Pre-fix the meta_effect fell through to `_:` push_warning. 10 MP
## burned for nothing.
##
## Implementation: BattleManager tracks _last_ability_cast_id +
## _last_ability_cast_caster. _execute_ability updates them for any
## non-mimic cast. The copy_last_ability arm replays the tracked
## ability via _execute_ability with the mimic caster as the source.
## Skipping mimic_ability itself in the tracker prevents a mimic of
## a mimic from infinite-recursing.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_tracking_field_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("var _last_ability_cast_id"),
		"BattleManager must declare _last_ability_cast_id")
	assert_true(src.contains("var _last_ability_cast_caster"),
		"BattleManager must declare _last_ability_cast_caster")


func test_tracker_reset_on_start_battle() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func start_battle")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_last_ability_cast_id = \"\""),
		"start_battle must reset _last_ability_cast_id to empty")
	assert_true(body.contains("_last_ability_cast_caster = null"),
		"start_battle must reset _last_ability_cast_caster to null")


func test_execute_ability_records_cast() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var fn_idx: int = src.find("func _execute_ability(caster: Combatant, ability_id: String")
	assert_gt(fn_idx, -1)
	var next_fn: int = src.find("\nfunc ", fn_idx + 1)
	var body: String = src.substr(fn_idx, next_fn - fn_idx) if next_fn > 0 else src.substr(fn_idx)
	assert_true(body.contains("_last_ability_cast_id = ability_id"),
		"_execute_ability must record the cast for the mimic path")
	assert_true(body.contains("if ability_id != \"mimic_ability\""),
		"recording must skip mimic_ability itself to prevent infinite recursion")


func test_copy_last_ability_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"copy_last_ability\":")
	assert_gt(arm_idx, -1, "copy_last_ability arm must exist")
	var window: String = src.substr(arm_idx, 1200)
	assert_true(window.contains("_last_ability_cast_id"),
		"copy_last_ability arm must read the tracked ability id")
	assert_true(window.contains("_execute_ability(caster, _last_ability_cast_id, targets)"),
		"copy_last_ability arm must replay via _execute_ability")


func test_data_authors_copy_last_ability() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("mimic_ability"))
	assert_eq(str(data["mimic_ability"].get("effect", "")), "copy_last_ability")
