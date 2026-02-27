extends GutTest

## Tests for TutorialHelpMenu overlay
## Validates menu creation, tab content, navigation, and integration


## ---- Script Loading ----

func test_tutorial_help_menu_script_loads() -> void:
	var script = load("res://src/ui/TutorialHelpMenu.gd")
	assert_not_null(script, "TutorialHelpMenu.gd should load without errors")


func test_tutorial_help_menu_class_exists() -> void:
	var menu = TutorialHelpMenu.new()
	assert_not_null(menu, "TutorialHelpMenu should instantiate")
	menu.queue_free()


## ---- Signal ----

func test_has_closed_signal() -> void:
	var menu = TutorialHelpMenu.new()
	assert_true(menu.has_signal("closed"), "Should have 'closed' signal")
	menu.queue_free()


## ---- Tab Constants ----

func test_tab_count_matches_names() -> void:
	assert_eq(TutorialHelpMenu.TAB_NAMES.size(), 5,
		"Should have 5 tabs: Controls, Battle, Jobs, Autobattle, Tips")


func test_tab_names_are_correct() -> void:
	assert_eq(TutorialHelpMenu.TAB_NAMES[0], "Controls")
	assert_eq(TutorialHelpMenu.TAB_NAMES[1], "Battle")
	assert_eq(TutorialHelpMenu.TAB_NAMES[2], "Jobs")
	assert_eq(TutorialHelpMenu.TAB_NAMES[3], "Autobattle")
	assert_eq(TutorialHelpMenu.TAB_NAMES[4], "Tips")


## ---- Initial State ----

func test_initial_tab_is_controls() -> void:
	var menu = TutorialHelpMenu.new()
	assert_eq(menu.current_tab, TutorialHelpMenu.Tab.CONTROLS,
		"Initial tab should be Controls")
	menu.queue_free()


func test_initial_scroll_offset_is_zero() -> void:
	var menu = TutorialHelpMenu.new()
	assert_eq(menu.scroll_offset, 0, "Initial scroll offset should be 0")
	menu.queue_free()


## ---- Content Generation ----

func test_controls_tab_has_content() -> void:
	var menu = TutorialHelpMenu.new()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.CONTROLS)
	assert_gt(content.size(), 0, "Controls tab should have content lines")
	menu.queue_free()


func test_battle_tab_has_content() -> void:
	var menu = TutorialHelpMenu.new()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.BATTLE)
	assert_gt(content.size(), 0, "Battle tab should have content lines")
	menu.queue_free()


func test_jobs_tab_has_content() -> void:
	var menu = TutorialHelpMenu.new()
	menu._load_jobs_data()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.JOBS)
	assert_gt(content.size(), 0, "Jobs tab should have content lines")
	menu.queue_free()


func test_autobattle_tab_has_content() -> void:
	var menu = TutorialHelpMenu.new()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.AUTOBATTLE)
	assert_gt(content.size(), 0, "Autobattle tab should have content lines")
	menu.queue_free()


func test_tips_tab_has_content() -> void:
	var menu = TutorialHelpMenu.new()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.TIPS)
	assert_gt(content.size(), 0, "Tips tab should have content lines")
	menu.queue_free()


## ---- Content Line Structure ----

func test_content_line_has_required_keys() -> void:
	var menu = TutorialHelpMenu.new()
	var line = menu._line("Test text", "header", 1, 14, 28)
	assert_true(line.has("text"), "Line should have 'text' key")
	assert_true(line.has("style"), "Line should have 'style' key")
	assert_true(line.has("indent"), "Line should have 'indent' key")
	assert_true(line.has("size"), "Line should have 'size' key")
	assert_true(line.has("spacing"), "Line should have 'spacing' key")
	menu.queue_free()


func test_line_helper_default_values() -> void:
	var menu = TutorialHelpMenu.new()
	var line = menu._line("Test")
	assert_eq(line["text"], "Test")
	assert_eq(line["style"], "normal")
	assert_eq(line["indent"], 0)
	assert_eq(line["size"], 13)
	assert_eq(line["spacing"], 26)
	menu.queue_free()


## ---- Tab Switching ----

func test_switch_tab_forward() -> void:
	var menu = TutorialHelpMenu.new()
	assert_eq(menu.current_tab, TutorialHelpMenu.Tab.CONTROLS)
	menu._switch_tab(1)
	assert_eq(menu.current_tab, TutorialHelpMenu.Tab.BATTLE,
		"Switching forward from Controls should go to Battle")
	menu.queue_free()


func test_switch_tab_backward() -> void:
	var menu = TutorialHelpMenu.new()
	menu.current_tab = TutorialHelpMenu.Tab.BATTLE
	menu._switch_tab(-1)
	assert_eq(menu.current_tab, TutorialHelpMenu.Tab.CONTROLS,
		"Switching backward from Battle should go to Controls")
	menu.queue_free()


func test_switch_tab_wraps_forward() -> void:
	var menu = TutorialHelpMenu.new()
	menu.current_tab = TutorialHelpMenu.Tab.TIPS
	menu._switch_tab(1)
	assert_eq(menu.current_tab, TutorialHelpMenu.Tab.CONTROLS,
		"Switching forward from last tab should wrap to Controls")
	menu.queue_free()


