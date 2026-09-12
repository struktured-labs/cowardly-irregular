extends GutTest

## Village interior doors need a PRESS, and in a dense village everything competes for it.
##
## `BaseVillage._setup_transitions` sets `require_interaction = true` on every interior door (the
## village EXIT is the opposite — `require_interaction = false`, auto-open on touch). So entering a
## building is a ui_accept, and ui_accept goes to whatever OverworldController's probe picks as
## nearest-by-anchor among everything with interact(). A village packs 94 NPCs, 29 shops, 30 chests,
## 12 inns and 41 transitions into 32px cells with ~44px interact zones: adjacent things overlap by
## construction, and a door losing SOME of its approach cells to the shop beside it is nearest-wins
## working correctly, not a defect.
##
## ⚠️ AN APPROACH IS A (CELL, FACING) PAIR, AND BOTH HALVES ARE THE UNION. A player may stand on
## any walkable cell touching the door — diagonals included — and face any of the four directions,
## so the building is enterable if ANY pair reaches it. Narrower models are wrong in both
## directions and I built two of them before this one: eight cells with one derived facing each
## invents fragility (it mis-faces diagonals sideways), four orthogonal cells invents SEALED DOORS
## (it throws away the diagonal approaches that really do open them). Neither error is visible in
## the output — both produce a tidy list of offenders.
##
## 🔑 MEASURED, AND NOTHING IS NEAR THE FLOOR: all 28 press-requiring doors across 13 villages are
## enterable, the thinnest at 2 of 12 pairs (Scriptura's GuildDoor and BookshopDoor, Brasston's
## ClockworkLoftDoor). So this file defends a floor rather than reporting a defect — worth having
## because a sealed door is silent in every other check: it still exists, still renders its prompt,
## still has walkable cells beside it, and the press opens a shop menu instead. Villages carry 94
## NPCs and 29 shops today and gain more routinely.

const TILE := 32.0
## Four facings, so an approach cell is orthogonal — see the header; diagonals cost me a headline.
const STEPS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]
const FACINGS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const VILLAGE_SCRIPTS := [
	"res://src/maps/villages/HarmoniaVillage.gd", "res://src/maps/villages/SandriftVillage.gd",
	"res://src/maps/villages/EldertreeVillage.gd", "res://src/maps/villages/GrimhollowVillage.gd",
	"res://src/maps/villages/IronhavenVillage.gd", "res://src/maps/villages/FrostholdVillage.gd",
	"res://src/maps/villages/MapleHeightsVillage.gd", "res://src/maps/villages/MapleStripMall.gd",
	"res://src/maps/villages/BrasstonVillage.gd", "res://src/maps/villages/ScripturaPlaza.gd",
	"res://src/maps/villages/RivetRowVillage.gd", "res://src/maps/villages/NodePrimeVillage.gd",
	"res://src/maps/villages/VertexVillage.gd",
]

var _vp: SubViewport = null


func _base(n: Node) -> String:
	if n.get_script() == null:
		return "?"
	return str(n.get_script().resource_path).get_file().get_basename()


## The corpus is "has interact()", never a class list — a class list is a to-do, not a corpus.
func _interactables(root: Node) -> Array:
	var out: Array = []
	var stack: Array = [root]
	while not stack.is_empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node2D and n.has_method("interact"):
			out.append(n)
	return out


## OverworldController's press, reproduced FLAT: villages never run Mode 7, so the reach is
## PROBE_REACH_FLAT and there is no displaced collider clone to reason about.
func _press_lands_on(feet: Vector2, facing: Vector2) -> Node:
	var space := _vp.world_2d.direct_space_state
	for point in [feet + facing * InteractGeometry.PROBE_REACH_FLAT, feet]:
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


