extends Control
class_name BattleBackground

## BattleBackground - Procedural battle backgrounds based on terrain type
## Renders stylized retro backgrounds with environmental elements

enum TerrainType {
	PLAINS,   # Default - Blue-gray background
	CAVE,     # Dark purple-brown with stalactites
	FOREST,   # Dark green with tree silhouettes
	VILLAGE,  # Warm brown with building shapes
	BOSS      # Red-tinted dramatic lighting
}

## SNES-quality terrain color palettes (richer, more saturated)
const TERRAIN_PALETTES = {
	TerrainType.PLAINS: {
		"sky_top": Color(0.08, 0.12, 0.32),
		"sky_mid": Color(0.15, 0.22, 0.48),
		"sky_bottom": Color(0.28, 0.38, 0.58),
		"ground": Color(0.22, 0.35, 0.18),
		"ground_dark": Color(0.15, 0.25, 0.12),
		"ground_light": Color(0.32, 0.45, 0.25),
		"accent": Color(0.38, 0.50, 0.32),
		"horizon": Color(0.45, 0.55, 0.65)
	},
	TerrainType.CAVE: {
		"sky_top": Color(0.06, 0.04, 0.10),
		"sky_mid": Color(0.10, 0.07, 0.16),
		"sky_bottom": Color(0.15, 0.10, 0.22),
		"ground": Color(0.12, 0.10, 0.16),
		"ground_dark": Color(0.08, 0.06, 0.10),
		"ground_light": Color(0.18, 0.15, 0.24),
		"accent": Color(0.28, 0.20, 0.35),
		"horizon": Color(0.20, 0.15, 0.28),
		"crystal": Color(0.40, 0.30, 0.65)
	},
	TerrainType.FOREST: {
		"sky_top": Color(0.02, 0.08, 0.04),
		"sky_mid": Color(0.04, 0.14, 0.06),
		"sky_bottom": Color(0.08, 0.22, 0.10),
		"ground": Color(0.10, 0.18, 0.08),
		"ground_dark": Color(0.06, 0.12, 0.04),
		"ground_light": Color(0.15, 0.25, 0.12),
		"accent": Color(0.18, 0.30, 0.15),
		"horizon": Color(0.12, 0.28, 0.14),
		"trunk": Color(0.28, 0.18, 0.10)
	},
	TerrainType.VILLAGE: {
		"sky_top": Color(0.18, 0.10, 0.06),
		"sky_mid": Color(0.28, 0.18, 0.10),
		"sky_bottom": Color(0.38, 0.28, 0.18),
		"ground": Color(0.32, 0.25, 0.18),
		"ground_dark": Color(0.22, 0.18, 0.12),
		"ground_light": Color(0.42, 0.35, 0.25),
		"accent": Color(0.42, 0.32, 0.22),
		"horizon": Color(0.50, 0.38, 0.28)
	},
	TerrainType.BOSS: {
		"sky_top": Color(0.18, 0.02, 0.04),
		"sky_mid": Color(0.30, 0.06, 0.08),
		"sky_bottom": Color(0.42, 0.10, 0.14),
		"ground": Color(0.22, 0.06, 0.08),
		"ground_dark": Color(0.14, 0.02, 0.04),
		"ground_light": Color(0.30, 0.10, 0.12),
		"accent": Color(0.48, 0.14, 0.18),
		"horizon": Color(0.55, 0.15, 0.20),
		"glow": Color(0.80, 0.25, 0.15)
	}
}

var current_terrain: TerrainType = TerrainType.PLAINS
var _background_elements: Array[Node] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -100  # Render behind everything


func set_terrain(terrain: TerrainType) -> void:
	"""Set the terrain type and redraw background"""
	current_terrain = terrain
	_draw_background()


