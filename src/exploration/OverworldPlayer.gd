extends CharacterBody2D
class_name OverworldPlayer

## OverworldPlayer - 32x32 animated player character for exploration
## Shows the party leader with 4-directional movement and walk animation

signal moved(steps: int)
signal interaction_requested()
signal menu_requested()

## Movement configuration
@export var move_speed: float = 150.0

## Direction enum
enum Direction { DOWN, UP, LEFT, RIGHT }

## Current state
var current_direction: Direction = Direction.DOWN
var is_moving: bool = false
var can_move: bool = true
var step_count: int = 0
var distance_walked: float = 0.0
const STEP_DISTANCE: float = 32.0  # One tile = one step

## Animation
var _sprite: Sprite2D
var _anim_frame: int = 0
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.15  # Seconds per frame
const SPRITE_SIZE: int = 32

## Sprite cache (direction -> frame -> texture)
var _sprite_cache: Dictionary = {}

## Job color palettes for character sprites
const JOB_PALETTES: Dictionary = {
	"fighter": {
		"hair": Color(0.35, 0.25, 0.18),
		"skin": Color(0.85, 0.70, 0.55),
		"armor": Color(0.30, 0.40, 0.60),
		"armor_light": Color(0.45, 0.55, 0.75),
		"armor_dark": Color(0.20, 0.28, 0.45),
		"pants": Color(0.35, 0.30, 0.25),
		"boots": Color(0.25, 0.20, 0.15)
	},
	"mage": {
		"hair": Color(0.55, 0.40, 0.65),
		"skin": Color(0.90, 0.78, 0.68),
		"armor": Color(0.45, 0.25, 0.55),
		"armor_light": Color(0.60, 0.38, 0.70),
		"armor_dark": Color(0.30, 0.15, 0.40),
		"pants": Color(0.40, 0.20, 0.50),
		"boots": Color(0.25, 0.12, 0.30)
	},
	"thief": {
		"hair": Color(0.20, 0.18, 0.15),
		"skin": Color(0.80, 0.65, 0.50),
		"armor": Color(0.25, 0.30, 0.25),
		"armor_light": Color(0.38, 0.45, 0.38),
		"armor_dark": Color(0.15, 0.20, 0.15),
		"pants": Color(0.22, 0.25, 0.22),
		"boots": Color(0.18, 0.18, 0.15)
	},
	"dark_mage": {
		"hair": Color(0.15, 0.12, 0.20),
		"skin": Color(0.75, 0.68, 0.72),
		"armor": Color(0.20, 0.15, 0.25),
		"armor_light": Color(0.35, 0.28, 0.40),
		"armor_dark": Color(0.10, 0.08, 0.15),
		"pants": Color(0.18, 0.12, 0.22),
		"boots": Color(0.12, 0.10, 0.15)
	}
}

## Current job for sprite generation
var current_job: String = "fighter"


func _ready() -> void:
	_setup_sprite()
	_generate_all_sprites()
	_update_sprite()


func _setup_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	add_child(_sprite)

	# Setup collision shape
	var collision = CollisionShape2D.new()
	collision.name = "Collision"
	var shape = RectangleShape2D.new()
	shape.size = Vector2(24, 24)  # Slightly smaller than sprite for easier navigation
	collision.shape = shape
	collision.position = Vector2(0, 4)  # Offset down slightly (feet collision)
	add_child(collision)


