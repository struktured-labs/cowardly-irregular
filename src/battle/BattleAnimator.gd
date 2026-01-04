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

## Animation speeds (frames per animation frame) - slower for visibility
const ANIM_SPEED: Dictionary = {
	"idle": 0.4,
	"attack": 0.25,
	"defend": 0.35,
	"hit": 0.2,
	"cast": 0.3,
	"item": 0.25,
	"victory": 0.35,
	"defeat": 0.3
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


func play_backstab(on_complete: Callable = Callable()) -> void:
	"""Quick diagonal lunge attack animation"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	# Store original position
	var original_pos = sprite.position

	# Quick diagonal dash forward-left
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(sprite, "position", original_pos + Vector2(-30, -15), 0.1)

	# Play attack animation during the lunge
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
			sprite.play("attack")
	)

	# Hold at strike position briefly
	tween.tween_interval(0.15)

	# Return to original position
	tween.tween_property(sprite, "position", original_pos, 0.15)

	# Return to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


func play_steal(on_complete: Callable = Callable()) -> void:
	"""Quick dash in and out animation for stealing"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	var original_pos = sprite.position

	# Play attack animation
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")

	# Quick dash forward
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(sprite, "position", original_pos + Vector2(-50, 0), 0.12)

	# Flash (invisible briefly = "grab")
	tween.tween_property(sprite, "modulate:a", 0.5, 0.05)
	tween.tween_property(sprite, "modulate:a", 1.0, 0.05)

	# Quick dash back
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(sprite, "position", original_pos, 0.15)

	# Return to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


func play_skill(on_complete: Callable = Callable()) -> void:
	"""Generic physical skill animation with pose hold"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	var original_pos = sprite.position

	# Play attack animation with a slight forward lean
	var tween = create_tween()

	# Prep pose - lean back
	tween.tween_property(sprite, "position", original_pos + Vector2(10, 0), 0.1)

	# Execute - quick forward lunge
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
			sprite.play("attack")
	)
	tween.tween_property(sprite, "position", original_pos + Vector2(-25, 0), 0.08)

	# Brief pause at impact
	tween.tween_interval(0.1)

	# Return
	tween.tween_property(sprite, "position", original_pos, 0.12)

	# Back to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


func play_mug(on_complete: Callable = Callable()) -> void:
	"""Combination attack + steal animation"""
	if not sprite:
		if on_complete.is_valid():
			on_complete.call()
		return

	var original_pos = sprite.position

	# Play attack animation
	if sprite.sprite_frames and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")

	# Aggressive dash forward with spin effect
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_EXPO)
	tween.tween_property(sprite, "position", original_pos + Vector2(-45, 0), 0.1)
	tween.parallel().tween_property(sprite, "rotation", 0.3, 0.1)

	# Strike and grab
	tween.tween_interval(0.08)
	tween.tween_property(sprite, "modulate", Color(1.2, 1.0, 0.8), 0.05)  # Flash gold
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.05)

	# Return with spin
	tween.tween_property(sprite, "position", original_pos, 0.15)
	tween.parallel().tween_property(sprite, "rotation", 0.0, 0.15)

	# Back to idle
	tween.tween_callback(func():
		if sprite and sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
			sprite.play("idle")
		if on_complete.is_valid():
			on_complete.call()
	)


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
			var target_animator = get_script().new()
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
	frames.set_animation_speed("idle", 2.0)  # Slower idle
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_hero_frame(0, 0.0))  # Normal
	frames.add_frame("idle", _create_hero_frame(0, -1.0))  # Slight up

	# Attack animation (4 frames, swing sword) - SLOWER for visibility
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)  # Much slower
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_hero_frame(1, 0.0))  # Wind up
	frames.add_frame("attack", _create_hero_frame(2, 0.0))  # Mid swing
	frames.add_frame("attack", _create_hero_frame(3, 0.0))  # Full swing
	frames.add_frame("attack", _create_hero_frame(0, 0.0))  # Return

	# Defend animation (2 frames, shield up)
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 3.0)  # Slower
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_hero_frame(4, 0.0))  # Shield up
	frames.add_frame("defend", _create_hero_frame(4, 0.0))  # Hold

	# Hit animation (3 frames, recoil) - SLOWER for visibility
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)  # Much slower
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_hero_frame(5, 2.0))   # Recoil back
	frames.add_frame("hit", _create_hero_frame(5, 1.0))   # Mid recoil
	frames.add_frame("hit", _create_hero_frame(0, 0.0))   # Return to normal

	# Victory animation (2 frames, pose)
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)  # Slower
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_hero_frame(6, 0.0))  # Victory pose
	frames.add_frame("victory", _create_hero_frame(6, -1.0))  # Slight bob

	# Defeat animation (3 frames, collapse) - SLOWER for visibility
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 3.0)  # Slower
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
	var w = img.get_width()
	var h = img.get_height()

	# Head (8x8)
	for y in range(-24 + lean/2, -16 + lean/2):
		for x in range(-4, 4):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < w and py >= 0 and py < h:
				img.set_pixel(px, py, skin)

	# Helmet highlight
	for y in range(-24 + lean/2, -22 + lean/2):
		for x in range(-3, 3):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < w and py >= 0 and py < h:
				img.set_pixel(px, py, armor_light)

	# Body (12x20)
	for y in range(-16, 4):
		for x in range(-6 + lean/4, 6 + lean/4):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < w and py >= 0 and py < h:
				var color = armor
				# Add shading
				if x < -2:
					color = armor_dark
				elif x > 2:
					color = armor_light
				img.set_pixel(px, py, color)

	# Legs (2x 4x8)
	for y in range(4, 12):
		# Left leg
		for x in range(-5, -1):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < w and py >= 0 and py < h:
				img.set_pixel(px, py, armor_dark)
		# Right leg
		for x in range(1, 5):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < w and py >= 0 and py < h:
				img.set_pixel(px, py, armor_dark)


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
	var w = img.get_width()
	var h = img.get_height()
	# Shield (8x12)
	for y in range(-6, 6):
		for x in range(-4, 4):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < w and py >= 0 and py < h:
				var color = accent if abs(x) < 2 else metal
				img.set_pixel(px, py, color)


static func create_slime_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for slime enemy (12-bit style)"""
	var frames = SpriteFrames.new()

	# Idle animation (4 frames, bouncy blob)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.5)  # Slower
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_slime_frame(0, 0.0, 1.0))    # Normal
	frames.add_frame("idle", _create_slime_frame(0, -2.0, 1.05))  # Stretch up
	frames.add_frame("idle", _create_slime_frame(0, 0.0, 1.0))    # Normal
	frames.add_frame("idle", _create_slime_frame(0, 1.0, 0.95))   # Squish down

	# Attack animation (3 frames, lunge forward) - SLOWER
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)  # Much slower
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_slime_frame(1, 0.0, 1.0))   # Wind up (squish)
	frames.add_frame("attack", _create_slime_frame(2, -4.0, 1.2))  # Lunge (stretch)
	frames.add_frame("attack", _create_slime_frame(0, 0.0, 1.0))   # Return

	# Hit animation (2 frames, wobble) - SLOWER
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)  # Much slower
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_slime_frame(3, 0.0, 0.9))   # Squish
	frames.add_frame("hit", _create_slime_frame(0, 0.0, 1.0))   # Return

	# Defeat animation (4 frames, melt) - SLOWER
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)  # Slower
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
		# Helper function for bounds-checked set_pixel
		var w = size
		var h = size
		# Left eye
		if center_x - 6 >= 0 and center_x - 6 < w and eye_y >= 0 and eye_y < h:
			img.set_pixel(center_x - 6, eye_y, Color.BLACK)
		if center_x - 6 >= 0 and center_x - 6 < w and eye_y - 1 >= 0 and eye_y - 1 < h:
			img.set_pixel(center_x - 6, eye_y - 1, Color.BLACK)
		# Right eye
		if center_x + 6 >= 0 and center_x + 6 < w and eye_y >= 0 and eye_y < h:
			img.set_pixel(center_x + 6, eye_y, Color.BLACK)
		if center_x + 6 >= 0 and center_x + 6 < w and eye_y - 1 >= 0 and eye_y - 1 < h:
			img.set_pixel(center_x + 6, eye_y - 1, Color.BLACK)

		# Eye highlights (12-bit style)
		if center_x - 7 >= 0 and center_x - 7 < w and eye_y - 1 >= 0 and eye_y - 1 < h:
			img.set_pixel(center_x - 7, eye_y - 1, Color.WHITE)
		if center_x + 5 >= 0 and center_x + 5 < w and eye_y - 1 >= 0 and eye_y - 1 < h:
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


