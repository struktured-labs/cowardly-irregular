extends Node
class_name FuturisticTileGenerator

## FuturisticTileGenerator - Procedurally generates 32x32 digital cityscape tiles
## Area 4: "Optimized for Computation" - Tron meets Ghost in the Shell meets sterile Apple Store
## Cool palette: electric blues, cyan, white, deep navy, neon accents
## Clean geometric shapes, holographic surfaces, scan lines, grid patterns, LED strips

const TILE_SIZE: int = 32

## Tile types for Area 4 (Futuristic digital computation world)
enum TileType {
	CIRCUIT_FLOOR,       # 0 - dark floor with glowing circuit trace patterns
	DATA_HIGHWAY,        # 1 - flowing light streaks on dark surface
	SERVER_TOWER,        # 2 - tall server rack with blinking LEDs (impassable)
	HOLOGRAM_DISPLAY,    # 3 - transparent blue projection surface
	SLEEP_POD,           # 4 - individual pod with status light (impassable)
	COOLING_VENT,        # 5 - floor grate with blue mist
	FIBER_CONDUIT,       # 6 - glowing fiber optic cable channel
	TERMINAL_STATION,    # 7 - computer terminal on pedestal (impassable)
	ANTENNA_ARRAY,       # 8 - tall antenna with signal rings (impassable)
	ENERGY_CELL,         # 9 - power storage unit, glowing core (impassable)
	SCAN_GATE,           # 10 - security scanner archway (impassable)
	PIXEL_GARDEN,        # 11 - digital plants made of light particles
	GLITCH_TILE,         # 12 - corrupted/flickering tile with RGB artifacts
	NEON_WALL,           # 13 - smooth wall with neon strip accent (impassable)
	ACCESS_PANEL,        # 14 - interactive floor panel with auth display
	VOID_FLOOR           # 15 - near-black floor hinting at the abyss below
}

## Digital computation color palettes - electric blues, cyan, deep navy, neon accents
const PALETTES: Dictionary = {
	TileType.CIRCUIT_FLOOR: {
		"base": Color(0.08, 0.10, 0.14),
		"light": Color(0.12, 0.15, 0.20),
		"mid": Color(0.10, 0.12, 0.17),
		"dark": Color(0.05, 0.07, 0.10),
		"deep": Color(0.03, 0.04, 0.06),
		"trace_cyan": Color(0.10, 0.78, 0.88),
		"trace_dim": Color(0.06, 0.42, 0.50),
		"node_bright": Color(0.20, 0.92, 1.0),
		"grid": Color(0.08, 0.18, 0.24)
	},
	TileType.DATA_HIGHWAY: {
		"base": Color(0.06, 0.08, 0.12),
		"light": Color(0.10, 0.14, 0.20),
		"mid": Color(0.08, 0.11, 0.16),
		"dark": Color(0.04, 0.05, 0.08),
		"deep": Color(0.02, 0.03, 0.05),
		"streak_blue": Color(0.20, 0.60, 0.95),
		"streak_white": Color(0.70, 0.88, 1.0),
		"streak_cyan": Color(0.15, 0.82, 0.92),
		"edge_glow": Color(0.08, 0.30, 0.50)
	},
	TileType.SERVER_TOWER: {
		"base": Color(0.15, 0.16, 0.20),
		"light": Color(0.25, 0.27, 0.32),
		"mid": Color(0.20, 0.22, 0.26),
		"dark": Color(0.10, 0.11, 0.14),
		"deep": Color(0.05, 0.06, 0.08),
		"led_green": Color(0.15, 0.92, 0.30),
		"led_amber": Color(0.95, 0.72, 0.12),
		"led_red": Color(0.92, 0.15, 0.12),
		"vent_slot": Color(0.04, 0.04, 0.06)
	},
	TileType.HOLOGRAM_DISPLAY: {
		"base": Color(0.08, 0.18, 0.32),
		"light": Color(0.18, 0.38, 0.58),
		"mid": Color(0.12, 0.28, 0.45),
		"dark": Color(0.05, 0.12, 0.22),
		"deep": Color(0.03, 0.08, 0.15),
		"holo_cyan": Color(0.30, 0.85, 0.95),
		"holo_blue": Color(0.20, 0.55, 0.90),
		"scanline": Color(0.15, 0.45, 0.68),
		"flicker": Color(0.40, 0.92, 1.0)
	},
	TileType.SLEEP_POD: {
		"base": Color(0.18, 0.20, 0.24),
		"light": Color(0.30, 0.32, 0.38),
		"mid": Color(0.24, 0.26, 0.30),
		"dark": Color(0.12, 0.13, 0.16),
		"deep": Color(0.06, 0.07, 0.09),
		"status_green": Color(0.12, 0.85, 0.40),
		"status_blue": Color(0.20, 0.55, 0.92),
		"glass_tint": Color(0.15, 0.30, 0.48),
		"frame_chrome": Color(0.55, 0.58, 0.62)
	},
	TileType.COOLING_VENT: {
		"base": Color(0.12, 0.14, 0.18),
		"light": Color(0.20, 0.22, 0.28),
		"mid": Color(0.16, 0.18, 0.22),
		"dark": Color(0.08, 0.09, 0.12),
		"deep": Color(0.04, 0.05, 0.07),
		"grate_metal": Color(0.35, 0.38, 0.42),
		"grate_dark": Color(0.18, 0.20, 0.24),
		"mist_blue": Color(0.30, 0.65, 0.85, 0.50),
		"mist_light": Color(0.50, 0.80, 0.95, 0.35)
	},
	TileType.FIBER_CONDUIT: {
		"base": Color(0.07, 0.09, 0.13),
		"light": Color(0.12, 0.15, 0.20),
		"mid": Color(0.09, 0.11, 0.16),
		"dark": Color(0.05, 0.06, 0.09),
		"deep": Color(0.03, 0.04, 0.06),
		"fiber_magenta": Color(0.92, 0.20, 0.65),
		"fiber_cyan": Color(0.15, 0.88, 0.95),
		"fiber_green": Color(0.20, 0.90, 0.45),
		"conduit_metal": Color(0.28, 0.30, 0.35)
	},
	TileType.TERMINAL_STATION: {
		"base": Color(0.14, 0.15, 0.19),
		"light": Color(0.24, 0.26, 0.32),
		"mid": Color(0.18, 0.20, 0.25),
		"dark": Color(0.09, 0.10, 0.13),
		"deep": Color(0.04, 0.05, 0.07),
		"screen_green": Color(0.15, 0.88, 0.35),
		"screen_bg": Color(0.02, 0.12, 0.05),
		"keyboard": Color(0.22, 0.24, 0.28),
		"pedestal": Color(0.30, 0.32, 0.38)
	},
	TileType.ANTENNA_ARRAY: {
		"base": Color(0.08, 0.10, 0.14),
		"light": Color(0.15, 0.18, 0.24),
		"mid": Color(0.11, 0.13, 0.18),
		"dark": Color(0.05, 0.06, 0.09),
		"deep": Color(0.03, 0.04, 0.06),
		"antenna_silver": Color(0.62, 0.65, 0.70),
		"antenna_dark": Color(0.35, 0.38, 0.42),
		"signal_ring": Color(0.25, 0.70, 0.92),
		"signal_fade": Color(0.15, 0.45, 0.65)
	},
	TileType.ENERGY_CELL: {
		"base": Color(0.12, 0.13, 0.17),
		"light": Color(0.22, 0.24, 0.30),
		"mid": Color(0.16, 0.18, 0.22),
		"dark": Color(0.08, 0.09, 0.12),
		"deep": Color(0.04, 0.05, 0.07),
		"core_blue": Color(0.20, 0.55, 0.98),
		"core_white": Color(0.65, 0.85, 1.0),
		"core_glow": Color(0.30, 0.65, 0.95),
		"casing_chrome": Color(0.42, 0.45, 0.50)
	},
	TileType.SCAN_GATE: {
		"base": Color(0.14, 0.15, 0.19),
		"light": Color(0.25, 0.28, 0.34),
		"mid": Color(0.19, 0.21, 0.26),
		"dark": Color(0.09, 0.10, 0.13),
		"deep": Color(0.05, 0.05, 0.07),
		"scan_red": Color(0.95, 0.18, 0.15),
		"scan_green": Color(0.15, 0.90, 0.35),
		"pillar_chrome": Color(0.50, 0.53, 0.58),
		"pillar_dark": Color(0.25, 0.28, 0.32)
	},
	TileType.PIXEL_GARDEN: {
		"base": Color(0.06, 0.10, 0.08),
		"light": Color(0.10, 0.18, 0.14),
		"mid": Color(0.08, 0.14, 0.10),
		"dark": Color(0.04, 0.07, 0.05),
		"deep": Color(0.02, 0.04, 0.03),
		"pixel_green": Color(0.15, 0.92, 0.45),
		"pixel_cyan": Color(0.20, 0.85, 0.82),
		"pixel_white": Color(0.72, 0.95, 0.88),
		"pixel_magenta": Color(0.85, 0.25, 0.70)
	},
	TileType.GLITCH_TILE: {
		"base": Color(0.10, 0.10, 0.12),
		"light": Color(0.20, 0.18, 0.22),
		"mid": Color(0.14, 0.13, 0.16),
		"dark": Color(0.06, 0.06, 0.08),
		"deep": Color(0.03, 0.02, 0.04),
		"glitch_red": Color(0.95, 0.10, 0.10),
		"glitch_green": Color(0.10, 0.95, 0.10),
		"glitch_blue": Color(0.10, 0.10, 0.95),
		"corruption": Color(0.85, 0.75, 0.20)
	},
	TileType.NEON_WALL: {
		"base": Color(0.15, 0.17, 0.22),
		"light": Color(0.25, 0.28, 0.35),
		"mid": Color(0.20, 0.22, 0.28),
		"dark": Color(0.10, 0.11, 0.14),
		"deep": Color(0.05, 0.06, 0.08),
		"neon_cyan": Color(0.15, 0.88, 0.95),
		"neon_glow": Color(0.25, 0.72, 0.85),
		"wall_panel": Color(0.18, 0.20, 0.25),
		"seam": Color(0.08, 0.09, 0.12)
	},
	TileType.ACCESS_PANEL: {
		"base": Color(0.10, 0.12, 0.16),
		"light": Color(0.18, 0.22, 0.28),
		"mid": Color(0.14, 0.16, 0.22),
		"dark": Color(0.06, 0.08, 0.11),
		"deep": Color(0.03, 0.04, 0.06),
		"panel_blue": Color(0.15, 0.45, 0.78),
		"panel_glow": Color(0.30, 0.62, 0.92),
		"auth_green": Color(0.15, 0.85, 0.40),
		"border_chrome": Color(0.40, 0.43, 0.48)
	},
	TileType.VOID_FLOOR: {
		"base": Color(0.03, 0.04, 0.06),
		"light": Color(0.07, 0.08, 0.12),
		"mid": Color(0.05, 0.06, 0.08),
		"dark": Color(0.02, 0.02, 0.04),
		"deep": Color(0.01, 0.01, 0.02),
		"star": Color(0.30, 0.50, 0.75),
		"star_bright": Color(0.55, 0.72, 0.95),
		"grid_faint": Color(0.05, 0.08, 0.12),
		"pulse": Color(0.08, 0.15, 0.28)
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
	var palette = PALETTES.get(type, PALETTES[TileType.CIRCUIT_FLOOR])

	match type:
		TileType.CIRCUIT_FLOOR:
			_draw_circuit_floor(img, palette, variant)
		TileType.DATA_HIGHWAY:
			_draw_data_highway(img, palette, variant)
		TileType.SERVER_TOWER:
			_draw_server_tower(img, palette, variant)
		TileType.HOLOGRAM_DISPLAY:
			_draw_hologram_display(img, palette, variant)
		TileType.SLEEP_POD:
			_draw_sleep_pod(img, palette, variant)
		TileType.COOLING_VENT:
			_draw_cooling_vent(img, palette, variant)
		TileType.FIBER_CONDUIT:
			_draw_fiber_conduit(img, palette, variant)
		TileType.TERMINAL_STATION:
			_draw_terminal_station(img, palette)
		TileType.ANTENNA_ARRAY:
			_draw_antenna_array(img, palette)
		TileType.ENERGY_CELL:
			_draw_energy_cell(img, palette)
		TileType.SCAN_GATE:
			_draw_scan_gate(img, palette)
		TileType.PIXEL_GARDEN:
			_draw_pixel_garden(img, palette, variant)
		TileType.GLITCH_TILE:
			_draw_glitch_tile(img, palette, variant)
		TileType.NEON_WALL:
			_draw_neon_wall(img, palette, variant)
		TileType.ACCESS_PANEL:
			_draw_access_panel(img, palette, variant)
		TileType.VOID_FLOOR:
			_draw_void_floor(img, palette, variant)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## Dark floor with glowing circuit traces, junction nodes, and subtle grid underlay
func _draw_circuit_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 11111

	# Subtle digital noise texture with PCB-like micro detail
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n1 = sin(x * 0.8 + variant * 1.5) * cos(y * 0.6 + variant * 0.9)
			var n2 = sin(x * 1.4 + y * 0.9 + variant * 2.2) * 0.25
			var combined = (n1 + n2) / 2.0 + rng.randf() * 0.10
			if combined < -0.2:
				img.set_pixel(x, y, palette["dark"])
			elif combined > 0.25:
				img.set_pixel(x, y, palette["light"])
			elif combined > 0.1:
				img.set_pixel(x, y, palette["mid"])

	# Faint background grid (every 8 pixels) - substrate pattern
	for x in range(TILE_SIZE):
		if x % 8 == 0:
			for y in range(TILE_SIZE):
				img.set_pixel(x, y, palette["grid"])
	for y in range(TILE_SIZE):
		if y % 8 == 0:
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, palette["grid"])

	# Multiple circuit traces with varying brightness based on variant
	var trace_y1 = 6 + (variant % 3) * 3
	var trace_y2 = 18 + (variant % 2) * 4
	var trace_y3 = 28 + (variant % 2) * 2  # Third trace for denser pattern

	# Draw traces with 2px width and glowing edges
	var trace_ys = [trace_y1, trace_y2]
	if trace_y3 < TILE_SIZE - 1:
		trace_ys.append(trace_y3)

	for ty in trace_ys:
		if ty >= TILE_SIZE:
			continue
		for x in range(TILE_SIZE):
			# Main trace line (bright center)
			img.set_pixel(x, ty, palette["trace_cyan"])
			# Dimmer second pixel for width
			if ty + 1 < TILE_SIZE:
				img.set_pixel(x, ty + 1, palette["trace_dim"])
			# Subtle glow above and below
			if ty - 1 >= 0:
				var above = img.get_pixel(x, ty - 1)
				img.set_pixel(x, ty - 1, above.lerp(palette["trace_cyan"], 0.15))
			if ty + 2 < TILE_SIZE:
				var below = img.get_pixel(x, ty + 2)
				img.set_pixel(x, ty + 2, below.lerp(palette["trace_cyan"], 0.10))

	# Vertical connectors between traces (2-3 of them)
	var vert_positions = [8 + (variant % 3) * 4, 20 + (variant % 4) * 3]
	if variant % 2 == 0:
		vert_positions.append(28)

	for vert_x in vert_positions:
		if vert_x >= TILE_SIZE:
			continue
		var y_start = trace_y1
		var y_end = trace_ys[trace_ys.size() - 1] + 1
		for y in range(y_start, mini(y_end + 1, TILE_SIZE)):
			img.set_pixel(vert_x, y, palette["trace_cyan"])
			# Side glow
			if vert_x - 1 >= 0:
				var left = img.get_pixel(vert_x - 1, y)
				img.set_pixel(vert_x - 1, y, left.lerp(palette["trace_cyan"], 0.12))
			if vert_x + 1 < TILE_SIZE:
				var right = img.get_pixel(vert_x + 1, y)
				img.set_pixel(vert_x + 1, y, right.lerp(palette["trace_cyan"], 0.12))

	# Junction nodes at all trace intersections (bright 3x3 diamonds with glow halos)
	var junctions: Array[Vector2i] = []
	for vert_x in vert_positions:
		for ty in trace_ys:
			if vert_x < TILE_SIZE and ty < TILE_SIZE:
				junctions.append(Vector2i(vert_x, ty))
	# Edge junctions
	junctions.append(Vector2i(0, trace_y1))
	junctions.append(Vector2i(TILE_SIZE - 1, trace_y2))

	for junc in junctions:
		if junc.x < 0 or junc.x >= TILE_SIZE or junc.y < 0 or junc.y >= TILE_SIZE:
			continue
		# Bright center pixel
		img.set_pixel(junc.x, junc.y, palette["node_bright"])
		# Diamond pattern around center
		var diamond_offsets = [
			Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)
		]
		for off in diamond_offsets:
			var px = junc.x + off.x
			var py = junc.y + off.y
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				img.set_pixel(px, py, palette["node_bright"].lerp(palette["trace_cyan"], 0.3))
		# Wider glow halo (2px radius)
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				if abs(dx) + abs(dy) > 2:
					continue
				if dx == 0 and dy == 0:
					continue
				if abs(dx) <= 1 and abs(dy) <= 1 and (dx == 0 or dy == 0):
					continue  # Already drawn as diamond
				var px = junc.x + dx
				var py = junc.y + dy
				if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
					var current = img.get_pixel(px, py)
					img.set_pixel(px, py, current.lerp(palette["trace_cyan"], 0.25))

	# Component pads (IC chips - small rectangles with pin dots)
	for _i in range(rng.randi_range(2, 4)):
		var cx = rng.randi_range(3, TILE_SIZE - 6)
		var cy = rng.randi_range(3, TILE_SIZE - 5)
		# Chip body (3x2 dark rectangle)
		for dx in range(3):
			for dy in range(2):
				if cx + dx < TILE_SIZE and cy + dy < TILE_SIZE:
					img.set_pixel(cx + dx, cy + dy, palette["dark"].darkened(0.15))
		# Pin dots on sides
		if cy - 1 >= 0 and cx + 1 < TILE_SIZE:
			img.set_pixel(cx, cy - 1, palette["trace_dim"])
			img.set_pixel(cx + 2, cy - 1, palette["trace_dim"])
		if cy + 2 < TILE_SIZE and cx + 1 < TILE_SIZE:
			img.set_pixel(cx, cy + 2, palette["trace_dim"])
			img.set_pixel(cx + 2, cy + 2, palette["trace_dim"])

	# Via holes (small bright dots where traces connect between layers)
	for _v in range(rng.randi_range(3, 6)):
		var vx = rng.randi_range(1, TILE_SIZE - 2)
		var vy = rng.randi_range(1, TILE_SIZE - 2)
		img.set_pixel(vx, vy, palette["trace_dim"].lightened(0.15))


