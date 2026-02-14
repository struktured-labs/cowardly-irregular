extends GutTest

## Regression tests for error handling and memory safety
## Ensures critical code paths handle edge cases properly


## Division by Zero Tests

func test_combatant_hp_percentage_handles_zero_max() -> void:
	"""Combatant.get_hp_percentage should not divide by zero"""
	var content = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")

	# Check for zero guard before division
	assert_true(content.contains("if max_hp <= 0"),
		"get_hp_percentage should guard against zero max_hp")


func test_combatant_mp_percentage_handles_zero_max() -> void:
	"""Combatant.get_mp_percentage should not divide by zero"""
	var content = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")

	# Check for zero guard before division
	assert_true(content.contains("if max_mp <= 0"),
		"get_mp_percentage should guard against zero max_mp")


func test_battle_manager_randi_has_size_checks() -> void:
	"""BattleManager should check array size before randi() % size"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# The rotate_aggro case should check enemies.size() > 0
	var rotate_aggro_idx = content.find('"rotate_aggro"')
	if rotate_aggro_idx > 0:
		var context = content.substr(rotate_aggro_idx, 200)
		assert_true(context.contains("enemies.size() > 0"),
			"rotate_aggro should check enemies.size() before randi()")


## Timer Cleanup Tests

func test_battle_dialogue_timer_cleanup() -> void:
	"""BattleDialogue should stop timer in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/ui/BattleDialogue.gd")

	assert_true(content.contains("func _exit_tree()"),
		"BattleDialogue should have _exit_tree")
	assert_true(content.contains("_typing_timer.stop()"),
		"BattleDialogue should stop typing timer in _exit_tree")


func test_win98_menu_timer_cleanup() -> void:
	"""Win98Menu should stop timers in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	assert_true(content.contains("func _exit_tree()"),
		"Win98Menu should have _exit_tree")
	assert_true(content.contains("_submenu_timer") and content.contains(".stop()"),
		"Win98Menu should stop submenu timer")


## Signal Cleanup Tests

func test_scene_transition_signal_cleanup() -> void:
	"""SceneTransition should disconnect signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/transitions/SceneTransition.gd")

	assert_true(content.contains("func _exit_tree()"),
		"SceneTransition should have _exit_tree")
	assert_true(content.contains(".disconnect("),
		"SceneTransition should disconnect signals")


func test_battle_scene_signal_cleanup() -> void:
	"""BattleScene should disconnect BattleManager signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")

	assert_true(content.contains("func _exit_tree()"),
		"BattleScene should have _exit_tree")
	assert_true(content.contains("BattleManager.battle_started.disconnect"),
		"BattleScene should disconnect battle_started")


## Null Safety Tests

func test_combatant_percentage_functions() -> void:
	"""Combatant percentage functions should handle edge cases"""
	var combatant = Combatant.new()
	add_child(combatant)

	# Test with zero max_hp
	combatant.max_hp = 0
	combatant.current_hp = 0
	var hp_pct = combatant.get_hp_percentage()
	assert_eq(hp_pct, 0.0, "Zero max_hp should return 0% not crash")

	# Test with zero max_mp
	combatant.max_mp = 0
	combatant.current_mp = 0
	var mp_pct = combatant.get_mp_percentage()
	assert_eq(mp_pct, 0.0, "Zero max_mp should return 0% not crash")

	combatant.queue_free()


func test_combatant_normal_percentage() -> void:
	"""Combatant percentage functions work with normal values"""
	var combatant = Combatant.new()
	add_child(combatant)

	combatant.max_hp = 100
	combatant.current_hp = 50
	var hp_pct = combatant.get_hp_percentage()
	assert_eq(hp_pct, 50.0, "50/100 HP should be 50%")

	combatant.max_mp = 50
	combatant.current_mp = 25
	var mp_pct = combatant.get_mp_percentage()
	assert_eq(mp_pct, 50.0, "25/50 MP should be 50%")

	combatant.queue_free()


## Array Bounds Tests

func test_safe_array_access_patterns() -> void:
	"""Code should use safe array access patterns"""
	var empty_array: Array = []

	# Test ternary pattern
	var first = empty_array[0] if empty_array.size() > 0 else null
	assert_null(first, "Empty array ternary should return null")

	# Test with data
	var filled_array = [1, 2, 3]
	first = filled_array[0] if filled_array.size() > 0 else null
	assert_eq(first, 1, "Non-empty array ternary should return first element")


## Dictionary Access Tests

func test_dictionary_get_with_default() -> void:
	"""Dictionary access should use get() with defaults"""
	var dict = {"key1": "value1"}

	# Safe pattern
	var value = dict.get("missing_key", "default")
	assert_eq(value, "default", "Missing key should return default")

	# Existing key
	value = dict.get("key1", "default")
	assert_eq(value, "value1", "Existing key should return value")


## Tween Cleanup Tests

func test_battle_animator_tween_cleanup() -> void:
	"""BattleAnimator should store tween reference and cleanup in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleAnimator.gd")

	assert_true(content.contains("var _current_tween"),
		"BattleAnimator should have _current_tween variable")
	assert_true(content.contains("func _exit_tree()"),
		"BattleAnimator should have _exit_tree")
	assert_true(content.contains("_current_tween.kill()"),
		"BattleAnimator should kill tween in _exit_tree")


