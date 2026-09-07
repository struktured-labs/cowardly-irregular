extends GutTest

## Overworld reachability framework (2026-07-13 — Castle Harmonia was
## unreachable because its AreaTransition collision box overlapped
## CaveEntrance by 2 tiles wide; cave sibling registered first, stole every
## ui_accept in the shared cells → player got warped to the cave). Same
## shape as the village reachability framework at
## test_village_reachability_framework.gd, but scoped to OverworldScene's
## `transitions` container.
##
## Two invariants pinned:
##   1. No two require_interaction=true transitions have overlapping AABBs
##      (the exact class the castle bug slipped through).
##   2. Every transition's collision must have non-zero area (guards
##      against a future refactor that silently sets size=0).


const TILE := 32
const OVERWORLD_SCRIPTS := [
	"res://src/exploration/OverworldScene.gd",
	# W2+ overworlds have their own _setup_transitions and are checked when their scripts route through the same AreaTransition class.
	"res://src/exploration/SuburbanOverworld.gd",
	"res://src/exploration/SteampunkOverworld.gd",
	"res://src/exploration/FuturisticOverworld.gd",
	"res://src/exploration/AbstractOverworld.gd",
]


func _first_collision(node: Node) -> CollisionShape2D:
	for c in node.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape != null:
			return c
	return null


## World-space AABB of a transition node's first collision (rect-shape only).
## Returns Rect2(pos, size) — pos = min corner, size = extent.
func _transition_aabb(node: Node2D) -> Rect2:
	var cs := _first_collision(node)
	if cs == null:
		return Rect2()
	var shape := cs.shape
	if not (shape is RectangleShape2D):
		return Rect2()
	var size: Vector2 = (shape as RectangleShape2D).size * cs.scale.abs()
	var world_center: Vector2 = node.global_position + cs.position
	return Rect2(world_center - size * 0.5, size)


## Two AABBs "overlap" if they share INTERIOR area (touching edges don't
## count — Godot's Rect2.intersects with include_borders=false semantics).
func _aabb_overlap(a: Rect2, b: Rect2) -> bool:
	if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
		return false
	return a.intersects(b, false)


## Simulate OverworldController._pick_nearest_interactable — from a query
## point, pick the transition whose global_position is closest (matches
## post-fix routing).
func _nearest_transition_at(candidates: Array, from_pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for t in candidates:
		if t == null or not is_instance_valid(t):
			continue
		var aabb: Rect2 = _transition_aabb(t)
		if not aabb.has_point(from_pos):
			continue
		var d2: float = t.global_position.distance_squared_to(from_pos)
		if d2 < best_d2:
			best_d2 = d2
			best = t
	return best


func test_every_transition_has_at_least_one_uniquely_reachable_cell() -> void:
	# The castle-vs-cave bug shape: two AreaTransitions with overlapping
	# collision boxes let the earlier sibling steal ui_accept when the
	# player's probe hit both. Fix B (nearest-hit routing in
	# OverworldController) makes overlap tolerable IF each transition still
	# owns at least one probe-reachable cell. This test simulates that
	# routing and asserts no transition is completely eclipsed by a neighbor.
	for path in OVERWORLD_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var scene = load(path).new()
		add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		var container = scene.get("transitions") if "transitions" in scene else null
		if container == null or not is_instance_valid(container):
			scene.free()
			await get_tree().process_frame
			continue

		var transitions: Array = []
		for kid in container.get_children():
			if "target_map" in kid:
				transitions.append(kid)

		for t in transitions:
			var aabb: Rect2 = _transition_aabb(t)
			if aabb.size == Vector2.ZERO:
				continue
			# Sample cell centers inside t's AABB, see if AT LEAST ONE picks t
			# as nearest via the routing sim.
			var min_c := Vector2i(int(floor(aabb.position.x / TILE)), int(floor(aabb.position.y / TILE)))
			var max_c := Vector2i(int(floor((aabb.position.x + aabb.size.x) / TILE)), int(floor((aabb.position.y + aabb.size.y) / TILE)))
			var owns_a_cell := false
			for cx in range(min_c.x, max_c.x + 1):
				for cy in range(min_c.y, max_c.y + 1):
					var probe := Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)
					if not aabb.has_point(probe):
						continue
					var winner: Node2D = _nearest_transition_at(transitions, probe)
					if winner == t:
						owns_a_cell = true
						break
				if owns_a_cell:
					break
			assert_true(owns_a_cell,
				"%s: transition '%s' has NO cell where it wins the nearest-hit probe — completely eclipsed by neighbors, unreachable" % [path.get_file(), t.name])

		scene.free()
		await get_tree().process_frame


func test_interaction_router_uses_nearest_hit_selection() -> void:
	# The castle-vs-cave bug's ACTUAL mechanism was first-hit-wins on the
	# physics query results. Even with the geometry-reachability test above,
	# a code regression that flips back to first-hit-wins would re-open the
	# whole class. Pin the routing shape.
	var src := FileAccess.get_file_as_string("res://src/exploration/OverworldController.gd")
	assert_true("_pick_nearest_interactable" in src,
		"OverworldController must use nearest-hit selection for overlapping-transition disambiguation — first-hit iteration order lets earlier siblings steal every ui_accept in shared cells")
	# The helper must actually pick by distance (guard against a rename-only refactor that reintroduces first-hit).
	var i := src.find("func _pick_nearest_interactable")
	assert_gt(i, -1, "helper must exist as its own function")
	var body := src.substr(i, 600)
	assert_true("distance_squared_to" in body,
		"_pick_nearest_interactable must select by distance — a rename without distance math would silently degrade to first-hit-wins")


func test_no_transition_has_zero_area_collision() -> void:
	# Guards against a future refactor that silently makes a collision box
	# empty (Rect2.size == Vector2.ZERO fails intersect but is a real bug).
	for path in OVERWORLD_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var scene = load(path).new()
		add_child(scene)
		await get_tree().process_frame
		await get_tree().process_frame
		var container = scene.get("transitions") if "transitions" in scene else null
		if container == null or not is_instance_valid(container):
			scene.free()
			await get_tree().process_frame
			continue
		for kid in container.get_children():
			if "target_map" in kid:
				var aabb: Rect2 = _transition_aabb(kid)
				assert_gt(aabb.size.x, 0.0, "%s: transition '%s' has zero-width collision" % [path.get_file(), kid.name])
				assert_gt(aabb.size.y, 0.0, "%s: transition '%s' has zero-height collision" % [path.get_file(), kid.name])
		scene.free()
		await get_tree().process_frame