func set_terrain_from_string(terrain_name: String) -> void:
	"""Set terrain from string name (for easy integration)"""
	match terrain_name.to_lower():
		"plains", "overworld":
			set_terrain(TerrainType.PLAINS)
		"cave", "dungeon":
			set_terrain(TerrainType.CAVE)
		"forest", "woods":
			set_terrain(TerrainType.FOREST)
		"village", "town":
			set_terrain(TerrainType.VILLAGE)
		"boss":
			set_terrain(TerrainType.BOSS)
		_:
			set_terrain(TerrainType.PLAINS)


func _draw_background() -> void:
	"""Draw the background based on current terrain"""
	# Clear existing elements
	for element in _background_elements:
		if is_instance_valid(element):
			element.queue_free()
	_background_elements.clear()

	# Clear any existing children
	for child in get_children():
		child.queue_free()

	var viewport_size = get_viewport_rect().size
	var palette = TERRAIN_PALETTES.get(current_terrain, TERRAIN_PALETTES[TerrainType.PLAINS])

	# Draw gradient background
	_draw_gradient(viewport_size, palette)

	# Draw terrain-specific elements
	match current_terrain:
		TerrainType.PLAINS:
			_draw_plains_elements(viewport_size, palette)
		TerrainType.CAVE:
			_draw_cave_elements(viewport_size, palette)
		TerrainType.FOREST:
			_draw_forest_elements(viewport_size, palette)
		TerrainType.VILLAGE:
			_draw_village_elements(viewport_size, palette)
		TerrainType.BOSS:
			_draw_boss_elements(viewport_size, palette)


