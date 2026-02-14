class_name MonsterSprites

## MonsterSprites - Procedural sprite generation for all monster/enemy types
## Extracted from BattleAnimator.gd. All sprites upgraded to SNES quality with
## _s() scaling, _safe_pixel(), outlines, multi-zone shading, 5+ color palettes.

const _SU = preload("res://src/battle/sprites/SpriteUtils.gd")

# Convenience aliases for readability
static func _s(v: float) -> int: return _SU._s(v)
static func _sf(v: float) -> float: return _SU._sf(v)
static func _sp(img: Image, x: int, y: int, c: Color) -> void: _SU._safe_pixel(img, x, y, c)


## =================
## SLIME (already Tier A - direct port)
## =================

static func create_slime_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("slime", func():
		return _generate_slime_sprite_frames()
	)

static func _generate_slime_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()

	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_slime_frame(0, 0.0, 1.0))
	frames.add_frame("idle", _create_slime_frame(0, -2.0, 1.05))
	frames.add_frame("idle", _create_slime_frame(0, 0.0, 1.0))
	frames.add_frame("idle", _create_slime_frame(0, 1.0, 0.95))

	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_slime_frame(1, 0.0, 1.0))
	frames.add_frame("attack", _create_slime_frame(2, -4.0, 1.2))
	frames.add_frame("attack", _create_slime_frame(0, 0.0, 1.0))

	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_slime_frame(3, 0.0, 0.9))
	frames.add_frame("hit", _create_slime_frame(0, 0.0, 1.0))

	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_slime_frame(0, 0.0, 1.0))
	frames.add_frame("defeat", _create_slime_frame(4, 2.0, 0.8))
	frames.add_frame("defeat", _create_slime_frame(4, 4.0, 0.5))
	frames.add_frame("defeat", _create_slime_frame(4, 6.0, 0.2))

	return frames


