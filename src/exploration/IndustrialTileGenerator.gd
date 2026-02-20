extends Node
class_name IndustrialTileGenerator

## IndustrialTileGenerator - Procedurally generates 32x32 industrial/factory tiles
## 32-bit era aesthetic (PS1/Saturn) - darker saturated palette with rust, steel, soot
## Area 3: "Optimization as Entropy" - optimized for PRODUCTION at the cost of individuality

const TILE_SIZE: int = 32

## Tile types for Area 3 (Industrial Factory District)
enum TileType {
	FACTORY_FLOOR,      # 0 - gray concrete with oil stains, bolt patterns
	IRON_GRATING,       # 1 - metal grate with gaps showing darkness below
	BRICK_WALL,         # 2 - dark red/brown industrial brick (impassable)
	SMOKESTACK,         # 3 - tall chimney base with soot gradient (impassable)
	CONVEYOR_BELT,      # 4 - moving belt with yellow/black hazard stripes
	RAIL_TRACK,         # 5 - train tracks on gravel bed
	CARGO_CONTAINER,    # 6 - colored shipping container (impassable)
	STEAM_VENT,         # 7 - floor vent with steam wisps
	WORKER_HOUSING,     # 8 - cramped identical facade (impassable)
	GUARD_POST,         # 9 - checkpoint booth (impassable)
	DRAINAGE_CHANNEL,   # 10 - green-tinted water channel
	CHEMICAL_BARREL,    # 11 - hazmat barrel on concrete (impassable)
	PIPE_CLUSTER,       # 12 - exposed industrial pipes (impassable)
	WARNING_SIGN,       # 13 - yellow/black caution sign on post (impassable)
	CHAIN_LINK_FENCE,   # 14 - wire fence on dirt (impassable)
	BREAK_ROOM_FLOOR    # 15 - slightly warmer concrete with coffee stain
}

