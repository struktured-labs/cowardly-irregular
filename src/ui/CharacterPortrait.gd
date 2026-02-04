extends Control
class_name CharacterPortrait

## CharacterPortrait - Generates SNES-quality character face portraits
## Pixel-art rendered via Image for proper shading, highlights, and detail
## Inspired by FF4/FF5/FF6 menu portraits

const CustomizationScript = preload("res://src/character/CharacterCustomization.gd")

## Size presets
enum PortraitSize {
	SMALL,   # 32x32 - for lists, small icons
	MEDIUM,  # 48x48 - for menus, party display
	LARGE,   # 64x64 - for battle, detailed view
	XLARGE   # 96x96 - for character creation preview
}

## Portrait data
var customization = null  # CharacterCustomization
var job_id: String = "fighter"
var size_preset: PortraitSize = PortraitSize.MEDIUM

## Calculated size
var _portrait_size: Vector2 = Vector2(48, 48)
## Internal render resolution (always render at 48x48 then scale)
const RENDER_SIZE: int = 48


func _init(custom = null, job: String = "fighter", size: PortraitSize = PortraitSize.MEDIUM) -> void:
	customization = custom
	job_id = job
	size_preset = size
	_calculate_size()


func _ready() -> void:
	_build_portrait()


func _calculate_size() -> void:
	match size_preset:
		PortraitSize.SMALL:
			_portrait_size = Vector2(32, 32)
		PortraitSize.MEDIUM:
			_portrait_size = Vector2(48, 48)
		PortraitSize.LARGE:
			_portrait_size = Vector2(64, 64)
		PortraitSize.XLARGE:
			_portrait_size = Vector2(96, 96)
	custom_minimum_size = _portrait_size
	size = _portrait_size


func set_customization(custom, job: String = "") -> void:
	customization = custom
	if job != "":
		job_id = job
	_build_portrait()


func _build_portrait() -> void:
	# Clear existing
	for child in get_children():
		child.queue_free()

	if not customization:
		_build_placeholder()
		return

	# Render portrait as pixel-art image at fixed resolution, then display scaled
	var img = Image.create(RENDER_SIZE, RENDER_SIZE, false, Image.FORMAT_RGBA8)
	_draw_portrait(img)

	var tex = ImageTexture.create_from_image(img)

	var sprite = TextureRect.new()
	sprite.texture = tex
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.size = _portrait_size
	sprite.position = Vector2.ZERO
	add_child(sprite)


func _build_placeholder() -> void:
	var bg = ColorRect.new()
	bg.color = Color(0.2, 0.2, 0.25)
	bg.size = _portrait_size
	add_child(bg)

	var question = Label.new()
	question.text = "?"
	question.add_theme_font_size_override("font_size", int(24 * _portrait_size.x / 48.0))
	question.position = _portrait_size / 2 - Vector2(6, 12)
	add_child(question)


## Safe pixel setter with bounds checking
func _sp(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)


## Draw a filled ellipse with gradient shading
func _draw_ellipse_shaded(img: Image, cx: int, cy: int, rx: int, ry: int, base: Color, dark: Color, light: Color) -> void:
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			var dist = sqrt(pow(float(x) / max(rx, 1), 2) + pow(float(y) / max(ry, 1), 2))
			if dist <= 1.0:
				var color = base
				# Top-left is highlight, bottom-right is shadow (SNES standard lighting)
				if y < -ry * 0.3 and x < rx * 0.2:
					color = light
				elif y > ry * 0.3 or x > rx * 0.5:
					color = dark
				_sp(img, cx + x, cy + y, color)


