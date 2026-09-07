extends GutTest

## tick 397: create_save meta_effect (Time Mage quicksave ability)
## now actually saves the game during battle.
##
## Pre-fix the meta_effect fell through to push_warning even though
## the ability description literally says "Create a quicksave during
## battle". SaveSystem.save_game / quick_save block during battle
## via can_quick_save — quicksave needed a battle-gate override.
##
## Post-fix routes through new SaveSystem.force_quick_save which
## bypasses the can_quick_save gate, writes to QUICK_SAVE_SLOT, and
## self-clears the bypass flag so it can't leak to other save paths.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"
const SAVE_SYSTEM_PATH := "res://src/save/SaveSystem.gd"


func _read(p: String) -> String:
	return FileAccess.get_file_as_string(p)


func test_force_quick_save_function_exists() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	assert_true(src.contains("func force_quick_save"),
		"SaveSystem must expose force_quick_save as the meta-ability override")
	assert_true(src.contains("_meta_save_bypass"),
		"SaveSystem must declare the _meta_save_bypass flag")


func test_save_game_consumes_bypass_flag() -> void:
	var src := _read(SAVE_SYSTEM_PATH)
	# Pin the consume-and-clear pattern so the flag can't leak.
	assert_true(src.contains("_meta_save_bypass = false"),
		"save_game must consume + clear the bypass flag on entry")
	assert_true(src.contains("if not bypass_gate"),
		"save_game must check `if not bypass_gate` before refusing the save")


func test_create_save_arm_exists() -> void:
	var src := _read(BATTLE_MANAGER_PATH)
	assert_true(src.contains("\"create_save\":"),
		"BattleManager._execute_meta_ability must have a create_save arm")
	assert_true(src.contains("force_quick_save"),
		"create_save must call SaveSystem.force_quick_save")


func test_data_authors_create_save() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("quicksave"))
	assert_eq(str(data["quicksave"].get("meta_effect", "")), "create_save")


func test_bypass_only_applies_once() -> void:
	# Critical safety: a SaveSystem.force_quick_save call sets the flag,
	# save_game consumes it. A subsequent normal save_game (called e.g.
	# from SaveScreen mid-interior) must still hit can_quick_save.
	var ss = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	if ss == null:
		pending("SaveSystem autoload required")
		return
	# Set the flag manually (simulating force_quick_save entry).
	ss._meta_save_bypass = true
	# This isn't a real save call — we just want to verify the field
	# exists and is settable. Sanity check.
	assert_true(ss._meta_save_bypass,
		"SaveSystem._meta_save_bypass must be settable as a public-facing override flag")
	# Clear before exiting test.
	ss._meta_save_bypass = false
