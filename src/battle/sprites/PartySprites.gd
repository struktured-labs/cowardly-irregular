class_name PartySprites

## PartySprites - Procedural sprite generation for party member characters
## Extracted from BattleAnimator.gd. All sprites are SNES-quality with _s() scaling,
## _safe_pixel(), outlines, multi-zone shading, 5+ color palettes, and shine effects.

const _SU = preload("res://src/battle/sprites/SpriteUtils.gd")


## =================
## HERO (FIGHTER) SPRITE - Already Tier A quality
## =================

static func create_hero_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	"""Create animated sprite frames for hero (12-bit style)"""
	var cache_key = "hero_%s" % weapon_id
	return _SU._get_cached_sprite(cache_key, func():
		return _generate_hero_sprite_frames(weapon_id)
	)

static func _generate_hero_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	"""Generate hero sprite frames (internal, called by cache system)."""
	var frames = SpriteFrames.new()
	var weapon_visual = _SU.get_weapon_visual(weapon_id)

	# Idle animation (2 frames, slight bob)
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_hero_frame(0, 0.0, weapon_visual))
	frames.add_frame("idle", _create_hero_frame(0, -1.0, weapon_visual))

	# Attack animation (4 frames, swing sword)
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_hero_frame(1, 0.0, weapon_visual))
	frames.add_frame("attack", _create_hero_frame(2, 0.0, weapon_visual))
	frames.add_frame("attack", _create_hero_frame(3, 0.0, weapon_visual))
	frames.add_frame("attack", _create_hero_frame(0, 0.0, weapon_visual))

	# Defend animation (2 frames, shield up)
	frames.add_animation("defend")
	frames.set_animation_speed("defend", 3.0)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_hero_frame(4, 0.0, weapon_visual))
	frames.add_frame("defend", _create_hero_frame(4, 0.0, weapon_visual))

	# Hit animation (3 frames, recoil)
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_hero_frame(5, 2.0, weapon_visual))
	frames.add_frame("hit", _create_hero_frame(5, 1.0, weapon_visual))
	frames.add_frame("hit", _create_hero_frame(0, 0.0, weapon_visual))

	# Victory animation (2 frames, pose)
	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_hero_frame(6, 0.0, weapon_visual))
	frames.add_frame("victory", _create_hero_frame(6, -1.0, weapon_visual))

	# Defeat animation (3 frames, collapse)
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 3.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_hero_frame(7, 0.0, weapon_visual))
	frames.add_frame("defeat", _create_hero_frame(7, 2.0, weapon_visual))
	frames.add_frame("defeat", _create_hero_frame(7, 4.0, weapon_visual))

	return frames


