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

## Sprite size configuration (SNES-style, larger for more detail)
const SPRITE_SIZE: int = 96  # Increased from 64 for more detail
const BASE_SIZE: int = 64    # Original design size for scaling calculations
const SPRITE_SCALE: float = float(SPRITE_SIZE) / float(BASE_SIZE)  # 1.5x scale

## Cached equipment data for weapon visuals
static var _equipment_data: Dictionary = {}
static var _equipment_loaded: bool = false

## Load equipment data from JSON
static func _load_equipment_data() -> void:
	if _equipment_loaded:
		return
	var file = FileAccess.open("res://data/equipment.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			_equipment_data = json.data
		file.close()
	_equipment_loaded = true


## Get weapon visual parameters for drawing
static func get_weapon_visual(weapon_id: String) -> Dictionary:
	"""Returns visual params for a weapon: type, colors, glow effects"""
	_load_equipment_data()

	if weapon_id.is_empty() or not _equipment_data.has("weapons"):
		return _get_default_weapon_visual("sword")

	var weapons = _equipment_data["weapons"]
	if not weapons.has(weapon_id):
		return _get_default_weapon_visual("sword")

	var weapon = weapons[weapon_id]
	var weapon_type = weapon.get("weapon_type", "sword")
	var visual = weapon.get("visual", {})

	var result = {
		"type": weapon_type,
		"glow": visual.get("glow", false),
	}

	match weapon_type:
		"sword":
			var blade = visual.get("blade_color", [0.7, 0.7, 0.8])
			var blade_light = visual.get("blade_light", [0.95, 0.95, 1.0])
			var blade_dark = visual.get("blade_dark", [0.5, 0.5, 0.6])
			result["metal"] = Color(blade[0], blade[1], blade[2])
			result["metal_light"] = Color(blade_light[0], blade_light[1], blade_light[2])
			result["metal_dark"] = Color(blade_dark[0], blade_dark[1], blade_dark[2])
			if visual.has("glow_color"):
				var gc = visual["glow_color"]
				result["glow_color"] = Color(gc[0], gc[1], gc[2])
		"staff":
			var wood = visual.get("wood_color", [0.5, 0.3, 0.2])
			var gem = visual.get("gem_color", [0.3, 0.8, 1.0])
			result["wood"] = Color(wood[0], wood[1], wood[2])
			result["gem"] = Color(gem[0], gem[1], gem[2])
			if visual.has("glow_color"):
				var gc = visual["glow_color"]
				result["glow_color"] = Color(gc[0], gc[1], gc[2])
		"dagger":
			var blade = visual.get("blade_color", [0.8, 0.8, 0.9])
			var blade_light = visual.get("blade_light", [1.0, 1.0, 1.0])
			result["blade"] = Color(blade[0], blade[1], blade[2])
			result["blade_light"] = Color(blade_light[0], blade_light[1], blade_light[2])

	return result


## Get default weapon visual for a type
static func _get_default_weapon_visual(weapon_type: String) -> Dictionary:
	match weapon_type:
		"sword":
			return {
				"type": "sword",
				"metal": Color(0.7, 0.7, 0.8),
				"metal_light": Color(0.95, 0.95, 1.0),
				"metal_dark": Color(0.5, 0.5, 0.6),
				"glow": false
			}
		"staff":
			return {
				"type": "staff",
				"wood": Color(0.5, 0.3, 0.2),
				"gem": Color(0.3, 0.8, 1.0),
				"glow": false
			}
		"dagger":
			return {
				"type": "dagger",
				"blade": Color(0.8, 0.8, 0.9),
				"blade_light": Color(1.0, 1.0, 1.0),
				"glow": false
			}
		_:
			return _get_default_weapon_visual("sword")


## Helper function to scale a value from base to current sprite size
static func _s(value: float) -> int:
	"""Scale a coordinate/size value to current sprite size"""
	return int(value * SPRITE_SCALE)

## Helper function for floating point scaling
static func _sf(value: float) -> float:
	"""Scale a value to current sprite size (float)"""
	return value * SPRITE_SCALE

## Draw a pixel with bounds checking
static func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void:
	"""Set pixel if within bounds"""
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)

## Draw an outlined pixel (adds dark outline around it)
static func _outlined_pixel(img: Image, x: int, y: int, color: Color, outline_color: Color = Color(0.1, 0.1, 0.1, 0.8)) -> void:
	"""Set pixel with outline effect for more definition"""
	var s = img.get_width()
	# Draw outline first
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			if ox != 0 or oy != 0:
				var px = x + ox
				var py = y + oy
				if px >= 0 and px < s and py >= 0 and py < s:
					var existing = img.get_pixel(px, py)
					if existing.a < 0.1:  # Only outline on transparent pixels
						img.set_pixel(px, py, outline_color)
	# Draw main pixel
	_safe_pixel(img, x, y, color)

## Draw a filled ellipse with better anti-aliasing
static func _draw_ellipse_filled(img: Image, cx: int, cy: int, rx: int, ry: int, color: Color, color_dark: Color, color_light: Color) -> void:
	"""Draw a filled ellipse with gradient shading"""
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			var dist = sqrt(pow(float(x) / rx, 2) + pow(float(y) / ry, 2))
			if dist <= 1.0:
				var px = cx + x
				var py = cy + y
				# Gradient shading based on position
				var shade_color = color
				if y < -ry * 0.3:
					shade_color = color_light  # Top highlight
				elif y > ry * 0.3:
					shade_color = color_dark   # Bottom shadow
				elif x < -rx * 0.3:
					shade_color = color_dark   # Left shadow
				_safe_pixel(img, px, py, shade_color)

## Draw a line with thickness
static func _draw_thick_line(img: Image, x1: int, y1: int, x2: int, y2: int, color: Color, thickness: int = 2) -> void:
	"""Draw a line with specified thickness"""
	var dx = x2 - x1
	var dy = y2 - y1
	var steps = max(abs(dx), abs(dy))
	if steps == 0:
		steps = 1
	for i in range(steps + 1):
		var t = float(i) / steps
		var x = int(x1 + dx * t)
		var y = int(y1 + dy * t)
		for tx in range(-thickness/2, thickness/2 + 1):
			for ty in range(-thickness/2, thickness/2 + 1):
				_safe_pixel(img, x + tx, y + ty, color)

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

static func create_hero_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	"""Create animated sprite frames for hero (12-bit style)"""
	var frames = SpriteFrames.new()
	var weapon_visual = get_weapon_visual(weapon_id)

	# Idle animation (2 frames, slight bob)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)  # Slower idle
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_hero_frame(0, 0.0, weapon_visual))  # Normal
	frames.add_frame("idle", _create_hero_frame(0, -1.0, weapon_visual))  # Slight up

	# Attack animation (4 frames, swing sword) - SLOWER for visibility
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)  # Much slower
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_hero_frame(1, 0.0, weapon_visual))  # Wind up
	frames.add_frame("attack", _create_hero_frame(2, 0.0, weapon_visual))  # Mid swing
	frames.add_frame("attack", _create_hero_frame(3, 0.0, weapon_visual))  # Full swing
	frames.add_frame("attack", _create_hero_frame(0, 0.0, weapon_visual))  # Return

	# Defend animation (2 frames, shield up)
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 3.0)  # Slower
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_hero_frame(4, 0.0, weapon_visual))  # Shield up
	frames.add_frame("defend", _create_hero_frame(4, 0.0, weapon_visual))  # Hold

	# Hit animation (3 frames, recoil) - SLOWER for visibility
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)  # Much slower
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_hero_frame(5, 2.0, weapon_visual))   # Recoil back
	frames.add_frame("hit", _create_hero_frame(5, 1.0, weapon_visual))   # Mid recoil
	frames.add_frame("hit", _create_hero_frame(0, 0.0, weapon_visual))   # Return to normal

	# Victory animation (2 frames, pose)
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)  # Slower
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_hero_frame(6, 0.0, weapon_visual))  # Victory pose
	frames.add_frame("victory", _create_hero_frame(6, -1.0, weapon_visual))  # Slight bob

	# Defeat animation (3 frames, collapse) - SLOWER for visibility
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 3.0)  # Slower
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_hero_frame(7, 0.0, weapon_visual))   # Stagger
	frames.add_frame("defeat", _create_hero_frame(7, 2.0, weapon_visual))   # Falling
	frames.add_frame("defeat", _create_hero_frame(7, 4.0, weapon_visual))   # Down

	return frames