## Draw the complete portrait into the image
func _draw_portrait(img: Image) -> void:
	var job_color = _get_job_color(job_id)

	# Background gradient (job-themed, like FF6 portraits)
	var bg_dark = job_color.darkened(0.55)
	var bg_mid = job_color.darkened(0.40)
	var bg_light = job_color.darkened(0.25)
	for y in range(RENDER_SIZE):
		var t = float(y) / RENDER_SIZE
		var bg_color = bg_dark.lerp(bg_mid, t)
		# Add subtle diagonal highlight
		for x in range(RENDER_SIZE):
			var diag = float(x + y) / (RENDER_SIZE * 2)
			var c = bg_color.lerp(bg_light, diag * 0.3)
			_sp(img, x, y, c)

	var skin = customization.skin_tone
	var skin_dark = skin.darkened(0.18)
	var skin_light = skin.lightened(0.12)
	var skin_shadow = skin.darkened(0.30)
	var hair = customization.hair_color
	var hair_dark = hair.darkened(0.25)
	var hair_light = hair.lightened(0.18)
	var hair_shine = hair.lightened(0.35)
	var outline = Color(0.08, 0.08, 0.12)

	var cx = 24  # Center X
	var face_top = 6
	var face_bottom = 42

	# ---- NECK ----
	for y in range(36, 44):
		var neck_w = 5 - (y - 36) / 3
		for x in range(-neck_w, neck_w + 1):
			var c = skin if x < 1 else skin_dark
			_sp(img, cx + x, y, c)

	# ---- JOB OUTFIT / COLLAR ----
	_draw_job_collar(img, cx, job_color)

	# ---- FACE SHAPE (elliptical, SNES-style) ----
	var face_cx = cx
	var face_cy = 24
	var face_rx = 14
	var face_ry = 16

	# Face outline
	for y in range(-face_ry - 1, face_ry + 2):
		for x in range(-face_rx - 1, face_rx + 2):
			var dist = sqrt(pow(float(x) / (face_rx + 1), 2) + pow(float(y) / (face_ry + 1), 2))
			if dist >= 0.92 and dist < 1.0:
				_sp(img, face_cx + x, face_cy + y, outline)

	# Face fill with shading
	for y in range(-face_ry, face_ry + 1):
		for x in range(-face_rx, face_rx + 1):
			var dist = sqrt(pow(float(x) / face_rx, 2) + pow(float(y) / face_ry, 2))
			if dist < 1.0:
				var color = skin
				# Cheek shading - bottom and sides darker
				if y > face_ry * 0.4:
					color = skin_dark
				elif y > face_ry * 0.2 and abs(x) > face_rx * 0.5:
					color = skin_dark
				# Top forehead lighter
				if y < -face_ry * 0.3:
					color = skin_light
				# Left side shadow
				if x > face_rx * 0.6 and y > -face_ry * 0.2:
					color = skin_shadow
				# Cheek blush (subtle)
				if y > 0 and y < face_ry * 0.5 and abs(x) > face_rx * 0.3 and abs(x) < face_rx * 0.7:
					color = skin.lerp(Color(0.85, 0.55, 0.50), 0.15)
				_sp(img, face_cx + x, face_cy + y, color)

	# ---- HAIR ----
	_draw_hair_snes(img, cx, face_cy, face_rx, face_ry, hair, hair_dark, hair_light, hair_shine, outline)

	# ---- EYES ----
	_draw_eyes_snes(img, cx, face_cy)

	# ---- EYEBROWS ----
	_draw_eyebrows_snes(img, cx, face_cy)

	# ---- NOSE ----
	_draw_nose_snes(img, cx, face_cy)

	# ---- MOUTH ----
	_draw_mouth_snes(img, cx, face_cy)

	# ---- JOB OUTFIT OVERLAY ----
	_draw_job_outfit_snes(img, cx, face_cy, hair)

	# ---- FRAME BORDER (2-tone like FF6) ----
	var border_light = job_color.lightened(0.2)
	var border_dark = job_color.darkened(0.2)
	# Top and left = light (highlight)
	for x in range(RENDER_SIZE):
		_sp(img, x, 0, border_light)
		_sp(img, x, 1, border_light.darkened(0.1))
		_sp(img, x, RENDER_SIZE - 1, border_dark)
		_sp(img, x, RENDER_SIZE - 2, border_dark.lightened(0.05))
	for y in range(RENDER_SIZE):
		_sp(img, 0, y, border_light)
		_sp(img, 1, y, border_light.darkened(0.1))
		_sp(img, RENDER_SIZE - 1, y, border_dark)
		_sp(img, RENDER_SIZE - 2, y, border_dark.lightened(0.05))


