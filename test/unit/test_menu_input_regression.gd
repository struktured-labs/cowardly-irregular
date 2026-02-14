extends GutTest

## Regression tests for menu input handling
## These tests verify fixes for input propagation issues

## Test: Win98Menu should be able to receive input when not in battle mode
func test_win98_menu_non_battle_mode_input() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	# Shop context: battle_mode = false
	menu.battle_mode = false

	# Add to scene tree
	add_child(menu)

	# Setup menu with items
	var items = [
		{"id": "buy", "label": "Buy"},
		{"id": "sell", "label": "Sell"},
		{"id": "exit", "label": "Exit"}
	]
	menu.setup("Test Menu", items, Vector2(100, 100), "fighter")

	# Verify menu is set up correctly
	assert_eq(menu.menu_items.size(), 3, "Menu should have 3 items")
	assert_eq(menu.selected_index, 0, "Should start at first item")
	assert_false(menu.battle_mode, "battle_mode should be false for shop context")

	menu.queue_free()


## Test: Win98Menu _can_accept_input flag should become true after delay
func test_win98_menu_input_delay_flag() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	add_child(menu)

	# Initially _can_accept_input should be false
	assert_false(menu._can_accept_input, "_can_accept_input should start false")

	# Setup triggers _build_menu which has the timers
	var items = [{"id": "test", "label": "Test"}]
	menu.setup("Test", items, Vector2.ZERO, "fighter")

	# Wait for input delay timers (0.08 + 0.05 = 0.13 seconds)
	await get_tree().create_timer(0.2).timeout

	# Now _can_accept_input should be true
	assert_true(menu._can_accept_input, "_can_accept_input should be true after delay")

	menu.queue_free()


## Test: Win98Menu L button state should reset on close
func test_win98_menu_l_button_reset_on_close() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	add_child(menu)

	# Simulate L button pressed
	menu._l_button_pressed = true
	menu._l_button_press_time = Time.get_ticks_msec() / 1000.0

	# Force close should reset L button state
	menu.force_close()

	assert_false(menu._l_button_pressed, "L button state should reset on close")


## Test: Win98Menu should have focus mode set correctly
func test_win98_menu_focus_mode_set_in_ready() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	# Add to tree triggers _ready()
	add_child(menu)

	# Check focus mode is set for input reception
	assert_eq(menu.focus_mode, Control.FOCUS_ALL, "Focus mode should be FOCUS_ALL")

	menu.queue_free()


## Test: Win98Menu _is_closing flag prevents double-close
func test_win98_menu_double_close_prevention() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	add_child(menu)

	# First close sets the flag
	assert_false(menu._is_closing, "_is_closing should start false")

	menu.force_close()

	assert_true(menu._is_closing, "_is_closing should be true after close")


## Test: Win98Menu selected item accessors work
func test_win98_menu_selected_item_accessors() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	add_child(menu)

	var items = [
		{"id": "item1", "label": "Item 1", "data": {"price": 100}},
		{"id": "item2", "label": "Item 2", "data": {"price": 200}}
	]
	menu.setup("Test", items, Vector2.ZERO, "fighter")

	# First item should be selected
	assert_eq(menu.get_selected_item_id(), "item1", "Should return first item id")
	var data = menu.get_selected_item_data()
	assert_eq(data.get("price"), 100, "Should return first item data")

	# Move selection
	menu.selected_index = 1
	assert_eq(menu.get_selected_item_id(), "item2", "Should return second item id")

	menu.queue_free()


## Test: ShopScene extends Control (for proper input propagation to child menus)
func test_shop_scene_extends_control() -> void:
	var ShopSceneScript = load("res://src/exploration/ShopScene.gd")
	var shop = ShopSceneScript.new()

	# ShopScene extends Control for proper input handling (changed from CanvasLayer)
	assert_true(shop is Control, "ShopScene should extend Control for proper input handling")

	shop.queue_free()


## Test: Win98Menu is root menu flag works correctly
func test_win98_menu_root_menu_flag() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	# Default should be false
	assert_false(menu.is_root_menu, "is_root_menu should default to false")

	# Setting it to true should work
	menu.is_root_menu = true
	assert_true(menu.is_root_menu, "is_root_menu should be settable to true")

	menu.queue_free()


## Test: Win98Menu setup before add_child pattern
## This tests the fix for the race condition between _ready() and setup()
func test_win98_menu_setup_pattern() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	# The correct pattern is:
	# 1. Create menu
	# 2. Set properties (battle_mode, is_root_menu, etc.)
	# 3. add_child()
	# 4. setup()

	menu.battle_mode = false
	menu.is_root_menu = true

	add_child(menu)

	var items = [{"id": "test", "label": "Test"}]
	menu.setup("Test", items, Vector2(100, 100), "fighter")

	# Verify menu was built correctly
	assert_eq(menu.menu_items.size(), 1, "Menu should have 1 item")
	assert_eq(menu.anchor_position, Vector2(100, 100), "Position should be set")

	menu.queue_free()