## Industrial color palettes - darker, more saturated than suburban
const PALETTES: Dictionary = {
	TileType.FACTORY_FLOOR: {
		"base": Color(0.42, 0.40, 0.38),
		"light": Color(0.52, 0.50, 0.48),
		"mid": Color(0.46, 0.44, 0.42),
		"dark": Color(0.32, 0.30, 0.28),
		"deep": Color(0.22, 0.20, 0.18),
		"oil": Color(0.18, 0.16, 0.14),
		"oil_sheen": Color(0.28, 0.22, 0.32),
		"bolt": Color(0.55, 0.55, 0.58),
		"bolt_shadow": Color(0.35, 0.33, 0.31)
	},
	TileType.IRON_GRATING: {
		"base": Color(0.48, 0.48, 0.50),
		"light": Color(0.62, 0.62, 0.65),
		"mid": Color(0.54, 0.54, 0.56),
		"dark": Color(0.36, 0.36, 0.38),
		"deep": Color(0.08, 0.06, 0.06),
		"void": Color(0.04, 0.03, 0.03),
		"rust": Color(0.55, 0.32, 0.18),
		"highlight": Color(0.68, 0.68, 0.72),
		"gap": Color(0.10, 0.08, 0.08)
	},
	TileType.BRICK_WALL: {
		"base": Color(0.48, 0.22, 0.14),
		"light": Color(0.58, 0.30, 0.20),
		"mid": Color(0.52, 0.26, 0.16),
		"dark": Color(0.36, 0.16, 0.10),
		"deep": Color(0.24, 0.10, 0.06),
		"mortar": Color(0.38, 0.35, 0.32),
		"mortar_dark": Color(0.28, 0.25, 0.22),
		"soot": Color(0.18, 0.16, 0.14),
		"moss": Color(0.22, 0.32, 0.16)
	},
	TileType.SMOKESTACK: {
		"base": Color(0.40, 0.38, 0.36),
		"light": Color(0.52, 0.50, 0.48),
		"mid": Color(0.45, 0.43, 0.42),
		"dark": Color(0.28, 0.26, 0.24),
		"deep": Color(0.16, 0.14, 0.12),
		"soot_top": Color(0.12, 0.10, 0.08),
		"soot_mid": Color(0.20, 0.18, 0.16),
		"rim": Color(0.55, 0.52, 0.50),
		"ember": Color(0.72, 0.28, 0.08)
	},
	TileType.CONVEYOR_BELT: {
		"base": Color(0.30, 0.30, 0.32),
		"light": Color(0.40, 0.40, 0.42),
		"mid": Color(0.35, 0.35, 0.37),
		"dark": Color(0.22, 0.22, 0.24),
		"deep": Color(0.14, 0.14, 0.16),
		"hazard_yellow": Color(0.88, 0.78, 0.12),
		"hazard_black": Color(0.12, 0.12, 0.14),
		"roller": Color(0.50, 0.50, 0.55),
		"rubber": Color(0.24, 0.22, 0.20)
	},
	TileType.RAIL_TRACK: {
		"base": Color(0.42, 0.38, 0.34),
		"light": Color(0.55, 0.50, 0.45),
		"mid": Color(0.48, 0.44, 0.38),
		"dark": Color(0.30, 0.26, 0.22),
		"deep": Color(0.20, 0.18, 0.14),
		"rail_steel": Color(0.58, 0.58, 0.62),
		"rail_shine": Color(0.72, 0.72, 0.78),
		"tie_wood": Color(0.35, 0.24, 0.14),
		"gravel": Color(0.48, 0.44, 0.40)
	},
	TileType.CARGO_CONTAINER: {
		"base": Color(0.55, 0.22, 0.15),
		"light": Color(0.68, 0.32, 0.22),
		"mid": Color(0.60, 0.26, 0.18),
		"dark": Color(0.42, 0.16, 0.10),
		"deep": Color(0.30, 0.10, 0.06),
		"corrugation_light": Color(0.62, 0.28, 0.20),
		"corrugation_dark": Color(0.48, 0.20, 0.12),
		"label_white": Color(0.88, 0.86, 0.82),
		"rust_streak": Color(0.52, 0.30, 0.16)
	},
	TileType.STEAM_VENT: {
		"base": Color(0.42, 0.40, 0.38),
		"light": Color(0.52, 0.50, 0.48),
		"mid": Color(0.46, 0.44, 0.42),
		"dark": Color(0.32, 0.30, 0.28),
		"deep": Color(0.22, 0.20, 0.18),
		"vent_slot": Color(0.15, 0.13, 0.12),
		"steam_white": Color(0.88, 0.90, 0.92),
		"steam_fade": Color(0.72, 0.74, 0.76),
		"grate_edge": Color(0.50, 0.48, 0.46)
	},
	TileType.WORKER_HOUSING: {
		"base": Color(0.52, 0.48, 0.44),
		"light": Color(0.62, 0.58, 0.54),
		"mid": Color(0.56, 0.52, 0.48),
		"dark": Color(0.40, 0.36, 0.32),
		"deep": Color(0.28, 0.24, 0.20),
		"window_dark": Color(0.15, 0.18, 0.22),
		"window_glint": Color(0.42, 0.48, 0.55),
		"door_gray": Color(0.38, 0.36, 0.34),
		"roof": Color(0.35, 0.32, 0.30)
	},
	TileType.GUARD_POST: {
		"base": Color(0.55, 0.55, 0.52),
		"light": Color(0.68, 0.68, 0.65),
		"mid": Color(0.60, 0.60, 0.58),
		"dark": Color(0.42, 0.42, 0.40),
		"deep": Color(0.30, 0.30, 0.28),
		"stripe_red": Color(0.72, 0.18, 0.14),
		"stripe_white": Color(0.88, 0.86, 0.84),
		"glass": Color(0.48, 0.58, 0.68),
		"roof_dark": Color(0.35, 0.33, 0.30)
	},
	TileType.DRAINAGE_CHANNEL: {
		"base": Color(0.28, 0.40, 0.30),
		"light": Color(0.38, 0.52, 0.40),
		"mid": Color(0.32, 0.45, 0.34),
		"dark": Color(0.20, 0.32, 0.22),
		"deep": Color(0.12, 0.22, 0.14),
		"foam": Color(0.55, 0.62, 0.50),
		"edge_stone": Color(0.45, 0.42, 0.38),
		"edge_dark": Color(0.32, 0.30, 0.26),
		"chemical_green": Color(0.35, 0.58, 0.25)
	},
	TileType.CHEMICAL_BARREL: {
		"base": Color(0.82, 0.68, 0.12),
		"light": Color(0.90, 0.78, 0.22),
		"mid": Color(0.85, 0.72, 0.16),
		"dark": Color(0.68, 0.55, 0.08),
		"deep": Color(0.52, 0.42, 0.04),
		"hazard_black": Color(0.12, 0.12, 0.14),
		"skull_white": Color(0.88, 0.86, 0.82),
		"concrete": Color(0.42, 0.40, 0.38),
		"drip_green": Color(0.32, 0.55, 0.18)
	},
	TileType.PIPE_CLUSTER: {
		"base": Color(0.48, 0.45, 0.42),
		"light": Color(0.62, 0.58, 0.55),
		"mid": Color(0.54, 0.50, 0.48),
		"dark": Color(0.35, 0.32, 0.28),
		"deep": Color(0.22, 0.20, 0.18),
		"copper": Color(0.68, 0.42, 0.20),
		"copper_patina": Color(0.35, 0.55, 0.45),
		"joint_ring": Color(0.58, 0.55, 0.52),
		"steam": Color(0.82, 0.85, 0.88)
	},
	TileType.WARNING_SIGN: {
		"base": Color(0.88, 0.78, 0.12),
		"light": Color(0.95, 0.88, 0.25),
		"mid": Color(0.90, 0.82, 0.18),
		"dark": Color(0.72, 0.62, 0.08),
		"deep": Color(0.55, 0.45, 0.04),
		"hazard_black": Color(0.12, 0.12, 0.14),
		"post_gray": Color(0.48, 0.48, 0.50),
		"post_dark": Color(0.35, 0.35, 0.37),
		"concrete": Color(0.42, 0.40, 0.38)
	},
	TileType.CHAIN_LINK_FENCE: {
		"base": Color(0.55, 0.55, 0.58),
		"light": Color(0.68, 0.68, 0.72),
		"mid": Color(0.60, 0.60, 0.64),
		"dark": Color(0.42, 0.42, 0.45),
		"deep": Color(0.30, 0.30, 0.32),
		"wire": Color(0.62, 0.62, 0.66),
		"post": Color(0.48, 0.48, 0.52),
		"dirt": Color(0.38, 0.34, 0.28),
		"dirt_dark": Color(0.28, 0.24, 0.18)
	},
	TileType.BREAK_ROOM_FLOOR: {
		"base": Color(0.48, 0.44, 0.40),
		"light": Color(0.58, 0.54, 0.50),
		"mid": Color(0.52, 0.48, 0.44),
		"dark": Color(0.38, 0.34, 0.30),
		"deep": Color(0.28, 0.24, 0.20),
		"coffee": Color(0.35, 0.22, 0.12),
		"coffee_ring": Color(0.42, 0.28, 0.16),
		"linoleum_light": Color(0.55, 0.52, 0.48),
		"warmth": Color(0.52, 0.46, 0.38)
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
	var palette = PALETTES.get(type, PALETTES[TileType.FACTORY_FLOOR])

	match type:
		TileType.FACTORY_FLOOR:
			_draw_factory_floor(img, palette, variant)
		TileType.IRON_GRATING:
			_draw_iron_grating(img, palette, variant)
		TileType.BRICK_WALL:
			_draw_brick_wall(img, palette, variant)
		TileType.SMOKESTACK:
			_draw_smokestack(img, palette, variant)
		TileType.CONVEYOR_BELT:
			_draw_conveyor_belt(img, palette, variant)
		TileType.RAIL_TRACK:
			_draw_rail_track(img, palette, variant)
		TileType.CARGO_CONTAINER:
			_draw_cargo_container(img, palette, variant)
		TileType.STEAM_VENT:
			_draw_steam_vent(img, palette, variant)
		TileType.WORKER_HOUSING:
			_draw_worker_housing(img, palette, variant)
		TileType.GUARD_POST:
			_draw_guard_post(img, palette)
		TileType.DRAINAGE_CHANNEL:
			_draw_drainage_channel(img, palette, variant)
		TileType.CHEMICAL_BARREL:
			_draw_chemical_barrel(img, palette)
		TileType.PIPE_CLUSTER:
			_draw_pipe_cluster(img, palette, variant)
		TileType.WARNING_SIGN:
			_draw_warning_sign(img, palette)
		TileType.CHAIN_LINK_FENCE:
			_draw_chain_link_fence(img, palette, variant)
		TileType.BREAK_ROOM_FLOOR:
			_draw_break_room_floor(img, palette, variant)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## Gray concrete factory floor with oil stains, bolt patterns, tire marks, footprints, worn paths
func _draw_factory_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	# Base concrete texture noise - rougher than suburban sidewalk with aggregate flecks
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.7 + variant * 1.4) * cos(y * 0.5 + variant * 0.9)
			var n2 = sin(x * 1.3 + y * 0.8 + variant * 2.2) * 0.35
			var n3 = sin(x * 2.8 + y * 1.9 + variant * 3.7) * 0.12  # Fine grain detail
			var combined = (n1 + n2 + n3) / 2.5 + rng.randf() * 0.16
			if combined < -0.22:
				img.set_pixel(x, y, palette["deep"])
			elif combined < -0.08:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.25:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.10:
				img.set_pixel(x, y, palette["mid"])
			# Aggregate flecks in concrete
			if rng.randf() < 0.03:
				img.set_pixel(x, y, palette["base"].lightened(0.12))

	# Concrete expansion joints - wider, more industrial (every 16 pixels)
	for x in range(TILE_SIZE):
		if x % 16 == 0:
			for y in range(TILE_SIZE):
				img.set_pixel(x, y, palette["dark"])
		if x % 16 == 1:
			for y in range(TILE_SIZE):
				img.set_pixel(x, y, palette["deep"].lightened(0.05))
	for y in range(TILE_SIZE):
		if y % 16 == 0:
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, palette["dark"])
		if y % 16 == 1:
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, palette["deep"].lightened(0.05))

	# Floor bolt pattern (4 bolts in corners of each 16x16 section) with slot detail
	var bolt_offsets = [Vector2i(3, 3), Vector2i(12, 3), Vector2i(3, 12), Vector2i(12, 12)]
	for section_x in range(0, TILE_SIZE, 16):
		for section_y in range(0, TILE_SIZE, 16):
			for offset in bolt_offsets:
				var bx = section_x + offset.x
				var by = section_y + offset.y
				if bx >= 0 and bx < TILE_SIZE and by >= 0 and by < TILE_SIZE:
					img.set_pixel(bx, by, palette["bolt"])
					if bx + 1 < TILE_SIZE:
						img.set_pixel(bx + 1, by, palette["bolt"])
					if by + 1 < TILE_SIZE:
						img.set_pixel(bx, by + 1, palette["bolt_shadow"])
					if bx + 1 < TILE_SIZE and by + 1 < TILE_SIZE:
						img.set_pixel(bx + 1, by + 1, palette["bolt_shadow"])
					# Bolt slot line (horizontal scratch across bolt head)
					if bx + 1 < TILE_SIZE:
						img.set_pixel(bx, by, palette["bolt_shadow"].darkened(0.1))
						img.set_pixel(bx + 1, by, palette["bolt_shadow"].darkened(0.1))

	# Oil stains - dark blotchy patches with iridescent sheen
	if variant % 2 == 0:
		var num_stains = rng.randi_range(1, 3)
		for _s in range(num_stains):
			var ox = rng.randi_range(4, TILE_SIZE - 6)
			var oy = rng.randi_range(4, TILE_SIZE - 6)
			var stain_size = rng.randi_range(3, 7)
			for dy in range(stain_size):
				for dx in range(stain_size):
					var px = ox + dx
					var py = oy + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						var dist = sqrt(pow(dx - stain_size / 2.0, 2) + pow(dy - stain_size / 2.0, 2))
						if dist < stain_size / 2.0 and rng.randf() < 0.75:
							var stain_col: Color
							var sheen_r = rng.randf()
							if sheen_r < 0.15:
								stain_col = palette["oil_sheen"]
							elif sheen_r < 0.30:
								stain_col = palette["oil_sheen"].lerp(Color(0.20, 0.28, 0.22), 0.4)
							else:
								stain_col = palette["oil"]
							# Edge of stain is thinner
							if dist > stain_size / 2.0 - 1.0:
								stain_col = stain_col.lerp(palette["base"], 0.5)
							img.set_pixel(px, py, stain_col)

	# Tire scuff marks on some variants
	if variant % 5 == 0:
		var scuff_y = rng.randi_range(8, TILE_SIZE - 8)
		var scuff_start = rng.randi_range(4, 10)
		var scuff_end = rng.randi_range(18, 28)
		for x in range(scuff_start, scuff_end):
			if x < TILE_SIZE and scuff_y < TILE_SIZE:
				img.set_pixel(x, scuff_y, palette["deep"])
				if scuff_y + 1 < TILE_SIZE:
					img.set_pixel(x, scuff_y + 1, palette["dark"])
				# Tire tread pattern (gaps every 3 pixels)
				if x % 3 == 0 and scuff_y - 1 >= 0:
					img.set_pixel(x, scuff_y - 1, palette["dark"].lightened(0.05))

	# Worn path - lighter strip where foot traffic erodes concrete
	if variant % 3 == 0:
		var path_center_y = TILE_SIZE / 2 + rng.randi_range(-4, 4)
		for x in range(TILE_SIZE):
			for dy in range(-2, 3):
				var py = path_center_y + dy
				if py >= 0 and py < TILE_SIZE:
					var wear_strength = 1.0 - abs(dy) / 3.0
					var current = img.get_pixel(x, py)
					img.set_pixel(x, py, current.lightened(0.06 * wear_strength))

	# Boot print marks (partial shoe shapes)
	if variant % 4 == 0:
		for _f in range(rng.randi_range(1, 2)):
			var fx = rng.randi_range(4, TILE_SIZE - 8)
			var fy = rng.randi_range(8, TILE_SIZE - 6)
			# Boot sole outline - simplified 3x5 print
			var boot_col = palette["dark"].darkened(0.05)
			if fx + 3 < TILE_SIZE and fy + 5 < TILE_SIZE:
				# Heel
				img.set_pixel(fx, fy + 3, boot_col)
				img.set_pixel(fx + 1, fy + 3, boot_col)
				img.set_pixel(fx + 2, fy + 3, boot_col)
				img.set_pixel(fx, fy + 4, boot_col)
				img.set_pixel(fx + 1, fy + 4, boot_col)
				img.set_pixel(fx + 2, fy + 4, boot_col)
				# Toe
				img.set_pixel(fx, fy, boot_col)
				img.set_pixel(fx + 1, fy, boot_col)
				img.set_pixel(fx + 2, fy, boot_col)
				img.set_pixel(fx + 1, fy + 1, boot_col)

	# Dust/grit accumulation in corners near joints
	for section_x in range(0, TILE_SIZE, 16):
		for section_y in range(0, TILE_SIZE, 16):
			for dx in range(2, 5):
				for dy in range(2, 5):
					var px = section_x + dx
					var py = section_y + dy
					if px < TILE_SIZE and py < TILE_SIZE and rng.randf() < 0.3:
						var current = img.get_pixel(px, py)
						img.set_pixel(px, py, current.darkened(0.04))


