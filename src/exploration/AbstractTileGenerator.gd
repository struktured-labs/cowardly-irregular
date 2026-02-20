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
## Stare long enough and your eyes invent patterns - phantom grain, ghostly Moire,
## the visual equivalent of silence so deep you hear your own blood.
func _draw_void_white(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 10001

	# Layer 1: Perlin-ish noise field - so subtle it might be your imagination
	# Multiple overlapping sine waves at different frequencies create organic grain
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Three octaves of noise, each barely visible
			var n1 = sin(x * 0.15 + variant * 0.7) * cos(y * 0.12 + variant * 0.4) * 0.35
			var n2 = sin(x * 0.4 + y * 0.3 + variant * 1.1) * 0.2
			var n3 = sin(x * 0.8 + y * 0.7 - variant * 0.3) * cos(x * 0.2 - y * 0.5) * 0.1
			# Micro-dithering: individual pixel noise, barely above threshold
			var dither = (rng.randf() - 0.5) * 0.06
			var combined = n1 + n2 + n3 + dither

			if combined < -0.25:
				img.set_pixel(x, y, palette["grain1"])
			elif combined < -0.12:
				# Ghostly pattern - your eyes create shapes that aren't there
				img.set_pixel(x, y, palette["absence"])
			elif combined > 0.22:
				img.set_pixel(x, y, palette["breath"])
			elif combined > 0.10:
				img.set_pixel(x, y, palette["grain2"])
			elif combined > 0.05:
				img.set_pixel(x, y, palette["nothing"])

	# Layer 2: Phantom Moire pattern - concentric circles so faint they
	# appear and disappear as your eyes move. The void breathes.
	var center_x = TILE_SIZE / 2 + int(sin(variant * 1.7) * 6)
	var center_y = TILE_SIZE / 2 + int(cos(variant * 2.3) * 6)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - center_x, 2) + pow(y - center_y, 2))
			var ring = sin(dist * 0.6 + variant * 0.9) * 0.5 + 0.5
			if ring > 0.92 and rng.randf() < 0.15:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(palette["grain1"], 0.25))

	# Layer 3: Temperature drift - warm or cool currents barely perceptible,
	# like air moving in an empty room
	var drift_angle = variant * 0.618  # Golden ratio for non-repeating drift
	var drift_dx = cos(drift_angle)
	var drift_dy = sin(drift_angle)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var projected = x * drift_dx + y * drift_dy
			var wave = sin(projected * 0.12 + variant * 0.4) * 0.5 + 0.5
			if wave > 0.88 and rng.randf() < 0.08:
				var current = img.get_pixel(x, y)
				var drift_col = palette["warm"] if variant % 3 == 0 else palette["cool"]
				img.set_pixel(x, y, current.lerp(drift_col, 0.12))

	# Layer 4: Rare dust motes - single pixels that suggest particles
	# floating in the void, visible only because the void is so empty
	if variant % 5 == 0:
		var mote_count = rng.randi_range(1, 2)
		for _m in range(mote_count):
			var mx = rng.randi_range(3, TILE_SIZE - 4)
			var my = rng.randi_range(3, TILE_SIZE - 4)
			img.set_pixel(mx, my, palette["dust"])
			# Mote has the faintest halo
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var hx = mx + d.x
				var hy = my + d.y
				if hx >= 0 and hx < TILE_SIZE and hy >= 0 and hy < TILE_SIZE:
					var current = img.get_pixel(hx, hy)
					img.set_pixel(hx, hy, current.lerp(palette["dust"], 0.06))


## VOID_GRAY - Slightly darker void suggesting depth beneath the white
## Like looking down into fog from a great height. There are layers below -
## gray within gray within gray, each one slightly darker, receding forever.
## You could fall into this. You might already be falling.
func _draw_void_gray(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 20002

	# Layer 1: Deep fog turbulence - billowing clouds of gray suggesting
	# massive depth below the surface. Each pixel is a window into the abyss.
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			# Multiple fog layers at different "depths"
			var shallow = sin(x * 0.2 + y * 0.15 + variant * 0.9) * 0.25
			var mid_depth = sin(x * 0.35 + y * 0.28 + variant * 1.6) * 0.18
			var deep_layer = sin(x * 0.55 + y * 0.45 + variant * 2.3) * 0.12
			var turbulence = sin(x * 0.7 + y * 0.5 + variant * 1.6) * 0.08
			var combined = shallow + mid_depth + deep_layer + turbulence + rng.randf() * 0.05

			if combined < -0.30:
				img.set_pixel(x, y, palette["deep"])
			elif combined < -0.18:
				img.set_pixel(x, y, palette["dark"])
			elif combined < -0.06:
				img.set_pixel(x, y, palette["edge"])
			elif combined > 0.20:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.08:
				img.set_pixel(x, y, palette["mid"])

	# Layer 2: Vertical depth gradient - darker toward the center,
	# as if the tile is a well you're peering into
	var well_cx = TILE_SIZE / 2 + int(sin(variant * 1.1) * 4)
	var well_cy = TILE_SIZE / 2 + int(cos(variant * 0.7) * 4)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist_from_center = sqrt(pow(x - well_cx, 2) + pow(y - well_cy, 2))
			var depth_factor = 1.0 - clamp(dist_from_center / 18.0, 0.0, 1.0)
			if depth_factor > 0.1:
				var current = img.get_pixel(x, y)
				var deeper = current.lerp(palette["dark"], depth_factor * 0.15)
				img.set_pixel(x, y, deeper)

	# Layer 3: Fog wisps - thin streaks that suggest movement in the depths
	var wisp_count = rng.randi_range(2, 4)
	for _w in range(wisp_count):
		var wy = rng.randi_range(4, TILE_SIZE - 5)
		var wx_start = rng.randi_range(0, TILE_SIZE / 3)
		var wx_end = rng.randi_range(TILE_SIZE * 2 / 3, TILE_SIZE)
		for wx in range(wx_start, wx_end):
			if wx >= 0 and wx < TILE_SIZE:
				var wisp_y = wy + int(sin(wx * 0.3 + variant * 0.5) * 1.5)
				if wisp_y >= 0 and wisp_y < TILE_SIZE:
					var fade = sin(float(wx - wx_start) / float(wx_end - wx_start) * PI)
					var current = img.get_pixel(wx, wisp_y)
					img.set_pixel(wx, wisp_y, current.lerp(palette["light"], fade * 0.12))

	# Layer 4: Temperature - the fog has warm and cool pockets
	var temp_shift = sin(variant * 2.3) * 0.5 + 0.5
	var temp_col = palette["warm"] if temp_shift > 0.5 else palette["cool"]
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var temp_noise = sin(x * 0.25 + y * 0.2 + variant * 3.1) * 0.5 + 0.5
			if temp_noise > 0.85 and rng.randf() < 0.06:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(temp_col, 0.08))

	# Layer 5: Edge dissolution - the gray fades to white at borders,
	# suggesting the fog recedes where it meets the void
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var edge_dist = min(min(x, TILE_SIZE - 1 - x), min(y, TILE_SIZE - 1 - y))
			if edge_dist < 4:
				var fade_amount = (4.0 - edge_dist) / 4.0
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(palette["fade"], fade_amount * 0.3))


