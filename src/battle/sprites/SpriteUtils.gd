class_name SpriteUtils

## SpriteUtils - Shared static helper functions for procedural sprite generation
## Extracted from BattleAnimator.gd to reduce file size and improve modularity

## Sprite size configuration (legacy 96x96 for monster sprites)
const SPRITE_SIZE: int = 96  # Increased from 64 for more detail
const BASE_SIZE: int = 64    # Original design size for scaling calculations
const SPRITE_SCALE: float = float(SPRITE_SIZE) / float(BASE_SIZE)  # 1.5x scale

## SNES-authentic party sprite dimensions (32x48, displayed at 3x)
const SNES_WIDTH: int = 32
const SNES_HEIGHT: int = 48
const SNES_DISPLAY_SCALE: int = 3

## Cached equipment data for weapon visuals
static var _equipment_data: Dictionary = {}
static var _equipment_loaded: bool = false

## Sprite frame cache - avoids regenerating identical procedural sprites
## Key format: "type_param1_param2" -> SpriteFrames
static var _sprite_cache: Dictionary = {}
static var _sprite_cache_enabled: bool = true


## Get cached sprite frames or generate and cache them
static func _get_cached_sprite(cache_key: String, generator: Callable) -> SpriteFrames:
	"""Return cached SpriteFrames if available, otherwise generate, cache, and return."""
	if _sprite_cache_enabled and _sprite_cache.has(cache_key):
		# Return a duplicate to avoid shared mutation issues with AnimatedSprite2D
		return _sprite_cache[cache_key].duplicate()
	var frames = generator.call()
	if _sprite_cache_enabled:
		_sprite_cache[cache_key] = frames
	return frames.duplicate() if _sprite_cache_enabled else frames


## Clear the sprite cache (call when equipment changes or on memory pressure)
static func clear_sprite_cache() -> void:
	_sprite_cache.clear()


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


## Draw an outline around an elliptical region
static func _draw_ellipse_outline(img: Image, cx: int, cy: int, rx: int, ry: int, outline_color: Color) -> void:
	"""Draw outline around an elliptical shape"""
	for y in range(-ry - 1, ry + 2):
		for x in range(-rx - 1, rx + 2):
			var dist = sqrt(pow(float(x) / (rx + 1), 2) + pow(float(y) / (ry + 1), 2))
			if dist >= 0.85 and dist < 1.0:
				_safe_pixel(img, cx + x, cy + y, outline_color)


## Draw a shine spot (radial gradient for SNES-style highlights)
static func _draw_shine_spot(img: Image, cx: int, cy: int, radius: int, shine_color: Color, intensity: float = 0.8) -> void:
	"""Draw a circular shine/highlight spot"""
	for sy in range(-radius, radius + 1):
		for sx in range(-radius, radius + 1):
			var dist = sqrt(sx * sx + sy * sy)
			if dist < radius:
				var alpha = (1.0 - dist / float(radius)) * intensity
				var color = shine_color
				color.a = alpha
				var px = cx + sx
				var py = cy + sy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
						_safe_pixel(img, px, py, existing.blend(color))


## =================
## SNES-STYLE ENHANCEMENT FUNCTIONS
## These provide the classic FF4/5/6 era visual techniques
## =================


## Generate a proper 4-shade palette from a base color (SNES style)
## Returns: [deep_shadow, shadow, base, highlight]
static func make_4shade_palette(base: Color) -> Array[Color]:
	"""Create a 4-shade palette from base color - classic SNES technique"""
	var highlight = base.lightened(0.35)
	var shadow = base.darkened(0.25)
	var deep_shadow = base.darkened(0.45)
	# Slightly shift hue for more interesting shading (warm highlights, cool shadows)
	highlight = Color(
		min(1.0, highlight.r * 1.05),
		highlight.g,
		highlight.b * 0.95,
		highlight.a
	)
	deep_shadow = Color(
		deep_shadow.r * 0.9,
		deep_shadow.g * 0.95,
		min(1.0, deep_shadow.b * 1.1),
		deep_shadow.a
	)
	return [deep_shadow, shadow, base, highlight]


