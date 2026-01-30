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

	# Shop colors based on type (SNES-quality multi-tone palettes)
	var main_color: Color
	var main_light: Color
	var main_dark: Color
	var accent_color: Color
	var accent_light: Color
	match shop_type:
		ShopType.WEAPON:
			main_color = Color(0.40, 0.35, 0.45)
			main_light = Color(0.52, 0.48, 0.58)
			main_dark = Color(0.28, 0.24, 0.32)
			accent_color = Color(0.60, 0.55, 0.30)
			accent_light = Color(0.75, 0.68, 0.40)
		ShopType.ARMOR:
			main_color = Color(0.35, 0.40, 0.50)
			main_light = Color(0.48, 0.52, 0.62)
			main_dark = Color(0.22, 0.28, 0.38)
			accent_color = Color(0.50, 0.50, 0.55)
			accent_light = Color(0.65, 0.65, 0.70)
		ShopType.ITEM:
			main_color = Color(0.25, 0.45, 0.35)
			main_light = Color(0.35, 0.58, 0.45)
			main_dark = Color(0.15, 0.32, 0.24)
			accent_color = Color(0.70, 0.60, 0.40)
			accent_light = Color(0.82, 0.72, 0.52)
		ShopType.ACCESSORY:
			main_color = Color(0.45, 0.30, 0.45)
			main_light = Color(0.58, 0.42, 0.58)
			main_dark = Color(0.32, 0.18, 0.32)
			accent_color = Color(0.80, 0.65, 0.30)
			accent_light = Color(0.92, 0.78, 0.42)
		_:
			main_color = Color(0.40, 0.35, 0.30)
			main_light = Color(0.52, 0.48, 0.42)
			main_dark = Color(0.28, 0.22, 0.18)
			accent_color = Color(0.65, 0.55, 0.35)
			accent_light = Color(0.78, 0.68, 0.48)

	var wood = Color(0.48, 0.32, 0.16)
	var wood_light = Color(0.58, 0.42, 0.22)
	var wood_dark = Color(0.35, 0.22, 0.10)
	var wood_grain = Color(0.42, 0.28, 0.14)
	var window = Color(0.72, 0.82, 0.92)
	var window_light = Color(0.85, 0.90, 0.98)
	var window_frame = Color(0.25, 0.18, 0.10)
	var outline = Color(0.12, 0.08, 0.05)

	# Awning with proper stripe shading and scalloped bottom edge
	for y in range(0, 16):
		var awning_sag = int(sin(y * 0.4) * 1.5)  # Slight fabric sag
		for x in range(4, 60):
			var stripe_phase = ((x + y) / 4) % 2 == 0
			var c = accent_color if stripe_phase else main_color
			# Top of awning lighter, bottom darker (fabric drape shading)
			if y < 4:
				c = (accent_light if stripe_phase else main_light)
			elif y > 12:
				c = c.darkened(0.1)
			# Left-right shading
			if x < 10:
				c = c.darkened(0.1)
			elif x > 54:
				c = c.darkened(0.1)
			image.set_pixel(x, y, c)
	# Scalloped bottom edge of awning
	for x in range(4, 60):
		var scallop = int(sin(x * 0.5) * 1.5) + 15
		if scallop >= 0 and scallop < 64:
			image.set_pixel(x, scallop, main_dark)

	# Building body with wood plank texture and shading
	for y in range(16, 58):
		for x in range(8, 56):
			var c = wood
			# Horizontal plank lines
			if (y - 16) % 8 == 0:
				c = wood_dark
			# Wood grain texture
			elif (x + y * 3) % 7 == 0:
				c = wood_grain
			# Left wall shadow, right wall highlight
			elif x < 14:
				c = wood_dark
			elif x > 50:
				c = wood_dark
			elif x < 18:
				c = wood
			elif x > 46:
				c = wood
			else:
				# Alternate light/dark planks for depth
				c = wood if ((y - 16) / 8) % 2 == 0 else wood_light
			image.set_pixel(x, y, c)
	# Building outline
	for y in range(16, 58):
		image.set_pixel(8, y, outline)
		image.set_pixel(55, y, outline)
	for x in range(8, 56):
		image.set_pixel(x, 57, outline)

	# Large window/counter with frame and cross-bar
	# Window frame
	for y in range(22, 46):
		for x in range(12, 52):
			if y == 22 or y == 45 or x == 12 or x == 51:
				image.set_pixel(x, y, window_frame)
			elif y == 23 or x == 13:
				image.set_pixel(x, y, wood_light)  # Inner frame highlight
	# Window glass with slight gradient
	for y in range(24, 44):
		for x in range(14, 50):
			var grad = float(y - 24) / 20.0
			var c = window_light.lerp(window, grad)
			# Vertical dividers
			if x == 25 or x == 38:
				c = window_frame
			image.set_pixel(x, y, c)

	# Counter shelf with 3D beveled edge
	for y in range(42, 47):
		for x in range(10, 54):
			var c = wood_dark
			if y == 42:
				c = wood_light  # Top highlight
			elif y == 43:
				c = wood
			elif y == 46:
				c = outline  # Shadow underneath
			image.set_pixel(x, y, c)

	# Display items on counter based on shop type (SNES quality)
	match shop_type:
		ShopType.WEAPON:
			# Detailed sword silhouettes with hilts
			var sword_colors = [Color(0.65, 0.65, 0.70), Color(0.55, 0.55, 0.60), Color(0.52, 0.42, 0.32)]
			var sword_x_pos = [20, 32, 44]
			for i in range(3):
				var sx = sword_x_pos[i]
				var sc = sword_colors[i]
				# Blade
				for y in range(28, 39):
					image.set_pixel(sx, y, sc)
					image.set_pixel(sx + 1, y, sc.darkened(0.1))
				# Crossguard
				for x in range(sx - 2, sx + 4):
					image.set_pixel(x, 39, sc.darkened(0.2))
				# Grip
				image.set_pixel(sx, 40, Color(0.4, 0.25, 0.15))
				image.set_pixel(sx, 41, Color(0.4, 0.25, 0.15))
				# Blade tip shine
				image.set_pixel(sx, 28, sc.lightened(0.3))
		ShopType.ARMOR:
			# Shield and breastplate
			# Shield (round with emblem)
			for y in range(28, 40):
				for x in range(17, 27):
					var dx = abs(x - 22.0)
					var dy = abs(y - 34.0)
					if dx * dx / 25.0 + dy * dy / 36.0 < 1.0:
						var c = Color(0.52, 0.52, 0.58)
						if dx + dy < 3:
							c = Color(0.70, 0.65, 0.30)  # Center emblem
						elif y < 32:
							c = Color(0.62, 0.62, 0.68)  # Top highlight
						image.set_pixel(x, y, c)
			# Breastplate
			for y in range(29, 41):
				for x in range(37, 47):
					var rel_y = float(y - 29) / 12.0
					var c = Color(0.45, 0.35, 0.25)
					if rel_y < 0.3:
						c = Color(0.55, 0.45, 0.32)
					elif rel_y > 0.7:
						c = Color(0.35, 0.25, 0.18)
					if x == 37 or x == 46:
						c = c.darkened(0.15)
					image.set_pixel(x, y, c)
		ShopType.ITEM:
			# Detailed potion bottles with cork and liquid
			var potion_data = [
				[19, Color(0.92, 0.30, 0.28), Color(1.0, 0.5, 0.45)],   # Red HP
				[31, Color(0.28, 0.48, 0.92), Color(0.45, 0.65, 1.0)],   # Blue MP
				[43, Color(0.28, 0.82, 0.32), Color(0.50, 0.95, 0.55)],  # Green antidote
			]
			for p in potion_data:
				var px = p[0]
				var liquid = p[1]
				var liquid_light = p[2]
				# Cork
				image.set_pixel(px, 30, Color(0.55, 0.42, 0.28))
				image.set_pixel(px + 1, 30, Color(0.55, 0.42, 0.28))
				# Bottle neck
				image.set_pixel(px, 31, Color(0.75, 0.82, 0.88))
				image.set_pixel(px + 1, 31, Color(0.65, 0.72, 0.78))
				# Bottle body with liquid
				for y in range(32, 41):
					var bottle_w = 2 if y < 34 else 3
					for dx in range(-bottle_w + 1, bottle_w + 1):
						var bx = px + dx
						if bx >= 0 and bx < 64:
							var c = liquid
							if y < 34:
								c = Color(0.70, 0.78, 0.85)  # Empty upper part
							elif dx == -bottle_w + 1:
								c = liquid_light  # Left highlight
							image.set_pixel(bx, y, c)
		ShopType.ACCESSORY:
			# Ring and amulet display
			# Ring on cushion
			for y in range(34, 40):
				for x in range(17, 27):
					image.set_pixel(x, y, Color(0.55, 0.20, 0.25))  # Red cushion
			# Ring
			for angle in range(12):
				var rx = 22 + int(cos(angle * 0.52) * 3)
				var ry = 33 + int(sin(angle * 0.52) * 2)
				if rx >= 0 and rx < 64 and ry >= 0 and ry < 64:
					image.set_pixel(rx, ry, Color(0.85, 0.75, 0.30))
			# Amulet
			for y in range(30, 40):
				for x in range(38, 46):
					var dx = abs(x - 42.0)
					var dy = abs(y - 36.0)
					if dx + dy < 4:
						image.set_pixel(x, y, Color(0.82, 0.68, 0.28))
			# Chain
			for y in range(28, 32):
				image.set_pixel(42, y, Color(0.75, 0.65, 0.25))

	# Shop sign with detailed lettering area
	var sign_bg = Color(0.78, 0.72, 0.58)
	var sign_dark = Color(0.58, 0.52, 0.38)
	for y in range(2, 14):
		for x in range(22, 42):
			var c = sign_bg
			if x == 22 or x == 41 or y == 2 or y == 13:
				c = sign_dark  # Border
			elif y == 3 or x == 23:
				c = Color(0.85, 0.80, 0.65)  # Highlight
			image.set_pixel(x, y, c)
	# Hanging hooks
	image.set_pixel(24, 1, outline)
	image.set_pixel(39, 1, outline)


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
