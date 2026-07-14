extends GutTest

## tick 403: dungeon_skip (Skiptrotter warp_to_boss ability) sets
## meta_dungeon_skip_pending flag. Pre-fix the 30 MP cast fell
## through to `_:` push_warning. Future dungeon-warp wiring reads
## the flag on next exploration return.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func test_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"dungeon_skip\":")
	assert_gt(arm_idx, -1, "dungeon_skip arm must exist")
	var window: String = src.substr(arm_idx, 600)
	assert_true(window.contains("meta_dungeon_skip_pending"),
		"dungeon_skip arm must write meta_dungeon_skip_pending flag")


func test_data_authors_dungeon_skip() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("warp_to_boss"))
	assert_eq(str(data["warp_to_boss"].get("meta_effect", "")), "dungeon_skip")


func test_flag_writes_at_runtime() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null or not GameState:
		pending("BattleManager + GameState required")
		return
	GameState.game_constants["meta_dungeon_skip_pending"] = false
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Skiptrotter", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster)
	var ability: Dictionary = {
		"id": "test_warp_to_boss",
		"meta_effect": "dungeon_skip",
	}
	bm._execute_meta_ability(caster, ability, [])
	assert_true(bool(GameState.game_constants.get("meta_dungeon_skip_pending", false)),
		"meta_dungeon_skip_pending must be true after the cast")
	GameState.game_constants["meta_dungeon_skip_pending"] = false
