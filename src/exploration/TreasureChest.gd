extends Area2D
class_name TreasureChest

## TreasureChest - Openable treasure container
## Contains items, gold, or equipment

signal chest_opened(contents: Dictionary)

@export var chest_id: String = "chest_001"  # Unique ID for save tracking
@export var contents_type: String = "item"  # item, gold, equipment
@export var contents_id: String = "potion"
@export var contents_amount: int = 1
@export var gold_amount: int = 100

## Visual
var sprite: Sprite2D
var name_label: Label
var dialogue_box: Control
var dialogue_label: Label

## State
var _is_opened: bool = false
var _player_nearby: bool = false

const TILE_SIZE: int = 32


func _ready() -> void:
	_check_if_opened()
	_generate_sprite()
	_setup_collision()
	_setup_name_label()
	_setup_dialogue_box()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _check_if_opened() -> void:
	# Check GameState for opened chests (if implemented)
	# For now, all chests start closed
	_is_opened = false


func _generate_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "Sprite"

	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_chest(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)


func _draw_chest(image: Image) -> void:
	image.fill(Color.TRANSPARENT)

	var wood = Color(0.5, 0.35, 0.15) if not _is_opened else Color(0.4, 0.28, 0.12)
	var wood_dark = Color(0.35, 0.22, 0.10)
	var metal = Color(0.7, 0.6, 0.2)  # Gold trim
	var metal_dark = Color(0.5, 0.4, 0.15)

	if _is_opened:
		# Open chest - lid tilted back
		# Lid (back, tilted)
		for y in range(4, 12):
			for x in range(6, 26):
				image.set_pixel(x, y, wood_dark)

		# Chest body (front)
		for y in range(14, 28):
			for x in range(4, 28):
				if x == 4 or x == 27 or y == 14 or y == 27:
					image.set_pixel(x, y, metal)
				else:
					image.set_pixel(x, y, wood)

		# Open interior (dark)
		for y in range(15, 20):
			for x in range(6, 26):
				image.set_pixel(x, y, Color(0.15, 0.1, 0.05))

		# Sparkles for found treasure
		image.set_pixel(10, 17, Color.YELLOW)
		image.set_pixel(20, 18, Color.YELLOW)

	else:
		# Closed chest
		# Lid (top)
		for y in range(6, 14):
			for x in range(4, 28):
				if y == 6:
					image.set_pixel(x, y, metal)
				else:
					var c = wood if (x % 4 < 2) else wood_dark
					image.set_pixel(x, y, c)

		# Chest body
		for y in range(14, 28):
			for x in range(4, 28):
				if x == 4 or x == 27 or y == 14 or y == 27:
					image.set_pixel(x, y, metal)
				else:
					var c = wood if (x % 4 < 2) else wood_dark
					image.set_pixel(x, y, c)

		# Lock
		for y in range(16, 22):
			for x in range(14, 18):
				image.set_pixel(x, y, metal)
		image.set_pixel(15, 18, metal_dark)
		image.set_pixel(16, 18, metal_dark)

		# Gleam effect
		image.set_pixel(8, 8, Color(1.0, 1.0, 0.8, 0.8))
		image.set_pixel(9, 9, Color(1.0, 1.0, 0.8, 0.5))


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE, TILE_SIZE)
	collision.shape = shape
	add_child(collision)

	collision_layer = 4
	collision_mask = 2
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = "Treasure" if not _is_opened else "(Empty)"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-30, -24)
	name_label.size = Vector2(60, 20)
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.GOLD if not _is_opened else Color.GRAY)
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
	panel.position = Vector2(-100, -70)
	panel.size = Vector2(200, 50)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.08, 0.05, 0.95)
	style.border_color = Color.GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue_box.add_child(panel)

	dialogue_label = Label.new()
	dialogue_label.position = Vector2(-92, -62)
	dialogue_label.size = Vector2(184, 34)
	dialogue_label.add_theme_font_size_override("font_size", 11)
	dialogue_label.add_theme_color_override("font_color", Color.WHITE)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue_box.add_child(dialogue_label)

	add_child(dialogue_box)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = true
		if not _is_opened:
			name_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		dialogue_box.visible = false


func interact(player: Node2D) -> void:
	if _is_opened:
		dialogue_box.visible = true
		dialogue_label.text = "The chest is empty."
		await get_tree().create_timer(1.0).timeout
		dialogue_box.visible = false
		return

	_open_chest(player)


func _open_chest(player: Node2D) -> void:
	_is_opened = true

	# Play sound
	if SoundManager:
		SoundManager.play_ui("chest_open")

	# Update sprite
	var image = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	_draw_chest(image)
	sprite.texture = ImageTexture.create_from_image(image)

	# Update label
	name_label.text = "(Empty)"
	name_label.add_theme_color_override("font_color", Color.GRAY)
	name_label.visible = true

	# Give contents to player
	var contents_text = ""
	match contents_type:
		"gold":
			contents_text = "Found %d Gold!" % gold_amount
			# Add gold to party (if implemented)
		"item":
			var item_name = contents_id.replace("_", " ").capitalize()
			contents_text = "Found %s x%d!" % [item_name, contents_amount]
			# Add items to party
			var game_loop = get_tree().root.get_node_or_null("GameLoop")
			if game_loop and game_loop.party.size() > 0:
				game_loop.party[0].add_item(contents_id, contents_amount)
		"equipment":
			var equip_name = contents_id.replace("_", " ").capitalize()
			contents_text = "Found %s!" % equip_name
			# Add to equipment pool
			var game_loop = get_tree().root.get_node_or_null("GameLoop")
			if game_loop:
				var pool_key = "weapons"  # Default, should determine from item
				if "armor" in contents_id or "robe" in contents_id or "mail" in contents_id:
					pool_key = "armors"
				elif "ring" in contents_id or "amulet" in contents_id or "boots" in contents_id:
					pool_key = "accessories"
				if not game_loop.equipment_pool.has(pool_key):
					game_loop.equipment_pool[pool_key] = []
				game_loop.equipment_pool[pool_key].append(contents_id)

	# Show dialogue
	dialogue_box.visible = true
	dialogue_label.text = contents_text

	chest_opened.emit({"type": contents_type, "id": contents_id, "amount": contents_amount})

	# Hide after delay
	await get_tree().create_timer(2.0).timeout
	dialogue_box.visible = false
