extends Node
class_name TileGenerator

## TileGenerator - Procedurally generates 32x32 terrain tiles for overworld exploration
## FF1/Dragon Quest style 8-bit aesthetic with limited color palettes

const TILE_SIZE: int = 32

## Tile types for Area 1 (FF1 western fantasy setting)
enum TileType {
	GRASS,
	FOREST,
	MOUNTAIN,
	WATER,
	PATH,
	BRIDGE,
	CAVE_ENTRANCE,
	VILLAGE_GATE,
	WALL,
	FLOOR
}

## SNES-quality color palettes (richer, more saturated, more shading levels)
const PALETTES: Dictionary = {
	TileType.GRASS: {
		"base": Color(0.22, 0.52, 0.18),
		"light": Color(0.35, 0.68, 0.28),
		"mid_light": Color(0.28, 0.58, 0.22),
		"dark": Color(0.14, 0.38, 0.10),
		"accent": Color(0.30, 0.55, 0.20),
		"highlight": Color(0.45, 0.75, 0.35)
	},
	TileType.FOREST: {
		"base": Color(0.12, 0.38, 0.10),
		"light": Color(0.20, 0.50, 0.16),
		"dark": Color(0.06, 0.22, 0.04),
		"deep": Color(0.03, 0.15, 0.02),
		"trunk": Color(0.38, 0.24, 0.12),
		"trunk_dark": Color(0.25, 0.15, 0.08),
		"trunk_light": Color(0.48, 0.32, 0.18)
	},
	TileType.MOUNTAIN: {
		"base": Color(0.48, 0.42, 0.36),
		"light": Color(0.62, 0.58, 0.52),
		"mid": Color(0.55, 0.50, 0.44),
		"dark": Color(0.32, 0.28, 0.24),
		"deep": Color(0.22, 0.20, 0.18),
		"snow": Color(0.92, 0.94, 0.98),
		"snow_shadow": Color(0.75, 0.78, 0.88)
	},
	TileType.WATER: {
		"base": Color(0.18, 0.42, 0.72),
		"light": Color(0.32, 0.58, 0.85),
		"mid_light": Color(0.25, 0.50, 0.78),
		"dark": Color(0.10, 0.28, 0.55),
		"deep": Color(0.06, 0.18, 0.42),
		"foam": Color(0.78, 0.88, 0.98),
		"foam_light": Color(0.88, 0.94, 1.0)
	},
	TileType.PATH: {
		"base": Color(0.58, 0.48, 0.32),
		"light": Color(0.68, 0.58, 0.40),
		"dark": Color(0.42, 0.34, 0.22),
		"stone": Color(0.52, 0.50, 0.46),
		"stone_light": Color(0.62, 0.60, 0.56),
		"stone_dark": Color(0.40, 0.38, 0.35)
	},
	TileType.BRIDGE: {
		"base": Color(0.48, 0.32, 0.18),
		"light": Color(0.58, 0.40, 0.24),
		"dark": Color(0.34, 0.22, 0.12),
		"grain": Color(0.42, 0.28, 0.15),
		"nail": Color(0.38, 0.38, 0.44),
		"nail_light": Color(0.55, 0.55, 0.62)
	},
	TileType.CAVE_ENTRANCE: {
		"base": Color(0.10, 0.08, 0.06),
		"rock": Color(0.42, 0.36, 0.30),
		"dark": Color(0.04, 0.03, 0.02),
		"highlight": Color(0.58, 0.52, 0.46),
		"moss": Color(0.25, 0.35, 0.20),
		"crystal": Color(0.45, 0.35, 0.65)
	},
	TileType.VILLAGE_GATE: {
		"base": Color(0.52, 0.38, 0.22),
		"light": Color(0.62, 0.45, 0.28),
		"dark": Color(0.38, 0.26, 0.14),
		"metal": Color(0.48, 0.48, 0.54),
		"metal_light": Color(0.62, 0.62, 0.68),
		"metal_dark": Color(0.35, 0.35, 0.40)
	},
	TileType.WALL: {
		"base": Color(0.52, 0.48, 0.42),
		"light": Color(0.65, 0.60, 0.54),
		"dark": Color(0.38, 0.34, 0.28),
		"mortar": Color(0.45, 0.42, 0.38),
		"moss": Color(0.28, 0.42, 0.22),
		"crack": Color(0.30, 0.28, 0.24)
	},
	TileType.FLOOR: {
		"base": Color(0.58, 0.52, 0.44),
		"light": Color(0.68, 0.62, 0.52),
		"dark": Color(0.44, 0.40, 0.34),
		"accent": Color(0.50, 0.46, 0.40),
		"grout": Color(0.38, 0.35, 0.30)
	}
}

## Cached tiles to avoid regenerating
var _tile_cache: Dictionary = {}


## Generate a tile texture for the given type
func generate_tile(type: TileType, variant: int = 0) -> ImageTexture:
	var cache_key = "%d_%d" % [type, variant]
	if _tile_cache.has(cache_key):
		return _tile_cache[cache_key]

	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var palette = PALETTES.get(type, PALETTES[TileType.GRASS])

	match type:
		TileType.GRASS:
			_draw_grass(img, palette, variant)
		TileType.FOREST:
			_draw_forest(img, palette, variant)
		TileType.MOUNTAIN:
			_draw_mountain(img, palette, variant)
		TileType.WATER:
			_draw_water(img, palette, variant)
		TileType.PATH:
			_draw_path(img, palette, variant)
		TileType.BRIDGE:
			_draw_bridge(img, palette, variant)
		TileType.CAVE_ENTRANCE:
			_draw_cave_entrance(img, palette)
		TileType.VILLAGE_GATE:
			_draw_village_gate(img, palette)
		TileType.WALL:
			_draw_wall(img, palette, variant)
		TileType.FLOOR:
			_draw_floor(img, palette, variant)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## Grass tile - SNES-quality with multi-tone shading and natural variation
