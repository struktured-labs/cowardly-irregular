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

## Movement physics
const ACCELERATION: float = 800.0
const DECELERATION: float = 600.0

## Animation
var _sprite: Sprite2D
var _anim_frame: int = 0
var _anim_timer: float = 0.0
const ANIM_SPEED: float = 0.08  # Seconds per frame (slightly faster for 4-frame cycle)
const SPRITE_SIZE: int = 32
const WALK_FRAMES: int = 4  # 4-frame walk cycle for smoother animation

## Sprite cache (direction -> frame -> texture) - instance level
var _sprite_cache: Dictionary = {}

## Static sprite cache shared across all OverworldPlayer instances (survives scene changes)
## Key: "<job>_<use_custom>_<hair_hex>_<skin_hex>" -> Dictionary of frame caches
static var _static_sprite_cache: Dictionary = {}

## Click-to-move
var _click_target: Vector2 = Vector2.ZERO
var _moving_to_click: bool = false
var _interact_on_arrival: bool = false
const CLICK_ARRIVE_DIST: float = 8.0
const INTERACT_ARRIVE_DIST: float = 40.0  # Close enough for 48px interaction range

## SNES-quality job color palettes — 3-tone shading (shadow/base/highlight) per region
## Keys: hair_s/hair/hair_h, skin_s/skin/skin_h, body_s/body/body_h,
##       leg_s/leg/leg_h, boot_s/boot/boot_h, accent (weapon/badge color), outline
const JOB_PALETTES: Dictionary = {
	"fighter": {
		# Steel-blue plate armor, brown leather, warm skin
		"outline": Color(0.08, 0.07, 0.06),
		"skin_s": Color(0.68, 0.54, 0.40), "skin": Color(0.84, 0.69, 0.54), "skin_h": Color(0.94, 0.80, 0.65),
		"hair_s": Color(0.22, 0.14, 0.08), "hair": Color(0.36, 0.24, 0.15), "hair_h": Color(0.50, 0.35, 0.22),
		"body_s": Color(0.18, 0.28, 0.50), "body": Color(0.28, 0.40, 0.65), "body_h": Color(0.45, 0.57, 0.82),
		"leg_s": Color(0.22, 0.18, 0.13), "leg": Color(0.36, 0.30, 0.22), "leg_h": Color(0.48, 0.40, 0.30),
		"boot_s": Color(0.16, 0.12, 0.09), "boot": Color(0.26, 0.20, 0.14), "boot_h": Color(0.38, 0.30, 0.20),
		"accent": Color(0.80, 0.72, 0.35),  # Gold trim
	},
	"cleric": {
		# White/cream robes with gold cross trim, warm blonde hair
		"outline": Color(0.10, 0.09, 0.07),
		"skin_s": Color(0.74, 0.62, 0.52), "skin": Color(0.90, 0.78, 0.66), "skin_h": Color(0.98, 0.90, 0.78),
		"hair_s": Color(0.30, 0.24, 0.16), "hair": Color(0.50, 0.40, 0.28), "hair_h": Color(0.66, 0.54, 0.38),
		"body_s": Color(0.72, 0.70, 0.62), "body": Color(0.90, 0.88, 0.80), "body_h": Color(0.98, 0.97, 0.92),
		"leg_s": Color(0.65, 0.62, 0.56), "leg": Color(0.82, 0.80, 0.72), "leg_h": Color(0.94, 0.92, 0.86),
		"boot_s": Color(0.40, 0.36, 0.28), "boot": Color(0.56, 0.50, 0.38), "boot_h": Color(0.68, 0.62, 0.48),
		"accent": Color(0.90, 0.78, 0.20),  # Gold holy symbol
	},
	"mage": {
		# Deep purple robes, silver staff accent, pale skin
		"outline": Color(0.08, 0.05, 0.12),
		"skin_s": Color(0.72, 0.62, 0.54), "skin": Color(0.88, 0.76, 0.66), "skin_h": Color(0.96, 0.86, 0.76),
		"hair_s": Color(0.28, 0.18, 0.38), "hair": Color(0.45, 0.30, 0.58), "hair_h": Color(0.62, 0.46, 0.75),
		"body_s": Color(0.22, 0.10, 0.34), "body": Color(0.36, 0.18, 0.52), "body_h": Color(0.54, 0.34, 0.72),
		"leg_s": Color(0.20, 0.08, 0.30), "leg": Color(0.32, 0.14, 0.46), "leg_h": Color(0.48, 0.28, 0.62),
		"boot_s": Color(0.14, 0.06, 0.20), "boot": Color(0.22, 0.10, 0.30), "boot_h": Color(0.34, 0.18, 0.42),
		"accent": Color(0.72, 0.88, 0.96),  # Ice-blue staff crystal
	},
	"rogue": {
		# Dark forest green/grey leather, hidden blades accent
		"outline": Color(0.05, 0.06, 0.05),
		"skin_s": Color(0.62, 0.50, 0.36), "skin": Color(0.78, 0.64, 0.48), "skin_h": Color(0.90, 0.76, 0.58),
		"hair_s": Color(0.08, 0.08, 0.06), "hair": Color(0.16, 0.16, 0.12), "hair_h": Color(0.28, 0.28, 0.22),
		"body_s": Color(0.12, 0.18, 0.12), "body": Color(0.22, 0.30, 0.22), "body_h": Color(0.36, 0.46, 0.36),
		"leg_s": Color(0.10, 0.14, 0.10), "leg": Color(0.18, 0.24, 0.18), "leg_h": Color(0.30, 0.38, 0.30),
		"boot_s": Color(0.10, 0.10, 0.08), "boot": Color(0.18, 0.18, 0.14), "boot_h": Color(0.28, 0.28, 0.22),
		"accent": Color(0.78, 0.74, 0.62),  # Steel dagger blade
	},
	"bard": {
		# Gold/amber doublet with red feather cap, warm tones
		"outline": Color(0.09, 0.07, 0.03),
		"skin_s": Color(0.68, 0.54, 0.40), "skin": Color(0.84, 0.70, 0.55), "skin_h": Color(0.94, 0.82, 0.66),
		"hair_s": Color(0.24, 0.16, 0.08), "hair": Color(0.40, 0.28, 0.14), "hair_h": Color(0.56, 0.42, 0.24),
		"body_s": Color(0.58, 0.48, 0.10), "body": Color(0.80, 0.66, 0.18), "body_h": Color(0.96, 0.84, 0.38),
		"leg_s": Color(0.34, 0.26, 0.08), "leg": Color(0.52, 0.42, 0.14), "leg_h": Color(0.68, 0.56, 0.24),
		"boot_s": Color(0.28, 0.22, 0.08), "boot": Color(0.44, 0.34, 0.14), "boot_h": Color(0.58, 0.46, 0.22),
		"accent": Color(0.85, 0.20, 0.18),  # Red feather
	},
	"guardian": {
		# Heavy bronze/gold plate, very sturdy build
		"outline": Color(0.08, 0.07, 0.05),
		"skin_s": Color(0.68, 0.54, 0.40), "skin": Color(0.84, 0.70, 0.55), "skin_h": Color(0.94, 0.82, 0.66),
		"hair_s": Color(0.18, 0.14, 0.10), "hair": Color(0.30, 0.24, 0.18), "hair_h": Color(0.44, 0.36, 0.26),
		"body_s": Color(0.42, 0.32, 0.10), "body": Color(0.62, 0.50, 0.18), "body_h": Color(0.80, 0.66, 0.30),
		"leg_s": Color(0.36, 0.28, 0.08), "leg": Color(0.54, 0.44, 0.16), "leg_h": Color(0.70, 0.58, 0.26),
		"boot_s": Color(0.28, 0.22, 0.08), "boot": Color(0.46, 0.36, 0.14), "boot_h": Color(0.60, 0.48, 0.22),
		"accent": Color(0.85, 0.80, 0.40),  # Bright gold shield trim
	},
	"ninja": {
		# All-black with dark navy, white sash, fast silhouette
		"outline": Color(0.04, 0.04, 0.06),
		"skin_s": Color(0.62, 0.50, 0.36), "skin": Color(0.78, 0.64, 0.48), "skin_h": Color(0.90, 0.76, 0.58),
		"hair_s": Color(0.05, 0.05, 0.08), "hair": Color(0.10, 0.10, 0.15), "hair_h": Color(0.18, 0.18, 0.26),
		"body_s": Color(0.06, 0.06, 0.10), "body": Color(0.12, 0.12, 0.18), "body_h": Color(0.22, 0.22, 0.32),
		"leg_s": Color(0.05, 0.05, 0.08), "leg": Color(0.10, 0.10, 0.15), "leg_h": Color(0.18, 0.18, 0.26),
		"boot_s": Color(0.05, 0.05, 0.08), "boot": Color(0.10, 0.10, 0.15), "boot_h": Color(0.18, 0.18, 0.26),
		"accent": Color(0.92, 0.92, 0.92),  # White sash/wrappings
	},
	"summoner": {
		# Emerald green ceremonial robes, circlet
		"outline": Color(0.06, 0.09, 0.06),
		"skin_s": Color(0.72, 0.60, 0.48), "skin": Color(0.88, 0.74, 0.60), "skin_h": Color(0.96, 0.84, 0.70),
		"hair_s": Color(0.16, 0.24, 0.16), "hair": Color(0.26, 0.38, 0.26), "hair_h": Color(0.38, 0.54, 0.38),
		"body_s": Color(0.12, 0.32, 0.20), "body": Color(0.20, 0.50, 0.34), "body_h": Color(0.34, 0.68, 0.50),
		"leg_s": Color(0.10, 0.28, 0.18), "leg": Color(0.18, 0.44, 0.30), "leg_h": Color(0.30, 0.60, 0.44),
		"boot_s": Color(0.12, 0.20, 0.14), "boot": Color(0.20, 0.32, 0.22), "boot_h": Color(0.32, 0.44, 0.34),
		"accent": Color(0.90, 0.76, 0.20),  # Gold summoning circle glow
	},
	"speculator": {
		# Sharp grey/charcoal suit, gold coin accent
		"outline": Color(0.07, 0.07, 0.07),
		"skin_s": Color(0.68, 0.54, 0.40), "skin": Color(0.84, 0.70, 0.55), "skin_h": Color(0.94, 0.82, 0.66),
		"hair_s": Color(0.16, 0.16, 0.16), "hair": Color(0.28, 0.28, 0.28), "hair_h": Color(0.42, 0.42, 0.42),
		"body_s": Color(0.18, 0.18, 0.20), "body": Color(0.30, 0.30, 0.34), "body_h": Color(0.46, 0.46, 0.50),
		"leg_s": Color(0.16, 0.16, 0.18), "leg": Color(0.26, 0.26, 0.30), "leg_h": Color(0.40, 0.40, 0.46),
		"boot_s": Color(0.12, 0.10, 0.08), "boot": Color(0.22, 0.18, 0.14), "boot_h": Color(0.34, 0.28, 0.22),
		"accent": Color(0.88, 0.76, 0.20),  # Gold coin
	},
	"scriptweaver": {
		# Teal tech outfit with glowing accents
		"outline": Color(0.06, 0.08, 0.08),
		"skin_s": Color(0.68, 0.56, 0.44), "skin": Color(0.84, 0.72, 0.58), "skin_h": Color(0.94, 0.82, 0.68),
		"hair_s": Color(0.08, 0.22, 0.20), "hair": Color(0.16, 0.36, 0.34), "hair_h": Color(0.26, 0.52, 0.50),
		"body_s": Color(0.10, 0.28, 0.28), "body": Color(0.18, 0.44, 0.44), "body_h": Color(0.30, 0.62, 0.60),
		"leg_s": Color(0.08, 0.22, 0.22), "leg": Color(0.16, 0.36, 0.36), "leg_h": Color(0.28, 0.52, 0.50),
		"boot_s": Color(0.08, 0.16, 0.16), "boot": Color(0.14, 0.26, 0.26), "boot_h": Color(0.22, 0.38, 0.38),
		"accent": Color(0.40, 0.96, 0.80),  # Neon code glow
	},
	"time_mage": {
		# Deep indigo with silver constellation patterns
		"outline": Color(0.06, 0.06, 0.10),
		"skin_s": Color(0.70, 0.60, 0.52), "skin": Color(0.86, 0.76, 0.66), "skin_h": Color(0.96, 0.88, 0.78),
		"hair_s": Color(0.12, 0.10, 0.28), "hair": Color(0.22, 0.18, 0.46), "hair_h": Color(0.36, 0.30, 0.64),
		"body_s": Color(0.14, 0.12, 0.36), "body": Color(0.24, 0.20, 0.56), "body_h": Color(0.38, 0.32, 0.76),
		"leg_s": Color(0.12, 0.10, 0.30), "leg": Color(0.20, 0.18, 0.48), "leg_h": Color(0.32, 0.28, 0.66),
		"boot_s": Color(0.10, 0.08, 0.22), "boot": Color(0.18, 0.14, 0.34), "boot_h": Color(0.28, 0.22, 0.48),
		"accent": Color(0.80, 0.88, 1.00),  # Silver starlight
	},
	"necromancer": {
		# Black robes with bone-white trim, sickly purple glow
		"outline": Color(0.04, 0.03, 0.06),
		"skin_s": Color(0.50, 0.46, 0.48), "skin": Color(0.66, 0.62, 0.64), "skin_h": Color(0.80, 0.76, 0.78),
		"hair_s": Color(0.06, 0.04, 0.08), "hair": Color(0.12, 0.08, 0.16), "hair_h": Color(0.22, 0.16, 0.28),
		"body_s": Color(0.08, 0.06, 0.10), "body": Color(0.14, 0.10, 0.18), "body_h": Color(0.24, 0.18, 0.30),
		"leg_s": Color(0.06, 0.04, 0.08), "leg": Color(0.12, 0.08, 0.14), "leg_h": Color(0.20, 0.14, 0.24),
		"boot_s": Color(0.06, 0.04, 0.08), "boot": Color(0.10, 0.08, 0.12), "boot_h": Color(0.18, 0.14, 0.22),
		"accent": Color(0.56, 0.86, 0.36),  # Sickly bone green
	},
	"bossbinder": {
		# Blood red tech armor with dark metal
		"outline": Color(0.08, 0.04, 0.04),
		"skin_s": Color(0.64, 0.50, 0.38), "skin": Color(0.80, 0.66, 0.52), "skin_h": Color(0.92, 0.78, 0.62),
		"hair_s": Color(0.20, 0.06, 0.06), "hair": Color(0.34, 0.12, 0.12), "hair_h": Color(0.50, 0.20, 0.20),
		"body_s": Color(0.30, 0.08, 0.08), "body": Color(0.50, 0.14, 0.14), "body_h": Color(0.70, 0.24, 0.24),
		"leg_s": Color(0.24, 0.06, 0.06), "leg": Color(0.40, 0.12, 0.12), "leg_h": Color(0.58, 0.20, 0.20),
		"boot_s": Color(0.14, 0.10, 0.10), "boot": Color(0.24, 0.16, 0.16), "boot_h": Color(0.36, 0.24, 0.24),
		"accent": Color(0.96, 0.82, 0.12),  # Gold circuit lines
	},
	"skiptrotter": {
		# Khaki/tan adventurer outfit, very casual
		"outline": Color(0.08, 0.07, 0.05),
		"skin_s": Color(0.68, 0.54, 0.38), "skin": Color(0.84, 0.70, 0.52), "skin_h": Color(0.94, 0.82, 0.64),
		"hair_s": Color(0.28, 0.22, 0.12), "hair": Color(0.46, 0.36, 0.20), "hair_h": Color(0.62, 0.50, 0.30),
		"body_s": Color(0.40, 0.32, 0.18), "body": Color(0.60, 0.50, 0.28), "body_h": Color(0.78, 0.66, 0.42),
		"leg_s": Color(0.32, 0.26, 0.16), "leg": Color(0.50, 0.42, 0.24), "leg_h": Color(0.66, 0.56, 0.36),
		"boot_s": Color(0.22, 0.18, 0.10), "boot": Color(0.36, 0.30, 0.16), "boot_h": Color(0.52, 0.44, 0.26),
		"accent": Color(0.60, 0.80, 0.96),  # Sky blue compass
	},
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

	# Rotate input to match Mode 7 camera direction
	if input_dir != Vector2.ZERO and Mode7Overlay.camera_angle != 0.0:
		input_dir = input_dir.rotated(Mode7Overlay.camera_angle)

	# Keyboard/gamepad cancels click-to-move
	if input_dir != Vector2.ZERO:
		_moving_to_click = false

	# Click-to-move fallback when no keyboard input
	if input_dir == Vector2.ZERO and _moving_to_click:
		var to_target = _click_target - global_position
		var arrive_dist = INTERACT_ARRIVE_DIST if _interact_on_arrival else CLICK_ARRIVE_DIST
		if to_target.length() < arrive_dist:
			_moving_to_click = false
			if _interact_on_arrival:
				_interact_on_arrival = false
				interaction_requested.emit()
		else:
			input_dir = to_target.normalized()

	if input_dir != Vector2.ZERO:
		input_dir = input_dir.normalized()
		velocity = velocity.move_toward(input_dir * move_speed, ACCELERATION * delta)
		is_moving = true

		# Update facing direction (prioritize horizontal for diagonal)
		if abs(input_dir.x) > abs(input_dir.y):
			current_direction = Direction.LEFT if input_dir.x < 0 else Direction.RIGHT
		else:
			current_direction = Direction.UP if input_dir.y < 0 else Direction.DOWN
	else:
		velocity = velocity.move_toward(Vector2.ZERO, DECELERATION * delta)
		is_moving = velocity.length() > 10.0

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

	# Left-click: interact with NPC if clicked near one, otherwise click-to-move
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_pos = get_global_mouse_position()
		var target_npc = _find_clicked_interactable(click_pos)
		if target_npc:
			var dist_to_npc = global_position.distance_to(target_npc.global_position)
			if dist_to_npc < INTERACT_ARRIVE_DIST:
				# Already close enough — interact immediately
				interaction_requested.emit()
			else:
				# Walk to the NPC, then interact on arrival
				_click_target = target_npc.global_position
				_moving_to_click = true
				_interact_on_arrival = true
		else:
			_click_target = click_pos
			_moving_to_click = true
			_interact_on_arrival = false
	# Right-click menu is handled by GameLoop — don't consume the event here


func _update_animation(delta: float) -> void:
	var speed = velocity.length()
	if speed > 10.0:
		var speed_factor = speed / move_speed
		var effective_frame_time = ANIM_SPEED / max(speed_factor, 0.3)
		_anim_timer += delta
		if _anim_timer >= effective_frame_time:
			_anim_timer -= effective_frame_time
			_anim_frame = (_anim_frame + 1) % WALK_FRAMES
			_update_sprite()
	else:
		if _anim_frame != 0:
			_anim_frame = 0
			_anim_timer = 0.0
			_update_sprite()


func _update_sprite() -> void:
	var cache_key = "%d_%d" % [current_direction, _anim_frame]
	if _sprite_cache.has(cache_key):
		_sprite.texture = _sprite_cache[cache_key]


func _get_static_cache_key() -> String:
	if _use_custom_colors:
		return "%s_1_%s_%s" % [current_job, _custom_hair_color.to_html(false), _custom_skin_color.to_html(false)]
	return "%s_0" % current_job


func _generate_all_sprites() -> void:
	var static_key = _get_static_cache_key()
	if _static_sprite_cache.has(static_key):
		_sprite_cache = _static_sprite_cache[static_key]
		return

	var new_cache: Dictionary = {}

	# Try artist sheet first — artist work is authoritative regardless of
	# custom colors. Custom colors only apply to proc-gen sprites; when artist
	# sheets exist, we use them as-is.
	var artist_cache = _try_build_artist_sprites()
	if not artist_cache.is_empty():
		_static_sprite_cache[static_key] = artist_cache
		_sprite_cache = artist_cache
		if _static_sprite_cache.size() > 30:
			_static_sprite_cache.erase(_static_sprite_cache.keys()[0])
		return

	for dir in [Direction.DOWN, Direction.UP, Direction.LEFT, Direction.RIGHT]:
		for frame in range(WALK_FRAMES):
			var img = _generate_character_sprite(dir, frame)
			var tex = ImageTexture.create_from_image(img)
			var cache_key = "%d_%d" % [dir, frame]
			new_cache[cache_key] = tex

	_static_sprite_cache[static_key] = new_cache
	_sprite_cache = new_cache

	if _static_sprite_cache.size() > 30:
		var keys = _static_sprite_cache.keys()
		_static_sprite_cache.erase(keys[0])


## Extract and downscale a single frame from a SpriteFrames animation into a 32x32 Image.
## Returns null if the frame cannot be extracted.
func _extract_artist_frame(sf: SpriteFrames, anim: String, frame_idx: int, flip_h: bool) -> ImageTexture:
	if not sf.has_animation(anim):
		return null
	var count = sf.get_frame_count(anim)
	if count == 0:
		return null
	var idx = frame_idx % count
	var frame_tex = sf.get_frame_texture(anim, idx)
	if not frame_tex:
		return null

	var src_img: Image = null
	if frame_tex is AtlasTexture:
		var atlas_tex = frame_tex as AtlasTexture
		if not atlas_tex.atlas:
			return null
		var atlas_img = atlas_tex.atlas.get_image()
		if not atlas_img:
			return null
		var region = atlas_tex.region
		src_img = atlas_img.get_region(Rect2i(int(region.position.x), int(region.position.y), int(region.size.x), int(region.size.y)))
	else:
		src_img = frame_tex.get_image()

	if not src_img:
		return null

	# Crop to opaque bounding box before downscaling — battle sprites are
	# 256x256 with the character occupying ~40% of the frame. Without cropping,
	# the 32x32 result is a tiny blob.
	var used_rect = src_img.get_used_rect()
	if used_rect.size.x > 0 and used_rect.size.y > 0:
		src_img = src_img.get_region(used_rect)

	if flip_h:
		src_img.flip_x()

	# Scale proportionally to fit within SPRITE_SIZE, then center on
	# transparent canvas. Direct resize(32,32) squashes the aspect ratio.
	var sw = src_img.get_width()
	var sh = src_img.get_height()
	var scale_factor = min(float(SPRITE_SIZE) / max(sw, 1), float(SPRITE_SIZE) / max(sh, 1))
	var new_w = max(1, int(sw * scale_factor))
	var new_h = max(1, int(sh * scale_factor))
	src_img.resize(new_w, new_h, Image.INTERPOLATE_NEAREST)

	var canvas = Image.create(SPRITE_SIZE, SPRITE_SIZE, true, Image.FORMAT_RGBA8)
	var x_off = (SPRITE_SIZE - new_w) / 2
	var y_off = SPRITE_SIZE - new_h  # foot-align to bottom
	canvas.blit_rect(src_img, Rect2i(0, 0, new_w, new_h), Vector2i(x_off, y_off))
	return ImageTexture.create_from_image(canvas)


## Try to build a full direction×frame sprite cache from artist sheets.
## Returns an empty Dictionary if the job has no usable artist sheet.
func _try_build_artist_sprites() -> Dictionary:
	# Only use artist sheets — check manifest to avoid proc-gen fallback
	if not HybridSpriteLoader.has_artist_sheet(current_job):
		print("[OVERWORLD] No artist sheet for '%s', using procedural" % current_job)
		return {}

	var sf = HybridSpriteLoader.load_sprite_frames(null, current_job)
	if not sf:
		return {}
	if not sf.has_animation("idle") or not sf.has_animation("walk"):
		print("[OVERWORLD] Artist sheet for '%s' missing idle/walk animations" % current_job)
		return {}

	# Verify at least one frame exists in each required animation
	if sf.get_frame_count("idle") == 0 or sf.get_frame_count("walk") == 0:
		return {}

	var cache: Dictionary = {}

	# walk animation: cycle through WALK_FRAMES walk frames
	# idle animation: use frame 0 for all non-walk (standing) frames
	for frame in range(WALK_FRAMES):
		var walk_tex_r = _extract_artist_frame(sf, "walk", frame, false)
		var walk_tex_l = _extract_artist_frame(sf, "walk", frame, true)
		var idle_tex   = _extract_artist_frame(sf, "idle", 0, false)

		if not walk_tex_r or not walk_tex_l or not idle_tex:
			return {}

		# right: artist frames facing right (artist side-profile default)
		cache["%d_%d" % [Direction.RIGHT, frame]] = walk_tex_r if frame > 0 else _extract_artist_frame(sf, "idle", 0, false)
		# left: horizontally flipped
		cache["%d_%d" % [Direction.LEFT, frame]]  = walk_tex_l if frame > 0 else _extract_artist_frame(sf, "idle", 0, true)
		# down/up: use first idle frame as front/back approximation
		cache["%d_%d" % [Direction.DOWN, frame]] = idle_tex
		cache["%d_%d" % [Direction.UP, frame]]   = idle_tex

	print("[OVERWORLD] Using artist sheet for '%s' overworld sprite" % current_job)
	return cache


func _generate_character_sprite(direction: Direction, frame: int) -> Image:
	var img = Image.create(SPRITE_SIZE, SPRITE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var palette = JOB_PALETTES.get(current_job, JOB_PALETTES["fighter"]).duplicate()

	# Override skin/hair with custom colors from party leader
	if _use_custom_colors:
		# Derive 3-tone palette from single color for custom skin/hair
		var sh = _custom_skin_color
		palette["skin_s"] = sh.darkened(0.18)
		palette["skin"] = sh
		palette["skin_h"] = sh.lightened(0.12)
		var hh = _custom_hair_color
		palette["hair_s"] = hh.darkened(0.22)
		palette["hair"] = hh
		palette["hair_h"] = hh.lightened(0.18)

	# 4-frame walk cycle:
	# 0 = neutral/stand, 1 = right stride, 2 = neutral/stand, 3 = left stride
	var phase = _get_walk_phase(frame)

	match direction:
		Direction.DOWN:
			_draw_chibi_front(img, palette, phase)
		Direction.UP:
			_draw_chibi_back(img, palette, phase)
		Direction.LEFT:
			_draw_chibi_side(img, palette, phase, true)
		Direction.RIGHT:
			_draw_chibi_side(img, palette, phase, false)

	return img


func _get_walk_phase(frame: int) -> Dictionary:
	# 4-frame walk cycle producing natural leg/arm swing
	# leg values: 0=neutral, positive=forward stride, negative=backward
	# arm values: mirror of opposite leg for natural cross-swing
	# bob: 0=ground contact, 1=up-stroke mid-swing
	match frame:
		0:  # Neutral stand / ground contact
			return {"bob": 0, "ll": 0, "rl": 0, "la": 0, "ra": 0}
		1:  # Right foot forward, left arm forward
			return {"bob": 1, "ll": -2, "rl": 2, "la": 1, "ra": -1}
		2:  # Neutral stand / ground contact (opposite side)
			return {"bob": 0, "ll": 0, "rl": 0, "la": 0, "ra": 0}
		3:  # Left foot forward, right arm forward
			return {"bob": 1, "ll": 2, "rl": -2, "la": -1, "ra": 1}
		_:
			return {"bob": 0, "ll": 0, "rl": 0, "la": 0, "ra": 0}


## =========================================================
## CHIBI SPRITE DRAWING — SNES-style overworld characters
## Canvas: 32x32  Centre X: 16  Feet baseline: 31
##
## Chibi proportions (all relative to feet at y=31):
##   Head top:    y=2   (12px tall head = 38% of height)
##   Neck:        y=13
##   Torso top:   y=14  Torso bottom: y=21  (8px)
##   Legs:        y=22–27  (6px)
##   Boots:       y=28–30  (3px, toe extends +1 forward)
##
## For each job the _draw_chibi_* functions:
##  1. Ground shadow (semi-transparent ellipse)
##  2. Headgear (drawn FIRST so head overlaps it)
##  3. Chibi head (10px wide × 12px tall ellipse)
##  4. Hair cap on top of head
##  5. Face: eyes, brows, nose, mouth
##  6. Neck
##  7. Torso (job-coloured body)
##  8. Arms (swing with phase)
##  9. Legs (stride with phase)
## 10. Boots
## 11. Job accessories (weapon on back, badge, etc.)
## =========================================================

# ---- shared helpers ----

func _px(img: Image, x: int, y: int, c: Color) -> void:
	# Inline safe pixel — clips to sprite bounds
	if x >= 0 and x < SPRITE_SIZE and y >= 0 and y < SPRITE_SIZE:
		img.set_pixel(x, y, c)


func _hline(img: Image, x0: int, x1: int, y: int, c: Color) -> void:
	for x in range(x0, x1 + 1):
		_px(img, x, y, c)


func _vline(img: Image, x: int, y0: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		_px(img, x, y, c)


func _draw_shadow(img: Image, cx: int, ground_y: int) -> void:
	# Soft elliptical ground shadow
	for dx in range(-6, 7):
		var t = float(dx) / 6.0
		var alpha = 0.22 * (1.0 - t * t)
		_px(img, cx + dx, ground_y,     Color(0, 0, 0, alpha))
		_px(img, cx + dx, ground_y - 1, Color(0, 0, 0, alpha * 0.5))


func _draw_chibi_head(img: Image, p: Dictionary, hx: int, hy: int) -> void:
	# hy = top-left y of head region (head is 10 wide, 12 tall)
	# hx = centre x
	# Draws: hair cap, head ellipse, eyes, brows, nose, mouth, neck
	var ol = p["outline"]
	var sk  = p["skin"];   var sks = p["skin_s"]; var skh = p["skin_h"]
	var hr  = p["hair"];   var hrs = p["hair_s"]; var hrh = p["hair_h"]

	# Hair cap (rows hy to hy+3 — sits on top of head)
	# Width tapers: row0=10, row1=10, row2=8, row3=6
	var hair_widths = [5, 5, 4, 3]  # half-widths from centre
	for row in range(4):
		var hw = hair_widths[row]
		for dx in range(-hw, hw + 1):
			var c = hrh if row == 0 and abs(dx) < 3 else (hrs if abs(dx) >= hw - 1 else hr)
			_px(img, hx + dx, hy + row, c)
		# Outline edges
		_px(img, hx - hw - 1, hy + row, ol)
		_px(img, hx + hw + 1, hy + row, ol)
	# Top hair outline
	_hline(img, hx - 5, hx + 5, hy - 1, ol)

	# Head ellipse: centre at hx, hy+7; rx=5, ry=5
	var head_cy = hy + 7
	var hrx = 5; var hry = 5
	for dy in range(-hry, hry + 1):
		for dx in range(-hrx, hrx + 1):
			var d2 = (float(dx)/hrx) * (float(dx)/hrx) + (float(dy)/hry) * (float(dy)/hry)
			if d2 <= 1.02:
				var c = sk
				if dy < -2: c = skh   # forehead
				elif dy > 2: c = sks   # chin
				elif abs(dx) >= 4: c = sks  # cheek shadow
				_px(img, hx + dx, head_cy + dy, c)

	# Head outline ring
	for dy in range(-hry - 1, hry + 2):
		for dx in range(-hrx - 1, hrx + 2):
			var d2 = (float(dx)/(hrx+0.5)) * (float(dx)/(hrx+0.5)) + (float(dy)/(hry+0.5)) * (float(dy)/(hry+0.5))
			if d2 >= 0.85 and d2 < 1.0:
				_px(img, hx + dx, head_cy + dy, ol)

	# Eyes — y = head_cy + 1 (chibi: big eyes, simple)
	var ey = head_cy + 1
	# Left eye cluster (dx -3, -2)
	_px(img, hx - 3, ey - 1, ol)
	_px(img, hx - 2, ey - 1, ol)
	_px(img, hx - 3, ey, Color(0.95, 0.95, 0.98))   # white
	_px(img, hx - 2, ey, Color(0.15, 0.20, 0.42))   # iris
	_px(img, hx - 2, ey + 1, Color(0.05, 0.05, 0.05)) # pupil
	_px(img, hx - 3, ey, Color(1, 1, 1))              # catchlight overwrite
	# Right eye cluster (dx +2, +3)
	_px(img, hx + 2, ey - 1, ol)
	_px(img, hx + 3, ey - 1, ol)
	_px(img, hx + 2, ey, Color(0.15, 0.20, 0.42))
	_px(img, hx + 3, ey, Color(0.95, 0.95, 0.98))
	_px(img, hx + 2, ey + 1, Color(0.05, 0.05, 0.05))
	_px(img, hx + 2, ey, Color(1, 1, 1))              # catchlight

	# Eyebrows
	_px(img, hx - 3, ey - 2, hrs)
	_px(img, hx - 2, ey - 2, hrs)
	_px(img, hx + 2, ey - 2, hrs)
	_px(img, hx + 3, ey - 2, hrs)

	# Nose (1px shadow dot at centre)
	_px(img, hx, head_cy + 3, sks)

	# Mouth
	_px(img, hx - 1, head_cy + 4, Color(0.70, 0.44, 0.42))
	_px(img, hx,     head_cy + 4, Color(0.62, 0.38, 0.36))
	_px(img, hx + 1, head_cy + 4, Color(0.70, 0.44, 0.42))

	# Neck (2px wide, 2 rows)
	var neck_y = head_cy + hry + 1
	_px(img, hx - 1, neck_y,     sks)
	_px(img, hx,     neck_y,     sk)
	_px(img, hx + 1, neck_y,     sks)
	_px(img, hx - 1, neck_y + 1, sks)
	_px(img, hx,     neck_y + 1, sk)
	_px(img, hx + 1, neck_y + 1, sks)
	# Neck outline
	_px(img, hx - 2, neck_y, ol);     _px(img, hx + 2, neck_y, ol)
	_px(img, hx - 2, neck_y + 1, ol); _px(img, hx + 2, neck_y + 1, ol)


func _draw_chibi_head_back(img: Image, p: Dictionary, hx: int, hy: int) -> void:
	# Back-facing head — all hair, no face features, neck nub
	var ol = p["outline"]
	var hr = p["hair"]; var hrs = p["hair_s"]; var hrh = p["hair_h"]
	var sk = p["skin"]; var sks = p["skin_s"]

	# Full hair dome (larger than front hair cap)
	var head_cy = hy + 7
	var hrx = 5; var hry = 5
	for dy in range(-hry - 2, hry + 1):
		for dx in range(-hrx, hrx + 1):
			var d2 = (float(dx)/hrx) * (float(dx)/hrx) + (float(dy)/(hry+1.0)) * (float(dy)/(hry+1.0))
			if d2 <= 1.02:
				var c = hr
				if dy < -3: c = hrh
				elif dy > 2: c = hrs
				elif abs(dx) >= 4: c = hrs
				_px(img, hx + dx, head_cy + dy, c)
	# Hair highlight streak (left of centre)
	for dy in range(-hry - 1, 0):
		_px(img, hx - 1, head_cy + dy, hrh)

	# Outline
	for dy in range(-hry - 3, hry + 2):
		for dx in range(-hrx - 1, hrx + 2):
			var d2 = (float(dx)/(hrx+0.5)) * (float(dx)/(hrx+0.5)) + (float(dy)/(hry+1.5)) * (float(dy)/(hry+1.5))
			if d2 >= 0.85 and d2 < 1.0:
				_px(img, hx + dx, head_cy + dy, ol)

	# Neck peek
	var neck_y = head_cy + hry + 1
	_px(img, hx - 1, neck_y,     sks); _px(img, hx, neck_y, sk); _px(img, hx + 1, neck_y, sks)
	_px(img, hx - 1, neck_y + 1, sks); _px(img, hx, neck_y + 1, sk); _px(img, hx + 1, neck_y + 1, sks)
	_px(img, hx - 2, neck_y, ol); _px(img, hx + 2, neck_y, ol)
	_px(img, hx - 2, neck_y + 1, ol); _px(img, hx + 2, neck_y + 1, ol)


func _draw_chibi_head_side(img: Image, p: Dictionary, hx: int, hy: int, face_right: bool) -> void:
	# Side-profile head: ellipse with face features on one side, hair behind
	var ol = p["outline"]
	var sk = p["skin"]; var sks = p["skin_s"]; var skh = p["skin_h"]
	var hr = p["hair"]; var hrs = p["hair_s"]; var hrh = p["hair_h"]
	var face_dir = 1 if face_right else -1  # +1 = face looks right

	var head_cy = hy + 7
	var hrx = 4; var hry = 5

	# Hair behind head (opposite side from face)
	var hair_start = -hrx * face_dir
	for dy in range(-hry - 2, hry + 1):
		for step in range(0, 4):
			var hbx = hx + hair_start - face_dir * step
			var c = hrh if dy < -2 else (hrs if step >= 2 else hr)
			_px(img, hbx, head_cy + dy, c)
	# Top hair over whole head
	for dx in range(-hrx - 1, hrx + 2):
		var c = hrh if abs(dx) < 2 else hr
		_px(img, hx + dx, head_cy - hry - 1, c)
		_px(img, hx + dx, head_cy - hry,     c)
	_hline(img, hx - hrx - 1, hx + hrx + 1, head_cy - hry - 2, ol)

	# Head ellipse (slightly narrower on side for profile feel)
	for dy in range(-hry, hry + 1):
		for dx in range(-hrx, hrx + 1):
			var d2 = (float(dx)/hrx) * (float(dx)/hrx) + (float(dy)/hry) * (float(dy)/hry)
			if d2 <= 1.02:
				var c = sk
				if dy < -2: c = skh
				elif dy > 2: c = sks
				elif dx * face_dir < -2: c = sks  # back of head shadow
				_px(img, hx + dx, head_cy + dy, c)

	# Outline
	for dy in range(-hry - 1, hry + 2):
		for dx in range(-hrx - 1, hrx + 2):
			var d2 = (float(dx)/(hrx+0.5)) * (float(dx)/(hrx+0.5)) + (float(dy)/(hry+0.5)) * (float(dy)/(hry+0.5))
			if d2 >= 0.85 and d2 < 1.0:
				_px(img, hx + dx, head_cy + dy, ol)

	# Nose bump on face side
	var nx = hx + face_dir * (hrx + 1)
	_px(img, nx, head_cy + 1, sk)
	_px(img, nx, head_cy + 2, sks)
	_px(img, nx + face_dir, head_cy + 1, ol)

	# One visible eye
	var ex = hx + face_dir * 2
	var ey = head_cy + 1
	_px(img, ex - face_dir, ey - 1, ol)
	_px(img, ex, ey - 1, ol)
	_px(img, ex - face_dir, ey, Color(0.95, 0.95, 0.98))
	_px(img, ex, ey, Color(0.15, 0.20, 0.42))
	_px(img, ex, ey + 1, Color(0.05, 0.05, 0.05))
	_px(img, ex - face_dir, ey, Color(1, 1, 1))  # catchlight

	# Eyebrow
	_px(img, ex - face_dir, ey - 2, p["hair_s"])
	_px(img, ex, ey - 2, p["hair_s"])

	# Mouth
	_px(img, hx + face_dir, head_cy + 4, Color(0.68, 0.42, 0.40))
	_px(img, hx + face_dir * 2, head_cy + 4, Color(0.62, 0.38, 0.36))

	# Neck
	var neck_y = head_cy + hry + 1
	_px(img, hx - 1, neck_y, sks); _px(img, hx, neck_y, sk); _px(img, hx + 1, neck_y, sks)
	_px(img, hx - 1, neck_y + 1, sks); _px(img, hx, neck_y + 1, sk); _px(img, hx + 1, neck_y + 1, sks)
	_px(img, hx - 2, neck_y, ol); _px(img, hx + 2, neck_y, ol)
	_px(img, hx - 2, neck_y + 1, ol); _px(img, hx + 2, neck_y + 1, ol)


func _draw_chibi_torso_front(img: Image, p: Dictionary, cx: int, ty: int) -> void:
	# Torso: 10px wide at shoulders, 8px at waist, 8 rows tall
	# ty = top of torso row
	var ol = p["outline"]
	var bs = p["body_s"]; var b = p["body"]; var bh = p["body_h"]
	var widths = [5, 5, 5, 4, 4, 4, 4, 4]  # half-widths per row
	for row in range(8):
		var w = widths[row]
		# Outline
		_px(img, cx - w - 1, ty + row, ol)
		_px(img, cx + w + 1, ty + row, ol)
		for dx in range(-w, w + 1):
			var c = b
			if dx <= -w + 1: c = bs   # left shadow
			elif dx >= w - 1: c = bs  # right shadow
			elif dx < 0: c = bh       # left-centre highlight
			# Shoulder shine on top 2 rows
			if row < 2 and abs(dx) < 3: c = bh
			_px(img, cx + dx, ty + row, c)
	# Top outline of torso
	_hline(img, cx - 5, cx + 5, ty - 1, ol)
	# Belt line at bottom
	_hline(img, cx - 4, cx + 4, ty + 7, p["leg_s"])
	_px(img, cx, ty + 7, p["accent"])  # belt buckle / badge


func _draw_chibi_torso_back(img: Image, p: Dictionary, cx: int, ty: int) -> void:
	# Same silhouette as front but with spine line detail
	var ol = p["outline"]
	var bs = p["body_s"]; var b = p["body"]; var bh = p["body_h"]
	var widths = [5, 5, 5, 4, 4, 4, 4, 4]
	for row in range(8):
		var w = widths[row]
		_px(img, cx - w - 1, ty + row, ol)
		_px(img, cx + w + 1, ty + row, ol)
		for dx in range(-w, w + 1):
			var c = b
			if dx <= -w + 1: c = bs
			elif dx >= w - 1: c = bs
			elif abs(dx) < 2: c = bs  # Spine crease
			if row < 2 and abs(dx) > 2: c = bh
			_px(img, cx + dx, ty + row, c)
	_hline(img, cx - 5, cx + 5, ty - 1, ol)
	_hline(img, cx - 4, cx + 4, ty + 7, p["leg_s"])


func _draw_chibi_torso_side(img: Image, p: Dictionary, cx: int, ty: int, face_right: bool) -> void:
	# Thinner torso from side: 6px wide (3 each side of centre)
	var ol = p["outline"]
	var bs = p["body_s"]; var b = p["body"]; var bh = p["body_h"]
	var fd = 1 if face_right else -1  # face direction
	for row in range(8):
		_px(img, cx - 3 - 1, ty + row, ol)
		_px(img, cx + 3 + 1, ty + row, ol)
		for dx in range(-3, 4):
			var c = b
			if dx * fd > 1: c = bh   # face side brighter
			elif dx * fd < -1: c = bs # back side darker
			if row < 2 and dx * fd > 0: c = bh
			_px(img, cx + dx, ty + row, c)
	_hline(img, cx - 3, cx + 3, ty - 1, ol)
	_hline(img, cx - 3, cx + 3, ty + 7, p["leg_s"])


func _draw_chibi_arms_front(img: Image, p: Dictionary, cx: int, ty: int, la: int, ra: int) -> void:
	# Arms hanging from shoulder tops; la/ra = vertical swing offset
	var ol = p["outline"]
	var bs = p["body_s"]; var b = p["body"]; var bh = p["body_h"]
	var sk = p["skin"]; var sks = p["skin_s"]
	# Left arm (at cx-6)
	var lax = cx - 6
	var lay_start = ty + la
	for i in range(5):
		_px(img, lax - 1, lay_start + i, ol)
		_px(img, lax,     lay_start + i, bs)
		_px(img, lax + 1, lay_start + i, b)
		_px(img, lax + 2, lay_start + i, ol)
	# Left hand
	_px(img, lax - 1, lay_start + 5, ol)
	_px(img, lax,     lay_start + 5, sks)
	_px(img, lax + 1, lay_start + 5, sk)
	_px(img, lax + 2, lay_start + 5, ol)
	# Right arm (at cx+6)
	var rax = cx + 5
	var ray_start = ty + ra
	for i in range(5):
		_px(img, rax - 1, ray_start + i, ol)
		_px(img, rax,     ray_start + i, b)
		_px(img, rax + 1, ray_start + i, bh)
		_px(img, rax + 2, ray_start + i, ol)
	# Right hand
	_px(img, rax - 1, ray_start + 5, ol)
	_px(img, rax,     ray_start + 5, sk)
	_px(img, rax + 1, ray_start + 5, sk)
	_px(img, rax + 2, ray_start + 5, ol)


func _draw_chibi_arms_back(img: Image, p: Dictionary, cx: int, ty: int, la: int, ra: int) -> void:
	# Mirror of front arms for back view
	_draw_chibi_arms_front(img, p, cx, ty, la, ra)


func _draw_chibi_arms_side(img: Image, p: Dictionary, cx: int, ty: int,
		front_arm: int, back_arm: int, face_right: bool) -> void:
	# Side view: two arms stacked, back arm behind body, front arm in front
	var ol = p["outline"]
	var bs = p["body_s"]; var b = p["body"]; var bh = p["body_h"]
	var sk = p["skin"]; var sks = p["skin_s"]
	var fd = 1 if face_right else -1

	# Back arm (body-width side, darker)
	var bax = cx - fd * 3
	for i in range(5):
		var ay = ty + 1 - back_arm + i
		_px(img, bax - 1, ay, ol)
		_px(img, bax,     ay, bs)
		_px(img, bax + 1, ay, ol)
	_px(img, bax, ty + 6 - back_arm, sks)  # back hand

	# Front arm (face side, lighter)
	var fax = cx + fd * 4
	for i in range(5):
		var ay = ty + 1 - front_arm + i
		_px(img, fax - 1, ay, ol)
		_px(img, fax,     ay, b)
		_px(img, fax + 1, ay, bh)
		_px(img, fax + 2, ay, ol)
	# Front hand
	_px(img, fax,     ty + 6 - front_arm, sk)
	_px(img, fax + 1, ty + 6 - front_arm, sk)


func _draw_chibi_legs_front(img: Image, p: Dictionary, cx: int, leg_top: int, ll: int, rl: int) -> void:
	# Legs: each 2px wide, 6 rows. ll/rl = stride offset (positive = forward = more to left/right)
	var ol = p["outline"]
	var ls = p["leg_s"]; var lg = p["leg"]; var lh = p["leg_h"]
	var bs = p["boot_s"]; var bt = p["boot"]; var bth = p["boot_h"]
	# Left leg: centred at cx-3, shifted left by ll
	var llx = cx - 3 - ll
	for i in range(6):
		_px(img, llx - 1, leg_top + i, ol)
		_px(img, llx,     leg_top + i, ls)
		_px(img, llx + 1, leg_top + i, lg)
		_px(img, llx + 2, leg_top + i, ol)
	# Left boot (row 6–7 below leg)
	_px(img, llx - 1, leg_top + 6, ol)
	_px(img, llx,     leg_top + 6, bs)
	_px(img, llx + 1, leg_top + 6, bt)
	_px(img, llx + 2, leg_top + 6, bth)
	_px(img, llx + 3, leg_top + 6, ol)
	_hline(img, llx - 1, llx + 3, leg_top + 7, ol)  # boot sole

	# Right leg: centred at cx+2, shifted right by rl
	var rlx = cx + 2 + rl
	for i in range(6):
		_px(img, rlx - 1, leg_top + i, ol)
		_px(img, rlx,     leg_top + i, lg)
		_px(img, rlx + 1, leg_top + i, lh)
		_px(img, rlx + 2, leg_top + i, ol)
	# Right boot
	_px(img, rlx - 1, leg_top + 6, ol)
	_px(img, rlx,     leg_top + 6, bt)
	_px(img, rlx + 1, leg_top + 6, bth)
	_px(img, rlx + 2, leg_top + 6, bt)
	_px(img, rlx + 3, leg_top + 6, ol)
	_hline(img, rlx - 1, rlx + 3, leg_top + 7, ol)


func _draw_chibi_legs_back(img: Image, p: Dictionary, cx: int, leg_top: int, ll: int, rl: int) -> void:
	# Back legs same as front — reverse shading only
	var ol = p["outline"]
	var ls = p["leg_s"]; var lg = p["leg"]; var lh = p["leg_h"]
	var bs = p["boot_s"]; var bt = p["boot"]; var bth = p["boot_h"]
	var llx = cx - 3 - ll
	for i in range(6):
		_px(img, llx - 1, leg_top + i, ol)
		_px(img, llx,     leg_top + i, lg)
		_px(img, llx + 1, leg_top + i, ls)
		_px(img, llx + 2, leg_top + i, ol)
	_px(img, llx - 1, leg_top + 6, ol); _px(img, llx, leg_top + 6, bt)
	_px(img, llx + 1, leg_top + 6, bs); _px(img, llx + 2, leg_top + 6, bs)
	_px(img, llx + 3, leg_top + 6, ol)
	_hline(img, llx - 1, llx + 3, leg_top + 7, ol)

	var rlx = cx + 2 + rl
	for i in range(6):
		_px(img, rlx - 1, leg_top + i, ol)
		_px(img, rlx,     leg_top + i, ls)
		_px(img, rlx + 1, leg_top + i, lg)
		_px(img, rlx + 2, leg_top + i, ol)
	_px(img, rlx - 1, leg_top + 6, ol); _px(img, rlx, leg_top + 6, bs)
	_px(img, rlx + 1, leg_top + 6, bt); _px(img, rlx + 2, leg_top + 6, bth)
	_px(img, rlx + 3, leg_top + 6, ol)
	_hline(img, rlx - 1, rlx + 3, leg_top + 7, ol)


func _draw_chibi_legs_side(img: Image, p: Dictionary, cx: int, leg_top: int,
		front_leg: int, back_leg: int, face_right: bool) -> void:
	# Side legs: front leg brighter (face side), back leg darker, offset for stride
	var ol = p["outline"]
	var ls = p["leg_s"]; var lg = p["leg"]; var lh = p["leg_h"]
	var bs = p["boot_s"]; var bt = p["boot"]; var bth = p["boot_h"]
	var fd = 1 if face_right else -1

	# Back leg (darker, slight offset behind)
	var blx = cx - fd * 1
	var bloff = back_leg * fd
	for i in range(6):
		var lx = blx + bloff
		_px(img, lx - 1, leg_top + i, ol)
		_px(img, lx,     leg_top + i, ls)
		_px(img, lx + 1, leg_top + i, lg.darkened(0.1))
		_px(img, lx + 2, leg_top + i, ol)
	var blboot = blx + bloff
	_px(img, blboot - 1, leg_top + 6, ol); _px(img, blboot, leg_top + 6, bs)
	_px(img, blboot + 1, leg_top + 6, bt); _px(img, blboot + 2 + fd, leg_top + 6, ol)
	_hline(img, blboot - 1, blboot + 2, leg_top + 7, ol)

	# Front leg (brighter, further forward in stride)
	var flx = cx + fd * 1
	var floff = front_leg * fd
	for i in range(6):
		var lx = flx + floff
		_px(img, lx - 1, leg_top + i, ol)
		_px(img, lx,     leg_top + i, lg)
		_px(img, lx + 1, leg_top + i, lh)
		_px(img, lx + 2, leg_top + i, ol)
	var flboot = flx + floff
	_px(img, flboot - 1, leg_top + 6, ol); _px(img, flboot, leg_top + 6, bt)
	_px(img, flboot + 1, leg_top + 6, bth); _px(img, flboot + 2 + fd, leg_top + 6, ol)
	_hline(img, flboot - 1, flboot + 2, leg_top + 7, ol)


# ---- Job-specific headgear helpers ----

func _draw_headgear_helmet(img: Image, p: Dictionary, cx: int, hy: int) -> void:
	# Open-face steel helmet: visor ridge + cheek guards
	var ol = p["outline"]
	var bh = p["body_h"]; var b = p["body"]
	# Brow plate (2 rows above hair cap)
	_hline(img, cx - 5, cx + 5, hy - 2, b)
	_hline(img, cx - 5, cx + 5, hy - 3, bh)
	_hline(img, cx - 5, cx + 5, hy - 4, ol)
	# Side cheek guards (3 rows below hair start, framing face)
	for dy in range(3):
		_px(img, cx - 6, hy + 4 + dy, b)
		_px(img, cx - 7, hy + 4 + dy, ol)
		_px(img, cx + 6, hy + 4 + dy, b)
		_px(img, cx + 7, hy + 4 + dy, ol)
	# Helmet shine
	_px(img, cx - 2, hy - 3, bh.lightened(0.2))
	_px(img, cx - 1, hy - 3, bh.lightened(0.2))

func _draw_headgear_pointed_hat(img: Image, p: Dictionary, cx: int, hy: int) -> void:
	# Tall conical mage hat: 8 rows of taper + brim
	var ol = p["outline"]
	var b = p["body"]; var bh = p["body_h"]; var bs = p["body_s"]
	# Hat cone (rows hy-9 to hy-1)
	for row in range(9):
		var hw = row  # widens toward brim
		var y = hy - 9 + row
		_hline(img, cx - hw, cx + hw, y, b if row > 0 else bh)
		_px(img, cx - hw - 1, y, ol)
		_px(img, cx + hw + 1, y, ol)
	# Brim (1 row, extends beyond cone — shadow tone on underside)
	_hline(img, cx - 6, cx + 6, hy,     b)
	_hline(img, cx - 7, cx + 7, hy - 1, bs)
	_hline(img, cx - 7, cx + 7, hy + 1, ol)
	_hline(img, cx - 6, cx + 6, hy - 1, b)
	# Outline top tip
	_px(img, cx, hy - 10, ol)

func _draw_headgear_hood(img: Image, p: Dictionary, cx: int, hy: int) -> void:
	# Cleric hood: rounded cowl that frames the face
	var ol = p["outline"]
	var b = p["body"]; var bh = p["body_h"]; var bs = p["body_s"]
	# Hood dome (3 rows above hair)
	_hline(img, cx - 5, cx + 5, hy - 1, b)
	_hline(img, cx - 6, cx + 6, hy - 2, bh)
	_hline(img, cx - 5, cx + 5, hy - 3, bh)
	_hline(img, cx - 4, cx + 4, hy - 4, ol)
	# Hood sides (drape beside head, covers ears — shadow on lower portion)
	for dy in range(0, 8):
		_px(img, cx - 6, hy + dy, b if dy < 4 else bs)
		_px(img, cx - 7, hy + dy, ol)
		_px(img, cx + 6, hy + dy, b if dy < 4 else bs)
		_px(img, cx + 7, hy + dy, ol)
	# Gold trim accent line
	_hline(img, cx - 5, cx + 5, hy - 2, p["accent"])

func _draw_headgear_feathered_cap(img: Image, p: Dictionary, cx: int, hy: int) -> void:
	# Bard's tilted beret with red feather (accent color)
	var ol = p["outline"]
	var b = p["body"]; var bh = p["body_h"]
	var ac = p["accent"]  # red feather
	# Beret body (left-tilted, 2 rows — bh for top sheen)
	_hline(img, cx - 4, cx + 5, hy - 1, b)
	_hline(img, cx - 5, cx + 6, hy - 2, bh)
	_hline(img, cx - 5, cx + 6, hy - 3, ol)
	_px(img, cx - 4, hy - 1, ol); _px(img, cx + 5, hy - 1, ol)
	# Feather (top-right, pointing up-right)
	_px(img, cx + 5, hy - 4, ac)
	_px(img, cx + 6, hy - 5, ac)
	_px(img, cx + 7, hy - 6, ac)
	_px(img, cx + 6, hy - 6, ac.lightened(0.2))
	_px(img, cx + 8, hy - 7, ol)
	_px(img, cx + 7, hy - 7, ac)

func _draw_headgear_bandana(img: Image, p: Dictionary, cx: int, hy: int) -> void:
	# Rogue bandana: low brow wrap with a tail on one side
	var ol = p["outline"]
	var b = p["body"]; var bs = p["body_s"]
	# Brow band (2 rows: highlight row + shadow row below)
	_hline(img, cx - 5, cx + 5, hy + 2, b)
	_px(img, cx - 6, hy + 2, ol); _px(img, cx + 6, hy + 2, ol)
	_hline(img, cx - 5, cx + 5, hy + 1, bs)
	_px(img, cx - 6, hy + 1, ol); _px(img, cx + 6, hy + 1, ol)
	# Bandana tail on right (flap hangs down)
	_px(img, cx + 5, hy + 3, b)
	_px(img, cx + 6, hy + 4, b)
	_px(img, cx + 6, hy + 3, ol)
	_px(img, cx + 7, hy + 4, ol)


# ---- Job weapon/accessory overlays ----

func _draw_job_accessory_front(img: Image, p: Dictionary, _cx: int, _ty: int) -> void:
	# Per-job front accessory (badge, lute strings, etc.)
	match current_job:
		"fighter":
			# Tiny sword pommel peeking at hip-right (already covered by arms at sides)
			pass
		"cleric":
			# Holy cross emblem on chest
			_px(img, _cx, _ty + 2, p["accent"])
			_px(img, _cx - 1, _ty + 3, p["accent"])
			_px(img, _cx, _ty + 3, p["accent"])
			_px(img, _cx + 1, _ty + 3, p["accent"])
			_px(img, _cx, _ty + 4, p["accent"])
		"mage":
			# Staff crystal tip poking above shoulder (right side)
			_px(img, _cx + 7, _ty - 3, p["accent"])
			_px(img, _cx + 7, _ty - 4, p["accent"].lightened(0.3))
			_px(img, _cx + 8, _ty - 3, p["outline"])
		"rogue":
			# Two dagger hilts at belt (left and right)
			_px(img, _cx - 3, _ty + 7, p["accent"])
			_px(img, _cx - 4, _ty + 7, p["outline"])
			_px(img, _cx + 3, _ty + 7, p["accent"])
			_px(img, _cx + 4, _ty + 7, p["outline"])
		"bard":
			# Lute body outline on left arm area
			_px(img, _cx - 7, _ty + 3, p["accent"].darkened(0.1))
			_px(img, _cx - 7, _ty + 4, p["accent"].darkened(0.1))
			_px(img, _cx - 8, _ty + 4, p["outline"])


func _draw_job_accessory_back(img: Image, p: Dictionary, cx: int, ty: int) -> void:
	match current_job:
		"fighter":
			# Sword on back: blade running vertically
			var sx = cx + 3
			_px(img, sx, ty - 3, p["accent"])         # pommel
			_px(img, sx, ty - 2, p["outline"])         # crossguard shadow
			_px(img, sx - 1, ty - 2, p["outline"])
			_px(img, sx + 1, ty - 2, p["outline"])
			_vline(img, sx, ty - 1, ty + 5, Color(0.78, 0.80, 0.88))  # blade
			_px(img, sx, ty + 5, p["outline"])         # tip
		"cleric":
			# Staff on back (right of centre)
			var stx = cx + 4
			_vline(img, stx, ty - 3, ty + 5, Color(0.65, 0.55, 0.30))
			_px(img, stx - 1, ty - 3, p["accent"])
			_px(img, stx, ty - 4, p["accent"].lightened(0.2))
			_px(img, stx + 1, ty - 3, p["accent"])
		"mage":
			# Tall staff (left of centre)
			var stx = cx - 4
			_vline(img, stx, ty - 4, ty + 5, Color(0.40, 0.28, 0.50))
			# Crystal orb at top
			_px(img, stx - 1, ty - 4, p["accent"])
			_px(img, stx, ty - 5, p["accent"].lightened(0.3))
			_px(img, stx + 1, ty - 4, p["accent"])
			_px(img, stx, ty - 4, p["accent"].lightened(0.1))
		"rogue":
			# Crossed daggers on back
			for i in range(4):
				_px(img, cx - 2 + i, ty + i, Color(0.78, 0.78, 0.82))
				_px(img, cx + 2 - i, ty + i, Color(0.78, 0.78, 0.82))
			_px(img, cx - 2, ty - 1, p["accent"])
			_px(img, cx + 2, ty - 1, p["accent"])
		"bard":
			# Lute on back
			_px(img, cx, ty + 1, Color(0.65, 0.45, 0.20))
			_px(img, cx, ty + 2, Color(0.65, 0.45, 0.20))
			_px(img, cx - 1, ty + 2, Color(0.65, 0.45, 0.20))
			_px(img, cx + 1, ty + 2, Color(0.65, 0.45, 0.20))
			_px(img, cx, ty + 3, Color(0.72, 0.52, 0.25))
			_px(img, cx, ty, p["accent"].darkened(0.1))


func _draw_job_accessory_side(img: Image, p: Dictionary, cx: int, ty: int, face_right: bool) -> void:
	var fd = 1 if face_right else -1
	match current_job:
		"fighter":
			# Sword hilt visible at hip (face side)
			_px(img, cx + fd * 4, ty + 6, p["accent"])
			_px(img, cx + fd * 4, ty + 7, Color(0.78, 0.80, 0.88))
			_px(img, cx + fd * 5, ty + 6, p["outline"])
		"cleric":
			# Staff (behind character, back side)
			var stx = cx - fd * 5
			_vline(img, stx, ty - 2, ty + 5, Color(0.65, 0.55, 0.30))
			_px(img, stx, ty - 3, p["accent"].lightened(0.2))
		"mage":
			# Staff in front arm position
			var stx = cx + fd * 5
			_vline(img, stx, ty - 3, ty + 4, Color(0.40, 0.28, 0.50))
			_px(img, stx, ty - 4, p["accent"])
			_px(img, stx - fd, ty - 4, p["accent"].lightened(0.2))
		"rogue":
			# Single dagger at belt
			_px(img, cx + fd * 4, ty + 6, p["accent"])
			_px(img, cx + fd * 4, ty + 7, Color(0.78, 0.80, 0.84))
		"bard":
			# Lute neck visible behind
			var lx = cx - fd * 4
			_vline(img, lx, ty + 1, ty + 3, Color(0.65, 0.45, 0.20))


# ---- Top-level directional draw functions ----

func _draw_chibi_front(img: Image, p: Dictionary, phase: Dictionary) -> void:
	var bob = phase["bob"]         # 0 or 1 (body rises 1px mid-stride)
	var ll  = phase["ll"]          # left leg offset  (+= forward)
	var rl  = phase["rl"]          # right leg offset (+= forward)
	var la  = phase["la"]          # left arm swing   (+= forward/down)
	var ra  = phase["ra"]          # right arm swing

	var cx   = 16
	var feet = 30                  # feet row
	var oy   = bob                 # upward bob shifts entire character up

	# Ground shadow
	_draw_shadow(img, cx, feet + 1)

	# Layout rows (shifted up by bob)
	var head_top  = 2 - oy   # top of hair cap
	var torso_top = 15 - oy  # top of torso
	var leg_top   = 23 - oy  # top of legs

	# Headgear drawn BEFORE head (head will cover it where it overlaps)
	match current_job:
		"fighter":   _draw_headgear_helmet(img, p, cx, head_top)
		"cleric":    _draw_headgear_hood(img, p, cx, head_top)
		"mage":      _draw_headgear_pointed_hat(img, p, cx, head_top)
		"rogue":     _draw_headgear_bandana(img, p, cx, head_top)
		"bard":      _draw_headgear_feathered_cap(img, p, cx, head_top)
		"guardian":  _draw_headgear_helmet(img, p, cx, head_top)
		"ninja":     _draw_headgear_bandana(img, p, cx, head_top)
		_: pass  # Other jobs use default (no headgear on overworld)

	# Chibi head
	_draw_chibi_head(img, p, cx, head_top)

	# Torso
	_draw_chibi_torso_front(img, p, cx, torso_top)

	# Arms
	_draw_chibi_arms_front(img, p, cx, torso_top, la, ra)

	# Legs
	_draw_chibi_legs_front(img, p, cx, leg_top, ll, rl)

	# Job accessories
	_draw_job_accessory_front(img, p, cx, torso_top)


func _draw_chibi_back(img: Image, p: Dictionary, phase: Dictionary) -> void:
	var bob = phase["bob"]
	var ll  = phase["ll"]
	var rl  = phase["rl"]
	var la  = phase["la"]
	var ra  = phase["ra"]

	var cx   = 16
	var feet = 30
	var oy   = bob

	_draw_shadow(img, cx, feet + 1)

	var head_top  = 2 - oy
	var torso_top = 15 - oy
	var leg_top   = 23 - oy

	# Back view: job accessories drawn FIRST (behind body)
	_draw_job_accessory_back(img, p, cx, torso_top)

	# Back torso
	_draw_chibi_torso_back(img, p, cx, torso_top)

	# Back arms
	_draw_chibi_arms_back(img, p, cx, torso_top, la, ra)

	# Back legs
	_draw_chibi_legs_back(img, p, cx, leg_top, ll, rl)

	# Back head (hair dome, no face)
	_draw_chibi_head_back(img, p, cx, head_top)


func _draw_chibi_side(img: Image, p: Dictionary, phase: Dictionary, facing_left: bool) -> void:
	var bob = phase["bob"]
	# For side view, front_leg is the leg on the facing side (steps forward)
	var front_leg = phase["ll"] if facing_left else phase["rl"]
	var back_leg  = phase["rl"] if facing_left else phase["ll"]
	var front_arm = phase["la"] if facing_left else phase["ra"]
	var back_arm  = phase["ra"] if facing_left else phase["la"]
	var face_right = not facing_left  # sprite faces right when NOT facing_left

	var cx   = 16
	var feet = 30
	var oy   = bob

	_draw_shadow(img, cx, feet + 1)

	var head_top  = 2 - oy
	var torso_top = 15 - oy
	var leg_top   = 23 - oy

	# Side accessories drawn first (behind body)
	_draw_job_accessory_side(img, p, cx, torso_top, face_right)

	# Torso side
	_draw_chibi_torso_side(img, p, cx, torso_top, face_right)

	# Side arms
	_draw_chibi_arms_side(img, p, cx, torso_top, front_arm, back_arm, face_right)

	# Side legs
	_draw_chibi_legs_side(img, p, cx, leg_top, front_leg, back_leg, face_right)

	# Side head (profile with one visible eye)
	_draw_chibi_head_side(img, p, cx, head_top, face_right)

	# Side headgear (drawn on top of head)
	match current_job:
		"fighter":   _draw_headgear_helmet(img, p, cx, head_top)
		"cleric":    _draw_headgear_hood(img, p, cx, head_top)
		"mage":      _draw_headgear_pointed_hat(img, p, cx, head_top)
		"rogue":     _draw_headgear_bandana(img, p, cx, head_top)
		"bard":      _draw_headgear_feathered_cap(img, p, cx, head_top)
		"guardian":  _draw_headgear_helmet(img, p, cx, head_top)
		"ninja":     _draw_headgear_bandana(img, p, cx, head_top)
		_: pass


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


## Find an interactable (NPC, sign, chest, etc.) near the click position
func _find_clicked_interactable(click_pos: Vector2) -> Node2D:
	var interactables = get_tree().get_nodes_in_group("interactables")
	var closest: Node2D = null
	var closest_dist: float = 32.0  # Max click distance to count as clicking on an interactable
	for interactable in interactables:
		if interactable is Node2D and interactable.has_method("interact"):
			var dist = click_pos.distance_to(interactable.global_position)
			if dist < closest_dist:
				closest = interactable
				closest_dist = dist
	return closest
