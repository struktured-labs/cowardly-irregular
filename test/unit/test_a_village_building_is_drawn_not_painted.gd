extends GutTest

## struktured 2026-11-01: "did the village changes land with the buildings redrawn? i dont see anything substantial".
## The shipped facades were procedural (VillageProp paints a flat roof and wall), and the blocks the shops' stalls
## claimed stayed bare stone. Harmonia now draws every building from manifest building_art (T1, gpt-image-2, the
## straight-on direction he picked): BaseVillage._spawn_building_art places it bottom-aligned on each block.
## The corpus is DERIVED from Harmonia's own map (every building-glyph block), not from the art list, so a block
## added later without art reds here instead of silently staying procedural.

const VILLAGE := "res://src/maps/villages/HarmoniaVillage.gd"
const BUILDING_GLYPHS := "HIAPGB"


func _built(path: String) -> Node:
	var vp := SubViewport.new()
	vp.world_2d = World2D.new()
	add_child_autofree(vp)
	var v = load(path).new()
	vp.add_child(v)
	await get_tree().process_frame
	await get_tree().process_frame
	return v


## Every building block of the map: [Rect2i] in tiles, found by flood fill over each building glyph.
func _blocks(rows: Array) -> Array:
	var out: Array = []
	var seen := {}
	for y in rows.size():
		var row := str(rows[y])
		for x in row.length():
			var g := row[x]
			if not BUILDING_GLYPHS.contains(g) or seen.has(Vector2i(x, y)):
				continue
			var minp := Vector2i(x, y)
			var maxp := Vector2i(x, y)
			var stack := [Vector2i(x, y)]
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				if seen.has(p) or p.y < 0 or p.y >= rows.size() or p.x < 0 or p.x >= str(rows[p.y]).length() or str(rows[p.y])[p.x] != g:
					continue
				seen[p] = true
				minp = Vector2i(mini(minp.x, p.x), mini(minp.y, p.y))
				maxp = Vector2i(maxi(maxp.x, p.x), maxi(maxp.y, p.y))
				stack.append_array([p + Vector2i.RIGHT, p + Vector2i.LEFT, p + Vector2i.DOWN, p + Vector2i.UP])
			out.append(Rect2i(minp, maxp - minp + Vector2i.ONE))
	return out


## The art prop standing on `block`: a VillageProp whose base cell is the block's bottom-left and that carries art.
func _art_on(v: Node, block: Rect2i) -> Node:
	var base := Vector2((block.position.x + 0.5) * 32, (block.end.y) * 32)
	for p in v.props.get_children():
		if str(p.get("art_path")) != "" and p.position.is_equal_approx(base):
			return p
	return null


func test_every_harmonia_building_is_drawn() -> void:
	var v = await _built(VILLAGE)
	var blocks := _blocks(v._map_rows)
	assert_gte(blocks.size(), 8, "FLOOR: Harmonia's building blocks must be found from its map (%d)" % blocks.size())
	var bare: Array = []
	for b in blocks:
		var art = _art_on(v, b)
		if art == null:
			bare.append(str(b))
			continue
		var spr: Sprite2D = art.get_node_or_null("Sprite")
		var drawn: Texture2D = load(str(art.art_path))
		assert_true(spr != null and spr.texture != null and drawn != null, "CONTROL: %s must draw a texture" % b)
		if spr != null and spr.texture != null and drawn != null:
			assert_eq(spr.texture.get_size(), drawn.get_size(), "%s must draw its art, not the procedural paint" % b)
			assert_eq(int(spr.texture.get_width()), b.size.x * 32, "%s's art must span its block exactly" % b)
	assert_eq(bare, [], "these Harmonia buildings fell back to the procedural block: %s" % [bare])


func test_nothing_draws_over_or_doubles_the_art() -> void:
	var v = await _built(VILLAGE)
	assert_gt(v._art_blocks.size(), 0, "CONTROL: the art blocks must be recorded")
	var leaks: Array = []
	var doors := 0
	for n in v.buildings.get_children():
		if n is AreaTransition:
			var cell := Vector2i(floori(n.position.x / 32), floori(n.position.y / 32))
			for r in v._art_blocks:
				if (r as Rect2i).has_point(cell):
					doors += 1
					if n.show_gate_visual:
						leaks.append("%s draws its archway over the art" % n.name)
					if not n.require_interaction:
						leaks.append("%s lost its interaction" % n.name)
			continue
		var spr = n.get("sprite")
		if spr is Sprite2D and (spr as Sprite2D).visible and spr.texture != null:
			var cells: Rect2i = v._building_cells(n)
			for r in v._art_blocks:
				if cells.intersects(r):
					leaks.append("%s's stall sprite still draws over an art block" % n.name)
	assert_gte(doors, 3, "CONTROL: the library, chapel and attic doors must sit on art blocks (%d)" % doors)
	assert_eq(leaks, [], "the art must replace, not be painted over: %s" % [leaks])


func test_a_village_without_art_keeps_its_facades() -> void:
	# CONTROL: the seam is opt-in. A village that lists no building_art still gets the procedural facade.
	var v = await _built("res://src/maps/villages/FrostholdVillage.gd")
	var art := 0
	var painted := 0
	for p in v.props.get_children():
		if p is VillageProp and (p as VillageProp).kind == VillageProp.Kind.HOUSE:
			if str(p.art_path) != "":
				art += 1
			else:
				painted += 1
	assert_eq(art, 0, "a village with no building_art must not grow drawn art")
	assert_gt(painted, 0, "and it must still draw its procedural facades")