## Flowing light streaks on dark surface - data packets in transit
func _draw_data_highway(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 22222

	# Dark road surface texture with subtle directional grain
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 1.0 + y * 0.7 + variant * 2.0) * 0.2 + rng.randf() * 0.08
			# Directional vertical streaking for motion feel
			var motion_n = sin(y * 0.3 + variant * 0.5) * 0.06
			n += motion_n
			if n < -0.12:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.15:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Edge glow lines (lane markers) with inner glow
	for y in range(TILE_SIZE):
		# Left edge - bright core with falloff
		img.set_pixel(2, y, palette["edge_glow"])
		img.set_pixel(3, y, palette["edge_glow"].darkened(0.15))
		if y % 2 == 0:
			img.set_pixel(1, y, palette["edge_glow"].lerp(palette["base"], 0.6))
			img.set_pixel(4, y, palette["edge_glow"].lerp(palette["base"], 0.7))
		# Right edge
		img.set_pixel(TILE_SIZE - 3, y, palette["edge_glow"])
		img.set_pixel(TILE_SIZE - 4, y, palette["edge_glow"].darkened(0.15))
		if y % 2 == 0:
			img.set_pixel(TILE_SIZE - 2, y, palette["edge_glow"].lerp(palette["base"], 0.6))
			img.set_pixel(TILE_SIZE - 5, y, palette["edge_glow"].lerp(palette["base"], 0.7))

	# Center dashed light line with phase-shifted glow based on variant
	var phase_offset = (variant * 3) % 8
	for y in range(TILE_SIZE):
		if ((y + phase_offset) / 4) % 2 == 0:
			img.set_pixel(TILE_SIZE / 2, y, palette["streak_blue"])
			img.set_pixel(TILE_SIZE / 2 + 1, y, palette["streak_blue"].darkened(0.12))
			# Side glow on center line
			if TILE_SIZE / 2 - 1 >= 0:
				var left = img.get_pixel(TILE_SIZE / 2 - 1, y)
				img.set_pixel(TILE_SIZE / 2 - 1, y, left.lerp(palette["streak_blue"], 0.15))
			if TILE_SIZE / 2 + 2 < TILE_SIZE:
				var right = img.get_pixel(TILE_SIZE / 2 + 2, y)
				img.set_pixel(TILE_SIZE / 2 + 2, y, right.lerp(palette["streak_blue"], 0.12))

	# Data packet streaks - multiple lanes, phase-shifted by variant for animation feel
	var lane_xs = [6, 11, 20, 25]  # Fixed lanes
	var num_streaks = rng.randi_range(3, 5)
	for _s in range(num_streaks):
		var lane_idx = rng.randi() % lane_xs.size()
		var sx = lane_xs[lane_idx] + rng.randi_range(-1, 1)
		sx = clampi(sx, 5, TILE_SIZE - 6)
		# Phase offset per variant creates motion illusion across tile variants
		var sy_start = (rng.randi_range(0, TILE_SIZE - 4) + variant * 5) % TILE_SIZE
		var streak_len = rng.randi_range(5, 10)
		var streak_colors = [palette["streak_blue"], palette["streak_cyan"], palette["streak_white"]]
		var streak_col = streak_colors[rng.randi() % 3]
		for i in range(streak_len):
			var py = (sy_start + i) % TILE_SIZE
			if py >= 0 and py < TILE_SIZE:
				# Head is brightest (white-hot), tail fades through color to dark
				var brightness = 1.0 - float(i) / float(streak_len)
				var col: Color
				if i == 0:
					col = palette["streak_white"]  # Bright leading edge
				elif i == 1:
					col = streak_col.lightened(0.2)
				else:
					col = streak_col.lerp(palette["base"], 1.0 - brightness)
				img.set_pixel(sx, py, col)
				# Side glow - wider on head, narrowing toward tail
				var glow_width = 2 if i < 2 else 1
				for gw in range(1, glow_width + 1):
					var glow_blend = 0.6 + float(gw) * 0.15
					if sx - gw >= 0:
						var left = img.get_pixel(sx - gw, py)
						img.set_pixel(sx - gw, py, left.lerp(streak_col, (1.0 - glow_blend) * brightness))
					if sx + gw < TILE_SIZE:
						var right = img.get_pixel(sx + gw, py)
						img.set_pixel(sx + gw, py, right.lerp(streak_col, (1.0 - glow_blend) * brightness))

	# Directional arrow markers on road surface (faint chevrons)
	var arrow_y = 8 + (variant * 7) % 16
	if arrow_y < TILE_SIZE - 4:
		var arrow_cx = TILE_SIZE / 2
		for i in range(3):
			var ay = arrow_y + i
			if ay < TILE_SIZE:
				var half_w = 3 - i
				for dx in range(-half_w, half_w + 1):
					var px = arrow_cx + dx
					if px >= 5 and px < TILE_SIZE - 5:
						var current = img.get_pixel(px, ay)
						img.set_pixel(px, ay, current.lerp(palette["edge_glow"], 0.18))

	# Scan line effect (faint horizontal lines for CRT/digital feel)
	for y in range(TILE_SIZE):
		if y % 3 == 0:
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.05))


