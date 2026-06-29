extends GutTest

## tick 402: sequence_break + autobattle_editor meta_effects now
## write their respective flags and surface battle log messages.
##
## Pre-fix both fell through to `_:` push_warning — sequence_break
## (50 MP) and create_autobattle_script (20 MP) silently fizzled.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func test_sequence_break_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"sequence_break\":")
	assert_gt(arm_idx, -1)
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("meta_sequence_break_pending"),
		"sequence_break arm must write meta_sequence_break_pending flag")
	assert_true(window.contains("GameState.add_corruption(corruption_risk)"),
		"sequence_break arm must apply the authored corruption_risk")


func test_autobattle_editor_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	var arm_idx: int = src.find("\"autobattle_editor\":")
	assert_gt(arm_idx, -1)
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("meta_autobattle_editor_requested"),
		"autobattle_editor arm must write meta_autobattle_editor_requested flag")


func test_data_authors_both_effects() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("sequence_break"))
	assert_eq(str(data["sequence_break"].get("meta_effect", "")), "sequence_break")
	assert_true(data.has("create_autobattle_script"))
	assert_eq(str(data["create_autobattle_script"].get("meta_effect", "")), "autobattle_editor")


func test_sequence_break_writes_flag_at_runtime() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null or not GameState:
		pending("BattleManager + GameState required")
		return
	GameState.game_constants["meta_sequence_break_pending"] = false
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Skiptrotter", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster)
	var ability: Dictionary = {
		"id": "test_sequence_break",
		"meta_effect": "sequence_break",
		"corruption_risk": 0.0,
	}
	bm._execute_meta_ability(caster, ability, [])
	assert_true(bool(GameState.game_constants.get("meta_sequence_break_pending", false)),
		"meta_sequence_break_pending must be true after the cast")
	GameState.game_constants["meta_sequence_break_pending"] = false


func test_autobattle_editor_writes_flag_at_runtime() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null or not GameState:
		pending("BattleManager + GameState required")
		return
	GameState.game_constants["meta_autobattle_editor_requested"] = false
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Scriptweaver", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster)
	var ability: Dictionary = {
		"id": "test_autobattle_editor",
		"meta_effect": "autobattle_editor",
	}
	bm._execute_meta_ability(caster, ability, [])
	assert_true(bool(GameState.game_constants.get("meta_autobattle_editor_requested", false)),
		"meta_autobattle_editor_requested must be true after the cast")
	GameState.game_constants["meta_autobattle_editor_requested"] = false