static func create_mage_sprite_frames(robe_color: Color = Color(0.9, 0.9, 1.0)) -> SpriteFrames:
	"""Create animated sprite frames for mage character (12-bit style)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, slight bob) - SLOWER
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_mage_frame(0, 0.0, robe_color))
	frames.add_frame("idle", _create_mage_frame(0, -1.0, robe_color))

	# Attack animation (staff thrust) - MUCH SLOWER
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_mage_frame(1, 0.0, robe_color))
	frames.add_frame("attack", _create_mage_frame(2, 0.0, robe_color))
	frames.add_frame("attack", _create_mage_frame(0, 0.0, robe_color))

	# Defend animation - SLOWER
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 2.5)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_mage_frame(3, 0.0, robe_color))
	frames.add_frame("defend", _create_mage_frame(3, 0.0, robe_color))

	# Hit animation - MUCH SLOWER
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_mage_frame(4, 2.0, robe_color))
	frames.add_frame("hit", _create_mage_frame(4, 1.0, robe_color))
	frames.add_frame("hit", _create_mage_frame(0, 0.0, robe_color))

	# Cast animation (magic) - SLOWER for dramatic effect
	frames.add_animation("cast")
	frames.set_animation_speed("cast", 2.5)
	frames.set_animation_loop("cast", false)
	frames.add_frame("cast", _create_mage_frame(5, 0.0, robe_color))
	frames.add_frame("cast", _create_mage_frame(6, -2.0, robe_color))
	frames.add_frame("cast", _create_mage_frame(5, 0.0, robe_color))
	frames.add_frame("cast", _create_mage_frame(0, 0.0, robe_color))

	# Item animation - SLOWER
	frames.add_animation("item")
	frames.set_animation_speed("item", 3.0)
	frames.set_animation_loop("item", false)
	frames.add_frame("item", _create_mage_frame(1, 0.0, robe_color))
	frames.add_frame("item", _create_mage_frame(0, 0.0, robe_color))

	# Victory animation - SLOWER
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_mage_frame(7, 0.0, robe_color))
	frames.add_frame("victory", _create_mage_frame(7, -1.0, robe_color))

	# Defeat animation - SLOWER
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_mage_frame(4, 0.0, robe_color))
	frames.add_frame("defeat", _create_mage_frame(4, 2.0, robe_color))
	frames.add_frame("defeat", _create_mage_frame(4, 4.0, robe_color))

	return frames


static func _create_mage_frame(pose: int, y_offset: float, robe_color: Color) -> ImageTexture:
	"""Create a single mage sprite frame (12-bit style robed figure)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette
	var color_robe = robe_color
	var color_robe_dark = robe_color.darkened(0.3)
	var color_robe_light = robe_color.lightened(0.2)
	var color_skin = Color(0.9, 0.7, 0.6)
	var color_staff = Color(0.5, 0.3, 0.2)  # Brown wood
	var color_gem = Color(0.3, 0.8, 1.0)    # Cyan gem

	var center_x = size / 2
	var base_y = int(size * 0.75 + y_offset)

	match pose:
		0:  # Idle stance
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 10, base_y - 10, 0, color_staff, color_gem)

		1:  # Staff forward
			_draw_mage_body(img, center_x, base_y, 5, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 6, base_y - 14, 20, color_staff, color_gem)

		2:  # Staff thrust
			_draw_mage_body(img, center_x, base_y, 10, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x - 4, base_y - 16, 60, color_staff, color_gem)

		3:  # Defend (staff across)
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x, base_y - 12, 90, color_staff, color_gem)

		4:  # Hit (recoil)
			_draw_mage_body(img, center_x, base_y, -10, color_robe, color_robe_dark, color_robe_light, color_skin)

		5:  # Cast prep (staff raised)
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 8, base_y - 20, -20, color_staff, color_gem)

		6:  # Cast release (staff glowing)
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 8, base_y - 20, -20, color_staff, Color.WHITE)
			# Add magic glow effect
			_draw_magic_glow(img, center_x, base_y - 30, color_gem)

		7:  # Victory pose
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x, base_y - 28, -45, color_staff, color_gem)

	return ImageTexture.create_from_image(img)


static func _draw_mage_body(img: Image, cx: int, cy: int, lean: int, robe: Color, robe_dark: Color, robe_light: Color, skin: Color) -> void:
	"""Draw mage body (robed figure with hood)"""
	var size = img.get_width()

	# Hood/Head (10x10)
	for y in range(-26 + lean/2, -16 + lean/2):
		for x in range(-5, 5):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				var color = robe
				if y > -20 + lean/2:
					color = skin  # Face visible under hood
				elif x < -2:
					color = robe_dark
				img.set_pixel(px, py, color)

	# Hood point
	for y in range(-30 + lean/2, -26 + lean/2):
		for x in range(-2, 2):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, robe)

	# Robe body (wider at bottom, triangular)
	for y in range(-16, 8):
		var width = 6 + int(y / 2.5)
		for x in range(-width + lean/4, width + lean/4):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				var color = robe
				if x < -width + 3:
					color = robe_dark
				elif x > width - 3:
					color = robe_light
				img.set_pixel(px, py, color)

	# Robe hem
	for y in range(8, 12):
		var width = 12
		for x in range(-width, width):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, robe_dark)


static func _draw_staff(img: Image, cx: int, cy: int, angle: int, wood: Color, gem: Color) -> void:
	"""Draw staff with gem"""
	var length = 24
	var angle_rad = deg_to_rad(angle)

	# Draw staff shaft
	for i in range(length):
		var x = int(cx + cos(angle_rad) * i)
		var y = int(cy + sin(angle_rad) * i)
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, wood)

	# Draw gem at top
	var gem_x = int(cx + cos(angle_rad) * (length - 2))
	var gem_y = int(cy + sin(angle_rad) * (length - 2))
	for gy in range(-2, 3):
		for gx in range(-2, 3):
			var px = gem_x + gx
			var py = gem_y + gy
			if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
				if abs(gx) + abs(gy) < 4:
					img.set_pixel(px, py, gem)


static func _draw_magic_glow(img: Image, cx: int, cy: int, glow_color: Color) -> void:
	"""Draw magic glow effect"""
	for gy in range(-4, 5):
		for gx in range(-4, 5):
			var dist = sqrt(gx * gx + gy * gy)
			if dist < 4:
				var px = cx + gx
				var py = cy + gy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					var alpha = 1.0 - (dist / 4.0)
					var color = glow_color
					color.a = alpha * 0.7
					# Blend with existing pixel
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
						img.set_pixel(px, py, existing.blend(color))
					else:
						img.set_pixel(px, py, color)


static func create_thief_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for thief character (12-bit style)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, slight bob) - SLOWER
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_thief_frame(0, 0.0))
	frames.add_frame("idle", _create_thief_frame(0, -1.0))

	# Attack animation (quick slash) - SLOWER but still quick for thief
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_thief_frame(1, 0.0))
	frames.add_frame("attack", _create_thief_frame(2, -2.0))
	frames.add_frame("attack", _create_thief_frame(3, 0.0))
	frames.add_frame("attack", _create_thief_frame(0, 0.0))

	# Defend animation - SLOWER
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 2.5)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_thief_frame(4, 0.0))
	frames.add_frame("defend", _create_thief_frame(4, 0.0))

	# Hit animation - SLOWER
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_thief_frame(5, 2.0))
	frames.add_frame("hit", _create_thief_frame(5, 1.0))
	frames.add_frame("hit", _create_thief_frame(0, 0.0))

	# Cast animation (use item/throw) - SLOWER
	frames.add_animation("cast")
	frames.set_animation_speed("cast", 3.0)
	frames.set_animation_loop("cast", false)
	frames.add_frame("cast", _create_thief_frame(6, 0.0))
	frames.add_frame("cast", _create_thief_frame(6, -1.0))
	frames.add_frame("cast", _create_thief_frame(0, 0.0))

	# Item animation - SLOWER
	frames.add_animation("item")
	frames.set_animation_speed("item", 3.0)
	frames.set_animation_loop("item", false)
	frames.add_frame("item", _create_thief_frame(6, 0.0))
	frames.add_frame("item", _create_thief_frame(0, 0.0))

	# Victory animation - SLOWER
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_thief_frame(7, 0.0))
	frames.add_frame("victory", _create_thief_frame(7, -1.0))

	# Defeat animation - SLOWER
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_thief_frame(5, 0.0))
	frames.add_frame("defeat", _create_thief_frame(5, 2.0))
	frames.add_frame("defeat", _create_thief_frame(5, 4.0))

	return frames


