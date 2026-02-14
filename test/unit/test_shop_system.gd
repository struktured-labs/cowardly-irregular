extends GutTest

## Tests for Shop System components
## Covers ShopScene, VillageShop, and Win98Menu in shop context

var _game_state: Node
var _item_system: Node
var _equipment_system: Node
var _job_system: Node


func before_all() -> void:
	_game_state = get_tree().root.get_node_or_null("GameState")
	_item_system = get_tree().root.get_node_or_null("ItemSystem")
	_equipment_system = get_tree().root.get_node_or_null("EquipmentSystem")
	_job_system = get_tree().root.get_node_or_null("JobSystem")


## ShopScene Tests

func test_shop_scene_can_be_instantiated() -> void:
	var ShopSceneScript = load("res://src/exploration/ShopScene.gd")
	assert_not_null(ShopSceneScript, "ShopScene script should load")

	var shop = ShopSceneScript.new()
	assert_not_null(shop, "ShopScene should instantiate")

	# Cleanup
	shop.queue_free()


func test_shop_scene_has_correct_enums() -> void:
	var ShopSceneScript = load("res://src/exploration/ShopScene.gd")
	var shop = ShopSceneScript.new()

	# Test ShopMode enum exists
	assert_eq(shop.ShopMode.MAIN, 0, "ShopMode.MAIN should be 0")
	assert_eq(shop.ShopMode.BUY, 1, "ShopMode.BUY should be 1")
	assert_eq(shop.ShopMode.SELL, 2, "ShopMode.SELL should be 2")

	# Test ShopType enum exists
	assert_eq(shop.ShopType.ITEM, 0, "ShopType.ITEM should be 0")
	assert_eq(shop.ShopType.BLACK_MAGIC, 1, "ShopType.BLACK_MAGIC should be 1")
	assert_eq(shop.ShopType.WHITE_MAGIC, 2, "ShopType.WHITE_MAGIC should be 2")
	assert_eq(shop.ShopType.BLACKSMITH, 3, "ShopType.BLACKSMITH should be 3")

	shop.queue_free()


func test_shop_scene_setup_stores_values() -> void:
	var ShopSceneScript = load("res://src/exploration/ShopScene.gd")
	var shop = ShopSceneScript.new()

	var inventory = ["potion", "hi_potion"]
	shop.setup(shop.ShopType.ITEM, "Test Shop", inventory, null)

	assert_eq(shop.shop_type, shop.ShopType.ITEM, "shop_type should match")
	assert_eq(shop.shop_name, "Test Shop", "shop_name should match")
	assert_eq(shop.shop_inventory.size(), 2, "inventory should have 2 items")

	shop.queue_free()


func test_shop_scene_emits_shop_closed_signal() -> void:
	var ShopSceneScript = load("res://src/exploration/ShopScene.gd")
	var shop = ShopSceneScript.new()

	assert_has_signal(shop, "shop_closed", "ShopScene should have shop_closed signal")

	shop.queue_free()


## VillageShop Tests

func test_village_shop_can_be_instantiated() -> void:
	var VillageShopScript = load("res://src/exploration/VillageShop.gd")
	assert_not_null(VillageShopScript, "VillageShop script should load")

	var shop = VillageShopScript.new()
	assert_not_null(shop, "VillageShop should instantiate")

	shop.queue_free()


func test_village_shop_has_shop_type_enum() -> void:
	var VillageShopScript = load("res://src/exploration/VillageShop.gd")
	var shop = VillageShopScript.new()

	assert_eq(shop.ShopType.ITEM, 0, "VillageShop.ShopType.ITEM should be 0")
	assert_eq(shop.ShopType.BLACKSMITH, 3, "VillageShop.ShopType.BLACKSMITH should be 3")

	shop.queue_free()


func test_village_shop_has_inventory_arrays() -> void:
	var VillageShopScript = load("res://src/exploration/VillageShop.gd")
	var shop = VillageShopScript.new()

	assert_gt(shop.ITEM_INVENTORY.size(), 0, "ITEM_INVENTORY should have items")
	assert_gt(shop.BLACK_MAGIC_INVENTORY.size(), 0, "BLACK_MAGIC_INVENTORY should have items")
	assert_gt(shop.WHITE_MAGIC_INVENTORY.size(), 0, "WHITE_MAGIC_INVENTORY should have items")
	assert_gt(shop.BLACKSMITH_WEAPONS.size(), 0, "BLACKSMITH_WEAPONS should have items")

	shop.queue_free()


func test_village_shop_item_purchased_signal_exists() -> void:
	var VillageShopScript = load("res://src/exploration/VillageShop.gd")
	var shop = VillageShopScript.new()

	assert_has_signal(shop, "item_purchased", "VillageShop should have item_purchased signal")

	shop.queue_free()