## Tall server rack with individually blinking LED rows, vent slots, and status indicators
func _draw_server_tower(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 33333

	# Main server body - brushed metal texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.3 + y * 0.15 + variant * 0.8) * 0.15 + rng.randf() * 0.06
			# Vertical brushed metal grain
			var grain = sin(y * 0.8 + x * 0.05) * 0.04
			n += grain
			if n > 0.1:
				img.set_pixel(x, y, palette["light"])
			elif n < -0.08:
				img.set_pixel(x, y, palette["dark"])

	# Side edges (beveled frame with highlights)
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["deep"])
		img.set_pixel(1, y, palette["dark"])
		img.set_pixel(2, y, palette["mid"])
		img.set_pixel(TILE_SIZE - 3, y, palette["mid"])
		img.set_pixel(TILE_SIZE - 2, y, palette["dark"])
		img.set_pixel(TILE_SIZE - 1, y, palette["deep"])

	# Top edge with highlight
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["light"].lightened(0.05))
		img.set_pixel(x, 1, palette["mid"])
	# Bottom edge shadow
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 1, palette["deep"])
		img.set_pixel(x, TILE_SIZE - 2, palette["dark"])

	# Drive bay dividers (horizontal lines every 4 px) with recessed groove
	for row in range(1, 8):
		var by = row * 4
		if by < TILE_SIZE:
			for x in range(3, TILE_SIZE - 3):
				img.set_pixel(x, by, palette["deep"])
				if by + 1 < TILE_SIZE:
					img.set_pixel(x, by + 1, palette["mid"].lightened(0.05))  # Light edge below groove

	# Vent slots (horizontal slashes in each bay) with airflow depth
	for row in range(0, 7):
		var bay_top = row * 4 + 2
		if bay_top + 1 < TILE_SIZE - 2:
			for x in range(5, 14):
				img.set_pixel(x, bay_top, palette["vent_slot"])
				img.set_pixel(x, bay_top + 1, palette["deep"].lightened(0.02))
				# Subtle airflow glow on alternate vents
				if row % 2 == 0 and x % 3 == 0:
					img.set_pixel(x, bay_top, palette["vent_slot"].lerp(Color(0.12, 0.22, 0.35), 0.3))

	# LED rows - each row has multiple LEDs across, individually colored
	# Primary LED column (right side)
	var led_x_start = TILE_SIZE - 10
	var led_count_per_row = 4  # 4 LEDs per row
	for row in range(0, 7):
		var led_y = row * 4 + 2
		if led_y >= TILE_SIZE - 2:
			continue
		for led_i in range(led_count_per_row):
			var lx = led_x_start + led_i * 2
			if lx >= TILE_SIZE - 2:
				continue
			# Each LED has independent color based on row, position, and variant
			var led_seed = (variant * 7 + row * 13 + led_i * 31) % 100
			var led_col: Color
			var r = rng.randf()
			# Variant changes which LEDs are "on" vs "off" (simulates blinking)
			var is_on = ((led_seed + variant) % 3) != 0
			if not is_on:
				# LED is off - very dim
				led_col = palette["led_green"].darkened(0.75)
				img.set_pixel(lx, led_y, led_col)
				continue
			if r < 0.45:
				led_col = palette["led_green"]
			elif r < 0.75:
				led_col = palette["led_amber"]
			else:
				led_col = palette["led_red"]
			# LED core
			img.set_pixel(lx, led_y, led_col)
			# LED glow halo (subtle bloom around each LED)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var px = lx + dx
					var py = led_y + dy
					if px >= 3 and px < TILE_SIZE - 2 and py >= row * 4 + 1 and py < (row + 1) * 4:
						var current = img.get_pixel(px, py)
						var glow_strength = 0.20 if (abs(dx) + abs(dy) == 1) else 0.10
						img.set_pixel(px, py, current.lerp(led_col, glow_strength))

	# Activity indicator - rapidly flashing LED (different per variant)
	var activity_row = variant % 7
	var activity_y = activity_row * 4 + 3
	var activity_x = TILE_SIZE - 5
	if activity_y < TILE_SIZE - 2 and activity_x < TILE_SIZE - 2:
		var activity_on = variant % 2 == 0
		if activity_on:
			img.set_pixel(activity_x, activity_y, palette["led_green"].lightened(0.25))
			# Strong glow for activity
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var px = activity_x + dx
					var py = activity_y + dy
					if px >= 3 and px < TILE_SIZE - 2 and py >= 0 and py < TILE_SIZE:
						var current = img.get_pixel(px, py)
						img.set_pixel(px, py, current.lerp(palette["led_green"], 0.15))

	# Rack label area with barcode
	for y in range(3, 6):
		for x in range(4, 13):
			if y < TILE_SIZE and x < TILE_SIZE - 3:
				img.set_pixel(x, y, palette["light"].lightened(0.08))
	# Barcode detail
	for x in range(5, 12):
		if rng.randf() < 0.55:
			img.set_pixel(x, 4, palette["deep"])


## Transparent blue projection surface with holographic data, scan lines, and translucent layering
func _draw_hologram_display(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 44444

	# Holographic gradient fill with translucent shimmer (top brighter, fading down)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var rel_y = float(y) / float(TILE_SIZE)
			var rel_x = float(x) / float(TILE_SIZE)
			# Smooth gradient instead of banded
			var shade = palette["light"].lerp(palette["deep"], rel_y)
			# Diagonal shimmer wave for holographic interference pattern
			var shimmer = sin(x * 0.5 + y * 0.3 + variant * 1.8) * 0.15
			var shimmer2 = sin((x - y) * 0.4 + variant * 2.5) * 0.08  # Diagonal rainbow
			shimmer += shimmer2
			if shimmer > 0.10:
				shade = shade.lightened(0.08)
			elif shimmer > 0.04:
				shade = shade.lightened(0.03)
			elif shimmer < -0.10:
				shade = shade.darkened(0.05)
			# Translucent edge fade (left/right edges more transparent-looking)
			if rel_x < 0.15 or rel_x > 0.85:
				shade = shade.lerp(palette["deep"], 0.2)
			img.set_pixel(x, y, shade)

	# Prominent scan lines (every 2 rows) with varying intensity for CRT feel
	for y in range(TILE_SIZE):
		if y % 2 == 0:
			var scanline_intensity = 0.18 + sin(y * 0.3) * 0.05
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lerp(palette["scanline"], scanline_intensity))
		# Alternating rows slightly brighter (interlace simulation)
		elif y % 4 == 1:
			for x in range(TILE_SIZE):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.lightened(0.03))

	# Holographic data fragments (floating text/code snippets in different sizes)
	var num_fragments = rng.randi_range(4, 7)
	for _f in range(num_fragments):
		var fx = rng.randi_range(3, TILE_SIZE - 10)
		var fy = rng.randi_range(4, TILE_SIZE - 5)
		var flen = rng.randi_range(3, 8)
		var frow_height = rng.randi_range(1, 2)  # Some are 2px tall
		for dy in range(frow_height):
			for i in range(flen):
				if fx + i < TILE_SIZE - 1 and fy + dy < TILE_SIZE - 1:
					if rng.randf() < 0.65:
						var frag_col = palette["holo_cyan"] if rng.randf() < 0.6 else palette["holo_blue"]
						# Vary brightness for depth/translucency
						var alpha_sim = rng.randf_range(0.5, 1.0)
						frag_col = frag_col.lerp(img.get_pixel(fx + i, fy + dy), 1.0 - alpha_sim)
						img.set_pixel(fx + i, fy + dy, frag_col)
					else:
						# Gap in text
						pass

	# Holographic border frame with double line and glow
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["holo_blue"])
		img.set_pixel(x, 1, palette["holo_blue"].lerp(palette["base"], 0.4))
		img.set_pixel(x, TILE_SIZE - 1, palette["holo_blue"])
		img.set_pixel(x, TILE_SIZE - 2, palette["holo_blue"].lerp(palette["base"], 0.4))
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["holo_blue"])
		img.set_pixel(1, y, palette["holo_blue"].lerp(palette["base"], 0.4))
		img.set_pixel(TILE_SIZE - 1, y, palette["holo_blue"])
		img.set_pixel(TILE_SIZE - 2, y, palette["holo_blue"].lerp(palette["base"], 0.4))

	# Corner accent brackets (L-shaped, longer)
	for i in range(5):
		# Top-left
		img.set_pixel(i, 2, palette["holo_cyan"])
		img.set_pixel(2, i, palette["holo_cyan"])
		# Top-right
		img.set_pixel(TILE_SIZE - 1 - i, 2, palette["holo_cyan"])
		img.set_pixel(TILE_SIZE - 3, i, palette["holo_cyan"])
		# Bottom-left
		img.set_pixel(i, TILE_SIZE - 3, palette["holo_cyan"])
		img.set_pixel(2, TILE_SIZE - 1 - i, palette["holo_cyan"])
		# Bottom-right
		img.set_pixel(TILE_SIZE - 1 - i, TILE_SIZE - 3, palette["holo_cyan"])
		img.set_pixel(TILE_SIZE - 3, TILE_SIZE - 1 - i, palette["holo_cyan"])

	# Flicker/sparkle points (holographic glints)
	for _i in range(rng.randi_range(3, 7)):
		var px = rng.randi_range(3, TILE_SIZE - 4)
		var py = rng.randi_range(3, TILE_SIZE - 4)
		img.set_pixel(px, py, palette["flicker"])
		# Cross-shaped micro flare
		if px - 1 >= 2:
			var left = img.get_pixel(px - 1, py)
			img.set_pixel(px - 1, py, left.lerp(palette["flicker"], 0.3))
		if px + 1 < TILE_SIZE - 2:
			var right = img.get_pixel(px + 1, py)
			img.set_pixel(px + 1, py, right.lerp(palette["flicker"], 0.3))


