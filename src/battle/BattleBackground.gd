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

## Seed-based RNG for reproducible but varied backgrounds
var background_seed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## 3-layer depth system
var _layer_far: Control = null    # z=-100 (distant elements)
var _layer_mid: Control = null    # z=-50 (mid-distance elements)
var _layer_near: Control = null   # z=-10 (close/foreground elements)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = -100  # Render behind everything
	_setup_layers()


func _setup_layers() -> void:
	"""Create the 3-layer depth system"""
	_layer_far = Control.new()
	_layer_far.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_far.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_far.z_index = -100
	add_child(_layer_far)

	_layer_mid = Control.new()
	_layer_mid.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_mid.z_index = -50
	add_child(_layer_mid)

	_layer_near = Control.new()
	_layer_near.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer_near.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer_near.z_index = -10
	add_child(_layer_near)


func set_terrain(terrain: TerrainType) -> void:
	"""Set the terrain type and redraw background with random seed"""
	current_terrain = terrain
	if background_seed == 0:
		background_seed = randi()
	_rng.seed = background_seed
	_draw_background()


func set_terrain_with_seed(terrain: TerrainType, seed_value: int) -> void:
	"""Set terrain with a specific seed for reproducible backgrounds"""
	background_seed = seed_value
	current_terrain = terrain
	_rng.seed = background_seed
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

	# Clear layer children (but not the layers themselves)
	if _layer_far:
		for child in _layer_far.get_children():
			child.queue_free()
	if _layer_mid:
		for child in _layer_mid.get_children():
			child.queue_free()
	if _layer_near:
		for child in _layer_near.get_children():
			child.queue_free()

	# Ensure layers exist
	if not _layer_far:
		_setup_layers()

	var viewport_size = get_viewport_rect().size
	var palette = TERRAIN_PALETTES.get(current_terrain, TERRAIN_PALETTES[TerrainType.PLAINS])

	# Draw gradient background (directly on this control, behind layers)
	_draw_gradient(viewport_size, palette)

	# Draw terrain-specific elements into layers
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


func _add_to_layer(element: Node, layer: Control) -> void:
	"""Add an element to a specific depth layer"""
	layer.add_child(element)
	_background_elements.append(element)


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
	"""Draw plains background elements - rolling hills, grass, flowers, clouds"""
	# Far layer: distant hills with seed-based variation
	for i in range(3):
		var x_offset = _rng.randf_range(-0.05, 0.05)
		var hill = _create_hill(
			Vector2(viewport_size.x * (0.2 + i * 0.3 + x_offset), viewport_size.y * 0.6),
			Vector2(_rng.randf_range(160, 240), _rng.randf_range(60, 100)),
			palette["accent"].darkened(0.2 + i * 0.1)
		)
		_add_to_layer(hill, _layer_far)

	# Far layer: wispy clouds
	for i in range(_rng.randi_range(2, 4)):
		var cloud = _create_cloud(
			Vector2(_rng.randf_range(30, viewport_size.x - 30), viewport_size.y * _rng.randf_range(0.08, 0.25)),
			palette["sky_bottom"].lightened(0.15)
		)
		_add_to_layer(cloud, _layer_far)

	# Mid layer: scattered grass tufts
	for i in range(8):
		var grass = _create_grass_tuft(
			Vector2(_rng.randf_range(50, viewport_size.x - 50), viewport_size.y * _rng.randf_range(0.75, 0.9)),
			palette["accent"]
		)
		_add_to_layer(grass, _layer_mid)

	# Near layer: wildflowers scattered in foreground
	for i in range(_rng.randi_range(4, 8)):
		var flower = _create_flower(
			Vector2(_rng.randf_range(30, viewport_size.x - 30), viewport_size.y * _rng.randf_range(0.82, 0.95)),
			palette["accent"]
		)
		_add_to_layer(flower, _layer_near)

	# Near layer: wind-swept grass blades (larger, foreground)
	for i in range(_rng.randi_range(3, 5)):
		var tall_grass = _create_grass_tuft(
			Vector2(_rng.randf_range(20, viewport_size.x - 20), viewport_size.y * _rng.randf_range(0.88, 0.96)),
			palette["accent"].lightened(0.1)
		)
		_add_to_layer(tall_grass, _layer_near)