func test_switch_tab_wraps_backward() -> void:
	var menu = TutorialHelpMenu.new()
	menu.current_tab = TutorialHelpMenu.Tab.CONTROLS
	menu._switch_tab(-1)
	assert_eq(menu.current_tab, TutorialHelpMenu.Tab.TIPS,
		"Switching backward from Controls should wrap to Tips")
	menu.queue_free()


func test_switch_tab_resets_scroll() -> void:
	var menu = TutorialHelpMenu.new()
	menu.scroll_offset = 5
	menu._switch_tab(1)
	assert_eq(menu.scroll_offset, 0,
		"Switching tabs should reset scroll offset to 0")
	menu.queue_free()


## ---- Jobs Data Loading ----

func test_jobs_data_loads_from_json() -> void:
	var menu = TutorialHelpMenu.new()
	menu._load_jobs_data()
	assert_gt(menu._jobs_data.size(), 0, "Jobs data should load from JSON")
	menu.queue_free()


func test_jobs_data_has_starter_jobs() -> void:
	var menu = TutorialHelpMenu.new()
	menu._load_jobs_data()
	assert_true(menu._jobs_data.has("fighter"), "Should have fighter job")
	assert_true(menu._jobs_data.has("cleric"), "Should have cleric job")
	assert_true(menu._jobs_data.has("mage"), "Should have mage job")
	assert_true(menu._jobs_data.has("rogue"), "Should have rogue job")
	assert_true(menu._jobs_data.has("bard"), "Should have bard job")
	menu.queue_free()


func test_jobs_tab_mentions_starter_jobs() -> void:
	var menu = TutorialHelpMenu.new()
	menu._load_jobs_data()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.JOBS)
	var all_text = ""
	for line in content:
		all_text += line.get("text", "") + "\n"
	assert_true(all_text.contains("Fighter"), "Jobs tab should mention Fighter")
	assert_true(all_text.contains("Cleric"), "Jobs tab should mention Cleric")
	assert_true(all_text.contains("Mage"), "Jobs tab should mention Mage")
	assert_true(all_text.contains("Rogue"), "Jobs tab should mention Rogue")
	assert_true(all_text.contains("Bard"), "Jobs tab should mention Bard")
	menu.queue_free()


## ---- Style Constants ----

func test_uses_retro_panel() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/TutorialHelpMenu.gd")
	assert_true(content.contains("RetroPanel"),
		"TutorialHelpMenu should use RetroPanel for borders")


func test_has_matching_style_constants() -> void:
	"""Ensure help menu style matches the overworld menu palette"""
	var content = FileAccess.get_file_as_string("res://src/ui/TutorialHelpMenu.gd")
	assert_true(content.contains("BG_COLOR"), "Should define BG_COLOR")
	assert_true(content.contains("PANEL_COLOR"), "Should define PANEL_COLOR")
	assert_true(content.contains("BORDER_LIGHT"), "Should define BORDER_LIGHT")
	assert_true(content.contains("BORDER_SHADOW"), "Should define BORDER_SHADOW")
	assert_true(content.contains("TEXT_COLOR"), "Should define TEXT_COLOR")


## ---- Integration with OverworldMenu ----

func test_overworld_menu_has_help_option() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_true(content.contains('"help"'),
		"OverworldMenu should have a 'help' menu option")


func test_overworld_menu_handles_help_action() -> void:
	var content = FileAccess.get_file_as_string("res://src/ui/OverworldMenu.gd")
	assert_true(content.contains("_open_help_menu"),
		"OverworldMenu should have _open_help_menu method")


## ---- Integration with GameLoop ----

func test_gameloop_has_help_menu_support() -> void:
	var content = FileAccess.get_file_as_string("res://src/GameLoop.gd")
	assert_true(content.contains("_help_menu"),
		"GameLoop should have help menu variables")
	assert_true(content.contains("_toggle_help_menu"),
		"GameLoop should have _toggle_help_menu method")
	assert_true(content.contains("KEY_F1"),
		"GameLoop should handle F1 key for help menu")


## ---- Controls Content Completeness ----

func test_controls_tab_covers_all_input_contexts() -> void:
	var menu = TutorialHelpMenu.new()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.CONTROLS)
	var all_text = ""
	for line in content:
		all_text += line.get("text", "") + "\n"

	assert_true(all_text.contains("EXPLORATION"), "Should have Exploration section")
	assert_true(all_text.contains("BATTLE"), "Should have Battle section")
	assert_true(all_text.contains("MENUS"), "Should have Menus section")
	assert_true(all_text.contains("AUTOBATTLE EDITOR"), "Should have Autobattle Editor section")
	menu.queue_free()


## ---- Battle Content Completeness ----

func test_battle_tab_covers_ap_system() -> void:
	var menu = TutorialHelpMenu.new()
	var content = menu._get_tab_content(TutorialHelpMenu.Tab.BATTLE)
	var all_text = ""
	for line in content:
		all_text += line.get("text", "") + "\n"

	assert_true(all_text.contains("AP"), "Battle tab should explain AP system")
	assert_true(all_text.contains("DEFER") or all_text.contains("Defer"),
		"Battle tab should explain Defer")
	assert_true(all_text.contains("ADVANCE") or all_text.contains("Advance"),
		"Battle tab should explain Advance")
	menu.queue_free()
