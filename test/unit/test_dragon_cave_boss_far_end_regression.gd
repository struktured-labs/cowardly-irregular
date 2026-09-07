extends GutTest

## Dragon cave boss floors: boss at far end + winding path + treasures
## (struktured msg 2788: "why is the dragon at the very beginning of the
## cave? seems silly — make it a little harder to reach, wear the
## character out, maybe get some treasures on the way").
##
## Superseded once (msg 2788, class-level fix): all 4 caves got a shared
## 3-floor boss layout with B pinned to the top-right corner. Superseded
## again 2026-09-06 (struktured, live: "the dragon dungeons are too
## shallow... should be more involved in general") — each cave is now
## 5 floors deep with its own elemental boss arena, so a shared pinned
## quadrant no longer applies. What survives from msg 2788 is the INTENT:
## the boss must not sit trivially next to the arrival point, and the
## descent must reward exploration with real treasure. Exact quadrant/
## floor-count pins are gone; the concern itself is not. Full puzzle-layer
## reachability (portals/switches/mimics) is covered by
## test_w1_dungeon_depth_solver.gd — this file stays narrowly about the
## "boss isn't trivially adjacent to arrival, and treasure exists en
## route" shape.

const DRAGON_CAVES: Array = [
	["res://src/maps/dungeons/LightningDragonCave.gd", "LightningDragonCaveScene"],
	["res://src/maps/dungeons/FireDragonCave.gd", "FireDragonCaveScene"],
	["res://src/maps/dungeons/IceDragonCave.gd", "IceDragonCaveScene"],
	["res://src/maps/dungeons/ShadowDragonCave.gd", "ShadowDragonCaveScene"],
]

## Minimum Manhattan distance (in tiles) between the boss floor's arrival
## point and B — msg 2788's "not trivially close" concern, made relative
## instead of pinned to a quadrant so re-authoring a floor stays free.
const MIN_ARRIVAL_TO_BOSS_DISTANCE := 6


func _find_char(rows: Array, ch: String) -> Vector2i:
	for y in range(rows.size()):
		var r: String = str(rows[y])
		for x in range(r.length()):
			if r[x] == ch:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


func _count_char_in_layout(layout: Array, ch: String) -> int:
	var n := 0
	for y in range(layout.size()):
		var r: String = str(layout[y])
		for x in range(r.length()):
			if r[x] == ch:
				n += 1
	return n


## Best-case reachability: every switch on this floor is assumed already
## thrown (mirrors "the player solved every puzzle"), consistent with
## DungeonPuzzleLayer.is_walkable's flip semantics rather than a naive
## plain-wall flood fill — several treasures now sit behind a lever.
func _flood_reach(cave, floor_num: int, start: Vector2i, goal: Vector2i) -> bool:
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
		return false
	var active := {}
	for sw_id in (cave.switch_effects as Dictionary):
		active[sw_id] = true
	var layout: Array = cave.floor_layouts[floor_num]
	var seen := {}
	var stack: Array = [start]
	while stack.size() > 0:
		var p: Vector2i = stack.pop_back()
		if p == goal:
			return true
		if seen.has(p):
			continue
		seen[p] = true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.y < 0 or q.y >= layout.size():
				continue
			var r: String = str(layout[q.y])
			if q.x < 0 or q.x >= r.length():
				continue
			if not DungeonPuzzleLayer.is_walkable(cave.floor_layouts, cave.switch_effects, floor_num, q, active):
				continue
			stack.append(q)
	return false


## Every cave is now 4-5 floors deep (struktured 2026-09-06 depth pass).
func test_all_dragon_caves_have_at_least_four_floors() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		assert_not_null(script, "%s loads" % entry[0])
		var inst = script.new()
		assert_gte(inst.total_floors, 4,
			"%s: total_floors must be >= 4 (msg 2788's spirit, deepened 2026-09-06)" % entry[1])
		inst.free()


## The boss must not sit trivially next to the floor's arrival point
## (whichever D/entrance lands the player there).
func test_boss_is_not_adjacent_to_the_arrival_point() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		var inst = script.new()
		var boss_floor: Array = inst.floor_layouts[inst.total_floors]
		var b := _find_char(boss_floor, "B")
		var d := _find_char(boss_floor, "D")
		assert_ne(b, Vector2i(-1, -1), "%s boss floor has a B marker" % entry[1])
		assert_ne(d, Vector2i(-1, -1), "%s boss floor has a D marker" % entry[1])
		var dist: int = absi(b.x - d.x) + absi(b.y - d.y)
		assert_gte(dist, MIN_ARRIVAL_TO_BOSS_DISTANCE,
			"%s: B%s is only %d tiles from arrival D%s — too close for msg 2788's concern" % [
				entry[1], str(b), dist, str(d)])
		inst.free()


## Every dungeon carries real treasure across its full descent (not just the
## boss floor) — the deepened design spreads loot across floors rather than
## cramming it onto the last one alone.
func test_dungeon_carries_treasure_across_the_full_descent() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		var inst = script.new()
		var total_t := 0
		for f in (inst.floor_layouts as Dictionary):
			total_t += _count_char_in_layout(inst.floor_layouts[f], "T")
		assert_gte(total_t, 4,
			"%s: dungeon-wide T count must be >= 4 (got %d) — 'get some treasures on the way'" % [entry[1], total_t])
		inst.free()


## Walkability: every floor's own D/U landing point can reach every other
## walkable cell on that floor via plain movement (ignores puzzle-layer
## switches/portals, which test_w1_dungeon_depth_solver.gd covers). Catches
## the layout-authoring trap where a whole room ends up sealed behind walls.
func test_every_floor_is_internally_connected_from_its_landing_point() -> void:
	for entry in DRAGON_CAVES:
		var script = load(entry[0])
		var inst = script.new()
		for f in (inst.floor_layouts as Dictionary):
			var layout: Array = inst.floor_layouts[f]
			var landing: Vector2i = _find_char(layout, "D")
			if landing == Vector2i(-1, -1):
				landing = _find_char(layout, "U")
			if landing == Vector2i(-1, -1):
				continue
			for y in range(layout.size()):
				var r: String = str(layout[y])
				for x in range(r.length()):
					var ch := r[x]
					if ch in ["T", "U", "D", "B"]:
						assert_true(_flood_reach(inst, int(f), landing, Vector2i(x, y)),
							"%s floor %s: %s at (%d,%d) unreachable from the floor's own landing point (even with every switch solved)" % [
								entry[1], str(f), ch, x, y])
		inst.free()
