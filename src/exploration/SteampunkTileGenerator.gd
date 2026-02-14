extends Node
class_name SteampunkTileGenerator

## SteampunkTileGenerator - Procedurally generates 32x32 urban/industrial tiles
## 90s suburban/EarthBound aesthetic with steampunk industrial elements

const TILE_SIZE: int = 32

## Tile types for Area 3 (Steampunk/EarthBound 90s suburban-industrial setting)
enum TileType {
	CONCRETE,       # 0 - gray sidewalk with crack details
	ASPHALT,        # 1 - dark road surface with lane markings
	BRICK_WALL,     # 2 - red/brown brick pattern (impassable)
	METAL_FLOOR,    # 3 - riveted steel floor
	PIPE,           # 4 - industrial piping (impassable)
	PARK_GRASS,     # 5 - green park grass with flowers
	BUILDING_WALL,  # 6 - city building wall (impassable)
	DOOR,           # 7 - building entrance
	WINDOW,         # 8 - decorative (impassable)
	RAIL_TRACK,     # 9 - train tracks
	NEON_SIGN,      # 10 - decorative neon accent (impassable)
	WATER_FEATURE,  # 11 - fountain/pond
	FENCE,          # 12 - park/yard fence (impassable)
	ALLEY,          # 13 - narrow passageway
	LAMPPOST,       # 14 - street light (impassable)
	MANHOLE         # 15 - manhole cover (special tile)
}

