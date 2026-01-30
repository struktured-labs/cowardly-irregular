class_name SpriteUtils

## SpriteUtils - Shared static helper functions for procedural sprite generation
## Extracted from BattleAnimator.gd to reduce file size and improve modularity

## Sprite size configuration (SNES-style, larger for more detail)
const SPRITE_SIZE: int = 96  # Increased from 64 for more detail
const BASE_SIZE: int = 64    # Original design size for scaling calculations
const SPRITE_SCALE: float = float(SPRITE_SIZE) / float(BASE_SIZE)  # 1.5x scale

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
