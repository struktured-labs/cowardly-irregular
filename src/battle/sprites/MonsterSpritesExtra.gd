class_name MonsterSpritesExtra

## MonsterSpritesExtra - Procedural sprites for Suburban and Meta/Glitch monsters
## Suburban: EarthBound-style bright/mundane enemies
## Meta/Glitch: Digital corruption aesthetic

const _SU = preload("res://src/battle/sprites/SpriteUtils.gd")

static func _s(v: float) -> int: return _SU._s(v)
static func _sf(v: float) -> float: return _SU._sf(v)
static func _sp(img: Image, x: int, y: int, c: Color) -> void: _SU._safe_pixel(img, x, y, c)


## Helper: build standard 4-anim SpriteFrames from a frame generator callable
## gen takes (pose: int, y_offset: float) -> ImageTexture
static func _build_standard_frames(cache_key: String, gen: Callable) -> SpriteFrames:
	return _SU._get_cached_sprite(cache_key, func():
		var frames = SpriteFrames.new()
		frames.add_animation("idle")
		frames.set_animation_speed("idle", 3.0)
		frames.set_animation_loop("idle", true)
		frames.add_frame("idle", gen.call(0, 0.0))
		frames.add_frame("idle", gen.call(0, -1.0))
		frames.add_frame("idle", gen.call(0, 0.0))
		frames.add_frame("idle", gen.call(0, 1.0))
		frames.add_animation("attack")
		frames.set_animation_speed("attack", 4.0)
		frames.set_animation_loop("attack", false)
		frames.add_frame("attack", gen.call(1, 0.0))
		frames.add_frame("attack", gen.call(2, -2.0))
		frames.add_frame("attack", gen.call(1, 0.0))
		frames.add_frame("attack", gen.call(0, 0.0))
		frames.add_animation("hit")
		frames.set_animation_speed("hit", 5.0)
		frames.set_animation_loop("hit", false)
		frames.add_frame("hit", gen.call(3, 1.0))
		frames.add_frame("hit", gen.call(3, -1.0))
		frames.add_frame("hit", gen.call(0, 0.0))
		frames.add_animation("defeat")
		frames.set_animation_speed("defeat", 2.5)
		frames.set_animation_loop("defeat", false)
		frames.add_frame("defeat", gen.call(4, 0.0))
		frames.add_frame("defeat", gen.call(4, 2.0))
		frames.add_frame("defeat", gen.call(4, 4.0))
		frames.add_frame("defeat", gen.call(4, 6.0))
		return frames
	)


## =============================
## SUBURBAN MONSTERS
## =============================


## --- NEW AGE RETRO HIPPIE ---
static func create_new_age_retro_hippie_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("new_age_retro_hippie", _create_hippie_frame)

