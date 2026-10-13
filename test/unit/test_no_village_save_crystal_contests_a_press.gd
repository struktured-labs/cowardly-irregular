extends GutTest

const SoundState := preload("res://test/unit/helpers/sound_state.gd")
const DIR := "res://src/maps/villages/"

## 🐛 SIX OF THIRTEEN VILLAGES HAD A SAVE CRYSTAL THAT STOLE OR LOST A FACED PRESS — 24 contests.
## Two village DOORS saved instead of opening (Brasston's Clockwork Loft, NodePrime's Daemon
## Lounge); three named NPCs lost approach cells to the crystal and took cells from it (Elder
## Vesper, Madame Hex, The Keeper); and three authored examines lost their prose to it (the Frosthold
## cairn, the NodePrime terminal, the Vertex monolith). All six crystals moved, 2-5 cells, every cell
## press-tested in both directions. Same defect class as the two overworld crystals and the
## chest-in-the-doorway, in the one place nobody had probed.
##
## ⛔ CO-LOCATION GUARDS CANNOT SEE THIS, WHICH IS WHY IT SURVIVED. `test_no_villager_stands_on_an
## _interactable` and `test_the_save_crystal_stands_on_the_floor` both pass on all 24 — nothing was
## sharing a cell. `SAVE_RADIUS` is 48 px, a cell is 32, so a crystal contests presses a cell and a
## half beyond its own tile and the overlap is invisible to any same-cell check.
##
## ⛔ AND A CELL-LEVEL OCCUPANCY FIX DOES NOT TOUCH IT EITHER. I fixed a real blindness first —
## `_occupied_interact_cells` walked only `npcs`, so it could not see the crystal (parented to the
## scene root) or the doors (under `transitions`) — and re-measured: still 24. Necessary, unrelated.
## A radius overlap is not a cell collision.
##
## ⛔ CENTRING THE CRYSTAL ON ITS CELL IS A WASH AND I ALMOST SHIPPED IT. Village crystals sit on the
## cell CORNER (`cell * TILE_SIZE`, no half-tile) while this repo documents centring as load-bearing
## for interactables, so it looks like the one-line mechanism fix. Measured: 24 -> 23, Grimhollow
## 6 -> 2, and A NEW CONTEST IN MAPLE HEIGHTS, which was clean before. It redistributes rather than
## resolves. Corner placement is left alone.
##
## 🔑 THE ARM ASSERTS A RELATIONSHIP AND THE CELLS ARE NOT PINNED HERE. Each village's crystal cell
## lives in its own `_get_save_point_position()`; this file says only that wherever it is, it answers
## every one of its own approach cells and takes none of anybody else's. A relocation chosen by the
## same method passes without touching this file.

var _vp: SubViewport = null
var _step: float = 32.0


func _build(file: String) -> Node2D:
	var scr = load(DIR + file)
	if scr == null or not (scr is GDScript) or not scr.can_instantiate():
		return null
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var v = scr.new()
	_vp.add_child(v)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step = float(v.TILE_SIZE) if "TILE_SIZE" in v else 32.0
	return v


func _villages() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	assert_not_null(d, "CONTROL: the villages directory must be readable")
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd") and f != "BaseVillage.gd":
			out.append(f)
	out.sort()
	return out


func _fits(at: Vector2) -> bool:
	var sh := CircleShape2D.new()
	sh.radius = 8.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = sh
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


## OverworldController's press reproduced: flat reach (villages are never Mode 7), facing probe then
## standing probe, nearest by anchor. Verified against `OverworldController:245-278` rather than
## modelled — same two probes, same `collide_with_areas`, same mask 4, and NO facing cone, which the
## controller's probe path does not apply.
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
		for hit in space.intersect_point(q):
			var c = hit.get("collider")
			if c == null or not is_instance_valid(c) or not (c is Node2D):
				continue
			if not (c is SavePoint or c.has_method("interact") or c.is_in_group("interactables")):
				continue
			var d: float = InteractGeometry.anchor(c).distance_squared_to(feet)
			if d < bd:
				bd = d
				best = c
		if best != null:
			return best
	return null


func _winners(n: Node2D) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var feet: Vector2 = n.global_position + Vector2(dx * _step, dy * _step)
			if not _fits(feet):
				continue
			var facing := Vector2(-dx, 0) if absi(dx) >= absi(dy) else Vector2(0, -dy)
			out.append({"cell": "(%d,%d)" % [dx, dy], "won": _press(feet, facing)})
	return out


func _label(n: Node) -> String:
	var nm = n.get("npc_name")
	if nm != null and str(nm) != "":
		return str(nm)
	return str(n.name)


func _split(v: Node2D) -> Dictionary:
	var saves: Array = []
	var others: Array = []
	var stack: Array = [v]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is Node2D):
			continue
		if n is SavePoint:
			saves.append(n)
		elif n.has_method("interact") or n.is_in_group("interactables"):
			others.append(n)
	return {"saves": saves, "others": others}


