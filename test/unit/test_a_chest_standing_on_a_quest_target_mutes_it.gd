extends GutTest

## A treasure chest was authored on a quest NPC's EXACT cell, and it silenced him.
##
## `maple_heights_chest_3` and the Basement Developer were both placed at
## `Vector2(7 * TILE_SIZE, 16 * TILE_SIZE)` — same file, 155 lines apart. ui_accept goes to
## whatever OverworldController's probe picks as nearest-by-anchor, the anchors were identical,
## and the chest won all 24 of his (cell, facing) presses from all six walkable cells beside him.
## `world2_wrong_blue` step 3 is `{"type": "talk", "target_npc": "basement_developer_w2"}`, so the
## quest could not be finished. A chest is a ONE-SHOT: after it is looted `TreasureChest.interact`
## still claims the press and answers "The chest is empty." — in the developer's place, forever.
##
## The same sweep found Frosthold's Ice Chapel mute: Clockkeeper Yara stood one cell from the shop
## and took all three of its approach cells, so a W1 magic shop could not be opened at all. She
## moved one cell east — the chapel opens, and she is easier to reach herself.
##
## ⚠️ AN APPROACH IS A (CELL, FACING) PAIR AND BOTH HALVES ARE THE UNION — a player stands on any
## walkable cell touching the thing, DIAGONALS INCLUDED, and faces any of four directions. Narrower
## models are wrong in both directions and I built two of them against the village doors first:
## eight cells with one derived facing each invents fragility (it mis-faces diagonals sideways),
## four orthogonal cells invents sealed doors (it discards diagonal approaches that really do
## reach). Neither error is visible in the output — both hand you a tidy offender list.
##
## 🔑 RUNTIME POSITIONS, NOT AUTHORED ONES. `BaseVillage._validate_placements()` relocates an NPC
## off an impassable tile to the nearest walkable cell, silently, so where a village SAYS it put
## someone and where the player meets them are different questions. A source-level check for two
## nodes sharing a coordinate would also have found this pair — and would be blind to any pair the
## relocator creates, which is the more likely way the next one arrives.

const TILE := 32.0
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
	return str(n.get_script().resource_path).get_file().get_basename() if n.get_script() else "?"


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


## Whatever the thing calls itself, so the offender line names a person or a shop, not @Area2D@905.
func _identify(n: Node2D) -> String:
	for k in ["npc_name", "shop_name", "chest_id", "npc_id", "display_name"]:
		if k in n and str(n.get(k)) != "":
			return str(n.get(k))
	return str(n.name)


## OverworldController's press, reproduced FLAT — villages never run Mode 7, so there is no
## displaced collider clone here and PROBE_REACH_FLAT is the reach.
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


func _reach(village: Node, n: Node2D) -> Dictionary:
	var cell := Vector2i(int(floor(n.global_position.x / TILE)), int(floor(n.global_position.y / TILE)))
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
			for f in FACINGS:
				var won := _press_lands_on(feet, f)
				if won == n:
					opens += 1
				elif won != null and won != n:
					var who := "%s %s" % [_base(won), _identify(won as Node2D)]
					if not thieves.has(who):
						thieves.append(who)
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


func test_no_village_interactable_is_mute() -> void:
	## Mode 7 is a STATIC and a W1 test earlier in the run leaves it true; forced, not assumed.
	var prior_mode7: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false

	var mute: Array = []
	var checked := 0
	for path in VILLAGE_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var v = await _build(path)
		var vid: String = v._get_area_id() if v.has_method("_get_area_id") else path.get_file()
		for n in _interactables(v):
			checked += 1
			var r: Dictionary = _reach(v, n)
			if int(r["walkable"]) == 0:
				continue  # nothing can stand beside it — test_village_global_reachability's question
			if int(r["opens"]) == 0:
				mute.append("%s: %s \"%s\" at cell %s — %d walkable cells beside it and NOT ONE of the %d (cell,facing) presses reaches it; %s takes them all. Move one of the two" % [
					vid, _base(n), _identify(n), str(r["cell"]), int(r["walkable"]),
					int(r["walkable"]) * 4, ", ".join(r["thieves"])])
		v.queue_free()
		await get_tree().physics_frame
	Mode7Overlay.is_active = prior_mode7

	assert_gt(checked, 150,
		"CONTROL: only %d village interactables collected — with a thin corpus the [] below is free" % checked)
	mute.sort()
	assert_eq(mute, [],
		"a village interactable cannot be reached by any press — it renders, it has room to stand " +
		"beside it, and the press goes to its neighbour every time: %s" % ", ".join(mute))


## CONTROL: the sweep must be able to SEE a mute node, or its [] is decoration. Reproduces the
## shipped defect exactly — a chest on an NPC's own cell — rather than a synthetic fixture.
func test_the_sweep_can_see_a_chest_standing_on_an_npc() -> void:
	var prior_mode7: bool = Mode7Overlay.is_active
	Mode7Overlay.is_active = false
	var v = await _build("res://src/maps/villages/MapleHeightsVillage.gd")
	var npc: Node2D = null
	for n in _interactables(v):
		if "npc_id" in n and str(n.npc_id) == "basement_developer_w2":
			npc = n
	assert_not_null(npc, "CONTROL: MapleHeights must carry the Basement Developer")
	if npc == null:
		Mode7Overlay.is_active = prior_mode7
		return
	var before: Dictionary = _reach(v, npc)
	assert_gt(int(before["opens"]), 0,
		"CONTROL: the developer answers presses before the chest is planted back on him")

	var thief = load("res://src/exploration/TreasureChest.gd").new()
	thief.chest_id = "zz_probe_on_the_npc"
	thief.contents_type = "item"
	thief.contents_id = "ether"
	thief.contents_amount = 1
	thief.position = npc.position
	v.add_child(thief)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var after: Dictionary = _reach(v, npc)
	thief.queue_free()
	await get_tree().physics_frame
	Mode7Overlay.is_active = prior_mode7
	assert_eq(int(after["opens"]), 0,
		"a chest on the NPC's own cell must take EVERY press (%d of %d still reach him). That is " % [
			int(after["opens"]), int(after["walkable"]) * 4] +
		"the shipped defect; if it does not reproduce, the sweep above cannot detect it")