## VOID_BLACK - Deep absence, the REAL void (impassable)
## Not just darkness - the complete absence of everything. Even absence is absent here.
## Stare into it and you feel it staring back. Occasionally a star flickers -
## impossibly distant, from a universe that was also optimized away.
func _draw_void_black(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 30003

	# Layer 1: The base void - not flat black but unsettlingly varied,
	# like the darkness behind your eyelids that shifts and churns
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.3 + y * 0.25 + variant * 1.4) * 0.18
			var n2 = sin(x * 0.6 - y * 0.4 + variant * 2.7) * 0.10
			var n3 = cos(x * 0.15 + y * 0.35 + variant * 0.6) * 0.08
			var noise = rng.randf() * 0.06
			var combined = n1 + n2 + n3 + noise

			if combined < -0.20:
				img.set_pixel(x, y, palette["abyss"])
			elif combined < -0.08:
				img.set_pixel(x, y, palette["deep"])
			elif combined > 0.18:
				img.set_pixel(x, y, palette["surface"])
			elif combined > 0.06:
				img.set_pixel(x, y, palette["grain"])

	# Layer 2: Deep color veins - the void is not just black, it shifts
	# between impossible dark purples and blues, like bruises in reality
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var vein = sin(x * 0.18 + y * 0.12 + variant * 3.1) * cos(x * 0.08 - y * 0.2)
			if vein > 0.35 and rng.randf() < 0.12:
				var current = img.get_pixel(x, y)
				var vein_col = palette["void_purple"] if variant % 3 != 2 else palette["void_blue"]
				img.set_pixel(x, y, current.lerp(vein_col, 0.3))
			elif vein < -0.35 and rng.randf() < 0.10:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(palette["void_blue"], 0.25))

	# Layer 3: Barely-visible stars - impossibly distant pinpricks of light
	# from a universe that was also optimized away. 1-3 per tile.
	var star_count = rng.randi_range(0, 3)
	for _s in range(star_count):
		var sx = rng.randi_range(2, TILE_SIZE - 3)
		var sy = rng.randi_range(2, TILE_SIZE - 3)
		# Star brightness varies - some are barely visible, one might twinkle
		var brightness = rng.randf_range(0.08, 0.18)
		var star_col = Color(brightness, brightness, brightness + 0.02)
		img.set_pixel(sx, sy, star_col)
		# Faintest possible diffraction spike on brightest stars
		if brightness > 0.14:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var dx = sx + d.x
				var dy = sy + d.y
				if dx >= 0 and dx < TILE_SIZE and dy >= 0 and dy < TILE_SIZE:
					var spike_col = Color(brightness * 0.3, brightness * 0.3, brightness * 0.35)
					var current = img.get_pixel(dx, dy)
					img.set_pixel(dx, dy, current.lerp(spike_col, 0.4))

	# Layer 4: Edge shimmer - the boundary between void and world is unstable,
	# as if reality is being pulled apart at the seams
	for x in range(TILE_SIZE):
		for border_y in [0, TILE_SIZE - 1]:
			if rng.randf() < 0.18:
				img.set_pixel(x, border_y, palette["shimmer"])
			elif rng.randf() < 0.06:
				img.set_pixel(x, border_y, palette["edge_glow"])
	for y in range(1, TILE_SIZE - 1):
		for border_x in [0, TILE_SIZE - 1]:
			if rng.randf() < 0.18:
				img.set_pixel(border_x, y, palette["shimmer"])
			elif rng.randf() < 0.06:
				img.set_pixel(border_x, y, palette["edge_glow"])

	# Layer 5: The deepest abyss pocket - one spot per tile that is
	# somehow DARKER than black. A hole in the hole.
	if variant % 2 == 0:
		var ax = rng.randi_range(6, TILE_SIZE - 7)
		var ay = rng.randi_range(6, TILE_SIZE - 7)
		var abyss_r = rng.randi_range(2, 4)
		for dy in range(-abyss_r, abyss_r + 1):
			for dx in range(-abyss_r, abyss_r + 1):
				var dist = sqrt(dx * dx + dy * dy)
				if dist < abyss_r:
					var px = ax + dx
					var py = ay + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						var depth = 1.0 - (dist / abyss_r)
						var current = img.get_pixel(px, py)
						img.set_pixel(px, py, current.lerp(palette["abyss"], depth * 0.5))