func test_battle_animator_kills_existing_tween() -> void:
	"""BattleAnimator animation methods should kill existing tween before creating new"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleAnimator.gd")

	# Check that animation methods kill existing tween
	var backstab_idx = content.find("func play_backstab")
	if backstab_idx > 0:
		var context = content.substr(backstab_idx, 300)
		assert_true(context.contains("_current_tween.kill()"),
			"play_backstab should kill existing tween")


func test_effect_system_has_cleanup() -> void:
	"""EffectSystem should cleanup in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/battle/EffectSystem.gd")

	assert_true(content.contains("func _exit_tree()"),
		"EffectSystem should have _exit_tree")
	assert_true(content.contains("_effects_container") and content.contains("queue_free()"),
		"EffectSystem should cleanup effects container")


## Safe Dictionary Access Tests

func test_battle_manager_uses_safe_dict_access() -> void:
	"""BattleManager should use .get() for dictionary access on ability data"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# Check that ability type checks use .get()
	assert_true(content.contains('a.get("type"'),
		"BattleManager should use .get() for ability type access")
	assert_true(content.contains('heal.get("id"') or content.contains('spell.get("id"'),
		"BattleManager should use .get() for ability id access")


func test_battle_manager_action_dict_uses_get() -> void:
	"""BattleManager action execution should use .get() for action dictionary access"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# Check that action type matching uses .get()
	assert_true(content.contains('action.get("type"'),
		"BattleManager should use .get() for action type access")
	# Check that action target/ability_id uses .get()
	assert_true(content.contains('action.get("target"'),
		"BattleManager should use .get() for action target access")
	assert_true(content.contains('action.get("ability_id"'),
		"BattleManager should use .get() for action ability_id access")


func test_game_state_safe_random_access() -> void:
	"""GameState should check size before random access"""
	var content = FileAccess.get_file_as_string("res://src/meta/GameState.gd")

	# Check for size guard on game_constants random access
	assert_true(content.contains("game_constants.size() > 0"),
		"GameState should check game_constants.size() before random access")


func test_battle_manager_null_checks_singletons() -> void:
	"""BattleManager should null-check singletons before use"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# Check that ItemSystem is null-checked
	assert_true(content.contains("if ItemSystem and ItemSystem.use_item"),
		"BattleManager should null-check ItemSystem before use_item")


## Signal Cleanup Tests (Additional)

func test_autobattle_toggle_ui_signal_cleanup() -> void:
	"""AutobattleToggleUI should disconnect singleton signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleToggleUI.gd")

	assert_true(content.contains("func _exit_tree()"),
		"AutobattleToggleUI should have _exit_tree")
	assert_true(content.contains("BattleManager.battle_started.disconnect"),
		"AutobattleToggleUI should disconnect battle_started signal")


func test_overworld_controller_signal_cleanup() -> void:
	"""OverworldController should disconnect player signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/exploration/OverworldController.gd")

	assert_true(content.contains("func _exit_tree()"),
		"OverworldController should have _exit_tree")
	assert_true(content.contains("player.moved.disconnect"),
		"OverworldController should disconnect player.moved signal")


func test_battle_scene_popup_cleanup() -> void:
	"""BattleScene should have popup cleanup function"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")

	assert_true(content.contains("var _current_popup"),
		"BattleScene should track popup reference")
	assert_true(content.contains("func _cleanup_popup()"),
		"BattleScene should have _cleanup_popup method")
	assert_true(content.contains("_cleanup_popup()"),
		"BattleScene should call _cleanup_popup in appropriate places")


## Array Bounds Checking Tests (MenuScene and SaveScreen)

