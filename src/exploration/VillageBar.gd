extends Area2D
class_name VillageBar

## VillageBar - Classic JRPG bar with dancing girl (FF5 style)
## Now triggers transition to TavernInterior scene when entered

signal drink_purchased()
signal transition_triggered(target_map: String, target_spawn: String)

@export var bar_name: String = "The Dancing Tonberry"

## Visual
var sprite: Sprite2D
var dancer_sprite: Sprite2D
var name_label: Label
var enter_label: Label

## Animation state
var _anim_frame: int = 0
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.2

## Dancer sprite cache
var _dancer_frames: Array[ImageTexture] = []

## State
var _player_nearby: bool = false

const TILE_SIZE: int = 32


func _ready() -> void:
	_generate_bar_sprite()
	_generate_dancer_sprites()
	_setup_collision()
	_setup_name_label()
	_setup_enter_label()

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(delta: float) -> void:
	# Animate dancer
	_anim_timer += delta
	if _anim_timer >= ANIM_SPEED:
		_anim_timer -= ANIM_SPEED
		_anim_frame = (_anim_frame + 1) % _dancer_frames.size()
		if dancer_sprite and _dancer_frames.size() > 0:
			dancer_sprite.texture = _dancer_frames[_anim_frame]


func _generate_bar_sprite() -> void:
	sprite = Sprite2D.new()
	sprite.name = "BarSprite"

	var image = Image.create(TILE_SIZE * 3, TILE_SIZE * 2, false, Image.FORMAT_RGBA8)
	_draw_bar(image)

	var texture = ImageTexture.create_from_image(image)
	sprite.texture = texture
	sprite.centered = true
	add_child(sprite)

	# Add dancer sprite separately for animation
	dancer_sprite = Sprite2D.new()
	dancer_sprite.name = "DancerSprite"
	dancer_sprite.position = Vector2(20, -8)  # Position on stage
	add_child(dancer_sprite)


func _draw_bar(image: Image) -> void:
	image.fill(Color.TRANSPARENT)

	var wood = Color(0.35, 0.22, 0.12)
	var wood_dark = Color(0.28, 0.16, 0.08)
	var brick = Color(0.55, 0.35, 0.25)
	var brick_dark = Color(0.45, 0.28, 0.18)
	var window = Color(0.9, 0.8, 0.5, 0.8)  # Warm tavern light
	var stage = Color(0.5, 0.4, 0.25)

	# Building body
	for y in range(0, 58):
		for x in range(4, 92):
			if y < 10:
				# Roof
				var c = wood if ((x + y) / 3) % 2 == 0 else wood_dark
				image.set_pixel(x, y, c)
			else:
				# Brick walls
				var brick_row = ((y - 10) / 6) % 2 == 0
				var brick_col = (x / 8) % 2 == 0
				var offset = 4 if brick_row else 0
				var in_mortar = ((x + offset) % 8 == 0) or ((y - 10) % 6 == 0)
				var c = brick_dark if in_mortar else brick
				image.set_pixel(x, y, c)

	# Large window showing interior
	for y in range(16, 40):
		for x in range(12, 84):
			image.set_pixel(x, y, window)

	# Stage inside (visible through window)
	for y in range(30, 40):
		for x in range(50, 78):
			image.set_pixel(x, y, stage)

	# Bar counter
	for y in range(28, 38):
		for x in range(16, 45):
			image.set_pixel(x, y, wood_dark)

	# Door
	for y in range(42, 58):
		for x in range(40, 56):
			image.set_pixel(x, y, wood_dark)

	# Sign with mug icon
	for y in range(2, 10):
		for x in range(38, 58):
			image.set_pixel(x, y, Color(0.8, 0.7, 0.5))
	# Mug shape
	for y in range(4, 8):
		for x in range(44, 52):
			image.set_pixel(x, y, Color(0.6, 0.5, 0.3))