static func _create_slime_frame(pose: int, y_offset: float, scale_y: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-style 5-shade palette for slime (more vibrant green)
	var base_green = Color(0.25, 0.75, 0.35)
	var palette = _SU.make_5shade_palette(base_green)
	var color_deep_shadow = palette[0]   # Dark green-blue
	var color_shadow = palette[1]         # Medium shadow
	var color_slime = palette[2]          # Base green
	var color_highlight = palette[3]      # Bright green
	var color_rim = palette[4]            # Rim light (almost white-green)
	var color_outline = Color(0.08, 0.22, 0.12, 0.95)
	var color_core = Color(0.3, 0.7, 0.95, 0.35)  # Blue inner glow
	var color_specular = Color(0.85, 1.0, 0.9)     # White-green specular

	var center_x = size / 2
	var base_y = int(size * 0.65 + _sf(y_offset))
	var radius = _s(18)

	# Anti-aliased outline with proper edge smoothing
	var outline_radius = radius + _s(2)
	_SU._draw_aa_ellipse_outline(img, center_x, base_y, int(outline_radius), int(outline_radius * scale_y), color_outline)

	# Body with 4-zone SNES shading + dithered transitions
	for y in range(-int(radius * scale_y), int(radius * scale_y) + 1):
		for x in range(-radius, radius + 1):
			var dist = sqrt(pow(float(x) / radius, 2) + pow(float(y) / (radius * scale_y), 2))
			if dist < 1.0:
				var px = center_x + x
				var py = base_y + y
				var color = color_slime
				var v_pos = float(y) / (radius * scale_y)
				var h_pos = float(x) / radius

				# 4-zone shading with dithered transitions
				if v_pos < -0.45:
					color = color_highlight
				elif v_pos < -0.25:
					# Dithered transition: highlight to base
					color = color_highlight if ((px + py) % 2 == 0) else color_slime
				elif v_pos > 0.55:
					color = color_deep_shadow
				elif v_pos > 0.35:
					# Dithered transition: shadow to deep shadow
					color = color_shadow if ((px + py) % 2 == 0) else color_deep_shadow
				elif v_pos > 0.15:
					color = color_shadow
				# Horizontal shading (left side slightly darker for 3D effect)
				if h_pos > 0.5 and v_pos > -0.3:
					if v_pos > 0.35:
						color = color_deep_shadow
					elif (px + py) % 2 == 0:
						color = color_shadow
				# Rim lighting on left edge
				if h_pos < -0.7 and v_pos < 0.2 and v_pos > -0.4:
					if (px + py) % 3 == 0:
						color = color_rim
				_sp(img, px, py, color)

	# Inner glow/core (translucent blue center)
	var core_radius = _s(8)
	for y in range(-int(core_radius * scale_y), int(core_radius * scale_y) + 1):
		for x in range(-core_radius, core_radius + 1):
			var dist = sqrt(pow(float(x) / core_radius, 2) + pow(float(y) / (core_radius * scale_y), 2))
			if dist < 0.7:
				var px = center_x + x + _s(2)
				var py = base_y + y - _s(3)
				if px >= 0 and px < size and py >= 0 and py < size:
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
						var intensity = (0.7 - dist) / 0.7
						var core = color_core
						core.a = intensity * 0.4
						_sp(img, px, py, existing.blend(core))

	# SNES-style eyes with proper detail
	var eye_y = base_y - _s(int(6 * scale_y))
	var eye_spacing = _s(8)
	if pose != 4:
		for eye_side in [-1, 1]:
			var eye_x = center_x + eye_side * eye_spacing
			# Eye socket (darker indent)
			for ey in range(_s(-4), _s(4)):
				for ex in range(_s(-4), _s(4)):
					if ex * ex + ey * ey <= _s(4) * _s(4):
						var socket_color = color_shadow
						socket_color.a = 0.6
						var spx = eye_x + ex
						var spy = eye_y + ey
						if spx >= 0 and spx < size and spy >= 0 and spy < size:
							var existing = img.get_pixel(spx, spy)
							if existing.a > 0:
								_sp(img, spx, spy, existing.blend(socket_color))
			# Eye white/iris
			_SU._draw_snes_eye(img, eye_x, eye_y, _s(3), Color(0.15, 0.15, 0.2), eye_side == -1)

	# Primary specular highlight (top-left, classic SNES placement)
	if pose != 4:
		var spec_x = center_x - _s(6)
		var spec_y = base_y - _s(int(12 * scale_y))
		_SU._draw_specular(img, spec_x, spec_y, 2, color_specular)

		# Secondary smaller highlight
		var spec2_x = center_x + _s(7)
		var spec2_y = base_y - _s(int(8 * scale_y))
		_sp(img, spec2_x, spec2_y, color_rim)

	# Drip details with better shading
	if pose != 4 and scale_y >= 0.9:
		var drip_y = base_y + int(radius * scale_y) - _s(2)
		var drip_positions = [_s(-9), _s(-2), _s(5)]
		var drip_lengths = [_s(4), _s(6), _s(3)]
		for i in range(3):
			var drip_x = center_x + drip_positions[i]
			var drip_len = drip_lengths[i]
			for dy in range(drip_len):
				var t = float(dy) / float(drip_len)
				var drip_width = max(1, _s(2) - dy / 2)
				for dx in range(-drip_width, drip_width + 1):
					var drip_color = color_shadow if dx > 0 else color_slime
					drip_color.a = 1.0 - t * 0.6
					_sp(img, drip_x + dx, drip_y + dy, drip_color)
				# Highlight on left side of drip
				if dy < drip_len - 1:
					_sp(img, drip_x - drip_width, drip_y + dy, color_highlight)

	# Add rim lighting on the left edge for depth
	_SU._draw_rim_light(img, center_x, base_y, radius, int(radius * scale_y), color_rim, -0.6)

	return ImageTexture.create_from_image(img)


## =================
## SKELETON (Tier B -> Tier A upgrade: add _s() scaling, outline, shine, 5+ palette)
## =================

static func create_skeleton_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("skeleton", func():
		return _generate_skeleton_sprite_frames()
	)

static func _generate_skeleton_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_skeleton_frame(0, 0.0))
	frames.add_frame("idle", _create_skeleton_frame(0, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_skeleton_frame(1, 0.0))
	frames.add_frame("attack", _create_skeleton_frame(2, -2.0))
	frames.add_frame("attack", _create_skeleton_frame(3, 0.0))
	frames.add_frame("attack", _create_skeleton_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_skeleton_frame(4, 2.0))
	frames.add_frame("hit", _create_skeleton_frame(4, -2.0))
	frames.add_frame("hit", _create_skeleton_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_skeleton_frame(5, 0.0))
	frames.add_frame("defeat", _create_skeleton_frame(5, 2.0))
	frames.add_frame("defeat", _create_skeleton_frame(6, 4.0))
	frames.add_frame("defeat", _create_skeleton_frame(7, 6.0))
	return frames


static func _create_skeleton_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var color_bone = Color(0.9, 0.88, 0.8)
	var color_bone_dark = Color(0.6, 0.55, 0.5)
	var color_bone_mid = Color(0.75, 0.72, 0.65)
	var color_bone_light = Color(1.0, 0.98, 0.95)
	var color_bone_shine = Color(1.0, 1.0, 0.95)
	var color_eye = Color(0.8, 0.2, 0.2)
	var color_eye_glow = Color(1.0, 0.4, 0.3)
	var color_outline = Color(0.2, 0.18, 0.15)

	var center_x = size / 2
	var base_y = int(size * 0.75 + _sf(y_offset))

	match pose:
		0:
			_draw_skeleton_body_enhanced(img, center_x, base_y, 0, color_bone, color_bone_dark, color_bone_mid, color_bone_light, color_bone_shine, color_eye, color_eye_glow, color_outline)
			_draw_bone_sword_enhanced(img, center_x + _s(10), base_y - _s(8), 10, color_bone, color_bone_light, color_bone_dark, color_outline)
		1:
			_draw_skeleton_body_enhanced(img, center_x, base_y, _s(-5), color_bone, color_bone_dark, color_bone_mid, color_bone_light, color_bone_shine, color_eye, color_eye_glow, color_outline)
			_draw_bone_sword_enhanced(img, center_x + _s(14), base_y - _s(12), -20, color_bone, color_bone_light, color_bone_dark, color_outline)
		2:
			_draw_skeleton_body_enhanced(img, center_x - _s(4), base_y, _s(10), color_bone, color_bone_dark, color_bone_mid, color_bone_light, color_bone_shine, color_eye, color_eye_glow, color_outline)
			_draw_bone_sword_enhanced(img, center_x - _s(10), base_y - _s(10), 45, color_bone, color_bone_light, color_bone_dark, color_outline)
		3:
			_draw_skeleton_body_enhanced(img, center_x, base_y, _s(5), color_bone, color_bone_dark, color_bone_mid, color_bone_light, color_bone_shine, color_eye, color_eye_glow, color_outline)
			_draw_bone_sword_enhanced(img, center_x - _s(8), base_y - _s(4), 80, color_bone, color_bone_light, color_bone_dark, color_outline)
		4:
			_draw_skeleton_body_enhanced(img, center_x, base_y, _s(-8), color_bone, color_bone_dark, color_bone_mid, color_bone_light, color_bone_shine, color_eye, color_eye_glow, color_outline)
		5:
			_draw_skeleton_body_enhanced(img, center_x, base_y, _s(-15), color_bone, color_bone_dark, color_bone_mid, color_bone_light, color_bone_shine, color_eye, color_eye_glow, color_outline)
		6:
			_draw_scattered_bones_enhanced(img, center_x, base_y + _s(4), 0.5, color_bone, color_bone_dark, color_outline)
		7:
			_draw_scattered_bones_enhanced(img, center_x, base_y + _s(8), 1.0, color_bone, color_bone_dark, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_skeleton_body_enhanced(img: Image, cx: int, cy: int, lean: int, bone: Color, bone_dark: Color, bone_mid: Color, bone_light: Color, bone_shine: Color, eye: Color, eye_glow: Color, outline: Color) -> void:
	"""Draw SNES-quality skeleton body with outline, shading, shine, and proper bone detail"""

	# Skull with anti-aliased outline and 4-zone shading
	var skull_x = cx + lean/4
	var skull_y = cy - _s(20)
	var skull_rx = _s(7)
	var skull_ry = _s(8)

	# Draw AA outline for smoother edges
	_SU._draw_aa_ellipse_outline(img, skull_x, skull_y, skull_rx, skull_ry, outline)

	# Skull fill with proper 4-zone shading and dithered transitions
	for y in range(-skull_ry, skull_ry + 1):
		for x in range(-skull_rx, skull_rx + 1):
			var dist = sqrt(pow(float(x) / skull_rx, 2) + pow(float(y) / skull_ry, 2))
			if dist < 0.92:
				var px = skull_x + x
				var py = skull_y + y
				var color = bone
				var v_pos = float(y) / skull_ry
				var h_pos = float(x) / skull_rx

				# 4-zone shading with dithering
				if v_pos < -0.4:
					color = bone_light
				elif v_pos < -0.2:
					# Dither transition
					color = bone_light if ((px + py) % 2 == 0) else bone
				elif v_pos > 0.4:
					color = bone_dark
				elif v_pos > 0.2:
					color = bone_mid if ((px + py) % 2 == 0) else bone_dark
				# Side shading
				if h_pos > 0.5 and v_pos > -0.3:
					color = bone_dark if v_pos > 0.2 else bone_mid
				_sp(img, px, py, color)

	# Skull specular highlight (classic placement)
	_SU._draw_specular(img, skull_x - _s(2), skull_y - _s(3), 1, bone_shine)

	# Eye sockets with glowing red eyes (iconic skeleton look)
	for eye_side in [-1, 1]:
		var ex = skull_x + eye_side * _s(3)
		var ey = skull_y
		# Dark socket
		for oy in range(_s(-2), _s(3)):
			for ox in range(_s(-2), _s(3)):
				if ox * ox + oy * oy <= _s(2) * _s(2):
					_sp(img, ex + ox, ey + oy, Color(0.03, 0.01, 0.01))
		# Glowing eye core
		_sp(img, ex, ey, eye)
		# Eye glow effect (spreads slightly)
		for gy in range(-1, 2):
			for gx in range(-1, 2):
				if gx == 0 or gy == 0:
					var glow = eye_glow
					glow.a = 0.4
					var gpx = ex + gx
					var gpy = ey + gy
					if gpx >= 0 and gpx < img.get_width() and gpy >= 0 and gpy < img.get_height():
						var existing = img.get_pixel(gpx, gpy)
						if existing.a > 0:
							_sp(img, gpx, gpy, existing.blend(glow))
		# Bright catchlight
		_sp(img, ex - 1, ey - 1, eye_glow)

	# Jaw with teeth detail
	for jx in range(_s(-4), _s(5)):
		_sp(img, skull_x + jx, skull_y + _s(5), bone_dark)
		# Individual teeth with highlights
		if abs(jx) <= _s(3) and jx % _s(2) == 0:
			_sp(img, skull_x + jx, skull_y + _s(6), bone_light)
			_sp(img, skull_x + jx, skull_y + _s(7), bone)

	# Spine with proper bone segment detail
	for seg in range(6):
		var seg_y = cy - _s(12) + seg * _s(3)
		var spine_x = cx + lean/8
		# Vertebra shape (slightly wider in middle)
		var seg_width = 2 if seg == 2 or seg == 3 else 1
		for sw in range(-seg_width, seg_width + 1):
			_sp(img, spine_x + sw, seg_y, bone if sw == 0 else bone_mid)
			_sp(img, spine_x + sw, seg_y + 1, bone_mid if sw == 0 else bone_dark)
		# Outline
		_sp(img, spine_x - seg_width - 1, seg_y, outline)
		_sp(img, spine_x + seg_width + 1, seg_y, outline)

	# Ribcage with curved ribs and proper shading
	for rib in range(4):
		var rib_y = cy - _s(10) + rib * _s(4)
		for rib_side in [-1, 1]:
			for rx in range(_s(2), _s(7)):
				var curve_y = int(float(rx - _s(2)) * 0.3)
				var rib_px = cx + rx * rib_side + lean/6
				var rib_py = rib_y + curve_y
				# Rib with shading (top light, bottom dark)
				_sp(img, rib_px, rib_py, bone_light if rib_side < 0 else bone)
				_sp(img, rib_px, rib_py + 1, bone if rib_side < 0 else bone_mid)
				# Outline on edges
				if rx == _s(6):
					_sp(img, rib_px, rib_py - 1, outline)
					_sp(img, rib_px, rib_py + 2, outline)

	# Pelvis with proper bone shape
	for y in range(_s(5), _s(10)):
		for x in range(_s(-5), _s(6)):
			var pelvis_dist = abs(x) + (y - _s(5))
			if pelvis_dist < _s(8):
				var color = bone
				if y > _s(7):
					color = bone_dark
				elif abs(x) > _s(3):
					color = bone_mid
				# Dithered edges
				if pelvis_dist > _s(6) and ((cx + x + cy + y) % 2 == 0):
					color = bone_dark
				_sp(img, cx + x + lean/8, cy + y, color)

	# Leg bones (femur and tibia) with proper joint bulges
	for leg_side in [-1, 1]:
		var lx = cx + leg_side * _s(4) + lean/10
		# Femur (thigh bone)
		for y in range(_s(10), _s(15)):
			var width = 1 if y != _s(10) and y != _s(14) else 2
			for w in range(-width, width + 1):
				_sp(img, lx + w, cy + y, bone if w <= 0 else bone_dark)
			_sp(img, lx - width - 1, cy + y, outline)
			_sp(img, lx + width + 1, cy + y, outline)
		# Knee joint (bulge)
		for ky in range(_s(-1), _s(2)):
			for kx in range(_s(-2), _s(3)):
				if abs(kx) + abs(ky) <= _s(2):
					_sp(img, lx + kx, cy + _s(15) + ky, bone_mid)
		# Tibia (shin bone)
		for y in range(_s(16), _s(20)):
			_sp(img, lx - 1, cy + y, outline)
			_sp(img, lx, cy + y, bone)
			_sp(img, lx + 1, cy + y, bone_dark)
			_sp(img, lx + 2, cy + y, outline)


static func _draw_bone_sword_enhanced(img: Image, cx: int, cy: int, angle: int, bone: Color, bone_light: Color, bone_dark: Color, outline: Color) -> void:
	"""Draw bone sword with outline and shading"""
	var length = _s(22)
	var angle_rad = deg_to_rad(angle)

	for i in range(length):
		for w in range(-2, 3):
			var px = int(cx + cos(angle_rad) * i + sin(angle_rad) * w)
			var py = int(cy + sin(angle_rad) * i - cos(angle_rad) * w)
			if abs(w) == 2:
				_sp(img, px, py, outline)
			else:
				var color = bone_light if i < _s(4) else bone if w >= 0 else bone_dark
				_sp(img, px, py, color)


static func _draw_scattered_bones_enhanced(img: Image, cx: int, cy: int, scatter: float, bone: Color, bone_dark: Color, outline: Color) -> void:
	"""Draw scattered bone pile with outline"""
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(14):
		var x = cx + int((rng.randf() - 0.5) * _s(24) * scatter)
		var y = cy + int(rng.randf() * _s(10) * scatter)
		var length = rng.randi_range(_s(3), _s(10))
		var angle = rng.randf() * PI
		for j in range(length):
			var px = x + int(cos(angle) * j)
			var py = y + int(sin(angle) * j)
			_sp(img, px - 1, py, outline)
			_sp(img, px, py, bone if j < length/2 else bone_dark)
			_sp(img, px + 1, py, outline)


## =================
## SPECTER (Tier B -> Tier A: add _s() scaling, outline, shine, 5+ palette)
## =================

static func create_specter_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("specter", func():
		return _generate_specter_sprite_frames()
	)

static func _generate_specter_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_specter_frame(0, 0.0, 1.0))
	frames.add_frame("idle", _create_specter_frame(0, -3.0, 1.0))
	frames.add_frame("idle", _create_specter_frame(0, -4.0, 0.95))
	frames.add_frame("idle", _create_specter_frame(0, -2.0, 1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.5)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_specter_frame(1, 0.0, 1.0))
	frames.add_frame("attack", _create_specter_frame(2, -4.0, 0.8))
	frames.add_frame("attack", _create_specter_frame(3, -2.0, 1.2))
	frames.add_frame("attack", _create_specter_frame(0, 0.0, 1.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_specter_frame(4, 0.0, 0.6))
	frames.add_frame("hit", _create_specter_frame(4, 0.0, 1.0))
	frames.add_frame("hit", _create_specter_frame(0, 0.0, 1.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_specter_frame(5, 0.0, 1.0))
	frames.add_frame("defeat", _create_specter_frame(5, -2.0, 0.7))
	frames.add_frame("defeat", _create_specter_frame(5, -4.0, 0.4))
	frames.add_frame("defeat", _create_specter_frame(5, -6.0, 0.1))
	return frames


static func _create_specter_frame(pose: int, y_offset: float, alpha: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var color_body = Color(0.7, 0.8, 0.95, alpha * 0.7)
	var color_body_light = Color(0.9, 0.95, 1.0, alpha * 0.9)
	var color_body_dark = Color(0.4, 0.5, 0.7, alpha * 0.5)
	var color_body_shine = Color(0.95, 0.98, 1.0, alpha * 0.95)
	var color_eye = Color(0.3, 0.9, 1.0, alpha)
	var color_eye_glow = Color(0.5, 1.0, 1.0, alpha)
	var color_outline = Color(0.2, 0.3, 0.5, alpha * 0.6)

	var center_x = size / 2
	var base_y = int(size * 0.55 + _sf(y_offset))

	var lean = 0
	var stretch = 1.0
	match pose:
		1: lean = _s(-5)
		2: lean = _s(10); stretch = 0.8
		3: lean = _s(15); stretch = 1.2
		4: stretch = 0.6
		5: stretch = 0.5

	# Hooded body with outline and shading
	for y in range(_s(-22), _s(22)):
		var width = _s(14) - abs(y) / 3
		if y > 0:
			width = _s(14) - y / 2
		for x in range(-int(width * stretch), int(width * stretch)):
			var px = center_x + x + lean/3
			var py = base_y + y
			if px >= 0 and px < size and py >= 0 and py < size:
				var dist_from_center = abs(x) / float(max(width, 1))
				var vert_fade = 1.0 - max(0, (y - _s(5)) / _sf(15))
				var color = color_body
				if y < _s(-10): color = color_body_light
				elif x < -width/2: color = color_body_dark
				elif dist_from_center > 0.7: color = color_body_dark
				# Outline at edges
				if dist_from_center > 0.85:
					color = color_outline
				color.a = color.a * vert_fade * alpha
				if color.a > 0.1:
					img.set_pixel(px, py, color)

	# Shine spot on hood
	if pose != 5:
		_sp(img, center_x - _s(3) + lean/3, base_y - _s(16), color_body_shine)
		_sp(img, center_x - _s(2) + lean/3, base_y - _s(16), color_body_shine)

	# Glowing eyes with halo
	if pose != 5:
		for eye_side in [-1, 1]:
			var ex = center_x + eye_side * _s(5) + lean/4
			var ey = base_y - _s(8)
			# Eye glow halo
			for gy in range(_s(-3), _s(4)):
				for gx in range(_s(-3), _s(4)):
					var dist = sqrt(gx * gx + gy * gy)
					if dist < _sf(3):
						var ga = alpha * (1.0 - dist / _sf(3)) * 0.5
						if ga > 0.1:
							var gcolor = color_eye_glow
							gcolor.a = ga
							var gpx = ex + gx
							var gpy = ey + gy
							if gpx >= 0 and gpx < size and gpy >= 0 and gpy < size:
								var existing = img.get_pixel(gpx, gpy)
								if existing.a > 0:
									_sp(img, gpx, gpy, existing.blend(gcolor))
								else:
									_sp(img, gpx, gpy, gcolor)
			# Eye core
			for ey2 in range(_s(-2), _s(2)):
				for ex2 in range(_s(-2), _s(2)):
					if ex2 * ex2 + ey2 * ey2 <= _s(2) * _s(2):
						var glow = color_eye
						glow.a = alpha
						_sp(img, ex + ex2, ey + ey2, glow)
			# Catchlight
			_sp(img, ex - 1, ey - 1, Color(1.0, 1.0, 1.0, alpha))

	# Wispy trails
	var rng = RandomNumberGenerator.new()
	rng.seed = pose * 100
	for i in range(10):
		var trail_x = center_x + int((rng.randf() - 0.5) * _s(18)) + lean/4
		var trail_start = base_y + _s(12)
		for ty in range(_s(8)):
			var tpx = trail_x + int(sin(ty * 0.5 + i) * _sf(3))
			var tpy = trail_start + ty
			if tpx >= 0 and tpx < size and tpy >= 0 and tpy < size:
				var trail_color = color_body_dark
				trail_color.a = alpha * 0.35 * (1.0 - float(ty) / _sf(8))
				if trail_color.a > 0.05:
					img.set_pixel(tpx, tpy, trail_color)

	return ImageTexture.create_from_image(img)


## =================
## IMP (Tier B -> Tier A: add _s() scaling, outline, shine, 5+ palette)
## =================

static func create_imp_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("imp", func(): return _generate_imp_sprite_frames())

static func _generate_imp_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 4.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_imp_frame(0, 0.0))
	frames.add_frame("idle", _create_imp_frame(0, -2.0))
	frames.add_frame("idle", _create_imp_frame(0, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.5)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_imp_frame(1, 0.0))
	frames.add_frame("attack", _create_imp_frame(2, -2.0))
	frames.add_frame("attack", _create_imp_frame(3, -1.0))
	frames.add_frame("attack", _create_imp_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_imp_frame(4, 2.0))
	frames.add_frame("hit", _create_imp_frame(4, 0.0))
	frames.add_frame("hit", _create_imp_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_imp_frame(5, 0.0))
	frames.add_frame("defeat", _create_imp_frame(5, 3.0))
	frames.add_frame("defeat", _create_imp_frame(6, 6.0))
	frames.add_frame("defeat", _create_imp_frame(7, 10.0))
	return frames


static func _create_imp_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var color_body = Color(0.8, 0.25, 0.2)
	var color_body_dark = Color(0.5, 0.15, 0.1)
	var color_body_mid = Color(0.65, 0.2, 0.15)
	var color_body_light = Color(0.95, 0.4, 0.3)
	var color_body_shine = Color(1.0, 0.55, 0.45)
	var color_wing = Color(0.6, 0.1, 0.15)
	var color_wing_dark = Color(0.4, 0.05, 0.08)
	var color_eye = Color(1.0, 0.9, 0.2)
	var color_horn = Color(0.3, 0.2, 0.15)
	var color_outline = Color(0.2, 0.08, 0.06)

	var center_x = size / 2
	var base_y = int(size * 0.65 + _sf(y_offset))

	var lean = 0
	var wing_up = false
	match pose:
		0: wing_up = true
		1: lean = _s(-8)
		2: lean = _s(12); wing_up = true
		3: lean = _s(6)
		4: lean = _s(-15)
		5: lean = _s(-10)
		6, 7: pass

	if pose >= 6:
		# Collapsed imp with outline
		for y in range(_s(-5), _s(5)):
			for x in range(_s(-10), _s(10)):
				var dist = sqrt(pow(float(x) / _sf(10), 2) + pow(float(y) / _sf(4), 2))
				if dist < 1.0:
					_sp(img, center_x + x, base_y + y + _s(8), color_body_dark if dist > 0.7 else color_body_mid)
				elif dist < 1.1:
					_sp(img, center_x + x, base_y + y + _s(8), color_outline)
		return ImageTexture.create_from_image(img)

	# Wings with membrane detail and outline
	var wing_y_offset = _s(-8) if wing_up else _s(-4)
	for wx_side in [-1, 1]:
		var wing_x = center_x + wx_side * _s(12) + lean/4
		for wy in range(_s(-8), _s(5)):
			for wxx in range(_s(8)):
				var dist = (wxx + abs(wy)) / _sf(10)
				if dist < 1.0:
					var px = wing_x + (wxx if wx_side > 0 else -wxx)
					var py = base_y + wy + wing_y_offset
					var color = color_wing if dist < 0.8 else color_wing_dark
					# Wing vein detail
					if wxx % _s(3) == 0:
						color = color_wing_dark
					_sp(img, px, py, color)
				elif dist < 1.1:
					_sp(img, wing_x + (wxx if wx_side > 0 else -wxx), base_y + wy + wing_y_offset, color_outline)

	# Head with outline
	var head_rx = _s(6)
	var head_ry = _s(5)
	var head_x = center_x + lean/6
	var head_y = base_y - _s(15)
	_SU._draw_ellipse_outline(img, head_x, head_y, head_rx, head_ry, color_outline)
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			if sqrt(pow(float(x)/head_rx, 2) + pow(float(y)/head_ry, 2)) < 0.95:
				var color = color_body
				if y < -head_ry * 0.3: color = color_body_light
				elif x < -head_rx * 0.3: color = color_body_dark
				_sp(img, head_x + x, head_y + y, color)

	# Shine on head
	_sp(img, head_x - _s(2), head_y - _s(2), color_body_shine)

	# Horns with shading
	for hx_side in [-1, 1]:
		for hy in range(_s(-6), 0):
			var hw = _s(2) - abs(hy) / 3
			for hxx in range(-hw, hw + 1):
				var px = head_x + hx_side * _s(5) + hxx + lean/8
				var py = head_y - _s(6) + hy
				_sp(img, px, py, color_horn if hxx <= 0 else color_horn.lightened(0.15))

	# Eyes with glow
	for ex_side in [-1, 1]:
		var eye_x = head_x + ex_side * _s(3)
		var eye_y = head_y - _s(1)
		_sp(img, eye_x, eye_y, color_eye)
		_sp(img, eye_x + ex_side, eye_y, color_eye)
		_sp(img, eye_x, eye_y - 1, Color.WHITE)  # Catchlight

	# Body with outline
	var body_rx = _s(5)
	var body_ry = _s(8)
	_SU._draw_ellipse_outline(img, center_x + lean/5, base_y - _s(5), body_rx, body_ry, color_outline)
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			if sqrt(pow(float(x)/body_rx, 2) + pow(float(y)/body_ry, 2)) < 0.9:
				var color = color_body
				if x < -body_rx/2: color = color_body_dark
				elif x > body_rx/2: color = color_body_light
				elif y > body_ry * 0.5: color = color_body_mid
				_sp(img, center_x + x + lean/5, base_y - _s(5) + y, color)

	# Tail with thickness
	for i in range(_s(12)):
		var tail_x = center_x + _s(5) + i + lean/6
		var tail_y = base_y + int(sin(i * 0.4) * _sf(4))
		for tw in range(-1, 2):
			_sp(img, tail_x, tail_y + tw, color_body_dark)

	# Legs
	for leg_side in [-1, 1]:
		for y in range(_s(2), _s(10)):
			var lx = center_x + leg_side * _s(3) + lean/8
			_sp(img, lx - 1, base_y + y, color_outline)
			_sp(img, lx, base_y + y, color_body_mid)
			_sp(img, lx + 1, base_y + y, color_body_dark)

	return ImageTexture.create_from_image(img)


## =================
## WOLF (Tier C -> Tier A: FULL REWRITE)
## =================

static func create_wolf_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("wolf", func(): return _generate_wolf_sprite_frames())

static func _generate_wolf_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_wolf_frame(0, 0.0))
	frames.add_frame("idle", _create_wolf_frame(0, -0.5))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_wolf_frame(1, 0.0))
	frames.add_frame("attack", _create_wolf_frame(2, -3.0))
	frames.add_frame("attack", _create_wolf_frame(3, -1.0))
	frames.add_frame("attack", _create_wolf_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_wolf_frame(4, 1.0))
	frames.add_frame("hit", _create_wolf_frame(4, 0.0))
	frames.add_frame("hit", _create_wolf_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_wolf_frame(5, 0.0))
	frames.add_frame("defeat", _create_wolf_frame(5, 2.0))
	frames.add_frame("defeat", _create_wolf_frame(6, 4.0))
	return frames


static func _create_wolf_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-quality 6-color fur palette
	var fur = Color(0.35, 0.3, 0.28)
	var fur_dark = Color(0.18, 0.15, 0.13)
	var fur_mid = Color(0.28, 0.24, 0.22)
	var fur_light = Color(0.5, 0.45, 0.4)
	var fur_shine = Color(0.6, 0.55, 0.5)
	var eye_color = Color(0.9, 0.6, 0.1)
	var eye_glow = Color(1.0, 0.8, 0.3)
	var teeth_color = Color(0.95, 0.95, 0.9)
	var nose_color = Color(0.15, 0.12, 0.1)
	var outline = Color(0.1, 0.08, 0.06)

	var cx = size / 2
	var cy = int(size * 0.7 + _sf(y_offset))

	var crouch = 0
	var lunge = 0
	var mouth_open = false
	match pose:
		1: crouch = _s(4)
		2: lunge = _s(-8); crouch = _s(-2)
		3: lunge = _s(-4); mouth_open = true
		4: crouch = _s(2)
		5, 6: crouch = _s(6)

	if pose == 6:
		# Collapsed wolf with outline
		for y in range(_s(-5), _s(8)):
			for x in range(_s(-18), _s(18)):
				var dist = sqrt(pow(float(x) / _sf(18), 2) + pow(float(y) / _sf(5), 2))
				if dist < 1.0:
					_sp(img, cx + x, cy + y + _s(4), fur_dark if dist > 0.6 else fur_mid)
				elif dist < 1.1:
					_sp(img, cx + x, cy + y + _s(4), outline)
		return ImageTexture.create_from_image(img)

	# Body (elliptical with fur texture) - outline first
	var body_rx = _s(14)
	var body_ry = _s(8)
	var body_cx = cx + lunge
	var body_cy = cy - _s(2) + crouch

	_SU._draw_ellipse_outline(img, body_cx, body_cy, body_rx + 1, body_ry + 1, outline)

	# Body fill with fur texture
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var color = fur
				if y < -body_ry * 0.3: color = fur_light
				elif y > body_ry * 0.3: color = fur_dark
				if x < -body_rx * 0.5: color = fur_mid
				# Fur texture (subtle noise)
				if (x + y * 3) % _s(5) < _s(1):
					color = color.darkened(0.06)
				_sp(img, body_cx + x, body_cy + y, color)

	# Body shine
	_sp(img, body_cx - _s(4), body_cy - _s(4), fur_shine)
	_sp(img, body_cx - _s(3), body_cy - _s(4), fur_shine)

	# Head (elongated ellipse with outline)
	var head_x = cx - _s(16) + lunge
	var head_y = cy - _s(6) + crouch
	var head_rx = _s(10)
	var head_ry = _s(7)

	_SU._draw_ellipse_outline(img, head_x, head_y, head_rx + 1, head_ry + 1, outline)
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = fur
				if y < -head_ry * 0.3: color = fur_light
				elif x < -head_rx * 0.3: color = fur_mid
				_sp(img, head_x + x, head_y + y, color)

	# Snout with nostrils
	var snout_x = head_x - _s(8)
	var snout_y = head_y + _s(2)
	for y in range(_s(-3), _s(4)):
		for x in range(_s(-8), _s(2)):
			var dist = sqrt(pow(float(x + _s(3)) / _sf(5), 2) + pow(float(y) / _sf(3), 2))
			if dist < 1.0:
				_sp(img, snout_x + x, snout_y + y, fur if y < 0 else fur_mid)
			elif dist < 1.15:
				_sp(img, snout_x + x, snout_y + y, outline)
	# Nose
	for ny in range(_s(-1), _s(2)):
		for nx in range(_s(-2), _s(2)):
			if nx * nx + ny * ny <= _s(2) * _s(2):
				_sp(img, snout_x - _s(5) + nx, snout_y + ny, nose_color)
	# Nostrils
	_sp(img, snout_x - _s(5) - 1, snout_y - 1, Color(0.05, 0.03, 0.02))
	_sp(img, snout_x - _s(5) + 1, snout_y - 1, Color(0.05, 0.03, 0.02))

	# Eyes (3px with amber glow)
	var eye_x = head_x - _s(3)
	var eye_y = head_y - _s(3)
	for ey in range(_s(-2), _s(2)):
		for ex in range(_s(-2), _s(2)):
			if ex * ex + ey * ey <= _s(2) * _s(2):
				_sp(img, eye_x + ex, eye_y + ey, eye_color)
	_sp(img, eye_x, eye_y, Color.BLACK)  # Pupil
	_sp(img, eye_x - 1, eye_y - 1, eye_glow)  # Catchlight

	# Teeth/mouth
	if mouth_open:
		for tx in range(_s(-6), _s(-1)):
			_sp(img, snout_x + tx, snout_y + _s(3), teeth_color)
			_sp(img, snout_x + tx, snout_y + _s(4), outline)
		# Fangs
		_sp(img, snout_x - _s(5), snout_y + _s(3), teeth_color)
		_sp(img, snout_x - _s(5), snout_y + _s(4), teeth_color)
		_sp(img, snout_x - _s(2), snout_y + _s(3), teeth_color)

	# Ears (triangular with inner detail)
	for ear_side in [0, 1]:
		var ear_x = head_x - _s(5) + ear_side * _s(5)
		var ear_y = head_y - _s(8)
		for ey in range(_s(6)):
			var ew = _s(3) - ey / 2
			for ex in range(-ew, ew + 1):
				var color = fur_dark
				if abs(ex) < ew - 1 and ey > _s(1):
					color = Color(0.5, 0.35, 0.3)  # Inner ear pink
				_sp(img, ear_x + ex, ear_y + ey, color)

	# Thick legs with paws (4 legs)
	var leg_data = [
		[cx - _s(10) + lunge, cy + _s(4) + crouch],
		[cx - _s(4) + lunge, cy + _s(4) + crouch],
		[cx + _s(4) + lunge, cy + _s(4) + crouch],
		[cx + _s(8) + lunge, cy + _s(4) + crouch]
	]
	for leg in leg_data:
		var lx = int(leg[0])
		var ly = int(leg[1])
		for leg_y in range(_s(10) - crouch):
			var lw = _s(3) - leg_y / 6
			for lwx in range(-lw, lw + 1):
				_sp(img, lx + lwx, ly + leg_y, fur_dark if lwx < 0 else fur_mid)
			# Outline
			_sp(img, lx - lw - 1, ly + leg_y, outline)
			_sp(img, lx + lw + 1, ly + leg_y, outline)
		# Paw
		for px in range(_s(-3), _s(3)):
			_sp(img, lx + px, ly + _s(10) - crouch, fur_dark)
			_sp(img, lx + px, ly + _s(10) - crouch + 1, outline)

	# Curved tail with shading
	for i in range(_s(14)):
		var t = float(i) / _sf(14)
		var tail_x = cx + _s(10) + lunge + int(cos(t * 1.5) * _sf(4))
		var tail_y = cy - _s(6) + crouch - int(t * _sf(10))
		var tw = _s(2) - int(t * _sf(1.5))
		for twx in range(-tw, tw + 1):
			_sp(img, tail_x, tail_y + twx, fur if twx >= 0 else fur_dark)
		_sp(img, tail_x, tail_y - tw - 1, outline)
		_sp(img, tail_x, tail_y + tw + 1, outline)

	return ImageTexture.create_from_image(img)


## =================
## VIPER (Tier B -> Tier A)
## =================

static func create_viper_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("viper", func(): return _generate_viper_sprite_frames())

static func _generate_viper_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_viper_frame(0, 0.0))
	frames.add_frame("idle", _create_viper_frame(0, -1.0))
	frames.add_frame("idle", _create_viper_frame(0, 0.5))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 6.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_viper_frame(1, 0.0))
	frames.add_frame("attack", _create_viper_frame(2, -2.0))
	frames.add_frame("attack", _create_viper_frame(3, -1.0))
	frames.add_frame("attack", _create_viper_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_viper_frame(4, 1.0))
	frames.add_frame("hit", _create_viper_frame(4, 0.0))
	frames.add_frame("hit", _create_viper_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_viper_frame(5, 0.0))
	frames.add_frame("defeat", _create_viper_frame(6, 2.0))
	frames.add_frame("defeat", _create_viper_frame(7, 4.0))
	return frames


