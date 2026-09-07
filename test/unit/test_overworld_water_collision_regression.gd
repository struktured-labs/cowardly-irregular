extends GutTest

## Directive #12 (2026-07-01): overworld collision detection for water and
## mountain-edge terrain was not properly implemented.
##
## Baseline bug: each non-medieval tile generator overrode
## `_get_impassable_types()` with its own list and — because these lists were
## drafted independently per world — several water-analogue tiles were
## silently omitted, letting the player walk on them:
##
##   - Steampunk: WATER_FEATURE (fountain / pond) — omitted, walkable
##   - Industrial: DRAINAGE_CHANNEL ("green-tinted water channel") — omitted
##   - Futuristic: VOID_FLOOR ("near-black floor hinting at the abyss below")
##     — omitted
##   - Medieval (base): VILLAGE_HEDGE — HarmoniaVillage's layout comment
##     explicitly said "impassable decorative border" but the tile was
##     missing from the impassable set. Any village that placed hedges
##     as a boundary let the player walk through them.
##
## This test guards each generator's impassable list so a future refactor
## that touches the enum or the override can't silently drop these tiles.


const TileGeneratorScript := preload("res://src/exploration/TileGenerator.gd")
const SteampunkTileGeneratorScript := preload("res://src/exploration/SteampunkTileGenerator.gd")
const IndustrialTileGeneratorScript := preload("res://src/exploration/IndustrialTileGenerator.gd")
const FuturisticTileGeneratorScript := preload("res://src/exploration/FuturisticTileGenerator.gd")
const AbstractTileGeneratorScript := preload("res://src/exploration/AbstractTileGenerator.gd")
const SuburbanTileGeneratorScript := preload("res://src/exploration/SuburbanTileGenerator.gd")


func test_medieval_water_mountain_lava_hedge_are_impassable() -> void:
	var gen = TileGeneratorScript.new()
	var impassable = gen.call("_get_impassable_types")
	assert_true(gen.TileType.WATER in impassable,
		"Medieval WATER must be impassable — player should not walk on lakes/rivers.")
	assert_true(gen.TileType.MOUNTAIN in impassable,
		"Medieval MOUNTAIN must be impassable.")
	assert_true(gen.TileType.LAVA in impassable,
		"Medieval LAVA must be impassable.")
	assert_true(gen.TileType.VILLAGE_HEDGE in impassable,
		"Medieval VILLAGE_HEDGE must be impassable — HarmoniaVillage relies on this for its decorative border.")


func test_steampunk_water_feature_is_impassable() -> void:
	var gen = SteampunkTileGeneratorScript.new()
	var impassable = gen.call("_get_impassable_types")
	assert_true(gen.TileType.WATER_FEATURE in impassable,
		"Steampunk WATER_FEATURE (fountain/pond) must be impassable — analogue of medieval WATER.")


func test_industrial_drainage_channel_is_impassable() -> void:
	var gen = IndustrialTileGeneratorScript.new()
	var impassable = gen.call("_get_impassable_types")
	assert_true(gen.TileType.DRAINAGE_CHANNEL in impassable,
		"Industrial DRAINAGE_CHANNEL (green-tinted water channel) must be impassable.")


func test_futuristic_void_floor_is_impassable() -> void:
	var gen = FuturisticTileGeneratorScript.new()
	var impassable = gen.call("_get_impassable_types")
	assert_true(gen.TileType.VOID_FLOOR in impassable,
		"Futuristic VOID_FLOOR (abyss below) must be impassable — analogue of Abstract VOID_BLACK.")


func test_abstract_void_black_still_impassable() -> void:
	# Regression guard: this was already correct on baseline; assert it stays.
	var gen = AbstractTileGeneratorScript.new()
	var impassable = gen.call("_get_impassable_types")
	assert_true(gen.TileType.VOID_BLACK in impassable,
		"Abstract VOID_BLACK must be impassable (deep void).")


func test_suburban_impassable_covers_all_wall_tiles() -> void:
	# Suburban has no water/lava-analogue tile in its enum — the correctness
	# concern here is coverage of the tiles annotated (impassable) in the
	# enum's own comments.
	var gen = SuburbanTileGeneratorScript.new()
	var impassable = gen.call("_get_impassable_types")
	var must_block = [
		gen.TileType.HOUSE_WALL, gen.TileType.STORE_FRONT, gen.TileType.HOUSE_WINDOW,
		gen.TileType.PICKET_FENCE, gen.TileType.MAILBOX, gen.TileType.FIRE_HYDRANT,
		gen.TileType.SHADE_TREE, gen.TileType.PARK_BENCH,
	]
	for tile in must_block:
		assert_true(tile in impassable, "Suburban tile %d must be impassable per enum comment." % tile)