func _physics_process(delta: float) -> void:
	if not can_move:
		is_moving = false
		return

	# Get input direction
	var input_dir = Vector2.ZERO
	if Input.is_action_pressed("ui_left"):
		input_dir.x -= 1
	if Input.is_action_pressed("ui_right"):
		input_dir.x += 1
	if Input.is_action_pressed("ui_up"):
		input_dir.y -= 1
	if Input.is_action_pressed("ui_down"):
		input_dir.y += 1

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		velocity = input_dir * move_speed
		is_moving = true

		# Update facing direction (prioritize horizontal for diagonal)
		if abs(input_dir.x) > abs(input_dir.y):
			current_direction = Direction.LEFT if input_dir.x < 0 else Direction.RIGHT
		else:
			current_direction = Direction.UP if input_dir.y < 0 else Direction.DOWN

		# Track distance for step counting
		var old_pos = position
		move_and_slide()
		var moved_dist = position.distance_to(old_pos)
		distance_walked += moved_dist

		# Emit step signal every STEP_DISTANCE pixels
		while distance_walked >= STEP_DISTANCE:
			distance_walked -= STEP_DISTANCE
			step_count += 1
			moved.emit(step_count)
	else:
		velocity = Vector2.ZERO
		is_moving = false

	# Update animation
	_update_animation(delta)


func _input(event: InputEvent) -> void:
	if not can_move:
		return

	if event.is_action_pressed("ui_accept"):
		interaction_requested.emit()
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_cancel"):
		menu_requested.emit()
		get_viewport().set_input_as_handled()


func _update_animation(delta: float) -> void:
	if is_moving:
		_anim_timer += delta
		if _anim_timer >= ANIM_SPEED:
			_anim_timer -= ANIM_SPEED
			_anim_frame = (_anim_frame + 1) % 2
			_update_sprite()
	else:
		_anim_frame = 0
		_anim_timer = 0.0
		_update_sprite()


func _update_sprite() -> void:
	var cache_key = "%d_%d" % [current_direction, _anim_frame]
	if _sprite_cache.has(cache_key):
		_sprite.texture = _sprite_cache[cache_key]


func _generate_all_sprites() -> void:
	for dir in [Direction.DOWN, Direction.UP, Direction.LEFT, Direction.RIGHT]:
		for frame in [0, 1]:
			var img = _generate_character_sprite(dir, frame)
			var tex = ImageTexture.create_from_image(img)
			var cache_key = "%d_%d" % [dir, frame]
			_sprite_cache[cache_key] = tex


func _generate_character_sprite(direction: Direction, frame: int) -> Image:
	var img = Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Transparent background

	var palette = JOB_PALETTES.get(current_job, JOB_PALETTES["fighter"])

	# Walk cycle offset (slight bob and leg movement)
	var bob_offset = 1 if frame == 1 else 0
	var leg_offset = 2 if frame == 1 else 0

	match direction:
		Direction.DOWN:
			_draw_character_front(img, palette, bob_offset, leg_offset)
		Direction.UP:
			_draw_character_back(img, palette, bob_offset, leg_offset)
		Direction.LEFT:
			_draw_character_side(img, palette, bob_offset, leg_offset, true)
		Direction.RIGHT:
			_draw_character_side(img, palette, bob_offset, leg_offset, false)

	return img


