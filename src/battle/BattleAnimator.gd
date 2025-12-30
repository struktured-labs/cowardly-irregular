extends Node
class_name BattleAnimator

## BattleAnimator - Handles sprite animations for combatants in battle
## 12-bit style battle animations (SNES/Genesis era aesthetic)

## Animation states for combatants
enum AnimState {
	IDLE,
	ATTACK,
	DEFEND,
	HIT,
	CAST,
	ITEM,
	VICTORY,
	DEFEAT,
	DEAD
}

## Animation speeds (frames per animation frame)
const ANIM_SPEED: Dictionary = {
	"idle": 0.3,
	"attack": 0.1,
	"defend": 0.2,
	"hit": 0.08,
	"cast": 0.15,
	"item": 0.12,
	"victory": 0.25,
	"defeat": 0.2
}

## Current animation state
var current_state: AnimState = AnimState.IDLE
var current_frame: int = 0
var frame_timer: float = 0.0
var is_playing: bool = false
var loop_animation: bool = true
var on_animation_complete: Callable

## Reference to the sprite node
var sprite: AnimatedSprite2D

## Animation callbacks
signal animation_started(state: AnimState)
signal animation_finished(state: AnimState)


func _init() -> void:
	"""Initialize the animator"""
	pass


func setup(animated_sprite: AnimatedSprite2D) -> void:
	"""Setup the animator with a sprite"""
	sprite = animated_sprite
	if sprite:
		sprite.animation_finished.connect(_on_sprite_animation_finished)


func play_animation(state: AnimState, loop: bool = false, on_complete: Callable = Callable()) -> void:
	"""Play an animation state"""
	if not sprite:
		push_warning("BattleAnimator: No sprite assigned!")
		return

	current_state = state
	loop_animation = loop
	on_animation_complete = on_complete
	is_playing = true
	current_frame = 0

	# Map state to animation name
	var anim_name = _get_animation_name(state)

	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_name):
		sprite.play(anim_name)
		animation_started.emit(state)
	else:
		push_warning("BattleAnimator: Animation '%s' not found!" % anim_name)
		is_playing = false


func stop_animation() -> void:
	"""Stop current animation"""
	if sprite:
		sprite.stop()
	is_playing = false


func set_idle() -> void:
	"""Set sprite to idle state"""
	play_animation(AnimState.IDLE, true)


func play_attack(on_complete: Callable = Callable()) -> void:
	"""Play attack animation"""
	play_animation(AnimState.ATTACK, false, on_complete)


func play_defend(on_complete: Callable = Callable()) -> void:
	"""Play defend animation"""
	play_animation(AnimState.DEFEND, false, on_complete)


func play_hit(on_complete: Callable = Callable()) -> void:
	"""Play hit/damage animation"""
	play_animation(AnimState.HIT, false, on_complete)


func play_cast(on_complete: Callable = Callable()) -> void:
	"""Play spell cast animation"""
	play_animation(AnimState.CAST, false, on_complete)


func play_item(on_complete: Callable = Callable()) -> void:
	"""Play item use animation"""
	play_animation(AnimState.ITEM, false, on_complete)


func play_victory(on_complete: Callable = Callable()) -> void:
	"""Play victory animation"""
	play_animation(AnimState.VICTORY, true, on_complete)


func play_defeat(on_complete: Callable = Callable()) -> void:
	"""Play defeat animation"""
	play_animation(AnimState.DEFEAT, false, on_complete)


func _get_animation_name(state: AnimState) -> String:
	"""Convert animation state to string name"""
	match state:
		AnimState.IDLE: return "idle"
		AnimState.ATTACK: return "attack"
		AnimState.DEFEND: return "defend"
		AnimState.HIT: return "hit"
		AnimState.CAST: return "cast"
		AnimState.ITEM: return "item"
		AnimState.VICTORY: return "victory"
		AnimState.DEFEAT: return "defeat"
		AnimState.DEAD: return "dead"
	return "idle"


func _on_sprite_animation_finished() -> void:
	"""Handle animation completion"""
	animation_finished.emit(current_state)

	# Call completion callback if set
	if on_animation_complete.is_valid():
		on_animation_complete.call()
		on_animation_complete = Callable()

	# Return to idle unless it's a looping animation
	if not loop_animation and current_state != AnimState.IDLE:
		set_idle()

	is_playing = false


## Helper functions for common animation sequences

func attack_sequence(target_sprite: AnimatedSprite2D, damage_callback: Callable) -> void:
	"""Complete attack sequence: attack -> target hit -> return to idle"""
	play_attack(func():
		if target_sprite:
			var target_animator = BattleAnimator.new()
			target_animator.setup(target_sprite)
			target_animator.play_hit(func():
				damage_callback.call()
			)
	)


func defend_sequence(on_complete: Callable = Callable()) -> void:
	"""Complete defend sequence"""
	play_defend(on_complete)


func cast_sequence(on_complete: Callable = Callable()) -> void:
	"""Complete spell cast sequence"""
	play_cast(on_complete)