func _draw_hair_snes(img: Image, cx: int, face_cy: int, face_rx: int, face_ry: int, hair: Color, hair_dark: Color, hair_light: Color, hair_shine: Color, outline: Color) -> void:
	var skin = customization.skin_tone if customization else Color(0.9, 0.75, 0.6)
	match customization.hair_style:
		CustomizationScript.HairStyle.SHORT:
			# Short cropped hair covering top of head
			for y in range(face_cy - face_ry - 2, face_cy - face_ry / 3):
				for x in range(cx - face_rx - 1, cx + face_rx + 2):
					var dist = sqrt(pow(float(x - cx) / (face_rx + 2), 2) + pow(float(y - (face_cy - face_ry)) / (face_ry * 0.5), 2))
					if dist < 1.2:
						var c = hair
						if y < face_cy - face_ry:
							c = hair_light
						elif x > cx + 2:
							c = hair_dark
						_sp(img, x, y, c)
			# Shine highlight
			_sp(img, cx - 4, face_cy - face_ry, hair_shine)
			_sp(img, cx - 3, face_cy - face_ry, hair_shine)

		CustomizationScript.HairStyle.LONG:
			# Long flowing hair past shoulders
			for y in range(face_cy - face_ry - 3, face_cy + face_ry + 4):
				var base_w = face_rx + 3 if y < face_cy else face_rx + 1
				if y > face_cy + 4:
					base_w = face_rx + 3 - (y - face_cy - 4) / 2
				for x in range(cx - base_w, cx + base_w + 1):
					var dist = abs(x - cx)
					if dist <= base_w:
						# Only draw hair where it should be (top, sides, not over face center)
						var is_side = abs(x - cx) > face_rx - 2
						var is_top = y < face_cy - face_ry / 2
						if is_side or is_top:
							var c = hair
							if y < face_cy - face_ry:
								c = hair_light
							elif (y + x) % 5 == 0:
								c = hair_dark  # Strand texture
							elif x > cx + 3:
								c = hair_dark
							_sp(img, x, y, c)
			# Shine
			for dy in range(3):
				_sp(img, cx - 5, face_cy - face_ry + dy, hair_shine)
				_sp(img, cx - 4, face_cy - face_ry + dy, hair_shine)

		CustomizationScript.HairStyle.SPIKY:
			# Spiky upward hair (like Cloud / anime style)
			for y in range(face_cy - face_ry - 8, face_cy - face_ry / 3):
				for x in range(cx - face_rx - 3, cx + face_rx + 4):
					var norm_x = float(x - cx) / (face_rx + 3)
					var norm_y = float(y - (face_cy - face_ry)) / (face_ry * 0.7)
					# Spike envelope
					var spike_val = sin(norm_x * 8.0) * 0.5 + 0.5
					var spike_height = -0.8 - spike_val * 0.6
					if norm_y > spike_height and norm_y < 0.8 and abs(norm_x) < 1.0:
						var c = hair
						if norm_y < spike_height + 0.3:
							c = hair_light
						elif norm_x > 0.3:
							c = hair_dark
						_sp(img, x, y, c)
			# Bright tips
			for sx in [-8, -3, 2, 7]:
				_sp(img, cx + sx, face_cy - face_ry - 6, hair_shine)
				_sp(img, cx + sx, face_cy - face_ry - 5, hair_light)

		CustomizationScript.HairStyle.BRAIDED:
			# Braided hair with visible braid over shoulder
			# Top hair
			for y in range(face_cy - face_ry - 2, face_cy - face_ry / 3):
				for x in range(cx - face_rx - 1, cx + face_rx + 2):
					var dist = abs(x - cx) / float(face_rx + 1)
					if dist < 1.0:
						var c = hair if dist < 0.6 else hair_dark
						if y < face_cy - face_ry:
							c = hair_light
						_sp(img, x, y, c)
			# Braid hanging down right side
			var braid_x = cx + face_rx - 2
			for y in range(face_cy - 4, face_cy + face_ry + 6):
				var braid_offset = int(sin(y * 0.8) * 2)
				var c = hair if (y % 3 < 2) else hair_dark
				_sp(img, braid_x + braid_offset, y, c)
				_sp(img, braid_x + braid_offset + 1, y, hair_dark)
			# Braid tie
			_sp(img, braid_x, face_cy + face_ry + 5, Color(0.8, 0.2, 0.2))
			_sp(img, braid_x + 1, face_cy + face_ry + 5, Color(0.8, 0.2, 0.2))

		CustomizationScript.HairStyle.PONYTAIL:
			# Hair on top with ponytail pulled back
			for y in range(face_cy - face_ry - 2, face_cy - face_ry / 3):
				for x in range(cx - face_rx, cx + face_rx + 1):
					var dist = abs(x - cx) / float(face_rx)
					if dist < 1.0:
						var c = hair
						if y < face_cy - face_ry:
							c = hair_light
						elif x > cx + 2:
							c = hair_dark
						_sp(img, x, y, c)
			# Ponytail flowing right
			for y in range(face_cy - face_ry + 2, face_cy + 8):
				var tail_x = cx + face_rx + (y - face_cy + face_ry) / 3
				var c = hair if y % 2 == 0 else hair_dark
				_sp(img, tail_x, y, c)
				_sp(img, tail_x + 1, y, hair_dark)
			# Hair tie
			_sp(img, cx + face_rx, face_cy - face_ry + 4, Color(0.7, 0.6, 0.2))

		CustomizationScript.HairStyle.MOHAWK:
			# Mohawk strip along center, shaved sides
			# Thin hair on sides
			for y in range(face_cy - face_ry - 1, face_cy - face_ry / 2):
				for x in range(cx - face_rx, cx + face_rx + 1):
					if abs(x - cx) > 3:
						_sp(img, x, y, skin.darkened(0.05))  # Shaved sides
			# Central mohawk strip
			for y in range(face_cy - face_ry - 10, face_cy - face_ry / 3):
				var moh_w = 4 if y > face_cy - face_ry - 4 else 3
				for x in range(cx - moh_w, cx + moh_w + 1):
					var c = hair
					if y < face_cy - face_ry - 6:
						c = hair_light
					elif abs(x - cx) == moh_w:
						c = hair_dark
					_sp(img, x, y, c)
			# Shine on mohawk
			_sp(img, cx - 1, face_cy - face_ry - 8, hair_shine)
			_sp(img, cx, face_cy - face_ry - 8, hair_shine)


