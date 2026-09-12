extends GutTest

## A 500-gold chest was authored ON the Ironhaven village door, and W1 doors need a press.
##
## Every overworld transition is built with `require_interaction = true` ("Press A to enter"), so a
## village door competes for ui_accept with anything else carrying interact(). `w1_iron_gold` sat
## 0.71 cells from IronhavenEntrance and won the faced press from 3 of its 5 standable approach
## cells. The chest is a one-shot: after it is looted, `TreasureChest.interact` still claims the
## press and answers "The chest is empty." — so those three approaches told the player the chest
## was empty, in front of the village door, for the rest of the campaign.
##
## `w1_swamp_remedy` had the same defect one cell milder against GrimhollowEntrance (1 of 8).
## Both moved: (82,58) -> (80,61) and (72,8) -> (74,11), chosen by measurement rather than by eye.
##
## ⚠️ SCOPED TO NON-DOOR THIEVES ON PURPOSE, and the exclusion is a different mechanism rather than
## an allowlist. Door-vs-door overlap is real in W1 (SandriftEntrance shares cells with
## LightningDragonCave) and has its OWN arbitration — `AreaTransition._a_nearer_transition_has`,
## added 2026-09-09 for exactly that pair, deciding by distance inside the transition's own
## ui_accept handler. This file reproduces OverworldController's probe, which does not run that
## check, so it is not competent to judge a door losing to a door and does not try. A chest losing
## a door its press has no second layer to save it.
##
## 🔑 The second arm blocks HALF the cheap fix, and the half it does not block is worth naming
## because I walked into it. Moving a chest until it stops robbing a door is satisfiable by moving
## it somewhere useless, in two different ways:
##   no standable neighbour  (86,57): zero thefts, zero approaches   <- THIS arm catches it
##   sealed inside terrain   (84,57): zero thefts, opens fine when faced from a neighbour, and the
##                           player can never get to those neighbours  <- this arm does NOT, and
##                           test_overworld_secrets_are_reachable does. (84,57) was my chosen cell
##                           for one run; that file red and this one was green.
##
## ⛔ And the reason I chose it: I read the painted PNG to decide the cell was grass. That is the
## grid model test_overworld_secrets_are_reachable's own header records as wrong in BOTH directions
## — the Mode 7 collider clone is displaced +140.6 px, so what is painted at a cell and what blocks
## a body there are 2.2 cells apart. (84,57) paints as grass and is sealed; (80,61), the cell that
## shipped, paints as lava and is standable. Choose overworld cells with a physics query.

const BODY_RADIUS := 8.0
const W1 := "res://src/exploration/OverworldScene.gd"

var _vp: SubViewport = null
var _w: Node2D = null
var _step: float = 64.0


func _build() -> void:
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState")
	if gs != null:
		gs.set_story_flag("world1_mordaine_defeated", true)
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	_w = load(W1).new()
	_vp.add_child(_w)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_step = float(int(_w.MAP_SCALE) * int(_w.TILE_SIZE))


func _base(n: Node) -> String:
	if n.get_script() == null:
		return "?"
	return str(n.get_script().resource_path).get_file().get_basename()


func _interactables() -> Array:
	var out: Array = []
	var stack: Array = [_w]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node2D and n.has_method("interact"):
			out.append(n)
	return out


func _fits(at: Vector2) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


## OverworldController's press, reproduced: facing probe, then standing probe, nearest by anchor.
func _press_lands_on(feet: Vector2, facing: Vector2) -> Node:
	var space := _vp.world_2d.direct_space_state
	for point in [feet + facing * InteractGeometry.PROBE_REACH_MODE7, feet]:
		var q := PhysicsPointQueryParameters2D.new()
		q.position = point
		q.collide_with_areas = true
		q.collide_with_bodies = false
		q.collision_mask = 4
		var best: Node = null
		var best_d := INF
		for hit in space.intersect_point(q):
			var c = hit.get("collider")
			if c == null or not is_instance_valid(c) or not c.has_method("interact") or not (c is Node2D):
				continue
			var d: float = InteractGeometry.anchor(c).distance_squared_to(feet)
			if d < best_d:
				best_d = d
				best = c
		if best != null:
			return best
	return null


## Who wins each standable cell touching `n` when the player faces `n` from it.
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
			out.append({"cell": "(%d,%d)" % [dx, dy], "won": _press_lands_on(feet, facing)})
	return out


func test_no_door_loses_its_press_to_something_that_is_not_a_door() -> void:
	await _build()
	var doors: Array = []
	for n in _interactables():
		if _base(n) == "AreaTransition":
			doors.append(n)
	assert_gt(doors.size(), 8,
		"CONTROL: only %d doors collected — with no doors, the [] below is free" % doors.size())

	var robbed: Array = []
	for d in doors:
		for row in _winners(d):
			var won = row["won"]
			if won == d or won == null:
				continue
			if _base(won) == "AreaTransition":
				continue  # door-vs-door: AreaTransition._a_nearer_transition_has owns that, not this file
			robbed.append("%s: standing %s and facing the door opens %s (%s) instead — move it; a door needs a press and this one is a one-shot that keeps answering after it is looted" % [
				str(d.name), str(row["cell"]), _base(won), str(won.name)])
	robbed.sort()
	assert_eq(robbed, [],
		"a village door lost its faced press to something that is not a door: %s" % ", ".join(robbed))


## Relocating a chest to a cell with no standable neighbour at all — the other half is the sibling
## guard's; see the header. Also the mirror of the arm above: a chest must keep its OWN faced press.
func test_no_chest_was_moved_out_of_reach() -> void:
	await _build()
	var chests: Array = []
	for n in _interactables():
		if _base(n) == "TreasureChest":
			chests.append(n)
	assert_gt(chests.size(), 8, "CONTROL: only %d chests collected" % chests.size())

	var bad: Array = []
	for c in chests:
		var rows: Array = _winners(c)
		if rows.is_empty():
			bad.append("%s — no standable cell touches it at all; it robs nothing because nobody can reach it" % str(c.chest_id))
			continue
		for row in rows:
			if row["won"] != c:
				var w = row["won"]
				bad.append("%s — standing %s and facing it opens %s instead" % [
					str(c.chest_id), str(row["cell"]), _base(w) if w else "NOTHING"])
	bad.sort()
	assert_eq(bad, [], "a chest cannot be opened from a cell touching it: %s" % ", ".join(bad))


## CONTROL: put a chest back in the Ironhaven doorway. The arm above must see it.
func test_the_arm_can_see_a_chest_in_a_doorway() -> void:
	await _build()
	var door: Node2D = null
	for n in _interactables():
		if str(n.name) == "IronhavenEntrance":
			door = n
	assert_not_null(door, "CONTROL: IronhavenEntrance exists")
	if door == null:
		return
	var clean := true
	for row in _winners(door):
		if row["won"] != door and row["won"] != null and _base(row["won"]) != "AreaTransition":
			clean = false
	assert_true(clean, "CONTROL: the door answers its own faced press before the thief is planted")

	var thief = load("res://src/exploration/TreasureChest.gd").new()
	thief.chest_id = "zz_probe_doorway"
	thief.contents_type = "gold"
	thief.gold_amount = 1
	thief.position = door.position + Vector2(45, 0)
	_w.add_child(thief)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var stolen := 0
	for row in _winners(door):
		if row["won"] == thief:
			stolen += 1
	thief.queue_free()
	await get_tree().physics_frame
	assert_gt(stolen, 0,
		"a chest planted 45px from the door must take faced presses from it — at the distance " +
		"w1_iron_gold actually sat. If it does not, the real arm passes for free")
