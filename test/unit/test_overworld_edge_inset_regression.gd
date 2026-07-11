extends GutTest

## Overworld edge-detection regression (live playtest 2026-07-11, msg 2360:
## "the edge detection is not great in overworld still"). Boundary walls were
## flush with the map pixel edge, so under Mode 7 the player sprite clipped
## past the rendered terrain edge before physics stopped it. All six worlds
## now stop the player one tile inside (edge_inset). The companion invariant:
## no spawn point may sit within the inset margin, or arriving players would
## materialize inside the new walls (steampunk_portal at y=1.5 tiles is the
## closest legal case — 16px clearance).

const WORLDS := [
	"res://src/exploration/OverworldScene.gd",
	"res://src/exploration/SuburbanOverworld.gd",
	"res://src/exploration/SteampunkOverworld.gd",
	"res://src/exploration/IndustrialOverworld.gd",
	"res://src/exploration/FuturisticOverworld.gd",
	"res://src/exploration/AbstractOverworld.gd",
]

## Spawns must keep at least this many tiles from the map edge: 1 (inset)
## plus half a tile of player clearance.
const MIN_SPAWN_TILES := 1.4


func test_all_worlds_use_inset_boundaries() -> void:
	for path in WORLDS:
		var src: String = FileAccess.get_file_as_string(path)
		assert_ne(src, "", "%s readable" % path)
		var fn_start := src.find("func _create_map_boundaries")
		assert_gt(fn_start, 0, "%s builds map boundaries" % path)
		var fn := src.substr(fn_start, 900)
		assert_true(fn.contains("var edge_inset"), "%s declares edge_inset" % path)
		var uses := fn.count("edge_inset") - 1
		assert_eq(uses, 4, "%s applies edge_inset to all four walls (got %d)" % [path, uses])
		assert_false(fn.contains("Vector2(map_w / 2, -wall_thickness / 2)"),
			"%s must not keep a flush top wall" % path)


func test_no_spawn_point_inside_the_inset_margin() -> void:
	var spawn_re := RegEx.create_from_string(
		"spawn_points\\[\"[^\"]+\"\\]\\s*=\\s*Vector2\\(\\s*(\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^,]*,\\s*(\\d+(?:\\.\\d+)?)\\s*\\*\\s*TILE_SIZE[^)]*\\)")
	var dim_re := RegEx.create_from_string("const MAP_WIDTH: int = (\\d+)[\\s\\S]*?const MAP_HEIGHT: int = (\\d+)")
	for path in WORLDS:
		var src: String = FileAccess.get_file_as_string(path)
		var dims := dim_re.search(src)
		assert_not_null(dims, "%s declares map dims" % path)
		var mw := float(dims.get_string(1))
		var mh := float(dims.get_string(2))
		for m in spawn_re.search_all(src):
			var sx := float(m.get_string(1)) + 0.5
			var sy := float(m.get_string(2)) + 0.5
			assert_true(
				sx >= MIN_SPAWN_TILES and sx <= mw - MIN_SPAWN_TILES \
				and sy >= MIN_SPAWN_TILES and sy <= mh - MIN_SPAWN_TILES,
				"%s spawn at (%s,%s) sits inside the edge-inset margin of a %sx%s map" % [
					path, sx, sy, mw, mh])