func _draw_cave_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw cave background elements - stalactites, crystals, light rays"""
	# Far layer: stalactites from ceiling
	for i in range(6):
		var x_jitter = _rng.randf_range(-0.03, 0.03)
		var stalactite = _create_stalactite(
			Vector2(viewport_size.x * (0.1 + i * 0.15 + x_jitter), 0),
			_rng.randf_range(60, 120),
			palette["accent"]
		)
		_add_to_layer(stalactite, _layer_far)

	# Far layer: glowing crystals on walls
	var crystal_color = palette.get("crystal", palette["accent"].lightened(0.3))
	for i in range(_rng.randi_range(2, 5)):
		var crystal = _create_crystal(
			Vector2(_rng.randf_range(30, viewport_size.x - 30), viewport_size.y * _rng.randf_range(0.4, 0.7)),
			crystal_color
		)
		_add_to_layer(crystal, _layer_far)

	# Mid layer: stalagmites from ground
	for i in range(5):
		var x_jitter = _rng.randf_range(-0.02, 0.02)
		var stalagmite = _create_stalagmite(
			Vector2(viewport_size.x * (0.05 + i * 0.2 + x_jitter), viewport_size.y),
			_rng.randf_range(40, 80),
			palette["accent"]
		)
		_add_to_layer(stalagmite, _layer_mid)

	# Mid layer: dim light rays from above (atmospheric)
	for i in range(_rng.randi_range(1, 3)):
		var ray = _create_light_ray(
			Vector2(_rng.randf_range(80, viewport_size.x - 80), 0),
			viewport_size.y * _rng.randf_range(0.4, 0.7),
			palette["accent"].lightened(0.2)
		)
		_add_to_layer(ray, _layer_mid)

	# Near layer: rock formations
	for i in range(3):
		var rock = _create_rock(
			Vector2(_rng.randf_range(50, viewport_size.x - 50), viewport_size.y * 0.85),
			Vector2(_rng.randf_range(30, 50), _rng.randf_range(20, 40)),
			palette["ground"].lightened(0.1)
		)
		_add_to_layer(rock, _layer_near)


func _draw_forest_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw forest background elements - tree silhouettes, fireflies, fallen logs, mushrooms"""
	# Far layer: background trees (darker, smaller, dense canopy)
	for i in range(8):
		var x_jitter = _rng.randf_range(-0.02, 0.02)
		var tree = _create_tree_silhouette(
			Vector2(viewport_size.x * (i * 0.12 + x_jitter), viewport_size.y * 0.5),
			_rng.randf_range(80, 120),
			palette["sky_bottom"].darkened(0.3)
		)
		_add_to_layer(tree, _layer_far)

	# Far layer: fireflies drifting among the trees
	for i in range(_rng.randi_range(4, 8)):
		var firefly = _create_firefly(
			Vector2(_rng.randf_range(40, viewport_size.x - 40), viewport_size.y * _rng.randf_range(0.25, 0.55)),
			palette["accent"].lightened(0.5)
		)
		_add_to_layer(firefly, _layer_far)

	# Mid layer: foreground trees (larger, slightly lighter)
	for i in range(5):
		var x_jitter = _rng.randf_range(-0.05, 0.05)
		var tree = _create_tree_silhouette(
			Vector2(viewport_size.x * (i * 0.22 + x_jitter), viewport_size.y * 0.6),
			_rng.randf_range(120, 160),
			palette["accent"].darkened(0.2)
		)
		_add_to_layer(tree, _layer_mid)

	# Mid layer: fallen logs on ground
	for i in range(_rng.randi_range(1, 3)):
		var log = _create_fallen_log(
			Vector2(_rng.randf_range(60, viewport_size.x - 60), viewport_size.y * _rng.randf_range(0.78, 0.88)),
			palette.get("trunk", palette["accent"].darkened(0.3))
		)
		_add_to_layer(log, _layer_mid)

	# Near layer: mushrooms growing on forest floor
	for i in range(_rng.randi_range(3, 6)):
		var mushroom = _create_mushroom(
			Vector2(_rng.randf_range(30, viewport_size.x - 30), viewport_size.y * _rng.randf_range(0.85, 0.95)),
			palette["accent"]
		)
		_add_to_layer(mushroom, _layer_near)

	# Near layer: grass tufts on forest floor
	for i in range(_rng.randi_range(4, 7)):
		var grass = _create_grass_tuft(
			Vector2(_rng.randf_range(20, viewport_size.x - 20), viewport_size.y * _rng.randf_range(0.88, 0.96)),
			palette["accent"].darkened(0.1)
		)
		_add_to_layer(grass, _layer_near)


