extends Area2D
class_name VillageShop

## VillageShop - Buy weapons, armor, or items
## Different shop types with different inventories

signal item_purchased(item_id: String)

enum ShopType { ITEM, BLACK_MAGIC, WHITE_MAGIC, BLACKSMITH }

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

## Shop inventories
const ITEM_INVENTORY = [
	"potion", "antidote", "eye_drops", "echo_herbs", "smoke_bomb",
	"hi_potion", "ether", "phoenix_down", "gold_needle",
	"power_drink", "speed_tonic", "defense_tonic", "magic_tonic",
	"bomb_fragment", "lightning_bolt", "holy_water",
	"remedy", "repel", "x_potion", "hi_ether",
	"arctic_wind", "mega_potion", "tent", "mega_ether", "elixir"
]
const BLACK_MAGIC_INVENTORY = ["fire", "blizzard", "thunder", "fira"]
const WHITE_MAGIC_INVENTORY = ["cure", "cura", "raise", "protect"]
const BLACKSMITH_WEAPONS = [
	"bronze_sword", "iron_dagger", "wooden_staff", "bone_staff",
	"iron_sword", "poison_dagger", "oak_staff", "sleep_dagger",
	"steel_sword", "shadow_rod", "war_axe", "thunder_rod",
	"mythril_dagger", "ice_blade", "flame_sword", "crystal_staff",
	"assassin_blade", "mythril_sword", "holy_staff"
]
const BLACKSMITH_ARMOR = [
	"leather_armor", "cloth_robe", "thief_garb",
	"bone_armor", "chain_mail", "dark_robe",
	"iron_armor", "mage_robe", "ninja_garb",
	"sage_robe", "mythril_vest", "dragon_mail"
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
		ShopType.ITEM:
			main_color = Color(0.25, 0.45, 0.35)
			main_light = Color(0.35, 0.58, 0.45)
			main_dark = Color(0.15, 0.32, 0.24)
			accent_color = Color(0.70, 0.60, 0.40)
			accent_light = Color(0.82, 0.72, 0.52)
		ShopType.BLACK_MAGIC:
			main_color = Color(0.30, 0.18, 0.40)
			main_light = Color(0.42, 0.28, 0.55)
			main_dark = Color(0.18, 0.10, 0.28)
			accent_color = Color(0.55, 0.30, 0.65)
			accent_light = Color(0.70, 0.45, 0.80)
		ShopType.WHITE_MAGIC:
			main_color = Color(0.85, 0.82, 0.75)
			main_light = Color(0.95, 0.92, 0.88)
			main_dark = Color(0.65, 0.60, 0.55)
			accent_color = Color(0.80, 0.70, 0.35)
			accent_light = Color(0.92, 0.82, 0.48)
		ShopType.BLACKSMITH:
			main_color = Color(0.45, 0.30, 0.18)
			main_light = Color(0.58, 0.40, 0.25)
			main_dark = Color(0.32, 0.20, 0.10)
			accent_color = Color(0.75, 0.45, 0.20)
			accent_light = Color(0.88, 0.58, 0.30)
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
		ShopType.ITEM:
			# Potion bottles with cork and liquid
			var potion_data = [
				[19, Color(0.92, 0.30, 0.28), Color(1.0, 0.5, 0.45)],   # Red HP
				[31, Color(0.28, 0.48, 0.92), Color(0.45, 0.65, 1.0)],   # Blue MP
				[43, Color(0.28, 0.82, 0.32), Color(0.50, 0.95, 0.55)],  # Green antidote
			]
			for p in potion_data:
				var px = p[0]
				var liquid = p[1]
				var liquid_light = p[2]
				image.set_pixel(px, 30, Color(0.55, 0.42, 0.28))
				image.set_pixel(px + 1, 30, Color(0.55, 0.42, 0.28))
				image.set_pixel(px, 31, Color(0.75, 0.82, 0.88))
				image.set_pixel(px + 1, 31, Color(0.65, 0.72, 0.78))
				for y in range(32, 41):
					var bottle_w = 2 if y < 34 else 3
					for dx in range(-bottle_w + 1, bottle_w + 1):
						var bx = px + dx
						if bx >= 0 and bx < 64:
							var c = liquid if y >= 34 else Color(0.70, 0.78, 0.85)
							if y >= 34 and dx == -bottle_w + 1:
								c = liquid_light
							image.set_pixel(bx, y, c)
		ShopType.BLACK_MAGIC:
			# Glowing rune crystal ball on counter
			for y in range(28, 40):
				for x in range(26, 38):
					var dx2 = abs(x - 32.0)
					var dy2 = abs(y - 34.0)
					if dx2 * dx2 / 36.0 + dy2 * dy2 / 36.0 < 1.0:
						var glow = 1.0 - (dx2 + dy2) / 12.0
						image.set_pixel(x, y, Color(0.4 + glow * 0.3, 0.15, 0.6 + glow * 0.2))
			# Small flame icons on each side
			for side_x in [18, 44]:
				for dy in range(5):
					var flame_w = 2 if dy > 1 else 1
					for dx in range(-flame_w, flame_w + 1):
						var fy = 38 - dy
						image.set_pixel(side_x + dx, fy, Color(0.6 + dy * 0.08, 0.2 + dy * 0.04, 0.8))
		ShopType.WHITE_MAGIC:
			# Star/cross symbol on counter
			var star_cx = 32
			var star_cy = 34
			var star_color = Color(0.95, 0.90, 0.60)
			var star_glow = Color(0.80, 0.75, 0.45)
			# Vertical bar
			for dy in range(-5, 6):
				image.set_pixel(star_cx, star_cy + dy, star_color)
				if abs(dy) < 4:
					image.set_pixel(star_cx + 1, star_cy + dy, star_glow)
			# Horizontal bar
			for dx in range(-5, 6):
				image.set_pixel(star_cx + dx, star_cy, star_color)
				if abs(dx) < 4:
					image.set_pixel(star_cx + dx, star_cy + 1, star_glow)
			# Candles
			for candle_x in [20, 44]:
				for dy in range(4):
					image.set_pixel(candle_x, 37 - dy, Color(0.85, 0.80, 0.70))
				image.set_pixel(candle_x, 33, Color(1.0, 0.85, 0.30))  # Flame
				image.set_pixel(candle_x, 32, Color(1.0, 0.70, 0.20))
		ShopType.BLACKSMITH:
			# Anvil on counter
			for y in range(33, 40):
				var anvil_w = 6 if y > 36 else (4 if y > 34 else 3)
				for dx in range(-anvil_w, anvil_w + 1):
					var c = Color(0.45, 0.42, 0.40)
					if y == 33:
						c = Color(0.55, 0.52, 0.50)  # Top highlight
					elif dx == -anvil_w or dx == anvil_w:
						c = Color(0.35, 0.32, 0.30)
					image.set_pixel(32 + dx, y, c)
			# Sword on left
			for y in range(28, 39):
				image.set_pixel(20, y, Color(0.65, 0.65, 0.70))
				image.set_pixel(21, y, Color(0.55, 0.55, 0.60))
			for x in range(18, 24):
				image.set_pixel(x, 39, Color(0.50, 0.45, 0.40))
			# Shield on right
			for y in range(30, 40):
				for x in range(40, 48):
					var sdx = abs(x - 44.0)
					var sdy = abs(y - 35.0)
					if sdx * sdx / 16.0 + sdy * sdy / 25.0 < 1.0:
						image.set_pixel(x, y, Color(0.52, 0.52, 0.58))

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
		ShopType.ITEM:
			name_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		ShopType.BLACK_MAGIC:
			name_label.add_theme_color_override("font_color", Color(0.7, 0.4, 0.9))
		ShopType.WHITE_MAGIC:
			name_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.75))
		ShopType.BLACKSMITH:
			name_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))

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
	var ShopkeeperDataScript = preload("res://src/exploration/ShopkeeperData.gd")
	var keeper_custom = ShopkeeperDataScript.get_shopkeeper_for_type(shop_type)
	shop_scene.setup(_get_shop_type_enum(), shop_name, _get_inventory(), keeper_custom)

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
	return shop_type


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
		ShopType.ITEM:
			return ITEM_INVENTORY
		ShopType.BLACK_MAGIC:
			return BLACK_MAGIC_INVENTORY
		ShopType.WHITE_MAGIC:
			return WHITE_MAGIC_INVENTORY
		ShopType.BLACKSMITH:
			return BLACKSMITH_WEAPONS + BLACKSMITH_ARMOR
	return []


func _get_type_name() -> String:
	match shop_type:
		ShopType.ITEM:
			return "items"
		ShopType.BLACK_MAGIC:
			return "black magic"
		ShopType.WHITE_MAGIC:
			return "white magic"
		ShopType.BLACKSMITH:
			return "weapons and armor"
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
