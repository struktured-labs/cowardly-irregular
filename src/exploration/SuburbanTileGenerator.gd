extends Node
class_name SuburbanTileGenerator

## SuburbanTileGenerator - Procedurally generates 32x32 suburban tiles
## Bright EarthBound pastel aesthetic with American suburb elements

const TILE_SIZE: int = 32

## Tile types for Area 2 (EarthBound-style American suburban neighborhood)
enum TileType {
	SIDEWALK,        # 0 - light concrete with expansion joints
	ROAD,            # 1 - dark asphalt with yellow center line / crosswalk
	HOUSE_WALL,      # 2 - pastel siding (4 color variants) (impassable)
	LAWN,            # 3 - bright trimmed green grass with mower stripes
	STORE_FRONT,     # 4 - strip mall facade with awning (impassable)
	HOUSE_DOOR,      # 5 - house entrance with welcome mat
	HOUSE_WINDOW,    # 6 - window with flower box (impassable)
	PICKET_FENCE,    # 7 - white picket fence on grass (impassable)
	MAILBOX,         # 8 - blue USPS mailbox on concrete (impassable)
	FIRE_HYDRANT,    # 9 - red hydrant on sidewalk (impassable)
	PLAYGROUND,      # 10 - sand base with colorful equipment
	PARKING_LOT,     # 11 - gray surface with yellow parking lines
	SHADE_TREE,      # 12 - green canopy on brown trunk (impassable)
	PARK_BENCH,      # 13 - brown wood bench with iron frame (impassable)
	BASKETBALL_COURT,# 14 - orange surface with white lines
	FLOWER_BED       # 15 - rainbow flowers on dark soil
}