static func _create_hippie_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var skin = Color(0.85, 0.7, 0.55)
	var skin_shadow = Color(0.7, 0.55, 0.4)
	var hair_c = Color(0.55, 0.35, 0.15)
	var headband = Color(0.9, 0.3, 0.2)
	var shirt1 = Color(0.9, 0.4, 0.1)  # Tie-dye orange
	var shirt2 = Color(0.3, 0.8, 0.4)  # Tie-dye green
	var shirt3 = Color(0.6, 0.2, 0.8)  # Tie-dye purple
	var pants = Color(0.3, 0.35, 0.6)  # Denim blue
	var outline = Color(0.15, 0.1, 0.08)
	var peace_c = Color(1.0, 1.0, 0.3)  # Yellow peace sign

	var cx = size / 2
	var by = int(size * 0.85 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Collapsed sideways
		for y in range(_s(-3), _s(4)):
			for x in range(_s(-14), _s(14)):
				var t = float(x + _s(14)) / _s(28)
				var c = shirt1.lerp(shirt2, t) if abs(y) < _s(2) else pants
				_sp(img, cx + x, by - _s(2) + y, c)
		return ImageTexture.create_from_image(img)

	# Legs
	var leg_spread = _s(3) if pose == 1 else _s(2)
	for leg_side in [-1, 1]:
		var lx = cx + leg_side * leg_spread
		for ly in range(_s(8)):
			for lw in range(_s(-2), _s(3)):
				_sp(img, lx + lw, by - ly, pants if ly < _s(6) else skin_shadow)
				if abs(lw) == _s(2):
					_sp(img, lx + lw, by - ly, outline)

	# Torso - tie-dye shirt with swirl pattern
	var torso_top = by - _s(22)
	var torso_bot = by - _s(8)
	var torso_w = _s(8)
	var lean = _s(4) if pose == 2 else 0  # Lunge forward on attack
	for y in range(torso_top, torso_bot):
		for x in range(-torso_w, torso_w + 1):
			var px = cx + x + lean
			# Tie-dye swirl: use sin/cos of distance from center
			var dist = sqrt(x * x + (y - (torso_top + torso_bot) / 2.0) * (y - (torso_top + torso_bot) / 2.0))
			var angle = atan2(float(y - (torso_top + torso_bot) / 2), float(x))
			var swirl = sin(dist * 0.3 + angle * 2.0)
			var c: Color
			if swirl < -0.3:
				c = shirt1
			elif swirl < 0.3:
				c = shirt2
			else:
				c = shirt3
			if abs(x) >= torso_w - 1:
				c = outline
			_sp(img, px, y, c)

	# Arms
	var arm_raise = _s(-4) if pose == 2 else 0
	for arm_side in [-1, 1]:
		var ax = cx + arm_side * (torso_w + _s(1)) + lean
		for ay in range(_s(10)):
			_sp(img, ax, torso_top + _s(3) + ay + arm_raise, skin if ay > _s(2) else shirt1)
			_sp(img, ax + arm_side, torso_top + _s(3) + ay + arm_raise, skin_shadow if ay > _s(2) else shirt2)

	# Peace sign (raised in attack pose)
	if pose == 2:
		var px = cx + _s(10) + lean
		var py = torso_top - _s(2)
		# Circle
		for a in range(24):
			var angle = a * TAU / 24.0
			var prx = px + int(cos(angle) * _sf(3))
			var pry = py + int(sin(angle) * _sf(3))
			_sp(img, prx, pry, peace_c)
		# Peace lines
		for i in range(_s(6)):
			_sp(img, px, py - _s(3) + i, peace_c)
		_sp(img, px - _s(1), py + _s(1), peace_c)
		_sp(img, px + _s(1), py + _s(1), peace_c)

	# Head
	var head_y = torso_top - _s(6)
	var head_r = _s(6)
	_SU._draw_ellipse_outline(img, cx + lean, head_y, head_r + 1, head_r + 1, outline)
	_SU._draw_ellipse_filled(img, cx + lean, head_y, head_r, head_r, skin, skin_shadow, skin)

	# Hair (long, flowing)
	for hx in range(-head_r - _s(1), head_r + _s(2)):
		for hy in range(-head_r - _s(2), _s(4)):
			if hy < -head_r * 0.3 or abs(hx) > head_r - _s(1):
				_sp(img, cx + hx + lean, head_y + hy, hair_c)

	# Headband
	for hx in range(-head_r - _s(1), head_r + _s(2)):
		_sp(img, cx + hx + lean, head_y - _s(2), headband)
		_sp(img, cx + hx + lean, head_y - _s(1), headband)

	# Eyes (small dots) and smile
	if pose != 3:  # Not hit
		_sp(img, cx - _s(2) + lean, head_y, Color(0.1, 0.1, 0.1))
		_sp(img, cx + _s(2) + lean, head_y, Color(0.1, 0.1, 0.1))
		_sp(img, cx + lean, head_y + _s(2), Color(0.8, 0.3, 0.3))  # Smile
	else:
		# Hit: X eyes
		for d in [-1, 1]:
			_sp(img, cx - _s(2) + d + lean, head_y + d, Color(0.1, 0.1, 0.1))
			_sp(img, cx + _s(2) + d + lean, head_y + d, Color(0.1, 0.1, 0.1))

	return ImageTexture.create_from_image(img)


## --- SPITEFUL CROW ---
static func create_spiteful_crow_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("spiteful_crow", _create_crow_frame)

static func _create_crow_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body_c = Color(0.1, 0.1, 0.12)
	var body_light = Color(0.18, 0.18, 0.22)
	var body_dark = Color(0.05, 0.05, 0.07)
	var wing_c = Color(0.08, 0.08, 0.1)
	var beak = Color(0.85, 0.65, 0.2)
	var beak_dark = Color(0.6, 0.45, 0.15)
	var eye_c = Color(0.9, 0.15, 0.1)
	var eye_glow = Color(1.0, 0.3, 0.2)
	var leg_c = Color(0.4, 0.35, 0.2)
	var outline = Color(0.2, 0.2, 0.25)

	var cx = size / 2
	var cy = int(size * 0.55 + _sf(y_offset))
	var defeated = pose == 4
	var attacking = pose == 1 or pose == 2

	if defeated:
		# Bird on its back, feet up
		for y in range(_s(-3), _s(4)):
			for x in range(_s(-10), _s(10)):
				_sp(img, cx + x, cy + _s(6) + y, body_dark)
		# Feet sticking up
		for fs in [-1, 1]:
			_sp(img, cx + fs * _s(3), cy + _s(2), leg_c)
			_sp(img, cx + fs * _s(3), cy + _s(1), leg_c)
		return ImageTexture.create_from_image(img)

	# Legs/feet
	for ls in [-1, 1]:
		var lx = cx + ls * _s(3)
		for ly in range(_s(4)):
			_sp(img, lx, cy + _s(6) + ly, leg_c)
		# Toes
		_sp(img, lx - 1, cy + _s(10), leg_c)
		_sp(img, lx + 1, cy + _s(10), leg_c)

	# Body (oval)
	var bdy_rx = _s(7)
	var bdy_ry = _s(6)
	_SU._draw_ellipse_outline(img, cx, cy, bdy_rx + 1, bdy_ry + 1, outline)
	for y in range(-bdy_ry, bdy_ry + 1):
		for x in range(-bdy_rx, bdy_rx + 1):
			var dist = sqrt(pow(float(x) / bdy_rx, 2) + pow(float(y) / bdy_ry, 2))
			if dist < 1.0:
				var c = body_c
				if y < -bdy_ry * 0.3: c = body_light
				elif y > bdy_ry * 0.3: c = body_dark
				_sp(img, cx + x, cy + y, c)

	# Wings
	var wing_up = _s(-6) if attacking else 0
	for side in [-1, 1]:
		for i in range(_s(12)):
			var wx = cx + side * (_s(6) + i)
			var wh = _s(4) - i / 3
			var wy = cy + wing_up + int(i * 0.4) * (1 if not attacking else -1)
			for w_y in range(-wh, wh):
				var c = wing_c if abs(w_y) < wh - 1 else outline
				_sp(img, wx, wy + w_y, c)

	# Head
	var head_y = cy - _s(8)
	var head_r = _s(5)
	_SU._draw_ellipse_outline(img, cx, head_y, head_r + 1, head_r + 1, outline)
	_SU._draw_ellipse_filled(img, cx, head_y, head_r, head_r, body_c, body_dark, body_light)

	# Angry red eyes (beady)
	for es in [-1, 1]:
		var ex = cx + es * _s(2)
		_sp(img, ex, head_y - _s(1), eye_c)
		_sp(img, ex, head_y, eye_c)
		_sp(img, ex - 1, head_y - _s(1), eye_glow)  # Catchlight
		# Angry eyebrow line
		_sp(img, ex - 1, head_y - _s(2), outline)
		_sp(img, ex, head_y - _s(2), outline)
		_sp(img, ex + es, head_y - _s(3), outline)

	# Beak
	var beak_len = _s(5) if attacking else _s(3)
	for bx in range(beak_len):
		var bw = max(1, _s(2) - bx / 2)
		for by in range(-bw, bw + 1):
			var c = beak if by <= 0 else beak_dark
			_sp(img, cx + _s(5) + bx, head_y + _s(1) + by, c)

	return ImageTexture.create_from_image(img)


## --- SKATE PUNK ---
static func create_skate_punk_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("skate_punk", _create_skate_punk_frame)

static func _create_skate_punk_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var skin = Color(0.82, 0.68, 0.55)
	var skin_shadow = Color(0.65, 0.5, 0.38)
	var hair_c = Color(0.2, 0.8, 0.3)  # Green mohawk
	var shirt_c = Color(0.15, 0.15, 0.15)  # Black band tee
	var skull_c = Color(0.9, 0.9, 0.9)  # Skull graphic
	var shorts = Color(0.6, 0.5, 0.3)  # Cargo shorts
	var shoe_c = Color(0.7, 0.2, 0.2)  # Red sneakers
	var board_top = Color(0.7, 0.55, 0.3)  # Skateboard deck
	var board_bot = Color(0.5, 0.8, 0.3)  # Board graphic
	var cap_c = Color(0.8, 0.2, 0.2)  # Backwards red cap
	var outline = Color(0.1, 0.08, 0.06)

	var cx = size / 2
	var by = int(size * 0.88 + _sf(y_offset))
	var defeated = pose == 4
	var attacking = pose == 1 or pose == 2

	if defeated:
		# Lying flat with skateboard rolling away
		for x in range(_s(-12), _s(12)):
			for y in range(_s(-2), _s(3)):
				_sp(img, cx + x, by - _s(2) + y, shirt_c if x < _s(4) else shorts)
		# Board rolling away
		for x in range(_s(8)):
			_sp(img, cx + _s(14) + x, by, board_top)
			_sp(img, cx + _s(14) + x, by + 1, board_bot)
		return ImageTexture.create_from_image(img)

	# Skateboard (under feet normally, held in attack)
	if not attacking:
		for x in range(_s(-8), _s(8)):
			_sp(img, cx + x, by, board_top)
			_sp(img, cx + x, by + 1, board_bot)
			if abs(x) >= _s(7):
				_sp(img, cx + x, by - 1, board_top)  # Kicktail
		# Wheels
		for ws in [-1, 1]:
			_sp(img, cx + ws * _s(5), by + _s(2), Color(0.3, 0.3, 0.3))

	# Legs
	for ls in [-1, 1]:
		var lx = cx + ls * _s(3)
		for ly in range(_s(8)):
			_sp(img, lx, by - _s(2) - ly, shorts if ly < _s(5) else skin)
			_sp(img, lx + 1, by - _s(2) - ly, shorts if ly < _s(5) else skin_shadow)
		# Shoes
		_sp(img, lx, by - _s(1), shoe_c)
		_sp(img, lx + 1, by - _s(1), shoe_c)
		_sp(img, lx - 1, by - _s(1), shoe_c)

	# Torso (black band tee)
	var torso_top = by - _s(22)
	var torso_bot = by - _s(10)
	for y in range(torso_top, torso_bot):
		for x in range(_s(-7), _s(7)):
			_sp(img, cx + x, y, shirt_c)
			if abs(x) == _s(6):
				_sp(img, cx + x, y, outline)

	# Skull graphic on shirt
	var skull_y = (torso_top + torso_bot) / 2
	for sx in range(_s(-3), _s(3)):
		for sy in range(_s(-3), _s(3)):
			var dist = abs(sx) + abs(sy)
			if dist < _s(3):
				_sp(img, cx + sx, skull_y + sy, skull_c)
	# Skull eyes
	_sp(img, cx - _s(1), skull_y - _s(1), shirt_c)
	_sp(img, cx + _s(1), skull_y - _s(1), shirt_c)

	# Arms (one holds board when attacking)
	for as2 in [-1, 1]:
		var ax = cx + as2 * _s(8)
		for ay in range(_s(8)):
			_sp(img, ax, torso_top + _s(3) + ay, skin)

	# Skateboard held overhead in attack
	if attacking:
		for x in range(_s(-8), _s(8)):
			_sp(img, cx + x, torso_top - _s(6), board_top)
			_sp(img, cx + x, torso_top - _s(5), board_bot)

	# Head
	var head_y = torso_top - _s(5)
	var head_r = _s(5)
	_SU._draw_ellipse_filled(img, cx, head_y, head_r, head_r, skin, skin_shadow, skin)
	_SU._draw_ellipse_outline(img, cx, head_y, head_r + 1, head_r + 1, outline)

	# Backwards cap
	for hx in range(-head_r, head_r + 1):
		if hx > -_s(2):  # Backwards = brim on back
			_sp(img, cx + hx, head_y - head_r, cap_c)
			_sp(img, cx + hx, head_y - head_r + 1, cap_c)
	# Brim going back
	for bx in range(_s(4)):
		_sp(img, cx + head_r + bx - _s(1), head_y - head_r + _s(1), cap_c)

	# Green mohawk poking out front
	for mx in range(_s(-4), _s(0)):
		for my in range(_s(4)):
			_sp(img, cx + mx, head_y - head_r - my, hair_c)

	# Eyes and smirk
	if pose != 3:
		_sp(img, cx - _s(2), head_y, Color(0.1, 0.1, 0.1))
		_sp(img, cx + _s(2), head_y, Color(0.1, 0.1, 0.1))
		_sp(img, cx + _s(1), head_y + _s(2), Color(0.7, 0.3, 0.3))  # Smirk
	else:
		_sp(img, cx, head_y, Color(0.8, 0.2, 0.1))  # Ouch face

	return ImageTexture.create_from_image(img)


## --- UNASSUMING DOG ---
static func create_unassuming_dog_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("unassuming_dog", _create_unassuming_dog_frame)

static func _create_unassuming_dog_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var fur = Color(0.75, 0.6, 0.4)
	var fur_dark = Color(0.55, 0.4, 0.25)
	var fur_light = Color(0.9, 0.78, 0.6)
	var belly = Color(0.92, 0.85, 0.75)
	var nose_c = Color(0.15, 0.12, 0.1)
	var eye_c = Color(0.2, 0.15, 0.1)
	var eye_white = Color(0.95, 0.95, 0.9)
	var tongue = Color(0.85, 0.4, 0.45)
	var outline = Color(0.2, 0.15, 0.1)

	var cx = size / 2
	var cy = int(size * 0.6 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Dog lying on side
		for y in range(_s(-4), _s(4)):
			for x in range(_s(-14), _s(14)):
				var c = fur if y < _s(1) else belly
				_sp(img, cx + x, cy + _s(4) + y, c)
		# X eyes
		_sp(img, cx + _s(8), cy + _s(2), eye_c)
		return ImageTexture.create_from_image(img)

	# Legs (4 legs, side view)
	for ls in [-1, 1]:
		var front_x = cx + ls * _s(2) + _s(6)
		var back_x = cx + ls * _s(2) - _s(6)
		for ly in range(_s(6)):
			_sp(img, front_x, cy + _s(6) + ly, fur_dark)
			_sp(img, back_x, cy + _s(6) + ly, fur_dark)

	# Body (horizontal oval for side-view dog)
	var body_rx = _s(10)
	var body_ry = _s(6)
	_SU._draw_ellipse_outline(img, cx, cy, body_rx + 1, body_ry + 1, outline)
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var c = fur
				if y > body_ry * 0.3: c = belly
				elif y < -body_ry * 0.3: c = fur_light
				elif x > body_rx * 0.3: c = fur_dark
				_sp(img, cx + x, cy + y, c)

	# Tail (wagging in idle, drooping in hit)
	var tail_wag = _s(3) if pose == 0 else (_s(-2) if pose == 3 else _s(1))
	for tx in range(_s(6)):
		_sp(img, cx - body_rx - tx, cy - _s(2) - tail_wag + tx / 2, fur_dark)
		_sp(img, cx - body_rx - tx, cy - _s(1) - tail_wag + tx / 2, fur)

	# Head
	var head_x = cx + _s(10)
	var head_y = cy - _s(3)
	var head_r = _s(5)
	_SU._draw_ellipse_outline(img, head_x, head_y, head_r + 1, head_r + 1, outline)
	_SU._draw_ellipse_filled(img, head_x, head_y, head_r, head_r, fur, fur_dark, fur_light)

	# Ears (floppy)
	for ey in range(_s(5)):
		_sp(img, head_x - _s(3), head_y - head_r + ey, fur_dark)
		_sp(img, head_x - _s(4), head_y - head_r + ey + 1, fur_dark)
		_sp(img, head_x + _s(3), head_y - head_r + ey, fur_dark)
		_sp(img, head_x + _s(4), head_y - head_r + ey + 1, fur_dark)

	# Snout
	var snout_x = head_x + _s(4)
	for sx in range(_s(3)):
		for sy in range(_s(-2), _s(2)):
			_sp(img, snout_x + sx, head_y + _s(1) + sy, fur_light)
	_sp(img, snout_x + _s(3), head_y, nose_c)  # Nose
	_sp(img, snout_x + _s(3), head_y + 1, nose_c)

	# Eyes - slightly menacing (narrow)
	_sp(img, head_x - _s(1), head_y - _s(1), eye_white)
	_sp(img, head_x, head_y - _s(1), eye_c)
	# Slight eyebrow angle for menace
	_sp(img, head_x - _s(2), head_y - _s(2), outline)
	_sp(img, head_x - _s(1), head_y - _s(3), outline)

	# Tongue (in attack pose)
	if pose == 1 or pose == 2:
		for ty in range(_s(3)):
			_sp(img, snout_x + _s(2), head_y + _s(2) + ty, tongue)

	return ImageTexture.create_from_image(img)


## --- CRANKY LADY ---
static func create_cranky_lady_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("cranky_lady", _create_cranky_lady_frame)

static func _create_cranky_lady_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var skin = Color(0.88, 0.75, 0.65)
	var skin_shadow = Color(0.72, 0.58, 0.48)
	var hair_c = Color(0.7, 0.7, 0.75)  # Gray hair
	var hair_dark = Color(0.5, 0.5, 0.55)
	var dress = Color(0.55, 0.2, 0.4)  # Purple-ish dress
	var dress_light = Color(0.7, 0.35, 0.55)
	var bag_c = Color(0.5, 0.3, 0.15)  # Brown handbag
	var bag_clasp = Color(0.8, 0.7, 0.3)  # Gold clasp
	var shoe_c = Color(0.3, 0.15, 0.1)
	var glasses = Color(0.6, 0.6, 0.65)
	var outline = Color(0.15, 0.1, 0.1)

	var cx = size / 2
	var by = int(size * 0.88 + _sf(y_offset))
	var defeated = pose == 4
	var attacking = pose == 1 or pose == 2

	if defeated:
		for x in range(_s(-10), _s(10)):
			for y in range(_s(-3), _s(3)):
				_sp(img, cx + x, by - _s(2) + y, dress)
		return ImageTexture.create_from_image(img)

	# Shoes
	for ss in [-1, 1]:
		for sx in range(_s(-2), _s(3)):
			_sp(img, cx + ss * _s(3) + sx, by, shoe_c)

	# Dress (A-line, wider at bottom)
	var dress_top = by - _s(22)
	for y in range(dress_top, by - _s(1)):
		var progress = float(y - dress_top) / float(by - _s(1) - dress_top)
		var width = int(_s(6) + progress * _s(4))
		for x in range(-width, width + 1):
			var c = dress if abs(x) < width - 1 else dress_light
			if abs(x) == width: c = outline
			_sp(img, cx + x, y, c)

	# Arms
	var bag_swing = _s(6) if attacking else 0
	for ay in range(_s(8)):
		# Left arm normal
		_sp(img, cx - _s(7), dress_top + _s(3) + ay, skin)
		# Right arm - holds handbag, swings in attack
		_sp(img, cx + _s(7) + bag_swing, dress_top + _s(3) + ay, skin)

	# Handbag weapon
	var bag_x = cx + _s(8) + bag_swing
	var bag_y = dress_top + _s(12)
	for bx in range(_s(-3), _s(4)):
		for bag_by in range(_s(-3), _s(4)):
			_sp(img, bag_x + bx, bag_y + bag_by, bag_c)
	_sp(img, bag_x, bag_y - _s(3), bag_clasp)  # Clasp
	# Handle
	for hx in range(_s(-2), _s(3)):
		_sp(img, bag_x + hx, bag_y - _s(4), bag_c)

	# Head
	var head_y = dress_top - _s(5)
	var head_r = _s(5)
	_SU._draw_ellipse_filled(img, cx, head_y, head_r, head_r, skin, skin_shadow, skin)
	_SU._draw_ellipse_outline(img, cx, head_y, head_r + 1, head_r + 1, outline)

	# Gray hair (piled up bun style)
	for hx in range(-head_r, head_r + 1):
		for hy in range(-head_r - _s(3), -head_r + _s(2)):
			var dist = abs(hx) + abs(hy + head_r)
			if dist < head_r + _s(2):
				_sp(img, cx + hx, head_y + hy, hair_c if (hx + hy) % 2 == 0 else hair_dark)

	# Glasses (round)
	for gs in [-1, 1]:
		var gx = cx + gs * _s(2)
		for a in range(16):
			var angle = a * TAU / 16.0
			_sp(img, gx + int(cos(angle) * _sf(2)), head_y + int(sin(angle) * _sf(2)), glasses)
	# Bridge
	_sp(img, cx, head_y, glasses)

	# Angry expression
	if pose != 3:
		# Angry eyebrows (V shape)
		for d in range(_s(3)):
			_sp(img, cx - _s(3) + d, head_y - _s(3) + d, outline)
			_sp(img, cx + _s(3) - d, head_y - _s(3) + d, outline)
		# Frown
		_sp(img, cx - _s(1), head_y + _s(3), outline)
		_sp(img, cx, head_y + _s(3) + 1, outline)
		_sp(img, cx + _s(1), head_y + _s(3), outline)
	else:
		_sp(img, cx, head_y + _s(2), Color(0.8, 0.2, 0.1))

	return ImageTexture.create_from_image(img)


## --- ABSTRACT ART ---
static func create_abstract_art_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("abstract_art", _create_abstract_art_frame)

static func _create_abstract_art_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Bold modern art colors
	var red = Color(0.9, 0.15, 0.1)
	var blue = Color(0.1, 0.3, 0.9)
	var yellow = Color(0.95, 0.85, 0.1)
	var black = Color(0.1, 0.1, 0.1)
	var white_c = Color(0.95, 0.95, 0.92)
	var pink = Color(0.9, 0.4, 0.6)
	var teal = Color(0.1, 0.7, 0.65)

	var cx = size / 2
	var cy = int(size * 0.5 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Shattered into fragments
		var seed_val = 42
		for i in range(12):
			seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
			var fx = cx + (seed_val % _s(30)) - _s(15)
			seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
			var fy = cy + (seed_val % _s(20)) - _s(5)
			seed_val = (seed_val * 1103515245 + 12345) & 0x7FFFFFFF
			var fc = [red, blue, yellow, pink, teal][seed_val % 5]
			for dx in range(_s(3)):
				for dy in range(_s(3)):
					_sp(img, fx + dx, fy + dy + _s(4), fc)
		return ImageTexture.create_from_image(img)

	var wobble = _s(2) if pose == 0 else (_s(-3) if pose == 2 else 0)

	# Large triangle (red)
	for y in range(_s(16)):
		var w = y
		for x in range(-w, w + 1):
			_sp(img, cx - _s(10) + x + wobble, cy - _s(8) + y, red)

	# Circle (blue)
	var circle_r = _s(7)
	for y in range(-circle_r, circle_r + 1):
		for x in range(-circle_r, circle_r + 1):
			if x * x + y * y < circle_r * circle_r:
				_sp(img, cx + _s(6) + x + wobble, cy - _s(4) + y, blue)

	# Rectangle (yellow)
	for y in range(_s(8)):
		for x in range(_s(10)):
			_sp(img, cx - _s(5) + x + wobble, cy + _s(4) + y, yellow)

	# Intersecting lines (black, Mondrian-style)
	for i in range(_s(30)):
		_sp(img, cx - _s(15) + i + wobble, cy, black)
		_sp(img, cx - _s(15) + i + wobble, cy + 1, black)
	for i in range(_s(24)):
		_sp(img, cx + wobble, cy - _s(12) + i, black)
		_sp(img, cx + 1 + wobble, cy - _s(12) + i, black)

	# Floating dots
	_sp(img, cx - _s(8) + wobble, cy - _s(10), pink)
	_sp(img, cx + _s(10) + wobble, cy + _s(8), teal)
	_sp(img, cx + _s(3) + wobble, cy - _s(12), white_c)

	# "Eyes" - two small white dots that make it feel alive
	if pose != 4:
		_sp(img, cx - _s(2) + wobble, cy - _s(2), white_c)
		_sp(img, cx + _s(4) + wobble, cy - _s(2), white_c)
		_sp(img, cx - _s(2) + wobble, cy - _s(1), black)
		_sp(img, cx + _s(4) + wobble, cy - _s(1), black)

	return ImageTexture.create_from_image(img)


## --- RUNAWAY DOG ---
static func create_runaway_dog_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("runaway_dog", _create_runaway_dog_frame)

static func _create_runaway_dog_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var fur = Color(0.9, 0.85, 0.75)  # Light golden
	var fur_dark = Color(0.7, 0.6, 0.45)
	var fur_spot = Color(0.6, 0.4, 0.2)  # Brown spots
	var belly = Color(0.95, 0.92, 0.88)
	var tongue = Color(0.9, 0.4, 0.45)
	var nose_c = Color(0.15, 0.12, 0.1)
	var eye_c = Color(0.2, 0.15, 0.1)
	var outline = Color(0.25, 0.18, 0.12)

	var cx = size / 2
	var cy = int(size * 0.6 + _sf(y_offset))
	var defeated = pose == 4
	var running = pose == 0 or pose == 1

	if defeated:
		# Tired dog lying down panting
		for y in range(_s(-3), _s(4)):
			for x in range(_s(-12), _s(12)):
				_sp(img, cx + x, cy + _s(4) + y, fur)
		# Tongue hanging out
		for ty in range(_s(3)):
			_sp(img, cx + _s(10), cy + _s(5) + ty, tongue)
		return ImageTexture.create_from_image(img)

	# Animated legs (running motion)
	var leg_phase = 0 if not running else (1 if pose == 0 else 2)
	for i in range(4):
		var lx = cx + (i - 2) * _s(5)
		var leg_offset = _s(2) * (1 if (i + leg_phase) % 2 == 0 else -1)
		for ly in range(_s(6)):
			_sp(img, lx, cy + _s(5) + ly + leg_offset, fur_dark)

	# Body (slightly stretched for running feel)
	var body_rx = _s(12)
	var body_ry = _s(5)
	_SU._draw_ellipse_outline(img, cx, cy, body_rx + 1, body_ry + 1, outline)
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var c = fur
				if y > body_ry * 0.3: c = belly
				elif y < -body_ry * 0.3: c = fur_dark
				# Brown spots
				if (x + y * 3) % _s(8) < _s(2) and dist < 0.7:
					c = fur_spot
				_sp(img, cx + x, cy + y, c)

	# Tail (wagging enthusiastically - up and curled)
	for tx in range(_s(6)):
		var tail_y = cy - _s(4) - tx
		_sp(img, cx - body_rx + _s(1) - tx, tail_y, fur_dark)
		_sp(img, cx - body_rx + _s(1) - tx, tail_y + 1, fur)

	# Head (eager, forward-leaning)
	var head_x = cx + _s(10)
	var head_y = cy - _s(3)
	var head_r = _s(5)
	_SU._draw_ellipse_outline(img, head_x, head_y, head_r + 1, head_r + 1, outline)
	_SU._draw_ellipse_filled(img, head_x, head_y, head_r, head_r, fur, fur_dark, belly)

	# Floppy ears (bouncing)
	var ear_bounce = _s(1) if running else 0
	for ey in range(_s(5)):
		_sp(img, head_x - _s(3), head_y - head_r + ey + ear_bounce, fur_dark)
		_sp(img, head_x + _s(3), head_y - head_r + ey + ear_bounce, fur_dark)

	# Snout with open mouth
	for sx in range(_s(4)):
		for sy in range(_s(-2), _s(3)):
			_sp(img, head_x + head_r + sx, head_y + sy, fur)
	_sp(img, head_x + head_r + _s(4), head_y - _s(1), nose_c)
	_sp(img, head_x + head_r + _s(4), head_y, nose_c)

	# Tongue hanging out (excited!)
	for ty in range(_s(4)):
		_sp(img, head_x + head_r + _s(2), head_y + _s(2) + ty, tongue)
		_sp(img, head_x + head_r + _s(3), head_y + _s(2) + ty, tongue.darkened(0.1))

	# Happy eyes (wide, excited)
	_sp(img, head_x - _s(1), head_y - _s(1), eye_c)
	_sp(img, head_x - _s(1), head_y - _s(2), eye_c)
	# Catchlight
	_sp(img, head_x - _s(2), head_y - _s(2), Color(0.95, 0.95, 0.9))

	return ImageTexture.create_from_image(img)


## --- COUCH POTATO ---
static func create_couch_potato_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("couch_potato", _create_couch_potato_frame)

static func _create_couch_potato_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var potato = Color(0.7, 0.55, 0.3)
	var potato_dark = Color(0.5, 0.38, 0.2)
	var potato_light = Color(0.85, 0.72, 0.5)
	var spot = Color(0.55, 0.42, 0.22)  # Potato spots/eyes
	var couch = Color(0.4, 0.55, 0.35)  # Green couch
	var couch_dark = Color(0.3, 0.42, 0.25)
	var couch_light = Color(0.5, 0.65, 0.45)
	var eye_c = Color(0.15, 0.12, 0.08)
	var outline = Color(0.25, 0.18, 0.1)
	var remote_c = Color(0.3, 0.3, 0.35)

	var cx = size / 2
	var cy = int(size * 0.55 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Potato rolled off couch, couch tipped
		# Tipped couch
		for x in range(_s(-10), _s(10)):
			for y in range(_s(-2), _s(3)):
				_sp(img, cx + x - _s(6), cy + _s(8) + y, couch_dark)
		# Rolled potato
		var p_r = _s(5)
		for y in range(-p_r, p_r + 1):
			for x in range(-p_r, p_r + 1):
				if x * x + y * y < p_r * p_r:
					_sp(img, cx + _s(8) + x, cy + _s(6) + y, potato_dark)
		return ImageTexture.create_from_image(img)

	# Tiny couch (drawn first, behind potato)
	# Seat
	for x in range(_s(-12), _s(12)):
		for y in range(_s(4)):
			_sp(img, cx + x, cy + _s(4) + y, couch)
			if y == 0: _sp(img, cx + x, cy + _s(4), couch_light)

	# Couch back
	for x in range(_s(-12), _s(12)):
		for y in range(_s(6)):
			_sp(img, cx + x, cy - _s(2) + y, couch_dark if y < _s(2) else couch)
	# Armrests
	for arm_side in [-1, 1]:
		for y in range(_s(-2), _s(8)):
			for ax in range(_s(3)):
				_sp(img, cx + arm_side * (_s(12) + ax), cy + y, couch_dark)

	# Potato (sitting on couch)
	var p_rx = _s(8)
	var p_ry = _s(7)
	_SU._draw_ellipse_outline(img, cx, cy, p_rx + 1, p_ry + 1, outline)
	for y in range(-p_ry, p_ry + 1):
		for x in range(-p_rx, p_rx + 1):
			var dist = sqrt(pow(float(x) / p_rx, 2) + pow(float(y) / p_ry, 2))
			if dist < 1.0:
				var c = potato
				if y < -p_ry * 0.3: c = potato_light
				elif y > p_ry * 0.3: c = potato_dark
				# Potato spots
				if (x * 7 + y * 13) % 17 < 2 and dist < 0.8:
					c = spot
				_sp(img, cx + x, cy + y, c)

	# Stubby arms holding remote
	var arm_y = cy + _s(1)
	_sp(img, cx + _s(7), arm_y, potato_dark)
	_sp(img, cx + _s(8), arm_y, potato_dark)
	# Remote control
	for rx in range(_s(4)):
		_sp(img, cx + _s(9) + rx, arm_y, remote_c)
		_sp(img, cx + _s(9) + rx, arm_y - 1, remote_c)
	_sp(img, cx + _s(10), arm_y - 1, Color(0.8, 0.2, 0.2))  # Red button

	# Face on potato
	var wobble = 0
	if pose == 2: wobble = _s(2)  # Lean forward in attack (throws remote)
	if pose != 3:
		# Lazy half-closed eyes
		_sp(img, cx - _s(3) + wobble, cy - _s(2), eye_c)
		_sp(img, cx + _s(3) + wobble, cy - _s(2), eye_c)
		# Half-lid
		_sp(img, cx - _s(3) + wobble, cy - _s(3), potato)
		_sp(img, cx + _s(3) + wobble, cy - _s(3), potato)
		# Bored mouth
		_sp(img, cx - _s(1) + wobble, cy + _s(2), eye_c)
		_sp(img, cx + wobble, cy + _s(2), eye_c)
		_sp(img, cx + _s(1) + wobble, cy + _s(2), eye_c)
	else:
		# Surprised face when hit
		_sp(img, cx - _s(3), cy - _s(2), eye_c)
		_sp(img, cx + _s(3), cy - _s(2), eye_c)
		# O mouth
		for a in range(8):
			var angle = a * TAU / 8.0
			_sp(img, cx + int(cos(angle) * _sf(1)), cy + _s(2) + int(sin(angle) * _sf(1)), eye_c)

	return ImageTexture.create_from_image(img)


## --- MALL COP ---
static func create_mall_cop_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("mall_cop", _create_mall_cop_frame)

static func _create_mall_cop_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var skin = Color(0.8, 0.65, 0.5)
	var skin_shadow = Color(0.65, 0.5, 0.38)
	var shirt = Color(0.3, 0.35, 0.5)  # Navy blue
	var shirt_light = Color(0.4, 0.45, 0.6)
	var pants_c = Color(0.25, 0.25, 0.3)
	var belt = Color(0.2, 0.15, 0.1)
	var badge_c = Color(0.85, 0.75, 0.2)  # Gold badge
	var flash_body = Color(0.25, 0.25, 0.25)
	var flash_light = Color(1.0, 1.0, 0.7)  # Flashlight beam
	var shoe_c = Color(0.15, 0.12, 0.1)
	var hat_c = Color(0.2, 0.22, 0.35)
	var outline = Color(0.1, 0.08, 0.08)

	var cx = size / 2
	var by = int(size * 0.88 + _sf(y_offset))
	var defeated = pose == 4
	var attacking = pose == 1 or pose == 2

	if defeated:
		for x in range(_s(-12), _s(12)):
			for y in range(_s(-3), _s(3)):
				_sp(img, cx + x, by - _s(2) + y, shirt if x < 0 else pants_c)
		return ImageTexture.create_from_image(img)

	# Shoes
	for ss in [-1, 1]:
		for sx in range(_s(-2), _s(3)):
			_sp(img, cx + ss * _s(3) + sx, by, shoe_c)

	# Legs
	for ls in [-1, 1]:
		var lx = cx + ls * _s(3)
		for ly in range(_s(8)):
			_sp(img, lx, by - _s(1) - ly, pants_c)
			_sp(img, lx + 1, by - _s(1) - ly, pants_c)

	# Belt
	for bx in range(_s(-7), _s(7)):
		_sp(img, cx + bx, by - _s(9), belt)

	# Torso (slightly pudgy)
	var torso_top = by - _s(22)
	var torso_bot = by - _s(9)
	for y in range(torso_top, torso_bot):
		var progress = float(y - torso_top) / float(torso_bot - torso_top)
		var width = int(_s(6) + progress * _s(2))  # Wider at bottom (belly)
		for x in range(-width, width + 1):
			var c = shirt if abs(x) < width else outline
			if x > 0 and x < _s(3) and y < torso_top + _s(4):
				c = shirt_light  # Lighter chest area
			_sp(img, cx + x, y, c)

	# Badge
	_sp(img, cx - _s(3), torso_top + _s(3), badge_c)
	_sp(img, cx - _s(3), torso_top + _s(4), badge_c)
	_sp(img, cx - _s(2), torso_top + _s(3), badge_c)

	# Arms + flashlight
	for ay in range(_s(8)):
		_sp(img, cx - _s(7), torso_top + _s(3) + ay, skin if ay > _s(5) else shirt)
		var right_x = cx + _s(7)
		_sp(img, right_x, torso_top + _s(3) + ay, skin if ay > _s(5) else shirt)

	# Flashlight in right hand
	var flash_x = cx + _s(8)
	var flash_y = torso_top + _s(10)
	for fx in range(_s(5)):
		_sp(img, flash_x + fx, flash_y, flash_body)
		_sp(img, flash_x + fx, flash_y + 1, flash_body)
	# Flashlight beam (in attack)
	if attacking:
		for bx in range(_s(10)):
			var beam_width = 1 + bx / _s(3)
			for bwy in range(-beam_width, beam_width + 1):
				var c = flash_light
				c.a = 0.7 - float(bx) / _sf(15)
				_sp(img, flash_x + _s(5) + bx, flash_y + bwy, c)

	# Head
	var head_y = torso_top - _s(5)
	var head_r = _s(5)
	_SU._draw_ellipse_filled(img, cx, head_y, head_r, head_r, skin, skin_shadow, skin)
	_SU._draw_ellipse_outline(img, cx, head_y, head_r + 1, head_r + 1, outline)

	# Security hat
	for hx in range(-head_r - _s(1), head_r + _s(2)):
		_sp(img, cx + hx, head_y - head_r, hat_c)
		_sp(img, cx + hx, head_y - head_r - 1, hat_c)
		if hx > -_s(2) and hx < _s(3):
			_sp(img, cx + hx, head_y - head_r - 2, hat_c)
	# Hat brim
	for hx in range(-head_r - _s(2), head_r + _s(3)):
		_sp(img, cx + hx, head_y - head_r + _s(1), hat_c)

	# Stern expression
	if pose != 3:
		_sp(img, cx - _s(2), head_y, Color(0.15, 0.12, 0.1))
		_sp(img, cx + _s(2), head_y, Color(0.15, 0.12, 0.1))
		# Flat mouth
		for mx in range(_s(-2), _s(2)):
			_sp(img, cx + mx, head_y + _s(3), outline)
		# Mustache
		for mx in range(_s(-3), _s(3)):
			_sp(img, cx + mx, head_y + _s(2), Color(0.3, 0.2, 0.15))

	return ImageTexture.create_from_image(img)


## --- PRANK CALLER ---
static func create_prank_caller_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("prank_caller", _create_prank_caller_frame)

static func _create_prank_caller_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var shadow_c = Color(0.15, 0.1, 0.2)
	var shadow_mid = Color(0.22, 0.15, 0.28)
	var shadow_light = Color(0.3, 0.22, 0.38)
	var phone = Color(0.6, 0.6, 0.65)
	var phone_screen = Color(0.3, 0.9, 0.4)  # Green phone screen
	var eye_c = Color(0.4, 0.9, 0.3)  # Mischievous green eyes
	var grin = Color(0.9, 0.9, 0.85)
	var outline = Color(0.08, 0.05, 0.1)

	var cx = size / 2
	var by = int(size * 0.85 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Shadow dissipates into wisps
		for i in range(8):
			var wx = cx + (i * 7 - 24) % _s(30) - _s(15)
			var wy = by - _s(2) + (i * 3) % _s(6)
			for d in range(_s(3)):
				var c = shadow_c
				c.a = 0.5 - float(d) / _sf(6)
				_sp(img, wx + d, wy, c)
		return ImageTexture.create_from_image(img)

	# Shadowy body (amorphous, slightly transparent at edges)
	var body_rx = _s(8)
	var body_ry = _s(14)
	var body_cy = by - _s(14)
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var c = shadow_c
				if dist > 0.7:
					c = shadow_light
					c.a = 1.0 - (dist - 0.7) * 2.5
				elif y < -body_ry * 0.2:
					c = shadow_mid
				_sp(img, cx + x, body_cy + y, c)

	# Wispy bottom (no clear feet, fades out)
	for x in range(-body_rx, body_rx + 1):
		for wy in range(_s(4)):
			var c = shadow_c
			c.a = 0.6 - float(wy) / _sf(6)
			if (x + wy) % 3 != 0:  # Wispy effect
				_sp(img, cx + x, by + wy, c)

	# Phone held up to "ear" area
	var phone_x = cx + _s(6) if not (pose == 2) else cx + _s(10)
	var phone_y = body_cy - _s(4)
	for px in range(_s(3)):
		for py in range(_s(6)):
			_sp(img, phone_x + px, phone_y + py, phone)
	# Screen glow
	_sp(img, phone_x + _s(1), phone_y + _s(1), phone_screen)
	_sp(img, phone_x + _s(1), phone_y + _s(2), phone_screen)
	_sp(img, phone_x + _s(1), phone_y + _s(3), phone_screen)

	# Mischievous eyes (glowing green)
	if pose != 4:
		for es in [-1, 1]:
			var ex = cx + es * _s(3)
			var ey = body_cy - _s(5)
			_sp(img, ex, ey, eye_c)
			_sp(img, ex, ey + 1, eye_c)
			# Sly half-lid
			_sp(img, ex - 1, ey - 1, shadow_c)
			_sp(img, ex + 1, ey - 1, shadow_c)

		# Wide mischievous grin
		if pose != 3:
			for gx in range(_s(-4), _s(4)):
				var gy_off = abs(gx) / _s(2)
				_sp(img, cx + gx, body_cy - _s(1) + gy_off, grin)
		else:
			# Shocked O mouth when hit
			for a in range(8):
				var angle = a * TAU / 8.0
				_sp(img, cx + int(cos(angle) * _sf(2)), body_cy - _s(1) + int(sin(angle) * _sf(2)), grin)

	return ImageTexture.create_from_image(img)


## =============================
## META / GLITCH MONSTERS
## =============================


## --- CORRUPTED SPRITE ---
static func create_corrupted_sprite_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("corrupted_sprite", _create_corrupted_sprite_frame)

static func _create_corrupted_sprite_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var magenta = Color(1.0, 0.0, 1.0)
	var cyan = Color(0.0, 1.0, 1.0)
	var glitch_white = Color(1.0, 1.0, 1.0)
	var void_black = Color(0.05, 0.02, 0.08)
	var static_gray = Color(0.5, 0.5, 0.5)
	var outline = Color(0.3, 0.0, 0.3)

	var cx = size / 2
	var cy = int(size * 0.5 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Dissolving into static
		for y in range(size):
			for x in range(size):
				var hash_val = ((x * 73 + y * 137 + 42) * 1103515245 + 12345) & 0x7FFFFFFF
				if hash_val % 8 == 0 and abs(x - cx) < _s(15) and abs(y - cy) < _s(10):
					var c = [magenta, cyan, static_gray, void_black][hash_val % 4]
					c.a = 0.3
					_sp(img, x, y, c)
		return ImageTexture.create_from_image(img)

	# Base: scrambled humanoid shape
	var body_top = cy - _s(14)
	var body_bot = cy + _s(14)

	for y in range(body_top, body_bot):
		var row_width = _s(8)
		if y < cy - _s(8): row_width = _s(5)
		elif y > cy + _s(6): row_width = _s(6)

		var scanline_hash = ((y * 73 + pose * 17) * 1103515245 + 12345) & 0x7FFFFFFF
		var glitch_offset = 0
		if scanline_hash % 5 == 0:
			glitch_offset = (scanline_hash % _s(8)) - _s(4)

		for x in range(-row_width, row_width + 1):
			var px = cx + x + glitch_offset
			var hash_val = ((px * 73 + y * 137 + pose * 7) * 1103515245 + 12345) & 0x7FFFFFFF

			var c: Color
			if hash_val % 12 == 0:
				c = glitch_white
			elif hash_val % 7 == 0:
				c = magenta
			elif hash_val % 9 == 0:
				c = cyan
			elif hash_val % 11 == 0:
				c = static_gray
			else:
				c = void_black

			if y % _s(6) < _s(1):
				c = static_gray if hash_val % 2 == 0 else void_black

			_sp(img, px, y, c)

	# RGB color split on attack
	if pose == 2:
		for y in range(body_top, body_bot):
			for x in range(cx - _s(10), cx + _s(10)):
				if x >= 0 and x < size and y >= 0 and y < size:
					var existing = img.get_pixel(x, y)
					if existing.a > 0.1:
						_sp(img, x - 2, y, Color(existing.r, 0, 0, 0.3))
						_sp(img, x + 2, y, Color(0, 0, existing.b, 0.3))

	# Glitchy eyes
	if pose != 4:
		for es in [-1, 1]:
			var ex = cx + es * _s(3)
			var ey = cy - _s(10)
			_sp(img, ex, ey, magenta)
			_sp(img, ex, ey + 1, magenta)
			_sp(img, ex + es, ey, cyan)

	return ImageTexture.create_from_image(img)


## --- GLITCH ENTITY ---
static func create_glitch_entity_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("glitch_entity", _create_glitch_entity_frame)

static func _create_glitch_entity_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var magenta = Color(1.0, 0.0, 1.0)
	var cyan = Color(0.0, 1.0, 1.0)
	var glitch_white = Color(1.0, 1.0, 1.0)
	var void_black = Color(0.05, 0.02, 0.08)
	var red_split = Color(1.0, 0.0, 0.0)
	var green_split = Color(0.0, 1.0, 0.0)
	var blue_split = Color(0.0, 0.0, 1.0)
	var outline = Color(0.4, 0.0, 0.4)

	var cx = size / 2
	var cy = int(size * 0.5 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		for i in range(15):
			var hash_v = ((i * 1103515245 + 12345) & 0x7FFFFFFF)
			var px = cx + (hash_v % _s(20)) - _s(10)
			hash_v = (hash_v * 1103515245 + 12345) & 0x7FFFFFFF
			var py = cy + (hash_v % _s(16)) - _s(8)
			var c = [magenta, cyan, glitch_white][hash_v % 3]
			c.a = 0.3
			_sp(img, px, py, c)
		return ImageTexture.create_from_image(img)

	var shape_size = _s(14)
	var jitter = _s(2) if pose == 1 else 0

	# Diamond shape
	for y in range(-shape_size, shape_size + 1):
		var row_w = shape_size - abs(y)
		for x in range(-row_w, row_w + 1):
			var hash_val = ((x * 37 + y * 53 + pose * 11) * 1103515245) & 0x7FFFFFFF
			var c: Color
			if abs(x) + abs(y) > shape_size - _s(2):
				c = outline
			elif hash_val % 6 == 0:
				c = glitch_white
			elif hash_val % 4 == 0:
				c = magenta if y < 0 else cyan
			else:
				c = void_black
			_sp(img, cx + x + jitter, cy + y, c)

	# RGB split overlay triangles
	var tri_size = _s(6)
	var offsets = [Vector2i(-_s(2), -_s(1)), Vector2i(_s(2), -_s(1)), Vector2i(0, _s(2))]
	var colors = [red_split, green_split, blue_split]
	for idx in range(3):
		var off = offsets[idx]
		var col = colors[idx]
		col.a = 0.35
		for y in range(tri_size):
			var w = y
			for x in range(-w, w + 1):
				_sp(img, cx + off.x + x + jitter, cy + off.y - tri_size / 2 + y, col)

	# Scanlines
	for y in range(cy - shape_size, cy + shape_size):
		if y % _s(4) == 0:
			for x in range(cx - shape_size, cx + shape_size):
				if x >= 0 and x < size and y >= 0 and y < size:
					var existing = img.get_pixel(x, y)
					if existing.a > 0.1:
						_sp(img, x, y, existing.darkened(0.3))

	# Central eye
	if pose != 4:
		var eye_r = _s(3)
		for y in range(-eye_r, eye_r + 1):
			for x in range(-eye_r, eye_r + 1):
				if x * x + y * y < eye_r * eye_r:
					_sp(img, cx + x + jitter, cy + y, glitch_white)
				if x * x + y * y < (_s(1) + 1) * (_s(1) + 1):
					_sp(img, cx + x + jitter, cy + y, void_black)

	return ImageTexture.create_from_image(img)


## --- SCRIPT ERROR ---
static func create_script_error_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("script_error", _create_script_error_frame)

static func _create_script_error_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var bg = Color(0.15, 0.05, 0.05)
	var border_c = Color(0.8, 0.2, 0.2)
	var text_c = Color(0.9, 0.85, 0.8)
	var x_red = Color(0.9, 0.15, 0.1)
	var glitch_white = Color(1.0, 1.0, 1.0)
	var magenta = Color(1.0, 0.0, 1.0)
	var void_black = Color(0.05, 0.02, 0.08)

	var cx = size / 2
	var cy = int(size * 0.5 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		for y in range(_s(-8), _s(8)):
			for x in range(_s(-14), _s(14)):
				var hash_val = ((x * 53 + y * 37) * 1103515245) & 0x7FFFFFFF
				if hash_val % 4 == 0:
					var c = [bg, border_c, void_black][hash_val % 3]
					c.a = 0.3
					_sp(img, cx + x, cy + y, c)
		return ImageTexture.create_from_image(img)

	var wobble = 0
	if pose == 1: wobble = _s(-2)
	elif pose == 2: wobble = _s(3)
	elif pose == 3: wobble = _s(-1)

	# Error dialog box
	var box_w = _s(16)
	var box_h = _s(12)
	var box_top = cy - box_h
	var box_bot = cy + box_h

	# Background
	for y in range(box_top, box_bot):
		for x in range(-box_w, box_w + 1):
			_sp(img, cx + x + wobble, y, bg)

	# Red border
	for x in range(-box_w, box_w + 1):
		_sp(img, cx + x + wobble, box_top, border_c)
		_sp(img, cx + x + wobble, box_top + 1, border_c)
		_sp(img, cx + x + wobble, box_bot - 1, border_c)
		_sp(img, cx + x + wobble, box_bot, border_c)
	for y in range(box_top, box_bot + 1):
		_sp(img, cx - box_w + wobble, y, border_c)
		_sp(img, cx - box_w + 1 + wobble, y, border_c)
		_sp(img, cx + box_w + wobble, y, border_c)
		_sp(img, cx + box_w - 1 + wobble, y, border_c)

	# Red X icon circle
	var x_cx = cx - _s(10) + wobble
	var x_cy = cy - _s(4)
	var x_size = _s(4)
	for y in range(-x_size - 1, x_size + 2):
		for x in range(-x_size - 1, x_size + 2):
			if x * x + y * y < (x_size + 1) * (x_size + 1):
				_sp(img, x_cx + x, x_cy + y, x_red)
	for d in range(-x_size + 1, x_size):
		_sp(img, x_cx + d, x_cy + d, glitch_white)
		_sp(img, x_cx + d, x_cy - d, glitch_white)
		_sp(img, x_cx + d + 1, x_cy + d, glitch_white)
		_sp(img, x_cx + d + 1, x_cy - d, glitch_white)

	# "ERR" text (pixel font)
	var tx = cx - _s(4) + wobble
	var ty = cy - _s(3)
	# E
	for i in range(_s(5)):
		_sp(img, tx, ty + i, text_c)
	for i in range(_s(3)):
		_sp(img, tx + i, ty, text_c)
		_sp(img, tx + i, ty + _s(2), text_c)
		_sp(img, tx + i, ty + _s(4), text_c)
	# R
	tx = cx + wobble
	for i in range(_s(5)):
		_sp(img, tx, ty + i, text_c)
	for i in range(_s(3)):
		_sp(img, tx + i, ty, text_c)
		_sp(img, tx + i, ty + _s(2), text_c)
	_sp(img, tx + _s(2), ty + _s(1), text_c)
	_sp(img, tx + _s(1), ty + _s(3), text_c)
	_sp(img, tx + _s(2), ty + _s(4), text_c)
	# R2
	tx = cx + _s(4) + wobble
	for i in range(_s(5)):
		_sp(img, tx, ty + i, text_c)
	for i in range(_s(3)):
		_sp(img, tx + i, ty, text_c)
		_sp(img, tx + i, ty + _s(2), text_c)
	_sp(img, tx + _s(2), ty + _s(1), text_c)
	_sp(img, tx + _s(1), ty + _s(3), text_c)
	_sp(img, tx + _s(2), ty + _s(4), text_c)

	# Exclamation
	var ey = cy + _s(5)
	for i in range(_s(3)):
		_sp(img, cx + wobble, ey + i, text_c)
	_sp(img, cx + wobble, ey + _s(4), text_c)

	# Attack glitch flicker
	if pose == 2:
		for i in range(6):
			var hash_v = ((i * 1103515245 + 12345) & 0x7FFFFFFF)
			var gx = cx + (hash_v % _s(30)) - _s(15)
			hash_v = (hash_v * 1103515245 + 12345) & 0x7FFFFFFF
			var gy = cy + (hash_v % _s(20)) - _s(10)
			_sp(img, gx, gy, magenta)
			_sp(img, gx + 1, gy, magenta)

	return ImageTexture.create_from_image(img)


## --- NULL ENTITY ---
static func create_null_entity_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("null_entity", _create_null_entity_frame)

static func _create_null_entity_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var void_black = Color(0.05, 0.02, 0.08)
	var void_deep = Color(0.02, 0.0, 0.04)
	var void_purple = Color(0.15, 0.05, 0.2)
	var void_edge = Color(0.25, 0.1, 0.35)
	var hole_c = Color(0, 0, 0, 0)  # Actual transparency (pixel holes)
	var outline = Color(0.3, 0.1, 0.4)
	var glint = Color(0.6, 0.3, 0.8)

	var cx = size / 2
	var cy = int(size * 0.5 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Collapse into a single point
		for r in range(_s(3)):
			for a in range(12):
				var angle = a * TAU / 12.0
				_sp(img, cx + int(cos(angle) * float(r)), cy + int(sin(angle) * float(r)), void_purple)
		_sp(img, cx, cy, void_deep)
		return ImageTexture.create_from_image(img)

	# Amorphous void shape - humanoid absence
	var body_r = _s(14)
	var shrink = _s(2) if pose == 3 else 0  # Shrink when hit

	for y in range(-body_r + shrink, body_r - shrink + 1):
		for x in range(-body_r + shrink, body_r - shrink + 1):
			var dist = sqrt(pow(float(x) / (body_r - shrink), 2) + pow(float(y) / (body_r - shrink), 2))
			if dist < 1.0:
				var hash_val = ((x * 41 + y * 67 + pose * 13) * 1103515245 + 12345) & 0x7FFFFFFF

				# Pixel holes - create absence effect
				if hash_val % 7 == 0:
					continue  # Leave transparent = pixel hole

				var c: Color
				if dist > 0.85:
					c = void_edge
				elif dist > 0.6:
					c = void_purple
				elif dist > 0.3:
					c = void_black
				else:
					c = void_deep

				# More holes toward center (void within void)
				if dist < 0.4 and hash_val % 4 == 0:
					continue

				_sp(img, cx + x, cy + y, c)

	# Outline with gaps
	for a in range(48):
		var angle = a * TAU / 48.0
		var hash_a = ((a * 1103515245 + 12345) & 0x7FFFFFFF)
		if hash_a % 3 != 0:  # Gaps in outline
			var ox = cx + int(cos(angle) * float(body_r - shrink + 1))
			var oy = cy + int(sin(angle) * float(body_r - shrink + 1))
			_sp(img, ox, oy, outline)

	# Faint glints where "eyes" would be
	if pose != 4:
		for es in [-1, 1]:
			var ex = cx + es * _s(4)
			var ey2 = cy - _s(3)
			_sp(img, ex, ey2, glint)
			# Fading glow around
			for d in range(1, _s(3)):
				var gc = glint
				gc.a = 0.3 / float(d)
				_sp(img, ex + d, ey2, gc)
				_sp(img, ex - d, ey2, gc)
				_sp(img, ex, ey2 + d, gc)
				_sp(img, ex, ey2 - d, gc)

	# Pulsing expansion in attack pose
	if pose == 1 or pose == 2:
		var pulse_r = body_r + _s(3)
		for a in range(32):
			var angle = a * TAU / 32.0
			var pr = pulse_r + (a % 3) - 1
			var px = cx + int(cos(angle) * float(pr))
			var py = cy + int(sin(angle) * float(pr))
			var pc = void_purple
			pc.a = 0.4
			_sp(img, px, py, pc)

	return ImageTexture.create_from_image(img)


## --- ROGUE PROCESS ---
static func create_rogue_process_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("rogue_process", _create_rogue_process_frame)

static func _create_rogue_process_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var body_c = Color(0.1, 0.15, 0.12)  # Dark terminal green-black
	var grid_c = Color(0.0, 0.4, 0.1)  # Matrix green
	var text_bright = Color(0.0, 1.0, 0.2)  # Bright terminal green
	var text_dim = Color(0.0, 0.5, 0.1)
	var hex_c = Color(0.0, 0.8, 0.3)
	var eye_c = Color(1.0, 0.0, 0.0)  # Red process indicator
	var outline = Color(0.0, 0.3, 0.08)
	var void_black = Color(0.05, 0.02, 0.08)

	var cx = size / 2
	var cy = int(size * 0.5 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Process killed - "SIGTERM" scatter
		for i in range(10):
			var hash_v = ((i * 1103515245 + 12345) & 0x7FFFFFFF)
			var px = cx + (hash_v % _s(24)) - _s(12)
			hash_v = (hash_v * 1103515245 + 12345) & 0x7FFFFFFF
			var py = cy + (hash_v % _s(16)) - _s(8)
			var c = text_dim
			c.a = 0.4
			_sp(img, px, py, c)
			_sp(img, px + 1, py, c)
		return ImageTexture.create_from_image(img)

	# Body: rectangular terminal-window shape
	var box_w = _s(12)
	var box_h = _s(14)
	var box_top = cy - box_h
	var jitter = _s(1) if pose == 1 else 0

	# Terminal background
	for y in range(box_top, cy + box_h):
		for x in range(-box_w, box_w + 1):
			_sp(img, cx + x + jitter, y, body_c)

	# Green border/outline
	for x in range(-box_w, box_w + 1):
		_sp(img, cx + x + jitter, box_top, grid_c)
		_sp(img, cx + x + jitter, cy + box_h - 1, grid_c)
	for y in range(box_top, cy + box_h):
		_sp(img, cx - box_w + jitter, y, grid_c)
		_sp(img, cx + box_w + jitter, y, grid_c)

	# Binary/hex patterns scrolling down the body
	for y in range(box_top + _s(2), cy + box_h - _s(2)):
		var row_hash = ((y * 73 + pose * 31) * 1103515245) & 0x7FFFFFFF
		for x in range(-box_w + _s(2), box_w - _s(1), _s(3)):
			var hash_val = ((x * 37 + y * 53 + pose * 7) * 1103515245) & 0x7FFFFFFF
			if hash_val % 3 == 0:
				var c = text_bright if hash_val % 5 == 0 else text_dim
				_sp(img, cx + x + jitter, y, c)
				if hash_val % 7 == 0:
					_sp(img, cx + x + 1 + jitter, y, c)

	# "Legs" - data tendrils extending down
	for tendril in range(4):
		var tx = cx + (tendril - 2) * _s(5) + jitter
		for ty in range(_s(6)):
			var hash_v = ((tendril * 37 + ty * 53) * 1103515245) & 0x7FFFFFFF
			var c = grid_c if hash_v % 2 == 0 else text_dim
			c.a = 1.0 - float(ty) / _sf(8)
			_sp(img, tx, cy + box_h + ty, c)

	# Red "PID" eyes
	if pose != 4:
		for es in [-1, 1]:
			var ex = cx + es * _s(5) + jitter
			var ey2 = box_top + _s(5)
			for r in range(_s(2)):
				for a in range(8):
					var angle = a * TAU / 8.0
					_sp(img, ex + int(cos(angle) * float(r)), ey2 + int(sin(angle) * float(r)), eye_c)

	# Attack: data burst
	if pose == 2:
		for i in range(12):
			var hash_v = ((i * 1103515245 + 12345) & 0x7FFFFFFF)
			var bx = cx + (hash_v % _s(36)) - _s(18)
			hash_v = (hash_v * 1103515245 + 12345) & 0x7FFFFFFF
			var b_y = cy + (hash_v % _s(30)) - _s(15)
			_sp(img, bx, b_y, text_bright)
			_sp(img, bx + 1, b_y, hex_c)

	return ImageTexture.create_from_image(img)


## --- MEMORY LEAK ---
static func create_memory_leak_sprite_frames() -> SpriteFrames:
	return _build_standard_frames("memory_leak", _create_memory_leak_frame)

static func _create_memory_leak_frame(pose: int, y_offset: float) -> ImageTexture:
	var size = _SU.SPRITE_SIZE
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var fluid = Color(0.0, 0.7, 0.9)  # Cyan digital fluid
	var fluid_dark = Color(0.0, 0.4, 0.6)
	var fluid_light = Color(0.3, 0.9, 1.0)
	var pixel_c = Color(0.0, 1.0, 0.5)  # Degrading green pixels
	var pixel_dim = Color(0.0, 0.5, 0.25)
	var magenta = Color(1.0, 0.0, 1.0)
	var void_black = Color(0.05, 0.02, 0.08)
	var outline = Color(0.0, 0.3, 0.45)

	var cx = size / 2
	var cy = int(size * 0.45 + _sf(y_offset))
	var defeated = pose == 4

	if defeated:
		# Fully leaked - just a puddle
		for y in range(_s(-2), _s(3)):
			for x in range(_s(-14), _s(14)):
				var dist = float(abs(x)) / _sf(14)
				var c = fluid_dark
				c.a = 0.6 - dist * 0.4
				_sp(img, cx + x, cy + _s(12) + y, c)
		return ImageTexture.create_from_image(img)

	# Main body: amorphous blob that's dripping/degrading
	var body_rx = _s(10)
	var body_ry = _s(8)

	# Degradation: top half is more intact, bottom is breaking apart
	for y in range(-body_ry, body_ry + 1):
		for x in range(-body_rx, body_rx + 1):
			var dist = sqrt(pow(float(x) / body_rx, 2) + pow(float(y) / body_ry, 2))
			if dist < 1.0:
				var hash_val = ((x * 41 + y * 67 + pose * 13) * 1103515245) & 0x7FFFFFFF
				var v_pos = float(y) / body_ry

				# Bottom half degrades - missing pixels
				if v_pos > 0.3 and hash_val % 4 == 0:
					continue  # Missing pixel

				var c: Color
				if v_pos < -0.4:
					c = fluid_light
				elif v_pos < 0.0:
					c = fluid
				elif v_pos < 0.4:
					c = fluid_dark
				else:
					c = pixel_dim if hash_val % 3 == 0 else fluid_dark

				_sp(img, cx + x, cy + y, c)

	# Outline (partial, degrading)
	for a in range(48):
		var angle = a * TAU / 48.0
		var hash_a = ((a * 1103515245) & 0x7FFFFFFF)
		if hash_a % 4 != 0 or angle < PI:  # Outline mostly on top
			var ox = cx + int(cos(angle) * float(body_rx + 1))
			var oy = cy + int(sin(angle) * float(body_ry + 1))
			_sp(img, ox, oy, outline)

	# Dripping fluid tendrils
	var drip_positions = [-_s(7), -_s(3), _s(1), _s(5), _s(8)]
	for i in range(drip_positions.size()):
		var dx = cx + drip_positions[i]
		var drip_start = cy + body_ry
		var drip_len = _s(6) + (i * 3) % _s(4)
		if pose == 1: drip_len += _s(2)  # More dripping in attack

		for dy in range(drip_len):
			var t = float(dy) / float(drip_len)
			var c = fluid.lerp(fluid_dark, t)
			c.a = 1.0 - t * 0.6
			# Drip width narrows
			var dw = max(1, _s(2) - dy / _s(2))
			for dxx in range(-dw, dw + 1):
				_sp(img, dx + dxx, drip_start + dy, c)

		# Drip droplet at bottom
		if drip_len > _s(4):
			_sp(img, dx, drip_start + drip_len, fluid)
			_sp(img, dx, drip_start + drip_len + 1, fluid_dark)

	# Degrading pixels floating away
	for i in range(8):
		var hash_v = ((i * 1103515245 + 12345 + pose * 7) & 0x7FFFFFFF)
		var px = cx + (hash_v % _s(24)) - _s(12)
		hash_v = (hash_v * 1103515245 + 12345) & 0x7FFFFFFF
		var py = cy - _s(8) - (hash_v % _s(8))
		var c = pixel_c if hash_v % 2 == 0 else pixel_dim
		c.a = 0.5
		_sp(img, px, py, c)

	# "Eyes" - two leaking data points
	if pose != 4:
		for es in [-1, 1]:
			var ex = cx + es * _s(4)
			var ey2 = cy - _s(3)
			_sp(img, ex, ey2, magenta)
			_sp(img, ex, ey2 + 1, magenta)
			# Tear/leak from eye
			for ty in range(_s(3)):
				var tc = fluid_light
				tc.a = 0.7 - float(ty) / _sf(5)
				_sp(img, ex, ey2 + _s(2) + ty, tc)

	return ImageTexture.create_from_image(img)