func _draw_eyes_snes(img: Image, cx: int, face_cy: int) -> void:
	var eye_white = Color(0.95, 0.95, 1.0)
	var eye_iris = Color(0.2, 0.35, 0.6)  # Blue-ish iris
	var eye_pupil = Color(0.08, 0.08, 0.12)
	var eye_highlight = Color(1.0, 1.0, 1.0)
	var eye_shadow = Color(0.15, 0.12, 0.18)

	var eye_y = face_cy - 2
	var eye_spacing = 7

	# Eye dimensions based on shape
	var ew = 4  # eye white width (half)
	var eh = 3  # eye height (half)
	var iris_r = 2

	match customization.eye_shape:
		CustomizationScript.EyeShape.NORMAL:
			ew = 4; eh = 3; iris_r = 2
		CustomizationScript.EyeShape.NARROW:
			ew = 5; eh = 2; iris_r = 1
		CustomizationScript.EyeShape.WIDE:
			ew = 5; eh = 4; iris_r = 2
		CustomizationScript.EyeShape.CLOSED:
			# Draw closed eyes as curved lines
			for side in [-1, 1]:
				var ex = cx + side * eye_spacing
				for dx in range(-3, 4):
					var dy = abs(dx) / 2
					_sp(img, ex + dx, eye_y + dy, eye_shadow)
			return

	for side in [-1, 1]:
		var ex = cx + side * eye_spacing

		# Eye white (elliptical)
		for y in range(-eh, eh + 1):
			for x in range(-ew, ew + 1):
				var dist = sqrt(pow(float(x) / ew, 2) + pow(float(y) / eh, 2))
				if dist < 1.0:
					_sp(img, ex + x, eye_y + y, eye_white)

		# Upper eyelid shadow
		for x in range(-ew + 1, ew):
			_sp(img, ex + x, eye_y - eh, eye_shadow)

		# Iris (colored circle)
		for y in range(-iris_r, iris_r + 1):
			for x in range(-iris_r, iris_r + 1):
				if x * x + y * y <= iris_r * iris_r:
					var c = eye_iris
					if y < 0:
						c = eye_iris.lightened(0.15)
					_sp(img, ex + x, eye_y + y, c)

		# Pupil
		_sp(img, ex, eye_y, eye_pupil)
		if iris_r >= 2:
			_sp(img, ex, eye_y + 1, eye_pupil)

		# Catchlight (white reflection dot, upper-left)
		_sp(img, ex - 1, eye_y - 1, eye_highlight)

		# Lower eyelash for emphasis
		_sp(img, ex + ew - 1, eye_y + eh - 1, eye_shadow)