## Bright EarthBound pastel color palettes
const PALETTES: Dictionary = {
	TileType.SIDEWALK: {
		"base": Color(0.78, 0.76, 0.74),
		"light": Color(0.88, 0.86, 0.84),
		"mid": Color(0.82, 0.80, 0.78),
		"dark": Color(0.65, 0.63, 0.61),
		"deep": Color(0.55, 0.53, 0.51),
		"crack": Color(0.58, 0.56, 0.54),
		"crack_light": Color(0.84, 0.82, 0.80),
		"gum": Color(0.45, 0.28, 0.35),
		"joint": Color(0.62, 0.60, 0.58)
	},
	TileType.ROAD: {
		"base": Color(0.28, 0.28, 0.30),
		"light": Color(0.38, 0.38, 0.40),
		"mid": Color(0.33, 0.33, 0.35),
		"dark": Color(0.20, 0.20, 0.22),
		"deep": Color(0.14, 0.14, 0.16),
		"lane_yellow": Color(0.85, 0.75, 0.20),
		"crosswalk_white": Color(0.92, 0.92, 0.90),
		"edge_white": Color(0.85, 0.85, 0.82),
		"gravel": Color(0.40, 0.38, 0.36)
	},
	TileType.HOUSE_WALL: {
		"base": Color(0.65, 0.78, 0.92),
		"light": Color(0.75, 0.86, 0.96),
		"mid": Color(0.70, 0.82, 0.94),
		"dark": Color(0.55, 0.68, 0.82),
		"deep": Color(0.45, 0.58, 0.72),
		"trim_white": Color(0.95, 0.95, 0.94),
		"siding_line": Color(0.58, 0.70, 0.85),
		"pink": Color(0.92, 0.72, 0.72),
		"mint": Color(0.72, 0.90, 0.75)
	},
	TileType.LAWN: {
		"base": Color(0.35, 0.72, 0.30),
		"light": Color(0.50, 0.82, 0.42),
		"mid": Color(0.42, 0.76, 0.35),
		"dark": Color(0.25, 0.58, 0.20),
		"deep": Color(0.18, 0.45, 0.14),
		"lime": Color(0.55, 0.85, 0.35),
		"clover": Color(0.30, 0.65, 0.28),
		"dandelion": Color(0.95, 0.88, 0.25),
		"stripe_light": Color(0.40, 0.75, 0.35)
	},
	TileType.STORE_FRONT: {
		"base": Color(0.88, 0.82, 0.72),
		"light": Color(0.94, 0.90, 0.82),
		"mid": Color(0.90, 0.85, 0.76),
		"dark": Color(0.75, 0.70, 0.60),
		"deep": Color(0.62, 0.58, 0.50),
		"awning_red": Color(0.82, 0.22, 0.18),
		"awning_white": Color(0.95, 0.94, 0.92),
		"sign_bg": Color(0.25, 0.42, 0.60),
		"sign_text": Color(0.95, 0.92, 0.85)
	},
	TileType.HOUSE_DOOR: {
		"base": Color(0.52, 0.32, 0.18),
		"light": Color(0.65, 0.44, 0.28),
		"mid": Color(0.58, 0.38, 0.22),
		"dark": Color(0.38, 0.24, 0.12),
		"deep": Color(0.06, 0.05, 0.04),
		"frame_white": Color(0.95, 0.95, 0.94),
		"handle_brass": Color(0.78, 0.68, 0.28),
		"mat_red": Color(0.68, 0.25, 0.18),
		"mat_brown": Color(0.55, 0.38, 0.22)
	},
	TileType.HOUSE_WINDOW: {
		"base": Color(0.65, 0.78, 0.92),
		"light": Color(0.55, 0.72, 0.88),
		"mid": Color(0.60, 0.75, 0.90),
		"dark": Color(0.48, 0.62, 0.78),
		"deep": Color(0.38, 0.52, 0.68),
		"frame_white": Color(0.95, 0.95, 0.94),
		"glare": Color(0.96, 0.98, 1.0),
		"flower_red": Color(0.88, 0.28, 0.22),
		"flower_pink": Color(0.92, 0.55, 0.60)
	},
	TileType.PICKET_FENCE: {
		"base": Color(0.95, 0.94, 0.92),
		"light": Color(0.98, 0.98, 0.97),
		"mid": Color(0.90, 0.89, 0.86),
		"dark": Color(0.80, 0.78, 0.75),
		"deep": Color(0.70, 0.68, 0.65),
		"grass": Color(0.35, 0.72, 0.30),
		"grass_dark": Color(0.25, 0.58, 0.20),
		"picket_shadow": Color(0.82, 0.80, 0.77),
		"rail": Color(0.88, 0.86, 0.83)
	},
	TileType.MAILBOX: {
		"base": Color(0.20, 0.35, 0.62),
		"light": Color(0.30, 0.48, 0.75),
		"mid": Color(0.25, 0.40, 0.68),
		"dark": Color(0.15, 0.28, 0.52),
		"deep": Color(0.10, 0.20, 0.40),
		"flag_red": Color(0.85, 0.22, 0.18),
		"post_gray": Color(0.58, 0.56, 0.54),
		"concrete": Color(0.78, 0.76, 0.74),
		"slot": Color(0.08, 0.12, 0.22)
	},
	TileType.FIRE_HYDRANT: {
		"base": Color(0.82, 0.18, 0.15),
		"light": Color(0.92, 0.32, 0.28),
		"mid": Color(0.85, 0.24, 0.20),
		"dark": Color(0.65, 0.12, 0.10),
		"deep": Color(0.48, 0.08, 0.06),
		"cap": Color(0.72, 0.72, 0.74),
		"nozzle": Color(0.62, 0.62, 0.64),
		"concrete": Color(0.78, 0.76, 0.74),
		"highlight": Color(0.95, 0.45, 0.40)
	},
	TileType.PLAYGROUND: {
		"base": Color(0.82, 0.75, 0.58),
		"light": Color(0.90, 0.84, 0.68),
		"mid": Color(0.85, 0.78, 0.62),
		"dark": Color(0.72, 0.65, 0.48),
		"deep": Color(0.60, 0.54, 0.38),
		"slide_red": Color(0.85, 0.25, 0.20),
		"swing_blue": Color(0.25, 0.45, 0.78),
		"bar_yellow": Color(0.92, 0.82, 0.25),
		"chain_gray": Color(0.65, 0.65, 0.68)
	},
	TileType.PARKING_LOT: {
		"base": Color(0.55, 0.55, 0.57),
		"light": Color(0.65, 0.65, 0.67),
		"mid": Color(0.60, 0.60, 0.62),
		"dark": Color(0.45, 0.45, 0.47),
		"deep": Color(0.35, 0.35, 0.37),
		"line_yellow": Color(0.85, 0.75, 0.20),
		"oil_stain": Color(0.28, 0.26, 0.25),
		"oil_rainbow": Color(0.42, 0.35, 0.48),
		"gravel": Color(0.50, 0.48, 0.46)
	},
	TileType.SHADE_TREE: {
		"base": Color(0.25, 0.62, 0.22),
		"light": Color(0.38, 0.75, 0.32),
		"mid": Color(0.30, 0.68, 0.26),
		"dark": Color(0.18, 0.50, 0.15),
		"deep": Color(0.12, 0.38, 0.10),
		"trunk": Color(0.48, 0.32, 0.18),
		"trunk_dark": Color(0.35, 0.22, 0.12),
		"grass": Color(0.35, 0.72, 0.30),
		"grass_dark": Color(0.25, 0.58, 0.20)
	},
	TileType.PARK_BENCH: {
		"base": Color(0.55, 0.38, 0.22),
		"light": Color(0.68, 0.50, 0.32),
		"mid": Color(0.60, 0.42, 0.26),
		"dark": Color(0.42, 0.28, 0.15),
		"deep": Color(0.32, 0.20, 0.10),
		"iron_gray": Color(0.42, 0.42, 0.44),
		"iron_light": Color(0.55, 0.55, 0.58),
		"grass": Color(0.35, 0.72, 0.30),
		"grass_dark": Color(0.25, 0.58, 0.20)
	},
	TileType.BASKETBALL_COURT: {
		"base": Color(0.82, 0.48, 0.22),
		"light": Color(0.90, 0.58, 0.32),
		"mid": Color(0.85, 0.52, 0.26),
		"dark": Color(0.70, 0.38, 0.16),
		"deep": Color(0.58, 0.30, 0.12),
		"line_white": Color(0.95, 0.95, 0.94),
		"line_shadow": Color(0.72, 0.42, 0.18),
		"key_paint": Color(0.75, 0.42, 0.18),
		"rim_red": Color(0.82, 0.22, 0.15)
	},
	TileType.FLOWER_BED: {
		"base": Color(0.32, 0.24, 0.16),
		"light": Color(0.42, 0.34, 0.24),
		"mid": Color(0.36, 0.28, 0.20),
		"dark": Color(0.24, 0.18, 0.12),
		"deep": Color(0.18, 0.12, 0.08),
		"flower_red": Color(0.88, 0.22, 0.20),
		"flower_pink": Color(0.92, 0.52, 0.58),
		"flower_yellow": Color(0.95, 0.88, 0.25),
		"flower_purple": Color(0.62, 0.28, 0.72)
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
	var palette = PALETTES.get(type, PALETTES[TileType.SIDEWALK])

	match type:
		TileType.SIDEWALK:
			_draw_sidewalk(img, palette, variant)
		TileType.ROAD:
			_draw_road(img, palette, variant)
		TileType.HOUSE_WALL:
			_draw_house_wall(img, palette, variant)
		TileType.LAWN:
			_draw_lawn(img, palette, variant)
		TileType.STORE_FRONT:
			_draw_store_front(img, palette, variant)
		TileType.HOUSE_DOOR:
			_draw_house_door(img, palette)
		TileType.HOUSE_WINDOW:
			_draw_house_window(img, palette)
		TileType.PICKET_FENCE:
			_draw_picket_fence(img, palette, variant)
		TileType.MAILBOX:
			_draw_mailbox(img, palette)
		TileType.FIRE_HYDRANT:
			_draw_fire_hydrant(img, palette)
		TileType.PLAYGROUND:
			_draw_playground(img, palette, variant)
		TileType.PARKING_LOT:
			_draw_parking_lot(img, palette, variant)
		TileType.SHADE_TREE:
			_draw_shade_tree(img, palette)
		TileType.PARK_BENCH:
			_draw_park_bench(img, palette)
		TileType.BASKETBALL_COURT:
			_draw_basketball_court(img, palette, variant)
		TileType.FLOWER_BED:
			_draw_flower_bed(img, palette, variant)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## Light gray sidewalk with expansion joints, cracks, and gum spots
func _draw_sidewalk(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	# Base texture noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.5 + variant * 1.2) * cos(y * 0.4 + variant * 0.8)
			var n2 = sin(x * 1.1 + y * 0.7 + variant * 1.8) * 0.3
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.12
			if combined < -0.2:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.25:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.1:
				img.set_pixel(x, y, palette["mid"])

	# Expansion joint grid (every 16 pixels)
	for x in range(TILE_SIZE):
		if x % 16 == 0 or x % 16 == 1:
			for y in range(TILE_SIZE):
				img.set_pixel(x, y, palette["joint"])
	for y in range(TILE_SIZE):
		if y % 16 == 0 or y % 16 == 1:
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, palette["joint"])

	# Random cracks
	var crack_count = rng.randi_range(1, 3)
	for _c in range(crack_count):
		var cx = rng.randi_range(4, TILE_SIZE - 4)
		var cy = rng.randi_range(4, TILE_SIZE - 4)
		var crack_len = rng.randi_range(4, 10)
		for i in range(crack_len):
			var px = cx + rng.randi_range(-1, 1)
			var py = cy + i
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				img.set_pixel(px, py, palette["crack"])
				if px + 1 < TILE_SIZE:
					img.set_pixel(px + 1, py, palette["crack_light"])

	# Occasional gum spots
	if variant % 4 == 0:
		for _g in range(rng.randi_range(1, 2)):
			var gx = rng.randi_range(3, TILE_SIZE - 4)
			var gy = rng.randi_range(3, TILE_SIZE - 4)
			img.set_pixel(gx, gy, palette["gum"])
			img.set_pixel(gx + 1, gy, palette["gum"])
			if gy + 1 < TILE_SIZE:
				img.set_pixel(gx, gy + 1, palette["gum"].darkened(0.15))


## Dark asphalt road with yellow center line, crosswalk, and edge line variants
func _draw_road(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 22222

	# Road texture - asphalt noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 1.6 + y * 1.3 + variant * 2.5) * 0.3 + rng.randf() * 0.22
			if n < -0.15:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Scattered gravel flecks
	for _i in range(6):
		var gx = rng.randi_range(0, TILE_SIZE - 1)
		var gy = rng.randi_range(0, TILE_SIZE - 1)
		img.set_pixel(gx, gy, palette["gravel"])

	# Variant 0: Yellow dashed center line
	if variant % 3 == 0:
		for y in range(TILE_SIZE):
			if (y / 4) % 2 == 0:
				img.set_pixel(15, y, palette["lane_yellow"])
				img.set_pixel(16, y, palette["lane_yellow"])
	# Variant 1: White crosswalk stripes (horizontal bands)
	elif variant % 3 == 1:
		for y in range(TILE_SIZE):
			if (y / 4) % 2 == 0:
				for x in range(4, TILE_SIZE - 4):
					img.set_pixel(x, y, palette["crosswalk_white"])
	# Variant 2: Solid white edge line
	elif variant % 3 == 2:
		for y in range(TILE_SIZE):
			img.set_pixel(2, y, palette["edge_white"])
			img.set_pixel(TILE_SIZE - 3, y, palette["edge_white"])


## Pastel house siding - 4 color variants with clapboard detail and corner trim
func _draw_house_wall(img: Image, palette: Dictionary, variant: int) -> void:
	# Pick wall color based on variant
	var wall_colors = [
		Color(0.65, 0.80, 0.95),  # baby blue (brighter)
		Color(0.95, 0.72, 0.75),  # pink (more saturated)
		Color(0.72, 0.92, 0.78),  # mint (brighter)
		Color(0.98, 0.92, 0.62)   # buttercup (more vivid)
	]
	var wall_color = wall_colors[variant % 4]
	img.fill(wall_color)
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	# Individual clapboard siding rows (4px tall each)
	var board_h = 4
	for row in range(TILE_SIZE / board_h):
		var by = row * board_h
		var board_shift = rng.randf_range(-0.04, 0.04)
		var board_col = wall_color.lightened(board_shift) if board_shift > 0 else wall_color.darkened(-board_shift)

		for dy in range(board_h):
			for x in range(TILE_SIZE):
				var py = by + dy
				if py >= TILE_SIZE:
					continue
				var shade = board_col
				if dy == 0:
					shade = board_col.lightened(0.10)
				elif dy == 1:
					shade = board_col
				elif dy == 2:
					shade = board_col.darkened(0.03)
				elif dy == board_h - 1:
					shade = board_col.darkened(0.14)
				var grain = sin(x * 0.25 + py * 0.8 + variant * 0.7) * 0.06
				if grain > 0.03:
					shade = shade.lightened(0.03)
				elif grain < -0.03:
					shade = shade.darkened(0.03)
				img.set_pixel(x, py, shade)

	# Nail dots on every other board
	for row in range(0, TILE_SIZE / board_h, 2):
		var nail_y = row * board_h + 1
		if nail_y < TILE_SIZE:
			for nx in range(4, TILE_SIZE - 2, 8):
				img.set_pixel(nx, nail_y, wall_color.darkened(0.22))
				if nail_y > 0:
					img.set_pixel(nx, nail_y - 1, wall_color.lightened(0.05))

	# White trim at top
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["trim_white"])
		img.set_pixel(x, 1, palette["trim_white"])
		img.set_pixel(x, 2, palette["trim_white"].darkened(0.08))
		img.set_pixel(x, 3, palette["trim_white"].darkened(0.15))

	# White trim at bottom
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 1, palette["trim_white"])
		img.set_pixel(x, TILE_SIZE - 2, palette["trim_white"].darkened(0.06))

	# Corner trim on left and right edges
	for y in range(4, TILE_SIZE - 2):
		img.set_pixel(0, y, palette["trim_white"].darkened(0.04))
		img.set_pixel(1, y, palette["trim_white"].darkened(0.10))
		img.set_pixel(TILE_SIZE - 1, y, palette["trim_white"].darkened(0.04))
		img.set_pixel(TILE_SIZE - 2, y, palette["trim_white"].darkened(0.10))


## Bright green lawn with mower stripes, blade tufts, clover patches, and dandelions
func _draw_lawn(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 44444

	# Grass texture noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.6 + variant * 1.6) * cos(y * 0.5 + variant * 0.5)
			var n2 = sin(x * 1.3 + y * 0.9 + variant * 2.0) * 0.35
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.18
			if combined < -0.2:
				img.set_pixel(x, y, palette["deep"])
			elif combined < -0.05:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.3:
				img.set_pixel(x, y, palette["lime"])
			elif combined > 0.15:
				img.set_pixel(x, y, palette["light"])

	# Mower stripe pattern
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var band = (y / 8) % 2
			var current = img.get_pixel(x, y)
			if band == 0:
				img.set_pixel(x, y, current.lightened(0.06))
			else:
				img.set_pixel(x, y, current.darkened(0.06))

	# Grass blade tufts
	for _i in range(4 + variant % 3):
		var tx = rng.randi_range(2, TILE_SIZE - 3)
		var ty = rng.randi_range(8, TILE_SIZE - 2)
		for blade in range(rng.randi_range(2, 4)):
			var bx = tx + blade - 1
			var blade_h = rng.randi_range(2, 4)
			for h in range(blade_h):
				var px = bx + rng.randi_range(-1, 0)
				var py = ty - h
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					var shade = palette["lime"] if h == blade_h - 1 else palette["light"]
					img.set_pixel(px, py, shade)

	# Clover patches (bigger, 3-leaf shape)
	if variant % 3 == 0:
		for _i in range(rng.randi_range(1, 2)):
			var cx = rng.randi_range(5, TILE_SIZE - 6)
			var cy = rng.randi_range(5, TILE_SIZE - 6)
			img.set_pixel(cx, cy - 1, palette["clover"])
			img.set_pixel(cx - 1, cy, palette["clover"])
			img.set_pixel(cx + 1, cy, palette["clover"])
			img.set_pixel(cx, cy, palette["clover"].lightened(0.08))
			if cy + 1 < TILE_SIZE:
				img.set_pixel(cx, cy + 1, palette["dark"])
			if cy + 2 < TILE_SIZE:
				img.set_pixel(cx, cy + 2, palette["dark"])

	# Dandelions (bigger, with puffy head)
	if variant % 4 == 0:
		for _d in range(rng.randi_range(1, 2)):
			var dx = rng.randi_range(4, TILE_SIZE - 5)
			var dy = rng.randi_range(4, TILE_SIZE - 7)
			img.set_pixel(dx, dy, palette["dandelion"])
			if dx + 1 < TILE_SIZE:
				img.set_pixel(dx + 1, dy, palette["dandelion"])
			if dy > 0:
				img.set_pixel(dx, dy - 1, palette["dandelion"].lightened(0.1))
				if dx + 1 < TILE_SIZE:
					img.set_pixel(dx + 1, dy - 1, palette["dandelion"].lightened(0.05))
			if dx > 0:
				img.set_pixel(dx - 1, dy, palette["dandelion"].darkened(0.15))
			if dx + 2 < TILE_SIZE:
				img.set_pixel(dx + 2, dy, palette["dandelion"].darkened(0.15))
			for s in range(3):
				if dy + s + 1 < TILE_SIZE:
					img.set_pixel(dx, dy + s + 1, palette["dark"])
			if dx + 1 < TILE_SIZE and dy + 2 < TILE_SIZE:
				img.set_pixel(dx + 1, dy + 2, palette["clover"])


## Strip mall facade with scalloped awning, display window, sign, and doorway
func _draw_store_front(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 55555

	# Subtle stucco wall texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.4 + y * 0.2 + variant * 1.2) * 0.15 + rng.randf() * 0.08
			if n > 0.12:
				img.set_pixel(x, y, palette["light"])
			elif n < -0.1:
				img.set_pixel(x, y, palette["dark"])

	# Red/white striped awning (rows 0-4)
	for y in range(5):
		for x in range(TILE_SIZE):
			var stripe = (x / 4) % 2
			if stripe == 0:
				img.set_pixel(x, y, palette["awning_red"])
			else:
				img.set_pixel(x, y, palette["awning_white"])

	# Scalloped awning fringe
	for x in range(TILE_SIZE):
		var scallop = (x % 4)
		if scallop < 2:
			img.set_pixel(x, 5, palette["awning_red"].darkened(0.15))
		else:
			img.set_pixel(x, 5, palette["deep"])
	for x in range(TILE_SIZE):
		img.set_pixel(x, 6, palette["base"].darkened(0.12))

	# Sign rectangle (rows 8-13)
	var sign_top = 8
	var sign_bot = 14
	var sign_left = 3
	var sign_right = TILE_SIZE - 3
	for y in range(sign_top, sign_bot):
		for x in range(sign_left, sign_right):
			img.set_pixel(x, y, palette["sign_bg"])
	for x in range(sign_left, sign_right):
		img.set_pixel(x, sign_top, palette["sign_text"])
		img.set_pixel(x, sign_bot - 1, palette["sign_text"])
	for y in range(sign_top, sign_bot):
		img.set_pixel(sign_left, y, palette["sign_text"])
		img.set_pixel(sign_right - 1, y, palette["sign_text"])
	var text_y = sign_top + 2
	var text_start = sign_left + 3
	for _w in range(rng.randi_range(2, 4)):
		var word_len = rng.randi_range(3, 6)
		for i in range(word_len):
			if text_start + i < sign_right - 2:
				img.set_pixel(text_start + i, text_y, palette["sign_text"])
				img.set_pixel(text_start + i, text_y + 1, palette["sign_text"].darkened(0.1))
		text_start += word_len + 2

	# Display window (rows 15-25)
	var win_top = 15
	var win_bot = 26
	var win_left = 3
	var win_right = TILE_SIZE - 8
	for y in range(win_top, win_bot):
		for x in range(win_left, win_right):
			var rel_y = float(y - win_top) / float(win_bot - win_top)
			var shade: Color
			if rel_y < 0.25:
				shade = Color(0.55, 0.72, 0.88)
			elif rel_y > 0.75:
				shade = Color(0.38, 0.52, 0.68)
			else:
				shade = Color(0.48, 0.62, 0.78)
			img.set_pixel(x, y, shade)
	for x in range(win_left, win_right):
		img.set_pixel(x, win_top, Color(0.85, 0.85, 0.82))
		img.set_pixel(x, win_bot - 1, Color(0.85, 0.85, 0.82))
	for y in range(win_top, win_bot):
		img.set_pixel(win_left, y, Color(0.85, 0.85, 0.82))
		img.set_pixel(win_right - 1, y, Color(0.85, 0.85, 0.82))
	for i in range(4):
		var gx = win_left + 2 + i
		var gy = win_top + 2 + i
		if gx < win_right - 1 and gy < win_bot - 1:
			img.set_pixel(gx, gy, Color(0.92, 0.96, 1.0, 0.85))

	# Doorway on right side
	var door_left = TILE_SIZE - 7
	var door_right = TILE_SIZE - 1
	for y in range(win_top, TILE_SIZE - 1):
		for x in range(door_left, door_right):
			var shade = Color(0.48, 0.30, 0.16)
			var grain = sin(y * 0.8 + x * 0.15) * 0.08
			shade = shade.lightened(grain) if grain > 0 else shade.darkened(-grain)
			img.set_pixel(x, y, shade)
	for y in range(win_top, TILE_SIZE - 1):
		img.set_pixel(door_left, y, Color(0.85, 0.85, 0.82))
	img.set_pixel(door_left + 2, 22, Color(0.78, 0.68, 0.28))
	img.set_pixel(door_left + 2, 23, Color(0.78, 0.68, 0.28))

	# Bottom base/step
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 1, palette["deep"])
		img.set_pixel(x, TILE_SIZE - 2, palette["dark"])


## House entrance with white frame, wooden door, peephole, panels, and patterned welcome mat
func _draw_house_door(img: Image, palette: Dictionary) -> void:
	# White frame background
	img.fill(palette["frame_white"])

	# Door frame borders with molding profile
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["frame_white"])
		img.set_pixel(1, y, palette["frame_white"])
		img.set_pixel(2, y, palette["frame_white"].darkened(0.05))
		img.set_pixel(3, y, palette["frame_white"].darkened(0.10))
		img.set_pixel(TILE_SIZE - 4, y, palette["frame_white"].darkened(0.10))
		img.set_pixel(TILE_SIZE - 3, y, palette["frame_white"].darkened(0.05))
		img.set_pixel(TILE_SIZE - 2, y, palette["frame_white"])
		img.set_pixel(TILE_SIZE - 1, y, palette["frame_white"])
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["frame_white"])
		img.set_pixel(x, 1, palette["frame_white"])
		img.set_pixel(x, 2, palette["frame_white"].darkened(0.05))
		img.set_pixel(x, 3, palette["frame_white"].darkened(0.10))

	# Wooden door panel with richer grain
	for y in range(4, TILE_SIZE - 6):
		for x in range(4, TILE_SIZE - 4):
			var rel_y = float(y - 4) / float(TILE_SIZE - 10)
			var shade = palette["base"]
			if rel_y < 0.08:
				shade = palette["light"]
			elif rel_y > 0.92:
				shade = palette["dark"]
			var grain1 = sin(y * 1.2 + x * 0.08) * 0.15
			var grain2 = sin(y * 0.4 + x * 0.25 + 1.5) * 0.08
			var grain = grain1 + grain2
			if grain > 0.12:
				shade = shade.lightened(0.07)
			elif grain > 0.04:
				shade = shade.lightened(0.03)
			elif grain < -0.12:
				shade = shade.darkened(0.07)
			elif grain < -0.04:
				shade = shade.darkened(0.03)
			img.set_pixel(x, y, shade)

	# Upper panel inset with highlight/shadow borders
	var panel_left = 7
	var panel_right = TILE_SIZE - 7
	for y in range(7, 13):
		for x in range(panel_left, panel_right):
			img.set_pixel(x, y, palette["mid"])
	for x in range(panel_left, panel_right):
		img.set_pixel(x, 7, palette["dark"].darkened(0.05))
	for y in range(7, 13):
		img.set_pixel(panel_left, y, palette["dark"].darkened(0.05))
	for x in range(panel_left, panel_right):
		img.set_pixel(x, 12, palette["light"].lightened(0.05))
	for y in range(7, 13):
		img.set_pixel(panel_right - 1, y, palette["light"].lightened(0.05))

	# Lower panel inset
	for y in range(16, 22):
		for x in range(panel_left, panel_right):
			img.set_pixel(x, y, palette["mid"])
	for x in range(panel_left, panel_right):
		img.set_pixel(x, 16, palette["dark"].darkened(0.05))
	for y in range(16, 22):
		img.set_pixel(panel_left, y, palette["dark"].darkened(0.05))
	for x in range(panel_left, panel_right):
		img.set_pixel(x, 21, palette["light"].lightened(0.05))
	for y in range(16, 22):
		img.set_pixel(panel_right - 1, y, palette["light"].lightened(0.05))

	# Peephole
	img.set_pixel(TILE_SIZE / 2, 9, palette["deep"])
	img.set_pixel(TILE_SIZE / 2 + 1, 9, palette["deep"])
	img.set_pixel(TILE_SIZE / 2, 10, palette["deep"])
	img.set_pixel(TILE_SIZE / 2 + 1, 10, palette["deep"])
	if TILE_SIZE / 2 - 1 >= 0:
		img.set_pixel(TILE_SIZE / 2 - 1, 9, palette["handle_brass"].darkened(0.2))
	img.set_pixel(TILE_SIZE / 2 + 2, 9, palette["handle_brass"].darkened(0.2))

	# Brass door handle with backplate
	var hx = TILE_SIZE - 9
	var hy = TILE_SIZE / 2
	for dy in range(-1, 4):
		if hy + dy >= 0 and hy + dy < TILE_SIZE:
			img.set_pixel(hx, hy + dy, palette["handle_brass"].darkened(0.15))
	img.set_pixel(hx + 1, hy, palette["handle_brass"])
	img.set_pixel(hx + 1, hy + 1, palette["handle_brass"])
	img.set_pixel(hx + 2, hy, palette["handle_brass"].lightened(0.2))
	img.set_pixel(hx + 2, hy + 1, palette["handle_brass"].lightened(0.1))
	img.set_pixel(hx + 1, hy + 2, palette["deep"])

	# Patterned welcome mat (diamond pattern)
	for y in range(TILE_SIZE - 6, TILE_SIZE):
		for x in range(4, TILE_SIZE - 4):
			var rel_x = (x - 4) % 4
			var rel_y = (y - (TILE_SIZE - 6)) % 3
			var is_diamond = (rel_x + rel_y) % 2 == 0
			var mat_col = palette["mat_red"] if is_diamond else palette["mat_brown"]
			img.set_pixel(x, y, mat_col)
	for x in range(4, TILE_SIZE - 4):
		img.set_pixel(x, TILE_SIZE - 6, palette["mat_brown"].darkened(0.2))