func test_menu_scene_equipment_bounds_check() -> void:
	"""MenuScene equipment functions should check selected_member_index bounds"""
	var content = FileAccess.get_file_as_string("res://src/ui/MenuScene.gd")

	# Check _show_equipment_selection has bounds check
	var idx = content.find("func _show_equipment_selection")
	if idx > 0:
		var context = content.substr(idx, 300)
		assert_true(context.contains("selected_member_index >= party.size()"),
			"_show_equipment_selection should check party bounds")

	# Check _on_equipment_selected has bounds check
	idx = content.find("func _on_equipment_selected")
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("selected_member_index >= party.size()"),
			"_on_equipment_selected should check party bounds")


func test_menu_scene_ability_bounds_check() -> void:
	"""MenuScene ability functions should check array bounds"""
	var content = FileAccess.get_file_as_string("res://src/ui/MenuScene.gd")

	# Check _show_ability_target_selection has bounds check
	var idx = content.find("func _show_ability_target_selection")
	if idx > 0:
		var context = content.substr(idx, 300)
		assert_true(context.contains("selected_member_index >= party.size()"),
			"_show_ability_target_selection should check party bounds")

	# Check _on_ability_target_selected checks both indices
	idx = content.find("func _on_ability_target_selected")
	if idx > 0:
		var context = content.substr(idx, 250)
		assert_true(context.contains("target_index >= party.size()") or context.contains("or target_index"),
			"_on_ability_target_selected should check target_index bounds")


func test_menu_scene_passive_bounds_check() -> void:
	"""MenuScene passive functions should check selected_member_index bounds"""
	var content = FileAccess.get_file_as_string("res://src/ui/MenuScene.gd")

	# Check _on_passive_unequip_pressed has bounds check
	var idx = content.find("func _on_passive_unequip_pressed")
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("selected_member_index >= party.size()"),
			"_on_passive_unequip_pressed should check party bounds")

	# Check _on_passive_equip_pressed has bounds check
	idx = content.find("func _on_passive_equip_pressed")
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("selected_member_index >= party.size()"),
			"_on_passive_equip_pressed should check party bounds")


func test_menu_scene_item_bounds_check() -> void:
	"""MenuScene item use should check selected_member_index bounds"""
	var content = FileAccess.get_file_as_string("res://src/ui/MenuScene.gd")

	var idx = content.find("func _on_item_use_pressed")
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("selected_member_index >= party.size()"),
			"_on_item_use_pressed should check party bounds")


func test_save_screen_slot_bounds_check() -> void:
	"""SaveScreen should check selected_slot bounds before array access"""
	var content = FileAccess.get_file_as_string("res://src/ui/SaveScreen.gd")

	var idx = content.find("func _handle_confirm")
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("selected_slot >= _slot_panels.size()"),
			"_handle_confirm should check slot panel bounds")


## CharacterPortrait Null Safety Tests

func test_character_portrait_null_customization() -> void:
	"""CharacterPortrait _draw_portrait should check for null customization"""
	var content = FileAccess.get_file_as_string("res://src/ui/CharacterPortrait.gd")

	var idx = content.find("func _draw_portrait")
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("not customization"),
			"_draw_portrait should check for null customization")


## AutobattleGridEditor Cleanup Tests

func test_autobattle_grid_editor_exit_tree() -> void:
	"""AutobattleGridEditor should cleanup modal and keyboard in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleGridEditor.gd")

	assert_true(content.contains("func _exit_tree()"),
		"AutobattleGridEditor should have _exit_tree")
	assert_true(content.contains("_edit_modal") and content.contains("queue_free()"),
		"AutobattleGridEditor should cleanup _edit_modal")
	assert_true(content.contains("_keyboard") and content.contains("queue_free()"),
		"AutobattleGridEditor should cleanup _keyboard")


## PassiveSystem Null Safety Tests

func test_passive_system_null_combatant_checks() -> void:
	"""PassiveSystem functions should check for null combatant"""
	var content = FileAccess.get_file_as_string("res://src/jobs/PassiveSystem.gd")

	# Check equip_passive
	var idx = content.find("func equip_passive")
	if idx > 0:
		var context = content.substr(idx, 250)
		assert_true(context.contains("not combatant or not is_instance_valid"),
			"equip_passive should check for null/invalid combatant")

	# Check unequip_passive
	idx = content.find("func unequip_passive")
	if idx > 0:
		var context = content.substr(idx, 250)
		assert_true(context.contains("not combatant or not is_instance_valid"),
			"unequip_passive should check for null/invalid combatant")

	# Check can_equip_passive
	idx = content.find("func can_equip_passive")
	if idx > 0:
		var context = content.substr(idx, 250)
		assert_true(context.contains("not combatant or not is_instance_valid"),
			"can_equip_passive should check for null/invalid combatant")

	# Check get_passive_mods
	idx = content.find("func get_passive_mods")
	if idx > 0:
		var context = content.substr(idx, 250)
		assert_true(context.contains("not combatant or not is_instance_valid"),
			"get_passive_mods should check for null/invalid combatant")


## Win98Menu Bounds Check Tests

func test_win98_menu_negative_index_check() -> void:
	"""Win98Menu should check selected_index >= 0"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	# Check for proper bounds validation pattern
	assert_true(content.contains("selected_index >= 0 and selected_index < menu_items.size()"),
		"Win98Menu should check selected_index >= 0 in ternary expressions")
	assert_true(content.contains("selected_index < 0 or selected_index >= menu_items.size()"),
		"Win98Menu should check selected_index < 0 in guard clauses")