static func _create_thief_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single thief sprite frame (12-bit style nimble rogue)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for thief
	var color_cloak = Color(0.3, 0.25, 0.4)      # Dark purple cloak
	var color_cloak_dark = Color(0.2, 0.15, 0.3)
	var color_cloak_light = Color(0.4, 0.35, 0.5)
	var color_skin = Color(0.9, 0.7, 0.6)
	var color_dagger = Color(0.8, 0.8, 0.9)      # Silver dagger
	var color_dagger_light = Color(1.0, 1.0, 1.0)

	var center_x = size / 2
	var base_y = int(size * 0.75 + y_offset)

	match pose:
		0:  # Idle stance
			_draw_thief_body(img, center_x, base_y, 0, color_cloak, color_cloak_dark, color_cloak_light, color_skin)
			_draw_dagger(img, center_x + 8, base_y - 6, 0, color_dagger, color_dagger_light)

		1:  # Wind up (crouch)
			_draw_thief_body(img, center_x, base_y + 2, -5, color_cloak, color_cloak_dark, color_cloak_light, color_skin)
			_draw_dagger(img, center_x + 10, base_y - 4, -20, color_dagger, color_dagger_light)

		2:  # Dash attack
			_draw_thief_body(img, center_x - 6, base_y, 15, color_cloak, color_cloak_dark, color_cloak_light, color_skin)
			_draw_dagger(img, center_x - 12, base_y - 8, 60, color_dagger, color_dagger_light)

		3:  # Recovery
			_draw_thief_body(img, center_x, base_y, 5, color_cloak, color_cloak_dark, color_cloak_light, color_skin)
			_draw_dagger(img, center_x + 6, base_y - 6, 30, color_dagger, color_dagger_light)

		4:  # Defend (dodge stance)
			_draw_thief_body(img, center_x + 4, base_y, -10, color_cloak, color_cloak_dark, color_cloak_light, color_skin)
			_draw_dagger(img, center_x + 10, base_y - 8, -30, color_dagger, color_dagger_light)

		5:  # Hit (recoil)
			_draw_thief_body(img, center_x, base_y, -15, color_cloak, color_cloak_dark, color_cloak_light, color_skin)

		6:  # Throw/item
			_draw_thief_body(img, center_x, base_y, 10, color_cloak, color_cloak_dark, color_cloak_light, color_skin)
			_draw_dagger(img, center_x - 8, base_y - 16, 45, color_dagger, color_dagger_light)

		7:  # Victory pose
			_draw_thief_body(img, center_x, base_y, 0, color_cloak, color_cloak_dark, color_cloak_light, color_skin)
			_draw_dagger(img, center_x + 4, base_y - 18, -60, color_dagger, color_dagger_light)

	return ImageTexture.create_from_image(img)


static func _draw_thief_body(img: Image, cx: int, cy: int, lean: int, cloak: Color, cloak_dark: Color, cloak_light: Color, skin: Color) -> void:
	"""Draw thief body (slim, cloaked figure)"""
	var size = img.get_width()

	# Head (smaller than hero)
	for y in range(-22 + lean/3, -14 + lean/3):
		for x in range(-3, 3):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, skin)

	# Hood/hair
	for y in range(-24 + lean/3, -20 + lean/3):
		for x in range(-4, 4):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, cloak_dark)

	# Body (slim, cloaked)
	for y in range(-14, 4):
		var width = 4 + int(y / 4)
		for x in range(-width + lean/5, width + lean/5):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				var color = cloak
				if x < -width + 2:
					color = cloak_dark
				elif x > width - 2:
					color = cloak_light
				img.set_pixel(px, py, color)

	# Legs (slim)
	for y in range(4, 10):
		# Left leg
		for x in range(-4, -1):
			var px = cx + x + lean/6
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, cloak_dark)
		# Right leg
		for x in range(1, 4):
			var px = cx + x + lean/6
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, cloak_dark)


static func _draw_dagger(img: Image, cx: int, cy: int, angle: int, blade: Color, blade_light: Color) -> void:
	"""Draw dagger at given position and angle"""
	var length = 12
	var angle_rad = deg_to_rad(angle)

	# Draw dagger blade (thinner than sword)
	for i in range(length):
		var x = int(cx + cos(angle_rad) * i)
		var y = int(cy + sin(angle_rad) * i)
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			var color = blade_light if i < 2 else blade
			img.set_pixel(x, y, color)


## =================
## MONSTER SPRITES
## =================

static func create_skeleton_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for skeleton enemy (12-bit style)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, slight sway)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_skeleton_frame(0, 0.0))
	frames.add_frame("idle", _create_skeleton_frame(0, -1.0))

	# Attack animation (4 frames, sword slash)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_skeleton_frame(1, 0.0))  # Wind up
	frames.add_frame("attack", _create_skeleton_frame(2, -2.0))  # Lunge
	frames.add_frame("attack", _create_skeleton_frame(3, 0.0))  # Slash
	frames.add_frame("attack", _create_skeleton_frame(0, 0.0))  # Return

	# Hit animation (3 frames, rattle)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_skeleton_frame(4, 2.0))
	frames.add_frame("hit", _create_skeleton_frame(4, -2.0))
	frames.add_frame("hit", _create_skeleton_frame(0, 0.0))

	# Defeat animation (4 frames, collapse into bones)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_skeleton_frame(5, 0.0))
	frames.add_frame("defeat", _create_skeleton_frame(5, 2.0))
	frames.add_frame("defeat", _create_skeleton_frame(6, 4.0))
	frames.add_frame("defeat", _create_skeleton_frame(7, 6.0))  # Bone pile

	return frames


static func _create_skeleton_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single skeleton sprite frame (12-bit style bones)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# 12-bit color palette for skeleton
	var color_bone = Color(0.9, 0.88, 0.8)       # Off-white bone
	var color_bone_dark = Color(0.6, 0.55, 0.5)  # Shadow
	var color_bone_light = Color(1.0, 0.98, 0.95) # Highlight
	var color_eye = Color(0.8, 0.2, 0.2)         # Red eyes

	var center_x = size / 2
	var base_y = int(size * 0.75 + y_offset)

	match pose:
		0:  # Idle
			_draw_skeleton_body(img, center_x, base_y, 0, color_bone, color_bone_dark, color_bone_light, color_eye)
			_draw_bone_sword(img, center_x + 10, base_y - 8, 10, color_bone, color_bone_light)

		1:  # Wind up
			_draw_skeleton_body(img, center_x, base_y, -5, color_bone, color_bone_dark, color_bone_light, color_eye)
			_draw_bone_sword(img, center_x + 14, base_y - 12, -20, color_bone, color_bone_light)

		2:  # Lunge
			_draw_skeleton_body(img, center_x - 4, base_y, 10, color_bone, color_bone_dark, color_bone_light, color_eye)
			_draw_bone_sword(img, center_x - 10, base_y - 10, 45, color_bone, color_bone_light)

		3:  # Slash
			_draw_skeleton_body(img, center_x, base_y, 5, color_bone, color_bone_dark, color_bone_light, color_eye)
			_draw_bone_sword(img, center_x - 8, base_y - 4, 80, color_bone, color_bone_light)

		4:  # Hit (rattling)
			_draw_skeleton_body(img, center_x, base_y, -8, color_bone, color_bone_dark, color_bone_light, color_eye)

		5:  # Defeat start
			_draw_skeleton_body(img, center_x, base_y, -15, color_bone, color_bone_dark, color_bone_light, color_eye)

		6:  # Collapsing
			_draw_scattered_bones(img, center_x, base_y + 4, 0.5, color_bone, color_bone_dark)

		7:  # Bone pile
			_draw_scattered_bones(img, center_x, base_y + 8, 1.0, color_bone, color_bone_dark)

	return ImageTexture.create_from_image(img)