## Clinical sleep/compute pod - claustrophobic coffin-like enclosure with monitoring equipment
func _draw_sleep_pod(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 55555

	# Pod casing with sterile clinical texture - very uniform, oppressive
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.4 + y * 0.2 + variant * 1.2) * 0.08 + rng.randf() * 0.04
			if n > 0.06:
				img.set_pixel(x, y, palette["light"])
			elif n < -0.05:
				img.set_pixel(x, y, palette["dark"])

	# Thick chrome frame edges (heavy, prison-like)
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["frame_chrome"])
		img.set_pixel(1, y, palette["frame_chrome"])
		img.set_pixel(2, y, palette["frame_chrome"].darkened(0.08))
		img.set_pixel(3, y, palette["frame_chrome"].darkened(0.18))
		img.set_pixel(TILE_SIZE - 1, y, palette["frame_chrome"])
		img.set_pixel(TILE_SIZE - 2, y, palette["frame_chrome"])
		img.set_pixel(TILE_SIZE - 3, y, palette["frame_chrome"].darkened(0.08))
		img.set_pixel(TILE_SIZE - 4, y, palette["frame_chrome"].darkened(0.18))
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["frame_chrome"])
		img.set_pixel(x, 1, palette["frame_chrome"])
		img.set_pixel(x, 2, palette["frame_chrome"].darkened(0.08))
		img.set_pixel(x, TILE_SIZE - 1, palette["deep"])
		img.set_pixel(x, TILE_SIZE - 2, palette["dark"])
		img.set_pixel(x, TILE_SIZE - 3, palette["dark"].lightened(0.03))

	# Narrow glass viewing window (claustrophobically small)
	var win_top = 5
	var win_bot = 18
	var win_left = 6
	var win_right = TILE_SIZE - 6
	for y in range(win_top, win_bot):
		for x in range(win_left, win_right):
			var rel_y = float(y - win_top) / float(win_bot - win_top)
			var rel_x = float(x - win_left) / float(win_right - win_left)
			var shade = palette["glass_tint"]
			# Darker gradient from edges inward (like looking into a dark pod)
			if rel_y < 0.12:
				shade = palette["glass_tint"].lightened(0.12)
			elif rel_y > 0.88:
				shade = palette["glass_tint"].darkened(0.15)
			# Vignette on sides
			if rel_x < 0.15 or rel_x > 0.85:
				shade = shade.darkened(0.10)
			# Reflection streaks (curved glass feel)
			var refl = sin(x * 0.6 + y * 0.2) * 0.2
			if refl > 0.12:
				shade = shade.lightened(0.06)
			img.set_pixel(x, y, shade)

	# Faint silhouette inside pod (dark shape suggesting occupant)
	if variant % 3 != 2:
		var sil_cx = (win_left + win_right) / 2
		for y in range(win_top + 2, win_bot - 2):
			var sil_width = 2 if y < win_top + 5 else 3
			for dx in range(-sil_width, sil_width + 1):
				var px = sil_cx + dx
				if px > win_left and px < win_right - 1:
					var current = img.get_pixel(px, y)
					img.set_pixel(px, y, current.darkened(0.08))

	# Glass frame border with rivets
	for x in range(win_left - 1, win_right + 1):
		if x >= 0 and x < TILE_SIZE:
			img.set_pixel(x, win_top - 1, palette["frame_chrome"].darkened(0.05))
			img.set_pixel(x, win_bot, palette["frame_chrome"].darkened(0.05))
	for y in range(win_top - 1, win_bot + 1):
		if y >= 0 and y < TILE_SIZE:
			img.set_pixel(win_left - 1, y, palette["frame_chrome"].darkened(0.05))
			img.set_pixel(win_right, y, palette["frame_chrome"].darkened(0.05))
	# Rivets at corners
	img.set_pixel(win_left - 1, win_top - 1, palette["frame_chrome"].lightened(0.08))
	img.set_pixel(win_right, win_top - 1, palette["frame_chrome"].lightened(0.08))
	img.set_pixel(win_left - 1, win_bot, palette["frame_chrome"].lightened(0.08))
	img.set_pixel(win_right, win_bot, palette["frame_chrome"].lightened(0.08))

	# Glare on glass (narrow diagonal streak)
	for i in range(4):
		var gx = win_left + 1 + i
		var gy = win_top + 1 + i
		if gx < win_right - 1 and gy < win_bot - 1:
			img.set_pixel(gx, gy, Color(0.55, 0.72, 0.88, 0.7))
			if gx + 1 < win_right:
				img.set_pixel(gx + 1, gy, Color(0.48, 0.65, 0.82, 0.4))

	# Status light (bottom center) - red for "occupied", green for "available"
	var status_x = TILE_SIZE / 2
	var status_y = TILE_SIZE - 6
	var status_col: Color
	if variant % 3 == 0:
		status_col = palette["status_green"]  # Available
	elif variant % 3 == 1:
		status_col = palette["status_blue"]  # Processing
	else:
		status_col = Color(0.90, 0.20, 0.15)  # Occupied/warning (red)
	img.set_pixel(status_x, status_y, status_col)
	img.set_pixel(status_x + 1, status_y, status_col)
	img.set_pixel(status_x, status_y + 1, status_col.darkened(0.15))
	img.set_pixel(status_x + 1, status_y + 1, status_col.darkened(0.15))
	# Status glow halo
	for dx in range(-2, 4):
		for dy in range(-2, 4):
			var px = status_x + dx
			var py = status_y + dy
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var current = img.get_pixel(px, py)
				if not current.is_equal_approx(status_col) and not current.is_equal_approx(status_col.darkened(0.15)):
					var dist = sqrt(pow(dx - 0.5, 2) + pow(dy - 0.5, 2))
					if dist < 3.0:
						img.set_pixel(px, py, current.lerp(status_col, 0.18 * (1.0 - dist / 3.0)))

	# Control panel strip with EKG-like readout
	var panel_y = win_bot + 2
	if panel_y < TILE_SIZE - 4:
		for x in range(win_left, win_right):
			img.set_pixel(x, panel_y, palette["dark"].lightened(0.03))
			img.set_pixel(x, panel_y + 1, palette["dark"].lightened(0.03))
		# EKG line (heartbeat pattern)
		var ekg_col = palette["status_green"].darkened(0.2)
		for x in range(win_left + 1, win_right - 1):
			var ekg_offset = 0
			var local_x = x - win_left
			if local_x % 8 == 3:
				ekg_offset = -1  # Spike up
			elif local_x % 8 == 4:
				ekg_offset = 1  # Spike down
			var ey = panel_y + ekg_offset
			if ey >= 0 and ey < TILE_SIZE:
				img.set_pixel(x, ey, ekg_col)
		# Tiny indicator LEDs below panel
		for x in range(win_left + 1, win_right - 1, 4):
			if panel_y + 2 < TILE_SIZE - 2:
				img.set_pixel(x, panel_y + 2, palette["status_blue"].darkened(0.5))

	# Latch/lock mechanism on side
	var latch_y = (win_top + win_bot) / 2
	img.set_pixel(3, latch_y, palette["frame_chrome"].lightened(0.12))
	img.set_pixel(3, latch_y + 1, palette["frame_chrome"].lightened(0.08))
	img.set_pixel(TILE_SIZE - 4, latch_y, palette["frame_chrome"].lightened(0.12))
	img.set_pixel(TILE_SIZE - 4, latch_y + 1, palette["frame_chrome"].lightened(0.08))