static func _create_viper_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var scale_c = Color(0.25, 0.45, 0.2)
	var scale_dark = Color(0.15, 0.3, 0.1)
	var scale_mid = Color(0.2, 0.38, 0.15)
	var scale_light = Color(0.4, 0.6, 0.3)
	var scale_shine = Color(0.5, 0.7, 0.4)
	var belly = Color(0.7, 0.65, 0.5)
	var eye_c = Color(0.9, 0.7, 0.1)
	var tongue_c = Color(0.9, 0.2, 0.3)
	var outline = Color(0.1, 0.18, 0.06)

	var cx = size / 2
	var cy = int(size * 0.65 + _sf(y_offset))

	var strike = 0
	var coil_tight = 1.0
	var show_tongue = false
	match pose:
		1: coil_tight = 1.3
		2: strike = _s(-12); show_tongue = true
		3: strike = _s(-8); show_tongue = true
		4: strike = _s(4)
		5: coil_tight = 0.8
		6: coil_tight = 0.5
		7: coil_tight = 0.2

	if pose == 7:
		for x in range(_s(-22), _s(22)):
			for tw in range(-2, 3):
				var color = scale_dark if tw < 0 else belly if tw > 0 else scale_c
				_sp(img, cx + x, cy + _s(8) + tw, color)
			_sp(img, cx + x, cy + _s(8) - 3, outline)
			_sp(img, cx + x, cy + _s(8) + 3, outline)
		return ImageTexture.create_from_image(img)

	# Coiled body (thicker with outline and scale pattern)
	for coil in range(3):
		var coil_y = cy + int(coil * _s(6) * coil_tight)
		var coil_radius = (_s(14) - coil * _s(3)) * coil_tight
		for angle in range(0, 360, 10):
			var rad = deg_to_rad(angle)
			var bx = cx + int(cos(rad) * coil_radius)
			var by = int(coil_y + sin(rad) * coil_radius * 0.4)
			# Thicker body with shading
			for thick in range(_s(-2), _s(3)):
				var color = scale_c
				if thick < 0: color = scale_light
				elif thick > _s(1): color = belly
				if angle % 30 < 10: color = color.darkened(0.08)  # Scale pattern
				_sp(img, bx, by + thick, color)
			# Outline
			_sp(img, bx, by - _s(2) - 1, outline)
			_sp(img, bx, by + _s(2) + 1, outline)

	# Head with outline
	var head_x = cx - _s(10) + strike
	var head_y = cy - _s(14)
	var head_rx = _s(8)
	var head_ry = _s(5)

	_SU._draw_ellipse_outline(img, head_x, head_y, head_rx + 1, head_ry + 1, outline)
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = scale_c
				if y < -_s(1): color = scale_light
				elif y > _s(1): color = belly
				_sp(img, head_x + x, head_y + y, color)

	# Shine on head
	_sp(img, head_x - _s(2), head_y - _s(2), scale_shine)

	# Eyes (slit pupils)
	var eye_x = head_x - _s(4)
	var eye_y = head_y - _s(1)
	for ey in range(_s(-2), _s(2)):
		for ex in range(_s(-1), _s(2)):
			_sp(img, eye_x + ex, eye_y + ey, eye_c)
	# Slit pupil
	for ey in range(_s(-2), _s(2)):
		_sp(img, eye_x, eye_y + ey, Color.BLACK)
	_sp(img, eye_x - 1, eye_y - 1, Color.WHITE)  # Catchlight

	# Tongue (forked)
	if show_tongue:
		for tx in range(_s(-10), _s(-3)):
			_sp(img, head_x + tx, head_y + _s(1), tongue_c)
		_sp(img, head_x - _s(10), head_y, tongue_c)
		_sp(img, head_x - _s(10), head_y + _s(2), tongue_c)

	# Hood pattern (diamond marking)
	var hood_x = head_x + _s(3)
	var hood_y = head_y + _s(1)
	for hy in range(_s(-3), _s(4)):
		for hx in range(_s(-2), _s(3)):
			if abs(hx) + abs(hy) < _s(3):
				_sp(img, hood_x + hx, hood_y + hy, scale_shine)

	return ImageTexture.create_from_image(img)