## GRID_LINE - The world's skeleton, faint geometric grid on white
## When everything else is stripped away, only structure remains.
## This is what reality looks like under the skin - pure coordinate space,
## the wireframe model of existence. Some lines pulse faintly, still alive.
func _draw_grid_line(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 40004

	# Layer 1: Primary grid structure - major lines every 16px, minor every 8px
	# The lines themselves have varying opacity, as if some are fading out of existence
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var on_major_x = (x % 16 == 0)
			var on_major_y = (y % 16 == 0)
			var on_minor_x = (x % 8 == 0)
			var on_minor_y = (y % 8 == 0)

			if on_major_x and on_major_y:
				# Grid intersection nodes - brighter, like synapses
				img.set_pixel(x, y, palette["node"])
				# Node glow bleeds one pixel in each direction
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx = x + d.x
					var ny = y + d.y
					if nx >= 0 and nx < TILE_SIZE and ny >= 0 and ny < TILE_SIZE:
						if not ((nx % 8 == 0) or (ny % 8 == 0)):
							img.set_pixel(nx, ny, palette["glow"])
			elif on_major_x or on_major_y:
				# Major lines - broken in places, as if the structure is decaying
				var line_fade = sin(float(y if on_major_x else x) * 0.3 + variant * 0.8) * 0.5 + 0.5
				if line_fade > 0.2:
					img.set_pixel(x, y, palette["line"] if line_fade > 0.5 else palette["line_faint"])
				else:
					# Broken segment - the line disappears briefly
					if rng.randf() < 0.15:
						img.set_pixel(x, y, palette["ghost"])
			elif on_minor_x or on_minor_y:
				# Minor lines - much fainter, dotted, flickering
				var minor_phase = sin(float(y if on_minor_x else x) * 0.5 + variant * 1.2)
				if minor_phase > 0.0 and rng.randf() < 0.45:
					img.set_pixel(x, y, palette["ghost"])

	# Layer 2: Grid pulse - data still flows through certain lines,
	# a pulse of light traveling along a line like a signal in a circuit
	var pulse_count = rng.randi_range(1, 2)
	for _p in range(pulse_count):
		var is_horizontal = rng.randf() < 0.5
		var line_pos = rng.randi_range(0, 1) * 16  # On a major line (0 or 16)
		var pulse_start = rng.randi_range(2, 10)
		var pulse_end = rng.randi_range(18, 30)
		var pulse_center = (pulse_start + pulse_end) / 2

		for i in range(pulse_start, min(pulse_end, TILE_SIZE)):
			var dist_from_center = abs(i - pulse_center)
			var pulse_intensity = 1.0 - (float(dist_from_center) / float(pulse_end - pulse_start) * 2.0)
			if pulse_intensity > 0:
				var px = i if is_horizontal else line_pos
				var py = line_pos if is_horizontal else i
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					var current = img.get_pixel(px, py)
					img.set_pixel(px, py, current.lerp(palette["pulse"], pulse_intensity * 0.4))

	# Layer 3: Perspective distortion - the grid subtly warps near edges,
	# as if we're seeing it from an angle, giving a 3D quality
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var warp = sin(x * 0.08 + y * 0.06 + variant * 0.3) * 0.003
			if warp > 0.002:
				var current = img.get_pixel(x, y)
				if current != palette["base"]:
					img.set_pixel(x, y, current.lerp(palette["skeleton"], 0.08))

	# Layer 4: Warmth spots - traces of humanity that bled into the grid
	if variant % 3 == 0:
		var warm_count = rng.randi_range(1, 3)
		for _w in range(warm_count):
			var wx = rng.randi_range(3, TILE_SIZE - 4)
			var wy = rng.randi_range(3, TILE_SIZE - 4)
			var current = img.get_pixel(wx, wy)
			img.set_pixel(wx, wy, current.lerp(palette["warmth"], 0.15))
			if wx + 1 < TILE_SIZE:
				var neighbor = img.get_pixel(wx + 1, wy)
				img.set_pixel(wx + 1, wy, neighbor.lerp(palette["warmth"], 0.08))


## FRAGMENT_GRASS - A single tuft of green on white (memory of nature)
## Everything green was optimized away. This single tuft refused to leave.
## In a world of white, this tiny splash of green is heartbreaking -
## a memory of meadows, forests, life. It sways slightly in a wind that
## no longer exists. The soil beneath it shouldn't be here either.
func _draw_fragment_grass(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 50005

	# Subtle white-on-white background with the faintest texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.15 + y * 0.12 + variant * 0.8) * 0.08 + rng.randf() * 0.02
			if n > 0.06:
				img.set_pixel(x, y, palette["dust"])

	# The precious grass fragment - centered, small, achingly vivid
	var cx = TILE_SIZE / 2 + rng.randi_range(-3, 3)
	var cy = TILE_SIZE / 2 + rng.randi_range(-1, 3)

	# Tiny irregular soil patch - the last earth that hasn't been optimized away
	for dy in range(-1, 3):
		for dx in range(-3, 4):
			var px = cx + dx
			var py = cy + dy + 3
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var soil_dist = sqrt(dx * dx + dy * dy * 2)
				if soil_dist < 3.0:
					var soil_shade = palette["soil"]
					if dy == -1 or abs(dx) == 3:
						# Crumbling edges - the soil is fragmenting
						if rng.randf() < 0.5:
							soil_shade = palette["soil"].lerp(palette["base"], 0.4)
						else:
							continue
					img.set_pixel(px, py, soil_shade)

	# Grass blades - each one lovingly detailed, reaching upward
	# like tiny green prayers. Varying heights, subtle sway.
	var blade_count = rng.randi_range(4, 6)
	for b in range(blade_count):
		var bx = cx + rng.randi_range(-2, 2)
		var blade_height = rng.randi_range(5, 9)
		var sway = rng.randf_range(-0.35, 0.35)
		var thickness = 1 if b < 2 else 0  # First two blades are thicker

		for h in range(blade_height):
			var sway_amount = sin(h * 0.45 + sway * 2.5) * (h * 0.18)
			var px = bx + int(sway_amount)
			var py = cy + 2 - h
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				# Color gradient: dark at base, vivid in middle, bright at tip
				var shade: Color
				var t = float(h) / float(blade_height)
				if t < 0.2:
					shade = palette["grass_dark"]
				elif t < 0.7:
					shade = palette["grass_green"]
				else:
					shade = palette["grass_light"]
				img.set_pixel(px, py, shade)

				# Thicker blades have a highlight edge
				if thickness > 0 and px + 1 < TILE_SIZE:
					var highlight = shade.lightened(0.12)
					img.set_pixel(px + 1, py, highlight)

		# Tip of tallest blades has the brightest green - catching light
		# from a sun that was deleted
		if blade_height >= 7:
			var tip_px = bx + int(sin(blade_height * 0.45 + sway * 2.5) * (blade_height * 0.18))
			var tip_py = cy + 2 - blade_height
			if tip_px >= 0 and tip_px < TILE_SIZE and tip_py >= 0 and tip_py < TILE_SIZE:
				img.set_pixel(tip_px, tip_py, palette["grass_light"].lightened(0.1))

	# Memory glow - the green bleeds into the surrounding white
	# as if the grass is radiating life outward. Circular gradient halo.
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist > 4 and dist < 10:
				var current = img.get_pixel(x, y)
				if current.r > 0.92 and current.g > 0.92:  # Only bleed into white
					var intensity = (10.0 - dist) / 6.0
					img.set_pixel(x, y, current.lerp(palette["memory_glow"], intensity * 0.08))


## FRAGMENT_BRICK - A single brick floating in white (memory of civilization)
## One brick from a wall that no longer exists. It remembers being part of something.
## You can almost see the ghost of mortar where its neighbors used to be.
## It is impossibly sad - this one brick, in all this white, holding the memory
## of every building that ever was.
func _draw_fragment_brick(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 60006

	# Subtle background texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.12 + y * 0.1 + variant * 0.6) * 0.06 + rng.randf() * 0.02
			if n > 0.05:
				img.set_pixel(x, y, palette["dust"])

	# The lone brick - slightly off-center, floating in the void
	var brick_x = TILE_SIZE / 2 - 5 + rng.randi_range(-2, 2)
	var brick_y = TILE_SIZE / 2 - 3 + rng.randi_range(-2, 2)
	var brick_w = 10
	var brick_h = 6

	# Faint shadow beneath - the brick levitates slightly, as if
	# gravity itself is uncertain here
	for dx in range(-1, brick_w + 2):
		for dy in range(1, 4):
			var px = brick_x + dx
			var py = brick_y + brick_h + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var shadow_fade = 1.0 - (float(dy) / 4.0)
				var x_fade = 1.0 - abs(float(dx - brick_w / 2) / float(brick_w / 2 + 2))
				var current = img.get_pixel(px, py)
				img.set_pixel(px, py, current.lerp(palette["shadow"], shadow_fade * x_fade * 0.22))

	# The brick itself - richly textured, lovingly detailed
	# because this is the LAST BRICK. It deserves to be beautiful.
	for dy in range(brick_h):
		for dx in range(brick_w):
			var px = brick_x + dx
			var py = brick_y + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var shade = palette["brick_red"]
				# 3D beveling: top-left highlight, bottom-right shadow
				if dy == 0:
					shade = palette["brick_light"]
				elif dy == brick_h - 1:
					shade = palette["brick_dark"]
				elif dx == 0:
					shade = palette["brick_light"]
				elif dx == brick_w - 1:
					shade = palette["brick_dark"]
				elif dy == 1 and dx > 0 and dx < brick_w - 1:
					shade = shade.lightened(0.04)
				elif dy == brick_h - 2:
					shade = shade.darkened(0.03)
				else:
					# Internal grain - fired clay texture with micro-variation
					var grain1 = sin(dx * 0.8 + dy * 1.2 + variant * 0.5) * 0.10
					var grain2 = sin(dx * 1.5 + dy * 0.6 + variant * 1.2) * 0.05
					var grain = grain1 + grain2
					if grain > 0.08:
						shade = shade.lightened(0.07)
					elif grain > 0.03:
						shade = shade.lightened(0.03)
					elif grain < -0.08:
						shade = shade.darkened(0.07)
					elif grain < -0.03:
						shade = shade.darkened(0.03)
				img.set_pixel(px, py, shade)

	# Ghost mortar lines - traces of where neighboring bricks used to be
	# These extend outward from the brick, fading into nothing
	# Top mortar ghost (the brick above is gone)
	for dx in range(-2, brick_w + 2):
		var px = brick_x + dx
		var py = brick_y - 1
		if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
			var fade = 1.0 - abs(float(dx - brick_w / 2) / float(brick_w / 2 + 3))
			if rng.randf() < 0.5 * fade:
				var current = img.get_pixel(px, py)
				img.set_pixel(px, py, current.lerp(palette["mortar"], 0.25 * fade))
	# Side mortar ghosts (where neighboring bricks connected)
	for dy in range(-1, brick_h + 1):
		# Left neighbor ghost
		var left_px = brick_x - 1
		var py = brick_y + dy
		if left_px >= 0 and py >= 0 and py < TILE_SIZE and rng.randf() < 0.35:
			var current = img.get_pixel(left_px, py)
			img.set_pixel(left_px, py, current.lerp(palette["mortar"], 0.18))
		# Right neighbor ghost
		var right_px = brick_x + brick_w
		if right_px < TILE_SIZE and py >= 0 and py < TILE_SIZE and rng.randf() < 0.35:
			var current = img.get_pixel(right_px, py)
			img.set_pixel(right_px, py, current.lerp(palette["mortar"], 0.18))

	# Phantom neighbor - the very faintest outline of where the adjacent
	# brick used to be, like a watermark. Almost invisible.
	if variant % 3 == 0:
		var ghost_x = brick_x + brick_w + 1
		for dy in range(brick_h):
			for dx in range(min(brick_w, TILE_SIZE - ghost_x)):
				var px = ghost_x + dx
				var py = brick_y + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					var current = img.get_pixel(px, py)
					if current.r > 0.93:
						img.set_pixel(px, py, current.lerp(palette["memory_glow"], 0.04))

	# Memory glow - warm aura around the brick, the residual heat
	# of all the hearths this wall once sheltered
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var current = img.get_pixel(x, y)
			if current.r > 0.92 and current.g > 0.92:
				var dist_x = 0.0
				if x < brick_x:
					dist_x = brick_x - x
				elif x >= brick_x + brick_w:
					dist_x = x - (brick_x + brick_w - 1)
				var dist_y = 0.0
				if y < brick_y:
					dist_y = brick_y - y
				elif y >= brick_y + brick_h:
					dist_y = y - (brick_y + brick_h - 1)
				var dist = sqrt(dist_x * dist_x + dist_y * dist_y)
				if dist > 0 and dist < 5:
					var intensity = (5.0 - dist) / 5.0
					img.set_pixel(x, y, current.lerp(palette["memory_glow"], intensity * 0.10))


## FRAGMENT_CIRCUIT - A single circuit trace on white (memory of technology)
## A fragment of logic. It still tries to carry a signal, but there is nothing
## left to power. The trace fades at both ends - disconnected from whatever
## circuit it once belonged to. A copper solder point gleams. The last computation.
func _draw_fragment_circuit(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 70007

	# Subtle background - cleaner than other fragments, this was precision-made
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.14 + y * 0.11 + variant * 0.7) * 0.06 + rng.randf() * 0.015
			if n > 0.05:
				img.set_pixel(x, y, palette["dust"])

	# Generate a believable circuit path with proper right-angle routing
	var start_x = rng.randi_range(3, 8)
	var start_y = TILE_SIZE / 2 + rng.randi_range(-4, 4)
	var trace_segments: Array[Vector2i] = []
	var turn_points: Array[Vector2i] = []

	var cx = start_x
	var cy = start_y
	var direction = 0  # 0=right, 1=down, 2=up
	turn_points.append(Vector2i(cx, cy))

	for _seg in range(rng.randi_range(5, 8)):
		var seg_len = rng.randi_range(3, 7)
		for _s in range(seg_len):
			if cx >= 1 and cx < TILE_SIZE - 1 and cy >= 1 and cy < TILE_SIZE - 1:
				trace_segments.append(Vector2i(cx, cy))
			match direction:
				0: cx += 1
				1: cy += 1
				2: cy -= 1
		if cx >= 1 and cx < TILE_SIZE - 1 and cy >= 1 and cy < TILE_SIZE - 1:
			turn_points.append(Vector2i(cx, cy))
		# Always turn at right angles (proper PCB routing)
		if direction == 0:
			direction = 1 if rng.randf() < 0.5 else 2
		else:
			direction = 0

	# Draw the trace with fading at both ends (disconnected)
	var total_len = trace_segments.size()
	for idx in range(total_len):
		var pos = trace_segments[idx]
		if pos.x >= 0 and pos.x < TILE_SIZE and pos.y >= 0 and pos.y < TILE_SIZE:
			# Fade factor: full in middle, fading at ends
			var fade_in = min(float(idx) / 4.0, 1.0)
			var fade_out = min(float(total_len - 1 - idx) / 4.0, 1.0)
			var fade = fade_in * fade_out

			# Main trace pixel
			var trace_col = palette["base"].lerp(palette["trace_green"], fade)
			img.set_pixel(pos.x, pos.y, trace_col)

			# Trace width (2px wide for most of it)
			if fade > 0.3:
				if pos.x + 1 < TILE_SIZE:
					img.set_pixel(pos.x + 1, pos.y, palette["base"].lerp(palette["trace_dark"], fade * 0.8))
				if pos.y + 1 < TILE_SIZE:
					img.set_pixel(pos.x, pos.y + 1, palette["base"].lerp(palette["trace_dark"], fade * 0.6))

	# Solder points at turns - round copper pads with sheen
	for point in turn_points:
		if point.x >= 2 and point.x < TILE_SIZE - 2 and point.y >= 2 and point.y < TILE_SIZE - 2:
			# 3x3 solder pad
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var px = point.x + dx
					var py = point.y + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						var dist = sqrt(dx * dx + dy * dy)
						if dist < 1.6:
							var solder_shade = palette["solder"]
							# Highlight on top-left for 3D effect
							if dx <= 0 and dy <= 0:
								solder_shade = solder_shade.lightened(0.08)
							img.set_pixel(px, py, solder_shade)
			# Bright center
			img.set_pixel(point.x, point.y, palette["trace_bright"])

	# A single component - tiny resistor or capacitor, lovingly detailed
	if trace_segments.size() > 5:
		var mid_idx = trace_segments.size() / 2
		var comp = trace_segments[mid_idx]
		if comp.x >= 2 and comp.x < TILE_SIZE - 2 and comp.y >= 2 and comp.y < TILE_SIZE - 2:
			# Resistor body (horizontal stripe pattern)
			for dx in range(-2, 3):
				for dy in range(-1, 2):
					var px = comp.x + dx
					var py = comp.y + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						if abs(dx) == 2:
							img.set_pixel(px, py, palette["copper"])
						elif dy == 0:
							var band_col = palette["trace_dark"] if abs(dx) == 1 else palette["copper"]
							img.set_pixel(px, py, band_col)
						else:
							img.set_pixel(px, py, palette["solder"])

	# Memory glow - the trace still wants to carry current. A faint
	# green phosphorescence surrounds it, like residual charge.
	for pos in trace_segments:
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var gx = pos.x + dx
				var gy = pos.y + dy
				if gx >= 0 and gx < TILE_SIZE and gy >= 0 and gy < TILE_SIZE:
					var dist = sqrt(dx * dx + dy * dy)
					if dist > 1.0 and dist < 3.0:
						var current = img.get_pixel(gx, gy)
						if current.r > 0.92:
							var glow_intensity = (3.0 - dist) / 2.0
							img.set_pixel(gx, gy, current.lerp(palette["memory_glow"], glow_intensity * 0.05))


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
## Multiple concentric rectangles fade inward, each one a different echo -
## a wall from a deleted castle, a boundary from a removed level, the edge of
## a room that exists in a save file that was corrupted. They overlap and interfere.
func _draw_echo_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 90009

	# Interior fill - slightly different shade to distinguish from void
	for y in range(1, TILE_SIZE - 1):
		for x in range(1, TILE_SIZE - 1):
			img.set_pixel(x, y, palette["inner"])

	# Multiple concentric echo rectangles, each from a different "timeline"
	# Outermost is darkest (most "present"), inner ones fade to nothing
	var echo_count = 5
	for echo in range(echo_count):
		var inset = echo * 3
		var left = 1 + inset
		var right = TILE_SIZE - 2 - inset
		var top = 1 + inset
		var bot = TILE_SIZE - 2 - inset

		if left >= right or top >= bot:
			continue

		# Fade factor: outermost echoes are strongest
		var echo_strength = 1.0 - (float(echo) / float(echo_count))
		echo_strength = echo_strength * echo_strength  # Quadratic fade
		var echo_col: Color
		match echo:
			0: echo_col = palette["outline"]
			1: echo_col = palette["outline_faint"]
			2: echo_col = palette["echo1"]
			3: echo_col = palette["echo2"]
			_: echo_col = palette["echo3"]

		# Slightly offset each echo to suggest parallax/different timelines
		var offset_x = int(sin(echo * 1.7 + variant * 0.5) * 1.2)
		var offset_y = int(cos(echo * 2.3 + variant * 0.3) * 1.0)

		# Draw echo rectangle with breaks (the wall is incomplete)
		# Top edge
		for x in range(left, right + 1):
			var px = x + offset_x
			if px >= 0 and px < TILE_SIZE and top + offset_y >= 0 and top + offset_y < TILE_SIZE:
				var break_chance = 0.05 + echo * 0.08  # More breaks in fainter echoes
				if rng.randf() > break_chance:
					var current = img.get_pixel(px, top + offset_y)
					img.set_pixel(px, top + offset_y, current.lerp(echo_col, echo_strength * 0.8))
		# Bottom edge
		for x in range(left, right + 1):
			var px = x + offset_x
			var py = bot + offset_y
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if rng.randf() > 0.05 + echo * 0.08:
					var current = img.get_pixel(px, py)
					img.set_pixel(px, py, current.lerp(echo_col, echo_strength * 0.8))
		# Left edge
		for y in range(top, bot + 1):
			var px = left + offset_x
			var py = y + offset_y
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if rng.randf() > 0.05 + echo * 0.08:
					var current = img.get_pixel(px, py)
					img.set_pixel(px, py, current.lerp(echo_col, echo_strength * 0.8))
		# Right edge
		for y in range(top, bot + 1):
			var px = right + offset_x
			var py = y + offset_y
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if rng.randf() > 0.05 + echo * 0.08:
					var current = img.get_pixel(px, py)
					img.set_pixel(px, py, current.lerp(echo_col, echo_strength * 0.8))

	# Primary solid wall outline at edges (this is the "real" wall)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["outline"])
		img.set_pixel(x, TILE_SIZE - 1, palette["outline"])
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["outline"])
		img.set_pixel(TILE_SIZE - 1, y, palette["outline"])

	# Corner reinforcements - stronger at corners where walls intersect
	for d in range(3):
		var corner_col = palette["corner"] if d < 2 else palette["outline"]
		img.set_pixel(d, d, corner_col)
		img.set_pixel(TILE_SIZE - 1 - d, d, corner_col)
		img.set_pixel(d, TILE_SIZE - 1 - d, corner_col)
		img.set_pixel(TILE_SIZE - 1 - d, TILE_SIZE - 1 - d, corner_col)

	# Flicker effect - some echoes briefly become more solid,
	# as if the timelines are overlapping
	if variant % 4 == 0:
		var flicker_y = rng.randi_range(4, TILE_SIZE - 5)
		for x in range(3, TILE_SIZE - 3):
			if rng.randf() < 0.35:
				img.set_pixel(x, flicker_y, palette["shadow"])
	elif variant % 4 == 1:
		var flicker_x = rng.randi_range(4, TILE_SIZE - 5)
		for y in range(3, TILE_SIZE - 3):
			if rng.randf() < 0.35:
				img.set_pixel(flicker_x, y, palette["shadow"])


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
## It is the most important tile in the game. The most BEAUTIFUL tile.
## Pure vivid defiance against the optimized nothing. A rainbow compressed
## into a single point, radiating outward, staining the void with purpose.
## This tile should make you feel something. That's the point.
func _draw_color_spot(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12012

	# The void background - slightly warmer here, as if the color
	# has been warming this patch of nothing for a long time
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - TILE_SIZE / 2, 2) + pow(y - TILE_SIZE / 2, 2))
			if dist > 10:
				var n = sin(x * 0.12 + y * 0.1 + variant * 0.5) * 0.04 + rng.randf() * 0.015
				if n > 0.03:
					img.set_pixel(x, y, palette["bleed"])

	# Choose base color - each variant gets a different primary
	var color_options = [
		palette["color_core"],   # Red - passion, anger, love
		palette["color_warm"],   # Orange - warmth, memory, fire
		palette["color_cool"],   # Blue - sadness, sky, depth
		palette["color_life"],   # Green - life, growth, hope
	]
	var primary = color_options[variant % color_options.size()]

	# Secondary and tertiary colors for the rainbow bleed
	var secondary = color_options[(variant + 1) % color_options.size()]
	var tertiary = color_options[(variant + 2) % color_options.size()]

	var cx = TILE_SIZE / 2
	var cy = TILE_SIZE / 2
	var max_radius = 8.0

	# Layer 1: Outer rainbow halo - multiple colors bleeding outward
	# This is the color reaching out, trying to paint the void
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist > max_radius - 2 and dist < max_radius + 5:
				var angle = atan2(y - cy, x - cx)
				var ring_pos = (angle + PI) / (2.0 * PI)  # 0 to 1 around the circle
				# Rainbow: cycle through colors around the ring
				var ring_col: Color
				if ring_pos < 0.33:
					ring_col = primary.lerp(secondary, ring_pos / 0.33)
				elif ring_pos < 0.66:
					ring_col = secondary.lerp(tertiary, (ring_pos - 0.33) / 0.33)
				else:
					ring_col = tertiary.lerp(primary, (ring_pos - 0.66) / 0.34)

				var ring_fade = 1.0 - abs(dist - max_radius) / 5.0
				ring_fade = clamp(ring_fade, 0.0, 1.0)
				ring_fade *= ring_fade  # Soft edges
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(ring_col, ring_fade * 0.20))

	# Layer 2: Main color body - radial gradient with rich saturation
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist < max_radius:
				var intensity = 1.0 - (dist / max_radius)
				# Cubic falloff for rich, saturated center with soft edge
				intensity = intensity * intensity * intensity
				var angle = atan2(y - cy, x - cx)
				# Slight color shift across the spot - it's not monochrome
				var shift = sin(angle * 2.0 + variant * 0.7) * 0.15
				var spot_col = primary
				if shift > 0.05:
					spot_col = spot_col.lerp(secondary, shift)
				elif shift < -0.05:
					spot_col = spot_col.lerp(tertiary, -shift)

				var pixel_col = palette["base"].lerp(spot_col, intensity)
				img.set_pixel(x, y, pixel_col)

	# Layer 3: Inner core - pure, undiluted, MAXIMUM saturation color
	# This is the beating heart. 3x3 cross of pure defiance.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var px = cx + dx
			var py = cy + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var dist = sqrt(dx * dx + dy * dy)
				if dist < 2.2:
					var core_intensity = 1.0 - (dist / 2.2)
					var core_col = primary.lerp(palette["glow_inner"], core_intensity * 0.4)
					img.set_pixel(px, py, core_col)

	# Layer 4: Sparkle highlights - tiny bright spots that catch the eye,
	# like a gemstone refracting light
	var sparkle_count = rng.randi_range(3, 5)
	for _s in range(sparkle_count):
		var angle = rng.randf() * TAU
		var r = rng.randf_range(1.5, max_radius - 1)
		var sx = cx + int(cos(angle) * r)
		var sy = cy + int(sin(angle) * r)
		if sx >= 0 and sx < TILE_SIZE and sy >= 0 and sy < TILE_SIZE:
			var current = img.get_pixel(sx, sy)
			img.set_pixel(sx, sy, current.lerp(Color.WHITE, 0.35))

	# Layer 5: Center sparkle - the absolute brightest pixel in the game
	img.set_pixel(cx, cy, palette["glow_inner"].lightened(0.15))
	# Cross-shaped specular highlight
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var hx = cx + d.x
		var hy = cy + d.y
		if hx >= 0 and hx < TILE_SIZE and hy >= 0 and hy < TILE_SIZE:
			var current = img.get_pixel(hx, hy)
			img.set_pixel(hx, hy, current.lerp(Color.WHITE, 0.20))

	# Layer 6: Color bleeding rays - like a tiny sun, rays of color
	# extend outward in random directions, staining the void
	var ray_count = rng.randi_range(3, 6)
	for _r in range(ray_count):
		var angle = rng.randf() * TAU
		var ray_len = rng.randf_range(5.0, 12.0)
		var ray_col = [primary, secondary, tertiary][rng.randi() % 3]
		for step in range(int(ray_len)):
			var rx = cx + int(cos(angle) * step)
			var ry = cy + int(sin(angle) * step)
			if rx >= 0 and rx < TILE_SIZE and ry >= 0 and ry < TILE_SIZE:
				var ray_fade = 1.0 - (float(step) / ray_len)
				var current = img.get_pixel(rx, ry)
				img.set_pixel(rx, ry, current.lerp(ray_col, ray_fade * 0.08))


