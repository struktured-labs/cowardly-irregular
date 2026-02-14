extends Node
class_name TileGenerator

## TileGenerator - Procedurally generates 32x32 terrain tiles for overworld exploration
## FF4/5/6 era SNES aesthetic with rich shading and detail

const TILE_SIZE: int = 32

## Tile types for Area 1 (FF4-6 western fantasy setting)
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
	FLOOR,
	CAVE_FLOOR,
	CAVE_WALL
}

## FF4/5/6 era color palettes - rich, vibrant, with full 24-bit depth
const PALETTES: Dictionary = {
	TileType.GRASS: {
		"base": Color(0.24, 0.54, 0.20),
		"light": Color(0.38, 0.72, 0.32),
		"mid_light": Color(0.30, 0.62, 0.25),
		"dark": Color(0.16, 0.40, 0.12),
		"deep": Color(0.10, 0.30, 0.08),
		"accent": Color(0.32, 0.58, 0.24),
		"highlight": Color(0.52, 0.82, 0.42),
		"yellow_tip": Color(0.62, 0.72, 0.32),
		"soil": Color(0.45, 0.35, 0.22),
		"soil_dark": Color(0.32, 0.24, 0.14)
	},
	TileType.FOREST: {
		"base": Color(0.14, 0.42, 0.12),
		"light": Color(0.24, 0.55, 0.20),
		"mid": Color(0.18, 0.48, 0.15),
		"dark": Color(0.08, 0.28, 0.06),
		"deep": Color(0.04, 0.18, 0.03),
		"canopy_highlight": Color(0.35, 0.62, 0.28),
		"trunk": Color(0.42, 0.28, 0.14),
		"trunk_dark": Color(0.28, 0.18, 0.10),
		"trunk_light": Color(0.52, 0.38, 0.22),
		"bark_detail": Color(0.35, 0.22, 0.12),
		"undergrowth": Color(0.12, 0.35, 0.10),
		"moss": Color(0.20, 0.42, 0.18)
	},
	TileType.MOUNTAIN: {
		"base": Color(0.52, 0.46, 0.40),
		"light": Color(0.68, 0.64, 0.58),
		"mid": Color(0.58, 0.54, 0.48),
		"dark": Color(0.38, 0.34, 0.30),
		"deep": Color(0.25, 0.22, 0.20),
		"cliff": Color(0.42, 0.38, 0.35),
		"snow": Color(0.94, 0.96, 1.0),
		"snow_shadow": Color(0.78, 0.82, 0.92),
		"snow_blue": Color(0.72, 0.78, 0.88),
		"rock_orange": Color(0.55, 0.42, 0.32),
		"rock_purple": Color(0.45, 0.40, 0.48)
	},
	TileType.WATER: {
		"base": Color(0.20, 0.45, 0.75),
		"light": Color(0.38, 0.62, 0.88),
		"mid_light": Color(0.28, 0.52, 0.82),
		"dark": Color(0.12, 0.32, 0.58),
		"deep": Color(0.08, 0.22, 0.45),
		"abyss": Color(0.05, 0.15, 0.35),
		"foam": Color(0.82, 0.90, 0.98),
		"foam_light": Color(0.92, 0.96, 1.0),
		"sparkle": Color(1.0, 1.0, 1.0),
		"teal_accent": Color(0.18, 0.55, 0.72)
	},
	TileType.PATH: {
		"base": Color(0.62, 0.52, 0.36),
		"light": Color(0.72, 0.62, 0.45),
		"mid": Color(0.65, 0.55, 0.40),
		"dark": Color(0.48, 0.40, 0.28),
		"deep": Color(0.38, 0.30, 0.20),
		"stone": Color(0.55, 0.52, 0.48),
		"stone_light": Color(0.65, 0.62, 0.58),
		"stone_dark": Color(0.42, 0.40, 0.38),
		"pebble": Color(0.50, 0.48, 0.44)
	},
	TileType.BRIDGE: {
		"base": Color(0.52, 0.36, 0.22),
		"light": Color(0.62, 0.45, 0.28),
		"mid": Color(0.55, 0.40, 0.25),
		"dark": Color(0.38, 0.26, 0.15),
		"grain": Color(0.45, 0.32, 0.18),
		"grain_dark": Color(0.38, 0.25, 0.14),
		"nail": Color(0.40, 0.40, 0.48),
		"nail_light": Color(0.58, 0.58, 0.65),
		"rope": Color(0.55, 0.45, 0.30)
	},
	TileType.CAVE_ENTRANCE: {
		"base": Color(0.08, 0.06, 0.05),
		"rock": Color(0.45, 0.40, 0.35),
		"rock_light": Color(0.55, 0.50, 0.45),
		"dark": Color(0.03, 0.02, 0.02),
		"void": Color(0.0, 0.0, 0.0),
		"highlight": Color(0.62, 0.56, 0.50),
		"moss": Color(0.28, 0.40, 0.24),
		"crystal": Color(0.50, 0.40, 0.70),
		"crystal_glow": Color(0.65, 0.55, 0.85)
	},
	TileType.VILLAGE_GATE: {
		"base": Color(0.55, 0.42, 0.28),
		"light": Color(0.68, 0.52, 0.35),
		"mid": Color(0.60, 0.46, 0.32),
		"dark": Color(0.42, 0.32, 0.20),
		"deep": Color(0.32, 0.24, 0.14),
		"metal": Color(0.52, 0.52, 0.58),
		"metal_light": Color(0.68, 0.68, 0.75),
		"metal_dark": Color(0.38, 0.38, 0.44),
		"gold": Color(0.85, 0.70, 0.30),
		"gold_light": Color(0.95, 0.85, 0.45)
	},
	TileType.WALL: {
		"base": Color(0.55, 0.52, 0.48),
		"light": Color(0.70, 0.66, 0.60),
		"mid": Color(0.60, 0.58, 0.54),
		"dark": Color(0.42, 0.40, 0.36),
		"deep": Color(0.32, 0.30, 0.28),
		"mortar": Color(0.48, 0.46, 0.42),
		"mortar_dark": Color(0.38, 0.36, 0.34),
		"moss": Color(0.32, 0.48, 0.28),
		"crack": Color(0.35, 0.32, 0.30),
		"stain": Color(0.48, 0.44, 0.40)
	},
	TileType.FLOOR: {
		"base": Color(0.62, 0.56, 0.48),
		"light": Color(0.72, 0.66, 0.58),
		"mid": Color(0.65, 0.60, 0.52),
		"dark": Color(0.48, 0.44, 0.38),
		"deep": Color(0.38, 0.35, 0.30),
		"accent": Color(0.55, 0.52, 0.46),
		"grout": Color(0.42, 0.40, 0.36),
		"polish": Color(0.78, 0.72, 0.65)
	},
	TileType.CAVE_FLOOR: {
		"base": Color(0.28, 0.26, 0.24),
		"light": Color(0.38, 0.36, 0.34),
		"mid": Color(0.32, 0.30, 0.28),
		"dark": Color(0.22, 0.20, 0.18),
		"deep": Color(0.15, 0.14, 0.12),
		"wet": Color(0.25, 0.28, 0.30),
		"puddle": Color(0.18, 0.25, 0.35),
		"crystal": Color(0.45, 0.38, 0.62),
		"crystal_glow": Color(0.55, 0.48, 0.75),
		"moss": Color(0.25, 0.35, 0.22)
	},
	TileType.CAVE_WALL: {
		"base": Color(0.35, 0.32, 0.28),
		"light": Color(0.48, 0.45, 0.40),
		"mid": Color(0.40, 0.38, 0.34),
		"dark": Color(0.25, 0.22, 0.20),
		"deep": Color(0.15, 0.14, 0.12),
		"vein": Color(0.42, 0.38, 0.50),
		"ore": Color(0.55, 0.45, 0.25),
		"ore_light": Color(0.70, 0.58, 0.32),
		"moss": Color(0.22, 0.32, 0.20),
		"drip": Color(0.32, 0.38, 0.42)
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
		TileType.CAVE_FLOOR:
			_draw_cave_floor(img, palette, variant)
		TileType.CAVE_WALL:
			_draw_cave_wall(img, palette, variant)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## Grass tile - FF4/5/6 quality with detailed blades, shading, and seamless tiling
func _draw_grass(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with base color
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12345

	var mid_light = palette.get("mid_light", palette["base"].lerp(palette["light"], 0.5))
	var highlight = palette.get("highlight", palette["light"].lightened(0.15))
	var deep = palette.get("deep", palette["dark"].darkened(0.2))
	var yellow_tip = palette.get("yellow_tip", Color(0.62, 0.72, 0.32))
	var soil = palette.get("soil", Color(0.45, 0.35, 0.22))
	var soil_dark = palette.get("soil_dark", Color(0.32, 0.24, 0.14))

	# Multi-layer grass texture with diagonal light direction (FF-style top-left light)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Base noise combining multiple frequencies for organic look
			var n1 = sin(x * 0.45 + variant * 1.7) * cos(y * 0.35 + variant * 0.3)
			var n2 = sin(x * 1.1 + y * 0.7 + variant * 2.1) * 0.45
			var n3 = sin((x + y) * 0.28 + variant * 0.7) * 0.28
			var n4 = sin((x - y) * 0.4 + variant * 1.2) * 0.2
			var combined = (n1 + n2 + n3 + n4) / 4.0 + rng.randf() * 0.25

			# Diagonal lighting gradient (brighter top-left)
			var light_bias = (float(TILE_SIZE - x) + float(TILE_SIZE - y)) / (TILE_SIZE * 2.0) * 0.15
			combined += light_bias

			# 6-tone shading for rich depth
			if combined < -0.30:
				img.set_pixel(x, y, deep)
			elif combined < -0.15:
				img.set_pixel(x, y, palette["dark"])
			elif combined < 0.0:
				img.set_pixel(x, y, palette["accent"])
			elif combined > 0.35:
				img.set_pixel(x, y, highlight)
			elif combined > 0.22:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.10:
				img.set_pixel(x, y, mid_light)

	# Detailed grass blade tufts with light/shadow sides
	var tuft_count = 8 + (variant % 4)
	for i in range(tuft_count):
		var tuft_x = rng.randi_range(2, TILE_SIZE - 3)
		var tuft_y = rng.randi_range(5, TILE_SIZE - 2)

		# Draw 3-6 blade tuft with varying heights and lean
		var blade_count = rng.randi_range(3, 6)
		var lean_dir = rng.randi_range(-1, 1)
		for blade in range(blade_count):
			var bx = tuft_x + blade - blade_count / 2
			var blade_height = rng.randi_range(3, 6)
			var blade_lean = lean_dir * (blade_height / 3)
			for h in range(blade_height):
				var px = bx + int(float(blade_lean) * float(h) / float(blade_height))
				var py = tuft_y - h
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					var shade: Color
					if h == blade_height - 1:
						# Tip: yellow-green highlight or bright green
						shade = yellow_tip if rng.randf() < 0.3 else highlight
					elif h >= blade_height * 2 / 3:
						shade = palette["light"]
					elif h >= blade_height / 3:
						shade = mid_light
					else:
						shade = palette["dark"]
					# Add slight variation to blade color
					if rng.randf() < 0.2:
						shade = shade.lightened(0.05) if rng.randf() < 0.5 else shade.darkened(0.05)
					img.set_pixel(px, py, shade)

	# Soil/dirt patches for ground texture (more natural distribution)
	var soil_patches = rng.randi_range(2, 5)
	for i in range(soil_patches):
		var sx = rng.randi_range(1, TILE_SIZE - 2)
		var sy = rng.randi_range(TILE_SIZE / 2, TILE_SIZE - 2)  # More dirt visible at base
		var patch_size = rng.randi_range(1, 3)
		for dy in range(patch_size):
			for dx in range(patch_size):
				var px = sx + dx
				var py = sy + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE and rng.randf() < 0.7:
					img.set_pixel(px, py, soil if rng.randf() < 0.6 else soil_dark)

	# Decorative flowers on certain variants
	if variant % 4 == 0:
		var flower_palettes = [
			[Color(0.95, 0.88, 0.25), Color(1.0, 0.98, 0.50), Color(0.88, 0.72, 0.15)],  # Yellow daisy
			[Color(0.92, 0.52, 0.62), Color(1.0, 0.72, 0.78), Color(0.78, 0.38, 0.48)],  # Pink rose
			[Color(0.62, 0.62, 0.92), Color(0.80, 0.80, 1.0), Color(0.48, 0.48, 0.78)],  # Lavender
			[Color(0.92, 0.45, 0.35), Color(1.0, 0.62, 0.52), Color(0.78, 0.32, 0.25)],  # Orange poppy
			[Color(0.98, 0.98, 0.95), Color(1.0, 1.0, 1.0), Color(0.88, 0.88, 0.82)],    # White
		]
		var flower_count = rng.randi_range(1, 3)
		for f in range(flower_count):
			var fx = rng.randi_range(3, TILE_SIZE - 4)
			var fy = rng.randi_range(3, TILE_SIZE - 6)
			var fp = flower_palettes[rng.randi() % flower_palettes.size()]
			# 5-petal flower with 3D shading
			img.set_pixel(fx, fy, fp[1])  # Center (brightest)
			if fx > 0: img.set_pixel(fx - 1, fy, fp[0])
			if fx < TILE_SIZE - 1: img.set_pixel(fx + 1, fy, fp[2])  # Shadow side
			if fy > 0: img.set_pixel(fx, fy - 1, fp[0])
			if fy < TILE_SIZE - 1 and fy + 1 < TILE_SIZE: img.set_pixel(fx, fy + 1, fp[2])  # Shadow
			# Stem with gradient
			for stem_y in range(1, 4):
				if fy + stem_y + 1 < TILE_SIZE:
					var stem_shade = palette["dark"] if stem_y < 2 else deep
					img.set_pixel(fx, fy + stem_y + 1, stem_shade)

	# Subtle dithering at edges for seamless tiling
	for edge in range(2):
		for i in range(TILE_SIZE):
			if rng.randf() < 0.3:
				# Top/bottom edge blending
				if edge == 0 and i < TILE_SIZE:
					var c = img.get_pixel(i, 0)
					img.set_pixel(i, 0, c.lerp(palette["base"], 0.3))
				else:
					var c = img.get_pixel(i, TILE_SIZE - 1)
					img.set_pixel(i, TILE_SIZE - 1, c.lerp(palette["base"], 0.3))


## Forest tile - FF4/5/6 quality tree with detailed foliage, bark texture, and undergrowth
func _draw_forest(img: Image, palette: Dictionary, variant: int) -> void:
	# Dark undergrowth base
	img.fill(palette.get("undergrowth", palette["dark"]))

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 54321

	var trunk_dark = palette.get("trunk_dark", palette["trunk"].darkened(0.3))
	var trunk_light = palette.get("trunk_light", palette["trunk"].lightened(0.2))
	var bark_detail = palette.get("bark_detail", palette["trunk"].darkened(0.15))
	var deep_shadow = palette.get("deep", palette["dark"].darkened(0.3))
	var canopy_highlight = palette.get("canopy_highlight", palette["light"].lightened(0.1))
	var mid = palette.get("mid", palette["base"].lerp(palette["light"], 0.4))
	var moss = palette.get("moss", Color(0.20, 0.42, 0.18))

	# Detailed undergrowth with multiple layers
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.55 + variant * 1.2) * cos(y * 0.45 + variant * 0.8)
			var n2 = sin(x * 1.1 + y * 0.9 + variant * 1.8) * 0.4
			var noise = (n1 + n2) / 2.0 + rng.randf() * 0.25
			if noise < 0.0:
				img.set_pixel(x, y, deep_shadow)
			elif noise < 0.25:
				img.set_pixel(x, y, palette["dark"])
			elif noise > 0.55:
				img.set_pixel(x, y, palette["base"])
			elif noise > 0.40:
				img.set_pixel(x, y, palette.get("undergrowth", palette["dark"]))

	# Tree trunk with detailed bark texture
	var trunk_x = 15 + rng.randi_range(-2, 2)
	var trunk_bottom = 31
	var trunk_top = 12
	var trunk_width = 3

	# Draw trunk with bark rings and 3D shading
	for y in range(trunk_top, trunk_bottom):
		var y_progress = float(y - trunk_top) / float(trunk_bottom - trunk_top)
		var current_width = trunk_width + int(y_progress * 1.5)  # Slight taper
		for dx in range(-current_width, current_width + 1):
			var x = trunk_x + dx
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				var c = palette["trunk"]
				var rel_x = float(dx) / float(current_width)

				# Cylindrical shading (left lit, right shadow)
				if rel_x < -0.6:
					c = trunk_light
				elif rel_x < -0.3:
					c = palette["trunk"]
				elif rel_x > 0.6:
					c = trunk_dark
				elif rel_x > 0.3:
					c = bark_detail

				# Bark texture - horizontal lines and knots
				var bark_noise = sin(y * 0.8 + dx * 0.3 + variant * 0.5)
				if bark_noise > 0.6:
					c = trunk_dark
				elif bark_noise < -0.5 and abs(rel_x) < 0.4:
					c = trunk_light.darkened(0.1)

				# Occasional knot holes
				if rng.randf() < 0.01 and abs(dx) < 2:
					c = trunk_dark.darkened(0.3)

				img.set_pixel(x, y, c)

		# Trunk edge shadows
		var left_edge = trunk_x - current_width - 1
		var right_edge = trunk_x + current_width + 1
		if left_edge >= 0:
			img.set_pixel(left_edge, y, deep_shadow)
		if right_edge < TILE_SIZE:
			img.set_pixel(right_edge, y, deep_shadow)

	# Moss on trunk base
	for y in range(trunk_bottom - 4, trunk_bottom):
		for dx in range(-trunk_width - 1, trunk_width + 2):
			var x = trunk_x + dx
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				if rng.randf() < 0.4:
					img.set_pixel(x, y, moss)

	# Multi-layered foliage canopy with FF-style shading
	var foliage_cx = trunk_x
	var foliage_cy = 8
	var foliage_r = 13

	# Draw main canopy
	for y in range(foliage_cy - foliage_r, foliage_cy + foliage_r):
		for x in range(foliage_cx - foliage_r, foliage_cx + foliage_r):
			var dist = sqrt(pow(x - foliage_cx, 2) + pow(y - foliage_cy, 2))
			# Irregular canopy edge
			var edge_noise = sin(atan2(y - foliage_cy, x - foliage_cx) * 6 + variant) * 1.5
			var effective_r = foliage_r + edge_noise

			if dist < effective_r and x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				var shade = palette["base"]
				var norm_y = float(y - foliage_cy) / foliage_r
				var norm_x = float(x - foliage_cx) / foliage_r

				# 5-zone spherical shading for 3D canopy
				var light_angle = norm_x * 0.6 + norm_y * 0.8  # Light from top-left
				if light_angle < -0.5:
					shade = canopy_highlight
				elif light_angle < -0.2:
					shade = palette["light"]
				elif light_angle < 0.1:
					shade = mid
				elif light_angle < 0.4:
					shade = palette["dark"]
				else:
					shade = deep_shadow

				# Leaf cluster texture (organic variation)
				var leaf_noise = sin(x * 1.4 + y * 1.1 + variant * 2.5) * 0.5
				leaf_noise += sin(x * 2.8 + y * 2.2 + variant * 4.0) * 0.25
				if leaf_noise > 0.4 and shade != canopy_highlight:
					shade = shade.lightened(0.1)
				elif leaf_noise < -0.35 and shade != deep_shadow:
					shade = shade.darkened(0.1)

				img.set_pixel(x, y, shade)

	# Canopy outline with irregular edge
	for y in range(foliage_cy - foliage_r - 2, foliage_cy + foliage_r + 2):
		for x in range(foliage_cx - foliage_r - 2, foliage_cx + foliage_r + 2):
			var dist = sqrt(pow(x - foliage_cx, 2) + pow(y - foliage_cy, 2))
			var edge_noise = sin(atan2(y - foliage_cy, x - foliage_cx) * 6 + variant) * 1.5
			var effective_r = foliage_r + edge_noise
			if dist >= effective_r - 1.2 and dist < effective_r + 0.5 and x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				# Only darken if we're at the edge (check current pixel is foliage)
				var current = img.get_pixel(x, y)
				if current.g > 0.3:  # Is foliage
					img.set_pixel(x, y, deep_shadow)

	# Highlight spots on canopy (dappled sunlight through leaves)
	for i in range(6):
		var hx = foliage_cx + rng.randi_range(-8, 4)
		var hy = foliage_cy + rng.randi_range(-10, -3)
		if hx >= 0 and hx < TILE_SIZE and hy >= 0 and hy < TILE_SIZE:
			img.set_pixel(hx, hy, canopy_highlight)
			# Soft glow around highlight
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0: continue
					var px = hx + dx
					var py = hy + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						var c = img.get_pixel(px, py)
						if c.g > 0.2 and rng.randf() < 0.5:
							img.set_pixel(px, py, c.lightened(0.08))


## Mountain tile - FF4/5/6 quality rocky peaks with detailed textures and snow
func _draw_mountain(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with dark base (sky/void behind mountain)
	img.fill(palette.get("deep", palette["dark"].darkened(0.2)))

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 98765

	var mid = palette.get("mid", palette["base"].lerp(palette["light"], 0.5))
	var deep = palette.get("deep", palette["dark"].darkened(0.3))
	var cliff = palette.get("cliff", palette["dark"])
	var snow_shadow = palette.get("snow_shadow", palette["snow"].darkened(0.15))
	var snow_blue = palette.get("snow_blue", Color(0.72, 0.78, 0.88))
	var rock_orange = palette.get("rock_orange", Color(0.55, 0.42, 0.32))
	var rock_purple = palette.get("rock_purple", Color(0.45, 0.40, 0.48))

	# Mountain shape with slight variation
	var peak_x = 16 + rng.randi_range(-3, 3)
	var peak_y = 2
	var base_left = 0
	var base_right = 31
	var base_y = 31

	# Draw mountain body with multiple rock faces
	for y in range(peak_y, base_y + 1):
		var progress = float(y - peak_y) / float(base_y - peak_y)
		var left_x = int(lerp(peak_x, base_left, progress))
		var right_x = int(lerp(peak_x, base_right, progress))

		for x in range(left_x, right_x + 1):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				var face_pos = float(x - left_x) / max(right_x - left_x, 1)
				var shade = palette["base"]

				# Multi-faceted rock face shading (simulating cliff faces at different angles)
				# Left cliff face (deep shadow)
				if face_pos < 0.15:
					shade = deep
				elif face_pos < 0.25:
					shade = cliff
				# Left slope (shadowed)
				elif face_pos < 0.38:
					shade = palette["dark"]
				# Center-left (base)
				elif face_pos < 0.48:
					shade = palette["base"]
				# Center lit face
				elif face_pos < 0.58:
					shade = mid
				# Main highlight band
				elif face_pos < 0.72:
					shade = palette["light"]
				# Right transition
				elif face_pos < 0.82:
					shade = palette["base"]
				# Right shadow
				elif face_pos < 0.92:
					shade = palette["dark"]
				else:
					shade = cliff

				# Rock texture: multiple noise layers for realistic stone
				var n1 = sin(x * 1.8 + y * 1.2 + variant * 1.5) * 0.4
				var n2 = sin(x * 3.5 + y * 2.8 + variant * 2.2) * 0.2
				var n3 = sin((x + y) * 0.6 + variant * 0.8) * 0.25
				var rock_noise = n1 + n2 + n3

				if rock_noise > 0.45:
					shade = shade.lightened(0.08)
				elif rock_noise > 0.25:
					shade = shade.lightened(0.03)
				elif rock_noise < -0.4:
					shade = shade.darkened(0.08)
				elif rock_noise < -0.2:
					shade = shade.darkened(0.03)

				# Color variation (subtle orange/purple tints in rock)
				if rng.randf() < 0.08:
					shade = shade.lerp(rock_orange, 0.15)
				elif rng.randf() < 0.05:
					shade = shade.lerp(rock_purple, 0.12)

				img.set_pixel(x, y, shade)

		# Sharp mountain edge outlines
		if left_x >= 0 and left_x < TILE_SIZE and y < TILE_SIZE:
			img.set_pixel(left_x, y, deep)
		if right_x >= 0 and right_x < TILE_SIZE and y < TILE_SIZE:
			img.set_pixel(right_x, y, deep)

	# Snow cap with realistic shading and drift
	var snow_line = peak_y + 10
	for y in range(peak_y, snow_line + 1):
		var progress = float(y - peak_y) / float(snow_line - peak_y)
		var base_width = int(progress * 8)
		# Irregular snow edge
		var edge_variation = int(sin(y * 0.8 + variant) * 2)

		for x in range(peak_x - base_width - edge_variation, peak_x + base_width + edge_variation + 1):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				# Check if we're within mountain bounds
				var mtn_progress = float(y - peak_y) / float(base_y - peak_y)
				var mtn_left = int(lerp(peak_x, base_left, mtn_progress))
				var mtn_right = int(lerp(peak_x, base_right, mtn_progress))
				if x < mtn_left or x > mtn_right:
					continue

				var rel_x = float(x - peak_x) / max(base_width + edge_variation, 1)
				var c = palette["snow"]

				# Snow shading: lit from top-right in FF style
				if rel_x < -0.5:
					c = snow_blue  # Deep shadow (left side)
				elif rel_x < -0.2:
					c = snow_shadow  # Light shadow
				elif y >= snow_line - 1:
					c = snow_shadow  # Bottom edge
				elif rel_x > 0.3 and y < peak_y + 4:
					c = Color(1.0, 1.0, 1.0)  # Bright peak highlight

				# Snow texture
				var snow_noise = sin(x * 2.2 + y * 1.8 + variant * 2.0) * 0.3
				if snow_noise > 0.2:
					c = c.lightened(0.05)

				img.set_pixel(x, y, c)

	# Rocky outcrops and crevices
	var crevice_count = rng.randi_range(3, 5)
	for i in range(crevice_count):
		var cx = rng.randi_range(peak_x - 10, peak_x + 10)
		var cy = rng.randi_range(snow_line + 3, base_y - 5)
		var crev_len = rng.randi_range(2, 5)

		# Diagonal crevice line
		for d in range(crev_len):
			var px = cx + d / 2
			var py = cy + d
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				img.set_pixel(px, py, deep)
				# Highlight on one side of crevice
				if px + 1 < TILE_SIZE:
					var existing = img.get_pixel(px + 1, py)
					if existing.r > 0.2:  # Is rock, not void
						img.set_pixel(px + 1, py, existing.lightened(0.1))

	# Rocky ledges with shadows beneath
	for i in range(2):
		var lx = rng.randi_range(peak_x - 8, peak_x + 8)
		var ly = rng.randi_range(snow_line + 5, base_y - 8)
		var ledge_w = rng.randi_range(3, 6)
		# Ledge top (lit)
		for dx in range(ledge_w):
			var px = lx + dx
			if px >= 0 and px < TILE_SIZE and ly >= 0 and ly < TILE_SIZE:
				img.set_pixel(px, ly, palette["light"])
		# Shadow beneath ledge
		for dx in range(ledge_w):
			var px = lx + dx
			if px >= 0 and px < TILE_SIZE and ly + 1 >= 0 and ly + 1 < TILE_SIZE:
				img.set_pixel(px, ly + 1, deep)


## Water tile - FF4/5/6 quality animated water with waves, depth, and sparkles
func _draw_water(img: Image, palette: Dictionary, variant: int) -> void:
	# Deep water base
	var abyss = palette.get("abyss", palette["deep"].darkened(0.2))
	img.fill(palette["dark"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	var mid_light = palette.get("mid_light", palette["base"].lightened(0.1))
	var deep = palette.get("deep", palette["dark"].darkened(0.2))
	var foam_light = palette.get("foam_light", palette["foam"].lightened(0.15))
	var sparkle = palette.get("sparkle", Color(1.0, 1.0, 1.0))
	var teal_accent = palette.get("teal_accent", Color(0.18, 0.55, 0.72))

	# Wave animation offset (4 frames for seamless looping)
	var wave_offset = (variant % 4) * 8
	var secondary_offset = (variant % 4) * 5
	var tertiary_offset = (variant % 4) * 3

	# Multi-layered wave system
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Primary wave (large, slow rolling waves)
			var w1 = sin((x + wave_offset) * 0.32 + y * 0.16) * 0.40 + 0.5
			# Secondary wave (medium diagonal pattern)
			var w2 = sin((x - secondary_offset) * 0.24 + y * 0.35 + 1.5) * 0.28 + 0.5
			# Tertiary wave (small ripples)
			var w3 = sin((x + tertiary_offset) * 0.52 + y * 0.48 + 0.8) * 0.18 + 0.5
			# Cross-wave interference
			var w4 = sin((x - y) * 0.18 + variant * 0.3) * 0.12 + 0.5

			var combined = (w1 + w2 + w3 + w4) / 4.0

			# 8-tone water palette for rich depth
			if combined > 0.78:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.68:
				img.set_pixel(x, y, mid_light)
			elif combined > 0.55:
				img.set_pixel(x, y, palette["base"])
			elif combined > 0.45:
				img.set_pixel(x, y, teal_accent)  # Teal mid-tone accent
			elif combined > 0.35:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.25:
				img.set_pixel(x, y, deep)
			elif combined > 0.15:
				img.set_pixel(x, y, abyss)
			# else stays dark base

	# Wave crest foam with curved shapes and glow
	var foam_count = rng.randi_range(2, 4)
	for i in range(foam_count):
		var foam_x = rng.randi_range(2, TILE_SIZE - 12)
		var foam_y = rng.randi_range(3, TILE_SIZE - 5)
		var foam_len = rng.randi_range(6, 12)
		var foam_curve = rng.randf_range(0.5, 1.2)

		# Curved foam line (wave crest)
		for f in range(foam_len):
			var fx = foam_x + f
			var curve_offset = sin(f * foam_curve + variant * 0.4) * 2.5
			var fy = foam_y + int(curve_offset)

			if fx >= 0 and fx < TILE_SIZE and fy >= 0 and fy < TILE_SIZE:
				# Foam body with gradient
				if f == 0 or f == foam_len - 1:
					img.set_pixel(fx, fy, mid_light)  # Tapered ends
				elif f > foam_len / 4 and f < foam_len * 3 / 4:
					img.set_pixel(fx, fy, foam_light)  # Bright center
				else:
					img.set_pixel(fx, fy, palette["foam"])

				# Soft glow beneath foam (lit water beneath crest)
				if fy + 1 < TILE_SIZE:
					img.set_pixel(fx, fy + 1, palette["light"])
				# Shadow above foam (where wave is rising)
				if fy - 1 >= 0 and rng.randf() < 0.5:
					var existing = img.get_pixel(fx, fy - 1)
					img.set_pixel(fx, fy - 1, existing.darkened(0.1))

	# Sparkle highlights (sunlight glinting off water)
	var sparkle_count = rng.randi_range(3, 6)
	for i in range(sparkle_count):
		var sx = rng.randi_range(2, TILE_SIZE - 3)
		var sy = rng.randi_range(2, TILE_SIZE - 3)
		# Only sparkle on lighter parts of water
		var existing = img.get_pixel(sx, sy)
		if existing.b > 0.5:  # Is lighter water
			img.set_pixel(sx, sy, sparkle)
			# Small cross pattern for sparkle
			if sx > 0 and rng.randf() < 0.4:
				img.set_pixel(sx - 1, sy, foam_light)
			if sx < TILE_SIZE - 1 and rng.randf() < 0.4:
				img.set_pixel(sx + 1, sy, foam_light)

	# Subtle depth gradient (darker at bottom for seamless tiling into deeper water)
	for y in range(TILE_SIZE - 4, TILE_SIZE):
		for x in range(TILE_SIZE):
			var depth_factor = float(y - (TILE_SIZE - 4)) / 4.0 * 0.15
			var c = img.get_pixel(x, y)
			if rng.randf() < 0.6:
				img.set_pixel(x, y, c.darkened(depth_factor))


## Path/road tile - FF4/5/6 quality worn dirt road with texture, stones, grass edges
func _draw_path(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	var mid = palette.get("mid", palette["base"].lerp(palette["light"], 0.4))
	var deep = palette.get("deep", palette["dark"].darkened(0.15))
	var stone_light = palette.get("stone_light", palette["stone"].lightened(0.1))
	var stone_dark = palette.get("stone_dark", palette["stone"].darkened(0.1))
	var pebble = palette.get("pebble", Color(0.50, 0.48, 0.44))

	# Multi-layer dirt texture with FF-style diagonal lighting
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Center-weighted wear pattern (worn smoother in middle)
			var cx_dist = abs(x - TILE_SIZE / 2.0) / (TILE_SIZE / 2.0)
			var wear_factor = 1.0 - cx_dist * 0.4

			# Multiple noise frequencies for organic look
			var n1 = sin(x * 0.75 + variant * 1.3) * cos(y * 0.55 + variant * 0.9)
			var n2 = sin(x * 1.4 + y * 1.1 + variant * 2.5) * 0.38
			var n3 = sin((x + y) * 0.32 + variant * 1.1) * 0.22
			var combined = (n1 + n2 + n3) / 3.0 + rng.randf() * 0.28

			# Diagonal light gradient (brighter top-left)
			var light_bias = (float(TILE_SIZE - x) + float(TILE_SIZE - y)) / (TILE_SIZE * 2.0) * 0.12
			combined += light_bias

			# 6-tone shading
			if combined < -0.25:
				img.set_pixel(x, y, deep)
			elif combined < -0.10:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.35 * wear_factor:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.22 * wear_factor:
				img.set_pixel(x, y, mid)
			elif combined > 0.10:
				img.set_pixel(x, y, palette["base"].lightened(0.04))

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


## Cave floor tile - FF4/5/6 quality dark stone with puddles, crystals, and atmospheric details
func _draw_cave_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 66666

	var mid = palette.get("mid", palette["base"].lerp(palette["light"], 0.4))
	var deep = palette.get("deep", palette["dark"].darkened(0.2))
	var wet = palette.get("wet", Color(0.25, 0.28, 0.30))
	var puddle = palette.get("puddle", Color(0.18, 0.25, 0.35))
	var crystal = palette.get("crystal", Color(0.45, 0.38, 0.62))
	var crystal_glow = palette.get("crystal_glow", Color(0.55, 0.48, 0.75))
	var moss = palette.get("moss", Color(0.25, 0.35, 0.22))

	# Rough stone texture with multiple layers
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Multi-frequency noise for natural cave floor
			var n1 = sin(x * 0.4 + variant * 1.3) * cos(y * 0.35 + variant * 0.7)
			var n2 = sin(x * 0.9 + y * 0.7 + variant * 1.8) * 0.45
			var n3 = sin((x + y) * 0.25 + variant * 0.9) * 0.30
			var combined = (n1 + n2 + n3) / 3.0 + rng.randf() * 0.2

			# 6-tone shading for depth
			if combined < -0.30:
				img.set_pixel(x, y, deep)
			elif combined < -0.12:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.32:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.15:
				img.set_pixel(x, y, mid)

	# Cracks in the stone floor
	var crack_count = rng.randi_range(2, 4)
	for i in range(crack_count):
		var cx = rng.randi_range(2, TILE_SIZE - 8)
		var cy = rng.randi_range(2, TILE_SIZE - 2)
		var crack_len = rng.randi_range(4, 10)
		var crack_dir = rng.randi_range(0, 1)  # 0 = horizontal, 1 = diagonal

		for c in range(crack_len):
			var px = cx + c
			var py = cy + (c / 3 if crack_dir == 1 else rng.randi_range(-1, 1))
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				img.set_pixel(px, py, deep)
				# Highlight on one side of crack
				if py - 1 >= 0:
					var existing = img.get_pixel(px, py - 1)
					img.set_pixel(px, py - 1, existing.lightened(0.08))

	# Wet patches and puddles (moisture in cave)
	var puddle_count = rng.randi_range(1, 3)
	for i in range(puddle_count):
		var px = rng.randi_range(4, TILE_SIZE - 6)
		var py = rng.randi_range(4, TILE_SIZE - 6)
		var puddle_w = rng.randi_range(3, 6)
		var puddle_h = rng.randi_range(2, 4)

		for dy in range(-1, puddle_h + 1):
			for dx in range(-1, puddle_w + 1):
				var ppx = px + dx
				var ppy = py + dy
				if ppx >= 0 and ppx < TILE_SIZE and ppy >= 0 and ppy < TILE_SIZE:
					# Wet edge around puddle
					if dx == -1 or dx == puddle_w or dy == -1 or dy == puddle_h:
						if rng.randf() < 0.6:
							img.set_pixel(ppx, ppy, wet)
					else:
						# Puddle body with reflection
						var puddle_shade = puddle
						if dy == 0 and dx > 0 and dx < puddle_w - 1:
							# Highlight/reflection at top of puddle
							puddle_shade = puddle.lightened(0.15)
						img.set_pixel(ppx, ppy, puddle_shade)

	# Small crystals growing from floor (variant-based)
	if variant % 3 == 0:
		var crystal_count = rng.randi_range(1, 3)
		for i in range(crystal_count):
			var crx = rng.randi_range(3, TILE_SIZE - 4)
			var cry = rng.randi_range(3, TILE_SIZE - 5)
			var crystal_h = rng.randi_range(2, 4)

			# Crystal shaft
			for h in range(crystal_h):
				if crx >= 0 and crx < TILE_SIZE and cry - h >= 0 and cry - h < TILE_SIZE:
					var shade = crystal_glow if h == crystal_h - 1 else crystal
					img.set_pixel(crx, cry - h, shade)
					# Crystal facet highlight
					if crx + 1 < TILE_SIZE and h > 0:
						img.set_pixel(crx + 1, cry - h, crystal.darkened(0.2))

			# Glow around crystal base
			for dx in [-1, 0, 1]:
				for dy in [0, 1]:
					var gpx = crx + dx
					var gpy = cry + dy
					if gpx >= 0 and gpx < TILE_SIZE and gpy >= 0 and gpy < TILE_SIZE:
						var existing = img.get_pixel(gpx, gpy)
						img.set_pixel(gpx, gpy, existing.lerp(crystal, 0.15))

	# Scattered pebbles and debris
	for i in range(rng.randi_range(3, 6)):
		var px = rng.randi_range(1, TILE_SIZE - 2)
		var py = rng.randi_range(1, TILE_SIZE - 2)
		if rng.randf() < 0.5:
			img.set_pixel(px, py, palette["light"])
		else:
			img.set_pixel(px, py, deep)

	# Occasional moss patches in damp areas
	if variant % 4 != 3:
		for i in range(rng.randi_range(0, 2)):
			var mx = rng.randi_range(2, TILE_SIZE - 4)
			var my = rng.randi_range(2, TILE_SIZE - 4)
			for dy in range(2):
				for dx in range(3):
					if mx + dx < TILE_SIZE and my + dy < TILE_SIZE and rng.randf() < 0.5:
						img.set_pixel(mx + dx, my + dy, moss)


## Cave wall tile - FF4/5/6 quality rocky walls with ore veins, dripping water, and detail
func _draw_cave_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 77777

	var mid = palette.get("mid", palette["base"].lerp(palette["light"], 0.4))
	var deep = palette.get("deep", palette["dark"].darkened(0.3))
	var vein = palette.get("vein", Color(0.42, 0.38, 0.50))
	var ore = palette.get("ore", Color(0.55, 0.45, 0.25))
	var ore_light = palette.get("ore_light", Color(0.70, 0.58, 0.32))
	var moss = palette.get("moss", Color(0.22, 0.32, 0.20))
	var drip = palette.get("drip", Color(0.32, 0.38, 0.42))

	# Multi-layered rock texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Multiple noise frequencies for realistic rock surface
			var n1 = sin(x * 0.38 + variant * 1.5) * cos(y * 0.32 + variant * 0.8)
			var n2 = sin(x * 0.85 + y * 0.65 + variant * 2.0) * 0.42
			var n3 = sin((x - y) * 0.28 + variant * 1.1) * 0.32
			var n4 = sin(x * 1.6 + y * 1.4 + variant * 2.5) * 0.18
			var combined = (n1 + n2 + n3 + n4) / 4.0 + rng.randf() * 0.18

			# 6-tone rock shading
			if combined < -0.32:
				img.set_pixel(x, y, deep)
			elif combined < -0.15:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.35:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.20:
				img.set_pixel(x, y, mid)
			elif combined > 0.05:
				img.set_pixel(x, y, palette["base"])

	# Rock strata/layering lines (horizontal bands in rock)
	var strata_count = rng.randi_range(2, 4)
	for i in range(strata_count):
		var sy = rng.randi_range(4, TILE_SIZE - 4)
		var wave = rng.randf_range(0.3, 0.8)
		for x in range(TILE_SIZE):
			var strata_y = sy + int(sin(x * wave + variant) * 1.5)
			if strata_y >= 0 and strata_y < TILE_SIZE:
				var existing = img.get_pixel(x, strata_y)
				img.set_pixel(x, strata_y, existing.darkened(0.12))
				if strata_y + 1 < TILE_SIZE:
					existing = img.get_pixel(x, strata_y + 1)
					img.set_pixel(x, strata_y + 1, existing.lightened(0.08))

	# Ore veins (mineral deposits in wall)
	if variant % 3 != 2:
		var vein_count = rng.randi_range(1, 2)
		for i in range(vein_count):
			var vx = rng.randi_range(3, TILE_SIZE - 8)
			var vy = rng.randi_range(3, TILE_SIZE - 3)
			var vein_len = rng.randi_range(5, 12)
			var vein_dir_x = rng.randf_range(0.8, 1.2)
			var vein_dir_y = rng.randf_range(-0.5, 0.5)

			for v in range(vein_len):
				var pvx = vx + int(v * vein_dir_x)
				var pvy = vy + int(v * vein_dir_y + sin(v * 0.5) * 1.5)
				if pvx >= 0 and pvx < TILE_SIZE and pvy >= 0 and pvy < TILE_SIZE:
					img.set_pixel(pvx, pvy, vein)
					# Ore nuggets along vein
					if rng.randf() < 0.3:
						img.set_pixel(pvx, pvy, ore)
						if pvx + 1 < TILE_SIZE:
							img.set_pixel(pvx + 1, pvy, ore_light)

	# Deep crevices/shadows
	var crevice_count = rng.randi_range(1, 3)
	for i in range(crevice_count):
		var cx = rng.randi_range(2, TILE_SIZE - 4)
		var cy = rng.randi_range(2, TILE_SIZE - 4)
		var crev_len = rng.randi_range(2, 5)
		for c in range(crev_len):
			var pcy = cy + c
			if cx >= 0 and cx < TILE_SIZE and pcy >= 0 and pcy < TILE_SIZE:
				img.set_pixel(cx, pcy, deep)

	# Water drip marks (vertical wet streaks from ceiling)
	if variant % 4 == 0:
		var drip_count = rng.randi_range(1, 2)
		for i in range(drip_count):
			var dx = rng.randi_range(4, TILE_SIZE - 5)
			var drip_start = rng.randi_range(0, 4)
			var drip_len = rng.randi_range(8, TILE_SIZE - drip_start - 2)

			for d in range(drip_len):
				var dy = drip_start + d
				if dx >= 0 and dx < TILE_SIZE and dy >= 0 and dy < TILE_SIZE:
					# Drip gets wider and lighter toward bottom
					var drip_width = 1 if d < drip_len / 2 else 2
					for dw in range(drip_width):
						var pdx = dx + dw
						if pdx < TILE_SIZE:
							var drip_shade = drip.lightened(0.05) if d > drip_len * 2 / 3 else drip
							img.set_pixel(pdx, dy, drip_shade)

	# Moss on damp rock
	if variant % 3 == 1:
		for i in range(rng.randi_range(2, 4)):
			var mx = rng.randi_range(1, TILE_SIZE - 4)
			var my = rng.randi_range(TILE_SIZE / 2, TILE_SIZE - 3)
			var moss_size = rng.randi_range(2, 4)
			for dy in range(moss_size):
				for dx in range(moss_size):
					if mx + dx < TILE_SIZE and my + dy < TILE_SIZE and rng.randf() < 0.55:
						img.set_pixel(mx + dx, my + dy, moss.lightened(rng.randf_range(-0.05, 0.08)))

	# Protruding rock edges (3D effect)
	for i in range(rng.randi_range(2, 4)):
		var ex = rng.randi_range(2, TILE_SIZE - 6)
		var ey = rng.randi_range(2, TILE_SIZE - 4)
		var edge_w = rng.randi_range(3, 6)
		# Lit top edge
		for dx in range(edge_w):
			if ex + dx < TILE_SIZE and ey >= 0 and ey < TILE_SIZE:
				img.set_pixel(ex + dx, ey, palette["light"])
		# Shadow beneath
		for dx in range(edge_w):
			if ex + dx < TILE_SIZE and ey + 1 >= 0 and ey + 1 < TILE_SIZE:
				img.set_pixel(ex + dx, ey + 1, deep)


## Create a TileSet with all tile types for use in TileMap
func create_tileset() -> TileSet:
	print("Creating FF4/5/6 quality tileset...")
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer for collision
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)  # Layer 1
	tileset.set_physics_layer_collision_mask(0, 1)

	# Create atlas source from generated tiles
	var atlas = TileSetAtlasSource.new()

	# Expanded 5x4 atlas (20 tiles) to include cave tiles and variants
	var atlas_cols = 5
	var atlas_rows = 4
	var atlas_img = Image.create(TILE_SIZE * atlas_cols, TILE_SIZE * atlas_rows, false, Image.FORMAT_RGBA8)

	# Generate and place tiles in atlas
	# Row 0: Base terrain types
	# Row 1: Buildings and structures
	# Row 2: Cave tiles and grass variants
	# Row 3: Water animation frames
	var tile_order = [
		# Row 0: Core terrain
		TileType.GRASS, TileType.FOREST, TileType.MOUNTAIN, TileType.WATER, TileType.PATH,
		# Row 1: Structures
		TileType.BRIDGE, TileType.CAVE_ENTRANCE, TileType.VILLAGE_GATE, TileType.WALL, TileType.FLOOR,
		# Row 2: Cave and variants
		TileType.CAVE_FLOOR, TileType.CAVE_WALL, TileType.GRASS, TileType.GRASS, TileType.FOREST,
		# Row 3: Water animation + mountain variant
		TileType.WATER, TileType.WATER, TileType.WATER, TileType.WATER, TileType.MOUNTAIN
	]

	# Variant mapping: tile index -> variant number
	var tile_variants = {
		12: 1,  # Grass variant 1
		13: 2,  # Grass variant 2
		14: 1,  # Forest variant 1
		15: 1,  # Water frame 1
		16: 2,  # Water frame 2
		17: 3,  # Water frame 3
		18: 4,  # Water frame 4
		19: 1   # Mountain variant 1
	}

	# Impassable tile types (need collision)
	var impassable_types = [TileType.FOREST, TileType.MOUNTAIN, TileType.WATER, TileType.WALL, TileType.CAVE_WALL]

	for i in range(tile_order.size()):
		var tile_type = tile_order[i]
		var variant = tile_variants.get(i, 0)

		var tile_tex = generate_tile(tile_type, variant)
		var tile_img = tile_tex.get_image()

		var atlas_x = (i % atlas_cols) * TILE_SIZE
		var atlas_y = (i / atlas_cols) * TILE_SIZE

		# Copy tile to atlas
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				atlas_img.set_pixel(atlas_x + x, atlas_y + y, tile_img.get_pixel(x, y))

	var atlas_texture = ImageTexture.create_from_image(atlas_img)
	atlas.texture = atlas_texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Debug: Save atlas to disk for inspection
	atlas_img.save_png("user://debug_atlas.png")
	print("Atlas saved to user://debug_atlas.png (size: %dx%d, %d tiles)" % [atlas_img.get_width(), atlas_img.get_height(), tile_order.size()])

	# First, create all tiles in atlas without collision
	for i in range(tile_order.size()):
		var coords = Vector2i(i % atlas_cols, i / atlas_cols)
		atlas.create_tile(coords)

	# Add the atlas source to the tileset BEFORE setting collision data
	tileset.add_source(atlas)

	# Now add collision for impassable tiles
	for i in range(tile_order.size()):
		var tile_type = tile_order[i]
		if tile_type in impassable_types:
			var coords = Vector2i(i % atlas_cols, i / atlas_cols)
			var tile_data = atlas.get_tile_data(coords, 0)
			if tile_data:
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
	# Mapping based on tile_order in create_tileset (5-column layout)
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
		TileType.CAVE_FLOOR: return 10
		TileType.CAVE_WALL: return 11
	return 0


## Get atlas coordinates for a tile ID (for 5-column layout)
static func get_atlas_coords_for_id(tile_id: int) -> Vector2i:
	return Vector2i(tile_id % 5, tile_id / 5)