## Metal grate with gaps showing darkness below - diamond plate pattern
func _draw_iron_grating(img: Image, palette: Dictionary, variant: int) -> void:
	# Dark void beneath the grating
	img.fill(palette["void"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 22222

	# Draw metal grid bars (leaving gaps for void)
	var bar_width = 3
	var gap_width = 5
	var spacing = bar_width + gap_width

	# Horizontal bars
	for y in range(TILE_SIZE):
		var in_bar = (y % spacing) < bar_width
		if in_bar:
			for x in range(TILE_SIZE):
				var shade = palette["base"]
				var bar_pos = y % spacing
				if bar_pos == 0:
					shade = palette["light"]
				elif bar_pos == bar_width - 1:
					shade = palette["dark"]
				# Surface texture
				var n = sin(x * 0.8 + y * 0.3 + variant * 1.2) * 0.2 + rng.randf() * 0.08
				if n > 0.15:
					shade = shade.lightened(0.06)
				elif n < -0.12:
					shade = shade.darkened(0.06)
				img.set_pixel(x, y, shade)

	# Vertical bars (cross pattern)
	for x in range(TILE_SIZE):
		var in_bar = (x % spacing) < bar_width
		if in_bar:
			for y in range(TILE_SIZE):
				# Only draw on gaps (intersections are already drawn)
				var y_in_bar = (y % spacing) < bar_width
				if not y_in_bar:
					var shade = palette["mid"]
					var bar_pos = x % spacing
					if bar_pos == 0:
						shade = palette["highlight"]
					elif bar_pos == bar_width - 1:
						shade = palette["dark"]
					img.set_pixel(x, y, shade)

	# Intersection highlights (where bars cross)
	for gx in range(0, TILE_SIZE, spacing):
		for gy in range(0, TILE_SIZE, spacing):
			if gx + 1 < TILE_SIZE and gy + 1 < TILE_SIZE:
				img.set_pixel(gx, gy, palette["highlight"])

	# Void below has subtle depth variation
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var y_in_bar = (y % spacing) < bar_width
			var x_in_bar = (x % spacing) < bar_width
			if not y_in_bar and not x_in_bar:
				var depth_n = sin(x * 0.4 + y * 0.6) * 0.3 + rng.randf() * 0.12
				if depth_n > 0.1:
					img.set_pixel(x, y, palette["gap"])
				# Occasional orange glow from below (furnace)
				if variant % 4 == 0 and rng.randf() < 0.08:
					img.set_pixel(x, y, Color(0.35, 0.12, 0.04))

	# Rust spots on bars
	if variant % 3 == 0:
		for _i in range(rng.randi_range(2, 5)):
			var rx = rng.randi_range(0, TILE_SIZE - 1)
			var ry = rng.randi_range(0, TILE_SIZE - 1)
			var y_in_bar = (ry % spacing) < bar_width
			var x_in_bar = (rx % spacing) < bar_width
			if y_in_bar or x_in_bar:
				img.set_pixel(rx, ry, palette["rust"])


## Dark red/brown industrial brick - soot-stained, heavier than suburban, with cracks and grime
func _draw_brick_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["mortar"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	var brick_h = 4
	var brick_w = 8

	for row in range(TILE_SIZE / brick_h):
		var offset = (brick_w / 2) if row % 2 == 1 else 0
		for col in range((TILE_SIZE / brick_w) + 2):
			var bx = col * brick_w + offset - brick_w
			var by = row * brick_h

			# Pick brick color - darker and more varied than suburban
			var brick_col = palette["base"]
			var r = rng.randf()
			if r < 0.12:
				brick_col = palette["light"]
			elif r < 0.28:
				brick_col = palette["dark"]
			elif r < 0.40:
				brick_col = palette["deep"]
			elif r < 0.52:
				brick_col = palette["mid"]
			elif r < 0.58:
				# Scorched brick - darker than usual
				brick_col = palette["deep"].darkened(0.1)

			# Draw brick body with highlight/shadow edges and surface texture
			for dy in range(1, brick_h):
				for dx in range(1, brick_w):
					var px = bx + dx
					var py = by + dy
					if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
						var shade = brick_col
						# Top edge highlight
						if dy == 1:
							shade = brick_col.lightened(0.08)
						elif dx == 1:
							shade = brick_col.lightened(0.04)
						# Bottom-right shadow
						elif dy == brick_h - 1:
							shade = brick_col.darkened(0.12)
						elif dx == brick_w - 1:
							shade = brick_col.darkened(0.06)
						# Richer surface variation - clay texture
						var grain = sin(px * 0.4 + py * 0.6 + variant * 0.8) * 0.05
						var grain2 = sin(px * 1.2 + py * 0.3 + variant * 1.6) * 0.03
						grain += grain2
						if grain > 0.03:
							shade = shade.lightened(0.03)
						elif grain < -0.03:
							shade = shade.darkened(0.03)
						# Speckled clay inclusions
						if rng.randf() < 0.04:
							shade = shade.lightened(0.06)
						img.set_pixel(px, py, shade)

	# Mortar lines with variation - some crumbling, some intact
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			if img.get_pixel(x, y).is_equal_approx(palette["mortar"]):
				var mortar_n = rng.randf()
				if mortar_n < 0.15:
					img.set_pixel(x, y, palette["mortar_dark"])
				elif mortar_n < 0.25:
					img.set_pixel(x, y, palette["mortar"].darkened(0.06))
				elif mortar_n < 0.30:
					# Crumbling mortar - lighter gap
					img.set_pixel(x, y, palette["mortar"].lightened(0.08))

	# Soot staining from top (gradient darkening) - heavier than before
	for y in range(min(12, TILE_SIZE)):
		for x in range(TILE_SIZE):
			var soot_strength = (12.0 - y) / 12.0 * 0.35
			# Streaky soot pattern
			var streak = sin(x * 0.3 + variant * 2.0) * 0.15
			soot_strength += streak
			if rng.randf() < 0.65:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(palette["soot"], clamp(soot_strength, 0.0, 0.4)))

	# Soot streaks dripping down from top (vertical dark lines)
	if variant % 3 != 2:
		for _streak in range(rng.randi_range(1, 3)):
			var sx = rng.randi_range(2, TILE_SIZE - 3)
			var streak_len = rng.randi_range(8, 18)
			for sy in range(streak_len):
				if sy < TILE_SIZE:
					var fade = float(sy) / float(streak_len)
					var current = img.get_pixel(sx, sy)
					img.set_pixel(sx, sy, current.lerp(palette["soot"], (1.0 - fade) * 0.2))

	# Cracks in bricks (diagonal lines through individual bricks)
	if variant % 3 == 0:
		var crack_x = rng.randi_range(4, TILE_SIZE - 6)
		var crack_y = rng.randi_range(4, TILE_SIZE - 8)
		var crack_len = rng.randi_range(4, 8)
		for i in range(crack_len):
			var cx = crack_x + i + rng.randi_range(-1, 0)
			var cy = crack_y + i
			if cx >= 0 and cx < TILE_SIZE and cy >= 0 and cy < TILE_SIZE:
				img.set_pixel(cx, cy, palette["deep"].darkened(0.1))
				if cx + 1 < TILE_SIZE:
					img.set_pixel(cx + 1, cy, palette["dark"].darkened(0.05))

	# Chipped brick edges
	if variant % 2 == 0:
		for _chip in range(rng.randi_range(1, 3)):
			var cx = rng.randi_range(1, TILE_SIZE - 3)
			var cy = rng.randi_range(1, TILE_SIZE - 3)
			img.set_pixel(cx, cy, palette["mortar_dark"])
			if cx + 1 < TILE_SIZE:
				img.set_pixel(cx + 1, cy, palette["mortar"])

	# Occasional moss in mortar joints (bottom rows only)
	if variant % 4 == 0:
		for _i in range(rng.randi_range(3, 7)):
			var mx = rng.randi_range(0, TILE_SIZE - 1)
			var my = rng.randi_range(TILE_SIZE - 12, TILE_SIZE - 1)
			if my >= 0 and my < TILE_SIZE:
				var current = img.get_pixel(mx, my)
				if current.is_equal_approx(palette["mortar"]) or current.is_equal_approx(palette["mortar_dark"]):
					img.set_pixel(mx, my, palette["moss"])
					# Spread moss slightly
					if mx + 1 < TILE_SIZE and rng.randf() < 0.4:
						img.set_pixel(mx + 1, my, palette["moss"].darkened(0.1))

	# Water stain from drainage (darker wet area at bottom)
	if variant % 5 == 0:
		for y in range(TILE_SIZE - 6, TILE_SIZE):
			for x in range(TILE_SIZE):
				if rng.randf() < 0.4:
					var current = img.get_pixel(x, y)
					img.set_pixel(x, y, current.darkened(0.08))


## Smokestack base - imposing cylindrical chimney with soot gradient, rivets, and heat shimmer
func _draw_smokestack(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["deep"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 44444

	# Dark factory background fill with smoke haze
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.15
			if n < 0.04:
				img.set_pixel(x, y, Color(0.10, 0.08, 0.06))
			# Smoke haze near top
			if y < 6 and rng.randf() < 0.15:
				img.set_pixel(x, y, Color(0.18, 0.16, 0.15))

	# Cylindrical smokestack body (centered, 20px wide)
	var stack_left = 6
	var stack_right = 26
	var stack_width = stack_right - stack_left

	for y in range(TILE_SIZE):
		for x in range(stack_left, stack_right):
			var rel_x = float(x - stack_left) / float(stack_width)
			var shade: Color

			# Cylindrical shading (lighter in center, darker at edges)
			if rel_x < 0.10:
				shade = palette["deep"]
			elif rel_x < 0.22:
				shade = palette["dark"]
			elif rel_x < 0.38:
				shade = palette["mid"]
			elif rel_x < 0.62:
				shade = palette["light"]
			elif rel_x < 0.78:
				shade = palette["mid"]
			elif rel_x < 0.90:
				shade = palette["dark"]
			else:
				shade = palette["deep"]

			# Soot gradient from top (heavier)
			var soot_factor = (1.0 - float(y) / float(TILE_SIZE)) * 0.50
			shade = shade.lerp(palette["soot_top"], soot_factor)

			# Surface texture - brick/plate lines
			var n = sin(x * 0.3 + y * 0.8 + variant * 1.5) * 0.08
			var plate_n = sin(y * 0.4 + variant * 0.9) * 0.04
			if n + plate_n > 0.06:
				shade = shade.lightened(0.03)
			elif n + plate_n < -0.06:
				shade = shade.darkened(0.03)

			# Horizontal plate seams every 8 pixels
			if y % 8 == 0 and y > 2 and y < TILE_SIZE - 3:
				shade = shade.darkened(0.08)
			elif y % 8 == 1 and y > 3 and y < TILE_SIZE - 2:
				shade = shade.lightened(0.03)

			img.set_pixel(x, y, shade)

	# Rim at top - thick lip with overhang shadow
	for x in range(stack_left - 2, stack_right + 2):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, 0, palette["rim"].lightened(0.05))
			img.set_pixel(x, 1, palette["rim"])
			img.set_pixel(x, 2, palette["rim"].darkened(0.08))
			img.set_pixel(x, 3, palette["soot_mid"])

	# Heat shimmer effect at top (wavy distortion pattern above opening)
	for x in range(stack_left + 1, stack_right - 1):
		var shimmer_offset = sin(x * 0.8 + variant * 3.0) * 1.5
		if abs(shimmer_offset) > 0.5:
			# Faint heat haze pixels above the stack
			var haze_col = Color(0.22, 0.18, 0.14, 0.6)
			if x >= 0 and x < TILE_SIZE:
				img.set_pixel(x, 0, palette["rim"].lerp(haze_col, 0.3))
		# Inner glow at the opening
		if x > stack_left + 2 and x < stack_right - 2:
			var glow_strength = 0.3 + sin(x * 0.5 + variant * 1.2) * 0.2
			img.set_pixel(x, 1, palette["ember"].lerp(palette["soot_top"], 1.0 - glow_strength))

	# Rim at bottom (base flange) - wider, more imposing
	for x in range(stack_left - 3, stack_right + 3):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, TILE_SIZE - 1, palette["rim"].darkened(0.18))
			img.set_pixel(x, TILE_SIZE - 2, palette["rim"].darkened(0.08))
			img.set_pixel(x, TILE_SIZE - 3, palette["rim"])
			img.set_pixel(x, TILE_SIZE - 4, palette["mid"])

	# Rivet lines - two rows for industrial look
	for rivet_y in [TILE_SIZE / 3, TILE_SIZE * 2 / 3]:
		for x in range(stack_left + 2, stack_right - 2, 3):
			if x < TILE_SIZE and rivet_y >= 0 and rivet_y < TILE_SIZE:
				img.set_pixel(x, rivet_y, palette["rim"].lightened(0.12))
				if rivet_y + 1 < TILE_SIZE:
					img.set_pixel(x, rivet_y + 1, palette["dark"].darkened(0.05))
				# Rivet shadow
				if x + 1 < TILE_SIZE:
					img.set_pixel(x + 1, rivet_y, palette["dark"])

	# Ember glow at top opening - always present, intensity varies
	for x in range(stack_left + 3, stack_right - 3):
		var glow_strength = rng.randf() * 0.6 + 0.2
		if variant % 3 == 0:
			glow_strength += 0.2  # Extra glow on some variants
		glow_strength = clamp(glow_strength, 0.0, 1.0)
		img.set_pixel(x, 2, palette["ember"].lerp(palette["soot_top"], 1.0 - glow_strength * 0.7))

	# Soot drip stains running down the sides
	for _drip in range(rng.randi_range(1, 3)):
		var drip_x = rng.randi_range(stack_left + 1, stack_right - 2)
		var drip_start = rng.randi_range(4, 10)
		var drip_len = rng.randi_range(6, 14)
		for dy in range(drip_len):
			var py = drip_start + dy
			if py < TILE_SIZE - 3 and drip_x < TILE_SIZE:
				var fade = float(dy) / float(drip_len)
				var current = img.get_pixel(drip_x, py)
				img.set_pixel(drip_x, py, current.lerp(palette["soot_top"], (1.0 - fade) * 0.25))


## Conveyor belt with yellow/black hazard stripes, visible rollers, tread marks, and wear
func _draw_conveyor_belt(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 55555

	# Belt surface texture (rubber) with detailed tread pattern
	for y in range(6, TILE_SIZE - 6):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.5 + y * 1.8 + variant * 2.0) * 0.2 + rng.randf() * 0.1
			var shade = palette["rubber"]
			if n > 0.1:
				shade = shade.lightened(0.06)
			elif n < -0.1:
				shade = shade.darkened(0.04)
			# Belt tread pattern - chevron ridges (V-pattern like real conveyor belts)
			var tread_v = ((x + y) % 6 == 0) or ((x - y + 100) % 6 == 0)
			if y % 4 == 0:
				shade = shade.lightened(0.05)
			elif y % 4 == 2:
				shade = shade.darkened(0.04)
			if tread_v and y % 2 == 0:
				shade = shade.lightened(0.03)
			# Rubber grain texture
			if rng.randf() < 0.04:
				shade = shade.darkened(0.06)
			img.set_pixel(x, y, shade)

	# Belt side edges - slightly raised rubber lip
	for x in range(TILE_SIZE):
		if 6 < TILE_SIZE and 5 < TILE_SIZE:
			img.set_pixel(x, 6, palette["rubber"].lightened(0.08))
		if TILE_SIZE - 7 >= 0:
			img.set_pixel(x, TILE_SIZE - 7, palette["rubber"].darkened(0.06))

	# Yellow/black hazard stripes on edges (top and bottom rails) with worn paint
	for x in range(TILE_SIZE):
		for y_band in [range(0, 6), range(TILE_SIZE - 6, TILE_SIZE)]:
			for y in y_band:
				# Diagonal stripe pattern
				var stripe_pos = (x + y) % 8
				if stripe_pos < 4:
					var yellow = palette["hazard_yellow"]
					# Paint wear variation
					if rng.randf() < 0.08:
						yellow = yellow.darkened(0.12)
					img.set_pixel(x, y, yellow)
				else:
					var black = palette["hazard_black"]
					# Scuff marks on black stripes
					if rng.randf() < 0.06:
						black = black.lightened(0.08)
					img.set_pixel(x, y, black)

	# Visible roller drums at edges (cylindrical cross-sections)
	for rx in range(0, TILE_SIZE, 6):
		for rail_y in [5, TILE_SIZE - 7]:
			if rail_y >= 0 and rail_y < TILE_SIZE:
				for dx in range(4):
					var px = rx + dx
					if px < TILE_SIZE:
						var rel = float(dx) / 3.0
						var roller_shade = palette["roller"]
						# Cylindrical shading across roller
						if rel < 0.25:
							roller_shade = roller_shade.darkened(0.12)
						elif rel < 0.5:
							roller_shade = roller_shade
						elif rel < 0.75:
							roller_shade = roller_shade.lightened(0.08)
						else:
							roller_shade = roller_shade.darkened(0.06)
						img.set_pixel(px, rail_y, roller_shade)
						# Roller axle shadow beneath
						if rail_y + 1 < TILE_SIZE:
							img.set_pixel(px, rail_y + 1, palette["dark"])

	# Movement indicator arrows on belt surface (painted arrows)
	if variant % 3 == 0:
		var arrow_cx = TILE_SIZE / 2
		var arrow_cy = TILE_SIZE / 2
		var arrow_col = palette["mid"].lightened(0.06)
		# Double chevron pointing right
		for offset in [0, 5]:
			for i in range(4):
				var ax = arrow_cx - 2 + i + offset
				var ay1 = arrow_cy - i
				var ay2 = arrow_cy + i
				if ax >= 0 and ax < TILE_SIZE:
					if ay1 >= 6 and ay1 < TILE_SIZE - 6:
						img.set_pixel(ax, ay1, arrow_col)
					if ay2 >= 6 and ay2 < TILE_SIZE - 6:
						img.set_pixel(ax, ay2, arrow_col)

	# Wear marks and scuffs on belt surface
	for _i in range(rng.randi_range(2, 5)):
		var wx = rng.randi_range(2, TILE_SIZE - 4)
		var wy = rng.randi_range(8, TILE_SIZE - 10)
		if wy < TILE_SIZE - 6:
			img.set_pixel(wx, wy, palette["dark"])
			if wx + 1 < TILE_SIZE:
				img.set_pixel(wx + 1, wy, palette["dark"].lightened(0.04))

	# Grease drip from rollers
	if variant % 4 == 0:
		var drip_x = rng.randi_range(2, TILE_SIZE - 4)
		for dy in range(rng.randi_range(2, 4)):
			var py = 7 + dy
			if py < TILE_SIZE - 6 and drip_x < TILE_SIZE:
				img.set_pixel(drip_x, py, palette["dark"].darkened(0.08))


## Rail tracks on gravel bed with wooden ties and steel rails
func _draw_rail_track(img: Image, palette: Dictionary, variant: int) -> void:
	# Gravel bed base
	img.fill(palette["gravel"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 66666

	# Gravel texture - rougher than suburban road
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.45 + sin(x * 1.6 + y * 1.3 + variant * 2.8) * 0.2
			if n < 0.18:
				img.set_pixel(x, y, palette["deep"])
			elif n < 0.30:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.50:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.40:
				img.set_pixel(x, y, palette["mid"])

	# Railroad ties (horizontal wooden beams)
	for ty in range(0, TILE_SIZE, 6):
		for x in range(2, TILE_SIZE - 2):
			for dy in range(2):
				var py = ty + dy
				if py < TILE_SIZE:
					var shade = palette["tie_wood"]
					if dy == 0:
						shade = shade.lightened(0.08)
					# Wood grain variation
					var grain = sin(x * 0.3 + py * 0.1) * 0.06
					if grain > 0.03:
						shade = shade.lightened(0.03)
					elif grain < -0.03:
						shade = shade.darkened(0.03)
					img.set_pixel(x, py, shade)

	# Steel rails (two parallel lines with proper profile)
	var rail_left = 8
	var rail_right = TILE_SIZE - 9
	for y in range(TILE_SIZE):
		# Left rail - full rail profile
		img.set_pixel(rail_left - 1, y, palette["dark"])
		img.set_pixel(rail_left, y, palette["rail_steel"])
		img.set_pixel(rail_left + 1, y, palette["rail_shine"])
		img.set_pixel(rail_left + 2, y, palette["dark"])
		# Right rail
		img.set_pixel(rail_right - 1, y, palette["dark"])
		img.set_pixel(rail_right, y, palette["rail_steel"])
		img.set_pixel(rail_right + 1, y, palette["rail_shine"])
		img.set_pixel(rail_right + 2, y, palette["dark"])

	# Rail spikes at each tie
	for ty in range(0, TILE_SIZE, 6):
		for rail_x in [rail_left - 2, rail_left + 3, rail_right - 2, rail_right + 3]:
			if rail_x >= 0 and rail_x < TILE_SIZE and ty < TILE_SIZE:
				img.set_pixel(rail_x, ty, palette["rail_steel"].darkened(0.2))


## Colored shipping container with corrugated walls and labels
func _draw_cargo_container(img: Image, palette: Dictionary, variant: int) -> void:
	# Container color variations
	var container_colors = [
		[Color(0.55, 0.22, 0.15), Color(0.68, 0.32, 0.22), Color(0.42, 0.16, 0.10)],  # rust red
		[Color(0.18, 0.35, 0.55), Color(0.28, 0.48, 0.68), Color(0.12, 0.25, 0.40)],   # shipping blue
		[Color(0.22, 0.45, 0.22), Color(0.32, 0.58, 0.32), Color(0.15, 0.32, 0.15)],   # army green
		[Color(0.48, 0.42, 0.18), Color(0.58, 0.52, 0.28), Color(0.35, 0.30, 0.10)],   # khaki
	]
	var color_set = container_colors[variant % container_colors.size()]
	var base_col = color_set[0]
	var light_col = color_set[1]
	var dark_col = color_set[2]

	img.fill(base_col)
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 77777

	# Corrugated wall texture (vertical ridges)
	for x in range(TILE_SIZE):
		for y in range(3, TILE_SIZE - 3):
			var ridge = x % 4
			var shade = base_col
			if ridge == 0:
				shade = light_col
			elif ridge == 1:
				shade = base_col
			elif ridge == 2:
				shade = base_col.darkened(0.04)
			else:
				shade = dark_col.lightened(0.02)
			img.set_pixel(x, y, shade)

	# Top edge frame
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, dark_col.darkened(0.15))
		img.set_pixel(x, 1, dark_col)
		img.set_pixel(x, 2, base_col.darkened(0.08))

	# Bottom edge frame
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 1, dark_col.darkened(0.15))
		img.set_pixel(x, TILE_SIZE - 2, dark_col)
		img.set_pixel(x, TILE_SIZE - 3, base_col.darkened(0.08))

	# Side frame bars (left and right vertical edges)
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, dark_col.darkened(0.12))
		img.set_pixel(1, y, dark_col)
		img.set_pixel(TILE_SIZE - 1, y, dark_col.darkened(0.12))
		img.set_pixel(TILE_SIZE - 2, y, dark_col)

	# Label/ID rectangle
	var label_left = 8
	var label_right = 24
	var label_top = 10
	var label_bot = 18
	for y in range(label_top, label_bot):
		for x in range(label_left, label_right):
			img.set_pixel(x, y, palette["label_white"])
	# Label text dots (serial number)
	var text_y_val = label_top + 2
	for i in range(rng.randi_range(6, 10)):
		var tx = label_left + 2 + i
		if tx < label_right - 1:
			img.set_pixel(tx, text_y_val, dark_col)
			img.set_pixel(tx, text_y_val + 1, dark_col.lightened(0.1))

	# Rust streaks from top
	if variant % 2 == 0:
		for _i in range(rng.randi_range(1, 3)):
			var rx = rng.randi_range(4, TILE_SIZE - 5)
			var streak_len = rng.randi_range(6, 14)
			for j in range(streak_len):
				var ry = 3 + j
				if ry < TILE_SIZE - 3:
					var rust_strength = 1.0 - float(j) / float(streak_len)
					var current = img.get_pixel(rx, ry)
					img.set_pixel(rx, ry, current.lerp(palette["rust_streak"], rust_strength * 0.5))

	# Dents
	if variant % 5 == 0:
		var dx = rng.randi_range(6, TILE_SIZE - 8)
		var dy = rng.randi_range(8, TILE_SIZE - 8)
		for ddx in range(3):
			for ddy in range(2):
				if dx + ddx < TILE_SIZE and dy + ddy < TILE_SIZE:
					img.set_pixel(dx + ddx, dy + ddy, dark_col.lightened(0.05))


## Floor vent with steam wisps, visible condensation, and moisture staining
func _draw_steam_vent(img: Image, palette: Dictionary, variant: int) -> void:
	# Factory floor base
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 88888

	# Floor texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.6 + y * 0.5 + variant * 1.4) * 0.2 + rng.randf() * 0.12
			if n < -0.15:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.18:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.06:
				img.set_pixel(x, y, palette["mid"])

	# Moisture ring around vent area (darkened wet concrete)
	var vent_cx = (6 + 26) / 2
	var vent_cy = (8 + 24) / 2
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - vent_cx, 2) + pow(y - vent_cy, 2))
			if dist > 10 and dist < 14 and rng.randf() < 0.35:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.06))

	# Vent grate (rectangular, centered) with bolted frame
	var vent_left = 6
	var vent_right = 26
	var vent_top = 8
	var vent_bot = 24

	# Vent frame - thicker with bolt detail
	for x in range(vent_left, vent_right):
		img.set_pixel(x, vent_top, palette["grate_edge"])
		img.set_pixel(x, vent_top - 1, palette["grate_edge"].darkened(0.08))
		img.set_pixel(x, vent_bot, palette["grate_edge"])
		img.set_pixel(x, vent_bot + 1, palette["grate_edge"].darkened(0.08))
	for y in range(vent_top - 1, vent_bot + 2):
		if y >= 0 and y < TILE_SIZE:
			img.set_pixel(vent_left, y, palette["grate_edge"])
			img.set_pixel(vent_left - 1, y, palette["grate_edge"].darkened(0.08)) if vent_left - 1 >= 0 else null
			img.set_pixel(vent_right - 1, y, palette["grate_edge"])
			img.set_pixel(vent_right, y, palette["grate_edge"].darkened(0.08)) if vent_right < TILE_SIZE else null

	# Frame corner bolts
	for corner in [Vector2i(vent_left, vent_top), Vector2i(vent_right - 1, vent_top),
					Vector2i(vent_left, vent_bot), Vector2i(vent_right - 1, vent_bot)]:
		img.set_pixel(corner.x, corner.y, palette["grate_edge"].lightened(0.12))

	# Vent slots with depth and louver angle
	for y in range(vent_top + 1, vent_bot):
		for x in range(vent_left + 1, vent_right - 1):
			if y % 3 == 0:
				img.set_pixel(x, y, palette["vent_slot"])
			elif y % 3 == 1:
				# Louver top edge (bright)
				img.set_pixel(x, y, palette["dark"].lightened(0.08))
			else:
				# Louver body
				img.set_pixel(x, y, palette["dark"].lightened(0.03))

	# Steam wisps rising above vent - more volumetric
	for _w in range(rng.randi_range(4, 8)):
		var sx = rng.randi_range(vent_left + 2, vent_right - 3)
		var sy = rng.randi_range(0, vent_top - 1)
		if sx < TILE_SIZE and sy >= 0 and sy < TILE_SIZE:
			var steam_alpha = 1.0 - float(vent_top - 1 - sy) / float(vent_top)
			img.set_pixel(sx, sy, palette["steam_white"].lerp(palette["base"], 1.0 - steam_alpha * 0.7))
			# Steam spread (wider as it rises)
			if sx + 1 < TILE_SIZE:
				img.set_pixel(sx + 1, sy, palette["steam_fade"].lerp(palette["base"], 1.0 - steam_alpha * 0.4))
			if sx - 1 >= 0:
				img.set_pixel(sx - 1, sy, palette["steam_fade"].lerp(palette["base"], 1.0 - steam_alpha * 0.4))
			# Wispy tendrils
			if sy > 0 and rng.randf() < 0.5:
				var drift = rng.randi_range(-1, 1)
				if sx + drift >= 0 and sx + drift < TILE_SIZE:
					img.set_pixel(sx + drift, sy - 1, palette["steam_fade"].lerp(palette["base"], 0.6))

	# Condensation droplets on floor near vent
	for _d in range(rng.randi_range(4, 8)):
		var dx = rng.randi_range(vent_left - 3, vent_right + 2)
		var dy = rng.randi_range(vent_bot + 1, TILE_SIZE - 1)
		if dx >= 0 and dx < TILE_SIZE and dy >= 0 and dy < TILE_SIZE:
			var current = img.get_pixel(dx, dy)
			img.set_pixel(dx, dy, current.lerp(palette["steam_fade"], 0.25))

	# Steam below vent too (escaping through floor)
	for _w in range(rng.randi_range(2, 4)):
		var sx = rng.randi_range(vent_left + 2, vent_right - 3)
		var sy = rng.randi_range(vent_bot + 1, TILE_SIZE - 1)
		if sx < TILE_SIZE and sy < TILE_SIZE:
			img.set_pixel(sx, sy, palette["steam_fade"].lerp(palette["base"], 0.35))
			if sx + 1 < TILE_SIZE:
				img.set_pixel(sx + 1, sy, palette["steam_fade"].lerp(palette["base"], 0.55))

	# Rust staining on vent frame from moisture
	if variant % 2 == 0:
		for _r in range(rng.randi_range(2, 4)):
			var rx = rng.randi_range(vent_left, vent_right - 1)
			var ry = vent_bot
			if rx < TILE_SIZE and ry + 1 < TILE_SIZE:
				img.set_pixel(rx, ry, Color(0.50, 0.30, 0.16))
				img.set_pixel(rx, ry + 1, Color(0.48, 0.28, 0.14).lerp(palette["base"], 0.5))


