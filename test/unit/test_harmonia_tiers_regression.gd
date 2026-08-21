extends GutTest

## Harmonia is the proof map for elevation: castle approach (tier 2) / town (tier 1) /
## market + gate (tier 0). Pins the stair cells, proves both staged scenes still walk legal
## ground, and flood-fills the LIVE village so every NPC is reachable from the entrance.

const HARMONIA_TSCN := "res://src/maps/villages/HarmoniaVillage.tscn"
const TILE := 32
const STAIRS := [Vector2i(11, 8), Vector2i(12, 8), Vector2i(22, 8), Vector2i(23, 8),
	Vector2i(12, 19), Vector2i(13, 19), Vector2i(22, 19), Vector2i(23, 19)]
const SCENES := ["res://data/cutscenes/world1_chapter1.json", "res://data/cutscenes/world1_harmonia_after_cave.json"]

var _v: Node


func before_each() -> void:
	_v = (load(HARMONIA_TSCN) as PackedScene).instantiate()
	add_child_autofree(_v)
	await get_tree().process_frame
	await get_tree().process_frame


func _cell(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


func test_three_tiers_and_eight_stairs() -> void:
	var HG := preload("res://src/exploration/HeightGrid.gd")
	assert_eq(HG.height_at(_v._height_grid, Vector2i(18, 4)), 2, "castle approach")
	assert_eq(HG.height_at(_v._height_grid, Vector2i(18, 13)), 1, "town")
	assert_eq(HG.height_at(_v._height_grid, Vector2i(18, 22)), 0, "market")
	assert_eq(_v._stair_cells.size(), STAIRS.size())
	for s in STAIRS:
		assert_true(_v._stair_cells.has(s), "stair at %s" % s)
		assert_true(_v._is_cell_walkable(s), "stair %s walkable" % s)
	assert_gt(_v._face_cells.size(), 30, "two cliff lines derive faces")
	assert_false(_v._is_cell_walkable(Vector2i(6, 8)), "row 8 face blocks")
	assert_false(_v._is_cell_walkable(Vector2i(15, 19)), "row 19 face blocks")


func test_stairs_connect_and_ledges_do_not() -> void:
	assert_true(_v._can_step(Vector2i(11, 7), Vector2i(11, 8)), "down the west stair")
	assert_true(_v._can_step(Vector2i(23, 8), Vector2i(23, 9)), "off the east stair into town")
	assert_true(_v._can_step(Vector2i(12, 18), Vector2i(12, 19)), "town -> market stair")
	assert_false(_v._can_step(Vector2i(9, 7), Vector2i(9, 8)), "straight off the ledge")
	assert_false(_v._can_step(Vector2i(20, 18), Vector2i(20, 19)), "straight off the lower ledge")


func test_staged_marks_are_walkable_and_paths_never_leave_a_tier_without_a_stair() -> void:
	for path in SCENES:
		var scene = JSON.parse_string(FileAccess.get_file_as_string(path))
		var where := {}
		var idx := 0
		for step in scene.get("steps", []):
			if step is Dictionary:
				var id := str(step.get("id", ""))
				if step.get("type") == "spawn_actor" and step.get("at") is Array:
					var at: Vector2 = Vector2(float(step["at"][0]), float(step["at"][1]))
					assert_true(_v._is_cell_walkable(_cell(at)), "%s[%d] %s spawns on walkable %s" % [path.get_file(), idx, id, _cell(at)])
					where[id] = at
				elif step.get("type") == "move_actor" and step.get("to") is Array and where.has(id):
					var to: Vector2 = Vector2(float(step["to"][0]), float(step["to"][1]))
					var from: Vector2 = where[id]
					var steps := int(ceil(from.distance_to(to) / (TILE * 0.5)))
					var last := _cell(from)
					for s in range(1, steps + 1):
						var c := _cell(from.lerp(to, float(s) / float(steps)))
						if c != last:
							assert_true(_v._can_step(last, c), "%s[%d] %s walks %s -> %s illegally" % [path.get_file(), idx, id, last, c])
							last = c
					where[id] = to
			idx += 1


func test_every_npc_is_reachable_from_the_entrance() -> void:
	var start := _cell(_v.spawn_points["default"])
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if not seen.has(n) and _v._can_step(c, n):
				seen[n] = true
				queue.append(n)
	assert_gt(seen.size(), 300, "the three tiers are one connected walk")
	for n in _v.npcs.get_children():
		if not ("npc_name" in n):
			continue
		var c := _cell(n.position)
		var near := false
		for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if seen.has(c + d):
				near = true
		assert_true(near, "'%s' at %s is reachable from the entrance" % [n.npc_name, c])
	for sp in ["exit", "entrance", "bar_exit", "chapel_exit", "library_exit", "cartographer_exit"]:
		assert_true(seen.has(_cell(_v.spawn_points[sp])), "spawn '%s' reachable" % sp)


func test_harmonia_is_dressed_and_lit() -> void:
	assert_gte(_v.props.get_child_count(), 12, "market stalls, trees, lamps, crates, cart")
	var lamps := 0
	for c in _v.lighting.get_children():
		if c is PointLight2D:
			lamps += 1
	assert_gte(lamps, 4, "lamp posts light the approach and the gate")
	for p in _v.props.get_children():
		for cell in p.footprint_cells(_cell(p.position - Vector2(0, 1))):
			assert_false(_v._face_cells.has(cell), "prop %s stands on a cliff face" % p.name)
			assert_false(_v._stair_cells.has(cell), "prop %s blocks a stair" % p.name)
	assert_true(_v._is_cell_walkable(_cell(_v.spawn_points["default"])), "entrance spawn kept clear")