static func _draw_skeleton_body(img: Image, cx: int, cy: int, lean: int, bone: Color, bone_dark: Color, bone_light: Color, eye: Color) -> void:
	"""Draw skeleton body (bones structure)"""
	var size = img.get_width()

	# Skull (10x10 rounded square)
	for y in range(-24 + lean/3, -14 + lean/3):
		for x in range(-5, 5):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				var dist = abs(x) + abs(y + 19 - lean/3)
				if dist < 8:
					var color = bone
					if y < -21 + lean/3:
						color = bone_light
					elif y > -17 + lean/3:
						color = bone_dark
					img.set_pixel(px, py, color)

	# Eye sockets
	for ex in [-3, 3]:
		var eye_x = cx + ex
		var eye_y = cy - 19 + lean/3
		if eye_x >= 0 and eye_x < size and eye_y >= 0 and eye_y < size:
			img.set_pixel(eye_x, eye_y, eye)
			if eye_x + 1 < size:
				img.set_pixel(eye_x + 1, eye_y, eye)

	# Spine (vertical bones)
	for y in range(-14, 4):
		var px = cx + lean/8
		var py = cy + y
		if px >= 0 and px < size and py >= 0 and py < size:
			img.set_pixel(px, py, bone)
			if px + 1 < size:
				img.set_pixel(px + 1, py, bone_dark)

	# Ribcage
	for rib in range(4):
		var rib_y = cy - 12 + rib * 3
		for x in range(-4, 5):
			var px = cx + x + lean/6
			if px >= 0 and px < size and rib_y >= 0 and rib_y < size:
				if abs(x) > 0:
					img.set_pixel(px, rib_y, bone if x < 0 else bone_dark)

	# Pelvis
	for y in range(4, 8):
		for x in range(-4, 5):
			var px = cx + x + lean/8
			var py = cy + y
			if px >= 0 and px < size and py >= 0 and py < size:
				if abs(x) + (y - 4) < 6:
					img.set_pixel(px, py, bone_dark)

	# Leg bones
	for y in range(8, 16):
		# Left leg
		var left_px = cx - 3 + lean/10
		if left_px >= 0 and left_px < size and cy + y >= 0 and cy + y < size:
			img.set_pixel(left_px, cy + y, bone)
		# Right leg
		var right_px = cx + 3 + lean/10
		if right_px >= 0 and right_px < size and cy + y >= 0 and cy + y < size:
			img.set_pixel(right_px, cy + y, bone)


static func _draw_bone_sword(img: Image, cx: int, cy: int, angle: int, bone: Color, bone_light: Color) -> void:
	"""Draw bone sword weapon"""
	var length = 18
	var angle_rad = deg_to_rad(angle)

	for i in range(length):
		var x = int(cx + cos(angle_rad) * i)
		var y = int(cy + sin(angle_rad) * i)
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			var color = bone_light if i < 3 else bone
			img.set_pixel(x, y, color)
			if y + 1 < img.get_height():
				img.set_pixel(x, y + 1, color)


static func _draw_scattered_bones(img: Image, cx: int, cy: int, scatter: float, bone: Color, bone_dark: Color) -> void:
	"""Draw scattered bone pile"""
	var size = img.get_width()
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345  # Fixed seed for consistent look

	# Draw random bone pieces
	for i in range(12):
		var x = cx + int((rng.randf() - 0.5) * 24 * scatter)
		var y = cy + int(rng.randf() * 8 * scatter)
		var length = rng.randi_range(3, 8)
		var angle = rng.randf() * PI

		for j in range(length):
			var px = x + int(cos(angle) * j)
			var py = y + int(sin(angle) * j)
			if px >= 0 and px < size and py >= 0 and py < size:
				img.set_pixel(px, py, bone if j < length/2 else bone_dark)


static func create_specter_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for specter/ghost enemy (12-bit style)"""
	var frames = SpriteFrames.new()

	# Idle animation (4 frames, floating bob with shimmer)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_specter_frame(0, 0.0, 1.0))
	frames.add_frame("idle", _create_specter_frame(0, -3.0, 1.0))
	frames.add_frame("idle", _create_specter_frame(0, -4.0, 0.95))
	frames.add_frame("idle", _create_specter_frame(0, -2.0, 1.0))

	# Attack animation (4 frames, phase through)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.5)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_specter_frame(1, 0.0, 1.0))   # Coalesce
	frames.add_frame("attack", _create_specter_frame(2, -4.0, 0.8))  # Phase forward
	frames.add_frame("attack", _create_specter_frame(3, -2.0, 1.2))  # Strike
	frames.add_frame("attack", _create_specter_frame(0, 0.0, 1.0))   # Return

	# Hit animation (3 frames, flicker)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_specter_frame(4, 0.0, 0.6))   # Flicker out
	frames.add_frame("hit", _create_specter_frame(4, 0.0, 1.0))   # Flicker in
	frames.add_frame("hit", _create_specter_frame(0, 0.0, 1.0))   # Return

	# Defeat animation (4 frames, dissipate)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_specter_frame(5, 0.0, 1.0))   # Swirl
	frames.add_frame("defeat", _create_specter_frame(5, -2.0, 0.7))  # Fade
	frames.add_frame("defeat", _create_specter_frame(5, -4.0, 0.4))  # Dissolve
	frames.add_frame("defeat", _create_specter_frame(5, -6.0, 0.1))  # Gone

	return frames


static func _create_specter_frame(pose: int, y_offset: float, alpha: float) -> ImageTexture:
	"""Create a single specter sprite frame (ethereal ghost)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for specter (ethereal blues/whites)
	var color_body = Color(0.7, 0.8, 0.95, alpha * 0.7)
	var color_body_light = Color(0.9, 0.95, 1.0, alpha * 0.9)
	var color_body_dark = Color(0.4, 0.5, 0.7, alpha * 0.5)
	var color_eye = Color(0.3, 0.9, 1.0, alpha)  # Glowing cyan eyes

	var center_x = size / 2
	var base_y = int(size * 0.55 + y_offset)

	# Draw ghostly form
	_draw_specter_body(img, center_x, base_y, pose, color_body, color_body_light, color_body_dark, color_eye, alpha)

	return ImageTexture.create_from_image(img)


static func _draw_specter_body(img: Image, cx: int, cy: int, pose: int, body: Color, body_light: Color, body_dark: Color, eye: Color, alpha: float) -> void:
	"""Draw specter ghostly body"""
	var size = img.get_width()

	var lean = 0
	var stretch = 1.0
	match pose:
		1: lean = -5
		2: lean = 10; stretch = 0.8
		3: lean = 15; stretch = 1.2
		4: stretch = 0.6
		5: stretch = 0.5

	# Main body (hooded figure shape that fades at bottom)
	for y in range(-20, 20):
		var width = 12 - abs(y) / 3
		if y > 0:
			width = 12 - y / 2  # Taper at bottom

		for x in range(-int(width * stretch), int(width * stretch)):
			var px = cx + x + lean/3
			var py = cy + y

			if px >= 0 and px < size and py >= 0 and py < size:
				var dist_from_center = abs(x) / float(width) if width > 0 else 0
				var vert_fade = 1.0 - max(0, (y - 5) / 15.0)  # Fade at bottom

				var color = body
				if y < -10:
					color = body_light  # Hood highlight
				elif x < -width/2:
					color = body_dark
				elif dist_from_center > 0.7:
					color = body_dark

				color.a = color.a * vert_fade * alpha
				if color.a > 0.1:
					img.set_pixel(px, py, color)

	# Glowing eyes
	if pose != 5:  # No eyes when dissipating
		for ex in [-4, 4]:
			var eye_x = cx + ex + lean/4
			var eye_y = cy - 8
			for ey in range(-1, 2):
				for exx in range(-1, 2):
					var px = eye_x + exx
					var py = eye_y + ey
					if px >= 0 and px < size and py >= 0 and py < size:
						var glow = eye
						glow.a = alpha * (1.0 - sqrt(exx*exx + ey*ey) / 2.0)
						if glow.a > 0.2:
							img.set_pixel(px, py, glow)

	# Wispy trails at bottom
	var rng = RandomNumberGenerator.new()
	rng.seed = pose * 100
	for i in range(8):
		var trail_x = cx + int((rng.randf() - 0.5) * 16) + lean/4
		var trail_start = cy + 10
		for ty in range(6):
			var px = trail_x + int(sin(ty * 0.5 + i) * 2)
			var py = trail_start + ty
			if px >= 0 and px < size and py >= 0 and py < size:
				var trail_color = body_dark
				trail_color.a = alpha * 0.3 * (1.0 - ty / 6.0)
				if trail_color.a > 0.05:
					img.set_pixel(px, py, trail_color)