## Walkable cells touching `door` from which facing it opens it, and who takes the rest.
## `_is_cell_walkable` is the village's OWN authority — no second grid model is built here.
func _ways_in(village: Node, door: Node2D) -> Dictionary:
	var cell := Vector2i(int(floor(door.global_position.x / TILE)), int(floor(door.global_position.y / TILE)))
	var walkable := 0
	var opens := 0
	var thieves: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var nc: Vector2i = cell + Vector2i(dx, dy)
			if not village._is_cell_walkable(nc):
				continue
			walkable += 1
			var feet := Vector2((nc.x + 0.5) * TILE, (nc.y + 0.5) * TILE)
			## UNION over the four facings: the player may stand anywhere walkable and face any way,
			## so the building is enterable if ANY (cell, facing) pair reaches the door.
			for facing in FACINGS:
				var won := _press_lands_on(feet, facing)
				if won == door:
					opens += 1
				elif won != null and _base(won) != "AreaTransition":
					if not thieves.has(_base(won)):
						thieves.append(_base(won))
	return {"cell": cell, "walkable": walkable, "opens": opens, "thieves": thieves}


func _build(path: String) -> Node:
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.world_2d = World2D.new()
	add_child_autofree(_vp)
	var v = load(path).new()
	_vp.add_child(v)
	await get_tree().physics_frame
	await get_tree().physics_frame
	return v


func test_every_village_door_has_at_least_one_way_in() -> void:
	## Mode 7 is a STATIC and a W1 test earlier in the run leaves it true; forced, not assumed.
	var prior_mode7: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false

	var sealed: Array = []
	var doors := 0
	var thin: Array = []
	for path in VILLAGE_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var v = await _build(path)
		var vid: String = v._get_area_id() if v.has_method("_get_area_id") else path.get_file()
		for n in _interactables(v):
			if _base(n) != "AreaTransition" or not bool(n.require_interaction):
				continue
			doors += 1
			var r: Dictionary = _ways_in(v, n)
			if int(r["walkable"]) == 0:
				continue  # no walkable cell touches it at all — a different defect, and not one today
			if int(r["opens"]) == 0:
				sealed.append("%s/%s at cell %s — %d walkable cells touch it and NOT ONE of the %d (cell,facing) presses opens it; %s takes them. Move that prop, or the building cannot be entered" % [
					vid, str(n.name), str(r["cell"]), int(r["walkable"]), int(r["walkable"]) * 4, ", ".join(r["thieves"])])
			else:
				thin.append("%s/%s  %d of %d (cell,facing) pairs open it" % [vid, str(n.name), int(r["opens"]), int(r["walkable"]) * 4])
	Mode7Overlay.is_active = prior_mode7

	assert_gt(doors, 20,
		"CONTROL: only %d press-requiring village doors collected — with an empty corpus the [] below is free" % doors)
	thin.sort()
	gut.p("  doors needing a press: %d   sealed: %d" % [doors, sealed.size()])
	for t in thin:
		gut.p("    %s" % t)
	sealed.sort()
	assert_eq(sealed, [],
		"a village building cannot be entered — the door renders, prompts, and hands its press to " +
		"the prop beside it: %s" % ", ".join(sealed))


## The offender path itself: a door that answers nothing must be REPORTED, not merely measured.
func test_a_door_that_answers_nothing_is_reported() -> void:
	var prior_mode7: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false
	var v = await _build("res://src/maps/villages/ScripturaPlaza.gd")
	var door: Node2D = null
	for n in _interactables(v):
		if str(n.name) == "GuildDoor":
			door = n
	if door == null:
		Mode7Overlay.is_active = prior_mode7
		return
	var before: Dictionary = _ways_in(v, door)
	assert_gt(int(before["opens"]), 0, "CONTROL: the door opens while it is on the interact layer")
	assert_gt(int(before["walkable"]), 0, "CONTROL: walkable cells touch it, so 'sealed' is reachable-but-mute")

	var prior_layer: int = door.collision_layer
	door.collision_layer = 0
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after: Dictionary = _ways_in(v, door)
	door.collision_layer = prior_layer
	Mode7Overlay.is_active = prior_mode7
	assert_eq(int(after["opens"]), 0,
		"a door off the interact layer must answer NO approach — got %d. The main arm keys on " % int(after["opens"]) +
		"opens == 0, so if that state is unreachable the offender branch never runs")
	assert_gt(int(after["walkable"]), 0,
		"and it must still have walkable cells beside it, or the main arm skips it as a different defect")
