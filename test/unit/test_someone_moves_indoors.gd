extends GutTest

## struktured 2026-11-12: "no one moves inside houses/buildings, but they should be able to move sometimes".
## Some interior NPCs stroll between spots near their mark; keepers stay. One walk loop (PatrolWalk, WanderingNPC's).

const ROOMS: Array = [
	["res://src/maps/interiors/InnInterior.gd", "INN_LAYOUT", ""],
	["res://src/maps/interiors/ShopInterior.gd", "SHOP_LAYOUT", "SHELF_GLYPHS"],
	["res://src/maps/interiors/TavernInterior.gd", "TAVERN_LAYOUT", ""],
	["res://src/maps/interiors/HarmoniaChapelInterior.gd", "", ""],
	["res://src/maps/interiors/HarmoniaLibraryInterior.gd", "", ""],
	["res://src/maps/interiors/HarmoniaCartographerInterior.gd", "", ""],
	["res://src/maps/interiors/GrimhollowWitchHutInterior.gd", "", ""],
]

var _was_enabled := true


class Stander:
	extends Node2D
	var npc_type := "villager"
	var npc_name := "Someone"
	var is_object := false
	var interactable := true
	var stroll := ""


func before_each() -> void:
	_was_enabled = OverworldNPC.strolling_enabled
	OverworldNPC.strolling_enabled = true


func after_each() -> void:
	OverworldNPC.strolling_enabled = _was_enabled


func _open(w: int, h: int) -> Dictionary:
	var walk := {}
	for y in h:
		for x in w:
			walk[Vector2i(x, y)] = true
	return walk


## A real room in the tree, its deferred stroll assignment done. [room, layout, glyphs].
func _room(row: Array) -> Array:
	var room: Node = load(str(row[0])).new()
	add_child_autofree(room)
	await get_tree().process_frame
	await get_tree().process_frame
	var layout: Array = room.get(str(row[1])) if str(row[1]) != "" else room._get_layout()
	var glyphs: String = str(room.get(str(row[2]))) if str(row[2]) != "" else ""
	return [room, layout, glyphs]


func _strollers(room: Node) -> Array:
	var out: Array = []
	for n in room.npcs.get_children():
		if n.has_method("is_strolling") and n.is_strolling():
			out.append(n)
	return out


func test_the_walk_rests_where_it_is_told_and_holds_its_mark() -> void:
	var w := PatrolWalk.new()
	var pts: Array[Vector2] = [Vector2.ZERO, Vector2(40, 0), Vector2(80, 0)]
	w.points = pts
	w.rests = [true, false, true]
	w.rng = RandomNumberGenerator.new()
	w.rng.seed = 7
	w.target = 1
	var pos := Vector2.ZERO
	var rested_at_mid := false
	for i in 200:
		pos = w.step(pos, 0.05)
		if w.paused and w.target == 1:
			rested_at_mid = true
		if w.paused and w.target == 2:
			break
	assert_false(rested_at_mid, "a point flagged false is walked through, not rested at")
	assert_true(w.paused and w.target == 2, "CONTROL: it reaches and rests at the flagged point (%s)" % str(pos))
	w.hold_at = 0
	w.holding = true
	for i in 2000:
		pos = w.step(pos, 0.05)
	assert_true(w.is_held(), "an NPC told to hold walks to its mark and stays")
	assert_lt(pos.distance_to(Vector2.ZERO), 6.0, "and the mark is point 0")


func test_keepers_objects_and_scenery_never_stroll() -> void:
	var s := Stander.new()
	autofree(s)
	assert_eq(InteriorStroll.role_of(s), "stroll", "CONTROL: a villager strolls")
	for t in InteriorStroll.FIXED_TYPES:
		s.npc_type = t
		assert_eq(InteriorStroll.role_of(s), "fixed", "a %s keeps its mark" % t)
	s.npc_type = "villager"
	s.is_object = true
	assert_eq(InteriorStroll.role_of(s), "fixed", "an object never moves")
	s.is_object = false
	s.interactable = false
	assert_eq(InteriorStroll.role_of(s), "fixed", "scenery never moves")
	s.interactable = true
	s.stroll = "fixed"
	assert_eq(InteriorStroll.role_of(s), "fixed", "an authored 'fixed' wins over the role")
	s.npc_type = "shopkeeper"
	s.stroll = "stroll"
	assert_eq(InteriorStroll.role_of(s), "stroll", "and an authored 'stroll' wins the other way")


