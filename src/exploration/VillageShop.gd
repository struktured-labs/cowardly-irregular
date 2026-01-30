extends Area2D
class_name VillageShop

## VillageShop - Buy weapons, armor, or items
## Different shop types with different inventories

signal item_purchased(item_id: String)

enum ShopType { WEAPON, ARMOR, ITEM, ACCESSORY }

@export var shop_name: String = "Shop"
@export var shop_type: ShopType = ShopType.ITEM
@export var keeper_name: String = "Shopkeeper"

## Visual
var sprite: Sprite2D
var name_label: Label
var dialogue_box: Control
var dialogue_label: Label

## State
var _player_nearby: bool = false
var _is_showing_menu: bool = false
var _dialogue_state: int = 0

const TILE_SIZE: int = 32

## Shop inventories - expanded with full catalog
const WEAPON_INVENTORY = [
	"bronze_sword", "iron_dagger", "wooden_staff", "bone_staff",
	"iron_sword", "poison_dagger", "oak_staff", "sleep_dagger",
	"steel_sword", "shadow_rod", "war_axe", "thunder_rod",
	"mythril_dagger", "ice_blade", "flame_sword", "crystal_staff",
	"assassin_blade", "mythril_sword", "holy_staff"
]
const ARMOR_INVENTORY = [
	"leather_armor", "cloth_robe", "thief_garb",
	"bone_armor", "chain_mail", "dark_robe",
	"iron_armor", "mage_robe", "ninja_garb",
	"sage_robe", "mythril_vest", "dragon_mail"
]
const ITEM_INVENTORY = [
	"potion", "antidote", "eye_drops", "echo_herbs", "smoke_bomb",
	"hi_potion", "ether", "phoenix_down", "gold_needle",
	"power_drink", "speed_tonic", "defense_tonic", "magic_tonic",
	"bomb_fragment", "lightning_bolt", "holy_water",
	"remedy", "repel", "x_potion", "hi_ether",
	"arctic_wind", "mega_potion", "tent", "mega_ether", "elixir"
]
const ACCESSORY_INVENTORY = [
	"warriors_belt", "power_ring", "magic_ring", "lucky_charm",
	"speed_boots", "resist_ring", "barrier_ring",
	"thiefs_glove", "hp_amulet", "mp_amulet",
	"elven_cloak", "glass_amulet"
]


func _ready() -> void:
	_generate_sprite()
	_setup_collision()
	_setup_name_label()
	_setup_dialogue_box()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _generate_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"

	var image = Image.create(TILE_SIZE * 2, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	_draw_shop(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)


func _draw_shop(image: Image) -> void:
	image.fill(Color.TRANSPARENT)

	# Shop colors based on type
	var main_color: Color
	var accent_color: Color
	match shop_type:
		ShopType.WEAPON:
			main_color = Color(0.4, 0.35, 0.45)  # Grayish purple (smithy)
			accent_color = Color(0.6, 0.55, 0.3)  # Bronze
		ShopType.ARMOR:
			main_color = Color(0.35, 0.40, 0.50)  # Steel blue
			accent_color = Color(0.5, 0.5, 0.55)  # Silver
		ShopType.ITEM:
			main_color = Color(0.25, 0.45, 0.35)  # Forest green
			accent_color = Color(0.7, 0.6, 0.4)  # Tan
		ShopType.ACCESSORY:
			main_color = Color(0.45, 0.30, 0.45)  # Purple
			accent_color = Color(0.8, 0.65, 0.3)  # Gold

	var wood = Color(0.45, 0.30, 0.15)
	var wood_dark = Color(0.35, 0.22, 0.10)
	var window = Color(0.7, 0.8, 0.9)

	# Awning at top
	for y in range(0, 16):
		for x in range(4, 60):
			var stripe = ((x + y) / 4) % 2 == 0
			image.set_pixel(x, y, accent_color if stripe else main_color)

	# Building body
	for y in range(16, 58):
		for x in range(8, 56):
			var c = wood if (x + y) % 8 < 4 else wood_dark
			image.set_pixel(x, y, c)

	# Large window/counter at front
	for y in range(24, 44):
		for x in range(14, 50):
			image.set_pixel(x, y, window)

	# Counter shelf
	for y in range(42, 46):
		for x in range(12, 52):
			image.set_pixel(x, y, wood_dark)

	# Display items on counter based on shop type
	match shop_type:
		ShopType.WEAPON:
			# Swords
			for y in range(28, 40):
				image.set_pixel(20, y, Color(0.6, 0.6, 0.65))
				image.set_pixel(32, y, Color(0.6, 0.6, 0.65))
				image.set_pixel(44, y, Color(0.5, 0.4, 0.3))
		ShopType.ARMOR:
			# Shields/armor pieces
			for y in range(30, 40):
				for x in range(18, 26):
					image.set_pixel(x, y, Color(0.5, 0.5, 0.55))
				for x in range(38, 46):
					image.set_pixel(x, y, Color(0.4, 0.3, 0.2))
		ShopType.ITEM:
			# Potions
			for y in range(32, 40):
				image.set_pixel(20, y, Color(0.9, 0.3, 0.3))  # Red potion
				image.set_pixel(22, y, Color(0.9, 0.3, 0.3))
				image.set_pixel(32, y, Color(0.3, 0.5, 0.9))  # Blue potion
				image.set_pixel(34, y, Color(0.3, 0.5, 0.9))
				image.set_pixel(44, y, Color(0.3, 0.8, 0.3))  # Green potion
				image.set_pixel(46, y, Color(0.3, 0.8, 0.3))

	# Sign
	for y in range(4, 14):
		for x in range(24, 40):
			image.set_pixel(x, y, Color(0.8, 0.75, 0.6))


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)
	collision.shape = shape
	collision.position = Vector2(0, TILE_SIZE / 2)
	add_child(collision)

	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = shop_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-50, -40)
	name_label.size = Vector2(100, 20)
	name_label.add_theme_font_size_override("font_size", 12)

	# Color based on type
	match shop_type:
		ShopType.WEAPON:
			name_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
		ShopType.ARMOR:
			name_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		ShopType.ITEM:
			name_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))

	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.visible = false
	add_child(name_label)


