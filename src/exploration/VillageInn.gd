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

	var wood = Color(0.48, 0.32, 0.16)
	var wood_light = Color(0.58, 0.42, 0.22)
	var wood_dark = Color(0.35, 0.22, 0.10)
	var wood_grain = Color(0.42, 0.28, 0.14)
	var roof = Color(0.68, 0.26, 0.16)
	var roof_light = Color(0.78, 0.35, 0.22)
	var roof_dark = Color(0.50, 0.18, 0.10)
	var roof_shadow = Color(0.42, 0.14, 0.08)
	var window = Color(0.82, 0.85, 0.50)
	var window_bright = Color(0.95, 0.92, 0.65)
	var sign_color = Color(0.72, 0.62, 0.42)
	var sign_light = Color(0.82, 0.72, 0.52)
	var outline = Color(0.15, 0.10, 0.05)

	# Roof with proper triangular shading and tile texture
	for y in range(0, 20):
		var roof_width = 32 - y
		for x in range(32 - roof_width, 32 + roof_width):
			if x >= 0 and x < 64:
				var c = roof
				# Tile row shading (horizontal bands for shingle rows)
				var row = (y / 3) % 2
				if row == 0:
					c = roof
				else:
					c = roof_dark
				# Left side = lit, right side = shadow
				if x < 32:
					if y < 8:
						c = roof_light  # Peak highlight
					elif y < 14:
						c = roof
				else:
					c = c.darkened(0.1)
				# Edge outlines
				var edge_dist_l = abs(x - (32 - roof_width))
				var edge_dist_r = abs(x - (32 + roof_width - 1))
				if edge_dist_l < 1 or edge_dist_r < 1:
					c = outline
				if y == 0 and abs(x - 32) < 2:
					c = roof_light  # Peak highlight
				# Tile texture detail
				if y > 2 and (x + y * 2) % 6 == 0:
					c = c.darkened(0.06)
				image.set_pixel(x, y, c)

	# Eaves (overhang shadow)
	for x in range(6, 58):
		if x >= 0 and x < 64:
			image.set_pixel(x, 20, roof_shadow)
			image.set_pixel(x, 21, roof_dark)

	# Building body with plank texture and shading
	for y in range(22, 58):
		for x in range(8, 56):
			var c = wood
			# Plank lines
			if (y - 22) % 7 == 0:
				c = wood_dark
			# Wood grain
			elif (x * 3 + y) % 9 == 0:
				c = wood_grain
			# Left wall darker (shadow), right wall lighter
			elif x < 14:
				c = wood_dark
			elif x > 50:
				c = wood_dark
			elif ((y - 22) / 7) % 2 == 0:
				c = wood
			else:
				c = wood_light
			image.set_pixel(x, y, c)
	# Building outline
	for y in range(22, 58):
		image.set_pixel(8, y, outline)
		image.set_pixel(55, y, outline)
	for x in range(8, 56):
		image.set_pixel(x, 57, outline)

	# Door (center) with wood grain and frame
	for y in range(40, 57):
		for x in range(26, 38):
			var c = wood_dark
			# Door panel shading
			if x > 28 and x < 36 and y > 42 and y < 55:
				# Recessed panel
				if x == 29 or y == 43:
					c = wood  # Panel edge highlight
				elif x == 35 or y == 54:
					c = Color(0.25, 0.15, 0.08)  # Panel edge shadow
				else:
					c = Color(0.30, 0.18, 0.09)
			# Wood grain on door
			elif (y + x * 2) % 5 == 0:
				c = Color(0.28, 0.16, 0.08)
			image.set_pixel(x, y, c)
	# Door frame
	for y in range(39, 57):
		image.set_pixel(25, y, outline)
		image.set_pixel(38, y, outline)
	for x in range(25, 39):
		image.set_pixel(x, 39, outline)
	# Doorknob
	image.set_pixel(35, 48, Color(0.72, 0.62, 0.30))
	image.set_pixel(35, 49, Color(0.55, 0.45, 0.22))
	# Step at door base
	for x in range(24, 40):
		image.set_pixel(x, 57, Color(0.52, 0.48, 0.42))

	# Windows with frame, cross-bar, and warm glow
	for win_x in [[12, 22], [42, 52]]:
		# Window frame
		for y in range(25, 37):
			for x in range(win_x[0] - 1, win_x[1] + 1):
				if y == 25 or y == 36 or x == win_x[0] - 1 or x == win_x[1]:
					if x >= 0 and x < 64:
						image.set_pixel(x, y, outline)
		# Window glass with warm light gradient
		for y in range(26, 36):
			for x in range(win_x[0], win_x[1]):
				var grad = float(y - 26) / 10.0
				var c = window_bright.lerp(window, grad)
				# Cross-bar
				if x == (win_x[0] + win_x[1]) / 2 or y == 31:
					c = outline
				image.set_pixel(x, y, c)
		# Window sill
		for x in range(win_x[0] - 1, win_x[1] + 1):
			if x >= 0 and x < 64:
				image.set_pixel(x, 37, wood_light)

	# Chimney on right side of roof
	for y in range(0, 12):
		for x in range(46, 52):
			if x < 64:
				var c = Color(0.55, 0.32, 0.22) if y % 3 < 2 else Color(0.42, 0.24, 0.15)
				if x == 46 or x == 51:
					c = outline
				image.set_pixel(x, y, c)
	# Chimney smoke (subtle)
	image.set_pixel(48, 0, Color(0.6, 0.6, 0.6, 0.3))
	image.set_pixel(49, 0, Color(0.6, 0.6, 0.6, 0.2))

	# Sign hanging from roof with detail
	# Hanging chains
	image.set_pixel(30, 21, outline)
	image.set_pixel(34, 21, outline)
	# Sign board
	for y in range(22, 30):
		for x in range(27, 37):
			var c = sign_color
			if x == 27 or x == 36 or y == 22 or y == 29:
				c = outline  # Border
			elif y == 23 or x == 28:
				c = sign_light  # Highlight
			image.set_pixel(x, y, c)
	# "INN" text (better pixel lettering)
	# I
	for y in range(24, 28):
		image.set_pixel(29, y, outline)
	# N
	for y in range(24, 28):
		image.set_pixel(31, y, outline)
		image.set_pixel(33, y, outline)
	image.set_pixel(31, 24, outline)
	image.set_pixel(32, 25, outline)
	image.set_pixel(33, 26, outline)
	# N (second)
	for y in range(24, 28):
		image.set_pixel(34, y, outline)

	# Lantern near door
	image.set_pixel(23, 38, Color(0.92, 0.80, 0.35))
	image.set_pixel(23, 39, Color(0.82, 0.68, 0.25))
	image.set_pixel(40, 38, Color(0.92, 0.80, 0.35))
	image.set_pixel(40, 39, Color(0.82, 0.68, 0.25))


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