func _generate_dancer_sprites() -> void:
	_dancer_frames.clear()

	# Generate 4 dance animation frames
	for frame in range(4):
		var image = Image.create(24, 32, false, Image.FORMAT_RGBA8)
		_draw_dancer(image, frame)
		var texture = ImageTexture.create_from_image(image)
		_dancer_frames.append(texture)

	if _dancer_frames.size() > 0:
		dancer_sprite.texture = _dancer_frames[0]


func _draw_dancer(image: Image, frame: int) -> void:
	image.fill(Color.TRANSPARENT)

	var skin = Color(0.95, 0.80, 0.70)
	var hair = Color(0.85, 0.65, 0.25)  # Blonde
	var dress = Color(0.85, 0.25, 0.35)  # Red dress
	var dress_light = Color(0.95, 0.45, 0.55)

	# Animation offsets
	var arm_angle = sin(frame * PI / 2) * 4
	var leg_angle = cos(frame * PI / 2) * 3
	var body_sway = sin(frame * PI / 2) * 2

	var cx = 12 + int(body_sway)

	# Head
	for y in range(2, 10):
		for x in range(cx - 4, cx + 4):
			if x >= 0 and x < 24:
				image.set_pixel(x, y, skin)

	# Hair (flowing)
	for y in range(0, 8):
		for x in range(cx - 5, cx + 5):
			if x >= 0 and x < 24 and y < 6:
				image.set_pixel(x, y, hair)
	# Side hair waves
	var hair_wave = int(sin(frame * PI / 2) * 2)
	for y in range(4, 14):
		var hx = cx + 5 + hair_wave
		if hx >= 0 and hx < 24:
			image.set_pixel(hx, y, hair)

	# Dress body
	for y in range(10, 26):
		var dress_width = 5 if y < 18 else 7
		for x in range(cx - dress_width, cx + dress_width):
			if x >= 0 and x < 24:
				var c = dress if (x + y) % 3 != 0 else dress_light
				image.set_pixel(x, y, c)

	# Arms (raised in dance pose)
	var left_arm_x = cx - 6 + int(arm_angle)
	var right_arm_x = cx + 5 - int(arm_angle)
	for y in range(12, 18):
		if left_arm_x >= 0 and left_arm_x < 24:
			image.set_pixel(left_arm_x, y, skin)
		if right_arm_x >= 0 and right_arm_x < 24:
			image.set_pixel(right_arm_x, y, skin)

	# Legs (dancing)
	var left_leg_x = cx - 3 + int(leg_angle)
	var right_leg_x = cx + 2 - int(leg_angle)
	for y in range(26, 32):
		if left_leg_x >= 0 and left_leg_x < 24:
			image.set_pixel(left_leg_x, y, skin)
		if right_leg_x >= 0 and right_leg_x < 24:
			image.set_pixel(right_leg_x, y, skin)


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
	name_label.text = bar_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.position = Vector2(-70, -50)
	name_label.size = Vector2(140, 20)
	name_label.add_theme_font_size_override("font_size", 14)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.visible = false
	add_child(name_label)


func _setup_enter_label() -> void:
	enter_label = Label.new()
	enter_label.text = "[A] Enter"
	enter_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enter_label.position = Vector2(-30, 35)
	enter_label.size = Vector2(60, 20)
	enter_label.add_theme_font_size_override("font_size", 10)
	enter_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	enter_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	enter_label.add_theme_constant_override("shadow_offset_x", 1)
	enter_label.add_theme_constant_override("shadow_offset_y", 1)
	enter_label.visible = false
	add_child(enter_label)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = true
		name_label.visible = true
		enter_label.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_can_move"):
		_player_nearby = false
		name_label.visible = false
		enter_label.visible = false


func interact(_player: Node2D) -> void:
	# Trigger transition to tavern interior
	print("[BAR] Interact triggered - transitioning to tavern_interior")
	if SoundManager:
		SoundManager.play_ui("menu_open")
	transition_triggered.emit("tavern_interior", "entrance")
	print("[BAR] transition_triggered signal emitted")