static func _create_hero_frame(pose: int, y_offset: float, weapon_visual: Dictionary = {}) -> ImageTexture:
	"""Create a single hero sprite frame (SNES-style knight/fighter with more detail)"""
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-style color palette (16 colors)
	var color_armor = Color(0.2, 0.4, 0.8)
	var color_armor_dark = Color(0.1, 0.2, 0.5)
	var color_armor_mid = Color(0.15, 0.3, 0.65)
	var color_armor_light = Color(0.4, 0.6, 1.0)
	var color_armor_shine = Color(0.6, 0.8, 1.0)
	var color_skin = Color(0.9, 0.7, 0.6)
	var color_skin_dark = Color(0.7, 0.5, 0.4)
	var color_hair = Color(0.6, 0.45, 0.3)
	var color_outline = Color(0.08, 0.15, 0.35)

	var color_metal = weapon_visual.get("metal", Color(0.7, 0.7, 0.8))
	var color_metal_light = weapon_visual.get("metal_light", Color(0.95, 0.95, 1.0))
	var color_metal_dark = weapon_visual.get("metal_dark", Color(0.5, 0.5, 0.6))
	var weapon_glow = weapon_visual.get("glow", false)
	var glow_color = weapon_visual.get("glow_color", Color(1.0, 0.5, 0.2))

	var center_x = size / 2
	var base_y = int(size * 0.75 + _SU._sf(y_offset))

	match pose:
		0:  # Idle stance
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x + _SU._s(12), base_y - _SU._s(12), 0, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x + _SU._s(12), base_y - _SU._s(12), 0, glow_color)
		1:  # Wind up
			_draw_hero_body_enhanced(img, center_x, base_y, _SU._s(-5), color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x + _SU._s(18), base_y - _SU._s(18), -30, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x + _SU._s(18), base_y - _SU._s(18), -30, glow_color)
		2:  # Mid swing
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x - _SU._s(12), base_y - _SU._s(24), 45, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x - _SU._s(12), base_y - _SU._s(24), 45, glow_color)
		3:  # Full swing
			_draw_hero_body_enhanced(img, center_x, base_y, _SU._s(5), color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x - _SU._s(18), base_y - _SU._s(12), 90, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x - _SU._s(18), base_y - _SU._s(12), 90, glow_color)
		4:  # Defend
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_shield_enhanced(img, center_x - _SU._s(12), base_y - _SU._s(18), color_metal, color_metal_light, color_armor, color_armor_dark, color_outline)
		5:  # Hit
			_draw_hero_body_enhanced(img, center_x, base_y, _SU._s(-10), color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
		6:  # Victory
			_draw_hero_body_enhanced(img, center_x, base_y, 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)
			_draw_sword_enhanced(img, center_x, base_y - _SU._s(36), -45, color_metal, color_metal_light, color_metal_dark, color_outline)
			if weapon_glow:
				_draw_weapon_glow(img, center_x, base_y - _SU._s(36), -45, glow_color)
		7:  # Defeat
			_draw_hero_body_enhanced(img, center_x, base_y + int(_SU._sf(y_offset)), 0, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_armor_shine, color_skin, color_skin_dark, color_hair, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_hero_body_enhanced(img: Image, cx: int, cy: int, lean: int, armor: Color, armor_dark: Color, armor_mid: Color, armor_light: Color, armor_shine: Color, skin: Color, skin_dark: Color, hair: Color, outline: Color) -> void:
	"""Draw enhanced SNES-style hero body (knight/fighter)"""
	# Head outline
	var head_x = cx + lean/4
	var head_y = cy - _SU._s(28)
	var head_rx = _SU._s(6)
	var head_ry = _SU._s(7)

	for y in range(-head_ry - 1, head_ry + 2):
		for x in range(-head_rx - 1, head_rx + 2):
			var dist = sqrt(pow(float(x) / (head_rx + 1), 2) + pow(float(y) / (head_ry + 1), 2))
			if dist >= 0.85 and dist < 1.0:
				_SU._safe_pixel(img, head_x + x, head_y + y, outline)

	# Hair (top of head)
	for y in range(-head_ry - _SU._s(2), -head_ry/2):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y + head_ry) / (head_ry/2), 2))
			if dist < 1.2:
				_SU._safe_pixel(img, head_x + x, head_y + y, hair)

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
				_SU._safe_pixel(img, head_x + x, head_y + y, color)

	# Eyes
	for eye_side in [-1, 1]:
		var eye_x = head_x + eye_side * _SU._s(3)
		var eye_y = head_y
		_SU._safe_pixel(img, eye_x, eye_y, Color(0.3, 0.4, 0.6))
		_SU._safe_pixel(img, eye_x, eye_y - 1, Color(0.2, 0.2, 0.3))

	# Helmet (visor piece)
	for hx in range(-head_rx, head_rx + 1):
		_SU._safe_pixel(img, head_x + hx, head_y - _SU._s(4), armor_light)

	# Body armor outline
	var body_width = _SU._s(9)
	var body_height = _SU._s(18)

	for y in range(-body_height/2, body_height/2 + 2):
		var width = body_width - abs(y) / 5
		for x in range(-width - 1, width + 2):
			var inside = abs(x) - width
			if inside >= 0 and inside < 2:
				_SU._safe_pixel(img, cx + x + lean/4, cy + y - _SU._s(8), outline)

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
			_SU._safe_pixel(img, cx + x + lean/4, cy + y - _SU._s(8), color)

	# Armor shine spot
	_SU._safe_pixel(img, cx - _SU._s(3) + lean/4, cy - _SU._s(12), armor_shine)
	_SU._safe_pixel(img, cx - _SU._s(2) + lean/4, cy - _SU._s(12), armor_shine)

	# Shoulder pauldrons
	for shoulder_side in [-1, 1]:
		var shoulder_x = cx + shoulder_side * _SU._s(10) + lean/5
		var shoulder_y = cy - _SU._s(14)
		for sy in range(_SU._s(-4), _SU._s(5)):
			var sw = _SU._s(5) - abs(sy) / 2
			for sx in range(-sw, sw + 1):
				var color = armor_mid if sy > 0 else armor_light
				_SU._safe_pixel(img, shoulder_x + sx, shoulder_y + sy, color)

	# Legs
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * _SU._s(4) + lean/6
		for y in range(_SU._s(8), _SU._s(18)):
			var leg_width = _SU._s(4) - (y - _SU._s(8)) / 10
			for lx in range(-leg_width, leg_width + 1):
				var color = armor_mid if lx * leg_side < 0 else armor_dark
				_SU._safe_pixel(img, leg_x + lx, cy + y, color)


static func _draw_sword_enhanced(img: Image, cx: int, cy: int, angle: int, metal: Color, metal_light: Color, metal_dark: Color, outline: Color) -> void:
	"""Draw enhanced sword with more detail"""
	var length = _SU._s(24)
	var blade_width = _SU._s(2)
	var angle_rad = deg_to_rad(angle)

	# Blade outline
	for i in range(-1, length + 1):
		for w in range(-blade_width - 1, blade_width + 2):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			if abs(w) == blade_width + 1 or i == -1 or i == length:
				_SU._safe_pixel(img, px, py, outline)

	# Blade fill with gradient
	for i in range(length):
		for w in range(-blade_width, blade_width + 1):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			var color = metal
			if i < _SU._s(4):
				color = metal_light
			elif w < 0:
				color = metal_dark
			if i > length - _SU._s(4):
				color = metal_light
			_SU._safe_pixel(img, px, py, color)

	# Crossguard
	var guard_x = int(cx + cos(angle_rad) * _SU._sf(3))
	var guard_y = int(cy + sin(angle_rad) * _SU._sf(3))
	for gx in range(_SU._s(-4), _SU._s(5)):
		for gy in range(_SU._s(-1), _SU._s(2)):
			var px = guard_x + int(sin(angle_rad) * gx) + int(cos(angle_rad) * gy)
			var py = guard_y - int(cos(angle_rad) * gx) + int(sin(angle_rad) * gy)
			_SU._safe_pixel(img, px, py, Color(0.6, 0.5, 0.3))