## Procedural sprite frame generation for 12-bit style

static func create_hero_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for hero (12-bit style)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, slight bob)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 3.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_hero_frame(0, 0.0))  # Normal
	frames.add_frame("idle", _create_hero_frame(0, -1.0))  # Slight up

	# Attack animation (4 frames, swing sword)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 10.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_hero_frame(1, 0.0))  # Wind up
	frames.add_frame("attack", _create_hero_frame(2, 0.0))  # Mid swing
	frames.add_frame("attack", _create_hero_frame(3, 0.0))  # Full swing
	frames.add_frame("attack", _create_hero_frame(0, 0.0))  # Return

	# Defend animation (2 frames, shield up)
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 5.0)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_hero_frame(4, 0.0))  # Shield up
	frames.add_frame("defend", _create_hero_frame(4, 0.0))  # Hold

	# Hit animation (3 frames, recoil)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 12.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_hero_frame(5, 2.0))   # Recoil back
	frames.add_frame("hit", _create_hero_frame(5, 1.0))   # Mid recoil
	frames.add_frame("hit", _create_hero_frame(0, 0.0))   # Return to normal

	# Victory animation (2 frames, pose)
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 2.0)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_hero_frame(6, 0.0))  # Victory pose
	frames.add_frame("victory", _create_hero_frame(6, -1.0))  # Slight bob

	# Defeat animation (3 frames, collapse)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 5.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_hero_frame(7, 0.0))   # Stagger
	frames.add_frame("defeat", _create_hero_frame(7, 2.0))   # Falling
	frames.add_frame("defeat", _create_hero_frame(7, 4.0))   # Down

	return frames


static func _create_hero_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single hero sprite frame (12-bit style knight/fighter)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# 12-bit color palette (limited colors like SNES)
	var color_armor = Color(0.2, 0.4, 0.8)      # Blue armor
	var color_armor_dark = Color(0.1, 0.2, 0.5) # Dark blue
	var color_armor_light = Color(0.4, 0.6, 1.0) # Light blue
	var color_skin = Color(0.9, 0.7, 0.6)       # Skin tone
	var color_metal = Color(0.7, 0.7, 0.8)      # Metal/sword
	var color_metal_light = Color(0.9, 0.9, 1.0) # Highlight

	var center_x = size / 2
	var base_y = int(size * 0.75 + y_offset)

	match pose:
		0:  # Idle stance
			_draw_hero_body(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_light, color_skin)
			_draw_sword(img, center_x + 8, base_y - 8, 0, color_metal, color_metal_light)

		1:  # Wind up (sword back)
			_draw_hero_body(img, center_x, base_y, -5, color_armor, color_armor_dark, color_armor_light, color_skin)
			_draw_sword(img, center_x + 12, base_y - 12, -30, color_metal, color_metal_light)

		2:  # Mid swing
			_draw_hero_body(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_light, color_skin)
			_draw_sword(img, center_x - 8, base_y - 16, 45, color_metal, color_metal_light)

		3:  # Full swing (sword forward)
			_draw_hero_body(img, center_x, base_y, 5, color_armor, color_armor_dark, color_armor_light, color_skin)
			_draw_sword(img, center_x - 12, base_y - 8, 90, color_metal, color_metal_light)

		4:  # Defend (shield up)
			_draw_hero_body(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_light, color_skin)
			_draw_shield(img, center_x - 8, base_y - 12, color_metal, color_armor)

		5:  # Hit (recoiling)
			_draw_hero_body(img, center_x, base_y, -10, color_armor, color_armor_dark, color_armor_light, color_skin)

		6:  # Victory pose (sword raised)
			_draw_hero_body(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_light, color_skin)
			_draw_sword(img, center_x, base_y - 24, -45, color_metal, color_metal_light)

		7:  # Defeat (collapsed)
			_draw_hero_body(img, center_x, base_y + int(y_offset), 0, color_armor, color_armor_dark, color_armor_light, color_skin)

	return ImageTexture.create_from_image(img)


static func _draw_hero_body(img: Image, cx: int, cy: int, lean: int, armor: Color, armor_dark: Color, armor_light: Color, skin: Color) -> void:
	"""Draw hero body (knight/fighter)"""
	# Head (8x8)
	for y in range(-24 + lean/2, -16 + lean/2):
		for x in range(-4, 4):
			img.set_pixel(cx + x, cy + y, skin)

	# Helmet highlight
	for y in range(-24 + lean/2, -22 + lean/2):
		for x in range(-3, 3):
			img.set_pixel(cx + x, cy + y, armor_light)

	# Body (12x20)
	for y in range(-16, 4):
		for x in range(-6 + lean/4, 6 + lean/4):
			var color = armor
			# Add shading
			if x < -2:
				color = armor_dark
			elif x > 2:
				color = armor_light
			img.set_pixel(cx + x, cy + y, color)

	# Legs (2x 4x8)
	for y in range(4, 12):
		# Left leg
		for x in range(-5, -1):
			img.set_pixel(cx + x, cy + y, armor_dark)
		# Right leg
		for x in range(1, 5):
			img.set_pixel(cx + x, cy + y, armor_dark)