func _draw_eyebrows_snes(img: Image, cx: int, face_cy: int) -> void:
	var brow_color = customization.hair_color.darkened(0.2)
	var brow_y = face_cy - 7
	var eye_spacing = 7

	for side in [-1, 1]:
		var bx = cx + side * eye_spacing

		match customization.eyebrow_style:
			CustomizationScript.EyebrowStyle.NORMAL:
				for dx in range(-3, 4):
					_sp(img, bx + dx, brow_y, brow_color)
				_sp(img, bx - 3, brow_y + 1, brow_color)
			CustomizationScript.EyebrowStyle.THICK:
				for dx in range(-4, 5):
					_sp(img, bx + dx, brow_y, brow_color)
					_sp(img, bx + dx, brow_y + 1, brow_color)
				_sp(img, bx - 4, brow_y + 2, brow_color)
			CustomizationScript.EyebrowStyle.THIN:
				for dx in range(-3, 4):
					_sp(img, bx + dx, brow_y, brow_color)
			CustomizationScript.EyebrowStyle.ARCHED:
				for dx in range(-3, 4):
					var dy = -1 if abs(dx) < 2 else 0
					_sp(img, bx + dx, brow_y + dy, brow_color)
				_sp(img, bx + (3 * side), brow_y + 1, brow_color)


func _draw_nose_snes(img: Image, cx: int, face_cy: int) -> void:
	var nose_shadow = customization.skin_tone.darkened(0.15)
	var nose_highlight = customization.skin_tone.lightened(0.08)
	var nose_y = face_cy + 5

	match customization.nose_shape:
		CustomizationScript.NoseShape.NORMAL:
			# Simple nose shadow line, SNES style
			_sp(img, cx, nose_y, nose_shadow)
			_sp(img, cx, nose_y + 1, nose_shadow)
			_sp(img, cx - 1, nose_y + 2, nose_shadow)
			_sp(img, cx + 1, nose_y + 2, nose_shadow)
			_sp(img, cx - 1, nose_y + 1, nose_highlight)
		CustomizationScript.NoseShape.SMALL:
			_sp(img, cx, nose_y + 1, nose_shadow)
			_sp(img, cx - 1, nose_y + 1, nose_highlight)
		CustomizationScript.NoseShape.POINTED:
			for dy in range(4):
				_sp(img, cx, nose_y + dy, nose_shadow)
			_sp(img, cx - 1, nose_y, nose_highlight)
			_sp(img, cx + 1, nose_y + 3, nose_shadow)
		CustomizationScript.NoseShape.BROAD:
			_sp(img, cx, nose_y, nose_shadow)
			_sp(img, cx, nose_y + 1, nose_shadow)
			_sp(img, cx - 2, nose_y + 2, nose_shadow)
			_sp(img, cx - 1, nose_y + 2, nose_shadow)
			_sp(img, cx + 1, nose_y + 2, nose_shadow)
			_sp(img, cx + 2, nose_y + 2, nose_shadow)
			_sp(img, cx - 2, nose_y + 1, nose_highlight)