## Window with white frame, glass pane, curtains, sill, and flower box with lush flowers
func _draw_house_window(img: Image, palette: Dictionary) -> void:
	# Wall background with siding lines
	var wall_col = Color(0.65, 0.80, 0.95)
	img.fill(wall_col)
	for y in range(TILE_SIZE):
		if y % 4 == 0:
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, wall_col.darkened(0.10))

	# White window frame outer
	var frame_top = 2
	var frame_bot = TILE_SIZE - 9
	var frame_left = 3
	var frame_right = TILE_SIZE - 3
	for x in range(frame_left, frame_right):
		img.set_pixel(x, frame_top, palette["frame_white"])
		img.set_pixel(x, frame_top + 1, palette["frame_white"])
		img.set_pixel(x, frame_bot, palette["frame_white"])
		img.set_pixel(x, frame_bot + 1, palette["frame_white"])
	for y in range(frame_top, frame_bot + 2):
		img.set_pixel(frame_left, y, palette["frame_white"])
		img.set_pixel(frame_left + 1, y, palette["frame_white"])
		img.set_pixel(frame_right - 1, y, palette["frame_white"])
		img.set_pixel(frame_right - 2, y, palette["frame_white"])

	# Glass pane with gradient
	var glass_top = frame_top + 2
	var glass_bot = frame_bot
	var glass_left = frame_left + 2
	var glass_right = frame_right - 2
	for y in range(glass_top, glass_bot):
		for x in range(glass_left, glass_right):
			var rel_y = float(y - glass_top) / float(glass_bot - glass_top)
			var shade: Color
			if rel_y < 0.25:
				shade = palette["light"]
			elif rel_y < 0.5:
				shade = palette["mid"]
			elif rel_y < 0.75:
				shade = palette["base"]
			else:
				shade = palette["dark"]
			img.set_pixel(x, y, shade)

	# Cross pane divider
	var mid_x = (glass_left + glass_right) / 2
	var mid_y = (glass_top + glass_bot) / 2
	for x in range(glass_left, glass_right):
		img.set_pixel(x, mid_y, palette["frame_white"])
	for y in range(glass_top, glass_bot):
		img.set_pixel(mid_x, y, palette["frame_white"])

	# Glare reflection
	for i in range(3):
		var gx = glass_left + 2 + i
		var gy = glass_top + 1 + i
		if gx < mid_x and gy < mid_y:
			img.set_pixel(gx, gy, palette["glare"])

	# Curtain on right pane
	var curtain_col = Color(0.88, 0.45, 0.42)
	for y in range(glass_top + 1, mid_y):
		img.set_pixel(glass_right - 2, y, curtain_col)
		img.set_pixel(glass_right - 3, y, curtain_col.darkened(0.08))
		if y % 3 == 0:
			img.set_pixel(glass_right - 4, y, curtain_col.darkened(0.15))

	# Window sill
	var sill_y = frame_bot + 2
	for x in range(frame_left - 1, frame_right + 1):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, sill_y, palette["frame_white"])
			if sill_y + 1 < TILE_SIZE:
				img.set_pixel(x, sill_y + 1, palette["frame_white"].darkened(0.12))

	# Flower box below sill
	var box_top = sill_y + 2
	var box_bot = box_top + 3
	for y in range(box_top, box_bot):
		if y >= TILE_SIZE:
			break
		for x in range(frame_left, frame_right):
			var box_shade = Color(0.52, 0.34, 0.18)
			if y == box_top:
				box_shade = Color(0.58, 0.40, 0.22)
			img.set_pixel(x, y, box_shade)

	# Lush flowers
	var flower_colors = [palette["flower_red"], Color(0.95, 0.60, 0.65), palette["flower_red"], Color(0.92, 0.50, 0.55)]
	for i in range(4):
		var fx = frame_left + 3 + i * 5
		var fy = box_top - 1
		if fx >= TILE_SIZE - 3 or fy < 0:
			continue
		img.set_pixel(fx, fy, flower_colors[i])
		if fx > 0:
			img.set_pixel(fx - 1, fy, flower_colors[i].darkened(0.10))
		if fx + 1 < TILE_SIZE:
			img.set_pixel(fx + 1, fy, flower_colors[i].darkened(0.10))
		if fy > 0:
			img.set_pixel(fx, fy - 1, flower_colors[i].lightened(0.12))
		img.set_pixel(fx, fy + 1, Color(0.30, 0.58, 0.25))
		if fx + 1 < TILE_SIZE and fy + 1 < TILE_SIZE:
			img.set_pixel(fx + 1, fy + 1, Color(0.38, 0.65, 0.30))

	# Bottom wall with siding
	for y in range(box_bot, TILE_SIZE):
		for x in range(TILE_SIZE):
			if y < TILE_SIZE:
				img.set_pixel(x, y, wall_col)
				if y % 4 == 0:
					img.set_pixel(x, y, wall_col.darkened(0.10))


