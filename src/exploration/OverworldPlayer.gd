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
const ANIM_SPEED: float = 0.12  # Seconds per frame (slightly faster for 4-frame cycle)
const SPRITE_SIZE: int = 32
const WALK_FRAMES: int = 4  # 4-frame walk cycle for smoother animation

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

## Character customization for appearance
var _custom_hair_color: Color = Color(0.35, 0.25, 0.18)
var _custom_skin_color: Color = Color(0.85, 0.70, 0.55)
var _use_custom_colors: bool = false


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

	# Set collision layers: layer 1 = walls, layer 2 = player (for NPC detection)
	collision_layer = 2  # Player is on layer 2 so NPCs can detect us
	collision_mask = 1   # Player collides with walls (layer 1)


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
			_anim_frame = (_anim_frame + 1) % WALK_FRAMES
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
		for frame in range(WALK_FRAMES):
			var img = _generate_character_sprite(dir, frame)
			var tex = ImageTexture.create_from_image(img)
			var cache_key = "%d_%d" % [dir, frame]
			_sprite_cache[cache_key] = tex


func _generate_character_sprite(direction: Direction, frame: int) -> Image:
	var img = Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Transparent background

	var palette = JOB_PALETTES.get(current_job, JOB_PALETTES["fighter"]).duplicate()

	# Override with custom colors from party leader if available
	if _use_custom_colors:
		palette["hair"] = _custom_hair_color
		palette["skin"] = _custom_skin_color

	# 4-frame walk cycle with better animation:
	# Frame 0: Neutral/standing (contact right)
	# Frame 1: Right foot forward, left arm forward (passing right)
	# Frame 2: Neutral/standing (contact left)
	# Frame 3: Left foot forward, right arm forward (passing left)
	var walk_phase = _get_walk_phase(frame)

	match direction:
		Direction.DOWN:
			_draw_character_front(img, palette, walk_phase)
		Direction.UP:
			_draw_character_back(img, palette, walk_phase)
		Direction.LEFT:
			_draw_character_side(img, palette, walk_phase, true)
		Direction.RIGHT:
			_draw_character_side(img, palette, walk_phase, false)

	return img


func _get_walk_phase(frame: int) -> Dictionary:
	"""Return walk animation parameters for the given frame"""
	# 4-frame walk cycle: contact-passing-contact-passing
	match frame:
		0:  # Contact right - right foot forward touching ground
			return {
				"bob": 0,
				"left_leg": 0,
				"right_leg": 2,
				"left_arm": 1,
				"right_arm": -1,
				"lean": 0
			}
		1:  # Passing right - transitioning, body rises
			return {
				"bob": -1,  # Slight rise
				"left_leg": 1,
				"right_leg": 1,
				"left_arm": 0,
				"right_arm": 0,
				"lean": 0
			}
		2:  # Contact left - left foot forward touching ground
			return {
				"bob": 0,
				"left_leg": 2,
				"right_leg": 0,
				"left_arm": -1,
				"right_arm": 1,
				"lean": 0
			}
		3:  # Passing left - transitioning, body rises
			return {
				"bob": -1,  # Slight rise
				"left_leg": 1,
				"right_leg": 1,
				"left_arm": 0,
				"right_arm": 0,
				"lean": 0
			}
		_:
			return {"bob": 0, "left_leg": 0, "right_leg": 0, "left_arm": 0, "right_arm": 0, "lean": 0}


