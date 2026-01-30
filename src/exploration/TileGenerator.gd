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

## Color palettes for each tile type (limited palette per tile for authenticity)
const PALETTES: Dictionary = {
	TileType.GRASS: {
		"base": Color(0.25, 0.55, 0.20),
		"light": Color(0.35, 0.65, 0.25),
		"dark": Color(0.18, 0.40, 0.15),
		"accent": Color(0.30, 0.50, 0.22)
	},
	TileType.FOREST: {
		"base": Color(0.15, 0.40, 0.12),
		"light": Color(0.22, 0.50, 0.18),
		"dark": Color(0.08, 0.25, 0.06),
		"trunk": Color(0.35, 0.22, 0.12)
	},
	TileType.MOUNTAIN: {
		"base": Color(0.45, 0.40, 0.35),
		"light": Color(0.60, 0.55, 0.50),
		"dark": Color(0.30, 0.28, 0.25),
		"snow": Color(0.90, 0.92, 0.95)
	},
	TileType.WATER: {
		"base": Color(0.20, 0.45, 0.70),
		"light": Color(0.35, 0.60, 0.80),
		"dark": Color(0.12, 0.30, 0.55),
		"foam": Color(0.75, 0.85, 0.95)
	},
	TileType.PATH: {
		"base": Color(0.55, 0.45, 0.30),
		"light": Color(0.65, 0.55, 0.38),
		"dark": Color(0.40, 0.32, 0.22),
		"stone": Color(0.50, 0.48, 0.45)
	},
	TileType.BRIDGE: {
		"base": Color(0.45, 0.30, 0.18),
		"light": Color(0.55, 0.38, 0.22),
		"dark": Color(0.32, 0.22, 0.12),
		"nail": Color(0.35, 0.35, 0.40)
	},
	TileType.CAVE_ENTRANCE: {
		"base": Color(0.12, 0.10, 0.08),
		"rock": Color(0.40, 0.35, 0.30),
		"dark": Color(0.05, 0.04, 0.03),
		"highlight": Color(0.55, 0.50, 0.45)
	},
	TileType.VILLAGE_GATE: {
		"base": Color(0.50, 0.35, 0.20),
		"light": Color(0.60, 0.42, 0.25),
		"dark": Color(0.35, 0.25, 0.15),
		"metal": Color(0.45, 0.45, 0.50)
	},
	TileType.WALL: {
		"base": Color(0.50, 0.45, 0.40),
		"light": Color(0.62, 0.58, 0.52),
		"dark": Color(0.35, 0.32, 0.28),
		"moss": Color(0.30, 0.45, 0.25)
	},
	TileType.FLOOR: {
		"base": Color(0.55, 0.50, 0.42),
		"light": Color(0.65, 0.60, 0.50),
		"dark": Color(0.42, 0.38, 0.32),
		"accent": Color(0.48, 0.44, 0.38)
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


## Grass tile - green base with scattered darker patches, flowers, and grass tufts
func _draw_grass(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with base color
	img.fill(palette["base"])

	# Add texture variation using seeded randomness
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12345

	# Simplex-like noise pattern for natural look
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Create clustered variation (not pure random)
			var cluster_val = sin(x * 0.4 + variant) * cos(y * 0.3) * 0.5 + 0.5
			var noise_val = rng.randf() * 0.7 + cluster_val * 0.3

			if noise_val < 0.12:
				img.set_pixel(x, y, palette["dark"])
			elif noise_val < 0.22:
				img.set_pixel(x, y, palette["light"])
			elif noise_val < 0.28:
				img.set_pixel(x, y, palette["accent"])

	# Add grass tufts (multiple blades)
	for i in range(5):
		var tuft_x = rng.randi_range(4, TILE_SIZE - 5)
		var tuft_y = rng.randi_range(4, TILE_SIZE - 4)

		# Draw a small tuft of 3 blades
		for blade in range(3):
			var bx = tuft_x + blade - 1
			var blade_height = rng.randi_range(2, 4)
			for h in range(blade_height):
				if bx >= 0 and bx < TILE_SIZE and tuft_y - h >= 0:
					var shade = palette["light"] if h == blade_height - 1 else palette["dark"]
					img.set_pixel(bx, tuft_y - h, shade)

	# Add occasional small flowers (based on variant)
	if variant % 3 == 0:  # Only some tiles get flowers
		var flower_colors = [
			Color(0.9, 0.9, 0.3),  # Yellow
			Color(0.9, 0.6, 0.7),  # Pink
			Color(0.7, 0.7, 0.9),  # Light purple
			Color(0.9, 0.5, 0.4),  # Orange-red
		]
		var flower_count = rng.randi_range(1, 3)
		for f in range(flower_count):
			var fx = rng.randi_range(3, TILE_SIZE - 4)
			var fy = rng.randi_range(3, TILE_SIZE - 4)
			var flower_color = flower_colors[rng.randi() % flower_colors.size()]
			# Draw small flower (cross pattern)
			img.set_pixel(fx, fy, flower_color)
			if fx > 0:
				img.set_pixel(fx - 1, fy, flower_color)
			if fx < TILE_SIZE - 1:
				img.set_pixel(fx + 1, fy, flower_color)
			if fy > 0:
				img.set_pixel(fx, fy - 1, flower_color)
			# Flower center
			img.set_pixel(fx, fy, Color(1.0, 1.0, 0.6))


## Forest tile - tree pattern (impassable)
func _draw_forest(img: Image, palette: Dictionary, variant: int) -> void:
	# Grass base
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 54321

	# Draw tree trunk in center-ish
	var trunk_x = 14 + rng.randi_range(-2, 2)
	var trunk_bottom = 28
	var trunk_top = 16
	for y in range(trunk_top, trunk_bottom):
		for x in range(trunk_x - 1, trunk_x + 2):
			img.set_pixel(x, y, palette["trunk"])

	# Draw foliage (circular blob at top)
	var foliage_cx = trunk_x
	var foliage_cy = 12
	var foliage_r = 10
	for y in range(foliage_cy - foliage_r, foliage_cy + foliage_r):
		for x in range(foliage_cx - foliage_r, foliage_cx + foliage_r):
			var dist = sqrt(pow(x - foliage_cx, 2) + pow(y - foliage_cy, 2))
			if dist < foliage_r and x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				var shade = palette["base"]
				if y < foliage_cy - 3:
					shade = palette["light"]
				elif y > foliage_cy + 3:
					shade = palette["dark"]
				img.set_pixel(x, y, shade)

	# Dark outline on bottom for depth
	for x in range(foliage_cx - foliage_r + 2, foliage_cx + foliage_r - 2):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, foliage_cy + foliage_r - 2, palette["dark"])


## Mountain tile - rocky peaks (impassable)
func _draw_mountain(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with dark base
	img.fill(palette["dark"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 98765

	# Draw triangular mountain shape
	var peak_x = 16 + rng.randi_range(-4, 4)
	var peak_y = 4
	var base_left = 2
	var base_right = 30
	var base_y = 30

	for y in range(peak_y, base_y):
		var progress = float(y - peak_y) / float(base_y - peak_y)
		var left_x = int(lerp(peak_x, base_left, progress))
		var right_x = int(lerp(peak_x, base_right, progress))
		for x in range(left_x, right_x):
			if x >= 0 and x < TILE_SIZE:
				var shade = palette["base"]
				if x < (left_x + right_x) / 2 - 2:
					shade = palette["dark"]
				elif x > (left_x + right_x) / 2 + 2:
					shade = palette["light"]
				img.set_pixel(x, y, shade)

	# Snow cap on top
	for y in range(peak_y, peak_y + 6):
		var progress = float(y - peak_y) / 6.0
		var width = int(progress * 5)
		for x in range(peak_x - width, peak_x + width + 1):
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				img.set_pixel(x, y, palette["snow"])


## Water tile - animated blue waves with ripples and depth
func _draw_water(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with base blue
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	# Wave pattern based on variant (for animation frames)
	var wave_offset = (variant % 4) * 8
	var secondary_wave_offset = (variant % 4) * 4

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Multiple overlapping wave patterns for realistic water
			var wave1 = sin((x + wave_offset) * 0.4 + y * 0.2) * 0.5 + 0.5
			var wave2 = sin((x - secondary_wave_offset) * 0.25 + y * 0.35) * 0.3 + 0.5
			var combined = (wave1 + wave2) / 2.0

			if combined > 0.65:
				img.set_pixel(x, y, palette["light"])
			elif combined < 0.35:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.55:
				# Subtle mid-tone variation
				var mid_light = palette["base"].lightened(0.1)
				img.set_pixel(x, y, mid_light)

	# Add foam highlights in curved patterns
	for i in range(2):
		var foam_x = rng.randi_range(6, TILE_SIZE - 8)
		var foam_y = rng.randi_range(6, TILE_SIZE - 8)
		# Draw curved foam line (wave crest)
		for f in range(6):
			var fx = foam_x + f
			var fy = foam_y + int(sin(f * 0.8) * 2)
			if fx >= 0 and fx < TILE_SIZE and fy >= 0 and fy < TILE_SIZE:
				img.set_pixel(fx, fy, palette["foam"])
				# Add slight foam glow below
				if fy + 1 < TILE_SIZE:
					var glow = palette["foam"]
					glow.a = 0.5
					img.set_pixel(fx, fy + 1, palette["light"])

	# Add subtle depth variation (darker towards edges)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var edge_dist = min(x, y, TILE_SIZE - 1 - x, TILE_SIZE - 1 - y)
			if edge_dist < 3 and rng.randf() < 0.3:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.1))


## Path/road tile - worn ground with wheel ruts and varied stones
func _draw_path(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	# Add dirt texture with worn patterns
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Center of path is more worn (lighter)
			var center_dist = abs(x - TILE_SIZE / 2) + abs(y - TILE_SIZE / 2)
			var wear_factor = 1.0 - (center_dist / 32.0) * 0.3

			var noise = rng.randf()
			if noise < 0.10 * wear_factor:
				img.set_pixel(x, y, palette["dark"])
			elif noise < 0.18:
				img.set_pixel(x, y, palette["light"])
			elif noise < 0.24:
				img.set_pixel(x, y, palette["stone"])

	# Add wheel rut marks (subtle darker lines)
	var rut_positions = [10, 22]  # Two ruts for cart wheels
	for rut_x in rut_positions:
		for y in range(TILE_SIZE):
			if rng.randf() < 0.6:  # Not continuous
				var rx = rut_x + rng.randi_range(-1, 1)
				if rx >= 0 and rx < TILE_SIZE:
					var current = img.get_pixel(rx, y)
					img.set_pixel(rx, y, current.darkened(0.15))

	# Add varied stones
	var stone_count = rng.randi_range(2, 5)
	for i in range(stone_count):
		var sx = rng.randi_range(2, TILE_SIZE - 4)
		var sy = rng.randi_range(2, TILE_SIZE - 4)
		var stone_size = rng.randi_range(1, 3)
		var stone_shade = palette["stone"].lightened(rng.randf_range(-0.1, 0.1))

		# Draw irregular stone shape
		for dy in range(stone_size):
			for dx in range(stone_size):
				var px = sx + dx
				var py = sy + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					if dx == 0 and dy == 0:
						img.set_pixel(px, py, stone_shade.lightened(0.1))  # Highlight
					elif dx == stone_size - 1 or dy == stone_size - 1:
						img.set_pixel(px, py, stone_shade.darkened(0.1))  # Shadow
					else:
						img.set_pixel(px, py, stone_shade)

	# Add grass edges on sides
	var grass_color = Color(0.25, 0.45, 0.20)
	for y in range(TILE_SIZE):
		if rng.randf() < 0.3:
			if rng.randf() < 0.5:
				img.set_pixel(0, y, grass_color)
				img.set_pixel(1, y, grass_color.darkened(0.1))
			if rng.randf() < 0.5:
				img.set_pixel(TILE_SIZE - 1, y, grass_color)
				img.set_pixel(TILE_SIZE - 2, y, grass_color.darkened(0.1))


## Bridge tile - wooden planks
func _draw_bridge(img: Image, palette: Dictionary, variant: int) -> void:
	# Water underneath
	var water_pal = PALETTES[TileType.WATER]
	img.fill(water_pal["base"])

	# Draw wooden planks horizontally
	for plank in range(4):
		var py = 4 + plank * 7
		for y in range(py, py + 6):
			if y < TILE_SIZE:
				for x in range(TILE_SIZE):
					var shade = palette["base"]
					if y == py:
						shade = palette["light"]
					elif y == py + 5:
						shade = palette["dark"]
					img.set_pixel(x, y, shade)

		# Plank gap line
		for x in range(TILE_SIZE):
			if py + 6 < TILE_SIZE:
				img.set_pixel(x, py + 6, palette["dark"])

	# Add nails
	for plank in range(4):
		var py = 4 + plank * 7 + 2
		img.set_pixel(4, py, palette["nail"])
		img.set_pixel(27, py, palette["nail"])


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


## Wall tile - stone/brick pattern
func _draw_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 44444

	# Brick pattern
	var brick_h = 8
	var brick_w = 16

	for row in range(4):
		var y_start = row * brick_h
		var offset = (row % 2) * (brick_w / 2)  # Stagger rows

		for col in range(3):
			var x_start = col * brick_w - offset

			# Draw brick
			for y in range(y_start, mini(y_start + brick_h - 1, TILE_SIZE)):
				for x in range(maxi(0, x_start), mini(x_start + brick_w - 1, TILE_SIZE)):
					var shade = palette["base"]
					if rng.randf() < 0.1:
						shade = palette["light"]
					elif rng.randf() < 0.1:
						shade = palette["dark"]
					img.set_pixel(x, y, shade)

			# Mortar lines
			for x in range(maxi(0, x_start), mini(x_start + brick_w, TILE_SIZE)):
				if y_start + brick_h - 1 < TILE_SIZE:
					img.set_pixel(x, y_start + brick_h - 1, palette["dark"])
			for y in range(y_start, mini(y_start + brick_h, TILE_SIZE)):
				if x_start + brick_w - 1 >= 0 and x_start + brick_w - 1 < TILE_SIZE:
					img.set_pixel(x_start + brick_w - 1, y, palette["dark"])


## Floor tile - interior floor
func _draw_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 55555

	# Simple tile pattern
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Grid lines every 8 pixels
			if x % 8 == 0 or y % 8 == 0:
				img.set_pixel(x, y, palette["dark"])
			elif rng.randf() < 0.08:
				img.set_pixel(x, y, palette["light"])
			elif rng.randf() < 0.05:
				img.set_pixel(x, y, palette["accent"])


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