func test_a_route_leaves_and_returns_and_keeps_off_reserved_cells() -> void:
	var walk := _open(8, 6)
	var door := Vector2i(4, 5)
	var rows := [{"id": "a", "cell": Vector2i(2, 2), "role": "stroll"}, {"id": "keeper", "cell": Vector2i(6, 1), "role": "fixed"}]
	var plan := InteriorStroll.plan_room(walk, rows, {door: true})
	assert_true(plan.has("a"), "CONTROL: an open room gives the stroller a route")
	assert_false(plan.has("keeper"), "a fixed NPC gets none")
	if not plan.has("a"):
		return
	var route: Array = plan["a"]["route"]
	assert_eq(route[0], Vector2i(2, 2), "the route starts at the mark")
	assert_eq(route[route.size() - 1], Vector2i(2, 2), "and ends at it")
	for i in range(1, route.size()):
		var step: Vector2i = route[i] - route[i - 1]
		assert_eq(absi(step.x) + absi(step.y), 1, "every step is to a neighbouring cell (%s -> %s)" % [str(route[i - 1]), str(route[i])])
		assert_true(walk.has(route[i]), "on a walkable cell")
		assert_ne(route[i], door, "never the door cell")
		assert_gt(absi(route[i].x - 6) + absi(route[i].y - 1), 1, "never the keeper's cell or the cell the player talks to them from")
	assert_eq(str(InteriorStroll.plan_room(walk, rows, {door: true})), str(plan), "the same room plans the same routes every time")


func test_a_route_that_would_cut_the_room_in_two_is_refused() -> void:
	# A one-cell corridor between two halves: any walk along it blocks it.
	var walk := {}
	for x in 7:
		walk[Vector2i(x, 0)] = true
	var rows := [{"id": "a", "cell": Vector2i(3, 0), "role": "stroll"}]
	var plan := InteriorStroll.plan_room(walk, rows, {Vector2i(0, 0): true, Vector2i(6, 0): true})
	assert_false(plan.has("a"), "a stroller in a corridor stays put: its cells would wall the room")
	var wide := _open(7, 3)
	rows = [{"id": "a", "cell": Vector2i(3, 0), "role": "stroll"}]
	assert_true(InteriorStroll.plan_room(wide, rows, {Vector2i(0, 1): true, Vector2i(6, 1): true}).has("a"), "CONTROL: with room to pass, it strolls")


func test_two_strollers_never_share_a_cell() -> void:
	var walk := _open(9, 7)
	var rows := [{"id": "a", "cell": Vector2i(2, 3), "role": "stroll"}, {"id": "b", "cell": Vector2i(6, 3), "role": "stroll"}]
	var plan := InteriorStroll.plan_room(walk, rows, {Vector2i(4, 6): true})
	assert_eq(plan.size(), 2, "CONTROL: both stroll in an open room")
	if plan.size() < 2:
		return
	var seen := {}
	for c in plan["a"]["route"]:
		seen[c] = true
	for c in plan["b"]["route"]:
		assert_false(seen.has(c), "cell %s is on both routes" % str(c))