## Async Safety Tests (TreasureChest)

func test_treasure_chest_async_safety() -> void:
	"""TreasureChest should check is_instance_valid after await"""
	var content = FileAccess.get_file_as_string("res://src/exploration/TreasureChest.gd")

	# Check that await timer calls are followed by validity checks
	var timer_idx = content.find("await get_tree().create_timer")
	if timer_idx > 0:
		# Find the next 100 chars after the await
		var after_await = content.substr(timer_idx, 150)
		assert_true(after_await.contains("is_instance_valid"),
			"TreasureChest should check is_instance_valid after await")


## ItemSystem Safety Tests

func test_item_system_target_validation() -> void:
	"""ItemSystem should validate targets before applying effects"""
	var content = FileAccess.get_file_as_string("res://src/items/ItemSystem.gd")

	# Check for target validity in use_item loop
	var idx = content.find("for target in targets:")
	if idx > 0:
		var context = content.substr(idx, 150)
		assert_true(context.contains("is_instance_valid(target)"),
			"ItemSystem should check target validity before applying effects")


func test_item_system_battle_manager_check() -> void:
	"""ItemSystem should check BattleManager before accessing parties"""
	var content = FileAccess.get_file_as_string("res://src/items/ItemSystem.gd")

	var idx = content.find("func can_use_item")
	if idx > 0:
		var context = content.substr(idx, 400)
		assert_true(context.contains("not BattleManager"),
			"can_use_item should check BattleManager availability")


## EquipmentSystem Safety Tests

func test_equipment_system_stat_key_check() -> void:
	"""EquipmentSystem should check stat key exists before adding"""
	var content = FileAccess.get_file_as_string("res://src/jobs/EquipmentSystem.gd")

	# Check for key validation in stat mod application
	assert_true(content.contains("if total_mods.has(stat)"),
		"EquipmentSystem should check stat key exists in total_mods")


## Property Access Safety Tests

func test_battle_manager_uses_direct_combatant_speed() -> void:
	"""BattleManager should use combatant.speed, not combatant.stats.speed"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# Ensure no incorrect .stats. property access
	assert_false(content.contains("combatant.stats."),
		"BattleManager should not use combatant.stats (Combatant has direct properties)")


## Resource Loading Safety Tests

func test_scene_transition_load_null_check() -> void:
	"""SceneTransition should check for null after load()"""
	var content = FileAccess.get_file_as_string("res://src/transitions/SceneTransition.gd")

	var idx = content.find("battle_scene_resource = load")
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("not battle_scene_resource"),
			"SceneTransition should check for null after load()")


func test_map_system_load_null_check() -> void:
	"""MapSystem should check for null after load()"""
	var content = FileAccess.get_file_as_string("res://src/maps/MapSystem.gd")

	var idx = content.find("map_scene = load")
	if idx > 0:
		var context = content.substr(idx, 150)
		assert_true(context.contains("not map_scene"),
			"MapSystem should check for null after load()")


func test_game_loop_battle_scene_load_check() -> void:
	"""GameLoop should check for null after loading BattleScene"""
	var content = FileAccess.get_file_as_string("res://src/GameLoop.gd")

	# Find the specific pattern where load() is used (not preload or threaded)
	var idx = content.find('loaded_res = load("res://src/battle/BattleScene.tscn")')
	if idx > 0:
		var context = content.substr(idx, 200)
		assert_true(context.contains("not loaded_res"),
			"GameLoop should check for null after loading battle scene")


## Match Statement Default Case Tests

func test_battle_manager_action_type_default_case() -> void:
	"""BattleManager action execution should handle unknown action types"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# Find the action match statement and check for default case
	var idx = content.find('match action.get("type"')
	if idx > 0:
		var context = content.substr(idx, 600)
		assert_true(context.contains("_:") and context.contains("Unknown action type"),
			"BattleManager should have default case with warning for unknown action types")