func _setup_dialogue_box() -> void:
	dialogue_box = Control.new()
	dialogue_box.name = "DialogueBox"
	dialogue_box.visible = false
	dialogue_box.z_index = 100

	var panel = Panel.new()
	panel.position = Vector2(-140, -120)
	panel.size = Vector2(280, 100)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.6, 0.6, 0.7)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue_box.add_child(panel)

	dialogue_label = Label.new()
	dialogue_label.position = Vector2(-132, -112)
	dialogue_label.size = Vector2(264, 84)
	dialogue_label.add_theme_font_size_override("font_size", 11)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_box.add_child(dialogue_label)

	add_child(dialogue_box)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = true
		name_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		_close_menu()


func interact(player: Node2D) -> void:
	if _is_showing_menu:
		_advance_dialogue()
	else:
		_show_shop_menu()


func _show_shop_menu() -> void:
	_is_showing_menu = true

	# Open the ShopScene
	var shop_scene = preload("res://src/exploration/ShopScene.gd").new()
	shop_scene.setup(_get_shop_type_enum(), shop_name, _get_inventory())

	# Disable player movement
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_can_move"):
		player.set_can_move(false)

	# Add shop to scene
	get_tree().root.add_child(shop_scene)
	shop_scene.shop_closed.connect(_on_shop_closed.bind(player))

	if SoundManager:
		SoundManager.play_ui("menu_open")


func _on_shop_closed(player: Node) -> void:
	"""Handle shop closing"""
	_is_showing_menu = false

	# Re-enable player movement
	if player and player.has_method("set_can_move"):
		player.set_can_move(true)

	if SoundManager:
		SoundManager.play_ui("menu_close")


func _get_shop_type_enum() -> int:
	"""Convert ShopType enum to ShopScene.ShopType enum"""
	match shop_type:
		ShopType.WEAPON:
			return 0  # ShopScene.ShopType.WEAPON
		ShopType.ARMOR:
			return 1  # ShopScene.ShopType.ARMOR
		ShopType.ITEM:
			return 2  # ShopScene.ShopType.ITEM
		ShopType.ACCESSORY:
			return 3  # ShopScene.ShopType.ACCESSORY
	return 2


func _advance_dialogue() -> void:
	_dialogue_state += 1
	_update_dialogue()


func _update_dialogue() -> void:
	var inventory = _get_inventory()
	var type_name = _get_type_name()

	match _dialogue_state:
		0:
			dialogue_label.text = "%s: Welcome to %s!\nWe have the finest %s in town." % [keeper_name, shop_name, type_name]
		1:
			dialogue_label.text = "Available:\n%s\n[Shop system coming soon!]" % _format_inventory(inventory)
		_:
			dialogue_label.text = "Thanks for stopping by!\nCome again soon."
			# Close after this
			await get_tree().create_timer(1.0).timeout
			_close_menu()


func _get_inventory() -> Array:
	match shop_type:
		ShopType.WEAPON:
			return WEAPON_INVENTORY
		ShopType.ARMOR:
			return ARMOR_INVENTORY
		ShopType.ITEM:
			return ITEM_INVENTORY
		ShopType.ACCESSORY:
			return ACCESSORY_INVENTORY
	return []


func _get_type_name() -> String:
	match shop_type:
		ShopType.WEAPON:
			return "weapons"
		ShopType.ARMOR:
			return "armor"
		ShopType.ITEM:
			return "items"
		ShopType.ACCESSORY:
			return "accessories"
	return "goods"


func _format_inventory(items: Array) -> String:
	var result = ""
	for i in range(min(items.size(), 4)):
		var item_name = items[i].replace("_", " ").capitalize()
		result += "- %s\n" % item_name
	if items.size() > 4:
		result += "...and more!"
	return result


func _close_menu() -> void:
	_is_showing_menu = false
	_dialogue_state = 0
	dialogue_box.visible = false
