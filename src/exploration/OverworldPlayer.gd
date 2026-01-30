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

## SNES-quality job color palettes with extended shading tones
const JOB_PALETTES: Dictionary = {
	"fighter": {
		"hair": Color(0.35, 0.25, 0.18),
		"hair_light": Color(0.48, 0.35, 0.25),
		"hair_dark": Color(0.22, 0.15, 0.10),
		"skin": Color(0.85, 0.70, 0.55),
		"skin_light": Color(0.92, 0.78, 0.62),
		"skin_shadow": Color(0.72, 0.58, 0.45),
		"armor": Color(0.30, 0.40, 0.60),
		"armor_light": Color(0.45, 0.55, 0.75),
		"armor_mid": Color(0.38, 0.48, 0.68),
		"armor_dark": Color(0.20, 0.28, 0.45),
		"armor_shine": Color(0.55, 0.65, 0.85),
		"pants": Color(0.35, 0.30, 0.25),
		"pants_dark": Color(0.25, 0.20, 0.16),
		"boots": Color(0.25, 0.20, 0.15),
		"boots_light": Color(0.35, 0.28, 0.22),
		"outline": Color(0.10, 0.08, 0.06)
	},
	"mage": {
		"hair": Color(0.55, 0.40, 0.65),
		"hair_light": Color(0.68, 0.52, 0.78),
		"hair_dark": Color(0.38, 0.28, 0.48),
		"skin": Color(0.90, 0.78, 0.68),
		"skin_light": Color(0.95, 0.85, 0.75),
		"skin_shadow": Color(0.78, 0.65, 0.55),
		"armor": Color(0.45, 0.25, 0.55),
		"armor_light": Color(0.60, 0.38, 0.70),
		"armor_mid": Color(0.52, 0.30, 0.62),
		"armor_dark": Color(0.30, 0.15, 0.40),
		"armor_shine": Color(0.72, 0.50, 0.82),
		"pants": Color(0.40, 0.20, 0.50),
		"pants_dark": Color(0.28, 0.12, 0.38),
		"boots": Color(0.25, 0.12, 0.30),
		"boots_light": Color(0.35, 0.20, 0.42),
		"outline": Color(0.12, 0.06, 0.15)
	},
	"thief": {
		"hair": Color(0.20, 0.18, 0.15),
		"hair_light": Color(0.30, 0.28, 0.24),
		"hair_dark": Color(0.12, 0.10, 0.08),
		"skin": Color(0.80, 0.65, 0.50),
		"skin_light": Color(0.88, 0.72, 0.58),
		"skin_shadow": Color(0.68, 0.55, 0.42),
		"armor": Color(0.25, 0.30, 0.25),
		"armor_light": Color(0.38, 0.45, 0.38),
		"armor_mid": Color(0.30, 0.36, 0.30),
		"armor_dark": Color(0.15, 0.20, 0.15),
		"armor_shine": Color(0.48, 0.55, 0.48),
		"pants": Color(0.22, 0.25, 0.22),
		"pants_dark": Color(0.14, 0.16, 0.14),
		"boots": Color(0.18, 0.18, 0.15),
		"boots_light": Color(0.28, 0.28, 0.24),
		"outline": Color(0.06, 0.06, 0.05)
	},
	"dark_mage": {
		"hair": Color(0.15, 0.12, 0.20),
		"hair_light": Color(0.25, 0.20, 0.32),
		"hair_dark": Color(0.08, 0.06, 0.12),
		"skin": Color(0.75, 0.68, 0.72),
		"skin_light": Color(0.82, 0.76, 0.80),
		"skin_shadow": Color(0.62, 0.56, 0.60),
		"armor": Color(0.20, 0.15, 0.25),
		"armor_light": Color(0.35, 0.28, 0.40),
		"armor_mid": Color(0.28, 0.22, 0.32),
		"armor_dark": Color(0.10, 0.08, 0.15),
		"armor_shine": Color(0.42, 0.35, 0.50),
		"pants": Color(0.18, 0.12, 0.22),
		"pants_dark": Color(0.10, 0.06, 0.14),
		"boots": Color(0.12, 0.10, 0.15),
		"boots_light": Color(0.22, 0.18, 0.26),
		"outline": Color(0.05, 0.03, 0.08)
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
	var outline = palette.get("outline", Color(0.10, 0.08, 0.06))
	var skin_light = palette.get("skin_light", palette["skin"].lightened(0.1))
	var skin_shadow = palette.get("skin_shadow", palette["skin"].darkened(0.15))
	var hair_light = palette.get("hair_light", palette["hair"].lightened(0.15))
	var hair_dark = palette.get("hair_dark", palette["hair"].darkened(0.2))
	var armor_mid = palette.get("armor_mid", palette["armor"])
	var armor_shine = palette.get("armor_shine", palette["armor_light"].lightened(0.15))
	var pants_dark = palette.get("pants_dark", palette["pants"].darkened(0.2))
	var boots_light = palette.get("boots_light", palette["boots"].lightened(0.15))

	# Shadow beneath character (elliptical, more realistic)
	var shadow_y = 29
	for x in range(11, 22):
		var dist = abs(x - 16.0) / 5.5
		if dist <= 1.0:
			var shadow_alpha = 0.25 * (1.0 - dist * dist)
			_safe_pixel(img, x, shadow_y, Color(0, 0, 0, shadow_alpha))
			if shadow_alpha > 0.12:
				_safe_pixel(img, x, shadow_y + 1, Color(0, 0, 0, shadow_alpha * 0.5))

	# Head (front view) - elliptical with multi-zone skin shading
	var head_y = 4 - bob
	var head_cx = 16
	var head_rx = 6
	var head_ry = 5
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist <= 1.0:
				var px = head_cx + x
				var py = head_y + 4 + y
				# Multi-zone skin shading (SNES style)
				var c = palette["skin"]
				if y < -2:
					c = skin_light  # Forehead highlight
				elif y > 2:
					c = skin_shadow  # Chin shadow
				elif x < -3:
					c = skin_shadow  # Left cheek shadow
				elif x > 3:
					c = skin_shadow  # Right cheek shadow
				# Edge darkening for roundness
				if dist > 0.82:
					c = c.darkened(0.08)
				_safe_pixel(img, px, py, c)
			# Outline around head
			elif dist <= 1.2 and dist > 1.0:
				_safe_pixel(img, head_cx + x, head_y + 4 + y, outline)

	# Hair with highlight and shadow zones
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
				var c = palette["hair"]
				# Left side highlight, right side shadow
				if x < 14:
					c = hair_light
				elif x > 18:
					c = hair_dark
				# Top shine streak
				if y == head_y - 1 and abs(x - 15) < 3:
					c = hair_light
				_safe_pixel(img, x, y, c)
	# Hair outline on top
	for x in range(10, 23):
		if abs(x - 16) < 6:
			_safe_pixel(img, x, head_y - 2, outline)
	_safe_pixel(img, 10, head_y, outline)
	_safe_pixel(img, 22, head_y, outline)

	# Eyes with whites, iris, pupil, and catchlight (SNES FF6 style)
	# Left eye
	_safe_pixel(img, 12, head_y + 4, Color(0.95, 0.95, 0.95))  # White
	_safe_pixel(img, 13, head_y + 4, Color(0.95, 0.95, 0.95))  # White
	_safe_pixel(img, 14, head_y + 4, Color(0.15, 0.25, 0.45))  # Iris
	_safe_pixel(img, 14, head_y + 5, Color(0.0, 0.0, 0.0))     # Pupil
	_safe_pixel(img, 13, head_y + 3, outline)                    # Eyelid top
	_safe_pixel(img, 14, head_y + 3, outline)                    # Eyelid top
	_safe_pixel(img, 13, head_y + 5, Color(0.0, 0.0, 0.0))     # Lower lash
	# Catchlight
	_safe_pixel(img, 13, head_y + 4, Color(1.0, 1.0, 1.0))
	# Right eye
	_safe_pixel(img, 18, head_y + 4, Color(0.15, 0.25, 0.45))  # Iris
	_safe_pixel(img, 19, head_y + 4, Color(0.95, 0.95, 0.95))  # White
	_safe_pixel(img, 20, head_y + 4, Color(0.95, 0.95, 0.95))  # White
	_safe_pixel(img, 18, head_y + 5, Color(0.0, 0.0, 0.0))     # Pupil
	_safe_pixel(img, 18, head_y + 3, outline)                    # Eyelid top
	_safe_pixel(img, 19, head_y + 3, outline)                    # Eyelid top
	_safe_pixel(img, 19, head_y + 5, Color(0.0, 0.0, 0.0))     # Lower lash
	# Catchlight
	_safe_pixel(img, 19, head_y + 4, Color(1.0, 1.0, 1.0))

	# Eyebrows with expression
	_safe_pixel(img, 12, head_y + 3, hair_dark)
	_safe_pixel(img, 13, head_y + 2, hair_dark)
	_safe_pixel(img, 14, head_y + 2, hair_dark)
	_safe_pixel(img, 18, head_y + 2, hair_dark)
	_safe_pixel(img, 19, head_y + 2, hair_dark)
	_safe_pixel(img, 20, head_y + 3, hair_dark)

	# Nose shadow (subtle, 1-2 pixels)
	_safe_pixel(img, 16, head_y + 5, skin_shadow)
	_safe_pixel(img, 17, head_y + 5, skin_shadow)

	# Mouth with subtle lip color
	_safe_pixel(img, 15, head_y + 6, Color(0.72, 0.48, 0.45))
	_safe_pixel(img, 16, head_y + 6, Color(0.65, 0.42, 0.40))
	_safe_pixel(img, 17, head_y + 6, Color(0.72, 0.48, 0.45))

	# Neck
	_safe_pixel(img, 15, head_y + 8, skin_shadow)
	_safe_pixel(img, 16, head_y + 8, palette["skin"])
	_safe_pixel(img, 17, head_y + 8, skin_shadow)

	# Body/torso with 4-zone shading and outline
	var body_y = head_y + 9
	for y in range(body_y, body_y + 10):
		var body_width = 6 if y < body_y + 3 else 5
		# Body outline left and right
		_safe_pixel(img, 16 - body_width - 1, y, outline)
		_safe_pixel(img, 16 + body_width, y, outline)
		for x in range(16 - body_width, 16 + body_width):
			var rel_x = float(x - (16 - body_width)) / float(body_width * 2)
			var shade = palette["armor"]
			if rel_x < 0.15:
				shade = palette["armor_dark"]
			elif rel_x < 0.3:
				shade = armor_mid
			elif rel_x > 0.85:
				shade = palette["armor_dark"]
			elif rel_x > 0.65:
				shade = palette["armor_light"]
			elif rel_x > 0.45 and rel_x < 0.55:
				# Center crease/fold line
				if y > body_y + 2 and y < body_y + 7:
					shade = armor_mid
			# Shoulder shine on top rows
			if y < body_y + 2 and rel_x > 0.3 and rel_x < 0.5:
				shade = armor_shine
			_safe_pixel(img, x, y, shade)
	# Top outline of torso
	for x in range(10, 22):
		_safe_pixel(img, x, body_y - 1, outline)

	# Belt detail with buckle
	for x in range(11, 22):
		_safe_pixel(img, x, body_y + 7, palette["armor_dark"])
	# Belt buckle (2x2 bright spot)
	_safe_pixel(img, 15, body_y + 7, armor_shine)
	_safe_pixel(img, 16, body_y + 7, armor_shine)

	# Arms with swing animation, outline, and multi-tone shading
	var left_arm_y = body_y + 1 + left_arm
	var right_arm_y = body_y + 1 + right_arm
	for i in range(6):
		# Left arm (shadow side)
		_safe_pixel(img, 8, left_arm_y + i, outline)
		_safe_pixel(img, 9, left_arm_y + i, palette["armor_dark"])
		_safe_pixel(img, 10, left_arm_y + i, armor_mid)
		_safe_pixel(img, 11, left_arm_y + i, outline)
		# Right arm (lit side)
		_safe_pixel(img, 21, right_arm_y + i, outline)
		_safe_pixel(img, 22, right_arm_y + i, armor_mid)
		_safe_pixel(img, 23, right_arm_y + i, palette["armor_light"])
		_safe_pixel(img, 24, right_arm_y + i, outline)

	# Hands at end of arms with skin tones
	_safe_pixel(img, 8, left_arm_y + 6, outline)
	_safe_pixel(img, 9, left_arm_y + 6, skin_shadow)
	_safe_pixel(img, 10, left_arm_y + 6, palette["skin"])
	_safe_pixel(img, 11, left_arm_y + 6, outline)
	_safe_pixel(img, 21, right_arm_y + 6, outline)
	_safe_pixel(img, 22, right_arm_y + 6, palette["skin"])
	_safe_pixel(img, 23, right_arm_y + 6, skin_light)
	_safe_pixel(img, 24, right_arm_y + 6, outline)

	# Legs with proper stride, outline, and shading
	var leg_y = body_y + 10

	# Left leg
	var left_leg_x = 13 - left_leg
	var left_leg_length = 5 + (1 if left_leg > 1 else 0)
	for i in range(left_leg_length):
		_safe_pixel(img, left_leg_x - 1, leg_y + i, outline)
		_safe_pixel(img, left_leg_x, leg_y + i, pants_dark)
		_safe_pixel(img, left_leg_x + 1, leg_y + i, palette["pants"])
		_safe_pixel(img, left_leg_x + 2, leg_y + i, outline)

	# Right leg
	var right_leg_x = 18 + right_leg
	var right_leg_length = 5 + (1 if right_leg > 1 else 0)
	for i in range(right_leg_length):
		_safe_pixel(img, right_leg_x - 1, leg_y + i, outline)
		_safe_pixel(img, right_leg_x, leg_y + i, palette["pants"])
		_safe_pixel(img, right_leg_x + 1, leg_y + i, pants_dark)
		_safe_pixel(img, right_leg_x + 2, leg_y + i, outline)

	# Boots with highlight and outline
	var left_boot_y = leg_y + left_leg_length
	var right_boot_y = leg_y + right_leg_length
	# Left boot
	_safe_pixel(img, left_leg_x - 2, left_boot_y, outline)
	_safe_pixel(img, left_leg_x - 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x, left_boot_y, boots_light)
	_safe_pixel(img, left_leg_x + 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 2, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 3, left_boot_y, outline)
	# Boot sole outline
	_safe_pixel(img, left_leg_x - 1, left_boot_y + 1, outline)
	_safe_pixel(img, left_leg_x, left_boot_y + 1, outline)
	_safe_pixel(img, left_leg_x + 1, left_boot_y + 1, outline)
	_safe_pixel(img, left_leg_x + 2, left_boot_y + 1, outline)
	# Right boot
	_safe_pixel(img, right_leg_x - 2, right_boot_y, outline)
	_safe_pixel(img, right_leg_x - 1, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 1, right_boot_y, boots_light)
	_safe_pixel(img, right_leg_x + 2, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 3, right_boot_y, outline)
	# Boot sole outline
	_safe_pixel(img, right_leg_x - 1, right_boot_y + 1, outline)
	_safe_pixel(img, right_leg_x, right_boot_y + 1, outline)
	_safe_pixel(img, right_leg_x + 1, right_boot_y + 1, outline)
	_safe_pixel(img, right_leg_x + 2, right_boot_y + 1, outline)


func _draw_character_back(img: Image, palette: Dictionary, phase: Dictionary) -> void:
	var bob = phase["bob"]
	var left_leg = phase["left_leg"]
	var right_leg = phase["right_leg"]
	var left_arm = phase["left_arm"]
	var right_arm = phase["right_arm"]
	var outline = palette.get("outline", Color(0.10, 0.08, 0.06))
	var skin_shadow = palette.get("skin_shadow", palette["skin"].darkened(0.15))
	var hair_light = palette.get("hair_light", palette["hair"].lightened(0.15))
	var hair_dark = palette.get("hair_dark", palette["hair"].darkened(0.2))
	var armor_mid = palette.get("armor_mid", palette["armor"])
	var armor_shine = palette.get("armor_shine", palette["armor_light"].lightened(0.15))
	var pants_dark = palette.get("pants_dark", palette["pants"].darkened(0.2))
	var boots_light = palette.get("boots_light", palette["boots"].lightened(0.15))

	# Shadow beneath character (elliptical)
	var shadow_y = 29
	for x in range(11, 22):
		var dist = abs(x - 16.0) / 5.5
		if dist <= 1.0:
			var shadow_alpha = 0.25 * (1.0 - dist * dist)
			_safe_pixel(img, x, shadow_y, Color(0, 0, 0, shadow_alpha))
			if shadow_alpha > 0.12:
				_safe_pixel(img, x, shadow_y + 1, Color(0, 0, 0, shadow_alpha * 0.5))

	# Head (back view - mostly hair with multi-zone shading)
	var head_y = 4 - bob
	var head_cx = 16
	var head_rx = 6
	var head_ry = 5
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist <= 1.0:
				var px = head_cx + x
				var py = head_y + 4 + y
				# Hair shading: left highlight, right shadow, top shine
				var c = palette["hair"]
				if y < -2:
					c = hair_light  # Top highlight
				elif y > 2:
					c = hair_dark  # Bottom shadow
				elif x < -3:
					c = hair_light  # Left light
				elif x > 3:
					c = hair_dark  # Right shadow
				# Edge darkening
				if dist > 0.82:
					c = c.darkened(0.08)
				_safe_pixel(img, px, py, c)
			elif dist <= 1.2 and dist > 1.0:
				_safe_pixel(img, head_cx + x, head_y + 4 + y, outline)

	# Hair texture streaks (SNES style)
	for y in range(head_y - 1, head_y + 4):
		# Shine streak on left side
		if abs(y - head_y) < 3:
			_safe_pixel(img, 14, y, hair_light)
			_safe_pixel(img, 15, y, hair_light)
	# Hair parting line
	for y in range(head_y, head_y + 5):
		_safe_pixel(img, 16, y, hair_dark)
	# Hair outline on top
	for x in range(10, 23):
		if abs(x - 16) < 6:
			_safe_pixel(img, x, head_y - 2, outline)

	# Neck peek (skin between hair and armor)
	_safe_pixel(img, 14, head_y + 8, outline)
	_safe_pixel(img, 15, head_y + 8, skin_shadow)
	_safe_pixel(img, 16, head_y + 8, palette["skin"])
	_safe_pixel(img, 17, head_y + 8, skin_shadow)
	_safe_pixel(img, 18, head_y + 8, outline)

	# Body with 4-zone shading and outline
	var body_y = head_y + 9
	for y in range(body_y, body_y + 10):
		var body_width = 6 if y < body_y + 3 else 5
		_safe_pixel(img, 16 - body_width - 1, y, outline)
		_safe_pixel(img, 16 + body_width, y, outline)
		for x in range(16 - body_width, 16 + body_width):
			var rel_x = float(x - (16 - body_width)) / float(body_width * 2)
			var shade = palette["armor"]
			if rel_x < 0.15:
				shade = palette["armor_dark"]
			elif rel_x < 0.3:
				shade = armor_mid
			elif rel_x > 0.85:
				shade = palette["armor_dark"]
			elif rel_x > 0.65:
				shade = palette["armor_light"]
			# Shoulder shine on top
			if y < body_y + 2 and rel_x > 0.3 and rel_x < 0.5:
				shade = armor_shine
			_safe_pixel(img, x, y, shade)

	# Back detail - spine line / armor seam
	for y in range(body_y + 1, body_y + 7):
		_safe_pixel(img, 16, y, palette["armor_dark"])
	# Back armor plate edges
	for y in range(body_y + 3, body_y + 7):
		_safe_pixel(img, 13, y, armor_mid)
		_safe_pixel(img, 19, y, armor_mid)

	# Belt with buckle
	for x in range(11, 22):
		_safe_pixel(img, x, body_y + 7, palette["armor_dark"])
	_safe_pixel(img, 15, body_y + 7, armor_shine)
	_safe_pixel(img, 16, body_y + 7, armor_shine)

	# Top outline of torso
	for x in range(10, 22):
		_safe_pixel(img, x, body_y - 1, outline)

	# Arms with swing, outline, and multi-tone
	var left_arm_y = body_y + 1 + left_arm
	var right_arm_y = body_y + 1 + right_arm
	for i in range(6):
		_safe_pixel(img, 8, left_arm_y + i, outline)
		_safe_pixel(img, 9, left_arm_y + i, palette["armor_dark"])
		_safe_pixel(img, 10, left_arm_y + i, armor_mid)
		_safe_pixel(img, 11, left_arm_y + i, outline)
		_safe_pixel(img, 21, right_arm_y + i, outline)
		_safe_pixel(img, 22, right_arm_y + i, armor_mid)
		_safe_pixel(img, 23, right_arm_y + i, palette["armor_light"])
		_safe_pixel(img, 24, right_arm_y + i, outline)

	# Hands
	_safe_pixel(img, 8, left_arm_y + 6, outline)
	_safe_pixel(img, 9, left_arm_y + 6, skin_shadow)
	_safe_pixel(img, 10, left_arm_y + 6, palette["skin"])
	_safe_pixel(img, 11, left_arm_y + 6, outline)
	_safe_pixel(img, 21, right_arm_y + 6, outline)
	_safe_pixel(img, 22, right_arm_y + 6, palette["skin"])
	_safe_pixel(img, 23, right_arm_y + 6, palette.get("skin_light", palette["skin"].lightened(0.1)))
	_safe_pixel(img, 24, right_arm_y + 6, outline)

	# Legs with stride, outline, and shading
	var leg_y = body_y + 10

	var left_leg_x = 13 - left_leg
	var left_leg_length = 5 + (1 if left_leg > 1 else 0)
	for i in range(left_leg_length):
		_safe_pixel(img, left_leg_x - 1, leg_y + i, outline)
		_safe_pixel(img, left_leg_x, leg_y + i, pants_dark)
		_safe_pixel(img, left_leg_x + 1, leg_y + i, palette["pants"])
		_safe_pixel(img, left_leg_x + 2, leg_y + i, outline)

	var right_leg_x = 18 + right_leg
	var right_leg_length = 5 + (1 if right_leg > 1 else 0)
	for i in range(right_leg_length):
		_safe_pixel(img, right_leg_x - 1, leg_y + i, outline)
		_safe_pixel(img, right_leg_x, leg_y + i, palette["pants"])
		_safe_pixel(img, right_leg_x + 1, leg_y + i, pants_dark)
		_safe_pixel(img, right_leg_x + 2, leg_y + i, outline)

	# Boots with highlight and outline
	var left_boot_y = leg_y + left_leg_length
	var right_boot_y = leg_y + right_leg_length
	_safe_pixel(img, left_leg_x - 2, left_boot_y, outline)
	_safe_pixel(img, left_leg_x - 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x, left_boot_y, boots_light)
	_safe_pixel(img, left_leg_x + 1, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 2, left_boot_y, palette["boots"])
	_safe_pixel(img, left_leg_x + 3, left_boot_y, outline)
	_safe_pixel(img, left_leg_x - 1, left_boot_y + 1, outline)
	_safe_pixel(img, left_leg_x, left_boot_y + 1, outline)
	_safe_pixel(img, left_leg_x + 1, left_boot_y + 1, outline)
	_safe_pixel(img, left_leg_x + 2, left_boot_y + 1, outline)
	_safe_pixel(img, right_leg_x - 2, right_boot_y, outline)
	_safe_pixel(img, right_leg_x - 1, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 1, right_boot_y, boots_light)
	_safe_pixel(img, right_leg_x + 2, right_boot_y, palette["boots"])
	_safe_pixel(img, right_leg_x + 3, right_boot_y, outline)
	_safe_pixel(img, right_leg_x - 1, right_boot_y + 1, outline)
	_safe_pixel(img, right_leg_x, right_boot_y + 1, outline)
	_safe_pixel(img, right_leg_x + 1, right_boot_y + 1, outline)
	_safe_pixel(img, right_leg_x + 2, right_boot_y + 1, outline)


func _draw_character_side(img: Image, palette: Dictionary, phase: Dictionary, facing_left: bool) -> void:
	var bob = phase["bob"]
	var front_leg = phase["left_leg"] if facing_left else phase["right_leg"]
	var back_leg = phase["right_leg"] if facing_left else phase["left_leg"]
	var front_arm = phase["left_arm"] if facing_left else phase["right_arm"]
	var back_arm = phase["right_arm"] if facing_left else phase["left_arm"]
	var outline = palette.get("outline", Color(0.10, 0.08, 0.06))
	var skin_light = palette.get("skin_light", palette["skin"].lightened(0.1))
	var skin_shadow = palette.get("skin_shadow", palette["skin"].darkened(0.15))
	var hair_light = palette.get("hair_light", palette["hair"].lightened(0.15))
	var hair_dark = palette.get("hair_dark", palette["hair"].darkened(0.2))
	var armor_mid = palette.get("armor_mid", palette["armor"])
	var armor_shine = palette.get("armor_shine", palette["armor_light"].lightened(0.15))
	var pants_dark = palette.get("pants_dark", palette["pants"].darkened(0.2))
	var boots_light = palette.get("boots_light", palette["boots"].lightened(0.15))

	var flip = -1 if facing_left else 1
	var center_x = 16

	# Shadow beneath character (elliptical)
	var shadow_y = 29
	for x in range(11, 22):
		var dist = abs(x - 16.0) / 5.5
		if dist <= 1.0:
			var shadow_alpha = 0.25 * (1.0 - dist * dist)
			_safe_pixel(img, x, shadow_y, Color(0, 0, 0, shadow_alpha))
			if shadow_alpha > 0.12:
				_safe_pixel(img, x, shadow_y + 1, Color(0, 0, 0, shadow_alpha * 0.5))

	# Head (side view - narrower profile with multi-zone skin shading)
	var head_y = 4 - bob
	var head_rx = 5
	var head_ry = 5
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist <= 1.0:
				var px = center_x + x
				var py = head_y + 4 + y
				var c = palette["skin"]
				# Profile shading: face side lighter, back side darker
				if (facing_left and x > 1) or (not facing_left and x < -1):
					c = skin_shadow  # Back of head shadow
				elif y < -2:
					c = skin_light  # Forehead
				elif y > 2:
					c = skin_shadow  # Chin
				if dist > 0.82:
					c = c.darkened(0.08)
				_safe_pixel(img, px, py, c)
			elif dist <= 1.2 and dist > 1.0:
				_safe_pixel(img, center_x + x, head_y + 4 + y, outline)

	# Nose bump on profile (more defined)
	var nose_x = center_x + (4 * flip)
	_safe_pixel(img, nose_x, head_y + 4, palette["skin"])
	_safe_pixel(img, nose_x, head_y + 5, skin_shadow)
	_safe_pixel(img, nose_x + flip, head_y + 4, outline)  # Nose outline

	# Hair (on back of head, fuller) with shading zones
	var hair_back_dir = -flip
	for y in range(head_y - 1, head_y + 7):
		for offset in range(4):
			var hx = center_x + ((2 + offset) * hair_back_dir)
			if hx >= 0 and hx < SPRITE_SIZE:
				var c = palette["hair"]
				if offset < 1:
					c = hair_dark  # Inner transition
				elif offset > 2:
					c = hair_dark  # Outer edge
				elif y < head_y + 1:
					c = hair_light  # Top highlight
				_safe_pixel(img, hx, y, c)
	# Top hair with shine
	for x in range(center_x - 4, center_x + 5):
		var c = palette["hair"]
		if abs(x - (center_x - 1)) < 2:
			c = hair_light  # Shine streak
		_safe_pixel(img, x, head_y - 1, c)
		_safe_pixel(img, x, head_y, c)
		if abs(x - center_x) < 3:
			_safe_pixel(img, x, head_y + 1, c)
	# Hair outline
	for x in range(center_x - 4, center_x + 5):
		_safe_pixel(img, x, head_y - 2, outline)

	# Eye (one visible on side) with SNES-quality detail
	var eye_x = center_x + (2 * flip)
	var eye_white_x = eye_x + (1 if facing_left else -1)
	_safe_pixel(img, eye_white_x, head_y + 4, Color(0.95, 0.95, 0.95))  # White
	_safe_pixel(img, eye_x, head_y + 4, Color(0.15, 0.25, 0.45))        # Iris
	_safe_pixel(img, eye_x, head_y + 5, Color(0.0, 0.0, 0.0))           # Pupil
	_safe_pixel(img, eye_white_x, head_y + 4, Color(1.0, 1.0, 1.0))     # Catchlight
	# Eyelid line
	_safe_pixel(img, eye_x, head_y + 3, outline)
	_safe_pixel(img, eye_white_x, head_y + 3, outline)
	# Lower lash
	_safe_pixel(img, eye_x, head_y + 5, Color(0.0, 0.0, 0.0))

	# Eyebrow with expression
	_safe_pixel(img, eye_x, head_y + 2, hair_dark)
	_safe_pixel(img, eye_white_x, head_y + 2, hair_dark)
	_safe_pixel(img, eye_x + flip, head_y + 3, hair_dark)

	# Mouth
	var mouth_x = center_x + flip
	_safe_pixel(img, mouth_x, head_y + 6, Color(0.72, 0.48, 0.45))
	_safe_pixel(img, mouth_x + flip, head_y + 6, Color(0.65, 0.42, 0.40))

	# Neck with shading
	_safe_pixel(img, center_x - 1, head_y + 8, outline)
	_safe_pixel(img, center_x, head_y + 8, skin_shadow)
	_safe_pixel(img, center_x + 1, head_y + 8, outline)

	# Body with 4-zone shading and outline
	var body_y = head_y + 9
	for y in range(body_y, body_y + 10):
		var body_half_width = 4
		# Body outline
		_safe_pixel(img, center_x - body_half_width - 1, y, outline)
		_safe_pixel(img, center_x + body_half_width + 1, y, outline)
		for offset in range(-body_half_width, body_half_width + 1):
			var bx = center_x + offset
			var shade = palette["armor"]
			# Directional shading: facing side lighter, back side darker
			if facing_left:
				if offset < -2:
					shade = palette["armor_light"]
				elif offset < 0:
					shade = armor_mid
				elif offset > 2:
					shade = palette["armor_dark"]
			else:
				if offset > 2:
					shade = palette["armor_light"]
				elif offset > 0:
					shade = armor_mid
				elif offset < -2:
					shade = palette["armor_dark"]
			# Shoulder shine
			if y < body_y + 2:
				if (facing_left and offset < -1) or (not facing_left and offset > 1):
					shade = armor_shine
			_safe_pixel(img, bx, y, shade)
	# Top body outline
	for offset in range(-4, 5):
		_safe_pixel(img, center_x + offset, body_y - 1, outline)

	# Belt
	for offset in range(-4, 5):
		_safe_pixel(img, center_x + offset, body_y + 7, palette["armor_dark"])
	_safe_pixel(img, center_x, body_y + 7, armor_shine)  # Buckle

	# Back arm (behind body, swinging) with outline
	var back_arm_x = center_x + (4 if facing_left else -4)
	var back_arm_y_offset = -back_arm
	for i in range(5):
		var ay = body_y + 2 + back_arm_y_offset + i
		if ay >= 0 and ay < SPRITE_SIZE:
			_safe_pixel(img, back_arm_x - 1, ay, outline)
			_safe_pixel(img, back_arm_x, ay, palette["armor_dark"])
			_safe_pixel(img, back_arm_x + 1, ay, outline)
	var bh_y = body_y + 7 + back_arm_y_offset
	if bh_y >= 0 and bh_y < SPRITE_SIZE:
		_safe_pixel(img, back_arm_x, bh_y, skin_shadow)

	# Front arm (in front of body) with outline and shading
	var front_arm_x = center_x + (-5 if facing_left else 5)
	var front_arm_y_offset = -front_arm
	for i in range(6):
		var ay = body_y + 1 + front_arm_y_offset + i
		if ay >= 0 and ay < SPRITE_SIZE:
			var inner_x = front_arm_x + (1 if facing_left else -1)
			_safe_pixel(img, front_arm_x + (-1 if facing_left else 1), ay, outline)
			_safe_pixel(img, front_arm_x, ay, palette["armor"] if facing_left else palette["armor_light"])
			_safe_pixel(img, inner_x, ay, palette["armor_light"] if facing_left else palette["armor"])
			_safe_pixel(img, inner_x + (1 if facing_left else -1), ay, outline)
	# Hand
	var fh_y = body_y + 7 + front_arm_y_offset
	if fh_y >= 0 and fh_y < SPRITE_SIZE:
		_safe_pixel(img, front_arm_x, fh_y, palette["skin"])
		_safe_pixel(img, front_arm_x + (1 if facing_left else -1), fh_y, skin_light)

	# Legs (side view - proper walking cycle) with outline
	var leg_y = body_y + 10

	# Back leg (darker, behind) with outline
	var back_leg_offset = back_leg - 1
	var back_leg_x = center_x + (1 if facing_left else -1)
	for i in range(6):
		var ly = leg_y + i
		var lx = back_leg_x + (back_leg_offset if not facing_left else -back_leg_offset)
		_safe_pixel(img, lx - 1, ly, outline)
		_safe_pixel(img, lx, ly, pants_dark)
		_safe_pixel(img, lx + (1 if facing_left else -1), ly, palette["pants"].darkened(0.15))
		_safe_pixel(img, lx + (2 if facing_left else -2), ly, outline)

	# Front leg (brighter, in front) with outline
	var front_leg_offset = front_leg - 1
	var front_leg_x = center_x + (-1 if facing_left else 1)
	for i in range(6):
		var ly = leg_y + i
		var lx = front_leg_x + (-front_leg_offset if facing_left else front_leg_offset)
		_safe_pixel(img, lx + (-2 if facing_left else 2), ly, outline)
		_safe_pixel(img, lx + (-1 if facing_left else 1), ly, palette["pants"])
		_safe_pixel(img, lx, ly, palette["pants"])
		_safe_pixel(img, lx + (1 if facing_left else -1), ly, outline)

	# Boots with outline and highlight
	var boot_y = leg_y + 5
	var back_boot_x = back_leg_x + (back_leg_offset if not facing_left else -back_leg_offset)
	var front_boot_x = front_leg_x + (-front_leg_offset if facing_left else front_leg_offset)

	# Back boot with outline
	_safe_pixel(img, back_boot_x - 2, boot_y, outline)
	_safe_pixel(img, back_boot_x - 1, boot_y, palette["boots"].darkened(0.15))
	_safe_pixel(img, back_boot_x, boot_y, palette["boots"].darkened(0.15))
	_safe_pixel(img, back_boot_x + 1, boot_y, palette["boots"].darkened(0.15))
	_safe_pixel(img, back_boot_x + 2, boot_y, outline)
	# Back boot sole
	_safe_pixel(img, back_boot_x - 1, boot_y + 1, outline)
	_safe_pixel(img, back_boot_x, boot_y + 1, outline)
	_safe_pixel(img, back_boot_x + 1, boot_y + 1, outline)

	# Front boot with outline and highlight
	_safe_pixel(img, front_boot_x - 2, boot_y, outline)
	_safe_pixel(img, front_boot_x - 1, boot_y, palette["boots"])
	_safe_pixel(img, front_boot_x, boot_y, boots_light)
	_safe_pixel(img, front_boot_x + 1, boot_y, palette["boots"])
	_safe_pixel(img, front_boot_x + (2 if not facing_left else -2), boot_y, palette["boots"])
	_safe_pixel(img, front_boot_x + (3 if not facing_left else -3), boot_y, outline)
	# Front boot sole
	_safe_pixel(img, front_boot_x - 1, boot_y + 1, outline)
	_safe_pixel(img, front_boot_x, boot_y + 1, outline)
	_safe_pixel(img, front_boot_x + 1, boot_y + 1, outline)
	_safe_pixel(img, front_boot_x + (2 if not facing_left else -2), boot_y + 1, outline)


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