## Cramped identical worker housing facade - gray, lifeless, mass-produced, bleak but detailed
func _draw_worker_housing(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 99999

	# Wall texture - flat, featureless concrete panels with subtle staining
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.25 + y * 0.15 + variant * 0.8) * 0.12 + rng.randf() * 0.06
			if n > 0.08:
				img.set_pixel(x, y, palette["light"])
			elif n < -0.06:
				img.set_pixel(x, y, palette["dark"])
			# Water stain streaks running down wall
			if x % 11 == (variant % 5) and y > 4 and rng.randf() < 0.25:
				img.set_pixel(x, y, palette["dark"].darkened(0.04))

	# Horizontal panel seams (prefab concrete look) with gap detail
	for y_seam in [8, 16, 24]:
		if y_seam < TILE_SIZE:
			for x in range(TILE_SIZE):
				img.set_pixel(x, y_seam, palette["deep"])
				if y_seam + 1 < TILE_SIZE:
					img.set_pixel(x, y_seam + 1, palette["dark"])
				# Seal/caulk between panels - slightly different color
				if y_seam - 1 >= 0 and rng.randf() < 0.4:
					img.set_pixel(x, y_seam - 1, palette["base"].darkened(0.03))

	# Small dark windows (identical, soulless) - with more detail
	var window_positions = [
		Vector2i(4, 3), Vector2i(14, 3), Vector2i(24, 3),
		Vector2i(4, 11), Vector2i(14, 11), Vector2i(24, 11),
		Vector2i(4, 19), Vector2i(14, 19), Vector2i(24, 19)
	]
	for wi in range(window_positions.size()):
		var wpos = window_positions[wi]
		if wpos.x + 5 < TILE_SIZE and wpos.y + 4 < TILE_SIZE:
			# Window glass - dark with slight depth gradient
			for wy in range(wpos.y, wpos.y + 4):
				for wx in range(wpos.x, wpos.x + 5):
					var rel_y = float(wy - wpos.y) / 3.0
					var glass_col = palette["window_dark"]
					if rel_y < 0.3:
						glass_col = glass_col.lightened(0.04)
					img.set_pixel(wx, wy, glass_col)
			# Window frame - concrete surround
			for wx in range(wpos.x, wpos.x + 5):
				img.set_pixel(wx, wpos.y, palette["dark"])
				img.set_pixel(wx, wpos.y + 3, palette["dark"])
			for wy in range(wpos.y, wpos.y + 4):
				img.set_pixel(wpos.x, wy, palette["dark"])
				img.set_pixel(wpos.x + 4, wy, palette["dark"])
			# Cross pane divider (every window has a cross)
			img.set_pixel(wpos.x + 2, wpos.y + 1, palette["dark"].lightened(0.06))
			img.set_pixel(wpos.x + 2, wpos.y + 2, palette["dark"].lightened(0.06))
			# Occasional dim light in window
			if rng.randf() < 0.25:
				img.set_pixel(wpos.x + 1, wpos.y + 1, palette["window_glint"])
				img.set_pixel(wpos.x + 3, wpos.y + 1, palette["window_glint"].darkened(0.08))
			# Occasional closed curtain (darker half)
			elif rng.randf() < 0.3:
				for wy in range(wpos.y + 1, wpos.y + 3):
					img.set_pixel(wpos.x + 3, wy, palette["window_dark"].darkened(0.08))
					if wpos.x + 4 < TILE_SIZE:
						img.set_pixel(wpos.x + 4 - 1, wy, palette["window_dark"].darkened(0.05))
			# Window ledge shadow beneath
			if wpos.y + 4 < TILE_SIZE:
				for wx in range(wpos.x, wpos.x + 5):
					img.set_pixel(wx, wpos.y + 4 - 1, palette["dark"].darkened(0.04))

	# Door at bottom center - with more detail
	var door_left = 12
	var door_right = 19
	for y in range(TILE_SIZE - 8, TILE_SIZE):
		for x in range(door_left, door_right):
			var door_shade = palette["door_gray"]
			# Slight panel variation
			if (y - (TILE_SIZE - 8)) % 4 == 0:
				door_shade = door_shade.darkened(0.04)
			img.set_pixel(x, y, door_shade)
	# Door frame
	for y in range(TILE_SIZE - 8, TILE_SIZE):
		img.set_pixel(door_left, y, palette["deep"])
		img.set_pixel(door_right - 1, y, palette["deep"])
	for x in range(door_left, door_right):
		img.set_pixel(x, TILE_SIZE - 8, palette["deep"])
	# Door handle
	img.set_pixel(door_right - 3, TILE_SIZE - 5, palette["light"])
	img.set_pixel(door_right - 3, TILE_SIZE - 4, palette["light"].darkened(0.1))
	# Door number plate
	img.set_pixel(door_left + 2, TILE_SIZE - 7, palette["light"].lightened(0.1))
	img.set_pixel(door_left + 3, TILE_SIZE - 7, palette["light"].lightened(0.1))

	# Roof line at very top with gutter/drip edge
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["roof"])
		img.set_pixel(x, 1, palette["roof"].lightened(0.05))
		# Gutter edge
		img.set_pixel(x, 2, palette["roof"].darkened(0.08))

	# Unit number stencil - more readable, variant-based number
	var unit_num = (variant % 9) + 1
	var num_x = 22
	var num_y = TILE_SIZE - 6
	var num_col = palette["light"].lightened(0.05)
	if num_x + 3 < TILE_SIZE and num_y + 2 < TILE_SIZE:
		# Stenciled number plate background
		for dx in range(5):
			for dy in range(3):
				if num_x + dx < TILE_SIZE and num_y + dy < TILE_SIZE:
					img.set_pixel(num_x + dx, num_y + dy, palette["dark"].lightened(0.02))
		# Simple dot-matrix number
		img.set_pixel(num_x + 1, num_y, num_col)
		img.set_pixel(num_x + 2, num_y, num_col)
		img.set_pixel(num_x + 1, num_y + 1, num_col)
		img.set_pixel(num_x + 3, num_y + 1, num_col)

	# Grime/dirt accumulation at base of wall
	for x in range(TILE_SIZE):
		for dy in range(3):
			var py = TILE_SIZE - 1 - dy
			if py >= 0 and py < TILE_SIZE and rng.randf() < 0.35:
				var current = img.get_pixel(x, py)
				img.set_pixel(x, py, current.darkened(0.05 * (3 - dy)))

	# Pipe/conduit running along one edge
	if variant % 3 == 0:
		var pipe_x = TILE_SIZE - 3
		for y in range(3, TILE_SIZE - 2):
			if pipe_x < TILE_SIZE:
				img.set_pixel(pipe_x, y, palette["dark"].darkened(0.05))
				if pipe_x + 1 < TILE_SIZE:
					img.set_pixel(pipe_x + 1, y, palette["dark"])