static func _create_hero_frame(pose: int, y_offset: float, weapon_visual: Dictionary = {}) -> ImageTexture:
	"""Create a single hero sprite frame (SNES-style knight/fighter with more detail)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-style color palette (16 colors)
	var color_armor = Color(0.2, 0.4, 0.8)          # Blue armor base
	var color_armor_dark = Color(0.1, 0.2, 0.5)     # Deep shadow
	var color_armor_mid = Color(0.15, 0.3, 0.65)    # Mid shadow
	var color_armor_light = Color(0.4, 0.6, 1.0)    # Highlight
	var color_armor_shine = Color(0.6, 0.8, 1.0)    # Bright shine
	var color_skin = Color(0.9, 0.7, 0.6)           # Skin tone
	var color_skin_dark = Color(0.7, 0.5, 0.4)      # Skin shadow
	var color_hair = Color(0.6, 0.45, 0.3)          # Brown hair
	var color_outline = Color(0.08, 0.15, 0.35)     # Dark outline

	# Get weapon colors from visual params or use defaults
	var color_metal = weapon_visual.get("metal", Color(0.7, 0.7, 0.8))
	var color_metal_light = weapon_visual.get("metal_light", Color(0.95, 0.95, 1.0))
	var color_metal_dark = weapon_visual.get("metal_dark", Color(0.5, 0.5, 0.6))
	var weapon_glow = weapon_visual.get("glow", false)
	var glow_color = weapon_visual.get("glow_color", Color(1.0, 0.5, 0.2))

	var center_x = size / 2
	var base_y = int(size * 0.75 + _sf(y_offset))

	match pose:
		0:  # Idle stance
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x + _s(12), base_y - _s(12), 0, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x + _s(12), base_y - _s(12), 0, glow_color)

		1:  # Wind up (sword back)
			_draw_hero_body_enhanced(img, center_x, base_y, _s(-5), color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x + _s(18), base_y - _s(18), -30, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x + _s(18), base_y - _s(18), -30, glow_color)

		2:  # Mid swing
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x - _s(12), base_y - _s(24), 45, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x - _s(12), base_y - _s(24), 45, glow_color)

		3:  # Full swing (sword forward)
			_draw_hero_body_enhanced(img, center_x, base_y, _s(5), color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x - _s(18), base_y - _s(12), 90, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x - _s(18), base_y - _s(12), 90, glow_color)

		4:  # Defend (shield up)
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_shield_enhanced(img, center_x - _s(12), base_y - _s(18), color_metal, color_metal_light, color_armor, color_armor_dark, color_outline)

		5:  # Hit (recoiling)
			_draw_hero_body_enhanced(img, center_x, base_y, _s(-10), color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)

		6:  # Victory pose (sword raised)
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x, base_y - _s(36), -45, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x, base_y - _s(36), -45, glow_color)

		7:  # Defeat (collapsed)
			_draw_hero_body_enhanced(img, center_x, base_y + int(_sf(y_offset)), 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_hero_body_enhanced(img: Image, cx: int, cy: int, lean: int, armor: Color, armor_dark: Color, armor_mid: Color, armor_light: Color, armor_shine: Color, skin: Color, skin_dark: Color, hair: Color, outline: Color) -> void:
	"""Draw enhanced SNES-style hero body (knight/fighter)"""
	var s = img.get_width()

	# Head outline
	var head_x = cx + lean/4
	var head_y = cy - _s(28)
	var head_rx = _s(6)
	var head_ry = _s(7)

	for y in range(-head_ry - 1, head_ry + 2):
		for x in range(-head_rx - 1, head_rx + 2):
			var dist = sqrt(pow(float(x) / (head_rx + 1), 2) + pow(float(y) / (head_ry + 1), 2))
			if dist >= 0.85 and dist < 1.0:
				_safe_pixel(img, head_x + x, head_y + y, outline)

	# Hair (top of head)
	for y in range(-head_ry - _s(2), -head_ry/2):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y + head_ry) / (head_ry/2), 2))
			if dist < 1.2:
				_safe_pixel(img, head_x + x, head_y + y, hair)

	# Head fill (face)
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = skin
				if y < -head_ry * 0.3:
					continue  # Hair covers this
				elif x < -head_rx * 0.4:
					color = skin_dark
				_safe_pixel(img, head_x + x, head_y + y, color)

	# Eyes
	for eye_side in [-1, 1]:
		var eye_x = head_x + eye_side * _s(3)
		var eye_y = head_y
		_safe_pixel(img, eye_x, eye_y, Color(0.3, 0.4, 0.6))
		_safe_pixel(img, eye_x, eye_y - 1, Color(0.2, 0.2, 0.3))

	# Helmet (visor piece)
	for hx in range(-head_rx, head_rx + 1):
		_safe_pixel(img, head_x + hx, head_y - _s(4), armor_light)

	# Body armor outline
	var body_width = _s(9)
	var body_height = _s(18)

	for y in range(-body_height/2, body_height/2 + 2):
		var width = body_width - abs(y) / 5
		for x in range(-width - 1, width + 2):
			var inside = abs(x) - width
			if inside >= 0 and inside < 2:
				_safe_pixel(img, cx + x + lean/4, cy + y - _s(8), outline)

	# Body armor fill
	for y in range(-body_height/2, body_height/2 + 1):
		var width = body_width - abs(y) / 5
		for x in range(-width, width + 1):
			var color = armor
			if y < -body_height/4:
				color = armor_light
			elif y > body_height/4:
				color = armor_dark
			if abs(x) > width * 0.6:
				color = armor_mid
			_safe_pixel(img, cx + x + lean/4, cy + y - _s(8), color)

	# Armor shine spot
	_safe_pixel(img, cx - _s(3) + lean/4, cy - _s(12), armor_shine)
	_safe_pixel(img, cx - _s(2) + lean/4, cy - _s(12), armor_shine)

	# Shoulder pauldrons
	for shoulder_side in [-1, 1]:
		var shoulder_x = cx + shoulder_side * _s(10) + lean/5
		var shoulder_y = cy - _s(14)
		for sy in range(_s(-4), _s(5)):
			var sw = _s(5) - abs(sy) / 2
			for sx in range(-sw, sw + 1):
				var color = armor_mid if sy > 0 else armor_light
				_safe_pixel(img, shoulder_x + sx, shoulder_y + sy, color)

	# Legs
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * _s(4) + lean/6
		for y in range(_s(8), _s(18)):
			var leg_width = _s(4) - (y - _s(8)) / 10
			for lx in range(-leg_width, leg_width + 1):
				var color = armor_mid if lx * leg_side < 0 else armor_dark
				_safe_pixel(img, leg_x + lx, cy + y, color)


static func _draw_sword_enhanced(img: Image, cx: int, cy: int, angle: int, metal: Color, metal_light: Color, metal_dark: Color, outline: Color) -> void:
	"""Draw enhanced sword with more detail"""
	var length = _s(24)
	var blade_width = _s(2)
	var angle_rad = deg_to_rad(angle)

	# Blade outline
	for i in range(-1, length + 1):
		for w in range(-blade_width - 1, blade_width + 2):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			if abs(w) == blade_width + 1 or i == -1 or i == length:
				_safe_pixel(img, px, py, outline)

	# Blade fill with gradient
	for i in range(length):
		for w in range(-blade_width, blade_width + 1):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			var color = metal
			if i < _s(4):
				color = metal_light  # Hilt area bright
			elif w < 0:
				color = metal_dark  # Edge shadow
			if i > length - _s(4):
				color = metal_light  # Tip shine
			_safe_pixel(img, px, py, color)

	# Crossguard
	var guard_x = int(cx + cos(angle_rad) * _sf(3))
	var guard_y = int(cy + sin(angle_rad) * _sf(3))
	for gx in range(_s(-4), _s(5)):
		for gy in range(_s(-1), _s(2)):
			var px = guard_x + int(sin(angle_rad) * gx) + int(cos(angle_rad) * gy)
			var py = guard_y - int(cos(angle_rad) * gx) + int(sin(angle_rad) * gy)
			_safe_pixel(img, px, py, Color(0.6, 0.5, 0.3))


static func _draw_weapon_glow(img: Image, cx: int, cy: int, angle: int, glow_color: Color) -> void:
	"""Draw glowing aura around weapon (for magical weapons)"""
	var length = _s(24)
	var angle_rad = deg_to_rad(angle)

	# Draw glow particles along blade
	for i in range(0, length, _s(4)):
		var base_x = int(cx + cos(angle_rad) * i)
		var base_y = int(cy + sin(angle_rad) * i)

		# Draw soft glow around each point
		for gy in range(-_s(4), _s(5)):
			for gx in range(-_s(4), _s(5)):
				var dist = sqrt(gx * gx + gy * gy)
				if dist < _sf(4):
					var px = base_x + gx
					var py = base_y + gy
					if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
						var alpha = (1.0 - dist / _sf(4)) * 0.4
						var color = glow_color
						color.a = alpha
						var existing = img.get_pixel(px, py)
						if existing.a > 0:
							# Blend with additive-style mixing
							var blended = Color(
								min(1.0, existing.r + color.r * alpha),
								min(1.0, existing.g + color.g * alpha),
								min(1.0, existing.b + color.b * alpha),
								existing.a
							)
							img.set_pixel(px, py, blended)
						else:
							img.set_pixel(px, py, color)


static func _draw_shield_enhanced(img: Image, cx: int, cy: int, metal: Color, metal_light: Color, accent: Color, accent_dark: Color, outline: Color) -> void:
	"""Draw enhanced shield with more detail"""
	var shield_rx = _s(8)
	var shield_ry = _s(10)

	# Shield outline
	for y in range(-shield_ry - 1, shield_ry + 2):
		for x in range(-shield_rx - 1, shield_rx + 2):
			var dist = sqrt(pow(float(x) / (shield_rx + 1), 2) + pow(float(y) / (shield_ry + 1), 2))
			if dist >= 0.9 and dist < 1.0:
				_safe_pixel(img, cx + x, cy + y, outline)

	# Shield fill
	for y in range(-shield_ry, shield_ry + 1):
		for x in range(-shield_rx, shield_rx + 1):
			var dist = sqrt(pow(float(x) / shield_rx, 2) + pow(float(y) / shield_ry, 2))
			if dist < 1.0:
				var color = metal
				if y < -shield_ry * 0.3:
					color = metal_light
				elif abs(x) < shield_rx * 0.3:
					color = accent  # Center stripe
				_safe_pixel(img, cx + x, cy + y, color)

	# Shield emblem
	for ey in range(_s(-3), _s(4)):
		for ex in range(_s(-2), _s(3)):
			if abs(ex) + abs(ey) <= _s(3):
				_safe_pixel(img, cx + ex, cy + ey, accent_dark)


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
	"""Create a single slime sprite frame (SNES-style blob with more detail)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-style color palette for slime (16 colors max)
	var color_slime = Color(0.3, 0.8, 0.3)           # Green slime base
	var color_slime_dark = Color(0.15, 0.4, 0.15)    # Deep shadow
	var color_slime_mid = Color(0.25, 0.65, 0.25)    # Mid shadow
	var color_slime_light = Color(0.5, 0.95, 0.5)    # Highlight
	var color_slime_shine = Color(0.7, 1.0, 0.7)     # Bright shine
	var color_outline = Color(0.1, 0.25, 0.1, 0.9)   # Dark outline
	var color_core = Color(0.2, 0.6, 0.9, 0.4)       # Inner glow

	var center_x = size / 2
	var base_y = int(size * 0.65 + _sf(y_offset))
	var radius = _s(18)

	# Draw slime outline first (for SNES sprite definition)
	var outline_radius = radius + _s(2)
	for y in range(-int(outline_radius * scale_y), int(outline_radius * scale_y) + 1):
		for x in range(-outline_radius, outline_radius + 1):
			var dist = sqrt(pow(float(x) / outline_radius, 2) + pow(float(y) / (outline_radius * scale_y), 2))
			if dist >= 0.85 and dist < 1.0:
				var px = center_x + x
				var py = base_y + y
				_safe_pixel(img, px, py, color_outline)

	# Draw slime body with gradient shading
	for y in range(-int(radius * scale_y), int(radius * scale_y) + 1):
		for x in range(-radius, radius + 1):
			var dist = sqrt(pow(float(x) / radius, 2) + pow(float(y) / (radius * scale_y), 2))
			if dist < 1.0:
				var px = center_x + x
				var py = base_y + y

				# Multi-layer gradient shading
				var color = color_slime
				var v_pos = float(y) / (radius * scale_y)
				var h_pos = float(x) / radius

				if v_pos < -0.5:
					color = color_slime_light  # Top bright
				elif v_pos < -0.2:
					color = color_slime        # Top-mid
				elif v_pos > 0.5:
					color = color_slime_dark   # Bottom deep shadow
				elif v_pos > 0.2:
					color = color_slime_mid    # Bottom shadow

				# Add horizontal shading
				if h_pos < -0.5 and v_pos > -0.3:
					color = color.darkened(0.15)
				elif h_pos > 0.5 and v_pos < 0.3:
					color = color.lightened(0.1)

				_safe_pixel(img, px, py, color)

	# Draw inner glow/core for depth
	var core_radius = _s(8)
	for y in range(-int(core_radius * scale_y), int(core_radius * scale_y) + 1):
		for x in range(-core_radius, core_radius + 1):
			var dist = sqrt(pow(float(x) / core_radius, 2) + pow(float(y) / (core_radius * scale_y), 2))
			if dist < 0.7:
				var px = center_x + x + _s(2)  # Offset slightly
				var py = base_y + y - _s(2)
				var existing = img.get_pixel(px, py) if px >= 0 and px < size and py >= 0 and py < size else Color.TRANSPARENT
				if existing.a > 0:
					var blended = existing.blend(color_core)
					_safe_pixel(img, px, py, blended)

	# Draw eyes (larger, more expressive)
	var eye_y = base_y - _s(int(6 * scale_y))
	var eye_spacing = _s(8)
	var eye_size = _s(3)

	if pose != 4:  # No eyes when melting
		for eye_side in [-1, 1]:
			var eye_x = center_x + eye_side * eye_spacing
			# Eye white background
			for ey in range(-eye_size, eye_size + 1):
				for ex in range(-eye_size, eye_size + 1):
					if ex * ex + ey * ey <= eye_size * eye_size:
						_safe_pixel(img, eye_x + ex, eye_y + ey, Color(0.1, 0.1, 0.1))
			# Pupil
			var pupil_size = _s(1)
			for ey in range(-pupil_size, pupil_size + 1):
				for ex in range(-pupil_size, pupil_size + 1):
					_safe_pixel(img, eye_x + ex, eye_y + ey, Color.BLACK)
			# Eye highlight (catchlight)
			_safe_pixel(img, eye_x - _s(1), eye_y - _s(1), Color.WHITE)

	# Add multiple shine spots for SNES-style highlights
	if pose != 4:
		# Main shine
		var shine_y = base_y - _s(int(14 * scale_y))
		var shine_x = center_x - _s(6)
		for sy in range(_s(-4), _s(1)):
			for sx in range(_s(-3), _s(4)):
				var dist = sqrt(sx * sx + sy * sy)
				if dist < _sf(4):
					var alpha = 1.0 - dist / _sf(4)
					var shine_color = color_slime_shine
					shine_color.a = alpha * 0.8
					var px = shine_x + sx
					var py = shine_y + sy
					if px >= 0 and px < size and py >= 0 and py < size:
						var existing = img.get_pixel(px, py)
						if existing.a > 0:
							_safe_pixel(img, px, py, existing.blend(shine_color))

		# Secondary smaller shine
		var shine2_y = base_y - _s(int(8 * scale_y))
		var shine2_x = center_x + _s(8)
		for sy in range(_s(-2), _s(1)):
			for sx in range(_s(-2), _s(2)):
				if abs(sx) + abs(sy) < _s(3):
					_safe_pixel(img, shine2_x + sx, shine2_y + sy, color_slime_light)

	# Add subtle drip details at bottom
	if pose != 4 and scale_y >= 0.9:
		var drip_y = base_y + int(radius * scale_y) - _s(2)
		for drip in [_s(-8), _s(0), _s(6)]:
			var drip_x = center_x + drip
			for dy in range(_s(3)):
				var drip_alpha = 1.0 - float(dy) / _sf(3)
				var drip_color = color_slime_mid
				drip_color.a = drip_alpha * 0.7
				_safe_pixel(img, drip_x, drip_y + dy, drip_color)

	return ImageTexture.create_from_image(img)