## Generate a 5-shade palette with rim light (for better depth)
## Returns: [deep_shadow, shadow, base, highlight, rim_light]
static func make_5shade_palette(base: Color) -> Array[Color]:
	"""Create a 5-shade palette with rim lighting"""
	var palette = make_4shade_palette(base)
	var rim_light = base.lightened(0.5)
	rim_light = Color(
		min(1.0, rim_light.r * 1.1),
		min(1.0, rim_light.g * 1.05),
		rim_light.b,
		rim_light.a
	)
	palette.append(rim_light)
	return palette


## SNES-style dithering pattern for color transitions
## pattern_type: 0=checkerboard, 1=diagonal, 2=horizontal lines
static func _draw_dithered_rect(img: Image, x1: int, y1: int, x2: int, y2: int, color1: Color, color2: Color, pattern_type: int = 0) -> void:
	"""Draw a rectangle with dithered transition between two colors"""
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			var use_color1 = false
			match pattern_type:
				0:  # Checkerboard
					use_color1 = ((x + y) % 2 == 0)
				1:  # Diagonal stripes
					use_color1 = ((x + y) % 3 < 2)
				2:  # Horizontal lines
					use_color1 = (y % 2 == 0)
			_safe_pixel(img, x, y, color1 if use_color1 else color2)


## Draw dithered transition between two zones (gradient dither)
static func _draw_dithered_gradient(img: Image, cx: int, y_start: int, y_end: int, width: int, color_top: Color, color_bottom: Color) -> void:
	"""Draw a vertical gradient with SNES-style dithering"""
	var height = y_end - y_start
	if height <= 0:
		return
	for y in range(y_start, y_end + 1):
		var t = float(y - y_start) / float(height)
		# Use dithering in the transition zone (middle 60%)
		for x in range(cx - width, cx + width + 1):
			var color: Color
			if t < 0.2:
				color = color_top
			elif t > 0.8:
				color = color_bottom
			else:
				# Dithering zone - use checkerboard pattern with bias
				var dither_t = (t - 0.2) / 0.6  # Normalize to 0-1
				var threshold = 0.5 + (dither_t - 0.5) * 1.5  # Bias toward bottom color as we go down
				var pattern = ((x + y) % 2 == 0)
				if dither_t < 0.5:
					color = color_top if pattern or dither_t < 0.25 else color_bottom
				else:
					color = color_bottom if pattern or dither_t > 0.75 else color_top
			_safe_pixel(img, x, y, color)


## Anti-aliased outline with semi-transparent edge pixels
static func _draw_aa_ellipse_outline(img: Image, cx: int, cy: int, rx: int, ry: int, outline_color: Color) -> void:
	"""Draw ellipse outline with anti-aliasing hints (SNES-style edge smoothing)"""
	var aa_color = outline_color
	aa_color.a = 0.5  # Semi-transparent for AA effect

	for y in range(-ry - 2, ry + 3):
		for x in range(-rx - 2, rx + 3):
			var dist = sqrt(pow(float(x) / (rx + 1), 2) + pow(float(y) / (ry + 1), 2))
			var px = cx + x
			var py = cy + y
			if px < 0 or px >= img.get_width() or py < 0 or py >= img.get_height():
				continue

			if dist >= 0.85 and dist < 0.95:
				# Core outline
				_safe_pixel(img, px, py, outline_color)
			elif dist >= 0.95 and dist < 1.0:
				# Outer AA edge
				_safe_pixel(img, px, py, aa_color)
			elif dist >= 0.75 and dist < 0.85:
				# Inner AA edge (only on corners for that SNES look)
				if abs(x) > rx * 0.5 and abs(y) > ry * 0.5:
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
						_safe_pixel(img, px, py, existing.blend(aa_color))