func _draw_gradient(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw SNES-quality gradient background with smooth color banding"""
	# Use more steps for smoother gradient (SNES typically had 16-32 color bands)
	var gradient_steps = 24
	var sky_height = viewport_size.y * 0.65
	var step_height = sky_height / gradient_steps

	var sky_mid = palette.get("sky_mid", palette["sky_top"].lerp(palette["sky_bottom"], 0.5))

	for i in range(gradient_steps):
		var rect = ColorRect.new()
		var t = float(i) / (gradient_steps - 1)
		# Two-phase gradient: top -> mid -> bottom for more color range
		var color: Color
		if t < 0.5:
			color = palette["sky_top"].lerp(sky_mid, t * 2.0)
		else:
			color = sky_mid.lerp(palette["sky_bottom"], (t - 0.5) * 2.0)
		rect.color = color
		rect.position = Vector2(0, i * step_height)
		rect.size = Vector2(viewport_size.x, step_height + 1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)

	# Horizon glow line (SNES-style bright band at horizon)
	var horizon_color = palette.get("horizon", palette["sky_bottom"].lightened(0.2))
	var horizon = ColorRect.new()
	horizon.color = horizon_color
	horizon.position = Vector2(0, sky_height - 4)
	horizon.size = Vector2(viewport_size.x, 6)
	horizon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(horizon)
	# Slightly dimmer horizon edges
	var horizon_dim = ColorRect.new()
	horizon_dim.color = horizon_color.darkened(0.15)
	horizon_dim.position = Vector2(0, sky_height + 2)
	horizon_dim.size = Vector2(viewport_size.x, 3)
	horizon_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(horizon_dim)

	# Ground with multi-tone banding (like FF6 battle backgrounds)
	var ground_dark = palette.get("ground_dark", palette["ground"].darkened(0.2))
	var ground_light = palette.get("ground_light", palette["ground"].lightened(0.15))
	var ground_steps = 8
	var ground_height = viewport_size.y * 0.35
	var ground_step_h = ground_height / ground_steps

	for i in range(ground_steps):
		var rect = ColorRect.new()
		var t = float(i) / (ground_steps - 1)
		# Ground gets darker toward bottom, with slight color shift
		rect.color = ground_light.lerp(ground_dark, t)
		rect.position = Vector2(0, sky_height + i * ground_step_h)
		rect.size = Vector2(viewport_size.x, ground_step_h + 1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)


func _draw_plains_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw plains background elements - rolling hills"""
	# Distant hills
	for i in range(3):
		var hill = _create_hill(
			Vector2(viewport_size.x * (0.2 + i * 0.3), viewport_size.y * 0.6),
			Vector2(200, 80),
			palette["accent"].darkened(0.2 + i * 0.1)
		)
		add_child(hill)
		_background_elements.append(hill)

	# Scattered grass tufts
	for i in range(8):
		var grass = _create_grass_tuft(
			Vector2(randf_range(50, viewport_size.x - 50), viewport_size.y * randf_range(0.75, 0.9)),
			palette["accent"]
		)
		add_child(grass)
		_background_elements.append(grass)


func _draw_cave_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw cave background elements - stalactites and rock formations"""
	# Stalactites from ceiling
	for i in range(6):
		var stalactite = _create_stalactite(
			Vector2(viewport_size.x * (0.1 + i * 0.15), 0),
			randf_range(60, 120),
			palette["accent"]
		)
		add_child(stalactite)
		_background_elements.append(stalactite)

	# Stalagmites from ground
	for i in range(5):
		var stalagmite = _create_stalagmite(
			Vector2(viewport_size.x * (0.05 + i * 0.2), viewport_size.y),
			randf_range(40, 80),
			palette["accent"]
		)
		add_child(stalagmite)
		_background_elements.append(stalagmite)

	# Rock formations
	for i in range(3):
		var rock = _create_rock(
			Vector2(randf_range(50, viewport_size.x - 50), viewport_size.y * 0.85),
			Vector2(40, 30),
			palette["ground"].lightened(0.1)
		)
		add_child(rock)
		_background_elements.append(rock)


func _draw_forest_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw forest background elements - tree silhouettes"""
	# Background trees (darker, smaller)
	for i in range(8):
		var tree = _create_tree_silhouette(
			Vector2(viewport_size.x * (i * 0.12 + randf_range(-0.02, 0.02)), viewport_size.y * 0.5),
			randf_range(80, 120),
			palette["sky_bottom"].darkened(0.3)
		)
		add_child(tree)
		_background_elements.append(tree)

	# Foreground trees (larger, slightly lighter)
	for i in range(5):
		var tree = _create_tree_silhouette(
			Vector2(viewport_size.x * (i * 0.22 + randf_range(-0.05, 0.05)), viewport_size.y * 0.6),
			randf_range(120, 160),
			palette["accent"].darkened(0.2)
		)
		add_child(tree)
		_background_elements.append(tree)


func _draw_village_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw village background elements - building silhouettes"""
	# Building silhouettes
	var building_positions = [0.1, 0.3, 0.5, 0.7, 0.85]
	for i in range(building_positions.size()):
		var pos_x = viewport_size.x * building_positions[i]
		var building = _create_building(
			Vector2(pos_x, viewport_size.y * 0.55),
			Vector2(randf_range(60, 100), randf_range(80, 140)),
			palette["accent"].darkened(0.1 + randf_range(0, 0.1))
		)
		add_child(building)
		_background_elements.append(building)

	# Lamp posts
	for i in range(2):
		var lamp = _create_lamp_post(
			Vector2(viewport_size.x * (0.25 + i * 0.5), viewport_size.y * 0.75),
			palette["accent"]
		)
		add_child(lamp)
		_background_elements.append(lamp)


func _draw_boss_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw boss arena background - dramatic lighting"""
	# Ominous pillars
	for i in range(4):
		var pillar = _create_pillar(
			Vector2(viewport_size.x * (0.1 + i * 0.28), viewport_size.y * 0.3),
			Vector2(30, 200),
			palette["accent"]
		)
		add_child(pillar)
		_background_elements.append(pillar)

	# Energy particles/effects
	for i in range(10):
		var particle = _create_energy_particle(
			Vector2(randf_range(50, viewport_size.x - 50), randf_range(100, viewport_size.y - 100)),
			palette["sky_bottom"].lightened(0.3)
		)
		add_child(particle)
		_background_elements.append(particle)


## Element creation helpers - SNES-quality pixel-art rendered elements


func _create_hill(pos: Vector2, hill_size: Vector2, color: Color) -> TextureRect:
	"""Create a rounded hill with gradient shading (pixel-art rendered)"""
	var w = int(hill_size.x)
	var h = int(hill_size.y)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0
	var light = color.lightened(0.15)
	var dark = color.darkened(0.2)
	var mid = color.darkened(0.08)

	# Draw elliptical hill with multi-zone shading
	for y in range(h):
		var t = float(y) / h  # 0 at top, 1 at bottom
		# Width at this scanline (parabolic arch)
		var half_width = cx * (1.0 - pow(1.0 - t, 2.0)) if t > 0.1 else cx * t * 5.0
		for x in range(w):
			var dx = abs(x - cx)
			if dx < half_width:
				var rel_x = dx / max(half_width, 1.0)
				var c = color
				# Top is lighter (sky reflection)
				if t < 0.25:
					c = light
				elif t < 0.5:
					c = color
				else:
					c = mid
				# Left side highlight, right side shadow
				if rel_x > 0.7:
					c = dark
				elif rel_x < 0.3 and t < 0.5:
					c = light
				img.set_pixel(x, y, c)
			# Soft edge fade
			elif dx < half_width + 2:
				img.set_pixel(x, y, Color(dark.r, dark.g, dark.b, 0.3))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(hill_size.x / 2, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_grass_tuft(pos: Vector2, color: Color) -> TextureRect:
	"""Create a pixel-art grass tuft with multiple blades"""
	var w = 12
	var h = 16
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var light = color.lightened(0.25)
	var dark = color.darkened(0.15)

	# Draw 3-5 grass blades fanning out
	var blade_data = [
		[3, 15, -1],   # Left-leaning blade
		[5, 14, 0],    # Center blade
		[7, 15, 1],    # Right-leaning blade
		[4, 13, 0],    # Short center
		[8, 14, 1],    # Far right
	]
	for blade in blade_data:
		var bx = blade[0]
		var by = blade[1]
		var lean = blade[2]
		var blade_height = randi_range(5, 9)
		for i in range(blade_height):
			var px = bx + int(lean * i * 0.3)
			var py = by - i
			if px >= 0 and px < w and py >= 0 and py < h:
				var c = dark if i < 2 else (color if i < blade_height - 1 else light)
				img.set_pixel(px, py, c)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_stalactite(pos: Vector2, height: float, color: Color) -> TextureRect:
	"""Create a pixel-art stalactite with shading and drip detail"""
	var w = int(height * 0.4)
	var h = int(height)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0
	var light = color.lightened(0.15)
	var dark = color.darkened(0.25)
	var outline = color.darkened(0.4)

	for y in range(h):
		var t = float(y) / h  # 0=top (wide), 1=bottom (tip)
		var half_width = (w / 2.0) * (1.0 - t * 0.92)
		for x in range(w):
			var dx = abs(x - cx)
			if dx <= half_width:
				var rel_x = dx / max(half_width, 1.0)
				var c = color
				# Left highlight, right shadow
				if x < cx - half_width * 0.3:
					c = light
				elif x > cx + half_width * 0.3:
					c = dark
				# Tip gets darker
				if t > 0.85:
					c = c.darkened(0.1)
				# Texture noise
				if sin(x * 2.0 + y * 1.5) > 0.5:
					c = c.lightened(0.05)
				img.set_pixel(x, y, c)
			elif dx <= half_width + 1:
				img.set_pixel(x, y, outline)

	# Water drip at tip
	if h > 4:
		var tip_x = int(cx)
		img.set_pixel(tip_x, h - 1, light)
		img.set_pixel(tip_x, h - 2, color.lightened(0.2))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_stalagmite(pos: Vector2, height: float, color: Color) -> TextureRect:
	"""Create a pixel-art stalagmite with mineral deposits"""
	var w = int(height * 0.4)
	var h = int(height)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0
	var light = color.lightened(0.15)
	var dark = color.darkened(0.25)
	var outline = color.darkened(0.4)

	for y in range(h):
		var t = float(y) / h  # 0=top (tip), 1=bottom (wide)
		var half_width = (w / 2.0) * t
		for x in range(w):
			var dx = abs(x - cx)
			if dx <= half_width:
				var rel_x = dx / max(half_width, 1.0)
				var c = color
				# Left highlight, right shadow (light from upper-left)
				if x < cx - half_width * 0.3:
					c = light
				elif x > cx + half_width * 0.3:
					c = dark
				# Top tip is lighter (mineral deposits)
				if t < 0.15:
					c = light
				# Texture noise
				if sin(x * 1.8 + y * 2.2) > 0.4:
					c = c.darkened(0.05)
				img.set_pixel(x, y, c)
			elif dx <= half_width + 1 and half_width > 1:
				img.set_pixel(x, y, outline)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, height)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_rock(pos: Vector2, rock_size: Vector2, color: Color) -> TextureRect:
	"""Create a pixel-art rock with shading and texture"""
	var w = int(rock_size.x)
	var h = int(rock_size.y)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0
	var light = color.lightened(0.18)
	var dark = color.darkened(0.22)
	var outline = color.darkened(0.4)

	# Irregular rock shape (bumpy ellipse)
	for y in range(h):
		var t = float(y) / h
		# Base ellipse width with perturbation for irregular edges
		var bump = sin(y * 0.8) * 2.0 + sin(y * 1.5) * 1.5
		var half_width = (w / 2.0) * (1.0 - pow(t * 2.0 - 1.0, 2.0)) * 0.95 + bump
		for x in range(w):
			var dx = abs(x - cx)
			if dx <= half_width:
				var c = color
				# Multi-zone rock shading (light from upper-left)
				var norm_y = (t - 0.5) * 2.0
				var norm_x = (x - cx) / max(half_width, 1.0)
				if norm_y < -0.3 and norm_x < 0.2:
					c = light
				elif norm_y > 0.3 or norm_x > 0.5:
					c = dark
				# Rock texture noise
				var noise = sin(x * 2.5 + y * 1.8) * cos(x * 1.2 - y * 0.9) * 0.5
				if noise > 0.25:
					c = c.lightened(0.06)
				elif noise < -0.25:
					c = c.darkened(0.06)
				img.set_pixel(x, y, c)
			elif dx <= half_width + 1 and half_width > 2:
				img.set_pixel(x, y, outline)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(rock_size.x / 2, rock_size.y)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_tree_silhouette(pos: Vector2, height: float, color: Color) -> TextureRect:
	"""Create a pixel-art tree silhouette with layered canopy and trunk"""
	var w = int(height * 0.7)
	var h = int(height)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0
	var trunk_color = color.darkened(0.25)
	var trunk_light = color.darkened(0.15)
	var canopy_light = color.lightened(0.08)
	var canopy_dark = color.darkened(0.15)
	var outline = color.darkened(0.35)

	# Trunk (centered, tapers upward)
	var trunk_bottom = h - 1
	var trunk_top = int(h * 0.55)
	var trunk_half_w = int(height * 0.04) + 1
	for y in range(trunk_top, trunk_bottom + 1):
		var taper = float(y - trunk_top) / float(trunk_bottom - trunk_top)
		var tw = int(trunk_half_w * (0.7 + taper * 0.3))
		for dx in range(-tw - 1, tw + 2):
			var x = int(cx) + dx
			if x >= 0 and x < w:
				if abs(dx) == tw + 1:
					img.set_pixel(x, y, outline)
				elif dx < 0:
					img.set_pixel(x, y, trunk_light)
				else:
					img.set_pixel(x, y, trunk_color)

	# Canopy - 3 overlapping ellipses for layered look
	var canopy_layers = [
		[cx, h * 0.25, w * 0.45, h * 0.28],  # Top (smallest)
		[cx - 2, h * 0.38, w * 0.42, h * 0.25],  # Middle-left
		[cx + 2, h * 0.42, w * 0.40, h * 0.22],  # Middle-right
	]
	for layer in canopy_layers:
		var lcx = layer[0]
		var lcy = layer[1]
		var lrx = layer[2]
		var lry = layer[3]
		for y in range(int(lcy - lry), int(lcy + lry)):
			for x in range(int(lcx - lrx), int(lcx + lrx)):
				if x < 0 or x >= w or y < 0 or y >= h:
					continue
				var dx = (x - lcx) / max(lrx, 1.0)
				var dy = (y - lcy) / max(lry, 1.0)
				var dist = sqrt(dx * dx + dy * dy)
				if dist < 0.85:
					# Canopy shading: top lighter, bottom darker
					var c = color
					if dy < -0.3:
						c = canopy_light
					elif dy > 0.3:
						c = canopy_dark
					# Leaf cluster texture
					var leaf = sin(x * 1.8 + y * 2.2) * 0.5
					if leaf > 0.3:
						c = c.lightened(0.04)
					elif leaf < -0.3:
						c = c.darkened(0.04)
					img.set_pixel(x, y, c)
				elif dist < 1.0:
					img.set_pixel(x, y, outline)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_building(pos: Vector2, bld_size: Vector2, color: Color) -> TextureRect:
	"""Create a pixel-art building silhouette with roof, windows, and door"""
	var w = int(bld_size.x * 1.3)  # Extra for roof overhang
	var h = int(bld_size.y + bld_size.y * 0.3)  # Extra for roof
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var light = color.lightened(0.12)
	var dark = color.darkened(0.2)
	var outline = color.darkened(0.4)
	var roof_color = color.darkened(0.25)
	var roof_light = color.darkened(0.1)
	var window_color = Color(0.9, 0.8, 0.4, 0.8)
	var window_bright = Color(1.0, 0.95, 0.7, 0.9)
	var door_color = color.darkened(0.35)

	var body_x = int((w - bld_size.x) / 2)
	var roof_h = int(bld_size.y * 0.3)
	var body_top = roof_h
	var body_bottom = h - 1

	# Roof (triangular / pitched)
	var roof_cx = w / 2.0
	for y in range(roof_h):
		var t = float(y) / roof_h
		var half_width = (w / 2.0) * t
		for x in range(w):
			var dx = abs(x - roof_cx)
			if dx <= half_width:
				var c = roof_color
				if x < roof_cx:
					c = roof_light  # Left side lit
				if y == 0 or abs(dx - half_width) < 1:
					c = outline
				img.set_pixel(x, y, c)

	# Building body with shading
	for y in range(body_top, body_bottom + 1):
		for x in range(body_x, body_x + int(bld_size.x)):
			if x >= 0 and x < w:
				var c = color
				var rel_x = float(x - body_x) / bld_size.x
				# Left wall lighter, right wall darker
				if rel_x < 0.15:
					c = light
				elif rel_x > 0.85:
					c = dark
				# Wall texture (subtle brick lines)
				if (y - body_top) % 8 == 0:
					c = c.darkened(0.05)
				# Outline
				if x == body_x or x == body_x + int(bld_size.x) - 1:
					c = outline
				if y == body_bottom:
					c = outline
				img.set_pixel(x, y, c)

	# Windows (2x2 grid with frame and glow)
	var win_w = 8
	var win_h = 10
	for row in range(2):
		for col in range(2):
			var wx = body_x + int(bld_size.x * 0.2) + col * int(bld_size.x * 0.45)
			var wy = body_top + int(bld_size.y * 0.15) + row * int(bld_size.y * 0.35)
			for dy in range(win_h):
				for dx in range(win_w):
					var px = wx + dx
					var py = wy + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						if dx == 0 or dx == win_w - 1 or dy == 0 or dy == win_h - 1:
							img.set_pixel(px, py, outline)  # Frame
						elif dx == win_w / 2 or dy == win_h / 2:
							img.set_pixel(px, py, outline)  # Cross-bar
						else:
							# Window glow (brighter near center)
							var wdist = abs(dx - win_w / 2.0) + abs(dy - win_h / 2.0)
							var c = window_color if wdist > 3 else window_bright
							img.set_pixel(px, py, c)

	# Door at bottom center
	var door_w = int(bld_size.x * 0.2)
	var door_h = int(bld_size.y * 0.25)
	var door_x = body_x + int(bld_size.x / 2) - door_w / 2
	var door_y = body_bottom - door_h
	for dy in range(door_h):
		for dx in range(door_w):
			var px = door_x + dx
			var py = door_y + dy
			if px >= 0 and px < w and py >= 0 and py < h:
				if dx == 0 or dx == door_w - 1 or dy == 0:
					img.set_pixel(px, py, outline)
				else:
					img.set_pixel(px, py, door_color)
	# Door knob
	var knob_x = door_x + door_w - 3
	var knob_y = door_y + door_h / 2
	if knob_x >= 0 and knob_x < w and knob_y >= 0 and knob_y < h:
		img.set_pixel(knob_x, knob_y, Color(0.7, 0.65, 0.4))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_lamp_post(pos: Vector2, color: Color) -> TextureRect:
	"""Create a pixel-art lamp post with warm glow"""
	var w = 20
	var h = 56
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2
	var post_color = color.darkened(0.3)
	var post_light = color.darkened(0.15)
	var outline = color.darkened(0.5)
	var lamp_warm = Color(1.0, 0.9, 0.55, 0.95)
	var lamp_glow = Color(1.0, 0.85, 0.4, 0.5)

	# Post shaft (thin, tapered)
	for y in range(12, h):
		var half_w = 2 if y < h - 6 else 3  # Wider base
		for dx in range(-half_w, half_w + 1):
			var x = cx + dx
			if x >= 0 and x < w:
				if abs(dx) == half_w:
					img.set_pixel(x, y, outline)
				elif dx < 0:
					img.set_pixel(x, y, post_light)
				else:
					img.set_pixel(x, y, post_color)

	# Lamp housing (hexagonal shape at top)
	for y in range(4, 14):
		var t = abs(y - 9.0) / 5.0
		var half_w = int(5 * (1.0 - t * 0.6))
		for dx in range(-half_w, half_w + 1):
			var x = cx + dx
			if x >= 0 and x < w:
				if abs(dx) == half_w or y == 4 or y == 13:
					img.set_pixel(x, y, outline)
				else:
					# Warm lamp light gradient
					var dist = abs(dx) / max(half_w, 1.0)
					var c = lamp_warm if dist < 0.5 else Color(0.9, 0.8, 0.5, 0.8)
					img.set_pixel(x, y, c)

	# Glow effect around lamp (semi-transparent)
	for y in range(0, 18):
		for x in range(0, w):
			var dx = abs(x - cx)
			var dy = abs(y - 9)
			var dist = sqrt(dx * dx + dy * dy)
			if dist > 5 and dist < 10:
				var alpha = (1.0 - (dist - 5) / 5.0) * 0.15
				if img.get_pixel(x, y).a < 0.01:  # Only on transparent pixels
					img.set_pixel(x, y, Color(lamp_glow.r, lamp_glow.g, lamp_glow.b, alpha))

	# Base plate
	for dx in range(-4, 5):
		var x = cx + dx
		if x >= 0 and x < w:
			img.set_pixel(x, h - 1, outline)
			img.set_pixel(x, h - 2, post_color)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_pillar(pos: Vector2, pillar_size: Vector2, color: Color) -> TextureRect:
	"""Create a pixel-art dramatic pillar with shading and runes"""
	var w = int(pillar_size.x) + 10  # Extra for capital/base
	var h = int(pillar_size.y)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0
	var light = color.lightened(0.15)
	var dark = color.darkened(0.25)
	var outline = color.darkened(0.4)
	var rune_color = color.lightened(0.35)

	# Pillar shaft with cylindrical shading
	var shaft_half_w = int(pillar_size.x / 2)
	for y in range(int(h * 0.08), int(h * 0.92)):
		for dx in range(-shaft_half_w, shaft_half_w + 1):
			var x = int(cx) + dx
			if x >= 0 and x < w:
				var rel = float(dx + shaft_half_w) / float(shaft_half_w * 2)
				var c = color
				# Cylindrical shading (highlight left-center, shadow right)
				if rel < 0.2:
					c = dark
				elif rel < 0.4:
					c = color
				elif rel < 0.6:
					c = light  # Center highlight
				elif rel < 0.8:
					c = color
				else:
					c = dark
				# Fluting texture (vertical grooves)
				if int(dx) % 4 == 0 and abs(dx) > 2:
					c = c.darkened(0.08)
				img.set_pixel(x, y, c)
		# Outline
		if int(cx) - shaft_half_w - 1 >= 0:
			img.set_pixel(int(cx) - shaft_half_w - 1, y, outline)
		if int(cx) + shaft_half_w + 1 < w:
			img.set_pixel(int(cx) + shaft_half_w + 1, y, outline)

	# Capital (wider top)
	var cap_half_w = shaft_half_w + 3
	for y in range(0, int(h * 0.08)):
		for dx in range(-cap_half_w, cap_half_w + 1):
			var x = int(cx) + dx
			if x >= 0 and x < w:
				if abs(dx) == cap_half_w or y == 0:
					img.set_pixel(x, y, outline)
				elif dx < 0:
					img.set_pixel(x, y, light)
				else:
					img.set_pixel(x, y, color)

	# Base (wider bottom)
	for y in range(int(h * 0.92), h):
		for dx in range(-cap_half_w, cap_half_w + 1):
			var x = int(cx) + dx
			if x >= 0 and x < w:
				if abs(dx) == cap_half_w or y == h - 1:
					img.set_pixel(x, y, outline)
				else:
					img.set_pixel(x, y, dark)

	# Rune markings (glowing symbols scattered along shaft)
	for i in range(3):
		var ry = int(h * 0.2 + i * h * 0.25)
		for dx in range(-2, 3):
			var x = int(cx) + dx
			if x >= 0 and x < w and ry >= 0 and ry < h:
				if abs(dx) < 2:
					img.set_pixel(x, ry, rune_color)
				img.set_pixel(x, ry + 1, rune_color.darkened(0.15))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_energy_particle(pos: Vector2, color: Color) -> TextureRect:
	"""Create a pixel-art energy particle with glow"""
	var particle_size = randi_range(6, 12)
	var img = Image.create(particle_size, particle_size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = particle_size / 2.0
	var cy = particle_size / 2.0
	var bright = color.lightened(0.4)

	# Radial gradient glow
	for y in range(particle_size):
		for x in range(particle_size):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			var max_r = particle_size / 2.0
			if dist < max_r:
				var t = dist / max_r
				var alpha = (1.0 - t * t) * 0.8
				var c = bright.lerp(color, t)
				img.set_pixel(x, y, Color(c.r, c.g, c.b, alpha))

	# Bright core
	img.set_pixel(int(cx), int(cy), Color(bright.r, bright.g, bright.b, 0.95))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Animate particle floating
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(rect, "position:y", pos.y - 10, randf_range(1.5, 2.5))
	tween.tween_property(rect, "position:y", pos.y + 10, randf_range(1.5, 2.5))

	return rect


## Terrain modifier data (used by BattleManager)
static func get_terrain_modifiers(terrain: TerrainType) -> Dictionary:
	"""Get elemental damage modifiers for terrain"""
	match terrain:
		TerrainType.CAVE:
			return {
				"boost": ["ice", "dark"],
				"reduce": ["fire", "lightning"]
			}
		TerrainType.FOREST:
			return {
				"boost": ["fire", "wind"],
				"reduce": ["water"]
			}
		TerrainType.VILLAGE:
			return {
				"boost": ["holy"],
				"reduce": ["dark"]
			}
		TerrainType.BOSS:
			return {
				"boost": ["dark"],
				"reduce": []
			}
		_:  # PLAINS and default
			return {
				"boost": [],
				"reduce": []
			}


static func get_terrain_modifier_value() -> float:
	"""Get the modifier percentage (0.25 = 25% boost/reduction)"""
	return 0.25
