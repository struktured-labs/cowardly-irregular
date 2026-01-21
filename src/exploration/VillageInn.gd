extends Area2D
class_name VillageInn

## VillageInn - Rest at the inn to restore HP/MP
## Classic JRPG inn functionality

signal rest_completed()

@export var inn_name: String = "Inn"
@export var rest_cost: int = 50  # Gold cost to rest

## Visual
var sprite: Sprite2D
var name_label: Label
var dialogue_box: Control
var dialogue_label: Label

## State
var _player_nearby: bool = false
var _is_showing_menu: bool = false
var _current_player: Node2D = null

const TILE_SIZE: int = 32


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
	_draw_inn(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)


func _draw_inn(image: Image) -> void:
	image.fill(Color.TRANSPARENT)

	var wood = Color(0.45, 0.30, 0.15)
	var wood_dark = Color(0.35, 0.22, 0.10)
	var roof = Color(0.65, 0.25, 0.15)
	var roof_dark = Color(0.50, 0.18, 0.10)
	var window = Color(0.8, 0.85, 0.5)  # Warm light
	var sign_color = Color(0.7, 0.6, 0.4)

	# Roof (triangle shape at top)
	for y in range(0, 20):
		var roof_width = 32 - y
		for x in range(32 - roof_width, 32 + roof_width):
			if x >= 0 and x < 64:
				var c = roof if (x + y) % 4 < 2 else roof_dark
				image.set_pixel(x, y, c)

	# Building body
	for y in range(20, 58):
		for x in range(8, 56):
			var c = wood if (x + y) % 8 < 4 else wood_dark
			image.set_pixel(x, y, c)

	# Door (center)
	for y in range(40, 58):
		for x in range(26, 38):
			image.set_pixel(x, y, wood_dark)
	# Door frame
	for y in range(40, 58):
		image.set_pixel(26, y, Color(0.25, 0.15, 0.08))
		image.set_pixel(37, y, Color(0.25, 0.15, 0.08))
	for x in range(26, 38):
		image.set_pixel(x, 40, Color(0.25, 0.15, 0.08))

	# Windows (left and right)
	for y in range(26, 36):
		for x in range(12, 22):
			image.set_pixel(x, y, window)
		for x in range(42, 52):
			image.set_pixel(x, y, window)

	# Sign hanging from roof
	for y in range(22, 30):
		for x in range(28, 36):
			image.set_pixel(x, y, sign_color)
	# "INN" text (simplified)
	image.set_pixel(30, 25, Color.BLACK)
	image.set_pixel(30, 26, Color.BLACK)
	image.set_pixel(30, 27, Color.BLACK)
	image.set_pixel(32, 25, Color.BLACK)
	image.set_pixel(32, 26, Color.BLACK)
	image.set_pixel(32, 27, Color.BLACK)
	image.set_pixel(33, 26, Color.BLACK)


func _setup_collision() -> void:
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(TILE_SIZE * 2, TILE_SIZE)  # Interaction zone at bottom
	collision.shape = shape
	collision.position = Vector2(0, TILE_SIZE / 2)  # Offset to building front
	add_child(collision)

	collision_layer = 4  # Interactable
	collision_mask = 2   # Player
	monitoring = true
	monitorable = true


func _setup_name_label() -> void:
	name_label = Label.new()
	name_label.text = inn_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-40, -40)
	name_label.size = Vector2(80, 20)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.YELLOW)
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
	panel.position = Vector2(-120, -100)
	panel.size = Vector2(240, 80)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.10, 0.05, 0.95)
	style.border_color = Color(0.7, 0.5, 0.3)
	style.set_border_width_all(3)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)
	dialogue_box.add_child(panel)

	dialogue_label = Label.new()
	dialogue_label.position = Vector2(-112, -92)
	dialogue_label.size = Vector2(224, 64)
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
	_current_player = player
	if _is_showing_menu:
		_rest_party()
	else:
		_show_inn_menu()


func _show_inn_menu() -> void:
	_is_showing_menu = true
	dialogue_box.visible = true
	dialogue_label.text = "Welcome to %s!\nRest and restore your party?\n[Press again to rest, move away to cancel]" % inn_name
	if SoundManager:
		SoundManager.play_ui("menu_open")


func _rest_party() -> void:
	# Restore all party members to full HP/MP
	var game_loop = get_tree().root.get_node_or_null("GameLoop")
	if game_loop and game_loop.party:
		for member in game_loop.party:
			member.current_hp = member.max_hp
			member.current_mp = member.max_mp
			member.current_ap = 0  # Reset AP too

	dialogue_label.text = "Your party is fully rested!\nHP and MP restored."

	if SoundManager:
		SoundManager.play_ui("heal")

	rest_completed.emit()

	# Close after brief delay
	await get_tree().create_timer(1.5).timeout
	_close_menu()


func _close_menu() -> void:
	_is_showing_menu = false
	dialogue_box.visible = false
	_current_player = null
