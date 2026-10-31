extends GutTest

## struktured, 2026-10-30, on a SNES town: "I want some of that feel at least". The feel is the facade --
## a roof and wall drawn UP from a building's footprint -- not the pixels. Harmonia's buildings were flat
## blocks of WALL tiles. The first pass faced every block and hid the library door's banner and covered
## the Inn's cottage, so the regression arms here are the ones that matter most.

const HARMONIA := "res://src/maps/villages/HarmoniaVillage.tscn"


func _house(size: Vector2i, peaked: bool) -> VillageProp:
	var p := VillageProp.create(VillageProp.Kind.HOUSE, Vector2i(0, 0))
	p.size_tiles = size
	p.roof_peaked = peaked
	add_child_autofree(p)
	return p


func _image(p: VillageProp) -> Image:
	return (p.get_node("Sprite") as Sprite2D).texture.get_image()


func test_a_house_is_sized_by_its_block_not_by_the_kind_default() -> void:
	var img := _image(_house(Vector2i(4, 3), false))
	assert_eq(Vector2i(img.get_width(), img.get_height()), Vector2i(4 * 32, 3 * 32),
		"size_tiles did not override SIZES[HOUSE]")


func test_a_house_adds_no_collider_of_its_own() -> void:
	## Its cells already collide as WALL tiles; a second body would be two sources for one fact.
	var p := _house(Vector2i(3, 3), false)
	assert_eq(p.footprint_cells(Vector2i.ZERO).size(), 0, "HOUSE grew a footprint")
	for c in p.get_children():
		assert_false(c is StaticBody2D, "HOUSE built a StaticBody2D")


func test_the_roof_is_pitched_not_a_band() -> void:
	## A flat rectangle of stripes read as an awning. The top corners must be EMPTY -- that is the silhouette.
	for peaked in [false, true]:
		var img := _image(_house(Vector2i(3, 3), peaked))
		var w := img.get_width()
		assert_almost_eq(img.get_pixel(0, 0).a, 0.0, 0.01, "top-left corner is filled (peaked=%s)" % str(peaked))
		assert_almost_eq(img.get_pixel(w - 1, 0).a, 0.0, 0.01, "top-right corner is filled (peaked=%s)" % str(peaked))
		assert_gt(img.get_pixel(w / 2, 1).a, 0.9, "the ridge is empty (peaked=%s)" % str(peaked))


func test_a_band_roof_would_fail_that_arm() -> void:
	## CONTROL: a full-width fill -- what the first draft painted -- must flunk the corner check.
	var flat := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.72, 0.20, 0.18))
	assert_gt(flat.get_pixel(0, 0).a, 0.01, "the corner predicate cannot see a band roof")


func _village() -> Node:
	var v = load(HARMONIA).instantiate()
	add_child_autofree(v)
	return v


func _facades(v: Node) -> Array:
	var out: Array = []
	for c in v.props.get_children():
		if c is VillageProp and c.kind == VillageProp.Kind.HOUSE:
			out.append(c)
	return out


## The cells a facade's art covers: size_tiles wide from its base column, size_tiles tall UP from its base row.
func _covered(f: VillageProp) -> Rect2i:
	var base := Vector2i(floori(f.position.x / 32.0), floori(f.position.y / 32.0) - 1)
	return Rect2i(base.x, base.y - f.size_tiles.y + 1, f.size_tiles.x, f.size_tiles.y)


func test_harmonia_has_faced_houses() -> void:
	## Floor: without it every arm below passes on a village that faced nothing.
	assert_gt(_facades(_village()).size(), 0, "Harmonia built no facades at all")


func test_no_facade_covers_a_door_or_an_existing_building() -> void:
	## THE REGRESSION: the first pass hid the library door's banner and painted over the Inn's cottage.
	var v := _village()
	for f in _facades(v):
		var r := _covered(f)
		for b in v.buildings.get_children():
			if not (b is Node2D):
				continue
			var cell := Vector2i(floori(b.position.x / 32.0), floori(b.position.y / 32.0))
			assert_false(r.grow_individual(0, 0, 0, 1).has_point(cell),
				"facade %s covers building node %s at %s" % [str(r), b.name, str(cell)])


func test_every_facade_leaves_its_ground_row_alone() -> void:
	## Entrances live on a block's bottom row, so the art stops one row above it.
	var v := _village()
	for f in _facades(v):
		var r := _covered(f)
		var below: int = r.position.y + r.size.y
		var row: String = v._map_rows[below]
		assert_true("HIAPGB".contains(row[r.position.x]),
			"the row under facade %s is not its block's ground row (glyph '%s')" % [str(r), row[r.position.x]])