## White picket fence on grass background
func _draw_picket_fence(img: Image, palette: Dictionary, variant: int) -> void:
	# Grass background
	img.fill(palette["grass"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 66666

	# Grass texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.5 + y * 0.4 + variant * 1.6) * 0.3 + rng.randf() * 0.15
			if n < -0.1:
				img.set_pixel(x, y, palette["grass_dark"])

	# Two horizontal rails
	var rail_y1 = 12
	var rail_y2 = 22
	for x in range(TILE_SIZE):
		img.set_pixel(x, rail_y1, palette["rail"])
		img.set_pixel(x, rail_y1 + 1, palette["dark"])
		img.set_pixel(x, rail_y2, palette["rail"])
		img.set_pixel(x, rail_y2 + 1, palette["dark"])

	# White pointed pickets every 5 pixels
	var picket_spacing = 5
	for px in range(1, TILE_SIZE, picket_spacing):
		# Picket body
		for y in range(6, TILE_SIZE - 4):
			if px < TILE_SIZE:
				img.set_pixel(px, y, palette["base"])
			if px + 1 < TILE_SIZE:
				img.set_pixel(px + 1, y, palette["light"])
			if px + 2 < TILE_SIZE:
				img.set_pixel(px + 2, y, palette["picket_shadow"])
		# Pointed top
		if px + 1 < TILE_SIZE:
			img.set_pixel(px + 1, 5, palette["light"])
			img.set_pixel(px, 6, palette["base"])
			if px + 2 < TILE_SIZE:
				img.set_pixel(px + 2, 6, palette["picket_shadow"])

	# Picket bottom rests on grass
	for px in range(1, TILE_SIZE, picket_spacing):
		for dx in range(3):
			if px + dx < TILE_SIZE and TILE_SIZE - 4 < TILE_SIZE:
				img.set_pixel(px + dx, TILE_SIZE - 4, palette["deep"])


## Blue USPS mailbox on concrete sidewalk with text detail and brighter colors
func _draw_mailbox(img: Image, palette: Dictionary) -> void:
	# Sidewalk background
	img.fill(palette["concrete"])
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE / 2, palette["concrete"].darkened(0.06))

	# Gray post with shading
	var post_x = TILE_SIZE / 2
	for y in range(18, TILE_SIZE - 2):
		img.set_pixel(post_x - 1, y, palette["post_gray"].darkened(0.12))
		img.set_pixel(post_x, y, palette["post_gray"])
		img.set_pixel(post_x + 1, y, palette["post_gray"].lightened(0.10))

	# Post brace
	for i in range(4):
		var bx = post_x + 2 + i
		var by = TILE_SIZE - 5 - i
		if bx < TILE_SIZE and by >= 0 and by < TILE_SIZE:
			img.set_pixel(bx, by, palette["post_gray"].darkened(0.05))

	# Post base
	for dx in range(-2, 3):
		var bx = post_x + dx
		if bx >= 0 and bx < TILE_SIZE:
			img.set_pixel(bx, TILE_SIZE - 2, palette["post_gray"].darkened(0.15))
			img.set_pixel(bx, TILE_SIZE - 1, palette["post_gray"].darkened(0.22))

	# Blue mailbox body
	var box_left = 5
	var box_right = TILE_SIZE - 5
	var box_top = 3
	var box_bottom = 18

	# Rounded top
	for x in range(box_left + 3, box_right - 3):
		img.set_pixel(x, box_top, palette["light"])
	for x in range(box_left + 2, box_right - 2):
		img.set_pixel(x, box_top + 1, palette["light"])
	for x in range(box_left + 1, box_right - 1):
		img.set_pixel(x, box_top + 2, palette["mid"])

	# Main body with cylindrical shading
	for y in range(box_top + 3, box_bottom):
		for x in range(box_left, box_right):
			var rel_x = float(x - box_left) / float(box_right - box_left)
			var shade: Color
			if rel_x < 0.12:
				shade = palette["deep"]
			elif rel_x < 0.25:
				shade = palette["dark"]
			elif rel_x < 0.40:
				shade = palette["mid"]
			elif rel_x < 0.65:
				shade = palette["light"]
			elif rel_x < 0.80:
				shade = palette["mid"]
			elif rel_x < 0.90:
				shade = palette["dark"]
			else:
				shade = palette["deep"]
			img.set_pixel(x, y, shade)

	# Mail slot
	for x in range(box_left + 3, box_right - 3):
		img.set_pixel(x, box_top + 5, palette["slot"])

	# "US MAIL" text dots
	var text_y_pos = box_top + 8
	var text_dots = [
		Vector2i(9, 0), Vector2i(9, 1), Vector2i(9, 2), Vector2i(10, 2), Vector2i(11, 0), Vector2i(11, 1), Vector2i(11, 2),
		Vector2i(13, 0), Vector2i(14, 0), Vector2i(13, 1), Vector2i(14, 2), Vector2i(13, 2),
		Vector2i(17, 0), Vector2i(17, 1), Vector2i(17, 2), Vector2i(18, 0), Vector2i(19, 1), Vector2i(20, 0), Vector2i(20, 1), Vector2i(20, 2),
	]
	for dot in text_dots:
		var tx = dot.x
		var ty = text_y_pos + dot.y
		if tx >= 0 and tx < TILE_SIZE and ty >= 0 and ty < TILE_SIZE:
			img.set_pixel(tx, ty, Color(0.85, 0.85, 0.90))

	# Highlight streak
	for y in range(box_top + 4, box_bottom - 2):
		img.set_pixel(box_left + 3, y, palette["light"].lightened(0.12))

	# Red flag
	var flag_x = box_right
	var flag_y = box_top + 4
	img.set_pixel(flag_x, flag_y, palette["flag_red"].darkened(0.2))
	img.set_pixel(flag_x, flag_y + 1, palette["flag_red"].darkened(0.2))
	img.set_pixel(flag_x, flag_y + 2, palette["flag_red"].darkened(0.2))
	if flag_x + 1 < TILE_SIZE:
		img.set_pixel(flag_x + 1, flag_y, palette["flag_red"])
		img.set_pixel(flag_x + 1, flag_y + 1, palette["flag_red"])
	if flag_x + 2 < TILE_SIZE:
		img.set_pixel(flag_x + 2, flag_y, palette["flag_red"])
		img.set_pixel(flag_x + 2, flag_y + 1, palette["flag_red"].lightened(0.1))
	if flag_x + 3 < TILE_SIZE:
		img.set_pixel(flag_x + 3, flag_y, palette["flag_red"].lightened(0.08))

	for x in range(box_left, box_right):
		img.set_pixel(x, box_bottom - 1, palette["deep"])


## Red fire hydrant on sidewalk
func _draw_fire_hydrant(img: Image, palette: Dictionary) -> void:
	# Sidewalk background
	img.fill(palette["concrete"])

	var cx = TILE_SIZE / 2
	var body_top = 8
	var body_bottom = TILE_SIZE - 4

	# Hydrant body (center column)
	for y in range(body_top, body_bottom):
		for dx in range(-3, 4):
			var px = cx + dx
			if px >= 0 and px < TILE_SIZE:
				var shade = palette["base"]
				if dx <= -2:
					shade = palette["dark"]
				elif dx >= 2:
					shade = palette["dark"]
				elif dx == -1:
					shade = palette["mid"]
				elif dx == 1:
					shade = palette["mid"]
				else:
					shade = palette["light"]
				img.set_pixel(px, y, shade)

	# Cap on top (wider)
	for dx in range(-4, 5):
		var px = cx + dx
		if px >= 0 and px < TILE_SIZE:
			img.set_pixel(px, body_top - 1, palette["cap"])
			img.set_pixel(px, body_top, palette["cap"].darkened(0.1))
	# Very top cap (narrower)
	for dx in range(-2, 3):
		var px = cx + dx
		if px >= 0 and px < TILE_SIZE:
			img.set_pixel(px, body_top - 2, palette["cap"])
			img.set_pixel(px, body_top - 3, palette["cap"].lightened(0.1))

	# Side nozzles
	for dy in range(-1, 2):
		var ny = cx + dy + 2
		# Left nozzle
		if cx - 5 >= 0 and ny >= 0 and ny < TILE_SIZE:
			img.set_pixel(cx - 4, ny, palette["nozzle"])
			img.set_pixel(cx - 5, ny, palette["nozzle"].darkened(0.15))
		# Right nozzle
		if cx + 5 < TILE_SIZE and ny >= 0 and ny < TILE_SIZE:
			img.set_pixel(cx + 4, ny, palette["nozzle"])
			img.set_pixel(cx + 5, ny, palette["nozzle"].darkened(0.15))

	# Base (wider, bolted to ground)
	for dx in range(-4, 5):
		var px = cx + dx
		if px >= 0 and px < TILE_SIZE:
			img.set_pixel(px, body_bottom, palette["deep"])
			img.set_pixel(px, body_bottom + 1, palette["deep"].darkened(0.1))

	# Highlight reflection
	img.set_pixel(cx - 1, body_top + 2, palette["highlight"])
	img.set_pixel(cx - 1, body_top + 3, palette["highlight"])


## Sand base playground with recognizable slide, swing set, and monkey bar details
func _draw_playground(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 77777

	# Sand texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.8 + y * 0.6 + variant * 1.4) * 0.25 + rng.randf() * 0.2
			if n < -0.15:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Red slide (platform + diagonal chute)
	for x in range(22, 28):
		for y in range(3, 7):
			img.set_pixel(x, y, palette["slide_red"].darkened(0.1))
	for y in range(7, TILE_SIZE - 3):
		img.set_pixel(22, y, palette["chain_gray"])
		img.set_pixel(27, y, palette["chain_gray"])
	for i in range(18):
		var sx = 21 - i
		var sy = 6 + int(i * 1.2)
		if sx >= 0 and sx < TILE_SIZE and sy >= 0 and sy < TILE_SIZE:
			img.set_pixel(sx, sy, palette["slide_red"])
			if sx + 1 < TILE_SIZE:
				img.set_pixel(sx + 1, sy, palette["slide_red"].lightened(0.12))
			if sy - 1 >= 0:
				img.set_pixel(sx, sy - 1, palette["slide_red"].darkened(0.18))

	# Blue swing set (A-frame + chains + seats)
	var sw_left = 2
	var sw_right = 14
	var sw_top = 3
	for x in range(sw_left, sw_right + 1):
		img.set_pixel(x, sw_top, palette["swing_blue"])
		img.set_pixel(x, sw_top + 1, palette["swing_blue"].darkened(0.1))
	for y in range(sw_top + 2, TILE_SIZE - 3):
		img.set_pixel(sw_left, y, palette["swing_blue"])
		img.set_pixel(sw_left + 1, y, palette["swing_blue"].darkened(0.12))
	for y in range(sw_top + 2, TILE_SIZE - 3):
		img.set_pixel(sw_right - 1, y, palette["swing_blue"])
		img.set_pixel(sw_right, y, palette["swing_blue"].darkened(0.12))
	var seat1_x = sw_left + 3
	for y in range(sw_top + 2, 18):
		img.set_pixel(seat1_x, y, palette["chain_gray"])
	for dx in range(-1, 3):
		if seat1_x + dx >= 0 and seat1_x + dx < TILE_SIZE:
			img.set_pixel(seat1_x + dx, 18, palette["swing_blue"].darkened(0.25))
	var seat2_x = sw_right - 3
	for y in range(sw_top + 2, 16):
		img.set_pixel(seat2_x, y, palette["chain_gray"])
	for dx in range(-1, 3):
		if seat2_x + dx >= 0 and seat2_x + dx < TILE_SIZE:
			img.set_pixel(seat2_x + dx, 16, palette["swing_blue"].darkened(0.25))

	# Yellow monkey bars (bottom area)
	var mb_left = 16
	var mb_right = 30
	var mb_y = TILE_SIZE - 10
	for y in range(mb_y, TILE_SIZE - 3):
		img.set_pixel(mb_left, y, palette["bar_yellow"])
		img.set_pixel(mb_right, y, palette["bar_yellow"])
	for x in range(mb_left, mb_right + 1):
		img.set_pixel(x, mb_y, palette["bar_yellow"])
	for x in range(mb_left + 2, mb_right, 3):
		img.set_pixel(x, mb_y + 1, palette["bar_yellow"].darkened(0.1))

	# Footprints in sand
	if variant % 3 == 0:
		for _f in range(2):
			var fx = rng.randi_range(4, TILE_SIZE - 6)
			var fy = rng.randi_range(TILE_SIZE - 6, TILE_SIZE - 2)
			if fx < TILE_SIZE and fy < TILE_SIZE:
				img.set_pixel(fx, fy, palette["dark"].darkened(0.05))
				if fx + 1 < TILE_SIZE:
					img.set_pixel(fx + 1, fy, palette["dark"].darkened(0.05))


## Gray parking lot with yellow lines and oil stains
func _draw_parking_lot(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 88888

	# Asphalt texture noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 1.2 + y * 0.9 + variant * 2.2) * 0.25 + rng.randf() * 0.18
			if n < -0.15:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Scattered gravel
	for _i in range(4):
		var gx = rng.randi_range(0, TILE_SIZE - 1)
		var gy = rng.randi_range(0, TILE_SIZE - 1)
		img.set_pixel(gx, gy, palette["gravel"])

	# Yellow parking lines (vertical every 10 pixels)
	for lx_base in range(0, TILE_SIZE, 10):
		for y in range(TILE_SIZE):
			if lx_base < TILE_SIZE:
				img.set_pixel(lx_base, y, palette["line_yellow"])
			if lx_base + 1 < TILE_SIZE:
				img.set_pixel(lx_base + 1, y, palette["line_yellow"].darkened(0.1))

	# Oil stain spots
	if variant % 2 == 0:
		for _s in range(rng.randi_range(1, 3)):
			var ox = rng.randi_range(3, TILE_SIZE - 5)
			var oy = rng.randi_range(3, TILE_SIZE - 5)
			for dy in range(3):
				for dx in range(3):
					if ox + dx < TILE_SIZE and oy + dy < TILE_SIZE:
						if rng.randf() < 0.65:
							var stain_col = palette["oil_stain"] if rng.randf() > 0.3 else palette["oil_rainbow"]
							img.set_pixel(ox + dx, oy + dy, stain_col)


## Green tree canopy on brown trunk with grass background
func _draw_shade_tree(img: Image, palette: Dictionary) -> void:
	# Grass background
	img.fill(palette["grass"])

	# Grass texture
	var rng = RandomNumberGenerator.new()
	rng.seed = 12012
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.5 + y * 0.4) * 0.25 + rng.randf() * 0.12
			if n < -0.1:
				img.set_pixel(x, y, palette["grass_dark"])

	# Brown trunk (bottom center, 4 pixels wide)
	var trunk_x = TILE_SIZE / 2
	for y in range(TILE_SIZE - 10, TILE_SIZE - 1):
		for dx in range(-1, 3):
			var px = trunk_x + dx
			if px >= 0 and px < TILE_SIZE:
				var shade = palette["trunk"]
				if dx <= 0:
					shade = palette["trunk_dark"]
				img.set_pixel(px, y, shade)

	# Trunk base wider
	for dx in range(-2, 4):
		var px = trunk_x + dx
		if px >= 0 and px < TILE_SIZE:
			img.set_pixel(px, TILE_SIZE - 1, palette["trunk_dark"])

	# Large round green canopy (top portion)
	var canopy_cx = TILE_SIZE / 2 + 1
	var canopy_cy = 10
	var canopy_r = 10
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - canopy_cx, 2) + pow(y - canopy_cy, 2))
			if dist < canopy_r:
				var depth = dist / canopy_r
				var shade: Color
				if depth < 0.3:
					shade = palette["light"]
				elif depth < 0.5:
					shade = palette["mid"]
				elif depth < 0.7:
					shade = palette["base"]
				elif depth < 0.85:
					shade = palette["dark"]
				else:
					shade = palette["deep"]
				# Add some leaf noise
				var leaf_n = sin(x * 1.5 + y * 1.2) * 0.15 + rng.randf() * 0.1
				if leaf_n > 0.12:
					shade = shade.lightened(0.08)
				elif leaf_n < -0.1:
					shade = shade.darkened(0.08)
				img.set_pixel(x, y, shade)

	# Shadow on ground beneath canopy
	for x in range(trunk_x - 4, trunk_x + 6):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, TILE_SIZE - 2, palette["grass_dark"])


