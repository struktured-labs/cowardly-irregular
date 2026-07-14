extends GutTest

## tick 398: corrupt_save meta_effect (save_deletion ability) now
## applies its authored corruption_amount.
##
## Pre-fix the meta_effect fell through to `_:` push_warning. The
## save_deletion ability also has damage_multiplier=3.0 magic damage
## that routes elsewhere, but the corruption side-effect (the whole
## point of the "delete the player's save" terror move) silently
## dropped on the floor.
##
## Routes through GameState.add_corruption which clamps to [0, 1]
## and fires save_corrupted on increase — engine-level pieces
## already exist, just needed wiring.

const BATTLE_MANAGER_PATH := "res://src/battle/BattleManager.gd"


func test_arm_exists() -> void:
	var src: String = FileAccess.get_file_as_string(BATTLE_MANAGER_PATH)
	assert_true(src.contains("\"corrupt_save\":"),
		"BattleManager._execute_meta_ability must have a corrupt_save arm")
	# Pin the GameState.add_corruption call.
	var arm_idx: int = src.find("\"corrupt_save\":")
	var window: String = src.substr(arm_idx, 800)
	assert_true(window.contains("GameState.add_corruption(corruption_amount)"),
		"corrupt_save arm must call GameState.add_corruption with the authored amount")


func test_data_authors_corrupt_save() -> void:
	var raw: String = FileAccess.get_file_as_string("res://data/abilities.json")
	var parsed: Variant = JSON.parse_string(raw)
	var data: Dictionary = parsed
	assert_true(data.has("save_deletion"))
	assert_eq(str(data["save_deletion"].get("meta_effect", "")), "corrupt_save")
	# Must still author a non-zero corruption_amount for the fix to do anything.
	assert_gt(float(data["save_deletion"].get("corruption_amount", 0.0)), 0.0,
		"save_deletion must still author a positive corruption_amount")


func test_corrupt_save_raises_corruption() -> void:
	var bm = Engine.get_main_loop().root.get_node_or_null("BattleManager")
	if bm == null:
		pending("BattleManager autoload required")
		return
	if not GameState:
		pending("GameState autoload required")
		return
	var prior_corruption: float = GameState.corruption_level
	GameState.corruption_level = 0.0
	# Cast the meta ability synthetically.
	var c_script: GDScript = load("res://src/battle/Combatant.gd")
	var caster: Combatant = c_script.new()
	caster.initialize({"name": "Necromancer", "max_hp": 100, "max_mp": 100,
		"attack": 10, "defense": 10, "magic": 10, "speed": 10})
	add_child_autofree(caster)
	var ability: Dictionary = {
		"id": "test_save_deletion",
		"meta_effect": "corrupt_save",
		"corruption_amount": 0.3,
	}
	bm._execute_meta_ability(caster, ability, [])
	# Pre-fix corruption stayed at 0.0; post-fix it should rise.
	assert_gt(GameState.corruption_level, 0.0,
		"corruption_level must rise after corrupt_save meta_effect — pre-fix the cast silently fizzled")
	# Restore.
	GameState.corruption_level = prior_corruption
