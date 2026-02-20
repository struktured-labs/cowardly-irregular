extends Node
class_name AbstractTileGenerator

## AbstractTileGenerator - Procedurally generates 32x32 minimalist/existential tiles
## Area 5: The logical endpoint of total optimization. Everything unnecessary removed.
## Near-monochrome palette: whites, light grays, deep blacks, rare precious color.
## "Optimization as Entropy" - efficiency removes friction, friction is where humanity lives.

const TILE_SIZE: int = 32

## Tile types for Area 5 (Abstract minimalist void)
enum TileType {
	VOID_WHITE,       # 0  - pure white with barely perceptible texture
	VOID_GRAY,        # 1  - slightly darker void, suggests depth
	VOID_BLACK,       # 2  - deep absence (impassable)
	GRID_LINE,        # 3  - faint geometric grid on white (the world's skeleton)
	FRAGMENT_GRASS,   # 4  - single tuft of green on white (memory of nature)
	FRAGMENT_BRICK,   # 5  - single brick floating in white (memory of civilization)
	FRAGMENT_CIRCUIT, # 6  - single circuit trace on white (memory of technology)
	SHELF_UNIT,       # 7  - minimalist container shape (impassable)
	ECHO_WALL,        # 8  - barely-visible wall outline (impassable)
	THRESHOLD_FADE,   # 9  - gradient from white to lighter white (transition)
	COLOR_SPOT,       # 10 - single spot of vivid color on white (meaning persists)
	STATIC_TILE,      # 11 - TV static/noise pattern (corruption/memory loss)
	SHADOW_TILE,      # 12 - a shadow with no object casting it
	QUESTION_MARK,    # 13 - subtle ? shape embedded in the floor
	FOOTPRINT_TILE,   # 14 - previous visitors' traces, barely visible
	REMNANT_DOOR      # 15 - outline of a door that leads nowhere (impassable)
}