static func _draw_weapon_glow(img: Image, cx: int, cy: int, angle: int, glow_color: Color) -> void:
	"""Draw glowing aura around weapon (for magical weapons)"""
	var length = _SU._s(24)
	var angle_rad = deg_to_rad(angle)

	for i in range(0, length, _SU._s(4)):
		var base_x = int(cx + cos(angle_rad) * i)
		var base_y = int(cy + sin(angle_rad) * i)

		for gy in range(-_SU._s(4), _SU._s(5)):
			for gx in range(-_SU._s(4), _SU._s(5)):
				var dist = sqrt(gx * gx + gy * gy)
				if dist < _SU._sf(4):
					var px = base_x + gx
					var py = base_y + gy
					if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
						var alpha = (1.0 - dist / _SU._sf(4)) * 0.4
						var color = glow_color
						color.a = alpha
						var existing = img.get_pixel(px, py)
						if existing.a > 0:
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
	var shield_rx = _SU._s(8)
	var shield_ry = _SU._s(10)

	# Shield outline
	for y in range(-shield_ry - 1, shield_ry + 2):
		for x in range(-shield_rx - 1, shield_rx + 2):
			var dist = sqrt(pow(float(x) / (shield_rx + 1), 2) + pow(float(y) / (shield_ry + 1), 2))
			if dist >= 0.9 and dist < 1.0:
				_SU._safe_pixel(img, cx + x, cy + y, outline)

	# Shield fill
	for y in range(-shield_ry, shield_ry + 1):
		for x in range(-shield_rx, shield_rx + 1):
			var dist = sqrt(pow(float(x) / shield_rx, 2) + pow(float(y) / shield_ry, 2))
			if dist < 1.0:
				var color = metal
				if y < -shield_ry * 0.3:
					color = metal_light
				elif abs(x) < shield_rx * 0.3:
					color = accent
				_SU._safe_pixel(img, cx + x, cy + y, color)

	# Shield emblem
	for ey in range(_SU._s(-3), _SU._s(4)):
		for ex in range(_SU._s(-2), _SU._s(3)):
			if abs(ex) + abs(ey) <= _SU._s(3):
				_SU._safe_pixel(img, cx + ex, cy + ey, accent_dark)


## =================
## MAGE SPRITE - SNES UPGRADE (was Tier C, now Tier A)
## =================

static func create_mage_sprite_frames(robe_color: Color = Color(0.9, 0.9, 1.0), weapon_id: String = "") -> SpriteFrames:
	"""Create animated sprite frames for mage character (SNES quality)"""
	var cache_key = "mage_%s_%s" % [robe_color.to_html(), weapon_id]
	return _SU._get_cached_sprite(cache_key, func():
		return _generate_mage_sprite_frames(robe_color, weapon_id)
	)

static func _generate_mage_sprite_frames(robe_color: Color = Color(0.9, 0.9, 1.0), weapon_id: String = "") -> SpriteFrames:
	"""Generate mage sprite frames (internal, called by cache system)."""
	var frames = SpriteFrames.new()
	var weapon_visual = _SU.get_weapon_visual(weapon_id) if not weapon_id.is_empty() else _SU._get_default_weapon_visual("staff")

	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_mage_frame(0, 0.0, robe_color, weapon_visual))
	frames.add_frame("idle", _create_mage_frame(0, -1.0, robe_color, weapon_visual))

	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_mage_frame(1, 0.0, robe_color, weapon_visual))
	frames.add_frame("attack", _create_mage_frame(2, 0.0, robe_color, weapon_visual))
	frames.add_frame("attack", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	frames.add_animation("defend")
	frames.set_animation_speed("defend", 2.5)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_mage_frame(3, 0.0, robe_color, weapon_visual))
	frames.add_frame("defend", _create_mage_frame(3, 0.0, robe_color, weapon_visual))

	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_mage_frame(4, 2.0, robe_color, weapon_visual))
	frames.add_frame("hit", _create_mage_frame(4, 1.0, robe_color, weapon_visual))
	frames.add_frame("hit", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	frames.add_animation("cast")
	frames.set_animation_speed("cast", 2.5)
	frames.set_animation_loop("cast", false)
	frames.add_frame("cast", _create_mage_frame(5, 0.0, robe_color, weapon_visual))
	frames.add_frame("cast", _create_mage_frame(6, -2.0, robe_color, weapon_visual))
	frames.add_frame("cast", _create_mage_frame(5, 0.0, robe_color, weapon_visual))
	frames.add_frame("cast", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	frames.add_animation("item")
	frames.set_animation_speed("item", 3.0)
	frames.set_animation_loop("item", false)
	frames.add_frame("item", _create_mage_frame(1, 0.0, robe_color, weapon_visual))
	frames.add_frame("item", _create_mage_frame(0, 0.0, robe_color, weapon_visual))

	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_mage_frame(7, 0.0, robe_color, weapon_visual))
	frames.add_frame("victory", _create_mage_frame(7, -1.0, robe_color, weapon_visual))

	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_mage_frame(4, 0.0, robe_color, weapon_visual))
	frames.add_frame("defeat", _create_mage_frame(4, 2.0, robe_color, weapon_visual))
	frames.add_frame("defeat", _create_mage_frame(4, 4.0, robe_color, weapon_visual))

	return frames