## Floor grate with parallel slats, blue cooling mist, and condensation
func _draw_cooling_vent(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 66666

	# Floor texture under grate
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.15 + sin(x * 0.8 + y * 0.6) * 0.1
			if n < 0.05:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.18:
				img.set_pixel(x, y, palette["light"])

	# Grate slats (horizontal bars with gaps)
	var slat_h = 2
	var gap_h = 2
	for row in range(0, TILE_SIZE, slat_h + gap_h):
		# Draw slat
		for dy in range(slat_h):
			var y = row + dy
			if y >= TILE_SIZE:
				break
			for x in range(TILE_SIZE):
				var shade = palette["grate_metal"]
				if dy == 0:
					shade = palette["grate_metal"].lightened(0.08)
				else:
					shade = palette["grate_metal"].darkened(0.06)
				# Cross-slat variation
				var grain = sin(x * 0.2 + row * 0.5) * 0.05
				if grain > 0.02:
					shade = shade.lightened(0.03)
				img.set_pixel(x, y, shade)
		# Gap area (dark below)
		for dy in range(gap_h):
			var y = row + slat_h + dy
			if y >= TILE_SIZE:
				break
			for x in range(TILE_SIZE):
				img.set_pixel(x, y, palette["grate_dark"])

	# Cross supports (vertical bars every 8 px)
	for x_pos in range(0, TILE_SIZE, 8):
		for y in range(TILE_SIZE):
			if x_pos < TILE_SIZE:
				img.set_pixel(x_pos, y, palette["grate_metal"].darkened(0.05))
				if x_pos + 1 < TILE_SIZE:
					img.set_pixel(x_pos + 1, y, palette["grate_metal"])

	# Blue cooling mist wisps (semi-transparent effect)
	for _w in range(rng.randi_range(4, 8)):
		var mx = rng.randi_range(2, TILE_SIZE - 3)
		var my = rng.randi_range(2, TILE_SIZE - 3)
		var mist_len = rng.randi_range(2, 5)
		for i in range(mist_len):
			var px = mx + rng.randi_range(-1, 1)
			var py = my - i
			if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
				var current = img.get_pixel(px, py)
				var fade = float(i) / float(mist_len)
				img.set_pixel(px, py, current.lerp(Color(0.30, 0.65, 0.85), 0.25 * (1.0 - fade)))

	# Condensation droplets
	for _d in range(rng.randi_range(2, 5)):
		var dx = rng.randi_range(1, TILE_SIZE - 2)
		var dy = rng.randi_range(0, TILE_SIZE - 1)
		img.set_pixel(dx, dy, Color(0.45, 0.70, 0.88))


## Glowing fiber optic cable channels with multiple colored strands
func _draw_fiber_conduit(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 77777

	# Dark floor texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.9 + y * 0.7 + variant * 1.8) * 0.2 + rng.randf() * 0.08
			if n < -0.12:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.15:
				img.set_pixel(x, y, palette["light"])

	# Metal conduit channel (recessed trough in floor)
	var channel_top = 10
	var channel_bot = 22
	for y in range(channel_top, channel_bot):
		for x in range(TILE_SIZE):
			img.set_pixel(x, y, palette["dark"])
	# Channel edges
	for x in range(TILE_SIZE):
		img.set_pixel(x, channel_top, palette["conduit_metal"])
		img.set_pixel(x, channel_top + 1, palette["conduit_metal"].darkened(0.15))
		img.set_pixel(x, channel_bot - 1, palette["conduit_metal"])
		img.set_pixel(x, channel_bot - 2, palette["conduit_metal"].darkened(0.15))

	# Fiber optic strands (3 colored lines running through channel)
	var fibers = [
		{"y": channel_top + 3, "color": palette["fiber_cyan"]},
		{"y": channel_top + 6, "color": palette["fiber_magenta"]},
		{"y": channel_top + 9, "color": palette["fiber_green"]}
	]
	for fiber in fibers:
		var fy: int = fiber["y"]
		var fc: Color = fiber["color"]
		if fy < channel_bot - 1:
			for x in range(TILE_SIZE):
				img.set_pixel(x, fy, fc)
				# Subtle glow above and below
				if fy - 1 >= channel_top + 2:
					var above = img.get_pixel(x, fy - 1)
					img.set_pixel(x, fy - 1, above.lerp(fc, 0.20))
				if fy + 1 < channel_bot - 2:
					var below = img.get_pixel(x, fy + 1)
					img.set_pixel(x, fy + 1, below.lerp(fc, 0.20))

	# Data pulse bright spots on each fiber
	for fiber in fibers:
		var fy: int = fiber["y"]
		var fc: Color = fiber["color"]
		var pulse_x = rng.randi_range(4, TILE_SIZE - 5)
		if fy < channel_bot - 1:
			for dx in range(-1, 2):
				var px = pulse_x + dx
				if px >= 0 and px < TILE_SIZE:
					img.set_pixel(px, fy, fc.lightened(0.30))

	# Conduit cover bolts
	for bx in range(4, TILE_SIZE - 3, 8):
		img.set_pixel(bx, channel_top - 1, palette["conduit_metal"].lightened(0.1))
		img.set_pixel(bx, channel_bot, palette["conduit_metal"].lightened(0.1))


## Computer terminal with phosphor green CRT glow, scan lines, keyboard, and pedestal
func _draw_terminal_station(img: Image, palette: Dictionary) -> void:
	# Floor base
	img.fill(palette["base"])

	# Pedestal base (bottom portion) with beveled edges
	var ped_left = 6
	var ped_right = TILE_SIZE - 6
	var ped_top = TILE_SIZE - 8
	for y in range(ped_top, TILE_SIZE):
		for x in range(ped_left, ped_right):
			var shade = palette["pedestal"]
			if y == ped_top:
				shade = palette["pedestal"].lightened(0.10)
			elif y == TILE_SIZE - 1:
				shade = palette["pedestal"].darkened(0.12)
			var grain = sin(x * 0.3 + y * 0.5) * 0.04
			if grain > 0.02:
				shade = shade.lightened(0.03)
			img.set_pixel(x, y, shade)

	# Pedestal edge highlights
	for y in range(ped_top, TILE_SIZE):
		img.set_pixel(ped_left, y, palette["pedestal"].lightened(0.08))
		img.set_pixel(ped_right - 1, y, palette["pedestal"].darkened(0.08))

	# Monitor body (upper portion) with thicker bezel
	var mon_left = 3
	var mon_right = TILE_SIZE - 3
	var mon_top = 1
	var mon_bot = ped_top - 2

	# Monitor casing with slight bevel
	for y in range(mon_top, mon_bot):
		for x in range(mon_left, mon_right):
			var shade = palette["dark"]
			# Subtle rounded bezel shading
			var rel_x = float(x - mon_left) / float(mon_right - mon_left)
			if rel_x < 0.1 or rel_x > 0.9:
				shade = palette["dark"].darkened(0.08)
			img.set_pixel(x, y, shade)
	# Casing frame with highlight/shadow
	for x in range(mon_left, mon_right):
		img.set_pixel(x, mon_top, palette["mid"].lightened(0.05))
		img.set_pixel(x, mon_top + 1, palette["mid"])
		img.set_pixel(x, mon_bot - 1, palette["deep"])
	for y in range(mon_top, mon_bot):
		img.set_pixel(mon_left, y, palette["mid"])
		img.set_pixel(mon_left + 1, y, palette["mid"].darkened(0.05))
		img.set_pixel(mon_right - 1, y, palette["deep"])
		img.set_pixel(mon_right - 2, y, palette["deep"].lightened(0.03))

	# Screen (inside monitor casing) with CRT phosphor glow background
	var scr_left = mon_left + 3
	var scr_right = mon_right - 3
	var scr_top = mon_top + 2
	var scr_bot = mon_bot - 2

	# Screen background - darker at edges (CRT curvature simulation)
	for y in range(scr_top, scr_bot):
		for x in range(scr_left, scr_right):
			var rel_x = float(x - scr_left) / float(scr_right - scr_left)
			var rel_y = float(y - scr_top) / float(scr_bot - scr_top)
			# Distance from center (CRT vignette)
			var dist_x = abs(rel_x - 0.5) * 2.0
			var dist_y = abs(rel_y - 0.5) * 2.0
			var vignette = 1.0 - (dist_x * dist_x + dist_y * dist_y) * 0.15
			var shade = palette["screen_bg"].lightened(0.02 * vignette)
			img.set_pixel(x, y, shade)

	# Phosphor green text lines with varying brightness
	var rng = RandomNumberGenerator.new()
	rng.seed = 77777
	for row in range(0, scr_bot - scr_top, 2):
		var text_y = scr_top + row
		if text_y >= scr_bot:
			break
		var text_len = rng.randi_range(4, scr_right - scr_left - 2)
		var text_start = scr_left + 1
		for i in range(text_len):
			var tx = text_start + i
			if tx < scr_right - 1:
				if rng.randf() < 0.65:
					# Phosphor green with slight brightness variation
					var brightness = rng.randf_range(0.0, 0.15)
					img.set_pixel(tx, text_y, palette["screen_green"].lightened(brightness))
				elif rng.randf() < 0.4:
					# Dimmer characters
					img.set_pixel(tx, text_y, palette["screen_green"].darkened(0.25))

	# CRT scan lines (every other row is slightly darker)
	for y in range(scr_top, scr_bot):
		if y % 2 == 0:
			for x in range(scr_left, scr_right):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.06))

	# Cursor blink (bright block with glow)
	var cursor_x = scr_left + 2
	var cursor_y = scr_bot - 2
	if cursor_x + 1 < scr_right and cursor_y >= scr_top:
		img.set_pixel(cursor_x, cursor_y, palette["screen_green"].lightened(0.30))
		img.set_pixel(cursor_x + 1, cursor_y, palette["screen_green"].lightened(0.30))
		# Cursor glow
		for dx in range(-1, 3):
			for dy in range(-1, 2):
				var px = cursor_x + dx
				var py = cursor_y + dy
				if px >= scr_left and px < scr_right and py >= scr_top and py < scr_bot:
					var current = img.get_pixel(px, py)
					if not current.is_equal_approx(palette["screen_green"].lightened(0.30)):
						img.set_pixel(px, py, current.lerp(palette["screen_green"], 0.20))

	# Phosphor CRT glow bleeding onto monitor bezel (green ambient light)
	for y in range(scr_top - 1, scr_bot + 1):
		if y >= mon_top and y < mon_bot:
			# Left bezel glow
			for dx in range(1, 3):
				var px = scr_left - dx
				if px >= mon_left:
					var current = img.get_pixel(px, y)
					img.set_pixel(px, y, current.lerp(palette["screen_green"], 0.10 / float(dx)))
			# Right bezel glow
			for dx in range(1, 3):
				var px = scr_right - 1 + dx
				if px < mon_right:
					var current = img.get_pixel(px, y)
					img.set_pixel(px, y, current.lerp(palette["screen_green"], 0.08 / float(dx)))
	# Top bezel glow
	for x in range(scr_left, scr_right):
		for dy in range(1, 2):
			var py = scr_top - dy
			if py >= mon_top:
				var current = img.get_pixel(x, py)
				img.set_pixel(x, py, current.lerp(palette["screen_green"], 0.06))
	# Bottom bezel glow
	for x in range(scr_left, scr_right):
		for dy in range(1, 2):
			var py = scr_bot - 1 + dy
			if py < mon_bot:
				var current = img.get_pixel(x, py)
				img.set_pixel(x, py, current.lerp(palette["screen_green"], 0.06))

	# Green glow on floor beneath monitor
	for y in range(ped_top, mini(ped_top + 2, TILE_SIZE)):
		for x in range(ped_left, ped_right):
			var current = img.get_pixel(x, y)
			img.set_pixel(x, y, current.lerp(palette["screen_green"], 0.04))

	# Keyboard tray (between monitor and pedestal) with individual key caps
	var kb_y = mon_bot
	for x in range(mon_left + 1, mon_right - 1):
		img.set_pixel(x, kb_y, palette["keyboard"])
		if kb_y + 1 < ped_top:
			img.set_pixel(x, kb_y + 1, palette["keyboard"].darkened(0.08))
	# Individual key caps with highlights
	for x in range(mon_left + 2, mon_right - 2, 2):
		img.set_pixel(x, kb_y, palette["keyboard"].lightened(0.12))
		# Key gaps
		if x + 1 < mon_right - 1:
			img.set_pixel(x + 1, kb_y, palette["keyboard"].darkened(0.06))

	# Power LED on monitor bezel
	img.set_pixel(mon_right - 3, mon_bot - 1, Color(0.15, 0.85, 0.30))