## STATIC_TILE - TV static/noise pattern (corruption/memory loss)
## When data is lost, this is what remains. Not silence - noise.
## Reality itself is breaking down here. Between the static, fleeting fragments
## of color signals try to push through - ghosts of images from deleted channels,
## a single pixel of blue sky, half a scanline of someone's face.
func _draw_static_tile(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 13013

	# Layer 1: Base static noise - every pixel randomized, but with
	# a subtle bias toward lighter grays (CRT phosphor persistence)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var noise_val = rng.randf()
			# Weight distribution toward mid-grays for authentic CRT look
			var col: Color
			if noise_val < 0.08:
				col = palette["noise_dark"]
			elif noise_val < 0.22:
				col = palette["dark"]
			elif noise_val < 0.42:
				col = palette["mid"]
			elif noise_val < 0.62:
				col = palette["noise_gray"]
			elif noise_val < 0.80:
				col = palette["light"]
			elif noise_val < 0.92:
				col = palette["noise_white"]
			else:
				# Hot pixels - pure white sparks
				col = Color(0.99, 0.99, 1.0)
			img.set_pixel(x, y, col)

	# Layer 2: Scanlines - alternating dark/light rows for CRT authenticity
	for y in range(TILE_SIZE):
		if y % 2 == 0:
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.06))
		# Every 8th line is a stronger scanline
		if y % 8 == 0:
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.10))

	# Layer 3: Horizontal coherence bands - brief moments where the static
	# briefly organizes, as if a signal is trying to break through
	var band_count = rng.randi_range(1, 3)
	for _b in range(band_count):
		var band_y = rng.randi_range(4, TILE_SIZE - 6)
		var band_h = rng.randi_range(1, 3)
		var band_brightness = rng.randf_range(0.6, 0.9)
		for y in range(band_y, min(band_y + band_h, TILE_SIZE)):
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(palette["scanline"], band_brightness * 0.4))

	# Layer 4: Color signal ghosts - fragments of color trying to persist
	# through the noise. A pixel of blue sky. A flash of red. A hint of green.
	var color_signals = [
		Color(0.85, 0.22, 0.28),  # Red signal
		Color(0.22, 0.55, 0.85),  # Blue signal
		Color(0.30, 0.75, 0.35),  # Green signal
		Color(0.90, 0.80, 0.20),  # Yellow signal
	]
	var signal_count = rng.randi_range(2, 6)
	for _s in range(signal_count):
		var sx = rng.randi_range(2, TILE_SIZE - 3)
		var sy = rng.randi_range(2, TILE_SIZE - 3)
		var sig_col = color_signals[rng.randi() % color_signals.size()]
		# Single pixel or short horizontal run (like a partial image scanline)
		var run_len = rng.randi_range(1, 4)
		for i in range(run_len):
			if sx + i < TILE_SIZE:
				var fade = 1.0 - float(i) / float(run_len)
				var current = img.get_pixel(sx + i, sy)
				img.set_pixel(sx + i, sy, current.lerp(sig_col, fade * 0.5))

	# Layer 5: Vertical tear/roll - the tracking is off, image shears
	if variant % 3 != 2:
		var tear_x = rng.randi_range(6, TILE_SIZE - 6)
		var tear_width = rng.randi_range(1, 2)
		for y in range(TILE_SIZE):
			var wobble = rng.randi_range(-1, 1)
			for tw in range(tear_width):
				var px = tear_x + wobble + tw
				if px >= 0 and px < TILE_SIZE:
					# Tear line is brighter on one side, darker on the other
					if tw == 0:
						img.set_pixel(px, y, palette["noise_white"])
					else:
						img.set_pixel(px, y, palette["noise_dark"])

	# Layer 6: Interference pattern - diagonal stripes suggesting
	# electromagnetic interference, very faint
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var interference = sin((x + y) * 0.5 + variant * 2.1) * 0.5 + 0.5
			if interference > 0.85:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lightened(0.04))


