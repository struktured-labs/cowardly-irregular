class_name InteriorStroll
extends RefCounted

## Who moves indoors, and where (struktured 2026-11-12: "no one moves inside houses/buildings, but they should be able
## to move sometimes"). SOME NPCs drift between a couple of spots near their mark and come back; keepers stay at
## their counter. The walk itself is PatrolWalk, the loop WanderingNPC patrols with: this file only decides the route.
##
## A route is planned on the room's own walkable cells (InteriorPlacementSweep.walkable_cells: floor, off every
## furniture footprint) and is accepted only if the room stays in one piece with EVERY stroller's cells blocked at
## once, so no combination of positions can cut the player off from the door, a counter or another NPC.

const TILE: int = 32
## Roles that keep their mark: they serve from it, or they are posted there.
const FIXED_TYPES: Array = ["shopkeeper", "innkeeper", "bartender", "blacksmith", "merchant", "dancer", "elder", "guard", "knight", "soldier"]
const MAX_SPOTS: int = 2
const MIN_STEPS: int = 2
const MAX_STEPS: int = 5
const NEIGHBOURS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


## "fixed" or "stroll". An authored `stroll` on the NPC wins; an object, scenery and the keeper roles never move.
static func role_of(npc) -> String:
	if npc == null or not is_instance_valid(npc) or not ("npc_type" in npc):
		return "fixed"
	var authored := str(npc.get("stroll"))
	if authored == "fixed" or authored == "stroll":
		return authored
	if bool(npc.get("is_object")) or not bool(npc.get("interactable")):
		return "fixed"
	return "fixed" if str(npc.get("npc_type")) in FIXED_TYPES else "stroll"


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


static func centre_of(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)


## Every cell reachable from `seeds` over `walk` minus `blocked`.
static func flood(walk: Dictionary, blocked: Dictionary, seeds: Array) -> Dictionary:
	var seen := {}
	var queue: Array = []
	for s in seeds:
		if walk.has(s) and not blocked.has(s) and not seen.has(s):
			seen[s] = true
			queue.append(s)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in NEIGHBOURS:
			var n: Vector2i = c + d
			if walk.has(n) and not blocked.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen


## True when blocking `blocked` cuts nothing apart: every group of cells of `whole` that was connected before is still
## connected among its unblocked cells. (Flooding from every door at once would pass a corridor cut in two with a door
## on each side: measured in this tip's first run.)
static func stays_whole(walk: Dictionary, blocked: Dictionary, _seeds: Array, whole: Dictionary) -> bool:
	var grouped := {}
	for c in whole:
		if grouped.has(c):
			continue
		var group := flood(walk, {}, [c])
		var first: Variant = null
		for k in group:
			grouped[k] = true
			if first == null and not blocked.has(k):
				first = k
		if first == null:
			continue
		var now := flood(walk, blocked, [first])
		for k in group:
			if not blocked.has(k) and not now.has(k):
				return false
	return true