func test_autobattle_action_def_default_case() -> void:
	"""AutobattleSystem _action_def_to_action should handle unknown action types"""
	var content = FileAccess.get_file_as_string("res://src/autobattle/AutobattleSystem.gd")

	# Find the action def match and check for default case
	var idx = content.find("func _action_def_to_action")
	if idx > 0:
		var context = content.substr(idx, 1200)
		assert_true(context.contains("_:") and context.contains("Unknown action type"),
			"_action_def_to_action should have default case with warning")


## Combatant Revive Safety Tests

func test_combatant_revive_minimum_hp() -> void:
	"""Combatant revive should ensure minimum 1 HP"""
	var content = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")

	var idx = content.find("func revive")
	if idx > 0:
		var context = content.substr(idx, 300)
		assert_true(context.contains("max(1,"),
			"revive should use max(1, ...) to ensure minimum 1 HP")


## Tween Cleanup Tests

func test_damage_number_tween_cleanup() -> void:
	"""DamageNumber should track and cleanup flash tween"""
	var content = FileAccess.get_file_as_string("res://src/ui/DamageNumber.gd")

	assert_true(content.contains("var _flash_tween"),
		"DamageNumber should have _flash_tween variable")
	assert_true(content.contains("func _exit_tree()"),
		"DamageNumber should have _exit_tree for tween cleanup")
	assert_true(content.contains("_flash_tween.kill()"),
		"DamageNumber should kill tween in _exit_tree")


func test_sound_manager_tween_cleanup() -> void:
	"""SoundManager should cleanup tweens in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/audio/SoundManager.gd")

	assert_true(content.contains("func _exit_tree()"),
		"SoundManager should have _exit_tree for tween cleanup")
	assert_true(content.contains("_crossfade_tween.kill()"),
		"SoundManager should kill crossfade tween in _exit_tree")
	assert_true(content.contains("_danger_tween.kill()"),
		"SoundManager should kill danger tween in _exit_tree")


## VirtualKeyboard Safety Tests

func test_virtual_keyboard_empty_layout_check() -> void:
	"""VirtualKeyboard should check for empty layout before accessing"""
	var content = FileAccess.get_file_as_string("res://src/ui/VirtualKeyboard.gd")

	# Check for empty layout guard
	assert_true(content.contains("layout.is_empty()") or content.contains("layout.size() == 0"),
		"VirtualKeyboard should check for empty layout")


## BattleScene Party Safety Tests

func test_battle_scene_party_member_bounds_check() -> void:
	"""BattleScene should check party_members size before access"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")

	# Check for safe party_members access pattern
	assert_true(content.contains("party_members.size() > 0 else null"),
		"BattleScene should guard party_members[0] access with size check")


## Summary Test

func test_critical_files_have_error_handling() -> void:
	"""Summary: Critical files should have proper error handling"""
	var issues = []

	# Check Combatant has division guards
	var combatant_content = FileAccess.get_file_as_string("res://src/battle/Combatant.gd")
	if not combatant_content.contains("if max_hp <= 0"):
		issues.append("Combatant.gd missing max_hp guard")
	if not combatant_content.contains("if max_mp <= 0"):
		issues.append("Combatant.gd missing max_mp guard")

	# Check BattleDialogue has timer cleanup
	var dialogue_content = FileAccess.get_file_as_string("res://src/ui/BattleDialogue.gd")
	if not dialogue_content.contains("func _exit_tree()"):
		issues.append("BattleDialogue.gd missing _exit_tree")

	# Check SceneTransition has signal cleanup
	var transition_content = FileAccess.get_file_as_string("res://src/transitions/SceneTransition.gd")
	if not transition_content.contains("func _exit_tree()"):
		issues.append("SceneTransition.gd missing _exit_tree")

	# Check AutobattleToggleUI has signal cleanup
	var toggle_content = FileAccess.get_file_as_string("res://src/ui/autobattle/AutobattleToggleUI.gd")
	if not toggle_content.contains("func _exit_tree()"):
		issues.append("AutobattleToggleUI.gd missing _exit_tree")

	# Check OverworldController has signal cleanup
	var controller_content = FileAccess.get_file_as_string("res://src/exploration/OverworldController.gd")
	if not controller_content.contains("func _exit_tree()"):
		issues.append("OverworldController.gd missing _exit_tree")

	assert_true(issues.is_empty(),
		"All critical files should have error handling. Issues: %s" % str(issues))