## SHADOW_TILE - A shadow with no object casting it
## Something was here. Something that cast a shadow. The object is gone but
## its shadow stayed. You can recognize the shapes: a person standing, a tree
## in bloom, a house, scattered fragments. The shadows remember what the void forgot.
func _draw_shadow_tile(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 14014

	# Clean white background - slightly warmer where the shadow falls,
	# as if the shadow retains heat from the deleted sun
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.1 + y * 0.08 + variant * 0.4) * 0.03 + rng.randf() * 0.01
			if n > 0.02:
				img.set_pixel(x, y, palette["ground"])

	# The shadow shape - varies by variant, each tells a story
	var shadow_type = variant % 4
	match shadow_type:
		0:
			# Humanoid shadow - someone was standing here, looking up.
			# Head, body, arms slightly raised (waving? reaching?)
			var cx = TILE_SIZE / 2
			# Head shadow (oval, slightly tilted)
			for dy in range(-3, 4):
				for dx in range(-2, 3):
					var dist = sqrt(pow(dx / 2.2, 2) + pow(dy / 2.8, 2))
					if dist < 1.2:
						var px = cx + dx
						var py = 5 + dy
						if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
							var shade = palette["shadow_mid"].lerp(palette["shadow_core"], (1.2 - dist) / 1.2)
							img.set_pixel(px, py, shade)
			# Body shadow with shoulders and slight arm raise
			for dy in range(8, 26):
				var base_width: int
				if dy < 10:
					base_width = 4  # Shoulders
				elif dy < 12:
					base_width = 5  # Arms extending
				elif dy < 20:
					base_width = 4  # Torso
				else:
					base_width = 3  # Legs narrowing

				for dx in range(-base_width, base_width + 1):
					var px = cx + dx
					if px >= 0 and px < TILE_SIZE and dy < TILE_SIZE:
						var edge_fade = 1.0 - (abs(dx) / float(base_width + 1))
						var vert_fade = 1.0 - abs(float(dy - 14) / 12.0)
						var intensity = edge_fade * vert_fade
						var shade = palette["shadow_light"].lerp(palette["shadow_dark"], intensity * 0.65)
						img.set_pixel(px, dy, shade)

			# Raised arms (reaching upward or waving goodbye)
			for arm_side in [-1, 1]:
				var arm_start_y = 10
				for i in range(5):
					var ax = cx + arm_side * (5 + i)
					var ay = arm_start_y - i
					if ax >= 0 and ax < TILE_SIZE and ay >= 0 and ay < TILE_SIZE:
						img.set_pixel(ax, ay, palette["shadow_light"])
						if ay + 1 < TILE_SIZE:
							img.set_pixel(ax, ay + 1, palette["shadow_light"])

			# Shadow core - darkest along center line
			for dy in range(9, 24):
				for dx in range(-1, 2):
					var px = cx + dx
					if px >= 0 and px < TILE_SIZE and dy < TILE_SIZE:
						img.set_pixel(px, dy, palette["shadow_core"])
		1:
			# Tree shadow - organic, branching, full canopy.
			# A tree that must have been beautiful.
			var trunk_x = TILE_SIZE / 2
			# Trunk shadow with bark texture
			for y in range(16, TILE_SIZE - 2):
				for dx in range(-1, 2):
					var px = trunk_x + dx
					if px >= 0 and px < TILE_SIZE:
						var bark_var = sin(y * 0.8 + dx * 2.0) * 0.03
						var shade = palette["shadow_mid"]
						if bark_var > 0.01:
							shade = shade.lightened(0.03)
						img.set_pixel(px, y, shade)
			# Roots spreading at base
			for root_dir in [-1, 1]:
				for i in range(4):
					var rx = trunk_x + root_dir * (1 + i)
					var ry = TILE_SIZE - 3 + (i / 2)
					if rx >= 0 and rx < TILE_SIZE and ry < TILE_SIZE:
						img.set_pixel(rx, ry, palette["shadow_light"])
			# Canopy - irregular organic blob with leaf texture
			for y in range(2, 18):
				for x in range(3, TILE_SIZE - 3):
					var dist = sqrt(pow(x - trunk_x, 2) + pow(y - 9, 2))
					var wobble = sin(x * 0.6 + y * 0.4 + variant * 0.7) * 2.5
					wobble += sin(x * 1.2 + y * 0.8) * 1.0  # Finer leaf detail
					if dist + wobble < 10:
						var fade = (dist + wobble * 0.3) / 10.0
						var shade = palette["shadow_light"].lerp(palette["shadow_dark"], clamp(1.0 - fade, 0.0, 1.0))
						img.set_pixel(x, y, shade)
			# Branch shadows extending from canopy
			for _b in range(3):
				var bx = trunk_x + rng.randi_range(-6, 6)
				var by = rng.randi_range(6, 14)
				var branch_len = rng.randi_range(3, 6)
				var branch_dir = 1 if bx < trunk_x else -1
				for i in range(branch_len):
					var px = bx + i * branch_dir
					if px >= 0 and px < TILE_SIZE and by < TILE_SIZE:
						img.set_pixel(px, by, palette["shadow_light"])
		2:
			# Building shadow - a house or structure with windows and a roof
			var ox = 6
			var oy = 4
			var bw = 20
			var bh = 22
			# Main building shadow
			for dy in range(bh):
				for dx in range(bw):
					var px = ox + dx
					var py = oy + dy
					if px < TILE_SIZE and py < TILE_SIZE:
						var edge_dist = min(dx, bw - 1 - dx, dy, bh - 1 - dy)
						var shade: Color
						if edge_dist > 5:
							shade = palette["shadow_dark"]
						elif edge_dist > 3:
							shade = palette["shadow_mid"]
						elif edge_dist > 1:
							shade = palette["shadow_light"]
						else:
							shade = palette["shadow_light"].lerp(palette["base"], 0.3)
						img.set_pixel(px, py, shade)
			# Window shadows (lighter rectangles where light came through)
			for win_y in [oy + 5, oy + 13]:
				for win_x in [ox + 3, ox + 11]:
					for dy in range(4):
						for dx in range(5):
							var px = win_x + dx
							var py = win_y + dy
							if px < TILE_SIZE and py < TILE_SIZE:
								img.set_pixel(px, py, palette["shadow_light"])
			# Roof peak shadow (triangle)
			for i in range(bw / 2 + 2):
				var left_x = ox - 1 + i
				var right_x = ox + bw - i
				if left_x >= 0 and left_x < TILE_SIZE and oy - 1 - i / 2 >= 0:
					img.set_pixel(left_x, oy - 1 - i / 2, palette["shadow_light"])
				if right_x < TILE_SIZE and oy - 1 - i / 2 >= 0:
					img.set_pixel(right_x, oy - 1 - i / 2, palette["shadow_light"])
		3:
			# Scattered/broken shadow - something that shattered and the
			# fragments drifted apart. Each piece casting its own tiny shadow.
			var fragment_count = rng.randi_range(6, 10)
			for _f in range(fragment_count):
				var fx = rng.randi_range(3, TILE_SIZE - 7)
				var fy = rng.randi_range(3, TILE_SIZE - 7)
				var fw = rng.randi_range(2, 5)
				var fh = rng.randi_range(2, 4)
				# Rotation simulation via skew
				var skew = rng.randf_range(-0.3, 0.3)
				for dy in range(fh):
					for dx in range(fw):
						var px = fx + dx + int(dy * skew)
						var py = fy + dy
						if px >= 0 and px < TILE_SIZE and py < TILE_SIZE:
							var dist_center = sqrt(pow(dx - fw / 2.0, 2) + pow(dy - fh / 2.0, 2))
							var shade = palette["shadow_mid"] if dist_center < 1.5 else palette["shadow_light"]
							img.set_pixel(px, py, shade)

	# Edge softening - all shadows fade gently at their borders
	for x in range(TILE_SIZE):
		for y in range(TILE_SIZE):
			var current = img.get_pixel(x, y)
			if current != palette["base"] and current != palette["ground"]:
				# Check if near a non-shadow pixel (edge detection)
				var is_edge = false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx = x + d.x
					var ny = y + d.y
					if nx >= 0 and nx < TILE_SIZE and ny >= 0 and ny < TILE_SIZE:
						var neighbor = img.get_pixel(nx, ny)
						if neighbor == palette["base"] or neighbor == palette["ground"]:
							is_edge = true
							break
				if is_edge:
					img.set_pixel(x, y, current.lerp(palette["base"], 0.25))

	# Warmth trace - shadows remember the heat of what cast them
	if variant % 3 == 0:
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				if current == palette["shadow_core"] or current == palette["shadow_dark"]:
					if rng.randf() < 0.06:
						img.set_pixel(x, y, current.lerp(palette["warmth"], 0.12))


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