func _draw_character_front(img: Image, palette: Dictionary, phase: Dictionary) -> void:
	var bob = phase["bob"]
	var left_leg = phase["left_leg"]
	var right_leg = phase["right_leg"]
	var left_arm = phase["left_arm"]
	var right_arm = phase["right_arm"]

	# Shadow beneath character (subtle)
	var shadow_y = 29
	for x in range(12, 21):
		var shadow_alpha = 0.2 - abs(x - 16) * 0.02
		_safe_pixel(img, x, shadow_y, Color(0, 0, 0, shadow_alpha))

	# Head (front view)
	var head_y = 4 - bob
	_draw_ellipse(img, 16, head_y + 4, 6, 5, palette["skin"])

	# Hair with more detail
	for y in range(head_y - 1, head_y + 3):
		for x in range(10, 23):
			var in_hair = false
			if y < head_y + 1:
				in_hair = abs(x - 16) < 6
			elif y < head_y + 2:
				in_hair = abs(x - 16) < 5
			else:
				in_hair = (x > 12 and x < 20) or x < 12 or x > 20
			if in_hair:
				_safe_pixel(img, x, y, palette["hair"])

	# Eyes with pupils
	_safe_pixel(img, 13, head_y + 4, Color(1, 1, 1))
	_safe_pixel(img, 14, head_y + 4, Color.BLACK)
	_safe_pixel(img, 18, head_y + 4, Color.BLACK)
	_safe_pixel(img, 19, head_y + 4, Color(1, 1, 1))

	# Eyebrows
	_safe_pixel(img, 13, head_y + 3, palette["hair"])
	_safe_pixel(img, 14, head_y + 3, palette["hair"])
	_safe_pixel(img, 18, head_y + 3, palette["hair"])
	_safe_pixel(img, 19, head_y + 3, palette["hair"])

	# Mouth
	_safe_pixel(img, 15, head_y + 6, Color(0.6, 0.4, 0.4))
	_safe_pixel(img, 16, head_y + 6, Color(0.6, 0.4, 0.4))
	_safe_pixel(img, 17, head_y + 6, Color(0.6, 0.4, 0.4))

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

	# Belt detail
	for x in range(11, 22):
		_safe_pixel(img, x, body_y + 7, palette["armor_dark"])

	# Arms with swing animation
	var left_arm_y = body_y + 1 + left_arm
	var right_arm_y = body_y + 1 + right_arm
	for i in range(6):
		_safe_pixel(img, 9, left_arm_y + i, palette["armor_dark"])
		_safe_pixel(img, 10, left_arm_y + i, palette["armor"])
		_safe_pixel(img, 22, right_arm_y + i, palette["armor"])
		_safe_pixel(img, 23, right_arm_y + i, palette["armor_light"])

	# Hands at end of arms
	_safe_pixel(img, 9, left_arm_y + 6, palette["skin"])
	_safe_pixel(img, 10, left_arm_y + 6, palette["skin"])
	_safe_pixel(img, 22, right_arm_y + 6, palette["skin"])
	_safe_pixel(img, 23, right_arm_y + 6, palette["skin"])

	# Legs with proper stride
	var leg_y = body_y + 10

	# Left leg - when extended forward, it's lower on screen and spread outward
	var left_leg_x = 13 - left_leg
	var left_leg_length = 5 + (1 if left_leg > 1 else 0)
	for i in range(left_leg_length):
		_safe_pixel(img, left_leg_x, leg_y + i, palette["pants"])
		_safe_pixel(img, left_leg_x + 1, leg_y + i, palette["pants"])

	# Right leg
	var right_leg_x = 18 + right_leg
	var right_leg_length = 5 + (1 if right_leg > 1 else 0)
	for i in range(right_leg_length):
		_safe_pixel(img, right_leg_x, leg_y + i, palette["pants"])
		_safe_pixel(img, right_leg_x + 1, leg_y + i, palette["pants"])

	# Boots with proper positioning
	var left_boot_y = leg_y + left_leg_length
	var right_boot_y = leg_y + right_leg_length
	_safe_pixel(img, left_leg_x - 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 2, left_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x - 1, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 1, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 2, right_boot_y, palette["boots"])