func _draw_grass(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with base color
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12345

	var mid_light = palette.get("mid_light", palette["base"].lerp(palette["light"], 0.5))
	var highlight = palette.get("highlight", palette["light"].lightened(0.15))

	# Multi-frequency noise for natural SNES grass texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Combine multiple noise frequencies for organic look
			var n1 = sin(x * 0.5 + variant * 1.7) * cos(y * 0.4 + variant * 0.3)
			var n2 = sin(x * 1.2 + y * 0.8 + variant * 2.1) * 0.5
			var n3 = sin((x + y) * 0.3 + variant * 0.7) * 0.3
			var combined = (n1 + n2 + n3) / 3.0 + rng.randf() * 0.3

			if combined < -0.25:
				img.set_pixel(x, y, palette["dark"])
			elif combined < -0.10:
				img.set_pixel(x, y, palette["accent"])
			elif combined > 0.30:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.18:
				img.set_pixel(x, y, mid_light)

	# Grass tufts with varied heights (SNES-style detail)
	for i in range(7):
		var tuft_x = rng.randi_range(3, TILE_SIZE - 4)
		var tuft_y = rng.randi_range(6, TILE_SIZE - 3)

		# Draw 3-5 blade tuft
		var blade_count = rng.randi_range(3, 5)
		for blade in range(blade_count):
			var bx = tuft_x + blade - blade_count / 2
			var blade_height = rng.randi_range(2, 5)
			for h in range(blade_height):
				if bx >= 0 and bx < TILE_SIZE and tuft_y - h >= 0:
					var shade = highlight if h == blade_height - 1 else (palette["light"] if h > blade_height / 2 else palette["dark"])
					img.set_pixel(bx, tuft_y - h, shade)

	# Scattered soil/dirt spots for ground texture
	for i in range(3):
		var sx = rng.randi_range(2, TILE_SIZE - 3)
		var sy = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(sx, sy, Color(0.42, 0.35, 0.25))

	# Flowers (richer variety)
	if variant % 3 == 0:
		var flower_palettes = [
			[Color(0.95, 0.90, 0.30), Color(1.0, 1.0, 0.55)],  # Yellow
			[Color(0.92, 0.55, 0.65), Color(1.0, 0.75, 0.80)],  # Pink
			[Color(0.65, 0.65, 0.92), Color(0.82, 0.82, 1.0)],  # Lavender
			[Color(0.92, 0.48, 0.38), Color(1.0, 0.65, 0.55)],  # Coral
		]
		var flower_count = rng.randi_range(1, 3)
		for f in range(flower_count):
			var fx = rng.randi_range(4, TILE_SIZE - 5)
			var fy = rng.randi_range(4, TILE_SIZE - 5)
			var fp = flower_palettes[rng.randi() % flower_palettes.size()]
			# 5-petal flower pattern
			img.set_pixel(fx, fy, fp[1])  # Center (lighter)
			if fx > 0: img.set_pixel(fx - 1, fy, fp[0])
			if fx < TILE_SIZE - 1: img.set_pixel(fx + 1, fy, fp[0])
			if fy > 0: img.set_pixel(fx, fy - 1, fp[0])
			if fy < TILE_SIZE - 1: img.set_pixel(fx, fy + 1, fp[0])
			# Stem
			if fy + 1 < TILE_SIZE: img.set_pixel(fx, fy + 1, palette["dark"])
			if fy + 2 < TILE_SIZE: img.set_pixel(fx, fy + 2, palette["dark"])


## Forest tile - SNES-quality tree with detailed foliage and trunk shading
func _draw_forest(img: Image, palette: Dictionary, variant: int) -> void:
	# Grass base with undergrowth variation
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 54321

	var trunk_dark = palette.get("trunk_dark", palette["trunk"].darkened(0.3))
	var trunk_light = palette.get("trunk_light", palette["trunk"].lightened(0.2))
	var deep_shadow = palette.get("deep", palette["dark"].darkened(0.3))

	# Ground undergrowth texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var noise = sin(x * 0.6 + variant) * cos(y * 0.5) * 0.5 + rng.randf() * 0.3
			if noise < 0.15:
				img.set_pixel(x, y, palette["dark"])
			elif noise > 0.6:
				img.set_pixel(x, y, palette["light"])

	# Tree trunk with bark texture (wider, more detailed)
	var trunk_x = 14 + rng.randi_range(-2, 2)
	var trunk_bottom = 30
	var trunk_top = 14
	var trunk_width = 3
	for y in range(trunk_top, trunk_bottom):
		for dx in range(-trunk_width, trunk_width + 1):
			var x = trunk_x + dx
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				var c = palette["trunk"]
				# Bark shading: left highlight, right shadow
				if dx < -1:
					c = trunk_light
				elif dx > 1:
					c = trunk_dark
				# Bark texture pattern
				if (y + dx) % 4 == 0:
					c = trunk_dark
				img.set_pixel(x, y, c)
		# Trunk outline
		if trunk_x - trunk_width - 1 >= 0:
			img.set_pixel(trunk_x - trunk_width - 1, y, deep_shadow)
		if trunk_x + trunk_width + 1 < TILE_SIZE:
			img.set_pixel(trunk_x + trunk_width + 1, y, deep_shadow)

	# Foliage with multi-layer shading (SNES-style round canopy)
	var foliage_cx = trunk_x
	var foliage_cy = 10
	var foliage_r = 12
	for y in range(foliage_cy - foliage_r, foliage_cy + foliage_r):
		for x in range(foliage_cx - foliage_r, foliage_cx + foliage_r):
			var dist = sqrt(pow(x - foliage_cx, 2) + pow(y - foliage_cy, 2))
			if dist < foliage_r and x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				var shade = palette["base"]
				# Multi-zone shading for 3D canopy effect
				var norm_y = float(y - foliage_cy) / foliage_r
				var norm_x = float(x - foliage_cx) / foliage_r
				if norm_y < -0.4:
					shade = palette["light"]  # Top highlight
				elif norm_y < -0.1 and norm_x < 0:
					shade = palette["light"]  # Upper-left light
				elif norm_y > 0.4:
					shade = deep_shadow  # Bottom deep shadow
				elif norm_y > 0.1:
					shade = palette["dark"]  # Lower shadow
				elif norm_x > 0.4:
					shade = palette["dark"]  # Right shadow

				# Leaf cluster texture (subtle variation)
				var leaf_noise = sin(x * 1.5 + y * 1.2 + variant * 3.0) * 0.5
				if leaf_noise > 0.3 and shade != deep_shadow:
					shade = shade.lightened(0.08)
				elif leaf_noise < -0.3 and shade != palette["light"]:
					shade = shade.darkened(0.08)

				img.set_pixel(x, y, shade)

	# Foliage outline for definition
	for y in range(foliage_cy - foliage_r, foliage_cy + foliage_r):
		for x in range(foliage_cx - foliage_r, foliage_cx + foliage_r):
			var dist = sqrt(pow(x - foliage_cx, 2) + pow(y - foliage_cy, 2))
			if dist >= foliage_r - 1.5 and dist < foliage_r and x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				img.set_pixel(x, y, deep_shadow)

	# Highlight spots on canopy (dappled light)
	for i in range(4):
		var hx = foliage_cx + rng.randi_range(-6, 2)
		var hy = foliage_cy + rng.randi_range(-8, -2)
		if hx >= 0 and hx < TILE_SIZE and hy >= 0 and hy < TILE_SIZE:
			img.set_pixel(hx, hy, palette["light"].lightened(0.15))


## Mountain tile - SNES-quality rocky peaks with detailed shading
func _draw_mountain(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with dark base
	img.fill(palette.get("deep", palette["dark"].darkened(0.2)))

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 98765

	var mid = palette.get("mid", palette["base"].lerp(palette["light"], 0.5))
	var deep = palette.get("deep", palette["dark"].darkened(0.3))
	var snow_shadow = palette.get("snow_shadow", palette["snow"].darkened(0.15))

	# Mountain shape
	var peak_x = 16 + rng.randi_range(-4, 4)
	var peak_y = 3
	var base_left = 1
	var base_right = 31
	var base_y = 31

	for y in range(peak_y, base_y):
		var progress = float(y - peak_y) / float(base_y - peak_y)
		var left_x = int(lerp(peak_x, base_left, progress))
		var right_x = int(lerp(peak_x, base_right, progress))
		var mid_x = (left_x + right_x) / 2

		for x in range(left_x, right_x):
			if x >= 0 and x < TILE_SIZE:
				# Multi-zone shading for 3D mountain face
				var face_pos = float(x - left_x) / max(right_x - left_x, 1)
				var shade = palette["base"]

				# Left face (lit) -> center -> right face (shadow)
				if face_pos < 0.25:
					shade = deep  # Deep left shadow (cliff face)
				elif face_pos < 0.40:
					shade = palette["dark"]  # Left shadow
				elif face_pos < 0.55:
					shade = mid  # Center lit face
				elif face_pos < 0.70:
					shade = palette["light"]  # Main highlight
				elif face_pos < 0.85:
					shade = palette["base"]  # Right transition
				else:
					shade = palette["dark"]  # Far right shadow

				# Rock texture noise
				var rock_noise = sin(x * 2.1 + y * 1.5 + variant) * 0.5
				if rock_noise > 0.3:
					shade = shade.lightened(0.05)
				elif rock_noise < -0.3:
					shade = shade.darkened(0.05)

				img.set_pixel(x, y, shade)

		# Mountain edge outline
		if left_x >= 0 and left_x < TILE_SIZE and y < TILE_SIZE:
			img.set_pixel(left_x, y, deep)
		if right_x - 1 >= 0 and right_x - 1 < TILE_SIZE and y < TILE_SIZE:
			img.set_pixel(right_x - 1, y, deep)

	# Snow cap with shadow and highlight
	var snow_line = peak_y + 8
	for y in range(peak_y, snow_line):
		var progress = float(y - peak_y) / float(snow_line - peak_y)
		var width = int(progress * 7)
		for x in range(peak_x - width, peak_x + width + 1):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				var c = palette["snow"]
				# Snow shading
				if x < peak_x - width / 2:
					c = snow_shadow  # Shadow side
				elif y == snow_line - 1:
					c = snow_shadow  # Bottom edge
				elif x == peak_x and y < peak_y + 3:
					c = Color(1.0, 1.0, 1.0)  # Bright peak
				img.set_pixel(x, y, c)

	# Rocky crags/crevice details
	for i in range(3):
		var cx = rng.randi_range(peak_x - 8, peak_x + 8)
		var cy = rng.randi_range(snow_line + 2, base_y - 4)
		for dy in range(3):
			if cx >= 0 and cx < TILE_SIZE and cy + dy >= 0 and cy + dy < TILE_SIZE:
				img.set_pixel(cx, cy + dy, deep)


## Water tile - SNES-quality animated water with rich color depth
func _draw_water(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	var mid_light = palette.get("mid_light", palette["base"].lightened(0.1))
	var deep = palette.get("deep", palette["dark"].darkened(0.2))
	var foam_light = palette.get("foam_light", palette["foam"].lightened(0.15))

	# Wave animation offset (4 frames for seamless looping)
	var wave_offset = (variant % 4) * 8
	var secondary_offset = (variant % 4) * 5
	var tertiary_offset = (variant % 4) * 3

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Three overlapping wave frequencies for rich water surface
			var w1 = sin((x + wave_offset) * 0.35 + y * 0.18) * 0.45 + 0.5
			var w2 = sin((x - secondary_offset) * 0.22 + y * 0.32 + 1.5) * 0.30 + 0.5
			var w3 = sin((x + tertiary_offset) * 0.55 + y * 0.45 + 0.8) * 0.15 + 0.5
			var combined = (w1 + w2 + w3) / 3.0

			# 6-tone water palette for SNES depth
			if combined > 0.72:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.60:
				img.set_pixel(x, y, mid_light)
			elif combined > 0.45:
				img.set_pixel(x, y, palette["base"])
			elif combined > 0.32:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.20:
				img.set_pixel(x, y, deep)
			# else stays base

	# Foam/wave crests with glow (more realistic curved shapes)
	for i in range(3):
		var foam_x = rng.randi_range(4, TILE_SIZE - 10)
		var foam_y = rng.randi_range(4, TILE_SIZE - 6)
		var foam_len = rng.randi_range(5, 10)
		# Curved foam line
		for f in range(foam_len):
			var fx = foam_x + f
			var fy = foam_y + int(sin(f * 0.7 + variant * 0.5) * 2.5)
			if fx >= 0 and fx < TILE_SIZE and fy >= 0 and fy < TILE_SIZE:
				img.set_pixel(fx, fy, palette["foam"])
				# Bright center
				if f > 1 and f < foam_len - 1:
					img.set_pixel(fx, fy, foam_light)
				# Glow underneath
				if fy + 1 < TILE_SIZE:
					img.set_pixel(fx, fy + 1, palette["light"])

	# Subtle sparkle highlights (SNES water shimmer)
	for i in range(4):
		var sx = rng.randi_range(2, TILE_SIZE - 3)
		var sy = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(sx, sy, foam_light)


## Path/road tile - SNES-quality worn dirt road with ruts, stones, grass edges
func _draw_path(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	var stone_light = palette.get("stone_light", palette["stone"].lightened(0.1))
	var stone_dark = palette.get("stone_dark", palette["stone"].darkened(0.1))

	# Multi-frequency dirt texture (SNES style organic noise)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Center-weighted wear pattern: center is more trodden (lighter)
			var cx_dist = abs(x - TILE_SIZE / 2.0) / (TILE_SIZE / 2.0)
			var wear_factor = 1.0 - cx_dist * 0.5
			# Combine noise frequencies
			var n1 = sin(x * 0.8 + variant * 1.3) * cos(y * 0.6 + variant * 0.9)
			var n2 = sin(x * 1.5 + y * 1.2 + variant * 2.5) * 0.4
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.35

			if combined < -0.15:
				img.set_pixel(x, y, palette["dark"])
			elif combined < 0.0:
				img.set_pixel(x, y, palette["base"].darkened(0.08))
			elif combined > 0.30 * wear_factor:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.20:
				img.set_pixel(x, y, palette["base"].lightened(0.05))

	# Wheel rut marks with depth shading (darker center, lighter edges)
	var rut_positions = [10, 22]
	for rut_x in rut_positions:
		for y in range(TILE_SIZE):
			if rng.randf() < 0.7:
				var rx = rut_x + rng.randi_range(-1, 1)
				if rx >= 1 and rx < TILE_SIZE - 1:
					img.set_pixel(rx - 1, y, img.get_pixel(rx - 1, y).lightened(0.05))  # Edge highlight
					img.set_pixel(rx, y, palette["dark"])  # Rut center
					img.set_pixel(rx + 1, y, img.get_pixel(rx + 1, y).darkened(0.05))   # Shadow side

	# Varied stones with highlight/shadow and outline
	var stone_count = rng.randi_range(3, 6)
	for i in range(stone_count):
		var sx = rng.randi_range(3, TILE_SIZE - 5)
		var sy = rng.randi_range(3, TILE_SIZE - 5)
		var stone_w = rng.randi_range(2, 4)
		var stone_h = rng.randi_range(1, 3)
		var stone_base = palette["stone"].lightened(rng.randf_range(-0.08, 0.08))

		for dy in range(-1, stone_h + 1):
			for dx in range(-1, stone_w + 1):
				var px = sx + dx
				var py = sy + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					if dx == -1 or dy == -1 or dx == stone_w or dy == stone_h:
						# Outline / shadow
						if dy == stone_h or dx == stone_w:
							img.set_pixel(px, py, stone_dark)  # Bottom/right shadow
						elif dy == -1 or dx == -1:
							img.set_pixel(px, py, stone_light)  # Top/left highlight
					else:
						var c = stone_base
						if dx == 0 and dy == 0:
							c = stone_light  # Top-left highlight
						elif dx == stone_w - 1 and dy == stone_h - 1:
							c = stone_dark  # Bottom-right shadow
						img.set_pixel(px, py, c)

	# Grass encroachment from edges with varied blade heights
	var grass_base = Color(0.22, 0.48, 0.18)
	var grass_light = Color(0.32, 0.58, 0.26)
	var grass_dark = Color(0.15, 0.35, 0.12)
	for y in range(TILE_SIZE):
		# Left edge grass
		var left_reach = rng.randi_range(0, 3)
		for gx in range(left_reach):
			var c = grass_base if gx > 0 else grass_dark
			img.set_pixel(gx, y, c)
		# Grass blade tips
		if rng.randf() < 0.5 and left_reach > 0:
			var blade_x = left_reach
			if blade_x < TILE_SIZE:
				img.set_pixel(blade_x, y, grass_light)
		# Right edge grass
		var right_reach = rng.randi_range(0, 3)
		for gx in range(right_reach):
			var px = TILE_SIZE - 1 - gx
			var c = grass_base if gx > 0 else grass_dark
			img.set_pixel(px, y, c)
		if rng.randf() < 0.5 and right_reach > 0:
			var blade_x = TILE_SIZE - 1 - right_reach
			if blade_x >= 0:
				img.set_pixel(blade_x, y, grass_light)

	# Scattered pebbles in center path area
	for i in range(4):
		var px = rng.randi_range(8, 24)
		var py = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(px, py, palette["dark"])
		if px + 1 < TILE_SIZE:
			img.set_pixel(px + 1, py, stone_dark)


## Bridge tile - SNES-quality wooden planks with grain texture and nail details
func _draw_bridge(img: Image, palette: Dictionary, variant: int) -> void:
	# Water underneath (visible in gaps between planks)
	var water_pal = PALETTES[TileType.WATER]
	img.fill(water_pal["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 77777

	var grain_color = palette.get("grain", palette["base"].darkened(0.08))
	var nail_light = palette.get("nail_light", palette["nail"].lightened(0.2))

	# Water shimmer underneath (visible in gaps)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var w = sin(x * 0.4 + y * 0.3 + variant) * 0.5 + 0.5
			if w > 0.6:
				img.set_pixel(x, y, water_pal["light"])
			elif w < 0.3:
				img.set_pixel(x, y, water_pal["dark"])

	# Draw wooden planks with grain texture
	for plank in range(4):
		var py = 4 + plank * 7
		for y in range(py, mini(py + 6, TILE_SIZE)):
			var row_in_plank = y - py
			for x in range(TILE_SIZE):
				var shade = palette["base"]
				# Vertical position-based shading (rounded plank profile)
				if row_in_plank == 0:
					shade = palette["light"]  # Top highlight
				elif row_in_plank == 1:
					shade = palette["base"].lightened(0.05)
				elif row_in_plank == 4:
					shade = palette["base"].darkened(0.05)
				elif row_in_plank == 5:
					shade = palette["dark"]  # Bottom shadow
				# Wood grain texture (horizontal streaks)
				var grain_noise = sin(x * 0.2 + plank * 3.7 + row_in_plank * 0.8) * 0.5
				if grain_noise > 0.3 and row_in_plank > 0 and row_in_plank < 5:
					shade = grain_color
				elif grain_noise < -0.35 and row_in_plank > 0 and row_in_plank < 5:
					shade = shade.lightened(0.06)
				# Weathering/knot holes (rare)
				if rng.randf() < 0.008:
					shade = palette["dark"]
				img.set_pixel(x, y, shade)

		# Plank gap (darker line with shadow below)
		for x in range(TILE_SIZE):
			if py + 6 < TILE_SIZE:
				img.set_pixel(x, py + 6, palette["dark"].darkened(0.2))
			if py + 5 < TILE_SIZE:
				# Bottom edge of plank is darker
				var current = img.get_pixel(x, py + 5)
				img.set_pixel(x, py + 5, current.darkened(0.08))

	# Bridge rail/support beams on edges (2-pixel wide, darker wood)
	for y in range(TILE_SIZE):
		# Left rail
		img.set_pixel(0, y, palette["dark"])
		img.set_pixel(1, y, palette["dark"].lightened(0.05))
		# Right rail
		img.set_pixel(TILE_SIZE - 2, y, palette["dark"].lightened(0.05))
		img.set_pixel(TILE_SIZE - 1, y, palette["dark"])

	# Nails with 3D look (highlight + shadow)
	for plank in range(4):
		var nail_y = 4 + plank * 7 + 2
		for nail_x in [4, 15, 27]:
			if nail_y >= 0 and nail_y < TILE_SIZE:
				# Nail head: bright center, dark surround
				img.set_pixel(nail_x, nail_y, nail_light)  # Highlight
				if nail_x + 1 < TILE_SIZE:
					img.set_pixel(nail_x + 1, nail_y, palette["nail"])
				if nail_y + 1 < TILE_SIZE:
					img.set_pixel(nail_x, nail_y + 1, palette["nail"].darkened(0.1))  # Shadow


## Cave entrance tile - dark opening in rock with stalactites and crystals
func _draw_cave_entrance(img: Image, palette: Dictionary) -> void:
	# Rock surround
	var mtn_pal = PALETTES[TileType.MOUNTAIN]
	img.fill(mtn_pal["base"])

	# Draw detailed rock texture with cracks
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var noise = rng.randf()
			if noise < 0.15:
				img.set_pixel(x, y, mtn_pal["dark"])
			elif noise < 0.25:
				img.set_pixel(x, y, mtn_pal["light"])

	# Add horizontal crack lines in rock
	for crack_y in [5, 8, 26, 29]:
		var crack_start = rng.randi_range(0, 8)
		var crack_end = rng.randi_range(24, 32)
		for x in range(crack_start, crack_end):
			if x >= 0 and x < TILE_SIZE:
				img.set_pixel(x, crack_y, mtn_pal["dark"])

	# Draw cave opening (arch shape)
	var cave_cx = 16
	var cave_bottom = 30
	var cave_width = 10
	var cave_height = 18

	for y in range(cave_bottom - cave_height, cave_bottom):
		var progress = float(cave_bottom - y) / float(cave_height)
		var width = int(cave_width * (1.0 - progress * 0.5))
		for x in range(cave_cx - width, cave_cx + width):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				# Deeper gradient for more dramatic cave depth
				var depth = float(cave_bottom - y) / float(cave_height)
				var dark_amt = 0.6 + depth * 0.3
				var c = Color(palette["base"].r * dark_amt, palette["base"].g * dark_amt, palette["base"].b * dark_amt)
				img.set_pixel(x, y, c)

	# Stalactites hanging from cave ceiling
	var stalactite_positions = [11, 14, 17, 20]
	for sx in stalactite_positions:
		var stala_len = rng.randi_range(3, 6)
		var stala_y = cave_bottom - cave_height
		for i in range(stala_len):
			var width_offset = 1 if i < 2 else 0
			for dx in range(-width_offset, width_offset + 1):
				var px = sx + dx
				var py = stala_y + i
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					var shade = palette["rock"] if i == 0 else palette["dark"]
					img.set_pixel(px, py, shade)

	# Small glowing crystals inside cave (subtle purple/blue)
	var crystal_color = Color(0.4, 0.3, 0.6)
	var crystal_glow = Color(0.6, 0.5, 0.8)
	var crystal_positions = [[13, 20], [19, 22], [15, 25]]
	for pos in crystal_positions:
		var cx = pos[0]
		var cy = pos[1]
		if cx >= 0 and cx < TILE_SIZE and cy >= 0 and cy < TILE_SIZE:
			img.set_pixel(cx, cy, crystal_glow)
			img.set_pixel(cx, cy + 1, crystal_color)
			img.set_pixel(cx, cy + 2, crystal_color)

	# Highlight around entrance (lighter on left, darker on right for 3D effect)
	for y in range(cave_bottom - cave_height - 1, cave_bottom):
		var progress = float(cave_bottom - y) / float(cave_height)
		var width = int(cave_width * (1.0 - progress * 0.5)) + 1
		var left_x = cave_cx - width
		var right_x = cave_cx + width - 1
		if left_x >= 0 and y >= 0 and y < TILE_SIZE:
			img.set_pixel(left_x, y, palette["highlight"])
			if left_x + 1 < TILE_SIZE:
				img.set_pixel(left_x + 1, y, mtn_pal["light"])
		if right_x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
			img.set_pixel(right_x, y, mtn_pal["dark"])
			if right_x - 1 >= 0:
				img.set_pixel(right_x - 1, y, palette["dark"])

	# Moss/lichen near entrance (greenish)
	var moss_color = Color(0.25, 0.35, 0.20)
	for moss_y in [cave_bottom - cave_height - 2, cave_bottom - cave_height - 1]:
		for mx in range(cave_cx - 8, cave_cx + 8):
			if rng.randf() < 0.3 and mx >= 0 and mx < TILE_SIZE and moss_y >= 0:
				img.set_pixel(mx, moss_y, moss_color)


## Village gate tile - ornate wooden arch entrance with lanterns
func _draw_village_gate(img: Image, palette: Dictionary) -> void:
	# Cobblestone path base instead of plain dirt
	var path_pal = PALETTES[TileType.PATH]
	img.fill(path_pal["base"])

	# Draw cobblestone pattern
	var rng = RandomNumberGenerator.new()
	rng.seed = 88888
	for stone_y in range(0, TILE_SIZE, 6):
		var offset = (stone_y / 6 % 2) * 4
		for stone_x in range(-2 + offset, TILE_SIZE, 8):
			# Draw individual cobblestone
			for dy in range(5):
				for dx in range(7):
					var px = stone_x + dx
					var py = stone_y + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						var shade = path_pal["stone"]
						if dy == 0 or dx == 0:
							shade = path_pal["dark"]
						elif dy == 4 or dx == 6:
							shade = path_pal["light"]
						img.set_pixel(px, py, shade)

	# Draw ornate gate posts (left and right) - thicker with details
	for post_x in [2, 24]:
		# Main post body
		for y in range(0, 28):
			for x in range(post_x, post_x + 6):
				var shade = palette["base"]
				if x == post_x:
					shade = palette["dark"]
				elif x == post_x + 5:
					shade = palette["light"]
				img.set_pixel(x, y, shade)

		# Post cap (wider at top)
		for y in range(0, 3):
			for x in range(post_x - 1, post_x + 7):
				if x >= 0 and x < TILE_SIZE:
					var shade = palette["base"]
					if y == 0:
						shade = palette["light"]
					elif y == 2:
						shade = palette["dark"]
					img.set_pixel(x, y, shade)

		# Decorative carved lines on posts
		for carved_y in [6, 12, 18, 24]:
			for x in range(post_x + 1, post_x + 5):
				img.set_pixel(x, carved_y, palette["dark"])

	# Draw arch across top with decorative trim
	for y in range(3, 10):
		for x in range(8, 24):
			var shade = palette["base"]
			if y == 3:
				shade = palette["light"]
			elif y == 9:
				shade = palette["dark"]
			# Add decorative pattern in middle of arch
			if y == 6 and (x % 4 == 0):
				shade = palette["light"]
			img.set_pixel(x, y, shade)

	# Arch keystone (center decorative piece)
	for y in range(3, 8):
		for x in range(14, 18):
			var shade = palette["light"] if y < 5 else palette["base"]
			img.set_pixel(x, y, shade)

	# Village sign hanging from arch
	var sign_color = Color(0.4, 0.35, 0.25)
	var sign_text_color = Color(0.8, 0.75, 0.6)
	for y in range(10, 16):
		for x in range(11, 21):
			img.set_pixel(x, y, sign_color)
	# Sign border
	for x in range(11, 21):
		img.set_pixel(x, 10, palette["dark"])
		img.set_pixel(x, 15, palette["dark"])
	for y in range(10, 16):
		img.set_pixel(11, y, palette["dark"])
		img.set_pixel(20, y, palette["dark"])
	# Simple text representation on sign (just lines)
	for x in range(13, 19):
		img.set_pixel(x, 12, sign_text_color)
		if x % 2 == 0:
			img.set_pixel(x, 13, sign_text_color)

	# Hanging chains for sign
	img.set_pixel(12, 9, palette["metal"])
	img.set_pixel(19, 9, palette["metal"])

	# Lanterns on posts (warm glow)
	var lantern_color = Color(0.9, 0.7, 0.3)
	var lantern_glow = Color(1.0, 0.9, 0.5)
	var lantern_frame = palette["metal"]
	for lantern_x in [0, 30]:
		if lantern_x >= 0 and lantern_x < TILE_SIZE - 1:
			# Lantern body
			for y in range(8, 14):
				img.set_pixel(lantern_x, y, lantern_frame)
				img.set_pixel(lantern_x + 1, y, lantern_color)
			# Lantern glow center
			img.set_pixel(lantern_x + 1, 10, lantern_glow)
			img.set_pixel(lantern_x + 1, 11, lantern_glow)

	# Metal bands on posts (decorative)
	for post_x in [2, 24]:
		for band_y in [8, 20]:
			for x in range(post_x, post_x + 6):
				img.set_pixel(x, band_y, palette["metal"])

	# Flowers/plants at base of posts (greenery)
	var plant_color = Color(0.3, 0.5, 0.25)
	var flower_color = Color(0.8, 0.4, 0.5)
	for base_x in [1, 29]:
		for py in range(26, 30):
			if base_x >= 0 and base_x < TILE_SIZE:
				if rng.randf() < 0.6:
					img.set_pixel(base_x, py, plant_color)
				elif rng.randf() < 0.3:
					img.set_pixel(base_x, py, flower_color)


## Wall tile - SNES-quality stone/brick with mortar, moss, and surface detail
func _draw_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 44444

	var mortar_color = palette.get("mortar", palette["dark"].lightened(0.08))
	var moss_color = palette.get("moss", Color(0.28, 0.42, 0.22))
	var crack_color = palette.get("crack", palette["dark"].darkened(0.1))

	# Brick pattern with proper shading per-brick
	var brick_h = 8
	var brick_w = 16

	for row in range(4):
		var y_start = row * brick_h
		var offset = (row % 2) * (brick_w / 2)

		for col in range(-1, 4):
			var x_start = col * brick_w - offset
			var x_min = maxi(0, x_start)
			var x_max = mini(x_start + brick_w - 1, TILE_SIZE)
			var y_max = mini(y_start + brick_h - 1, TILE_SIZE)
			if x_min >= TILE_SIZE or x_max <= 0:
				continue

			# Per-brick color variation
			var brick_tint = rng.randf_range(-0.06, 0.06)
			var brick_base = palette["base"].lightened(brick_tint) if brick_tint > 0 else palette["base"].darkened(-brick_tint)

			# Draw brick face with multi-zone shading
			for y in range(y_start, y_max):
				for x in range(x_min, x_max):
					var rel_x = float(x - x_start) / float(brick_w - 1)
					var rel_y = float(y - y_start) / float(brick_h - 1)
					var shade = brick_base
					# Top edge highlight
					if rel_y < 0.2:
						shade = palette["light"]
					# Bottom edge shadow
					elif rel_y > 0.85:
						shade = palette["dark"]
					# Left edge highlight
					elif rel_x < 0.1:
						shade = palette["light"].darkened(0.05)
					# Right edge shadow
					elif rel_x > 0.9:
						shade = palette["dark"].lightened(0.05)
					# Surface noise texture
					var noise = sin(x * 1.8 + y * 2.2 + variant * row) * 0.5
					if noise > 0.3:
						shade = shade.lightened(0.04)
					elif noise < -0.3:
						shade = shade.darkened(0.04)
					img.set_pixel(x, y, shade)

			# Mortar lines (horizontal between rows, more visible)
			var mortar_dark = mortar_color.darkened(0.12)
			for x in range(x_min, mini(x_start + brick_w, TILE_SIZE)):
				if y_start + brick_h - 1 >= 0 and y_start + brick_h - 1 < TILE_SIZE:
					img.set_pixel(x, y_start + brick_h - 1, mortar_dark)
				if y_start + brick_h < TILE_SIZE:
					img.set_pixel(x, y_start + brick_h, mortar_color)
			# Vertical mortar at brick edge
			for y in range(y_start, mini(y_start + brick_h, TILE_SIZE)):
				var vx = x_start + brick_w - 1
				if vx >= 0 and vx < TILE_SIZE:
					img.set_pixel(vx, y, mortar_dark)

	# Cracks in random bricks (sparse, natural looking)
	var crack_count = rng.randi_range(1, 3)
	for i in range(crack_count):
		var cx = rng.randi_range(4, TILE_SIZE - 5)
		var cy = rng.randi_range(2, TILE_SIZE - 3)
		var crack_len = rng.randi_range(2, 5)
		for c in range(crack_len):
			var px = cx + c
			var py = cy + rng.randi_range(-1, 1)
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				img.set_pixel(px, py, crack_color)

	# Moss growth in mortar lines and lower bricks (subtle green patches)
	if variant % 3 != 2:  # Not all walls have moss
		for i in range(rng.randi_range(2, 5)):
			var mx = rng.randi_range(1, TILE_SIZE - 3)
			var my = rng.randi_range(TILE_SIZE / 2, TILE_SIZE - 2)  # More moss near bottom
			var moss_spread = rng.randi_range(1, 3)
			for dy in range(moss_spread):
				for dx in range(moss_spread):
					var px = mx + dx
					var py = my + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						if rng.randf() < 0.6:
							img.set_pixel(px, py, moss_color.lightened(rng.randf_range(-0.05, 0.1)))


## Floor tile - SNES-quality interior stone/tile floor with grout and wear
func _draw_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 55555

	var grout_color = palette.get("grout", palette["dark"].lightened(0.05))
	var accent = palette.get("accent", palette["base"].darkened(0.06))

	# 8x8 tile grid with per-tile shading variation
	var tile_px = 8
	for tile_row in range(TILE_SIZE / tile_px):
		for tile_col in range(TILE_SIZE / tile_px):
			# Per-tile color variation
			var tint = rng.randf_range(-0.05, 0.05)
			var tile_base = palette["base"].lightened(tint) if tint > 0 else palette["base"].darkened(-tint)

			var tx = tile_col * tile_px
			var ty = tile_row * tile_px

			for dy in range(tile_px):
				for dx in range(tile_px):
					var px = tx + dx
					var py = ty + dy
					if px >= TILE_SIZE or py >= TILE_SIZE:
						continue

					# Grout lines (slightly recessed look)
					if dx == 0 or dy == 0:
						img.set_pixel(px, py, grout_color)
						continue
					if dx == 1 or dy == 1:
						# Light edge next to grout (beveled edge effect)
						img.set_pixel(px, py, palette["light"])
						continue
					if dx == tile_px - 1 or dy == tile_px - 1:
						# Shadow edge before grout
						img.set_pixel(px, py, palette["dark"])
						continue

					# Tile face with subtle noise texture
					var shade = tile_base
					var noise = sin(px * 1.5 + py * 1.8 + variant * 2.0 + tile_row * 3.0) * 0.5
					if noise > 0.3:
						shade = shade.lightened(0.04)
					elif noise < -0.3:
						shade = shade.darkened(0.04)
					# Occasional accent color variation
					if rng.randf() < 0.04:
						shade = accent
					img.set_pixel(px, py, shade)

	# Wear marks / scuff patterns (subtle darker spots in high-traffic areas)
	for i in range(rng.randi_range(1, 3)):
		var wx = rng.randi_range(4, TILE_SIZE - 5)
		var wy = rng.randi_range(4, TILE_SIZE - 5)
		var wear_size = rng.randi_range(2, 4)
		for dy in range(wear_size):
			for dx in range(wear_size):
				var px = wx + dx
				var py = wy + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					if rng.randf() < 0.5:
						var c = img.get_pixel(px, py)
						img.set_pixel(px, py, c.darkened(0.06))

	# Tiny dust/debris specks
	for i in range(3):
		var dx = rng.randi_range(2, TILE_SIZE - 3)
		var dy = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(dx, dy, palette["light"].darkened(0.1))


## Create a TileSet with all tile types for use in TileMap
func create_tileset() -> TileSet:
	print("Creating tileset...")
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer for collision
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)  # Layer 1
	tileset.set_physics_layer_collision_mask(0, 1)

	# Create atlas source from generated tiles
	var atlas = TileSetAtlasSource.new()

	# We'll create a 4x4 atlas image (16 tiles)
	var atlas_size = 4
	var atlas_img = Image.create(TILE_SIZE * atlas_size, TILE_SIZE * atlas_size, false, Image.FORMAT_RGBA8)

	# Generate and place tiles in atlas
	var tile_order = [
		TileType.GRASS, TileType.FOREST, TileType.MOUNTAIN, TileType.WATER,
		TileType.PATH, TileType.BRIDGE, TileType.CAVE_ENTRANCE, TileType.VILLAGE_GATE,
		TileType.WALL, TileType.FLOOR, TileType.GRASS, TileType.GRASS,  # Variants
		TileType.WATER, TileType.WATER, TileType.WATER, TileType.WATER   # Animation frames
	]

	# Impassable tile types (need collision)
	var impassable_types = [TileType.FOREST, TileType.MOUNTAIN, TileType.WATER, TileType.WALL]

	for i in range(tile_order.size()):
		var tile_type = tile_order[i]
		var variant = 0
		if i >= 10:
			variant = i - 9  # Water animation variants
		elif i == 10 or i == 11:
			variant = i - 9  # Grass variants

		var tile_tex = generate_tile(tile_type, variant)
		var tile_img = tile_tex.get_image()

		var atlas_x = (i % atlas_size) * TILE_SIZE
		var atlas_y = (i / atlas_size) * TILE_SIZE

		# Copy tile to atlas
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				atlas_img.set_pixel(atlas_x + x, atlas_y + y, tile_img.get_pixel(x, y))

	var atlas_texture = ImageTexture.create_from_image(atlas_img)
	atlas.texture = atlas_texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Debug: Save atlas to disk for inspection
	atlas_img.save_png("user://debug_atlas.png")
	print("Atlas saved to user://debug_atlas.png (size: %dx%d)" % [atlas_img.get_width(), atlas_img.get_height()])

	# First, create all tiles in atlas without collision
	for i in range(tile_order.size()):
		var coords = Vector2i(i % atlas_size, i / atlas_size)
		atlas.create_tile(coords)

	# Add the atlas source to the tileset BEFORE setting collision data
	# This ensures the tile data has access to the tileset's physics layers
	tileset.add_source(atlas)

	# Now add collision for impassable tiles (after source is added to tileset)
	for i in range(tile_order.size()):
		var tile_type = tile_order[i]
		if tile_type in impassable_types:
			var coords = Vector2i(i % atlas_size, i / atlas_size)
			var tile_data = atlas.get_tile_data(coords, 0)
			if tile_data:
				# Create full-tile collision polygon (centered around tile origin)
				var half = TILE_SIZE / 2.0
				var polygon = PackedVector2Array([
					Vector2(-half, -half),
					Vector2(half, -half),
					Vector2(half, half),
					Vector2(-half, half)
				])
				tile_data.add_collision_polygon(0)
				tile_data.set_collision_polygon_points(0, 0, polygon)

	return tileset


## Helper to get tile ID for a given type (for painting in TileMap)
static func get_tile_id(type: TileType) -> int:
	# Mapping based on tile_order in create_tileset
	match type:
		TileType.GRASS: return 0
		TileType.FOREST: return 1
		TileType.MOUNTAIN: return 2
		TileType.WATER: return 3
		TileType.PATH: return 4
		TileType.BRIDGE: return 5
		TileType.CAVE_ENTRANCE: return 6
		TileType.VILLAGE_GATE: return 7
		TileType.WALL: return 8
		TileType.FLOOR: return 9
	return 0