static func create_imp_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for imp enemy (small demon)"""
	var frames = SpriteFrames.new()

	# Idle animation (3 frames, hovering with wing flaps)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 4.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_imp_frame(0, 0.0))
	frames.add_frame("idle", _create_imp_frame(0, -2.0))
	frames.add_frame("idle", _create_imp_frame(0, -1.0))

	# Attack animation (4 frames, fireball throw)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.5)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_imp_frame(1, 0.0))   # Wind up
	frames.add_frame("attack", _create_imp_frame(2, -2.0))  # Throw
	frames.add_frame("attack", _create_imp_frame(3, -1.0))  # Release
	frames.add_frame("attack", _create_imp_frame(0, 0.0))   # Return

	# Hit animation (3 frames, tumble)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_imp_frame(4, 2.0))
	frames.add_frame("hit", _create_imp_frame(4, 0.0))
	frames.add_frame("hit", _create_imp_frame(0, 0.0))

	# Defeat animation (4 frames, spiral down)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_imp_frame(5, 0.0))
	frames.add_frame("defeat", _create_imp_frame(5, 3.0))
	frames.add_frame("defeat", _create_imp_frame(6, 6.0))
	frames.add_frame("defeat", _create_imp_frame(7, 10.0))

	return frames


static func _create_imp_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single imp sprite frame (small demon)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for imp (reds and oranges)
	var color_body = Color(0.8, 0.25, 0.2)       # Red skin
	var color_body_dark = Color(0.5, 0.15, 0.1)  # Dark red
	var color_body_light = Color(0.95, 0.4, 0.3) # Light red
	var color_wing = Color(0.6, 0.1, 0.15)       # Dark wing membrane
	var color_eye = Color(1.0, 0.9, 0.2)         # Yellow eyes
	var color_horn = Color(0.3, 0.2, 0.15)       # Dark horns

	var center_x = size / 2
	var base_y = int(size * 0.65 + y_offset)

	_draw_imp_body(img, center_x, base_y, pose, color_body, color_body_dark, color_body_light, color_wing, color_eye, color_horn)

	return ImageTexture.create_from_image(img)


static func _draw_imp_body(img: Image, cx: int, cy: int, pose: int, body: Color, body_dark: Color, body_light: Color, wing: Color, eye: Color, horn: Color) -> void:
	"""Draw imp body (small demon with wings)"""
	var s = img.get_width()

	var lean = 0
	var wing_up = false
	match pose:
		0: wing_up = true
		1: lean = -8
		2: lean = 12; wing_up = true
		3: lean = 6
		4: lean = -15
		5: lean = -10
		6, 7: pass  # Collapsed poses

	if pose >= 6:
		# Draw collapsed imp
		for y in range(-4, 4):
			for x in range(-8, 8):
				var px = cx + x
				var py = cy + y + 8
				if px >= 0 and px < s and py >= 0 and py < s:
					if abs(x) + abs(y) < 8:
						img.set_pixel(px, py, body_dark)
		return

	# Wings (draw first, behind body)
	var wing_y_offset = -8 if wing_up else -4
	for wx in [-12, 8]:
		var wing_x = cx + wx + lean/4
		for wy in range(-6, 4):
			for wxx in range(6):
				var px = wing_x + (wxx if wx > 0 else -wxx)
				var py = cy + wy + wing_y_offset
				if px >= 0 and px < s and py >= 0 and py < s:
					if wxx + abs(wy) < 8:
						img.set_pixel(px, py, wing)

	# Head (round)
	for y in range(-18 + lean/4, -10 + lean/4):
		for x in range(-5, 5):
			var px = cx + x + lean/6
			var py = cy + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var dist = sqrt(x*x + pow(y + 14 - lean/4, 2))
				if dist < 5:
					var color = body
					if y < -15 + lean/4:
						color = body_light
					elif x < -2:
						color = body_dark
					img.set_pixel(px, py, color)

	# Horns
	for hx in [-4, 4]:
		for hy in range(-4, 0):
			var px = cx + hx + lean/8
			var py = cy - 18 + hy + lean/4
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, horn)

	# Eyes (glowing)
	for ex in [-2, 2]:
		var eye_x = cx + ex + lean/6
		var eye_y = cy - 14 + lean/4
		if eye_x >= 0 and eye_x < s and eye_y >= 0 and eye_y < s:
			img.set_pixel(eye_x, eye_y, eye)

	# Body (small torso)
	for y in range(-10, 2):
		var width = 4 - abs(y + 4) / 3
		for x in range(-width, width):
			var px = cx + x + lean/5
			var py = cy + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var color = body
				if x < -width/2:
					color = body_dark
				elif x > width/2:
					color = body_light
				img.set_pixel(px, py, color)

	# Tail
	for i in range(10):
		var tail_x = cx + 5 + i + lean/6
		var tail_y = cy + int(sin(i * 0.4) * 3)
		if tail_x >= 0 and tail_x < s and tail_y >= 0 and tail_y < s:
			img.set_pixel(tail_x, tail_y, body_dark)

	# Legs (small)
	for y in range(2, 8):
		for lx in [-2, 2]:
			var px = cx + lx + lean/8
			var py = cy + y
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, body_dark)


static func create_wolf_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for dire wolf enemy"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, breathing)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_wolf_frame(0, 0.0))
	frames.add_frame("idle", _create_wolf_frame(0, -0.5))

	# Attack animation (4 frames, lunge bite)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_wolf_frame(1, 0.0))   # Crouch
	frames.add_frame("attack", _create_wolf_frame(2, -3.0))  # Leap
	frames.add_frame("attack", _create_wolf_frame(3, -1.0))  # Bite
	frames.add_frame("attack", _create_wolf_frame(0, 0.0))   # Return

	# Hit animation (3 frames, yelp)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_wolf_frame(4, 1.0))
	frames.add_frame("hit", _create_wolf_frame(4, 0.0))
	frames.add_frame("hit", _create_wolf_frame(0, 0.0))

	# Defeat animation (3 frames, collapse)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_wolf_frame(5, 0.0))
	frames.add_frame("defeat", _create_wolf_frame(5, 2.0))
	frames.add_frame("defeat", _create_wolf_frame(6, 4.0))

	return frames


static func _create_wolf_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single wolf sprite frame (dire wolf)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for wolf (grays and browns)
	var color_fur = Color(0.35, 0.3, 0.28)       # Dark gray-brown fur
	var color_fur_dark = Color(0.2, 0.18, 0.16)  # Shadow
	var color_fur_light = Color(0.5, 0.45, 0.4)  # Highlight
	var color_eye = Color(0.9, 0.6, 0.1)         # Amber eyes
	var color_teeth = Color(0.95, 0.95, 0.9)     # White teeth

	var center_x = size / 2
	var base_y = int(size * 0.7 + y_offset)

	_draw_wolf_body(img, center_x, base_y, pose, color_fur, color_fur_dark, color_fur_light, color_eye, color_teeth)

	return ImageTexture.create_from_image(img)


static func _draw_wolf_body(img: Image, cx: int, cy: int, pose: int, fur: Color, fur_dark: Color, fur_light: Color, eye: Color, teeth: Color) -> void:
	"""Draw wolf body (quadruped)"""
	var s = img.get_width()

	var crouch = 0
	var lunge = 0
	var mouth_open = false
	match pose:
		1: crouch = 4
		2: lunge = -8; crouch = -2
		3: lunge = -4; mouth_open = true
		4: crouch = 2
		5, 6: crouch = 6

	if pose == 6:
		# Collapsed wolf
		for y in range(-4, 6):
			for x in range(-14, 14):
				var px = cx + x
				var py = cy + y + 4
				if px >= 0 and px < s and py >= 0 and py < s:
					if abs(y) < 4 and abs(x) < 12:
						img.set_pixel(px, py, fur_dark)
		return

	# Main body (horizontal ellipse)
	for y in range(-8 + crouch, 4 + crouch):
		for x in range(-12 + lunge, 8 + lunge):
			var px = cx + x
			var py = cy + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var dist = sqrt(pow(x - lunge + 2, 2) / 100.0 + pow(y - crouch + 2, 2) / 36.0)
				if dist < 1.0:
					var color = fur
					if y < -4 + crouch:
						color = fur_light
					elif y > 0 + crouch:
						color = fur_dark
					img.set_pixel(px, py, color)

	# Head (elongated)
	var head_x = cx - 14 + lunge
	var head_y = cy - 4 + crouch
	for y in range(-6, 4):
		for x in range(-8, 2):
			var px = head_x + x
			var py = head_y + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var dist = sqrt(pow(x + 3, 2) / 25.0 + pow(y + 1, 2) / 16.0)
				if dist < 1.0:
					var color = fur
					if y < -3:
						color = fur_light
					img.set_pixel(px, py, color)

	# Snout
	for y in range(-2, 3):
		for x in range(-12, -6):
			var px = head_x + x
			var py = head_y + y + 2
			if px >= 0 and px < s and py >= 0 and py < s:
				if abs(y) < 3 - (x + 12) / 2:
					img.set_pixel(px, py, fur)

	# Eye
	var eye_x = head_x - 2
	var eye_y = head_y - 2
	if eye_x >= 0 and eye_x < s and eye_y >= 0 and eye_y < s:
		img.set_pixel(eye_x, eye_y, eye)

	# Teeth/mouth
	if mouth_open:
		for tx in range(-10, -6):
			var px = head_x + tx
			var py = head_y + 3
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, teeth)

	# Ears
	for ear in [-4, 0]:
		for ey in range(-4, 0):
			var px = head_x + ear
			var py = head_y - 6 + ey
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, fur_dark)

	# Legs
	var leg_positions = [[-8, cy + 4 + crouch], [-2, cy + 4 + crouch], [4, cy + 4 + crouch], [6, cy + 4 + crouch]]
	for leg in leg_positions:
		var leg_x = cx + leg[0] + lunge
		var leg_y = leg[1]
		for ly in range(8 - crouch):
			var px = leg_x
			var py = leg_y + ly
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, fur_dark)
				if px + 1 < s:
					img.set_pixel(px + 1, py, fur_dark)

	# Tail
	for i in range(10):
		var tail_x = cx + 8 + i + lunge
		var tail_y = cy - 6 + crouch - int(i / 2)
		if tail_x >= 0 and tail_x < s and tail_y >= 0 and tail_y < s:
			img.set_pixel(tail_x, tail_y, fur)
			if tail_y + 1 < s:
				img.set_pixel(tail_x, tail_y + 1, fur_dark)


static func create_viper_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for viper/snake enemy"""
	var frames = SpriteFrames.new()

	# Idle animation (3 frames, coiled swaying)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_viper_frame(0, 0.0))
	frames.add_frame("idle", _create_viper_frame(0, -1.0))
	frames.add_frame("idle", _create_viper_frame(0, 0.5))

	# Attack animation (4 frames, strike)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 6.0)  # Fast strike
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_viper_frame(1, 0.0))   # Coil back
	frames.add_frame("attack", _create_viper_frame(2, -2.0))  # Strike forward
	frames.add_frame("attack", _create_viper_frame(3, -1.0))  # Bite
	frames.add_frame("attack", _create_viper_frame(0, 0.0))   # Return

	# Hit animation (3 frames, recoil)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_viper_frame(4, 1.0))
	frames.add_frame("hit", _create_viper_frame(4, 0.0))
	frames.add_frame("hit", _create_viper_frame(0, 0.0))

	# Defeat animation (3 frames, uncoil and fall)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_viper_frame(5, 0.0))
	frames.add_frame("defeat", _create_viper_frame(6, 2.0))
	frames.add_frame("defeat", _create_viper_frame(7, 4.0))

	return frames