## Draw rim lighting on edges (classic SNES effect for depth)
static func _draw_rim_light(img: Image, cx: int, cy: int, rx: int, ry: int, rim_color: Color, light_angle: float = -0.785) -> void:
	"""Add rim lighting to an elliptical shape (light_angle in radians, -PI/4 = top-left)"""
	var light_x = cos(light_angle)
	var light_y = sin(light_angle)

	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			var dist = sqrt(pow(float(x) / rx, 2) + pow(float(y) / ry, 2))
			if dist >= 0.7 and dist < 0.95:
				# Check if this edge faces the light
				var edge_angle = atan2(float(y), float(x))
				var facing = cos(edge_angle - light_angle)
				if facing > 0.3:  # Facing toward light
					var px = cx + x
					var py = cy + y
					if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
						var existing = img.get_pixel(px, py)
						if existing.a > 0:
							var intensity = facing * (1.0 - (dist - 0.7) / 0.25) * 0.5
							var rim = rim_color
							rim.a = intensity
							_safe_pixel(img, px, py, existing.blend(rim))


## Draw specular highlight (the bright "pop" on rounded surfaces)
static func _draw_specular(img: Image, cx: int, cy: int, size: int, highlight_color: Color) -> void:
	"""Draw a specular highlight spot with soft falloff"""
	# Main bright spot
	_safe_pixel(img, cx, cy, highlight_color)

	# Softer surrounding pixels
	var soft = highlight_color
	soft.a = 0.6
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx != 0 or dy != 0:
				var px = cx + dx
				var py = cy + dy
				if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
					var existing = img.get_pixel(px, py)
					if existing.a > 0:
						_safe_pixel(img, px, py, existing.blend(soft))

	# Even softer outer ring for larger highlights
	if size > 1:
		var very_soft = highlight_color
		very_soft.a = 0.3
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if abs(dx) == 2 or abs(dy) == 2:
					var px = cx + dx
					var py = cy + dy
					if px >= 0 and px < img.get_width() and py >= 0 and py < img.get_height():
						var existing = img.get_pixel(px, py)
						if existing.a > 0:
							_safe_pixel(img, px, py, existing.blend(very_soft))


## Fill ellipse with proper SNES-style 4-zone shading
static func _draw_ellipse_4zone(img: Image, cx: int, cy: int, rx: int, ry: int, palette: Array[Color]) -> void:
	"""Draw ellipse with 4-zone shading: deep_shadow, shadow, base, highlight"""
	# Expects palette = [deep_shadow, shadow, base, highlight]
	var deep_shadow = palette[0]
	var shadow = palette[1]
	var base = palette[2]
	var highlight = palette[3]

	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			var dist = sqrt(pow(float(x) / rx, 2) + pow(float(y) / ry, 2))
			if dist < 1.0:
				var px = cx + x
				var py = cy + y
				var color = base

				# Vertical zones (top = highlight, bottom = shadow)
				var vert_pos = float(y) / ry
				# Horizontal zones (left = shadow from light angle)
				var horiz_pos = float(x) / rx

				# Top-left quadrant: highlight zone
				if vert_pos < -0.3 and horiz_pos < 0.3:
					color = highlight
				# Bottom zone: shadow
				elif vert_pos > 0.4:
					color = shadow
					# Deep shadow at bottom-right
					if horiz_pos > 0.3:
						color = deep_shadow
				# Left side in shadow
				elif horiz_pos > 0.5 and vert_pos > -0.2:
					color = shadow
				# Dithered transition zones
				elif vert_pos > 0.2 and vert_pos < 0.4:
					# Dither between base and shadow
					if (px + py) % 2 == 0:
						color = shadow
				elif vert_pos < -0.1 and vert_pos > -0.3 and horiz_pos < 0.1:
					# Dither between base and highlight
					if (px + py) % 2 == 0:
						color = highlight

				_safe_pixel(img, px, py, color)


