extends GutTest
## Can the player actually WALK to every village interactable from where they arrive?
##
## THE GAP THIS FILLS. test_village_reachability_framework asks, per interactable, "does its
## trigger overlap at least one WALKABLE cell". That is a LOCAL question and it is answered
## correctly by a cell in a region the player can never get to. `_can_step` -- the rule that
## actually governs movement, and the only thing that knows about the elevation tiers added
## in the CrossCode pass -- is likewise local: it compares two ADJACENT cells.
##
## Nothing runs the global version. That is the same hole that hid two W1 elemental dragon
## bosses inside sealed enclaves for months while a spawn ratchet correctly reported
## "0 of 15 spawns in solid geometry" (2026-08-22). "Is this cell solid", "can a body stand
## here", and "can a player REACH here" are three different capabilities, and an instrument
## for one is silent about the others.
##
## Harmonia is the live risk: 3 tiers, 8 stair cells, and `_can_step` permits a tier change
## ONLY through a stair or ramp. Move or mis-paint one connector and an entire tier becomes
## unreachable -- while every trigger on it still overlaps a perfectly walkable cell and the
## existing framework still passes.

const TILE := 32.0
const PLAYER_HALF := 12.0
const INTERACT_REACH := 40.0  # OverworldController's flat-village press probe

const VILLAGE_SCRIPTS := [
	"res://src/maps/villages/HarmoniaVillage.gd",
	"res://src/maps/villages/SandriftVillage.gd",
	"res://src/maps/villages/EldertreeVillage.gd",
	"res://src/maps/villages/GrimhollowVillage.gd",
	"res://src/maps/villages/IronhavenVillage.gd",
	"res://src/maps/villages/FrostholdVillage.gd",
	"res://src/maps/villages/MapleHeightsVillage.gd",
	"res://src/maps/villages/MapleStripMall.gd",
	"res://src/maps/villages/BrasstonVillage.gd",
	"res://src/maps/villages/ScripturaPlaza.gd",
	"res://src/maps/villages/RivetRowVillage.gd",
	"res://src/maps/villages/NodePrimeVillage.gd",
	"res://src/maps/villages/VertexVillage.gd",
]


func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / TILE)), int(floor(pos.y / TILE)))


## Every cell reachable from `start` under the village's OWN `_can_step` rule
func _flood(village, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + step
			if seen.has(n):
				continue
			if village._can_step(cur, n):
				seen[n] = true
				queue.append(n)
	return seen


func _first_collision(node: Node) -> CollisionShape2D:
	for c in node.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			return c
	return null


func _half_extent(cs: CollisionShape2D) -> Vector2:
	var s := cs.shape
	if s is RectangleShape2D:
		return (s as RectangleShape2D).size * 0.5 * cs.scale.abs()
	if s is CircleShape2D:
		var r := (s as CircleShape2D).radius
		return Vector2(r * absf(cs.scale.x), r * absf(cs.scale.y))
	return Vector2.ZERO


## Does the trigger overlap a cell the player can WALK TO -- not merely a walkable one
func _overlaps_reachable(node: Node2D, reachable: Dictionary) -> bool:
	var cs := _first_collision(node)
	if cs == null:
		return true
	var center: Vector2 = node.global_position + cs.position
	var half := _half_extent(cs) + Vector2(PLAYER_HALF, PLAYER_HALF)
	var min_c := _cell_of(center - half)
	var max_c := _cell_of(center + half)
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			if not reachable.has(Vector2i(cx, cy)):
				continue
			var cc := Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)
			if absf(cc.x - center.x) <= half.x and absf(cc.y - center.y) <= half.y:
				return true
	return false


## Press-A reach from a REACHABLE cell. This is the semantics the press probe actually uses,
## and it is NOT body-overlap: a fountain sits inside its own 5x5 prop footprint, so the
## player never stands on it and body-overlap reports it unreachable. Using the wrong one
## produced a false positive on Harmonia's fountain the first time this file ran.
func _probe_reaches(node: Node2D, reachable: Dictionary) -> bool:
	var cs := _first_collision(node)
	if cs == null:
		return true
	var center: Vector2 = node.global_position + cs.position
	var half := _half_extent(cs)
	var search := half + Vector2(INTERACT_REACH + PLAYER_HALF, INTERACT_REACH + PLAYER_HALF)
	var min_c := _cell_of(center - search)
	var max_c := _cell_of(center + search)
	for cx in range(min_c.x, max_c.x + 1):
		for cy in range(min_c.y, max_c.y + 1):
			if not reachable.has(Vector2i(cx, cy)):
				continue
			var stand := Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)
			for facing in [Vector2(0, INTERACT_REACH), Vector2(0, -INTERACT_REACH), Vector2(INTERACT_REACH, 0), Vector2(-INTERACT_REACH, 0)]:
				var probe: Vector2 = stand + facing
				if absf(probe.x - center.x) <= half.x and absf(probe.y - center.y) <= half.y:
					return true
	return false


func _interactables(v) -> Array:
	var out: Array = []
	for holder in ["buildings", "transitions", "props", "npcs"]:
		if not (holder in v) or v.get(holder) == null:
			continue
		for kid in v.get(holder).get_children():
			if kid is Node2D and (kid.has_method("interact") or ("target_map" in kid)):
				out.append(kid)
	return out


func test_every_village_interactable_can_be_walked_to() -> void:
	var villages_checked := 0
	var problems: Array = []
	for path in VILLAGE_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var v = load(path).new()
		add_child(v)
		await get_tree().process_frame
		await get_tree().process_frame

		var spawn: Vector2 = v.spawn_points.get("default", Vector2.ZERO) if "spawn_points" in v else Vector2.ZERO
		if spawn == Vector2.ZERO and v.has_method("_get_player_spawn_fallback"):
			spawn = v._get_player_spawn_fallback()
		var start := _cell_of(spawn)
		var vid: String = v._get_area_id() if v.has_method("_get_area_id") else path.get_file()

		if not v._is_cell_walkable(start):
			problems.append("%s: SPAWN cell %s is not walkable" % [vid, str(start)])
			v.queue_free()
			continue

		var reachable := _flood(v, start)
		# CONTROL: a flood that reached almost nothing would make every check below vacuous
		if reachable.size() < 30:
			problems.append("%s: flood from spawn reached only %d cells -- probe is broken, not the map" % [vid, reachable.size()])
			v.queue_free()
			continue

		var items := _interactables(v)
		if items.is_empty():
			problems.append("%s: found NO interactables -- the scan is not seeing this village" % vid)
			v.queue_free()
			continue

		villages_checked += 1
		for node in items:
			# an auto-warp door fires on body_entered, so it needs a reachable cell the
			# player's BODY covers; a press-A interactable only needs probe reach
			var auto_warp: bool = ("target_map" in node) and not bool(node.get("require_interaction"))
			var ok: bool = _overlaps_reachable(node, reachable) if auto_warp else _probe_reaches(node, reachable)
			if not ok:
				problems.append("%s: '%s' (%s) at %s cannot be %s from ANY cell reachable from the spawn (%d reachable) -- walkable, and walled off from the player" % [
					vid, node.name, ("auto-warp" if auto_warp else "press-A"),
					str(_cell_of(node.global_position)), ("entered" if auto_warp else "probed"), reachable.size()])
		v.queue_free()
		await get_tree().process_frame

	assert_gt(villages_checked, 8, "only %d villages were actually measured -- too few for this to mean anything" % villages_checked)
	assert_eq(problems, [], "global reachability problems:\n  %s" % "\n  ".join(problems))
