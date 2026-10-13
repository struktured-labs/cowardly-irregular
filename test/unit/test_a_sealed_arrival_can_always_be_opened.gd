extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")

## ⛔ A GATE IS A PUZZLE IF YOU CAN OPEN IT AND A TRAP IF YOU CANNOT, AND THE DIFFERENCE IS NOT
## VISIBLE IN THE GEOMETRY. Three dungeon arrivals land on a cell sealed in the floor's initial
## state — driven with the real `_transition_to_floor` and the real body, every direction blocked:
##
##     whispering f3  stairs_up (11,11)   gate (11,10), lever `sw0` at (5,10)
##     whispering f4  stairs_up  (6,11)   `G` lock gate between D(6,9) and U(6,11)
##     ice f2         stairs_up (17,13)   gate (16,13), lever `sw2`
##
## I first reported those four as soft-locks. They are the unsolved state of the Zelda-style gates
## WhisperingCave's own header introduces ("struktured 2026-10-07"), so sealed-at-build-time is the
## designed state and says nothing. cowir-main asked the question that actually decides it.
##
## 🔑 THERE ARE TWO WAYS A SEALED ARRIVAL IS SAFE AND ONLY ONE OF THEM IS "REACH THE LEVER FROM
## INSIDE". The other is that the switch MUST ALREADY BE ACTIVE in every state where that arrival is
## used: you can only descend to f3 from f4, you can only have reached f4 through f3's gate, and
## `DungeonPuzzleLayer` persists switches in `GameState.game_constants[cave_id + "_switches"]` and
## re-applies the flips in `rebuild_floor` on every floor entry. This file asserts the DISJUNCTION
## and reports which limb each case rests on, because a case resting on the second limb is one
## persistence bug away from a soft lock and should be named.

const CASES := [
	{"path": "res://src/maps/dungeons/WhisperingCave.gd", "name": "whispering", "from": 4, "to": 3},
	{"path": "res://src/maps/dungeons/WhisperingCave.gd", "name": "whispering", "from": 5, "to": 4},
	{"path": "res://src/maps/dungeons/IceDragonCave.gd", "name": "ice", "from": 3, "to": 2},
]

var _vp: SubViewport = null


## \u26d4 BOTH PERSISTED KEYS, AND THE SECOND ONE CAUGHT ME. Puzzle switches live under
## `<cave_id>_switches` and lock/pickup state under `<cave_id>_mechanics`. Erasing only the first
## let case 2 inherit the locks case 1 had opened in the SAME PROCESS, and Whispering f4 reported
## `sealed_initially=false` — a case that passes because an earlier case unlocked it is not a case.
func _clean_state(cave_id: String) -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null:
		gs.game_constants.erase(cave_id + "_switches")
		gs.game_constants.erase(cave_id + "_mechanics")


func _build(path: String, floor_n: int) -> Node2D:
	var scr = load(path)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return null
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var d = scr.new()
	d.current_floor = floor_n
	_vp.add_child(d)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return d


func _teardown(d: Node2D) -> void:
	d.queue_free()
	await get_tree().process_frame
	_vp.queue_free()
	await get_tree().process_frame


## The real press: facing probe then standing probe, nearest by anchor, flat reach — dungeons are
## never Mode 7.
func _press(feet: Vector2, facing: Vector2) -> Node:
	var space := _vp.world_2d.direct_space_state
	for point in [feet + facing * InteractGeometry.PROBE_REACH_FLAT, feet]:
		var q := PhysicsPointQueryParameters2D.new()
		q.position = point
		q.collide_with_areas = true
		q.collide_with_bodies = false
		q.collision_mask = InteractGeometry.LAYER_INTERACTABLE
		var best: Node = null
		var bd := INF
		for hit in space.intersect_point(q, 32):
			var c = hit.get("collider")
			if c == null or not is_instance_valid(c) or not (c is Node2D):
				continue
			if not (c.has_method("interact") or c.is_in_group("interactables")):
				continue
			var dd: float = InteractGeometry.anchor(c).distance_squared_to(feet)
			if dd < bd:
				bd = dd
				best = c
		if best != null:
			return best
	return null


## Can the real body step one tile in any direction from here?
func _can_leave(body: CharacterBody2D, tile: float) -> bool:
	for dirn in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if body.move_and_collide(dirn * tile, true) == null:
			return true
	return false