static func _create_viper_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single viper sprite frame (coiled snake)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for viper (greens with pattern)
	var color_scale = Color(0.25, 0.45, 0.2)       # Dark green scales
	var color_scale_dark = Color(0.15, 0.3, 0.1)   # Shadow
	var color_scale_light = Color(0.4, 0.6, 0.3)   # Highlight
	var color_belly = Color(0.7, 0.65, 0.5)        # Lighter belly
	var color_eye = Color(0.9, 0.7, 0.1)           # Yellow slit eyes
	var color_tongue = Color(0.9, 0.2, 0.3)        # Red tongue

	var center_x = size / 2
	var base_y = int(size * 0.65 + y_offset)

	_draw_viper_body(img, center_x, base_y, pose, color_scale, color_scale_dark, color_scale_light, color_belly, color_eye, color_tongue)

	return ImageTexture.create_from_image(img)


static func _draw_viper_body(img: Image, cx: int, cy: int, pose: int, scale: Color, scale_dark: Color, scale_light: Color, belly: Color, eye: Color, tongue: Color) -> void:
	"""Draw viper body (coiled snake)"""
	var s = img.get_width()

	var strike_extend = 0
	var coil_tight = 1.0
	var show_tongue = false
	match pose:
		1: coil_tight = 1.3  # Coil tighter
		2: strike_extend = -12; show_tongue = true
		3: strike_extend = -8; show_tongue = true
		4: strike_extend = 4
		5: coil_tight = 0.8
		6: coil_tight = 0.5
		7: coil_tight = 0.2

	if pose == 7:
		# Fallen snake (just a line)
		for x in range(-20, 20):
			var px = cx + x
			var py = cy + 8
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, scale_dark)
				if py + 1 < s:
					img.set_pixel(px, py + 1, scale)
		return

	# Draw coiled body (spiral)
	for coil in range(3):
		var coil_y = cy + coil * 5 * coil_tight
		var coil_radius = (12 - coil * 2) * coil_tight
		for angle in range(0, 360, 15):
			var rad = deg_to_rad(angle)
			var bx = cx + int(cos(rad) * coil_radius)
			var by = int(coil_y + sin(rad) * coil_radius * 0.4)
			if bx >= 0 and bx < s and by >= 0 and by < s:
				var color = scale if angle % 30 == 0 else scale_dark
				img.set_pixel(bx, by, color)
				# Make body 2-3 pixels thick
				for thick in range(-1, 2):
					var tpy = by + thick
					if tpy >= 0 and tpy < s:
						img.set_pixel(bx, tpy, color if thick == 0 else (belly if thick > 0 else scale_light))

	# Head (raised from coil)
	var head_x = cx - 8 + strike_extend
	var head_y = cy - 12
	for y in range(-4, 4):
		for x in range(-6, 4):
			var px = head_x + x
			var py = head_y + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var dist = sqrt(pow(x + 1, 2) / 20.0 + pow(y, 2) / 10.0)
				if dist < 1.0:
					var color = scale
					if y < -1:
						color = scale_light
					elif y > 1:
						color = belly
					img.set_pixel(px, py, color)

	# Eyes (slit pupils)
	var eye_x = head_x - 3
	var eye_y = head_y - 1
	if eye_x >= 0 and eye_x < s and eye_y >= 0 and eye_y < s:
		img.set_pixel(eye_x, eye_y, eye)

	# Tongue
	if show_tongue:
		for tx in range(-8, -3):
			var px = head_x + tx
			var py = head_y + 1
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, tongue)
		# Forked tongue
		if head_x - 8 >= 0:
			img.set_pixel(head_x - 8, head_y, tongue)
			img.set_pixel(head_x - 8, head_y + 2, tongue)

	# Hood pattern (diamond marking on back)
	var hood_x = head_x + 2
	var hood_y = head_y + 1
	for hy in range(-2, 3):
		for hx in range(-1, 2):
			var px = hood_x + hx
			var py = hood_y + hy
			if px >= 0 and px < s and py >= 0 and py < s:
				if abs(hx) + abs(hy) < 2:
					img.set_pixel(px, py, scale_light)


