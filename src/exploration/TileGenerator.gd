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


## Grass tile - green base with scattered darker patches
func _draw_grass(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with base color
	img.fill(palette["base"])

	# Add texture variation using seeded randomness
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12345

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var noise_val = rng.randf()
			if noise_val < 0.15:
				img.set_pixel(x, y, palette["dark"])
			elif noise_val < 0.25:
				img.set_pixel(x, y, palette["light"])
			elif noise_val < 0.30:
				img.set_pixel(x, y, palette["accent"])

	# Add small grass blades
	for i in range(8):
		var bx = rng.randi_range(2, TILE_SIZE - 3)
		var by = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(bx, by, palette["dark"])
		img.set_pixel(bx, by - 1, palette["light"])


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


## Water tile - animated blue waves
func _draw_water(img: Image, palette: Dictionary, variant: int) -> void:
	# Fill with base blue
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	# Wave pattern based on variant (for animation frames)
	var wave_offset = (variant % 4) * 8

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Sinusoidal wave pattern
			var wave = sin((x + wave_offset) * 0.4 + y * 0.2) * 0.5 + 0.5
			if wave > 0.7:
				img.set_pixel(x, y, palette["light"])
			elif wave < 0.3:
				img.set_pixel(x, y, palette["dark"])

	# Add foam highlights
	for i in range(3):
		var fx = rng.randi_range(4, TILE_SIZE - 5)
		var fy = rng.randi_range(4, TILE_SIZE - 5)
		img.set_pixel(fx, fy, palette["foam"])
		img.set_pixel(fx + 1, fy, palette["foam"])


## Path/road tile - worn ground
func _draw_path(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	# Add dirt texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var noise = rng.randf()
			if noise < 0.12:
				img.set_pixel(x, y, palette["dark"])
			elif noise < 0.22:
				img.set_pixel(x, y, palette["light"])
			elif noise < 0.26:
				img.set_pixel(x, y, palette["stone"])

	# Add occasional small stones
	for i in range(2):
		var sx = rng.randi_range(4, TILE_SIZE - 5)
		var sy = rng.randi_range(4, TILE_SIZE - 5)
		img.set_pixel(sx, sy, palette["stone"])
		img.set_pixel(sx + 1, sy, palette["stone"])


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


## Cave entrance tile - dark opening in rock
func _draw_cave_entrance(img: Image, palette: Dictionary) -> void:
	# Rock surround
	var mtn_pal = PALETTES[TileType.MOUNTAIN]
	img.fill(mtn_pal["base"])

	# Draw rock texture
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if rng.randf() < 0.2:
				img.set_pixel(x, y, mtn_pal["dark"])
			elif rng.randf() < 0.1:
				img.set_pixel(x, y, mtn_pal["light"])

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
				# Gradient from dark at back to slightly lighter at front
				var depth = float(cave_bottom - y) / float(cave_height)
				var dark_amt = 0.8 + depth * 0.2
				var c = Color(palette["base"].r * dark_amt, palette["base"].g * dark_amt, palette["base"].b * dark_amt)
				img.set_pixel(x, y, c)

	# Highlight around entrance
	for y in range(cave_bottom - cave_height - 1, cave_bottom):
		var progress = float(cave_bottom - y) / float(cave_height)
		var width = int(cave_width * (1.0 - progress * 0.5)) + 1
		var left_x = cave_cx - width
		var right_x = cave_cx + width - 1
		if left_x >= 0 and y >= 0 and y < TILE_SIZE:
			img.set_pixel(left_x, y, palette["highlight"])
		if right_x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
			img.set_pixel(right_x, y, mtn_pal["dark"])


## Village gate tile - wooden arch entrance
func _draw_village_gate(img: Image, palette: Dictionary) -> void:
	# Path base
	var path_pal = PALETTES[TileType.PATH]
	img.fill(path_pal["base"])

	# Draw gate posts (left and right)
	for post_x in [4, 24]:
		for y in range(2, 28):
			for x in range(post_x, post_x + 4):
				var shade = palette["base"]
				if x == post_x:
					shade = palette["dark"]
				elif x == post_x + 3:
					shade = palette["light"]
				img.set_pixel(x, y, shade)

	# Draw arch across top
	for y in range(2, 8):
		for x in range(4, 28):
			var shade = palette["base"]
			if y == 2:
				shade = palette["light"]
			elif y == 7:
				shade = palette["dark"]
			img.set_pixel(x, y, shade)

	# Gate opening (darker area under arch)
	for y in range(8, 30):
		for x in range(8, 24):
			# Slightly darker path to indicate entrance
			img.set_pixel(x, y, path_pal["dark"])

	# Metal bands on posts
	for post_x in [4, 24]:
		for band_y in [8, 18]:
			for x in range(post_x, post_x + 4):
				img.set_pixel(x, band_y, palette["metal"])


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

	# Create tiles in atlas and add collision for impassable ones
	for i in range(tile_order.size()):
		var coords = Vector2i(i % atlas_size, i / atlas_size)
		atlas.create_tile(coords)

		var tile_type = tile_order[i]
		# Add collision for impassable tiles
		if tile_type in impassable_types:
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

	tileset.add_source(atlas)

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