## Everything a press from inside the sealed region can reach, walking only cells the body can
## occupy without leaving the region.
func _switch_reachable_from_inside(d: Node2D, body: CharacterBody2D, tile: float) -> String:
	var start: Vector2 = body.global_position
	var seen: Dictionary = {Vector2i(start / tile): true}
	var queue: Array = [start]
	while not queue.is_empty() and seen.size() < 40:
		var at: Vector2 = queue.pop_front()
		body.global_position = at
		for dirn in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			## Does a press from here reach a lever or a lock?
			var hit := _press(at, dirn)
			if hit != null:
				var b := "?" if hit.get_script() == null else str(hit.get_script().resource_path).get_file()
				if "Lever" in str(hit.name) or "Lock" in str(hit.name) or b.contains("Puzzle") or b.contains("Mechanics"):
					body.global_position = start
					return "%s '%s'" % [b, str(hit.name)]
			if body.move_and_collide(dirn * tile, true) == null:
				var nxt: Vector2 = at + dirn * tile
				var cell := Vector2i(nxt / tile)
				if not seen.has(cell):
					seen[cell] = true
					queue.append(nxt)
	body.global_position = start
	return ""


func test_every_sealed_arrival_rests_on_a_named_limb() -> void:
	var rows: Array = []
	var trapped: Array = []
	for cs in CASES:
		## Cleared before the build as well: `_load_persisted_state` runs in `attach`, so a dirty
		## key is already read by the time the scene exists.
		var gs0: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
		if gs0 != null:
			for suffix in ["_switches", "_mechanics"]:
				gs0.game_constants.erase("whispering_cave" + suffix)
				gs0.game_constants.erase("ice_dragon_cave" + suffix)
		var d = await _build(str(cs["path"]), int(cs["from"]))
		if d == null:
			continue
		_clean_state(str(d.cave_id))
		var tile := float(d.TILE_SIZE)
		var who := "%s f%d" % [str(cs["name"]), int(cs["to"])]

		## 1 — descend for real, with the switch state cleared, and confirm the seal.
		d._transition_to_floor(int(cs["to"]), "down")
		for _i in range(90):
			await get_tree().physics_frame
		var body := d.player as CharacterBody2D
		assert_not_null(body, "CONTROL: %s must build a player body" % who)
		if body == null:
			await _teardown(d)
			continue
		var sealed_at_first := not _can_leave(body, tile)
		var arrival: Vector2 = body.global_position

		## 2 — cowir-main's question: from inside, does a real press reach the switch?
		var from_inside := ""
		if sealed_at_first:
			from_inside = _switch_reachable_from_inside(d, body, tile)

		## 3 — the other limb: fire the switch the way the lever does, rebuild as floor entry does,
		## and require the arrival to open.
		## \u26d4 BOTH LAYERS, BECAUSE THERE ARE TWO KINDS OF GATE AND I FIRST FIRED ONLY ONE.
		## `DungeonPuzzleLayer` owns lever/plate FLIPS; `DungeonMechanics` owns `G`/`Z` LOCKS, which
		## need their key COLLECTED before `try_open` will do anything. Firing only the puzzle
		## switches reported Whispering f4 as a trap — it is a lock gate, so nothing I fired could
		## have opened it, and the row was about my instrument rather than the map.
		var opened := false
		var layer = d.get("_puzzle_layer")
		if layer != null and is_instance_valid(layer):
			for sw in (d.switch_effects as Dictionary).keys():
				if (d.switch_effects[sw] as Dictionary).has("flip"):
					layer.activate_switch(str(sw))
			layer.rebuild_floor(int(cs["to"]))
		var mech = d.get("_mechanics_layer")
		if mech != null and is_instance_valid(mech):
			## A player standing on f5 necessarily came through this gate, so they necessarily had
			## the key. Granting it is restoring the state the arrival implies, not cheating.
			for pk in mech.scan_pickups(d.floor_layouts):
				mech._collected[str(pk["id"])] = true
			for lk in mech.scan_locks(d.floor_layouts):
				mech.try_open(str(lk["id"]))
			mech.rebuild_floor(int(cs["to"]))
		await get_tree().physics_frame
		await get_tree().physics_frame
		body.global_position = arrival
		await get_tree().physics_frame
		opened = _can_leave(body, tile)

		var limb := ""
		if not sealed_at_first:
			limb = "not sealed at all"
		elif from_inside != "":
			limb = "REACHABLE FROM INSIDE (%s)" % from_inside
		elif opened:
			limb = "opens once its switch fires (switch is necessarily already active on this path)"
		else:
			limb = "NEITHER — a trap"
			trapped.append("%s: arrival %s is sealed, no switch reachable from inside, and firing every flip switch does not open it" % [who, str(arrival)])
		rows.append("%s | arrival %s | sealed_initially=%s | from_inside=%s | opens_on_switch=%s | %s" % [
			who, str(arrival), str(sealed_at_first), ("no" if from_inside == "" else from_inside), str(opened), limb])
		await _teardown(d)

	assert_eq(rows.size(), CASES.size(),
		"CONTROL: %d of %d cases produced a row — a case that did not build is not a case that passed" % [rows.size(), CASES.size()])
	for r in rows:
		gut.p("GATE %s" % str(r))
	trapped.sort()
	assert_eq(trapped, [],
		"a sealed arrival cannot be opened by the player who lands in it: %s" % "; ".join(trapped))


func after_all() -> void:
	SoundState.restore()