static func create_bat_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for bat enemy"""
	var frames = SpriteFrames.new()

	# Idle animation (4 frames, wing flap hovering)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 6.0)  # Fast wing flaps
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_bat_frame(0, 0.0))   # Wings up
	frames.add_frame("idle", _create_bat_frame(1, -1.0))  # Wings mid
	frames.add_frame("idle", _create_bat_frame(2, -2.0))  # Wings down
	frames.add_frame("idle", _create_bat_frame(1, -1.0))  # Wings mid

	# Attack animation (4 frames, swoop)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_bat_frame(3, 0.0))   # Dive start
	frames.add_frame("attack", _create_bat_frame(4, 2.0))   # Diving
	frames.add_frame("attack", _create_bat_frame(5, 0.0))   # Bite
	frames.add_frame("attack", _create_bat_frame(0, -1.0))  # Return

	# Hit animation (3 frames, tumble)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_bat_frame(6, 1.0))
	frames.add_frame("hit", _create_bat_frame(6, 0.0))
	frames.add_frame("hit", _create_bat_frame(0, 0.0))

	# Defeat animation (3 frames, fall)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_bat_frame(6, 0.0))
	frames.add_frame("defeat", _create_bat_frame(7, 4.0))
	frames.add_frame("defeat", _create_bat_frame(7, 8.0))

	return frames


static func _create_bat_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single bat sprite frame"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for bat (purples and dark grays)
	var color_fur = Color(0.35, 0.25, 0.4)        # Dark purple fur
	var color_fur_dark = Color(0.2, 0.15, 0.25)   # Shadow
	var color_wing = Color(0.3, 0.2, 0.35)        # Wing membrane
	var color_wing_dark = Color(0.15, 0.1, 0.2)   # Wing shadow
	var color_eye = Color(0.9, 0.2, 0.2)          # Red eyes
	var color_fang = Color(0.95, 0.95, 0.9)       # White fangs

	var center_x = size / 2
	var base_y = int(size * 0.5 + y_offset)

	_draw_bat_body(img, center_x, base_y, pose, color_fur, color_fur_dark, color_wing, color_wing_dark, color_eye, color_fang)

	return ImageTexture.create_from_image(img)


static func _draw_bat_body(img: Image, cx: int, cy: int, pose: int, fur: Color, fur_dark: Color, wing: Color, wing_dark: Color, eye: Color, fang: Color) -> void:
	"""Draw bat body with wings"""
	var s = img.get_width()

	var wing_angle = 0  # 0=up, 1=mid, 2=down
	var diving = false
	var tumble = false
	match pose:
		0: wing_angle = 0
		1: wing_angle = 1
		2: wing_angle = 2
		3: wing_angle = 0; diving = true
		4: wing_angle = 2; diving = true
		5: wing_angle = 1
		6: tumble = true
		7: tumble = true

	if pose == 7:
		# Fallen bat
		for y in range(-2, 4):
			for x in range(-12, 12):
				var px = cx + x
				var py = cy + y + 8
				if px >= 0 and px < s and py >= 0 and py < s:
					if abs(y) < 3:
						img.set_pixel(px, py, fur_dark if abs(x) > 4 else fur)
		return

	# Wings
	var wing_y_offsets = [-10, 0, 8]
	var wing_y_base = wing_y_offsets[wing_angle]

	for side in [-1, 1]:
		for i in range(16):
			var wing_x = cx + side * (4 + i)
			var wing_height = 6 - i / 3
			var wing_y = cy + wing_y_base + int(i * 0.3) * (1 if wing_angle == 2 else -1 if wing_angle == 0 else 0)

			for wy in range(-wing_height, wing_height):
				var px = wing_x
				var py = wing_y + wy
				if px >= 0 and px < s and py >= 0 and py < s:
					var color = wing if abs(wy) < wing_height - 1 else wing_dark
					img.set_pixel(px, py, color)

			# Wing bones
			if i % 4 == 0:
				for wy in range(-wing_height, wing_height):
					var px = wing_x
					var py = wing_y + wy
					if px >= 0 and px < s and py >= 0 and py < s:
						img.set_pixel(px, py, fur_dark)

	# Body
	var body_lean = 10 if diving else (-10 if tumble else 0)
	for y in range(-6, 6):
		for x in range(-4, 4):
			var px = cx + x + body_lean / 10
			var py = cy + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var dist = sqrt(x*x / 16.0 + y*y / 36.0)
				if dist < 1.0:
					var color = fur
					if y < -2:
						color = fur_dark
					img.set_pixel(px, py, color)

	# Head
	var head_y = cy - 8
	for y in range(-4, 2):
		for x in range(-3, 3):
			var px = cx + x
			var py = head_y + y
			if px >= 0 and px < s and py >= 0 and py < s:
				if abs(x) + abs(y + 1) < 5:
					img.set_pixel(px, py, fur)

	# Ears
	for ear in [-3, 3]:
		for ey in range(-4, 0):
			var px = cx + ear
			var py = head_y - 4 + ey
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, fur_dark)

	# Eyes
	for ex in [-2, 2]:
		var eye_x = cx + ex
		var eye_y = head_y - 1
		if eye_x >= 0 and eye_x < s and eye_y >= 0 and eye_y < s:
			img.set_pixel(eye_x, eye_y, eye)

	# Fangs
	for fx in [-1, 1]:
		var fang_x = cx + fx
		var fang_y = head_y + 2
		if fang_x >= 0 and fang_x < s and fang_y >= 0 and fang_y < s:
			img.set_pixel(fang_x, fang_y, fang)


static func create_fungoid_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for fungoid/mushroom enemy"""
	var frames = SpriteFrames.new()

	# Idle animation (3 frames, pulsing)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_fungoid_frame(0, 0.0, 1.0))
	frames.add_frame("idle", _create_fungoid_frame(0, -1.0, 1.02))
	frames.add_frame("idle", _create_fungoid_frame(0, 0.0, 0.98))

	# Attack animation (4 frames, spore release)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_fungoid_frame(1, 0.0, 1.0))   # Swell
	frames.add_frame("attack", _create_fungoid_frame(2, -1.0, 1.1))  # Expand
	frames.add_frame("attack", _create_fungoid_frame(3, 0.0, 0.9))   # Release spores
	frames.add_frame("attack", _create_fungoid_frame(0, 0.0, 1.0))   # Return

	# Hit animation (3 frames, wobble)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_fungoid_frame(4, 0.0, 0.9))
	frames.add_frame("hit", _create_fungoid_frame(4, 1.0, 1.0))
	frames.add_frame("hit", _create_fungoid_frame(0, 0.0, 1.0))

	# Defeat animation (3 frames, wilt)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_fungoid_frame(5, 0.0, 1.0))
	frames.add_frame("defeat", _create_fungoid_frame(5, 2.0, 0.8))
	frames.add_frame("defeat", _create_fungoid_frame(6, 4.0, 0.5))

	return frames