## Brown park bench with wood-grain slats, iron arm supports, and grass detail
func _draw_park_bench(img: Image, palette: Dictionary) -> void:
	# Grass background
	img.fill(palette["grass"])

	var rng = RandomNumberGenerator.new()
	rng.seed = 13013
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.6 + y * 0.3) * 0.25 + rng.randf() * 0.12
			if n < -0.1:
				img.set_pixel(x, y, palette["grass_dark"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["grass"].lightened(0.08))

	# Grass blade tufts
	for _i in range(4):
		var tx = rng.randi_range(1, TILE_SIZE - 2)
		var ty = rng.randi_range(TILE_SIZE - 4, TILE_SIZE - 1)
		for h in range(rng.randi_range(1, 3)):
			if ty - h >= 0:
				img.set_pixel(tx, ty - h, palette["grass"].lightened(0.1))

	var bench_left = 3
	var bench_right = TILE_SIZE - 4
	var seat_y = 14

	# Iron supports
	for y in range(8, TILE_SIZE - 4):
		img.set_pixel(bench_left, y, palette["iron_gray"])
		img.set_pixel(bench_left + 1, y, palette["iron_light"])
	for y in range(8, TILE_SIZE - 4):
		img.set_pixel(bench_right, y, palette["iron_gray"])
		img.set_pixel(bench_right + 1, y, palette["iron_light"])
	img.set_pixel(bench_left + 2, 8, palette["iron_gray"])
	img.set_pixel(bench_left + 2, 9, palette["iron_gray"])
	img.set_pixel(bench_right - 1, 8, palette["iron_gray"])
	img.set_pixel(bench_right - 1, 9, palette["iron_gray"])

	# Iron feet
	for pos_x in [bench_left, bench_right]:
		for dx in range(-1, 3):
			var lx = pos_x + dx
			if lx >= 0 and lx < TILE_SIZE:
				img.set_pixel(lx, TILE_SIZE - 4, palette["iron_gray"].darkened(0.10))
				img.set_pixel(lx, TILE_SIZE - 3, palette["iron_gray"].darkened(0.18))

	# Seat slats with wood grain
	var slat_ys = [seat_y, seat_y + 3, seat_y + 6]
	for si in range(slat_ys.size()):
		var sy = slat_ys[si]
		for x in range(bench_left, bench_right + 2):
			if x < 0 or x >= TILE_SIZE:
				continue
			for dy in range(2):
				var py = sy + dy
				if py < 0 or py >= TILE_SIZE:
					continue
				var shade = palette["base"]
				var grain = sin(x * 0.3 + si * 2.0) * 0.1
				if grain > 0.05:
					shade = shade.lightened(0.06)
				elif grain < -0.05:
					shade = shade.darkened(0.06)
				if dy == 0:
					shade = shade.lightened(0.08)
				img.set_pixel(x, py, shade)
			if sy + 2 < TILE_SIZE:
				img.set_pixel(x, sy + 2, palette["dark"])

	# Backrest
	var back_ys = [8, 11]
	for bi in range(back_ys.size()):
		var by = back_ys[bi]
		for x in range(bench_left + 2, bench_right):
			if x < 0 or x >= TILE_SIZE:
				continue
			var shade = palette["mid"]
			var grain = sin(x * 0.35 + bi * 1.5) * 0.08
			if grain > 0.04:
				shade = shade.lightened(0.05)
			elif grain < -0.04:
				shade = shade.darkened(0.05)
			if by >= 0 and by < TILE_SIZE:
				img.set_pixel(x, by, shade.lightened(0.06))
			if by + 1 < TILE_SIZE:
				img.set_pixel(x, by + 1, shade)
			if by + 2 < TILE_SIZE:
				img.set_pixel(x, by + 2, palette["dark"])

	# Shadow beneath bench
	for x in range(bench_left - 1, bench_right + 3):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, TILE_SIZE - 2, palette["grass_dark"])


