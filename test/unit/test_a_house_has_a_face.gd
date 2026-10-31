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


func test_no_facade_covers_a_building_that_already_has_a_face() -> void:
	## THE REGRESSION: the first pass painted over the Inn's cottage. Judged by ART, not origin: the bar sits beside its block.
	var v := _village()
	var checked: int = 0
	for b in v.buildings.get_children():
		if not (b is Node2D) or b is AreaTransition:
			continue
		var art: Rect2i = v._building_cells(b)
		checked += 1
		for f in _facades(v):
			var r := _covered(f).grow_individual(0, 0, 0, 1)
			assert_false(r.intersects(art), "facade %s covers %s's art %s" % [str(r), b.name, str(art)])
	assert_gt(checked, 3, "no art-bearing buildings were checked")


func _door(v: Node, door_name: String) -> Node2D:
	return v.buildings.get_node_or_null(door_name) as Node2D


func _facade_fronted_by(v: Node, door: Node2D) -> VillageProp:
	var cell := Vector2i(floori(door.position.x / 32.0), floori(door.position.y / 32.0))
	for f in _facades(v):
		var r := _covered(f)
		if Rect2i(r.position.x, r.position.y + r.size.y, r.size.x, 1).has_point(cell):
			return f
	return null


func test_a_door_block_is_faced_and_its_door_draws_on_the_front() -> void:
	## struktured wants the elevation on the door blocks too; the door must sort AFTER its facade or the arch is hidden.
	var v := _village()
	assert_true(v.buildings.y_sort_enabled, "Buildings is not y-sorted, so every door sorts at y=0 behind every facade")
	for door_name in ["LibraryDoor", "ChapelDoor", "CartographerDoor"]:
		var door := _door(v, door_name)
		assert_not_null(door, "%s is missing" % door_name)
		if door == null:
			continue
		var f := _facade_fronted_by(v, door)
		assert_not_null(f, "%s's block has no facade" % door_name)
		if f != null:
			assert_gt(door.global_position.y, f.global_position.y, "%s sorts before its facade and is drawn under it" % door_name)


func test_a_building_sorts_by_its_base_without_moving_on_screen() -> void:
	## The art is centred on the node, so sorting by the node put a villager below its middle BEHIND the shop.
	var v := _village()
	var checked: int = 0
	for b in v.buildings.get_children():
		var spr = b.get("sprite") if b is Node2D else null
		if not (spr is Sprite2D) or spr.texture == null:
			continue
		var r: Rect2 = spr.get_rect()
		r.position += spr.position
		assert_true(b.y_sort_enabled, "%s does not let its sprite sort on its own key" % b.name)
		assert_almost_eq(spr.position.y, r.end.y, 0.5, "%s sorts at %.1f, not its art's base %.1f" % [b.name, spr.position.y, r.end.y])
		assert_almost_eq(r.get_center().y, 0.0, 0.5, "%s's art moved on screen" % b.name)
		checked += 1
	assert_gt(checked, 3, "no sprite-bearing buildings were checked")


func test_every_facade_leaves_its_ground_row_alone() -> void:
	## Entrances live on a block's bottom row, so the art stops one row above it.
	var v := _village()
	for f in _facades(v):
		var r := _covered(f)
		var below: int = r.position.y + r.size.y
		var row: String = v._map_rows[below]
		assert_true("HIAPGB".contains(row[r.position.x]),
			"the row under facade %s is not its block's ground row (glyph '%s')" % [str(r), row[r.position.x]])


func test_a_flat_roofed_world_still_stands_up() -> void:
	## Desert, factory and neon blocks have flat roofs; the lit roof PLANE sits inset, so the corners above it stay empty.
	for style in ["adobe", "corrugated", "neon"]:
		var p := VillageProp.create(VillageProp.Kind.HOUSE, Vector2i(0, 0))
		p.size_tiles = Vector2i(3, 4)
		p.house_style = style
		add_child_autofree(p)
		var img := _image(p)
		var w := img.get_width()
		assert_almost_eq(img.get_pixel(0, 0).a, 0.0, 0.01, "%s: the top-left corner is filled, a band not a roof" % style)
		assert_almost_eq(img.get_pixel(w - 1, 0).a, 0.0, 0.01, "%s: the top-right corner is filled" % style)
		assert_gt(img.get_pixel(w / 2, 1).a, 0.9, "%s: no roof plane" % style)
		assert_gt(img.get_pixel(0, img.get_height() - 1).a, 0.9, "%s: the front wall does not reach the base" % style)


func _glyph_cells(v: Node, glyph: String) -> Array:
	var out: Array = []
	for y in range(v._map_rows.size()):
		var row: String = v._map_rows[y]
		for x in range(row.length()):
			if row[x] == glyph:
				out.append(Vector2i(x, y))
	return out


func test_a_secret_or_a_barrier_is_never_given_a_face() -> void:
	## Sandrift's T is a HIDDEN tent with a chest in it; NodePrime's F is a firewall, not a building.
	for pair in [["res://src/maps/villages/SandriftVillage.gd", "T"], ["res://src/maps/villages/NodePrimeVillage.gd", "F"]]:
		var v = load(pair[0]).new()
		add_child_autofree(v)
		var cells := _glyph_cells(v, pair[1])
		assert_gt(cells.size(), 0, "CONTROL: %s still has its '%s' block" % [pair[0].get_file(), pair[1]])
		for f in _facades(v):
			var r := _covered(f).grow_individual(0, 0, 0, 1)
			for c in cells:
				assert_false(r.has_point(c), "%s faced its '%s' block at %s" % [pair[0].get_file(), pair[1], str(c)])


func test_no_village_faces_over_a_buildings_art() -> void:
	## The same contract as Harmonia's arm, across every village that calls _spawn_house_facades.
	var faced: int = 0
	for f in DirAccess.get_files_at("res://src/maps/villages"):
		if not f.ends_with("Village.gd") or f == "BaseVillage.gd":
			continue
		var v = load("res://src/maps/villages/" + f).new()
		add_child_autofree(v)
		for h in _facades(v):
			faced += 1
			var r := _covered(h).grow_individual(0, 0, 0, 1)
			for b in v.buildings.get_children():
				if b is Node2D and not (b is AreaTransition):
					assert_false(r.intersects(v._building_cells(b)), "%s: facade %s covers %s" % [f, str(r), b.name])
	assert_gt(faced, 5, "CONTROL: facades were built across the villages (%d)" % faced)
