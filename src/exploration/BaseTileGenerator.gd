extends Node
class_name BaseTileGenerator

## BaseTileGenerator - Shared base for all procedural tile generators
## Handles tile caching, atlas construction, and tileset creation
## Subclasses provide tile-specific drawing and configuration via virtual methods

const TILE_SIZE: int = 32

var _tile_cache: Dictionary = {}


# --- Virtual methods for subclasses to override ---

## Return palette dictionary keyed by tile type enum values
func _get_palettes() -> Dictionary:
	return {}

## Return the default tile type used as palette fallback
func _get_default_tile_type() -> int:
	return 0

## Draw a specific tile type onto the image
func _draw_tile(img: Image, tile_type: int, palette: Dictionary, variant: int) -> void:
	pass

## Return ordered array of tile type values for atlas layout
func _get_tile_order() -> Array:
	return []

## Return array of tile types that block movement
func _get_impassable_types() -> Array:
	return []

## Return atlas grid dimensions as Vector2i(cols, rows)
func _get_atlas_dimensions() -> Vector2i:
	return Vector2i(4, 4)

## Return tile variant overrides: {tile_index: variant_number}
## Only needed for generators with multiple variants per tile type in the atlas
func _get_tile_variants() -> Dictionary:
	return {}

## Return debug atlas filename (without extension)
func _get_debug_atlas_name() -> String:
	return "debug_atlas"


# --- Shared implementation ---

## Generate a tile texture for the given type, with caching
func generate_tile(type: int, variant: int = 0) -> ImageTexture:
	var cache_key = "%d_%d" % [type, variant]
	if _tile_cache.has(cache_key):
		return _tile_cache[cache_key]

	var img = Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var palettes = _get_palettes()
	var palette = palettes.get(type, palettes.get(_get_default_tile_type(), {}))

	_draw_tile(img, type, palette, variant)

	var texture = ImageTexture.create_from_image(img)
	_tile_cache[cache_key] = texture
	return texture


## Create a TileSet with all tile types for use in TileMap
func create_tileset() -> TileSet:
	var dims = _get_atlas_dimensions()
	var atlas_cols = dims.x
	var atlas_rows = dims.y

	var tileset = TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Add physics layer for collision
	tileset.add_physics_layer()
	tileset.set_physics_layer_collision_layer(0, 1)  # Layer 1
	tileset.set_physics_layer_collision_mask(0, 1)

	# Create atlas source from generated tiles
	var atlas = TileSetAtlasSource.new()
	var atlas_img = Image.create(TILE_SIZE * atlas_cols, TILE_SIZE * atlas_rows, false, Image.FORMAT_RGBA8)

	var tile_order = _get_tile_order()
	var tile_variants = _get_tile_variants()
	var impassable_types = _get_impassable_types()

	for i in range(tile_order.size()):
		var tile_type = tile_order[i]
		var variant = tile_variants.get(i, 0)

		var tile_tex = generate_tile(tile_type, variant)
		var tile_img = tile_tex.get_image()

		# Use blit_rect for native C++ image copy instead of per-pixel GDScript loop
		var col = i % atlas_cols
		var row = i / atlas_cols
		atlas_img.blit_rect(tile_img, Rect2i(0, 0, TILE_SIZE, TILE_SIZE), Vector2i(col * TILE_SIZE, row * TILE_SIZE))

	var atlas_texture = ImageTexture.create_from_image(atlas_img)
	atlas.texture = atlas_texture
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)

	# Debug: Save atlas to disk for inspection
	if OS.is_debug_build():
		var debug_name = _get_debug_atlas_name()
		atlas_img.save_png("user://%s.png" % debug_name)
		print("%s saved (size: %dx%d, %d tiles)" % [debug_name, atlas_img.get_width(), atlas_img.get_height(), tile_order.size()])

	# Create all tiles in atlas
	for i in range(tile_order.size()):
		var coords = Vector2i(i % atlas_cols, i / atlas_cols)
		atlas.create_tile(coords)

	# Add the atlas source to the tileset BEFORE setting collision data
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