func _draw_mouth_snes(img: Image, cx: int, face_cy: int) -> void:
	var mouth_y = face_cy + 10
	var lip_color = Color(0.70, 0.40, 0.40)
	var lip_dark = Color(0.50, 0.28, 0.28)
	var lip_light = Color(0.80, 0.55, 0.50)
	var skin_below = customization.skin_tone.darkened(0.08)

	match customization.mouth_style:
		CustomizationScript.MouthStyle.NEUTRAL:
			for dx in range(-3, 4):
				_sp(img, cx + dx, mouth_y, lip_color)
			_sp(img, cx - 3, mouth_y, lip_dark)
			_sp(img, cx + 3, mouth_y, lip_dark)
			# Subtle chin shadow below
			for dx in range(-2, 3):
				_sp(img, cx + dx, mouth_y + 2, skin_below)

		CustomizationScript.MouthStyle.SMILE:
			# Curved upward smile
			for dx in range(-4, 5):
				var dy = 0 if abs(dx) < 3 else -1
				_sp(img, cx + dx, mouth_y + dy, lip_color)
			_sp(img, cx - 4, mouth_y - 1, lip_dark)
			_sp(img, cx + 4, mouth_y - 1, lip_dark)
			# Teeth hint
			for dx in range(-2, 3):
				_sp(img, cx + dx, mouth_y - 1, lip_light)

		CustomizationScript.MouthStyle.FROWN:
			# Curved downward frown
			for dx in range(-3, 4):
				var dy = 0 if abs(dx) < 2 else 1
				_sp(img, cx + dx, mouth_y + dy, lip_color)
			_sp(img, cx - 3, mouth_y + 1, lip_dark)
			_sp(img, cx + 3, mouth_y + 1, lip_dark)

		CustomizationScript.MouthStyle.SMIRK:
			# Asymmetric smile (left side up)
			for dx in range(-3, 4):
				var dy = 0
				if dx < -1:
					dy = -1
				elif dx > 2:
					dy = 1
				_sp(img, cx + dx, mouth_y + dy, lip_color)
			_sp(img, cx - 3, mouth_y - 1, lip_dark)
			_sp(img, cx + 3, mouth_y + 1, lip_dark)


func _draw_job_collar(img: Image, cx: int, job_color: Color) -> void:
	"""Draw collar/clothing at bottom of portrait"""
	var collar_color = job_color
	var collar_dark = job_color.darkened(0.25)
	var collar_light = job_color.lightened(0.15)

	for y in range(40, RENDER_SIZE):
		var w = 18 + (y - 40) * 2
		for x in range(cx - w, cx + w + 1):
			if x >= 0 and x < RENDER_SIZE:
				var c = collar_color
				if x < cx - w + 3:
					c = collar_dark
				elif x > cx + w - 3:
					c = collar_light
				# Collar neckline V-shape
				if y < 44 and abs(x - cx) < (44 - y):
					continue  # Leave skin visible
				_sp(img, x, y, c)

	# Collar detail line
	for y in range(42, 46):
		if abs(y - 44) < 2:
			_sp(img, cx - (44 - y) - 1, y, collar_light)
			_sp(img, cx + (44 - y) + 1, y, collar_dark)