## =================
## BAT (Tier C -> Tier A: FULL REWRITE)
## =================

static func create_bat_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("bat", func(): return _generate_bat_sprite_frames())

static func _generate_bat_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 6.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_bat_frame(0, 0.0))
	frames.add_frame("idle", _create_bat_frame(1, -1.0))
	frames.add_frame("idle", _create_bat_frame(2, -2.0))
	frames.add_frame("idle", _create_bat_frame(1, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_bat_frame(3, 0.0))
	frames.add_frame("attack", _create_bat_frame(4, 2.0))
	frames.add_frame("attack", _create_bat_frame(5, 0.0))
	frames.add_frame("attack", _create_bat_frame(0, -1.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_bat_frame(6, 1.0))
	frames.add_frame("hit", _create_bat_frame(6, 0.0))
	frames.add_frame("hit", _create_bat_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_bat_frame(6, 0.0))
	frames.add_frame("defeat", _create_bat_frame(7, 4.0))
	frames.add_frame("defeat", _create_bat_frame(7, 8.0))
	return frames


static func _create_bat_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-quality 6-color palette
	var fur = Color(0.35, 0.25, 0.4)
	var fur_dark = Color(0.2, 0.12, 0.25)
	var fur_mid = Color(0.28, 0.2, 0.33)
	var fur_light = Color(0.48, 0.38, 0.55)
	var wing_c = Color(0.3, 0.2, 0.35)
	var wing_dark = Color(0.15, 0.1, 0.2)
	var wing_vein = Color(0.25, 0.15, 0.3)
	var eye_c = Color(0.9, 0.2, 0.2)
	var eye_glow = Color(1.0, 0.4, 0.3)
	var fang_c = Color(0.95, 0.95, 0.9)
	var ear_pink = Color(0.6, 0.35, 0.4)
	var outline = Color(0.1, 0.06, 0.12)

	var cx = size / 2
	var cy = int(size * 0.5 + _sf(y_offset))

	var wing_angle = 0
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
		# Fallen bat with wings spread
		for y in range(_s(-3), _s(5)):
			for x in range(_s(-16), _s(16)):
				var dist = sqrt(pow(float(x) / _sf(16), 2) + pow(float(y) / _sf(4), 2))
				if dist < 1.0:
					_sp(img, cx + x, cy + y + _s(8), wing_dark if abs(x) > _s(5) else fur_dark)
				elif dist < 1.1:
					_sp(img, cx + x, cy + y + _s(8), outline)
		return ImageTexture.create_from_image(img)

	# Wings with membrane, vein detail, and outline
	var wing_y_offsets = [_s(-10), 0, _s(8)]
	var wing_y_base = wing_y_offsets[wing_angle]

	for side in [-1, 1]:
		for i in range(_s(18)):
			var wing_x = cx + side * (_s(4) + i)
			var wing_height = _s(8) - i / 3
			var wy = cy + wing_y_base + int(i * 0.3) * (1 if wing_angle == 2 else -1 if wing_angle == 0 else 0)

			for w_y in range(-wing_height, wing_height):
				var color = wing_c
				if abs(w_y) > wing_height - _s(2):
					color = outline  # Wing edge outline
				elif i % _s(5) < _s(1):
					color = wing_vein  # Wing bone/vein
				elif abs(w_y) < wing_height / 2:
					# Semi-transparent membrane center
					color = wing_c
				else:
					color = wing_dark
				_sp(img, wing_x, wy + w_y, color)

	# Fur body (elliptical with 3-zone shading)
	var body_lean = _s(10) if diving else (_s(-10) if tumble else 0)
	var body_rx = _s(5)
	var body_ry = _s(7)

	_SU._draw_ellipse_outline(img, cx + body_lean / 10, cy, body_rx + 1, body_ry + 1, outline)

	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var color = fur
				if y < -body_ry * 0.3: color = fur_light  # Top zone
				elif y > body_ry * 0.3: color = fur_dark   # Bottom zone
				elif x < -body_rx * 0.3: color = fur_mid   # Side
				_sp(img, cx + x + body_lean / 10, cy + y, color)

	# Head with detail
	var head_y = cy - _s(10)
	var head_rx2 = _s(5)
	var head_ry2 = _s(4)

	_SU._draw_ellipse_outline(img, cx, head_y, head_rx2 + 1, head_ry2 + 1, outline)
	for y in range(-head_ry2, head_ry2 + 1):
		for x in range(-head_rx2, head_rx2 + 1):
			var dist = sqrt(pow(float(x) / head_rx2, 2) + pow(float(y) / head_ry2, 2))
			if dist < 1.0:
				_sp(img, cx + x, head_y + y, fur if y > -_s(1) else fur_light)

	# Triangular ears with inner pink
	for ear_side in [-1, 1]:
		var ear_x = cx + ear_side * _s(4)
		var ear_y = head_y - _s(6)
		for ey in range(_s(6)):
			var ew = _s(3) - ey / 2
			for ex in range(-ew, ew + 1):
				if abs(ex) < ew - 1 and ey > _s(1):
					_sp(img, ear_x + ex, ear_y + ey, ear_pink)  # Inner pink
				else:
					_sp(img, ear_x + ex, ear_y + ey, fur_dark)

	# Red eyes with glow
	for eye_side in [-1, 1]:
		var ex = cx + eye_side * _s(3)
		var ey = head_y - _s(1)
		for ey2 in range(_s(-1), _s(2)):
			for ex2 in range(_s(-1), _s(2)):
				if ex2 * ex2 + ey2 * ey2 <= _s(1) * _s(1):
					_sp(img, ex + ex2, ey + ey2, eye_c)
		_sp(img, ex - 1, ey - 1, eye_glow)  # Glow/catchlight

	# 2-3px fangs
	for fx in [-1, 1]:
		var fang_x = cx + fx * _s(1)
		for fy in range(_s(3)):
			_sp(img, fang_x, head_y + _s(3) + fy, fang_c)
			if fy == _s(2):
				_sp(img, fang_x, head_y + _s(3) + fy, fang_c.darkened(0.1))

	return ImageTexture.create_from_image(img)


## =================
## FUNGOID (Tier B -> Tier A)
## =================

static func create_fungoid_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("fungoid", func(): return _generate_fungoid_sprite_frames())

static func _generate_fungoid_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_fungoid_frame(0, 0.0, 1.0))
	frames.add_frame("idle", _create_fungoid_frame(0, -1.0, 1.02))
	frames.add_frame("idle", _create_fungoid_frame(0, 0.0, 0.98))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_fungoid_frame(1, 0.0, 1.0))
	frames.add_frame("attack", _create_fungoid_frame(2, -1.0, 1.1))
	frames.add_frame("attack", _create_fungoid_frame(3, 0.0, 0.9))
	frames.add_frame("attack", _create_fungoid_frame(0, 0.0, 1.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_fungoid_frame(4, 0.0, 0.9))
	frames.add_frame("hit", _create_fungoid_frame(4, 1.0, 1.0))
	frames.add_frame("hit", _create_fungoid_frame(0, 0.0, 1.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_fungoid_frame(5, 0.0, 1.0))
	frames.add_frame("defeat", _create_fungoid_frame(5, 2.0, 0.8))
	frames.add_frame("defeat", _create_fungoid_frame(6, 4.0, 0.5))
	return frames


static func _create_fungoid_frame(pose: int, y_offset: float, fn_scale: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cap = Color(0.6, 0.35, 0.25)
	var cap_dark = Color(0.4, 0.2, 0.15)
	var cap_mid = Color(0.5, 0.28, 0.2)
	var cap_light = Color(0.75, 0.5, 0.35)
	var cap_shine = Color(0.85, 0.6, 0.45)
	var spots = Color(0.95, 0.9, 0.8)
	var stem = Color(0.8, 0.75, 0.65)
	var stem_dark = Color(0.65, 0.58, 0.5)
	var eye_c = Color(0.2, 0.15, 0.1)
	var outline = Color(0.2, 0.1, 0.08)

	var cx = size / 2
	var cy = int(size * 0.7 + _sf(y_offset))

	var lean = 0
	var show_spores = false
	match pose:
		1: lean = _s(-3)
		2: lean = _s(-5)
		3: show_spores = true
		4: lean = _s(8)
		5: lean = _s(15)
		6: lean = _s(25)

	# Stem with outline and shading
	var stem_height = int(_s(14) * fn_scale)
	for y in range(0, stem_height):
		var width = int((_s(5) + y / 3) * fn_scale)
		for x in range(-width - 1, width + 2):
			var px = cx + x + lean/3
			var py = cy + y - _s(4)
			if abs(x) == width + 1:
				_sp(img, px, py, outline)
			else:
				var color = stem if x > -width/2 else stem_dark
				_sp(img, px, py, color)

	# Cap (dome shape with outline and multi-zone shading)
	var cap_radius = int(_s(16) * fn_scale)
	var cap_height = int(_s(14) * fn_scale)
	var cap_y = cy - _s(10)

	# Cap outline
	for y in range(-cap_height - 1, _s(5)):
		var y_factor = abs(y) / float(max(cap_height, 1))
		var width = int(cap_radius * sqrt(max(0, 1 - y_factor * y_factor * 0.7)))
		_sp(img, cx - width - 1 + lean/4, cap_y + y, outline)
		_sp(img, cx + width + 1 + lean/4, cap_y + y, outline)

	# Cap fill
	for y in range(-cap_height, _s(4)):
		var y_factor = abs(y) / float(max(cap_height, 1))
		var width = int(cap_radius * sqrt(max(0, 1 - y_factor * y_factor * 0.7)))
		for x in range(-width, width + 1):
			var color = cap
			if y < -cap_height/2: color = cap_light
			elif y > 0: color = cap_dark
			elif abs(x) > width - _s(3): color = cap_mid
			_sp(img, cx + x + lean/4, cap_y + y, color)

	# Cap shine
	_sp(img, cx - _s(4) + lean/4, cap_y - cap_height/2, cap_shine)
	_sp(img, cx - _s(3) + lean/4, cap_y - cap_height/2, cap_shine)

	# Spots on cap
	var spot_positions = [[_s(-7), _s(-8)], [_s(5), _s(-6)], [_s(-2), _s(-10)], [_s(9), _s(-4)]]
	for spot in spot_positions:
		var sx = cx + int(spot[0] * fn_scale) + lean/4
		var sy = cap_y + int(spot[1] * fn_scale / 2) + _s(4)
		for sy2 in range(_s(-2), _s(3)):
			for sx2 in range(_s(-2), _s(3)):
				if abs(sx2) + abs(sy2) < _s(3):
					_sp(img, sx + sx2, sy + sy2, spots)

	# Eyes with catchlights
	if pose < 6:
		for ex_side in [-1, 1]:
			var eye_x = cx + ex_side * _s(4) + lean/4
			var eye_y = cy - _s(2)
			for ey in range(_s(-2), _s(2)):
				for exx in range(_s(-2), _s(2)):
					if exx * exx + ey * ey <= _s(2) * _s(2):
						_sp(img, eye_x + exx, eye_y + ey, eye_c)
			_sp(img, eye_x - 1, eye_y - 1, Color.WHITE)  # Catchlight

	# Spores (when attacking)
	if show_spores:
		var rng = RandomNumberGenerator.new()
		rng.seed = 54321
		for i in range(16):
			var spore_x = cx + int((rng.randf() - 0.5) * _s(35))
			var spore_y = cap_y - _s(10) - int(rng.randf() * _s(18))
			for sy in range(-1, 2):
				for sx in range(-1, 2):
					if abs(sx) + abs(sy) < 2:
						_sp(img, spore_x + sx, spore_y + sy, Color(0.8, 0.9, 0.6, 0.8))

	return ImageTexture.create_from_image(img)


## =================
## GOBLIN (already Tier A - fully extracted from BattleAnimator)
## =================

static func create_goblin_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("goblin", func(): return _generate_goblin_sprite_frames())

static func _generate_goblin_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_goblin_frame(0, 0.0))
	frames.add_frame("idle", _create_goblin_frame(0, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_goblin_frame(1, 0.0))
	frames.add_frame("attack", _create_goblin_frame(2, -1.0))
	frames.add_frame("attack", _create_goblin_frame(3, 0.0))
	frames.add_frame("attack", _create_goblin_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_goblin_frame(4, 2.0))
	frames.add_frame("hit", _create_goblin_frame(4, 1.0))
	frames.add_frame("hit", _create_goblin_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_goblin_frame(5, 0.0))
	frames.add_frame("defeat", _create_goblin_frame(5, 3.0))
	frames.add_frame("defeat", _create_goblin_frame(6, 6.0))
	return frames


static func _create_goblin_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Generate SNES-style 5-shade palette for goblin skin (more vibrant green)
	var base_green = Color(0.42, 0.55, 0.32)
	var skin_palette = _SU.make_5shade_palette(base_green)
	var color_skin_deep = skin_palette[0]
	var color_skin_dark = skin_palette[1]
	var color_skin = skin_palette[2]
	var color_skin_light = skin_palette[3]
	var color_skin_rim = skin_palette[4]

	# Cloth palette
	var cloth_palette = _SU.make_4shade_palette(Color(0.5, 0.35, 0.25))
	var color_cloth_deep = cloth_palette[0]
	var color_cloth_dark = cloth_palette[1]
	var color_cloth = cloth_palette[2]
	var color_cloth_light = cloth_palette[3]

	var color_eye = Color(0.95, 0.78, 0.15)
	var color_eye_glow = Color(1.0, 0.92, 0.35)
	var color_club = Color(0.48, 0.35, 0.22)
	var color_club_dark = Color(0.32, 0.22, 0.14)
	var color_outline = Color(0.12, 0.18, 0.08)

	var center_x = size / 2
	var base_y = int(size * 0.72 + _sf(y_offset))

	_draw_goblin_body_enhanced(img, center_x, base_y, pose, color_skin, color_skin_dark, color_skin_deep, color_skin_light, color_cloth, color_cloth_dark, color_eye, color_eye_glow, color_club, color_club_dark, color_outline)

	# Add rim lighting for depth
	if pose < 6:
		_SU._draw_rim_light(img, center_x + int(float(pose) * 2), base_y - _s(24), _s(10), _s(12), color_skin_rim, -0.7)

	return ImageTexture.create_from_image(img)


static func _draw_goblin_body_enhanced(img: Image, cx: int, cy: int, pose: int, skin: Color, skin_dark: Color, skin_mid: Color, skin_light: Color, cloth: Color, cloth_dark: Color, eye: Color, eye_glow: Color, club: Color, club_dark: Color, outline: Color) -> void:
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
		for y in range(_s(-6), _s(6)):
			for x in range(_s(-15), _s(15)):
				var dist = sqrt(pow(float(x) / _sf(15), 2) + pow(float(y) / _sf(4), 2))
				if dist < 1.0:
					_sp(img, cx + x, cy + y + _s(8), skin_dark if dist > 0.6 else skin_mid)
		return

	# Club (drawn first, behind in some poses)
	if pose != 5 and pose != 6:
		var club_length = _s(20)
		var club_rad = deg_to_rad(club_angle)
		var club_x = cx + _s(12) + lean/4
		var club_y = cy - _s(12)
		var club_thickness = _s(3)

		for i in range(club_length):
			var base_x = club_x + int(cos(club_rad) * i)
			var base_y = club_y + int(sin(club_rad) * i)
			var thickness = club_thickness + (1 if i > club_length * 0.7 else 0)

			for t in range(-thickness, thickness + 1):
				var px = base_x + int(sin(club_rad) * t)
				var py = base_y - int(cos(club_rad) * t)
				var color = club if t > -thickness/2 else club_dark
				_sp(img, px, py, color)

		# Club knob at end
		var knob_x = club_x + int(cos(club_rad) * club_length)
		var knob_y = club_y + int(sin(club_rad) * club_length)
		for ky in range(_s(-4), _s(5)):
			for kx in range(_s(-4), _s(5)):
				if kx * kx + ky * ky <= _s(4) * _s(4):
					var color = club if ky < 0 else club_dark
					_sp(img, knob_x + kx, knob_y + ky, color)

	# Head (large relative to body) - outline first
	var head_x = cx + lean/5
	var head_y = cy - _s(24)
	var head_rx = _s(10)
	var head_ry = _s(12)

	# Head outline
	for y in range(-head_ry - 2, head_ry + 3):
		for x in range(-head_rx - 2, head_rx + 3):
			var dist = sqrt(pow(float(x) / (head_rx + 1), 2) + pow(float(y + _s(3)) / (head_ry + 1), 2))
			if dist >= 0.9 and dist < 1.1:
				_sp(img, head_x + x, head_y + y, outline)

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
				_sp(img, head_x + x, head_y + y, color)

	# Pointy ears (larger, more detailed)
	for ear_side in [-1, 1]:
		var ear_x = head_x + ear_side * _s(10)
		var ear_y = head_y - _s(6)
		for ey in range(_s(-6), _s(2)):
			var ear_width = _s(3) - abs(ey) / 2
			for ex in range(-ear_width, ear_width + 1):
				var px = ear_x + ex * ear_side
				var py = ear_y + ey
				var color = skin if ex * ear_side > 0 else skin_dark
				_sp(img, px, py, color)
		for ey in range(_s(-6), _s(2)):
			_sp(img, ear_x + ((_s(3) - abs(ey) / 2) * ear_side), ear_y + ey, outline)

	# Large warty nose
	var nose_x = head_x - _s(4)
	var nose_y = head_y + _s(2)
	for ny in range(_s(-3), _s(4)):
		for nx in range(_s(-3), _s(2)):
			if nx * nx + ny * ny <= _s(3) * _s(3):
				var color = skin_dark if nx < 0 else skin_mid
				_sp(img, nose_x + nx, nose_y + ny, color)
	_sp(img, nose_x + _s(1), nose_y - _s(1), skin)

	# Eyes (larger, meaner looking)
	for eye_side in [-1, 1]:
		var eye_x = head_x + eye_side * _s(4)
		var eye_y = head_y - _s(4)
		var eye_rx = _s(3)
		var eye_ry = _s(2)
		for ey in range(-eye_ry, eye_ry + 1):
			for ex in range(-eye_rx, eye_rx + 1):
				if abs(ex) + abs(ey) <= eye_rx + 1:
					_sp(img, eye_x + ex, eye_y + ey, eye)
		for ey in range(_s(-1), _s(2)):
			_sp(img, eye_x, eye_y + ey, Color.BLACK)
		_sp(img, eye_x - _s(1), eye_y - _s(1), eye_glow)

	# Mouth/fangs
	var mouth_y = head_y + _s(8)
	for mx in range(_s(-4), _s(5)):
		_sp(img, head_x + mx, mouth_y, skin_dark)
	for fang_x in [_s(-3), _s(3)]:
		_sp(img, head_x + fang_x, mouth_y + _s(1), Color(0.9, 0.9, 0.85))
		_sp(img, head_x + fang_x, mouth_y + _s(2), Color(0.85, 0.85, 0.8))

	# Body with more detail
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
				_sp(img, px, py, outline)

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
			_sp(img, px, py, color)

	# Belt detail
	var belt_y = cy + _s(2)
	for bx in range(-body_width + 1, body_width):
		_sp(img, cx + bx + lean/4, belt_y, skin_dark)
		_sp(img, cx + bx + lean/4, belt_y + _s(1), skin_mid)

	# Legs (with more shape)
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * _s(4) + lean/6
		for y in range(_s(6), _s(16)):
			var leg_width = _s(3) - (y - _s(6)) / 8
			for lx in range(-leg_width, leg_width + 1):
				var px = leg_x + lx
				var py = cy + y
				var color = skin_mid if lx * leg_side < 0 else skin_dark
				_sp(img, px, py, color)
		var foot_y = cy + _s(15)
		for fx in range(_s(-4), _s(3)):
			_sp(img, leg_x + fx * leg_side, foot_y, skin_dark)


## =================
## SHADOW KNIGHT (already Tier A - fully extracted from BattleAnimator)
## =================

static func create_shadow_knight_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("shadow_knight", func(): return _generate_shadow_knight_sprite_frames())

static func _generate_shadow_knight_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.5)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_shadow_knight_frame(0, 0.0))
	frames.add_frame("idle", _create_shadow_knight_frame(0, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.5)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_shadow_knight_frame(1, 0.0))
	frames.add_frame("attack", _create_shadow_knight_frame(2, -2.0))
	frames.add_frame("attack", _create_shadow_knight_frame(3, 0.0))
	frames.add_frame("attack", _create_shadow_knight_frame(4, 1.0))
	frames.add_frame("attack", _create_shadow_knight_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_shadow_knight_frame(5, 1.0))
	frames.add_frame("hit", _create_shadow_knight_frame(5, 0.0))
	frames.add_frame("hit", _create_shadow_knight_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_shadow_knight_frame(6, 0.0))
	frames.add_frame("defeat", _create_shadow_knight_frame(6, 2.0))
	frames.add_frame("defeat", _create_shadow_knight_frame(7, 4.0))
	frames.add_frame("defeat", _create_shadow_knight_frame(8, 8.0))
	return frames


static func _create_shadow_knight_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var color_armor = Color(0.15, 0.12, 0.2)
	var color_armor_dark = Color(0.08, 0.06, 0.12)
	var color_armor_mid = Color(0.2, 0.16, 0.28)
	var color_armor_light = Color(0.35, 0.28, 0.45)
	var color_accent = Color(0.6, 0.1, 0.15)
	var color_accent_glow = Color(0.9, 0.2, 0.25)
	var color_eye = Color(0.95, 0.15, 0.1)
	var color_eye_glow = Color(1.0, 0.4, 0.2)
	var color_blade = Color(0.2, 0.15, 0.25)
	var color_blade_edge = Color(0.8, 0.1, 0.15)
	var color_cape = Color(0.1, 0.05, 0.12)
	var color_outline = Color(0.05, 0.03, 0.08)

	var center_x = size / 2
	var base_y = int(size * 0.78 + _sf(y_offset))

	_draw_shadow_knight_body(img, center_x, base_y, pose, color_armor, color_armor_dark, color_armor_mid, color_armor_light, color_accent, color_accent_glow, color_eye, color_eye_glow, color_blade, color_blade_edge, color_cape, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_shadow_knight_body(img: Image, cx: int, cy: int, pose: int, armor: Color, armor_dark: Color, armor_mid: Color, armor_light: Color, accent: Color, accent_glow: Color, eye: Color, eye_glow: Color, blade: Color, blade_edge: Color, cape: Color, outline: Color) -> void:
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

	if pose >= 7:
		for y in range(_s(-8), _s(8)):
			for x in range(_s(-20), _s(20)):
				var dist = sqrt(pow(float(x) / _sf(20), 2) + pow(float(y) / _sf(6), 2))
				if dist < 1.0:
					var color = armor_dark if dist > 0.6 else armor_mid
					_sp(img, cx + x, cy + y + _s(10), color)
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
			if abs(x) > width * 0.6:
				color = armor_dark
			_sp(img, px, py, color)

	# Greatsword
	if pose < 6:
		var sword_length = _s(40)
		var sword_width = _s(4)
		var sword_rad = deg_to_rad(sword_angle)
		var sword_x = cx - _s(8) + lean/3
		var sword_y = cy - _s(15)

		for i in range(sword_length):
			var bw = sword_width if i < sword_length * 0.9 else sword_width - (i - sword_length * 0.9)
			for w in range(-int(bw), int(bw) + 1):
				var px = sword_x + int(cos(sword_rad) * i) + int(sin(sword_rad) * w)
				var py = sword_y + int(sin(sword_rad) * i) - int(cos(sword_rad) * w)
				var color = blade
				if abs(w) >= bw - 1:
					color = blade_edge
				elif w < 0:
					color = armor_dark
				_sp(img, px, py, color)

		# Crossguard
		var guard_x = sword_x + int(cos(sword_rad) * _sf(5))
		var guard_y = sword_y + int(sin(sword_rad) * _sf(5))
		for gx in range(_s(-8), _s(9)):
			for gy in range(_s(-2), _s(3)):
				_sp(img, guard_x + gx, guard_y + gy, accent)

	# Helmet (horned, menacing)
	var helm_x = cx + lean/4
	var helm_y = cy - _s(32)
	var helm_rx = _s(8)
	var helm_ry = _s(10)

	_SU._draw_ellipse_outline(img, helm_x, helm_y, helm_rx, helm_ry, outline)
	for y in range(-helm_ry, helm_ry + 1):
		for x in range(-helm_rx, helm_rx + 1):
			var dist = sqrt(pow(float(x) / helm_rx, 2) + pow(float(y) / helm_ry, 2))
			if dist < 1.0:
				var color = armor
				if y < -helm_ry * 0.3:
					color = armor_light
				elif y > helm_ry * 0.3:
					color = armor_dark
				_sp(img, helm_x + x, helm_y + y, color)

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
				_sp(img, px, py, color)
			if hy < _s(-8):
				_sp(img, horn_x + horn_side * abs(hy) / 4, horn_y + hy, accent)

	# Visor slit with glowing eyes
	var visor_y = helm_y + _s(2)
	for vx in range(_s(-5), _s(6)):
		_sp(img, helm_x + vx, visor_y, armor_dark)
		_sp(img, helm_x + vx, visor_y + _s(1), armor_dark)
	for eye_side in [-1, 1]:
		var eye_x_pos = helm_x + eye_side * _s(3)
		_sp(img, eye_x_pos, visor_y, eye)
		_sp(img, eye_x_pos + eye_side, visor_y, eye_glow)
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
								_sp(img, px, py, existing.blend(glow_color))

	# Armored body (bulky pauldrons)
	var body_x = cx + lean/3
	var body_y = cy

	# Pauldrons
	for pauldron_side in [-1, 1]:
		var pauL_x = body_x + pauldron_side * _s(14)
		var pauL_y = body_y - _s(20)
		for py in range(_s(-6), _s(8)):
			var pw = _s(8) - abs(py) / 2
			for px in range(-pw, pw + 1):
				var color = armor_mid if py < 0 else armor_dark
				if px * pauldron_side > pw/2:
					color = armor_light if py < 0 else armor
				_sp(img, pauL_x + px, pauL_y + py, color)
		for spike_y in range(_s(-10), _s(-4)):
			_sp(img, pauL_x, pauL_y + spike_y, accent)

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
			_sp(img, body_x + x, body_y + y - _s(8), color)

	# Red accent on chest (evil emblem)
	var emblem_y = body_y - _s(8)
	for ey in range(_s(-4), _s(5)):
		for ex in range(_s(-3), _s(4)):
			if abs(ex) + abs(ey) <= _s(4):
				_sp(img, body_x + ex, emblem_y + ey, accent)
	_sp(img, body_x, emblem_y, accent_glow)

	# Armored legs
	for leg_side in [-1, 1]:
		var leg_x = body_x + leg_side * _s(5)
		for y in range(_s(10), _s(25)):
			var leg_width = _s(5) - (y - _s(10)) / 8
			for lx in range(-leg_width, leg_width + 1):
				var color = armor_mid if lx * leg_side < 0 else armor_dark
				_sp(img, leg_x + lx, cy + y, color)
		var boot_y = cy + _s(24)
		for bx in range(_s(-6), _s(5)):
			for by in range(_s(3)):
				var color = armor_dark if by > 0 else armor_mid
				_sp(img, leg_x + bx * leg_side, boot_y + by, color)


## =================
## CAVE TROLL (already Tier A - fully extracted from BattleAnimator)
## =================

static func create_cave_troll_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("cave_troll", func(): return _generate_cave_troll_sprite_frames())

static func _generate_cave_troll_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 1.2)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_cave_troll_frame(0, 0.0))
	frames.add_frame("idle", _create_cave_troll_frame(0, -1.5))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 3.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_cave_troll_frame(1, -2.0))
	frames.add_frame("attack", _create_cave_troll_frame(2, 0.0))
	frames.add_frame("attack", _create_cave_troll_frame(3, 2.0))
	frames.add_frame("attack", _create_cave_troll_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_cave_troll_frame(4, 1.0))
	frames.add_frame("hit", _create_cave_troll_frame(4, 0.0))
	frames.add_frame("hit", _create_cave_troll_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 1.5)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_cave_troll_frame(5, 0.0))
	frames.add_frame("defeat", _create_cave_troll_frame(5, 4.0))
	frames.add_frame("defeat", _create_cave_troll_frame(6, 10.0))
	return frames


