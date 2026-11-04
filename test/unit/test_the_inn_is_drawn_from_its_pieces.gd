extends GutTest

## struktured 2026-11-01 (via cowir-main 21319/21370): interiors to the outdoor standard, the inn first. Harmonia's inn is
## drawn from pieces cut from its approved style tile; the hearth is the drawn fire box and must land WHOLE on its cells.

const InnInteriorScript := preload("res://src/maps/interiors/InnInterior.gd")
const KINDS := ["floor", "wall", "hearth", "back_wall"]
const HEARTH_SOURCE := 2
const HEARTH_AT := Vector2i(12, 2)
const HEARTH_SIZE := Vector2i(3, 2)


func after_each() -> void:
	VillageProp.prop_art_override = null


func test_harmonias_inn_resolves_every_piece_to_its_own_art() -> void:
	for kind in KINDS:
		assert_eq(InteriorArt.path(kind, "inn", "harmonia"), "res://assets/sprites/interiors/harmonia/%s_inn.png" % kind, "the inn's %s is not drawn" % kind)
	assert_eq(InteriorArt.path("hearth", "inn", "frosthold"), "", "another village was handed Harmonia's hearth")


func _layout_has_hearth_at(at: Vector2i, size: Vector2i) -> bool:
	for y in range(at.y, at.y + size.y):
		for x in range(at.x, at.x + size.x):
			if InnInteriorScript.INN_LAYOUT[y][x] != "h":
				return false
	return true


func _seam_cost(src: Image, origin: Vector2i, size: Vector2i, grid: Vector2i) -> float:
	var img := Image.create(size.x * 32, size.y * 32, false, Image.FORMAT_RGBA8)
	## blit_rect needs matching formats and copies NOTHING otherwise, which reads as zero seams on every sampling.
	src = src.duplicate()
	src.convert(Image.FORMAT_RGBA8)
	for y in range(size.y):
		for x in range(size.x):
			var c := Vector2i(posmod(origin.x + x, grid.x), posmod(origin.y + y, grid.y))
			img.blit_rect(src, Rect2i(c * 32, Vector2i(32, 32)), Vector2i(x, y) * 32)
	var cost := 0.0
	for bx in range(1, size.x):
		for py in range(img.get_height()):
			var a := img.get_pixel(bx * 32 - 1, py)
			var b := img.get_pixel(bx * 32, py)
			cost += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	for by in range(1, size.y):
		for px in range(img.get_width()):
			var a := img.get_pixel(px, by * 32 - 1)
			var b := img.get_pixel(px, by * 32)
			cost += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	return cost


func test_the_drawn_hearth_lands_whole_on_its_cells() -> void:
	assert_true(_layout_has_hearth_at(HEARTH_AT, HEARTH_SIZE), "CONTROL: INN_LAYOUT still puts the hearth at %s" % HEARTH_AT)
	VillageProp.prop_art_override = {"hearth_inn": {"path": "res://assets/sprites/interiors/harmonia/hearth_inn.png"}}
	var inn = InnInteriorScript.new()
	add_child_autofree(inn)
	var src := inn.tilemap.tile_set.get_source(HEARTH_SOURCE) as TileSetAtlasSource
	var grid := src.get_atlas_grid_size()
	assert_eq(grid, HEARTH_SIZE, "the hearth is not one 3x2 drawn piece")
	var img := src.texture.get_image()
	var as_sampled := InteriorArt.cell_in(inn.tilemap, HEARTH_SOURCE, HEARTH_AT)
	var whole := _seam_cost(img, as_sampled, HEARTH_SIZE, grid)
	var shifted := _seam_cost(img, as_sampled + Vector2i(1, 0), HEARTH_SIZE, grid)
	assert_lt(whole, shifted * 0.8, "the hearth does not land whole (seams %.0f vs %.0f one cell off)" % [whole, shifted])


func test_a_drawn_hearth_is_the_only_fireplace() -> void:
	## The 2026-11-04 render: Harmonia's inn stood the painted stone surround and flame BESIDE its drawn hearth, two fireplaces.
	VillageProp.prop_art_override = {}
	var painted = InnInteriorScript.new()
	add_child_autofree(painted)
	assert_gt(painted.find_child("FireplaceSurround", true, false).find_children("*", "Sprite2D", false, false).size(), 0, "CONTROL: a painted inn stands its painted surround")
	assert_not_null(painted.find_child("FireFlame", false, false), "CONTROL: a painted inn burns its painted flame")
	VillageProp.prop_art_override = {"hearth_inn": {"path": "res://assets/sprites/interiors/harmonia/hearth_inn.png"}}
	var inn = InnInteriorScript.new()
	add_child_autofree(inn)
	assert_eq(inn.find_child("FireplaceSurround", true, false).find_children("*", "Sprite2D", false, false).size(), 0, "a painted surround stood beside the drawn hearth")
	assert_null(inn.find_child("FireFlame", false, false), "a painted flame burned beside the drawn hearth's own fire")
	assert_not_null(inn.find_child("HearthCollision", true, false), "the drawn hearth lost its collider")
