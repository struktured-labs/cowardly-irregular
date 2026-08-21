extends GutTest

## Stairs slow you through the player's REAL terrain-speed path (spec: 0.6, same scale as
## mud/snow), and a parent that is not a village keeps the legacy lookup untouched.

const TILE := 32
const PlayerScript := preload("res://src/exploration/OverworldPlayer.gd")


class StairVillage extends BaseVillage:
	func _get_area_id() -> String: return "stair_speed_village"
	func _get_map_pixel_size() -> Vector2i: return Vector2i(5 * TILE_SIZE, 5 * TILE_SIZE)
	func _generate_map() -> void:
		var layout := ["WWWWW", "WgggW", "Wg^gW", "WgggW", "WWWWW"]
		for y in range(5):
			for x in range(5):
				var t: int = TileGeneratorScript.TileType.WALL if layout[y][x] == "W" else TileGeneratorScript.TileType.VILLAGE_GRASS
				tile_map.set_cell(Vector2i(x, y), 0, TileGeneratorScript.get_atlas_coords_for_id(TileGeneratorScript.get_tile_id(t)))
		spawn_points["default"] = Vector2(1.5 * TILE, 1.5 * TILE)
		_build_derived_layers(layout, ["00000", "02220", "01110", "01110", "00000"])


func test_village_reports_stair_speed_only_on_stair_cells() -> void:
	var v := StairVillage.new()
	add_child_autofree(v)
	assert_almost_eq(v.get_terrain_speed_at(Vector2(2.5 * TILE, 2.5 * TILE)), 0.6, 0.001, "stair cell")
	assert_almost_eq(v.get_terrain_speed_at(Vector2(1.5 * TILE, 1.5 * TILE)), 1.0, 0.001, "plain grass")
	assert_almost_eq(BaseVillage.STAIR_SPEED, 0.6, 0.001, "spec value")


func test_player_inside_a_village_uses_the_village_seam() -> void:
	var v := StairVillage.new()
	add_child_autofree(v)
	v.player.position = Vector2(2.5 * TILE, 2.5 * TILE)
	assert_almost_eq(v.player._get_terrain_speed_modifier(), 0.6, 0.001, "player on the stair is slowed")
	v.player.position = Vector2(3.5 * TILE, 3.5 * TILE)
	assert_almost_eq(v.player._get_terrain_speed_modifier(), 1.0, 0.001, "player off the stair is not")


func test_player_under_a_plain_node_keeps_legacy_path() -> void:
	var host := Node2D.new()
	add_child_autofree(host)
	var p := PlayerScript.new()
	host.add_child(p)
	assert_almost_eq(p._get_terrain_speed_modifier(), 1.0, 0.001, "no tile_generator, no village: legacy default")