static func _draw_sword(img: Image, cx: int, cy: int, angle: int, metal: Color, metal_light: Color) -> void:
	"""Draw sword at given position and angle"""
	var length = 16
	var angle_rad = deg_to_rad(angle)

	# Draw sword blade
	for i in range(length):
		var x = int(cx + cos(angle_rad) * i)
		var y = int(cy + sin(angle_rad) * i)
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			var color = metal_light if i < 3 else metal
			img.set_pixel(x, y, color)
			# Make sword 2 pixels wide
			if y + 1 < img.get_height():
				img.set_pixel(x, y + 1, color)


static func _draw_shield(img: Image, cx: int, cy: int, metal: Color, accent: Color) -> void:
	"""Draw shield"""
	# Shield (8x12)
	for y in range(-6, 6):
		for x in range(-4, 4):
			var color = accent if abs(x) < 2 else metal
			img.set_pixel(cx + x, cy + y, color)


static func create_slime_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for slime enemy (12-bit style)"""
	var frames = SpriteFrames.new()

	# Idle animation (4 frames, bouncy blob)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 4.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_slime_frame(0, 0.0, 1.0))    # Normal
	frames.add_frame("idle", _create_slime_frame(0, -2.0, 1.05))  # Stretch up
	frames.add_frame("idle", _create_slime_frame(0, 0.0, 1.0))    # Normal
	frames.add_frame("idle", _create_slime_frame(0, 1.0, 0.95))   # Squish down

	# Attack animation (3 frames, lunge forward)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 8.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_slime_frame(1, 0.0, 1.0))   # Wind up (squish)
	frames.add_frame("attack", _create_slime_frame(2, -4.0, 1.2))  # Lunge (stretch)
	frames.add_frame("attack", _create_slime_frame(0, 0.0, 1.0))   # Return

	# Hit animation (2 frames, wobble)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 10.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_slime_frame(3, 0.0, 0.9))   # Squish
	frames.add_frame("hit", _create_slime_frame(0, 0.0, 1.0))   # Return

	# Defeat animation (4 frames, melt)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 4.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_slime_frame(0, 0.0, 1.0))   # Normal
	frames.add_frame("defeat", _create_slime_frame(4, 2.0, 0.8))   # Deflate
	frames.add_frame("defeat", _create_slime_frame(4, 4.0, 0.5))   # Melt
	frames.add_frame("defeat", _create_slime_frame(4, 6.0, 0.2))   # Puddle

	return frames


static func _create_slime_frame(pose: int, y_offset: float, scale_y: float) -> ImageTexture:
	"""Create a single slime sprite frame (12-bit style blob)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# 12-bit color palette for slime
	var color_slime = Color(0.3, 0.8, 0.3)       # Green slime
	var color_slime_dark = Color(0.2, 0.5, 0.2)  # Dark green
	var color_slime_light = Color(0.5, 1.0, 0.5) # Light green (highlight)
	var color_core = Color(0.2, 0.6, 0.9)        # Blue core

	var center_x = size / 2
	var base_y = int(size * 0.65 + y_offset)
	var radius = 18

	# Draw slime blob (ellipse)
	for y in range(-int(radius * scale_y), int(radius * scale_y)):
		for x in range(-radius, radius):
			var dist = sqrt(pow(x, 2) / pow(radius, 2) + pow(y, 2) / pow(radius * scale_y, 2))
			if dist < 1.0:
				var px = center_x + x
				var py = base_y + y

				if px >= 0 and px < size and py >= 0 and py < size:
					# Color based on position (gradient shading)
					var color = color_slime
					if y < -radius * scale_y * 0.3:
						color = color_slime_light  # Top highlight
					elif y > radius * scale_y * 0.3:
						color = color_slime_dark   # Bottom shadow

					img.set_pixel(px, py, color)

	# Draw eyes (simple dots)
	var eye_y = base_y - int(6 * scale_y)
	if pose != 4:  # No eyes when melting
		# Left eye
		img.set_pixel(center_x - 6, eye_y, Color.BLACK)
		img.set_pixel(center_x - 6, eye_y - 1, Color.BLACK)
		# Right eye
		img.set_pixel(center_x + 6, eye_y, Color.BLACK)
		img.set_pixel(center_x + 6, eye_y - 1, Color.BLACK)

		# Eye highlights (12-bit style)
		img.set_pixel(center_x - 7, eye_y - 1, Color.WHITE)
		img.set_pixel(center_x + 5, eye_y - 1, Color.WHITE)

	# Add slime highlight/shine
	if pose != 4:
		var shine_y = base_y - int(12 * scale_y)
		for sy in range(-3, 0):
			for sx in range(-2, 3):
				var px = center_x + sx - 4
				var py = shine_y + sy
				if px >= 0 and px < size and py >= 0 and py < size:
					img.set_pixel(px, py, color_slime_light)

	return ImageTexture.create_from_image(img)