## Draw a detailed eye with iris, pupil, and catchlight (SNES RPG style)
static func _draw_snes_eye(img: Image, cx: int, cy: int, size: int, iris_color: Color, is_left: bool = true) -> void:
	"""Draw a detailed SNES-style eye with all the classic elements"""
	var eye_white = Color(0.95, 0.95, 1.0)
	var eye_shadow = Color(0.8, 0.8, 0.9)
	var pupil = Color(0.08, 0.08, 0.12)
	var catchlight = Color(1.0, 1.0, 1.0)

	var eye_rx = size
	var eye_ry = max(1, size - 1)

	# Eye white (almond shape)
	for y in range(-eye_ry, eye_ry + 1):
		for x in range(-eye_rx, eye_rx + 1):
			var dist = sqrt(pow(float(x) / eye_rx, 2) + pow(float(y) / eye_ry, 2))
			if dist < 1.0:
				var color = eye_white
				if y < -eye_ry * 0.3:
					color = eye_shadow  # Upper eyelid shadow
				_safe_pixel(img, cx + x, cy + y, color)

	# Iris (centered, slightly smaller)
	var iris_r = max(1, size - 1)
	var iris_highlight = iris_color.lightened(0.25)
	for y in range(-iris_r, iris_r + 1):
		for x in range(-iris_r, iris_r + 1):
			if x * x + y * y <= iris_r * iris_r:
				var color = iris_color
				if y < 0:
					color = iris_highlight
				_safe_pixel(img, cx + x, cy + y, color)

	# Pupil (small dark center)
	_safe_pixel(img, cx, cy, pupil)
	if size > 2:
		_safe_pixel(img, cx, cy + 1, pupil)

	# Catchlight (bright white dot, offset to suggest light source)
	var catch_x = cx - 1 if is_left else cx + 1
	var catch_y = cy - 1
	_safe_pixel(img, catch_x, catch_y, catchlight)


## Create texture/pattern overlay (for fur, scales, fabric, etc.)
static func _apply_texture_pattern(img: Image, x1: int, y1: int, x2: int, y2: int, pattern: String, dark_offset: float = 0.08) -> void:
	"""Apply a subtle texture pattern to an area (modifies existing pixels)"""
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			if x < 0 or x >= img.get_width() or y < 0 or y >= img.get_height():
				continue
			var existing = img.get_pixel(x, y)
			if existing.a < 0.5:
				continue

			var darken = false
			match pattern:
				"fur":
					# Diagonal fur strokes
					darken = ((x + y * 3) % 5 < 1)
				"scales":
					# Overlapping scale pattern
					darken = ((x % 4 == 0 and y % 3 < 2) or (x % 4 == 2 and (y + 1) % 3 < 2))
				"fabric":
					# Woven fabric look
					darken = ((x % 3 == 0) or (y % 3 == 0))
				"stone":
					# Random rocky texture
					darken = ((x * 7 + y * 13) % 11 < 3)
				"metal":
					# Subtle metal grain
					darken = ((x + y) % 6 < 1)

			if darken:
				existing = existing.darkened(dark_offset)
				_safe_pixel(img, x, y, existing)


## =================
## SNES PARTY SPRITE HELPERS (32x48 canvas, no AA, hard color transitions)
## =================


## Generate a strict SNES 4-color palette: [outline, dark, base, highlight]
## No lerp, no blending - hard color transitions only
static func make_snes_palette(base: Color) -> Array[Color]:
	"""Create an authentic SNES 4-color palette from a base color."""
	var outline = Color(
		max(0.0, base.r * 0.25),
		max(0.0, base.g * 0.25),
		max(0.0, base.b * 0.3),
		1.0
	)
	var dark = Color(
		max(0.0, base.r * 0.55),
		max(0.0, base.g * 0.55),
		max(0.0, base.b * 0.6),
		1.0
	)
	var highlight = Color(
		min(1.0, base.r * 1.3 + 0.1),
		min(1.0, base.g * 1.3 + 0.1),
		min(1.0, base.b * 1.25 + 0.08),
		1.0
	)
	return [outline, dark, base, highlight]