func _draw_character_front(img: Image, palette: Dictionary, bob: int, leg_off: int) -> void:
	# Head (front view)
	var head_y = 4 - bob
	_draw_ellipse(img, 16, head_y + 4, 6, 5, palette["skin"])

	# Hair
	for y in range(head_y, head_y + 3):
		for x in range(11, 22):
			if y < head_y + 2 or (x > 12 and x < 20):
				_safe_pixel(img, x, y, palette["hair"])

	# Eyes
	_safe_pixel(img, 13, head_y + 4, Color.BLACK)
	_safe_pixel(img, 19, head_y + 4, Color.BLACK)

	# Body/torso
	var body_y = head_y + 9
	for y in range(body_y, body_y + 10):
		var body_width = 6 if y < body_y + 3 else 5
		for x in range(16 - body_width, 16 + body_width):
			var shade = palette["armor"]
			if x < 16 - body_width + 2:
				shade = palette["armor_dark"]
			elif x > 16 + body_width - 3:
				shade = palette["armor_light"]
			_safe_pixel(img, x, y, shade)

	# Arms
	for y in range(body_y + 1, body_y + 7):
		_safe_pixel(img, 9, y, palette["armor_dark"])
		_safe_pixel(img, 10, y, palette["armor"])
		_safe_pixel(img, 22, y, palette["armor"])
		_safe_pixel(img, 23, y, palette["armor_light"])

	# Hands
	_safe_pixel(img, 9, body_y + 7, palette["skin"])
	_safe_pixel(img, 10, body_y + 7, palette["skin"])
	_safe_pixel(img, 22, body_y + 7, palette["skin"])
	_safe_pixel(img, 23, body_y + 7, palette["skin"])

	# Legs
	var leg_y = body_y + 10
	# Left leg
	for y in range(leg_y, leg_y + 6):
		var lx = 13 - leg_off if leg_off > 0 else 13
		_safe_pixel(img, lx, y, palette["pants"])
		_safe_pixel(img, lx + 1, y, palette["pants"])
	# Right leg
	for y in range(leg_y, leg_y + 6):
		var rx = 18 + leg_off if leg_off > 0 else 18
		_safe_pixel(img, rx, y, palette["pants"])
		_safe_pixel(img, rx + 1, y, palette["pants"])

	# Boots
	var boot_y = leg_y + 5
	_safe_pixel(img, 12 - leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 13 - leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 14 - leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 18 + leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 19 + leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 20 + leg_off, boot_y, palette["boots"])


func _draw_character_back(img: Image, palette: Dictionary, bob: int, leg_off: int) -> void:
	# Head (back view - mostly hair)
	var head_y = 4 - bob
	_draw_ellipse(img, 16, head_y + 4, 6, 5, palette["hair"])

	# Body
	var body_y = head_y + 9
	for y in range(body_y, body_y + 10):
		var body_width = 6 if y < body_y + 3 else 5
		for x in range(16 - body_width, 16 + body_width):
			var shade = palette["armor"]
			if x < 16 - body_width + 2:
				shade = palette["armor_dark"]
			elif x > 16 + body_width - 3:
				shade = palette["armor_light"]
			_safe_pixel(img, x, y, shade)

	# Arms
	for y in range(body_y + 1, body_y + 7):
		_safe_pixel(img, 9, y, palette["armor_dark"])
		_safe_pixel(img, 10, y, palette["armor"])
		_safe_pixel(img, 22, y, palette["armor"])
		_safe_pixel(img, 23, y, palette["armor_light"])

	# Hands
	_safe_pixel(img, 9, body_y + 7, palette["skin"])
	_safe_pixel(img, 10, body_y + 7, palette["skin"])
	_safe_pixel(img, 22, body_y + 7, palette["skin"])
	_safe_pixel(img, 23, body_y + 7, palette["skin"])

	# Legs
	var leg_y = body_y + 10
	for y in range(leg_y, leg_y + 6):
		var lx = 13 - leg_off if leg_off > 0 else 13
		_safe_pixel(img, lx, y, palette["pants"])
		_safe_pixel(img, lx + 1, y, palette["pants"])
		var rx = 18 + leg_off if leg_off > 0 else 18
		_safe_pixel(img, rx, y, palette["pants"])
		_safe_pixel(img, rx + 1, y, palette["pants"])

	# Boots
	var boot_y = leg_y + 5
	_safe_pixel(img, 12 - leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 13 - leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 14 - leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 18 + leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 19 + leg_off, boot_y, palette["boots"])
	_safe_pixel(img, 20 + leg_off, boot_y, palette["boots"])