## Tall antenna with metallic pole, dish, and radiating signal rings
func _draw_antenna_array(img: Image, palette: Dictionary) -> void:
	# Dark floor background
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = 88888
	# Floor noise
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.12
			if n < 0.03:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.09:
				img.set_pixel(x, y, palette["mid"])

	# Main antenna pole (center vertical)
	var pole_x = TILE_SIZE / 2
	for y in range(4, TILE_SIZE - 3):
		img.set_pixel(pole_x - 1, y, palette["antenna_dark"])
		img.set_pixel(pole_x, y, palette["antenna_silver"])
		img.set_pixel(pole_x + 1, y, palette["antenna_silver"].lightened(0.08))

	# Base mount (wider at bottom)
	for y in range(TILE_SIZE - 5, TILE_SIZE - 1):
		for dx in range(-3, 4):
			var px = pole_x + dx
			if px >= 0 and px < TILE_SIZE:
				var shade = palette["antenna_dark"]
				if abs(dx) <= 1:
					shade = palette["antenna_silver"]
				img.set_pixel(px, y, shade)
	# Base bottom edge
	for dx in range(-4, 5):
		var px = pole_x + dx
		if px >= 0 and px < TILE_SIZE:
			img.set_pixel(px, TILE_SIZE - 1, palette["antenna_dark"].darkened(0.15))

	# Dish at top (V-shape pointing up)
	for dx in range(-6, 7):
		var dy_off = abs(dx) / 2
		var px = pole_x + dx
		var py = 6 + dy_off
		if px >= 0 and px < TILE_SIZE and py >= 0 and py < TILE_SIZE:
			img.set_pixel(px, py, palette["antenna_silver"])
			if py - 1 >= 0:
				img.set_pixel(px, py - 1, palette["antenna_silver"].lightened(0.1))

	# Antenna tip
	img.set_pixel(pole_x, 2, palette["antenna_silver"].lightened(0.15))
	img.set_pixel(pole_x, 3, palette["antenna_silver"])

	# Signal rings (concentric arcs emanating from tip)
	var ring_cx = pole_x
	var ring_cy = 3
	for r in [6, 10, 14]:
		for angle in range(-70, -20, 4):
			var rad = deg_to_rad(angle)
			var rx = ring_cx + int(cos(rad) * r)
			var ry = ring_cy + int(sin(rad) * r)
			if rx >= 0 and rx < TILE_SIZE and ry >= 0 and ry < TILE_SIZE:
				var fade = float(r) / 14.0
				img.set_pixel(rx, ry, palette["signal_ring"].lerp(palette["base"], fade * 0.4))
		# Mirror on left side
		for angle in range(-160, -110, 4):
			var rad = deg_to_rad(angle)
			var rx = ring_cx + int(cos(rad) * r)
			var ry = ring_cy + int(sin(rad) * r)
			if rx >= 0 and rx < TILE_SIZE and ry >= 0 and ry < TILE_SIZE:
				var fade = float(r) / 14.0
				img.set_pixel(rx, ry, palette["signal_fade"].lerp(palette["base"], fade * 0.4))

	# Blinking light at very top
	img.set_pixel(pole_x, 1, palette["signal_ring"].lightened(0.2))


## Power storage unit with glowing blue core and chrome casing
func _draw_energy_cell(img: Image, palette: Dictionary) -> void:
	img.fill(palette["base"])

	var rng = RandomNumberGenerator.new()
	rng.seed = 99999
	# Floor texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = rng.randf() * 0.1
			if n < 0.03:
				img.set_pixel(x, y, palette["deep"])

	# Chrome casing body (rectangular)
	var case_left = 4
	var case_right = TILE_SIZE - 4
	var case_top = 3
	var case_bot = TILE_SIZE - 3

	for y in range(case_top, case_bot):
		for x in range(case_left, case_right):
			var rel_x = float(x - case_left) / float(case_right - case_left)
			var shade = palette["casing_chrome"]
			# Cylindrical chrome shading
			if rel_x < 0.12:
				shade = palette["dark"]
			elif rel_x < 0.25:
				shade = palette["casing_chrome"].darkened(0.1)
			elif rel_x < 0.45:
				shade = palette["casing_chrome"]
			elif rel_x < 0.55:
				shade = palette["casing_chrome"].lightened(0.08)
			elif rel_x < 0.75:
				shade = palette["casing_chrome"]
			elif rel_x < 0.88:
				shade = palette["casing_chrome"].darkened(0.1)
			else:
				shade = palette["dark"]
			img.set_pixel(x, y, shade)

	# Top and bottom caps
	for x in range(case_left, case_right):
		img.set_pixel(x, case_top, palette["casing_chrome"].lightened(0.1))
		img.set_pixel(x, case_top + 1, palette["casing_chrome"])
		img.set_pixel(x, case_bot - 1, palette["dark"])
		img.set_pixel(x, case_bot - 2, palette["casing_chrome"].darkened(0.08))

	# Glowing core window (center circle)
	var cx = TILE_SIZE / 2
	var cy = TILE_SIZE / 2
	var core_r = 7
	for y in range(case_top + 2, case_bot - 2):
		for x in range(case_left + 2, case_right - 2):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist < core_r:
				var depth = dist / core_r
				var shade: Color
				if depth < 0.2:
					shade = palette["core_white"]
				elif depth < 0.4:
					shade = palette["core_blue"].lightened(0.15)
				elif depth < 0.6:
					shade = palette["core_blue"]
				elif depth < 0.8:
					shade = palette["core_glow"]
				else:
					shade = palette["core_glow"].darkened(0.2)
				img.set_pixel(x, y, shade)
			elif dist < core_r + 1.5:
				img.set_pixel(x, y, palette["casing_chrome"].darkened(0.15))

	# Energy glow halo (extends beyond casing slightly)
	for y in range(maxi(0, case_top - 1), mini(TILE_SIZE, case_bot + 1)):
		for x in range(maxi(0, case_left - 1), mini(TILE_SIZE, case_right + 1)):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist >= core_r and dist < core_r + 4:
				var current = img.get_pixel(x, y)
				var glow_str = 1.0 - (dist - core_r) / 4.0
				img.set_pixel(x, y, current.lerp(palette["core_glow"], glow_str * 0.12))

	# Warning stripes on casing
	for x in range(case_left + 1, case_left + 3):
		for y in range(case_top + 3, case_bot - 3, 4):
			if y < case_bot - 3:
				img.set_pixel(x, y, Color(0.92, 0.72, 0.12))


## Security scanner archway with scan beam and status panels
func _draw_scan_gate(img: Image, palette: Dictionary) -> void:
	img.fill(palette["base"])

	# Floor section
	for y in range(TILE_SIZE - 4, TILE_SIZE):
		for x in range(TILE_SIZE):
			img.set_pixel(x, y, palette["dark"])

	# Left pillar
	var pil_width = 6
	for y in range(0, TILE_SIZE - 3):
		for x in range(0, pil_width):
			var rel_x = float(x) / float(pil_width)
			var shade = palette["pillar_chrome"]
			if rel_x < 0.2:
				shade = palette["pillar_dark"]
			elif rel_x > 0.8:
				shade = palette["pillar_dark"]
			elif rel_x > 0.4 and rel_x < 0.6:
				shade = palette["pillar_chrome"].lightened(0.06)
			img.set_pixel(x, y, shade)

	# Right pillar
	for y in range(0, TILE_SIZE - 3):
		for x in range(TILE_SIZE - pil_width, TILE_SIZE):
			var rel_x = float(x - (TILE_SIZE - pil_width)) / float(pil_width)
			var shade = palette["pillar_chrome"]
			if rel_x < 0.2:
				shade = palette["pillar_dark"]
			elif rel_x > 0.8:
				shade = palette["pillar_dark"]
			elif rel_x > 0.4 and rel_x < 0.6:
				shade = palette["pillar_chrome"].lightened(0.06)
			img.set_pixel(x, y, shade)

	# Top arch (connecting beam)
	for x in range(pil_width, TILE_SIZE - pil_width):
		img.set_pixel(x, 0, palette["pillar_chrome"])
		img.set_pixel(x, 1, palette["pillar_chrome"].darkened(0.08))
		img.set_pixel(x, 2, palette["pillar_dark"])

	# Scan beam (vertical red/green line down the center)
	var beam_x = TILE_SIZE / 2
	for y in range(3, TILE_SIZE - 4):
		img.set_pixel(beam_x, y, palette["scan_red"])
		# Beam glow
		if beam_x - 1 >= pil_width:
			img.set_pixel(beam_x - 1, y, palette["scan_red"].lerp(palette["base"], 0.65))
		if beam_x + 1 < TILE_SIZE - pil_width:
			img.set_pixel(beam_x + 1, y, palette["scan_red"].lerp(palette["base"], 0.65))

	# Status panels on pillars
	# Left panel
	for y in range(8, 14):
		for x in range(1, 4):
			img.set_pixel(x, y, palette["deep"])
	img.set_pixel(2, 10, palette["scan_green"])
	img.set_pixel(2, 11, palette["scan_green"].darkened(0.2))

	# Right panel
	for y in range(8, 14):
		for x in range(TILE_SIZE - 4, TILE_SIZE - 1):
			img.set_pixel(x, y, palette["deep"])
	img.set_pixel(TILE_SIZE - 3, 10, palette["scan_red"])
	img.set_pixel(TILE_SIZE - 3, 11, palette["scan_red"].darkened(0.2))

	# Floor markers (approach lines)
	for x in range(pil_width + 2, TILE_SIZE - pil_width - 2):
		img.set_pixel(x, TILE_SIZE - 2, palette["mid"])