## 90s suburban-industrial color palettes
const PALETTES: Dictionary = {
	TileType.CONCRETE: {
		"base": Color(0.62, 0.60, 0.58),
		"light": Color(0.72, 0.70, 0.68),
		"mid": Color(0.66, 0.64, 0.62),
		"dark": Color(0.50, 0.48, 0.46),
		"deep": Color(0.40, 0.38, 0.36),
		"crack": Color(0.45, 0.42, 0.40),
		"crack_light": Color(0.68, 0.66, 0.64),
		"stain": Color(0.52, 0.50, 0.48),
		"gum": Color(0.30, 0.28, 0.28)
	},
	TileType.ASPHALT: {
		"base": Color(0.25, 0.25, 0.28),
		"light": Color(0.35, 0.35, 0.38),
		"mid": Color(0.30, 0.30, 0.32),
		"dark": Color(0.18, 0.18, 0.20),
		"deep": Color(0.12, 0.12, 0.14),
		"lane_yellow": Color(0.85, 0.75, 0.20),
		"lane_white": Color(0.88, 0.88, 0.85),
		"pothole": Color(0.15, 0.14, 0.16),
		"gravel": Color(0.38, 0.36, 0.34)
	},
	TileType.BRICK_WALL: {
		"base": Color(0.60, 0.30, 0.20),
		"light": Color(0.72, 0.40, 0.28),
		"mid": Color(0.65, 0.34, 0.24),
		"dark": Color(0.48, 0.22, 0.14),
		"deep": Color(0.35, 0.15, 0.10),
		"mortar": Color(0.72, 0.68, 0.62),
		"mortar_dark": Color(0.58, 0.54, 0.48),
		"stain": Color(0.42, 0.25, 0.18),
		"moss": Color(0.30, 0.42, 0.22)
	},
	TileType.METAL_FLOOR: {
		"base": Color(0.50, 0.52, 0.55),
		"light": Color(0.65, 0.67, 0.70),
		"mid": Color(0.56, 0.58, 0.60),
		"dark": Color(0.38, 0.40, 0.42),
		"deep": Color(0.28, 0.30, 0.32),
		"rivet": Color(0.42, 0.44, 0.46),
		"rivet_light": Color(0.72, 0.74, 0.76),
		"rust": Color(0.55, 0.35, 0.20),
		"seam": Color(0.32, 0.34, 0.36)
	},
	TileType.PIPE: {
		"base": Color(0.45, 0.42, 0.38),
		"light": Color(0.62, 0.58, 0.52),
		"mid": Color(0.52, 0.48, 0.44),
		"dark": Color(0.32, 0.30, 0.28),
		"deep": Color(0.22, 0.20, 0.18),
		"copper": Color(0.72, 0.45, 0.22),
		"copper_light": Color(0.85, 0.58, 0.32),
		"steam": Color(0.85, 0.88, 0.90),
		"joint": Color(0.55, 0.52, 0.48)
	},
	TileType.PARK_GRASS: {
		"base": Color(0.28, 0.58, 0.24),
		"light": Color(0.42, 0.72, 0.36),
		"mid": Color(0.34, 0.64, 0.28),
		"dark": Color(0.18, 0.44, 0.14),
		"deep": Color(0.12, 0.32, 0.08),
		"flower_red": Color(0.88, 0.25, 0.22),
		"flower_yellow": Color(0.92, 0.85, 0.25),
		"flower_white": Color(0.95, 0.95, 0.92),
		"soil": Color(0.48, 0.38, 0.24)
	},
	TileType.BUILDING_WALL: {
		"base": Color(0.55, 0.52, 0.48),
		"light": Color(0.68, 0.65, 0.60),
		"mid": Color(0.60, 0.58, 0.54),
		"dark": Color(0.42, 0.40, 0.36),
		"deep": Color(0.32, 0.30, 0.28),
		"trim": Color(0.72, 0.70, 0.65),
		"shadow": Color(0.28, 0.26, 0.24),
		"accent": Color(0.48, 0.35, 0.28)
	},
	TileType.DOOR: {
		"base": Color(0.45, 0.30, 0.18),
		"light": Color(0.58, 0.42, 0.28),
		"mid": Color(0.50, 0.35, 0.22),
		"dark": Color(0.32, 0.22, 0.12),
		"deep": Color(0.05, 0.04, 0.03),
		"frame": Color(0.55, 0.52, 0.48),
		"frame_light": Color(0.68, 0.65, 0.60),
		"handle": Color(0.75, 0.65, 0.25),
		"step": Color(0.58, 0.56, 0.52)
	},
	TileType.WINDOW: {
		"base": Color(0.35, 0.50, 0.65),
		"light": Color(0.55, 0.70, 0.85),
		"mid": Color(0.42, 0.58, 0.72),
		"dark": Color(0.25, 0.38, 0.52),
		"deep": Color(0.15, 0.25, 0.38),
		"frame": Color(0.58, 0.55, 0.50),
		"frame_light": Color(0.72, 0.68, 0.62),
		"curtain": Color(0.72, 0.35, 0.28),
		"glare": Color(0.92, 0.95, 1.0)
	},
	TileType.RAIL_TRACK: {
		"base": Color(0.48, 0.42, 0.35),
		"light": Color(0.58, 0.52, 0.45),
		"mid": Color(0.52, 0.46, 0.38),
		"dark": Color(0.35, 0.30, 0.25),
		"deep": Color(0.25, 0.22, 0.18),
		"rail": Color(0.55, 0.55, 0.58),
		"rail_light": Color(0.72, 0.72, 0.75),
		"tie": Color(0.38, 0.28, 0.18),
		"gravel": Color(0.52, 0.48, 0.42)
	},
	TileType.NEON_SIGN: {
		"base": Color(0.22, 0.20, 0.25),
		"light": Color(0.35, 0.32, 0.38),
		"mid": Color(0.28, 0.25, 0.30),
		"dark": Color(0.15, 0.14, 0.18),
		"deep": Color(0.08, 0.08, 0.10),
		"neon_teal": Color(0.20, 0.80, 0.70),
		"neon_magenta": Color(0.85, 0.20, 0.60),
		"neon_glow": Color(0.40, 0.90, 0.82),
		"neon_pink_glow": Color(0.92, 0.40, 0.72)
	},
	TileType.WATER_FEATURE: {
		"base": Color(0.22, 0.48, 0.72),
		"light": Color(0.38, 0.62, 0.85),
		"mid": Color(0.28, 0.54, 0.78),
		"dark": Color(0.15, 0.35, 0.55),
		"deep": Color(0.08, 0.22, 0.42),
		"foam": Color(0.85, 0.90, 0.95),
		"sparkle": Color(1.0, 1.0, 1.0),
		"stone": Color(0.55, 0.52, 0.48),
		"stone_dark": Color(0.42, 0.40, 0.38)
	},
	TileType.FENCE: {
		"base": Color(0.52, 0.38, 0.22),
		"light": Color(0.65, 0.50, 0.32),
		"mid": Color(0.58, 0.44, 0.28),
		"dark": Color(0.38, 0.28, 0.15),
		"deep": Color(0.28, 0.20, 0.10),
		"post": Color(0.60, 0.45, 0.28),
		"post_light": Color(0.72, 0.58, 0.38),
		"grass": Color(0.28, 0.52, 0.22),
		"grass_dark": Color(0.18, 0.38, 0.14)
	},
	TileType.ALLEY: {
		"base": Color(0.35, 0.33, 0.32),
		"light": Color(0.45, 0.43, 0.42),
		"mid": Color(0.38, 0.36, 0.35),
		"dark": Color(0.25, 0.23, 0.22),
		"deep": Color(0.15, 0.14, 0.14),
		"puddle": Color(0.22, 0.30, 0.42),
		"trash": Color(0.42, 0.38, 0.32),
		"shadow": Color(0.12, 0.11, 0.12),
		"grime": Color(0.30, 0.28, 0.25)
	},
	TileType.LAMPPOST: {
		"base": Color(0.35, 0.38, 0.40),
		"light": Color(0.52, 0.55, 0.58),
		"mid": Color(0.42, 0.45, 0.48),
		"dark": Color(0.25, 0.28, 0.30),
		"deep": Color(0.18, 0.20, 0.22),
		"lamp_glow": Color(1.0, 0.92, 0.60),
		"lamp_bright": Color(1.0, 0.98, 0.85),
		"glass": Color(0.82, 0.78, 0.55),
		"concrete": Color(0.58, 0.56, 0.54)
	},
	TileType.MANHOLE: {
		"base": Color(0.42, 0.42, 0.44),
		"light": Color(0.55, 0.55, 0.58),
		"mid": Color(0.48, 0.48, 0.50),
		"dark": Color(0.30, 0.30, 0.32),
		"deep": Color(0.18, 0.18, 0.20),
		"ring": Color(0.52, 0.50, 0.48),
		"hole": Color(0.05, 0.04, 0.05),
		"rim": Color(0.60, 0.58, 0.55),
		"concrete": Color(0.62, 0.60, 0.58)
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
	var palette = PALETTES.get(type, PALETTES[TileType.CONCRETE])

	match type:
		TileType.CONCRETE:
			_draw_concrete(img, palette, variant)
		TileType.ASPHALT:
			_draw_asphalt(img, palette, variant)
		TileType.BRICK_WALL:
			_draw_brick_wall(img, palette, variant)
		TileType.METAL_FLOOR:
			_draw_metal_floor(img, palette, variant)
		TileType.PIPE:
			_draw_pipe(img, palette, variant)
		TileType.PARK_GRASS:
			_draw_park_grass(img, palette, variant)
		TileType.BUILDING_WALL:
			_draw_building_wall(img, palette, variant)
		TileType.DOOR:
			_draw_door(img, palette)
		TileType.WINDOW:
			_draw_window(img, palette)
		TileType.RAIL_TRACK:
			_draw_rail_track(img, palette, variant)
		TileType.NEON_SIGN:
			_draw_neon_sign(img, palette, variant)
		TileType.WATER_FEATURE:
			_draw_water_feature(img, palette, variant)
		TileType.FENCE:
			_draw_fence(img, palette, variant)
		TileType.ALLEY:
			_draw_alley(img, palette, variant)
		TileType.LAMPPOST:
			_draw_lamppost(img, palette)
		TileType.MANHOLE:
			_draw_manhole(img, palette)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## Concrete sidewalk with crack details and weathering
func _draw_concrete(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	# Base texture noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.6 + variant * 1.3) * cos(y * 0.5 + variant * 0.7)
			var n2 = sin(x * 1.2 + y * 0.8 + variant * 2.0) * 0.3
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.15
			if combined < -0.2:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.25:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.1:
				img.set_pixel(x, y, palette["mid"])

	# Sidewalk grid lines (every 16 pixels)
	for x in range(TILE_SIZE):
		if x % 16 == 0 or x % 16 == 1:
			for y in range(TILE_SIZE):
				img.set_pixel(x, y, palette["crack"])
	for y in range(TILE_SIZE):
		if y % 16 == 0 or y % 16 == 1:
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, palette["crack"])

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
				# Highlight next to crack
				if px + 1 < TILE_SIZE:
					img.set_pixel(px + 1, py, palette["crack_light"])

	# Stain patches
	if variant % 3 == 0:
		var sx = rng.randi_range(3, TILE_SIZE - 6)
		var sy = rng.randi_range(3, TILE_SIZE - 6)
		for dy in range(3):
			for dx in range(3):
				if rng.randf() < 0.6 and sx + dx < TILE_SIZE and sy + dy < TILE_SIZE:
					img.set_pixel(sx + dx, sy + dy, palette["stain"])

	# Gum spots
	if variant % 5 == 0:
		var gx = rng.randi_range(2, TILE_SIZE - 3)
		var gy = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(gx, gy, palette["gum"])
		img.set_pixel(gx + 1, gy, palette["gum"])


## Asphalt road surface with lane markings
func _draw_asphalt(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 22222

	# Road texture - gravel noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 1.8 + y * 1.4 + variant * 3.0) * 0.3 + rng.randf() * 0.25
			if n < -0.15:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Scattered gravel spots
	for _i in range(8):
		var gx = rng.randi_range(0, TILE_SIZE - 1)
		var gy = rng.randi_range(0, TILE_SIZE - 1)
		img.set_pixel(gx, gy, palette["gravel"])

	# Lane markings (dashed yellow center line on variant 0, white edge on variant 1)
	if variant % 4 == 0:
		# Center dashed yellow line
		for y in range(TILE_SIZE):
			if (y / 4) % 2 == 0:
				img.set_pixel(15, y, palette["lane_yellow"])
				img.set_pixel(16, y, palette["lane_yellow"])
	elif variant % 4 == 1:
		# Solid white edge line
		for y in range(TILE_SIZE):
			img.set_pixel(2, y, palette["lane_white"])
	elif variant % 4 == 2:
		# Right edge line
		for y in range(TILE_SIZE):
			img.set_pixel(TILE_SIZE - 3, y, palette["lane_white"])

	# Pothole on some variants
	if variant % 7 == 0:
		var px = rng.randi_range(6, TILE_SIZE - 8)
		var py = rng.randi_range(6, TILE_SIZE - 8)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if dx * dx + dy * dy <= 5 and px + dx >= 0 and px + dx < TILE_SIZE and py + dy >= 0 and py + dy < TILE_SIZE:
					img.set_pixel(px + dx, py + dy, palette["pothole"])


## Red/brown brick wall pattern
func _draw_brick_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["mortar"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	var brick_h = 4
	var brick_w = 8

	for row in range(TILE_SIZE / brick_h):
		var offset = (brick_w / 2) if row % 2 == 1 else 0
		for col in range((TILE_SIZE / brick_w) + 1):
			var bx = col * brick_w + offset
			var by = row * brick_h

			# Pick brick color with variation
			var brick_col = palette["base"]
			var r = rng.randf()
			if r < 0.2:
				brick_col = palette["light"]
			elif r < 0.35:
				brick_col = palette["dark"]
			elif r < 0.45:
				brick_col = palette["stain"]

			# Draw brick body
			for dy in range(1, brick_h):
				for dx in range(1, brick_w):
					var px = bx + dx
					var py = by + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						var shade = brick_col
						# Top-left highlight
						if dy == 1:
							shade = brick_col.lightened(0.1)
						elif dx == 1:
							shade = brick_col.lightened(0.05)
						# Bottom-right shadow
						elif dy == brick_h - 1:
							shade = brick_col.darkened(0.1)
						elif dx == brick_w - 1:
							shade = brick_col.darkened(0.05)
						img.set_pixel(px, py, shade)

	# Occasional moss in mortar
	if variant % 3 == 0:
		for _i in range(3):
			var mx = rng.randi_range(0, TILE_SIZE - 1)
			var my = rng.randi_range(0, TILE_SIZE - 1)
			if img.get_pixel(mx, my).is_equal_approx(palette["mortar"]):
				img.set_pixel(mx, my, palette["moss"])


## Riveted steel floor
func _draw_metal_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 44444

	# Diamond plate texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.7 + y * 0.5 + variant * 1.5) * cos(x * 0.3 - y * 0.4) * 0.5
			n += rng.randf() * 0.1
			if n < -0.2:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Plate seams (cross pattern)
	for i in range(TILE_SIZE):
		if i < TILE_SIZE:
			img.set_pixel(i, TILE_SIZE / 2, palette["seam"])
			img.set_pixel(TILE_SIZE / 2, i, palette["seam"])

	# Rivets at corners and edges
	var rivet_positions = [
		Vector2i(4, 4), Vector2i(TILE_SIZE - 5, 4),
		Vector2i(4, TILE_SIZE - 5), Vector2i(TILE_SIZE - 5, TILE_SIZE - 5),
		Vector2i(TILE_SIZE / 2, 4), Vector2i(TILE_SIZE / 2, TILE_SIZE - 5),
		Vector2i(4, TILE_SIZE / 2), Vector2i(TILE_SIZE - 5, TILE_SIZE / 2)
	]
	for pos in rivet_positions:
		# Rivet body
		img.set_pixel(pos.x, pos.y, palette["rivet"])
		# Rivet highlight (top-left)
		if pos.x > 0 and pos.y > 0:
			img.set_pixel(pos.x - 1, pos.y - 1, palette["rivet_light"])
		# Rivet shadow (bottom-right)
		if pos.x + 1 < TILE_SIZE and pos.y + 1 < TILE_SIZE:
			img.set_pixel(pos.x + 1, pos.y + 1, palette["deep"])

	# Rust spots
	if variant % 3 == 0:
		for _i in range(rng.randi_range(2, 5)):
			var rx = rng.randi_range(2, TILE_SIZE - 3)
			var ry = rng.randi_range(2, TILE_SIZE - 3)
			img.set_pixel(rx, ry, palette["rust"])
			if rx + 1 < TILE_SIZE:
				img.set_pixel(rx + 1, ry, palette["rust"].darkened(0.15))


## Industrial piping (impassable)
func _draw_pipe(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["deep"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 55555

	# Main horizontal pipe
	var pipe_top = 8
	var pipe_bottom = 24

	for y in range(pipe_top, pipe_bottom):
		for x in range(TILE_SIZE):
			var rel_y = float(y - pipe_top) / float(pipe_bottom - pipe_top)
			var shade: Color
			# Cylindrical shading
			if rel_y < 0.15:
				shade = palette["light"]
			elif rel_y < 0.3:
				shade = palette["mid"]
			elif rel_y < 0.5:
				shade = palette["base"]
			elif rel_y < 0.7:
				shade = palette["mid"]
			elif rel_y < 0.85:
				shade = palette["dark"]
			else:
				shade = palette["deep"]

			# Copper accent on some variants
			if variant % 2 == 0 and rng.randf() < 0.1:
				shade = shade.lerp(palette["copper"], 0.3)

			img.set_pixel(x, y, shade)

	# Pipe joints every 16 pixels
	for jx in [0, 16]:
		for y in range(pipe_top - 1, pipe_bottom + 1):
			for dx in range(3):
				var x = jx + dx
				if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
					img.set_pixel(x, y, palette["joint"])

	# Steam wisps on certain variants
	if variant % 3 == 0:
		for _i in range(3):
			var sx = rng.randi_range(4, TILE_SIZE - 4)
			var sy = rng.randi_range(1, pipe_top - 1)
			if sx < TILE_SIZE and sy < TILE_SIZE:
				img.set_pixel(sx, sy, palette["steam"])


## Green park grass with flowers
func _draw_park_grass(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 66666

	# Grass texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.5 + variant * 1.8) * cos(y * 0.4 + variant * 0.4)
			var n2 = sin(x * 1.2 + y * 0.8 + variant * 2.2) * 0.4
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.2
			if combined < -0.25:
				img.set_pixel(x, y, palette["deep"])
			elif combined < -0.1:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.3:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.15:
				img.set_pixel(x, y, palette["mid"])

	# Grass blade tufts
	for _i in range(6 + variant % 3):
		var tx = rng.randi_range(2, TILE_SIZE - 3)
		var ty = rng.randi_range(6, TILE_SIZE - 2)
		for blade in range(rng.randi_range(2, 4)):
			var bx = tx + blade - 1
			var blade_h = rng.randi_range(2, 5)
			for h in range(blade_h):
				var px = bx + rng.randi_range(-1, 0)
				var py = ty - h
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					var shade = palette["light"] if h == blade_h - 1 else palette["mid"]
					img.set_pixel(px, py, shade)

	# Flowers on certain variants
	if variant % 3 == 0:
		var flower_colors = [palette["flower_red"], palette["flower_yellow"], palette["flower_white"]]
		for _f in range(rng.randi_range(1, 3)):
			var fx = rng.randi_range(3, TILE_SIZE - 4)
			var fy = rng.randi_range(3, TILE_SIZE - 6)
			var fc = flower_colors[rng.randi() % flower_colors.size()]
			img.set_pixel(fx, fy, fc)
			if fx > 0: img.set_pixel(fx - 1, fy, fc.darkened(0.15))
			if fx + 1 < TILE_SIZE: img.set_pixel(fx + 1, fy, fc.darkened(0.15))
			if fy > 0: img.set_pixel(fx, fy - 1, fc.lightened(0.1))
			# Stem
			for s in range(2):
				if fy + s + 1 < TILE_SIZE:
					img.set_pixel(fx, fy + s + 1, palette["dark"])

	# Soil patches near edges
	for _i in range(rng.randi_range(1, 3)):
		var sx = rng.randi_range(0, TILE_SIZE - 3)
		var sy = rng.randi_range(TILE_SIZE - 4, TILE_SIZE - 1)
		if sx < TILE_SIZE and sy < TILE_SIZE:
			img.set_pixel(sx, sy, palette["soil"])


## City building wall (impassable)
func _draw_building_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 77777

	# Flat wall with subtle texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.3 + y * 0.2 + variant * 1.1) * 0.2 + rng.randf() * 0.1
			if n < -0.1:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.15:
				img.set_pixel(x, y, palette["light"])

	# Top trim/cornice
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["trim"])
		img.set_pixel(x, 1, palette["trim"])
		img.set_pixel(x, 2, palette["shadow"])

	# Bottom base
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 1, palette["deep"])
		img.set_pixel(x, TILE_SIZE - 2, palette["dark"])

	# Vertical pillars on some variants
	if variant % 2 == 0:
		for y in range(3, TILE_SIZE - 2):
			img.set_pixel(0, y, palette["accent"])
			img.set_pixel(1, y, palette["mid"])
			img.set_pixel(TILE_SIZE - 2, y, palette["mid"])
			img.set_pixel(TILE_SIZE - 1, y, palette["accent"])


## Building entrance/door
func _draw_door(img: Image, palette: Dictionary) -> void:
	# Frame background
	img.fill(palette["frame"])

	# Door frame
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["frame_light"])
		img.set_pixel(1, y, palette["frame"])
		img.set_pixel(TILE_SIZE - 2, y, palette["frame"])
		img.set_pixel(TILE_SIZE - 1, y, palette["frame_light"])
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["frame_light"])
		img.set_pixel(x, 1, palette["frame"])

	# Step at bottom
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 1, palette["step"])
		img.set_pixel(x, TILE_SIZE - 2, palette["step"])

	# Door panels
	for y in range(3, TILE_SIZE - 3):
		for x in range(3, TILE_SIZE - 3):
			var rel_y = float(y - 3) / float(TILE_SIZE - 6)
			var shade = palette["base"]
			if rel_y < 0.1:
				shade = palette["light"]
			elif rel_y > 0.9:
				shade = palette["dark"]
			# Wood grain
			var grain = sin(y * 0.8 + x * 0.1) * 0.3
			if grain > 0.15:
				shade = shade.lightened(0.05)
			elif grain < -0.15:
				shade = shade.darkened(0.05)
			img.set_pixel(x, y, shade)

	# Door handle
	img.set_pixel(TILE_SIZE - 8, TILE_SIZE / 2, palette["handle"])
	img.set_pixel(TILE_SIZE - 8, TILE_SIZE / 2 + 1, palette["handle"])
	img.set_pixel(TILE_SIZE - 7, TILE_SIZE / 2, palette["handle"].lightened(0.2))

	# Dark opening hint at center crack
	for y in range(4, TILE_SIZE - 4):
		img.set_pixel(TILE_SIZE / 2, y, palette["deep"])


## Decorative window (impassable)
func _draw_window(img: Image, palette: Dictionary) -> void:
	# Wall background
	img.fill(palette["frame"])

	# Window frame
	for x in range(4, TILE_SIZE - 4):
		img.set_pixel(x, 4, palette["frame_light"])
		img.set_pixel(x, TILE_SIZE - 5, palette["frame_light"])
	for y in range(4, TILE_SIZE - 4):
		img.set_pixel(4, y, palette["frame_light"])
		img.set_pixel(TILE_SIZE - 5, y, palette["frame_light"])

	# Glass pane
	for y in range(5, TILE_SIZE - 5):
		for x in range(5, TILE_SIZE - 5):
			var rel_y = float(y - 5) / float(TILE_SIZE - 10)
			var shade = palette["base"]
			if rel_y < 0.3:
				shade = palette["light"]
			elif rel_y > 0.7:
				shade = palette["dark"]
			else:
				shade = palette["mid"]
			img.set_pixel(x, y, shade)

	# Cross pane divider
	for x in range(5, TILE_SIZE - 5):
		img.set_pixel(x, TILE_SIZE / 2, palette["frame"])
	for y in range(5, TILE_SIZE - 5):
		img.set_pixel(TILE_SIZE / 2, y, palette["frame"])

	# Glare reflection
	img.set_pixel(8, 8, palette["glare"])
	img.set_pixel(9, 8, palette["glare"])
	img.set_pixel(8, 9, palette["glare"].darkened(0.1))

	# Curtain hint on one side
	for y in range(6, TILE_SIZE - 6):
		img.set_pixel(TILE_SIZE - 8, y, palette["curtain"])
		img.set_pixel(TILE_SIZE - 7, y, palette["curtain"].darkened(0.1))


## Train tracks
func _draw_rail_track(img: Image, palette: Dictionary, variant: int) -> void:
	# Gravel bed base
	img.fill(palette["gravel"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 99999

	# Gravel texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.4 + sin(x * 1.5 + y * 1.2) * 0.2
			if n < 0.15:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.45:
				img.set_pixel(x, y, palette["light"])

	# Railroad ties (horizontal wooden beams)
	for ty in range(0, TILE_SIZE, 6):
		for x in range(2, TILE_SIZE - 2):
			for dy in range(2):
				var py = ty + dy
				if py < TILE_SIZE:
					img.set_pixel(x, py, palette["tie"])
					if dy == 0:
						img.set_pixel(x, py, palette["tie"].lightened(0.08))

	# Steel rails (two parallel lines)
	var rail_left = 8
	var rail_right = TILE_SIZE - 9
	for y in range(TILE_SIZE):
		# Left rail
		img.set_pixel(rail_left, y, palette["rail"])
		img.set_pixel(rail_left + 1, y, palette["rail_light"])
		img.set_pixel(rail_left - 1, y, palette["dark"])
		# Right rail
		img.set_pixel(rail_right, y, palette["rail"])
		img.set_pixel(rail_right + 1, y, palette["rail_light"])
		img.set_pixel(rail_right - 1, y, palette["dark"])


## Decorative neon accent (impassable)
func _draw_neon_sign(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 10101

	# Dark wall background texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.2
			if n < 0.05:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.15:
				img.set_pixel(x, y, palette["mid"])

	# Neon tubes - alternating teal and magenta based on variant
	var neon_col = palette["neon_teal"] if variant % 2 == 0 else palette["neon_magenta"]
	var glow_col = palette["neon_glow"] if variant % 2 == 0 else palette["neon_pink_glow"]

	# Draw neon shape (simple geometric - zigzag or circle)
	if variant % 3 == 0:
		# Zigzag pattern
		for i in range(TILE_SIZE - 8):
			var y_off = 12 + int(sin(i * 0.5) * 6)
			var x_pos = 4 + i
			if x_pos < TILE_SIZE and y_off >= 0 and y_off < TILE_SIZE:
				img.set_pixel(x_pos, y_off, neon_col)
				# Glow around neon
				for dy in [-1, 1]:
					if y_off + dy >= 0 and y_off + dy < TILE_SIZE:
						img.set_pixel(x_pos, y_off + dy, glow_col.lerp(palette["base"], 0.6))
	else:
		# Horizontal neon bar
		for x in range(6, TILE_SIZE - 6):
			var cy = TILE_SIZE / 2
			img.set_pixel(x, cy, neon_col)
			img.set_pixel(x, cy + 1, neon_col)
			# Glow
			for dy in [-2, -1, 2, 3]:
				if cy + dy >= 0 and cy + dy < TILE_SIZE:
					var glow_strength = 0.4 if abs(dy) == 1 else 0.7
					img.set_pixel(x, cy + dy, glow_col.lerp(palette["base"], glow_strength))

	# Corner mounting brackets
	for corner in [Vector2i(3, 3), Vector2i(TILE_SIZE - 4, 3), Vector2i(3, TILE_SIZE - 4), Vector2i(TILE_SIZE - 4, TILE_SIZE - 4)]:
		if corner.x >= 0 and corner.x < TILE_SIZE and corner.y >= 0 and corner.y < TILE_SIZE:
			img.set_pixel(corner.x, corner.y, palette["light"])


## Fountain/pond water feature
func _draw_water_feature(img: Image, palette: Dictionary, variant: int) -> void:
	# Stone border
	img.fill(palette["stone"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12121

	# Stone texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.3
			if n < 0.08:
				img.set_pixel(x, y, palette["stone_dark"])

	# Water pool (circular area)
	var cx = TILE_SIZE / 2
	var cy = TILE_SIZE / 2
	var radius = 11
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist < radius:
				var depth = dist / radius
				var shade: Color
				if depth < 0.3:
					shade = palette["deep"]
				elif depth < 0.5:
					shade = palette["dark"]
				elif depth < 0.7:
					shade = palette["base"]
				elif depth < 0.85:
					shade = palette["mid"]
				else:
					shade = palette["light"]
				img.set_pixel(x, y, shade)
			elif dist < radius + 1.5:
				# Stone rim
				img.set_pixel(x, y, palette["stone_dark"])

	# Sparkle highlights
	for _i in range(4):
		var sx = cx + rng.randi_range(-6, 6)
		var sy = cy + rng.randi_range(-6, 6)
		if sx >= 0 and sx < TILE_SIZE and sy >= 0 and sy < TILE_SIZE:
			var dist = sqrt(pow(sx - cx, 2) + pow(sy - cy, 2))
			if dist < radius - 2:
				img.set_pixel(sx, sy, palette["sparkle"])

	# Foam ring
	for angle in range(0, 360, 15):
		var rad = deg_to_rad(angle)
		var fx = cx + int(cos(rad) * (radius - 3))
		var fy = cy + int(sin(rad) * (radius - 3))
		if fx >= 0 and fx < TILE_SIZE and fy >= 0 and fy < TILE_SIZE:
			if rng.randf() < 0.5:
				img.set_pixel(fx, fy, palette["foam"])


## Park/yard fence (impassable)
func _draw_fence(img: Image, palette: Dictionary, variant: int) -> void:
	# Grass background
	img.fill(palette["grass"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 13131

	# Grass texture underneath
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.6 + y * 0.4 + variant * 1.5) * 0.3 + rng.randf() * 0.15
			if n < -0.1:
				img.set_pixel(x, y, palette["grass_dark"])

	# Fence posts (vertical)
	var post_spacing = 8
	for px in range(0, TILE_SIZE, post_spacing):
		for y in range(4, TILE_SIZE - 4):
			if px < TILE_SIZE:
				img.set_pixel(px, y, palette["post"])
				if px + 1 < TILE_SIZE:
					img.set_pixel(px + 1, y, palette["post_light"])

	# Horizontal rails
	var rail_y1 = 10
	var rail_y2 = 20
	for x in range(TILE_SIZE):
		img.set_pixel(x, rail_y1, palette["base"])
		img.set_pixel(x, rail_y1 + 1, palette["dark"])
		img.set_pixel(x, rail_y2, palette["base"])
		img.set_pixel(x, rail_y2 + 1, palette["dark"])

	# Post caps
	for px in range(0, TILE_SIZE, post_spacing):
		if px < TILE_SIZE and px + 1 < TILE_SIZE:
			img.set_pixel(px, 3, palette["light"])
			img.set_pixel(px + 1, 3, palette["light"])
			img.set_pixel(px, 4, palette["post_light"])
			img.set_pixel(px + 1, 4, palette["post_light"])


## Narrow alley passageway
func _draw_alley(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 14141

	# Grime and dirt texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.8 + y * 0.6 + variant * 2.0) * 0.3 + rng.randf() * 0.2
			if n < -0.15:
				img.set_pixel(x, y, palette["deep"])
			elif n < -0.05:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.08:
				img.set_pixel(x, y, palette["mid"])

	# Wall shadows on sides
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["shadow"])
		img.set_pixel(1, y, palette["shadow"])
		img.set_pixel(TILE_SIZE - 1, y, palette["shadow"])
		img.set_pixel(TILE_SIZE - 2, y, palette["shadow"])
		img.set_pixel(2, y, palette["dark"])
		img.set_pixel(TILE_SIZE - 3, y, palette["dark"])

	# Puddle on some variants
	if variant % 2 == 0:
		var py = rng.randi_range(10, TILE_SIZE - 8)
		for dy in range(4):
			for dx in range(-3, 4):
				var px = TILE_SIZE / 2 + dx
				var ppy = py + dy
				if px >= 3 and px < TILE_SIZE - 3 and ppy < TILE_SIZE:
					if abs(dx) + abs(dy - 2) < 4:
						img.set_pixel(px, ppy, palette["puddle"])

	# Grime streaks
	for _i in range(rng.randi_range(2, 4)):
		var gx = rng.randi_range(3, TILE_SIZE - 4)
		var gy = rng.randi_range(0, TILE_SIZE - 6)
		for j in range(rng.randi_range(3, 6)):
			if gy + j < TILE_SIZE:
				img.set_pixel(gx, gy + j, palette["grime"])


## Street light (impassable)
func _draw_lamppost(img: Image, palette: Dictionary) -> void:
	# Concrete base
	img.fill(palette["concrete"])

	# Pole (center vertical)
	var pole_x = TILE_SIZE / 2
	for y in range(6, TILE_SIZE - 2):
		img.set_pixel(pole_x - 1, y, palette["dark"])
		img.set_pixel(pole_x, y, palette["base"])
		img.set_pixel(pole_x + 1, y, palette["light"])

	# Pole base (wider)
	for y in range(TILE_SIZE - 4, TILE_SIZE - 1):
		for dx in range(-2, 3):
			var px = pole_x + dx
			if px >= 0 and px < TILE_SIZE:
				img.set_pixel(px, y, palette["mid"])
	# Base bottom edge
	for dx in range(-3, 4):
		var px = pole_x + dx
		if px >= 0 and px < TILE_SIZE:
			img.set_pixel(px, TILE_SIZE - 1, palette["dark"])

	# Lamp head
	for dx in range(-3, 4):
		for dy in range(3):
			var px = pole_x + dx
			var py = 4 + dy
			if px >= 0 and px < TILE_SIZE and py >= 0:
				img.set_pixel(px, py, palette["glass"])
	# Bright lamp center
	img.set_pixel(pole_x, 5, palette["lamp_bright"])
	img.set_pixel(pole_x - 1, 5, palette["lamp_glow"])
	img.set_pixel(pole_x + 1, 5, palette["lamp_glow"])
	img.set_pixel(pole_x, 4, palette["lamp_glow"])

	# Glow halo
	for dx in range(-4, 5):
		for dy in range(-1, 4):
			var px = pole_x + dx
			var py = 3 + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var dist = sqrt(dx * dx + dy * dy)
				if dist > 2 and dist < 5:
					var current = img.get_pixel(px, py)
					img.set_pixel(px, py, current.lerp(palette["lamp_glow"], 0.15))


## Manhole cover (special tile)
func _draw_manhole(img: Image, palette: Dictionary) -> void:
	# Concrete surround
	img.fill(palette["concrete"])

	var cx = TILE_SIZE / 2
	var cy = TILE_SIZE / 2

	# Manhole cover (circular)
	var radius = 12
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist < radius:
				var depth = dist / radius
				if depth < 0.7:
					img.set_pixel(x, y, palette["base"])
				else:
					img.set_pixel(x, y, palette["dark"])
			elif dist < radius + 1.5:
				img.set_pixel(x, y, palette["rim"])

	# Cross pattern on cover
	for i in range(-radius + 2, radius - 1):
		var px1 = cx + i
		var py1 = cy
		var px2 = cx
		var py2 = cy + i
		if px1 >= 0 and px1 < TILE_SIZE:
			img.set_pixel(px1, py1, palette["mid"])
		if py2 >= 0 and py2 < TILE_SIZE:
			img.set_pixel(px2, py2, palette["mid"])

	# Concentric ring pattern
	for r in [4, 8]:
		for angle in range(0, 360, 5):
			var rad = deg_to_rad(angle)
			var rx = cx + int(cos(rad) * r)
			var ry = cy + int(sin(rad) * r)
			if rx >= 0 and rx < TILE_SIZE and ry >= 0 and ry < TILE_SIZE:
				img.set_pixel(rx, ry, palette["ring"])

	# Center hole hint
	img.set_pixel(cx, cy, palette["hole"])
	img.set_pixel(cx + 1, cy, palette["hole"])
	img.set_pixel(cx, cy + 1, palette["hole"])
	img.set_pixel(cx + 1, cy + 1, palette["hole"])


## Create tileset with all steampunk tiles
func create_tileset() -> TileSet:
	print("Creating steampunk/industrial tileset...")
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
		# Row 0: Ground tiles
		TileType.CONCRETE, TileType.ASPHALT, TileType.BRICK_WALL, TileType.METAL_FLOOR,
		# Row 1: Industrial
		TileType.PIPE, TileType.PARK_GRASS, TileType.BUILDING_WALL, TileType.DOOR,
		# Row 2: Decorative
		TileType.WINDOW, TileType.RAIL_TRACK, TileType.NEON_SIGN, TileType.WATER_FEATURE,
		# Row 3: Misc
		TileType.FENCE, TileType.ALLEY, TileType.LAMPPOST, TileType.MANHOLE
	]

	# Impassable tile types (need collision)
	var impassable_types = [
		TileType.BRICK_WALL, TileType.PIPE, TileType.BUILDING_WALL,
		TileType.WINDOW, TileType.NEON_SIGN, TileType.FENCE, TileType.LAMPPOST
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
	atlas_img.save_png("user://debug_steampunk_atlas.png")
	print("Steampunk atlas saved (size: %dx%d, %d tiles)" % [atlas_img.get_width(), atlas_img.get_height(), tile_order.size()])

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