func test_no_real_room_can_be_cut_off_by_its_strollers() -> void:
	var strolling := 0
	for row in ROOMS:
		var got: Array = await _room(row)
		var room: Node = got[0]
		var walk := InteriorPlacementSweep.walkable_cells(room, room.decorations, got[1], got[2])
		var reserved := InteriorStroll.reserved_cells(room, room.npcs)
		var seeds: Array = []
		for c in reserved:
			if walk.has(c):
				seeds.append(c)
		assert_gt(seeds.size(), 0, "%s: CONTROL: the room has a door or service cell to reach" % str(row[0]).get_file())
		var whole := InteriorStroll.flood(walk, {}, seeds)
		var blocked := {}
		for n in _strollers(room):
			strolling += 1
			for p in n._stroll.points:
				var c := InteriorStroll.cell_of(p)
				blocked[c] = true
				assert_true(walk.has(c), "%s: %s strolls onto %s, which is wall or furniture" % [str(row[0]).get_file(), n.npc_name, str(c)])
				assert_false(reserved.has(c) and c != InteriorStroll.cell_of(n._stroll.points[0]), "%s: %s strolls onto a door or service cell %s" % [str(row[0]).get_file(), n.npc_name, str(c)])
		assert_true(InteriorStroll.stays_whole(walk, blocked, seeds, whole), "%s: with every stroller's cells blocked at once the room must stay in one piece" % str(row[0]).get_file())
	assert_gt(strolling, 0, "CONTROL: somebody strolls in at least one of the %d rooms, or this arm judged nothing" % ROOMS.size())


func test_a_keeper_stays_and_a_stroller_moves() -> void:
	var got: Array = await _room(ROOMS[0])
	var room: Node = got[0]
	var before := {}
	for n in room.npcs.get_children():
		before[n] = (n as Node2D).position
	for i in 600:
		for n in room.npcs.get_children():
			n._process(0.05)
	var moved := 0
	for n in room.npcs.get_children():
		if InteriorStroll.role_of(n) == "fixed":
			assert_eq((n as Node2D).position, before[n], "%s keeps its mark for 30 s" % str(n.get("npc_name")))
		elif n.has_method("is_strolling") and n.is_strolling():
			var far := 0.0
			for p in n._stroll.points:
				far = maxf(far, (p as Vector2).distance_to(before[n]))
			assert_lt(((n as Node2D).position as Vector2).distance_to(before[n]), far + 1.0, "%s stays on its route" % str(n.get("npc_name")))
			if (n as Node2D).position != before[n] or n._stroll.target != 0:
				moved += 1
	assert_gt(moved, 0, "CONTROL: at least one inn guest left their mark in 30 s")


func test_a_stroller_stands_still_for_the_player_a_lock_and_the_freeze_switch() -> void:
	var got: Array = await _room(ROOMS[0])
	var walkers := _strollers(got[0])
	assert_gt(walkers.size(), 0, "CONTROL: the inn has a stroller to judge")
	if walkers.is_empty():
		return
	var n: Node = walkers[0]
	n._stroll.paused = false
	n._stroll.target = 1
	var at: Vector2 = n.position
	n._process(0.1)
	assert_ne(n.position, at, "CONTROL: left alone it walks")
	at = n.position
	n._player_nearby = true
	n._process(0.1)
	assert_eq(n.position, at, "it stops while the player is beside it")
	n._player_nearby = false
	InputLockManager.push_lock("test_indoor_stroll")
	n._process(0.1)
	InputLockManager.pop_lock("test_indoor_stroll")
	assert_eq(n.position, at, "it stops under an input lock")
	OverworldNPC.strolling_enabled = false
	n._process(0.1)
	assert_eq(n.position, at, "it stops while strolling is switched off (the screenshot tool's switch)")
	OverworldNPC.strolling_enabled = true
	n._is_talking = true
	n._process(0.1)
	n._is_talking = false
	assert_eq(n.position, at, "it stops while it is talking")


func test_every_room_that_places_npcs_plans_their_strolls() -> void:
	for path in ["res://src/maps/interiors/BaseInterior.gd", "res://src/maps/interiors/InnInterior.gd", "res://src/maps/interiors/ShopInterior.gd", "res://src/maps/interiors/TavernInterior.gd"]:
		var src := FileAccess.get_file_as_string(path)
		var sweep := src.find("InteriorPlacementSweep.sweep(")
		var assign := src.find("InteriorStroll.assign.call_deferred(")
		assert_gt(sweep, -1, "CONTROL: %s sweeps its NPCs" % path.get_file())
		assert_gt(assign, sweep, "%s must plan strolls after the sweep has settled where everyone stands" % path.get_file())