## Guard post / checkpoint booth with red/white barrier stripe and window
func _draw_guard_post(img: Image, palette: Dictionary) -> void:
	img.fill(palette["concrete"])

	# Concrete ground
	for y in range(TILE_SIZE - 4, TILE_SIZE):
		for x in range(TILE_SIZE):
			img.set_pixel(x, y, palette["dark"])

	# Booth body (center)
	var booth_left = 4
	var booth_right = 28
	var booth_top = 4
	var booth_bot = TILE_SIZE - 4

	for y in range(booth_top, booth_bot):
		for x in range(booth_left, booth_right):
			var shade = palette["base"]
			if y < booth_top + 2:
				shade = palette["roof_dark"]
			elif x < booth_left + 2 or x >= booth_right - 2:
				shade = palette["dark"]
			img.set_pixel(x, y, shade)

	# Observation window
	var win_left = booth_left + 4
	var win_right = booth_right - 4
	var win_top = booth_top + 4
	var win_bot = booth_top + 12
	for y in range(win_top, win_bot):
		for x in range(win_left, win_right):
			var rel_y = float(y - win_top) / float(win_bot - win_top)
			var glass_shade = palette["glass"]
			if rel_y < 0.3:
				glass_shade = glass_shade.lightened(0.15)
			elif rel_y > 0.7:
				glass_shade = glass_shade.darkened(0.10)
			img.set_pixel(x, y, glass_shade)
	# Window frame
	for x in range(win_left, win_right):
		img.set_pixel(x, win_top, palette["mid"])
		img.set_pixel(x, win_bot - 1, palette["mid"])
	for y in range(win_top, win_bot):
		img.set_pixel(win_left, y, palette["mid"])
		img.set_pixel(win_right - 1, y, palette["mid"])

	# Glare
	img.set_pixel(win_left + 2, win_top + 1, Color(0.92, 0.95, 1.0))
	img.set_pixel(win_left + 3, win_top + 1, Color(0.85, 0.88, 0.95))

	# Red/white barrier stripe below window
	var stripe_y = win_bot + 2
	for x in range(booth_left, booth_right):
		if stripe_y < booth_bot:
			var stripe_pos = (x - booth_left) % 6
			if stripe_pos < 3:
				img.set_pixel(x, stripe_y, palette["stripe_red"])
				img.set_pixel(x, stripe_y + 1, palette["stripe_red"].darkened(0.1))
			else:
				img.set_pixel(x, stripe_y, palette["stripe_white"])
				img.set_pixel(x, stripe_y + 1, palette["stripe_white"].darkened(0.06))

	# Roof overhang
	for x in range(booth_left - 2, booth_right + 2):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, booth_top, palette["roof_dark"])
			img.set_pixel(x, booth_top + 1, palette["roof_dark"].lightened(0.05))
			if booth_top + 2 < TILE_SIZE:
				img.set_pixel(x, booth_top + 2, palette["roof_dark"].darkened(0.08))
			if booth_top + 3 < TILE_SIZE:
				img.set_pixel(x, booth_top + 3, palette["deep"])