func _draw_character_back(img: Image, palette: Dictionary, phase: Dictionary) -> void:
	var bob = phase["bob"]
	var left_leg = phase["left_leg"]
	var right_leg = phase["right_leg"]
	var left_arm = phase["left_arm"]
	var right_arm = phase["right_arm"]

	# Shadow beneath character
	var shadow_y = 29
	for x in range(12, 21):
		var shadow_alpha = 0.2 - abs(x - 16) * 0.02
		_safe_pixel(img, x, shadow_y, Color(0, 0, 0, shadow_alpha))

	# Head (back view - mostly hair)
	var head_y = 4 - bob
	_draw_ellipse(img, 16, head_y + 4, 6, 5, palette["hair"])

	# Hair detail - slightly different shade for texture
	var hair_highlight = palette["hair"].lightened(0.15)
	for y in range(head_y, head_y + 3):
		for x in range(13, 16):
			_safe_pixel(img, x, y, hair_highlight)

	# Neck peek
	_safe_pixel(img, 15, head_y + 8, palette["skin"])
	_safe_pixel(img, 16, head_y + 8, palette["skin"])
	_safe_pixel(img, 17, head_y + 8, palette["skin"])

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

	# Back detail (cape clasp or armor line)
	for y in range(body_y + 2, body_y + 8):
		_safe_pixel(img, 16, y, palette["armor_dark"])

	# Belt
	for x in range(11, 22):
		_safe_pixel(img, x, body_y + 7, palette["armor_dark"])

	# Arms with swing
	var left_arm_y = body_y + 1 + left_arm
	var right_arm_y = body_y + 1 + right_arm
	for i in range(6):
		_safe_pixel(img, 9, left_arm_y + i, palette["armor_dark"])
		_safe_pixel(img, 10, left_arm_y + i, palette["armor"])
		_safe_pixel(img, 22, right_arm_y + i, palette["armor"])
		_safe_pixel(img, 23, right_arm_y + i, palette["armor_light"])

	# Hands
	_safe_pixel(img, 9, left_arm_y + 6, palette["skin"])
	_safe_pixel(img, 10, left_arm_y + 6, palette["skin"])
	_safe_pixel(img, 22, right_arm_y + 6, palette["skin"])
	_safe_pixel(img, 23, right_arm_y + 6, palette["skin"])

	# Legs with stride
	var leg_y = body_y + 10

	var left_leg_x = 13 - left_leg
	var left_leg_length = 5 + (1 if left_leg > 1 else 0)
	for i in range(left_leg_length):
		_safe_pixel(img, left_leg_x, leg_y + i, palette["pants"])
		_safe_pixel(img, left_leg_x + 1, leg_y + i, palette["pants"])

	var right_leg_x = 18 + right_leg
	var right_leg_length = 5 + (1 if right_leg > 1 else 0)
	for i in range(right_leg_length):
		_safe_pixel(img, right_leg_x, leg_y + i, palette["pants"])
		_safe_pixel(img, right_leg_x + 1, leg_y + i, palette["pants"])

	# Boots
	var left_boot_y = leg_y + left_leg_length
	var right_boot_y = leg_y + right_leg_length
	_safe_pixel(img, left_leg_x - 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 2, left_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x - 1, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 1, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 2, right_boot_y, palette["boots"])