## Orange basketball court surface with white lines
func _draw_basketball_court(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 99999

	# Court surface texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.4 + y * 0.3 + variant * 1.6) * 0.2 + rng.randf() * 0.1
			if n < -0.1:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.15:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Center line (vertical through middle)
	for y in range(TILE_SIZE):
		img.set_pixel(TILE_SIZE / 2, y, palette["line_white"])
		img.set_pixel(TILE_SIZE / 2 + 1, y, palette["line_shadow"])

	# Border lines (all four edges)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["line_white"])
		img.set_pixel(x, 1, palette["line_shadow"])
		img.set_pixel(x, TILE_SIZE - 1, palette["line_white"])
		img.set_pixel(x, TILE_SIZE - 2, palette["line_shadow"])
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["line_white"])
		img.set_pixel(1, y, palette["line_shadow"])
		img.set_pixel(TILE_SIZE - 1, y, palette["line_white"])
		img.set_pixel(TILE_SIZE - 2, y, palette["line_shadow"])

	# Free throw arc (partial circle on left side)
	var arc_cx = 0
	var arc_cy = TILE_SIZE / 2
	var arc_r = 12
	for angle in range(-60, 61, 3):
		var rad = deg_to_rad(angle)
		var ax = arc_cx + int(cos(rad) * arc_r)
		var ay = arc_cy + int(sin(rad) * arc_r)
		if ax >= 0 and ax < TILE_SIZE and ay >= 0 and ay < TILE_SIZE:
			img.set_pixel(ax, ay, palette["line_white"])

	# Center circle hint
	var cc_cx = TILE_SIZE / 2
	var cc_cy = TILE_SIZE / 2
	var cc_r = 6
	for angle in range(0, 360, 8):
		var rad = deg_to_rad(angle)
		var rx = cc_cx + int(cos(rad) * cc_r)
		var ry = cc_cy + int(sin(rad) * cc_r)
		if rx >= 0 and rx < TILE_SIZE and ry >= 0 and ry < TILE_SIZE:
			img.set_pixel(rx, ry, palette["line_white"])