## Green-tinted drainage channel with flowing toxic water
func _draw_drainage_channel(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["edge_stone"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 10101

	# Stone edge texture on borders (top and bottom 5 rows)
	for y in [range(0, 5), range(TILE_SIZE - 5, TILE_SIZE)]:
		for row in y:
			for x in range(TILE_SIZE):
				var n = sin(x * 0.6 + row * 0.4 + variant * 1.2) * 0.15 + rng.randf() * 0.1
				if n > 0.1:
					img.set_pixel(x, row, palette["edge_stone"].lightened(0.06))
				elif n < -0.08:
					img.set_pixel(x, row, palette["edge_dark"])

	# Channel walls (sloped)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 5, palette["edge_dark"])
		img.set_pixel(x, TILE_SIZE - 6, palette["edge_dark"])

	# Toxic water fill (center region)
	for y in range(6, TILE_SIZE - 6):
		for x in range(TILE_SIZE):
			var rel_y = float(y - 6) / float(TILE_SIZE - 12)
			var shade = palette["base"]
			# Depth gradient
			if rel_y < 0.2:
				shade = palette["light"]
			elif rel_y < 0.4:
				shade = palette["mid"]
			elif rel_y < 0.6:
				shade = palette["base"]
			elif rel_y < 0.8:
				shade = palette["dark"]
			else:
				shade = palette["deep"]
			# Flow ripple pattern
			var ripple = sin(x * 0.5 + y * 0.3 + variant * 2.5) * 0.15
			ripple += sin(x * 0.2 - y * 0.8 + variant * 1.8) * 0.1
			if ripple > 0.12:
				shade = shade.lightened(0.08)
			elif ripple < -0.10:
				shade = shade.darkened(0.06)
			img.set_pixel(x, y, shade)

	# Chemical green highlights/foam
	for _i in range(rng.randi_range(4, 8)):
		var fx = rng.randi_range(2, TILE_SIZE - 3)
		var fy = rng.randi_range(7, TILE_SIZE - 8)
		img.set_pixel(fx, fy, palette["chemical_green"])
		if fx + 1 < TILE_SIZE:
			img.set_pixel(fx + 1, fy, palette["foam"])

	# Foam patches floating on surface
	if variant % 2 == 0:
		var foam_x = rng.randi_range(6, TILE_SIZE - 10)
		var foam_y = rng.randi_range(8, TILE_SIZE - 10)
		for dx in range(4):
			for dy in range(2):
				if foam_x + dx < TILE_SIZE and foam_y + dy < TILE_SIZE - 6:
					if rng.randf() < 0.6:
						img.set_pixel(foam_x + dx, foam_y + dy, palette["foam"])


## Hazmat barrel on concrete - yellow/black with hazmat symbols, drip stains, corrosion
func _draw_chemical_barrel(img: Image, palette: Dictionary) -> void:
	# Concrete background
	img.fill(palette["concrete"])

	var rng = RandomNumberGenerator.new()
	rng.seed = 54321

	# Concrete texture with chemical staining
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.5 + y * 0.4) * 0.15 + rng.randf() * 0.08
			if n > 0.1:
				img.set_pixel(x, y, palette["concrete"].lightened(0.05))
			elif n < -0.08:
				img.set_pixel(x, y, palette["concrete"].darkened(0.05))

	# Barrel body (center, cylindrical) with dents and wear
	var barrel_left = 8
	var barrel_right = 24
	var barrel_top = 4
	var barrel_bot = TILE_SIZE - 3
	var barrel_width = barrel_right - barrel_left

	for y in range(barrel_top, barrel_bot):
		for x in range(barrel_left, barrel_right):
			var rel_x = float(x - barrel_left) / float(barrel_width)
			var shade: Color
			# Cylindrical shading
			if rel_x < 0.12:
				shade = palette["deep"]
			elif rel_x < 0.25:
				shade = palette["dark"]
			elif rel_x < 0.40:
				shade = palette["mid"]
			elif rel_x < 0.65:
				shade = palette["light"]
			elif rel_x < 0.78:
				shade = palette["mid"]
			elif rel_x < 0.90:
				shade = palette["dark"]
			else:
				shade = palette["deep"]
			# Surface wear
			if rng.randf() < 0.03:
				shade = shade.darkened(0.06)
			img.set_pixel(x, y, shade)

	# Barrel rings (top and bottom bands + middle) with rivet detail
	for ring_y in [barrel_top, barrel_top + 1, (barrel_top + barrel_bot) / 2, barrel_bot - 2, barrel_bot - 1]:
		if ring_y >= 0 and ring_y < TILE_SIZE:
			for x in range(barrel_left, barrel_right):
				var current = img.get_pixel(x, ring_y)
				img.set_pixel(x, ring_y, current.darkened(0.15))
			# Rivets on rings
			if ring_y == (barrel_top + barrel_bot) / 2:
				for rx in range(barrel_left + 2, barrel_right - 2, 4):
					img.set_pixel(rx, ring_y, palette["skull_white"].darkened(0.3))

	# Top cap with bung hole
	for x in range(barrel_left + 2, barrel_right - 2):
		img.set_pixel(x, barrel_top, palette["dark"].darkened(0.1))
	# Bung hole (small dark circle on top cap)
	var bung_x = (barrel_left + barrel_right) / 2 + 2
	if bung_x < barrel_right and barrel_top >= 0:
		img.set_pixel(bung_x, barrel_top, palette["hazard_black"])
		if bung_x + 1 < barrel_right:
			img.set_pixel(bung_x + 1, barrel_top, palette["hazard_black"])

	# Hazard symbol - trefoil/radiation style (3 triangular segments around center)
	var sym_cx = (barrel_left + barrel_right) / 2
	var sym_cy = (barrel_top + barrel_bot) / 2
	# Black diamond background
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			if abs(dx) + abs(dy) <= 4:
				var px = sym_cx + dx
				var py = sym_cy + dy
				if px >= barrel_left and px < barrel_right and py >= barrel_top and py < barrel_bot:
					img.set_pixel(px, py, palette["hazard_black"])
	# Skull face (more detailed - eyes, nose, jaw)
	# Eyes
	img.set_pixel(sym_cx - 1, sym_cy - 2, palette["skull_white"])
	img.set_pixel(sym_cx + 1, sym_cy - 2, palette["skull_white"])
	# Nose
	img.set_pixel(sym_cx, sym_cy - 1, palette["skull_white"])
	# Jaw/teeth row
	img.set_pixel(sym_cx - 2, sym_cy + 1, palette["skull_white"])
	img.set_pixel(sym_cx - 1, sym_cy + 1, palette["skull_white"])
	img.set_pixel(sym_cx, sym_cy + 1, palette["skull_white"])
	img.set_pixel(sym_cx + 1, sym_cy + 1, palette["skull_white"])
	img.set_pixel(sym_cx + 2, sym_cy + 1, palette["skull_white"])
	# Crossbones below skull
	img.set_pixel(sym_cx - 2, sym_cy + 2, palette["skull_white"])
	img.set_pixel(sym_cx + 2, sym_cy + 2, palette["skull_white"])
	img.set_pixel(sym_cx - 1, sym_cy + 3, palette["skull_white"])
	img.set_pixel(sym_cx + 1, sym_cy + 3, palette["skull_white"])
	img.set_pixel(sym_cx, sym_cy + 2, palette["skull_white"])

	# Chemical drip from barrel - multiple drip paths
	var drip_x1 = barrel_right - 2
	var drip_x2 = barrel_left + 1
	for drip_x in [drip_x1, drip_x2]:
		var drip_active = (drip_x == drip_x1) or (rng.randf() < 0.5)
		if drip_active:
			for dy in range(barrel_bot, TILE_SIZE):
				if dy < TILE_SIZE and drip_x < TILE_SIZE and drip_x >= 0:
					var drip_fade = float(dy - barrel_bot) / float(TILE_SIZE - barrel_bot)
					var drip_col = palette["drip_green"].lerp(palette["concrete"], drip_fade * 0.7)
					# Drip wobble
					var wobble = 0
					if dy > barrel_bot + 2:
						wobble = rng.randi_range(-1, 0)
					if drip_x + wobble >= 0 and drip_x + wobble < TILE_SIZE:
						img.set_pixel(drip_x + wobble, dy, drip_col)

	# Puddle under barrel - larger and more detailed
	for dx in range(-3, 4):
		for dy in range(-1, 2):
			var px = drip_x1 + dx
			var py = TILE_SIZE - 1 + dy - 1
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var dist = abs(dx) / 4.0
				if rng.randf() < 0.7 - dist * 0.3:
					img.set_pixel(px, py, palette["drip_green"].darkened(0.10 + dist * 0.1))

	# Chemical stain on concrete around base
	for dx in range(-2, barrel_width + 3):
		var px = barrel_left + dx
		if px >= 0 and px < TILE_SIZE:
			var py = barrel_bot
			if py < TILE_SIZE and rng.randf() < 0.3:
				img.set_pixel(px, py, palette["concrete"].lerp(palette["drip_green"], 0.15))

	# Dent in barrel side
	var dent_x = barrel_left + 3
	var dent_y = barrel_top + 6
	if dent_x + 2 < barrel_right and dent_y + 2 < barrel_bot:
		img.set_pixel(dent_x, dent_y, palette["dark"].lightened(0.04))
		img.set_pixel(dent_x + 1, dent_y, palette["dark"].lightened(0.02))
		img.set_pixel(dent_x, dent_y + 1, palette["mid"].darkened(0.02))


## Exposed industrial pipes (multiple parallel, impassable)
func _draw_pipe_cluster(img: Image, palette: Dictionary, variant: int) -> void:
	# Dark background behind pipes
	img.fill(palette["deep"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12121

	# Background wall texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.12
			if n < 0.03:
				img.set_pixel(x, y, Color(0.14, 0.12, 0.10))

	# Three horizontal pipes at different heights
	var pipe_specs = [
		{"y": 4, "radius": 4, "color": "base"},
		{"y": 16, "radius": 5, "color": "copper"},
		{"y": 26, "radius": 3, "color": "mid"}
	]

	for spec in pipe_specs:
		var pipe_cy = spec["y"]
		var pipe_r = spec["radius"]
		var pipe_col = palette[spec["color"]]

		for y in range(pipe_cy - pipe_r, pipe_cy + pipe_r + 1):
			if y < 0 or y >= TILE_SIZE:
				continue
			for x in range(TILE_SIZE):
				var rel_y = float(y - (pipe_cy - pipe_r)) / float(pipe_r * 2)
				var shade: Color
				# Cylindrical shading
				if rel_y < 0.15:
					shade = pipe_col.lightened(0.18)
				elif rel_y < 0.30:
					shade = pipe_col.lightened(0.08)
				elif rel_y < 0.50:
					shade = pipe_col
				elif rel_y < 0.70:
					shade = pipe_col.darkened(0.08)
				elif rel_y < 0.85:
					shade = pipe_col.darkened(0.18)
				else:
					shade = pipe_col.darkened(0.28)

				# Patina on copper pipe
				if spec["color"] == "copper" and variant % 2 == 0:
					var patina_n = sin(x * 0.3 + y * 0.5 + variant * 2.0) * 0.3
					if patina_n > 0.15:
						shade = shade.lerp(palette["copper_patina"], 0.35)

				img.set_pixel(x, y, shade)

		# Joint rings every 10 pixels
		for jx in range(0, TILE_SIZE, 10):
			for dy in range(-pipe_r - 1, pipe_r + 2):
				var jy = pipe_cy + dy
				if jy >= 0 and jy < TILE_SIZE:
					for dx in range(2):
						if jx + dx >= 0 and jx + dx < TILE_SIZE:
							img.set_pixel(jx + dx, jy, palette["joint_ring"])

	# Steam leak on one pipe (variant-dependent)
	if variant % 3 == 0:
		var steam_x = rng.randi_range(8, TILE_SIZE - 8)
		var steam_y = pipe_specs[1]["y"] - pipe_specs[1]["radius"] - 1
		for _w in range(4):
			var sx = steam_x + rng.randi_range(-2, 2)
			var sy = steam_y - rng.randi_range(0, 3)
			if sx >= 0 and sx < TILE_SIZE and sy >= 0 and sy < TILE_SIZE:
				img.set_pixel(sx, sy, palette["steam"])


## Yellow/black warning sign on metal post
func _draw_warning_sign(img: Image, palette: Dictionary) -> void:
	# Concrete ground
	img.fill(palette["concrete"])

	# Post (center vertical)
	var post_x = TILE_SIZE / 2
	for y in range(14, TILE_SIZE - 2):
		img.set_pixel(post_x - 1, y, palette["post_dark"])
		img.set_pixel(post_x, y, palette["post_gray"])
		img.set_pixel(post_x + 1, y, palette["post_gray"].lightened(0.08))

	# Post base
	for dx in range(-2, 3):
		var px = post_x + dx
		if px >= 0 and px < TILE_SIZE:
			img.set_pixel(px, TILE_SIZE - 2, palette["post_dark"])
			img.set_pixel(px, TILE_SIZE - 1, palette["post_dark"].darkened(0.1))

	# Warning sign (diamond shape, rotated 45 degrees)
	var sign_cx = TILE_SIZE / 2
	var sign_cy = 8
	var sign_r = 7

	# Diamond background
	for dy in range(-sign_r, sign_r + 1):
		for dx in range(-sign_r, sign_r + 1):
			if abs(dx) + abs(dy) <= sign_r:
				var px = sign_cx + dx
				var py = sign_cy + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					img.set_pixel(px, py, palette["base"])

	# Diamond border (black outline)
	for i in range(-sign_r, sign_r + 1):
		# Top-right edge
		var px1 = sign_cx + i
		var py1 = sign_cy - (sign_r - abs(i))
		if px1 >= 0 and px1 < TILE_SIZE and py1 >= 0 and py1 < TILE_SIZE:
			img.set_pixel(px1, py1, palette["hazard_black"])
		# Bottom-left edge
		var px2 = sign_cx + i
		var py2 = sign_cy + (sign_r - abs(i))
		if px2 >= 0 and px2 < TILE_SIZE and py2 >= 0 and py2 < TILE_SIZE:
			img.set_pixel(px2, py2, palette["hazard_black"])

	# Exclamation mark in center
	for dy in range(-3, 1):
		var py = sign_cy + dy
		if py >= 0 and py < TILE_SIZE:
			img.set_pixel(sign_cx, py, palette["hazard_black"])
	# Dot of exclamation
	if sign_cy + 2 < TILE_SIZE:
		img.set_pixel(sign_cx, sign_cy + 2, palette["hazard_black"])

	# Highlight on sign face
	for dy in range(-sign_r + 2, 0):
		for dx in range(-1, 1):
			var px = sign_cx + dx - 2
			var py = sign_cy + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				if abs(px - sign_cx) + abs(py - sign_cy) < sign_r - 1:
					var current = img.get_pixel(px, py)
					if not current.is_equal_approx(palette["hazard_black"]):
						img.set_pixel(px, py, palette["light"])


## Chain-link wire fence on dirt ground
func _draw_chain_link_fence(img: Image, palette: Dictionary, variant: int) -> void:
	# Dirt ground
	img.fill(palette["dirt"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 13131

	# Dirt texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.7 + y * 0.5 + variant * 1.6) * 0.25 + rng.randf() * 0.18
			if n < -0.15:
				img.set_pixel(x, y, palette["dirt_dark"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["dirt"].lightened(0.06))

	# Fence posts (vertical metal tubes)
	var post_spacing = 10
	for px_base in range(2, TILE_SIZE, post_spacing):
		if px_base + 2 < TILE_SIZE:
			for y in range(3, TILE_SIZE - 3):
				img.set_pixel(px_base, y, palette["post"])
				img.set_pixel(px_base + 1, y, palette["mid"])
			# Post cap
			img.set_pixel(px_base, 2, palette["light"])
			img.set_pixel(px_base + 1, 2, palette["light"])
			# Post base
			img.set_pixel(px_base, TILE_SIZE - 3, palette["deep"])
			img.set_pixel(px_base + 1, TILE_SIZE - 3, palette["deep"])

	# Chain-link diamond mesh pattern
	for y in range(4, TILE_SIZE - 4):
		for x in range(TILE_SIZE):
			# Skip post positions
			var on_post = false
			for post_check in range(2, TILE_SIZE, post_spacing):
				if x >= post_check and x <= post_check + 1:
					on_post = true
					break
			if on_post:
				continue

			# Diamond mesh: diagonal crosshatch
			var diag1 = (x + y) % 4
			var diag2 = (x - y + 100) % 4  # +100 to avoid negative modulo
			if diag1 == 0 or diag2 == 0:
				var wire_shade = palette["wire"]
				# Add subtle variation
				var n = sin(x * 0.5 + y * 0.3) * 0.1
				if n > 0.05:
					wire_shade = wire_shade.lightened(0.06)
				elif n < -0.05:
					wire_shade = wire_shade.darkened(0.06)
				img.set_pixel(x, y, wire_shade)

	# Top rail (horizontal bar)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 3, palette["base"])
		img.set_pixel(x, 4, palette["dark"])

	# Bottom rail
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 5, palette["base"])
		img.set_pixel(x, TILE_SIZE - 4, palette["dark"])

	# Barbed wire on top (optional, variant-dependent)
	if variant % 2 == 0:
		for x in range(0, TILE_SIZE, 3):
			if x + 1 < TILE_SIZE:
				img.set_pixel(x, 2, palette["mid"])
				img.set_pixel(x + 1, 1, palette["base"])
				if x + 2 < TILE_SIZE:
					img.set_pixel(x + 2, 2, palette["mid"])


## Warmer linoleum floor with coffee stains, crumbs, scuff marks - humanity persists here
func _draw_break_room_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 14141

	# Warmer concrete/linoleum texture - noticeably different from factory floor
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.4 + variant * 1.0) * cos(y * 0.35 + variant * 0.6)
			var n2 = sin(x * 0.9 + y * 0.6 + variant * 1.5) * 0.3
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.14
			if combined < -0.20:
				img.set_pixel(x, y, palette["deep"])
			elif combined < -0.08:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.22:
				img.set_pixel(x, y, palette["linoleum_light"])
			elif combined > 0.10:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.02:
				img.set_pixel(x, y, palette["warmth"])
			# Overall warm tint compared to factory
			if rng.randf() < 0.08:
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(palette["warmth"], 0.15))

	# Linoleum tile pattern (faint grid, 8x8 squares) with alternating shade
	for ty in range(0, TILE_SIZE, 8):
		for tx in range(0, TILE_SIZE, 8):
			var checker = ((tx / 8) + (ty / 8)) % 2
			if checker == 1:
				for dy in range(8):
					for dx in range(8):
						var px = tx + dx
						var py = ty + dy
						if px < TILE_SIZE and py < TILE_SIZE:
							var current = img.get_pixel(px, py)
							img.set_pixel(px, py, current.lerp(palette["warmth"], 0.08))

	# Tile grid lines
	for x in range(TILE_SIZE):
		if x % 8 == 0:
			for y in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.05))
	for y in range(TILE_SIZE):
		if y % 8 == 0:
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.05))

	# Coffee ring stain (circular, warm brown) - more detailed
	if variant % 2 == 0:
		var ring_cx = rng.randi_range(10, TILE_SIZE - 10)
		var ring_cy = rng.randi_range(10, TILE_SIZE - 10)
		var ring_r = rng.randi_range(4, 6)
		for y in range(TILE_SIZE):
			for x in range(TILE_SIZE):
				var dist = sqrt(pow(x - ring_cx, 2) + pow(y - ring_cy, 2))
				# Ring (not filled circle) - thicker, more visible
				if dist > ring_r - 1.2 and dist < ring_r + 1.0:
					if rng.randf() < 0.78:
						var ring_shade = palette["coffee_ring"]
						# Ring is darker at bottom (gravity)
						if y > ring_cy:
							ring_shade = ring_shade.darkened(0.06)
						img.set_pixel(x, y, ring_shade)
				# Faint fill inside
				elif dist < ring_r - 1.2:
					if rng.randf() < 0.25:
						var current = img.get_pixel(x, y)
						img.set_pixel(x, y, current.lerp(palette["coffee"], 0.18))

	# Spilled coffee spot (separate from ring) with drip trail
	if variant % 3 == 0:
		var sx = rng.randi_range(4, TILE_SIZE - 8)
		var sy = rng.randi_range(4, TILE_SIZE - 8)
		for dy in range(4):
			for dx in range(5):
				var px = sx + dx
				var py = sy + dy
				if px < TILE_SIZE and py < TILE_SIZE:
					var dist = sqrt(pow(dx - 2.5, 2) + pow(dy - 2.0, 2))
					if dist < 2.5 and rng.randf() < 0.65:
						img.set_pixel(px, py, palette["coffee"])
		# Drip trail from spill
		for trail in range(3):
			var tx = sx + 2 + rng.randi_range(-1, 1)
			var ty = sy + 4 + trail
			if tx >= 0 and tx < TILE_SIZE and ty >= 0 and ty < TILE_SIZE:
				img.set_pixel(tx, ty, palette["coffee"].lerp(palette["base"], float(trail) / 3.0))

	# Scuff marks from chair legs (arc-shaped scratches)
	if variant % 4 == 0:
		for _i in range(rng.randi_range(1, 3)):
			var scuff_x = rng.randi_range(4, TILE_SIZE - 8)
			var scuff_y = rng.randi_range(4, TILE_SIZE - 4)
			# Curved scuff arc
			for dx in range(4):
				var dy_offset = 0 if dx < 2 else 1
				if scuff_x + dx < TILE_SIZE and scuff_y + dy_offset < TILE_SIZE:
					img.set_pixel(scuff_x + dx, scuff_y + dy_offset, palette["dark"])

	# Crumb trail (tiny bright specks - someone was eating)
	if variant % 2 == 0:
		for _c in range(rng.randi_range(3, 6)):
			var cx = rng.randi_range(2, TILE_SIZE - 3)
			var cy = rng.randi_range(2, TILE_SIZE - 3)
			img.set_pixel(cx, cy, palette["linoleum_light"].lightened(0.08))

	# Sugar packet or wrapper corner (tiny colored rectangle)
	if variant % 5 == 0:
		var wx = rng.randi_range(4, TILE_SIZE - 6)
		var wy = rng.randi_range(4, TILE_SIZE - 6)
		var wrapper_col = Color(0.85, 0.85, 0.82)  # White wrapper
		for dx in range(3):
			for dy in range(2):
				if wx + dx < TILE_SIZE and wy + dy < TILE_SIZE:
					img.set_pixel(wx + dx, wy + dy, wrapper_col)
		# Brand stripe on wrapper
		if wx + 1 < TILE_SIZE and wy < TILE_SIZE:
			img.set_pixel(wx + 1, wy, Color(0.75, 0.25, 0.20))

	# Slightly worn path to door (lighter strip at edge)
	if variant % 3 == 0:
		for y in range(TILE_SIZE):
			for dx in range(3):
				var px = dx
				if px < TILE_SIZE:
					var current = img.get_pixel(px, y)
					img.set_pixel(px, y, current.lightened(0.03))


