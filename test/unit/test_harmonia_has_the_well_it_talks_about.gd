extends GutTest

## Six shipped lines put a well in Harmonia (Phil the Lost sits at it; "Look east. Past the well.") and the square drew
## none; its "Stone Well" examine was an invisible hotspot seven cells from Phil (main 24238). The text stays: the village
## gets its well, and the examine is read at it.

const VP := preload("res://src/exploration/VillageProp.gd")
const Harmonia := preload("res://src/maps/villages/HarmoniaVillage.gd")
const TILE := 32
const N4: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _village() -> Node:
	var v: Node = Harmonia.new()
	add_child_autofree(v)
	await get_tree().process_frame
	return v


func _well(v: Node) -> Node:
	for p in v.props.get_children():
		if p.get("kind") == VP.Kind.WELL:
			return p
	return null


func _cell(n: Node2D) -> Vector2i:
	return Vector2i(int(floor(n.position.x / TILE)), int(floor(n.position.y / TILE)))


func _named(v: Node, wanted: String) -> Node2D:
	for n in v.npcs.get_children():
		if str(n.name) == wanted or str(n.get("npc_name")) == wanted:
			return n
	return null


## Every cell reachable on foot from the arrival spawn, with `opened` cells treated as walkable.
func _reach(v: Node, opened: Array = []) -> Dictionary:
	var start := Vector2i(v.spawn_points["default"] / float(TILE))
	var seen := {start: true}
	var queue: Array = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in N4:
			var n: Vector2i = c + d
			if not seen.has(n) and (v._is_cell_walkable(n) or opened.has(n)):
				seen[n] = true
				queue.append(n)
	return seen


func test_harmonia_draws_a_well_where_its_text_puts_one() -> void:
	var v: Node = await _village()
	var well := _well(v)
	assert_not_null(well, "Harmonia places a Kind.WELL prop")
	if well == null:
		return
	var foot: Array = well.footprint_cells(Harmonia.WELL_CELL)
	assert_gt(foot.size(), 0, "CONTROL: a well has a footprint")
	for c in foot:
		assert_false(v._is_cell_walkable(c), "the well's cell %s is solid" % str(c))
	var phil := _named(v, "Phil the Lost")
	assert_not_null(phil, "CONTROL: Phil the Lost is in the square")
	if phil == null:
		return
	var near := 99
	for c in foot:
		near = mini(near, maxi(absi(c.x - _cell(phil).x), absi(c.y - _cell(phil).y)))
	assert_lte(near, 2, "Phil sits AT the well: within two cells of its kerb (he is %d away)" % near)


func test_the_well_blocks_no_road_and_cuts_nothing_off() -> void:
	var v: Node = await _village()
	var well := _well(v)
	if well == null:
		fail_test("no well to judge")
		return
	var foot: Array = well.footprint_cells(Harmonia.WELL_CELL)
	var with_well := _reach(v)
	var without := _reach(v, foot)
	assert_gt(with_well.size(), 100, "CONTROL: the square is walkable from the gate (%d cells)" % with_well.size())
	for c in without:
		if not foot.has(c):
			assert_true(with_well.has(c), "cell %s was reachable before the well stood there" % str(c))
	for c in foot:
		assert_true(v._is_cell_walkable(c + Vector2i(0, 1)), "the road cell south of the well %s stays open" % str(c + Vector2i(0, 1)))


func test_the_stone_well_is_read_at_the_drawn_well() -> void:
	var v: Node = await _village()
	var well := _well(v)
	var examine := _named(v, "Examine_harmonia_well")
	assert_not_null(examine, "CONTROL: the Stone Well examine is placed")
	if well == null or examine == null:
		return
	var foot: Array = well.footprint_cells(Harmonia.WELL_CELL)
	assert_true(foot.has(_cell(examine)), "the Stone Well text is on the well's own cell, not %s" % str(_cell(examine)))
	var reach := _reach(v)
	var approach := false
	for d in N4:
		if reach.has(_cell(examine) + d):
			approach = true
	assert_true(approach, "and a player can stand beside it")
	var statue := _named(v, "Examine_harmonia_statue")
	assert_not_null(statue, "CONTROL: an examine with no drawn thing is still placed by its offset")
	if statue != null:
		assert_true(v._is_cell_walkable(_cell(statue)), "CONTROL: and that one still lands on a walkable cell")


func test_phil_his_notebook_and_the_chicken_keep_their_places() -> void:
	var v: Node = await _village()
	var reach := _reach(v)
	for wanted in ["Phil the Lost", "PhilNotebook"]:
		var n := _named(v, wanted)
		assert_not_null(n, "CONTROL: %s is in the square" % wanted)
		if n == null:
			continue
		var ok := reach.has(_cell(n))
		for d in N4:
			ok = ok or reach.has(_cell(n) + d)
		assert_true(ok, "%s at %s can still be walked up to" % [wanted, str(_cell(n))])
	var phil := _named(v, "Phil the Lost")
	if phil != null:
		assert_eq(phil.position, Vector2(28 * TILE, 21 * TILE), "Phil stands where he was authored")
