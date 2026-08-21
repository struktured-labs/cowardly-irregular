extends GutTest

## Props are the first thing in a village the player can walk BEHIND. Pins: the containers
## are Y-sorted, a prop's origin is the bottom-centre of its base cell, its footprint blocks
## walkability AND physics, and zero-footprint props (banners) block nothing.

const TILE := 32
const VP := preload("res://src/exploration/VillageProp.gd")


class PropVillage extends BaseVillage:
	func _get_area_id() -> String: return "prop_test_village"
	func _get_map_pixel_size() -> Vector2i: return Vector2i(6 * TILE_SIZE, 6 * TILE_SIZE)
	func _generate_map() -> void:
		for y in range(6):
			for x in range(6):
				var wall := x == 0 or y == 0 or x == 5 or y == 5
				var t: int = TileGeneratorScript.TileType.WALL if wall else TileGeneratorScript.TileType.VILLAGE_GRASS
				tile_map.set_cell(Vector2i(x, y), 0, TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id(t)))
		spawn_points["default"] = Vector2(1.5 * TILE, 1.5 * TILE)
	func _setup_buildings() -> void:
		_add_prop(VP.Kind.TREE, Vector2i(2, 2))
		_add_prop(VP.Kind.STALL, Vector2i(3, 4))
		_add_prop(VP.Kind.BANNER, Vector2i(1, 3))


func test_containers_are_y_sorted() -> void:
	var v := PropVillage.new()
	add_child_autofree(v)
	assert_true(v.y_sort_enabled, "village root sorts children by y")
	assert_true(v.props.y_sort_enabled, "props sort among themselves")
	assert_true(v.npcs.y_sort_enabled, "NPCs sort with the player")
	assert_eq(v.props.name, "Props")


func test_prop_origin_is_bottom_centre_of_base_cell() -> void:
	var p := VP.create(VP.Kind.TREE, Vector2i(2, 2))
	assert_eq(p.position, Vector2(2.5 * TILE, 3 * TILE))
	assert_eq(p.footprint_cells(Vector2i(2, 2)), [Vector2i(2, 2)])
	assert_eq(VP.create(VP.Kind.STALL, Vector2i(3, 4)).footprint_cells(Vector2i(3, 4)), [Vector2i(3, 4), Vector2i(4, 4)])
	assert_eq(VP.create(VP.Kind.BANNER, Vector2i(1, 3)).footprint_cells(Vector2i(1, 3)), [])
	p.free()


func test_footprint_blocks_walkability_and_physics() -> void:
	var v := PropVillage.new()
	add_child_autofree(v)
	assert_false(v._is_cell_walkable(Vector2i(2, 2)), "tree trunk cell blocked")
	assert_true(v._is_cell_walkable(Vector2i(2, 1)), "the cell BEHIND the tree stays walkable (canopy only)")
	assert_false(v._is_cell_walkable(Vector2i(4, 4)), "stall second cell blocked")
	assert_true(v._is_cell_walkable(Vector2i(1, 3)), "banner blocks nothing")
	var bodies := 0
	for p in v.props.get_children():
		for c in p.get_children():
			if c is StaticBody2D:
				bodies += 1
				assert_eq((c as StaticBody2D).collision_layer, 1, "props are walls to the player")
	assert_eq(bodies, 2, "tree + stall carry bodies, banner does not")


func test_sprite_extends_upward_from_the_origin() -> void:
	var p := VP.create(VP.Kind.LAMP_POST, Vector2i(1, 1))
	add_child_autofree(p)
	var spr: Sprite2D = p.get_node("Sprite")
	assert_not_null(spr)
	assert_lt(spr.position.y, 0.0, "drawn above the base")
	assert_lt(p.light_anchor.y, -TILE, "lamp head sits at least a tile up")