static func create_mage_sprite_frames(robe_color: Color = Color(0.9, 0.9, 1.0), weapon_id: String = "") -> SpriteFrames:
	"""Create animated sprite frames for mage character (12-bit style)"""
	var frames = SpriteFrames.new()
	var weapon_visual = get_weapon_visual(weapon_id) if not weapon_id.is_empty() else _get_default_weapon_visual("staff")

	# Idle animation (2 frames, slight bob) - SLOWER
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_mage_frame(0, 0.0, robe_color, weapon_visual))
	frames.add_frame("idle", _create_mage_frame(0, -1.0, robe_color, weapon_visual))

	# Attack animation (staff thrust) - MUCH SLOWER
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_mage_frame(1, 0.0, robe_color, weapon_visual))
	frames.add_frame("attack", _create_mage_frame(2, 0.0, robe_color, weapon_visual))
	frames.add_frame("attack", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	# Defend animation - SLOWER
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 2.5)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_mage_frame(3, 0.0, robe_color, weapon_visual))
	frames.add_frame("defend", _create_mage_frame(3, 0.0, robe_color, weapon_visual))

	# Hit animation - MUCH SLOWER
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_mage_frame(4, 2.0, robe_color, weapon_visual))
	frames.add_frame("hit", _create_mage_frame(4, 1.0, robe_color, weapon_visual))
	frames.add_frame("hit", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	# Cast animation (magic) - SLOWER for dramatic effect
	frames.add_animation("cast")
	frames.set_animation_speed("cast", 2.5)
	frames.set_animation_loop("cast", false)
	frames.add_frame("cast", _create_mage_frame(5, 0.0, robe_color, weapon_visual))
	frames.add_frame("cast", _create_mage_frame(6, -2.0, robe_color, weapon_visual))
	frames.add_frame("cast", _create_mage_frame(5, 0.0, robe_color, weapon_visual))
	frames.add_frame("cast", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	# Item animation - SLOWER
	frames.add_animation("item")
	frames.set_animation_speed("item", 3.0)
	frames.set_animation_loop("item", false)
	frames.add_frame("item", _create_mage_frame(1, 0.0, robe_color, weapon_visual))
	frames.add_frame("item", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	# Victory animation - SLOWER
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_mage_frame(7, 0.0, robe_color, weapon_visual))
	frames.add_frame("victory", _create_mage_frame(7, -1.0, robe_color, weapon_visual))

	# Defeat animation - SLOWER
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_mage_frame(4, 0.0, robe_color, weapon_visual))
	frames.add_frame("defeat", _create_mage_frame(4, 2.0, robe_color, weapon_visual))
	frames.add_frame("defeat", _create_mage_frame(4, 4.0, robe_color, weapon_visual))

	return frames


static func _create_mage_frame(pose: int, y_offset: float, robe_color: Color, weapon_visual: Dictionary = {}) -> ImageTexture:
	"""Create a single mage sprite frame (12-bit style robed figure)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette
	var color_robe = robe_color
	var color_robe_dark = robe_color.darkened(0.3)
	var color_robe_light = robe_color.lightened(0.2)
	var color_skin = Color(0.9, 0.7, 0.6)

	# Get weapon colors from visual params or use defaults
	var color_staff = weapon_visual.get("wood", Color(0.5, 0.3, 0.2))
	var color_gem = weapon_visual.get("gem", Color(0.3, 0.8, 1.0))
	var weapon_glow = weapon_visual.get("glow", false)
	var glow_color = weapon_visual.get("glow_color", color_gem)

	var center_x = size / 2
	var base_y = int(size * 0.75 + y_offset)

	match pose:
		0:  # Idle stance
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 10, base_y - 10, 0, color_staff, color_gem)
			if weapon_glow:
				_draw_staff_glow(img, center_x + 10, base_y - 10, 0, glow_color)

		1:  # Staff forward
			_draw_mage_body(img, center_x, base_y, 5, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 6, base_y - 14, 20, color_staff, color_gem)
			if weapon_glow:
				_draw_staff_glow(img, center_x + 6, base_y - 14, 20, glow_color)

		2:  # Staff thrust
			_draw_mage_body(img, center_x, base_y, 10, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x - 4, base_y - 16, 60, color_staff, color_gem)
			if weapon_glow:
				_draw_staff_glow(img, center_x - 4, base_y - 16, 60, glow_color)

		3:  # Defend (staff across)
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x, base_y - 12, 90, color_staff, color_gem)
			if weapon_glow:
				_draw_staff_glow(img, center_x, base_y - 12, 90, glow_color)

		4:  # Hit (recoil)
			_draw_mage_body(img, center_x, base_y, -10, color_robe, color_robe_dark, color_robe_light, color_skin)

		5:  # Cast prep (staff raised)
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 8, base_y - 20, -20, color_staff, color_gem)
			if weapon_glow:
				_draw_staff_glow(img, center_x + 8, base_y - 20, -20, glow_color)

		6:  # Cast release (staff glowing)
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x + 8, base_y - 20, -20, color_staff, Color.WHITE)
			# Add magic glow effect
			_draw_magic_glow(img, center_x, base_y - 30, color_gem)

		7:  # Victory pose
			_draw_mage_body(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_light, color_skin)
			_draw_staff(img, center_x, base_y - 28, -45, color_staff, color_gem)
			if weapon_glow:
				_draw_staff_glow(img, center_x, base_y - 28, -45, glow_color)

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


static func _draw_staff_glow(img: Image, cx: int, cy: int, angle: int, glow_color: Color) -> void:
	"""Draw glowing aura around staff gem (for magical staves)"""
	var length = 24
	var angle_rad = deg_to_rad(angle)

	# Draw glow around gem at top of staff
	var gem_x = int(cx + cos(angle_rad) * (length - 2))
	var gem_y = int(cy + sin(angle_rad) * (length - 2))

	# Draw soft glow around gem
	for gy in range(-_s(5), _s(6)):
		for gx in range(-_s(5), _s(6)):
			var dist = sqrt(gx * gx + gy * gy)
			if dist < _sf(5):
				var px = gem_x + gx
				var py = gem_y + gy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					var alpha = (1.0 - dist / _sf(5)) * 0.5
					var color = glow_color
					color.a = alpha
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
						# Blend with additive-style mixing
						var blended = Color(
							min(1.0, existing.r + color.r * alpha),
							min(1.0, existing.g + color.g * alpha),
							min(1.0, existing.b + color.b * alpha),
							existing.a
						)
						img.set_pixel(px, py, blended)
					else:
						img.set_pixel(px, py, color)


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


static func create_thief_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	"""Create animated sprite frames for thief character (12-bit style)"""
	var frames = SpriteFrames.new()
	var weapon_visual = get_weapon_visual(weapon_id) if not weapon_id.is_empty() else _get_default_weapon_visual("dagger")

	# Idle animation (2 frames, slight bob) - SLOWER
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_thief_frame(0, 0.0, weapon_visual))
	frames.add_frame("idle", _create_thief_frame(0, -1.0, weapon_visual))

	# Attack animation (quick slash) - SLOWER but still quick for thief
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_thief_frame(1, 0.0, weapon_visual))
	frames.add_frame("attack", _create_thief_frame(2, -2.0, weapon_visual))
	frames.add_frame("attack", _create_thief_frame(3, 0.0, weapon_visual))
	frames.add_frame("attack", _create_thief_frame(0, 0.0, weapon_visual))

	# Defend animation - SLOWER
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 2.5)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_thief_frame(4, 0.0, weapon_visual))
	frames.add_frame("defend", _create_thief_frame(4, 0.0, weapon_visual))

	# Hit animation - SLOWER
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_thief_frame(5, 2.0, weapon_visual))
	frames.add_frame("hit", _create_thief_frame(5, 1.0, weapon_visual))
	frames.add_frame("hit", _create_thief_frame(0, 0.0, weapon_visual))

	# Cast animation (use item/throw) - SLOWER
	frames.add_animation("cast")
	frames.set_animation_speed("cast", 3.0)
	frames.set_animation_loop("cast", false)
	frames.add_frame("cast", _create_thief_frame(6, 0.0, weapon_visual))
	frames.add_frame("cast", _create_thief_frame(6, -1.0, weapon_visual))
	frames.add_frame("cast", _create_thief_frame(0, 0.0, weapon_visual))

	# Item animation - SLOWER
	frames.add_animation("item")
	frames.set_animation_speed("item", 3.0)
	frames.set_animation_loop("item", false)
	frames.add_frame("item", _create_thief_frame(6, 0.0, weapon_visual))
	frames.add_frame("item", _create_thief_frame(0, 0.0, weapon_visual))

	# Victory animation - SLOWER
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_thief_frame(7, 0.0, weapon_visual))
	frames.add_frame("victory", _create_thief_frame(7, -1.0, weapon_visual))

	# Defeat animation - SLOWER
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_thief_frame(5, 0.0, weapon_visual))
	frames.add_frame("defeat", _create_thief_frame(5, 2.0, weapon_visual))
	frames.add_frame("defeat", _create_thief_frame(5, 4.0, weapon_visual))

	return frames


static func _create_thief_frame(pose: int, y_offset: float, weapon_visual: Dictionary = {}) -> ImageTexture:
	"""Create a single thief sprite frame (12-bit style nimble rogue)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Color palette for thief
	var color_cloak = Color(0.3, 0.25, 0.4)      # Dark purple cloak
	var color_cloak_dark = Color(0.2, 0.15, 0.3)
	var color_cloak_light = Color(0.4, 0.35, 0.5)
	var color_skin = Color(0.9, 0.7, 0.6)

	# Get weapon colors from visual params or use defaults
	var color_dagger = weapon_visual.get("blade", Color(0.8, 0.8, 0.9))
	var color_dagger_light = weapon_visual.get("blade_light", Color(1.0, 1.0, 1.0))

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
	var size = SPRITE_SIZE
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
	var size = SPRITE_SIZE
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
	var size = SPRITE_SIZE
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
	var size = SPRITE_SIZE
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
	var size = SPRITE_SIZE
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
	var size = SPRITE_SIZE
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
	var size = SPRITE_SIZE
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
	"""Create a single goblin sprite frame (SNES-style with more detail)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-style color palette for goblin (16 colors)
	var color_skin = Color(0.45, 0.55, 0.3)         # Green skin base
	var color_skin_dark = Color(0.25, 0.35, 0.15)   # Deep shadow
	var color_skin_mid = Color(0.35, 0.45, 0.22)    # Mid shadow
	var color_skin_light = Color(0.58, 0.68, 0.42)  # Highlight
	var color_cloth = Color(0.5, 0.35, 0.25)        # Brown cloth
	var color_cloth_dark = Color(0.35, 0.22, 0.15)  # Cloth shadow
	var color_eye = Color(0.95, 0.75, 0.1)          # Yellow eyes
	var color_eye_glow = Color(1.0, 0.9, 0.3)       # Eye highlight
	var color_club = Color(0.45, 0.32, 0.2)         # Brown club
	var color_club_dark = Color(0.3, 0.2, 0.12)     # Club shadow
	var color_outline = Color(0.15, 0.2, 0.1)       # Dark outline

	var center_x = size / 2
	var base_y = int(size * 0.72 + _sf(y_offset))

	_draw_goblin_body_enhanced(img, center_x, base_y, pose, color_skin, color_skin_dark, color_skin_mid, color_skin_light, color_cloth, color_cloth_dark, color_eye, color_eye_glow, color_club, color_club_dark, color_outline)

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


static func _draw_goblin_body_enhanced(img: Image, cx: int, cy: int, pose: int, skin: Color, skin_dark: Color, skin_mid: Color, skin_light: Color, cloth: Color, cloth_dark: Color, eye: Color, eye_glow: Color, club: Color, club_dark: Color, outline: Color) -> void:
	"""Draw enhanced SNES-style goblin body with more detail"""
	var s = img.get_width()

	var lean = 0
	var club_angle = 20
	match pose:
		1: lean = _s(-5); club_angle = -40
		2: lean = _s(8); club_angle = 60
		3: lean = _s(5); club_angle = 90
		4: lean = _s(-12)
		5: lean = _s(-20)
		6: lean = _s(-30)

	if pose == 6:
		# Fallen goblin - draw pile
		for y in range(_s(-6), _s(6)):
			for x in range(_s(-15), _s(15)):
				var dist = sqrt(pow(float(x) / _sf(15), 2) + pow(float(y) / _sf(4), 2))
				if dist < 1.0:
					var px = cx + x
					var py = cy + y + _s(8)
					var color = skin_dark if dist > 0.6 else skin_mid
					_safe_pixel(img, px, py, color)
		return

	# Club (drawn first, behind in some poses)
	if pose != 5 and pose != 6:
		var club_length = _s(20)
		var club_rad = deg_to_rad(club_angle)
		var club_x = cx + _s(12) + lean/4
		var club_y = cy - _s(12)
		var club_thickness = _s(3)

		# Draw club with thickness and shading
		for i in range(club_length):
			var base_x = club_x + int(cos(club_rad) * i)
			var base_y = club_y + int(sin(club_rad) * i)
			var thickness = club_thickness + (1 if i > club_length * 0.7 else 0)  # Wider at end

			for t in range(-thickness, thickness + 1):
				var px = base_x + int(sin(club_rad) * t)
				var py = base_y - int(cos(club_rad) * t)
				var color = club if t > -thickness/2 else club_dark
				_safe_pixel(img, px, py, color)

		# Club knob at end
		var knob_x = club_x + int(cos(club_rad) * club_length)
		var knob_y = club_y + int(sin(club_rad) * club_length)
		for ky in range(_s(-4), _s(5)):
			for kx in range(_s(-4), _s(5)):
				if kx * kx + ky * ky <= _s(4) * _s(4):
					var color = club if ky < 0 else club_dark
					_safe_pixel(img, knob_x + kx, knob_y + ky, color)

	# Head (large relative to body) - draw outline first
	var head_x = cx + lean/5
	var head_y = cy - _s(24)
	var head_rx = _s(10)
	var head_ry = _s(12)

	# Head outline
	for y in range(-head_ry - 2, head_ry + 3):
		for x in range(-head_rx - 2, head_rx + 3):
			var dist = sqrt(pow(float(x) / (head_rx + 1), 2) + pow(float(y + _s(3)) / (head_ry + 1), 2))
			if dist >= 0.9 and dist < 1.1:
				_safe_pixel(img, head_x + x, head_y + y, outline)

	# Head fill
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y + _s(3)) / head_ry, 2))
			if dist < 1.0:
				var color = skin
				if y < -head_ry * 0.4:
					color = skin_light
				elif y > head_ry * 0.4:
					color = skin_mid
				elif x < -head_rx * 0.4:
					color = skin_mid
				_safe_pixel(img, head_x + x, head_y + y, color)

	# Pointy ears (larger, more detailed)
	for ear_side in [-1, 1]:
		var ear_x = head_x + ear_side * _s(10)
		var ear_y = head_y - _s(6)
		# Ear triangle
		for ey in range(_s(-6), _s(2)):
			var ear_width = _s(3) - abs(ey) / 2
			for ex in range(-ear_width, ear_width + 1):
				var px = ear_x + ex * ear_side
				var py = ear_y + ey
				var color = skin if ex * ear_side > 0 else skin_dark
				_safe_pixel(img, px, py, color)
		# Ear outline
		for ey in range(_s(-6), _s(2)):
			_safe_pixel(img, ear_x + ((_s(3) - abs(ey) / 2) * ear_side), ear_y + ey, outline)

	# Large warty nose
	var nose_x = head_x - _s(4)
	var nose_y = head_y + _s(2)
	for ny in range(_s(-3), _s(4)):
		for nx in range(_s(-3), _s(2)):
			if nx * nx + ny * ny <= _s(3) * _s(3):
				var color = skin_dark if nx < 0 else skin_mid
				_safe_pixel(img, nose_x + nx, nose_y + ny, color)
	# Nose highlight
	_safe_pixel(img, nose_x + _s(1), nose_y - _s(1), skin)

	# Eyes (larger, meaner looking)
	for eye_side in [-1, 1]:
		var eye_x = head_x + eye_side * _s(4)
		var eye_y = head_y - _s(4)
		var eye_rx = _s(3)
		var eye_ry = _s(2)

		# Eye shape (angular, menacing)
		for ey in range(-eye_ry, eye_ry + 1):
			for ex in range(-eye_rx, eye_rx + 1):
				if abs(ex) + abs(ey) <= eye_rx + 1:
					_safe_pixel(img, eye_x + ex, eye_y + ey, eye)
		# Pupil (slit)
		for ey in range(_s(-1), _s(2)):
			_safe_pixel(img, eye_x, eye_y + ey, Color.BLACK)
		# Eye glint
		_safe_pixel(img, eye_x - _s(1), eye_y - _s(1), eye_glow)

	# Mouth/fangs
	var mouth_y = head_y + _s(8)
	for mx in range(_s(-4), _s(5)):
		_safe_pixel(img, head_x + mx, mouth_y, skin_dark)
	# Fangs
	for fang_x in [_s(-3), _s(3)]:
		_safe_pixel(img, head_x + fang_x, mouth_y + _s(1), Color(0.9, 0.9, 0.85))
		_safe_pixel(img, head_x + fang_x, mouth_y + _s(2), Color(0.85, 0.85, 0.8))

	# Body (small, hunched) - with more detail
	var body_width = _s(8)
	var body_height = _s(16)

	# Body outline
	for y in range(-body_height/2, body_height/2 + 1):
		var width = body_width - abs(y) / 3
		for x in range(-width - 1, width + 2):
			var px = cx + x + lean/4
			var py = cy + y
			var inside_dist = abs(x) - width
			if inside_dist >= 0 and inside_dist < _s(2):
				_safe_pixel(img, px, py, outline)

	# Body fill
	for y in range(-body_height/2, body_height/2 + 1):
		var width = body_width - abs(y) / 3
		for x in range(-width, width + 1):
			var px = cx + x + lean/4
			var py = cy + y
			var color = cloth
			if x < -width/2:
				color = cloth_dark
			elif y > body_height/4:
				color = cloth_dark
			_safe_pixel(img, px, py, color)

	# Belt detail
	var belt_y = cy + _s(2)
	for bx in range(-body_width + 1, body_width):
		_safe_pixel(img, cx + bx + lean/4, belt_y, skin_dark)
		_safe_pixel(img, cx + bx + lean/4, belt_y + _s(1), skin_mid)

	# Legs (with more shape)
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * _s(4) + lean/6
		for y in range(_s(6), _s(16)):
			var leg_width = _s(3) - (y - _s(6)) / 8
			for lx in range(-leg_width, leg_width + 1):
				var px = leg_x + lx
				var py = cy + y
				var color = skin_mid if lx * leg_side < 0 else skin_dark
				_safe_pixel(img, px, py, color)
		# Feet
		var foot_y = cy + _s(15)
		for fx in range(_s(-4), _s(3)):
			_safe_pixel(img, leg_x + fx * leg_side, foot_y, skin_dark)


## =================
## SHADOW KNIGHT MINIBOSS SPRITE
## =================

static func create_shadow_knight_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for Shadow Knight miniboss (larger, more imposing)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, menacing stance)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_shadow_knight_frame(0, 0.0))
	frames.add_frame("idle", _create_shadow_knight_frame(0, -1.0))

	# Attack animation (5 frames, devastating sword slash)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.5)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_shadow_knight_frame(1, 0.0))   # Raise sword
	frames.add_frame("attack", _create_shadow_knight_frame(2, -2.0))  # Wind up
	frames.add_frame("attack", _create_shadow_knight_frame(3, 0.0))   # Slash down
	frames.add_frame("attack", _create_shadow_knight_frame(4, 1.0))   # Follow through
	frames.add_frame("attack", _create_shadow_knight_frame(0, 0.0))   # Return

	# Hit animation (3 frames, barely fazed)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_shadow_knight_frame(5, 1.0))
	frames.add_frame("hit", _create_shadow_knight_frame(5, 0.0))
	frames.add_frame("hit", _create_shadow_knight_frame(0, 0.0))

	# Defeat animation (4 frames, dramatic collapse)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_shadow_knight_frame(6, 0.0))
	frames.add_frame("defeat", _create_shadow_knight_frame(6, 2.0))
	frames.add_frame("defeat", _create_shadow_knight_frame(7, 4.0))
	frames.add_frame("defeat", _create_shadow_knight_frame(8, 8.0))

	return frames


static func _create_shadow_knight_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single Shadow Knight sprite frame (SNES-style dark knight boss)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Dark, menacing color palette
	var color_armor = Color(0.15, 0.12, 0.2)         # Dark purple-black armor
	var color_armor_dark = Color(0.08, 0.06, 0.12)   # Deep shadow
	var color_armor_mid = Color(0.2, 0.16, 0.28)     # Mid tone
	var color_armor_light = Color(0.35, 0.28, 0.45)  # Highlight
	var color_accent = Color(0.6, 0.1, 0.15)         # Blood red accents
	var color_accent_glow = Color(0.9, 0.2, 0.25)    # Glowing red
	var color_eye = Color(0.95, 0.15, 0.1)           # Burning red eyes
	var color_eye_glow = Color(1.0, 0.4, 0.2)        # Eye glow
	var color_blade = Color(0.2, 0.15, 0.25)         # Dark blade
	var color_blade_edge = Color(0.8, 0.1, 0.15)     # Red edge
	var color_cape = Color(0.1, 0.05, 0.12)          # Dark cape
	var color_outline = Color(0.05, 0.03, 0.08)      # Near-black outline

	var center_x = size / 2
	var base_y = int(size * 0.78 + _sf(y_offset))

	_draw_shadow_knight_body(img, center_x, base_y, pose, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_accent, color_accent_glow, color_eye, color_eye_glow, color_blade, color_blade_edge, color_cape, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_shadow_knight_body(img: Image, cx: int, cy: int, pose: int, armor: Color, armor_dark: Color, armor_mid: Color, armor_light: Color, accent: Color, accent_glow: Color, eye: Color, eye_glow: Color, blade: Color, blade_edge: Color, cape: Color, outline: Color) -> void:
	"""Draw Shadow Knight miniboss (imposing armored figure)"""
	var s = img.get_width()

	var lean = 0
	var sword_angle = -10
	var cape_flow = 0
	match pose:
		1: sword_angle = -60; lean = _s(-3)
		2: sword_angle = -120; lean = _s(-5)
		3: sword_angle = 45; lean = _s(8)
		4: sword_angle = 80; lean = _s(5)
		5: lean = _s(-8)
		6: lean = _s(-15)
		7: lean = _s(-25)
		8: lean = _s(-40)

	# Don't draw defeated poses normally
	if pose >= 7:
		# Collapsed knight
		for y in range(_s(-8), _s(8)):
			for x in range(_s(-20), _s(20)):
				var dist = sqrt(pow(float(x) / _sf(20), 2) + pow(float(y) / _sf(6), 2))
				if dist < 1.0:
					var color = armor_dark if dist > 0.6 else armor_mid
					_safe_pixel(img, cx + x, cy + y + _s(10), color)
		return

	# Cape (drawn first, behind everything)
	var cape_width = _s(18)
	var cape_height = _s(35)
	var cape_x = cx + _s(5) + lean/3
	var cape_y = cy - _s(25)

	for y in range(cape_height):
		var wave = int(sin(y * 0.15 + cape_flow) * _sf(3))
		var width = cape_width - y / 4
		for x in range(-width, width + 1):
			var px = cape_x + x + wave
			var py = cape_y + y
			var color = cape if x > -width/2 else armor_dark
			# Add some fabric folds
			if abs(x) > width * 0.6:
				color = armor_dark
			_safe_pixel(img, px, py, color)

	# Greatsword (large two-handed sword)
	if pose < 6:
		var sword_length = _s(40)
		var sword_width = _s(4)
		var sword_rad = deg_to_rad(sword_angle)
		var sword_x = cx - _s(8) + lean/3
		var sword_y = cy - _s(15)

		# Blade
		for i in range(sword_length):
			var blade_width = sword_width if i < sword_length * 0.9 else sword_width - (i - sword_length * 0.9)
			for w in range(-int(blade_width), int(blade_width) + 1):
				var px = sword_x + int(cos(sword_rad) * i) + int(sin(sword_rad) * w)
				var py = sword_y + int(sin(sword_rad) * i) - int(cos(sword_rad) * w)
				var color = blade
				if abs(w) >= blade_width - 1:
					color = blade_edge  # Red edge
				elif w < 0:
					color = armor_dark
				_safe_pixel(img, px, py, color)

		# Crossguard
		var guard_x = sword_x + int(cos(sword_rad) * _sf(5))
		var guard_y = sword_y + int(sin(sword_rad) * _sf(5))
		for gx in range(_s(-8), _s(9)):
			for gy in range(_s(-2), _s(3)):
				_safe_pixel(img, guard_x + gx, guard_y + gy, accent)

	# Helmet (horned, menacing)
	var helm_x = cx + lean/4
	var helm_y = cy - _s(32)
	var helm_rx = _s(8)
	var helm_ry = _s(10)

	# Helmet outline
	for y in range(-helm_ry - 1, helm_ry + 2):
		for x in range(-helm_rx - 1, helm_rx + 2):
			var dist = sqrt(pow(float(x) / (helm_rx + 1), 2) + pow(float(y) / (helm_ry + 1), 2))
			if dist >= 0.85 and dist < 1.0:
				_safe_pixel(img, helm_x + x, helm_y + y, outline)

	# Helmet fill
	for y in range(-helm_ry, helm_ry + 1):
		for x in range(-helm_rx, helm_rx + 1):
			var dist = sqrt(pow(float(x) / helm_rx, 2) + pow(float(y) / helm_ry, 2))
			if dist < 1.0:
				var color = armor
				if y < -helm_ry * 0.3:
					color = armor_light
				elif y > helm_ry * 0.3:
					color = armor_dark
				_safe_pixel(img, helm_x + x, helm_y + y, color)

	# Helmet horns
	for horn_side in [-1, 1]:
		var horn_x = helm_x + horn_side * _s(7)
		var horn_y = helm_y - _s(6)
		for hy in range(_s(-12), _s(1)):
			var horn_width = _s(3) - abs(hy) / 5
			for hx in range(-horn_width, horn_width + 1):
				var px = horn_x + hx + horn_side * abs(hy) / 4
				var py = horn_y + hy
				var color = armor_mid if hx * horn_side > 0 else armor_dark
				_safe_pixel(img, px, py, color)
			# Horn tip accent
			if hy < _s(-8):
				_safe_pixel(img, horn_x + horn_side * abs(hy) / 4, horn_y + hy, accent)

	# Visor slit with glowing eyes
	var visor_y = helm_y + _s(2)
	for vx in range(_s(-5), _s(6)):
		_safe_pixel(img, helm_x + vx, visor_y, armor_dark)
		_safe_pixel(img, helm_x + vx, visor_y + _s(1), armor_dark)
	# Glowing eyes behind visor
	for eye_side in [-1, 1]:
		var eye_x_pos = helm_x + eye_side * _s(3)
		_safe_pixel(img, eye_x_pos, visor_y, eye)
		_safe_pixel(img, eye_x_pos + eye_side, visor_y, eye_glow)
		# Eye glow effect
		for glow_r in range(1, _s(3)):
			var glow_color = eye_glow
			glow_color.a = 0.3 / glow_r
			for gy in range(-glow_r, glow_r + 1):
				for gx in range(-glow_r, glow_r + 1):
					if gx * gx + gy * gy <= glow_r * glow_r:
						var px = eye_x_pos + gx
						var py = visor_y + gy
						if px >= 0 and px < s and py >= 0 and py < s:
							var existing = img.get_pixel(px, py)
							if existing.a > 0:
								_safe_pixel(img, px, py, existing.blend(glow_color))

	# Armored body (bulky pauldrons)
	var body_x = cx + lean/3
	var body_y = cy

	# Pauldrons (shoulder armor)
	for pauldron_side in [-1, 1]:
		var pauL_x = body_x + pauldron_side * _s(14)
		var pauL_y = body_y - _s(20)
		for py in range(_s(-6), _s(8)):
			var pw = _s(8) - abs(py) / 2
			for px in range(-pw, pw + 1):
				var color = armor_mid if py < 0 else armor_dark
				if px * pauldron_side > pw/2:
					color = armor_light if py < 0 else armor
				_safe_pixel(img, pauL_x + px, pauL_y + py, color)
		# Spike on pauldron
		for spike_y in range(_s(-10), _s(-4)):
			_safe_pixel(img, pauL_x, pauL_y + spike_y, accent)

	# Chest armor
	var chest_width = _s(12)
	var chest_height = _s(20)
	for y in range(-chest_height/2, chest_height/2 + 1):
		var width = chest_width - abs(y) / 4
		for x in range(-width, width + 1):
			var color = armor
			if y < -chest_height/4:
				color = armor_light
			elif y > chest_height/4:
				color = armor_dark
			if abs(x) > width * 0.7:
				color = armor_mid
			_safe_pixel(img, body_x + x, body_y + y - _s(8), color)

	# Red accent on chest (evil emblem)
	var emblem_y = body_y - _s(8)
	for ey in range(_s(-4), _s(5)):
		for ex in range(_s(-3), _s(4)):
			if abs(ex) + abs(ey) <= _s(4):
				_safe_pixel(img, body_x + ex, emblem_y + ey, accent)
	# Inner emblem glow
	_safe_pixel(img, body_x, emblem_y, accent_glow)

	# Armored legs
	for leg_side in [-1, 1]:
		var leg_x = body_x + leg_side * _s(5)
		for y in range(_s(10), _s(25)):
			var leg_width = _s(5) - (y - _s(10)) / 8
			for lx in range(-leg_width, leg_width + 1):
				var color = armor_mid if lx * leg_side < 0 else armor_dark
				_safe_pixel(img, leg_x + lx, cy + y, color)
		# Armored boots
		var boot_y = cy + _s(24)
		for bx in range(_s(-6), _s(5)):
			for by in range(_s(3)):
				var color = armor_dark if by > 0 else armor_mid
				_safe_pixel(img, leg_x + bx * leg_side, boot_y + by, color)


## =================
## CAVE TROLL MINIBOSS SPRITE
## =================

static func create_cave_troll_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for Cave Troll miniboss (massive brute)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, heavy breathing)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.2)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_cave_troll_frame(0, 0.0))
	frames.add_frame("idle", _create_cave_troll_frame(0, -1.5))

	# Attack animation (4 frames, ground pound)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_cave_troll_frame(1, -2.0))  # Raise arms
	frames.add_frame("attack", _create_cave_troll_frame(2, 0.0))   # Slam down
	frames.add_frame("attack", _create_cave_troll_frame(3, 2.0))   # Impact
	frames.add_frame("attack", _create_cave_troll_frame(0, 0.0))   # Return

	# Hit animation (3 frames, roar)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_cave_troll_frame(4, 1.0))
	frames.add_frame("hit", _create_cave_troll_frame(4, 0.0))
	frames.add_frame("hit", _create_cave_troll_frame(0, 0.0))

	# Defeat animation (3 frames, topple)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 1.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_cave_troll_frame(5, 0.0))
	frames.add_frame("defeat", _create_cave_troll_frame(5, 4.0))
	frames.add_frame("defeat", _create_cave_troll_frame(6, 10.0))

	return frames


static func _create_cave_troll_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single Cave Troll sprite frame (massive rocky brute)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Earthy, rocky color palette
	var color_skin = Color(0.4, 0.35, 0.3)          # Gray-brown stone skin
	var color_skin_dark = Color(0.25, 0.2, 0.18)    # Deep shadow
	var color_skin_mid = Color(0.32, 0.28, 0.24)    # Mid shadow
	var color_skin_light = Color(0.55, 0.48, 0.42)  # Highlight
	var color_moss = Color(0.3, 0.45, 0.25)         # Mossy patches
	var color_eye = Color(0.9, 0.6, 0.1)            # Orange eyes
	var color_teeth = Color(0.85, 0.82, 0.75)       # Yellowed teeth
	var color_outline = Color(0.15, 0.12, 0.1)      # Dark outline

	var center_x = size / 2
	var base_y = int(size * 0.82 + _sf(y_offset))

	_draw_cave_troll_body(img, center_x, base_y, pose, color_skin, color_skin_dark, color_skin_mid, color_skin_light, color_moss, color_eye, color_teeth, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_cave_troll_body(img: Image, cx: int, cy: int, pose: int, skin: Color, skin_dark: Color, skin_mid: Color, skin_light: Color, moss: Color, eye: Color, teeth: Color, outline: Color) -> void:
	"""Draw Cave Troll miniboss (massive hulking figure)"""
	var s = img.get_width()

	var lean = 0
	var arms_up = false
	var arms_down = false
	var mouth_open = false
	match pose:
		1: arms_up = true; lean = _s(-3)
		2: arms_down = true; lean = _s(5)
		3: arms_down = true; lean = _s(3); mouth_open = true
		4: mouth_open = true; lean = _s(-5)
		5: lean = _s(-12)
		6: lean = _s(-40)

	if pose == 6:
		# Fallen troll
		for y in range(_s(-12), _s(12)):
			for x in range(_s(-30), _s(30)):
				var dist = sqrt(pow(float(x) / _sf(30), 2) + pow(float(y) / _sf(10), 2))
				if dist < 1.0:
					var color = skin_dark if dist > 0.6 else skin_mid
					_safe_pixel(img, cx + x, cy + y + _s(8), color)
		return

	# Massive body (draw before head for proper layering)
	var body_width = _s(20)
	var body_height = _s(28)
	var body_x = cx + lean/4
	var body_y = cy - _s(5)

	# Body outline
	for y in range(-body_height/2, body_height/2 + 2):
		var width = body_width - abs(y) / 5
		for x in range(-width - 2, width + 3):
			var inside = abs(x) - width
			if inside >= 0 and inside < 3:
				_safe_pixel(img, body_x + x, body_y + y, outline)

	# Body fill
	for y in range(-body_height/2, body_height/2 + 1):
		var width = body_width - abs(y) / 5
		for x in range(-width, width + 1):
			var color = skin
			if y < -body_height/4:
				color = skin_light
			elif y > body_height/4:
				color = skin_dark
			if abs(x) > width * 0.6:
				color = skin_mid
			_safe_pixel(img, body_x + x, body_y + y, color)

	# Mossy patches on body
	var moss_spots = [[_s(-8), _s(-5)], [_s(10), _s(2)], [_s(-5), _s(8)], [_s(6), _s(-8)]]
	for spot in moss_spots:
		var spot_x = body_x + int(spot[0])
		var spot_y = body_y + int(spot[1])
		for my in range(_s(-3), _s(4)):
			for mx in range(_s(-4), _s(5)):
				if mx * mx + my * my <= _s(4) * _s(4):
					if img.get_pixel(spot_x + mx, spot_y + my).a > 0.5 if spot_x + mx >= 0 and spot_x + mx < s and spot_y + my >= 0 and spot_y + my < s else false:
						_safe_pixel(img, spot_x + mx, spot_y + my, moss)

	# Arms (massive club-like arms)
	for arm_side in [-1, 1]:
		var arm_x = body_x + arm_side * _s(18)
		var arm_y = body_y - _s(8)
		var arm_angle = -30 if not arms_up else -100
		if arms_down:
			arm_angle = 60

		var arm_length = _s(25)
		var arm_rad = deg_to_rad(arm_angle * arm_side)

		for i in range(arm_length):
			var arm_width = _s(6) - i / 8
			for w in range(-arm_width, arm_width + 1):
				var px = arm_x + int(cos(arm_rad) * i) + int(sin(arm_rad) * w) * arm_side
				var py = arm_y + int(sin(arm_rad) * i) - int(cos(arm_rad) * w)
				var color = skin_mid if w < 0 else skin_dark
				_safe_pixel(img, px, py, color)

		# Fist at end
		var fist_x = arm_x + int(cos(arm_rad) * arm_length)
		var fist_y = arm_y + int(sin(arm_rad) * arm_length)
		for fy in range(_s(-6), _s(7)):
			for fx in range(_s(-6), _s(7)):
				if fx * fx + fy * fy <= _s(6) * _s(6):
					var color = skin if fy < 0 else skin_dark
					_safe_pixel(img, fist_x + fx, fist_y + fy, color)

	# Head (small relative to body, brutish)
	var head_x = cx + lean/3
	var head_y = cy - _s(32)
	var head_rx = _s(10)
	var head_ry = _s(8)

	# Head outline
	for y in range(-head_ry - 1, head_ry + 2):
		for x in range(-head_rx - 1, head_rx + 2):
			var dist = sqrt(pow(float(x) / (head_rx + 1), 2) + pow(float(y) / (head_ry + 1), 2))
			if dist >= 0.85 and dist < 1.0:
				_safe_pixel(img, head_x + x, head_y + y, outline)

	# Head fill
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = skin
				if y < -head_ry * 0.3:
					color = skin_light
				elif y > head_ry * 0.3:
					color = skin_mid
				_safe_pixel(img, head_x + x, head_y + y, color)

	# Brow ridge
	var brow_y = head_y - _s(3)
	for bx in range(_s(-9), _s(10)):
		for by in range(_s(-2), _s(2)):
			_safe_pixel(img, head_x + bx, brow_y + by, skin_dark)

	# Small angry eyes under brow
	for eye_side in [-1, 1]:
		var eye_x = head_x + eye_side * _s(4)
		var eye_y = head_y
		for ey in range(_s(-2), _s(2)):
			for ex in range(_s(-2), _s(2)):
				if abs(ex) + abs(ey) <= _s(2):
					_safe_pixel(img, eye_x + ex, eye_y + ey, eye)
		_safe_pixel(img, eye_x, eye_y, Color.BLACK)

	# Wide mouth with tusks
	var mouth_y = head_y + _s(4)
	var mouth_width = _s(8)
	var mouth_height = _s(3) if not mouth_open else _s(6)

	for my in range(mouth_height):
		for mx in range(-mouth_width, mouth_width + 1):
			_safe_pixel(img, head_x + mx, mouth_y + my, skin_dark if not mouth_open else Color(0.2, 0.1, 0.1))

	# Tusks
	for tusk_side in [-1, 1]:
		var tusk_x = head_x + tusk_side * _s(6)
		var tusk_y = mouth_y + _s(1)
		for ty in range(_s(6)):
			var tw = _s(2) - ty / 4
			for tx in range(-tw, tw + 1):
				_safe_pixel(img, tusk_x + tx + tusk_side * ty / 3, tusk_y + ty, teeth)

	# Stumpy legs
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * _s(8) + lean/5
		for y in range(_s(18), _s(28)):
			var leg_width = _s(8) - (y - _s(18)) / 6
			for lx in range(-leg_width, leg_width + 1):
				var color = skin_mid if lx * leg_side < 0 else skin_dark
				_safe_pixel(img, leg_x + lx, cy + y, color)
		# Feet
		for fx in range(_s(-9), _s(6)):
			for fy in range(_s(4)):
				_safe_pixel(img, leg_x + fx * leg_side, cy + _s(27) + fy, skin_dark)


## =================
## CAVE RAT KING BOSS SPRITE
## =================

static func create_cave_rat_king_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for Cave Rat King boss (large rat with tiny crown)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, twitchy rat behavior)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_rat_king_frame(0, 0.0))
	frames.add_frame("idle", _create_rat_king_frame(0, -1.0))

	# Attack animation (5 frames, lunging bite)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_rat_king_frame(1, 0.0))   # Rear back
	frames.add_frame("attack", _create_rat_king_frame(2, -2.0))  # Crouch
	frames.add_frame("attack", _create_rat_king_frame(3, 0.0))   # Lunge forward
	frames.add_frame("attack", _create_rat_king_frame(4, 2.0))   # Bite
	frames.add_frame("attack", _create_rat_king_frame(0, 0.0))   # Return

	# Hit animation (3 frames)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_rat_king_frame(5, 2.0))
	frames.add_frame("hit", _create_rat_king_frame(5, 0.0))
	frames.add_frame("hit", _create_rat_king_frame(0, 0.0))

	# Defeat animation (4 frames, dramatic collapse with crown falling)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_rat_king_frame(6, 0.0))
	frames.add_frame("defeat", _create_rat_king_frame(6, 3.0))
	frames.add_frame("defeat", _create_rat_king_frame(7, 6.0))
	frames.add_frame("defeat", _create_rat_king_frame(8, 10.0))

	# Summon animation (calling rat minions)
	frames.add_animation("summon")
	frames.set_animation_speed("summon", 3.0)
	frames.set_animation_loop("summon", false)
	frames.add_frame("summon", _create_rat_king_frame(9, 0.0))   # Stand tall
	frames.add_frame("summon", _create_rat_king_frame(10, -2.0)) # Raise paws
	frames.add_frame("summon", _create_rat_king_frame(10, 0.0))  # Squeak command
	frames.add_frame("summon", _create_rat_king_frame(0, 0.0))   # Return

	return frames


static func _create_rat_king_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single Cave Rat King sprite frame"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Mangy rat color palette
	var color_fur = Color(0.35, 0.28, 0.22)          # Dirty brown fur
	var color_fur_dark = Color(0.22, 0.17, 0.13)     # Dark shadows
	var color_fur_mid = Color(0.42, 0.35, 0.28)      # Mid tone
	var color_fur_light = Color(0.55, 0.45, 0.38)    # Highlights
	var color_skin = Color(0.7, 0.55, 0.5)           # Pink skin (ears, tail, paws)
	var color_skin_dark = Color(0.55, 0.4, 0.38)     # Darker skin
	var color_eye = Color(0.9, 0.15, 0.1)            # Beady red eyes
	var color_eye_glow = Color(1.0, 0.3, 0.2)        # Eye shine
	var color_nose = Color(0.85, 0.5, 0.5)           # Pink nose
	var color_teeth = Color(0.95, 0.9, 0.7)          # Yellowed teeth
	var color_crown = Color(0.95, 0.8, 0.2)          # Gold crown
	var color_crown_dark = Color(0.7, 0.55, 0.1)     # Crown shadow
	var color_crown_gem = Color(0.8, 0.15, 0.2)      # Red gem
	var color_outline = Color(0.12, 0.08, 0.06)      # Dark outline

	var center_x = size / 2
	var base_y = int(size * 0.75 + _sf(y_offset))

	_draw_rat_king_body(img, center_x, base_y, pose, color_fur, color_fur_dark, color_fur_mid, color_fur_light, color_skin, color_skin_dark, color_eye, color_eye_glow, color_nose, color_teeth, color_crown, color_crown_dark, color_crown_gem, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_rat_king_body(img: Image, cx: int, cy: int, pose: int, fur: Color, fur_dark: Color, fur_mid: Color, fur_light: Color, skin: Color, skin_dark: Color, eye: Color, eye_glow: Color, nose: Color, teeth: Color, crown: Color, crown_dark: Color, crown_gem: Color, outline: Color) -> void:
	"""Draw Cave Rat King boss (giant mangy rat with crown)"""
	var s = img.get_width()

	var lean = 0
	var crouch = 0
	var mouth_open = false
	var tail_up = false
	var paws_up = false
	var crown_tilt = 0

	match pose:
		1: lean = _s(-5); tail_up = true          # Rear back
		2: crouch = _s(8); lean = _s(-3)          # Crouch
		3: lean = _s(12); mouth_open = true       # Lunge
		4: lean = _s(15); mouth_open = true       # Bite
		5: lean = _s(-10); crown_tilt = 15        # Hit
		6: lean = _s(-18); crown_tilt = 30        # Defeat start
		7: lean = _s(-35); crown_tilt = 60        # Falling
		8: lean = _s(-45); crown_tilt = 90        # Defeated
		9: tail_up = true                         # Stand tall
		10: paws_up = true; tail_up = true        # Summoning

	# Defeated pose - collapsed rat
	if pose >= 7:
		# Fallen rat body (side view, pathetic)
		for y in range(_s(-10), _s(10)):
			for x in range(_s(-25), _s(25)):
				var dist = sqrt(pow(float(x) / _sf(25), 2) + pow(float(y) / _sf(8), 2))
				if dist < 1.0:
					var color = fur_dark if dist > 0.6 else fur_mid
					_safe_pixel(img, cx + x, cy + y + _s(8), color)
		# Fallen crown nearby
		var crown_x = cx + _s(20)
		var crown_y = cy + _s(5)
		for cy2 in range(_s(-4), _s(2)):
			for cx2 in range(_s(-6), _s(7)):
				if cy2 < 0 and abs(cx2) < _s(5):
					_safe_pixel(img, crown_x + cx2, crown_y + cy2, crown)
		return

	# === TAIL (draw first, behind body) ===
	var tail_x = cx - _s(18) + lean/3
	var tail_y = cy + _s(5) + crouch/2
	var tail_length = _s(30)
	var tail_curve = 0.08 if not tail_up else -0.12

	for i in range(tail_length):
		var t = float(i) / tail_length
		var curve = sin(t * PI * 1.5) * _s(15) * tail_curve
		var tx = tail_x - int(cos(0.3) * i)
		var ty = tail_y + int(curve) - int(t * _s(8)) if tail_up else tail_y + int(curve)
		var thickness = _s(4) - int(t * _s(3))
		for tw in range(-thickness, thickness + 1):
			_safe_pixel(img, tx, ty + tw, skin if t > 0.3 else skin_dark)

	# === BODY (large, hunched rat body) ===
	var body_x = cx + lean/4
	var body_y = cy - _s(5) + crouch
	var body_rx = _s(18)
	var body_ry = _s(14)

	# Body outline
	for y in range(-body_ry - 2, body_ry + 3):
		for x in range(-body_rx - 2, body_rx + 3):
			var dist = sqrt(pow(float(x) / (body_rx + 2), 2) + pow(float(y) / (body_ry + 2), 2))
			if dist >= 0.9 and dist < 1.0:
				_safe_pixel(img, body_x + x, body_y + y, outline)

	# Body fill with fur texture
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var color = fur
				# Shading
				if y < -body_ry * 0.3:
					color = fur_light
				elif y > body_ry * 0.4:
					color = fur_dark
				if x < -body_rx * 0.5:
					color = fur_mid
				# Mangy patches
				if (x + y) % _s(8) < _s(2) and dist > 0.5:
					color = fur_dark
				_safe_pixel(img, body_x + x, body_y + y, color)

	# === HIND LEGS ===
	for leg_side in [-1, 1]:
		var leg_x = body_x + leg_side * _s(10) - _s(5)
		var leg_y = body_y + _s(10)
		# Thigh
		for ly in range(_s(12)):
			var lw = _s(6) - ly / 4
			for lx in range(-lw, lw + 1):
				_safe_pixel(img, leg_x + lx, leg_y + ly, fur_mid if lx * leg_side > 0 else fur_dark)
		# Paw
		for py in range(_s(4)):
			for px in range(_s(-5), _s(6)):
				_safe_pixel(img, leg_x + px, leg_y + _s(12) + py, skin_dark)

	# === FRONT PAWS ===
	var paw_y_offset = 0 if not paws_up else _s(-15)
	for paw_side in [-1, 1]:
		var paw_x = body_x + paw_side * _s(12) + lean/3
		var paw_y = body_y + _s(8) + paw_y_offset
		# Arm
		for ay in range(_s(10)):
			var aw = _s(4) - ay / 5
			for ax in range(-aw, aw + 1):
				_safe_pixel(img, paw_x + ax, paw_y + ay - _s(5), fur_mid)
		# Paw with claws
		for py in range(_s(5)):
			for px in range(_s(-4), _s(5)):
				_safe_pixel(img, paw_x + px, paw_y + _s(5) + py, skin)
		# Claws
		for claw in range(3):
			var claw_x = paw_x - _s(2) + claw * _s(2)
			for cl in range(_s(3)):
				_safe_pixel(img, claw_x, paw_y + _s(10) + cl, Color(0.3, 0.25, 0.2))

	# === HEAD ===
	var head_x = cx + _s(12) + lean/2
	var head_y = cy - _s(18) + crouch/2
	var head_rx = _s(12)
	var head_ry = _s(10)

	# Head outline
	for y in range(-head_ry - 1, head_ry + 2):
		for x in range(-head_rx - 1, head_rx + 2):
			var dist = sqrt(pow(float(x) / (head_rx + 1), 2) + pow(float(y) / (head_ry + 1), 2))
			if dist >= 0.9 and dist < 1.0:
				_safe_pixel(img, head_x + x, head_y + y, outline)

	# Head fill
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = fur
				if y < -head_ry * 0.3:
					color = fur_light
				elif x > head_rx * 0.3:
					color = fur_mid  # Snout area lighter
				_safe_pixel(img, head_x + x, head_y + y, color)

	# === EARS (large rat ears) ===
	for ear_side in [-1, 1]:
		var ear_x = head_x + ear_side * _s(8)
		var ear_y = head_y - _s(12)
		# Outer ear
		for ey in range(_s(10)):
			var ew = _s(5) - abs(ey - _s(5)) / 2
			for ex in range(-ew, ew + 1):
				_safe_pixel(img, ear_x + ex, ear_y + ey, skin_dark)
		# Inner ear (pink)
		for ey in range(_s(2), _s(8)):
			var ew = _s(3) - abs(ey - _s(5)) / 2
			for ex in range(-ew, ew + 1):
				_safe_pixel(img, ear_x + ex, ear_y + ey, skin)

	# === SNOUT ===
	var snout_x = head_x + _s(10)
	var snout_y = head_y + _s(2)
	for sy in range(_s(-4), _s(5)):
		for sx in range(_s(8)):
			var dist = sqrt(pow(float(sx) / _sf(8), 2) + pow(float(sy) / _sf(4), 2))
			if dist < 1.0:
				_safe_pixel(img, snout_x + sx, snout_y + sy, fur_light if sy < 0 else fur_mid)

	# Nose
	for ny in range(_s(-2), _s(3)):
		for nx in range(_s(-2), _s(3)):
			if nx * nx + ny * ny <= _s(2) * _s(2):
				_safe_pixel(img, snout_x + _s(7) + nx, snout_y + ny, nose)

	# Whiskers
	for whisker in range(3):
		var wy = snout_y - _s(2) + whisker * _s(3)
		for wx in range(_s(12)):
			_safe_pixel(img, snout_x + _s(5) + wx, wy + wx/8, Color(0.6, 0.55, 0.5))
			_safe_pixel(img, snout_x + _s(5) + wx, wy - wx/8, Color(0.6, 0.55, 0.5))

	# === EYES (beady, menacing) ===
	var eye_x = head_x + _s(4)
	var eye_y = head_y - _s(2)
	# Eye socket
	for ey in range(_s(-3), _s(4)):
		for ex in range(_s(-3), _s(4)):
			if ex * ex + ey * ey <= _s(3) * _s(3):
				_safe_pixel(img, eye_x + ex, eye_y + ey, fur_dark)
	# Eye
	for ey in range(_s(-2), _s(3)):
		for ex in range(_s(-2), _s(3)):
			if ex * ex + ey * ey <= _s(2) * _s(2):
				_safe_pixel(img, eye_x + ex, eye_y + ey, eye)
	# Eye shine
	_safe_pixel(img, eye_x - _s(1), eye_y - _s(1), eye_glow)

	# === MOUTH / TEETH ===
	if mouth_open:
		var mouth_x = snout_x + _s(4)
		var mouth_y = snout_y + _s(3)
		# Open mouth
		for my in range(_s(6)):
			for mx in range(_s(-4), _s(5)):
				_safe_pixel(img, mouth_x + mx, mouth_y + my, Color(0.3, 0.1, 0.1))
		# Teeth (prominent front teeth)
		for tooth_side in [-1, 1]:
			var tooth_x = mouth_x + tooth_side * _s(2)
			for ty in range(_s(5)):
				_safe_pixel(img, tooth_x, mouth_y + ty, teeth)
				_safe_pixel(img, tooth_x + tooth_side, mouth_y + ty, teeth)
	else:
		# Closed mouth with buck teeth showing
		var mouth_x = snout_x + _s(6)
		var mouth_y = snout_y + _s(4)
		for tooth_side in [-1, 1]:
			for ty in range(_s(3)):
				_safe_pixel(img, mouth_x + tooth_side, mouth_y + ty, teeth)

	# === CROWN (tiny, comically small, tilted) ===
	var crown_x = head_x - _s(2)
	var crown_y = head_y - _s(14)
	var crown_tilt_rad = deg_to_rad(crown_tilt)

	# Crown base
	for cby in range(_s(4)):
		for cbx in range(_s(-6), _s(7)):
			var rotated_x = int(cbx * cos(crown_tilt_rad) - cby * sin(crown_tilt_rad))
			var rotated_y = int(cbx * sin(crown_tilt_rad) + cby * cos(crown_tilt_rad))
			_safe_pixel(img, crown_x + rotated_x, crown_y + rotated_y, crown if cby < _s(2) else crown_dark)

	# Crown points (3 points)
	for point in range(3):
		var point_x = _s(-4) + point * _s(4)
		for py in range(_s(6)):
			var pw = _s(2) - py / 3
			for px in range(-pw, pw + 1):
				var rx = int((point_x + px) * cos(crown_tilt_rad) - (-py) * sin(crown_tilt_rad))
				var ry = int((point_x + px) * sin(crown_tilt_rad) + (-py) * cos(crown_tilt_rad))
				_safe_pixel(img, crown_x + rx, crown_y + ry, crown)

	# Crown gem (center)
	var gem_x = crown_x
	var gem_y = crown_y - _s(2)
	for gy in range(_s(-2), _s(2)):
		for gx in range(_s(-2), _s(2)):
			if abs(gx) + abs(gy) <= _s(2):
				_safe_pixel(img, gem_x + gx, gem_y + gy, crown_gem)


## =================
## CAVE RAT SPRITE (summoned minion)
## =================

static func create_cave_rat_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for Cave Rat (smaller rat minion)"""
	var frames = SpriteFrames.new()

	# Idle animation (2 frames, twitchy)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 3.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_cave_rat_frame(0, 0.0))
	frames.add_frame("idle", _create_cave_rat_frame(0, -1.0))

	# Attack animation (3 frames, quick bite)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_cave_rat_frame(1, 0.0))
	frames.add_frame("attack", _create_cave_rat_frame(2, 0.0))
	frames.add_frame("attack", _create_cave_rat_frame(0, 0.0))

	# Hit animation
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_cave_rat_frame(3, 1.0))
	frames.add_frame("hit", _create_cave_rat_frame(0, 0.0))

	# Defeat animation
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_cave_rat_frame(4, 2.0))
	frames.add_frame("defeat", _create_cave_rat_frame(5, 5.0))

	return frames