## The routes for one room. `rows`: [{"id", "cell": Vector2i, "role"}]; `reserved`: cells nobody strolls onto (doors,
## service spots). Returns {id: {"route": Array[Vector2i] starting and ending at the mark, "spots": Array[Vector2i]}}.
## Deterministic: the same room plans the same routes every time.
static func plan_room(walk: Dictionary, rows: Array, reserved: Dictionary) -> Dictionary:
	var out := {}
	var homes := {}
	for r in rows:
		homes[r["cell"]] = true
	var seeds: Array = []
	for c in reserved:
		if walk.has(c):
			seeds.append(c)
	if seeds.is_empty():
		for r in rows:
			seeds.append(r["cell"])
	var whole := flood(walk, {}, seeds)
	var claimed := {}
	var strollers: Array = []
	for r in rows:
		if str(r["role"]) == "stroll" and walk.has(r["cell"]):
			strollers.append(r)
	strollers.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	for r in strollers:
		var home: Vector2i = r["cell"]
		# Off limits to this walker: reserved cells, every other NPC's cell and the cells beside it (where the
		# player stands to talk to them), and what another walker already uses.
		var shut := reserved.duplicate()
		for h in homes:
			if h != home:
				shut[h] = true
				for d in NEIGHBOURS:
					shut[h + d] = true
		for c in claimed:
			shut[c] = true
		shut.erase(home)
		var parent := {home: home}
		var steps := {home: 0}
		var queue: Array = [home]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_front()
			if int(steps[c]) >= MAX_STEPS:
				continue
			for d in NEIGHBOURS:
				var n: Vector2i = c + d
				if walk.has(n) and not shut.has(n) and not steps.has(n):
					steps[n] = int(steps[c]) + 1
					parent[n] = c
					queue.append(n)
		var candidates: Array = []
		for c in steps:
			if int(steps[c]) >= MIN_STEPS:
				candidates.append(c)
		# Somewhere to BE: beside furniture or a wall first (a hearth, a shelf, a window), then a stable order.
		candidates.sort_custom(func(a, b):
			var sa := _interest(walk, a)
			var sb := _interest(walk, b)
			if sa != sb:
				return sa > sb
			var ha := hash("%s|%d|%d" % [str(r["id"]), a.x, a.y])
			var hb := hash("%s|%d|%d" % [str(r["id"]), b.x, b.y])
			return ha < hb if ha != hb else (a.x < b.x if a.x != b.x else a.y < b.y))
		var route: Array = [home]
		var spots: Array = []
		var mine := {}
		for c in candidates:
			if spots.size() >= MAX_SPOTS:
				break
			var near_other := false
			for s in spots:
				if absi(s.x - c.x) + absi(s.y - c.y) < 2:
					near_other = true
			if near_other:
				continue
			var path: Array = []
			var at: Vector2i = c
			while at != home:
				path.push_front(at)
				at = parent[at]
			var trial := claimed.duplicate()
			for m in mine:
				trial[m] = true
			for p in path:
				trial[p] = true
			trial[home] = true
			if not stays_whole(walk, trial, seeds, whole):
				continue
			for p in path:
				mine[p] = true
				route.append(p)
			for i in range(path.size() - 2, -1, -1):
				route.append(path[i])
			route.append(home)
			spots.append(c)
		if spots.is_empty():
			continue
		for m in mine:
			claimed[m] = true
		claimed[home] = true
		out[r["id"]] = {"route": route, "spots": spots}
	return out


static func _interest(walk: Dictionary, c: Vector2i) -> int:
	var n := 0
	for d in NEIGHBOURS:
		if not walk.has(c + d):
			n += 1
	return n


## Cells nobody strolls onto: each door or service area and the ring around it, and every authored spawn point.
static func reserved_cells(scene_root, npcs) -> Dictionary:
	var out := {}
	if scene_root == null or not is_instance_valid(scene_root):
		return out
	var points = scene_root.get("spawn_points")
	if points is Dictionary:
		for k in points:
			if points[k] is Vector2:
				out[cell_of(points[k])] = true
	_reserve_areas(scene_root, scene_root, npcs, out)
	return out


static func _reserve_areas(scene_root: Node, node: Node, npcs, out: Dictionary) -> void:
	for child in node.get_children():
		if child == npcs or child.has_method("set_can_move"):
			continue
		if child is Area2D:
			var at: Vector2 = scene_root.to_local((child as Area2D).global_position) if (scene_root is Node2D and child.is_inside_tree()) else (child as Area2D).position
			var c := cell_of(at)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					out[c + Vector2i(dx, dy)] = true
		_reserve_areas(scene_root, child, npcs, out)


## Plan the room and hand each stroller its route. Call it deferred, once the room's doors exist. Untyped on purpose:
## a room freed before the deferred call arrives must reach the validity check, not die at a typed parameter.
static func assign(scene_root, npcs, decorations, layout: Array, blocked_glyphs: String = "") -> Dictionary:
	if scene_root == null or not is_instance_valid(scene_root) or npcs == null or not is_instance_valid(npcs):
		return {}
	var walk := InteriorPlacementSweep.walkable_cells(scene_root, decorations if (decorations != null and is_instance_valid(decorations)) else null, layout, blocked_glyphs)
	var rows: Array = []
	var by_id := {}
	for n in npcs.get_children():
		if not (n is Node2D):
			continue
		var id := "%s#%d" % [str(n.get("npc_name")), n.get_index()]
		rows.append({"id": id, "cell": cell_of((n as Node2D).position), "role": role_of(n)})
		by_id[id] = n
	var plan := plan_room(walk, rows, reserved_cells(scene_root, npcs))
	for id in plan:
		var npc = by_id[id]
		if not npc.has_method("set_stroll"):
			continue
		var route: Array = plan[id]["route"]
		var spots: Array = plan[id]["spots"]
		var points: Array[Vector2] = []
		var rests: Array = []
		for i in route.size():
			var c: Vector2i = route[i]
			var is_home: bool = c == route[0]
			points.append((npc as Node2D).position if is_home else centre_of(c))
			rests.append(is_home or spots.has(c))
		npc.set_stroll(points, rests, hash(id))
	return plan