static func _create_cave_troll_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var color_skin = Color(0.4, 0.35, 0.3)
	var color_skin_dark = Color(0.25, 0.2, 0.18)
	var color_skin_mid = Color(0.32, 0.28, 0.24)
	var color_skin_light = Color(0.55, 0.48, 0.42)
	var color_moss = Color(0.3, 0.45, 0.25)
	var color_eye = Color(0.9, 0.6, 0.1)
	var color_teeth = Color(0.85, 0.82, 0.75)
	var color_outline = Color(0.15, 0.12, 0.1)

	var center_x = size / 2
	var base_y = int(size * 0.82 + _sf(y_offset))

	_draw_cave_troll_body(img, center_x, base_y, pose, color_skin, color_skin_dark, color_skin_mid, color_skin_light, color_moss, color_eye, color_teeth, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_cave_troll_body(img: Image, cx: int, cy: int, pose: int, skin: Color, skin_dark: Color, skin_mid: Color, skin_light: Color, moss: Color, eye: Color, teeth: Color, outline: Color) -> void:
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
		for y in range(_s(-12), _s(12)):
			for x in range(_s(-30), _s(30)):
				var dist = sqrt(pow(float(x) / _sf(30), 2) + pow(float(y) / _sf(10), 2))
				if dist < 1.0:
					var color = skin_dark if dist > 0.6 else skin_mid
					_sp(img, cx + x, cy + y + _s(8), color)
		return

	# Massive body
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
				_sp(img, body_x + x, body_y + y, outline)

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
			_sp(img, body_x + x, body_y + y, color)

	# Mossy patches on body
	var moss_spots = [[_s(-8), _s(-5)], [_s(10), _s(2)], [_s(-5), _s(8)], [_s(6), _s(-8)]]
	for spot in moss_spots:
		var spot_x = body_x + int(spot[0])
		var spot_y = body_y + int(spot[1])
		for my in range(_s(-3), _s(4)):
			for mx in range(_s(-4), _s(5)):
				if mx * mx + my * my <= _s(4) * _s(4):
					if spot_x + mx >= 0 and spot_x + mx < s and spot_y + my >= 0 and spot_y + my < s:
						if img.get_pixel(spot_x + mx, spot_y + my).a > 0.5:
							_sp(img, spot_x + mx, spot_y + my, moss)

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
				_sp(img, px, py, color)

		var fist_x = arm_x + int(cos(arm_rad) * arm_length)
		var fist_y = arm_y + int(sin(arm_rad) * arm_length)
		for fy in range(_s(-6), _s(7)):
			for fx in range(_s(-6), _s(7)):
				if fx * fx + fy * fy <= _s(6) * _s(6):
					var color = skin if fy < 0 else skin_dark
					_sp(img, fist_x + fx, fist_y + fy, color)

	# Head (small relative to body, brutish)
	var head_x = cx + lean/3
	var head_y = cy - _s(32)
	var head_rx = _s(10)
	var head_ry = _s(8)

	_SU._draw_ellipse_outline(img, head_x, head_y, head_rx, head_ry, outline)
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = skin
				if y < -head_ry * 0.3:
					color = skin_light
				elif y > head_ry * 0.3:
					color = skin_mid
				_sp(img, head_x + x, head_y + y, color)

	# Brow ridge
	var brow_y = head_y - _s(3)
	for bx in range(_s(-9), _s(10)):
		for by in range(_s(-2), _s(2)):
			_sp(img, head_x + bx, brow_y + by, skin_dark)

	# Small angry eyes under brow
	for eye_side in [-1, 1]:
		var eye_x = head_x + eye_side * _s(4)
		var eye_y = head_y
		for ey in range(_s(-2), _s(2)):
			for ex in range(_s(-2), _s(2)):
				if abs(ex) + abs(ey) <= _s(2):
					_sp(img, eye_x + ex, eye_y + ey, eye)
		_sp(img, eye_x, eye_y, Color.BLACK)

	# Wide mouth with tusks
	var mouth_y = head_y + _s(4)
	var mouth_width = _s(8)
	var mouth_height = _s(3) if not mouth_open else _s(6)

	for my in range(mouth_height):
		for mx in range(-mouth_width, mouth_width + 1):
			_sp(img, head_x + mx, mouth_y + my, skin_dark if not mouth_open else Color(0.2, 0.1, 0.1))

	# Tusks
	for tusk_side in [-1, 1]:
		var tusk_x = head_x + tusk_side * _s(6)
		var tusk_y = mouth_y + _s(1)
		for ty in range(_s(6)):
			var tw = _s(2) - ty / 4
			for tx in range(-tw, tw + 1):
				_sp(img, tusk_x + tx + tusk_side * ty / 3, tusk_y + ty, teeth)

	# Stumpy legs
	for leg_side in [-1, 1]:
		var leg_x = cx + leg_side * _s(8) + lean/5
		for y in range(_s(18), _s(28)):
			var leg_width = _s(8) - (y - _s(18)) / 6
			for lx in range(-leg_width, leg_width + 1):
				var color = skin_mid if lx * leg_side < 0 else skin_dark
				_sp(img, leg_x + lx, cy + y, color)
		for fx in range(_s(-9), _s(6)):
			for fy in range(_s(4)):
				_sp(img, leg_x + fx * leg_side, cy + _s(27) + fy, skin_dark)


## =================
## CAVE RAT KING (already Tier A - fully extracted from BattleAnimator)
## =================

static func create_cave_rat_king_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("cave_rat_king", func(): return _generate_cave_rat_king_sprite_frames())

static func _generate_cave_rat_king_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_rat_king_frame(0, 0.0))
	frames.add_frame("idle", _create_rat_king_frame(0, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_rat_king_frame(1, 0.0))
	frames.add_frame("attack", _create_rat_king_frame(2, -2.0))
	frames.add_frame("attack", _create_rat_king_frame(3, 0.0))
	frames.add_frame("attack", _create_rat_king_frame(4, 2.0))
	frames.add_frame("attack", _create_rat_king_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_rat_king_frame(5, 2.0))
	frames.add_frame("hit", _create_rat_king_frame(5, 0.0))
	frames.add_frame("hit", _create_rat_king_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_rat_king_frame(6, 0.0))
	frames.add_frame("defeat", _create_rat_king_frame(6, 3.0))
	frames.add_frame("defeat", _create_rat_king_frame(7, 6.0))
	frames.add_frame("defeat", _create_rat_king_frame(8, 10.0))
	frames.add_animation("summon")
	frames.set_animation_speed("summon", 3.0)
	frames.set_animation_loop("summon", false)
	frames.add_frame("summon", _create_rat_king_frame(9, 0.0))
	frames.add_frame("summon", _create_rat_king_frame(10, -2.0))
	frames.add_frame("summon", _create_rat_king_frame(10, 0.0))
	frames.add_frame("summon", _create_rat_king_frame(0, 0.0))
	return frames


static func _create_rat_king_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var color_fur = Color(0.35, 0.28, 0.22)
	var color_fur_dark = Color(0.22, 0.17, 0.13)
	var color_fur_mid = Color(0.42, 0.35, 0.28)
	var color_fur_light = Color(0.55, 0.45, 0.38)
	var color_skin = Color(0.7, 0.55, 0.5)
	var color_skin_dark = Color(0.55, 0.4, 0.38)
	var color_eye = Color(0.9, 0.15, 0.1)
	var color_eye_glow = Color(1.0, 0.3, 0.2)
	var color_nose = Color(0.85, 0.5, 0.5)
	var color_teeth = Color(0.95, 0.9, 0.7)
	var color_crown = Color(0.95, 0.8, 0.2)
	var color_crown_dark = Color(0.7, 0.55, 0.1)
	var color_crown_gem = Color(0.8, 0.15, 0.2)
	var color_outline = Color(0.12, 0.08, 0.06)

	var center_x = size / 2
	var base_y = int(size * 0.75 + _sf(y_offset))

	_draw_rat_king_body(img, center_x, base_y, pose, color_fur, color_fur_dark, color_fur_mid, color_fur_light, color_skin, color_skin_dark, color_eye, color_eye_glow, color_nose, color_teeth, color_crown, color_crown_dark, color_crown_gem, color_outline)

	return ImageTexture.create_from_image(img)


static func _draw_rat_king_body(img: Image, cx: int, cy: int, pose: int, fur: Color, fur_dark: Color, fur_mid: Color, fur_light: Color, skin: Color, skin_dark: Color, eye: Color, eye_glow: Color, nose: Color, teeth: Color, crown: Color, crown_dark: Color, crown_gem: Color, outline: Color) -> void:
	var s = img.get_width()

	var lean = 0
	var crouch = 0
	var mouth_open = false
	var tail_up = false
	var paws_up = false
	var crown_tilt = 0

	match pose:
		1: lean = _s(-5); tail_up = true
		2: crouch = _s(8); lean = _s(-3)
		3: lean = _s(12); mouth_open = true
		4: lean = _s(15); mouth_open = true
		5: lean = _s(-10); crown_tilt = 15
		6: lean = _s(-18); crown_tilt = 30
		7: lean = _s(-35); crown_tilt = 60
		8: lean = _s(-45); crown_tilt = 90
		9: tail_up = true
		10: paws_up = true; tail_up = true

	if pose >= 7:
		for y in range(_s(-10), _s(10)):
			for x in range(_s(-25), _s(25)):
				var dist = sqrt(pow(float(x) / _sf(25), 2) + pow(float(y) / _sf(8), 2))
				if dist < 1.0:
					var color = fur_dark if dist > 0.6 else fur_mid
					_sp(img, cx + x, cy + y + _s(8), color)
		var crown_x2 = cx + _s(20)
		var crown_y2 = cy + _s(5)
		for cy2 in range(_s(-4), _s(2)):
			for cx2 in range(_s(-6), _s(7)):
				if cy2 < 0 and abs(cx2) < _s(5):
					_sp(img, crown_x2 + cx2, crown_y2 + cy2, crown)
		return

	# Tail (draw first, behind body)
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
			_sp(img, tx, ty + tw, skin if t > 0.3 else skin_dark)

	# Body (large, hunched rat body)
	var body_x = cx + lean/4
	var body_y = cy - _s(5) + crouch
	var body_rx = _s(18)
	var body_ry = _s(14)

	_SU._draw_ellipse_outline(img, body_x, body_y, body_rx + 1, body_ry + 1, outline)
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var color = fur
				if y < -body_ry * 0.3:
					color = fur_light
				elif y > body_ry * 0.4:
					color = fur_dark
				if x < -body_rx * 0.5:
					color = fur_mid
				if (x + y) % _s(8) < _s(2) and dist > 0.5:
					color = fur_dark
				_sp(img, body_x + x, body_y + y, color)

	# Hind legs
	for leg_side in [-1, 1]:
		var leg_x = body_x + leg_side * _s(10) - _s(5)
		var leg_y = body_y + _s(10)
		for ly in range(_s(12)):
			var lw = _s(6) - ly / 4
			for lx in range(-lw, lw + 1):
				_sp(img, leg_x + lx, leg_y + ly, fur_mid if lx * leg_side > 0 else fur_dark)
		for py in range(_s(4)):
			for px in range(_s(-5), _s(6)):
				_sp(img, leg_x + px, leg_y + _s(12) + py, skin_dark)

	# Front paws
	var paw_y_offset = 0 if not paws_up else _s(-15)
	for paw_side in [-1, 1]:
		var paw_x = body_x + paw_side * _s(12) + lean/3
		var paw_y = body_y + _s(8) + paw_y_offset
		for ay in range(_s(10)):
			var aw = _s(4) - ay / 5
			for ax in range(-aw, aw + 1):
				_sp(img, paw_x + ax, paw_y + ay - _s(5), fur_mid)
		for py in range(_s(5)):
			for px in range(_s(-4), _s(5)):
				_sp(img, paw_x + px, paw_y + _s(5) + py, skin)
		for claw in range(3):
			var claw_x = paw_x - _s(2) + claw * _s(2)
			for cl in range(_s(3)):
				_sp(img, claw_x, paw_y + _s(10) + cl, Color(0.3, 0.25, 0.2))

	# Head
	var head_x = cx + _s(12) + lean/2
	var head_y = cy - _s(18) + crouch/2
	var head_rx = _s(12)
	var head_ry = _s(10)

	_SU._draw_ellipse_outline(img, head_x, head_y, head_rx, head_ry, outline)
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = fur
				if y < -head_ry * 0.3:
					color = fur_light
				elif x > head_rx * 0.3:
					color = fur_mid
				_sp(img, head_x + x, head_y + y, color)

	# Ears (large rat ears)
	for ear_side in [-1, 1]:
		var ear_x = head_x + ear_side * _s(8)
		var ear_y = head_y - _s(12)
		for ey in range(_s(10)):
			var ew = _s(5) - abs(ey - _s(5)) / 2
			for ex in range(-ew, ew + 1):
				_sp(img, ear_x + ex, ear_y + ey, skin_dark)
		for ey in range(_s(2), _s(8)):
			var ew = _s(3) - abs(ey - _s(5)) / 2
			for ex in range(-ew, ew + 1):
				_sp(img, ear_x + ex, ear_y + ey, skin)

	# Snout
	var snout_x = head_x + _s(10)
	var snout_y = head_y + _s(2)
	for sy in range(_s(-4), _s(5)):
		for sx in range(_s(8)):
			var dist = sqrt(pow(float(sx) / _sf(8), 2) + pow(float(sy) / _sf(4), 2))
			if dist < 1.0:
				_sp(img, snout_x + sx, snout_y + sy, fur_light if sy < 0 else fur_mid)

	# Nose
	for ny in range(_s(-2), _s(3)):
		for nx in range(_s(-2), _s(3)):
			if nx * nx + ny * ny <= _s(2) * _s(2):
				_sp(img, snout_x + _s(7) + nx, snout_y + ny, nose)

	# Whiskers
	for whisker in range(3):
		var wy = snout_y - _s(2) + whisker * _s(3)
		for wx in range(_s(12)):
			_sp(img, snout_x + _s(5) + wx, wy + wx/8, Color(0.6, 0.55, 0.5))
			_sp(img, snout_x + _s(5) + wx, wy - wx/8, Color(0.6, 0.55, 0.5))

	# Eyes (beady, menacing)
	var eye_x = head_x + _s(4)
	var eye_y = head_y - _s(2)
	for ey in range(_s(-3), _s(4)):
		for ex in range(_s(-3), _s(4)):
			if ex * ex + ey * ey <= _s(3) * _s(3):
				_sp(img, eye_x + ex, eye_y + ey, fur_dark)
	for ey in range(_s(-2), _s(3)):
		for ex in range(_s(-2), _s(3)):
			if ex * ex + ey * ey <= _s(2) * _s(2):
				_sp(img, eye_x + ex, eye_y + ey, eye)
	_sp(img, eye_x - _s(1), eye_y - _s(1), eye_glow)

	# Mouth / Teeth
	if mouth_open:
		var mouth_x = snout_x + _s(4)
		var mouth_y2 = snout_y + _s(3)
		for my in range(_s(6)):
			for mx in range(_s(-4), _s(5)):
				_sp(img, mouth_x + mx, mouth_y2 + my, Color(0.3, 0.1, 0.1))
		for tooth_side in [-1, 1]:
			var tooth_x = mouth_x + tooth_side * _s(2)
			for ty in range(_s(5)):
				_sp(img, tooth_x, mouth_y2 + ty, teeth)
				_sp(img, tooth_x + tooth_side, mouth_y2 + ty, teeth)
	else:
		var mouth_x = snout_x + _s(6)
		var mouth_y2 = snout_y + _s(4)
		for tooth_side in [-1, 1]:
			for ty in range(_s(3)):
				_sp(img, mouth_x + tooth_side, mouth_y2 + ty, teeth)

	# Crown (tiny, comically small, tilted)
	var crown_x = head_x - _s(2)
	var crown_y = head_y - _s(14)
	var crown_tilt_rad = deg_to_rad(crown_tilt)

	for cby in range(_s(4)):
		for cbx in range(_s(-6), _s(7)):
			var rotated_x = int(cbx * cos(crown_tilt_rad) - cby * sin(crown_tilt_rad))
			var rotated_y = int(cbx * sin(crown_tilt_rad) + cby * cos(crown_tilt_rad))
			_sp(img, crown_x + rotated_x, crown_y + rotated_y, crown if cby < _s(2) else crown_dark)

	for point in range(3):
		var point_x = _s(-4) + point * _s(4)
		for py in range(_s(6)):
			var pw = _s(2) - py / 3
			for px in range(-pw, pw + 1):
				var rx = int((point_x + px) * cos(crown_tilt_rad) - (-py) * sin(crown_tilt_rad))
				var ry = int((point_x + px) * sin(crown_tilt_rad) + (-py) * cos(crown_tilt_rad))
				_sp(img, crown_x + rx, crown_y + ry, crown)

	var gem_x = crown_x
	var gem_y = crown_y - _s(2)
	for gy in range(_s(-2), _s(2)):
		for gx in range(_s(-2), _s(2)):
			if abs(gx) + abs(gy) <= _s(2):
				_sp(img, gem_x + gx, gem_y + gy, crown_gem)


## =================
## CAVE RAT (Tier C -> Tier A upgrade: _s() scaling, outline, 5+ palette, shine)
## =================

static func create_cave_rat_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("cave_rat", func(): return _generate_cave_rat_sprite_frames())

static func _generate_cave_rat_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 3.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_cave_rat_frame(0, 0.0))
	frames.add_frame("idle", _create_cave_rat_frame(0, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 5.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_cave_rat_frame(1, 0.0))
	frames.add_frame("attack", _create_cave_rat_frame(2, 0.0))
	frames.add_frame("attack", _create_cave_rat_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 5.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_cave_rat_frame(3, 1.0))
	frames.add_frame("hit", _create_cave_rat_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_cave_rat_frame(4, 2.0))
	frames.add_frame("defeat", _create_cave_rat_frame(5, 5.0))
	return frames


static func _create_cave_rat_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-quality 7-color palette (upgraded from Tier C)
	var fur = Color(0.4, 0.32, 0.25)
	var fur_dark = Color(0.28, 0.2, 0.15)
	var fur_mid = Color(0.34, 0.26, 0.2)
	var fur_light = Color(0.52, 0.42, 0.35)
	var fur_shine = Color(0.6, 0.5, 0.42)
	var skin = Color(0.7, 0.55, 0.5)
	var skin_dark = Color(0.55, 0.4, 0.38)
	var eye_c = Color(0.85, 0.2, 0.15)
	var eye_glow = Color(1.0, 0.35, 0.25)
	var teeth_c = Color(0.9, 0.85, 0.7)
	var nose_c = Color(0.8, 0.5, 0.5)
	var outline = Color(0.12, 0.08, 0.06)

	var cx = size / 2
	var cy = int(size * 0.7 + _sf(y_offset))

	var lean = 0
	var mouth_open = false

	match pose:
		1: lean = _s(-3)
		2: lean = _s(8); mouth_open = true
		3: lean = _s(-6)
		4: lean = _s(-12)
		5: lean = _s(-20)

	# Defeated - collapsed rat with outline
	if pose >= 4:
		for y in range(_s(-5), _s(6)):
			for x in range(_s(-16), _s(17)):
				var dist = sqrt(pow(float(x) / _sf(16), 2) + pow(float(y) / _sf(5), 2))
				if dist < 1.0:
					_sp(img, cx + x, cy + y + _s(5), fur_dark if dist > 0.5 else fur)
				elif dist < 1.12:
					_sp(img, cx + x, cy + y + _s(5), outline)
		return ImageTexture.create_from_image(img)

	# Tail with outline
	var tail_x = cx - _s(12) + lean/4
	var tail_y = cy + _s(2)
	for i in range(_s(20)):
		var t = float(i) / _sf(20)
		var ty = tail_y + int(sin(t * PI) * _sf(6))
		var tx = tail_x - i
		var thickness = _s(2) - int(t * _sf(1.5))
		for tw in range(-thickness - 1, thickness + 2):
			if abs(tw) > thickness:
				_sp(img, tx, ty + tw, outline)
			else:
				_sp(img, tx, ty + tw, skin if t > 0.3 else skin_dark)

	# Body (oval with outline and multi-zone shading)
	var body_rx = _s(12)
	var body_ry = _s(8)
	_SU._draw_ellipse_outline(img, cx + lean/3, cy, body_rx + 1, body_ry + 1, outline)
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var color = fur
				if dist > 0.7:
					color = fur_dark
				elif dist < 0.4:
					color = fur_light
				elif y < -body_ry * 0.3:
					color = fur_light
				elif x < -body_rx * 0.4:
					color = fur_mid
				_sp(img, cx + x + lean/3, cy + y, color)

	# Body shine
	_SU._draw_shine_spot(img, cx - _s(3) + lean/3, cy - _s(3), _s(3), fur_shine, 0.6)

	# Head with outline
	var head_x = cx + _s(8) + lean/2
	var head_y = cy - _s(2)
	var head_rx = _s(8)
	var head_ry = _s(6)
	_SU._draw_ellipse_outline(img, head_x, head_y, head_rx + 1, head_ry + 1, outline)
	for y in range(-head_ry, head_ry + 1):
		for x in range(-head_rx, head_rx + 1):
			var dist = sqrt(pow(float(x) / head_rx, 2) + pow(float(y) / head_ry, 2))
			if dist < 1.0:
				var color = fur
				if dist < 0.5:
					color = fur_light
				elif y < -head_ry * 0.3:
					color = fur_light
				elif x > head_rx * 0.3:
					color = fur_mid
				_sp(img, head_x + x, head_y + y, color)

	# Ears with inner detail
	for ear_side in [-1, 1]:
		var ear_x = head_x - _s(2)
		var ear_y = head_y - _s(7) + ear_side * _s(3)
		for ey in range(_s(-5), _s(2)):
			for ex in range(_s(-3), _s(4)):
				var edist = pow(float(ex) / _sf(3), 2) + pow(float(ey) / _sf(4), 2)
				if edist < 1.0:
					if edist < 0.5 and ey > _s(-3):
						_sp(img, ear_x + ex, ear_y + ey, skin)  # Inner pink
					else:
						_sp(img, ear_x + ex, ear_y + ey, fur)
				elif edist < 1.2:
					_sp(img, ear_x + ex, ear_y + ey, outline)

	# Eye with glow and catchlight
	var eye_x = head_x + _s(3)
	var eye_y = head_y - _s(1)
	for ey in range(_s(-2), _s(3)):
		for ex in range(_s(-2), _s(3)):
			if ex * ex + ey * ey <= _s(2) * _s(2):
				_sp(img, eye_x + ex, eye_y + ey, eye_c)
	_sp(img, eye_x, eye_y, Color.BLACK)  # Pupil
	_sp(img, eye_x - 1, eye_y - 1, eye_glow)  # Catchlight

	# Nose with detail
	for ny in range(_s(-1), _s(2)):
		for nx in range(_s(-1), _s(2)):
			if nx * nx + ny * ny <= _s(1) * _s(1):
				_sp(img, head_x + _s(8) + nx, head_y + _s(1) + ny, nose_c)

	# Whiskers
	for wy_off in [-_s(1), _s(1)]:
		for wx in range(_s(6)):
			_sp(img, head_x + _s(7) + wx, head_y + _s(1) + wy_off + wx/6, Color(0.6, 0.55, 0.5))

	# Mouth/teeth
	if mouth_open:
		for my in range(_s(3)):
			for mx in range(_s(-2), _s(3)):
				_sp(img, head_x + _s(6) + mx, head_y + _s(3) + my, Color(0.2, 0.1, 0.1))
		_sp(img, head_x + _s(5), head_y + _s(3), teeth_c)
		_sp(img, head_x + _s(7), head_y + _s(3), teeth_c)
		_sp(img, head_x + _s(5), head_y + _s(4), teeth_c)

	# Legs with outline (4 legs)
	for leg in range(4):
		var leg_x = cx - _s(6) + leg * _s(5) + lean/4
		var leg_y = cy + _s(6)
		for ly in range(_s(5)):
			_sp(img, leg_x - 1, leg_y + ly, outline)
			_sp(img, leg_x, leg_y + ly, fur_dark)
			_sp(img, leg_x + 1, leg_y + ly, fur_mid)
			_sp(img, leg_x + 2, leg_y + ly, outline)
		# Paw
		_sp(img, leg_x - 1, leg_y + _s(5), outline)
		_sp(img, leg_x, leg_y + _s(5), fur_dark)
		_sp(img, leg_x + 1, leg_y + _s(5), fur_dark)
		_sp(img, leg_x + 2, leg_y + _s(5), outline)

	return ImageTexture.create_from_image(img)


## =================
## RAT GUARD (Tier C -> Tier A upgrade: _s() scaling, outline, 5+ palette, shine)
## =================

static func create_rat_guard_sprite_frames() -> SpriteFrames:
	return _SU._get_cached_sprite("rat_guard", func(): return _generate_rat_guard_sprite_frames())

static func _generate_rat_guard_sprite_frames() -> SpriteFrames:
	var frames = SpriteFrames.new()
	frames.add_animation("idle")
	frames.set_animation_speed("idle", 2.0)
	frames.set_animation_loop("idle", true)
	frames.add_frame("idle", _create_rat_guard_frame(0, 0.0))
	frames.add_frame("idle", _create_rat_guard_frame(0, -1.0))
	frames.add_animation("attack")
	frames.set_animation_speed("attack", 4.0)
	frames.set_animation_loop("attack", false)
	frames.add_frame("attack", _create_rat_guard_frame(1, 0.0))
	frames.add_frame("attack", _create_rat_guard_frame(2, 0.0))
	frames.add_frame("attack", _create_rat_guard_frame(3, 0.0))
	frames.add_frame("attack", _create_rat_guard_frame(0, 0.0))
	frames.add_animation("hit")
	frames.set_animation_speed("hit", 4.0)
	frames.set_animation_loop("hit", false)
	frames.add_frame("hit", _create_rat_guard_frame(4, 1.0))
	frames.add_frame("hit", _create_rat_guard_frame(4, 0.0))
	frames.add_frame("hit", _create_rat_guard_frame(0, 0.0))
	frames.add_animation("defeat")
	frames.set_animation_speed("defeat", 2.0)
	frames.set_animation_loop("defeat", false)
	frames.add_frame("defeat", _create_rat_guard_frame(5, 2.0))
	frames.add_frame("defeat", _create_rat_guard_frame(6, 5.0))
	frames.add_frame("defeat", _create_rat_guard_frame(7, 8.0))
	return frames


static func _create_rat_guard_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# SNES-quality 10-color palette (upgraded from Tier C)
	var fur = Color(0.38, 0.3, 0.25)
	var fur_dark = Color(0.25, 0.18, 0.14)
	var fur_mid = Color(0.32, 0.24, 0.2)
	var fur_light = Color(0.5, 0.4, 0.35)
	var armor = Color(0.5, 0.45, 0.4)
	var armor_dark = Color(0.35, 0.3, 0.28)
	var armor_light = Color(0.65, 0.6, 0.55)
	var armor_shine = Color(0.75, 0.7, 0.65)
	var skin = Color(0.65, 0.5, 0.45)
	var eye_c = Color(0.8, 0.25, 0.2)
	var eye_glow = Color(1.0, 0.4, 0.3)
	var shield_c = Color(0.55, 0.4, 0.3)
	var shield_emblem = Color(0.7, 0.55, 0.2)
	var outline = Color(0.1, 0.08, 0.06)

	var cx = size / 2
	var cy = int(size * 0.72 + _sf(y_offset))

	var lean = 0
	var shield_up = true
	var attacking = false

	match pose:
		1: lean = _s(-3); shield_up = true
		2: lean = _s(5); attacking = true
		3: lean = _s(10); attacking = true
		4: lean = _s(-8); shield_up = false
		5: lean = _s(-15); shield_up = false
		6: lean = _s(-25); shield_up = false
		7: lean = _s(-35); shield_up = false

	# Defeated pose with outline
	if pose >= 6:
		for y in range(_s(-7), _s(9)):
			for x in range(_s(-19), _s(20)):
				var dist = sqrt(pow(float(x) / _sf(19), 2) + pow(float(y) / _sf(7), 2))
				if dist < 1.0:
					var color = armor_dark if (x + y) % 3 == 0 else fur_dark
					_sp(img, cx + x, cy + y + _s(6), color)
				elif dist < 1.1:
					_sp(img, cx + x, cy + y + _s(6), outline)
		# Fallen shield
		for sy in range(_s(-9), _s(4)):
			for sx in range(_s(-6), _s(7)):
				if abs(sx) + abs(sy) / 2 < _s(8):
					_sp(img, cx + _s(20) + sx, cy + sy + _s(8), shield_c)
		return ImageTexture.create_from_image(img)

	# Tail (behind everything) with outline
	var tail_x = cx - _s(14) + lean/4
	var tail_y = cy + _s(4)
	for i in range(_s(18)):
		var t = float(i) / _sf(18)
		var ty = tail_y + int(sin(t * PI) * _sf(5))
		for tw in range(-2, 3):
			if abs(tw) == 2:
				_sp(img, tail_x - i, ty + tw, outline)
			else:
				_sp(img, tail_x - i, ty + tw, skin)

	# Body with armor and outline
	var body_rx = _s(10)
	var body_ry = _s(12)
	_SU._draw_ellipse_outline(img, cx + lean/4, cy, body_rx + 1, body_ry + 1, outline)

	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y + _s(2)) / body_ry, 2))
			if dist < 1.0:
				# Armor on chest
				if y > _s(-8) and y < _s(5) and abs(x) < _s(8):
					var color = armor_light if y < _s(-4) else armor if y < _s(2) else armor_dark
					_sp(img, cx + x + lean/4, cy + y, color)
				else:
					_sp(img, cx + x + lean/4, cy + y, fur if dist > 0.6 else fur_light)

	# Armor shine
	_SU._draw_shine_spot(img, cx - _s(2) + lean/4, cy - _s(3), _s(2), armor_shine, 0.5)

	# Helmet (with outline and shading)
	var head_x = cx + _s(6) + lean/3
	var head_y = cy - _s(8)
	var helm_rx = _s(7)
	var helm_ry = _s(7)

	_SU._draw_ellipse_outline(img, head_x, head_y, helm_rx + 1, helm_ry + 1, outline)

	# Helmet top half
	for y in range(-helm_ry, 0):
		for x in range(-helm_rx, helm_rx + 1):
			var dist = sqrt(pow(float(x) / helm_rx, 2) + pow(float(y + _s(3)) / helm_ry, 2))
			if dist < 1.0:
				var color = armor
				if y < _s(-2):
					color = armor_light
				elif x > helm_rx * 0.3:
					color = armor_dark
				_sp(img, head_x + x, head_y + y, color)

	# Face below helmet
	for y in range(_s(-2), _s(6)):
		for x in range(_s(-5), _s(8)):
			var dist = sqrt(pow(float(x) / _sf(6), 2) + pow(float(y) / _sf(4), 2))
			if dist < 1.0:
				_sp(img, head_x + x, head_y + y, fur if dist > 0.5 else fur_light)

	# Ears poking through helmet
	for ear_y in range(_s(-4), 0):
		_sp(img, head_x - _s(4), head_y + ear_y - _s(4), fur)
		_sp(img, head_x + _s(4), head_y + ear_y - _s(4), fur)

	# Eye with glow
	for ey in range(_s(-1), _s(2)):
		for ex in range(_s(-1), _s(2)):
			if ex * ex + ey * ey <= _s(1) * _s(1):
				_sp(img, head_x + _s(3) + ex, head_y + _s(1) + ey, eye_c)
	_sp(img, head_x + _s(3) - 1, head_y, eye_glow)  # Catchlight

	# Snout with outline
	for sy in range(_s(-2), _s(3)):
		for sx in range(_s(5)):
			var sdist = sqrt(pow(float(sx) / _sf(5), 2) + pow(float(sy) / _sf(2), 2))
			if sdist < 1.0:
				_sp(img, head_x + _s(5) + sx, head_y + _s(2) + sy, fur_light)
			elif sdist < 1.2:
				_sp(img, head_x + _s(5) + sx, head_y + _s(2) + sy, outline)
	_sp(img, head_x + _s(10), head_y + _s(2), skin)  # Nose

	# Shield (on left side) with outline and emblem
	if shield_up:
		var shield_x = cx - _s(8) + lean/3
		var shield_y = cy - _s(2)
		# Shield body with outline
		for sy in range(_s(-11), _s(9)):
			for sx in range(_s(-6), _s(7)):
				var shield_dist = sqrt(pow(float(sx) / _sf(6), 2) + pow(float(sy + _s(1)) / _sf(10), 2))
				if shield_dist < 1.0:
					var color = shield_c
					if sy < _s(-6):
						color = armor_light
					elif sy > _s(4):
						color = armor_dark
					elif sx < _s(-3):
						color = shield_c.darkened(0.1)
					_sp(img, shield_x + sx, shield_y + sy, color)
				elif shield_dist < 1.1:
					_sp(img, shield_x + sx, shield_y + sy, outline)
		# Shield emblem (rat symbol)
		for ey in range(_s(-3), _s(4)):
			for ex in range(_s(-2), _s(3)):
				if abs(ex) + abs(ey) < _s(4):
					_sp(img, shield_x + ex, shield_y + ey, shield_emblem)
		# Shield shine
		_SU._draw_shine_spot(img, shield_x - _s(2), shield_y - _s(4), _s(2), armor_shine, 0.4)

	# Legs with greaves and outline
	for leg in range(2):
		var leg_x = cx - _s(4) + leg * _s(8) + lean/4
		var leg_y = cy + _s(8)
		for ly in range(_s(8)):
			var color = armor_dark if ly < _s(4) else fur_dark
			_sp(img, leg_x - 1, leg_y + ly, outline)
			_sp(img, leg_x, leg_y + ly, color)
			_sp(img, leg_x + _s(1), leg_y + ly, color)
			_sp(img, leg_x + _s(2), leg_y + ly, color)
			_sp(img, leg_x + _s(3), leg_y + ly, outline)

	return ImageTexture.create_from_image(img)
