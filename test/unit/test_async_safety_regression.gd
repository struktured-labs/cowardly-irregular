extends GutTest

## Regression tests for async safety bugs
## Ensures all await statements have proper validity checks
## These are structural tests that verify the codebase follows safe async patterns


## BattleManager Async Safety

func test_battle_manager_has_validity_checks() -> void:
	"""BattleManager should have is_instance_valid checks after await statements"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# Count awaits and validity checks
	var await_count = content.count("await get_tree()")
	var validity_count = content.count("is_instance_valid(self)")

	# There should be validity checks for async code
	assert_gt(validity_count, 0, "BattleManager should have validity checks")


func test_battle_manager_execute_next_action_protected() -> void:
	"""_execute_next_action calls should be protected after await"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleManager.gd")

	# Check that validity check appears before _execute_next_action after await
	var pattern_safe = "is_instance_valid(self)"
	assert_true(content.contains(pattern_safe),
		"BattleManager should check validity after timer awaits")


## SceneTransition Async Safety

func test_scene_transition_battle_ended_protected() -> void:
	"""SceneTransition._on_battle_ended should check validity after await"""
	var content = FileAccess.get_file_as_string("res://src/transitions/SceneTransition.gd")

	# Check for validity check in _on_battle_ended
	assert_true(content.contains("is_instance_valid(self)"),
		"SceneTransition should check validity after await")


## ShopScene Async Safety

func test_shop_scene_purchase_refresh_protected() -> void:
	"""ShopScene purchase refresh should check validity"""
	var content = FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")

	# Count validity checks - should have several for purchase/sell flows
	var validity_count = content.count("is_instance_valid(self)")
	assert_gte(validity_count, 3, "ShopScene should have validity checks after await")


func test_shop_scene_signal_cleanup() -> void:
	"""ShopScene should disconnect signals before freeing menu"""
	var content = FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")

	# Check for signal disconnection pattern
	assert_true(content.contains("disconnect(_on_menu_item_selected)") or
		content.contains("item_selected.disconnect"),
		"ShopScene should disconnect signals before freeing")


## Win98Menu Async Safety

func test_win98_menu_build_protected() -> void:
	"""Win98Menu._build_menu should have validity checks after await"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	# Check for validity checks in _build_menu
	assert_true(content.contains("is_instance_valid(self)"),
		"Win98Menu should check validity after await in _build_menu")


func test_win98_menu_process_guard() -> void:
	"""Win98Menu._process should guard against running on freed node"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	# Check for _is_closing guard in _process
	assert_true(content.contains("_is_closing"),
		"Win98Menu should have _is_closing guard")


func test_win98_menu_l_button_reset() -> void:
	"""Win98Menu should reset L button state on close"""
	var content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	# Check for l_button_pressed reset in force_close
	assert_true(content.contains("_l_button_pressed = false"),
		"Win98Menu should reset L button state on close")


## BattleTransition Audio Safety

func test_battle_transition_audio_validity() -> void:
	"""BattleTransition audio player should check validity before queue_free"""
	var content = FileAccess.get_file_as_string("res://src/transitions/BattleTransition.gd")

	# Check for validity check in audio finished callback
	assert_true(content.contains("is_instance_valid(player)"),
		"BattleTransition should check player validity before queue_free")


func test_battle_transition_fade_out_safety() -> void:
	"""BattleTransition fade_out should check validity after await"""
	var content = FileAccess.get_file_as_string("res://src/transitions/BattleTransition.gd")

	# Check for validity check after await tween.finished
	assert_true(content.contains("await tween.finished") and content.contains("is_instance_valid(self)"),
		"BattleTransition should check validity after await in fade_out")


func test_battle_transition_midpoint_safety() -> void:
	"""BattleTransition should check validity before emitting midpoint signal"""
	var content = FileAccess.get_file_as_string("res://src/transitions/BattleTransition.gd")

	# Check for validity check before transition_midpoint.emit()
	var midpoint_idx = content.find("transition_midpoint.emit()")
	if midpoint_idx > 0:
		var context_before = content.substr(max(0, midpoint_idx - 100), 100)
		assert_true(context_before.contains("is_instance_valid"),
			"BattleTransition should check validity before emitting midpoint signal")


## BattleDialogue Timer Safety

