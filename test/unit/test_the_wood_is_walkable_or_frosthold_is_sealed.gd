extends GutTest

## SNOW_TREE is the second finished tile in the medieval generator that no map painted. It carries a
## palette, `_draw_snow_tree`, atlas slot 22 and a 0.5 entry in `_get_rough_terrain_speeds()` — and
## the character was named by nothing in `src/`. A census over all six generators found exactly one
## such type per generator's worth of checking; this was the medieval one.
##
## It is now Frosthold's treeline. Frosthold was 73% bare `.` — the emptiest village in the game,
## a snowbound settlement with no snow and no trees.
##
## ⛔ WHY THIS FILE EXISTS, and it is NOT "does the tile appear". The wood is 134 cells wrapped
## around the village margin. `_get_impassable_types()` is a single `return [...]` in the shared
## generator that six worlds read, and one entry added to it turns every one into a wall at once —
## sealing Frosthold's margins, its two chests and its lamp posts behind a ring of scenery. That
## edit would look like tidying. MEASURED, not assumed — with SNOW_TREE added to that return, these
## five all stay GREEN and only this file reds:
##     village_global_reachability 1 · a_chest_you_cannot_walk_to 5 · village_grid_agrees_with_physics 1
##     village_placement_walkability 2 · frosthold_elevation_regression 4
## The flood reports the smaller village as healthy because every building, NPC and door sits in the
## cleared core, and grid-vs-physics agrees with itself either way.
##
## 🔑 So the load-bearing claim is the NEGATIVE one — the wood must stay walkable — and it is
## derived from the generator's own return, never a hand-list.

const VGS := preload("res://test/unit/helpers/village_grid_source.gd")
const FROSTHOLD := "res://src/maps/villages/FrostholdVillage.gd"
const TILE := 32.0
const TREE := "T"


func _rows() -> Array:
	var src := FileAccess.get_file_as_string(FROSTHOLD)
	assert_gt(src.length(), 1000, "PRECONDITION: FrostholdVillage must be readable")
	var rows: Array = VGS.rows(src)
	assert_gt(rows.size(), 15, "PRECONDITION: the map_data parser must return real rows")
	return rows


func _tree_cells() -> Array:
	var out: Array = []
	var rows := _rows()
	for y in range(rows.size()):
		var row := str(rows[y])
		for x in range(row.length()):
			if row[x] == TREE:
				out.append(Vector2i(x, y))
	return out


## THE TILE IS ON SCREEN. Source-level: a runtime check cannot tell "drawn" from "declared".
func test_frosthold_paints_the_snow_tree() -> void:
	var trees := _tree_cells().size()
	assert_gt(trees, 120,
		"Frosthold paints %d snow-tree cells; the authored treeline is 134. The tile was finished " % trees +
		"— palette, draw, atlas slot, terrain-speed entry — and painted nowhere for months. If this " +
		"falls back toward zero it has gone dead again.")
	# CONTROL: the counter must be able to report a character ABSENT.
	var absent := 0
	for r in _rows():
		absent += str(r).count("Q")
	assert_eq(absent, 0, "CONTROL: an unused legend char must count zero")


## THE LOAD-BEARING ARM. One entry added to the shared generator's impassable return walls off the
## whole wood in a single edit, and the reachability flood would call the smaller village healthy.
func test_the_wood_is_walkable_not_a_wall() -> void:
	var src := FileAccess.get_file_as_string(FROSTHOLD)
	var blocked: Dictionary = VGS.blocked_chars(src, [])
	assert_false(blocked.has(TREE),
		"'T' must NOT be a blocking char. SNOW_TREE is scenery you walk through; adding it to the " +
		"medieval generator's _get_impassable_types() seals Frosthold's whole margin — both chests, " +
		"four lamp posts and every tree cell — and five other village guards stay green through it.")
	assert_true(blocked.has("W"), "CONTROL present: the stone wall must block")
	assert_false(blocked.has("."), "CONTROL absent: the cleared floor must not block")


## RUNTIME. The source legend says walkable; the built village must agree, and the wood must be
## somewhere a player can actually get to rather than scenery behind a wall.
func test_the_player_can_walk_into_the_wood() -> void:
	var trees := _tree_cells()
	assert_gt(trees.size(), 120, "PRECONDITION: there must be a wood to walk into")

	var v = load(FROSTHOLD).new()
	add_child(v)
	await get_tree().process_frame
	await get_tree().process_frame

	var walkable := 0
	for cell in trees:
		if v._is_cell_walkable(cell):
			walkable += 1
	assert_eq(walkable, trees.size(),
		"every one of the %d tree cells must be walkable at runtime; %d were not, so the source " % [trees.size(), trees.size() - walkable] +
		"legend and the built collision disagree")

	# Reachable, not merely walkable — the distinction that hid two dragon bosses in sealed enclaves.
	var spawn: Vector2 = v.spawn_points.get("default", Vector2.ZERO)
	var start := Vector2i(int(floor(spawn.x / TILE)), int(floor(spawn.y / TILE)))
	assert_true(v._is_cell_walkable(start), "PRECONDITION: the spawn cell must be walkable")
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + step
			if seen.has(n):
				continue
			if v._can_step(cur, n):
				seen[n] = true
				queue.append(n)
	assert_gt(seen.size(), 200, "CONTROL: the flood must be healthy, or the arm below is vacuous")
	var reached := 0
	for cell in trees:
		if seen.has(cell):
			reached += 1
	assert_gt(reached, 120,
		"only %d of %d tree cells are reachable from the spawn — a wood the player cannot enter is " % [reached, trees.size()] +
		"a painted wall")
	v.queue_free()
