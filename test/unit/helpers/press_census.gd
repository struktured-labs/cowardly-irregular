extends RefCounted

## Reproduce the overworld PRESS, so a guard can ask "walk up to this, face it, press — do I get it?"
##
## ⛔ EXISTS BECAUSE THE PROPERTY IS "FACE IT AND PRESS", NOT "NO PRESS MOVES", AND THAT DISTINCTION
## IS ONLY DEFENSIBLE IF EVERY WORLD MEASURES IT THE SAME WAY. New 128px readable zones on a map
## authored around chests DO move presses — W1 measured three chests each losing 1-2 of a broad 5x5
## census to a lore prop, every one of them the player standing BESIDE the chest and facing AWAY.
## Asserting zero movement would force correct placements to relocate.
##
## The dispatch this models is OverworldController's: a facing probe at PROBE_REACH, then a standing
## probe, and NEAREST BY ANCHOR among the colliders that have interact(). Anchor, not origin —
## `InteractGeometry.anchor` adds the collision shape's offset, so offset-shape doors stop losing
## ties they visually win.
##
## 🔑 THE REFINEMENT W2 FORCED, and the reason this is a helper rather than three copies: a press
## lost to something the player stands AT LEAST AS CLOSE TO is the dispatch rule WORKING. W2's
## Timetable has `w2_bus_hipotion` exactly two cells below it, so its three south cells are
## equidistant (96 vs 96, 136 vs 136) and the chest answers them. `face_split` returns those
## separately as `yielded` so a caller REPORTS them with their numbers instead of allowlisting the
## cells — you cannot silence this green, only explain it green. A press lost to something FARTHER
## is `bad`, and that is the defect.
##
## W1Landmarks' guard predates this and carries its own inline copy of the unrefined form; it passes
## because no W1 landmark has an equidistant neighbour. Two instruments, deliberately, until someone
## moves W1 over — the maps differ, not the rule.

const BODY_RADIUS := 8.0

var _vp: SubViewport = null
var _step: float = 96.0


## `step` is one MAP CELL in pixels (MAP_SCALE * TILE_SIZE), the unit the overworlds author in.
func setup(vp: SubViewport, step: float) -> void:
	_vp = vp
	_step = step


## Can a player body stand here? Mask 1 is the terrain/collider layer.
func fits(at: Vector2) -> bool:
	if _vp == null or _vp.world_2d == null:
		return false
	var shape := CircleShape2D.new()
	shape.radius = BODY_RADIUS
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return _vp.world_2d.direct_space_state.intersect_shape(q, 1).is_empty()


func press_lands_on(feet: Vector2, facing: Vector2) -> Node:
	if _vp == null or _vp.world_2d == null:
		return null
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


## Broad census: every standable cell within two, every facing. Without it a prop whose whole ring
## is unstandable scores `bad` empty and reads as reachable.
func presses_for(prop: Node2D) -> int:
	var hits := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var feet: Vector2 = prop.global_position + Vector2(dx * _step, dy * _step)
			if not fits(feet):
				continue
			for facing in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				if press_lands_on(feet, facing) == prop:
					hits += 1
	return hits


## {"bad": [...], "yielded": [...]} — see the header. `bad` is the assertable half.
func face_split(prop: Node2D) -> Dictionary:
	var bad: Array = []
	var yielded: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var feet: Vector2 = prop.global_position + Vector2(dx * _step, dy * _step)
			if not fits(feet):
				continue
			var facing := Vector2(-dx, 0) if absi(dx) >= absi(dy) else Vector2(0, -dy)
			var won: Node = press_lands_on(feet, facing)
			if won == prop:
				continue
			if won == null:
				bad.append("(%d,%d) -> nothing" % [dx, dy])
				continue
			var mine: float = InteractGeometry.anchor(prop).distance_to(feet)
			var theirs: float = InteractGeometry.anchor(won as Node2D).distance_to(feet)
			if theirs <= mine + 0.5:
				yielded.append("(%d,%d) to %s at %.0fpx vs %.0f" % [dx, dy, label(won), theirs, mine])
			else:
				bad.append("(%d,%d) -> %s, %.0fpx away against my %.0f" % [dx, dy, label(won), theirs, mine])
	return {"bad": bad, "yielded": yielded}


## An OverworldNPC never sets its node name, so a thief reads as '@Area2D@276' unless we ask it who
## it is — and an unreadable red is a red nobody acts on.
func label(n: Node) -> String:
	for key in ["npc_name", "display_name", "chest_id", "sign_text"]:
		if n.get(key) != null and str(n.get(key)) != "":
			return "%s (%s)" % [str(n.get(key)), n.name]
	return str(n.name)


## Every interactable the SCENE owns — not the "interactables" group, which is global and carries
## other tests' leftovers into this one.
func scene_interactables(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Node2D and c.has_method("interact"):
			out.append(c)
		scene_interactables(c, out)