func _draw_character_side(img: Image, palette: Dictionary, phase: Dictionary, facing_left: bool) -> void:
	var bob = phase["bob"]
	# For side view, use different legs based on direction
	var front_leg = phase["left_leg"] if facing_left else phase["right_leg"]
	var back_leg = phase["right_leg"] if facing_left else phase["left_leg"]
	var front_arm = phase["left_arm"] if facing_left else phase["right_arm"]
	var back_arm = phase["right_arm"] if facing_left else phase["left_arm"]

	var flip = -1 if facing_left else 1
	var center_x = 16

	# Shadow beneath character
	var shadow_y = 29
	for x in range(12, 21):
		var shadow_alpha = 0.2 - abs(x - 16) * 0.02
		_safe_pixel(img, x, shadow_y, Color(0, 0, 0, shadow_alpha))

	# Head (side view - narrower, more profile)
	var head_y = 4 - bob
	_draw_ellipse(img, center_x, head_y + 4, 5, 5, palette["skin"])

	# Nose bump on profile (should be on the side we're facing)
	var nose_x = center_x + (3 * flip)
	_safe_pixel(img, nose_x, head_y + 4, palette["skin"])
	_safe_pixel(img, nose_x, head_y + 5, palette["skin"])

	# Hair (on back of head, fuller) - opposite side from where we're facing
	var hair_back_dir = -flip  # Hair goes opposite to facing direction
	for y in range(head_y - 1, head_y + 7):
		for offset in range(4):
			var hx = center_x + ((2 + offset) * hair_back_dir)
			if hx >= 0 and hx < SPRITE_SIZE:
				_safe_pixel(img, hx, y, palette["hair"])
	# Top hair
	for x in range(center_x - 4, center_x + 5):
		_safe_pixel(img, x, head_y - 1, palette["hair"])
		_safe_pixel(img, x, head_y, palette["hair"])
		if abs(x - center_x) < 3:
			_safe_pixel(img, x, head_y + 1, palette["hair"])

	# Eye (one visible on side) with detail - positioned on the side we're facing
	var eye_x = center_x + (2 * flip)
	_safe_pixel(img, eye_x + 1 if facing_left else eye_x - 1, head_y + 4, Color(1, 1, 1))  # Eye white
	_safe_pixel(img, eye_x, head_y + 4, Color.BLACK)  # Pupil

	# Eyebrow
	_safe_pixel(img, eye_x, head_y + 3, palette["hair"])
	_safe_pixel(img, eye_x + 1 if facing_left else eye_x - 1, head_y + 3, palette["hair"])

	# Mouth
	var mouth_x = center_x + flip
	_safe_pixel(img, mouth_x, head_y + 6, Color(0.6, 0.4, 0.4))

	# Neck
	_safe_pixel(img, center_x, head_y + 8, palette["skin"])

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

	# Belt
	for offset in range(-4, 5):
		_safe_pixel(img, center_x + offset, body_y + 7, palette["armor_dark"])

	# Back arm (behind body, swinging opposite to front leg)
	var back_arm_x = center_x + ((4 if facing_left else -4))
	var back_arm_y_offset = -back_arm  # Opposite swing
	for i in range(5):
		var ay = body_y + 2 + back_arm_y_offset + i
		if ay >= 0 and ay < SPRITE_SIZE:
			_safe_pixel(img, back_arm_x, ay, palette["armor_dark"])
	_safe_pixel(img, back_arm_x, body_y + 7 + back_arm_y_offset, palette["skin"])

	# Front arm (in front of body, swinging opposite to back leg)
	var front_arm_x = center_x + ((-5 if facing_left else 5))
	var front_arm_y_offset = -front_arm  # Opposite swing
	for i in range(6):
		var ay = body_y + 1 + front_arm_y_offset + i
		if ay >= 0 and ay < SPRITE_SIZE:
			_safe_pixel(img, front_arm_x, ay, palette["armor"])
			_safe_pixel(img, front_arm_x + (1 if facing_left else -1), ay, palette["armor_light"] if facing_left else palette["armor_dark"])
	# Hand
	_safe_pixel(img, front_arm_x, body_y + 7 + front_arm_y_offset, palette["skin"])
	_safe_pixel(img, front_arm_x + (1 if facing_left else -1), body_y + 7 + front_arm_y_offset, palette["skin"])

	# Legs (side view - proper walking cycle)
	var leg_y = body_y + 10

	# Back leg (darker, behind)
	var back_leg_offset = back_leg - 1  # Negative = back, positive = forward
	var back_leg_x = center_x + (1 if facing_left else -1)
	for i in range(6):
		var ly = leg_y + i
		var lx = back_leg_x + (back_leg_offset if not facing_left else -back_leg_offset)
		_safe_pixel(img, lx, ly, palette["pants"].darkened(0.2))
		_safe_pixel(img, lx + (1 if facing_left else -1), ly, palette["pants"].darkened(0.2))

	# Front leg (brighter, in front)
	var front_leg_offset = front_leg - 1
	var front_leg_x = center_x + (-1 if facing_left else 1)
	for i in range(6):
		var ly = leg_y + i
		var lx = front_leg_x + (-front_leg_offset if facing_left else front_leg_offset)
		_safe_pixel(img, lx, ly, palette["pants"])
		_safe_pixel(img, lx + (-1 if facing_left else 1), ly, palette["pants"])

	# Boots
	var boot_y = leg_y + 5
	var back_boot_x = back_leg_x + (back_leg_offset if not facing_left else -back_leg_offset)
	var front_boot_x = front_leg_x + (-front_leg_offset if facing_left else front_leg_offset)

	# Back boot
	_safe_pixel(img, back_boot_x - 1, boot_y, palette["boots"].darkened(0.15))
	_safe_pixel(img, back_boot_x, boot_y, palette["boots"].darkened(0.15))
	_safe_pixel(img, back_boot_x + 1, boot_y, palette["boots"].darkened(0.15))

	# Front boot
	_safe_pixel(img, front_boot_x - 1, boot_y, palette["boots"])
	_safe_pixel(img, front_boot_x, boot_y, palette["boots"])
	_safe_pixel(img, front_boot_x + 1, boot_y, palette["boots"])
	_safe_pixel(img, front_boot_x + (2 if not facing_left else -2), boot_y, palette["boots"])


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


## Set appearance from party leader's customization
func set_appearance_from_leader(leader: Combatant) -> void:
	"""Update avatar to match the lead party member"""
	if not leader:
		return

	# Get job from leader
	var job_id = "fighter"
	if leader.job:
		job_id = leader.job.get("id", "fighter")

	# Get colors from customization
	if leader.customization:
		_custom_hair_color = leader.customization.hair_color
		_custom_skin_color = leader.customization.skin_tone
		_use_custom_colors = true
	else:
		_use_custom_colors = false

	# Update job and regenerate sprites
	current_job = job_id
	_generate_all_sprites()
	_update_sprite()
	print("[OVERWORLD] Avatar updated: %s (%s)" % [leader.combatant_name, job_id])


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