func _draw_village_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw village background elements - buildings, lamp posts, smoke, cobblestones, flower boxes"""
	# Far layer: building silhouettes
	var building_positions = [0.1, 0.3, 0.5, 0.7, 0.85]
	for i in range(building_positions.size()):
		var pos_x = viewport_size.x * building_positions[i]
		var building = _create_building(
			Vector2(pos_x, viewport_size.y * 0.55),
			Vector2(_rng.randf_range(60, 100), _rng.randf_range(80, 140)),
			palette["accent"].darkened(0.1 + _rng.randf_range(0.0, 0.1))
		)
		_add_to_layer(building, _layer_far)

	# Far layer: chimney smoke wisps rising from buildings
	for i in range(_rng.randi_range(2, 4)):
		var smoke = _create_smoke_wisp(
			Vector2(viewport_size.x * building_positions[_rng.randi_range(0, building_positions.size() - 1)],
				viewport_size.y * _rng.randf_range(0.12, 0.30)),
			palette["sky_bottom"].lightened(0.08)
		)
		_add_to_layer(smoke, _layer_far)

	# Mid layer: lamp posts
	for i in range(2):
		var lamp = _create_lamp_post(
			Vector2(viewport_size.x * (0.25 + i * 0.5), viewport_size.y * 0.75),
			palette["accent"]
		)
		_add_to_layer(lamp, _layer_mid)

	# Near layer: cobblestone patches on ground
	for i in range(_rng.randi_range(2, 4)):
		var cobble = _create_cobblestones(
			Vector2(_rng.randf_range(40, viewport_size.x - 40), viewport_size.y * _rng.randf_range(0.82, 0.94)),
			palette["ground"].lightened(0.08)
		)
		_add_to_layer(cobble, _layer_near)

	# Near layer: flower boxes at building bases
	for i in range(_rng.randi_range(2, 4)):
		var idx = _rng.randi_range(0, building_positions.size() - 1)
		var fbox = _create_flower_box(
			Vector2(viewport_size.x * building_positions[idx] + _rng.randf_range(-10, 10),
				viewport_size.y * _rng.randf_range(0.78, 0.84)),
			palette["accent"]
		)
		_add_to_layer(fbox, _layer_near)


func _draw_boss_elements(viewport_size: Vector2, palette: Dictionary) -> void:
	"""Draw boss arena background - dramatic lighting, debris, arcane circles, lightning"""
	# Far layer: ominous pillars
	for i in range(4):
		var x_jitter = _rng.randf_range(-0.02, 0.02)
		var pillar = _create_pillar(
			Vector2(viewport_size.x * (0.1 + i * 0.28 + x_jitter), viewport_size.y * 0.3),
			Vector2(30, _rng.randf_range(180, 220)),
			palette["accent"]
		)
		_add_to_layer(pillar, _layer_far)

	# Far layer: arcane circle on the ground (ritual glyph)
	var glow_color = palette.get("glow", palette["accent"].lightened(0.3))
	var arcane = _create_arcane_circle(
		Vector2(viewport_size.x * 0.5, viewport_size.y * 0.78),
		glow_color
	)
	_add_to_layer(arcane, _layer_far)

	# Mid layer: lightning cracks in the sky
	for i in range(_rng.randi_range(1, 3)):
		var bolt = _create_lightning_crack(
			Vector2(_rng.randf_range(60, viewport_size.x - 60), _rng.randf_range(10, viewport_size.y * 0.3)),
			_rng.randf_range(60, 140),
			glow_color
		)
		_add_to_layer(bolt, _layer_mid)

	# Mid layer: energy particles/effects
	for i in range(10):
		var particle = _create_energy_particle(
			Vector2(_rng.randf_range(50, viewport_size.x - 50), _rng.randf_range(100, viewport_size.y - 100)),
			palette["sky_bottom"].lightened(0.3)
		)
		_add_to_layer(particle, _layer_mid)

	# Near layer: debris/rubble scattered on ground
	for i in range(_rng.randi_range(3, 6)):
		var debris = _create_debris(
			Vector2(_rng.randf_range(30, viewport_size.x - 30), viewport_size.y * _rng.randf_range(0.84, 0.96)),
			palette["ground"].lightened(0.05)
		)
		_add_to_layer(debris, _layer_near)


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
		var blade_height = _rng.randi_range(5, 9)
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
	var particle_size = _rng.randi_range(6, 12)
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
	var float_up = _rng.randf_range(1.5, 2.5)
	var float_down = _rng.randf_range(1.5, 2.5)
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(rect, "position:y", pos.y - 10, float_up)
	tween.tween_property(rect, "position:y", pos.y + 10, float_down)

	return rect


## New element helpers for seed-based terrain variety


func _create_cloud(pos: Vector2, color: Color) -> TextureRect:
	"""Create a wispy cloud with soft edges (SNES-style layered puffs)"""
	var w = _rng.randi_range(60, 110)
	var h = _rng.randi_range(18, 30)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0
	var cy = h / 2.0
	var light = color.lightened(0.15)

	# Draw 3 overlapping ellipses for puffy cloud shape
	var puffs = [
		[cx - w * 0.2, cy, w * 0.30, h * 0.40],
		[cx, cy - h * 0.1, w * 0.38, h * 0.45],
		[cx + w * 0.2, cy + h * 0.05, w * 0.28, h * 0.38],
	]

	for puff in puffs:
		var pcx = puff[0]
		var pcy = puff[1]
		var prx = puff[2]
		var pry = puff[3]
		for y in range(h):
			for x in range(w):
				var dx = (x - pcx) / max(prx, 1.0)
				var dy = (y - pcy) / max(pry, 1.0)
				var dist = sqrt(dx * dx + dy * dy)
				if dist < 1.0:
					# Soft fade at edges
					var alpha = (1.0 - dist) * 0.5
					var c = light if dy < -0.2 else color
					var existing = img.get_pixel(x, y)
					if existing.a < alpha:
						img.set_pixel(x, y, Color(c.r, c.g, c.b, alpha))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_flower(pos: Vector2, color: Color) -> TextureRect:
	"""Create a small pixel-art wildflower with stem and petals"""
	var w = 10
	var h = 14
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var stem_color = color.darkened(0.1)
	var stem_dark = color.darkened(0.3)
	# Random petal color (warm variations)
	var petal_hue = _rng.randf_range(0.0, 1.0)
	var petal_color: Color
	if petal_hue < 0.3:
		petal_color = Color(0.9, 0.3, 0.3)  # Red
	elif petal_hue < 0.6:
		petal_color = Color(0.9, 0.8, 0.2)  # Yellow
	else:
		petal_color = Color(0.7, 0.4, 0.9)  # Purple
	var petal_light = petal_color.lightened(0.3)
	var center_color = Color(0.95, 0.9, 0.3)

	var cx = w / 2

	# Stem (2px wide, slight lean)
	var lean = _rng.randi_range(-1, 1)
	for i in range(6):
		var sy = h - 1 - i
		var sx = cx + int(lean * i * 0.15)
		if sx >= 0 and sx < w and sy >= 0 and sy < h:
			img.set_pixel(sx, sy, stem_color if i > 1 else stem_dark)

	# Petals (4 directional + center)
	var flower_y = h - 7
	var flower_x = cx + int(lean * 5 * 0.15)
	var petal_offsets = [[-2, 0], [2, 0], [0, -2], [0, 2]]
	for offset in petal_offsets:
		var px = flower_x + offset[0]
		var py = flower_y + offset[1]
		if px >= 0 and px < w and py >= 0 and py < h:
			img.set_pixel(px, py, petal_color)
		# Inner petal (closer to center)
		var ipx = flower_x + int(offset[0] * 0.5)
		var ipy = flower_y + int(offset[1] * 0.5)
		if ipx >= 0 and ipx < w and ipy >= 0 and ipy < h:
			img.set_pixel(ipx, ipy, petal_light)
	# Center
	if flower_x >= 0 and flower_x < w and flower_y >= 0 and flower_y < h:
		img.set_pixel(flower_x, flower_y, center_color)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_crystal(pos: Vector2, color: Color) -> TextureRect:
	"""Create a glowing crystal cluster on cave walls"""
	var w = _rng.randi_range(14, 22)
	var h = _rng.randi_range(20, 32)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var light = color.lightened(0.35)
	var mid = color.lightened(0.15)
	var dark = color.darkened(0.25)
	var outline = color.darkened(0.4)
	var glow = color.lightened(0.5)

	# Draw 2-3 crystal shards with faceted shading
	var shard_count = _rng.randi_range(2, 3)
	for s in range(shard_count):
		var sx = int(w * (0.2 + s * 0.3) + _rng.randf_range(-2, 2))
		var shard_h = int(h * _rng.randf_range(0.5, 0.9))
		var shard_w = _rng.randi_range(3, 6)
		var shard_top = h - shard_h

		for y in range(shard_top, h):
			var t = float(y - shard_top) / max(shard_h, 1)
			# Tapers toward top
			var half_w = int(shard_w * 0.5 * t)
			for dx in range(-half_w, half_w + 1):
				var px = sx + dx
				if px >= 0 and px < w and y >= 0 and y < h:
					if abs(dx) == half_w:
						img.set_pixel(px, y, outline)
					elif dx < 0:
						img.set_pixel(px, y, light)  # Left facet (lit)
					else:
						img.set_pixel(px, y, mid)    # Right facet
			# Tip highlight
			if y == shard_top and sx >= 0 and sx < w:
				img.set_pixel(sx, y, glow)

	# Soft glow aura around crystal base
	var base_cx = w / 2.0
	var base_cy = float(h) - 3.0
	for y in range(h):
		for x in range(w):
			var dist = sqrt(pow(x - base_cx, 2) + pow(y - base_cy, 2))
			if dist < 8 and dist > 3:
				var alpha = (1.0 - (dist - 3) / 5.0) * 0.15
				if img.get_pixel(x, y).a < 0.01:
					img.set_pixel(x, y, Color(glow.r, glow.g, glow.b, alpha))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_light_ray(pos: Vector2, ray_length: float, color: Color) -> TextureRect:
	"""Create a diagonal light ray for cave atmosphere"""
	var w = int(ray_length * 0.4)
	var h = int(ray_length)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var lean = _rng.randf_range(-0.3, 0.3)

	# Draw a soft diagonal beam of light
	for y in range(h):
		var t = float(y) / max(h, 1)
		# Ray width narrows toward bottom, offset by lean
		var ray_w = int((1.0 - t * 0.6) * 6)
		var offset_x = int(lean * y)
		var cx = w / 2 + offset_x

		for dx in range(-ray_w, ray_w + 1):
			var px = cx + dx
			if px >= 0 and px < w:
				# Soft falloff from center
				var dist = abs(dx) / max(float(ray_w), 1.0)
				var alpha = (1.0 - dist) * (1.0 - t * 0.7) * 0.12
				if alpha > 0.01:
					img.set_pixel(px, y, Color(color.r, color.g, color.b, alpha))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_firefly(pos: Vector2, color: Color) -> TextureRect:
	"""Create an animated firefly with pulsing glow"""
	var s = 8
	var img = Image.create(s, s, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = s / 2.0
	var cy = s / 2.0
	var bright = Color(0.9, 1.0, 0.5, 0.9)

	# Tiny glow dot with soft aura
	for y in range(s):
		for x in range(s):
			var dist = sqrt(pow(x - cx, 2) + pow(y - cy, 2))
			if dist < 1.2:
				img.set_pixel(x, y, bright)
			elif dist < 3.5:
				var alpha = (1.0 - (dist - 1.2) / 2.3) * 0.35
				img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(s / 2.0, s / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Animate: gentle float + pulse
	var drift_x = _rng.randf_range(-15, 15)
	var drift_y = _rng.randf_range(-10, 10)
	var duration = _rng.randf_range(2.0, 4.0)
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(rect, "position", pos + Vector2(drift_x, drift_y), duration)
	tween.parallel().tween_property(rect, "modulate:a", 0.3, duration * 0.5)
	tween.tween_property(rect, "position", pos, duration)
	tween.parallel().tween_property(rect, "modulate:a", 1.0, duration * 0.5)

	return rect


func _create_fallen_log(pos: Vector2, color: Color) -> TextureRect:
	"""Create a horizontal fallen log on the forest floor"""
	var w = _rng.randi_range(50, 80)
	var h = _rng.randi_range(12, 18)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var light = color.lightened(0.15)
	var dark = color.darkened(0.2)
	var outline = color.darkened(0.4)
	var moss = Color(0.2, 0.4, 0.15)

	var cy = h / 2.0

	# Rounded cylindrical log with bark texture
	for y in range(h):
		var dy = abs(y - cy) / (h / 2.0)
		if dy > 1.0:
			continue
		var edge_squeeze = sqrt(1.0 - dy * dy)
		var x_start = int(w * 0.02 / edge_squeeze) if edge_squeeze > 0.1 else w / 2
		var x_end = w - x_start

		for x in range(x_start, x_end):
			var c = color
			# Cylindrical shading: top lighter, bottom darker
			if y < cy - h * 0.15:
				c = light
			elif y > cy + h * 0.15:
				c = dark
			# Bark texture
			if (x + y * 3) % 7 == 0:
				c = c.darkened(0.06)
			# Outline
			if y == int(cy - h / 2.0 * edge_squeeze) or y == int(cy + h / 2.0 * edge_squeeze) - 1:
				c = outline
			img.set_pixel(x, y, c)

	# Moss patches on top
	for i in range(_rng.randi_range(2, 5)):
		var mx = _rng.randi_range(5, w - 5)
		var my = int(cy - h * 0.3)
		for dx in range(-2, 3):
			for dy in range(-1, 2):
				var px = mx + dx
				var py = my + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					if img.get_pixel(px, py).a > 0.1:
						img.set_pixel(px, py, moss.lightened(0.05 * abs(dx)))

	# Cross-section circles at ends
	for end_x in [2, w - 3]:
		for dy in range(-int(h * 0.3), int(h * 0.3)):
			var px = end_x
			var py = int(cy) + dy
			if px >= 0 and px < w and py >= 0 and py < h:
				img.set_pixel(px, py, dark)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_mushroom(pos: Vector2, color: Color) -> TextureRect:
	"""Create a small pixel-art forest mushroom"""
	var w = _rng.randi_range(8, 14)
	var h = _rng.randi_range(10, 16)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# Random mushroom cap color
	var cap_hue = _rng.randf_range(0.0, 1.0)
	var cap_color: Color
	if cap_hue < 0.4:
		cap_color = Color(0.7, 0.2, 0.15)  # Red/brown
	elif cap_hue < 0.7:
		cap_color = Color(0.85, 0.65, 0.2)  # Golden
	else:
		cap_color = Color(0.5, 0.3, 0.6)    # Purple
	var cap_light = cap_color.lightened(0.25)
	var cap_dark = cap_color.darkened(0.2)
	var stem_color = Color(0.85, 0.8, 0.7)
	var stem_dark = stem_color.darkened(0.15)
	var outline = cap_color.darkened(0.4)
	var spot_color = Color(0.95, 0.92, 0.85)

	var cx = w / 2.0
	var cap_h = int(h * 0.45)
	var stem_top = cap_h - 2

	# Stem (tapered)
	for y in range(stem_top, h):
		var t = float(y - stem_top) / max(h - stem_top, 1)
		var half_w = int(w * 0.12 + w * 0.06 * t)
		for dx in range(-half_w, half_w + 1):
			var px = int(cx) + dx
			if px >= 0 and px < w:
				if abs(dx) == half_w:
					img.set_pixel(px, y, outline)
				elif dx < 0:
					img.set_pixel(px, y, stem_color)
				else:
					img.set_pixel(px, y, stem_dark)

	# Cap (dome shape)
	var cap_cy = cap_h * 0.6
	var cap_rx = w * 0.45
	var cap_ry = float(cap_h) * 0.55
	for y in range(cap_h + 2):
		for x in range(w):
			var dx = (x - cx) / max(cap_rx, 1.0)
			var dy = (y - cap_cy) / max(cap_ry, 1.0)
			var dist = sqrt(dx * dx + dy * dy)
			if dist < 0.9:
				var c = cap_color
				if dy < -0.3:
					c = cap_light
				elif dy > 0.4:
					c = cap_dark
				img.set_pixel(x, y, c)
			elif dist < 1.0:
				img.set_pixel(x, y, outline)

	# Spots on cap
	for i in range(_rng.randi_range(1, 3)):
		var sx = int(cx + _rng.randf_range(-cap_rx * 0.5, cap_rx * 0.5))
		var sy = int(cap_cy + _rng.randf_range(-cap_ry * 0.3, cap_ry * 0.1))
		if sx >= 0 and sx < w and sy >= 0 and sy < h:
			img.set_pixel(sx, sy, spot_color)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_smoke_wisp(pos: Vector2, color: Color) -> TextureRect:
	"""Create a gentle smoke wisp rising from a chimney"""
	var w = _rng.randi_range(20, 35)
	var h = _rng.randi_range(30, 50)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var cx = w / 2.0

	# Draw wispy smoke rising with S-curve
	for y in range(h):
		var t = float(y) / max(h, 1)
		# S-curve wobble
		var wobble = sin(t * 3.14 * 2.0 + _rng.randf_range(0, 3.14)) * (4.0 + t * 6.0)
		var radius = 2.0 + t * 5.0  # Expands as it rises (bottom=source, top=dissipated)
		var alpha = (1.0 - t) * 0.2  # Fades as it rises

		# Draw from bottom up (y=h-1 is source, y=0 is top)
		var draw_y = h - 1 - y
		for dx in range(int(-radius), int(radius) + 1):
			var px = int(cx + wobble) + dx
			if px >= 0 and px < w and draw_y >= 0 and draw_y < h:
				var dist = abs(dx) / max(radius, 1.0)
				var pixel_alpha = alpha * (1.0 - dist)
				if pixel_alpha > 0.01:
					img.set_pixel(px, draw_y, Color(color.r, color.g, color.b, pixel_alpha))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Gentle upward drift animation
	var drift = _rng.randf_range(1.5, 3.0)
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(rect, "position:y", pos.y - h - 20, drift)
	tween.tween_property(rect, "modulate:a", 0.0, drift * 0.3)
	tween.tween_callback(func():
		rect.position.y = pos.y - h
		rect.modulate.a = 1.0
	)

	return rect


func _create_cobblestones(pos: Vector2, color: Color) -> TextureRect:
	"""Create a small patch of cobblestone ground detail"""
	var w = _rng.randi_range(24, 40)
	var h = _rng.randi_range(10, 16)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var light = color.lightened(0.12)
	var dark = color.darkened(0.15)
	var gap_color = color.darkened(0.35)

	# Draw irregular cobblestone grid
	var stone_w = _rng.randi_range(5, 8)
	var stone_h = _rng.randi_range(4, 6)

	for row in range(0, h, stone_h + 1):
		var x_offset = (row / (stone_h + 1)) % 2 * int(stone_w * 0.5)  # Brick-like offset
		for col in range(-1, w / stone_w + 1):
			var sx = col * (stone_w + 1) + x_offset
			for dy in range(stone_h):
				for dx in range(stone_w):
					var px = sx + dx
					var py = row + dy
					if px >= 0 and px < w and py >= 0 and py < h:
						if dx == 0 or dx == stone_w - 1 or dy == 0 or dy == stone_h - 1:
							img.set_pixel(px, py, gap_color)
						else:
							var c = color
							# Per-stone shading variation
							var stone_shade = sin(float(col * 17 + row * 7)) * 0.5
							if stone_shade > 0.2:
								c = light
							elif stone_shade < -0.2:
								c = dark
							img.set_pixel(px, py, c)

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_flower_box(pos: Vector2, color: Color) -> TextureRect:
	"""Create a window flower box with colorful flowers"""
	var w = _rng.randi_range(24, 36)
	var h = _rng.randi_range(14, 20)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var box_color = color.darkened(0.3)
	var box_light = color.darkened(0.15)
	var outline = color.darkened(0.5)
	var soil_color = Color(0.3, 0.22, 0.12)
	var leaf_color = Color(0.25, 0.45, 0.2)
	var leaf_light = leaf_color.lightened(0.2)

	# Box body (lower half)
	var box_top = int(h * 0.45)
	for y in range(box_top, h):
		for x in range(w):
			if x == 0 or x == w - 1 or y == box_top or y == h - 1:
				img.set_pixel(x, y, outline)
			elif x < w / 2:
				img.set_pixel(x, y, box_light)
			else:
				img.set_pixel(x, y, box_color)

	# Soil visible at top of box
	for x in range(2, w - 2):
		if box_top + 1 < h:
			img.set_pixel(x, box_top + 1, soil_color)

	# Flowers and leaves poking up
	var flower_count = _rng.randi_range(3, 5)
	for i in range(flower_count):
		var fx = int(w * 0.15 + i * (w * 0.7 / max(flower_count - 1, 1)))
		if fx >= w:
			fx = w - 2

		# Stem
		for sy in range(box_top - 3, box_top):
			if fx >= 0 and fx < w and sy >= 0 and sy < h:
				img.set_pixel(fx, sy, leaf_color)

		# Leaves
		if fx - 1 >= 0 and box_top - 1 >= 0 and box_top - 1 < h:
			img.set_pixel(fx - 1, box_top - 1, leaf_light)
		if fx + 1 < w and box_top - 2 >= 0 and box_top - 2 < h:
			img.set_pixel(fx + 1, box_top - 2, leaf_light)

		# Flower head
		var fy = box_top - 4
		var flower_hue = _rng.randf_range(0.0, 1.0)
		var fc: Color
		if flower_hue < 0.3:
			fc = Color(0.9, 0.3, 0.35)
		elif flower_hue < 0.6:
			fc = Color(0.95, 0.85, 0.3)
		else:
			fc = Color(0.8, 0.5, 0.9)

		for pdx in [-1, 0, 1]:
			for pdy in [-1, 0, 1]:
				var px = fx + pdx
				var py = fy + pdy
				if px >= 0 and px < w and py >= 0 and py < h:
					if pdx == 0 and pdy == 0:
						img.set_pixel(px, py, Color(0.95, 0.9, 0.3))  # Center
					elif abs(pdx) + abs(pdy) == 1:
						img.set_pixel(px, py, fc)  # Petals

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _create_arcane_circle(pos: Vector2, color: Color) -> TextureRect:
	"""Create a glowing arcane ritual circle on the ground"""
	var s = 120
	var img = Image.create(s, int(s * 0.4), true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var w = s
	var h = int(s * 0.4)
	var cx = w / 2.0
	var cy = h / 2.0
	var rx = w * 0.45
	var ry = h * 0.42  # Perspective-compressed ellipse
	var bright = color.lightened(0.3)

	# Outer ring
	for y in range(h):
		for x in range(w):
			var dx = (x - cx) / max(rx, 1.0)
			var dy = (y - cy) / max(ry, 1.0)
			var dist = sqrt(dx * dx + dy * dy)
			# Outer ring band
			if dist > 0.85 and dist < 1.0:
				var alpha = (1.0 - abs(dist - 0.925) / 0.075) * 0.4
				img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))
			# Inner ring band
			elif dist > 0.55 and dist < 0.65:
				var alpha = (1.0 - abs(dist - 0.6) / 0.05) * 0.25
				img.set_pixel(x, y, Color(color.r, color.g, color.b, alpha))

	# Glyphs at cardinal points (small bright dots)
	var glyph_angles = [0, 1.57, 3.14, 4.71]  # N, E, S, W
	for angle in glyph_angles:
		var gx = int(cx + cos(angle) * rx * 0.92)
		var gy = int(cy + sin(angle) * ry * 0.92)
		for gdx in range(-2, 3):
			for gdy in range(-1, 2):
				var px = gx + gdx
				var py = gy + gdy
				if px >= 0 and px < w and py >= 0 and py < h:
					img.set_pixel(px, py, Color(bright.r, bright.g, bright.b, 0.6))

	# Central pentagram hint (5-point star lines)
	var star_r = rx * 0.4
	var star_ry_scaled = ry * 0.4
	for i in range(5):
		var a1 = i * 1.2566 - 1.5708  # 72 degrees apart, start at top
		var a2 = ((i + 2) % 5) * 1.2566 - 1.5708  # Skip one point
		var x1 = int(cx + cos(a1) * star_r)
		var y1 = int(cy + sin(a1) * star_ry_scaled)
		var x2 = int(cx + cos(a2) * star_r)
		var y2 = int(cy + sin(a2) * star_ry_scaled)
		# Bresenham-style line
		var steps = max(abs(x2 - x1), abs(y2 - y1))
		if steps == 0:
			steps = 1
		for step in range(steps + 1):
			var t = float(step) / steps
			var lx = int(x1 + (x2 - x1) * t)
			var ly = int(y1 + (y2 - y1) * t)
			if lx >= 0 and lx < w and ly >= 0 and ly < h:
				img.set_pixel(lx, ly, Color(color.r, color.g, color.b, 0.3))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h / 2.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Slow pulsing glow
	var pulse_dur = _rng.randf_range(2.0, 3.5)
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(rect, "modulate:a", 0.5, pulse_dur)
	tween.tween_property(rect, "modulate:a", 1.0, pulse_dur)

	return rect


func _create_lightning_crack(pos: Vector2, bolt_length: float, color: Color) -> TextureRect:
	"""Create a jagged lightning bolt crack in the sky"""
	var w = int(bolt_length * 0.6)
	var h = int(bolt_length)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var bright = color.lightened(0.5)
	var glow = color.lightened(0.3)

	# Generate jagged bolt path
	var bx = w / 2.0
	var by = 0.0
	var segments = _rng.randi_range(5, 9)
	var seg_h = float(h) / segments

	for seg in range(segments):
		var next_bx = bx + _rng.randf_range(-w * 0.25, w * 0.25)
		next_bx = clamp(next_bx, 3, w - 3)
		var next_by = by + seg_h

		# Draw segment with glow
		var dx = next_bx - bx
		var dy = next_by - by
		var steps = max(abs(int(dx)), abs(int(dy)))
		if steps == 0:
			steps = 1
		for i in range(steps + 1):
			var t = float(i) / steps
			var px = int(bx + dx * t)
			var py = int(by + dy * t)
			# Core bolt (bright white-ish)
			if px >= 0 and px < w and py >= 0 and py < h:
				img.set_pixel(px, py, Color(bright.r, bright.g, bright.b, 0.9))
			# Glow around bolt
			for gdx in [-1, 0, 1]:
				for gdy in [-1, 0, 1]:
					if gdx == 0 and gdy == 0:
						continue
					var gpx = px + gdx
					var gpy = py + gdy
					if gpx >= 0 and gpx < w and gpy >= 0 and gpy < h:
						if img.get_pixel(gpx, gpy).a < 0.3:
							img.set_pixel(gpx, gpy, Color(glow.r, glow.g, glow.b, 0.3))

		# Branch chance at each segment
		if _rng.randf() < 0.35 and seg > 0:
			var branch_len = _rng.randi_range(4, 12)
			var branch_dir = 1 if _rng.randf() > 0.5 else -1
			var bbx = bx
			var bby = by + seg_h * 0.5
			for bi in range(branch_len):
				bbx += branch_dir * _rng.randf_range(0.8, 2.0)
				bby += _rng.randf_range(0.5, 1.5)
				var bpx = int(bbx)
				var bpy = int(bby)
				if bpx >= 0 and bpx < w and bpy >= 0 and bpy < h:
					img.set_pixel(bpx, bpy, Color(glow.r, glow.g, glow.b, 0.6))

		bx = next_bx
		by = next_by

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, 0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Flash animation (appears then fades)
	var flash_dur = _rng.randf_range(3.0, 6.0)
	var tween = create_tween()
	tween.set_loops()
	rect.modulate.a = 0.0
	tween.tween_interval(flash_dur)
	tween.tween_property(rect, "modulate:a", 0.9, 0.05)
	tween.tween_property(rect, "modulate:a", 0.3, 0.1)
	tween.tween_property(rect, "modulate:a", 0.8, 0.05)
	tween.tween_property(rect, "modulate:a", 0.0, 0.4)

	return rect


func _create_debris(pos: Vector2, color: Color) -> TextureRect:
	"""Create scattered rubble/debris chunks on the ground"""
	var w = _rng.randi_range(14, 24)
	var h = _rng.randi_range(10, 16)
	var img = Image.create(w, h, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var light = color.lightened(0.15)
	var dark = color.darkened(0.2)
	var outline = color.darkened(0.4)

	# Draw 2-4 irregular rock chunks
	var chunk_count = _rng.randi_range(2, 4)
	for c in range(chunk_count):
		var chunk_x = int(w * (0.15 + c * (0.7 / max(chunk_count - 1, 1))))
		var chunk_y = int(h * _rng.randf_range(0.3, 0.6))
		var chunk_w = _rng.randi_range(3, 7)
		var chunk_h = _rng.randi_range(3, 6)

		for dy in range(chunk_h):
			for dx in range(chunk_w):
				var px = chunk_x + dx
				var py = chunk_y + dy
				if px >= 0 and px < w and py >= 0 and py < h:
					if dx == 0 or dx == chunk_w - 1 or dy == 0 or dy == chunk_h - 1:
						img.set_pixel(px, py, outline)
					else:
						# Simple shading: top-left light, bottom-right dark
						var cc = color
						if dx < chunk_w / 2 and dy < chunk_h / 2:
							cc = light
						elif dx >= chunk_w / 2 and dy >= chunk_h / 2:
							cc = dark
						img.set_pixel(px, py, cc)

	# Dust/small particles around debris
	for i in range(_rng.randi_range(3, 8)):
		var dx = _rng.randi_range(0, w - 1)
		var dy = _rng.randi_range(int(h * 0.5), h - 1)
		if img.get_pixel(dx, dy).a < 0.01:
			img.set_pixel(dx, dy, Color(color.r, color.g, color.b, 0.2))

	var tex = ImageTexture.create_from_image(img)
	var rect = TextureRect.new()
	rect.texture = tex
	rect.position = pos - Vector2(w / 2.0, h)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