## Near-monochrome palettes - subtle, lots of near-whites and near-grays
## with occasional moments of precious color
const PALETTES: Dictionary = {
	TileType.VOID_WHITE: {
		"base": Color(0.96, 0.96, 0.97),
		"warm": Color(0.97, 0.96, 0.95),
		"cool": Color(0.95, 0.96, 0.97),
		"grain1": Color(0.94, 0.94, 0.95),
		"grain2": Color(0.97, 0.97, 0.96),
		"dust": Color(0.93, 0.93, 0.94),
		"breath": Color(0.98, 0.98, 0.99),
		"absence": Color(0.95, 0.95, 0.96),
		"nothing": Color(0.96, 0.965, 0.97)
	},
	TileType.VOID_GRAY: {
		"base": Color(0.82, 0.82, 0.84),
		"light": Color(0.88, 0.88, 0.89),
		"mid": Color(0.85, 0.85, 0.86),
		"dark": Color(0.76, 0.76, 0.78),
		"deep": Color(0.70, 0.70, 0.72),
		"warm": Color(0.84, 0.82, 0.80),
		"cool": Color(0.80, 0.82, 0.86),
		"edge": Color(0.78, 0.78, 0.80),
		"fade": Color(0.90, 0.90, 0.91)
	},
	TileType.VOID_BLACK: {
		"base": Color(0.06, 0.06, 0.08),
		"surface": Color(0.10, 0.10, 0.12),
		"deep": Color(0.03, 0.03, 0.04),
		"abyss": Color(0.01, 0.01, 0.02),
		"shimmer": Color(0.14, 0.14, 0.18),
		"edge_glow": Color(0.20, 0.20, 0.24),
		"void_purple": Color(0.08, 0.05, 0.12),
		"void_blue": Color(0.05, 0.06, 0.12),
		"grain": Color(0.08, 0.08, 0.10)
	},
	TileType.GRID_LINE: {
		"base": Color(0.96, 0.96, 0.97),
		"line": Color(0.88, 0.88, 0.90),
		"line_faint": Color(0.92, 0.92, 0.93),
		"node": Color(0.84, 0.84, 0.86),
		"glow": Color(0.90, 0.91, 0.94),
		"warmth": Color(0.93, 0.92, 0.90),
		"skeleton": Color(0.86, 0.87, 0.90),
		"pulse": Color(0.85, 0.86, 0.92),
		"ghost": Color(0.91, 0.91, 0.92)
	},
	TileType.FRAGMENT_GRASS: {
		"base": Color(0.96, 0.96, 0.97),
		"grass_green": Color(0.30, 0.65, 0.25),
		"grass_light": Color(0.45, 0.78, 0.35),
		"grass_dark": Color(0.20, 0.50, 0.15),
		"soil": Color(0.55, 0.42, 0.28),
		"memory_glow": Color(0.40, 0.72, 0.35, 0.6),
		"white": Color(0.96, 0.96, 0.97),
		"dust": Color(0.94, 0.94, 0.95),
		"stem": Color(0.25, 0.55, 0.20)
	},
	TileType.FRAGMENT_BRICK: {
		"base": Color(0.96, 0.96, 0.97),
		"brick_red": Color(0.62, 0.28, 0.18),
		"brick_light": Color(0.72, 0.38, 0.26),
		"brick_dark": Color(0.48, 0.20, 0.12),
		"mortar": Color(0.78, 0.74, 0.68),
		"memory_glow": Color(0.68, 0.35, 0.22, 0.5),
		"white": Color(0.96, 0.96, 0.97),
		"dust": Color(0.94, 0.94, 0.95),
		"shadow": Color(0.90, 0.89, 0.88)
	},
	TileType.FRAGMENT_CIRCUIT: {
		"base": Color(0.96, 0.96, 0.97),
		"trace_green": Color(0.15, 0.55, 0.30),
		"trace_bright": Color(0.20, 0.72, 0.40),
		"trace_dark": Color(0.10, 0.40, 0.22),
		"solder": Color(0.75, 0.75, 0.78),
		"memory_glow": Color(0.18, 0.62, 0.35, 0.5),
		"white": Color(0.96, 0.96, 0.97),
		"dust": Color(0.94, 0.94, 0.95),
		"copper": Color(0.72, 0.50, 0.25)
	},
	TileType.SHELF_UNIT: {
		"base": Color(0.88, 0.88, 0.89),
		"frame": Color(0.78, 0.78, 0.80),
		"shelf": Color(0.82, 0.82, 0.84),
		"shadow": Color(0.72, 0.72, 0.74),
		"deep": Color(0.65, 0.65, 0.68),
		"highlight": Color(0.92, 0.92, 0.93),
		"edge": Color(0.75, 0.75, 0.77),
		"void_inside": Color(0.60, 0.60, 0.64),
		"label": Color(0.85, 0.85, 0.86)
	},
	TileType.ECHO_WALL: {
		"base": Color(0.94, 0.94, 0.95),
		"outline": Color(0.84, 0.84, 0.86),
		"outline_faint": Color(0.88, 0.88, 0.90),
		"inner": Color(0.92, 0.92, 0.93),
		"shadow": Color(0.86, 0.86, 0.88),
		"echo1": Color(0.90, 0.90, 0.91),
		"echo2": Color(0.91, 0.91, 0.92),
		"echo3": Color(0.93, 0.93, 0.94),
		"corner": Color(0.82, 0.82, 0.84)
	},
	TileType.THRESHOLD_FADE: {
		"base_top": Color(0.96, 0.96, 0.97),
		"base_bot": Color(0.92, 0.92, 0.93),
		"mid": Color(0.94, 0.94, 0.95),
		"warm": Color(0.95, 0.94, 0.92),
		"cool": Color(0.92, 0.93, 0.96),
		"dissolve1": Color(0.93, 0.93, 0.94),
		"dissolve2": Color(0.91, 0.91, 0.93),
		"particle": Color(0.88, 0.88, 0.90),
		"glow": Color(0.97, 0.97, 0.98)
	},
	TileType.COLOR_SPOT: {
		"base": Color(0.96, 0.96, 0.97),
		"color_core": Color(0.85, 0.22, 0.28),
		"color_warm": Color(0.92, 0.45, 0.18),
		"color_cool": Color(0.18, 0.42, 0.85),
		"color_life": Color(0.25, 0.75, 0.35),
		"glow_inner": Color(0.95, 0.60, 0.55),
		"glow_outer": Color(0.96, 0.92, 0.92),
		"white": Color(0.96, 0.96, 0.97),
		"bleed": Color(0.94, 0.90, 0.90)
	},
	TileType.STATIC_TILE: {
		"base": Color(0.88, 0.88, 0.90),
		"light": Color(0.95, 0.95, 0.96),
		"mid": Color(0.82, 0.82, 0.84),
		"dark": Color(0.65, 0.65, 0.68),
		"deep": Color(0.48, 0.48, 0.52),
		"noise_white": Color(0.98, 0.98, 0.98),
		"noise_gray": Color(0.72, 0.72, 0.74),
		"noise_dark": Color(0.38, 0.38, 0.42),
		"scanline": Color(0.78, 0.78, 0.80)
	},
	TileType.SHADOW_TILE: {
		"base": Color(0.96, 0.96, 0.97),
		"shadow_light": Color(0.88, 0.88, 0.90),
		"shadow_mid": Color(0.82, 0.82, 0.85),
		"shadow_dark": Color(0.75, 0.75, 0.78),
		"shadow_core": Color(0.68, 0.68, 0.72),
		"edge": Color(0.90, 0.90, 0.92),
		"ground": Color(0.94, 0.94, 0.95),
		"warmth": Color(0.92, 0.90, 0.88),
		"cold": Color(0.86, 0.88, 0.92)
	},
	TileType.QUESTION_MARK: {
		"base": Color(0.96, 0.96, 0.97),
		"mark_light": Color(0.88, 0.88, 0.90),
		"mark_mid": Color(0.84, 0.84, 0.86),
		"mark_dark": Color(0.78, 0.78, 0.82),
		"dot": Color(0.72, 0.72, 0.76),
		"glow": Color(0.90, 0.90, 0.94),
		"white": Color(0.96, 0.96, 0.97),
		"dust": Color(0.94, 0.94, 0.95),
		"echo": Color(0.92, 0.92, 0.93)
	},
	TileType.FOOTPRINT_TILE: {
		"base": Color(0.96, 0.96, 0.97),
		"print_light": Color(0.92, 0.92, 0.93),
		"print_mid": Color(0.90, 0.90, 0.91),
		"print_dark": Color(0.88, 0.88, 0.89),
		"print_deep": Color(0.86, 0.86, 0.87),
		"dust": Color(0.94, 0.94, 0.95),
		"white": Color(0.96, 0.96, 0.97),
		"age_fade": Color(0.93, 0.93, 0.94),
		"warmth": Color(0.94, 0.93, 0.91)
	},
	TileType.REMNANT_DOOR: {
		"base": Color(0.94, 0.94, 0.95),
		"frame": Color(0.78, 0.78, 0.80),
		"frame_light": Color(0.84, 0.84, 0.86),
		"frame_dark": Color(0.72, 0.72, 0.74),
		"inner": Color(0.90, 0.90, 0.92),
		"handle": Color(0.68, 0.68, 0.72),
		"shadow": Color(0.82, 0.82, 0.84),
		"memory": Color(0.86, 0.84, 0.80),
		"threshold": Color(0.88, 0.88, 0.90)
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
	var palette = PALETTES.get(type, PALETTES[TileType.VOID_WHITE])

	match type:
		TileType.VOID_WHITE:
			_draw_void_white(img, palette, variant)
		TileType.VOID_GRAY:
			_draw_void_gray(img, palette, variant)
		TileType.VOID_BLACK:
			_draw_void_black(img, palette, variant)
		TileType.GRID_LINE:
			_draw_grid_line(img, palette, variant)
		TileType.FRAGMENT_GRASS:
			_draw_fragment_grass(img, palette, variant)
		TileType.FRAGMENT_BRICK:
			_draw_fragment_brick(img, palette, variant)
		TileType.FRAGMENT_CIRCUIT:
			_draw_fragment_circuit(img, palette, variant)
		TileType.SHELF_UNIT:
			_draw_shelf_unit(img, palette, variant)
		TileType.ECHO_WALL:
			_draw_echo_wall(img, palette, variant)
		TileType.THRESHOLD_FADE:
			_draw_threshold_fade(img, palette, variant)
		TileType.COLOR_SPOT:
			_draw_color_spot(img, palette, variant)
		TileType.STATIC_TILE:
			_draw_static_tile(img, palette, variant)
		TileType.SHADOW_TILE:
			_draw_shadow_tile(img, palette, variant)
		TileType.QUESTION_MARK:
			_draw_question_mark(img, palette, variant)
		TileType.FOOTPRINT_TILE:
			_draw_footprint_tile(img, palette, variant)
		TileType.REMNANT_DOOR:
			_draw_remnant_door(img, palette, variant)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## VOID_WHITE - Pure white with barely perceptible texture
## The default state of total optimization. Nothing unnecessary remains.
## Look closely and you might see the faintest grain - or is that your eyes?
func _draw_void_white(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 10001

	# Extremely subtle texture noise - barely perceptible
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.15 + variant * 0.7) * cos(y * 0.12 + variant * 0.4)
			var n2 = sin(x * 0.4 + y * 0.3 + variant * 1.1) * 0.15
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.04
			if combined < -0.15:
				img.set_pixel(x, y, palette["grain1"])
			elif combined > 0.18:
				img.set_pixel(x, y, palette["breath"])
			elif combined > 0.08:
				img.set_pixel(x, y, palette["grain2"])

	# Occasional warm or cool drift across the void
	if variant % 5 == 0:
		var drift_y = rng.randi_range(8, 24)
		for x in range(TILE_SIZE):
			var fade = sin(x * 0.1 + variant * 0.5) * 0.5 + 0.5
			if fade > 0.6:
				img.set_pixel(x, drift_y, palette["warm"])
	elif variant % 5 == 2:
		var drift_x = rng.randi_range(8, 24)
		for y in range(TILE_SIZE):
			var fade = sin(y * 0.1 + variant * 0.3) * 0.5 + 0.5
			if fade > 0.65:
				img.set_pixel(drift_x, y, palette["cool"])

	# Very rare single dust mote
	if variant % 7 == 0:
		var dx = rng.randi_range(4, TILE_SIZE - 5)
		var dy = rng.randi_range(4, TILE_SIZE - 5)
		img.set_pixel(dx, dy, palette["dust"])


## VOID_GRAY - Slightly darker void suggesting depth beneath the white
## Like looking into fog - there's something underneath the nothing.
func _draw_void_gray(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 20002

	# Subtle depth variation - like fog layers
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var depth = sin(x * 0.2 + y * 0.15 + variant * 0.9) * 0.3
			var turbulence = sin(x * 0.7 + y * 0.5 + variant * 1.6) * 0.12
			var combined = depth + turbulence + rng.randf() * 0.06
			if combined < -0.18:
				img.set_pixel(x, y, palette["deep"])
			elif combined < -0.08:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.15:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.06:
				img.set_pixel(x, y, palette["mid"])

	# Warm/cool temperature shift
	var temp_shift = sin(variant * 2.3) * 0.5 + 0.5
	if temp_shift > 0.7:
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				if rng.randf() < 0.03:
					img.set_pixel(x, y, palette["warm"])
	elif temp_shift < 0.3:
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				if rng.randf() < 0.03:
					img.set_pixel(x, y, palette["cool"])

	# Soft edge fade toward white at borders
	for x in range(TILE_SIZE):
		var edge_fade = min(x, TILE_SIZE - 1 - x) / 6.0
		if edge_fade < 1.0:
			var current = img.get_pixel(x, 0)
			img.set_pixel(x, 0, current.lerp(palette["fade"], 1.0 - edge_fade))
		edge_fade = min(x, TILE_SIZE - 1 - x) / 6.0
		if edge_fade < 1.0:
			var current = img.get_pixel(x, TILE_SIZE - 1)
			img.set_pixel(x, TILE_SIZE - 1, current.lerp(palette["fade"], 1.0 - edge_fade))


## VOID_BLACK - Deep absence, the REAL void (impassable)
## Not just darkness - the complete absence of everything. Even absence is absent here.
func _draw_void_black(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 30003

	# Deep, unsettling texture - like staring into nothing
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.3 + y * 0.25 + variant * 1.4) * 0.2 + rng.randf() * 0.08
			if n < -0.12:
				img.set_pixel(x, y, palette["abyss"])
			elif n > 0.14:
				img.set_pixel(x, y, palette["surface"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["grain"])

	# Occasional deep color shifts - void is not just black
	var color_seed = variant % 4
	if color_seed == 0:
		for _i in range(rng.randi_range(2, 5)):
			var px = rng.randi_range(0, TILE_SIZE - 1)
			var py = rng.randi_range(0, TILE_SIZE - 1)
			img.set_pixel(px, py, palette["void_purple"])
	elif color_seed == 1:
		for _i in range(rng.randi_range(2, 5)):
			var px = rng.randi_range(0, TILE_SIZE - 1)
			var py = rng.randi_range(0, TILE_SIZE - 1)
			img.set_pixel(px, py, palette["void_blue"])

	# Faint shimmer along edges - boundary between void and world
	for x in range(TILE_SIZE):
		if rng.randf() < 0.15:
			img.set_pixel(x, 0, palette["shimmer"])
		if rng.randf() < 0.15:
			img.set_pixel(x, TILE_SIZE - 1, palette["shimmer"])
	for y in range(TILE_SIZE):
		if rng.randf() < 0.15:
			img.set_pixel(0, y, palette["shimmer"])
		if rng.randf() < 0.15:
			img.set_pixel(TILE_SIZE - 1, y, palette["shimmer"])

	# Rare edge glow - things dissolve at the boundary
	if variant % 3 == 0:
		var glow_side = rng.randi_range(0, 3)
		for i in range(TILE_SIZE):
			var intensity = sin(i * 0.2 + variant * 0.8) * 0.5 + 0.5
			if intensity > 0.6:
				match glow_side:
					0: img.set_pixel(i, 0, palette["edge_glow"])
					1: img.set_pixel(i, TILE_SIZE - 1, palette["edge_glow"])
					2: img.set_pixel(0, i, palette["edge_glow"])
					3: img.set_pixel(TILE_SIZE - 1, i, palette["edge_glow"])


## GRID_LINE - The world's skeleton, faint geometric grid on white
## When everything else is stripped away, only structure remains.
func _draw_grid_line(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 40004

	# Main grid lines every 8 pixels - the skeleton of reality
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var on_major_x = (x % 16 == 0)
			var on_major_y = (y % 16 == 0)
			var on_minor_x = (x % 8 == 0)
			var on_minor_y = (y % 8 == 0)

			if on_major_x and on_major_y:
				# Grid intersection nodes
				img.set_pixel(x, y, palette["node"])
			elif on_major_x or on_major_y:
				# Major grid lines
				var fade = rng.randf() * 0.15
				if fade < 0.08:
					img.set_pixel(x, y, palette["line"])
				else:
					img.set_pixel(x, y, palette["line_faint"])
			elif on_minor_x or on_minor_y:
				# Minor grid lines - even fainter
				if rng.randf() < 0.4:
					img.set_pixel(x, y, palette["ghost"])

	# Occasional grid "pulse" - a slightly brighter segment
	if variant % 3 == 0:
		var pulse_y = 0
		for x in range(rng.randi_range(4, 12), rng.randi_range(20, 28)):
			if x < TILE_SIZE:
				img.set_pixel(x, pulse_y, palette["pulse"])
	elif variant % 3 == 1:
		var pulse_x = 0
		for y in range(rng.randi_range(4, 12), rng.randi_range(20, 28)):
			if y < TILE_SIZE:
				img.set_pixel(pulse_x, y, palette["pulse"])

	# Warmth bleeding through at random spots
	if variant % 4 == 0:
		var wx = rng.randi_range(2, TILE_SIZE - 3)
		var wy = rng.randi_range(2, TILE_SIZE - 3)
		img.set_pixel(wx, wy, palette["warmth"])
		if wx + 1 < TILE_SIZE:
			img.set_pixel(wx + 1, wy, palette["warmth"])


## FRAGMENT_GRASS - A single tuft of green on white (memory of nature)
## Everything green was optimized away. This single blade refused to leave.
func _draw_fragment_grass(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 50005

	# Subtle white-on-white background texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.15 + y * 0.12 + variant * 0.8) * 0.1 + rng.randf() * 0.03
			if n > 0.08:
				img.set_pixel(x, y, palette["dust"])

	# The precious grass fragment - centered, small, vivid
	var cx = TILE_SIZE / 2 + rng.randi_range(-3, 3)
	var cy = TILE_SIZE / 2 + rng.randi_range(-2, 4)

	# Tiny soil patch beneath the grass
	for dx in range(-2, 3):
		for dy in range(0, 2):
			var px = cx + dx
			var py = cy + dy + 2
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if abs(dx) < 2 or rng.randf() < 0.4:
					img.set_pixel(px, py, palette["soil"])

	# Three or four grass blades reaching upward
	var blade_count = rng.randi_range(3, 5)
	for b in range(blade_count):
		var bx = cx + rng.randi_range(-2, 2)
		var blade_height = rng.randi_range(4, 8)
		var sway = rng.randf_range(-0.3, 0.3)
		for h in range(blade_height):
			var px = bx + int(sin(h * 0.4 + sway * 2.0) * (h * 0.15))
			var py = cy + 1 - h
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var shade = palette["grass_green"]
				if h == blade_height - 1:
					shade = palette["grass_light"]
				elif h < 2:
					shade = palette["grass_dark"]
				img.set_pixel(px, py, shade)

	# Memory glow - faint color bleeding into the white around the fragment
	for angle in range(0, 360, 30):
		var rad = deg_to_rad(angle)
		var dist = rng.randf_range(5.0, 8.0)
		var gx = cx + int(cos(rad) * dist)
		var gy = cy + int(sin(rad) * dist)
		if gx >= 0 and gx < TILE_SIZE and gy >= 0 and gy < TILE_SIZE:
			var current = img.get_pixel(gx, gy)
			if current.r > 0.93:  # Only bleed into white areas
				var bleed = current.lerp(palette["memory_glow"], 0.12)
				img.set_pixel(gx, gy, Color(bleed.r, bleed.g, bleed.b, 1.0))


## FRAGMENT_BRICK - A single brick floating in white (memory of civilization)
## One brick from a wall that no longer exists. It remembers being part of something.
func _draw_fragment_brick(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 60006

	# Subtle background texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.12 + y * 0.1 + variant * 0.6) * 0.08 + rng.randf() * 0.02
			if n > 0.06:
				img.set_pixel(x, y, palette["dust"])

	# The lone brick - slightly off-center, floating
	var brick_x = TILE_SIZE / 2 - 5 + rng.randi_range(-2, 2)
	var brick_y = TILE_SIZE / 2 - 3 + rng.randi_range(-2, 2)
	var brick_w = 10
	var brick_h = 6

	# Faint shadow beneath (the brick floats slightly)
	for dx in range(-1, brick_w + 2):
		for dy in range(1, 3):
			var px = brick_x + dx
			var py = brick_y + brick_h + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var shadow_fade = 1.0 - (dy / 3.0)
				var current = img.get_pixel(px, py)
				img.set_pixel(px, py, current.lerp(palette["shadow"], shadow_fade * 0.25))

	# The brick itself with proper texture
	for dy in range(brick_h):
		for dx in range(brick_w):
			var px = brick_x + dx
			var py = brick_y + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var shade = palette["brick_red"]
				# Top edge highlight
				if dy == 0:
					shade = palette["brick_light"]
				# Bottom edge dark
				elif dy == brick_h - 1:
					shade = palette["brick_dark"]
				# Left edge light
				elif dx == 0:
					shade = palette["brick_light"]
				# Right edge dark
				elif dx == brick_w - 1:
					shade = palette["brick_dark"]
				# Internal grain texture
				else:
					var grain = sin(dx * 0.8 + dy * 1.2 + variant * 0.5) * 0.12
					if grain > 0.06:
						shade = shade.lightened(0.06)
					elif grain < -0.06:
						shade = shade.darkened(0.06)
				img.set_pixel(px, py, shade)

	# Mortar traces - remnants of the wall it belonged to
	if variant % 3 == 0:
		# Mortar line at top (memory of the brick above)
		for dx in range(-1, brick_w + 1):
			var px = brick_x + dx
			var py = brick_y - 1
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if rng.randf() < 0.5:
					img.set_pixel(px, py, palette["mortar"])

	# Memory glow around the brick
	for dy in range(-2, brick_h + 3):
		for dx in range(-2, brick_w + 3):
			var px = brick_x + dx
			var py = brick_y + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var current = img.get_pixel(px, py)
				if current.r > 0.93 and current.g > 0.93:  # Only white pixels
					var dist_to_brick = max(0, max(-dx, dx - brick_w + 1, -dy, dy - brick_h + 1))
					if dist_to_brick > 0 and dist_to_brick < 3:
						var intensity = 0.08 * (1.0 - dist_to_brick / 3.0)
						img.set_pixel(px, py, current.lerp(palette["memory_glow"], intensity))


## FRAGMENT_CIRCUIT - A single circuit trace on white (memory of technology)
## A fragment of logic. It still tries to carry a signal, but there is nothing left to power.
func _draw_fragment_circuit(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 70007

	# Background texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.14 + y * 0.11 + variant * 0.7) * 0.08 + rng.randf() * 0.02
			if n > 0.06:
				img.set_pixel(x, y, palette["dust"])

	# Circuit trace - a path that goes somewhere specific
	var start_x = rng.randi_range(4, 10)
	var start_y = TILE_SIZE / 2 + rng.randi_range(-4, 4)
	var trace_segments: Array[Vector2i] = []

	# Generate a believable circuit path
	var cx = start_x
	var cy = start_y
	var direction = 0  # 0=right, 1=down, 2=up
	for _seg in range(rng.randi_range(4, 7)):
		var seg_len = rng.randi_range(3, 8)
		for _s in range(seg_len):
			if cx >= 0 and cx < TILE_SIZE and cy >= 0 and cy < TILE_SIZE:
				trace_segments.append(Vector2i(cx, cy))
			match direction:
				0: cx += 1
				1: cy += 1
				2: cy -= 1
		# Turn
		direction = rng.randi_range(0, 2)

	# Draw the trace
	for pos in trace_segments:
		if pos.x >= 0 and pos.x < TILE_SIZE and pos.y >= 0 and pos.y < TILE_SIZE:
			img.set_pixel(pos.x, pos.y, palette["trace_green"])
			# Trace has width
			if pos.x + 1 < TILE_SIZE:
				img.set_pixel(pos.x + 1, pos.y, palette["trace_dark"])
			if pos.y + 1 < TILE_SIZE:
				img.set_pixel(pos.x, pos.y + 1, palette["trace_dark"])

	# Solder points at trace turns/endpoints
	if trace_segments.size() > 0:
		var first = trace_segments[0]
		var last = trace_segments[trace_segments.size() - 1]
		for point in [first, last]:
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px = point.x + dx
					var py = point.y + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						img.set_pixel(px, py, palette["solder"])
			img.set_pixel(point.x, point.y, palette["trace_bright"])

	# A single tiny component - resistor or capacitor shape
	if variant % 2 == 0 and trace_segments.size() > 3:
		var mid_idx = trace_segments.size() / 2
		var comp = trace_segments[mid_idx]
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var px = comp.x + dx
				var py = comp.y + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					if dx == 0 or dy == 0:
						img.set_pixel(px, py, palette["copper"])

	# Memory glow along the trace
	for pos in trace_segments:
		for r in range(2, 4):
			for angle in range(0, 360, 90):
				var rad = deg_to_rad(angle)
				var gx = pos.x + int(cos(rad) * r)
				var gy = pos.y + int(sin(rad) * r)
				if gx >= 0 and gx < TILE_SIZE and gy >= 0 and gy < TILE_SIZE:
					var current = img.get_pixel(gx, gy)
					if current.r > 0.93:
						img.set_pixel(gx, gy, current.lerp(palette["memory_glow"], 0.06))


## SHELF_UNIT - Minimalist container where removed things are stored (impassable)
## The Catalog stores everything that was optimized away. These shelves are mostly empty.
func _draw_shelf_unit(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 80008

	# Shelf frame - clean, geometric, minimal
	var frame_left = 2
	var frame_right = TILE_SIZE - 3
	var frame_top = 1
	var frame_bot = TILE_SIZE - 2

	# Outer frame
	for x in range(frame_left, frame_right + 1):
		img.set_pixel(x, frame_top, palette["frame"])
		img.set_pixel(x, frame_bot, palette["frame"])
	for y in range(frame_top, frame_bot + 1):
		img.set_pixel(frame_left, y, palette["frame"])
		img.set_pixel(frame_right, y, palette["frame"])

	# Frame highlights and shadows for depth
	for x in range(frame_left + 1, frame_right):
		img.set_pixel(x, frame_top + 1, palette["highlight"])
		img.set_pixel(x, frame_bot - 1, palette["shadow"])
	for y in range(frame_top + 1, frame_bot):
		img.set_pixel(frame_left + 1, y, palette["highlight"])
		img.set_pixel(frame_right - 1, y, palette["shadow"])

	# Interior void - empty shelves
	for y in range(frame_top + 2, frame_bot - 1):
		for x in range(frame_left + 2, frame_right - 1):
			img.set_pixel(x, y, palette["void_inside"])

	# Horizontal shelf dividers (3 shelves)
	var shelf_spacing = (frame_bot - frame_top - 2) / 3
	for s in range(1, 3):
		var sy = frame_top + 2 + s * shelf_spacing
		if sy < frame_bot - 1:
			for x in range(frame_left + 1, frame_right):
				img.set_pixel(x, sy, palette["shelf"])
				if sy + 1 < frame_bot:
					img.set_pixel(x, sy + 1, palette["shadow"])

	# Tiny labels on shelves - what was stored here?
	for s in range(3):
		var label_y = frame_top + 3 + s * shelf_spacing
		var label_x = frame_left + 3 + rng.randi_range(0, 4)
		var label_len = rng.randi_range(3, 6)
		for i in range(label_len):
			var px = label_x + i
			if px < frame_right - 2 and label_y < frame_bot - 2:
				img.set_pixel(px, label_y, palette["label"])

	# One shelf might have a tiny something on it (or not)
	if variant % 4 == 0:
		var item_shelf = rng.randi_range(0, 2)
		var item_y = frame_top + 2 + item_shelf * shelf_spacing - 2
		var item_x = rng.randi_range(frame_left + 4, frame_right - 6)
		if item_y > frame_top + 1 and item_y < frame_bot - 3:
			for dx in range(3):
				for dy in range(2):
					if item_x + dx < frame_right - 1 and item_y + dy < frame_bot - 1:
						img.set_pixel(item_x + dx, item_y + dy, palette["edge"])


## ECHO_WALL - Barely-visible wall outline (impassable)
## A wall that used to be here. Or will be here. Or is here in a different timeline.
func _draw_echo_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 90009

	# Multiple echoing wall outlines, each fainter than the last
	var echo_count = 3
	for echo in range(echo_count):
		var offset = echo * 2
		var echo_palette_key = "echo%d" % (echo + 1)
		var col = palette.get(echo_palette_key, palette["outline_faint"])

		# Wall outline rectangle, slightly offset each echo
		var left = 3 + offset
		var right = TILE_SIZE - 4 - offset
		var top = 2 + offset
		var bot = TILE_SIZE - 3 - offset

		if left >= right or top >= bot:
			continue

		# Top edge
		for x in range(left, right + 1):
			if x < TILE_SIZE:
				img.set_pixel(x, top, col)
		# Bottom edge
		for x in range(left, right + 1):
			if x < TILE_SIZE and bot < TILE_SIZE:
				img.set_pixel(x, bot, col)
		# Left edge
		for y in range(top, bot + 1):
			if y < TILE_SIZE:
				img.set_pixel(left, y, col)
		# Right edge
		for y in range(top, bot + 1):
			if right < TILE_SIZE and y < TILE_SIZE:
				img.set_pixel(right, y, col)

	# Primary wall outline (darkest)
	for x in range(1, TILE_SIZE - 1):
		img.set_pixel(x, 0, palette["outline"])
		img.set_pixel(x, TILE_SIZE - 1, palette["outline"])
	for y in range(1, TILE_SIZE - 1):
		img.set_pixel(0, y, palette["outline"])
		img.set_pixel(TILE_SIZE - 1, y, palette["outline"])

	# Corner reinforcements
	for d in range(3):
		img.set_pixel(d, d, palette["corner"])
		img.set_pixel(TILE_SIZE - 1 - d, d, palette["corner"])
		img.set_pixel(d, TILE_SIZE - 1 - d, palette["corner"])
		img.set_pixel(TILE_SIZE - 1 - d, TILE_SIZE - 1 - d, palette["corner"])

	# Interior is slightly different from pure void
	for y in range(1, TILE_SIZE - 1):
		for x in range(1, TILE_SIZE - 1):
			var current = img.get_pixel(x, y)
			if current == palette["base"]:
				img.set_pixel(x, y, palette["inner"])

	# Occasional "flicker" - the wall briefly becomes more solid
	if variant % 5 == 0:
		var flicker_row = rng.randi_range(4, TILE_SIZE - 5)
		for x in range(2, TILE_SIZE - 2):
			if rng.randf() < 0.3:
				img.set_pixel(x, flicker_row, palette["shadow"])


## THRESHOLD_FADE - Gradient from white to lighter white (transition zone)
## The edge of where geometry dissolves. Walk further north and the world ends.
func _draw_threshold_fade(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base_top"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11011

	# Vertical gradient - dissolving toward the top
	for y in range(TILE_SIZE):
		var t = float(y) / float(TILE_SIZE - 1)
		var base_color = palette["base_top"].lerp(palette["base_bot"], t)
		for x in range(TILE_SIZE):
			var noise = sin(x * 0.3 + y * 0.2 + variant * 1.2) * 0.02 + rng.randf() * 0.01
			var col = base_color
			if noise > 0.015:
				col = col.lerp(palette["glow"], 0.1)
			elif noise < -0.01:
				col = col.lerp(palette["dissolve1"], 0.15)
			img.set_pixel(x, y, col)

	# Dissolving particles near the top - geometry breaking down
	for _p in range(rng.randi_range(3, 8)):
		var px = rng.randi_range(0, TILE_SIZE - 1)
		var py = rng.randi_range(0, TILE_SIZE / 2)
		var particle_col = palette["particle"] if rng.randf() < 0.5 else palette["dissolve2"]
		img.set_pixel(px, py, particle_col)

	# Temperature variation
	if variant % 3 == 0:
		for y in range(TILE_SIZE / 2, TILE_SIZE):
			for x in range(TILE_SIZE):
				if rng.randf() < 0.02:
					img.set_pixel(x, y, palette["warm"])
	elif variant % 3 == 1:
		for y in range(0, TILE_SIZE / 2):
			for x in range(TILE_SIZE):
				if rng.randf() < 0.02:
					img.set_pixel(x, y, palette["cool"])

	# Horizontal lines that get fainter toward the top (the grid dissolving)
	for row in range(0, TILE_SIZE, 8):
		var alpha = float(row) / float(TILE_SIZE)  # Fainter at top
		if alpha < 0.3:
			continue
		for x in range(TILE_SIZE):
			if rng.randf() < alpha * 0.4:
				img.set_pixel(x, row, palette["dissolve1"])


## COLOR_SPOT - A single spot of vivid color on white (meaning persists)
## In a world where everything unnecessary was removed, this color REFUSED to go.
## It is the most important tile in the game.
func _draw_color_spot(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12012

	# Subtle background
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.12 + y * 0.1 + variant * 0.5) * 0.06 + rng.randf() * 0.02
			if n > 0.05:
				img.set_pixel(x, y, palette["bleed"])

	# Choose which color this spot represents
	var color_options = [
		palette["color_core"],   # Red - passion, anger, love
		palette["color_warm"],   # Orange - warmth, memory, fire
		palette["color_cool"],   # Blue - sadness, sky, depth
		palette["color_life"],   # Green - life, growth, hope
	]
	var chosen_color = color_options[variant % color_options.size()]

	# The color spot itself - radial gradient, vivid at center
	var cx = TILE_SIZE / 2
	var cy = TILE_SIZE / 2
	var max_radius = 6.0

	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist < max_radius:
				var intensity = 1.0 - (dist / max_radius)
				intensity = intensity * intensity  # Quadratic falloff
				var pixel_col = palette["base"].lerp(chosen_color, intensity)
				img.set_pixel(x, y, pixel_col)

	# Inner core - pure, undiluted color
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var px = cx + dx
			var py = cy + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if abs(dx) + abs(dy) <= 1:
					img.set_pixel(px, py, chosen_color)

	# Glow ring - color bleeding outward into the white
	for angle in range(0, 360, 5):
		var rad = deg_to_rad(angle)
		for r in range(int(max_radius), int(max_radius) + 4):
			var gx = cx + int(cos(rad) * r)
			var gy = cy + int(sin(rad) * r)
			if gx >= 0 and gx < TILE_SIZE and gy >= 0 and gy < TILE_SIZE:
				var current = img.get_pixel(gx, gy)
				var bleed_strength = 0.05 * (1.0 - float(r - int(max_radius)) / 4.0)
				img.set_pixel(gx, gy, current.lerp(palette["glow_outer"], bleed_strength))

	# Sparkle at the very center
	img.set_pixel(cx, cy, palette["glow_inner"])


## STATIC_TILE - TV static/noise pattern (corruption/memory loss)
## When data is lost, this is what remains. Not silence - noise.
func _draw_static_tile(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 13013

	# Random noise - every pixel gets a random gray value
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var noise_val = rng.randf()
			var col: Color
			if noise_val < 0.12:
				col = palette["noise_dark"]
			elif noise_val < 0.30:
				col = palette["dark"]
			elif noise_val < 0.50:
				col = palette["mid"]
			elif noise_val < 0.70:
				col = palette["noise_gray"]
			elif noise_val < 0.88:
				col = palette["light"]
			else:
				col = palette["noise_white"]
			img.set_pixel(x, y, col)

	# Horizontal scanlines (CRT effect) - every 4th row is darker
	for y in range(0, TILE_SIZE, 4):
		for x in range(TILE_SIZE):
			var current = img.get_pixel(x, y)
			img.set_pixel(x, y, current.darkened(0.08))

	# Occasional "signal" trying to come through - horizontal bands of coherent color
	if variant % 3 == 0:
		var band_y = rng.randi_range(8, TILE_SIZE - 12)
		var band_h = rng.randi_range(2, 4)
		for y in range(band_y, min(band_y + band_h, TILE_SIZE)):
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, palette["scanline"])

	# Very rare: a single recognizable pixel of color (data trying to persist)
	if variant % 6 == 0:
		var signal_x = rng.randi_range(4, TILE_SIZE - 5)
		var signal_y = rng.randi_range(4, TILE_SIZE - 5)
		img.set_pixel(signal_x, signal_y, Color(0.85, 0.22, 0.28))

	# Vertical tear/roll (tracking error)
	if variant % 4 == 1:
		var tear_x = rng.randi_range(6, TILE_SIZE - 6)
		for y in range(TILE_SIZE):
			var offset = rng.randi_range(-1, 1)
			var px = tear_x + offset
			if px >= 0 and px < TILE_SIZE:
				img.set_pixel(px, y, palette["noise_white"])


## SHADOW_TILE - A shadow with no object casting it
## Something was here. Something that cast a shadow. The object is gone but its shadow stayed.
func _draw_shadow_tile(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 14014

	# Clean white background with minimal noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.1 + y * 0.08 + variant * 0.4) * 0.04 + rng.randf() * 0.01
			if n > 0.03:
				img.set_pixel(x, y, palette["ground"])

	# The shadow shape - varies by variant
	var shadow_type = variant % 4
	match shadow_type:
		0:
			# Humanoid shadow (someone was standing here)
			var cx = TILE_SIZE / 2
			# Head shadow (oval)
			for dy in range(-3, 3):
				for dx in range(-2, 3):
					var dist = sqrt(pow(dx / 2.0, 2) + pow(dy / 2.5, 2))
					if dist < 1.2:
						var px = cx + dx
						var py = 6 + dy
						if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
							img.set_pixel(px, py, palette["shadow_mid"])
			# Body shadow (rectangle with soft edges)
			for dy in range(9, 26):
				var width = 4 if dy < 20 else 3
				for dx in range(-width, width + 1):
					var px = cx + dx
					if px >= 0 and px < TILE_SIZE and dy < TILE_SIZE:
						var edge_fade = 1.0 - (abs(dx) / float(width + 1))
						var shade = palette["shadow_light"].lerp(palette["shadow_dark"], edge_fade * 0.6)
						img.set_pixel(px, dy, shade)
			# Shadow core
			for dy in range(10, 24):
				for dx in range(-1, 2):
					var px = cx + dx
					if px >= 0 and px < TILE_SIZE and dy < TILE_SIZE:
						img.set_pixel(px, dy, palette["shadow_core"])
		1:
			# Tree shadow (something organic, branching)
			var trunk_x = TILE_SIZE / 2 - 1
			# Trunk shadow
			for y in range(14, TILE_SIZE - 2):
				for dx in range(2):
					var px = trunk_x + dx
					if px < TILE_SIZE:
						img.set_pixel(px, y, palette["shadow_mid"])
			# Canopy shadow (irregular blob)
			for y in range(4, 16):
				for x in range(4, TILE_SIZE - 4):
					var dist = sqrt(pow(x - TILE_SIZE / 2, 2) + pow(y - 10, 2))
					var wobble = sin(x * 0.5 + y * 0.3 + variant * 0.7) * 2.0
					if dist + wobble < 9:
						var fade = dist / 9.0
						var shade = palette["shadow_light"].lerp(palette["shadow_dark"], 1.0 - fade)
						img.set_pixel(x, y, shade)
		2:
			# Geometric shadow (a cube or structure that no longer exists)
			var ox = 8
			var oy = 8
			# Main rectangle shadow
			for dy in range(16):
				for dx in range(14):
					var px = ox + dx
					var py = oy + dy
					if px < TILE_SIZE and py < TILE_SIZE:
						var edge_dist = min(dx, 13 - dx, dy, 15 - dy)
						var shade = palette["shadow_light"]
						if edge_dist > 4:
							shade = palette["shadow_dark"]
						elif edge_dist > 2:
							shade = palette["shadow_mid"]
						img.set_pixel(px, py, shade)
		3:
			# Scattered/broken shadow (something that shattered)
			for _fragment in range(rng.randi_range(5, 9)):
				var fx = rng.randi_range(4, TILE_SIZE - 8)
				var fy = rng.randi_range(4, TILE_SIZE - 8)
				var fw = rng.randi_range(2, 5)
				var fh = rng.randi_range(2, 4)
				for dy in range(fh):
					for dx in range(fw):
						var px = fx + dx
						var py = fy + dy
						if px < TILE_SIZE and py < TILE_SIZE:
							var shade = palette["shadow_mid"] if rng.randf() < 0.6 else palette["shadow_light"]
							img.set_pixel(px, py, shade)

	# Edge softening - shadows fade at borders
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var current = img.get_pixel(x, y)
			if current != palette["base"] and current != palette["ground"]:
				var edge_x = min(x, TILE_SIZE - 1 - x)
				var edge_y = min(y, TILE_SIZE - 1 - y)
				var edge_min = min(edge_x, edge_y)
				if edge_min < 2:
					img.set_pixel(x, y, current.lerp(palette["base"], 0.4 * (2.0 - edge_min) / 2.0))


## QUESTION_MARK - A subtle ? shape embedded in the floor
## The last question anyone asked before questioning itself was optimized away.
func _draw_question_mark(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 15015

	# Subtle background texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.13 + y * 0.11 + variant * 0.6) * 0.06 + rng.randf() * 0.02
			if n > 0.05:
				img.set_pixel(x, y, palette["dust"])

	# The question mark shape - drawn with subtle near-white colors
	var cx = TILE_SIZE / 2
	var mark_color = palette["mark_mid"]

	# Top curve of the ?
	# Upper arc
	for angle in range(-30, 210, 8):
		var rad = deg_to_rad(angle)
		var radius = 6.0
		var ax = cx + int(cos(rad) * radius)
		var ay = 10 + int(sin(rad) * radius * -1)
		if ax >= 0 and ax < TILE_SIZE and ay >= 0 and ay < TILE_SIZE:
			img.set_pixel(ax, ay, mark_color)
			# Thickness
			if ax + 1 < TILE_SIZE:
				img.set_pixel(ax + 1, ay, palette["mark_light"])

	# Right side descender
	for y in range(10, 16):
		var px = cx + 3
		if px < TILE_SIZE:
			img.set_pixel(px, y, mark_color)
			if px + 1 < TILE_SIZE:
				img.set_pixel(px + 1, y, palette["mark_light"])

	# Curve inward
	for y in range(16, 19):
		var offset = y - 16
		var px = cx + 3 - offset
		if px >= 0 and px < TILE_SIZE and y < TILE_SIZE:
			img.set_pixel(px, y, mark_color)

	# Vertical stem
	for y in range(19, 23):
		img.set_pixel(cx, y, mark_color)
		if cx + 1 < TILE_SIZE:
			img.set_pixel(cx + 1, y, palette["mark_light"])

	# Dot at the bottom
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var px = cx + dx
			var py = 26 + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if abs(dx) + abs(dy) <= 1:
					img.set_pixel(px, py, palette["dot"])

	# Faint glow around the question mark
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var current = img.get_pixel(x, y)
			if current == mark_color or current == palette["mark_light"] or current == palette["dot"]:
				# Add glow to neighbors
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						var gx = x + dx
						var gy = y + dy
						if gx >= 0 and gx < TILE_SIZE and gy >= 0 and gy < TILE_SIZE:
							var neighbor = img.get_pixel(gx, gy)
							if neighbor == palette["base"] or neighbor == palette["dust"]:
								var dist = sqrt(dx * dx + dy * dy)
								if dist > 0 and dist < 3:
									img.set_pixel(gx, gy, palette["glow"])

	# Echo marks - fainter question marks at offset (variant-dependent)
	if variant % 3 == 0:
		var echo_x = cx + rng.randi_range(-2, 2)
		var echo_y = 26
		if echo_x >= 0 and echo_x < TILE_SIZE and echo_y < TILE_SIZE:
			img.set_pixel(echo_x, echo_y, palette["echo"])


## FOOTPRINT_TILE - Previous visitors' traces, barely visible
## Others have walked here before you. Their footprints are almost gone.
func _draw_footprint_tile(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 16016

	# Subtle background
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.12 + y * 0.1 + variant * 0.5) * 0.05 + rng.randf() * 0.015
			if n > 0.04:
				img.set_pixel(x, y, palette["dust"])

	# Footprint pairs (shoe-shaped outlines, very faint)
	var print_count = rng.randi_range(1, 3)
	for _p in range(print_count):
		var foot_x = rng.randi_range(4, TILE_SIZE - 10)
		var foot_y = rng.randi_range(4, TILE_SIZE - 12)
		var is_left = rng.randf() < 0.5
		var age = rng.randi_range(0, 2)  # 0=fresh-ish, 1=old, 2=nearly gone

		var print_color: Color
		match age:
			0: print_color = palette["print_dark"]
			1: print_color = palette["print_mid"]
			2: print_color = palette["print_light"]
			_: print_color = palette["print_mid"]

		# Shoe sole shape (simplified)
		# Heel
		for dy in range(6, 8):
			for dx in range(1, 4):
				var px = foot_x + (dx if is_left else 5 - dx)
				var py = foot_y + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					if rng.randf() < 0.7 or age < 2:
						img.set_pixel(px, py, print_color)

		# Arch (gap in middle)
		for dy in range(3, 6):
			for dx in range(1, 5):
				var px = foot_x + (dx if is_left else 5 - dx)
				var py = foot_y + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					if (dx == 1 or dx == 4) and rng.randf() < 0.5:
						img.set_pixel(px, py, print_color)

		# Ball of foot
		for dy in range(0, 3):
			for dx in range(0, 5):
				var px = foot_x + (dx if is_left else 5 - dx)
				var py = foot_y + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					if rng.randf() < 0.6 or age < 1:
						img.set_pixel(px, py, print_color)

	# Warmth trace - footprints retain a ghost of body heat
	if variant % 4 == 0:
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				if current == palette["print_dark"] or current == palette["print_mid"]:
					img.set_pixel(x, y, current.lerp(palette["warmth"], 0.15))


## REMNANT_DOOR - Outline of a door that leads nowhere (impassable)
## A door frame with nothing behind it. Opening it would reveal... the same room.
func _draw_remnant_door(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 17017

	# Door frame outline - architectural ghost
	var door_left = 6
	var door_right = TILE_SIZE - 7
	var door_top = 2
	var door_bot = TILE_SIZE - 3

	# Outer frame
	for x in range(door_left - 1, door_right + 2):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, door_top - 1, palette["frame"])
			img.set_pixel(x, door_top, palette["frame_dark"])
	for y in range(door_top, door_bot + 1):
		if door_left - 1 >= 0:
			img.set_pixel(door_left - 1, y, palette["frame"])
			img.set_pixel(door_left, y, palette["frame_dark"])
		if door_right + 1 < TILE_SIZE:
			img.set_pixel(door_right + 1, y, palette["frame"])
			img.set_pixel(door_right, y, palette["frame_dark"])

	# Inner frame (lighter)
	for x in range(door_left + 1, door_right):
		img.set_pixel(x, door_top + 1, palette["frame_light"])
	for y in range(door_top + 1, door_bot):
		img.set_pixel(door_left + 1, y, palette["frame_light"])
		img.set_pixel(door_right - 1, y, palette["frame_light"])

	# Door interior - slightly different shade than surroundings
	for y in range(door_top + 2, door_bot):
		for x in range(door_left + 2, door_right - 1):
			img.set_pixel(x, y, palette["inner"])

	# Panel outlines (two rectangles suggesting traditional door panels)
	var panel_left = door_left + 3
	var panel_right = door_right - 2
	# Upper panel
	for x in range(panel_left, panel_right):
		img.set_pixel(x, door_top + 4, palette["shadow"])
		img.set_pixel(x, door_top + 10, palette["shadow"])
	for y in range(door_top + 4, door_top + 11):
		img.set_pixel(panel_left, y, palette["shadow"])
		img.set_pixel(panel_right - 1, y, palette["shadow"])
	# Lower panel
	for x in range(panel_left, panel_right):
		img.set_pixel(x, door_top + 13, palette["shadow"])
		img.set_pixel(x, door_bot - 3, palette["shadow"])
	for y in range(door_top + 13, door_bot - 2):
		img.set_pixel(panel_left, y, palette["shadow"])
		img.set_pixel(panel_right - 1, y, palette["shadow"])

	# Ghost of a door handle
	var handle_x = door_right - 4
	var handle_y = (door_top + door_bot) / 2
	for dy in range(-1, 2):
		for dx in range(-1, 1):
			var px = handle_x + dx
			var py = handle_y + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				img.set_pixel(px, py, palette["handle"])

	# Threshold at bottom
	for x in range(door_left - 1, door_right + 2):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, door_bot, palette["threshold"])
			img.set_pixel(x, door_bot + 1, palette["threshold"])

	# Memory warmth - this door was used once
	if variant % 3 == 0:
		for y in range(door_top + 2, door_bot):
			for x in range(door_left + 2, door_right - 1):
				var current = img.get_pixel(x, y)
				if rng.randf() < 0.04:
					img.set_pixel(x, y, current.lerp(palette["memory"], 0.2))


## Create tileset with all abstract tiles
func create_tileset() -> TileSet:
	print("Creating abstract void tileset...")
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
		# Row 0: Void foundations
		TileType.VOID_WHITE, TileType.VOID_GRAY, TileType.VOID_BLACK, TileType.GRID_LINE,
		# Row 1: Memory fragments
		TileType.FRAGMENT_GRASS, TileType.FRAGMENT_BRICK, TileType.FRAGMENT_CIRCUIT, TileType.SHELF_UNIT,
		# Row 2: Structures and transitions
		TileType.ECHO_WALL, TileType.THRESHOLD_FADE, TileType.COLOR_SPOT, TileType.STATIC_TILE,
		# Row 3: Traces and remnants
		TileType.SHADOW_TILE, TileType.QUESTION_MARK, TileType.FOOTPRINT_TILE, TileType.REMNANT_DOOR
	]

	# Impassable tile types (need collision)
	var impassable_types = [
		TileType.VOID_BLACK, TileType.SHELF_UNIT, TileType.ECHO_WALL,
		TileType.REMNANT_DOOR
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
	atlas_img.save_png("user://debug_abstract_atlas.png")
	print("Abstract atlas saved (size: %dx%d, %d tiles)" % [atlas_img.get_width(), atlas_img.get_height(), tile_order.size()])

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