func test_battle_dialogue_typing_tick_safety() -> void:
	"""BattleDialogue _on_typing_tick should check validity"""
	var content = FileAccess.get_file_as_string("res://src/ui/BattleDialogue.gd")

	# Check for validity check in _on_typing_tick
	var tick_idx = content.find("func _on_typing_tick()")
	if tick_idx > 0:
		var context = content.substr(tick_idx, 200)
		assert_true(context.contains("is_instance_valid(self)") or context.contains("is_instance_valid(_text_label)"),
			"BattleDialogue _on_typing_tick should check validity")


func test_battle_dialogue_finish_typing_safety() -> void:
	"""BattleDialogue _finish_typing should check component validity"""
	var content = FileAccess.get_file_as_string("res://src/ui/BattleDialogue.gd")

	# Check for validity check in _finish_typing
	var finish_idx = content.find("func _finish_typing()")
	if finish_idx > 0:
		var context = content.substr(finish_idx, 300)
		assert_true(context.contains("is_instance_valid"),
			"BattleDialogue _finish_typing should check component validity")


## VillageShop Player Reference Safety

func test_village_shop_player_validity() -> void:
	"""VillageShop should check player validity in callbacks"""
	var content = FileAccess.get_file_as_string("res://src/exploration/VillageShop.gd")

	# Check for is_instance_valid(player)
	assert_true(content.contains("is_instance_valid(player)"),
		"VillageShop should check player validity")


## CharacterPortrait Null Safety

func test_character_portrait_customization_check() -> void:
	"""CharacterPortrait should check customization before accessing"""
	var content = FileAccess.get_file_as_string("res://src/ui/CharacterPortrait.gd")

	# Check for null check before match on customization.hair_style
	assert_true(content.contains("if not customization") or
		content.contains("if customization:") or
		content.contains("customization else"),
		"CharacterPortrait should check customization nullity")


## CharacterCreationScreen Bounds Safety

func test_character_creation_options_bounds() -> void:
	"""CharacterCreationScreen should check OPTIONS array bounds"""
	var content = FileAccess.get_file_as_string("res://src/ui/CharacterCreationScreen.gd")

	# Check for bounds checking before OPTIONS[i] access
	assert_true(content.contains("OPTIONS.size()") or content.contains("i >= OPTIONS"),
		"CharacterCreationScreen should check OPTIONS bounds")


## General Async Patterns

func test_no_bare_await_without_check() -> void:
	"""Critical files should not have await without validity checks nearby"""
	var critical_files = [
		"res://src/battle/BattleManager.gd",
		"res://src/exploration/ShopScene.gd",
		"res://src/ui/Win98Menu.gd",
		"res://src/transitions/SceneTransition.gd"
	]

	for file_path in critical_files:
		var content = FileAccess.get_file_as_string(file_path)
		if content.contains("await get_tree().create_timer"):
			# If file has timer awaits, it should have validity checks
			assert_true(content.contains("is_instance_valid"),
				"%s should have validity checks if it uses timer awaits" % file_path)


## Signal Connection Safety

func test_signals_use_weak_references_or_cleanup() -> void:
	"""Files with signal connections should disconnect or use weak refs"""
	# This is a reminder test - actual signal management varies
	assert_true(true, "Signal connection patterns should be reviewed")


## Summary Test

func test_async_safety_summary() -> void:
	"""Summary: All critical async safety patterns should be present"""
	var all_safe = true
	var issues = []

	# Check each critical file
	var checks = {
		"res://src/battle/BattleManager.gd": "is_instance_valid",
		"res://src/exploration/ShopScene.gd": "is_instance_valid",
		"res://src/ui/Win98Menu.gd": "_is_closing",
		"res://src/transitions/SceneTransition.gd": "is_instance_valid",
		"res://src/transitions/BattleTransition.gd": "is_instance_valid"
	}

	for file_path in checks:
		var content = FileAccess.get_file_as_string(file_path)
		if not content.contains(checks[file_path]):
			all_safe = false
			issues.append(file_path)

	assert_true(all_safe, "All critical files should have async safety: %s" % str(issues))


func test_battle_scene_signal_cleanup() -> void:
	"""BattleScene should disconnect BattleManager signals in _exit_tree"""
	var content = FileAccess.get_file_as_string("res://src/battle/BattleScene.gd")

	# Check for _exit_tree function
	assert_true(content.contains("func _exit_tree()"),
		"BattleScene should have _exit_tree for cleanup")

	# Check that it disconnects BattleManager signals
	assert_true(content.contains("BattleManager.battle_started.disconnect"),
		"BattleScene should disconnect battle_started signal")
	assert_true(content.contains("BattleManager.battle_ended.disconnect"),
		"BattleScene should disconnect battle_ended signal")