func _contests(sp: Node2D, others: Array) -> Array:
	var bad: Array = []
	for row in _winners(sp):
		var won = row["won"]
		if won != null and won != sp:
			bad.append("standing %s at the crystal and facing it opens %s instead — the player cannot save there" % [
				str(row["cell"]), _label(won)])
	## ⛔ THE OTHER SIDE ASKS "IS IT STILL PRESSABLE AT ALL", NOT "DOES IT LOSE ANY CELL". Losing a
	## cell is often CORRECT: stand two tiles from an NPC, press, and the nearer save crystal
	## answering is nearest-by-anchor working as designed. The defect is being FULLY SHADOWED — no
	## standable cell anywhere from which a faced press reaches you.
	##
	## ⚠️ AND `_winners`' RING OF 8 CANNOT ASK IT. Harmonia's fountain is a 2x2 trigger inside a 5x5
	## basin, so it has no standable neighbour and the ring was EMPTY — this file called Harmonia clean
	## while the crystal, parked at (13,10) between the only ground and the basin, took every press
	## that would have reached the fountain's five rotating lines. A prop can be pressable from two
	## cells out and adjacent to nothing, so the search is over GROUND, not over adjacency.
	for o in others:
		if (o as Node2D).global_position.distance_to(sp.global_position) > 5.0 * _step:
			continue
		var near := Vector2i((o as Node2D).global_position / _step)
		var reachable := false
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var feet: Vector2 = Vector2((near.x + dx) * _step + _step / 2.0, (near.y + dy) * _step + _step / 2.0)
				if not _fits(feet):
					continue
				for fc in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
					if _press(feet, fc) == o:
						reachable = true
						break
				if reachable:
					break
			if reachable:
				break
		if not reachable:
			bad.append("%s is fully shadowed — no standable cell can press it, the save crystal answers every approach" % _label(o))
	return bad


func _teardown(v: Node2D) -> void:
	v.queue_free()
	await get_tree().process_frame
	_vp.queue_free()
	await get_tree().process_frame


func test_every_village_has_exactly_one_crystal_to_judge() -> void:
	var files := _villages()
	assert_gt(files.size(), 10, "CONTROL: found %d village scripts" % files.size())
	var wrong: Array = []
	for f in files:
		var v = await _build(f)
		if v == null:
			continue
		var n: int = (_split(v)["saves"] as Array).size()
		if n != 1:
			wrong.append("%s has %d save points" % [f, n])
		await _teardown(v)
	wrong.sort()
	assert_eq(wrong, [], "a village's save crystal is missing or doubled: %s" % ", ".join(wrong))


## ⛔ THE ARM.
func test_no_crystal_steals_or_loses_a_faced_press() -> void:
	var contested: Array = []
	var checked := 0
	var cells := 0
	for f in _villages():
		var v = await _build(f)
		if v == null:
			continue
		var got: Dictionary = _split(v)
		for sp in (got["saves"] as Array):
			checked += 1
			cells += _winners(sp as Node2D).size()
			for msg in _contests(sp as Node2D, got["others"] as Array):
				contested.append("%s: %s" % [f, msg])
		await _teardown(v)
	assert_gt(checked, 10, "CONTROL: only %d crystals examined" % checked)
	assert_gt(cells, 40,
		"CONTROL: only %d crystal approach cells were standable; the arm would clear vacuously" % cells)
	contested.sort()
	## ⚠️ ONE LINE PER CONTEST, because GUT TRUNCATES a long assert message. With 24 of these the
	## message named only the first village and my own mutation read as "the detector found one of
	## six". The assert is the verdict; these lines are the evidence, and they survive truncation.
	for c in contested:
		gut.p("CONTEST %s" % str(c))
	assert_eq(contested, [], "a faced press goes to the wrong thing: %s" % "; ".join(contested))
	gut.p("  %d village crystals, %d approach cells, no contested press" % [checked, cells])


## 🔑 THE POSITIVE CONTROL, because a zero is worth nothing without one. Park Harmonia's crystal on
## top of one of its own NPCs and require the detector to say so — the same shape the arm reports.
func test_the_detector_can_see_a_contest() -> void:
	var v = await _build("HarmoniaVillage.gd")
	assert_not_null(v, "CONTROL: Harmonia must build")
	if v == null:
		return
	var got: Dictionary = _split(v)
	var sp: Node2D = (got["saves"] as Array)[0]
	assert_eq(_contests(sp, got["others"] as Array), [],
		"CONTROL: Harmonia is clean before the plant, or the arm below proves nothing")
	var victim: Node2D = null
	for o in (got["others"] as Array):
		if o.has_method("interact") and _label(o) != "":
			victim = o
			break
	assert_not_null(victim, "CONTROL: an interactable to collide with")
	if victim == null:
		await _teardown(v)
		return
	sp.global_position = (victim as Node2D).global_position
	await get_tree().physics_frame
	await get_tree().physics_frame
	var seen := _contests(sp, got["others"] as Array)
	assert_gt(seen.size(), 0,
		"a crystal parked ON an interactable must be reported — if it is not, the arm's clean result is meaningless")
	await _teardown(v)


## Thirteen villages' _ready calls play_area_music, so this file writes SoundManager's area/world
## state without naming any of it.
func after_all() -> void:
	SoundState.restore()