## Create tileset with all industrial tiles
func create_tileset() -> TileSet:
	print("Creating industrial factory tileset...")
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
		TileType.FACTORY_FLOOR, TileType.IRON_GRATING, TileType.BRICK_WALL, TileType.SMOKESTACK,
		# Row 1: Mechanical/transport
		TileType.CONVEYOR_BELT, TileType.RAIL_TRACK, TileType.CARGO_CONTAINER, TileType.STEAM_VENT,
		# Row 2: Buildings/hazards
		TileType.WORKER_HOUSING, TileType.GUARD_POST, TileType.DRAINAGE_CHANNEL, TileType.CHEMICAL_BARREL,
		# Row 3: Infrastructure/misc
		TileType.PIPE_CLUSTER, TileType.WARNING_SIGN, TileType.CHAIN_LINK_FENCE, TileType.BREAK_ROOM_FLOOR
	]

	# Impassable tile types (need collision)
	var impassable_types = [
		TileType.BRICK_WALL, TileType.SMOKESTACK, TileType.CARGO_CONTAINER,
		TileType.WORKER_HOUSING, TileType.GUARD_POST, TileType.CHEMICAL_BARREL,
		TileType.PIPE_CLUSTER, TileType.WARNING_SIGN, TileType.CHAIN_LINK_FENCE
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
	atlas_img.save_png("user://debug_industrial_atlas.png")
	print("Industrial atlas saved (size: %dx%d, %d tiles)" % [atlas_img.get_width(), atlas_img.get_height(), tile_order.size()])

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