## Digital plants made of light particles - bioluminescent pixel flora
func _draw_pixel_garden(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 10101

	# Dark soil-like digital base texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.7 + y * 0.5 + variant * 1.5) * 0.25 + rng.randf() * 0.15
			if n < -0.15:
				img.set_pixel(x, y, palette["deep"])
			elif n < -0.05:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.2:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.1:
				img.set_pixel(x, y, palette["mid"])

	# Digital pixel plants (vertical stems with branching light particles)
	var plant_colors = [palette["pixel_green"], palette["pixel_cyan"], palette["pixel_white"], palette["pixel_magenta"]]
	var num_plants = rng.randi_range(4, 7)
	for _p in range(num_plants):
		var px = rng.randi_range(3, TILE_SIZE - 4)
		var plant_h = rng.randi_range(6, 14)
		var base_y = rng.randi_range(TILE_SIZE - 4, TILE_SIZE - 2)
		var pc = plant_colors[rng.randi() % plant_colors.size()]

		# Stem (vertical line with slight randomness)
		for h in range(plant_h):
			var sy = base_y - h
			var sx = px + rng.randi_range(-1, 0)
			if sx >= 0 and sx < TILE_SIZE and sy >= 0 and sy < TILE_SIZE:
				var fade = float(h) / float(plant_h)
				img.set_pixel(sx, sy, pc.darkened(0.3 * (1.0 - fade)))

		# Leaf particles (branching dots at intervals)
		for h in range(2, plant_h, 2):
			var sy = base_y - h
			if sy >= 0 and sy < TILE_SIZE:
				# Left leaf
				var lx = px - rng.randi_range(1, 3)
				if lx >= 0 and lx < TILE_SIZE:
					img.set_pixel(lx, sy, pc)
					if lx - 1 >= 0 and rng.randf() < 0.5:
						img.set_pixel(lx - 1, sy, pc.darkened(0.15))
				# Right leaf
				var rx = px + rng.randi_range(1, 3)
				if rx >= 0 and rx < TILE_SIZE:
					img.set_pixel(rx, sy, pc)
					if rx + 1 < TILE_SIZE and rng.randf() < 0.5:
						img.set_pixel(rx + 1, sy, pc.darkened(0.15))

		# Bloom at top (brighter cluster)
		var top_y = base_y - plant_h + 1
		if top_y >= 0 and top_y < TILE_SIZE:
			img.set_pixel(px, top_y, pc.lightened(0.25))
			for dx in range(-1, 2):
				for dy in range(-1, 1):
					var bx = px + dx
					var by = top_y + dy
					if bx >= 0 and bx < TILE_SIZE and by >= 0 and by < TILE_SIZE:
						if not (dx == 0 and dy == 0):
							img.set_pixel(bx, by, pc.lightened(0.10))

	# Ground level glow particles (scattered dots)
	for _g in range(rng.randi_range(5, 10)):
		var gx = rng.randi_range(0, TILE_SIZE - 1)
		var gy = rng.randi_range(TILE_SIZE - 5, TILE_SIZE - 1)
		var gc = plant_colors[rng.randi() % plant_colors.size()]
		img.set_pixel(gx, gy, gc.darkened(0.4))


## Corrupted/flickering tile - visually striking RGB shifts, corruption blocks, static noise
func _draw_glitch_tile(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 12121

	# Base noise with high variance - unstable, buzzing
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 1.5 + y * 1.1 + variant * 3.0) * 0.35 + rng.randf() * 0.30
			if n < -0.25:
				img.set_pixel(x, y, palette["deep"])
			elif n < -0.1:
				img.set_pixel(x, y, palette["dark"])
			elif n > 0.3:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.1:
				img.set_pixel(x, y, palette["mid"])

	# Prominent RGB split bands - wider, more saturated, with channel separation
	var num_bands = rng.randi_range(5, 9)
	for _b in range(num_bands):
		var band_y = rng.randi_range(0, TILE_SIZE - 3)
		var band_h = rng.randi_range(1, 4)
		var shift = rng.randi_range(-6, 6)
		var channel = rng.randi() % 3
		var channel_col: Color
		if channel == 0:
			channel_col = palette["glitch_red"]
		elif channel == 1:
			channel_col = palette["glitch_green"]
		else:
			channel_col = palette["glitch_blue"]

		for dy in range(band_h):
			var y = band_y + dy
			if y >= TILE_SIZE:
				break
			for x in range(TILE_SIZE):
				var sx = (x + shift) % TILE_SIZE
				if sx < 0:
					sx += TILE_SIZE
				# Stronger blend - more visible color shift
				var existing = img.get_pixel(sx, y)
				img.set_pixel(sx, y, channel_col.lerp(existing, 0.25))

	# RGB channel offset effect - shift entire rows by different amounts per channel
	var offset_region_y = rng.randi_range(4, TILE_SIZE - 8)
	var offset_region_h = rng.randi_range(3, 6)
	var r_shift = rng.randi_range(1, 3)
	var b_shift = rng.randi_range(-3, -1)
	for y in range(offset_region_y, mini(offset_region_y + offset_region_h, TILE_SIZE)):
		for x in range(TILE_SIZE):
			var current = img.get_pixel(x, y)
			# Red channel from shifted position
			var rx = (x + r_shift) % TILE_SIZE
			if rx < 0:
				rx += TILE_SIZE
			# Blue channel from opposite shift
			var bx = (x + b_shift) % TILE_SIZE
			if bx < 0:
				bx += TILE_SIZE
			var shifted_r = img.get_pixel(rx, y)
			var shifted_b = img.get_pixel(bx, y)
			var glitched = Color(
				shifted_r.r * 0.5 + current.r * 0.5,
				current.g,
				shifted_b.b * 0.5 + current.b * 0.5
			)
			img.set_pixel(x, y, glitched)

	# Large corruption blocks (rectangles of wrong/impossible colors)
	for _c in range(rng.randi_range(3, 7)):
		var cx = rng.randi_range(0, TILE_SIZE - 6)
		var cy = rng.randi_range(0, TILE_SIZE - 5)
		var cw = rng.randi_range(2, 7)
		var ch = rng.randi_range(1, 4)
		var corrupt_colors = [
			palette["corruption"],
			palette["glitch_red"],
			palette["glitch_green"],
			palette["glitch_blue"],
			Color(0.95, 0.0, 0.85),  # Hot magenta
			Color(0.0, 0.95, 0.95),  # Bright cyan
		]
		var corrupt_col = corrupt_colors[rng.randi() % corrupt_colors.size()]
		for dy in range(ch):
			for dx in range(cw):
				var px = cx + dx
				var py = cy + dy
				if px < TILE_SIZE and py < TILE_SIZE:
					if rng.randf() < 0.75:
						img.set_pixel(px, py, corrupt_col)
					elif rng.randf() < 0.5:
						# Checkerboard corruption pattern
						if (dx + dy) % 2 == 0:
							img.set_pixel(px, py, corrupt_col)

	# Dense static noise lines (TV static bands)
	for _s in range(rng.randi_range(5, 12)):
		var sy = rng.randi_range(0, TILE_SIZE - 1)
		var sx_start = rng.randi_range(0, TILE_SIZE - 4)
		var slen = rng.randi_range(4, TILE_SIZE)
		for i in range(slen):
			var px = sx_start + i
			if px < TILE_SIZE:
				# Pure random RGB static
				var static_col = Color(rng.randf(), rng.randf(), rng.randf())
				img.set_pixel(px, sy, static_col.lerp(palette["base"], 0.15))

	# Scan line tearing (horizontal displacement of entire rows)
	var tear_count = rng.randi_range(1, 3)
	for _t in range(tear_count):
		var tear_y = rng.randi_range(2, TILE_SIZE - 3)
		var tear_shift = rng.randi_range(2, 8)
		# Store row, then write shifted
		var row_pixels: Array[Color] = []
		for x in range(TILE_SIZE):
			row_pixels.append(img.get_pixel(x, tear_y))
		for x in range(TILE_SIZE):
			var src_x = (x + tear_shift) % TILE_SIZE
			img.set_pixel(x, tear_y, row_pixels[src_x])

	# "Memory leak" - faint text-like pattern bleeding through from another layer
	if variant % 2 == 0:
		var leak_y = rng.randi_range(6, TILE_SIZE - 6)
		for row in range(3):
			for x in range(1, TILE_SIZE - 1):
				if rng.randf() < 0.35:
					var ly = leak_y + row * 2
					if ly < TILE_SIZE:
						img.set_pixel(x, ly, Color(0.35, 0.65, 0.25, 0.7))

	# Dead pixel clusters (stuck bright pixels)
	for _d in range(rng.randi_range(2, 5)):
		var dx = rng.randi_range(1, TILE_SIZE - 2)
		var dy = rng.randi_range(1, TILE_SIZE - 2)
		var dead_col = Color(1.0, 1.0, 1.0) if rng.randf() < 0.3 else Color(rng.randf(), 0, rng.randf())
		img.set_pixel(dx, dy, dead_col)


## Smooth wall with neon strip accent, proper glow halos, panel seams, and industrial detail
func _draw_neon_wall(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 13131

	# Smooth wall panel texture with subtle variation
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.3 + y * 0.15 + variant * 0.9) * 0.12 + rng.randf() * 0.05
			if n > 0.08:
				img.set_pixel(x, y, palette["light"])
			elif n < -0.06:
				img.set_pixel(x, y, palette["dark"])

	# Panel seam lines (subtle recessed grid)
	for x in range(TILE_SIZE):
		img.set_pixel(x, 0, palette["seam"])
		img.set_pixel(x, TILE_SIZE - 1, palette["seam"])
	for y in range(TILE_SIZE):
		img.set_pixel(0, y, palette["seam"])
		img.set_pixel(TILE_SIZE - 1, y, palette["seam"])

	# Vertical panel divider with depth
	for y in range(TILE_SIZE):
		img.set_pixel(TILE_SIZE / 2, y, palette["seam"])
		img.set_pixel(TILE_SIZE / 2 + 1, y, palette["seam"].lightened(0.04))  # Light edge

	# Horizontal neon strip accent (the signature feature) - 3px wide for visibility
	var neon_y = TILE_SIZE / 2
	for x in range(1, TILE_SIZE - 1):
		# Bright white-hot center
		img.set_pixel(x, neon_y, palette["neon_cyan"].lightened(0.15))
		# Colored flanks
		img.set_pixel(x, neon_y - 1, palette["neon_cyan"])
		img.set_pixel(x, neon_y + 1, palette["neon_cyan"])

	# Wide neon glow halo (the key enhancement - extends 6px in each direction)
	for x in range(1, TILE_SIZE - 1):
		# Glow above the strip
		for dy in range(1, 7):
			var above_y = neon_y - 1 - dy
			if above_y >= 0:
				var current = img.get_pixel(x, above_y)
				var glow_str = 1.0 - float(dy) / 7.0
				# Exponential falloff for realistic glow
				glow_str = glow_str * glow_str
				img.set_pixel(x, above_y, current.lerp(palette["neon_glow"], glow_str * 0.40))
		# Glow below the strip
		for dy in range(1, 7):
			var below_y = neon_y + 1 + dy
			if below_y < TILE_SIZE:
				var current = img.get_pixel(x, below_y)
				var glow_str = 1.0 - float(dy) / 7.0
				glow_str = glow_str * glow_str
				img.set_pixel(x, below_y, current.lerp(palette["neon_glow"], glow_str * 0.40))

	# Neon strip at seam edges gets extra bright (light bleeds at intersections)
	for seam_x in [0, TILE_SIZE / 2, TILE_SIZE - 1]:
		for dy in range(-2, 3):
			var py = neon_y + dy
			if py >= 0 and py < TILE_SIZE:
				for dx in range(-1, 2):
					var px = seam_x + dx
					if px >= 0 and px < TILE_SIZE:
						var current = img.get_pixel(px, py)
						img.set_pixel(px, py, current.lerp(palette["neon_cyan"], 0.15))

	# Wall mounting points / bolts with chrome
	var bolt_positions = [
		Vector2i(4, 4), Vector2i(TILE_SIZE - 5, 4),
		Vector2i(4, TILE_SIZE - 5), Vector2i(TILE_SIZE - 5, TILE_SIZE - 5)
	]
	for pos in bolt_positions:
		# Bolt head (2x2 with highlight)
		img.set_pixel(pos.x, pos.y, palette["wall_panel"].lightened(0.12))
		if pos.x + 1 < TILE_SIZE:
			img.set_pixel(pos.x + 1, pos.y, palette["wall_panel"].lightened(0.06))
		if pos.y + 1 < TILE_SIZE:
			img.set_pixel(pos.x, pos.y + 1, palette["wall_panel"].darkened(0.04))
		if pos.x + 1 < TILE_SIZE and pos.y + 1 < TILE_SIZE:
			img.set_pixel(pos.x + 1, pos.y + 1, palette["wall_panel"].darkened(0.08))

	# Top trim accent with highlight edge
	for x in range(TILE_SIZE):
		img.set_pixel(x, 1, palette["light"].lightened(0.04))
		img.set_pixel(x, 2, palette["mid"])
		img.set_pixel(x, 3, palette["mid"].darkened(0.03))

	# Bottom base shadow gradient
	for x in range(TILE_SIZE):
		img.set_pixel(x, TILE_SIZE - 2, palette["dark"])
		img.set_pixel(x, TILE_SIZE - 3, palette["dark"].lightened(0.04))


## Interactive floor panel with authentication display and border chrome
func _draw_access_panel(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 14141

	# Floor texture
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var n = sin(x * 0.6 + y * 0.4 + variant * 1.4) * 0.18 + rng.randf() * 0.10
			if n < -0.12:
				img.set_pixel(x, y, palette["deep"])
			elif n > 0.15:
				img.set_pixel(x, y, palette["light"])
			elif n > 0.05:
				img.set_pixel(x, y, palette["mid"])

	# Chrome border frame (rectangular inset)
	var frame_left = 3
	var frame_right = TILE_SIZE - 3
	var frame_top = 3
	var frame_bot = TILE_SIZE - 3

	for x in range(frame_left, frame_right):
		img.set_pixel(x, frame_top, palette["border_chrome"])
		img.set_pixel(x, frame_top + 1, palette["border_chrome"].darkened(0.08))
		img.set_pixel(x, frame_bot - 1, palette["border_chrome"])
		img.set_pixel(x, frame_bot - 2, palette["border_chrome"].darkened(0.08))
	for y in range(frame_top, frame_bot):
		img.set_pixel(frame_left, y, palette["border_chrome"])
		img.set_pixel(frame_left + 1, y, palette["border_chrome"].darkened(0.08))
		img.set_pixel(frame_right - 1, y, palette["border_chrome"])
		img.set_pixel(frame_right - 2, y, palette["border_chrome"].darkened(0.08))

	# Panel surface (inside frame)
	for y in range(frame_top + 2, frame_bot - 2):
		for x in range(frame_left + 2, frame_right - 2):
			img.set_pixel(x, y, palette["panel_blue"].darkened(0.2))

	# Auth display area (small screen in center)
	var disp_left = frame_left + 4
	var disp_right = frame_right - 4
	var disp_top = frame_top + 4
	var disp_bot = frame_bot - 8
	for y in range(disp_top, disp_bot):
		for x in range(disp_left, disp_right):
			img.set_pixel(x, y, palette["panel_blue"])

	# Auth status icon (checkmark or lock pattern)
	var icon_cx = (disp_left + disp_right) / 2
	var icon_cy = (disp_top + disp_bot) / 2
	var auth_col = palette["auth_green"] if variant % 2 == 0 else palette["panel_glow"]

	# Simple diamond icon
	img.set_pixel(icon_cx, icon_cy - 1, auth_col)
	img.set_pixel(icon_cx - 1, icon_cy, auth_col)
	img.set_pixel(icon_cx + 1, icon_cy, auth_col)
	img.set_pixel(icon_cx, icon_cy + 1, auth_col)
	img.set_pixel(icon_cx, icon_cy, auth_col.lightened(0.2))

	# Scan line effect on display
	for y in range(disp_top, disp_bot):
		if y % 2 == 0:
			for x in range(disp_left, disp_right):
				var current = img.get_pixel(x, y)
				img.set_pixel(x, y, current.darkened(0.05))

	# Panel glow border
	for x in range(frame_left + 2, frame_right - 2):
		img.set_pixel(x, frame_top + 2, palette["panel_glow"].lerp(palette["base"], 0.7))
		img.set_pixel(x, frame_bot - 3, palette["panel_glow"].lerp(palette["base"], 0.7))

	# Bottom indicator strip
	var ind_y = frame_bot - 5
	for x in range(frame_left + 3, frame_right - 3, 3):
		if ind_y < frame_bot - 2:
			img.set_pixel(x, ind_y, auth_col.darkened(0.3))


## Near-black floor hinting at the computational abyss below - staring into the void
func _draw_void_floor(img: Image, palette: Dictionary, variant: int) -> void:
	img.fill(palette["base"])
	var rng = RandomNumberGenerator.new()
	rng.seed = variant * 15151

	# Vignette from center - center is darkest (the abyss), edges slightly lighter
	var cx = TILE_SIZE / 2.0
	var cy = TILE_SIZE / 2.0
	var max_dist = sqrt(cx * cx + cy * cy)
	for y in range(TILE_SIZE):
		for x in range(TILE_SIZE):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			var depth_factor = dist / max_dist  # 0 at center, 1 at corners
			# Inverse vignette: center is darkest
			var shade = palette["deep"].lerp(palette["mid"], depth_factor * 0.4)
			# Subtle noise overlay
			var n = rng.randf() * 0.03
			if n > 0.02:
				shade = shade.lightened(0.01)
			img.set_pixel(x, y, shade)

	# Barely-visible perspective grid lines (suggesting infinite depth)
	# Vertical lines with slight convergence toward center
	for gx in range(0, TILE_SIZE, 8):
		for y in range(TILE_SIZE):
			# Grid lines fade toward center (perspective hint)
			var dist_from_center = abs(y - cy) / cy
			var grid_alpha = 0.15 + dist_from_center * 0.15  # Brighter near edges
			if gx < TILE_SIZE:
				var current = img.get_pixel(gx, y)
				img.set_pixel(gx, y, current.lerp(palette["grid_faint"], grid_alpha))
	# Horizontal lines with same perspective fade
	for gy in range(0, TILE_SIZE, 8):
		for x in range(TILE_SIZE):
			var dist_from_center = abs(x - cx) / cx
			var grid_alpha = 0.15 + dist_from_center * 0.15
			if gy < TILE_SIZE:
				var current = img.get_pixel(x, gy)
				img.set_pixel(x, gy, current.lerp(palette["grid_faint"], grid_alpha))

	# Grid intersection dots (slightly brighter at crosspoints)
	for gx in range(0, TILE_SIZE, 8):
		for gy in range(0, TILE_SIZE, 8):
			if gx < TILE_SIZE and gy < TILE_SIZE:
				img.set_pixel(gx, gy, palette["grid_faint"].lightened(0.08))

	# Distant stars/data points deep below (rare, dim, suggesting vast depth)
	for _s in range(rng.randi_range(3, 7)):
		var sx = rng.randi_range(2, TILE_SIZE - 3)
		var sy = rng.randi_range(2, TILE_SIZE - 3)
		var star_col = palette["star"] if rng.randf() < 0.6 else palette["star_bright"]
		img.set_pixel(sx, sy, star_col)
		# Faint cross-hair around brighter stars
		if rng.randf() < 0.3:
			for d in range(1, 2):
				if sx - d >= 0:
					var left = img.get_pixel(sx - d, sy)
					img.set_pixel(sx - d, sy, left.lerp(star_col, 0.15))
				if sx + d < TILE_SIZE:
					var right = img.get_pixel(sx + d, sy)
					img.set_pixel(sx + d, sy, right.lerp(star_col, 0.15))
				if sy - d >= 0:
					var above = img.get_pixel(sx, sy - d)
					img.set_pixel(sx, sy - d, above.lerp(star_col, 0.15))
				if sy + d < TILE_SIZE:
					var below = img.get_pixel(sx, sy + d)
					img.set_pixel(sx, sy + d, below.lerp(star_col, 0.15))

	# Slow pulse wave (something alive below, undulating)
	var pulse_y = (variant * 7) % TILE_SIZE
	for wave in range(3):
		var wy = (pulse_y + wave) % TILE_SIZE
		if wy < TILE_SIZE:
			var wave_str = 0.18 - wave * 0.05
			for x in range(TILE_SIZE):
				# Sinusoidal pulse shape
				var wave_x = sin(float(x) / TILE_SIZE * PI) * wave_str
				var current = img.get_pixel(x, wy)
				img.set_pixel(x, wy, current.lerp(palette["pulse"], wave_x))

	# Edge fade (borders are absolute black - the void has no edges)
	for border in range(2):
		var darkness = 1.0 - float(border) * 0.3
		for x in range(TILE_SIZE):
			var top = img.get_pixel(x, border)
			img.set_pixel(x, border, top.lerp(palette["deep"], darkness * 0.6))
			var bot = img.get_pixel(x, TILE_SIZE - 1 - border)
			img.set_pixel(x, TILE_SIZE - 1 - border, bot.lerp(palette["deep"], darkness * 0.6))
		for y in range(TILE_SIZE):
			var left = img.get_pixel(border, y)
			img.set_pixel(border, y, left.lerp(palette["deep"], darkness * 0.6))
			var right = img.get_pixel(TILE_SIZE - 1 - border, y)
			img.set_pixel(TILE_SIZE - 1 - border, y, right.lerp(palette["deep"], darkness * 0.6))


## Create tileset with all futuristic tiles
func create_tileset() -> TileSet:
	print("Creating futuristic digital tileset...")
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
		# Row 0: Ground surfaces
		TileType.CIRCUIT_FLOOR, TileType.DATA_HIGHWAY, TileType.SERVER_TOWER, TileType.HOLOGRAM_DISPLAY,
		# Row 1: Infrastructure
		TileType.SLEEP_POD, TileType.COOLING_VENT, TileType.FIBER_CONDUIT, TileType.TERMINAL_STATION,
		# Row 2: Structures
		TileType.ANTENNA_ARRAY, TileType.ENERGY_CELL, TileType.SCAN_GATE, TileType.PIXEL_GARDEN,
		# Row 3: Special
		TileType.GLITCH_TILE, TileType.NEON_WALL, TileType.ACCESS_PANEL, TileType.VOID_FLOOR
	]

	# Impassable tile types (need collision)
	var impassable_types = [
		TileType.SERVER_TOWER, TileType.SLEEP_POD, TileType.TERMINAL_STATION,
		TileType.ANTENNA_ARRAY, TileType.ENERGY_CELL, TileType.SCAN_GATE,
		TileType.NEON_WALL
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
	atlas_img.save_png("user://debug_futuristic_atlas.png")
	print("Futuristic atlas saved (size: %dx%d, %d tiles)" % [atlas_img.get_width(), atlas_img.get_height(), tile_order.size()])

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