static func _create_fungoid_frame(pose: int, y_offset: float, scale: float) -> ImageTexture:
	"""Create a single fungoid sprite frame (mushroom creature)"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for fungoid (browns and oranges)
	var color_cap = Color(0.6, 0.35, 0.25)        # Brown cap
	var color_cap_dark = Color(0.4, 0.2, 0.15)    # Shadow
	var color_cap_light = Color(0.75, 0.5, 0.35)  # Highlight
	var color_spots = Color(0.95, 0.9, 0.8)       # White spots
	var color_stem = Color(0.8, 0.75, 0.65)       # Pale stem
	var color_eye = Color(0.2, 0.15, 0.1)         # Dark eyes

	var center_x = size / 2
	var base_y = int(size * 0.7 + y_offset)

	_draw_fungoid_body(img, center_x, base_y, pose, scale, color_cap, color_cap_dark, color_cap_light, color_spots, color_stem, color_eye)

	return ImageTexture.create_from_image(img)


static func _draw_fungoid_body(img: Image, cx: int, cy: int, pose: int, scale: float, cap: Color, cap_dark: Color, cap_light: Color, spots: Color, stem: Color, eye: Color) -> void:
	"""Draw fungoid body (mushroom with face)"""
	var s = img.get_width()

	var lean = 0
	var show_spores = false
	match pose:
		1: lean = -3
		2: lean = -5
		3: show_spores = true
		4: lean = 8
		5: lean = 15
		6: lean = 25

	# Stem (base)
	var stem_height = int(12 * scale)
	for y in range(0, stem_height):
		var width = int((4 + y / 3) * scale)
		for x in range(-width, width):
			var px = cx + x + lean/3
			var py = cy + y - 4
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, stem)

	# Cap (dome shape)
	var cap_radius = int(14 * scale)
	var cap_height = int(12 * scale)
	var cap_y = cy - 8

	for y in range(-cap_height, 4):
		var y_factor = abs(y) / float(cap_height)
		var width = int(cap_radius * sqrt(1 - y_factor * y_factor * 0.7))

		for x in range(-width, width):
			var px = cx + x + lean/4
			var py = cap_y + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var color = cap
				if y < -cap_height/2:
					color = cap_light
				elif y > 0:
					color = cap_dark
				elif abs(x) > width - 3:
					color = cap_dark
				img.set_pixel(px, py, color)

	# Spots on cap
	var spot_positions = [[-6, -14], [4, -12], [-2, -16], [8, -10]]
	for spot in spot_positions:
		var spot_x = cx + int(spot[0] * scale) + lean/4
		var spot_y = cap_y + int(spot[1] * scale / 2) + 8
		for sy in range(-2, 2):
			for sx in range(-2, 2):
				var px = spot_x + sx
				var py = spot_y + sy
				if px >= 0 and px < s and py >= 0 and py < s:
					if abs(sx) + abs(sy) < 3:
						img.set_pixel(px, py, spots)

	# Eyes (on stem)
	if pose < 6:
		for ex in [-3, 3]:
			var eye_x = cx + ex + lean/4
			var eye_y = cy - 2
			if eye_x >= 0 and eye_x < s and eye_y >= 0 and eye_y < s:
				img.set_pixel(eye_x, eye_y, eye)
				if eye_x + 1 < s:
					img.set_pixel(eye_x + 1, eye_y, eye)

	# Spores (when attacking)
	if show_spores:
		var rng = RandomNumberGenerator.new()
		rng.seed = 54321
		for i in range(12):
			var spore_x = cx + int((rng.randf() - 0.5) * 30)
			var spore_y = cap_y - 8 - int(rng.randf() * 15)
			if spore_x >= 0 and spore_x < s and spore_y >= 0 and spore_y < s:
				var spore_color = Color(0.8, 0.9, 0.6, 0.8)
				img.set_pixel(spore_x, spore_y, spore_color)


static func create_goblin_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for goblin enemy"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, slight bounce)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_goblin_frame(0, 0.0))
	frames.add_frame("idle", _create_goblin_frame(0, -1.0))

	# Attack animation (4 frames, club swing)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_goblin_frame(1, 0.0))   # Wind up
	frames.add_frame("attack", _create_goblin_frame(2, -1.0))  # Swing
	frames.add_frame("attack", _create_goblin_frame(3, 0.0))   # Impact
	frames.add_frame("attack", _create_goblin_frame(0, 0.0))   # Return

	# Hit animation (3 frames, stagger)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_goblin_frame(4, 2.0))
	frames.add_frame("hit", _create_goblin_frame(4, 1.0))
	frames.add_frame("hit", _create_goblin_frame(0, 0.0))

	# Defeat animation (3 frames, fall)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_goblin_frame(5, 0.0))
	frames.add_frame("defeat", _create_goblin_frame(5, 3.0))
	frames.add_frame("defeat", _create_goblin_frame(6, 6.0))

	return frames


static func _create_goblin_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single goblin sprite frame"""
	var size = 64
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for goblin (green skin)
	var color_skin = Color(0.45, 0.55, 0.3)       # Green skin
	var color_skin_dark = Color(0.3, 0.4, 0.2)    # Shadow
	var color_skin_light = Color(0.55, 0.65, 0.4) # Highlight
	var color_cloth = Color(0.5, 0.35, 0.25)      # Brown cloth
	var color_eye = Color(0.9, 0.7, 0.1)          # Yellow eyes
	var color_club = Color(0.4, 0.3, 0.2)         # Brown club

	var center_x = size / 2
	var base_y = int(size * 0.72 + y_offset)

	_draw_goblin_body(img, center_x, base_y, pose, color_skin, color_skin_dark, color_skin_light, color_cloth, color_eye, color_club)

	return ImageTexture.create_from_image(img)


static func _draw_goblin_body(img: Image, cx: int, cy: int, pose: int, skin: Color, skin_dark: Color, skin_light: Color, cloth: Color, eye: Color, club: Color) -> void:
	"""Draw goblin body (small humanoid)"""
	var s = img.get_width()

	var lean = 0
	var club_angle = 20
	match pose:
		1: lean = -5; club_angle = -40
		2: lean = 8; club_angle = 60
		3: lean = 5; club_angle = 90
		4: lean = -12
		5: lean = -20
		6: lean = -30

	if pose == 6:
		# Fallen goblin
		for y in range(-4, 4):
			for x in range(-10, 10):
				var px = cx + x
				var py = cy + y + 6
				if px >= 0 and px < s and py >= 0 and py < s:
					if abs(y) < 3:
						img.set_pixel(px, py, skin_dark)
		return

	# Club (drawn first, behind in some poses)
	if pose != 5 and pose != 6:
		var club_length = 14
		var club_rad = deg_to_rad(club_angle)
		var club_x = cx + 8 + lean/4
		var club_y = cy - 8

		for i in range(club_length):
			var px = club_x + int(cos(club_rad) * i)
			var py = club_y + int(sin(club_rad) * i)
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, club)
				if py + 1 < s:
					img.set_pixel(px, py + 1, club)

	# Head (large relative to body)
	var head_x = cx + lean/5
	var head_y = cy - 16
	for y in range(-8, 4):
		for x in range(-6, 6):
			var px = head_x + x
			var py = head_y + y
			if px >= 0 and px < s and py >= 0 and py < s:
				var dist = sqrt(x*x / 36.0 + pow(y + 2, 2) / 49.0)
				if dist < 1.0:
					var color = skin
					if y < -4:
						color = skin_light
					elif x < -3:
						color = skin_dark
					img.set_pixel(px, py, color)

	# Pointy ears
	for ear in [-7, 7]:
		for ey in range(-3, 0):
			var px = head_x + ear
			var py = head_y - 4 + ey
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, skin)

	# Large nose
	for ny in range(-2, 2):
		var px = head_x - 2
		var py = head_y + ny
		if px >= 0 and px < s and py >= 0 and py < s:
			img.set_pixel(px, py, skin_dark)

	# Eyes
	for ex in [-3, 2]:
		var eye_x = head_x + ex
		var eye_y = head_y - 2
		if eye_x >= 0 and eye_x < s and eye_y >= 0 and eye_y < s:
			img.set_pixel(eye_x, eye_y, eye)

	# Body (small, hunched)
	for y in range(-8, 4):
		var width = 5 - abs(y) / 3
		for x in range(-width, width):
			var px = cx + x + lean/4
			var py = cy + y
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, cloth)

	# Legs
	for y in range(4, 10):
		for lx in [-3, 3]:
			var px = cx + lx + lean/6
			var py = cy + y
			if px >= 0 and px < s and py >= 0 and py < s:
				img.set_pixel(px, py, skin_dark)
