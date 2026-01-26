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

## Terrain color palettes
const TERRAIN_PALETTES = {
	TerrainType.PLAINS: {
		"sky_top": Color(0.15, 0.18, 0.25),
		"sky_bottom": Color(0.25, 0.30, 0.40),
		"ground": Color(0.20, 0.25, 0.20),
		"accent": Color(0.35, 0.40, 0.35)
	},
	TerrainType.CAVE: {
		"sky_top": Color(0.10, 0.08, 0.15),
		"sky_bottom": Color(0.18, 0.12, 0.22),
		"ground": Color(0.12, 0.10, 0.15),
		"accent": Color(0.25, 0.18, 0.30)
	},
	TerrainType.FOREST: {
		"sky_top": Color(0.05, 0.12, 0.08),
		"sky_bottom": Color(0.10, 0.20, 0.12),
		"ground": Color(0.08, 0.15, 0.08),
		"accent": Color(0.15, 0.25, 0.15)
	},
	TerrainType.VILLAGE: {
		"sky_top": Color(0.20, 0.15, 0.12),
		"sky_bottom": Color(0.30, 0.22, 0.18),
		"ground": Color(0.25, 0.20, 0.15),
		"accent": Color(0.35, 0.28, 0.20)
	},
	TerrainType.BOSS: {
		"sky_top": Color(0.25, 0.08, 0.10),
		"sky_bottom": Color(0.35, 0.12, 0.15),
		"ground": Color(0.20, 0.08, 0.10),
		"accent": Color(0.40, 0.15, 0.18)
	}
}

var current_terrain: TerrainType = TerrainType.PLAINS
var _background_elements: Array[Node2D] = []


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
	"""Draw vertical gradient background"""
	var gradient_steps = 8
	var step_height = viewport_size.y / gradient_steps

	for i in range(gradient_steps):
		var rect = ColorRect.new()
		var t = float(i) / (gradient_steps - 1)
		rect.color = palette["sky_top"].lerp(palette["sky_bottom"], t)
		rect.position = Vector2(0, i * step_height)
		rect.size = Vector2(viewport_size.x, step_height + 1)  # +1 to avoid gaps
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)

	# Ground layer
	var ground = ColorRect.new()
	ground.color = palette["ground"]
	ground.position = Vector2(0, viewport_size.y * 0.7)
	ground.size = Vector2(viewport_size.x, viewport_size.y * 0.3)
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)


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


## Element creation helpers

func _create_hill(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	"""Create a simple hill shape (rounded rectangle approximation)"""
	var hill = ColorRect.new()
	hill.color = color
	hill.position = pos - Vector2(size.x / 2, 0)
	hill.size = size
	hill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return hill


func _create_grass_tuft(pos: Vector2, color: Color) -> ColorRect:
	"""Create a small grass tuft"""
	var grass = ColorRect.new()
	grass.color = color.lightened(0.2)
	grass.position = pos
	grass.size = Vector2(4, 8)
	grass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return grass


func _create_stalactite(pos: Vector2, height: float, color: Color) -> Control:
	"""Create a stalactite (triangle pointing down)"""
	var container = Control.new()
	container.position = pos
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Simple triangle approximation with stacked rectangles
	var width = height * 0.3
	for i in range(int(height / 4)):
		var rect = ColorRect.new()
		var t = float(i) / (height / 4)
		rect.size = Vector2(width * (1.0 - t * 0.9), 4)
		rect.position = Vector2(-rect.size.x / 2, i * 4)
		rect.color = color.lightened(t * 0.1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(rect)

	return container


func _create_stalagmite(pos: Vector2, height: float, color: Color) -> Control:
	"""Create a stalagmite (triangle pointing up)"""
	var container = Control.new()
	container.position = pos - Vector2(0, height)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var width = height * 0.3
	for i in range(int(height / 4)):
		var rect = ColorRect.new()
		var t = float(i) / (height / 4)
		rect.size = Vector2(width * t, 4)
		rect.position = Vector2(-rect.size.x / 2, i * 4)
		rect.color = color.darkened(t * 0.1)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(rect)

	return container


func _create_rock(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	"""Create a rock formation"""
	var rock = ColorRect.new()
	rock.color = color
	rock.position = pos - Vector2(size.x / 2, size.y)
	rock.size = size
	rock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rock


func _create_tree_silhouette(pos: Vector2, height: float, color: Color) -> Control:
	"""Create a tree silhouette"""
	var container = Control.new()
	container.position = pos
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Trunk
	var trunk = ColorRect.new()
	trunk.color = color.darkened(0.2)
	trunk.size = Vector2(height * 0.1, height * 0.4)
	trunk.position = Vector2(-trunk.size.x / 2, -trunk.size.y)
	trunk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(trunk)

	# Canopy (triangle layers)
	var canopy_height = height * 0.7
	for i in range(3):
		var layer = ColorRect.new()
		var layer_width = height * (0.5 - i * 0.1)
		layer.color = color.lightened(i * 0.05)
		layer.size = Vector2(layer_width, canopy_height * 0.4)
		layer.position = Vector2(-layer_width / 2, -trunk.size.y - canopy_height * 0.3 - i * canopy_height * 0.25)
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(layer)

	return container


func _create_building(pos: Vector2, size: Vector2, color: Color) -> Control:
	"""Create a building silhouette"""
	var container = Control.new()
	container.position = pos
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Main building
	var main = ColorRect.new()
	main.color = color
	main.size = size
	main.position = Vector2(-size.x / 2, -size.y)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(main)

	# Roof (triangle approximation)
	var roof = ColorRect.new()
	roof.color = color.darkened(0.2)
	roof.size = Vector2(size.x * 1.2, size.y * 0.2)
	roof.position = Vector2(-roof.size.x / 2, -size.y - roof.size.y)
	roof.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(roof)

	# Windows
	for row in range(2):
		for col in range(2):
			var window = ColorRect.new()
			window.color = Color(0.9, 0.8, 0.4, 0.7)  # Warm light
			window.size = Vector2(8, 10)
			window.position = Vector2(
				-size.x / 2 + size.x * 0.25 + col * size.x * 0.4,
				-size.y * 0.7 + row * size.y * 0.35
			)
			window.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(window)

	return container


func _create_lamp_post(pos: Vector2, color: Color) -> Control:
	"""Create a lamp post"""
	var container = Control.new()
	container.position = pos
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Post
	var post = ColorRect.new()
	post.color = color.darkened(0.3)
	post.size = Vector2(4, 40)
	post.position = Vector2(-2, -40)
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(post)

	# Lamp
	var lamp = ColorRect.new()
	lamp.color = Color(1.0, 0.9, 0.6, 0.9)
	lamp.size = Vector2(10, 8)
	lamp.position = Vector2(-5, -48)
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(lamp)

	return container


func _create_pillar(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	"""Create a dramatic pillar"""
	var pillar = ColorRect.new()
	pillar.color = color
	pillar.size = size
	pillar.position = pos - Vector2(size.x / 2, 0)
	pillar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pillar


func _create_energy_particle(pos: Vector2, color: Color) -> ColorRect:
	"""Create a small energy particle for boss arena"""
	var particle = ColorRect.new()
	particle.color = color
	particle.size = Vector2(randf_range(2, 5), randf_range(2, 5))
	particle.position = pos
	particle.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Animate particle floating
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(particle, "position:y", pos.y - 10, randf_range(1.5, 2.5))
	tween.tween_property(particle, "position:y", pos.y + 10, randf_range(1.5, 2.5))

	return particle


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