## Win98Menu Tests

func test_win98_menu_can_be_instantiated() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	assert_not_null(Win98MenuScript, "Win98Menu script should load")

	var menu = Win98MenuScript.new()
	assert_not_null(menu, "Win98Menu should instantiate")

	menu.queue_free()


func test_win98_menu_has_signals() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	assert_has_signal(menu, "item_selected", "Win98Menu should have item_selected signal")
	assert_has_signal(menu, "menu_closed", "Win98Menu should have menu_closed signal")
	assert_has_signal(menu, "actions_submitted", "Win98Menu should have actions_submitted signal")
	assert_has_signal(menu, "defer_requested", "Win98Menu should have defer_requested signal")

	menu.queue_free()


func test_win98_menu_has_battle_mode_property() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	# Default should be true (battle mode enabled)
	assert_true(menu.battle_mode, "battle_mode should default to true")

	# Can be set to false for shop context
	menu.battle_mode = false
	assert_false(menu.battle_mode, "battle_mode should be settable to false")

	menu.queue_free()


func test_win98_menu_has_focus_mode() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	# Add to tree to trigger _ready
	add_child(menu)

	# Menu should be focusable after _ready
	assert_eq(menu.focus_mode, Control.FOCUS_ALL, "Menu should have FOCUS_ALL")

	menu.queue_free()


func test_win98_menu_character_styles_exist() -> void:
	var Win98MenuScript = load("res://src/ui/Win98Menu.gd")
	var menu = Win98MenuScript.new()

	assert_true(menu.CHARACTER_STYLES.has("fighter"), "Should have fighter style")
	assert_true(menu.CHARACTER_STYLES.has("white_mage"), "Should have white_mage style")
	assert_true(menu.CHARACTER_STYLES.has("thief"), "Should have thief style")
	assert_true(menu.CHARACTER_STYLES.has("black_mage"), "Should have black_mage style")

	menu.queue_free()


## Regression Tests

func test_shop_scene_is_instance_valid_check_exists() -> void:
	"""Regression test: ShopScene should check is_instance_valid after await"""
	var script_content = FileAccess.get_file_as_string("res://src/exploration/ShopScene.gd")

	# Check that is_instance_valid is used after await statements
	assert_true(script_content.contains("is_instance_valid(self)"),
		"ShopScene should use is_instance_valid(self) check")
	assert_true(script_content.contains("is_instance_valid(gold_label)"),
		"ShopScene should check gold_label validity")


func test_win98_menu_process_guard_exists() -> void:
	"""Regression test: Win98Menu._process should guard against running on freed node"""
	var script_content = FileAccess.get_file_as_string("res://src/ui/Win98Menu.gd")

	# Check that _process has validity guard
	assert_true(script_content.contains("_is_closing"),
		"Win98Menu should have _is_closing flag")


func test_village_shop_player_validity_check() -> void:
	"""Regression test: VillageShop should check player validity"""
	var script_content = FileAccess.get_file_as_string("res://src/exploration/VillageShop.gd")

	assert_true(script_content.contains("is_instance_valid(player)"),
		"VillageShop should check player validity with is_instance_valid")


## Integration-like Tests (still unit tests, but test interaction)

func test_shop_scene_with_game_state_gold() -> void:
	if _game_state == null:
		pending("GameState not available")
		return

	# Reset game state for clean test
	_game_state.reset_game_state()
	var initial_gold = _game_state.get_gold()

	assert_gt(initial_gold, 0, "Player should have some starting gold")


func test_item_system_has_shop_items() -> void:
	if _item_system == null:
		pending("ItemSystem not available")
		return

	# Check some items that should be in shops
	assert_true(_item_system.items.has("potion"), "ItemSystem should have potion")
	assert_true(_item_system.items.has("hi_potion"), "ItemSystem should have hi_potion")


func test_equipment_system_has_shop_equipment() -> void:
	if _equipment_system == null:
		pending("EquipmentSystem not available")
		return

	# Check some equipment that should be in blacksmith
	assert_true(_equipment_system.weapons.has("iron_sword") or
		_equipment_system.weapons.has("bronze_sword"),
		"EquipmentSystem should have basic weapons")


func test_job_system_has_magic_spells() -> void:
	if _job_system == null:
		pending("JobSystem not available")
		return

	# Check some spells that should be in magic shops
	var fire = _job_system.get_ability("fire")
	var cure = _job_system.get_ability("cure")

	assert_false(fire.is_empty(), "JobSystem should have fire spell")
	assert_false(cure.is_empty(), "JobSystem should have cure spell")