## Hard pixel set with no anti-aliasing - for SNES party sprites
static func _pixel(img: Image, x: int, y: int, color: Color) -> void:
	"""Set a pixel with no AA, no blending - pure SNES style."""
	if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
		img.set_pixel(x, y, color)


## Draw 1px dark outline around a rectangular region
static func _snes_outline_rect(img: Image, x1: int, y1: int, x2: int, y2: int, outline_color: Color) -> void:
	"""Draw a 1px outline rectangle (SNES style)."""
	for x in range(x1, x2 + 1):
		_pixel(img, x, y1, outline_color)
		_pixel(img, x, y2, outline_color)
	for y in range(y1, y2 + 1):
		_pixel(img, x1, y, outline_color)
		_pixel(img, x2, y, outline_color)


## Fill a rectangle with a single color (no gradients)
static func _snes_fill_rect(img: Image, x1: int, y1: int, x2: int, y2: int, color: Color) -> void:
	"""Fill a rectangle with solid color (no AA)."""
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			_pixel(img, x, y, color)


## Get armor visual parameters for drawing
static func get_armor_visual(armor_id: String) -> Dictionary:
	"""Returns visual params for armor: category, color"""
	_load_equipment_data()
	if armor_id.is_empty() or not _equipment_data.has("armors"):
		return {"category": "medium", "color": Color(0.5, 0.5, 0.5)}
	var armors = _equipment_data["armors"]
	if not armors.has(armor_id):
		return {"category": "medium", "color": Color(0.5, 0.5, 0.5)}
	var armor = armors[armor_id]
	var visual = armor.get("visual", {})
	var category = visual.get("category", "medium")
	var color_arr = visual.get("color", [0.5, 0.5, 0.5])
	return {
		"category": category,
		"color": Color(color_arr[0], color_arr[1], color_arr[2]) if color_arr is Array else Color(0.5, 0.5, 0.5)
	}


## Get accessory visual parameters for drawing
static func get_accessory_visual(accessory_id: String) -> Dictionary:
	"""Returns visual params for accessory: type, color"""
	_load_equipment_data()
	if accessory_id.is_empty() or not _equipment_data.has("accessories"):
		return {}
	var accessories = _equipment_data["accessories"]
	if not accessories.has(accessory_id):
		return {}
	var accessory = accessories[accessory_id]
	var visual = accessory.get("visual", {})
	if visual.is_empty():
		return {}
	var vis_type = visual.get("type", "")
	var color_arr = visual.get("color", [0.7, 0.7, 0.7])
	return {
		"type": vis_type,
		"color": Color(color_arr[0], color_arr[1], color_arr[2]) if color_arr is Array else Color(0.7, 0.7, 0.7)
	}


## Load job visual data from jobs.json
static var _job_visuals: Dictionary = {}
static var _job_visuals_loaded: bool = false

static func get_job_visual(job_id: String) -> Dictionary:
	"""Get visual data for a job (sprite_type, outfit_color, headgear)."""
	if not _job_visuals_loaded:
		_load_job_visuals()
	return _job_visuals.get(job_id, {"sprite_type": "armored", "outfit_color": Color(0.4, 0.4, 0.5), "headgear": "none"})


static func _load_job_visuals() -> void:
	"""Load job visual data from jobs.json."""
	var file = FileAccess.open("res://data/jobs.json", FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
			for job_id in json.data:
				var job = json.data[job_id]
				if job.has("visual"):
					var vis = job["visual"]
					var color_arr = vis.get("outfit_color", [0.4, 0.4, 0.5])
					_job_visuals[job_id] = {
						"sprite_type": vis.get("sprite_type", "armored"),
						"outfit_color": Color(color_arr[0], color_arr[1], color_arr[2]),
						"headgear": vis.get("headgear", "none")
					}
		file.close()
	_job_visuals_loaded = true