func _draw_job_outfit_snes(img: Image, cx: int, face_cy: int, hair_color: Color) -> void:
	"""Draw job-specific accessories on the portrait"""
	match job_id:
		"fighter":
			# Red headband across forehead
			var band_y = face_cy - 12
			var band_color = Color(0.75, 0.18, 0.18)
			var band_dark = Color(0.55, 0.12, 0.12)
			var band_light = Color(0.90, 0.30, 0.25)
			for dx in range(-12, 13):
				_sp(img, cx + dx, band_y, band_color)
				_sp(img, cx + dx, band_y + 1, band_dark)
			# Highlight on band
			for dx in range(-4, 0):
				_sp(img, cx + dx, band_y, band_light)
			# Band tails on right side
			_sp(img, cx + 13, band_y + 1, band_color)
			_sp(img, cx + 14, band_y + 2, band_color)
			_sp(img, cx + 13, band_y + 2, band_dark)

		"white_mage":
			# White cowl/hood framing the face
			var hood_color = Color(0.95, 0.93, 0.98)
			var hood_dark = Color(0.78, 0.76, 0.85)
			var hood_light = Color(1.0, 1.0, 1.0)
			# Hood over hair
			for y in range(face_cy - 18, face_cy - 12):
				for dx in range(-14, 15):
					var c = hood_color
					if y == face_cy - 18:
						c = hood_light
					elif abs(dx) > 10:
						c = hood_dark
					_sp(img, cx + dx, y, c)
			# Hood sides
			for y in range(face_cy - 12, face_cy + 4):
				for dx in [range(-14, -11), range(12, 15)]:
					for x in dx:
						var c = hood_dark if x > cx else hood_color
						_sp(img, cx + x, y, c)
			# Red triangle on hood
			for dy in range(4):
				for ddx in range(-dy, dy + 1):
					_sp(img, cx + ddx, face_cy - 17 + dy, Color(0.75, 0.20, 0.20))

		"black_mage":
			# Tall pointed hat covering upper face
			var hat_color = Color(0.12, 0.12, 0.28)
			var hat_dark = Color(0.06, 0.06, 0.18)
			var hat_light = Color(0.22, 0.22, 0.40)
			# Hat brim
			for dx in range(-16, 17):
				_sp(img, cx + dx, face_cy - 10, hat_color)
				_sp(img, cx + dx, face_cy - 9, hat_dark)
			# Hat cone
			for y in range(face_cy - 24, face_cy - 10):
				var progress = float(face_cy - 10 - y) / 14.0
				var w = int(8 * (1.0 - progress * 0.7))
				for dx in range(-w, w + 1):
					var c = hat_color
					if dx < -w + 2:
						c = hat_light
					elif dx > w - 2:
						c = hat_dark
					_sp(img, cx + dx, y, c)
			# Hat tip curves
			_sp(img, cx + 3, face_cy - 24, hat_color)
			_sp(img, cx + 4, face_cy - 23, hat_color)
			# Glowing yellow eyes (iconic black mage look)
			var glow = Color(1.0, 0.9, 0.3)
			var glow_dim = Color(0.8, 0.7, 0.2)
			for side in [-1, 1]:
				var ex = cx + side * 6
				_sp(img, ex - 1, face_cy - 4, glow_dim)
				_sp(img, ex, face_cy - 4, glow)
				_sp(img, ex + 1, face_cy - 4, glow)
				_sp(img, ex, face_cy - 3, glow)
				_sp(img, ex, face_cy - 5, glow_dim)
			# Dark shadow where face would be
			for y in range(face_cy - 8, face_cy + 4):
				for dx in range(-10, 11):
					var dist = abs(dx) + abs(y - face_cy)
					if dist < 12:
						_sp(img, cx + dx, y, Color(0.02, 0.02, 0.08))
			# Re-draw the glow eyes on top of shadow
			for side in [-1, 1]:
				var ex = cx + side * 6
				_sp(img, ex - 1, face_cy - 4, glow_dim)
				_sp(img, ex, face_cy - 4, glow)
				_sp(img, ex + 1, face_cy - 4, glow)
				_sp(img, ex, face_cy - 3, glow)

		"thief":
			# Green bandana with mask
			var bandana = Color(0.22, 0.52, 0.22)
			var bandana_dark = Color(0.15, 0.38, 0.15)
			var bandana_light = Color(0.32, 0.62, 0.30)
			# Bandana across forehead
			var band_y = face_cy - 11
			for dx in range(-13, 14):
				_sp(img, cx + dx, band_y, bandana)
				_sp(img, cx + dx, band_y + 1, bandana_dark)
			for dx in range(-6, 0):
				_sp(img, cx + dx, band_y, bandana_light)
			# Tails flowing left
			_sp(img, cx - 14, band_y + 1, bandana)
			_sp(img, cx - 15, band_y + 2, bandana)
			_sp(img, cx - 14, band_y + 3, bandana_dark)

		"red_mage":
			# Feathered hat
			var hat = Color(0.70, 0.20, 0.25)
			var hat_dark = Color(0.50, 0.12, 0.18)
			var hat_light = Color(0.85, 0.35, 0.35)
			for y in range(face_cy - 20, face_cy - 10):
				var w = 10 - (face_cy - 10 - y) / 2
				for dx in range(-w, w + 1):
					var c = hat if dx < 2 else hat_dark
					_sp(img, cx + dx, y, c)
			# White feather
			for dy in range(8):
				_sp(img, cx + 8 + dy / 2, face_cy - 18 + dy, Color(1.0, 1.0, 1.0))

		"monk":
			# Simple headband, bare forehead
			var band = Color(0.65, 0.45, 0.20)
			var band_dark = Color(0.45, 0.30, 0.12)
			var band_y = face_cy - 12
			for dx in range(-12, 13):
				_sp(img, cx + dx, band_y, band)
				_sp(img, cx + dx, band_y + 1, band_dark)

		"shopkeeper":
			# Merchant apron straps over shoulders + coin emblem
			var apron = Color(0.75, 0.65, 0.50)
			var apron_dark = Color(0.55, 0.45, 0.30)
			var face_ry = 8  # Approximate face half-height
			# Apron straps from shoulders downward
			for y_off in range(0, 12):
				for dx in [-7, 7]:
					_sp(img, cx + dx, face_cy + face_ry + y_off, apron)
					_sp(img, cx + dx + (1 if dx > 0 else -1), face_cy + face_ry + y_off, apron_dark)
			# Apron body across chest
			for y_off in range(6, 12):
				for dx in range(-7, 8):
					_sp(img, cx + dx, face_cy + face_ry + y_off, apron)
			# Gold coin emblem at chest center
			var coin_y = face_cy + face_ry + 8
			var coin_color = Color(0.85, 0.75, 0.30)
			var coin_dark = Color(0.65, 0.55, 0.20)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var dist = abs(dx) + abs(dy)
					if dist <= 2:
						_sp(img, cx + dx, coin_y + dy, coin_color if dist <= 1 else coin_dark)


func _get_job_color(job: String) -> Color:
	match job:
		"fighter": return Color(0.7, 0.3, 0.3)
		"white_mage": return Color(0.9, 0.9, 0.95)
		"black_mage": return Color(0.3, 0.3, 0.6)
		"thief": return Color(0.3, 0.6, 0.3)
		"red_mage": return Color(0.7, 0.3, 0.5)
		"monk": return Color(0.6, 0.4, 0.2)
		"shopkeeper": return Color(0.6, 0.5, 0.3)
		_: return Color(0.4, 0.4, 0.5)


## Static helper to create a portrait quickly
static func create(custom, job: String = "fighter", size: PortraitSize = PortraitSize.MEDIUM) -> Control:
	var script = load("res://src/ui/CharacterPortrait.gd")
	var portrait = script.new(custom, job, size)
	return portrait