## Dark soil base with lush multicolor flowers, leaf pairs, and stone border edging
func _draw_flower_bed(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 10101

	# Rich soil texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.9 + y * 0.7 + variant * 1.5) * 0.3 + rng.randf() * 0.2
			if n < -0.2:
				img.set_pixel(x, y, palette["deep"])
			elif n < -0.05:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.25:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.1:
				img.set_pixel(x, y, palette["mid"])

	# Stone border edging
	var border_col = Color(0.62, 0.60, 0.56)
	var border_dark = Color(0.48, 0.46, 0.42)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, border_col)
		img.set_pixel(x, 1, border_dark)
		img.set_pixel(x, TILE_SIZE - 2, border_dark)
		img.set_pixel(x, TILE_SIZE - 1, border_col)
		if x % 6 == 0:
			img.set_pixel(x, 0, border_dark.darkened(0.1))
			img.set_pixel(x, 1, border_dark.darkened(0.1))
			img.set_pixel(x, TILE_SIZE - 2, border_dark.darkened(0.1))
			img.set_pixel(x, TILE_SIZE - 1, border_dark.darkened(0.1))

	# Multicolor flowers with fuller petals
	var flower_colors = [
		palette["flower_red"], palette["flower_pink"],
		palette["flower_yellow"], palette["flower_purple"],
		Color(0.98, 0.65, 0.20),
		Color(0.55, 0.65, 0.95)
	]
	var num_flowers = rng.randi_range(7, 12)
	for _f in range(num_flowers):
		var fx = rng.randi_range(3, TILE_SIZE - 4)
		var fy = rng.randi_range(5, TILE_SIZE - 7)
		var fc = flower_colors[rng.randi() % flower_colors.size()]

		var stem_h = rng.randi_range(3, 4)
		var stem_col = Color(0.28, 0.55, 0.22)
		for s in range(stem_h):
			if fy + s + 1 < TILE_SIZE - 2:
				img.set_pixel(fx, fy + s + 1, stem_col)

		if fy + 2 < TILE_SIZE - 2:
			if fx - 1 >= 0:
				img.set_pixel(fx - 1, fy + 2, Color(0.35, 0.62, 0.28))
			if fx + 1 < TILE_SIZE:
				img.set_pixel(fx + 1, fy + 3 if fy + 3 < TILE_SIZE - 2 else fy + 2, Color(0.35, 0.62, 0.28))

		img.set_pixel(fx, fy, fc.lightened(0.15))
		if fx > 0:
			img.set_pixel(fx - 1, fy, fc)
		if fx + 1 < TILE_SIZE:
			img.set_pixel(fx + 1, fy, fc)
		if fy > 2:
			img.set_pixel(fx, fy - 1, fc)
		img.set_pixel(fx, fy + 1, fc.darkened(0.08))
		if rng.randf() < 0.5:
			if fx - 1 >= 0 and fy > 2:
				img.set_pixel(fx - 1, fy - 1, fc.darkened(0.12))
			if fx + 1 < TILE_SIZE and fy > 2:
				img.set_pixel(fx + 1, fy - 1, fc.darkened(0.12))

	for _m in range(rng.randi_range(3, 6)):
		var mx = rng.randi_range(2, TILE_SIZE - 3)
		var my = rng.randi_range(TILE_SIZE - 6, TILE_SIZE - 3)
		img.set_pixel(mx, my, palette["light"])