static func _create_cave_rat_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single Cave Rat sprite frame (small rat)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Rat colors
	var fur = Color(0.4, 0.32, 0.25)
	var fur_dark = Color(0.28, 0.2, 0.15)
	var fur_light = Color(0.52, 0.42, 0.35)
	var skin = Color(0.7, 0.55, 0.5)
	var eye = Color(0.85, 0.2, 0.15)
	var teeth = Color(0.9, 0.85, 0.7)

	var cx = size / 2
	var cy = int(size * 0.7 + y_offset)

	var lean = 0
	var mouth_open = false

	match pose:
		1: lean = -3  # Prep bite
		2: lean = 8; mouth_open = true  # Bite
		3: lean = -6  # Hit
		4: lean = -12  # Defeated start
		5: lean = -20  # Defeated

	# Defeated - collapsed rat
	if pose >= 4:
		for y in range(-4, 5):
			for x in range(-15, 16):
				var dist = sqrt(pow(float(x) / 15.0, 2) + pow(float(y) / 4.0, 2))
				if dist < 1.0:
					_safe_pixel(img, cx + x, cy + y + 5, fur_dark if dist > 0.5 else fur)
		return ImageTexture.create_from_image(img)

	# Tail
	var tail_x = cx - 12 + lean/4
	var tail_y = cy + 2
	for i in range(20):
		var t = float(i) / 20.0
		var ty = tail_y + int(sin(t * PI) * 6)
		var tx = tail_x - i
		var thickness = 2 - int(t * 1.5)
		for tw in range(-thickness, thickness + 1):
			_safe_pixel(img, tx, ty + tw, skin)

	# Body (small oval)
	for y in range(-8, 9):
		for x in range(-12, 13):
			var dist = sqrt(pow(float(x) / 12.0, 2) + pow(float(y) / 7.0, 2))
			if dist < 1.0:
				var color = fur_dark if dist > 0.7 else fur if dist > 0.4 else fur_light
				_safe_pixel(img, cx + x + lean/3, cy + y, color)

	# Head
	var head_x = cx + 8 + lean/2
	var head_y = cy - 2
	for y in range(-6, 7):
		for x in range(-6, 10):
			var dist = sqrt(pow(float(x) / 8.0, 2) + pow(float(y) / 5.0, 2))
			if dist < 1.0:
				_safe_pixel(img, head_x + x, head_y + y, fur if dist > 0.5 else fur_light)

	# Ears
	for ear_side in [-1, 1]:
		var ear_x = head_x - 2
		var ear_y = head_y - 6 + ear_side * 3
		for ey in range(-4, 2):
			for ex in range(-3, 4):
				if ex * ex / 9.0 + ey * ey / 12.0 < 1.0:
					_safe_pixel(img, ear_x + ex, ear_y + ey, skin if ex * ex + ey * ey < 4 else fur)

	# Eye
	_safe_pixel(img, head_x + 3, head_y - 1, eye)
	_safe_pixel(img, head_x + 4, head_y - 1, eye)
	_safe_pixel(img, head_x + 3, head_y, eye)

	# Nose
	_safe_pixel(img, head_x + 8, head_y + 1, skin)
	_safe_pixel(img, head_x + 9, head_y + 1, skin)

	# Mouth/teeth
	if mouth_open:
		for my in range(3):
			for mx in range(-2, 3):
				_safe_pixel(img, head_x + 6 + mx, head_y + 3 + my, Color(0.2, 0.1, 0.1))
		_safe_pixel(img, head_x + 5, head_y + 3, teeth)
		_safe_pixel(img, head_x + 7, head_y + 3, teeth)

	# Legs
	for leg in range(4):
		var leg_x = cx - 6 + leg * 5 + lean/4
		var leg_y = cy + 6
		for ly in range(4):
			_safe_pixel(img, leg_x, leg_y + ly, fur_dark)
			_safe_pixel(img, leg_x + 1, leg_y + ly, fur_dark)

	return ImageTexture.create_from_image(img)