static func _create_mage_frame(pose: int, y_offset: float, robe_color: Color, weapon_visual: Dictionary = {}) -> ImageTexture:
	"""Create a single mage sprite frame (SNES-style robed figure with full detail)"""
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-quality 6-color robe palette
	var color_robe = robe_color
	var color_robe_dark = robe_color.darkened(0.35)
	var color_robe_mid = robe_color.darkened(0.18)
	var color_robe_light = robe_color.lightened(0.2)
	var color_robe_shine = robe_color.lightened(0.4)
	var color_skin = Color(0.9, 0.7, 0.6)
	var color_skin_dark = Color(0.7, 0.5, 0.4)
	var color_outline = Color(0.08, 0.08, 0.15)

	var color_staff = weapon_visual.get("wood", Color(0.5, 0.3, 0.2))
	var color_staff_dark = Color(0.35, 0.2, 0.12)
	var color_staff_light = Color(0.65, 0.42, 0.3)
	var color_gem = weapon_visual.get("gem", Color(0.3, 0.8, 1.0))
	var weapon_glow = weapon_visual.get("glow", false)
	var glow_color = weapon_visual.get("glow_color", color_gem)

	var center_x = size / 2
	var base_y = int(size * 0.75 + y_offset)

	match pose:
		0:  # Idle stance
			_draw_mage_body_enhanced(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
			_draw_staff_enhanced(img, center_x + _SU._s(10), base_y - _SU._s(10), 0, color_staff, color_staff_dark, color_staff_light, color_gem, color_outline)
			if weapon_glow:
				_draw_staff_glow(img, center_x + _SU._s(10), base_y - _SU._s(10), 0, glow_color)
		1:  # Staff forward
			_draw_mage_body_enhanced(img, center_x, base_y, _SU._s(5), color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
			_draw_staff_enhanced(img, center_x + _SU._s(6), base_y - _SU._s(14), 20, color_staff, color_staff_dark, color_staff_light, color_gem, color_outline)
			if weapon_glow:
				_draw_staff_glow(img, center_x + _SU._s(6), base_y - _SU._s(14), 20, glow_color)
		2:  # Staff thrust
			_draw_mage_body_enhanced(img, center_x, base_y, _SU._s(10), color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
			_draw_staff_enhanced(img, center_x - _SU._s(4), base_y - _SU._s(16), 60, color_staff, color_staff_dark, color_staff_light, color_gem, color_outline)
			if weapon_glow:
				_draw_staff_glow(img, center_x - _SU._s(4), base_y - _SU._s(16), 60, glow_color)
		3:  # Defend
			_draw_mage_body_enhanced(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
			_draw_staff_enhanced(img, center_x, base_y - _SU._s(12), 90, color_staff, color_staff_dark, color_staff_light, color_gem, color_outline)
			if weapon_glow:
				_draw_staff_glow(img, center_x, base_y - _SU._s(12), 90, glow_color)
		4:  # Hit (recoil)
			_draw_mage_body_enhanced(img, center_x, base_y, _SU._s(-10), color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
		5:  # Cast prep
			_draw_mage_body_enhanced(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
			_draw_staff_enhanced(img, center_x + _SU._s(8), base_y - _SU._s(20), -20, color_staff, color_staff_dark, color_staff_light, color_gem, color_outline)
			if weapon_glow:
				_draw_staff_glow(img, center_x + _SU._s(8), base_y - _SU._s(20), -20, glow_color)
		6:  # Cast release
			_draw_mage_body_enhanced(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
			_draw_staff_enhanced(img, center_x + _SU._s(8), base_y - _SU._s(20), -20, color_staff, color_staff_dark, color_staff_light, Color.WHITE, color_outline)
			_draw_magic_glow(img, center_x, base_y - _SU._s(30), color_gem)
		7:  # Victory
			_draw_mage_body_enhanced(img, center_x, base_y, 0, color_robe, color_robe_dark, color_robe_mid, color_robe_light, color_robe_shine, color_skin, color_skin_dark, color_outline)
			_draw_staff_enhanced(img, center_x, base_y - _SU._s(28), -45, color_staff, color_staff_dark, color_staff_light, color_gem, color_outline)
			if weapon_glow:
				_draw_staff_glow(img, center_x, base_y - _SU._s(28), -45, glow_color)

	return ImageTexture.create_from_image(img)


static func _draw_mage_body_enhanced(img: Image, cx: int, cy: int, lean: int, robe: Color, robe_dark: Color, robe_mid: Color, robe_light: Color, robe_shine: Color, skin: Color, skin_dark: Color, outline: Color) -> void:
	"""Draw SNES-quality mage body with hood, face, robe detail, and sleeve"""
	var size = _SU.SPRITE_SIZE

	# Hood (3-zone shading: top light, face opening dark, sides mid)
	var hood_cx = cx + lean/4
	var hood_cy = cy - _SU._s(26)
	var hood_rx = _SU._s(7)
	var hood_ry = _SU._s(8)

	# Hood outline
	_SU._draw_ellipse_outline(img, hood_cx, hood_cy, hood_rx + 1, hood_ry + 1, outline)

	# Hood fill with 3-zone shading
	for y in range(-hood_ry, hood_ry + 1):
		for x in range(-hood_rx, hood_rx + 1):
			var dist = sqrt(pow(float(x) / hood_rx, 2) + pow(float(y) / hood_ry, 2))
			if dist < 1.0:
				var color = robe
				if y < -hood_ry * 0.35:
					color = robe_light  # Top zone (light)
				elif y > hood_ry * 0.2:
					color = robe_dark   # Face opening zone (dark shadow)
				elif abs(x) > hood_rx * 0.5:
					color = robe_mid    # Side zones
				_SU._safe_pixel(img, hood_cx + x, hood_cy + y, color)

	# Hood point at top
	for y in range(_SU._s(-6), _SU._s(0)):
		var point_width = _SU._s(3) + y / 2
		if point_width < 0:
			point_width = 0
		for x in range(-point_width, point_width + 1):
			_SU._safe_pixel(img, hood_cx + x, hood_cy - hood_ry + y, robe_light if y < _SU._s(-3) else robe)
	# Hood point outline
	for y in range(_SU._s(-6), _SU._s(0)):
		var pw = _SU._s(3) + y / 2
		if pw >= 0:
			_SU._safe_pixel(img, hood_cx + pw + 1, hood_cy - hood_ry + y, outline)
			_SU._safe_pixel(img, hood_cx - pw - 1, hood_cy - hood_ry + y, outline)

	# Face visible under hood with two eyes and catchlights
	var face_cx = cx + lean/4
	var face_cy = cy - _SU._s(22)
	var face_rx = _SU._s(4)
	var face_ry = _SU._s(4)

	for y in range(-face_ry, face_ry + 1):
		for x in range(-face_rx, face_rx + 1):
			var dist = sqrt(pow(float(x) / face_rx, 2) + pow(float(y) / face_ry, 2))
			if dist < 0.9:
				var color = skin
				if x < -face_rx * 0.3:
					color = skin_dark
				_SU._safe_pixel(img, face_cx + x, face_cy + y, color)

	# Eyes with catchlights
	for eye_side in [-1, 1]:
		var eye_x = face_cx + eye_side * _SU._s(2)
		var eye_y = face_cy - _SU._s(1)
		# Eye base (dark)
		_SU._safe_pixel(img, eye_x, eye_y, Color(0.15, 0.15, 0.3))
		_SU._safe_pixel(img, eye_x + eye_side, eye_y, Color(0.2, 0.2, 0.35))
		# Pupil
		_SU._safe_pixel(img, eye_x, eye_y, Color(0.1, 0.1, 0.2))
		# Catchlight (white pixel above pupil)
		_SU._safe_pixel(img, eye_x - 1, eye_y - 1, Color.WHITE)

	# Robe body (tapered, wider at bottom) with fabric fold lines
	var robe_top = cy - _SU._s(18)
	var robe_bottom = cy + _SU._s(10)

	# Robe outline
	for y in range(robe_top, robe_bottom + 1):
		var t = float(y - robe_top) / (robe_bottom - robe_top)
		var width = int(_SU._s(6) + t * _SU._s(10))
		_SU._safe_pixel(img, cx - width - 1 + lean/4, y, outline)
		_SU._safe_pixel(img, cx + width + 1 + lean/4, y, outline)
	# Bottom outline
	var bot_width = int(_SU._s(6) + _SU._s(10))
	for x in range(-bot_width - 1, bot_width + 2):
		_SU._safe_pixel(img, cx + x + lean/4, robe_bottom, outline)

	# Robe fill with multi-zone shading and fold lines
	for y in range(robe_top, robe_bottom):
		var t = float(y - robe_top) / (robe_bottom - robe_top)
		var width = int(_SU._s(6) + t * _SU._s(10))
		for x in range(-width + lean/4, width + lean/4):
			var color = robe
			# Vertical zone shading
			if t < 0.2:
				color = robe_light  # Top (near shoulders)
			elif t > 0.8:
				color = robe_dark   # Hem area
			# Side shading
			var rel_x = float(x - lean/4) / max(width, 1)
			if rel_x < -0.6:
				color = robe_dark
			elif rel_x > 0.6:
				color = robe_mid
			# Fabric fold lines (vertical darker streaks)
			if abs(x - lean/4) > 0 and (x - lean/4) % _SU._s(5) == 0 and t > 0.3:
				color = robe_dark
			_SU._safe_pixel(img, cx + x, y, color)

	# Robe shine highlight
	_SU._safe_pixel(img, cx - _SU._s(2) + lean/4, robe_top + _SU._s(4), robe_shine)
	_SU._safe_pixel(img, cx - _SU._s(1) + lean/4, robe_top + _SU._s(4), robe_shine)

	# Sleeve detail on casting arm (right side)
	var sleeve_x = cx + _SU._s(7) + lean/5
	var sleeve_y = cy - _SU._s(12)
	for sy in range(_SU._s(-3), _SU._s(8)):
		var sw = _SU._s(4) - abs(sy) / 3
		for sx in range(-sw, sw + 1):
			var color = robe_mid if sx < 0 else robe
			if sy > _SU._s(4):
				color = robe_dark
			_SU._safe_pixel(img, sleeve_x + sx, sleeve_y + sy, color)
	# Hand at end of sleeve
	for hy in range(_SU._s(3)):
		for hx in range(_SU._s(-2), _SU._s(3)):
			_SU._safe_pixel(img, sleeve_x + hx, sleeve_y + _SU._s(7) + hy, skin)

	# Robe hem detail (zigzag pattern)
	for hx in range(-bot_width, bot_width + 1):
		if hx % _SU._s(3) == 0:
			_SU._safe_pixel(img, cx + hx + lean/4, robe_bottom - 1, robe_light)


static func _draw_staff_enhanced(img: Image, cx: int, cy: int, angle: int, wood: Color, wood_dark: Color, wood_light: Color, gem: Color, outline: Color) -> void:
	"""Draw SNES-quality staff with thicker shaft, wood grain, faceted gem with shine"""
	var length = _SU._s(28)
	var shaft_width = _SU._s(2)
	var angle_rad = deg_to_rad(angle)

	# Shaft outline
	for i in range(-1, length + 1):
		for w in range(-shaft_width - 1, shaft_width + 2):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			if abs(w) == shaft_width + 1 or i == -1 or i == length:
				_SU._safe_pixel(img, px, py, outline)

	# Shaft fill with wood grain
	for i in range(length):
		for w in range(-shaft_width, shaft_width + 1):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			var color = wood
			if w < 0:
				color = wood_dark
			elif w > 0:
				color = wood_light
			# Wood grain (alternating subtle bands)
			if i % _SU._s(4) < _SU._s(1):
				color = color.darkened(0.08)
			_SU._safe_pixel(img, px, py, color)

	# Faceted gem at top
	var gem_x = int(cx + cos(angle_rad) * (length - _SU._s(2)))
	var gem_y = int(cy + sin(angle_rad) * (length - _SU._s(2)))
	var gem_radius = _SU._s(4)
	var gem_light = gem.lightened(0.3)
	var gem_dark = gem.darkened(0.3)

	# Gem outline
	for gy in range(-gem_radius - 1, gem_radius + 2):
		for gx in range(-gem_radius - 1, gem_radius + 2):
			if abs(gx) + abs(gy) == gem_radius + 1:
				_SU._safe_pixel(img, gem_x + gx, gem_y + gy, outline)

	# Gem fill (diamond facets)
	for gy in range(-gem_radius, gem_radius + 1):
		for gx in range(-gem_radius, gem_radius + 1):
			if abs(gx) + abs(gy) <= gem_radius:
				var color = gem
				if gx < 0 and gy < 0:
					color = gem_light  # Top-left facet (light)
				elif gx > 0 and gy > 0:
					color = gem_dark   # Bottom-right facet (dark)
				_SU._safe_pixel(img, gem_x + gx, gem_y + gy, color)

	# Gem shine spot
	_SU._safe_pixel(img, gem_x - 1, gem_y - 1, Color.WHITE)
	_SU._safe_pixel(img, gem_x, gem_y - 1, gem_light)


static func _draw_staff_glow(img: Image, cx: int, cy: int, angle: int, glow_color: Color) -> void:
	"""Draw glowing aura around staff gem"""
	var length = _SU._s(28)
	var angle_rad = deg_to_rad(angle)
	var gem_x = int(cx + cos(angle_rad) * (length - _SU._s(2)))
	var gem_y = int(cy + sin(angle_rad) * (length - _SU._s(2)))
	var glow_radius = _SU._s(6)

	for gy in range(-glow_radius, glow_radius + 1):
		for gx in range(-glow_radius, glow_radius + 1):
			var dist = sqrt(gx * gx + gy * gy)
			if dist < glow_radius:
				var px = gem_x + gx
				var py = gem_y + gy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					var alpha = (1.0 - dist / float(glow_radius)) * 0.5
					var color = glow_color
					color.a = alpha
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
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
	"""Draw magic glow effect (SNES-style with larger radius)"""
	var radius = _SU._s(6)
	for gy in range(-radius, radius + 1):
		for gx in range(-radius, radius + 1):
			var dist = sqrt(gx * gx + gy * gy)
			if dist < radius:
				var px = cx + gx
				var py = cy + gy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					var alpha = (1.0 - dist / float(radius)) * 0.7
					var color = glow_color
					color.a = alpha
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
						img.set_pixel(px, py, existing.blend(color))
					else:
						img.set_pixel(px, py, color)


## =================
## THIEF SPRITE - SNES UPGRADE (was Tier C, now Tier A)
## =================

static func create_thief_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	"""Create animated sprite frames for thief character (SNES quality)"""
	var cache_key = "thief_%s" % weapon_id
	return _SU._get_cached_sprite(cache_key, func():
		return _generate_thief_sprite_frames(weapon_id)
	)

static func _generate_thief_sprite_frames(weapon_id: String = "") -> SpriteFrames:
	"""Generate thief sprite frames (internal, called by cache system)."""
	var frames = SpriteFrames.new()
	var weapon_visual = _SU.get_weapon_visual(weapon_id) if not weapon_id.is_empty() else _SU._get_default_weapon_visual("dagger")

	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_thief_frame(0, 0.0, weapon_visual))
	frames.add_frame("idle", _create_thief_frame(0, -1.0, weapon_visual))

	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_thief_frame(1, 0.0, weapon_visual))
	frames.add_frame("attack", _create_thief_frame(2, -2.0, weapon_visual))
	frames.add_frame("attack", _create_thief_frame(3, 0.0, weapon_visual))
	frames.add_frame("attack", _create_thief_frame(0, 0.0, weapon_visual))

	frames.add_animation("defend")
	frames.set_animation_speed("defend", 2.5)
	frames.set_animation_loop("defend", false)
	frames.add_frame("defend", _create_thief_frame(4, 0.0, weapon_visual))
	frames.add_frame("defend", _create_thief_frame(4, 0.0, weapon_visual))

	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_thief_frame(5, 2.0, weapon_visual))
	frames.add_frame("hit", _create_thief_frame(5, 1.0, weapon_visual))
	frames.add_frame("hit", _create_thief_frame(0, 0.0, weapon_visual))

	frames.add_animation("cast")
	frames.set_animation_speed("cast", 3.0)
	frames.set_animation_loop("cast", false)
	frames.add_frame("cast", _create_thief_frame(6, 0.0, weapon_visual))
	frames.add_frame("cast", _create_thief_frame(6, -1.0, weapon_visual))
	frames.add_frame("cast", _create_thief_frame(0, 0.0, weapon_visual))

	frames.add_animation("item")
	frames.set_animation_speed("item", 3.0)
	frames.set_animation_loop("item", false)
	frames.add_frame("item", _create_thief_frame(6, 0.0, weapon_visual))
	frames.add_frame("item", _create_thief_frame(0, 0.0, weapon_visual))

	frames.add_animation("victory")
	frames.set_animation_speed("victory", 1.5)
	frames.set_animation_loop("victory", true)
	frames.add_frame("victory", _create_thief_frame(7, 0.0, weapon_visual))
	frames.add_frame("victory", _create_thief_frame(7, -1.0, weapon_visual))

	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_thief_frame(5, 0.0, weapon_visual))
	frames.add_frame("defeat", _create_thief_frame(5, 2.0, weapon_visual))
	frames.add_frame("defeat", _create_thief_frame(5, 4.0, weapon_visual))

	return frames


static func _create_thief_frame(pose: int, y_offset: float, weapon_visual: Dictionary = {}) -> ImageTexture:
	"""Create a single thief sprite frame (SNES-style nimble rogue with full detail)"""
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-quality 6-color cloak palette
	var color_cloak = Color(0.3, 0.25, 0.4)
	var color_cloak_dark = Color(0.18, 0.13, 0.28)
	var color_cloak_mid = Color(0.25, 0.2, 0.35)
	var color_cloak_light = Color(0.42, 0.37, 0.55)
	var color_cloak_shine = Color(0.55, 0.48, 0.68)
	var color_skin = Color(0.9, 0.7, 0.6)
	var color_skin_dark = Color(0.7, 0.5, 0.4)
	var color_belt = Color(0.45, 0.3, 0.2)
	var color_belt_dark = Color(0.3, 0.18, 0.1)
	var color_outline = Color(0.1, 0.08, 0.18)

	var color_dagger = weapon_visual.get("blade", Color(0.8, 0.8, 0.9))
	var color_dagger_light = weapon_visual.get("blade_light", Color(1.0, 1.0, 1.0))
	var weapon_glow = weapon_visual.get("glow", false)
	var glow_color = weapon_visual.get("glow_color", Color(0.6, 0.3, 0.9))

	var center_x = size / 2
	var base_y = int(size * 0.75 + y_offset)

	match pose:
		0:  # Idle stance
			_draw_thief_body_enhanced(img, center_x, base_y, 0, color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
			_draw_dagger_enhanced(img, center_x + _SU._s(8), base_y - _SU._s(6), 0, color_dagger, color_dagger_light, color_outline)
			if weapon_glow:
				_draw_dagger_glow(img, center_x + _SU._s(8), base_y - _SU._s(6), 0, glow_color)
		1:  # Wind up (crouch)
			_draw_thief_body_enhanced(img, center_x, base_y + _SU._s(2), _SU._s(-5), color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
			_draw_dagger_enhanced(img, center_x + _SU._s(10), base_y - _SU._s(4), -20, color_dagger, color_dagger_light, color_outline)
		2:  # Dash attack
			_draw_thief_body_enhanced(img, center_x - _SU._s(6), base_y, _SU._s(15), color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
			_draw_dagger_enhanced(img, center_x - _SU._s(12), base_y - _SU._s(8), 60, color_dagger, color_dagger_light, color_outline)
		3:  # Recovery
			_draw_thief_body_enhanced(img, center_x, base_y, _SU._s(5), color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
			_draw_dagger_enhanced(img, center_x + _SU._s(6), base_y - _SU._s(6), 30, color_dagger, color_dagger_light, color_outline)
		4:  # Defend (dodge stance)
			_draw_thief_body_enhanced(img, center_x + _SU._s(4), base_y, _SU._s(-10), color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
			_draw_dagger_enhanced(img, center_x + _SU._s(10), base_y - _SU._s(8), -30, color_dagger, color_dagger_light, color_outline)
		5:  # Hit (recoil)
			_draw_thief_body_enhanced(img, center_x, base_y, _SU._s(-15), color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
		6:  # Throw/item
			_draw_thief_body_enhanced(img, center_x, base_y, _SU._s(10), color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
			_draw_dagger_enhanced(img, center_x - _SU._s(8), base_y - _SU._s(16), 45, color_dagger, color_dagger_light, color_outline)
		7:  # Victory pose
			_draw_thief_body_enhanced(img, center_x, base_y, 0, color_cloak, color_cloak_dark, color_cloak_mid, color_cloak_light, color_cloak_shine, color_skin, color_skin_dark, color_belt, color_belt_dark, color_outline)
			_draw_dagger_enhanced(img, center_x + _SU._s(4), base_y - _SU._s(18), -60, color_dagger, color_dagger_light, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_thief_body_enhanced(img: Image, cx: int, cy: int, lean: int, cloak: Color, cloak_dark: Color, cloak_mid: Color, cloak_light: Color, cloak_shine: Color, skin: Color, skin_dark: Color, belt: Color, belt_dark: Color, outline: Color) -> void:
	"""Draw SNES-quality thief body with bandana, face, cloak, belt with pouches"""

	# Head (bandana/hood with 3 shading zones)
	var head_x = cx + lean/4
	var head_y = cy - _SU._s(24)
	var head_rx = _SU._s(5)
	var head_ry = _SU._s(6)

	# Head outline
	_SU._draw_ellipse_outline(img, head_x, head_y, head_rx + 1, head_ry + 1, outline)

	# Bandana (top of head, 3 zones)
	for y in range(-head_ry, 0):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = cloak
				if y < -head_ry * 0.5:
					color = cloak_light  # Top (light)
				elif abs(x) > head_rx * 0.6:
					color = cloak_mid    # Sides (mid)
				_SU._safe_pixel(img, head_x + x, head_y + y, color)

	# Bandana tail (fluttering behind)
	for i in range(_SU._s(8)):
		var tx = head_x + head_rx + i
		var ty = head_y - _SU._s(2) + int(sin(i * 0.4) * _SU._sf(2))
		var tw = _SU._s(2) - i / 4
		for w in range(-tw, tw + 1):
			_SU._safe_pixel(img, tx, ty + w, cloak_mid if i > _SU._s(4) else cloak)

	# Face (visible under bandana)
	for y in range(-1, head_ry + 1):
		for x in range(-head_rx + 1, head_rx):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 0.9:
				var color = skin
				if x < -head_rx * 0.3:
					color = skin_dark
				_SU._safe_pixel(img, head_x + x, head_y + y, color)

	# Eyes with catchlights
	for eye_side in [-1, 1]:
		var eye_x = head_x + eye_side * _SU._s(2)
		var eye_y = head_y + _SU._s(1)
		_SU._safe_pixel(img, eye_x, eye_y, Color(0.2, 0.15, 0.3))
		_SU._safe_pixel(img, eye_x + eye_side, eye_y, Color(0.25, 0.2, 0.35))
		# Catchlight
		_SU._safe_pixel(img, eye_x - 1, eye_y - 1, Color.WHITE)

	# 4-tone cloak body with edge outline
	var cloak_top = cy - _SU._s(16)
	var cloak_bottom = cy + _SU._s(6)

	# Cloak outline
	for y in range(cloak_top, cloak_bottom + 1):
		var t = float(y - cloak_top) / (cloak_bottom - cloak_top)
		var width = int(_SU._s(5) + t * _SU._s(6))
		_SU._safe_pixel(img, cx - width - 1 + lean/4, y, outline)
		_SU._safe_pixel(img, cx + width + 1 + lean/4, y, outline)
	for x in range(-int(_SU._s(5) + _SU._s(6)) - 1, int(_SU._s(5) + _SU._s(6)) + 2):
		_SU._safe_pixel(img, cx + x + lean/4, cloak_bottom, outline)

	# Cloak fill (4 tones: light, base, mid, dark)
	for y in range(cloak_top, cloak_bottom):
		var t = float(y - cloak_top) / (cloak_bottom - cloak_top)
		var width = int(_SU._s(5) + t * _SU._s(6))
		for x in range(-width + lean/4, width + lean/4):
			var color = cloak
			var rel_x = float(x - lean/4) / max(width, 1)
			if t < 0.15:
				color = cloak_light
			elif t > 0.75:
				color = cloak_dark
			elif rel_x < -0.6:
				color = cloak_dark
			elif rel_x > 0.6:
				color = cloak_mid
			_SU._safe_pixel(img, cx + x, y, color)

	# Cloak shine
	_SU._safe_pixel(img, cx - _SU._s(1) + lean/4, cloak_top + _SU._s(3), cloak_shine)
	_SU._safe_pixel(img, cx + lean/4, cloak_top + _SU._s(3), cloak_shine)

	# Belt with pouches
	var belt_y = cy - _SU._s(2)
	var belt_width = int(_SU._s(5) + 0.55 * _SU._s(6))
	for bx in range(-belt_width, belt_width + 1):
		_SU._safe_pixel(img, cx + bx + lean/4, belt_y, belt)
		_SU._safe_pixel(img, cx + bx + lean/4, belt_y + 1, belt_dark)
	# Belt buckle
	_SU._safe_pixel(img, cx + lean/4, belt_y, Color(0.7, 0.6, 0.3))
	# Pouches
	for pouch_side in [-1, 1]:
		var pouch_x = cx + pouch_side * _SU._s(4) + lean/4
		for py in range(_SU._s(3)):
			for px in range(_SU._s(-2), _SU._s(2)):
				_SU._safe_pixel(img, pouch_x + px, belt_y + 2 + py, belt_dark if py > 0 else belt)

	# Legs (slim, athletic)
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * _SU._s(3) + lean/6
		for y in range(_SU._s(6), _SU._s(14)):
			var leg_width = _SU._s(3) - (y - _SU._s(6)) / 8
			for lx in range(-leg_width, leg_width + 1):
				var color = cloak_mid if lx * leg_side < 0 else cloak_dark
				_SU._safe_pixel(img, leg_x + lx, cy + y, color)
		# Boots
		for bx in range(_SU._s(-3), _SU._s(2)):
			_SU._safe_pixel(img, leg_x + bx * leg_side, cy + _SU._s(13), cloak_dark)
			_SU._safe_pixel(img, leg_x + bx * leg_side, cy + _SU._s(14), outline)


static func _draw_dagger_enhanced(img: Image, cx: int, cy: int, angle: int, blade: Color, blade_light: Color, outline: Color) -> void:
	"""Draw SNES-quality dagger with 2-3px blade, crossguard, edge highlight"""
	var length = _SU._s(14)
	var blade_width = _SU._s(1)
	var angle_rad = deg_to_rad(angle)

	# Blade outline
	for i in range(-1, length + 1):
		for w in range(-blade_width - 1, blade_width + 2):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			if abs(w) == blade_width + 1 or i == -1 or i == length:
				_SU._safe_pixel(img, px, py, outline)

	# Blade fill (tapered with highlight edge)
	for i in range(length):
		var taper = 1.0 if i < length * 0.7 else (1.0 - float(i - length * 0.7) / (length * 0.3))
		var bw = max(1, int(blade_width * taper))
		for w in range(-bw, bw + 1):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			var color = blade
			if i < _SU._s(3):
				color = blade_light
			elif w == -bw:
				color = blade_light  # Edge highlight
			if i > length - _SU._s(3):
				color = blade_light  # Tip shine
			_SU._safe_pixel(img, px, py, color)

	# Crossguard
	var guard_x = int(cx + cos(angle_rad) * _SU._sf(2))
	var guard_y = int(cy + sin(angle_rad) * _SU._sf(2))
	for gx in range(_SU._s(-3), _SU._s(4)):
		for gy in range(_SU._s(-1), _SU._s(2)):
			var px = guard_x + int(sin(angle_rad) * gx) + int(cos(angle_rad) * gy)
			var py = guard_y - int(cos(angle_rad) * gx) + int(sin(angle_rad) * gy)
			_SU._safe_pixel(img, px, py, Color(0.5, 0.4, 0.25))

	# Wrap handle
	for i in range(_SU._s(2)):
		var hx = int(cx - cos(angle_rad) * i)
		var hy = int(cy - sin(angle_rad) * i)
		_SU._safe_pixel(img, hx, hy, Color(0.4, 0.25, 0.15))


static func _draw_dagger_glow(img: Image, cx: int, cy: int, angle: int, glow_color: Color) -> void:
	"""Draw glow along dagger blade"""
	var length = _SU._s(14)
	var angle_rad = deg_to_rad(angle)

	for i in range(0, length, _SU._s(3)):
		var base_x = int(cx + cos(angle_rad) * i)
		var base_y = int(cy + sin(angle_rad) * i)
		for gy in range(-_SU._s(3), _SU._s(4)):
			for gx in range(-_SU._s(3), _SU._s(4)):
				var dist = sqrt(gx * gx + gy * gy)
				if dist < _SU._sf(3):
					var px = base_x + gx
					var py = base_y + gy
					if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
						var alpha = (1.0 - dist / _SU._sf(3)) * 0.35
						var color = glow_color
						color.a = alpha
						var existing = img.get_pixel(px, py)
						if existing.a > 0:
							img.set_pixel(px, py, Color(
								min(1.0, existing.r + color.r * alpha),
								min(1.0, existing.g + color.g * alpha),
								min(1.0, existing.b + color.b * alpha),
								existing.a
							))