## Create tileset with all suburban tiles
func create_tileset() -> TileSet:
	print("Creating suburban neighborhood tileset...")
	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer for collision
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)
	tileset.set_physics_layer_collision_mask(0, 1)

	# Create atlas source from generated tiles
	var atlas = TileSetAtlasSource.new()

	# 4x4 atlas (16 tiles)
	var atlas_cols = 4
	var atlas_rows = 4
	var atlas_img = Image.create(TILE_SIZE * atlas_cols, TILE_SIZE * atlas_rows, false, Image.FORMAT_RGBA8)

	# Tile order matching enum
	var tile_order = [
		# Row 0: Ground/structure
		TileType.SIDEWALK, TileType.ROAD, TileType.HOUSE_WALL, TileType.LAWN,
		# Row 1: Buildings
		TileType.STORE_FRONT, TileType.HOUSE_DOOR, TileType.HOUSE_WINDOW, TileType.PICKET_FENCE,
		# Row 2: Props
		TileType.MAILBOX, TileType.FIRE_HYDRANT, TileType.PLAYGROUND, TileType.PARKING_LOT,
		# Row 3: Nature/rec
		TileType.SHADE_TREE, TileType.PARK_BENCH, TileType.BASKETBALL_COURT, TileType.FLOWER_BED
	]

	# Impassable tile types (need collision)
	var impassable_types = [
		TileType.HOUSE_WALL, TileType.STORE_FRONT, TileType.HOUSE_WINDOW,
		TileType.PICKET_FENCE, TileType.MAILBOX, TileType.FIRE_HYDRANT,
		TileType.SHADE_TREE, TileType.PARK_BENCH
	]

	for i in range(tile_order.size()):
		var tile_type = tile_order[i]
		var tile_tex = generate_tile(tile_type, 0)
		var tile_img = tile_tex.get_image()

		var atlas_x = (i % atlas_cols) * TILE_SIZE
		var atlas_y = (i / atlas_cols) * TILE_SIZE

		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				atlas_img.set_pixel(atlas_x + x, atlas_y + y, tile_img.get_pixel(x, y))

	var atlas_texture = ImageTexture.create_from_image(atlas_img)
	atlas.texture = atlas_texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Debug: Save atlas to disk
	atlas_img.save_png("user://debug_suburban_atlas.png")
	print("Suburban atlas saved (size: %dx%d, %d tiles)" % [atlas_img.get_width(), atlas_img.get_height(), tile_order.size()])

	# Create all tiles in atlas
	for i in range(tile_order.size()):
		var coords = Vector2i(i % atlas_cols, i / atlas_cols)
		atlas.create_tile(coords)

	# Add atlas source to tileset
	tileset.add_source(atlas)

	# Add collision for impassable tiles
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
	# Direct mapping: enum value = tile index in 4-column atlas
	return type


## Get atlas coordinates for a tile ID (for 4-column layout)
static func get_atlas_coords_for_id(tile_id: int) -> Vector2i:
	return Vector2i(tile_id % 4, tile_id / 4)