## =================
## RAT GUARD SPRITE (armored rat soldier)
## =================

static func create_rat_guard_sprite_frames() -> SpriteFrames:
	"""Create animated sprite frames for Rat Guard (armored rat soldier)"""
	var frames = SpriteFrames.new()

	# Idle animation
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_rat_guard_frame(0, 0.0))
	frames.add_frame("idle", _create_rat_guard_frame(0, -1.0))

	# Attack animation (shield bash)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_rat_guard_frame(1, 0.0))
	frames.add_frame("attack", _create_rat_guard_frame(2, 0.0))
	frames.add_frame("attack", _create_rat_guard_frame(3, 0.0))
	frames.add_frame("attack", _create_rat_guard_frame(0, 0.0))

	# Hit animation
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_rat_guard_frame(4, 1.0))
	frames.add_frame("hit", _create_rat_guard_frame(4, 0.0))
	frames.add_frame("hit", _create_rat_guard_frame(0, 0.0))

	# Defeat animation
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_rat_guard_frame(5, 2.0))
	frames.add_frame("defeat", _create_rat_guard_frame(6, 5.0))
	frames.add_frame("defeat", _create_rat_guard_frame(7, 8.0))

	return frames


static func _create_rat_guard_frame(pose: int, y_offset: float) -> ImageTexture:
	"""Create a single Rat Guard sprite frame (armored rat)"""
	var size = SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Colors
	var fur = Color(0.38, 0.3, 0.25)
	var fur_dark = Color(0.25, 0.18, 0.14)
	var fur_light = Color(0.5, 0.4, 0.35)
	var armor = Color(0.5, 0.45, 0.4)       # Rusty metal
	var armor_dark = Color(0.35, 0.3, 0.28)
	var armor_light = Color(0.65, 0.6, 0.55)
	var skin = Color(0.65, 0.5, 0.45)
	var eye = Color(0.8, 0.25, 0.2)
	var shield_color = Color(0.55, 0.4, 0.3)
	var shield_emblem = Color(0.7, 0.55, 0.2)

	var cx = size / 2
	var cy = int(size * 0.72 + y_offset)

	var lean = 0
	var shield_up = true
	var attacking = false

	match pose:
		1: lean = -3; shield_up = true     # Wind up
		2: lean = 5; attacking = true       # Strike
		3: lean = 10; attacking = true      # Follow through
		4: lean = -8; shield_up = false     # Hit
		5: lean = -15; shield_up = false    # Defeat 1
		6: lean = -25; shield_up = false    # Defeat 2
		7: lean = -35; shield_up = false    # Defeated

	# Defeated pose
	if pose >= 6:
		# Fallen armored rat
		for y in range(-6, 8):
			for x in range(-18, 19):
				var dist = sqrt(pow(float(x) / 18.0, 2) + pow(float(y) / 6.0, 2))
				if dist < 1.0:
					var color = armor_dark if (x + y) % 3 == 0 else fur_dark
					_safe_pixel(img, cx + x, cy + y + 6, color)
		# Fallen shield
		for sy in range(-8, 3):
			for sx in range(-5, 6):
				if abs(sx) + abs(sy) / 2 < 8:
					_safe_pixel(img, cx + 20 + sx, cy + sy + 8, shield_color)
		return ImageTexture.create_from_image(img)

	# Tail (behind everything)
	var tail_x = cx - 14 + lean/4
	var tail_y = cy + 4
	for i in range(18):
		var t = float(i) / 18.0
		var ty = tail_y + int(sin(t * PI) * 5)
		for tw in range(-1, 2):
			_safe_pixel(img, tail_x - i, ty + tw, skin)

	# Body with armor
	for y in range(-12, 10):
		for x in range(-10, 11):
			var dist = sqrt(pow(float(x) / 10.0, 2) + pow(float(y + 2) / 10.0, 2))
			if dist < 1.0:
				# Armor on chest
				if y > -8 and y < 5 and abs(x) < 8:
					var color = armor_light if y < -4 else armor if y < 2 else armor_dark
					_safe_pixel(img, cx + x + lean/4, cy + y, color)
				else:
					_safe_pixel(img, cx + x + lean/4, cy + y, fur if dist > 0.6 else fur_light)

	# Helmet (simple metal cap)
	var head_x = cx + 6 + lean/3
	var head_y = cy - 8
	# Helmet
	for y in range(-8, 2):
		for x in range(-7, 8):
			var dist = sqrt(pow(float(x) / 7.0, 2) + pow(float(y + 3) / 6.0, 2))
			if dist < 1.0 and y < 0:
				_safe_pixel(img, head_x + x, head_y + y, armor if y < -2 else armor_dark)
	# Face visible below helmet
	for y in range(-2, 6):
		for x in range(-5, 8):
			var dist = sqrt(pow(float(x) / 6.0, 2) + pow(float(y) / 4.0, 2))
			if dist < 1.0:
				_safe_pixel(img, head_x + x, head_y + y, fur if dist > 0.5 else fur_light)

	# Ears poking through helmet
	for ear_y in range(-4, 0):
		_safe_pixel(img, head_x - 4, head_y + ear_y - 4, fur)
		_safe_pixel(img, head_x + 4, head_y + ear_y - 4, fur)

	# Eye
	_safe_pixel(img, head_x + 3, head_y + 1, eye)
	_safe_pixel(img, head_x + 4, head_y + 1, eye)

	# Snout
	for sy in range(-2, 3):
		for sx in range(5):
			_safe_pixel(img, head_x + 5 + sx, head_y + 2 + sy/2, fur_light)
	_safe_pixel(img, head_x + 10, head_y + 2, skin)

	# Shield (on left side)
	if shield_up:
		var shield_x = cx - 8 + lean/3
		var shield_y = cy - 2
		# Shield body
		for sy in range(-10, 8):
			for sx in range(-5, 6):
				var shield_dist = sqrt(pow(float(sx) / 5.0, 2) + pow(float(sy + 1) / 9.0, 2))
				if shield_dist < 1.0:
					var color = shield_color
					if sy < -6:
						color = armor_light
					elif sy > 4:
						color = armor_dark
					_safe_pixel(img, shield_x + sx, shield_y + sy, color)
		# Shield emblem (rat symbol)
		for ey in range(-3, 4):
			for ex in range(-2, 3):
				if abs(ex) + abs(ey) < 4:
					_safe_pixel(img, shield_x + ex, shield_y + ey, shield_emblem)

	# Legs with greaves
	for leg in range(2):
		var leg_x = cx - 4 + leg * 8 + lean/4
		var leg_y = cy + 8
		for ly in range(8):
			var color = armor_dark if ly < 4 else fur_dark
			_safe_pixel(img, leg_x, leg_y + ly, color)
			_safe_pixel(img, leg_x + 1, leg_y + ly, color)
			_safe_pixel(img, leg_x + 2, leg_y + ly, color)

	return ImageTexture.create_from_image(img)