func _draw_character_side(img: Image, palette: Dictionary, bob: int, leg_off: int, facing_left: bool) -> void:
	var flip = -1 if facing_left else 1
	var center_x = 16

	# Head (side view - narrower)
	var head_y = 4 - bob
	_draw_ellipse(img, center_x, head_y + 4, 5, 5, palette["skin"])

	# Hair (on back of head)
	var hair_x = center_x + (4 * flip) if not facing_left else center_x - 4
	for y in range(head_y, head_y + 6):
		for offset in range(3):
			var hx = center_x + ((3 + offset) * (-flip if facing_left else flip))
			if hx >= 0 and hx < SPRITE_SIZE:
				_safe_pixel(img, hx, y, palette["hair"])
	# Top hair
	for x in range(center_x - 3, center_x + 4):
		_safe_pixel(img, x, head_y, palette["hair"])
		_safe_pixel(img, x, head_y + 1, palette["hair"])

	# Eye (one visible on side)
	var eye_x = center_x + (2 * (-flip if facing_left else flip))
	_safe_pixel(img, eye_x, head_y + 4, Color.BLACK)

	# Body
	var body_y = head_y + 9
	for y in range(body_y, body_y + 10):
		var body_half_width = 4
		for offset in range(-body_half_width, body_half_width + 1):
			var bx = center_x + offset
			var shade = palette["armor"]
			if (facing_left and offset > 2) or (not facing_left and offset < -2):
				shade = palette["armor_dark"]
			elif (facing_left and offset < -1) or (not facing_left and offset > 1):
				shade = palette["armor_light"]
			_safe_pixel(img, bx, y, shade)

	# Arm (one visible, swinging)
	var arm_x = center_x + ((-5 if facing_left else 5))
	var arm_offset = leg_off if leg_off > 0 else 0
	for y in range(body_y + 1 - arm_offset, body_y + 7 - arm_offset):
		if y >= 0 and y < SPRITE_SIZE:
			_safe_pixel(img, arm_x, y, palette["armor"])
	# Hand
	_safe_pixel(img, arm_x, body_y + 7 - arm_offset, palette["skin"])

	# Legs (side view - one in front, one behind)
	var leg_y = body_y + 10

	# Back leg
	for y in range(leg_y, leg_y + 6):
		var back_leg_x = center_x + (1 if facing_left else -1)
		if leg_off > 0:
			back_leg_x += (-leg_off if facing_left else leg_off)
		_safe_pixel(img, back_leg_x, y, palette["pants"])

	# Front leg
	for y in range(leg_y, leg_y + 6):
		var front_leg_x = center_x + (-1 if facing_left else 1)
		if leg_off > 0:
			front_leg_x += (leg_off if facing_left else -leg_off)
		_safe_pixel(img, front_leg_x, y, palette["pants"])

	# Boots
	var boot_y = leg_y + 5
	var back_boot = center_x + (1 if facing_left else -1) + ((-leg_off if facing_left else leg_off) if leg_off > 0 else 0)
	var front_boot = center_x + (-1 if facing_left else 1) + ((leg_off if facing_left else -leg_off) if leg_off > 0 else 0)
	_safe_pixel(img, back_boot - 1, boot_y, palette["boots"])
	_safe_pixel(img, back_boot, boot_y, palette["boots"])
	_safe_pixel(img, front_boot - 1, boot_y, palette["boots"])
	_safe_pixel(img, front_boot, boot_y, palette["boots"])


func _draw_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			var dist = sqrt(pow(float(x) / rx, 2) + pow(float(y) / ry, 2))
			if dist <= 1.0:
				_safe_pixel(img, cx + x, cy + y, color)


func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < SPRITE_SIZE and y >= 0 and y < SPRITE_SIZE:
		img.set_pixel(x, y, color)


## Set the job type for sprite generation
func set_job(job_name: String) -> void:
	if current_job != job_name:
		current_job = job_name
		_generate_all_sprites()
		_update_sprite()


## Enable/disable player movement
func set_can_move(enabled: bool) -> void:
	can_move = enabled
	if not enabled:
		velocity = Vector2.ZERO
		is_moving = false


## Teleport player to position
func teleport(new_position: Vector2) -> void:
	position = new_position
	distance_walked = 0.0


## Reset step counter
func reset_step_count() -> void:
	step_count = 0
	distance_walked = 0.0
